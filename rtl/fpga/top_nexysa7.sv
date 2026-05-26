// SPDX-License-Identifier: Apache-2.0
//
// Derived in part from ibex-demo-system
//
// Copyright lowRISC contributors
// Copyright 2026 Raul Schmidlin

module top_nexysa7 #(
    parameter memfile = ""
) (
    // These inputs are defined in data/pins_nexysa7.xdc
    input         IO_CLK,
    input         IO_RST,
    input  [15:0] SW,
    input  [ 3:0] BTN,
    output [15:0] LED,
    output [ 5:0] RGB_LED,
    input         UART_RX,
    output        UART_TX
);

  logic clk_sys, rst_sys_n;

  // Instantiating the Ibex Demo System.
  minsoc_rv_top #(
      .memfile(memfile)
  ) u_minsoc_rv_top (
      .wb_clk_i  (clk_sys),
      .wb_rst_i  (~rst_sys_n),
      .tdo_pad_o (),
      .tms_pad_i (1'b0),
      .tck_pad_i (1'b0),
      .tdi_pad_i (1'b0),
      .uart_srx_i(UART_RX),
      .uart_stx_o(UART_TX)
  );

  logic IO_RST_N;
  assign IO_RST_N = ~IO_RST;

  // Generating the system clock and reset for the FPGA.
  // Nexys A7 has a 100 MHz clock.
  clkgen_xil7series clkgen (
      .IO_CLK,
      .IO_RST_N,
      .clk_sys,
      .rst_sys_n
  );

endmodule
