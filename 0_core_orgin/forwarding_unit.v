`timescale 1ns/1ps

module forwarding_unit (
    input  [6:0] opcode_i,       
    input  [4:0] rs1_i,           
    input  [4:0] rs2_i,           
    input        wb_reg_write_i,  
    input  [4:0] wb_rd_i,         
    output reg   forward_a_o,
    output reg   forward_b_o
);
    always @(*) begin
        forward_a_o = (wb_reg_write_i && (wb_rd_i != 5'd0) && (wb_rd_i == rs1_i));
        forward_b_o = (wb_reg_write_i && (wb_rd_i != 5'd0) && (wb_rd_i == rs2_i));
    end
endmodule