module immediate_generator (
    input  [31:0] instr_i,
    input  [6:0]  opcode_i,
    output reg [31:0] imm_o
);
`define OPCODE_LUI    7'b0110111
`define OPCODE_AUIPC  7'b0010111
`define OPCODE_I      7'b0010011
`define OPCODE_LOAD   7'b0000011
`define OPCODE_STORE  7'b0100011
`define OPCODE_BRANCH 7'b1100011
`define OPCODE_JAL    7'b1101111
`define OPCODE_JALR   7'b1100111

always @(*) begin
    imm_o = 32'b0;
    case (opcode_i)
        // I-type (ADDI/ANDI/.., JALR, LOAD 주소상수)
        `OPCODE_I, `OPCODE_JALR, `OPCODE_LOAD: begin
            imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
        end
        // S-type (STORE)
        `OPCODE_STORE: begin
            imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
        end
        // B-type (BRANCH)
        `OPCODE_BRANCH: begin
            imm_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
        end
        // U-type (★ LUI/AUIPC 공통)
        `OPCODE_LUI, `OPCODE_AUIPC: begin
            imm_o = {instr_i[31:12], 12'b0};
        end
        // J-type (JAL)
        `OPCODE_JAL: begin
            imm_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
        end
        default: imm_o = 32'b0;
    endcase
end
endmodule
