#include "demo_system.h"
#include "minsoc_rv_system_conf.h"
#include "uart.h"

int eins_und_eins_assembler(int a, int b);
void uart_interrupt2(void);

int main(int argc, char ** argv) {
    uart_init(UART0_BASE);
    install_exception_handler(UART_IRQ_NUM, &uart_interrupt2);
    enable_interrupts(UART_IRQ);
    set_global_interrupt_enable(1);

    int a = 1, b = 1;
    int c = eins_und_eins_assembler(a, b);

    uart_putc(8); // trigger simulation to send back a character
}
