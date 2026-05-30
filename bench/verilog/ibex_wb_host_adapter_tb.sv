// SPDX-License-Identifier: Apache-2.0
//
// Self-checking testbench for ibex_wb_host_adapter.
// Focuses on Ibex request/grant ordering versus Wishbone ACK/response ordering.
//

`timescale 1ns/1ps

module ibex_wb_host_adapter_tb;
  reg clk = 1'b0;
  reg rst = 1'b1;

  always #5 clk = ~clk;

  // Ibex-like request side
  reg         req_valid;
  reg  [31:0] req_addr;
  reg  [3:0]  req_len;
  reg         req_we;
  reg  [31:0] req_wdata;
  reg  [3:0]  req_be;
  wire        gnt;

  // Ibex-like response side
  wire        resp_valid;
  wire [31:0] resp_rdata;

  // Wishbone side
  wire        wb_cyc;
  wire        wb_stb;
  wire        wb_we;
  wire [31:0] wb_adr;
  wire [31:0] wb_dat_w;
  reg         wb_ack;
  reg  [31:0] wb_dat_r;
  wire [3:0]  wb_sel;
  wire [2:0]  wb_cti;
  wire [1:0]  wb_bte;

  ibex_wb_host_adapter dut (
    .clk(clk),
    .rst(rst),
    .req_valid(req_valid),
    .req_addr(req_addr),
    .req_len(req_len),
    .req_we(req_we),
    .req_wdata(req_wdata),
    .req_be(req_be),
    .gnt(gnt),
    .resp_valid(resp_valid),
    .resp_rdata(resp_rdata),
    .wb_cyc(wb_cyc),
    .wb_stb(wb_stb),
    .wb_we(wb_we),
    .wb_adr(wb_adr),
    .wb_dat_w(wb_dat_w),
    .wb_ack(wb_ack),
    .wb_dat_r(wb_dat_r),
    .wb_sel(wb_sel),
    .wb_cti(wb_cti),
    .wb_bte(wb_bte)
  );

  integer errors = 0;
  integer test_no = 0;

  // Scoreboard: every GNT creates exactly one expected response.
  reg [31:0] granted_addr [0:255];
  integer grant_wr;
  integer resp_rd;
  integer grants_seen;
  integer responses_seen;

  function [31:0] mem_data_for_addr(input [31:0] addr);
    mem_data_for_addr = addr ^ 32'h5a5a_1234;
  endfunction

  task fail(input [1023:0] msg);
    begin
      errors = errors + 1;
      $display("FAIL t=%0t: %0s", $time, msg);
    end
  endtask

  task check(input cond, input [1023:0] msg);
    begin
      if (!cond) fail(msg);
    end
  endtask

  task reset_dut;
    begin
      req_valid = 1'b0;
      req_addr  = 32'h0;
      req_len   = 4'd1;
      req_we    = 1'b0;
      req_wdata = 32'h0;
      req_be    = 4'hf;
      wb_ack    = 1'b0;
      wb_dat_r  = 32'h0;
      grant_wr = 0;
      resp_rd = 0;
      grants_seen = 0;
      responses_seen = 0;
      rst = 1'b1;
      repeat (5) @(posedge clk);
      rst = 1'b0;
      repeat (2) @(posedge clk);
    end
  endtask

  task start_test(input [1023:0] name);
    begin
      test_no = test_no + 1;
      $display("\nTEST %0d: %0s", test_no, name);
      reset_dut();
    end
  endtask

  // One-cycle request pulse helper. The address must be held stable until GNT.
  task request_until_grant(
    input [31:0] addr,
    input [3:0]  len,
    input        we,
    input [31:0] wdata,
    input [3:0]  be,
    input integer max_cycles
  );
    integer i;
    begin
      req_addr  <= addr;
      req_len   <= len;
      req_we    <= we;
      req_wdata <= wdata;
      req_be    <= be;
      req_valid <= 1'b1;

      for (i = 0; i < max_cycles; i = i + 1) begin
        @(posedge clk);
        if (gnt) begin
          req_valid <= 1'b0;
          @(posedge clk);
          disable request_until_grant;
        end
      end
      fail("request_until_grant timeout");
      req_valid <= 1'b0;
    end
  endtask

  // Present a request for one cycle only. Used for withdrawn/nonincremental corner cases.
  task request_one_cycle(
    input [31:0] addr,
    input [3:0]  len,
    input        we,
    input [31:0] wdata,
    input [3:0]  be
  );
    begin
      req_addr  <= addr;
      req_len   <= len;
      req_we    <= we;
      req_wdata <= wdata;
      req_be    <= be;
      req_valid <= 1'b1;
      @(posedge clk);
      req_valid <= 1'b0;
    end
  endtask

  // Wishbone memory model: manually controlled ACK pattern.
  // If ack_enable is high, ACK is generated whenever CYC && STB and the down-counter reaches zero.
  reg ack_enable;
  integer ack_gap;
  integer ack_countdown;

  always @(posedge clk) begin
    if (rst) begin
      wb_ack <= 1'b0;
      wb_dat_r <= 32'h0;
      ack_countdown <= 0;
    end else begin
      wb_ack <= 1'b0;
      if (ack_enable && wb_cyc && wb_stb) begin
        if (ack_countdown == 0) begin
          wb_ack <= 1'b1;
          wb_dat_r <= mem_data_for_addr(wb_adr);
          ack_countdown <= ack_gap;
        end else begin
          ack_countdown <= ack_countdown - 1;
        end
      end
    end
  end

  task set_ack_pattern(input integer gap);
    begin
      ack_enable = 1'b1;
      ack_gap = gap;
      ack_countdown = 0;
    end
  endtask

  task stop_ack;
    begin
      ack_enable = 1'b0;
      wb_ack = 1'b0;
    end
  endtask

  // Scoreboard bookkeeping.
  always @(posedge clk) begin
    if (!rst) begin
      if (gnt) begin
        granted_addr[grant_wr] = req_addr;
        grant_wr = grant_wr + 1;
        grants_seen = grants_seen + 1;
      end

      if (resp_valid) begin
        responses_seen = responses_seen + 1;
        if (responses_seen > grants_seen) begin
          fail("resp_valid without matching prior GNT");
        end else begin
          if (resp_rdata !== mem_data_for_addr(granted_addr[resp_rd])) begin
            $display("Expected response for granted addr %08x = %08x, got %08x",
                     granted_addr[resp_rd], mem_data_for_addr(granted_addr[resp_rd]), resp_rdata);
            fail("response data does not match oldest granted address");
          end
          resp_rd = resp_rd + 1;
        end
      end

      if (wb_cyc && wb_stb && (wb_bte !== 2'b00)) begin
        fail("wb_bte must be 2'b00 for linear bursts");
      end
    end
  end

  task wait_responses(input integer n, input integer max_cycles);
    integer i;
    begin
      for (i = 0; i < max_cycles; i = i + 1) begin
        @(posedge clk);
        if (responses_seen >= n) disable wait_responses;
      end
      fail("wait_responses timeout");
    end
  endtask

  task expect_counts(input integer g, input integer r);
    begin
      check(grants_seen == g, "unexpected number of grants");
      check(responses_seen == r, "unexpected number of responses");
    end
  endtask

  // --------------------------------------------------------------------------
  // Tests
  // --------------------------------------------------------------------------

  task test_classic_single_read;
    begin
      start_test("classic single read, req_len=1, CTI classic");
      set_ack_pattern(0);
      request_until_grant(32'h0000_0100, 4'd1, 1'b0, 32'h0, 4'hf, 20);
      wait_responses(1, 30);
      expect_counts(1, 1);
      check(!wb_cyc, "classic transfer should finish");
    end
  endtask

  task test_burst_continuous_ack;
    begin
      start_test("incrementing burst, continuous ACK");
      set_ack_pattern(0);

      fork
        begin
          request_until_grant(32'h0000_0200, 4'd4, 1'b0, 32'h0, 4'hf, 20);
          request_until_grant(32'h0000_0204, 4'd4, 1'b0, 32'h0, 4'hf, 20);
          request_until_grant(32'h0000_0208, 4'd4, 1'b0, 32'h0, 4'hf, 40);
          request_until_grant(32'h0000_020c, 4'd4, 1'b0, 32'h0, 4'hf, 40);
        end
        begin
          wait_responses(4, 120);
        end
      join
      expect_counts(4, 4);
    end
  endtask

  task test_burst_slave_waitstates;
    begin
      start_test("incrementing burst with Wishbone slave wait states");
      set_ack_pattern(2); // two cycles between ACK pulses

      fork
        begin
          request_until_grant(32'h0000_0300, 4'd4, 1'b0, 32'h0, 4'hf, 20);
          request_until_grant(32'h0000_0304, 4'd4, 1'b0, 32'h0, 4'hf, 40);
          request_until_grant(32'h0000_0308, 4'd4, 1'b0, 32'h0, 4'hf, 60);
          request_until_grant(32'h0000_030c, 4'd4, 1'b0, 32'h0, 4'hf, 60);
        end
        begin
          wait_responses(4, 200);
        end
      join
      expect_counts(4, 4);
    end
  endtask

  task test_req_gap_host_waitstate;
    begin
      start_test("Ibex/request side gap: no spurious second response");
      set_ack_pattern(0);

      // This is the corner case seen in the failing UART/interrupt trace:
      // req_len says a 2-beat burst is possible, but only one request is granted.
      request_until_grant(32'h0000_05a4, 4'd2, 1'b0, 32'h0, 4'hf, 20);

      // Withdraw request for several cycles. The adapter must not produce beat 2.
      req_valid <= 1'b0;
      repeat (12) @(posedge clk);

      expect_counts(1, 1);
      check(responses_seen <= grants_seen, "responses exceeded grants after request gap");

      // Now present the next sequential request. Adapter should resume, not stay stuck.
      request_until_grant(32'h0000_05a8, 4'd2, 1'b0, 32'h0, 4'hf, 40);
      wait_responses(2, 80);
      expect_counts(2, 2);
    end
  endtask

  task test_nonincremental_branch_restart;
    begin
      start_test("non-incremental fetch/branch restart does not misattribute stale response");
      set_ack_pattern(1);

      // Accept one or two sequential old-path requests.
      request_until_grant(32'h0000_0080, 4'd4, 1'b0, 32'h0, 4'hf, 20);
      request_until_grant(32'h0000_0084, 4'd4, 1'b0, 32'h0, 4'hf, 20);

      // Branch target appears. It must not be granted as continuation of 0x84.
      req_addr  <= 32'h0000_00e0;
      req_len   <= 4'd4;
      req_we    <= 1'b0;
      req_wdata <= 32'h0;
      req_be    <= 4'hf;
      req_valid <= 1'b1;

      repeat (5) @(posedge clk);
      // It is OK if the adapter is still draining old grants, but it must not have returned
      // a response for an ungranted target.
      check(responses_seen <= grants_seen, "branch restart produced ungranted response");

      // Keep target valid until it is eventually granted.
      while (!gnt) @(posedge clk);
      @(posedge clk);
      req_valid <= 1'b0;

      wait_responses(3, 120);
      expect_counts(3, 3);
      check(granted_addr[2] == 32'h0000_00e0, "branch target should be the third granted request");
    end
  endtask

  task test_write_classic;
    begin
      start_test("classic write with byte enables");
      set_ack_pattern(0);
      request_until_grant(32'h0000_1000, 4'd1, 1'b1, 32'hdead_beef, 4'b0011, 20);
      wait_responses(1, 30);
      expect_counts(1, 1);
      // For writes the adapter still returns a response pulse; the memory data value is not
      // meaningful architecturally, but the scoreboard uses wb_adr-derived data from this TB.
      check(wb_sel == 4'b0011 || !wb_cyc, "write byte-enable should be passed to Wishbone");
    end
  endtask



  task test_resp_valid_deasserts_between_wb_acks;
    begin
      start_test("resp_valid is a one-cycle pulse; no duplicate response during WB wait state");

      // Manual ACK control. This recreates the interrupt/UART failure class:
      // first beat is acknowledged, then the slave inserts wait states before the
      // next ACK. resp_valid must not remain high during that gap, otherwise Ibex
      // may consume the same/old fetch response twice and lose halfword alignment.
      stop_ack();

      fork
        begin
          request_until_grant(32'h0000_05e8, 4'd2, 1'b0, 32'h0, 4'hf, 30);
          request_until_grant(32'h0000_05ec, 4'd2, 1'b0, 32'h0, 4'hf, 30);
        end
        begin
          // Wait for active WB transaction.
          while (!(wb_cyc && wb_stb)) @(posedge clk);

          // First ACK.
          @(posedge clk);
          wb_dat_r <= mem_data_for_addr(wb_adr);
          wb_ack   <= 1'b1;
          @(posedge clk);
          wb_ack   <= 1'b0;

          // Give the DUT one cycle to emit resp_valid for the first ACK.
          @(posedge clk);
          check(resp_valid == 1'b1, "expected resp_valid pulse after first ACK");

          // Now insert a gap before the second ACK. During this whole gap,
          // resp_valid must be low. This is the explicit regression check.
          @(posedge clk);
          check(resp_valid == 1'b0, "resp_valid stayed high after first response");
          @(posedge clk);
          check(resp_valid == 1'b0, "resp_valid duplicated response during WB wait state");

          // Second ACK.
          wb_dat_r <= mem_data_for_addr(wb_adr);
          wb_ack   <= 1'b1;
          @(posedge clk);
          wb_ack   <= 1'b0;
        end
      join

      wait_responses(2, 60);
      expect_counts(2, 2);
    end
  endtask

  initial begin
    $dumpfile("ibex_wb_host_adapter_tb.vcd");
    $dumpvars(0, ibex_wb_host_adapter_tb);

    ack_enable = 1'b0;
    ack_gap = 0;
    ack_countdown = 0;

    test_classic_single_read();
    test_burst_continuous_ack();
    test_burst_slave_waitstates();
    test_req_gap_host_waitstate();
    test_resp_valid_deasserts_between_wb_acks();
    test_nonincremental_branch_restart();
    test_write_classic();

    if (errors == 0) begin
      $display("\nPASS: all ibex_wb_host_adapter tests passed");
    end else begin
      $display("\nFAIL: %0d ibex_wb_host_adapter test errors", errors);
    end
    $finish;
  end

endmodule
