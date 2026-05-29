// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 Raul Schmidlin

/* The adapter supports at most two outstanding Ibex grants:
- one active Wishbone transfer
- one buffered next request */

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


wire req_accepted;
wire valid_req_pending;
wire [31:0] next_address;
wire valid_req_address;
wire valid_req;

reg [3:0] transferred_len;
reg [3:0] accepted_len;
reg [31:0] req_addr_q;
reg gnt_q;

assign req_accepted = |(accepted_len);
assign valid_req_pending = req_accepted;
assign next_address = req_addr_q + 'd4;
assign valid_req_address = valid_req_pending ? (req_addr == next_address) : 1'b1;
assign valid_req = req_valid & valid_req_address;

localparam IDLE = 2'b00;
localparam ACCEPT = 2'b01;
localparam STALL = 2'b10;

reg [1:0] ib_state;

// Assert GNT with 2 cycles delay of request if not forbidden by transaction FSM
always @(posedge clk) begin
  if (rst) begin
    ib_state <= IDLE;
    req_addr_q <= 32'h0000_0000;
    gnt_q <= 1'b0;
    accepted_len <= 'd0;
  end
  else begin
    case (ib_state)
      IDLE: begin
        gnt_q <= 1'b0;
        if ((wb_state == IDLE) && (accepted_len == transferred_len)) begin  // accepted_len impacts ongoing burst if cleared too early
          req_addr_q   <= 32'h0000_0000;
          accepted_len <= 'd0;
        end
        if (valid_req && !wb_cyc) begin
          ib_state <= ACCEPT;
        end
      end
      ACCEPT: begin
        gnt_q <= 1'b0;
        if (valid_req) begin
          accepted_len <= accepted_len + 'd1;
          req_addr_q <= req_addr;
          gnt_q <= 1'b1;
        end
        else if (!gnt_q) begin  // if no request is there, STALL and potentially go to IDLE in sequence because !valid_req
          ib_state <= STALL;
        end
        if ('d2 == accepted_len) begin
          ib_state <= STALL;        // needed for write data otherwise we lose the data in the WB_FSM
        end
      end
      STALL: begin
        if (!valid_req) begin
          ib_state <= IDLE;
        end
        else if ((transferred_len == accepted_len) ||
                  (transferred_len + 'd2 == accepted_len)) begin
          if (accepted_len == req_len)
            ib_state <= IDLE;
          else
            ib_state <= ACCEPT;
        end
      end
    endcase
  end
end

assign gnt = gnt_q;


localparam ACTIVE = 2'b01;
localparam FINISH = 2'b10;

reg [1:0] wb_state;

wire wb_pending;

assign wb_pending = (accepted_len != 0) && (transferred_len < accepted_len);

always @(posedge clk) begin
  if (rst) begin
    transferred_len <= 'd0;
    wb_cyc <= 1'b0;
    wb_stb <= 1'b0;
    wb_we <= 1'b0;
    wb_adr <= 32'h0000_0000;
    wb_dat_w <= 32'h0000_0000;
    wb_sel <= req_be;
    wb_cti <= 3'b000;
    wb_bte <= 2'b00;
    wb_state <= IDLE;
  end
  else begin
    case (wb_state)
      IDLE: begin
        resp_valid <= 1'b0;
        wb_cyc <= 1'b0;
        wb_stb <= 1'b0;
        wb_we <= 1'b0;
        wb_adr <= 32'h0000_0000;
        wb_dat_w <= 32'h0000_0000;
        wb_sel <= req_be;
        wb_cti <= 3'b000;
        wb_bte <= 2'b00;

        if (accepted_len == 0)
          transferred_len <= 'd0;

        if (wb_pending) begin
          wb_state <= ACTIVE;
          transferred_len <= 'd0;
          wb_cyc <= 1'b1;
          wb_stb <= 1'b1;
          wb_we <= req_we;
          wb_adr <= req_addr_q;
          wb_dat_w <= req_wdata;
          if (req_len > 'd1) begin
            wb_cti <= 3'b010;
            wb_bte <= 2'b00;
          end
        end
      end
      ACTIVE: begin
        if (wb_ack) begin
          resp_rdata <= wb_dat_r;
          wb_dat_w <= req_wdata;
          resp_valid <= 1'b1;

          transferred_len <= transferred_len + 'd1;

          if ((transferred_len + 'd1) >= accepted_len) begin
            // Last accepted/granted beat has just completed.
            wb_cyc   <= 1'b0;
            wb_stb   <= 1'b0;
            wb_cti   <= 3'b000;
            wb_state <= IDLE;
          end else begin
            // More already-granted beats remain.
            wb_adr <= wb_adr + 'd4;

            if ((transferred_len + 'd2) >= accepted_len) begin
              wb_cti <= 3'b111;   // next accepted beat is the last one
              wb_state <= FINISH;
            end
            else
              wb_cti <= 3'b010;   // incrementing burst continues
          end
        end
      end
      FINISH: begin
        if (wb_ack) begin
          resp_rdata <= wb_dat_r;
          resp_valid <= 1'b1;
          wb_dat_w <= req_wdata;
          wb_adr <= req_addr_q;
          transferred_len <= transferred_len + 'd1;
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
