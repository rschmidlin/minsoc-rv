// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 Raul Schmidlin

#ifndef MINSOC_RV_SYSTEM_CONF
#define MINSOC_RV_SYSTEM_CONF

#define SYSCLK_FREQ 50000000

#define STACK_SIZE	0x01000

#define UART0_BASE 0x10000000
#define UART_IRQ_NUM 16
#define UART_IRQ (1 << UART_IRQ_NUM)
#define UART_BAUD_RATE 	115200

#define TIMER_BASE_ADDR (0x10001000UL)
#define TIMER_IRQ (1 << 7)


#endif
