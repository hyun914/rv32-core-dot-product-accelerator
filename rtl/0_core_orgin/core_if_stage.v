`timescale 1ns/1ps

// IF stage: PC, instruction fetch from synchronous IMEM (1-cycle latency),
// and the IF/ID pipeline register.
//   stall_i        : load-use hazard from ID. Freezes PC and IF/ID and
//                    re-issues the pending fetch.
//   branch_taken_i : redirect from EX. Loads the target into PC, flushes
//                    IF/ID and squashes the fetch that is already in flight.
module core_if_stage (
    input              clk_i,
    input              rst_ni,
    input              stall_i,
    input              branch_taken_i,
    input      [31:0]  branch_target_i,
    // IMEM
    input      [31:0]  imem_rd_data_i,
    output wire [31:0] imem_addr_o,
    output wire        imem_read_o,
    // IF/ID
    output reg [31:0]  if_id_pc_o,
    output reg [31:0]  if_id_instr_o
);

    reg  [31:0] pc_reg;         // address being issued to IMEM
    reg  [31:0] pc_fetch_reg;   // PC of the word IMEM returns this cycle

    wire [31:0] pc_plus_4 = pc_reg + 32'd4;
    wire [31:0] pc_next   = branch_taken_i ? branch_target_i : pc_plus_4;

    // Drops the IMEM word arriving next cycle: after a taken branch it is the
    // wrong path; right after reset it is the word fetched for pc 0 while still
    // in reset, and pc 0 is fetched again by the first real cycle.
    reg squash_fetch;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) squash_fetch <= 1'b1;
        else         squash_fetch <= branch_taken_i;
    end

    // stall_i and branch_taken_i are never high together: a stall needs a LW
    // in EX, a taken branch needs a branch/jump in EX.
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pc_reg       <= 32'b0;
            pc_fetch_reg <= 32'b0;
        end else if (!stall_i) begin
            pc_fetch_reg <= pc_reg;
            pc_reg       <= pc_next;
        end
    end

    // During a stall IF/ID is frozen, so the word for pc_fetch_reg arriving
    // this cycle would be lost. Re-issue pc_fetch_reg so the same word comes
    // back in the cycle the stall releases.
    assign imem_addr_o = stall_i ? pc_fetch_reg : pc_reg;
    assign imem_read_o = 1'b1;

    // IF/ID Pipeline Register
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            if_id_pc_o    <= 32'b0;
            if_id_instr_o <= 32'h00000013; // NOP
        end else if (branch_taken_i) begin
            if_id_pc_o    <= 32'b0;
            if_id_instr_o <= 32'h00000013; // flush
        end else if (!stall_i) begin
            if (squash_fetch) begin
                if_id_pc_o    <= 32'b0;
                if_id_instr_o <= 32'h00000013; // NOP
            end else begin
                if_id_pc_o    <= pc_fetch_reg;
                if_id_instr_o <= imem_rd_data_i;
            end
        end
    end

endmodule
