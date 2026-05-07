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