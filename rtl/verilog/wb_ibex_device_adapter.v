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
    output wire [ 3:0] req_len,
    output wire        req_we,
    output wire [31:0] req_wdata,
    output wire [ 3:0] req_be,

    // Response
    input wire         resp_valid,
    input wire  [31:0] resp_rdata
);

  localparam CTI_INCR = 3'b010;

  assign req_len   = 4'h1;
  assign req_we    = wb_we;
  assign req_wdata = wb_dat_w;
  assign req_be    = wb_sel;

  localparam IDLE = 1'b0;
  localparam WAIT = 1'b1;

  reg       state;
  reg [31:0] burst_addr;

  always @(posedge clk) begin
    if (rst) begin
      state     <= IDLE;
      wb_ack    <= 0;
      req_valid <= 0;
    end else begin
      wb_ack    <= 0;
      req_valid <= 0;

      case (state)
        IDLE: begin
          if (wb_cyc & wb_stb) begin
            req_valid  <= 1;
            req_addr   <= wb_adr;
            burst_addr <= wb_adr + 4;
            state      <= WAIT;
          end
        end

        WAIT: begin
          if (resp_valid) begin
            wb_ack   <= 1;
            wb_dat_r <= resp_rdata;

            // Continue burst when master keeps STB asserted with CTI=010
            if (wb_cti == CTI_INCR && wb_cyc && wb_stb) begin
              req_valid  <= 1;
              req_addr   <= burst_addr;
              burst_addr <= burst_addr + 4;
              // stay in WAIT for next beat
            end else begin
              state <= IDLE;
            end
          end
        end

        default: state <= IDLE;
      endcase
    end
  end

endmodule
