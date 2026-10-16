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

// ID stage: decode, register file read, immediate generation, control,
// load-use hazard detection, and the ID/EX pipeline register.
//   wb_*_i         : write port from WB; also bypassed to the read ports
//   branch_taken_i : flush from EX, ID/EX gets a bubble
//   stall_o        : load-use hazard, freezes IF (and puts a bubble in ID/EX)
module core_id_stage (
    input               clk_i,
    input               rst_ni,
    // IF/ID
    input  [31:0]       if_id_pc_i,
    input  [31:0]       if_id_instr_i,
    // WB
    input               wb_reg_write_i,
    input  [4:0]        wb_rd_i,
    input  [31:0]       wb_write_data_i,
    // EX
    input               branch_taken_i,

    output              stall_o,
    // ID/EX
    output reg [31:0]   id_ex_pc_o,
    output reg [31:0]   id_ex_rs1_data_o,
    output reg [31:0]   id_ex_rs2_data_o,
    output reg [31:0]   id_ex_imm_o,
    output reg [4:0]    id_ex_rs1_o,
    output reg [4:0]    id_ex_rs2_o,
    output reg [4:0]    id_ex_rd_o,
    output reg [6:0]    id_ex_opcode_o,
    output reg [2:0]    id_ex_funct3_o,
    output reg [6:0]    id_ex_funct7_o,
    output reg          id_ex_reg_write_o,
    output reg [1:0]    id_ex_mem_to_reg_o,
    output reg          id_ex_mem_read_o,
    output reg          id_ex_mem_write_o
);

    wire [31:0] instr  = if_id_instr_i;
    wire [6:0]  opcode = instr[6:0];
    wire [4:0]  rd     = instr[11:7];
    wire [2:0]  funct3 = instr[14:12];
    wire [4:0]  rs1    = instr[19:15];
    wire [4:0]  rs2    = instr[24:20];
    wire [6:0]  funct7 = instr[31:25];

    reg         mem_read;
    reg         mem_write;
    reg         reg_write;
    reg  [1:0]  mem_to_reg;
    reg  [31:0] imm;
    wire [31:0] rs1_dout;
    wire [31:0] rs2_dout;

    // Register File
    register_file rf (
        .clk_i       (clk_i),
        .rst_ni      (rst_ni),
        .reg_write_i (wb_reg_write_i),
        .rs1_i       (rs1),
        .rs2_i       (rs2),
        .rd_i        (wb_rd_i),
        .rd_din_i    (wb_write_data_i),
        .rs1_dout_o  (rs1_dout),
        .rs2_dout_o  (rs2_dout)
    );

    // Immediate Generation [BUG FIXED]
    always @(*) begin
        case (opcode)
            `OPCODE_R, `OPCODE_JALR, `OPCODE_I, `OPCODE_LOAD: begin
                imm = {{20{instr[31]}}, instr[31:20]};
                if (opcode == `OPCODE_I) begin
                    case (funct3)
                        `FUNCT3_SLL, `FUNCT3_SRL_SRA: imm = {{27{1'b0}}, instr[24:20]};
                        default: ;
                    endcase
                end
            end
            `OPCODE_STORE: begin
                imm = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end

            // [Fix] instr[31] added to make 32 bits
            `OPCODE_BRANCH: begin
                imm = {{19{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            end

            // [Fix] instr[31] added to make 32 bits
            `OPCODE_JAL: begin
                imm = {{11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            end

            `OPCODE_LUI,
            `OPCODE_AUIPC: begin
                imm = {instr[31:12], 12'b0};
            end
            default: begin
                imm = 32'b0;
            end
        endcase
    end

    // Control Unit Logic
    always @(*) begin
        mem_read   = 1'b0;
        mem_write  = 1'b0;
        reg_write  = 1'b0;
        mem_to_reg = 2'b00;

        case (opcode)
            `OPCODE_R: begin
                reg_write  = 1'b1;
                mem_to_reg = 2'b00;
            end
            `OPCODE_I: begin
                reg_write  = 1'b1;
                mem_to_reg = 2'b00;
            end
            `OPCODE_LOAD: begin
                reg_write  = 1'b1;
                mem_read   = 1'b1;
                mem_to_reg = 2'b01;
            end
            `OPCODE_STORE: begin
                mem_write  = 1'b1;
            end
            `OPCODE_JAL,
            `OPCODE_JALR: begin
                reg_write  = 1'b1;
                mem_to_reg = 2'b10;
            end
            `OPCODE_LUI: begin
                reg_write  = 1'b1;
                mem_to_reg = 2'b00;
            end
            `OPCODE_AUIPC: begin
                reg_write  = 1'b1;
                mem_to_reg = 2'b00;
            end
            default: begin
            end
        endcase
    end

    // WB->ID bypass (producer 3 instructions ahead writes RF in this cycle)
    wire wb_bypass_rs1 = wb_reg_write_i && (wb_rd_i != 5'd0) && (wb_rd_i == rs1);
    wire wb_bypass_rs2 = wb_reg_write_i && (wb_rd_i != 5'd0) && (wb_rd_i == rs2);

    wire [31:0] rs1_data = wb_bypass_rs1 ? wb_write_data_i : rs1_dout;
    wire [31:0] rs2_data = wb_bypass_rs2 ? wb_write_data_i : rs2_dout;

    // Hazard Detection (load-use)
    // LW in EX and this instruction reads its rd: the load data is only valid
    // in MEM, too late for EX. Hold PC and IF/ID for one cycle and put a
    // bubble into ID/EX. When this instruction then reaches EX, the LW is in
    // MEM/WB and is forwarded from there.
    // Only real source operands count; in other formats the rs1/rs2 fields
    // are immediate bits (same rule as forwarding_unit).
    wire uses_rs1 = (opcode == `OPCODE_R)      || (opcode == `OPCODE_I)
                 || (opcode == `OPCODE_LOAD)   || (opcode == `OPCODE_STORE)
                 || (opcode == `OPCODE_BRANCH) || (opcode == `OPCODE_JALR);
    wire uses_rs2 = (opcode == `OPCODE_R)      || (opcode == `OPCODE_STORE)
                 || (opcode == `OPCODE_BRANCH);

    assign stall_o = id_ex_mem_read_o && (id_ex_rd_o != 5'd0)
                  && ((uses_rs1 && (id_ex_rd_o == rs1))
                   || (uses_rs2 && (id_ex_rd_o == rs2)));

    // ID/EX Pipeline Register
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            id_ex_pc_o         <= 32'b0;
            id_ex_rs1_data_o   <= 32'b0;
            id_ex_rs2_data_o   <= 32'b0;
            id_ex_imm_o        <= 32'b0;
            id_ex_rs1_o        <= 5'b0;
            id_ex_rs2_o        <= 5'b0;
            id_ex_rd_o         <= 5'b0;
            id_ex_opcode_o     <= 7'b0;
            id_ex_funct3_o     <= 3'b0;
            id_ex_funct7_o     <= 7'b0;
            id_ex_reg_write_o  <= 1'b0;
            id_ex_mem_to_reg_o <= 2'b0;
            id_ex_mem_read_o   <= 1'b0;
            id_ex_mem_write_o  <= 1'b0;
        end else if (branch_taken_i || stall_o) begin
            // flush (taken branch) / bubble (load-use)
            id_ex_pc_o         <= 32'b0;
            id_ex_rs1_data_o   <= 32'b0;
            id_ex_rs2_data_o   <= 32'b0;
            id_ex_imm_o        <= 32'b0;
            id_ex_rs1_o        <= 5'b0;
            id_ex_rs2_o        <= 5'b0;
            id_ex_rd_o         <= 5'b0;
            id_ex_opcode_o     <= 7'b0;
            id_ex_funct3_o     <= 3'b0;
            id_ex_funct7_o     <= 7'b0;
            id_ex_reg_write_o  <= 1'b0;
            id_ex_mem_to_reg_o <= 2'b0;
            id_ex_mem_read_o   <= 1'b0;
            id_ex_mem_write_o  <= 1'b0;
        end else begin
            id_ex_pc_o         <= if_id_pc_i;
            id_ex_rs1_data_o   <= rs1_data;
            id_ex_rs2_data_o   <= rs2_data;
            id_ex_imm_o        <= imm;
            id_ex_rs1_o        <= rs1;
            id_ex_rs2_o        <= rs2;
            id_ex_rd_o         <= rd;
            id_ex_opcode_o     <= opcode;
            id_ex_funct3_o     <= funct3;
            id_ex_funct7_o     <= funct7;
            id_ex_reg_write_o  <= reg_write;
            id_ex_mem_to_reg_o <= mem_to_reg;
            id_ex_mem_read_o   <= mem_read;
            id_ex_mem_write_o  <= mem_write;
        end
    end

endmodule
