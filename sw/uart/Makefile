CROSS    = riscv64-unknown-elf-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
OBJDUMP  = $(CROSS)objdump
SIZE     = $(CROSS)size

ARCH     = -march=rv32imc_zicsr_zifencei -mabi=ilp32 -mcmodel=medany -Wall -fvisibility=hidden -ffreestanding

CFLAGS   = $(ARCH) -O0 -g -Wall -ffreestanding -nostdlib
LDFLAGS  = $(ARCH) -T link.ld -nostartfiles -nostdlib -lgcc

TARGET   = firmware

.PHONY: all clean

INCDIR 	 = ../common
LIBDIR	 = ../common
LIB 	 = common

all: $(TARGET).elf $(TARGET).bin $(TARGET).dis

$(TARGET).elf: firmware.c link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -I$(INCDIR) -L$(LIBDIR) -o $@ firmware.c ../common/crt0.o -l$(LIB)

$(TARGET).bin: $(TARGET).elf
	$(OBJCOPY) -O verilog $< $@_tmp
	@python3 byte2wordbin.py $@_tmp $@
	@rm $@_tmp

$(TARGET).dis: $(TARGET).elf
	$(OBJDUMP) -d $< > $@

size: $(TARGET).elf
	$(SIZE) $<

clean:
	rm -f $(TARGET).elf $(TARGET).bin $(TARGET).dis $(TARGET).bin_tmp
