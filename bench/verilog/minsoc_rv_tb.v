module minsoc_rv_tb;

   localparam MEM_SIZE = 32'h02000000; //Set default memory size to 32MB

   vlog_tb_utils vlog_tb_utils0();

   ////////////////////////////////////////////////////////////////////////
   //
   // ELF program loading
   //
   ////////////////////////////////////////////////////////////////////////
   integer mem_words;
   integer i;
   reg [31:0] mem_word;
   reg [1023:0] elf_file;

   initial begin
      if ($test$plusargs("clear_ram")) begin
	 $display("Clearing RAM");
	 for(i=0; i < MEM_SIZE/4; i = i+1)
	   minsoc_rv_tb.dut.wb_bfm_memory0.ram0.mem[i] = 32'h00000000;
      end

      if($value$plusargs("elf_load=%s", elf_file)) begin
	 $elf_load_file(elf_file);

	 mem_words = $elf_get_size/4;
	 $display("Loading %d words", mem_words);
	 for(i=0; i < mem_words; i = i+1)
	   minsoc_rv_tb.dut.wb_bfm_memory0.ram0.mem[i] = $elf_read_32(i*4);
      end else
	$display("No ELF file specified");
   end

   ////////////////////////////////////////////////////////////////////////
   //
   // Clock and reset generation
   //
   ////////////////////////////////////////////////////////////////////////
   reg syst_clk = 1;
   reg syst_rst = 1;

   always #5 syst_clk <= ~syst_clk;
   initial #100 syst_rst <= 0;

   ////////////////////////////////////////////////////////////////////////
   //
   // UART monitor
   //
   ////////////////////////////////////////////////////////////////////////
   wire uart_stx;

   localparam UART_TX_WAIT = 1000000000 / 115200;

   reg [40*8-1:0] line;
   reg new_line;
   reg new_char;
   reg flush_line;

   initial begin
      new_line = 1'b0;
      new_char = 1'b0;
      flush_line = 1'b0;
   end

   always @(posedge syst_clk)
      if (!syst_rst)
         uart_decoder;

   task uart_decoder;
      integer i;
      reg [7:0] tx_byte;
      begin
         new_char = 1'b0;
         new_line = 1'b0;

         // Wait for start bit
         while (uart_stx == 1'b1)
            @(uart_stx);

         #(UART_TX_WAIT + (UART_TX_WAIT/2));

         for (i = 0; i < 8; i = i + 1) begin
            tx_byte[i] = uart_stx;
            #UART_TX_WAIT;
         end

         // Check for stop bit
         if (uart_stx == 1'b0) begin
            while (uart_stx == 1'b0)
               @(uart_stx);
         end

         // Display the character
         $write("%c", tx_byte);

         if (flush_line) begin
            line = "";
            flush_line = 1'b0;
         end
         if (tx_byte == "\n") begin
            new_line = 1'b1;
            flush_line = 1'b1;
         end else begin
            line = {line[39*8-1:0], tx_byte};
            new_char = 1'b1;
         end
      end
   endtask

   ////////////////////////////////////////////////////////////////////////
   //
   // DUT
   //
   ////////////////////////////////////////////////////////////////////////
   minsoc_rv_top
     #(.MEM_SIZE (MEM_SIZE))
   dut
     (.wb_clk_i  (syst_clk),
      .wb_rst_i  (syst_rst),
      .tms_pad_i (1'b0),
      .tck_pad_i (1'b0),
      .tdi_pad_i (1'b0),
      .tdo_pad_o (),
      .uart_srx_i (1'b1),
      .uart_stx_o (uart_stx));

endmodule
