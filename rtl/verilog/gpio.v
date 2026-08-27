module gpio (
    input wire wb_clk_i,
    input wire wb_rst_i,
    input wire wb_cyc_i,
    input wire wb_stb_i,
    input wire [31:0] wb_adr_i,
    input wire wb_we_i,
    input wire [31:0] wb_dat_i,
    output wire [31:0] wb_dat_o,
    output wire wb_ack_o,

    inout [31:0] inoutput
);

wire oe_rd, oe_wr, dati_rd, dato_wr;

wire [31:0] oe_reg;
wire [31:0] dati_reg;
wire [31:0] dato_reg;

gpio_regblock gpio_regblock_i(
    .wb_clk_i(wb_clk_i),
    .wb_rst_i(wb_rst_i),
    .wb_cyc_i(wb_cyc_i),
    .wb_stb_i(wb_stb_i),
    .wb_adr_i(wb_adr_i),
    .wb_we_i(wb_we_i),
    .wb_dat_i(wb_dat_i),
    .wb_dat_o(wb_dat_o),
    .wb_ack_o(wb_ack_o),

    .oe_rd(oe_rd),
    .oe_wr(oe_wr),
    .dati_rd(dati_rd),
    .dato_wr(dato_wr),

    .oe(oe_reg),
    .dati(dati_reg),
    .dato(dato_reg)
);

genvar i;
reg [31:0] dout;
wire [31:0] din;

assign dati_reg = dout;

generate
   for (i = 0; i < 32; i = i +1) begin : mux
      assign din[i] = oe_reg[i] ? dato_reg[i] : inoutput[i];
   end
endgenerate

always @(posedge wb_clk_i) begin
   if (wb_rst_i) begin
      dout <= 32'h0000_0000;
   end
   else begin
      dout <= din;
   end
end

generate
   for (i = 0; i < 32; i = i +1) begin : tri_state_gen
      assign inoutput[i] = oe_reg[i] ? dout[i] : 1'bZ;
   end
endgenerate

endmodule
