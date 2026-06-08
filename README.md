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
    6) [ ] Cache
    7) [ ] Axi-Adapter
    8) [ ] Build with Yosys? 

## Cache

Encountered problems: 
  - 1) verschlucken von data, weil burst cut because of fifo_req_addr_q != wb_adr @236 ps
  - 2) attempt to modify to fifo_req_addr != wb_adrr + 4 led to verschlucken von response of address 94 - was already cut with 1
    Solution: solved by only checking outside of first request

  - 3) @220ps, accepting unrequested accesss to 0x160 from requested 0x15c that should follow with 0x144
    Solution: remove resp_valid if fifo_empty

  - 4) around 750 ps, on jump from 0x158 to 0x84, lost 0x84 request
    Solution: cancel request immediately on non-continuous access

Missing points:
  - 1) Instead of going to idle and removing cyc immediately, finish WB gracefuly and avoid resp_valid
  - 2) double-check fifo size because it is never full
  - 3) fifo_last_beat logic seems not to work, maybe related to point nr. 2
  - 4) req_len logic is meaningless, maybe remove
  - 5) test if it works without activated cache
  - 6) Adapt wb_ibex_device_adapter to work with host burst requests
  - 7) Check if ib_fsm could be replaced by Ibex directly connected to FIFO req_valid <-> wr_en

## Planned memory mapping

| Region                         | Address                                  |
|--------------------------------|------------------------------------------|
| BRAM / boot RAM                | `0x0000_0000 – 0x0000_FFFF`              |
| Internal SRAM / future TCM     | `0x0100_0000`                            |
| Debug ROM                      | `0x1A11_0000`                            |
| UART                           | `0x2000_0000`                            |
| Timer                          | `0x2000_1000`                            |
| External DDR / AXI memory      | `0x8000_0000`                            |

## Licensing

This project is primarily licensed under Apache-2.0.

Third-party components retain their original licenses:

- Ibex: Apache-2.0
- wb_intercon: ISC

Simulation infrastructure includes GPL-derived components from mor1kx/orpsoc testbench code.

See LICENSES/ for details.