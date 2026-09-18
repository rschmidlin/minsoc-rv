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
7. Memory may refuse a transfer by asserting `wb_err` instead of `wb_ack`. An error may land on a classic transfer, on a burst beat, or on the final end-of-burst beat.

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

### Bus errors (`wb_err`)

`wb_err` is a cycle-terminating signal in its own right. When the slave asserts it:

```text
the addressed transfer did not complete
wb_dat_r carries no valid read data
the current Wishbone cycle is over
```

The master's correct response is to negate CYC/STB immediately. In particular, an ERR that lands on a burst beat ends the burst there: the remaining beats of that cycle can never be delivered, so there is nothing left to terminate gracefully.

This is the one exception to the burst-abortion rule above. Issuing a `CYC=1, STB=0, CTI=111` graceful-abort cycle after an ERR would mean driving one more STB phase at a slave that has just refused the transfer, so

```text
CTI=010, CYC=1, STB=1, ERR=1  →  CYC=0
```

is legal. A CYC drop out of a burst beat that is *not* answering an ERR remains a protocol violation.

An error terminates the Wishbone *cycle*, not the request stream. Requests already granted behind the failing one are still owed responses and must be serviced by a new Wishbone cycle.

### Burst length versus lookahead depth

The burst-continuation decision is made from a fixed window of upcoming requests — in the current implementation the preload buffer's `slot0`/`slot1`/`slot2` plus, in one case, the FIFO head. Because that window reaches several requests ahead, an address break is seen several beats *before* the burst actually reaches it, and the burst is closed early.

Concretely, for the queue

```text
0x900, 0x904, 0x908, 0x9c0        (0x9c0 is the break)
```

the very first ACK already has `slot0=0x904`, `slot1=0x908`, `slot2=0x9c0` in view. The `slot1 → slot2` step is not sequential (`burst_valid_q` is false), so the burst is terminated there: the cycle transfers 0x900 and 0x904 — the latter as the CTI=111 beat — and 0x908 starts a new cycle even though it was sequential and could have been part of the burst.

This is a **performance** property, not a correctness one. No request is lost, reordered or duplicated, and responses stay in grant order. It is recorded here because:

1. scenarios that need to know which beat is serviced from FINISH (E3) depend on it, and
2. shortening the effective burst is the price the current structure pays for spotting a break early enough to drive CTI=111 on time. Detecting the break later would need a decision window that does not extend past the beat being terminated, which the slot pipeline as structured does not offer.

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

The sole exception is a cycle terminated by `wb_err`, which ends the cycle on its own; see R12.

### R11: Wishbone ERR must be forwarded as resp_err

A `wb_err` must be delivered to the Ibex side as the response for the beat it terminated:

```text
on wb_err:
  resp_valid = 1
  resp_err   = 1
```

This holds in every Wishbone phase the adapter can be in when the error arrives: a classic transfer (CTI=000), a burst beat (CTI=010), and the end-of-burst beat driven from FINISH (CTI=111).

`resp_rdata` is don't-care when `resp_err` is set — no data was transferred. The adapter must not present the slave's error-cycle data bus value as a valid read result, and the testbench must not check read data on an errored response.

### R12: An ERR ends the cycle, not the queue

An errored beat consumes exactly one granted request: the one it was serving. Every request granted behind it is untouched and still owes exactly one response (R5), so the adapter must open a new Wishbone cycle and service them normally.

```text
grant_count == resp_count                  still holds across an error
resp_err is set on exactly one response    (the errored beat)
every other response has resp_err == 0
```

A burst killed by an error must therefore be followed by a fresh cycle for the remainder of the queue, not by a silent drop of those requests. Because the ERR has already terminated the cycle, no graceful-abort cycle precedes the CYC drop (R10 exception).

### R13: An errored request must be retired, not replayed

The request the errored beat was serving is complete: its errored response has been delivered and the Ibex side has accounted for it. It must not be left in the preload buffer to become the first transfer of the next Wishbone cycle.

```text
when the cycle after an error starts:
  wb_adr == address of the request AFTER the errored one
```

A replay is wrong twice over: it re-drives an address the slave has already refused, and it shifts every later response one request out of order.

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

### Error accounting

