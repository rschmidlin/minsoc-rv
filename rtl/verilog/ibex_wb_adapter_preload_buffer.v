module ibex_wb_adapter_preload_buffer #(
    parameter DATA_WIDTH = 32
)
(
    // FIFO interface
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] fifo_dout,
    input wire fifo_empty,

    output wire rd_en,

    // Adapter interface
    output reg slot0_valid,
    output reg [DATA_WIDTH-1:0] slot0_data,
    input wire slot0_pop,

    output reg slot1_valid,
    output reg [DATA_WIDTH-1:0] slot1_data,
    
    output reg slot2_valid,
    output reg [DATA_WIDTH-1:0] slot2_data
);

reg read, late_read;

assign rd_en = (read & !slot0_pop) || late_read;

always @(posedge clk) begin
    if (rst) begin
        read <= 1'b0;

        slot0_valid <= 1'b0;
        slot0_data <= 'h0;

        slot1_valid <= 1'b0;
        slot1_data <= 'h0;

        slot2_valid <= 1'b0;
        slot2_data <= 'h0;

        late_read <= 1'b0;
        read <= 1'b0;
    end
    else begin
        late_read <= 1'b0;
        if (!fifo_empty && !slot2_valid) begin
            read <= 1'b1;
        end
        else begin
            read <= 1'b0;
        end
        if (slot0_pop) begin
            slot2_valid <= 1'b0;
            slot2_data <= 'h0;

            slot1_valid <= slot2_valid;
            slot1_data <= slot2_data;

            slot0_data <= slot1_data;
            slot0_valid <= slot1_valid;

            late_read <= read;
        end
        else if (read || late_read) begin
            slot2_data <= fifo_dout;
            slot2_valid <= 1'b1;
            
            if (!slot1_valid) begin
                slot1_data <= slot2_data;
                slot1_valid <= slot2_valid;
            end
                
            if (!slot0_valid) begin
                slot0_data <= slot1_data;
                slot0_valid <= slot1_valid;
            end
        end
        else begin
            if (slot2_valid && !slot1_valid) begin
                slot2_valid <= 1'b0;
                slot2_data <= 'h0;
                
                slot1_data <= slot2_data;
                slot1_valid <= slot2_valid;
            end

            if (slot1_valid && !slot0_valid) begin
                slot2_valid <= 1'b0;
                slot2_data <= 'h0;
                
                slot1_valid <= slot2_valid;
                slot1_data <= slot2_data;
                
                slot0_data <= slot1_data;
                slot0_valid <= slot1_valid;
            end
        end
    end
end

endmodule