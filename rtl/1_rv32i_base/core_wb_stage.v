`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// core_wb_stage
//   - 3-way Write-Back MUX:
//       mem_to_reg == 2'b01  -> dmem_rd_data_i  (LOAD)
//       mem_to_reg == 2'b10  -> pc_plus_4_i     (JAL/JALR link)
//       otherwise            -> alu_result_i    (ALU / accelerator result)
//
// Behavior is identical to the inline `wb_write_data_eff` MUX that previously
// lived in core.v.
// -----------------------------------------------------------------------------

module core_wb_stage (
    input  [1:0]  mem_to_reg_i,
    input  [31:0] alu_result_i,
    input  [31:0] mem_rdata_i,
    input  [31:0] pc_plus_4_i,
    output [31:0] rd_din_o
);

    assign rd_din_o =
        (mem_to_reg_i == 2'b01) ? mem_rdata_i  :
        (mem_to_reg_i == 2'b10) ? pc_plus_4_i  :
                                  alu_result_i;

endmodule
