# Ibex ↔ Wishbone Host Adapter: Requirements and Testbench Architecture

## 1. Purpose

The `ibex_wb_host_adapter` bridges the Ibex instruction/data request interface to a Wishbone host/master interface.

The adapter must preserve request/response ordering while allowing Wishbone burst transfers where possible. The most important correctness rule is:

```text
Every granted Ibex request must produce exactly one response,
and every response must correspond to the oldest granted request.
```

The adapter should be treated primarily as a request/response ordering unit, and only secondarily as a burst generator.

---

## 2. Assumptions

1. Memory normally acknowledges continuously over bursts.
2. Memory may still stall by withholding `wb_ack`.
3. The Wishbone host may add wait states by negating `wb_stb`.
4. Ibex may change `req_addr` immediately after `gnt`.
5. An address break may occur at any time because of branch, jump, exception, interrupt, debug entry, or frontend redirect.
6. The adapter does not need to know the reason for an address break. It only observes that the next request is not sequential.

---

## 3. Ibex-Side Interface Contract

Ibex presents a request using:

```text
req_valid = 1
req_addr
req_we
req_be
req_wdata
```

When the adapter asserts `gnt`, the request is accepted. At that point the adapter must store all request metadata needed for later execution:

```text
addr
we
be
wdata
```

After `gnt`, Ibex may either:

```text
- present the next request immediately, or
- negate req_valid
```

For every granted request, the adapter must later assert exactly one `resp_valid`.

For reads:

```text
resp_rdata must be valid when resp_valid is high.
```

For writes:

```text
the Wishbone write data and byte enables must match the request metadata captured at the corresponding gnt.
```

---

## 4. Wishbone-Side Requirements

The adapter may use Wishbone classic or incrementing burst cycles.

A Wishbone burst may continue only while the queued/granted request addresses are sequential:

```text
next_addr == current_addr + 4
```

If the next queued request is not sequential, the current Wishbone burst must be terminated gracefully.

For Wishbone B3-style burst termination:

```text
wb_cti = 3'b111 on the final effective beat
```

If a queued request should not belong to the current burst, the adapter must not consume or acknowledge it as part of that burst.

### Burst abortion

When a burst is cut short before its natural end (e.g., an address break interrupts an in-progress burst), the master must signal the abort with exactly one graceful-abort cycle before deasserting CYC:

```text
CYC=1, STB=0, CTI=3'b111
```

This is distinct from normal burst termination, where the final data beat carries CTI=111 and STB=1 simultaneously with the last transfer. In the abort case there is no additional data transfer — STB=0 conveys only the end-of-burst signal.

CYC must never fall directly from an active burst beat (CTI=010) to zero without this intermediate cycle.

---

## 5. Core Adapter Requirements

### R1: Grant only if storage is available

The adapter may assert `gnt` only when it can store the request for later execution.

```text
if fifo_full:
  gnt must remain 0
```

### R2: Store request metadata at grant time

The following fields must be captured atomically when `gnt` is asserted:

```text
req_addr
req_we
req_be
req_wdata
```

### R3: Start Wishbone only when a stored request exists

R3. Every resp_valid cycle must match exactly one previously granted request.
    If a request is discarded because of an address break, redirect, or burst
    termination, the corresponding Wishbone transfer shall not be issued
    (STB=0) and no resp_valid shall be generated for that request.

```text
wb_adr   = fifo_head.addr
wb_we    = fifo_head.we
wb_sel   = fifo_head.be
wb_dat_w = fifo_head.wdata
```

### R4: Preserve request/response order

The response stream must follow FIFO order.

```text
first granted request -> first response
second granted request -> second response
...
```

### R5: One response per grant

The adapter must never generate:

```text
more resp_valid pulses than gnt pulses
```

### R6: Continue bursts only across sequential granted addresses

The adapter may continue a burst only if the next stored request is sequential.

```text
fifo_next.addr == fifo_head.addr + 4
```

### R7: Address breaks terminate the current burst

An address break means:

```text
next granted address != previous granted address + 4
```

Examples:

```text
0x14c -> 0x150   sequential
0x158 -> 0x084   address break
0x14c -> 0xa14   address break, possibly caused by a bug elsewhere
```

On an address break, the adapter must prevent stale/wrong-path entries from being serviced as part of the old burst.

### R8: Response valid pulse must be well-formed

`resp_valid` should be asserted for exactly the intended response cycle. It must not stay high across Wishbone wait states unless the Ibex interface explicitly expects that behavior.

### R9: Wishbone ACK must not create an unrequested response

A `wb_ack` may produce `resp_valid` only if there is a corresponding outstanding FIFO entry.

### R10: Burst abortion must use a graceful-abort cycle

When the adapter terminates a burst early it must assert one cycle of `CYC=1, STB=0, CTI=111` before deasserting CYC. CYC must not transition directly from a burst beat (CTI=010) to deasserted.

