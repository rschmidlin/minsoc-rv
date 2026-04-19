By calling the following command after compiling sw/firmware, you can see Hello World. on the screen. 

```fusesoc run --target sim minsoc-rv --elf_load /home/user/workspace/minsoc-rv/sw/uart/firmware.elf --timeout 100000000```