`timescale 1ns/1ps

`define OPCODE_CUSTOM_0 7'b0001011
`define OPCODE_R      7'b0110011
`define OPCODE_I      7'b0010011
`define OPCODE_BRANCH 7'b1100011
`define OPCODE_STORE  7'b0100011
`define OPCODE_LOAD   7'b0000011
`define OPCODE_JALR   7'b1100111
`define OPCODE_JAL    7'b1101111
`define OPCODE_AUIPC  7'b0010111
`define OPCODE_LUI    7'b0110111

`define FUNCT3_ADD_SUB 3'b000
`define FUNCT3_SLL     3'b001
`define FUNCT3_SLT     3'b010
`define FUNCT3_SLTU    3'b011
`define FUNCT3_XOR     3'b100
`define FUNCT3_SRL_SRA 3'b101
`define FUNCT3_OR      3'b110
`define FUNCT3_AND     3'b111

module core_id_stage (
    input               clk_i,
    input               rst_ni,
    input  [31:0]       instr_i,
    input  [31:0]       rd_din_i,
    input  [4:0]        wb_rd_i,
    input               wb_reg_write_i,

    output [6:0]        opcode_o,
    output [4:0]        rd_o,
    output [2:0]        funct3_o,
    output [4:0]        rs1_o,
    output [4:0]        rs2_o,
    output [6:0]        funct7_o,
    output              mem_read_o,
    output              mem_write_o,
    output              reg_write_o,
    output [1:0]        mem_to_reg_o,
    output [31:0]       imm_o,
    output [31:0]       rs1_dout_o,
    output [31:0]       rs2_dout_o
);

    assign opcode_o = instr_i[6:0];
    assign rd_o     = instr_i[11:7];
    assign funct3_o = instr_i[14:12];
    assign rs1_o    = instr_i[19:15];
    assign rs2_o    = instr_i[24:20];
    assign funct7_o = instr_i[31:25];

    // Register File
    register_file rf (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .reg_write_i (wb_reg_write_i),
        .rs1_i       (rs1_o),
        .rs2_i       (rs2_o),
        .rd_i        (wb_rd_i),
        .rd_din_i    (rd_din_i),
        .rs1_dout_o  (rs1_dout_o),
        .rs2_dout_o  (rs2_dout_o)
    );

    // Immediate generator (extracted module)
    immediate_generator u_imm (
        .instr_i   (instr_i),
        .opcode_i  (opcode_o),
        .funct3_i  (funct3_o),
        .imm_o     (imm_o)
    );

    // Control unit / decoder (extracted module)
    decoder u_dec (
        .opcode_i      (opcode_o),
        .funct3_i      (funct3_o),
        .reg_write_o   (reg_write_o),
        .mem_read_o    (mem_read_o),
        .mem_write_o   (mem_write_o),
        .mem_to_reg_o  (mem_to_reg_o)
    );

endmodule