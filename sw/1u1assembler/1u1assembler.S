.section .data
a:
    .word 1
b:
    .word 1
c:
    .word 0

.section .text
.global _start

_start:
    j sleep_loop
    

/* end of execution */
sleep_loop:
    wfi
    j sleep_loop

/* =================================================== [ exceptions ] === */
/* This section has to be down here, since we have to disable rvc for it  */

  .section .vectors, "ax"

  // reset vector
  .org 0x80
  jal x0, _start

