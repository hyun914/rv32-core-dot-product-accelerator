`timescale 1ns/1ps

// 5-stage forwarding: two sources, EX/MEM has priority over MEM/WB because it
// holds the newer value of the same rd.
//   forward_*_o : 2'b00 ID/EX (no forwarding)
//                 2'b10 EX/MEM
//                 2'b01 MEM/WB
// opcode_i masks out fields that are not source registers (immediate bits in
// LUI/AUIPC/JAL, rs2 of I-type/LOAD/JALR), the same rule as the load-use
// check in core.v. That check keeps the dependent instruction in ID while a
// load sits in EX/MEM, so a load is never forwarded from EX/MEM; its data is
// picked up from MEM/WB one cycle later.
module forwarding_unit (
    input  [6:0] opcode_i,
    input  [4:0] rs1_i,
    input  [4:0] rs2_i,
    input        ex_mem_reg_write_i,
    input  [4:0] ex_mem_rd_i,
    input        mem_wb_reg_write_i,
    input  [4:0] mem_wb_rd_i,
    output reg [1:0] forward_a_o,
    output reg [1:0] forward_b_o
);
    localparam OP_R      = 7'b0110011;
    localparam OP_I      = 7'b0010011;
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JALR   = 7'b1100111;

    wire uses_rs1 = (opcode_i == OP_R)     || (opcode_i == OP_I)
                 || (opcode_i == OP_LOAD)  || (opcode_i == OP_STORE)
                 || (opcode_i == OP_BRANCH)|| (opcode_i == OP_JALR);
    wire uses_rs2 = (opcode_i == OP_R)     || (opcode_i == OP_STORE)
                 || (opcode_i == OP_BRANCH);

    always @(*) begin
        if (uses_rs1 && ex_mem_reg_write_i && (ex_mem_rd_i != 5'd0) && (ex_mem_rd_i == rs1_i))
            forward_a_o = 2'b10;
        else if (uses_rs1 && mem_wb_reg_write_i && (mem_wb_rd_i != 5'd0) && (mem_wb_rd_i == rs1_i))
            forward_a_o = 2'b01;
        else
            forward_a_o = 2'b00;

        if (uses_rs2 && ex_mem_reg_write_i && (ex_mem_rd_i != 5'd0) && (ex_mem_rd_i == rs2_i))
            forward_b_o = 2'b10;
        else if (uses_rs2 && mem_wb_reg_write_i && (mem_wb_rd_i != 5'd0) && (mem_wb_rd_i == rs2_i))
            forward_b_o = 2'b01;
        else
            forward_b_o = 2'b00;
    end
endmodule
