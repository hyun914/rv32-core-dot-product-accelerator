`timescale 1ns/1ps

module core_ex_stage (
    input        clk_i,
    input        rst_ni,
    input  [6:0] opcode_i,
    input  [2:0] funct3_i,
    input  [6:0] funct7_i,
    input  [31:0] rs1_dout_i,
    input  [31:0] rs2_dout_i,
    input  [31:0] imm_i,
    input  [31:0] pc_i,
    output reg [31:0] alu_result_o
);
    reg [3:0]  alu_op;
    reg [31:0] alu_in1, alu_in2;

    // ALU Control
    always @(*) begin
        alu_op = 4'b0000; // default ADD
        case (opcode_i)
            7'b0110011: begin // R-type
                case (funct3_i)
                    3'b000: alu_op = (funct7_i == 7'b0100000) ? 4'b0011 : 4'b0000; // SUB/ADD
                    3'b001: alu_op = 4'b0100; // SLL
                    3'b010: alu_op = 4'b0101; // SLT
                    3'b011: alu_op = 4'b0110; // SLTU
                    3'b100: alu_op = 4'b0010; // XOR
                    3'b101: alu_op = (funct7_i == 7'b0100000) ? 4'b0111 : 4'b1000; // SRA/SRL
                    3'b110: alu_op = 4'b0001; // OR
                    3'b111: alu_op = 4'b1001; // AND
                    default: alu_op = 4'b0000;
                endcase
            end
            7'b0010011: begin // I-type (ADDI...)
                case (funct3_i)
                    3'b000: alu_op = 4'b0000;
                    3'b010: alu_op = 4'b0101; // SLTI
                    3'b011: alu_op = 4'b0110;
                    3'b100: alu_op = 4'b0010;
                    3'b110: alu_op = 4'b0001;
                    3'b111: alu_op = 4'b1001;
                    3'b001: alu_op = 4'b0100;
                    3'b101: alu_op = (funct7_i == 7'b0100000) ? 4'b0111 : 4'b1000;
                    default: alu_op = 4'b0000;
                endcase
            end
            // BRANCH (필수!)
            7'b1100011: begin
                case (funct3_i)
                    3'b000, 3'b001: alu_op = 4'b0011; // BEQ, BNE -> SUB
                    3'b100, 3'b101: alu_op = 4'b0101; // BLT, BGE -> SLT
                    default: alu_op = 4'b0011;
                endcase
            end
            7'b0110111: alu_op = 4'b1010; // LUI
            default: alu_op = 4'b0000;
        endcase
    end

    // ALU Mux
    always @(*) begin
        alu_in1 = rs1_dout_i;
        alu_in2 = rs2_dout_i;
        case (opcode_i)
            7'b0010011, 7'b0000011, 7'b0100011, 7'b1100111: alu_in2 = imm_i; // I, Load, Store, JALR
            7'b0110111: begin alu_in1 = 32'b0; alu_in2 = imm_i; end // LUI
            7'b0010111: begin alu_in1 = pc_i; alu_in2 = imm_i; end // AUIPC
            default: ;
        endcase
    end

    // ALU Op
    always @(*) begin
        case (alu_op)
            4'b0000: alu_result_o = alu_in1 + alu_in2;
            4'b0001: alu_result_o = alu_in1 | alu_in2;
            4'b0010: alu_result_o = alu_in1 ^ alu_in2;
            4'b0011: alu_result_o = alu_in1 - alu_in2;
            4'b0100: alu_result_o = alu_in1 << alu_in2[4:0];
            4'b0101: alu_result_o = ($signed(alu_in1) < $signed(alu_in2)) ? 32'd1 : 32'd0;
            4'b0110: alu_result_o = (alu_in1 < alu_in2) ? 32'd1 : 32'd0;
            4'b0111: alu_result_o = $signed(alu_in1) >>> alu_in2[4:0];
            4'b1000: alu_result_o = alu_in1 >> alu_in2[4:0];
            4'b1001: alu_result_o = alu_in1 & alu_in2;
            4'b1010: alu_result_o = alu_in2; // LUI Pass
            default: alu_result_o = 32'b0;
        endcase
    end
endmodule