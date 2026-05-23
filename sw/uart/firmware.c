#include "demo_system.h"
#include "uart.h"
#include "timer.h"
//#include <stdio.h>

#define UART_BASE  		0x90000000

/* ------------------------------------------------------------------ */
/* main                                                               */
/* ------------------------------------------------------------------ */
int main(void)
{
    unsigned int start = timer_get();
    uart_init(UART_BASE);
    install_exception_handler(UART_IRQ_NUM, &uart_interrupt);
    enable_interrupts(UART_IRQ);
    set_global_interrupt_enable(1);
    unsigned int end = timer_get();
    uart_print_str("Init time elapsed in clock cycles: ");
    puthex(end-start);
    uart_print_str("Hello World.\n");

    /* Spin forever */
    while (1) {
        asm volatile("wfi");
    }
    return 0;
}
