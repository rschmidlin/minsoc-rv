module minsoc_rv_top
  #(parameter MEM_SIZE = 32'h02000000
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

// Register address from word-aligned bus address
wire [2:0] uart_reg_addr = wb_m2s_uart_adr[4:2];

// Write data: always in low byte (firmware uses 32-bit word writes)
wire [7:0] uart_wdata = wb_m2s_uart_dat[7:0];

// Read data: replicate across all four byte lanes
wire [7:0] uart_rdata;
assign wb_s2m_uart_dat = {uart_rdata, uart_rdata, uart_rdata, uart_rdata};

uart_top #(
	.debug	(0),
	.SIM	(0)
) uart16550 (
	.wb_clk_i	(wb_clk_i),
	.wb_rst_i	(wb_rst_i),
	.wb_adr_i	(uart_reg_addr),
	.wb_dat_i	(uart_wdata),
	.wb_sel_i	(4'h0),
	.wb_we_i	(wb_m2s_uart_we),
	.wb_cyc_i	(wb_m2s_uart_cyc),
	.wb_stb_i	(wb_m2s_uart_stb),
	.wb_dat_o	(uart_rdata),
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

    generate if (IBEX == 1'b0) begin 
////////////////////////////////////////////////////////////////////////
//
// PicoRV32 RISC-V Core with Wishbone Interface
//
////////////////////////////////////////////////////////////////////////

picorv32_wb #(
    .ENABLE_COUNTERS      ( 1 ),
    .ENABLE_COUNTERS64    ( 1 ),
    .ENABLE_REGS_16_31    ( 1 ),
    .ENABLE_REGS_DUALPORT ( 1 ),
    //.LATCHED_MEM_RDATA    ( 0 ),
    .TWO_STAGE_SHIFT      ( 1 ),
    .BARREL_SHIFTER       ( 0 ),
    .TWO_CYCLE_COMPARE    ( 0 ),
    .TWO_CYCLE_ALU        ( 0 ),
    .COMPRESSED_ISA       ( 0 ),
    .CATCH_MISALIGN       ( 1 ),
    .CATCH_ILLINSN        ( 1 ),
    .ENABLE_PCPI          ( 0 ),
    .ENABLE_MUL           ( 0 ),
    .ENABLE_FAST_MUL      ( 0 ),
    .ENABLE_DIV           ( 0 ),
    .ENABLE_IRQ           ( 1 ),
    .ENABLE_IRQ_QREGS     ( 1 ),
    .ENABLE_IRQ_TIMER     ( 1 ),
    .ENABLE_TRACE         ( 0 ),
    .REGS_INIT_ZERO       ( 0 ),
    .MASKED_IRQ           ( 32'h0000_0000 ),
    .LATCHED_IRQ          ( 32'hffff_ffff ),
    .PROGADDR_RESET       ( 32'h0000_0000 ),
    .PROGADDR_IRQ         ( 32'h0000_0010 ),
    .STACKADDR            ( 32'hffff_ffff )
) u_picorv32_wb (
    .wb_clk_i(wb_clk),
    .wb_rst_i(wb_rst),
    .trap(),

    // Wishbone Master Interface - routed to memory interconnect
    .wbm_cyc_o(wb_m2s_picorv32_cyc),
    .wbm_stb_o(wb_m2s_picorv32_stb),
    .wbm_we_o(wb_m2s_picorv32_we),
    .wbm_adr_o(wb_m2s_picorv32_adr),
    .wbm_dat_o(wb_m2s_picorv32_dat),
    .wbm_sel_o(wb_m2s_picorv32_sel),
    .wbm_ack_i(wb_s2m_picorv32_ack),
    .wbm_dat_i(wb_s2m_picorv32_dat),

	// Pico Co-Processor Interface (PCPI)
	.pcpi_valid(),
	.pcpi_insn(),
	.pcpi_rs1(),
	.pcpi_rs2(),
	.pcpi_wr(1'b0),
	.pcpi_rd(32'h0000_0000),
	.pcpi_wait(1'b0),
	.pcpi_ready(1'b0),
   
   // IRQ Interface (tied off for now)
   .irq(32'h0),
   .eoi(),
   
	// Trace Interface
	.trace_valid(),
	.trace_data(),
   
	.mem_instr()
);

// PicoRV32 does not drive Wishbone B3 cycle type signals;
// tie to classic cycle (cti=000, bte=00) so the interconnect
// and wb_ram accept the transactions.
assign wb_m2s_picorv32_cti = 3'b000;
assign wb_m2s_picorv32_bte = 2'b00;
    end // if (IBEX == 1)
    else begin

    wire irq_software_i, irq_timer_i, irq_external_i, irq_nm_i;
    wire [14:0] irq_fast_i;

    wire debug_req_i;
    wire [63:0] crash_dump_o;

    wire fetch_enable_i, alert_minor_o, alert_major_internal_o, alert_major_bus_o, core_sleep_o;

    assign irq_software_i = 1'b0;
    assign irq_timer_i = 1'b0;
    assign irq_external_i = 1'b0;
    assign irq_nm_i = 1'b0;
    assign irq_fast_i = 15'h0000;

    assign debug_req_i = 1'b0;

    assign fetch_enable_i = 1'b0;
    
    ibex_wb #(
      .PMPEnable                    (1'b0),
      .PMPGranularity               (0),
      .PMPNumRegions                (4),
      .MHPMCounterNum               (0),
      .MHPMCounterWidth             (40),
      .PMPRstCfg[P_MAX_REGIONS]     (ibex_pkg::PmpCfgRst),
      .PMPRstAddr[P_MAX_REGIONS]    (ibex_pkg::PmpAddrRst),
      .PMPRstMsecCfg                (ibex_pkg::PmpMseccfgRst),
      .RV32E                        (1'b0),
      .RV32M                        (RV32MFast),
      .RV32B                        (RV32BNone),
      .RV32ZC                       (RV32ZcaZcbZcmp),
      .RegFile                      (RegFileFF),
      .BranchTargetALU              (1'b0),
      .WritebackStage               (1'b0),
      .ICache                       (1'b0),
      .ICacheECC                    (1'b0),
      .BranchPredictor              (1'b0),
      .DbgTriggerEn                 (1'b0),
      .DbgHwBreakNum                (1),
      .SecureIbex                   (1'b0),
      .LockstepOffset               (1),
      .MemECC                       (SecureIbex),
      .MemDataWidth                 (MemECC ? 32 + 7 : 32),
      .ICacheScramble               (1'b0),
      .ICacheScrNumPrinceRoundsHalf (2),
      .ICacheTweakInfection         (SecureIbex),
      .RndCnstLfsrSeed              (RndCnstLfsrSeedDefault),
      .RndCnstLfsrPerm              (RndCnstLfsrPermDefault),
      .DmBaseAddr                   (32'h1A110000),
      .DmAddrMask                   (32'h00000FFF),
      .DmHaltAddr                   (32'h1A110800),
      .DmExceptionAddr              (32'h1A110808),
      .RndCnstIbexKey               (RndCnstIbexKeyDefault),
      .RndCnstIbexNonce             (RndCnstIbexNonceDefault),
      .CsrMvendorId                 (32'b0),
      .CsrMimpId                    (32'b0)
)
    u_ibex (
            .clk_i(wb_clk),
            .rst_ni(wb_rst),

	// Wishbone Instruction Memory Interface
            .instr_wb_cyc(wb_m2s_ibexi_cyc),
            .instr_wb_stb(wb_m2s_ibexi_stb),
            .instr_wb_we(wb_m2s_ibexi_we),
            .instr_wb_adr(wb_m2s_ibexi_adr),
            .instr_wb_dat_w(wb_m2s_ibexi_dat_w),
            .instr_wb_ack(wb_s2m_ibexi_ack),
            .instr_wb_dat_r(wb_s2m_ibexi_dat_r),
            .instr_wb_err(wb_s2m_ibexi_err),

	// Wishbone Data Memory Interface
            .data_wb_cyc(wb_m2s_ibexd_cyc),
            .data_wb_stb(wb_m2s_ibexd_stb),
            .data_wb_we(wb_m2s_ibexd_we),
            .data_wb_adr(wb_m2s_ibexd_adr),
            .data_wb_dat_w(wb_m2s_ibexd_dat_w),
            .data_wb_ack(wb_s2m_ibexd_ack),
            .data_wb_dat_r(wb_s2m_ibexd_dat_r),
            .data_wb_err(wb_s2m_ibexd_err),

	// Configuration
            .hart_id_i(hart_id_i),
            .boot_addr_i(boot_addr_i),

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
    end
    endgenerate

endmodule
