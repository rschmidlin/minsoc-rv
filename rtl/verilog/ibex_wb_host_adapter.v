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

reg [31:0] req_addr_q;
reg req_we_q;
reg [3:0] req_be_q;
reg [31:0] req_wdata_q;
reg req_valid_q;


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

always @(posedge clk) begin
  if (rst) begin
    req_we_q <= 1'b0;
    req_be_q <= 4'h0;
    req_wdata_q <= 32'h0000_0000;
    req_addr_q <= 32'h0000_0000;
    req_valid_q <= 1'b0;
  end
  else begin
    if (fifo_wr_en) begin
      req_we_q <= req_we;
      req_be_q <= req_be;
      req_wdata_q <= req_wdata;
      req_addr_q <= req_addr;
      req_valid_q <= req_valid;
    end
  end
end

assign fifo_wr_en = req_valid & ~fifo_full;
assign gnt = fifo_wr_en/* & req_valid*/;


// Recognize fifo_empty one read cycle ahead
reg [31:0] fifo_req_addr_q, fifo_req_addr_qq;
reg fifo_req_we_q, fifo_req_we_qq;
reg [3:0] fifo_req_be_q, fifo_req_be_qq;
reg [31:0] fifo_req_wdata_q, fifo_req_wdata_qq;

always @(posedge clk) begin
  if (rst) begin
    fifo_req_we_q <= 1'b0;
    fifo_req_be_q <= 4'h0;
    fifo_req_wdata_q <= 32'h0000_0000;
    fifo_req_addr_q <= 32'h0000_0000;
    
    fifo_req_we_qq <= 1'b0;
    fifo_req_be_qq <= 4'h0;
    fifo_req_wdata_qq <= 32'h0000_0000;
    fifo_req_addr_qq <= 32'h0000_0000;
  end
  if (fifo_rd_en) begin
    fifo_req_we_q <= fifo_req_we;
    fifo_req_be_q <= fifo_req_be;
    fifo_req_wdata_q <= fifo_req_wdata;
    fifo_req_addr_q <= fifo_req_addr;    
    
    fifo_req_we_qq <= fifo_req_we_q;
    fifo_req_be_qq <= fifo_req_be_q;
    fifo_req_wdata_qq <= fifo_req_wdata_q;
    fifo_req_addr_qq <= fifo_req_addr_q;    
  end
end

wire burst_rw_consistent;
wire burst_be_consistent;
wire burst_addr_valid;
wire burst_valid;

assign burst_rw_consistent = (fifo_req_we == fifo_req_we_q);
assign burst_be_consistent = (fifo_req_be == fifo_req_be_q);
assign burst_addr_valid = (fifo_req_addr == (fifo_req_addr_q + 'd4));
assign burst_valid = (burst_addr_valid & burst_be_consistent & burst_rw_consistent);


reg fifo_rd_wb_ctrl;
reg fifo_wb_rd;
reg fifo_rd_en_direct;
assign fifo_rd_en = fifo_rd_wb_ctrl ? fifo_wb_rd : (wb_ack & burst_valid);
//assign fifo_rd_en = fifo_rd_en_direct;

reg [3:0] wb_state;

localparam IDLE = 4'b0000;
localparam FIFO_WAIT1 = 4'b0001;
localparam PREPARE1 = 4'b0010;
localparam FIFO_WAIT2 = 4'b0011;
localparam PREPARE2 = 4'b0100;
localparam CLASSICQ = 4'b0101;
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

    fifo_rd_wb_ctrl <= 1'b1;
    fifo_wb_rd <= 1'b0;
    fifo_rd_en_direct <= 1'b0;
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

        fifo_rd_wb_ctrl <= 1'b1;
        fifo_wb_rd <= 1'b0;
        resp_valid <= 1'b0;

        if (!fifo_empty) begin
          fifo_rd_en_direct <= 1'b1;
          fifo_wb_rd <= 1'b1;
          wb_state <= FIFO_WAIT1;
        end
      end
      FIFO_WAIT1: begin
        fifo_rd_en_direct <= 1'b0;
        fifo_wb_rd <= 1'b0;
        wb_state <= PREPARE1;
      end
      PREPARE1: begin        
        if (!fifo_empty && burst_valid) begin
          fifo_rd_en_direct <= 1'b1;
          fifo_wb_rd <= 1'b1;
          wb_state <= FIFO_WAIT2;
        end
        else begin
          fifo_rd_en_direct <= 1'b0;
          fifo_wb_rd <= 1'b0;
          wb_state <= CLASSICQ;
        end
      end
      FIFO_WAIT2: begin
        fifo_rd_en_direct <= 1'b0;
        fifo_wb_rd <= 1'b0;
        wb_state <= PREPARE2;
      end
      PREPARE2: begin
        fifo_rd_en_direct <= 1'b0;
        fifo_wb_rd <= 1'b0;

        wb_cyc <= 1'b1;
        wb_stb <= 1'b1;

        wb_cti <= 3'b010;
        wb_bte <= 2'b00;

        wb_we <= fifo_req_we_qq;
        wb_adr <= fifo_req_addr_qq;
        wb_dat_w <= fifo_req_wdata_qq;
        wb_sel <= fifo_req_be_qq;
        
        wb_state <= BURST;
      end
      BURST: begin
        fifo_rd_en_direct <= 1'b0;
        resp_valid <= 1'b0;
        fifo_rd_wb_ctrl <= 1'b0;
        if (wb_ack) begin
          fifo_rd_en_direct <= 1'b1;
          wb_adr <= wb_adr + 'd4;
          resp_rdata <= wb_dat_r;
          wb_dat_w <= fifo_req_wdata_q;
          resp_valid <= 1'b1;

          if (fifo_empty || !burst_valid) begin
            fifo_rd_wb_ctrl <= 1'b1;
            wb_cti <= 3'b111;
            wb_state <= FINISH;
          end
        end
      end
      CLASSICQ: begin
        fifo_rd_en_direct <= 1'b0;
        wb_cyc <= 1'b1;
        wb_stb <= 1'b1;
        wb_we <= fifo_req_we_q;
        wb_adr <= fifo_req_addr_q;
        wb_dat_w <= fifo_req_wdata_q;
        wb_sel <= fifo_req_be_q;
        if (wb_ack) begin
          fifo_rd_en_direct <= 1'b1;
          resp_rdata <= wb_dat_r;
          resp_valid <= 1'b1;

          wb_cyc <= 1'b0;
          wb_stb <= 1'b0;
          wb_state <= IDLE;
        end
      end
      FINISH: begin
        fifo_rd_en_direct <= 1'b0;
        resp_valid <= 1'b0;
        if (wb_ack /*&& wb_stb*/) begin
          fifo_rd_en_direct <= 1'b1;
          resp_valid <= 1'b1;
          
          resp_rdata <= wb_dat_r;
          wb_dat_w <= fifo_req_wdata_q;
          wb_adr <= 32'h0000_0000;

          //fifo_wb_rd <= 1'b1;

          wb_cyc <= 1'b0;
          wb_stb <= 1'b0;
          wb_cti <= 3'b000;
          wb_bte <= 2'b00;

          wb_state <= IDLE;
        end
      end
    endcase
  end
end


endmodule