```text
illegal:   CTI=010, CYC=1, STB=1  →  CYC=0
required:  CTI=010, CYC=1, STB=1  →  CTI=111, CYC=1, STB=0  →  CYC=0
```

---

## 6. Important Invariants

The testbench should check these continuously.

### Grant/response count

```text
resp_count <= grant_count
```

### FIFO response order

```text
on gnt:
  push expected request into scoreboard

on resp_valid:
  pop oldest expected request
  check returned data/address matches it
```

### No response without outstanding request

```text
if resp_valid:
  scoreboard must not be empty
```

### No grant while FIFO full

```text
if fifo_full:
  gnt == 0
```

### Wishbone starts from FIFO head

```text
when wb cycle starts:
  wb_adr == oldest stored request address
```

### Burst continuation only when sequential

```text
if wb_cti == INCR:
  next stored request must be sequential
```

---

## 7. Testbench Architecture

The testbench should be structured in three layers.

### 7.1 Driver Layer

Responsible for protocol-level stimulus only.

#### Ibex request driver

Provides tasks:

```systemverilog
// Hold request stable until gnt is seen or timeout.
task hold_req_until_gnt(addr, we, be, wdata, max_cycles);

// Convenience wrappers (use hold_req_until_gnt internally).
task issue_read(addr);
task issue_write(addr, be, wdata);

// Deassert req_valid for N clock cycles.
task insert_req_gap(cycles);
```

All driver tasks use blocking assignments driven on `negedge clk`:

```systemverilog
@(negedge clk);
req_valid = 1'b1;   // blocking, not <=
req_addr  = addr;
```

`req_len` is not driven by the driver. It is not part of the FIFO-based burst model and should be tied off to a constant in the DUT instantiation.

`hold_req_until_gnt` samples `gnt` on `posedge clk`, deasserts `req_valid` on the following `negedge`:

```systemverilog
task hold_req_until_gnt(..., max_cycles);
  for (i = 0; i < max_cycles; i++) begin
    @(negedge clk);
    req_valid = 1; req_addr = addr; ...;
    @(posedge clk);
    if (gnt) begin
      @(negedge clk); req_valid = 0;
      disable hold_req_until_gnt;
    end
  end
  fail("timeout");
endtask
```

#### Wishbone slave driver

The slave must maintain its own internal address counter decoupled from `wb_adr`. Using `wb_adr` directly for `wb_dat_r` is incorrect for bursts.

**Why the simple registered model fails for bursts:**

The DUT uses registered outputs. When the slave fires its always block at posedge N and sees `wb_adr = A`, it schedules `wb_ack <= 1` and `wb_dat_r <= data(A)` as nonblocking assignments. These appear to the DUT at posedge N+1. At that same posedge N+1, the DUT's own NBA fires and advances `wb_adr` to `A+4`. However, at the *evaluation phase* of posedge N+1, the DUT's NBA has not yet fired — so the slave still sees `wb_adr = A` and drives `data(A)` a second time. The result is every even beat returning stale data.

**Correct approach — internal address counter:**

```systemverilog
reg [31:0] slave_adr;
reg        slave_in_burst;
reg        ack_enable;
integer    ack_gap;       // 0 = continuous; N = N wait-state cycles between acks
integer    ack_beats;     // -1 = unlimited; N > 0 = stop after N acks
integer    ack_countdown;

always @(posedge clk) begin
  if (rst) begin
    wb_ack <= 0; wb_dat_r <= 0;
    slave_adr <= 0; slave_in_burst <= 0; ack_countdown <= 0;
  end else begin
    wb_ack <= 1'b0;
    if (!wb_cyc) begin
      slave_in_burst <= 0; slave_adr <= 0; ack_countdown <= 0;
    end else if (wb_stb && ack_enable && (ack_beats != 0)) begin
      if (ack_countdown == 0) begin
        if (!slave_in_burst) begin
          wb_dat_r       <= mem_data_for_addr(wb_adr);
          slave_adr      <= wb_adr;
          slave_in_burst <= (wb_cti == 3'b010);
        end else begin
          wb_dat_r  <= mem_data_for_addr(slave_adr + 32'd4);
          slave_adr <= slave_adr + 32'd4;
          if (wb_cti == 3'b111) slave_in_burst <= 1'b0;
        end
        wb_ack        <= 1'b1;
        ack_countdown <= ack_gap;
        if (ack_beats > 0) ack_beats = ack_beats - 1;
      end else begin
        ack_countdown <= ack_countdown - 1;
      end
    end
  end
end
```

For the first beat or a classic transfer, `wb_adr` is stable (the master has not yet seen an ACK), so using `wb_adr` directly is correct. From the second beat onward, `slave_adr` tracks the acknowledged address independently of whatever `wb_adr` shows in the evaluation phase.

