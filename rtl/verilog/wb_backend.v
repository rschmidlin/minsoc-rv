// SPDX-License-Identifier: Apache-2.0
//
// Copyright 2026 Raul Schmidlin

module wb_backend (
    input  wire        clk,
    input  wire        rst,

    // Request
    input  wire        req_valid,
    input  wire [31:0] req_addr,
    input  wire [3:0]  req_len,   // up to 16 beats
    input  wire        req_we,
    input  wire [31:0] req_wdata,
    input wire [3:0]   req_be,

    output reg         busy,

    // Response
    output reg         resp_valid,
    output reg [31:0]  resp_rdata,

    // Wishbone
    output reg         wb_cyc,
    output reg         wb_stb,
    output reg         wb_we,
    output reg [31:0]  wb_adr,
    output reg [31:0]  wb_dat_w,
    input  wire        wb_ack,
    input  wire [31:0] wb_dat_r,
    output reg [3:0]   wb_sel
);

    reg [3:0] beat_cnt;
    reg [31:0] addr;

    reg [1:0] state;

    localparam IDLE = 2'h0;
    localparam RUN = 2'h1;
    localparam DONE = 2'h2;

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            wb_cyc <= 0;
            wb_stb <= 0;
            wb_sel <= 4'h0;
            busy <= 0;
        end else begin
            resp_valid <= 0;

            case (state)
            IDLE: begin
                if (req_valid) begin
                    busy <= 1;
                    wb_cyc <= 1;
                    wb_stb <= 1;
                    wb_we  <= req_we;

                    addr <= req_addr;
                    wb_adr <= req_addr;
                    wb_dat_w <= req_wdata;
                    beat_cnt <= req_len;
                    wb_sel <= req_be;

                    state <= RUN;
                end
            end

            RUN: begin
                if (wb_ack) begin
                    resp_rdata <= wb_dat_r;
                    resp_valid <= 1;

                    beat_cnt <= beat_cnt - 1;

                    if (beat_cnt == 1) begin
                        wb_cyc <= 0;
                        wb_stb <= 0;
                        state <= DONE;
                    end else begin
                        // next beat
                        addr <= addr + 4;
                        wb_adr <= addr + 4;
                        wb_stb <= 1; // keep pipeline
                    end
                end
            end

            DONE: begin
                busy <= 0;
                state <= IDLE;
            end
            default: begin
                state <= IDLE;
                wb_cyc <= 0;
                wb_stb <= 0;
                wb_sel <= 4'h0;
                busy <= 0;
            end
            endcase
        end
    end

endmodule
