`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// core_if_stage
//   - PC register, PC+4, branch redirect, squash on branch_taken
//   - Drives synchronous IMEM (1-cycle latency)
//   - Owns the IF/ID pipeline register (if_id_pc, if_id_instr)
//
// Behavior is identical to the inline IF logic that previously lived in core.v.
// Stall (load-use hazard) freezes PC and IF/ID; branch_taken flushes IF/ID to
// NOP (0x00000013) and squashes the in-flight fetch on the next cycle.
// -----------------------------------------------------------------------------

module core_if_stage (
    input              clk_i,
    input              rst_ni,

    // Hazard / control inputs
    input              stall_i,
    input              branch_taken_i,
    input  [31:0]      branch_target_i,

    // IMEM interface
    input  [31:0]      imem_rd_data_i,
    output wire [31:0] imem_addr_o,
    output wire        imem_read_o,

    // IF/ID outputs to ID stage
    output reg  [31:0] if_id_pc_o,
    output reg  [31:0] if_id_instr_o
);

    reg [31:0] pc_reg;
    reg [31:0] pc_fetch_reg;
    reg        squash_fetch;

    wire [31:0] pc_plus_4 = pc_reg + 32'd4;
    wire [31:0] pc_next   = branch_taken_i ? branch_target_i : pc_plus_4;

    // Squash flag: when branch is taken in EX, the instruction already issued
    // into IMEM addr (pc_fetch_reg) is wrong; mark it so IF/ID writes a NOP.
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) squash_fetch <= 1'b0;
        else         squash_fetch <= branch_taken_i;
    end

    // PC register (frozen on stall)
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pc_reg       <= 32'b0;
            pc_fetch_reg <= 32'b0;
        end else if (!stall_i) begin
            pc_fetch_reg <= pc_reg;
            pc_reg       <= pc_next;
        end
    end

    assign imem_addr_o = pc_reg;
    assign imem_read_o = 1'b1;

    // IF/ID pipeline register
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            if_id_pc_o    <= 32'b0;
            if_id_instr_o <= 32'h00000013;     // NOP
        end else if (branch_taken_i) begin
            if_id_pc_o    <= 32'b0;
            if_id_instr_o <= 32'h00000013;
        end else if (!stall_i) begin
            if (squash_fetch) begin
                if_id_pc_o    <= 32'b0;
                if_id_instr_o <= 32'h00000013;
            end else begin
                if_id_pc_o    <= pc_fetch_reg;
                if_id_instr_o <= imem_rd_data_i;
            end
        end
    end

endmodule
