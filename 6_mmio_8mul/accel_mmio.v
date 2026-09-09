`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// accel_mmio — Memory-mapped wrapper around dot_product.
//
// Standard RV32I lw/sw drive the accelerator instead of Custom-0 opcodes.
// Address map (relative to MMIO base; the wrapper decodes only the low 8 bits):
//
//   0x00 (write) : BUF_A_LO  — packed 4xINT8, buf_a[0..3]
//   0x04 (write) : BUF_A_HI  — buf_a[4..7]
//   0x08 (write) : BUF_B_LO  — buf_b[0..3]
//   0x0C (write) : BUF_B_HI  — buf_b[4..7]
//   0x10 (read)  : RESULT    — latched DOTPROD result
//   0x14 (write) : TRIGGER   — any write triggers DOTPROD compute
//
// Reads to any other offset return 0. This module is intended to live inside a
// top-level wrapper that decodes the high address bits to gate write_en / read_en.
// -----------------------------------------------------------------------------

module accel_mmio (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [7:0]  addr_i,       // low byte of MMIO address (offset)
    input  wire        we_i,         // write enable (filtered by top decoder)
    input  wire [31:0] wdata_i,

    output wire [31:0] rdata_o
);

    // Internal accelerator control derived from address + we
    wire is_a_lo  = we_i && (addr_i == 8'h00);
    wire is_a_hi  = we_i && (addr_i == 8'h04);
    wire is_b_lo  = we_i && (addr_i == 8'h08);
    wire is_b_hi  = we_i && (addr_i == 8'h0C);
    wire is_trig  = we_i && (addr_i == 8'h14);

    wire load_a_en = is_a_lo || is_a_hi;
    wire load_b_en = is_b_lo || is_b_hi;
    wire load_idx  = is_a_hi || is_b_hi;
    wire compute_en = is_trig;

    // The accelerator already has the load-a / load-b mux on the data_i port,
    // so we just feed wdata_i regardless (both loads use it).
    wire [31:0] result_w;

    dot_product_8mul u_dp (
        .clk          (clk),
        .rst_n        (rst_n),
        .data_i       (wdata_i),
        .load_a_en_i  (load_a_en),
        .load_b_en_i  (load_b_en),
        .load_idx_i   (load_idx),
        .compute_en_i (compute_en),
        .result_o     (result_w)
    );

    // RESULT register — already latched inside dot_product after DOTPROD.
    // The wrapper just exposes it (read at 0x10).
    assign rdata_o = (addr_i == 8'h10) ? result_w : 32'h0;

endmodule
