// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 Raul Schmidlin

// The adapter supports at most two outstanding Ibex grants:
//   - one active Wishbone transfer
//   - one buffered next request 
//   - ideally, Ibex requests come every cycle while the previous 
//      request on Wishbone is transferred. The strategy is to 
//      use the fact that Ibex requests and bursts should transfer
//      data every cycle. 
//
// TODO: How to stop transaction if IB_FSM detects incontiguous address but Wishbone burst was started? 
//       At the moment, going directly to CTI 000 and negating CYC, normally CTI 111 and CYC 1 required
//       for one cycle. Potentially negate STB while going for CTI 111 and CYC? 

module ibex_wb_host_adapter #(
  parameter MAX_FIFO_DEPTH = 2)
  (
    input wire clk,
    input wire rst,

    // Request
    input wire        req_valid,
    input wire [31:0] req_addr,
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
    output reg [ 1:0] wb_bte
);

wire fifo_wr_en;
wire fifo_rd_en;
wire fifo_full, fifo_empty;
wire fifo_req_we;
wire [3:0] fifo_req_be;
wire [31:0] fifo_req_wdata;
wire [31:0] fifo_req_addr;


// Store req_addr & req_be 
fifo_fwft #(
    .DEPTH_WIDTH(MAX_FIFO_DEPTH),
    .DATA_WIDTH(69)
  ) fifo_i(
    .clk(clk),
    .rst(rst),
    .din({req_we, req_be, req_wdata, req_addr}),
    .wr_en(fifo_wr_en),
    .dout({fifo_req_we, fifo_req_be, fifo_req_wdata, fifo_req_addr}),
    .rd_en(fifo_rd_en),
    .full(fifo_full),
    .empty(fifo_empty)
);

assign fifo_wr_en = req_valid & ~fifo_full;
assign gnt = fifo_wr_en;

wire slot0_valid;
wire slot1_valid;
reg slot1_req, slot2_req, preload_buffer_pop;

wire [31:0] slot0_addr, slot1_addr, slot2_addr;
wire slot0_we, slot1_we, slot2_we;
wire [3:0] slot0_be, slot1_be, slot2_be;
wire [31:0] slot0_wdata, slot1_wdata, slot2_wdata;

ibex_wb_adapter_preload_buffer #(
  .DATA_WIDTH(69)
) ibex_wb_adapter_preload_buffer_i(
  .clk(clk),
  .rst(rst),

  .fifo_dout({fifo_req_we, fifo_req_be, fifo_req_wdata, fifo_req_addr}),
  .fifo_empty(fifo_empty),
  .rd_en(fifo_rd_en),

  .slot0_valid(slot0_valid),
  .slot0_data({slot0_we, slot0_be, slot0_wdata, slot0_addr}),
  .slot0_pop(preload_buffer_pop),

  .slot1_valid(slot1_valid),
  .slot1_data({slot1_we, slot1_be, slot1_wdata, slot1_addr}),
  
  .slot2_valid(slot2_valid),
  .slot2_data({slot2_we, slot2_be, slot2_wdata, slot2_addr})
);

wire burst_rw_consistent;
wire burst_be_consistent;
wire burst_addr_valid;

wire slots_valid;
wire burst_valid;

