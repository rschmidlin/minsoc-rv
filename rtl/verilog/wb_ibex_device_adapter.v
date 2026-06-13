// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 Raul Schmidlin

// Wishbone B4 Registered-Feedback slave adapter.
// Converts incoming WB transactions (including bursts) to the
// internal req/resp protocol used by ibex-style memory modules.
// Processes one req/resp at a time; burst beats are serialised.

module wb_ibex_device_adapter (
    input wire clk,
    input wire rst,

    // Wishbone B4 Slave
    input  wire        wb_cyc,
    input  wire        wb_stb,
    input  wire        wb_we,
    input  wire [31:0] wb_adr,
    input  wire [31:0] wb_dat_w,
    input  wire [ 3:0] wb_sel,
    input  wire [ 2:0] wb_cti,
    input  wire [ 1:0] wb_bte,
    output reg         wb_ack,
    output reg  [31:0] wb_dat_r,

    // Request
    output reg         req_valid,
    output reg  [31:0] req_addr,
    output wire        req_we,
    output wire [31:0] req_wdata,
    output wire [ 3:0] req_be,

    // Response
    input wire  [31:0] resp_rdata
);

wire wb_valid = wb_cyc & wb_stb;
wire wb_last  = (wb_cti == 3'b000) || (wb_cti == 3'b111);

reg wb_valid_q;
reg [31:0] adr_q;

wire new_cycle = wb_valid & !wb_valid_q;
reg new_cycle_q;
wire [31:0] next_adr = adr_q + 32'd4;
wire [31:0] calc_addr = new_cycle ? wb_adr : next_adr;

always @(posedge clk) begin
  if (rst) begin
    wb_valid_q   <= 1'b0;
    wb_ack     <= 1'b0;
    req_valid <= 1'b0;
    adr_q        <= 32'h0;
    new_cycle_q <= 1'b0;
  end
  else begin
    wb_valid_q <= wb_valid;
    new_cycle_q <= new_cycle;

    wb_ack <= 1'b0;
    req_valid <= 1'b0;

    if (wb_valid & !req_valid) begin
      adr_q <= calc_addr;

      req_addr  <= calc_addr;
      req_we    <= wb_we;
      req_be    <= wb_sel;
      req_wdata <= wb_dat_w;
      req_valid <= 1'b1;
    end
    else if (wb_valid & !req_valid) begin
      req_valid <= 1'b0;
    end

    // one-cycle delayed completion
    wb_ack <= req_valid;
  end
end

assign wb_dat_r = resp_rdata;



endmodule
