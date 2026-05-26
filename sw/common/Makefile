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

ARCH     = -march=rv32imc_zicsr_zifencei -mabi=ilp32

CFLAGS   = $(ARCH) -mcmodel=medany -Wall -fvisibility=hidden -ffreestanding -O0 -g -Wall -ffreestanding -nostdlib
LDFLAGS  = $(ARCH) -T link.ld -nostartfiles -nostdlib -lgcc

TARGET   = libcommon.a

.PHONY: all clean

OBJS = demo_system.o crt0.o uart.o timer.o

all: $(TARGET)

$(TARGET): $(OBJS)
	$(AR) cru $@ $^
	$(RANLIB) $@

%.o: %.c
	$(CC) $(CFLAGS) $(INCLUDESPATH) -c $< -o $@

%.o: %.S
	$(CC) $(ARCH) $(INCLUDESPATH) -c $< -o $@

clean:
	rm -f $(TARGET) $(OBJS)
