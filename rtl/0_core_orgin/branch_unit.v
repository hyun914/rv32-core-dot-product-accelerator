`timescale 1ns/1ps

module branch_unit (
    input  [6:0]  opcode_i,
    input  [2:0]  funct3_i,
    // input alu_zero_i, // 더 이상 사용하지 않음 (직접 비교)
    input  [31:0] pc_i,
    input  [31:0] rs1_dout_i,
    input  [31:0] rs2_dout_i,    // ★ [추가] 비교를 위한 RS2 값
    input  [31:0] imm_i,

    output reg        branch_taken_o,
    output reg [31:0] pc_branch_o
);

    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JAL    = 7'b1101111;
    localparam OP_JALR   = 7'b1100111;

    // Funct3
    localparam BEQ  = 3'b000;
    localparam BNE  = 3'b001;
    localparam BLT  = 3'b100;
    localparam BGE  = 3'b101;
    localparam BLTU = 3'b110;
    localparam BGEU = 3'b111;

    always @(*) begin
        branch_taken_o = 1'b0;
        pc_branch_o    = pc_i + imm_i; // 기본값: Branch Target

        case (opcode_i)
            OP_JAL: begin
                branch_taken_o = 1'b1;
                pc_branch_o    = pc_i + imm_i;
            end
            OP_JALR: begin
                branch_taken_o = 1'b1;
                pc_branch_o    = (rs1_dout_i + imm_i) & 32'hFFFFFFFE;
            end
            OP_BRANCH: begin
                case (funct3_i)
                    BEQ:  branch_taken_o = (rs1_dout_i == rs2_dout_i);
                    BNE:  branch_taken_o = (rs1_dout_i != rs2_dout_i);
                    // ★ [$signed 비교] 음수 정렬의 핵심
                    BLT:  branch_taken_o = ($signed(rs1_dout_i) <  $signed(rs2_dout_i));
                    BGE:  branch_taken_o = ($signed(rs1_dout_i) >= $signed(rs2_dout_i));
                    // Unsigned 비교
                    BLTU: branch_taken_o = (rs1_dout_i <  rs2_dout_i);
                    BGEU: branch_taken_o = (rs1_dout_i >= rs2_dout_i);
                    default: branch_taken_o = 1'b0;
                endcase
            end
            default: ;
        endcase
    end
endmodule