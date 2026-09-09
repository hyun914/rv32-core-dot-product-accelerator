`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// core_mmio_top — wraps `core` so that accesses to 0xF000_00xx are routed to a
// memory-mapped dot_product accelerator instead of external DMEM.
//
// External pins are the same as `core` so the testbench is drop-in.
// External DMEM sees only non-MMIO accesses (writes are gated; reads still
// emit the address but the core internally muxes its rdata).
//
// The accelerator inside this wrapper is the plain 8-mul `dot_product` (NOT
// custom-opcode plumbed). The core itself is compiled with -DNO_ACCEL so its
// EX stage does NOT instance another dot_product; the only path to the accel
// is the MMIO region.
// -----------------------------------------------------------------------------

module core_mmio_top (
    input              clk_i,
    input              rst_ni,
    // IMEM
    input  [31:0]      imem_rd_data_i,
    output wire [31:0] imem_addr_o,
    output wire        imem_read_o,
    // DMEM (external — sees non-MMIO traffic only)
    input  [31:0]      dmem_rd_data_i,
    output wire [31:0] dmem_addr_o,
    output wire        dmem_read_o,
    output wire        dmem_write_o,
    output wire [31:0] dmem_wr_data_o
);

    wire [31:0] core_dmem_addr;
    wire        core_dmem_read;
    wire        core_dmem_write;
    wire [31:0] core_dmem_wdata;
    wire [31:0] core_dmem_rdata;

    // MMIO range: 0xF000_00xx (8-bit offset, 256 bytes window)
    wire is_mmio = (core_dmem_addr[31:24] == 8'hF0)
                && (core_dmem_addr[23:8]  == 16'h0000);

    wire [31:0] mmio_rdata;
    accel_mmio u_mmio (
        .clk     (clk_i),
        .rst_n   (rst_ni),
        .addr_i  (core_dmem_addr[7:0]),
        .we_i    (is_mmio && core_dmem_write),
        .wdata_i (core_dmem_wdata),
        .rdata_o (mmio_rdata)
    );

    // External DMEM: don't expose MMIO writes/reads. Address still drives
    // external bus, but write/read enables are gated.
    assign dmem_addr_o    = core_dmem_addr;
    assign dmem_read_o    = core_dmem_read  && !is_mmio;
    assign dmem_write_o   = core_dmem_write && !is_mmio;
    assign dmem_wr_data_o = core_dmem_wdata;

    // Mux rdata back to core: MMIO when address is in range, else external.
    assign core_dmem_rdata = is_mmio ? mmio_rdata : dmem_rd_data_i;

    core u_core (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .imem_rd_data_i (imem_rd_data_i),
        .imem_addr_o    (imem_addr_o),
        .imem_read_o    (imem_read_o),
        .dmem_rd_data_i (core_dmem_rdata),
        .dmem_addr_o    (core_dmem_addr),
        .dmem_read_o    (core_dmem_read),
        .dmem_write_o   (core_dmem_write),
        .dmem_wr_data_o (core_dmem_wdata)
    );

endmodule
