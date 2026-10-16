`timescale 1ns/1ps

// MEM stage (LSU): DMEM interface and the MEM/WB pipeline register.
// DMEM is synchronous with a 1-cycle read latency. The request (req_*_i) is
// computed in EX and latched by DMEM on the EX->MEM edge, so DMEM's own
// input register plays the role of EX/MEM for the request. Read data is
// valid during MEM and is captured into MEM/WB here.
// Word access only (lw/sw); the interface has no byte enables.
module core_mem_stage (
    input         clk_i,
    input         rst_ni,
    // DMEM request from EX
    input  [31:0] req_addr_i,
    input  [31:0] req_wr_data_i,
    input         req_read_i,
    input         req_write_i,
    // EX/MEM
    input  [31:0] pc_i,
    input  [31:0] result_i,
    input  [4:0]  rd_i,
    input         reg_write_i,
    input  [1:0]  mem_to_reg_i,
    // DMEM
    input  [31:0] dmem_rd_data_i,
    output [31:0] dmem_addr_o,
    output [31:0] dmem_wr_data_o,
    output        dmem_read_o,
    output        dmem_write_o,
    // MEM/WB
    output reg [31:0] mem_wb_pc_o,        // waveform/debug only
    output reg [31:0] mem_wb_result_o,    // ALU result, or PC+4 for JAL/JALR
    output reg [31:0] mem_wb_mem_rdata_o,
    output reg [4:0]  mem_wb_rd_o,
    output reg        mem_wb_reg_write_o,
    output reg [1:0]  mem_wb_mem_to_reg_o
);

    assign dmem_addr_o    = req_addr_i;
    assign dmem_wr_data_o = req_wr_data_i;
    assign dmem_read_o    = req_read_i;
    assign dmem_write_o   = req_write_i;

    // MEM/WB Pipeline Register
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mem_wb_pc_o         <= 32'b0;
            mem_wb_result_o     <= 32'b0;
            mem_wb_mem_rdata_o  <= 32'b0;
            mem_wb_rd_o         <= 5'b0;
            mem_wb_reg_write_o  <= 1'b0;
            mem_wb_mem_to_reg_o <= 2'b0;
        end else begin
            mem_wb_pc_o         <= pc_i;
            mem_wb_result_o     <= result_i;
            mem_wb_mem_rdata_o  <= dmem_rd_data_i;
            mem_wb_rd_o         <= rd_i;
            mem_wb_reg_write_o  <= reg_write_i;
            mem_wb_mem_to_reg_o <= mem_to_reg_i;
        end
    end

endmodule