```text
grant_count == resp_count            holds with or without errors
if resp_err:
  resp_rdata is don't-care and must not be checked
  the errored request is retired and never re-driven on the bus
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

**Error injection:**

The slave answers a chosen response with `wb_err` instead of `wb_ack`. Selecting the victim by *response index* rather than by cycle count keeps the injection independent of wait states and of how long the adapter takes to open the cycle:

```systemverilog
integer slave_resp_idx;       // every response produced since reset, ACKs and ERRs alike
integer err_beat;             // response index to fail; -1 disables
reg     err_on_finish;        // fail whichever beat the DUT services from FINISH
reg     slave_cyc_terminated; // this CYC was ended by ERR; no further responses

wire slave_err_now = ((err_beat >= 0) && (slave_resp_idx == err_beat))
                  || (err_on_finish && (dut.wb_state == DUT_FINISH));
```

The error branch slots in ahead of the two ACK branches of the always block above, `wb_err` gets the same default-low treatment as `wb_ack`, and the whole response arm is gated on `!slave_cyc_terminated`:

```systemverilog
      end else if (wb_stb && ack_enable && !slave_cyc_terminated && (ack_beats != 0)) begin
      if (ack_countdown == 0) begin
        if (slave_err_now) begin
          wb_err               <= 1'b1;
          wb_dat_r             <= 32'hdead_e770;  // poison: never valid read data
          slave_in_burst       <= 1'b0;           // ERR ends the cycle
          slave_cyc_terminated <= 1'b1;           // ...and no more responses on it
        end else if (!slave_in_burst) begin
          ...                                // unchanged, plus wb_ack <= 1'b1
        end else begin
          ...                                // unchanged, plus wb_ack <= 1'b1
        end
        slave_resp_idx <= slave_resp_idx + 1;
        ack_countdown  <= ack_gap;
        if (ack_beats > 0) ack_beats = ack_beats - 1;
      end
