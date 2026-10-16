`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// dot_product_pipe — 4-multiplier time-multiplexed dot product accelerator.
//
// Interface IDENTICAL to dot_product.v (drop-in compatible at port level), but:
//   - Only 4 INT8 multipliers internally (vs 8 in the baseline)
//   - DOTPROD is broken into two phases (LO half / HI half) using a 1-bit fold_idx
//     register; SW must issue compute_en_i TWICE in a row to retire one full
//     8-element dot product.
//
// SW pattern (test_accel_pipe.S):
//     DOTPROD x0 , x0, x0   ; first compute_en pulse -> fold_idx 0 -> 1 (no rd)
//     DOTPROD x14, x0, x0   ; second compute_en pulse -> fold_idx 1 -> 0 (result -> x14)
//
// Trade-off vs 8-mul baseline:
//   + ~50% multiplier hardware
//   + Adder tree is 4-input instead of 8-input (shorter critical path)
//   - +1 cycle DOTPROD overhead at the SW level (19 cycles vs 18)
// -----------------------------------------------------------------------------

module dot_product_4mul (
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

    reg               fold_idx;        // 0: next compute is LO half, 1: HI half
    reg signed [17:0] partial_sum;  // captured at end of LO compute
    reg signed [18:0] result_r;     // captured at end of HI compute

    // 4 multipliers, operands selected by current fold_idx.
    wire signed [7:0] a_sel [0:3];
    wire signed [7:0] b_sel [0:3];
    assign a_sel[0] = fold_idx ? buf_a[4] : buf_a[0];
    assign a_sel[1] = fold_idx ? buf_a[5] : buf_a[1];
    assign a_sel[2] = fold_idx ? buf_a[6] : buf_a[2];
    assign a_sel[3] = fold_idx ? buf_a[7] : buf_a[3];
    assign b_sel[0] = fold_idx ? buf_b[4] : buf_b[0];
    assign b_sel[1] = fold_idx ? buf_b[5] : buf_b[1];
    assign b_sel[2] = fold_idx ? buf_b[6] : buf_b[2];
    assign b_sel[3] = fold_idx ? buf_b[7] : buf_b[3];

    wire signed [15:0] mul_res [0:3];
    genvar j;
    generate
        for (j = 0; j < 4; j = j + 1) begin : mult_gen
            assign mul_res[j] = a_sel[j] * b_sel[j];
        end
    endgenerate

    wire signed [16:0] add_l1_0 = mul_res[0] + mul_res[1]; // tight optimiation
    wire signed [16:0] add_l1_1 = mul_res[2] + mul_res[3];
    wire signed [17:0] half_sum = add_l1_0 + add_l1_1;

    // On HI compute the combinational final_sum is (partial_sum + half_sum).
    wire signed [18:0] final_sum = $signed({partial_sum[17], partial_sum}) + $signed({half_sum[17], half_sum});

    // Result is combinationally valid only during a HI-fold_idx compute pulse.
    // Otherwise expose the latched result_r (matches dot_product.v semantics).
    assign result_o = (compute_en_i && fold_idx) ? $signed(final_sum) : result_r;

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1) begin
                buf_a[i] <= 8'sd0;
                buf_b[i] <= 8'sd0;
            end
            fold_idx       <= 1'b0;
            partial_sum <= 18'sd0; // 18 bit
            result_r    <= 19'sd0; // 19 bit
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
                if (fold_idx == 1'b0) begin
                    partial_sum <= half_sum;
                    fold_idx       <= 1'b1;
                end else begin
                    result_r    <= final_sum;
                    fold_idx       <= 1'b0;
                end
            end
        end
    end

endmodule
