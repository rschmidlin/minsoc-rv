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
    input wire [ 3:0] req_len,    // up to 16 beats
    input wire        req_we,
    input wire [31:0] req_wdata,
    input wire [ 3:0] req_be,

    output reg gnt,              // Combinatorial grant: high while collecting sequential requests

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

wire last_beat;
reg fifo_wr_en;
reg fifo_rd_en;
wire fifo_full, fifo_empty;
reg fifo_last_beat;
reg fifo_req_we;
reg [3:0] fifo_req_be;
reg [31:0] fifo_req_wdata;
reg [31:0] fifo_req_addr;

// Store req_addr & req_be 
fifo_fwft #(
    .DEPTH_WIDTH(MAX_FIFO_DEPTH),
    .DATA_WIDTH(70)
  ) fifo_i(
    .clk(clk),
    .rst(rst),
    .din({last_beat, req_we, req_be, req_wdata, req_addr}),
    .wr_en(fifo_wr_en),
    .dout({fifo_last_beat, fifo_req_we, fifo_req_be, fifo_req_wdata, fifo_req_addr}),
    .rd_en(fifo_rd_en),
    .full(fifo_full),
    .empty(fifo_empty)
);

reg [31:0] req_addr_q;
reg req_we_q;
reg [3:0] req_be_q;
reg [31:0] reg_wdata_q;

wire [31:0] next_address;
wire valid_req_address;

assign next_address = req_addr_q + 'd4;
assign valid_req_address = (req_addr == next_address);
assign last_beat = ~gnt & ((req_we ^ req_we_q) | (req_be ^ req_be_q) | !valid_req_address);

localparam IDLE = 2'b00;
localparam ACCEPT = 2'b01;
localparam STALL = 2'b10;

reg [1:0] ib_state;
reg [1:0] wb_state;

// Assert GNT with 2 cycles delay of request if not forbidden by transaction FSM
always @(posedge clk) begin
  if (rst) begin
    ib_state <= IDLE;
    gnt <= 1'b0;
    fifo_wr_en <= 1'b0;
  end
  else begin
    case (ib_state)
      IDLE: begin
        fifo_wr_en <= 1'b0;
        gnt <= 1'b0;
        if (req_valid) begin
          ib_state <= ACCEPT;
        end
      end
      ACCEPT: begin
        fifo_wr_en <= 1'b0;
        gnt <= 1'b0;
        if (fifo_full) begin
          ib_state <= STALL;        // needed for write data otherwise we lose the data in the WB_FSM
        end
        else if (req_valid && !fifo_wr_en && 
          (fifo_empty || (req_addr == (req_addr_q + 'h4)))) begin
          fifo_wr_en <= 1'b1;
          gnt <= 1'b1;
          req_addr_q <= req_addr;
          req_we_q <= req_we;
          req_be_q <= req_be;
          //reg_wdata_q <= reg_wdata;
        end
        else if (!gnt) begin  // after gnt is cleared new address is there, STALL if no request or address
            ib_state <= STALL;
        end
      end
      STALL: begin
        fifo_wr_en <= 1'b0;
        if (!req_valid) begin
          ib_state <= IDLE;
        end
        else if (!fifo_full) begin
          ib_state <= ACCEPT;
        end
      end
    endcase
  end
end

localparam PREPARE = 2'b01;
localparam ACTIVE = 2'b10;
localparam FINISH = 2'b11;

reg [31:0] fifo_req_addr_q;
reg fifo_req_we_q;
reg [3:0] fifo_req_be_q;
reg [31:0] fifo_reg_wdata_q;

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
    fifo_rd_en <= 1'b0;
  end
  else begin
    resp_valid <= 1'b0;  // default every cycle
    case (wb_state)
      IDLE: begin
        fifo_rd_en <= 1'b0;
        resp_valid <= 1'b0;
        wb_cyc <= 1'b0;
        wb_stb <= 1'b0;
        wb_we <= 1'b0;
        wb_adr <= 32'h0000_0000;
        wb_dat_w <= 32'h0000_0000;
        wb_sel <= 4'h0;
        wb_cti <= 3'b000;
        wb_bte <= 2'b00;

        if (!fifo_empty) begin
          fifo_rd_en <= 1'b1;
          fifo_req_we_q <= fifo_req_we;
          fifo_req_be_q <= fifo_req_be;
          fifo_reg_wdata_q <= fifo_req_wdata;
          fifo_req_addr_q <= fifo_req_addr;
          wb_state <= PREPARE;
        end
      end
      PREPARE: begin        
        fifo_rd_en <= 1'b0;
        
        fifo_req_we_q <= fifo_req_we;
        fifo_req_be_q <= fifo_req_be;
        fifo_reg_wdata_q <= fifo_req_wdata;
        fifo_req_addr_q <= fifo_req_addr;

        wb_cyc <= 1'b1;
        wb_stb <= 1'b1;
        wb_we <= fifo_req_we_q;
        wb_adr <= fifo_req_addr_q;
        wb_dat_w <= fifo_reg_wdata_q;
        wb_sel <= fifo_req_be_q;
        if (!fifo_last_beat && !fifo_req_we_q) begin
          wb_cti <= 3'b010;
          wb_bte <= 2'b00;
        end
        wb_state <= ACTIVE;
      end
      ACTIVE: begin
        fifo_rd_en <= 1'b0;

        if (wb_ack) begin
          resp_rdata <= wb_dat_r;
          resp_valid <= 1'b1;
          wb_dat_w <= fifo_reg_wdata_q;

          // If only one req was accepted or ib_fsm stopped, interrupt operation
          if (fifo_empty) begin
            // Last accepted/granted beat has just completed.
            wb_cyc   <= 1'b0;
            wb_stb   <= 1'b0;
            wb_cti   <= 3'b000;
            wb_state <= IDLE;
          end else begin
            fifo_rd_en <= 1'b1;
            fifo_req_we_q <= fifo_req_we;
            fifo_req_be_q <= fifo_req_be;
            fifo_reg_wdata_q <= fifo_req_wdata;
            fifo_req_addr_q <= fifo_req_addr;
            // More already-granted beats remain.
            wb_adr <= wb_adr + 'd4;

            if (fifo_last_beat || (fifo_req_addr_q != wb_adr)) begin
              wb_cti <= 3'b111;   // next accepted beat is the last one
              wb_state <= FINISH;
            end
            else
              wb_cti <= 3'b010;   // incrementing burst continues
          end
        end
      end
      FINISH: begin
        fifo_rd_en <= 1'b0;
        if (wb_ack) begin
          fifo_rd_en <= 1'b1;
          resp_rdata <= wb_dat_r;
          resp_valid <= 1'b1;
          wb_dat_w <= fifo_reg_wdata_q;
          wb_adr <= 32'h0000_0000;
        end
        wb_cyc <= 1'b0;
        wb_stb <= 1'b0;
        wb_cti <= 3'b000;
        wb_bte <= 2'b00;
        wb_state <= IDLE;
      end
    endcase
  end
end


endmodule