`ack_beats` uses `-1` to mean unlimited; `N > 0` means N more acks then stop. It is decremented with a blocking assignment inside the always block. Tasks write it between clock edges (no simultaneous conflict). `ack_enable` is task-driven only; the always block never writes it.

Slave control tasks:

```systemverilog
task set_ack_continuous;   // gap=0, unlimited
task set_ack_waitstates(n); // gap=n, unlimited
task set_ack_n_beats(n);   // gap=0, exactly n acks then stop
task stop_ack;             // disable entirely
```

ACK generation is centralized in the always block. Tasks never write `wb_ack` directly.

---

### 7.2 Scoreboard Layer

The scoreboard is the core of the testbench.

On every `gnt`, push:

```text
addr
we
be
wdata
```

On every `resp_valid`, pop and check:

```text
response corresponds to oldest granted request
if we == 0: resp_rdata == mem_data_for_addr(addr)
if we == 1: resp_rdata is architecturally don't-care; skip rdata check
```

`expected_rdata` is derived from `addr` via `mem_data_for_addr` at check time; it does not need to be stored separately.

The scoreboard should be independent of exact cycle count. It should check ordering and correctness, not implementation timing.

---

### 7.3 Scenario Layer

Scenarios are small directed tests built from the driver and checked by the scoreboard.

Each scenario should describe the behavior being tested, not the internal implementation.

---

## 8. Required Corner Cases

This list focuses only on `ibex_wb_host_adapter`. Cases C9–C12 are named regressions
that correspond directly to the four bugs recorded in README.md § Cache.

### C1. Classic single read

One request, one grant, one Wishbone access, one response.

Checks:

```text
one gnt
one resp_valid
returned data matches address
```

---

### C2. Classic single write

One write request with byte enables and write data.

Checks:

```text
wb_we is correct
wb_dat_w matches captured req_wdata
wb_sel matches captured req_be
one completion response
```

---

### C3. Sequential burst, continuous ACK

Multiple sequential requests:

```text
A, A+4, A+8, A+12
```

Wishbone acknowledges continuously.

Checks:

```text
responses match grant order
burst continues only while addresses are sequential
final beat uses CTI=111 if Wishbone burst mode is used
```

---

### C4. Sequential burst with Wishbone wait states

Same as C3, but `wb_ack` is periodically withheld.

Checks:

```text
no duplicate resp_valid
resp_valid deasserts between ACKs if no response is valid
responses remain ordered
```

This includes the regression:

```systemverilog
test_resp_valid_deasserts_between_wb_acks();
```

---

### C5. Host-side pause (Ibex request gap)

Ibex grants one or more requests, then `req_valid` is negated temporarily.

Checks:

```text
adapter does not invent further responses
Wishbone burst terminates cleanly if no next request is available
```

---

### C6. FIFO full / backpressure

Fill the request FIFO until full.

Checks:

```text
gnt is withheld while FIFO is full
no request is lost
once space is available, granting resumes correctly
```

---

### C7. Address break while FIFO non-empty

Sequential requests are already stored in the FIFO, then Ibex presents a non-sequential address.

Example:

```text
stored: 0x154, 0x158
new request: 0x084
```

Checks:

```text
stored entries are drained and responded to in order
non-sequential address is granted only after FIFO empties
response order remains valid after the break
```

---

### C8. Address break while Wishbone cycle active

A non-sequential request appears while the Wishbone side is actively processing a burst.

Example:

```text
active burst: 0x158, 0x15c
new request:  0x084
```

Checks:

```text
active burst completes gracefully
non-sequential address is granted after the burst drains
no response is duplicated
```

---

### C9. Address break request must not be swallowed

**Regression for README bug 4:** *"Jump 0x158 → 0x84 lost 0x84 request."*

The non-sequential address that triggers an address break must itself eventually be granted
and produce a response. It must not be silently discarded when the adapter terminates
the current burst.

Example:

```text
0x158 in WB pipeline, then 0x084 presented non-sequentially
```

Checks:

```text
0x158 produces one response
0x084 is granted after the break and produces one response
total: 2 grants, 2 responses
```

---

### C10. No resp_valid when FIFO empty (phantom response)

**Regression for README bug 3:** *"Unrequested access to 0x160 accepted after requested 0x15c."*

After all granted requests have been responded to, `resp_valid` must not fire for any
additional Wishbone beat that was never requested.

Example:

```text
only 0x15c is granted; 0x160 must never produce resp_valid
```

Checks:

```text
exactly one grant, exactly one response
resp_valid == 0 for several cycles after the response
```

---

### C11. First beat of burst must not be cut by sequential-address check

**Regression for README bugs 1 and 2:** *"Burst cut because of `fifo_req_addr_q != wb_adr`"*
and *"changing check to `fifo_req_addr != wb_adr + 4` swallowed response for 0x94."*

