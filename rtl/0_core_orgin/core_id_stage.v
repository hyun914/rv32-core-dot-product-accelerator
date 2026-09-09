`timescale 1ns/1ps

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
    output reg          mem_read_o,
    output reg          mem_write_o,
    output reg          reg_write_o,
    output reg [1:0]    mem_to_reg_o,
    output reg [31:0]   imm_o,
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

    // Immediate Generation [BUG FIXED]
    always @(*) begin
        case (opcode_o)
            `OPCODE_R, `OPCODE_JALR, `OPCODE_I, `OPCODE_LOAD: begin
                imm_o = {{20{instr_i[31]}}, instr_i[31:20]};
                if (opcode_o == `OPCODE_I) begin
                    case (funct3_o)
                        `FUNCT3_SLL, `FUNCT3_SRL_SRA: imm_o = {{27{1'b0}}, instr_i[24:20]};
                        default: ;
                    endcase
                end
            end
            `OPCODE_STORE: begin
                imm_o = {{20{instr_i[31]}}, instr_i[31:25], instr_i[11:7]};
            end
            
            // [Fix] instr_i[31] added to make 32 bits
            `OPCODE_BRANCH: begin
                imm_o = {{19{instr_i[31]}}, instr_i[31], instr_i[7], instr_i[30:25], instr_i[11:8], 1'b0};
            end
            
            // [Fix] instr_i[31] added to make 32 bits
            `OPCODE_JAL: begin
                imm_o = {{11{instr_i[31]}}, instr_i[31], instr_i[19:12], instr_i[20], instr_i[30:21], 1'b0};
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

    // Control Unit Logic
    always @(*) begin
        mem_read_o   = 1'b0;
        mem_write_o  = 1'b0;
        reg_write_o  = 1'b0;
        mem_to_reg_o = 2'b00;

        case (opcode_o)
            `OPCODE_R: begin
                reg_write_o  = 1'b1;
                mem_to_reg_o = 2'b00; 
            end
            `OPCODE_I: begin
                reg_write_o  = 1'b1;
                mem_to_reg_o = 2'b00; 
            end
            `OPCODE_LOAD: begin
                reg_write_o  = 1'b1;
                mem_read_o   = 1'b1;
                mem_to_reg_o = 2'b01; 
            end
            `OPCODE_STORE: begin
                mem_write_o  = 1'b1;
            end
            `OPCODE_JAL,
            `OPCODE_JALR: begin
                reg_write_o  = 1'b1;
                mem_to_reg_o = 2'b10; 
            end
            `OPCODE_LUI: begin
                reg_write_o  = 1'b1;
                mem_to_reg_o = 2'b00; 
            end
            `OPCODE_AUIPC: begin
                reg_write_o  = 1'b1;
                mem_to_reg_o = 2'b00; 
            end
            default: begin
            end
        endcase
    end

endmodule