## Cache

### Enabled by implementation of B4 Wishbone adapter with bursts

#### Architecture 

Architecture went through several steps reaching b5 or actually wishbone-burst-5. 

b4:
  weaker abstraction, because WB ACK directly drives FIFO reading.
  But the timing relation is neat: ACK means advance burst and fetch next candidate.

b5:
  stronger abstraction, because WB FSM normally reasons only about slot0/slot1.
  But the extreme no-bubble burst case reintroduces a carefully gated dependency on FIFO fallthrough.

| Variant                 | Main idea                                         | Strength                    | Weakness                        | Branch            | 
| ----------------------- | ------------------------------------------------- | --------------------------- | ------------------------------- |-------------------|
| Direct FSM              | no real queue, state-driven translation           | small                       | fragile around redirects/bursts | wishbone-burst    |
| Window/counter FSM      | accepted/transferred window tracking              | efficient                   | hard invariants                 | wishbone-burst-b2_working |
| FIFO with Ibex-side FSM | FSM accepts from Ibex, then writes FIFO           | controlled, easier to stage | two control layers              | wishbone-burst-b3 |
| FIFO directly on Ibex   | `req && gnt` pushes FIFO                          | clean OBI invariant         | WB side needs lookahead         | wishbone-burst-b4 |
| FIFO + preload buffer   | direct FIFO plus explicit `slot0/slot1` lookahead | cleanest separation         | slightly more local buffering   | wishbone-burst-b5 |

| Variant                 | Performance               | Stability | Determinism                    | Release suitability         |
| ----------------------- | ------------------------- | --------- | ------------------------------ | --------------------------- |
| Direct FSM              | potentially low latency   | weak      | weak around redirects/bursts   | no                          |
| Window/counter FSM      | probably fastest/smallest | fragile   | hard invariants                | no                          |
| FIFO with Ibex-side FSM | decent                    | better    | medium, but two control layers | maybe educational           |
| FIFO directly on Ibex   | good                      | good      | clean OBI boundary             | good, but lookahead awkward |
| FIFO + preload buffer   | good to very good         | best      | best                           | yes                         |


#### Verification

Parts of the adapter testbench were developed with AI assistance and then reviewed,
adapted, and extended during debugging of the real SoC-level failures. The final
tests encode the regression cases that drove the adapter architecture.

Verification steps:

Version 1:
  waveform inspection

Version 2:
  instruction trace

Version 3:
  request/response trace

Version 4:
  scoreboard

#### Problems leading to testcases
  - 1) verschlucken von data, weil burst cut because of fifo_req_addr_q != wb_adr @236 ps
  - 2) attempt to modify to fifo_req_addr != wb_adrr + 4 led to verschlucken von response of address 94 - was already cut with 1
    Solution: solved by only checking outside of first request

  - 3) @220ps, accepting unrequested accesss to 0x160 from requested 0x15c that should follow with 0x144
    Solution: remove resp_valid if fifo_empty

  - 4) around 750 ps, on jump from 0x158 to 0x84, lost 0x84 request
    Solution: cancel request immediately on non-continuous access

  - 5) after conversion to FIFO interface on Ibex - two different scenarios when burst needs to be stopped:
        - a) next address was not granted but fifo_req_addr is not valid because last fifo_rd_en is way back - C6
              results in burst being scattered - performance is bad
        - b) fifo_rd_en is asserted and address is invalid - C7 & C8

    Solution: address has to be evaluated, period. After first acknowledgement, we need to at least negate resp_valid if address check was not possible. 

  - 6) Instruction of address 0x648 was swallowed at 3184 ps with commit 0e93ccca5c159753b8fe737307575d4e8d602efa because of too many fifo_rd_en, one too much at end of burst
    Solution: avoid fifo_rd_en during FINISH. Question is whether this is always valid. 

  - 7) Testbench is not working properly because of combinatorial FIFO read: FIFO ends up reading more than expected. 

  - 8) Preload buffer burst_addr_valid logic is tweaked by slot2 (0x88) and slot 1 (0x84) on a new range but incremental while adapter is still processing slot 0 (0x15C). Burst is not cancelled. 
    Problem: prepare checks slot0 & 1 for burst, burst checks slot 2 & 1 after prepare buffer is popped, meaning that there was no check for slot 1 and 2 according to the initial conditions. Since prepare buffer contains addresses, 0x158, 0x15C, 0x84, 0x88, it works if first two and last two are checked but nobody checks steps 0x15C to 0x84.  
    Solution: Also check for burst_valid in BURST state. 

