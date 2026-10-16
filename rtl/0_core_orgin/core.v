`timescale 1ns/1ps

// 5-stage pipeline: IF - ID - EX - MEM - WB
// Each stage module holds its own logic and its output pipeline register:
//   core_if_stage  : PC, IMEM fetch                    -> IF/ID
//   core_id_stage  : decode, RF, load-use detection    -> ID/EX
//   core_ex_stage  : forwarding, ALU, Branch Unit      -> EX/MEM
//   core_mem_stage : DMEM interface (LSU)              -> MEM/WB
//   core_wb_stage  : write-back select                 -> RF (ID), forwarding (EX)
// IMEM and DMEM are synchronous with a 1-cycle read latency (tb_core.v).
// Feedback paths: stall (ID -> IF), branch_taken/target (EX -> IF, ID),
// wb_* (WB -> ID register file and EX forwarding).
module core (
    input  clk_i,
    input  rst_ni,
    // IMEM
    input  [31:0] imem_rd_data_i,
    output wire [31:0] imem_addr_o,
    output wire        imem_read_o,
    // DMEM
    input  [31:0] dmem_rd_data_i,
    output wire [31:0] dmem_addr_o,
    output wire        dmem_read_o,
    output wire        dmem_write_o,
    output wire [31:0] dmem_wr_data_o
);

    // Feedback
    wire        stall;
    wire        branch_taken;
    wire [31:0] branch_target;
    wire        wb_reg_write;
    wire [4:0]  wb_rd;
    wire [31:0] wb_write_data;

    // IF/ID
    wire [31:0] if_id_pc;
    wire [31:0] if_id_instr;

    // ID/EX
    wire [31:0] id_ex_pc;
    wire [31:0] id_ex_rs1_data;
    wire [31:0] id_ex_rs2_data;
    wire [31:0] id_ex_imm;
    wire [4:0]  id_ex_rs1;
    wire [4:0]  id_ex_rs2;
    wire [4:0]  id_ex_rd;
    wire [6:0]  id_ex_opcode;
    wire [2:0]  id_ex_funct3;
    wire [6:0]  id_ex_funct7;
    wire        id_ex_reg_write;
    wire [1:0]  id_ex_mem_to_reg;
    wire        id_ex_mem_read;
    wire        id_ex_mem_write;

    // EX -> MEM (DMEM request)
    wire [31:0] ex_mem_addr;
    wire [31:0] ex_mem_wr_data;
    wire        ex_mem_read;
    wire        ex_mem_write;

    // EX/MEM
    wire [31:0] ex_mem_pc;
    wire [31:0] ex_mem_result;
    wire [4:0]  ex_mem_rd;
    wire        ex_mem_reg_write;
    wire [1:0]  ex_mem_mem_to_reg;

    // MEM/WB
    wire [31:0] mem_wb_pc;
    wire [31:0] mem_wb_result;
    wire [31:0] mem_wb_mem_rdata;
    wire [4:0]  mem_wb_rd;
    wire        mem_wb_reg_write;
    wire [1:0]  mem_wb_mem_to_reg;


    // 1. IF Stage
    core_if_stage u_if (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),
        .stall_i         (stall),
        .branch_taken_i  (branch_taken),
        .branch_target_i (branch_target),
        .imem_rd_data_i  (imem_rd_data_i),
        .imem_addr_o     (imem_addr_o),
        .imem_read_o     (imem_read_o),
        .if_id_pc_o      (if_id_pc),
        .if_id_instr_o   (if_id_instr)
    );

    // 2. ID Stage
    core_id_stage u_id (
        .clk_i              (clk_i),
        .rst_ni             (rst_ni),
        .if_id_pc_i         (if_id_pc),
        .if_id_instr_i      (if_id_instr),
        .wb_reg_write_i     (wb_reg_write),
        .wb_rd_i            (wb_rd),
        .wb_write_data_i    (wb_write_data),
        .branch_taken_i     (branch_taken),
        .stall_o            (stall),
        .id_ex_pc_o         (id_ex_pc),
        .id_ex_rs1_data_o   (id_ex_rs1_data),
        .id_ex_rs2_data_o   (id_ex_rs2_data),
        .id_ex_imm_o        (id_ex_imm),
        .id_ex_rs1_o        (id_ex_rs1),
        .id_ex_rs2_o        (id_ex_rs2),
        .id_ex_rd_o         (id_ex_rd),
        .id_ex_opcode_o     (id_ex_opcode),
        .id_ex_funct3_o     (id_ex_funct3),
        .id_ex_funct7_o     (id_ex_funct7),
        .id_ex_reg_write_o  (id_ex_reg_write),
        .id_ex_mem_to_reg_o (id_ex_mem_to_reg),
        .id_ex_mem_read_o   (id_ex_mem_read),
        .id_ex_mem_write_o  (id_ex_mem_write)
    );

    // 3. EX Stage
    core_ex_stage u_ex (
        .clk_i               (clk_i),
        .rst_ni              (rst_ni),
        .pc_i                (id_ex_pc),
        .rs1_data_i          (id_ex_rs1_data),
        .rs2_data_i          (id_ex_rs2_data),
        .imm_i               (id_ex_imm),
        .rs1_i               (id_ex_rs1),
        .rs2_i               (id_ex_rs2),
        .rd_i                (id_ex_rd),
        .opcode_i            (id_ex_opcode),
        .funct3_i            (id_ex_funct3),
        .funct7_i            (id_ex_funct7),
        .reg_write_i         (id_ex_reg_write),
        .mem_to_reg_i        (id_ex_mem_to_reg),
        .mem_read_i          (id_ex_mem_read),
        .mem_write_i         (id_ex_mem_write),
        .wb_reg_write_i      (wb_reg_write),
        .wb_rd_i             (wb_rd),
        .wb_write_data_i     (wb_write_data),
        .branch_taken_o      (branch_taken),
        .branch_target_o     (branch_target),
        .mem_addr_o          (ex_mem_addr),
        .mem_wr_data_o       (ex_mem_wr_data),
        .mem_read_o          (ex_mem_read),
        .mem_write_o         (ex_mem_write),
        .ex_mem_pc_o         (ex_mem_pc),
        .ex_mem_result_o     (ex_mem_result),
        .ex_mem_rd_o         (ex_mem_rd),
        .ex_mem_reg_write_o  (ex_mem_reg_write),
        .ex_mem_mem_to_reg_o (ex_mem_mem_to_reg)
    );

    // 4. MEM Stage
    core_mem_stage u_mem (
        .clk_i               (clk_i),
        .rst_ni              (rst_ni),
        .req_addr_i          (ex_mem_addr),
        .req_wr_data_i       (ex_mem_wr_data),
        .req_read_i          (ex_mem_read),
        .req_write_i         (ex_mem_write),
        .pc_i                (ex_mem_pc),
        .result_i            (ex_mem_result),
        .rd_i                (ex_mem_rd),
        .reg_write_i         (ex_mem_reg_write),
        .mem_to_reg_i        (ex_mem_mem_to_reg),
        .dmem_rd_data_i      (dmem_rd_data_i),
        .dmem_addr_o         (dmem_addr_o),
        .dmem_wr_data_o      (dmem_wr_data_o),
        .dmem_read_o         (dmem_read_o),
        .dmem_write_o        (dmem_write_o),
        .mem_wb_pc_o         (mem_wb_pc),
        .mem_wb_result_o     (mem_wb_result),
        .mem_wb_mem_rdata_o  (mem_wb_mem_rdata),
        .mem_wb_rd_o         (mem_wb_rd),
        .mem_wb_reg_write_o  (mem_wb_reg_write),
        .mem_wb_mem_to_reg_o (mem_wb_mem_to_reg)
    );

    // 5. WB Stage
    core_wb_stage u_wb (
        .result_i        (mem_wb_result),
        .mem_rdata_i     (mem_wb_mem_rdata),
        .rd_i            (mem_wb_rd),
        .reg_write_i     (mem_wb_reg_write),
        .mem_to_reg_i    (mem_wb_mem_to_reg),
        .wb_reg_write_o  (wb_reg_write),
        .wb_rd_o         (wb_rd),
        .wb_write_data_o (wb_write_data)
    );

endmodule
