`timescale 1ns/1ps

// WB stage: selects the value written back. Its outputs drive the register
// file write port (ID) and are the MEM/WB forwarding source (EX).
//   mem_to_reg_i == 2'b01 -> load data
//   otherwise             -> result (ALU result, or PC+4 already selected in EX)
module core_wb_stage (
    // MEM/WB
    input  [31:0] result_i,
    input  [31:0] mem_rdata_i,
    input  [4:0]  rd_i,
    input         reg_write_i,
    input  [1:0]  mem_to_reg_i,

    output        wb_reg_write_o,
    output [4:0]  wb_rd_o,
    output [31:0] wb_write_data_o
);

    assign wb_reg_write_o  = reg_write_i;
    assign wb_rd_o         = rd_i;
    assign wb_write_data_o = (mem_to_reg_i == 2'b01) ? mem_rdata_i : result_i;

endmodule
