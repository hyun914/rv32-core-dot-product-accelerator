`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// immediate_generator
//   - Pure combinational immediate decoder for RV32I.
//   - Behavior is identical to the inline `imm_o` `always @(*)` block that
//     previously lived in core_id_stage.v (including the SLLI/SRLI/SRAI shamt
//     special-case under OPCODE_I + funct3 == 001/101).
// -----------------------------------------------------------------------------

`define OPCODE_R      7'b0110011
`define OPCODE_I      7'b0010011
`define OPCODE_BRANCH 7'b1100011
`define OPCODE_STORE  7'b0100011
`define OPCODE_LOAD   7'b0000011
`define OPCODE_JALR   7'b1100111
`define OPCODE_JAL    7'b1101111
`define OPCODE_AUIPC  7'b0010111
`define OPCODE_LUI    7'b0110111

`define FUNCT3_SLL     3'b001
`define FUNCT3_SRL_SRA 3'b101

module immediate_generator (
    input  [31:0] instr_i,
    input  [6:0]  opcode_i,
    input  [2:0]  funct3_i,
    output reg [31:0] imm_o
);

    always @(*) begin
        case (opcode_i)
            `OPCODE_R, `OPCODE_JALR, `OPCODE_I, `OPCODE_LOAD: begin
                imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
                if (opcode_i == `OPCODE_I) begin
                    case (funct3_i)
                        `FUNCT3_SLL,
                        `FUNCT3_SRL_SRA: imm_o = {{27{1'b0}}, instr_i[24:20]};
                        default: ;
                    endcase
                end
            end
            `OPCODE_STORE: begin
                imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
            end
            `OPCODE_BRANCH: begin
                imm_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7],
                         instr_i[30:25], instr_i[11:8], 1'b0};
            end
            `OPCODE_JAL: begin
                imm_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12],
                         instr_i[20], instr_i[30:21], 1'b0};
            end
            `OPCODE_LUI,
            `OPCODE_AUIPC: begin
                imm_o = {instr_i[31:12], 12'b0};
            end
            default: begin
                imm_o = 32'b0;
            end
        endcase
    end

endmodule
