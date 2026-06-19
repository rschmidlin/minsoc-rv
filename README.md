Install fusesoc, edalize and packaging in a virtual environment. 

```
python -m venv .venv
source .venv/bin/activate
pip install fusesoc
pip install edalize
pip install packaging
```

Prepare fusesoc

```
fusesoc library add fusesoc-cores https://github.com/fusesoc/fusesoc-cores
fusesoc library add elf-loader https://github.com/fusesoc/elf-loader.git
fusesoc library add minsoc-rv
```

Install Verilator and riscv compiler
```
sudo apt install gcc-riscv64-unknown-elf verilator
```

By calling the following command after compiling sw/firmware, you can see Hello World. on the screen. 

```fusesoc run --target sim --tool icarus minsoc-rv --elf_load /home/user/workspace/minsoc-rv/sw/uart/firmware.elf --timeout 50000```

Alternatively using Verilator

```fusesoc run --target sim --tool verilator minsoc-rv --elf_load ./minsoc-rv/sw/uart/firmware.elf --vcd testbench.vcd```


Current development: debugger mimics memory to CPU in order to debug. To do so, Ibex parameter for address to jump to in debug must be set and it must match the slave address of the debug unit in core file for the Wishbone generator

Adaptations to riscv-dbg:
    - applied 0001-User-lowrisc-instead-of-PULP-primitives.patch to vendor/riscv-dbg
    - substituted fifo_v3 of dm_csrs.sv by prim_fifo_sync

Next steps:
    1) [X] Interruptfähigkeit
    2) [X] Timer
    3) [X] Set license
    4) [X] Re-organize base addresses
    5) [X] Clean-up unused wires and file formatting
    6) [X] Cache
    7) [ ] Axi-Adapter
    8) [ ] Build with Yosys? 

## Planned memory mapping

| Region                         | Address                                  |
|--------------------------------|------------------------------------------|
| BRAM / boot RAM                | `0x0000_0000 – 0x0000_FFFF`              |
| Internal SRAM / future TCM     | `0x0100_0000`                            |
| Debug ROM                      | `0x1A11_0000`                            |
| UART                           | `0x2000_0000`                            |
| Timer                          | `0x2000_1000`                            |
| External DDR / AXI memory      | `0x8000_0000`                            |


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

#### VCD Debugging hints 
Hints on how to debug: trace following signals to keep track of Ibex execution:

```
TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.pc_id[31:0]
TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.pc_if[31:0]
TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.instr_rdata_c_id[15:0]
TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.instr_rdata_i[31:0]
TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.instr_rdata_id[31:0]

TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.instr_valid_id
TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.id_stage_i.controller_i.BranchPredictor
TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.id_stage_i.jump_set
TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.id_stage_i.jump_set_raw
TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.id_stage_i.branch_set
TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.id_stage_i.branch_set_raw
TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.if_stage_i.instr_is_compressed_id_o
```

instr_rdata_i      raw bus/fetch response
instr_rdata_id     instruction word visible in ID
instr_rdata_c_id   compressed halfword visible in ID
pc_if              IF-stage PC / next frontend position
pc_id              ID-stage PC
instr_valid_id     ID instruction is valid
instr_is_compressed_id_o  why PC advances by 2 instead of 4
jump_set / branch_set     control-flow decision

#### Missing points

  - 1) [X] Instead of going to idle and removing cyc immediately, finish WB gracefuly and avoid resp_valid
  - 2) [X] double-check fifo size because it is never full
  - 3) [X] fifo_last_beat logic seems not to work, maybe related to point nr. 2
  - 4) [X] req_len logic is meaningless, maybe remove
  - 5) [X] test if it works without activated cache
  - 6) [X] Adapt wb_ibex_device_adapter to work with host burst requests
  - 7) [X] Check if ib_fsm could be replaced by Ibex directly connected to FIFO req_valid <-> wr_en
  - 8) [X] Only negate gnt if fifo_full, requires that wr_en is based on both req_valid and gnt
  - 9) [ ] Rename top_nexyssa7.sv to top_xilinx.sv? 

## Licensing

This project is primarily licensed under Apache-2.0.

Third-party components retain their original licenses:

- Ibex: Apache-2.0
- wb_intercon: ISC

Simulation infrastructure includes GPL-derived components from mor1kx/orpsoc testbench code.

See LICENSES/ for details.