The sequential-address check that decides whether to continue a burst applies only from
the second beat onward. The first beat has no prior address to compare against and must
not be terminated by the check.

Example:

```text
grant 0x0090 and 0x0094
```

Checks:

```text
2 grants, 2 responses with correct data
if only 1 response arrives, the first-beat cut bug is present
```

---

### C12. Later burst beats must be cut if FIFO head is not sequential

**Regression for README bug 1 (complement):** the sequential-address check must work correctly
for beats after the first.

A multi-beat sequential burst must complete all beats, and the burst must terminate when
the FIFO empties. A subsequent non-sequential request must then start a fresh Wishbone cycle.

Example:

```text
sequential: 0x0100, 0x0104, 0x0108
non-sequential follow-up: 0x0200
```

Checks:

```text
3 grants for sequential burst, 3 correct responses, WB terminates
1 grant for 0x0200 in a fresh cycle, 1 correct response
total: 4 grants, 4 responses
```

---

## 9. Regression Mapping

### README § Cache bug 1 — burst cut on `fifo_req_addr_q != wb_adr`

Maps to: C11, C12

The wrong check terminated the burst after the first beat. C11 proves the first beat is
not cut; C12 proves later beats continue correctly across sequential entries.

---

### README § Cache bug 2 — `fifo_req_addr != wb_adr + 4` swallowed 0x94 response

Maps to: C11

Changing the check from `!= wb_adr` to `!= wb_adr + 4` fixed the continuation direction
but still cut the first beat. C11 regresses the first-beat exemption from the sequential check.

---

### README § Cache bug 3 — unrequested 0x160 response after 0x15c

Maps to: C10

The WB FSM generated `resp_valid` when no FIFO entry was outstanding. C10 verifies
`resp_valid` stays low after all granted requests have been responded to.

---

### README § Cache bug 4 — 0x84 request lost on jump from 0x158

Maps to: C9, C7, C8

The address that triggered the break was silently discarded. C9 directly regresses
the "break address must survive." C7 and C8 cover the FIFO-non-empty and WB-active
variants of the same scenario.

---

### `test_window_reset_after_drained_burst()` (old counter-based regression)

Maps to: C5, C6

---

### `test_resp_valid_deasserts_between_wb_acks()` (old regression)

Maps to: C4 (regression sub-case), C10

---

### `test_nonincremental_branch_restart()` (old regression)

Maps to: C7, C8, C9

---

## 10. Suggested Testbench Coding Rules

1. Avoid fixed cycle-count expectations unless the scenario is explicitly about latency.
2. Drive testbench stimulus on `negedge clk` or through a synchronous model.
3. Avoid nonblocking assignments inside tasks for immediate stimulus changes.
4. Keep ACK generation centralized; do not let multiple forked tasks drive `wb_ack`.
5. Let the scoreboard decide correctness.
6. Keep scenario tasks short and declarative.
7. Instantiate `vlog_tb_utils` for VCD, timeout, and heartbeat handling; do not roll your own plusarg VCD code.
8. In a burst-capable slave model, maintain an internal `slave_adr` counter and never use `wb_adr` directly for `wb_dat_r` in burst continuation. The DUT advances `wb_adr` via NBA at the same posedge the slave evaluates, so `wb_adr` in the evaluation phase still shows the previous beat's address.
9. Use `ack_beats = -1` to mean unlimited acks, `N > 0` for exactly N acks. Decrement with a blocking assignment inside the slave always block so the change is immediate within that evaluation. Tasks write `ack_beats` between clock edges; the always block writes it at posedge — no simultaneous conflict.
10. Assert that CYC never deasserts directly from a burst beat (CTI=010). Register one-cycle delayed copies of `wb_cyc` and `wb_cti` and check at every posedge: if the previous cycle was a burst beat (`wb_cyc_r && wb_cti_r == 3'b010`) and CYC is now 0, that is a protocol violation (R10).

---

## 11. Recommended File Structure

```text
tb/
  ibex_wb_host_adapter_tb.sv
  wb_slave_model.sv
  ibex_req_driver.sv
  scoreboard.sv
  tb_pkg.sv
```

For a small project, these can initially remain in one file, but the logical separation should still be visible.

---

## 12. Short Revised Requirements Text

The adapter accepts Ibex instruction/data requests and translates them to Wishbone host accesses. A request is accepted only when `gnt` is asserted. At that point all request metadata must be stored. Every accepted request must later produce exactly one `resp_valid`, in the same order in which requests were granted.

Wishbone bursts may be used only across stored requests with sequential word addresses. If the next stored request is not sequential, the current burst must be terminated and the next request must start a new Wishbone cycle. The adapter must handle Wishbone wait states, Ibex request gaps, FIFO full conditions, and address breaks without losing, duplicating, or reordering requests.

