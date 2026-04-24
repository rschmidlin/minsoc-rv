If you install edalize over pipx, need to export the path and make it available to fusesoc:

```
pipx inject fusesoc edalize
export PYTHONPATH=$(python3 -c "import site; print('/home/user/.local/pipx/venvs/fusesoc/lib/python3.11/site-packages')")
```

By calling the following command after compiling sw/firmware, you can see Hello World. on the screen. 

```fusesoc run --target sim --tool icarus minsoc-rv --elf_load /home/user/workspace/minsoc-rv/sw/uart/firmware.elf --timeout 50000```

Alternatively using Verilator

```fusesoc run --target sim --tool verilator minsoc-rv --elf_load ./minsoc-rv/sw/uart/firmware.elf --vcd testbench.vcd```