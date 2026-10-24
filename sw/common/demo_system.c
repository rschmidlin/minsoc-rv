// SPDX-License-Identifier: Apache-2.0
//
// Derived in part from ibex-demo-system
//
// Copyright lowRISC contributors
// Copyright 2026 Raul Schmidlin

#include "demo_system.h"
#include "minsoc_rv_system_conf.h"
#include "uart.h"

int putchar(int c) {
  if (c == '\n') {
    uart_putc('\r');
  }

  uart_putc(c);

  return c;
}

int getchar(void) { return uart_getc(); }

int puts(const char* str) {
  while (*str) {
    putchar(*str++);
  }

  return 0;
}

void puthex(uint32_t h) {
  int cur_digit;
  // Iterate through h taking top 4 bits each time and outputting ASCII of hex
  // digit for those 4 bits
  for (int i = 0; i < 8; i++) {
    cur_digit = h >> 28;

    if (cur_digit < 10)
      putchar('0' + cur_digit);
    else
      putchar('A' - 10 + cur_digit);

    h <<= 4;
  }
}

uint32_t get_mepc(void) {
  uint32_t result;
  __asm__ volatile("csrr %0, mepc;" : "=r"(result));
  return result;
}

uint32_t get_mcause(void) {
  uint32_t result;
  __asm__ volatile("csrr %0, mcause;" : "=r"(result));
  return result;
}

uint32_t get_mtval(void) {
  uint32_t result;
  __asm__ volatile("csrr %0, mtval;" : "=r"(result));
  return result;
}

uint32_t get_mcycle(void) {
  uint32_t result;
  __asm__ volatile("csrr %0, mcycle;" : "=r"(result));
  return result;
}

void reset_mcycle(void) { __asm__ volatile("csrw mcycle, x0"); }


uint32_t get_lsu_stalls(void)
{
  uint32_t result;
  __asm__ volatile("csrr %0, 0xB03;" : "=r"(result));
  return result;
}

uint32_t get_fetch_stalls(void)
{
  uint32_t result;
  __asm__ volatile("csrr %0, 0xB04;" : "=r"(result));
  return result;
}

uint32_t get_instr_counts(void)
{
  uint32_t result;
  __asm__ volatile("csrr %0, minstret;" : "=r"(result));
  return result;  
}

extern uint32_t _vectors_start;
volatile uint32_t* exc_vectors = &_vectors_start;

int install_exception_handler(uint32_t vector_num, void (*handler_fn)(void)) {
  if (vector_num >= 32) return 1;

  volatile uint32_t* handler_jmp_loc = exc_vectors + vector_num;
  int32_t offset                     = (uint32_t)handler_fn - (uint32_t)handler_jmp_loc;

  if ((offset >= (1 << 19)) || (offset < -(1 << 19))) {
    return 2;
  }

  uint32_t offset_uimm = offset;

  uint32_t jmp_ins = ((offset_uimm & 0x7fe) << 20) |     // imm[10:1] -> 21
                     ((offset_uimm & 0x800) << 9) |      // imm[11] -> 20
                     (offset_uimm & 0xff000) |           // imm[19:12] -> 12
                     ((offset_uimm & 0x100000) << 11) |  // imm[20] -> 31
                     0x6f;                               // J opcode

  *handler_jmp_loc = jmp_ins;

  __asm__ volatile("fence.i;");

  return 0;
}

void enable_interrupts(uint32_t enable_mask) { asm volatile("csrs mie, %0\n" : : "r"(enable_mask)); }

void disable_interrupts(uint32_t disable_mask) { asm volatile("csrc mie, %0\n" : : "r"(disable_mask)); }

void set_global_interrupt_enable(uint32_t enable) {
  if (enable) {
    asm volatile("csrs mstatus, %0\n" : : "r"(1 << 3));
  } else {
    asm volatile("csrc mstatus, %0\n" : : "r"(1 << 3));
  }
}

static uint32_t elapsed_cycles, load_store_stalls, fetch_stalls, nr_of_instructions;

void start_perf_trace(void)
{
  elapsed_cycles = get_mcycle();
  load_store_stalls = get_lsu_stalls();
  fetch_stalls = get_fetch_stalls();
  nr_of_instructions = get_instr_counts();
}

void print_perf_trace(void)
{
  uint32_t cycle_diff, lsu_stalls_diff, fetch_stalls_diff, nr_of_instr_diff;
  cycle_diff = get_mcycle() - elapsed_cycles;
  lsu_stalls_diff = get_lsu_stalls() - load_store_stalls;
  fetch_stalls_diff = get_fetch_stalls() - fetch_stalls;
  nr_of_instr_diff = get_instr_counts() - nr_of_instructions;
  puts("Performance counters:\n");
  puts("  cycles:  0x");
  puthex(cycle_diff);
  puts("\n  LSU stalls:  0x");
  puthex(lsu_stalls_diff);
  puts("\n  fetch stalls:  0x");
  puthex(fetch_stalls_diff);
  puts("\n  Instructions:  0x");
  puthex(nr_of_instr_diff);
  putchar('\n');
}

void simple_exc_handler(void) {
  puts("EXCEPTION!!!\n");
  puts("============\n");
  puts("MEPC:   0x");
  puthex(get_mepc());
  puts("\nMCAUSE: 0x");
  puthex(get_mcause());
  puts("\nMTVAL:  0x");
  puthex(get_mtval());
  putchar('\n');

  while (1)
    ;
}