```

`slave_cyc_terminated` is cleared with the rest of the per-cycle state when the master negates CYC.

**Why the gate is needed.** ERR ends the cycle, so the slave owes no further response on it. But the adapter has registered outputs and cannot drop CYC/STB in the same cycle it observes the response — STB is still high while the adapter is consuming the ERR and moving to IDLE. A slave that keys only off STB reads that as a fresh bus phase and ACKs it, so the *same* phase gets answered twice: first ERR, then ACK. Assertion S1 below exists to keep that from creeping back in.

The poison value is what catches an adapter that pulses `resp_valid` without `resp_err`: the scoreboard then reports it as a read-data mismatch instead of silently accepting garbage as a read result.

**Slave protocol assertion (S1).** Two things must never be observed on the bus:

```text
wb_ack and wb_err asserted in the same cycle
any response after an ERR, until the master negates CYC
```

This guards the *model*, not the DUT — by the time the stray ACK lands the adapter is in IDLE and ignores it — but a slave that has drifted from the protocol is no longer testing what the DUT will meet in the SoC, so it is asserted continuously rather than left to inspection.

**A related artifact, and what it is not.** The same registered handshake leaves the slave's ACK asserted for one cycle *after* CYC and STB have gone low. This is visible in every waveform and is easy to misread as the adapter driving an extra bus phase. It is not. The adapter holds CYC and STB exactly as long as the protocol requires — from the start of the transfer until it has sampled the terminating signal — and negates them in response to it. A classic transfer shows STB high for two cycles; a four-beat burst for five:

```text
t=155  cyc=1 stb=1 cti=010 adr=0x700 | ack=0     burst opens
t=165  cyc=1 stb=1 cti=010 adr=0x700 | ack=1     beat 1
t=175  cyc=1 stb=1 cti=010 adr=0x704 | ack=1     beat 2
t=185  cyc=1 stb=1 cti=010 adr=0x708 | ack=1     beat 3
t=195  cyc=1 stb=1 cti=111 adr=0x70c | ack=1     beat 4, end of burst
t=205  cyc=0 stb=0 cti=000           | ack=1     master gone, ACK trailing
```

The trailing ACK is the slave answering the STB it validly saw during the final handshake cycle, one cycle late. No transfer is implied by it — CYC is low — so nothing is read or written twice, and the adapter, in IDLE, ignores it. It is benign, and deliberately *not* what S1 asserts against: S1 is only about ERR, where a second response would contradict the first rather than merely repeat it.

Control tasks, alongside the ACK tasks:

```systemverilog
task set_err_after_beats(n);  // n normal responses from now, then ERR
task set_err_on_finish;       // ERR on the CTI=111 beat serviced from FINISH
task clear_err_injection;
```

**`err_on_finish` requires at least one wait state (`ack_gap >= 1`).** With continuous ACKs, the response that ends the burst is produced at the very posedge at which the adapter decides to enter FINISH — and the slave reads `dut.wb_state` in the evaluation phase, *before* that state register updates, so it still sees BURST and ACKs the final beat. The error would then fall on the extra CTI=111 STB phase that the adapter no longer consumes, and never reach the Ibex side.

One wait state removes the ambiguity: after every response the slave counts down for a cycle, so it is guaranteed to be idle on the BURST→FINISH edge, and the next response it produces — with `dut.wb_state` now reading FINISH — is exactly the one the adapter consumes while parked there.

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

```text
if resp_err == 1: skip the rdata check entirely (R11)
```

`expected_rdata` is derived from `addr` via `mem_data_for_addr` at check time; it does not need to be stored separately.

On every `resp_valid` the scoreboard should also **record `resp_err`, indexed in grant order**, so scenarios can assert *which* response carried the error. `resp_err` is a one-cycle pulse riding along with its `resp_valid`; a scenario task that samples it directly will almost always miss it.

**Wishbone address trace.** Checking R13 needs two more monitors:

```text
wb_cyc_addr[]     address each Wishbone cycle STARTS with (sampled when STB rises)
watch_addr_beats  number of terminated beats seen at a watched address
```

Sampling rule: both the slave's ACK/ERR and the adapter's `wb_adr` increment are registered, so **at the posedge where the DUT samples `wb_ack`/`wb_err`, `wb_adr` is the address of the beat being terminated**. That is the edge to count on. This is the mirror image of the slave-side hazard described in 7.1 — the *slave* cannot trust `wb_adr` during a burst, but a monitor sampling at the adapter's acceptance edge can.

It is also worth recording where the last error landed — its bus address, the CTI it was driven under, and the DUT state that consumed it — so each error scenario can prove the error occurred in the phase it claims to cover rather than somewhere else. Without that, an E-series test that accidentally errors the wrong beat still passes its grant/response counts.

The scoreboard should be independent of exact cycle count. It should check ordering and correctness, not implementation timing.

---

### 7.3 Scenario Layer

Scenarios are small directed tests built from the driver and checked by the scoreboard.

Each scenario should describe the behavior being tested, not the internal implementation.

---

## 8. Required Corner Cases

This list focuses only on `ibex_wb_host_adapter`. Cases C9–C12 are named regressions
that correspond directly to the four bugs recorded in README.md § Cache. Cases E1–E5
cover Wishbone bus errors (R11–R13): one per Wishbone phase in which an error can land,
E4 for the first beat of a burst, and E5 for an error taken while the preload buffer is
popped and refilled on the same edge. See *How the errored request gets retired* at the
end of this section for what separates them.

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

### E1. Bus error on a classic transfer

An ERR terminating a classic (CTI=000) transfer while further requests are already granted behind it.

Setup:

```text
stall the WB side and issue 0x300 alone    -> no second entry is visible at PREPARE1,
                                              so no burst opens and the FSM parks in CLASSIC
grant 0x304 and 0x308 while it is stalled  -> both are owed responses regardless
                                              of how 0x300 ends
release the bus with ERR on the first slave response
```

Checks:

```text
3 grants, 3 responses                                    (R12)
resp_err set on response 0 only                          (R11)
the errored beat was consumed in CLASSIC with CTI=000
the next Wishbone cycle starts at 0x304, not 0x300       (R13)
exactly one bus beat ever addressed 0x300                (R13)
```

---

### E2. Bus error on a burst beat

An ERR mid-burst, with several sequential requests still queued behind the failing beat. This covers the burst in *steady state* — at least one beat has already been acknowledged. The opening beat is covered separately by E4.

Setup:

```text
stall the WB side, pile up 0x800..0x814 (six sequential reads)
release with one good beat then ERR -> 0x800 ACKs, 0x804 errors,
                                       0x808..0x814 still queued
