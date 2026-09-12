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
    la   t0, a        # Adresse von a nach t0
    lw   t1, 0(t0)    # Wert von a nach t1

    la   t0, b
    lw   t2, 0(t0)    # Wert von b nach t2

    add  t3, t1, t2   # t3 = a + b

    la   t0, c
    sw   t3, 0(t0)    # Ergebnis nach c speichern

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

