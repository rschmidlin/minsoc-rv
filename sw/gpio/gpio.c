// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 Raul Schmidlin

#include "demo_system.h"
#include "minsoc_rv_system_conf.h"
#include "uart.h"
#include "timer.h"
//#include <stdio.h>

/* ------------------------------------------------------------------ */
/* main                                                               */
/* ------------------------------------------------------------------ */
int main(void)
{
    unsigned int start = timer_get();
    uart_init(UART0_BASE);
    install_exception_handler(UART_IRQ_NUM, &uart_interrupt);
    enable_interrupts(UART_IRQ);
    set_global_interrupt_enable(1);
    unsigned int end = timer_get();

    // Initialize IOs to output
    REG32(0x20002000) = -1;

    // Set output to DEADBEEF
    REG32(0x20002008) = 0xdeadbeef;

    uart_print_str("Init time elapsed in clock cycles: ");
    puthex(end-start);
    putchar('\n');
    uart_print_str("Hello World.\n");

    /* Spin forever */
    while (1) {
        asm volatile("wfi");
    }
    return 0;
}
