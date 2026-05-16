/* Linker script for minsoc-rv (PicoRV32)
 *
 * Memory map from minsoc-rv.core:
 *   mem:  0x00000080, size 0x000010000 (64 KB)
 *   uart: 0x90000000, size 8
 */

MEMORY {
    /* Reserve 32k for stack at the top */
    ram : ORIGIN = 0x00000080, LENGTH = 0x00008000
}

SECTIONS {
    .text : {
        *(.text.start)   /* Reset vector / startup code first */
        *(.text .text.*)
    } > ram

    .rodata : {
        *(.rodata .rodata.*)
    } > ram

    .data : {
        *(.data .data.*)
    } > ram

    .bss : {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        __bss_end = .;
    } > ram

    _stack_top = 0x02000000;
}
