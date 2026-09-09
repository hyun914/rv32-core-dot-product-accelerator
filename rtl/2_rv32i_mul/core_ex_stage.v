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
    reg [31:0] std_alu_result;

    // ==========================================
    // 1. 가속기 (Dot-Product) 제어 신호 디코딩
    // ==========================================
    wire is_custom_op = (opcode_i == 7'b0001011);

    wire accel_load_a_en = is_custom_op & ((funct3_i == 3'b000) | (funct3_i == 3'b001));
    wire accel_load_b_en = is_custom_op & ((funct3_i == 3'b010) | (funct3_i == 3'b011));
    wire accel_load_idx  = (funct3_i == 3'b001) | (funct3_i == 3'b011);  // idx=1 only (꼭 is_custom_op 불필요, custom일 때만 load_*_en 쓰임)
    wire accel_compute   = is_custom_op & (funct3_i == 3'b100);














































    // ALU Control (기존과 동일)
    always @(*) begin
        alu_op = 4'b0000;
        case (opcode_i)
            7'b0110011: begin
                case (funct3_i)
                    3'b000: begin
                        case (funct7_i)
                            7'b0100000: alu_op = 4'b0011;  // SUB

                            7'b0000001: alu_op = 4'b1011;  // MUL (RV32M)

                            default:    alu_op = 4'b0000;  // ADD
                        endcase
                    end
                    3'b001: alu_op = 4'b0100;
                    3'b010: alu_op = 4'b0101;
                    3'b011: alu_op = 4'b0110;
                    3'b100: alu_op = 4'b0010;
                    3'b101: alu_op = (funct7_i == 7'b0100000) ? 4'b0111 : 4'b1000;
                    3'b110: alu_op = 4'b0001;
                    3'b111: alu_op = 4'b1001;
                    default: alu_op = 4'b0000;
                endcase
            end
            7'b0010011: begin
                case (funct3_i)
                    3'b000: alu_op = 4'b0000;
                    3'b010: alu_op = 4'b0101;
                    3'b011: alu_op = 4'b0110;
                    3'b100: alu_op = 4'b0010;
                    3'b110: alu_op = 4'b0001;
                    3'b111: alu_op = 4'b1001;
                    3'b001: alu_op = 4'b0100;
                    3'b101: alu_op = (funct7_i == 7'b0100000) ? 4'b0111 : 4'b1000;
                    default: alu_op = 4'b0000;
                endcase
            end
            7'b1100011: begin
                case (funct3_i)
                    3'b000, 3'b001: alu_op = 4'b0011;
                    3'b100, 3'b101: alu_op = 4'b0101;
                    default: alu_op = 4'b0011;
                endcase
            end
            7'b0110111: alu_op = 4'b1010;
            default: alu_op = 4'b0000;
        endcase
    end

    // ALU Mux (기존과 동일)
    always @(*) begin
        alu_in1 = rs1_dout_i;
        alu_in2 = rs2_dout_i;
        case (opcode_i)
            7'b0010011, 7'b0000011, 7'b0100011, 7'b1100111: alu_in2 = imm_i;
            7'b0110111: begin alu_in1 = 32'b0; alu_in2 = imm_i; end
            7'b0010111: begin alu_in1 = pc_i; alu_in2 = imm_i; end
            default: ;
        endcase
    end

    // ==========================================
    // 3. ALU Op 및 최종 결과 MUX
    // ==========================================
    always @(*) begin
        case (alu_op)
            4'b0000: std_alu_result = alu_in1 + alu_in2;
            4'b0001: std_alu_result = alu_in1 | alu_in2;
            4'b0010: std_alu_result = alu_in1 ^ alu_in2;
            4'b0011: std_alu_result = alu_in1 - alu_in2;
            4'b0100: std_alu_result = alu_in1 << alu_in2[4:0];
            4'b0101: std_alu_result = ($signed(alu_in1) < $signed(alu_in2)) ? 32'd1 : 32'd0;
            4'b0110: std_alu_result = (alu_in1 < alu_in2) ? 32'd1 : 32'd0;
            4'b0111: std_alu_result = $signed(alu_in1) >>> alu_in2[4:0];
            4'b1000: std_alu_result = alu_in1 >> alu_in2[4:0];
            4'b1001: std_alu_result = alu_in1 & alu_in2;
            4'b1010: std_alu_result = alu_in2;

            4'b1011: std_alu_result = alu_in1 * alu_in2;  // MUL: lower 32 bits of rs1*rs2

            default: std_alu_result = 32'b0;
        endcase







        // No-accel build: Custom-0 명령은 디코드만 되고 실행 결과는 0.
        // (회귀 의미는 없고 면적 비교 합성 전용)
        alu_result_o = std_alu_result;

    end
endmodule
