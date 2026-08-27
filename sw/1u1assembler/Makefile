# SPDX-License-Identifier: Apache-2.0
#
# Copyright 2026 Raul Schmidlin

CROSS    = riscv64-unknown-elf-
CC       = $(CROSS)gcc
OBJCOPY  = $(CROSS)objcopy
OBJDUMP  = $(CROSS)objdump
SIZE     = $(CROSS)size
AR		 = $(CROSS)ar
RANLIB	 = $(CROSS)ranlib

ARCH     = -march=rv32im_zicsr_zifencei -mabi=ilp32

CFLAGS   = $(ARCH) -mcmodel=medany -Wall -fvisibility=hidden -ffreestanding -O0 -g -Wall -ffreestanding -nostdlib
LDFLAGS  = $(ARCH) -T link.ld -nostartfiles -nostdlib -lgcc

TARGET   = 1u1assembler

.PHONY: all clean

OBJS = 1u1assembler.o

all: $(TARGET).elf $(TARGET).dis

$(TARGET).elf: link.ld $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -I$(INCDIR) -L$(LIBDIR) $(OBJS) -o $@

$(TARGET).dis: $(TARGET).elf
	$(OBJDUMP) -d $< > $@

%.o: %.c
	$(CC) $(CFLAGS) $(INCLUDESPATH) -c $< -o $@

%.o: %.S
	$(CC) $(ARCH) -g $(INCLUDESPATH) -c $< -o $@

clean:
	rm -f $(TARGET) $(OBJS)