assign burst_rw_consistent = (slot1_we == slot0_we);
assign burst_be_consistent = (slot1_be == slot0_be);
assign burst_addr_valid = (slot1_addr == (slot0_addr + 'd4));

assign slots_valid = (slot0_valid & slot1_valid);

wire fifo_forward;
assign fifo_forward = /*fifo_rd_en & */preload_buffer_pop & ~slot2_valid;
assign burst_break_fifo_forward = fifo_forward & fifo_empty;

assign burst_valid = (slots_valid & burst_addr_valid & burst_be_consistent & burst_rw_consistent);

wire burst_rw_consistent_q;
wire burst_be_consistent_q;
wire burst_addr_valid_q;

wire slots_valid_q;
wire burst_valid_q;

assign burst_rw_consistent_q = (slot2_we == slot1_we);
assign burst_be_consistent_q = (slot2_be == slot1_be);
assign burst_addr_valid_q = (slot2_addr == (slot1_addr + 'd4));

assign burst_valid_q = burst_addr_valid_q & burst_be_consistent_q & burst_rw_consistent_q;

reg [3:0] wb_state;

localparam IDLE = 4'b0000;
localparam PREPARE1 = 4'b0010;
localparam CLASSIC = 4'b0101;
localparam BURST = 4'b0110;
localparam FINISH = 4'b0111;

reg [31:0] wb_adr_q;

always @(posedge clk) begin
  if (rst) begin
    wb_cyc <= 1'b0;
    wb_stb <= 1'b0;
    wb_we <= 1'b0;
    wb_adr <= 32'h0000_0000;
    wb_dat_w <= 32'h0000_0000;
    wb_sel <= 4'h0;
    wb_cti <= 3'b000;
    wb_bte <= 2'b00;

    wb_state <= IDLE;

    resp_rdata <= 32'h0000_0000;
    resp_valid <= 1'b0;

    preload_buffer_pop <= 1'b0;
  end
  else begin
    case (wb_state)
      IDLE: begin
        wb_cyc <= 1'b0;
        wb_stb <= 1'b0;
        wb_we <= 1'b0;
        wb_adr <= 32'h0000_0000;
        wb_dat_w <= 32'h0000_0000;
        wb_sel <= 4'h0;
        wb_cti <= 3'b000;
        wb_bte <= 2'b00;
    
        preload_buffer_pop <= 1'b0;

        resp_valid <= 1'b0;

        if (slot0_valid && !preload_buffer_pop) begin
          wb_state <= PREPARE1;
        end
      end
      PREPARE1: begin        
        preload_buffer_pop <= 1'b1;
        wb_we <= slot0_we;
        wb_adr <= slot0_addr;
        wb_dat_w <= slot0_wdata;
        wb_sel <= slot0_be;

        if (slot1_valid && burst_valid) begin
          wb_state <= BURST;
        end
        else begin
          wb_state <= CLASSIC;
        end
      end
      CLASSIC: begin
        wb_cyc <= 1'b1;
        wb_stb <= 1'b1;

        preload_buffer_pop <= 1'b0;
        if (wb_ack) begin
          resp_rdata <= wb_dat_r;
          resp_valid <= 1'b1;

          wb_cyc <= 1'b0;
          wb_stb <= 1'b0;

          wb_state <= IDLE;
        end
      end
      BURST: begin
        resp_valid <= 1'b0;

        wb_cyc <= 1'b1;
        wb_stb <= 1'b1;

        wb_cti <= 3'b010;
        wb_bte <= 2'b00;
        
        preload_buffer_pop <= 1'b0;

        if (wb_ack) begin
          wb_adr <= wb_adr + 'd4;
          resp_rdata <= wb_dat_r;
          // resp_valid signals whether we got an ack previosly and consequently have popped the buffer
          wb_dat_w <= (resp_valid) ? slot1_wdata : slot0_wdata;
          resp_valid <= 1'b1;

          preload_buffer_pop <= 1'b1;

          if ((!slot2_valid && !fifo_empty) || !burst_valid_q) begin
            wb_cti <= 3'b111;
            preload_buffer_pop <= 1'b1;
            wb_dat_w <= resp_valid ? slot1_wdata : slot0_wdata;
            wb_state <= FINISH;
          end
        end
      end
      FINISH: begin
        resp_valid <= 1'b0;
        
        preload_buffer_pop <= 1'b0;
        
        if (wb_ack) begin
          resp_valid <= 1'b1;
          
          resp_rdata <= wb_dat_r;
          wb_adr <= 32'h0000_0000;

          wb_cyc <= 1'b0;
          wb_stb <= 1'b0;
          wb_cti <= 3'b000;
          wb_bte <= 2'b00;

          //preload_buffer_pop <= 1'b1;

          wb_state <= IDLE;
        end
      end
    endcase
  end
end


endmodule
