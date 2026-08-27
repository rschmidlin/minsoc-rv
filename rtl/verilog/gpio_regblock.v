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

wire wb_req = wb_cyc_i & wb_stb_i;
wire wb_xfer = wb_req & ~wb_ack_o;
wire wb_write = wb_xfer & wb_we_i;

always @(posedge wb_clk_i)
   if (wb_rst_i) begin
     oe_wr <= 1'b0;
     oe    <= 32'h0000_0000;
   end
   else
   if (wb_write && wb_adr_i[3:2]==2'h0)
      begin
         oe_wr <= 1'b1;
         oe    <= wb_dat_i;
      end
      else
         oe_wr <= 1'b0;
	

always @(posedge wb_clk_i)
   if (wb_rst_i) begin
     dato_wr <= 1'b0;
     dato    <= 32'h0000_0000;
   end
   else
   if (wb_write && wb_adr_i[3:2]==2'h2)
      begin
         dato_wr <= 1'b1;
         dato    <= wb_dat_i;
      end
      else
         dato_wr <= 1'b0;

wire wb_read   = wb_xfer & ~wb_we_i;

reg oe_rd_d, dati_rd_d;

always @(*)   // asynchronous reading
begin
   case (wb_adr_i[3:2])
      2'h0: begin
         wb_dat_o  = oe;
         oe_rd_d   = 1'b1;
         dati_rd_d = 1'b0;
      end
      2'h1: begin
         wb_dat_o  = dati;
         oe_rd_d   = 1'b0;
         dati_rd_d = 1'b1;
      end
      default: begin
         wb_dat_o  = 32'h0000_0000;
         oe_rd_d   = 1'b0;
         dati_rd_d = 1'b0;
      end
   endcase // case(wb_adr_i[3:2])
end // always @ (*)

always @(posedge wb_clk_i) begin
   if (wb_rst_i) begin
     wb_ack_o <= 1'b0;
     oe_rd    <= 1'b0;
     dati_rd  <= 1'b0;
   end
   else begin
      wb_ack_o <= wb_xfer;
      // Lesepulsignale nur bei gültigem Zugriff
      oe_rd    <= oe_rd_d & wb_read; 
      dati_rd  <= dati_rd_d & wb_read; 
   end
end


endmodule
