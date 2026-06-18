module ibex_wb_adapter_preload_buffer #(
    parameter DATA_WIDTH = 32
)
(
    // FIFO interface
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] fifo_dout,
    input wire fifo_empty,

    output reg rd_en,

    // Adapter interface
    output reg slot0_valid,
    output reg [DATA_WIDTH-1:0] slot0_data,
    input wire slot0_pop,

    output reg slot1_valid,
    output reg [DATA_WIDTH-1:0] slot1_data,
    
    output reg slot2_valid,
    output reg [DATA_WIDTH-1:0] slot2_data
);
/*
reg read, late_read;

assign rd_en = (read & !slot0_pop) || late_read;
*/

reg slot0_pop_q;

always @(posedge clk) begin
    if (rst) begin
        rd_en <= 1'b0;      
    end
    else begin
        slot0_pop_q <= slot0_pop;
        rd_en <= 1'b0;
        if (!fifo_empty && (!slot1_valid || slot0_pop)) begin
            rd_en <= 1'b1;
        end
    end
end

always @(posedge clk) begin
    if (rst) begin
        slot0_valid <= 1'b0;
        slot0_data <= 'h0;

        slot1_valid <= 1'b0;
        slot1_data <= 'h0;

        slot2_valid <= 1'b0;
        slot2_data <= 'h0;
    end
    else begin
        if (slot0_pop && rd_en && !fifo_empty) begin
            slot2_valid <= 1'b0;
            slot2_data <= 'h0;

            if (slot1_valid) begin
                slot1_valid <= 1'b1;
                slot1_data <= fifo_dout;
                slot0_data <= slot1_data;
                slot0_valid <= slot1_valid;
            end
            else begin
                slot1_valid <= 1'b0;
                slot1_data <= 'h0;
                
                slot0_valid <= 1'b1;
                slot0_data <= fifo_dout;
            end
        end
        else begin
            if (slot0_pop) begin
                slot2_valid <= 1'b0;
                slot2_data <= 'h0;
                
                slot1_valid <= slot2_valid;
                slot1_data <= slot2_data;
                
                slot0_valid <= slot1_valid;
                // Keep last valid data in slot 0 data
                if (slot1_valid) 
                    slot0_data <= slot1_data;
            end
            if (rd_en && !fifo_empty) begin
                if (!slot0_valid) begin
                    slot0_valid <= 1'b1;
                    slot0_data <= fifo_dout;
                end
                else if (!slot1_valid) begin
                    slot1_valid <= 1'b1;
                    slot1_data <= fifo_dout;
                end
                else if (!slot2_valid) begin
                    slot2_valid <= 1'b1;
                    slot2_data <= fifo_dout;
                end
            end
        end
    end
end

endmodule