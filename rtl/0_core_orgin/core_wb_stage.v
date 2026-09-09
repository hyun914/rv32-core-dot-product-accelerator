`timescale 1ns/1ps
module core_wb_stage (
    input  [1:0]  mem_to_reg_i,     // 2'b00: ALU, 2'b01: MEM, 2'b10: PC+4
    input  [31:0] dmem_rd_data_i,
    input  [31:0] alu_result_i,
    input  [31:0] pc_plus_4_i,
    input  [31:0] imm_i,            // 호환용, 미사용
    output reg [31:0] rd_din_o
);
always @(*) begin
    case (mem_to_reg_i)
        2'b00: rd_din_o = alu_result_i;     // ALU
        2'b01,
        2'b11: rd_din_o = dmem_rd_data_i;   // ★ MEM (인코딩 호환)
        2'b10: rd_din_o = pc_plus_4_i;      // PC+4
        default: rd_din_o = alu_result_i;   // 안전 기본값
    endcase
end
endmodule
