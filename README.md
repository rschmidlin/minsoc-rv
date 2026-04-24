By calling the following command after compiling sw/firmware, you can see Hello World. on the screen. 

```fusesoc run --target sim minsoc-rv --tool icarus --elf_load /home/user/workspace/minsoc-rv/sw/uart/firmware.elf --timeout 50000```

Alternatively using Verilator

```fusesoc run --target sim minsoc-rv --tool verilator --elf_load ./minsoc-rv/sw/uart/firmware.elf --vcd testbench.vcd```