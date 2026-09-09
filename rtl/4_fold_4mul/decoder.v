`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// decoder
//   - Pure combinational control unit.
//   - Behavior is identical to the inline control `always @(*)` block that
//     previously lived in core_id_stage.v.
//   - Note: CUSTOM-0 reg_write depends on funct3 (only DOTPROD writes back).
// -----------------------------------------------------------------------------

`define OPCODE_CUSTOM_0 7'b0001011
`define OPCODE_R        7'b0110011
`define OPCODE_I        7'b0010011
`define OPCODE_BRANCH   7'b1100011
`define OPCODE_STORE    7'b0100011
`define OPCODE_LOAD     7'b0000011
`define OPCODE_JALR     7'b1100111
`define OPCODE_JAL      7'b1101111
`define OPCODE_AUIPC    7'b0010111
`define OPCODE_LUI      7'b0110111

module decoder (
    input  [6:0] opcode_i,
    input  [2:0] funct3_i,

    output reg        reg_write_o,
    output reg        mem_read_o,
    output reg        mem_write_o,
    output reg [1:0]  mem_to_reg_o
);

    always @(*) begin
        reg_write_o  = 1'b0;
        mem_read_o   = 1'b0;
        mem_write_o  = 1'b0;
        mem_to_reg_o = 2'b00;

        case (opcode_i)
            `OPCODE_CUSTOM_0: begin
                // Only DOTPROD (funct3 == 3'b100) writes back.
                // VLOAD_A / VLOAD_B push data into the accelerator buffers
                // and must NOT clobber the architectural register file.
                reg_write_o  = (funct3_i == 3'b100) ? 1'b1 : 1'b0;
                mem_to_reg_o = 2'b00;
            end
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
