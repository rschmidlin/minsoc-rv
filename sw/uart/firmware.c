/*
 * UART "Hello World" firmware for minsoc-rv (PicoRV32)
 *
 * Single-file bare-metal example: startup code + UART driver + main.
 * No interrupt handling. Mimics minsoc/sw/uart but for RISC-V.
 *
 * UART base address from minsoc-rv.core: 0x90000000
 */

/* ------------------------------------------------------------------ */
/* Startup code (must be placed at address 0x00000000)                */
/* ------------------------------------------------------------------ */
__attribute__((section(".text.start"), naked))
void _start(void)
{
    __asm__ volatile (
        ".option push          \n"
        ".option norelax       \n"
        "la     sp, _stack_top \n"  /* set stack pointer              */
        ".option pop           \n"
        "la     t0, __bss_start\n"  /* zero BSS                      */
        "la     t1, __bss_end  \n"
        "1:                    \n"
        "bge    t0, t1, 2f     \n"
        "sw     zero, 0(t0)    \n"
        "addi   t0, t0, 4      \n"
        "j      1b             \n"
        "2:                    \n"
        "jal    ra, main       \n"  /* call main()                    */
        "3:                    \n"
        "j      3b             \n"  /* loop forever                   */
    );
}

/* ------------------------------------------------------------------ */
/* UART 16550 register definitions (word-addressed, 4-byte spacing)   */
/*                                                                    */
/* PicoRV32 word-aligns all bus addresses and sets sel=0 on reads,    */
/* so UART registers are mapped at 4-byte intervals.  Firmware uses   */
/* 32-bit word accesses; only the low byte carries data.              */
/* ------------------------------------------------------------------ */
#define UART_BASE  0x90000000

#define REG32(addr) (*(volatile unsigned int *)(addr))

#define UART_TX    0x00   /* Transmit buffer  (DLAB=0, write)  */
#define UART_RX    0x00   /* Receive  buffer  (DLAB=0, read)   */
#define UART_DLL   0x00   /* Divisor Latch Low  (DLAB=1)       */
#define UART_DLM   0x04   /* Divisor Latch High (DLAB=1)       */
#define UART_IER   0x04   /* Interrupt Enable Register         */
#define UART_FCR   0x08   /* FIFO Control Register (write)     */
#define UART_LCR   0x0C   /* Line Control Register             */
#define UART_LSR   0x14   /* Line Status Register              */

/* FCR bits */
#define UART_FCR_ENABLE_FIFO  0x01
#define UART_FCR_CLEAR_RCVR   0x02
#define UART_FCR_CLEAR_XMIT   0x04
#define UART_FCR_TRIGGER_1    0x00

/* LCR bits */
#define UART_LCR_DLAB    0x80
#define UART_LCR_WLEN8   0x03
#define UART_LCR_STOP    0x04
#define UART_LCR_PARITY  0x08

/* LSR bits */
#define UART_LSR_TEMT  0x40   /* Transmitter empty          */
#define UART_LSR_THRE  0x20   /* Transmit-hold-reg empty    */

#define BOTH_EMPTY (UART_LSR_TEMT | UART_LSR_THRE)

/*
 * System clock for baud-rate divisor.
 * The testbench uses a 100 MHz clock (period 10 ns).
 * With SIM=1 the UART IP divides by 1, so this value is
 * mostly symbolic; the monitor samples at the configured rate.
 */
#define SYS_CLK       100000000
#define UART_BAUDRATE 115200

/* ------------------------------------------------------------------ */
/* UART driver                                                        */
/* ------------------------------------------------------------------ */

#define WAIT_FOR_THRE \
    do { lsr = REG32(UART_BASE + UART_LSR); } while ((lsr & UART_LSR_THRE) != UART_LSR_THRE)

#define WAIT_FOR_XMITR \
    do { lsr = REG32(UART_BASE + UART_LSR); } while ((lsr & BOTH_EMPTY) != BOTH_EMPTY)

static void uart_init(void)
{
    unsigned int divisor;

    /* Reset & enable FIFOs */
    REG32(UART_BASE + UART_FCR) = UART_FCR_ENABLE_FIFO
                                 | UART_FCR_CLEAR_RCVR
                                 | UART_FCR_CLEAR_XMIT
                                 | UART_FCR_TRIGGER_1;

    /* No interrupts */
    REG32(UART_BASE + UART_IER) = 0x00;

    /* 8N1 */
    REG32(UART_BASE + UART_LCR) = UART_LCR_WLEN8
                                 & ~(UART_LCR_STOP | UART_LCR_PARITY);

    /* Set baud rate using read-modify-write on LCR for DLAB */
    divisor = SYS_CLK / (16 * UART_BAUDRATE);
    REG32(UART_BASE + UART_LCR) |= UART_LCR_DLAB;
    REG32(UART_BASE + UART_DLM)  = (divisor >> 8) & 0xFF;
    REG32(UART_BASE + UART_DLL)  = divisor & 0xFF;
    REG32(UART_BASE + UART_LCR) &= ~UART_LCR_DLAB;
}

static void uart_putc(char c)
{
    unsigned int lsr;
    WAIT_FOR_THRE;
    REG32(UART_BASE + UART_TX) = c;
    WAIT_FOR_XMITR;
}

static void uart_print_str(const char *s)
{
    while (*s)
        uart_putc(*s++);
}

/* ------------------------------------------------------------------ */
/* main                                                               */
/* ------------------------------------------------------------------ */
int main(void)
{
    uart_init();
    uart_print_str("Hello World.");
    uart_putc('\n');

    /* Spin forever */
    while (1)
        ;
    return 0;
}
