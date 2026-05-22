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
    2) [ ] Timer
    3) [ ] Cache
    4) [ ] Set license
    5) [ ] Re-organize base addresses
    6) [ ] Clean-up unused wires and file formatting
    7) [ ] Axi-Adapter
