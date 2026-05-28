// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 Raul Schmidlin

module ibex_wb_host_adapter (
    input wire clk,
    input wire rst,

    // Request
    input wire        req_valid,
    input wire [31:0] req_addr,
    input wire [ 3:0] req_len,    // up to 16 beats
    input wire        req_we,
    input wire [31:0] req_wdata,
    input wire [ 3:0] req_be,

    output reg busy,

    // Response
    output reg        resp_valid,
    output reg [31:0] resp_rdata,

    // Wishbone B4
    output reg         wb_cyc,
    output reg         wb_stb,
    output reg         wb_we,
    output reg  [31:0] wb_adr,
    output reg  [31:0] wb_dat_w,
    input  wire        wb_ack,
    input  wire [31:0] wb_dat_r,
    output reg  [ 3:0] wb_sel,
    output reg  [ 2:0] wb_cti,   // Cycle Type Identifier
    output wire [ 1:0] wb_bte    // Burst Type Extension (always linear)
);

  localparam CTI_CLASSIC = 3'b000;  // Classic single cycle
  localparam CTI_INCR    = 3'b010;  // Incrementing burst
  localparam CTI_EOB     = 3'b111;  // End of burst

  assign wb_bte = 2'b00;  // Linear burst, always

  reg [ 3:0] beat_num;   // current beat being presented, 1-indexed
  reg [ 3:0] req_len_r;  // request length captured at start of transaction
  reg [31:0] addr;

  reg [ 1:0] state;

  localparam IDLE = 2'h0;
  localparam RUN  = 2'h1;
  localparam DONE = 2'h2;

  always @(posedge clk) begin
    if (rst) begin
      state  <= IDLE;
      wb_cyc <= 0;
      wb_stb <= 0;
      wb_sel <= 4'h0;
      wb_cti <= CTI_CLASSIC;
      busy   <= 0;
    end else begin
      resp_valid <= 0;

      case (state)
        IDLE: begin
          if (req_valid) begin
            busy      <= 1;
            wb_cyc    <= 1;
            wb_stb    <= 1;
            wb_we     <= req_we;
            addr      <= req_addr;
            wb_adr    <= req_addr;
            wb_dat_w  <= req_wdata;
            req_len_r <= req_len;
            beat_num  <= 1;
            wb_sel    <= req_be;
            wb_cti    <= (req_len == 1) ? CTI_CLASSIC : CTI_INCR;
            state     <= RUN;
          end
        end

        RUN: begin
          if (wb_ack) begin
            resp_rdata <= wb_dat_r;
            resp_valid <= 1;

            if (beat_num == req_len_r) begin
              wb_cyc <= 0;
              wb_stb <= 0;
              state  <= DONE;
            end else begin
              beat_num <= beat_num + 1;
              addr     <= addr + 4;
              wb_adr   <= addr + 4;
              wb_stb   <= 1;
              wb_cti   <= (beat_num + 1 == req_len_r) ? CTI_EOB : CTI_INCR;
            end
          end
        end

        DONE: begin
          busy  <= 0;
          state <= IDLE;
        end
        default: begin
          state  <= IDLE;
          wb_cyc <= 0;
          wb_stb <= 0;
          wb_sel <= 4'h0;
          wb_cti <= CTI_CLASSIC;
          busy   <= 0;
        end
      endcase
    end
  end

endmodule
