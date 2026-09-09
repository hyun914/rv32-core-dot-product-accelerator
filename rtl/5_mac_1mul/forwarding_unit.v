`timescale 1ns/1ps

// 5-stage pipeline: EX/MEM (priority) then MEM/WB. Do not forward load *data*
// from EX/MEM (core stalls LW->dependent-in-EX instead). JAL/JALR: PC+4.
module forwarding_unit (
    input  [4:0] rs1_i,
    input  [4:0] rs2_i,
    input [31:0] id_ex_rs1_data_i,
    input [31:0] id_ex_rs2_data_i,
    // EX/MEM
    input        ex_mem_reg_write_i,
    input        ex_mem_mem_read_i,
    input  [4:0] ex_mem_rd_i,
    input [31:0] ex_mem_alu_result_i,
    input  [31:0] ex_mem_pc_i,
    input  [1:0]  ex_mem_mem_to_reg_i,
    // MEM/WB
    input        mem_wb_reg_write_i,
    input  [4:0] mem_wb_rd_i,
    input  [1:0] mem_wb_mem_to_reg_i,
    input  [31:0] mem_wb_pc_i,
    input  [31:0] mem_wb_alu_i,
    input  [31:0] mem_wb_mem_rdata_i,
    output reg [31:0] rs1_fwd_o,
    output reg [31:0] rs2_fwd_o
);

    wire [31:0] mem_wb_fwd_val =
        (mem_wb_mem_to_reg_i == 2'b01) ? mem_wb_mem_rdata_i :
        (mem_wb_mem_to_reg_i == 2'b10) ? (mem_wb_pc_i + 32'd4) :
                                         mem_wb_alu_i;

    wire [31:0] ex_mem_fwd_val =
        (ex_mem_mem_to_reg_i == 2'b10) ? (ex_mem_pc_i + 32'd4) :
                                         ex_mem_alu_result_i;

    wire ex_mem_hazard_rs1 = ex_mem_reg_write_i && !ex_mem_mem_read_i
        && (ex_mem_rd_i != 5'd0) && (ex_mem_rd_i == rs1_i);
    wire ex_mem_hazard_rs2 = ex_mem_reg_write_i && !ex_mem_mem_read_i
        && (ex_mem_rd_i != 5'd0) && (ex_mem_rd_i == rs2_i);

    wire mem_wb_hazard_rs1 = mem_wb_reg_write_i && (mem_wb_rd_i != 5'd0)
        && (mem_wb_rd_i == rs1_i) && !ex_mem_hazard_rs1;
    wire mem_wb_hazard_rs2 = mem_wb_reg_write_i && (mem_wb_rd_i != 5'd0)
        && (mem_wb_rd_i == rs2_i) && !ex_mem_hazard_rs2;

    always @(*) begin
        if (ex_mem_hazard_rs1)
            rs1_fwd_o = ex_mem_fwd_val;
        else if (mem_wb_hazard_rs1)
            rs1_fwd_o = mem_wb_fwd_val;
        else
            rs1_fwd_o = id_ex_rs1_data_i;

        if (ex_mem_hazard_rs2)
            rs2_fwd_o = ex_mem_fwd_val;
        else if (mem_wb_hazard_rs2)
            rs2_fwd_o = mem_wb_fwd_val;
        else
            rs2_fwd_o = id_ex_rs2_data_i;
    end
endmodule
