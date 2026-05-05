
module ibex_backend (
    input  wire        clk,
    input  wire        rst,

    // Wishbone
    input reg         wb_cyc,
    input reg         wb_stb,
    input reg         wb_we,
    input reg [31:0]  wb_adr,
    input reg [31:0]  wb_dat_w,
    output  wire        wb_ack,
    output  wire [31:0] wb_dat_r,
    input wire [3:0]  wb_sel

    // Request
    output wire        req_valid,
    output wire [31:0] req_addr,
    output wire [3:0]  req_len,   // up to 16 beats
    output wire        req_we,
    output wire [31:0] req_wdata,
    output wire [3:0] req_be,

    // Response
    input reg         resp_valid,
    input reg [31:0]  resp_rdata,
);

// Identify Wishbone requests 
assign req_valid = wb_cyc & wb_stb;
assign req_addr = wb_adr;
assign req_len = 4'h1;
assign req_we = wb_we;
assign req_wdata = wb_dat_w;
assign req_be = wb_sel;

assign wb_ack = resp_valid;
assign wb_dat_r = resp_rdata;
