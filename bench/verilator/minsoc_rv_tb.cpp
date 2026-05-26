// SPDX-License-Identifier: GPL-2.0-or-later
//
// Derived from mor1kx/orpsoc Verilator testbench.
//
// Original authors:
//   Olof Kindgren <olof.kindgren@gmail.com>
//   Franck Jullien <franck.jullien@gmail.com>
//
// Modifications:
//   Copyright 2026 Raul Schmidlin
//   - Adapted for MinSoC-RV / Ibex
//   - UART RX/TX simulation
//   - Reset sequencing fixes
//   - Interactive UART handling

#include <iostream>
#include <stdint.h>
#include <signal.h>
#include <argp.h>
#include <verilator_tb_utils.h>

#include "Vminsoc_rv_top__Syms.h"

static bool done;

#define WIF_OPCODE 0x10500073UL

#define RESET_TIME		10

vluint64_t main_time = 0;       // Current simulation time
// This is a 64-bit integer to reduce wrap over issues and
// allow modulus.  You can also use a double, if you wish.

double sc_time_stamp () {       // Called by $time in Verilog
  return main_time;           // converts to double, to match
  // what SystemC does
}

void INThandler(int signal)
{
	printf("\nCaught ctrl-c\n");
	done = true;
}

static int parse_opt(int key, char *arg, struct argp_state *state)
{
	switch (key) {
	case ARGP_KEY_INIT:
		state->child_inputs[0] = state->input;
		break;
	// Add parsing of custom options here
	}

	return 0;
}

static int parse_args(int argc, char **argv, VerilatorTbUtils* tbUtils)
{
	struct argp_option options[] = {
		// Add custom options here
		{ 0 }
	};
	struct argp_child child_parsers[] = {
		{ &verilator_tb_utils_argp, 0, "", 0 },
		{ 0 }
	};
	struct argp argp = { options, parse_opt, 0, 0, child_parsers };

	return argp_parse(&argp, argc, argv, 0, 0, tbUtils);
}

#define UART_TX_WAIT (864)

int uart_decoder_step(Vminsoc_rv_top* top, VerilatorTbUtils* tbUtils)
{
    static unsigned int state = 0;
    static uint64_t start_timestamp = 0;
    static uint8_t byte = 0;
    static uint64_t bit_timestamp = 0;
    static uint8_t bitnr = 0;
    static bool new_bit_expected = false;
    uint64_t elapsed = 0;
    static bool tx_value = false;/*
    if (top->uart_stx_o != tx_value) {
        printf("UART: TX value changed to %d at time %lu\n", top->uart_stx_o, tbUtils->getTime());
        tx_value = top->uart_stx_o;
        printf("UART: State %u, bitnr %u\n", state, bitnr);
    }*/
    switch (state) {
        case 0: // Wait for restart
            if (top->uart_stx_o == 1) {
                bitnr = 0;
                byte = 0;
                state = 1;
            }
            break;
        case 1: // wait for start bit
            if (top->uart_stx_o == 0) {
                state = 2;
                start_timestamp = tbUtils->getTime();
            }
            break;
        case 2: // wait for data bit
            bit_timestamp = tbUtils->getTime();
            if (tbUtils->getTime() - start_timestamp >= (UART_TX_WAIT + (UART_TX_WAIT/2))) {
                new_bit_expected = true;
                state = 3;
            }
            break;
        case 3: // Read data bits
            elapsed = tbUtils->getTime() - bit_timestamp;
            if (new_bit_expected) {
                new_bit_expected = false;
                byte |= (top->uart_stx_o << bitnr);
                bitnr++;
            }
            if (elapsed >= UART_TX_WAIT) {
                bit_timestamp = tbUtils->getTime();
                if (bitnr >= 7) {
                    state = 4;
                } else {
                    new_bit_expected = true;
                    state = 3;
                }
            }
            break;
        case 4: // wait for stop bit to finish
            elapsed = tbUtils->getTime() - bit_timestamp;
            if ((elapsed >= UART_TX_WAIT) && (top->uart_stx_o == 1)) {
                printf("%c", byte);
                //printf("UART: Got byte 0x%02x ('%c') at time %lu\n", byte, byte, tbUtils->getTime());
                state = 0;
                return byte;
            }
            break;
        default:
            state = 0;
            break;
    }
    return -1;
}

