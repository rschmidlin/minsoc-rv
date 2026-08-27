.section .text
.global eins_und_eins_assembler
.global uart_interrupt2

eins_und_eins_assembler:
    wfi
    j eins_und_eins_assembler

uart_interrupt2:  
    wfi
    j uart_interrupt2
