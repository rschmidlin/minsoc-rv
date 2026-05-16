
module minsoc_riscv_dbg #(
  parameter int unsigned        NrHarts          = 1,
  parameter logic [31:0] IdcodeValue = 32'h 0000_0001,
  parameter int unsigned        BusWidth         = 32,
  parameter int unsigned        DmBaseAddress    = 'h1000, // default to non-zero page
  // Bitmask to select physically available harts for systems
  // that don't use hart numbers in a contiguous fashion.
  parameter logic [NrHarts-1:0] SelectableHarts  = {NrHarts{1'b1}},
  // toggle new behavior to drive master_be_o during a read
  parameter bit                 ReadByteEnable   = 1
) (
    input logic                     clk_i,
    input logic                     rst_ni,
    input logic [31:0]              next_dm_addr_i,
    input logic                     testmode_i,
    output logic                    ndmreset_o,
    input logic                     ndmreset_ack_i,
    output logic                    dmactive_o,
    output logic [NrHarts-1:0]      debug_req_o,
    input logic [NrHarts-1:0]       unavailable_i,

    // Wishbone Slave Interface
	input logic                     slave_wb_cyc_i,
	input logic                     slave_wb_stb_i,
	input logic                     slave_wb_we_i,
	input logic [BusWidth-1:0]      slave_wb_adr_i,
	input logic [BusWidth-1:0]      slave_wb_dat_w_i,
	output  logic                   slave_wb_ack_o,
	output  logic [BusWidth-1:0]    slave_wb_dat_r_o,
	output  logic                   slave_wb_err_o,
	input logic [BusWidth/8-1:0]    slave_wb_sel_i,

    // Wishbone Master Interface
	output logic                   master_wb_cyc_o,
	output logic                   master_wb_stb_o,
	output logic                   master_wb_we_o,
	output logic [BusWidth-1:0]    master_wb_adr_o,
	output logic [BusWidth-1:0]    master_wb_dat_w_o,
	input  logic                   master_wb_ack_i,
	input  logic [BusWidth-1:0]    master_wb_dat_r_i,
	input  logic                   master_wb_err_i,
	output logic [BusWidth/8-1:0]  master_wb_sel_o,

    input  logic        tck_i,    // JTAG test clock pad
    input  logic        tms_i,    // JTAG test mode select pad
    input  logic        trst_ni,  // JTAG test reset pad
    input  logic        td_i,     // JTAG test data input pad
    output logic        td_o      // JTAG test data output pad
);

	// Master backend adapter signals
	wire        master_req;
  wire        master_req_valid;
	wire [31:0] master_req_addr;
	wire [ 3:0] master_req_len;
	wire        master_req_we;
	wire [31:0] master_req_wdata;
    wire [3:0]  master_be;
    wire        master_gnt;
	wire        master_busy;
	wire        master_resp_valid;
	wire [31:0] master_resp_rdata;
    wire        master_rerror;

    // Slave memory interface signals
	wire        slave_req;
	wire        slave_gnt;
	wire        slave_rvalid;
	wire [31:0] slave_addr;
	wire [31:0] slave_rdata;
	wire        slave_err;

	// Slave backend adapter signals
	wire        slave_req_valid;
	wire [31:0] slave_req_addr;
	wire [ 3:0] slave_req_len;
	wire        slave_req_we;
	wire [31:0] slave_req_wdata;
	wire        slave_req_be;
	wire        slave_resp_valid;
	wire [31:0] slave_resp_rdata;

    // DTM wiring
    dm::dmi_req_t  dmi_req;
    dm::dmi_resp_t dmi_rsp;
    logic dmi_req_valid, dmi_req_ready;
    logic dmi_rsp_valid, dmi_rsp_ready;
    logic dmi_rst_n;

  // static debug hartinfo
  localparam dm::hartinfo_t DebugHartInfo = '{
    zero1:      '0,
    nscratch:   2, // Debug module needs at least two scratch regs
    zero0:      0,
    dataaccess: 1'b1, // data registers are memory mapped in the debugger
    datasize:   dm::DataCount,
    dataaddr:   dm::DataAddr
  };

  dm::hartinfo_t [NrHarts-1:0]      hartinfo;

  for (genvar i = 0; i < NrHarts; i++) begin : gen_dm_hart_ctrl
    assign hartinfo[i] = DebugHartInfo;
  end

