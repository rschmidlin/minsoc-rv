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

    output wire gnt,              // Combinatorial grant: high while collecting sequential requests

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
    output reg  [ 2:0] wb_cti,
    output wire [ 1:0] wb_bte
);

  localparam CTI_CLASSIC = 3'b000;
  localparam CTI_INCR    = 3'b010;
  localparam CTI_EOB     = 3'b111;

  assign wb_bte = 2'b00;

  // SM1: Grant Accumulator
  localparam GACC_IDLE    = 2'h0;
  localparam GACC_COLLECT = 2'h1;
  localparam GACC_WAIT    = 2'h2;

  // SM2: Wishbone Burst
  localparam WB_IDLE = 2'h0;
  localparam WB_RUN  = 2'h1;
  localparam WB_DONE = 2'h2;

  reg [1:0] gacc_state;
  reg [1:0] wb_state;

  // SM1 captured request parameters
  reg [31:0] start_addr;
  reg [ 3:0] req_len_r;
  reg        req_we_r;
  reg [31:0] req_wdata_r;
  reg [ 3:0] req_be_r;
  reg [ 3:0] grant_count;   // grants accepted so far in current accumulation

  // SM2 burst parameters (set by SM1 at trigger)
  reg [ 3:0] burst_len;
  reg [ 3:0] beat_num;

  // SM1→SM2 one-cycle trigger pulse
  reg wb_trigger;

  // Next expected address: start_addr + grant_count * 4
  wire addr_sequential = (req_addr == start_addr + {grant_count, 2'b00});

  // Grant is combinatorial: accept in IDLE for any req, or in COLLECT for next sequential req
  assign gnt = req_valid &&
               (gacc_state == GACC_IDLE ||
                (gacc_state == GACC_COLLECT && addr_sequential));

  // SM1: Grant Accumulator — collects req_len sequential requests before triggering WB burst
  always @(posedge clk) begin
    if (rst) begin
      gacc_state  <= GACC_IDLE;
      grant_count <= 4'h0;
      wb_trigger  <= 1'b0;
    end else begin
      wb_trigger <= 1'b0;

      case (gacc_state)
        GACC_IDLE: begin
          if (req_valid) begin
            start_addr  <= req_addr;
            req_len_r   <= req_len;
            req_we_r    <= req_we;
            req_wdata_r <= req_wdata;
            req_be_r    <= req_be;
            grant_count <= 4'h1;
            if (req_len == 4'h1) begin
              burst_len  <= 4'h1;
              wb_trigger <= 1'b1;
              gacc_state <= GACC_WAIT;
            end else begin
              gacc_state <= GACC_COLLECT;
            end
          end
        end

        GACC_COLLECT: begin
          if (req_valid && addr_sequential) begin
            grant_count <= grant_count + 4'h1;
            if (grant_count + 4'h1 == req_len_r) begin
              // All expected grants collected: trigger burst
              burst_len  <= grant_count + 4'h1;
              wb_trigger <= 1'b1;
              gacc_state <= GACC_WAIT;
            end
          end else if (req_valid) begin
            // Address break: trigger burst with grants accumulated so far
            burst_len  <= grant_count;
            wb_trigger <= 1'b1;
            gacc_state <= GACC_WAIT;
          end
        end

        GACC_WAIT: begin
          if (wb_state == WB_DONE) begin
            gacc_state <= GACC_IDLE;
          end
        end

        default: begin
          gacc_state <= GACC_IDLE;
        end
      endcase
    end
  end

  // SM2: Wishbone Burst — fires after SM1 has accumulated all grants
  always @(posedge clk) begin
    if (rst) begin
      wb_state <= WB_IDLE;
      wb_cyc   <= 1'b0;
      wb_stb   <= 1'b0;
      wb_sel   <= 4'h0;
      wb_cti   <= CTI_CLASSIC;
    end else begin
      resp_valid <= 1'b0;

      case (wb_state)
        WB_IDLE: begin
          if (wb_trigger) begin
            wb_cyc   <= 1'b1;
            wb_stb   <= 1'b1;
            wb_we    <= req_we_r;
            wb_adr   <= start_addr;
            wb_dat_w <= req_wdata_r;
            wb_sel   <= req_be_r;
            wb_cti   <= (burst_len == 4'h1) ? CTI_CLASSIC : CTI_INCR;
            beat_num <= 4'h1;
            wb_state <= WB_RUN;
          end
        end

        WB_RUN: begin
          if (wb_ack) begin
            resp_rdata <= wb_dat_r;
            resp_valid <= 1'b1;

            if (beat_num == burst_len) begin
              wb_cyc   <= 1'b0;
              wb_stb   <= 1'b0;
              wb_state <= WB_DONE;
            end else begin
              beat_num <= beat_num + 4'h1;
              wb_adr   <= start_addr + {beat_num, 2'b00};
              wb_cti   <= (beat_num + 4'h1 == burst_len) ? CTI_EOB : CTI_INCR;
            end
          end
        end

        WB_DONE: begin
          wb_state <= WB_IDLE;
        end

        default: begin
          wb_state <= WB_IDLE;
          wb_cyc   <= 1'b0;
          wb_stb   <= 1'b0;
          wb_sel   <= 4'h0;
          wb_cti   <= CTI_CLASSIC;
        end
      endcase
    end
  end

endmodule