int uart_transmit_step(Vminsoc_rv_top* top, VerilatorTbUtils* tbUtils)
{
    static unsigned int state = 0;
    static uint64_t start_timestamp = 0;
    static uint8_t byte = 'Y';
    static uint64_t bit_timestamp = 0;
    static uint8_t bitnr = 0;
    uint64_t elapsed = 0;
    static bool byte_sent = false;
    if (!byte_sent) {
        switch (state) {
            case 0: // Set start bit
                start_timestamp = tbUtils->getTime();
                top->uart_srx_i = 0;
                state = 1;
                break;
            case 1: // wait for start bit
                if (tbUtils->getTime() - start_timestamp >= (UART_TX_WAIT))
                {
                    bit_timestamp = tbUtils->getTime();
                    state = 2;
                }
                break;
            case 2: // Send data bits
                elapsed = tbUtils->getTime() - bit_timestamp;
                top->uart_srx_i = (byte >> bitnr) & 1;
                if (elapsed >= UART_TX_WAIT) {
                    bitnr++;
                    bit_timestamp = tbUtils->getTime();
                    if (bitnr >= 7) {
                        state = 3;
                    }
                }
                break;
            case 3: // wait for stop bit to finish
                elapsed = tbUtils->getTime() - bit_timestamp;
                top->uart_srx_i = 0;
                if (elapsed >= UART_TX_WAIT) {
                    state = 0;
                    top->uart_srx_i = 1;
                    byte_sent = true;
                }
                break;
            default:
                state = 0;
                break;
        }
    }
    return -1;
}

bool instruction_detect_wfi(Vminsoc_rv_top* top, VerilatorTbUtils* tbUtils)
{
    // WFI at 0xd2 and 0x14a are 2-byte aligned (RVC boundary) but not 4-byte aligned.
    // The Wishbone bus fetches 32-bit words at 4-byte aligned addresses, so the
    // word-aligned addresses containing these WFIs are 0xd0 and 0x148 respectively.
    // The opcode 0x10500073 is split across two fetches; the lower 16 bits (0x0073)
    // appear in dat_r[31:16] of the aligned fetch.

    if (top->minsoc_rv_top->ibexi_ack
        && ((top->minsoc_rv_top->ibexi_dat_r >> 16) == (WIF_OPCODE & 0xFFFF))) {
            return true;
    }

    return false;
}

int main(int argc, char **argv, char **env)
{
	uint32_t insn = 0;
	uint32_t ex_pc = 0;
    bool line_finished = false;
    bool send_character = false;

	Verilated::commandArgs(argc, argv);

	Vminsoc_rv_top* top = new Vminsoc_rv_top;
	VerilatorTbUtils* tbUtils =
		new VerilatorTbUtils(top->minsoc_rv_top->wb_ram_i->ram0->mem.data());

	parse_args(argc, argv, tbUtils);
	tbUtils->parsePlusArgs();

	signal(SIGINT, INThandler);

	top->wb_clk_i = 0;
	top->wb_rst_i = 0;
    top->uart_srx_i = 1;

	top->trace(tbUtils->tfp, 99);

	while (tbUtils->doCycle() && !done) {
		if (tbUtils->getTime() > RESET_TIME && tbUtils->getTime() < 2*RESET_TIME)
			top->wb_rst_i = 1;
        else if (tbUtils->getTime() >= 2*RESET_TIME) {
            top->wb_rst_i = 0;
        }

		top->eval();

		top->wb_clk_i = !top->wb_clk_i;

		tbUtils->doJTAG(&top->tms_pad_i, &top->tdi_pad_i, &top->tck_pad_i, top->tdo_pad_o);

        int byte = uart_decoder_step(top, tbUtils);

        if (send_character) {
            uart_transmit_step(top, tbUtils);    
            if (byte == 'Z' && !tbUtils->getJtagEnable()) {
                done = true;
            }
        }

        if (byte == 8) {
            send_character = true;
        }
	}

	printf("Simulation ended at PC = %08x (%lu)\n",
	       ex_pc, tbUtils->getTime());

	delete tbUtils;
	exit(0);
}