```

Checks:

```text
6 grants, 6 responses                                    (R12)
resp_err set on response 1 only                          (R11)
the errored beat was consumed in BURST with CTI=010
CYC may drop straight out of the burst beat              (R10 exception)
the next Wishbone cycle starts at 0x808, not 0x804       (R13)
exactly one bus beat ever addressed 0x804                (R13)
```

---

### E3. Bus error on the end-of-burst (FINISH) beat

The distinct case. The adapter has already terminated the burst itself — CTI=111 is driven and the preload buffer has been popped — and is only waiting for the last beat to be acknowledged. An ERR arriving there must still produce the response for that beat, and whatever was queued behind the burst must still be serviced.

Setup:

```text
stall the WB side, pile up 0x900, 0x904, 0x908 (sequential) and 0x9c0 (break)
release with one wait state (see 7.1) and err_on_finish armed
```

Checks:

```text
4 grants, 4 responses                                    (R12)
resp_err set on exactly the FINISH beat's response       (R11)
the errored beat was consumed in FINISH with CTI=111
the next Wishbone cycle starts at the request after the errored one   (R13)
exactly one bus beat ever addressed the errored beat     (R13)
```

**Which beat FINISH actually services.** Not the one this queue suggests. Per §4, *Burst length versus lookahead depth*, the slot2 lookahead sees the 0x9c0 break on the very first ACK, so the burst closes after **0x904** — that is the CTI=111 beat — and **both** 0x908 and 0x9c0 are the already-granted requests that must continue afterwards. The scenario is written against that, which makes it a regression on the lookahead depth as well as on error handling: if the effective burst length changes, the address assertions here fail loudly rather than the test quietly covering a different case.

---

### E4. Bus error on the first beat of a burst

The opening beat of a burst is a different path from every later one, so an error there is not covered by E2:

```text
its preload-buffer pop was issued by PREPARE1, not by a preceding ACK,
so no pop-on-ack has yet run inside BURST

the RTL uses resp_valid as the "we acked previously and consequently
popped the buffer" flag, and resp_valid is 0 only on this beat
```

It is also the only case in which a burst dies with no successful beat at all.

Setup:

```text
stall the WB side, pile up 0xa00..0xa14 (six sequential reads)
release with ERR on the very first slave response
```

Checks:

```text
6 grants, 6 responses                                    (R12)
resp_err set on response 0 only                          (R11)
the errored beat was consumed in BURST with CTI=010 at 0xa00
the next Wishbone cycle resumes at 0xa04                 (R13)
exactly one bus beat ever addressed 0xa00                (R13)
```

The failure this isolates is an **off-by-one in what the error retires**. The errored response must belong to the burst's own first request, and the next cycle must resume at the second one. Retiring one request too many restarts at 0xa08 and silently drops 0xa04; retiring one too few replays 0xa00. The cycle-start address and `watch_addr_beats` catch them respectively, and the response count catches the drop.

That the beat is genuinely distinct is demonstrable: a fault injected only into the `resp_valid == 0` path — an errored opening beat that produces no response at all — leaves E2 passing and is caught only by E4.

**Why there is no "first beat is also the FINISH beat" case.** It cannot occur, so E1–E4 are complete over the error phases:

```text
PREPARE1 enters BURST only on slot1_valid && burst_valid
  -> a burst needs two visible sequential requests; the minimum burst is
     two beats, and a lone request is issued as a classic transfer

FINISH is reachable only from the BURST wb_ack branch
  -> at least one ACK has been taken, so the CTI=111 beat is always beat >= 2
```

E4's condition (`resp_valid == 0`, first beat) and E3's (CTI=111, FINISH) are therefore mutually exclusive by construction. The minimal burst runs beat 1 as CTI=010 in BURST and beat 2 as CTI=111 in FINISH.

---

### E5. Bus error under back pressure, on a pop-and-refill edge

E2 and E4 error a burst that is draining a queue nobody is refilling. E5 keeps the Ibex side pushing for the whole test, so the FIFO stays full, the burst runs at one beat per cycle, and on every beat the preload buffer pops `slot0` and reads the FIFO on the *same* edge — the `fifo_forward` path, in which `fifo_dout` is consumed as the third-word lookahead (`burst_valid_qq`).

Setup:

```text
drive sequential requests continuously for the whole test (FIFO stays full)
let the FIFO saturate, then release continuous ACKs with ERR on beat 3
```

Checks, beyond the usual R11–R13 set:

```text
gnt was actually refused at some point      (back pressure really occurred)
fifo_empty == 0 at the error                (the refill path is the point)
fifo_forward == 1 at the error              (the scenario was reached)
slot0 still holds the erroring address at the error edge
preload_buffer_pop == 1 at the error edge   (the retiring pop is in flight)
```

**What this settles.** At the error edge `slot0` still holds the address that is erroring on the bus, so retiring it *requires* a preload-buffer pop — and the error path never issues one. It works because the pop was already scheduled by the **previous beat's ACK** and lands on this very edge. The `preload_buffer_pop <= 1'b0` at the top of the BURST block cannot cancel it: the buffer sampled the pop during the cycle that is now ending.

