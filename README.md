# MinSoC-RV - Minimal System-on-Chip RISC-V - shortest path between a CPU and a peripheral

MinSoC-RV follows the path of OpenCores MinSoC offering a minimal system-on-chip. This time the offered CPU implementes the RISC-V ISA. MinSoC-RV focus on readability and establishing a minimum set of modules still allowing you to get easily started with your own system-on-chip, peripheral or accelerator. Only memory and a UART peripheral are integrated alongside a working debug interface. In addition to the system-on-chip, the project offers a simple simulation environment to execute example applications while exercising the hardware design. This way, the system remains  small and mangeable so that a person can explore and understand it fully.

![Block diagram](/doc/SoC.png)

MinSoC-RV currently runs on the Boolean board and has also run on Nexys-A7 before. Easy FPGA integration has not yet been addressed. 

The extensibility of MinSoC is powered now by Fusesoc allowing integration of versioned IP cores and a standard way of simulating, synthesizing and linting the design. MinSoC-RV uses the wb_intercon core to generate its interconnect allowing for flexible extension and easy definition of the memory map. 

The selection of the CPU for MinSoC-RV was a lot more challenging in comparison to the selection of the OpenRISC CPU for MinSoC. There are multiple RISC-V CPUs today while back then there was basically only one option. Many open CPUs come with their own ecosystem and require rather complex configuration before getting a runnable system. In order to reach the goal of being understandable, I decided for a SystemVerilog implementation. This way the whole system is readable in a single language. 

Selecting the interconnect and its protocol matter for the peripherals to be used. It should be generated so that extensibility is easy different for example from original MinSoC's interconnect. My decision here is to re-use LibreCores IP-Cores because MinSoC already used them and they are intended for re-use and many are very mature to this date. For this reason the used protocol is Wishbone. Another reason for selecting Wishbone is the readability of data transmission in waveforms, as it is limited to a single defined time span and composed by a limited number of signals. This can happen at cost of performance but burst transmissions can help. Another advantage of Wishbone's simplicity is that it can lower the barrier of peripheral implementation because it is based on a simple contract between registerblock and interconnect. 

As MinSoC-RV ambition is to be seriously considered by embedded systems in MCU range. And for this, fast memory access is key. Cache helps here as after addresses are read they are available a single cycle until they get invalidated. Burst-memory access and cache read behavior complement themselves very well and is a target of MinSoC-RV. This has brought the decision about the CPU to Ibex, because Ibex offers cache, debugging, readability and low complexity. 

Burst access is done via the module ibex_wb_host_adapter. It converts Ibex memory accesses into Wishbone transmissions and issues burst accesses when it detects sequential memory accesses. Its implementation allow full asynchronous behavior and by consequence a sliding window. 

## Memory mapping

| Region                         | Address                                  |
|--------------------------------|------------------------------------------|
| BRAM / boot RAM                | `0x0000_0000 – 0x0000_FFFF`              |
| Internal SRAM / future TCM     | `0x0100_0000`                            |
| Debug ROM                      | `0x1A11_0000`                            |
| UART                           | `0x2000_0000`                            |
| Timer                          | `0x2000_1000`                            |
| External DDR / AXI memory      | `0x8000_0000`                            |

## Installation

### Packages

Install fusesoc and packaging in a virtual environment. 

```
mkdir workspace
cd workspace
python -m venv .venv
source .venv/bin/activate
pip install fusesoc
pip install packaging
git clone https://github.com/rschmidlin/minsoc-rv.git
```

Prepare fusesoc

```
fusesoc library add fusesoc-cores https://github.com/fusesoc/fusesoc-cores
fusesoc library add elf-loader https://github.com/fusesoc/elf-loader.git
fusesoc library add minsoc-rv
```

Install Verilator and riscv compiler
```
sudo apt install gcc-riscv64-unknown-elf verilator libelf-dev
```

### MinSoC-RV Preparation

After cloning MinSoC-RV, also initialize and update its submodules. 

```
git submodule update --init --recursive
```

And patch riscv-dbg

```
cd vendor/riscv-dbg
patch -p1 < ../../patches/riscv-dbg_lowrisc_prim.patch
```

## First execution

By calling the following command after compiling sw/firmware, you can see Hello World. on the screen. 

```
cd <path>/workspace
make -C minsoc-rv/sw/common
make -C minsoc-rv/sw/hello
source .venv/bin/activate
fusesoc run --target sim --elf_load ~/workspace/minsoc-rv/sw/hello/hello.elf
```


## VCD Debugging hints 
Hints on how to debug: trace following signals to keep track of Ibex execution:

| Signal                   | Bedeutung                                                                  | Modulpfad                                                                              |
|--------------------------|----------------------------------------------------------------------------|----------------------------------------------------------------------------------------|
| pc_if                    | Instruction-Fetch (IF) Program Counter (PC) / nächste auszulesende Adresse | TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.pc_if                               |
| instr_rdata_i            | Daten, die an der Instruction-Schnittstelle anliegen                       | TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.instr_rdata_i                       |
| pc_id                    | Program Counter im Instruction Decoder                                     | TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.pc_id                               |
| instr_valid_id           | ID-Anweisung ist gültig                                                    | TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.instr_valid_id                      |
| instr_is_compressed_id_o | Anweisung ist eine komprimierte Anweisung                                  | TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.if_stage_i.instr_is_compressed_id_o |
| instr_rdata_c_id         | Komprimierte Anweisung, die im ID liegt                                    | TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.instr_rdata_c_id                    |
| instr_rdata_id           | Anweisungswort, die im Instruction-Decoder (ID) liegt                      | TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.instr_rdata_id                      |
| jump_set / branch_set    | Sprunganweisung gültig                                                     | TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.id_stage_i.(jump_set/branch_set)    |
| pc_set                   | Sprunganweisung gültig                                                     | TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.pc_set                              |
| branch_target_ex         | Sprungadresse die angesprungen wird                                        | TOP.minsoc_rv_top.ibex_wb_i.ibex_top_i.u_ibex_core.branch_target_ex                    |

## Licensing

This project is primarily licensed under Apache-2.0.

Third-party components retain their original licenses:

- Ibex: Apache-2.0
- wb_intercon: ISC

Simulation infrastructure includes GPL-derived components from mor1kx/orpsoc testbench code.

See LICENSES/ for details.
