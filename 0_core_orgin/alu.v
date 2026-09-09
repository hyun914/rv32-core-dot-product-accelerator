module alu (
    input         clk_i,
    input         rst_ni,
    input  [31:0] in1_i,
    input  [31:0] in2_i,
    input  [3:0]  ctrl_i,
    output reg [31:0] result_o,
    output reg        zero_o
);

always @(*) begin
    case (ctrl_i)
        4'b0000: result_o = in1_i + in2_i;                     // ADD
        4'b0001: result_o = in1_i & in2_i;                     // AND
        4'b0010: result_o = in1_i | in2_i;                     // OR
        4'b0011: result_o = in1_i ^ in2_i;                     // XOR
        4'b0100: result_o = in1_i << in2_i[4:0];                    // SLL
        4'b0101: result_o = in1_i >> in2_i[4:0];                    // SRL
        4'b0110: result_o = $signed(in1_i) >>> in2_i[4:0];                   // SRA
        4'b0111: result_o = in1_i - in2_i;                     // SUB
        4'b1000: result_o = (in1_i < in2_i) ? 32'd1 : 32'd0;   // SLTU
        4'b1001: result_o = ($signed(in1_i) < $signed(in2_i)) ? 32'd1 : 32'd0;                  // SLT
        default: result_o = 32'd0;
    endcase

    zero_o = (result_o == 0);
end

endmodule
