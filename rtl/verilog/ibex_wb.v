/**
 * Ibex with Wishbone Backend
 *
 * This module wraps the Ibex RISC-V core and provides Wishbone interfaces
 * for both instruction and data memory via wb_backend adapters. The Ibex core's
 * native memory interfaces (instr_req/gnt/rvalid and data_req/gnt/rvalid) are
 * converted to Wishbone B4 interfaces.
 */

module ibex_wb #(
	// Ibex Parameters
	parameter bit          PMPEnable        = 1'b0,
	parameter int unsigned PMPGranularity   = 0,
	parameter int unsigned PMPNumRegions    = 4,
	parameter int unsigned MHPMCounterNum   = 0,
	parameter int unsigned MHPMCounterWidth = 40,
	parameter bit          RV32E            = 1'b0,
	parameter bit          RV32M            = 1'b1,
	parameter bit          RV32B            = 1'b0,
	parameter bit          RV32ZC           = 1'b0,
	parameter bit          RegFile          = 1'b0,
	parameter bit          ICache           = 1'b0,
	parameter bit          ICacheECC        = 1'b0,
	parameter bit          ICacheTweakInfection = 1'b0,
	parameter bit          ICacheScramble   = 1'b0,
	parameter bit          BranchPrediction = 1'b0,
	parameter bit          SecureIbex       = 1'b0,
	parameter bit          DbgTriggerEn     = 1'b0,
	parameter bit [31:0]   DmBaseAddr       = 32'h1A110000,
	parameter bit [31:0]   DmAddrMask       = 32'h00000FFF,
	parameter bit [31:0]   DmHaltAddr       = 32'h1A110800,
	parameter bit [31:0]   DmExceptionAddr  = 32'h1A110808
) (
	input  wire        clk_i,
	input  wire        rst_ni,

	// Wishbone Instruction Memory Interface
	output wire        instr_wb_cyc,
	output wire        instr_wb_stb,
	output wire        instr_wb_we,
	output wire [31:0] instr_wb_adr,
	output wire [31:0] instr_wb_dat_w,
	input  wire        instr_wb_ack,
	input  wire [31:0] instr_wb_dat_r,
	input  wire        instr_wb_err,

	// Wishbone Data Memory Interface
	output wire        data_wb_cyc,
	output wire        data_wb_stb,
	output wire        data_wb_we,
	output wire [31:0] data_wb_adr,
	output wire [31:0] data_wb_dat_w,
	input  wire        data_wb_ack,
	input  wire [31:0] data_wb_dat_r,
	input  wire        data_wb_err,

	// Configuration
	input  wire [31:0] hart_id_i,
	input  wire [31:0] boot_addr_i,

	// Interrupt inputs
	input  wire        irq_software_i,
	input  wire        irq_timer_i,
	input  wire        irq_external_i,
	input  wire [14:0] irq_fast_i,
	input  wire        irq_nm_i,

	// Debug interface (optional)
	input  wire        debug_req_i,
	output wire [63:0] crash_dump_o,

	// Control signals
	input  wire        fetch_enable_i,
	output wire        alert_minor_o,
	output wire        alert_major_internal_o,
	output wire        alert_major_bus_o,
	output wire        core_sleep_o
);

	// Instruction memory interface signals
	wire        instr_req;
	wire        instr_gnt;
	wire        instr_rvalid;
	wire [31:0] instr_addr;
	wire [31:0] instr_rdata;
	wire        instr_err;

	// Data memory interface signals
	wire        data_req;
	wire        data_gnt;
	wire        data_rvalid;
	wire        data_we;
	wire [ 3:0] data_be;
	wire [31:0] data_addr;
	wire [31:0] data_wdata;
	wire [31:0] data_rdata;
	wire        data_err;

	// Instruction backend adapter signals
	wire        instr_req_valid;
	wire [31:0] instr_req_addr;
	wire [ 3:0] instr_req_len;
	wire        instr_req_we;
	wire [31:0] instr_req_wdata;
	wire        instr_busy;
	wire        instr_resp_valid;
	wire [31:0] instr_resp_rdata;

	// Data backend adapter signals
	wire        data_req_valid;
	wire [31:0] data_req_addr;
	wire [ 3:0] data_req_len;
	wire        data_req_we;
	wire [31:0] data_req_wdata;
	wire        data_resp_busy;
	wire        data_resp_valid;
	wire [31:0] data_resp_rdata;

	/*
	 * Ibex Core Instance
	 */
	ibex_top #(
		.PMPEnable(PMPEnable),
		.PMPGranularity(PMPGranularity),
		.PMPNumRegions(PMPNumRegions),
		.MHPMCounterNum(MHPMCounterNum),
		.MHPMCounterWidth(MHPMCounterWidth),
		.RV32E(RV32E),
		.RV32M(RV32M),
		.RV32B(RV32B),
		.RV32ZC(RV32ZC),
		.RegFile(RegFile),
		.ICache(ICache),
		.ICacheECC(ICacheECC),
		.ICacheTweakInfection(ICacheTweakInfection),
		.ICacheScramble(ICacheScramble),
		.BranchPrediction(BranchPrediction),
		.SecureIbex(SecureIbex),
		.DbgTriggerEn(DbgTriggerEn),
		.DmBaseAddr(DmBaseAddr),
		.DmAddrMask(DmAddrMask),
		.DmHaltAddr(DmHaltAddr),
		.DmExceptionAddr(DmExceptionAddr)
	) i_ibex (
		// Clock and reset
		.clk_i(clk_i),
		.rst_ni(rst_ni),
		.test_en_i(1'b0),
		.scan_rst_ni(1'b1),
		.ram_cfg_i(10'b0),

		// Configuration
		.hart_id_i(hart_id_i),
		.boot_addr_i(boot_addr_i),

		// Instruction memory interface
		.instr_req_o(instr_req),
		.instr_gnt_i(instr_gnt),
		.instr_rvalid_i(instr_rvalid),
		.instr_addr_o(instr_addr),
		.instr_rdata_i(instr_rdata),
		.instr_rdata_intg_i(32'b0),
		.instr_err_i(instr_err),

		// Data memory interface
		.data_req_o(data_req),
		.data_gnt_i(data_gnt),
		.data_rvalid_i(data_rvalid),
		.data_we_o(data_we),
		.data_be_o(data_be),
		.data_addr_o(data_addr),
		.data_wdata_o(data_wdata),
		.data_wdata_intg_o(),
		.data_rdata_i(data_rdata),
		.data_rdata_intg_i(32'b0),
		.data_err_i(data_err),

		// Interrupt inputs
		.irq_software_i(irq_software_i),
		.irq_timer_i(irq_timer_i),
		.irq_external_i(irq_external_i),
		.irq_fast_i(irq_fast_i),
		.irq_nm_i(irq_nm_i),

		// Debug interface
		.debug_req_i(debug_req_i),
		.crash_dump_o(crash_dump_o),

		// Special control signals
		.fetch_enable_i(fetch_enable_i),
		.alert_minor_o(alert_minor_o),
		.alert_major_internal_o(alert_major_internal_o),
		.alert_major_bus_o(alert_major_bus_o),
		.core_sleep_o(core_sleep_o),

		// Lockstep signals (not used in this wrapper)
		.lockstep_cmp_en_o(),

		// Shadow core outputs (not used in this wrapper)
		.data_req_shadow_o(),
		.data_we_shadow_o(),
		.data_be_shadow_o(),
		.data_addr_shadow_o(),
		.data_wdata_shadow_o(),
		.data_wdata_intg_shadow_o(),
		.instr_req_shadow_o(),
		.instr_addr_shadow_o()
	);

	/*
	 * Instruction Memory Interface to Request/Response Adapter
	 *
	 * Converts Ibex's handshake-based instruction interface to a simple
	 * request/response protocol for the wb_backend.
	 */

	assign instr_gnt = ~instr_busy;
	assign instr_rvalid = instr_resp_valid;
	assign instr_rdata = instr_resp_rdata;
	assign instr_err = 1'b0;  // No errors for now

	assign instr_req_valid = instr_req;
	assign instr_req_addr = instr_addr;
	assign instr_req_we = 1'b0;      // Instructions are always reads
	assign instr_req_wdata = 32'b0;
	assign instr_req_len = 4'h1;     // Single beat

	/*
	 * Data Memory Interface to Request/Response Adapter
	 *
	 * Converts Ibex's handshake-based data interface to a simple
	 * request/response protocol for the wb_backend.
	 */

	assign data_gnt = ~data_resp_busy;
	assign data_rvalid = data_resp_valid;
	assign data_rdata = data_resp_rdata;
	assign data_err = 1'b0;  // No errors for now

	assign data_req_valid = data_req;
	assign data_req_addr = data_addr;
	assign data_req_we = data_we;
	assign data_req_wdata = data_wdata;
	assign data_req_len = 4'h1;  // Single beat

	/*
	 * Instruction Wishbone Backend Adapter Instance
	 */
	wb_backend i_instr_wb_backend (
		.clk(clk_i),
		.rst(~rst_ni),
		.req_valid(instr_req_valid),
		.req_addr(instr_req_addr),
		.req_len(instr_req_len),
		.req_we(instr_req_we),
		.req_wdata(instr_req_wdata),
		.busy(instr_busy),
		.resp_valid(instr_resp_valid),
		.resp_rdata(instr_resp_rdata),
		.wb_cyc(instr_wb_cyc),
		.wb_stb(instr_wb_stb),
		.wb_we(instr_wb_we),
		.wb_adr(instr_wb_adr),
		.wb_dat_w(instr_wb_dat_w),
		.wb_ack(instr_wb_ack),
		.wb_dat_r(instr_wb_dat_r)
	);

	/*
	 * Data Wishbone Backend Adapter Instance
	 */
	wb_backend i_data_wb_backend (
		.clk(clk_i),
		.rst(~rst_ni),
		.req_valid(data_req_valid),
		.req_addr(data_req_addr),
		.req_len(data_req_len),
		.req_we(data_req_we),
		.req_wdata(data_req_wdata),
		.busy(data_resp_busy),
		.resp_valid(data_resp_valid),
		.resp_rdata(data_resp_rdata),
		.wb_cyc(data_wb_cyc),
		.wb_stb(data_wb_stb),
		.wb_we(data_wb_we),
		.wb_adr(data_wb_adr),
		.wb_dat_w(data_wb_dat_w),
		.wb_ack(data_wb_ack),
		.wb_dat_r(data_wb_dat_r)
	);

endmodule
