CROSS    = riscv64-unknown-elf-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
OBJDUMP  = $(CROSS)objdump
SIZE     = $(CROSS)size

ARCH     = -march=rv32i -mabi=ilp32

CFLAGS   = $(ARCH) -O0 -g -Wall -ffreestanding -nostdlib
LDFLAGS  = $(ARCH) -T link.ld -nostartfiles -nostdlib -lgcc

TARGET   = firmware

.PHONY: all clean

all: $(TARGET).elf $(TARGET).bin $(TARGET).dis

$(TARGET).elf: firmware.c link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ firmware.c

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O verilog $< $@_tmp
	python3 byte2wordbin.py $@_tmp $@

$(TARGET).dis: $(TARGET).elf
	$(OBJDUMP) -d $< > $@

size: $(TARGET).elf
	$(SIZE) $<

clean:
	rm -f $(TARGET).elf $(TARGET).bin $(TARGET).dis
