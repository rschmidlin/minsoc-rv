module minsoc_rv_top
  #(parameter MEM_SIZE = 32'h02000000,
    parameter IBEX = 1'b1
   )
(
		input wb_clk_i,
		input wb_rst_i,
		output tdo_pad_o,
		input tms_pad_i,
		input tck_pad_i,
		input tdi_pad_i,
		input uart_srx_i,
		output uart_stx_o
);

localparam wb_aw = 32;
localparam wb_dw = 32;


////////////////////////////////////////////////////////////////////////
//
// Wishbone interconnect
//
////////////////////////////////////////////////////////////////////////
wire wb_clk = wb_clk_i;
wire wb_rst = wb_rst_i;

`include "wb_intercon.vh"


////////////////////////////////////////////////////////////////////////
//
// Generic main RAM
//
////////////////////////////////////////////////////////////////////////
wb_ram #(
	.depth	(MEM_SIZE)
) wb_bfm_memory0 (
	//Wishbone Master interface
	.wb_clk_i	(wb_clk_i),
	.wb_rst_i	(wb_rst_i),
	.wb_adr_i	(wb_m2s_mem_adr[$clog2(MEM_SIZE)-1:0]),
	.wb_dat_i	(wb_m2s_mem_dat),
	.wb_sel_i	(wb_m2s_mem_sel),
	.wb_we_i	(wb_m2s_mem_we),
	.wb_cyc_i	(wb_m2s_mem_cyc),
	.wb_stb_i	(wb_m2s_mem_stb),
	.wb_cti_i	(wb_m2s_mem_cti),
	.wb_bte_i	(wb_m2s_mem_bte),
	.wb_dat_o	(wb_s2m_mem_dat),
	.wb_ack_o	(wb_s2m_mem_ack),
	.wb_err_o	(wb_s2m_mem_err)
);
   assign wb_s2m_mem_rty = 1'b0;


////////////////////////////////////////////////////////////////////////
//
// UART (32-to-8 bit bridge, word-addressed registers)
//
// PicoRV32 word-aligns all bus addresses (adr[1:0] always 00) and
// sets sel=0 on reads (mem_wstrb is zero for loads).  To make both
// reads and writes work without modifying the CPU, the UART registers
// are mapped at 4-byte (word) spacing:
//
//   UART_BASE + 0x00  ->  register 0  (TX/RX/DLL)
//   UART_BASE + 0x04  ->  register 1  (IER/DLM)
//   UART_BASE + 0x08  ->  register 2  (FCR/IIR)
//   UART_BASE + 0x0C  ->  register 3  (LCR)
//   UART_BASE + 0x10  ->  register 4  (MCR)
//   UART_BASE + 0x14  ->  register 5  (LSR)
//   UART_BASE + 0x18  ->  register 6  (MSR)
//   UART_BASE + 0x1C  ->  register 7  (SCR)
//
// adr[4:2] gives the 3-bit UART register index directly.
// Data is always in the low byte (bits [7:0]) of the 32-bit bus.
//
////////////////////////////////////////////////////////////////////////
wire uart_irq;
wire [31:0] wb_big_endian_uart_adr;
assign wb_big_endian_uart_adr = {wb_m2s_uart_adr[31:2], ~wb_m2s_uart_adr[1:0]};  // Convert little-endian word address to big-endian byte address

uart_top #(
	.debug	(0),
	.SIM	(0)
) uart16550 (
	.wb_clk_i	(wb_clk_i),
	.wb_rst_i	(wb_rst_i),
	.wb_adr_i	(wb_big_endian_uart_adr),
	.wb_dat_i	(wb_m2s_uart_dat),
	.wb_sel_i	(wb_m2s_uart_sel),
	.wb_we_i	(wb_m2s_uart_we),
	.wb_cyc_i	(wb_m2s_uart_cyc),
	.wb_stb_i	(wb_m2s_uart_stb),
	.wb_dat_o	(wb_s2m_uart_dat),
	.wb_ack_o	(wb_s2m_uart_ack),
        .int_o		(uart_irq),
	.srx_pad_i	(uart_srx_i),
	.stx_pad_o	(uart_stx_o),
	.rts_pad_o	(),
	.cts_pad_i	(1'b0),
	.dtr_pad_o	(),
	.dsr_pad_i	(1'b0),
	.ri_pad_i	(1'b0),
	.dcd_pad_i	(1'b0)
);
   assign wb_s2m_uart_err = 1'b0;
   assign wb_s2m_uart_rty = 1'b0;


   wire irq_software_i, irq_timer_i, irq_external_i, irq_nm_i;
   wire [14:0] irq_fast_i;

   wire debug_req_i;
   wire [63:0] crash_dump_o;

   wire alert_minor_o, alert_major_internal_o, alert_major_bus_o, core_sleep_o;
   wire [3:0] fetch_enable_i;

   assign irq_software_i = 1'b0;
   assign irq_timer_i = 1'b0;
   assign irq_external_i = 1'b0;
   assign irq_nm_i = 1'b0;
   assign irq_fast_i = 15'h0000;

   assign debug_req_i = 1'b0;

   assign fetch_enable_i = 4'b0101;
   
   ibex_wb #(
      .PMPEnable(1'b0),
      .PMPGranularity(0),
      .PMPNumRegions(4)
)
   u_ibex (
         .clk_i(wb_clk),
         .rst_ni(~wb_rst),

// Wishbone Instruction Memory Interface
         .instr_wb_cyc(wb_m2s_ibexi_cyc),
         .instr_wb_stb(wb_m2s_ibexi_stb),
         .instr_wb_we(wb_m2s_ibexi_we),
         .instr_wb_adr(wb_m2s_ibexi_adr),
         .instr_wb_dat_w(wb_m2s_ibexi_dat),
         .instr_wb_ack(wb_s2m_ibexi_ack),
         .instr_wb_dat_r(wb_s2m_ibexi_dat),
         .instr_wb_err(wb_s2m_ibexi_err),
         .instr_wb_sel(wb_m2s_ibexi_sel), // byte enables for instruction bus only

// Wishbone Data Memory Interface
         .data_wb_cyc(wb_m2s_ibexd_cyc),
         .data_wb_stb(wb_m2s_ibexd_stb),
         .data_wb_we(wb_m2s_ibexd_we),
         .data_wb_adr(wb_m2s_ibexd_adr),
         .data_wb_dat_w(wb_m2s_ibexd_dat),
         .data_wb_ack(wb_s2m_ibexd_ack),
         .data_wb_dat_r(wb_s2m_ibexd_dat),
         .data_wb_err(wb_s2m_ibexd_err),
         .data_wb_sel(wb_m2s_ibexd_sel), // byte enables for data bus only

// Configuration
         .hart_id_i(32'hdeadbeef),
         .boot_addr_i(32'h00000000),

// Interrupt inputs
         .irq_software_i(irq_software_i),
         .irq_timer_i(irq_timer_i),
         .irq_external_i(irq_external_i),
         .irq_fast_i(irq_fast_i),
         .irq_nm_i(irq_nm_i),

// Debug interface (optional)
         .debug_req_i(debug_req_i),
         .crash_dump_o(crash_dump_o),

// Control signals
         .fetch_enable_i(fetch_enable_i),
         .alert_minor_o(alert_minor_o),
         .alert_major_internal_o(alert_major_internal_o),
         .alert_major_bus_o(alert_major_bus_o),
         .core_sleep_o(core_sleep_o)
         );

endmodule
