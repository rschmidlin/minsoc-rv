module gpio_regblock (
    input wire wb_clk_i,
    input wire wb_rst_i,
    input wire wb_cyc_i,
    input wire wb_stb_i,
    input wire [31:0] wb_adr_i,
    input wire wb_we_i,
    input wire [31:0] wb_dat_i,
    output reg [31:0] wb_dat_o,
    output reg wb_ack_o,
    
    output reg oe_wr,
    output reg oe_rd,
    output reg [31:0] oe,
    
    output reg dati_rd,
    input wire [31:0] dati,

    output reg dato_wr,
    output reg [31:0] dato
);

reg oe_rd_d, dati_rd_d;

endmodule
