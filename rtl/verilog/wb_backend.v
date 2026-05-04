module wb_backend (
    input  wire        clk,
    input  wire        rst,

    // Request
    input  wire        req_valid,
    input  wire [31:0] req_addr,
    input  wire [3:0]  req_len,   // up to 16 beats
    input  wire        req_we,
    input  wire [31:0] req_wdata,

    output wire        busy,

    // Response
    output wire        resp_valid,
    output wire [31:0] resp_rdata,

    // Wishbone
    output wire        wb_cyc,
    output wire        wb_stb,
    output wire        wb_we,
    output wire [31:0] wb_adr,
    output wire [31:0] wb_dat_w,
    input  wire        wb_ack,
    input  wire [31:0] wb_dat_r,
    output reg [3:0]  wb_sel
);

    typedef enum logic [1:0] {
        IDLE,
        RUN,
        DONE
    } state_t;

    state_t state;

    always @(*) begin
        case (wb_adr[1:0])
            2'h0: wb_sel = 4'b1111;
            2'h1: wb_sel = 4'b0010;
            2'h2: wb_sel = 4'b0110;
            2'h3: wb_sel = 4'b1000;
            default: wb_sel = 4'b0000;
        endcase
    end

    reg [3:0] beat_cnt;

    reg cyc, stb, we, busyq, resp_validq;
    reg [31:0] dat_w, addr, resp_rdataq, single_transaction_addr;
    reg req_validq, wb_ackq, single_transaction_busy;

    wire burst_transaction;

    assign burst_transaction = (req_len > 1) & (beat_cnt > 1);

    assign wb_cyc = burst_transaction ? cyc : single_transaction_busy;
    assign wb_stb = burst_transaction ? stb : single_transaction_busy;
    assign wb_we = burst_transaction ? we : req_we;
    assign wb_dat_w = burst_transaction ? dat_w : req_wdata;
    assign wb_adr = burst_transaction ? addr : single_transaction_addr;

    assign busy = burst_transaction ? busyq : single_transaction_busy;
    assign resp_valid = burst_transaction ? resp_validq : wb_ack;
    assign resp_rdata = burst_transaction ? resp_rdataq : wb_dat_r;

    always @(posedge clk) begin
        if (rst) begin
            wb_ackq <= 1'b0;
            req_validq <= 1'b0;
            single_transaction_addr <= 32'h0000_0000;
            single_transaction_busy <= 1'b0;
        end
        else begin
            wb_ackq <= wb_ack;
            req_validq <= req_valid;
            if (req_valid && !single_transaction_busy) begin
                single_transaction_addr <= req_addr;
                single_transaction_busy <= 1'b1;
            end
            if (wb_ack) 
                single_transaction_busy <= 1'b0;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            cyc <= 0;
            stb <= 0;
            busyq <= 0;
        end else begin
            resp_validq <= 0;

            case (state)
            IDLE: begin
                if (req_valid && req_len > 1) begin
                    busyq <= 1;
                    cyc <= 1;
                    stb <= 1;
                    we  <= req_we;

                    addr <= req_addr;
                    dat_w <= req_wdata;
                    beat_cnt <= req_len;

                    state <= RUN;
                end
            end

            RUN: begin
                if (wb_ack) begin
                    resp_rdataq <= wb_dat_r;
                    resp_validq <= 1;

                    beat_cnt <= beat_cnt - 1;

                    if (beat_cnt == 1) begin
                        cyc <= 0;
                        stb <= 0;
                        state <= DONE;
                    end else begin
                        // next beat
                        addr <= addr + 4;
                        stb <= 1; // keep pipeline
                    end
                end
            end

            DONE: begin
                busyq <= 0;
                state <= IDLE;
            end
            endcase
        end
    end

endmodule
