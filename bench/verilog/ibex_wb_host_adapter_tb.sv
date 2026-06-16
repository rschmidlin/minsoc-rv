// SPDX-License-Identifier: Apache-2.0
//
// Self-checking testbench for ibex_wb_host_adapter.
// Covers all nine corner cases from ibex_wb_host_adapter_testbench_architecture.md.
//
// Usage:
//   fusesoc run --target sim ::ibex_wb_adapter:0.1
//   fusesoc run --target sim ::ibex_wb_adapter:0.1 --vcd=wave.vcd

`timescale 1ns/1ps

module ibex_wb_host_adapter_tb;

  vlog_tb_utils vlog_tb_utils0 ();

  // ---------------------------------------------------------------------------
  // Clock and reset
  // ---------------------------------------------------------------------------
  reg clk = 1'b0;
  reg rst = 1'b1;

  always #5 clk = ~clk;

  // ---------------------------------------------------------------------------
  // DUT connections
  // ---------------------------------------------------------------------------
  reg         req_valid;
  reg  [31:0] req_addr;
  reg         req_we;
  reg  [31:0] req_wdata;
  reg  [3:0]  req_be;
  wire        gnt;

  wire        resp_valid;
  wire [31:0] resp_rdata;

  wire        wb_cyc;
  wire        wb_stb;
  wire        wb_we;
  wire [31:0] wb_adr;
  wire [31:0] wb_dat_w;
  reg  [31:0] wb_dat_r;
  reg         wb_ack;
  wire [3:0]  wb_sel;
  wire [2:0]  wb_cti;
  wire [1:0]  wb_bte;

  ibex_wb_host_adapter dut (
    .clk      (clk),
    .rst      (rst),
    .req_valid(req_valid),
    .req_addr (req_addr),
    .req_we   (req_we),
    .req_wdata(req_wdata),
    .req_be   (req_be),
    .gnt      (gnt),
    .resp_valid(resp_valid),
    .resp_rdata(resp_rdata),
    .wb_cyc   (wb_cyc),
    .wb_stb   (wb_stb),
    .wb_we    (wb_we),
    .wb_adr   (wb_adr),
    .wb_dat_w (wb_dat_w),
    .wb_ack   (wb_ack),
    .wb_dat_r (wb_dat_r),
    .wb_sel   (wb_sel),
    .wb_cti   (wb_cti),
    .wb_bte   (wb_bte)
  );

  // ---------------------------------------------------------------------------
  // Memory model helper
  // ---------------------------------------------------------------------------
  function [31:0] mem_data_for_addr(input [31:0] addr);
    mem_data_for_addr = addr ^ 32'h5a5a_1234;
  endfunction

  // ---------------------------------------------------------------------------
  // Scoreboard
  // ---------------------------------------------------------------------------
  reg [31:0] sb_addr  [0:255];
  reg        sb_we    [0:255];
  reg [3:0]  sb_be    [0:255];
  reg [31:0] sb_wdata [0:255];
  integer    sb_wr;
  integer    sb_rd;
  integer    grants_seen;
  integer    responses_seen;
  integer    errors;
  integer    test_no;
  reg [1023:0] testcase_filter;

  // Capture WB write-side signals for write-request checks.
  reg [31:0] cap_wb_dat_w;
  reg [3:0]  cap_wb_sel;
  reg        cap_wb_we;

  always @(posedge clk) begin
    if (wb_cyc && wb_stb) begin
      cap_wb_dat_w <= wb_dat_w;
      cap_wb_sel   <= wb_sel;
      cap_wb_we    <= wb_we;
    end
  end

  // R10: burst-abort protocol assertion.
  // CYC must not deassert directly from a burst beat (CTI=010).
  // The required sequence is: CTI=010 → CYC=1/STB=0/CTI=111 → CYC=0.
  reg        wb_cyc_r;
  reg [2:0]  wb_cti_r;

  always @(posedge clk) begin
    if (rst) begin
      wb_cyc_r <= 1'b0;
      wb_cti_r <= 3'b000;
    end else begin
      if (wb_cyc_r && !wb_cyc && wb_cti_r == 3'b010)
        fail("R10: burst aborted without CYC=1/STB=0/CTI=111 graceful-abort cycle");
      wb_cyc_r <= wb_cyc;
      wb_cti_r <= wb_cti;
    end
  end

  // L1: fifo_fwft full-flag set-latency monitor.
  // The base FIFO's full_o is a combinational function of the registered
  // read/write pointers, so it should appear on the clock edge *after* the
  // write that fills it (1-cycle latency).  This monitor records, each time
  // fifo_full transitions 0->1, whether the most recent filling write was on
  // the immediately preceding posedge (latency 1) or earlier (latency 2).
  reg     full_q;
  reg     fifo_wr_en_q;
  integer fifo_full_set_latency;

  always @(posedge clk) begin
    if (rst) begin
      full_q                <= 1'b0;
      fifo_wr_en_q          <= 1'b0;
      fifo_full_set_latency <= -1;
    end else begin
      if (!full_q && dut.fifo_full)
        fifo_full_set_latency <= fifo_wr_en_q ? 1 : 2;
      full_q       <= dut.fifo_full;
      fifo_wr_en_q <= dut.fifo_wr_en;
    end
  end

  task fail(input [1023:0] msg);
    errors = errors + 1;
    $display("FAIL t=%0t: %0s", $time, msg);
  endtask

  task check(input cond, input [1023:0] msg);
    if (!cond) fail(msg);
  endtask

  always @(posedge clk) begin
    if (!rst) begin
      if (gnt) begin
        sb_addr [sb_wr] = req_addr;
        sb_we   [sb_wr] = req_we;
        sb_be   [sb_wr] = req_be;
        sb_wdata[sb_wr] = req_wdata;
        sb_wr           = sb_wr + 1;
        grants_seen     = grants_seen + 1;
      end

      if (resp_valid) begin
        responses_seen = responses_seen + 1;
        if (responses_seen > grants_seen) begin
          fail("resp_valid without matching prior GNT");
        end else if (!sb_we[sb_rd]) begin
          if (resp_rdata !== mem_data_for_addr(sb_addr[sb_rd])) begin
            $display("  addr %08x  expected %08x  got %08x",
                     sb_addr[sb_rd],
                     mem_data_for_addr(sb_addr[sb_rd]),
                     resp_rdata);
            fail("read response data mismatch");
          end
        end
        sb_rd = sb_rd + 1;
      end

      if (wb_cyc && wb_stb && (wb_bte !== 2'b00))
        fail("wb_bte must be 2'b00 for linear bursts");
    end
  end

  // ---------------------------------------------------------------------------
  // Wishbone slave model
  //
  // slave_adr is the address being tracked for the current burst, updated by
  // the slave itself.  wb_adr is NOT used for burst continuation: the DUT's
  // wb_adr advances via NBA at the same posedge the slave evaluates, so the
  // slave evaluation phase still sees the previous beat's address.
  //
  // ack_beats: -1 = unlimited; N > 0 = N more acks then stop; 0 = stopped.
  // ---------------------------------------------------------------------------
  reg        ack_enable;
  integer    ack_gap;
  integer    ack_countdown;
  integer    ack_beats;
  reg [31:0] slave_adr;
  reg        slave_in_burst;

  always @(posedge clk) begin
    if (rst) begin
      wb_ack         <= 1'b0;
      wb_dat_r       <= 32'h0;
      slave_adr      <= 32'h0;
      slave_in_burst <= 1'b0;
      ack_countdown  <= 0;
    end else begin
      wb_ack <= 1'b0;

      if (!wb_cyc) begin
        slave_in_burst <= 1'b0;
        slave_adr      <= 32'h0;
        ack_countdown  <= 0;
      end else if (wb_stb && ack_enable && (ack_beats != 0)) begin
        if (ack_countdown == 0) begin
          if (!slave_in_burst) begin
            wb_dat_r       <= mem_data_for_addr(wb_adr);
            slave_adr      <= wb_adr;
            slave_in_burst <= (wb_cti == 3'b010);
          end else begin
            wb_dat_r  <= mem_data_for_addr(slave_adr + 32'd4);
            slave_adr <= slave_adr + 32'd4;
            if (wb_cti == 3'b111) slave_in_burst <= 1'b0;
          end
          wb_ack        <= 1'b1;
          ack_countdown <= ack_gap;
          if (ack_beats > 0) ack_beats = ack_beats - 1;
        end else begin
          ack_countdown <= ack_countdown - 1;
        end
      end
    end
  end

  task set_ack_continuous;
    ack_enable    = 1'b1;
    ack_gap       = 0;
    ack_beats     = -1;
    ack_countdown = 0;
  endtask

  task set_ack_waitstates(input integer n);
    ack_enable    = 1'b1;
    ack_gap       = n;
    ack_beats     = -1;
    ack_countdown = 0;
  endtask

  task set_ack_n_beats(input integer n);
    ack_enable    = 1'b1;
    ack_gap       = 0;
    ack_beats     = n;
    ack_countdown = 0;
  endtask

  task stop_ack;
    ack_enable = 1'b0;
  endtask

  // ---------------------------------------------------------------------------
  // Ibex request driver
  // ---------------------------------------------------------------------------

  // Hold request stable until gnt is seen (or timeout).
  // Drives signals with blocking assignments on negedge; samples gnt on posedge.
  task hold_req_until_gnt(
    input [31:0]  addr,
    input         we,
    input [3:0]   be,
    input [31:0]  wdata,
    input integer max_cycles
  );
    integer i;
    begin
      for (i = 0; i < max_cycles; i = i + 1) begin
        @(negedge clk);
        req_valid = 1'b1;
        req_addr  = addr;
        req_we    = we;
        req_be    = be;
        req_wdata = wdata;
        @(posedge clk);
        @(negedge clk);
        if (gnt) begin
          req_valid = 1'b0;
          disable hold_req_until_gnt;
        end
      end
      fail("hold_req_until_gnt: timeout");
      @(negedge clk);
      req_valid = 1'b0;
    end
  endtask

  task issue_read(input [31:0] addr);
    hold_req_until_gnt(addr, 1'b0, 4'hf, 32'h0, 50);
  endtask

  task issue_write(
    input [31:0] addr,
    input [3:0]  be,
    input [31:0] wdata
  );
    hold_req_until_gnt(addr, 1'b1, be, wdata, 50);
  endtask

  // Issue N sequential reads keeping req_valid continuously asserted.
  // The address advances as each grant is seen; the IB FSM stays in ACCEPT
  // (never visits STALL), granting every two cycles.  This fills the FIFO
  // fast enough for the WB FSM to observe multiple sequential entries and
  // open a Wishbone burst.
  task issue_burst_reads(
    input [31:0]  base_addr,
    input integer count,
    input integer max_cycles
  );
    integer   remaining;
    integer   waited;
    reg [31:0] cur_addr;
    begin
      remaining = count;
      waited    = 0;
      cur_addr  = base_addr;
      @(negedge clk);
      req_valid = 1'b1;
      req_we    = 1'b0;
      req_be    = 4'hf;
      req_wdata = 32'h0;
      // The loop drives req_addr and samples gnt from the very first posedge
      // after req_valid is asserted, so every grant — including the first —
      // is observed and counted here. Splitting the first request out into a
      // separate pre-loop step would leave a posedge unobserved by this loop
      // while the global scoreboard still counts it, causing grants_seen to
      // run ahead of remaining/gnt tracking (see C6 for the bug this caused).
      while (remaining > 0 && waited < max_cycles) begin
        req_addr = cur_addr;
        @(posedge clk);
        if (gnt) begin
          remaining = remaining - 1;
          cur_addr  = cur_addr + 32'd4;
        end
        waited = waited + 1;
        @(negedge clk);
      end
      req_valid = 1'b0;
      if (remaining > 0) fail("issue_burst_reads: timeout");
    end
  endtask

  task insert_req_gap(input integer cycles);
    @(negedge clk);
    req_valid = 1'b0;
    repeat (cycles) @(posedge clk);
  endtask

  // ---------------------------------------------------------------------------
  // Test infrastructure
  // ---------------------------------------------------------------------------
  task reset_dut;
    req_valid     = 1'b0;
    req_addr      = 32'h0;
    req_we        = 1'b0;
    req_wdata     = 32'h0;
    req_be        = 4'hf;
    ack_enable    = 1'b0;
    ack_gap       = 0;
    ack_beats     = -1;
    ack_countdown = 0;
    sb_wr         = 0;
    sb_rd         = 0;
    grants_seen   = 0;
    responses_seen = 0;
    rst = 1'b1;
    repeat (5) @(posedge clk);
    rst = 1'b0;
    repeat (2) @(posedge clk);
  endtask

  task start_test(input [1023:0] name);
    test_no = test_no + 1;
    $display("\nTEST %0d: %0s", test_no, name);
    reset_dut();
  endtask

  task wait_responses(input integer n, input integer max_cycles);
    integer i;
    for (i = 0; i < max_cycles; i = i + 1) begin
      @(negedge clk);
      if (responses_seen >= n) disable wait_responses;
    end
    fail("wait_responses: timeout");
  endtask

  task expect_counts(input integer g, input integer r);
    if (grants_seen != g || responses_seen != r)
      $display("  grants=%0d  responses=%0d", grants_seen, responses_seen);
    check(grants_seen   == g, "unexpected grant count");
    check(responses_seen == r, "unexpected response count");
  endtask

  // ---------------------------------------------------------------------------
  // Test scenarios
  // ---------------------------------------------------------------------------

  // C1: Classic single read
  task test_classic_single_read;
    begin
      start_test("C1: classic single read");
      set_ack_continuous();
      issue_read(32'h0000_0100);
      wait_responses(1, 30);
      expect_counts(1, 1);
      check(!wb_cyc, "WB cycle should have completed");
    end
  endtask

  // C2: Classic single write
  task test_classic_single_write;
    begin
      start_test("C2: classic single write with byte enables");
      set_ack_continuous();
      issue_write(32'h0000_1000, 4'b0011, 32'hdead_beef);
      wait_responses(1, 30);
      expect_counts(1, 1);
      check(cap_wb_we    == 1'b1,          "wb_we must be asserted for write");
      check(cap_wb_dat_w == 32'hdead_beef, "wb_dat_w must match req_wdata");
      check(cap_wb_sel   == 4'b0011,       "wb_sel must match req_be");
    end
  endtask

  // C3: Sequential burst, continuous ACK
  task test_burst_continuous_ack;
    begin
      start_test("C3: sequential burst, continuous ACK");
      set_ack_continuous();
      fork
        begin
          issue_burst_reads(32'h0000_0200, 4, 40);
        end
        begin
          wait_responses(4, 120);
        end
      join
      expect_counts(4, 4);
    end
  endtask

  // C4: Sequential burst with WB wait states
  task test_burst_slave_waitstates;
    begin
      start_test("C4: sequential burst with WB wait states");
      set_ack_waitstates(2);
      fork
        begin
          issue_burst_reads(32'h0000_0300, 4, 40);
        end
        begin
          wait_responses(4, 200);
        end
      join
      expect_counts(4, 4);
    end
  endtask

  // C4 regression: resp_valid is a one-cycle pulse; no duplicate during WB gap
  task test_resp_valid_deasserts_between_wb_acks;
    begin
      start_test("C4 regression: resp_valid deasserts between WB acks");
      stop_ack();

      issue_burst_reads(32'h0000_05e8, 2, 20);

      while (!(wb_cyc && wb_stb)) @(posedge clk);

      set_ack_n_beats(1);
      wait_responses(1, 30);
      // resp_valid is 1 at this posedge; must go to 0 on the next.
      @(posedge clk);
      check(resp_valid == 1'b0, "resp_valid stayed high after first response");
      @(posedge clk);
      check(resp_valid == 1'b0, "resp_valid duplicated during WB wait state");

      set_ack_n_beats(1);
      wait_responses(2, 30);
      expect_counts(2, 2);
    end
  endtask

  // C5: Host-side pause (Ibex request gap)
  task test_ibex_req_gap;
    begin
      start_test("C5: host-side pause - no spurious extra response");
      set_ack_continuous();

      issue_read(32'h0000_0400);
      issue_read(32'h0000_0404);

      insert_req_gap(10);
      check(responses_seen <= grants_seen,
            "spurious response during Ibex req gap");

      issue_read(32'h0000_0408);
      wait_responses(3, 80);
      expect_counts(3, 3);
    end
  endtask

  // C6: FIFO full / backpressure
  task test_fifo_full_backpressure;
    integer i;
    integer gnt_count;
    begin
      start_test("C6: FIFO full / backpressure");
      stop_ack();
      gnt_count = 0;

      // Drive sequential reads with req_valid held continuously asserted.
      // req_addr advances only when a grant is seen, so the IB FSM always
      // observes a properly sequential next address and never stalls due to
      // an address gap.  Run for 20 cycles — enough for a depth-4 FIFO to
      // saturate (5 grants × 2 cycles/grant = 10 cycles, plus margin).
      //
      // The loop must see the very first posedge after req_valid is
      // asserted: splitting that first request into a separate step before
      // the loop (as a previous version of this test did) leaves a posedge
      // unobserved by gnt_count while the global scoreboard's grants_seen
      // still counts it, so the FIFO silently accepts one more grant than
      // this task tracks.
      @(negedge clk);
      req_valid = 1'b1;
      req_we    = 1'b0;
      req_be    = 4'hf;
      req_wdata = 32'h0;
      for (i = 0; i < 20; i = i + 1) begin
        req_addr = 32'h0000_0600 + (gnt_count * 4);
        @(posedge clk);
        if (gnt) gnt_count = gnt_count + 1;
        @(negedge clk);
      end
      req_valid = 1'b0;

      // FIFO must be full: gnt stays deasserted for several more cycles.
      repeat (4) @(posedge clk);
      check(gnt == 1'b0,    "gnt must be deasserted when FIFO is full");
      check(gnt_count >= 2, "FIFO must have accepted at least two entries");

      // Drain FIFO.  The scoreboard verifies that responses arrive in grant
      // order and that every resp_rdata matches the corresponding granted address.
      set_ack_continuous();
      wait_responses(gnt_count, 100);
      expect_counts(gnt_count, gnt_count);

      // Granting must resume after the FIFO drains.
      issue_read(32'h0000_0600 + (gnt_count * 4));
      wait_responses(gnt_count + 1, 50);
      expect_counts(gnt_count + 1, gnt_count + 1);
    end
  endtask

  // Supplemental: address break after drained burst (simple variant of C7/C9)
  task test_address_break_after_drained_burst;
    begin
      start_test("address break after drained burst");
      set_ack_continuous();
      fork
        begin issue_burst_reads(32'h0000_0154, 2, 20); end
        begin wait_responses(2, 60); end
      join
      // Non-sequential; FIFO is empty so the DUT grants it immediately.
      issue_read(32'h0000_0084);
      wait_responses(3, 60);
      expect_counts(3, 3);
      check(!wb_cyc, "WB cycle must complete cleanly after break");
    end
  endtask

  // C7: Address break while FIFO non-empty
  task test_address_break_while_fifo_nonempty;
    begin
      start_test("C7: address break while FIFO non-empty");
      stop_ack();
      // Fill FIFO with 0x154 and 0x158; WB cycle starts but stalls (no ack).
      issue_burst_reads(32'h0000_0154, 2, 20);
      // Enable acks so FIFO drains.  Non-sequential 0x084 is held until then.
      set_ack_continuous();
      hold_req_until_gnt(32'h0000_0084, 1'b0, 4'hf, 32'h0, 100);
      wait_responses(3, 100);
      expect_counts(3, 3);
      check(sb_addr[0] == 32'h0000_0154, "first grant: 0x154");
      check(sb_addr[1] == 32'h0000_0158, "second grant: 0x158");
      check(sb_addr[2] == 32'h0000_0084, "third grant: 0x084 after break");
    end
  endtask

  // C8: Address break while Wishbone cycle active
  task test_address_break_while_wb_active;
    begin
      start_test("C8: address break while Wishbone cycle active");
      set_ack_continuous();
      fork
        begin issue_burst_reads(32'h0000_0158, 2, 20); end
        begin @(posedge clk); end  // let burst start before driving break
      join
      // Non-sequential arrives while WB burst is processing 0x158/0x15c.
      // The DUT stalls until the burst completes, then grants 0x084.
      fork
        begin
          hold_req_until_gnt(32'h0000_0084, 1'b0, 4'hf, 32'h0, 100);
        end
        begin
          wait_responses(3, 100);
        end
      join
      expect_counts(3, 3);
      check(sb_addr[2] == 32'h0000_0084,
            "non-seq address must be serviced after WB burst completes");
      check(!wb_cyc, "WB cycle must complete cleanly");
    end
  endtask

  // C9: Address break request must not be swallowed
  // Regression for README bug 4: jump 0x158 → 0x084 lost the 0x084 request.
  task test_address_break_request_retained;
    begin
      start_test("C9: address break request must not be swallowed");
      set_ack_continuous();
      issue_read(32'h0000_0158);
      // Non-sequential 0x084 arrives while 0x158 is in the WB pipeline.
      // The adapter must not discard it.
      hold_req_until_gnt(32'h0000_0084, 1'b0, 4'hf, 32'h0, 100);
      wait_responses(2, 60);
      expect_counts(2, 2);
      check(sb_addr[0] == 32'h0000_0158, "first grant: 0x158");
      check(sb_addr[1] == 32'h0000_0084, "break address must not be swallowed");
    end
  endtask

  // C10: No resp_valid when FIFO empty (phantom response check)
  // Regression for README bug 3: unrequested 0x160 response after 0x15c.
  task test_no_resp_valid_when_fifo_empty;
    begin
      start_test("C10: no resp_valid when FIFO empty");
      set_ack_continuous();
      // Only 0x15c is granted; adapter must not generate a phantom response
      // for the next sequential address 0x160.
      issue_read(32'h0000_015c);
      wait_responses(1, 30);
      repeat (8) @(posedge clk);
      check(resp_valid == 1'b0, "resp_valid must be 0 when no outstanding FIFO entry");
      expect_counts(1, 1);
    end
  endtask

  // C11: First beat of burst must not be cut by sequential-address check
  // Regression for README bugs 1 and 2: fifo_req_addr_q != wb_adr cut the burst
  // after the first beat; the first beat is exempt from the sequential check.
  task test_first_beat_not_cut;
    begin
      start_test("C11: first beat must not be cut by sequential-address check");
      set_ack_continuous();
      // 2-beat burst. If the first-beat cut bug is present, only 1 response arrives.
      fork
        begin issue_burst_reads(32'h0000_0090, 2, 20); end
        begin wait_responses(2, 60); end
      join
      expect_counts(2, 2);
    end
  endtask

  // C12: Later burst beats must be cut if FIFO head is not sequential
  // Regression for README bug 1 (complement): sequential check must work correctly
  // for beats after the first — continuing when sequential, terminating when not.
  task test_later_beats_cut_correctly;
    begin
      start_test("C12: later burst beats cut correctly when FIFO head not sequential");
      set_ack_continuous();
      // 3-beat sequential burst: all three must complete (check continuation).
      fork
        begin issue_burst_reads(32'h0000_0100, 3, 30); end
        begin wait_responses(3, 80); end
      join
      expect_counts(3, 3);
      @(posedge clk);  // wb_cyc NBA from final-beat termination settles here
      check(!wb_stb, "burst must terminate after last sequential beat");
      // Non-sequential follow-up must start a fresh WB cycle.
      issue_read(32'h0000_0200);
      wait_responses(4, 60);
      expect_counts(4, 4);
      check(sb_addr[3] == 32'h0000_0200,
            "non-sequential address must start fresh WB cycle");
    end
  endtask

  // L1: fifo_fwft full-flag latency
  // Requests words until the FIFO reports full (depth-4 base FIFO + 3-stage
  // FWFT output pipeline => 7 outstanding entries before fifo_full; the
  // adapter also pre-reads two while preparing the WB cycle, so ~9 grants).
  //
  // HARD CHECK: fifo_full asserts on the cycle after the filling write
  // (1-cycle SET latency) -- the property the design assumes.
  //
  // EXPERIMENT (reported, not asserted): the user asked to read two words,
  // write one, and see whether fifo_full reacts "next cycle".  It turns out
  // the FWFT output pipeline absorbs the first pop(s) internally before the
  // base FIFO read pointer advances, so fifo_full does NOT clear after only
  // two pops, and reading two then writing one leaves the FIFO non-full.
  // The test measures and prints this FWFT pop-to-clear latency so the real
  // behaviour is visible.
  task test_fifo_full_latency;
    integer fill_grants;
    integer rd_count;
    integer cyc;
    begin
      start_test("L1: fifo_fwft full-flag set latency");
      stop_ack();   // WB side stalls, so granted requests pile up in the FIFO

      // --- Phase 1: fill the FIFO until fifo_full asserts ---
      // Hold req_valid asserted, advancing req_addr per grant, until the base
      // FIFO reports full.  gnt = req_valid & ~fifo_full, so grants stop
      // exactly when fifo_full asserts.
      fill_grants = 0;
      cyc         = 0;
      @(negedge clk);
      req_valid = 1'b1;
      req_we    = 1'b0;
      req_be    = 4'hf;
      req_wdata = 32'h0;
      while (!dut.fifo_full && cyc < 60) begin
        req_addr = 32'h0000_0700 + (fill_grants * 4);
        @(posedge clk);
        if (gnt) fill_grants = fill_grants + 1;
        cyc = cyc + 1;
        @(negedge clk);
      end
      req_valid = 1'b0;

      // fifo_full stays asserted (no pops, no writes), so let the latency
      // monitor register the 0->1 transition it captured during the fill.
      @(posedge clk);
      @(posedge clk);

      check(dut.fifo_full == 1'b1, "L1: FIFO never reached full");
      $display("  L1: fifo_full after %0d grants; measured set latency = %0d cycle(s)",
               fill_grants, fifo_full_set_latency);
      check(fifo_full_set_latency == 1,
            "L1: fifo_full must assert the cycle after the filling write (1-cycle latency)");
      check(gnt == 1'b0, "L1: gnt must be deasserted while FIFO is full");

      // --- Phase 2: pop two words, then keep popping until fifo_full clears ---
      // Re-enable acks so the pending WB cycle advances; each accepted beat
      // pops one FIFO entry (fifo_rd_en high for one cycle).
      rd_count = 0;
      cyc      = 0;
      set_ack_continuous();
      while (rd_count < 2 && cyc < 40) begin
        @(negedge clk);
        if (dut.fifo_rd_en) rd_count = rd_count + 1;
        cyc = cyc + 1;
      end
      check(rd_count == 2, "L1: expected two FIFO reads");
      $display("  L1: after %0d pops fifo_full=%b (FWFT output pipeline absorbs the first pops before the base read pointer advances)",
               rd_count, dut.fifo_full);

      // Keep popping to report the FWFT pop-to-clear latency.
      while (dut.fifo_full && cyc < 40) begin
        @(negedge clk);
        if (dut.fifo_rd_en) rd_count = rd_count + 1;
        cyc = cyc + 1;
      end
      stop_ack();
      check(!dut.fifo_full, "L1: fifo_full never cleared while draining");
      $display("  L1: fifo_full cleared after %0d total pops", rd_count);

      // --- Phase 3: write a single word back and observe full-set latency ---
      @(negedge clk);
      req_valid = 1'b1;
      req_addr  = 32'h0000_07f0;
      req_we    = 1'b0;
      req_be    = 4'hf;
      @(posedge clk);          // single fifo_wr_en here (full is low)
      @(negedge clk);
      req_valid = 1'b0;

      cyc = 0;
      while (!dut.fifo_full && cyc < 5) begin
        @(posedge clk);
        cyc = cyc + 1;
      end
      if (dut.fifo_full)
        $display("  L1: single refill write -> fifo_full re-asserted ~%0d cycle(s) later", cyc);
      else
        $display("  L1: reading two words then writing one leaves fifo_full deasserted (FIFO has free capacity)");

      // Drain so the response path stays consistent for the run as a whole.
      set_ack_continuous();
      repeat (40) @(posedge clk);
    end
  endtask

  // GAP: req_valid dropped to 0 just before the filling grant, then
  // re-asserted.  Verifies no spurious grant during the gap and that fifo_full
  // still asserts exactly one cycle after the (delayed) filling write -- i.e.
  // the 1-cycle set latency is independent of req_valid continuity.
  task test_fifo_full_with_req_gap;
    integer fill_grants;
    integer total_to_full;
    integer cyc;
    begin
      start_test("GAP: req_valid gap before last grant");
      stop_ack();

      // Phase A: discover how many grants are needed to fill (continuous).
      fill_grants = 0;
      cyc         = 0;
      @(negedge clk);
      req_valid = 1'b1; req_we = 1'b0; req_be = 4'hf; req_wdata = 32'h0;
      while (!dut.fifo_full && cyc < 60) begin
        req_addr = 32'h0000_0a00 + (fill_grants * 4);
        @(posedge clk);
        if (gnt) fill_grants = fill_grants + 1;
        cyc = cyc + 1;
        @(negedge clk);
      end
      req_valid = 1'b0;
      total_to_full = fill_grants;
      $display("  GAP: continuous fill needs %0d grants", total_to_full);

      // Phase B: refill, but stop one grant short, insert a req_valid gap,
      // then deliver the final grant.
      reset_dut();
      stop_ack();
      fill_grants = 0;
      cyc         = 0;
      @(negedge clk);
      req_valid = 1'b1; req_we = 1'b0; req_be = 4'hf; req_wdata = 32'h0;
      while (fill_grants < total_to_full - 1 && cyc < 60) begin
        req_addr = 32'h0000_0a00 + (fill_grants * 4);
        @(posedge clk);
        if (gnt) fill_grants = fill_grants + 1;
        cyc = cyc + 1;
        @(negedge clk);
      end
      check(dut.fifo_full == 1'b0, "GAP: must not be full one grant short");

      // Gap: drop req_valid for two cycles; no grant, no full must appear.
      req_valid = 1'b0;
      repeat (2) begin
        @(negedge clk);
        check(gnt == 1'b0,           "GAP: gnt must be 0 while req_valid low");
        check(dut.fifo_full == 1'b0, "GAP: fifo_full must stay 0 during gap");
      end

      // Deliver the final (filling) grant on a single req_valid cycle.
      @(negedge clk);
      req_valid = 1'b1;
      req_addr  = 32'h0000_0a00 + (fill_grants * 4);
      @(posedge clk);                 // filling write sampled here
      check(gnt == 1'b1, "GAP: final grant must be given when req_valid returns");
      @(negedge clk);
      req_valid = 1'b0;
      check(dut.fifo_full == 1'b1, "GAP: fifo_full must be set the cycle after the filling write");

      // Confirm via the latency monitor too (it latches the 0->1 transition
      // one posedge after fifo_full asserts, so allow two edges).
      @(posedge clk);
      @(posedge clk);
      $display("  GAP: measured fifo_full set latency = %0d cycle(s)", fifo_full_set_latency);
      check(fifo_full_set_latency == 1,
            "GAP: 1-cycle set latency must hold despite the req_valid gap");

      set_ack_continuous();
      repeat (40) @(posedge clk);
    end
  endtask

  // P6: no extra fifo_rd_en during FINISH (regression for README bug 6)
  // A sequential burst is followed by a non-sequential request that is held
  // resident in the FIFO while the burst terminates (FSM in FINISH).  README
  // bug 6 was an extra fifo_rd_en at burst end that popped and discarded that
  // trailing request (instruction at 0x648 swallowed).  If that happens the
  // request is granted but never produces a response, so wait_responses below
  // times out.
  task test_finish_no_extra_fifo_rd_en;
    integer granted;
    integer waited;
    reg [31:0] cur;
    begin
      start_test("P6: no extra fifo_rd_en in FINISH (trailing request not swallowed)");
      // Stall the WB side first so all four requests pile up in the FIFO
      // before any of them is serviced.  This guarantees the non-sequential
      // 0x648 is resident in the FIFO when the 0x600/0x604/0x608 burst
      // terminates and the FSM enters FINISH -- exactly the window where the
      // extra fifo_rd_en of README bug 6 would pop and discard 0x648.
      stop_ack();

      // Accumulate 0x600/0x604/0x608 then non-sequential 0x648 (4 grants).
      granted = 0;
      waited  = 0;
      @(negedge clk);
      req_valid = 1'b1;
      req_we    = 1'b0;
      req_be    = 4'hf;
      req_wdata = 32'h0;
      while (granted < 4 && waited < 60) begin
        cur = (granted < 3) ? (32'h0000_0600 + granted * 4) : 32'h0000_0648;
        req_addr = cur;
        @(posedge clk);
        if (gnt) granted = granted + 1;
        waited = waited + 1;
        @(negedge clk);
      end
      req_valid = 1'b0;
      if (granted < 4) fail("P6: not all four requests were granted");

      // Release the WB side: the adapter bursts 0x600/0x604/0x608, then hits
      // the non-sequential 0x648 at the FIFO head and finishes the burst.
      set_ack_continuous();
      wait_responses(4, 120);   // times out if 0x648 was swallowed in FINISH
      expect_counts(4, 4);
      check(sb_addr[0] == 32'h0000_0600, "P6: first grant 0x600");
      check(sb_addr[3] == 32'h0000_0648,
            "P6: trailing non-sequential 0x648 must not be swallowed at burst end");
    end
  endtask

  // C13: fifo_empty in the middle of a burst (no non-sequential terminator)
  //
  // C7/C8 always end a burst with a *real* non-sequential entry, so burst_valid
  // goes false because the live FIFO head is non-contiguous.  Neither test
  // exercises the case where a burst must stop simply because the FIFO ran dry
  // while every queued address was sequential.
  //
  // That is the case this test isolates.  All queued addresses are sequential,
  // so the ONLY reason the burst may terminate is the FIFO becoming empty in the
  // middle of the burst.  The slave acks continuously, so a DUT that keeps
  // bursting whenever burst_valid reads true will over-run the queue and emit a
  // phantom response for an address that was never requested.
  //
  // burst_valid (RTL) is `fifo_req_addr == fifo_req_addr_q + 4`.  When the FWFT
  // FIFO empties, its dout holds the STALE last entry (fifo_fwft_adapter only
  // updates dout_o on a real pop), so burst_valid is a function of stale data
  // once the queue is dry.  The architecture's burst-termination rule (doc §4,
  // R6/R7) requires the burst to stop when no further sequential *stored* request
  // exists -- emptiness, not just a non-contiguous head, must end the burst.
  //
  // Method: stall the slave and pile up a deep run of sequential reads so the WB
  // FSM parks in BURST with several entries queued, then release continuous acks
  // so the whole run drains as ONE long burst from full to empty.  The scoreboard
  // fails on any resp_valid without a matching grant; expect_counts pins exactly
  // one response per granted request.
  task test_fifo_empty_midburst;
    integer granted;
    integer waited;
    begin
      start_test("C13: fifo_empty in the middle of a burst (all addresses sequential)");
      stop_ack();

      // Pile up a deep sequential run while the WB side is stalled.  Grants stop
      // when the FIFO fills; count however many were actually accepted so the
      // test does not depend on the exact FIFO/FWFT depth.
      granted = 0;
      waited  = 0;
      @(negedge clk);
      req_valid = 1'b1;
      req_we    = 1'b0;
      req_be    = 4'hf;
      req_wdata = 32'h0;
      while (granted < 6 && waited < 60) begin
        req_addr = 32'h0000_0800 + granted * 4;   // 0x800, 0x804, 0x808, ...
        @(posedge clk);
        if (gnt) granted = granted + 1;
        waited = waited + 1;
        @(negedge clk);
      end
      req_valid = 1'b0;
      check(granted >= 3, "C13: need at least a 3-deep sequential run to exercise mid-burst empty");

      // Release the WB side: the adapter bursts through the whole sequential run.
      // The burst must terminate when the queue empties -- not continue into a
      // phantom 0x800+granted*4 beat.
      set_ack_continuous();
      wait_responses(granted, 120);   // times out if the burst stalls / loses a beat
      expect_counts(granted, granted);

      // After the queue drains there must be no further response, and the WB
      // cycle must have closed cleanly (R10 graceful-abort is checked globally).
      repeat (8) @(posedge clk);
      check(resp_valid == 1'b0,
            "C13: phantom resp_valid after FIFO emptied mid-burst");
      check(!wb_cyc, "C13: WB cycle must close after the burst drains");
      expect_counts(granted, granted);
      check(sb_addr[0] == 32'h0000_0800, "C13: first grant 0x800");
    end
  endtask

  // ---------------------------------------------------------------------------
  // Top-level
  // ---------------------------------------------------------------------------
  // +testcase=<tag> selects a single test; omitting the plusarg runs all.
  // Tags: C1 C2 C3 C4 C4r C5 C6 supp C7 C8 C9 C10 C11 C12 C13 L1 GAP P6
  // The same plusarg names the VCD file when +vcd is also given (vlog_tb_utils).
  initial begin
    errors  = 0;
    test_no = 0;

    if (!$value$plusargs("testcase=%s", testcase_filter))
      testcase_filter = "";

    if (testcase_filter == "" || testcase_filter == "C1")   test_classic_single_read();
    if (testcase_filter == "" || testcase_filter == "C2")   test_classic_single_write();
    if (testcase_filter == "" || testcase_filter == "C3")   test_burst_continuous_ack();
    if (testcase_filter == "" || testcase_filter == "C4")   test_burst_slave_waitstates();
    if (testcase_filter == "" || testcase_filter == "C4r")  test_resp_valid_deasserts_between_wb_acks();
    if (testcase_filter == "" || testcase_filter == "C5")   test_ibex_req_gap();
    if (testcase_filter == "" || testcase_filter == "C6")   test_fifo_full_backpressure();
    if (testcase_filter == "" || testcase_filter == "supp") test_address_break_after_drained_burst();
    if (testcase_filter == "" || testcase_filter == "C7")   test_address_break_while_fifo_nonempty();
    if (testcase_filter == "" || testcase_filter == "C8")   test_address_break_while_wb_active();
    if (testcase_filter == "" || testcase_filter == "C9")   test_address_break_request_retained();
    if (testcase_filter == "" || testcase_filter == "C10")  test_no_resp_valid_when_fifo_empty();
    if (testcase_filter == "" || testcase_filter == "C11")  test_first_beat_not_cut();
    if (testcase_filter == "" || testcase_filter == "C12")  test_later_beats_cut_correctly();
    if (testcase_filter == "" || testcase_filter == "L1")   test_fifo_full_latency();
    if (testcase_filter == "" || testcase_filter == "GAP")  test_fifo_full_with_req_gap();
    if (testcase_filter == "" || testcase_filter == "C13")  test_fifo_empty_midburst();
    if (testcase_filter == "" || testcase_filter == "P6")   test_finish_no_extra_fifo_rd_en();

    if (errors == 0)
      $display("\nPASS: all ibex_wb_host_adapter tests passed");
    else
      $display("\nFAIL: %0d ibex_wb_host_adapter test errors", errors);
    $finish;
  end

endmodule