Correct behaviour here therefore rests on a cross-beat timing relationship rather than on anything the error handling does, which is the kind of dependency that breaks silently. Suppressing that in-flight pop on error (`slot0_pop & ~wb_err`) shifts every subsequent response one request out of order — every later read returns its neighbour's data.

The white-box checks are what stop the scenario decaying: if the stimulus stops reaching the `fifo_forward` path, the test fails rather than quietly becoming a second copy of E2.

---

### How the errored request gets retired

The five error scenarios are not five dressings of one case. Measured at the error edge, each lands the adapter in a different preload-buffer state, and there are **two distinct retirement mechanisms**:

| case | `fifo_forward` | `pop` in flight | `slot2_valid` | FIFO | `slot0` vs bus address | retired |
|---|---|---|---|---|---|---|
| E1 classic | 0 | 0 | 0 | filling | stale, invalid | before the error |
| E2 burst, steady state | 0 | **1** | 1 | loaded | **same** | by the in-flight pop |
| E3 FINISH | 0 | 0 | 0 | empty | already advanced | before the error |
| E4 burst, first beat | 0 | 0 | 1 | loaded | already advanced | before the error |
| E5 back pressure | **1** | **1** | 0 | **full** | **same** | by the in-flight pop |

Where `slot0` has already advanced past the bus address (E1, E3, E4), the request was retired by an earlier pop and the error path has nothing left to do. Where `slot0` still holds it (E2, E5), retirement depends on the in-flight pop landing on the error edge.

E5 is the only case in which `fifo_forward` is active at the error — the only one where `fifo_dout` is part of the live burst-decision window at the moment the cycle dies. That is why it exists despite E2 covering the same retirement mechanism.

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
10. Assert that CYC never deasserts directly from a burst beat (CTI=010). Register one-cycle delayed copies of `wb_cyc` and `wb_cti` and check at every posedge: if the previous cycle was a burst beat (`wb_cyc_r && wb_cti_r == 3'b010`) and CYC is now 0, that is a protocol violation (R10) — **unless that cycle also carried `wb_err`**, which terminates the cycle on its own (§4, *Bus errors*). Register a delayed copy of `wb_err` too and exempt that case, otherwise every legitimate error abort trips the assertion.
11. Inject bus errors by *response index*, not by cycle count or by waiting for a bus condition from a scenario task. A response counter in the slave makes the injection immune to wait states, to how long the adapter takes to open the cycle, and to the burst length the adapter happens to choose.
12. Record `resp_err` per response in the scoreboard, indexed in grant order. It is a one-cycle pulse; a scenario task that samples it after `wait_responses` returns will miss it. Skip the `resp_rdata` check whenever `resp_err` is set, and have the slave drive a recognisable poison value during an error cycle so a dropped `resp_err` surfaces as a data mismatch.
13. When a monitor needs the address of the beat that a `wb_ack`/`wb_err` terminates, sample `wb_adr` at the posedge the *DUT* accepts it. Both the slave's response and the adapter's address increment are registered, so at that edge `wb_adr` is the terminated beat's address — the opposite of the slave-side situation in rule 8.
14. Stop the slave from responding for the rest of a cycle it has terminated with ERR, and assert that it never does (S1, §7.1). Because the adapter's CYC/STB are registered, STB is still asserted while it consumes the ERR; a slave gated on STB alone will answer the same bus phase a second time with an ACK. Assert the ACK/ERR mutual exclusion in the same monitor — it costs nothing and both are real Wishbone rules.

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

A Wishbone `wb_err` must be forwarded to the Ibex side as `resp_err` on the response for the beat it terminated, in every phase an error can arrive: classic transfer, burst beat, and end-of-burst beat. An error terminates the Wishbone cycle — including any burst in progress, with no graceful-abort cycle needed — but not the request queue: requests granted behind the failing one are still owed exactly one response each and must be serviced by a new Wishbone cycle. The errored request is retired by its errored response and must never be replayed as the first transfer of that next cycle.