dm_top #(
  .NrHarts(NrHarts),
  .BusWidth(BusWidth),
  .DmBaseAddress(DmBaseAddress), // default to non-zero page
  // Bitmask to select physically available harts for systems
  // that don't use hart numbers in a contiguous fashion.
  .SelectableHarts(SelectableHarts),
  // toggle new behavior to drive master_be_o during a read
  .ReadByteEnable(ReadByteEnable)
) u_dm_top(
  .clk_i(clk_i),       // clock
  // asynchronous reset active low, connect PoR here, not the system reset
  .rst_ni(rst_ni),
  // Subsequent debug modules can be chained by setting the nextdm register value to the offset of
  // the next debug module. The RISC-V debug spec mandates that the first debug module located at
  // 0x0, and that the last debug module in the chain sets the nextdm register to 0x0. The nextdm
  // register is a word address and not a byte address. This value is passed in as a static signal
  // so that it becomes possible to assign this value with chiplet tie-offs or straps, if needed.
  .next_dm_addr_i(next_dm_addr_i),
  .testmode_i(testmode_i),
  .ndmreset_o(ndmreset_o),  // non-debug module reset
  .ndmreset_ack_i(ndmreset_q), // non-debug module reset acknowledgement pulse
  .dmactive_o(dmactive_o),  // debug module is active
  .debug_req_o(debug_req_o), // async debug request
  // communicate whether the hart is unavailable (e.g.: power down)
  .unavailable_i(unavailable_i),
  .hartinfo_i(hartinfo),

  .slave_req_i(slave_req_valid),
  .slave_we_i(slave_req_we),
  .slave_addr_i(slave_req_addr),
  .slave_be_i(slave_req_be),
  .slave_wdata_i(slave_req_wdata),
  .slave_rdata_o(slave_resp_rdata),

  .master_req_o(master_req_valid),
  .master_add_o(master_req_addr),
  .master_we_o(master_req_we),
  .master_wdata_o(master_req_wdata),
  .master_be_o(master_be),
  .master_gnt_i(master_gnt),
  .master_r_valid_i(master_resp_valid),
  .master_r_err_i(master_rerror),
  .master_r_other_err_i(), // *other_err_i has priority over *err_i
  .master_r_rdata_i(master_resp_rdata),

  // Connection to DTM - compatible to RocketChip Debug Module
  .dmi_rst_ni(dmi_rst_n), // Synchronous clear request from
                                            // the DTM to clear the DMI response
                                            // FIFO.
  .dmi_req_valid_i(dmi_req_valid),
  .dmi_req_ready_o(dmi_req_ready),
  .dmi_req_i(dmi_req),

  .dmi_resp_valid_o(dmi_resp_valid),
  .dmi_resp_ready_i(dmi_resp_ready),
  .dmi_resp_o(dmi_resp_o)
);


  // JTAG TAP
  dmi_jtag #(
    .IdcodeValue ( IdcodeValue )
  ) dap (
    .clk_i            (clk_i        ),
    .rst_ni           (rst_ni       ),
    .testmode_i       (testmode_i   ),
    .test_rst_ni      (1'b1         ),

    .dmi_rst_no       (dmi_rst_n    ),
    .dmi_req_o        (dmi_req      ),
    .dmi_req_valid_o  (dmi_req_valid),
    .dmi_req_ready_i  (dmi_req_ready),

    .dmi_resp_i       (dmi_rsp      ),
    .dmi_resp_ready_o (dmi_rsp_ready),
    .dmi_resp_valid_i (dmi_rsp_valid),

    //JTAG
    .tck_i,
    .tms_i,
    .trst_ni,
    .td_i,
    .td_o,
    .tdo_oe_o ()
  );

assign master_gnt = ~master_busy;
assign master_rerror = master_wb_err_i;

assign master_req_len = 4'h1;  // Single beat
assign master_wb_sel_o = master_be;

/*
 * Host Wishbone backend adapter
 */
wb_backend master_wb_backend (
    .clk(clk_i),
    .rst(~rst_ni),

    .req_valid(master_req_valid),
    .req_addr(master_req_addr),
    .req_len(master_req_len),
    .req_we(master_req_we),
    .req_wdata(master_req_wdata),
    .busy(master_busy),
    .resp_valid(master_resp_valid),
    .resp_rdata(master_resp_rdata),

    .wb_cyc(master_wb_cyc_o),
    .wb_stb(master_wb_stb_o),
    .wb_we(master_wb_we_o),
    .wb_adr(master_wb_adr_o),
    .wb_dat_w(master_wb_dat_w_o),
    .wb_ack(master_wb_ack_i),
    .wb_dat_r(master_wb_dat_r_i),
    .wb_sel(master_wb_sel_o)
    );


assign slave_wb_err_o = 1'b0; // no error for now
assign slave_req_len = 4'h1;

/*
 * Slave Ibex adapter
 */ 
ibex_backend slave_ibex_backend (
    .clk(clk_i),
    .rst(~rst_ni),

    // Wishbone
    .wb_cyc(slave_wb_cyc_i),
    .wb_stb(slave_wb_stb_i),
    .wb_we(slave_wb_we_i),
    .wb_adr(slave_wb_adr_i),
    .wb_dat_w(slave_wb_dat_w_i),
    .wb_ack(slave_wb_ack_o),
    .wb_dat_r(slave_wb_dat_r_o),
    .wb_sel(slave_wb_sel_i),

    // Request
    .req_valid(slave_req_valid),
    .req_addr(slave_req_addr),
    .req_len(slave_req_len),   // up to 16 beats
    .req_we(slave_req_we),
    .req_wdata(slave_req_wdata),
    .req_be(slave_req_be),

    // Response
    .resp_valid(slave_resp_valid),
    .resp_rdata(slave_resp_rdata)
);

endmodule
