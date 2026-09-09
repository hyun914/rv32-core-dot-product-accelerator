`timescale 1ns/1ps

module core_if_stage (
    input clk_i,
    input rst_ni,
    input [31:0] pc_i,
    input [31:0] imem_rd_data_i,

    output reg [31:0] imem_addr_o,
    output reg imem_read_en_o,

    output reg [31:0] pc_next_o,
    output reg [31:0] instr_o
);

    reg [31:0] pc_reg;
    reg [31:0] instr_reg;

    always @(*) begin
        imem_addr_o = pc_i;
        imem_read_en_o = 1'b1;
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pc_reg    <= 32'b0;
            instr_reg <= 32'b0;
            pc_next_o <= 32'b0;
            instr_o   <= 32'b0;
        end else begin
            pc_reg <= pc_i;
            instr_reg <= imem_rd_data_i;
            pc_next_o <= pc_i + 32'd4;
            instr_o <= imem_rd_data_i;
        end
    end

endmodule
