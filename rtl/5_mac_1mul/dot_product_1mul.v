`timescale 1ns/1ps

module dot_product_1mul (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [31:0] data_i,
    input  wire        load_a_en_i,
    input  wire        load_b_en_i,
    input  wire        load_idx_i,
    input  wire        compute_en_i,
    output wire [31:0] result_o
);

    reg signed [7:0]  buf_a [0:7];
    reg signed [7:0]  buf_b [0:7];

    reg [2:0]         fold_idx;
    reg signed [19:0] partial_sum;
    reg signed [31:0]        result_r;
    integer i;

    wire signed [7:0] a_sel;
    wire signed [7:0] b_sel;
    assign a_sel = buf_a[fold_idx]; // MUX#1
    assign b_sel = buf_b[fold_idx];

    wire signed [15:0] product = a_sel * b_sel;

    wire signed [19:0] final_sum = partial_sum + product;
    
    wire signed [19:0] partial_sum_w = (fold_idx == 3'd0) ? product : final_sum; // mux#2
    
    assign result_o = ((fold_idx == 3'b111) && (compute_en_i == 1'b1)) ? $signed(final_sum) : result_r; //mux#3

    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i=0; i<8; i = i + 1) begin
                buf_a[i] <= 8'sd0;
                buf_b[i] <= 8'sd0;
            end
            fold_idx     <= 3'b000;
            partial_sum  <= 20'sd0;
            result_r     <= 32'sd0;
        end else begin
            if (load_a_en_i) begin
                if (load_idx_i == 1'b0) begin
                    buf_a[0] <= data_i[7:0];
                    buf_a[1] <= data_i[15:8];
                    buf_a[2] <= data_i[23:16];
                    buf_a[3] <= data_i[31:24];
                end else begin
                    buf_a[4] <= data_i[7:0];
                    buf_a[5] <= data_i[15:8];
                    buf_a[6] <= data_i[23:16];
                    buf_a[7] <= data_i[31:24];
                end
            end
            if (load_b_en_i) begin
                if (load_idx_i == 1'b0) begin
                    buf_b[0] <= data_i[7:0];
                    buf_b[1] <= data_i[15:8];
                    buf_b[2] <= data_i[23:16];
                    buf_b[3] <= data_i[31:24];
                end else begin
                    buf_b[4] <= data_i[7:0];
                    buf_b[5] <= data_i[15:8];
                    buf_b[6] <= data_i[23:16];
                    buf_b[7] <= data_i[31:24];
                end
            end
            if (compute_en_i) begin
                partial_sum <= partial_sum_w;
                if(fold_idx == 3'd7) begin
                    result_r <= final_sum;
                    fold_idx <= 3'd0;
                end else begin
                    fold_idx <= fold_idx + 1'b1;
                end
            end
        end
    end
endmodule