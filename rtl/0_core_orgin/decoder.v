`timescale 1ns/1ps

// OPCODES
`define OPCODE_R      7'b0110011
`define OPCODE_I      7'b0010011
`define OPCODE_BRANCH 7'b1100011
`define OPCODE_STORE  7'b0100011
`define OPCODE_LOAD   7'b0000011
`define OPCODE_JALR   7'b1100111
`define OPCODE_JAL    7'b1101111
`define OPCODE_AUIPC  7'b0010111
`define OPCODE_LUI    7'b0110111

module decoder(
    input  [6:0] opcode_i,
    output reg        reg_write_o,
    output reg [1:0]  mem_to_reg_o,  // 00:ALU, 01:MEM, 10:PC+4, 11:MEM(호환)
    output reg        mem_write_o,
    output reg        mem_read_o
);

    always @(*) begin
        // 기본값
        reg_write_o   = 1'b0;
        mem_to_reg_o  = 2'b00;
        mem_write_o   = 1'b0;
        mem_read_o    = 1'b0;

        case (opcode_i)
            `OPCODE_R: begin
                reg_write_o  = 1'b1;          // ALU 결과
                mem_to_reg_o = 2'b00;
            end
            `OPCODE_I: begin
                reg_write_o  = 1'b1;          // ADDI 등 ALU-imm
                mem_to_reg_o = 2'b00;
            end
            `OPCODE_LOAD: begin
                reg_write_o   = 1'b1;
                mem_read_o    = 1'b1;
                mem_write_o   = 1'b0;
                mem_to_reg_o  = 2'b01;  // MEM
            end

            `OPCODE_STORE: begin
                reg_write_o  = 1'b0;          // 메모리로만 쓰기
                mem_write_o  = 1'b1;
            end
            `OPCODE_LUI: begin
                reg_write_o  = 1'b1;          // ALU 경유 LUI 결과
                mem_to_reg_o = 2'b00;
            end
            `OPCODE_AUIPC: begin
                reg_write_o  = 1'b1;          // WB에서 PC+4/PC 기반 선택은 상위에서 처리
                mem_to_reg_o = 2'b10;         // PC+4 경로 사용
            end
            `OPCODE_JAL,
            `OPCODE_JALR: begin
                reg_write_o  = 1'b1;          // x[rd] = PC+4
                mem_to_reg_o = 2'b10;
            end
            default: begin
                // 그대로 기본값
            end
        endcase
    end

endmodule
