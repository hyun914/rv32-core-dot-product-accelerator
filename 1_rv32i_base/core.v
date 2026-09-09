`timescale 1ns/1ps

module core (
    input  clk_i,
    input  rst_ni,
    // IMEM
    input  [31:0] imem_rd_data_i,
    output wire [31:0] imem_addr_o,
    output wire        imem_read_o,
    // DMEM
    input  [31:0] dmem_rd_data_i,
    output wire [31:0] dmem_addr_o,
    output wire        dmem_read_o,
    output wire        dmem_write_o,
    output wire [31:0] dmem_wr_data_o
);

    localparam ASYNC_DMEM_RD = 1'b1;

    // -------------------------------------------------------------------------
    // Pipeline registers (declare before hazard / forwarding references)
    // -------------------------------------------------------------------------
    // IF stage internals (PC, pc_fetch_reg, squash_fetch) and the IF/ID
    // pipeline register live inside `core_if_stage`. We only need their outputs
    // here.
    wire [31:0] if_id_pc;
    wire [31:0] if_id_instr;

    reg [31:0] id_ex_pc;
    reg [31:0] id_ex_rs1_data;
    reg [31:0] id_ex_rs2_data;
    reg [31:0] id_ex_imm;
    reg [4:0]  id_ex_rs1_addr;
    reg [4:0]  id_ex_rs2_addr;
    reg [4:0]  id_ex_rd;
    reg [6:0]  id_ex_opcode;
    reg [2:0]  id_ex_funct3;
    reg [6:0]  id_ex_funct7;
    reg        id_ex_reg_write;
    reg [1:0]  id_ex_mem_to_reg;
    reg        id_ex_mem_read;
    reg        id_ex_mem_write;

    reg [31:0] ex_mem_pc;
    reg [31:0] ex_mem_alu_result;
    reg [31:0] ex_mem_store_data;
    reg [4:0]  ex_mem_rd;
    reg        ex_mem_reg_write;
    reg [1:0]  ex_mem_mem_to_reg;
    reg        ex_mem_mem_read;
    reg        ex_mem_mem_write;

    reg [31:0] mem_wb_pc;
    reg [31:0] mem_wb_alu_result;
    reg [31:0] mem_wb_mem_rdata;
    reg [4:0]  mem_wb_rd;
    reg        mem_wb_reg_write;
    reg [1:0]  mem_wb_mem_to_reg;

    // -------------------------------------------------------------------------
    // ID Stage (combinational decode + RF read)
    // -------------------------------------------------------------------------
    wire [6:0]  id_opcode;
    wire [4:0]  id_rd;
    wire [2:0]  id_funct3;
    wire [4:0]  id_rs1;
    wire [4:0]  id_rs2;
    wire [6:0]  id_funct7;
    wire        id_mem_read;
    wire        id_mem_write;
    wire        id_reg_write;
    wire [1:0]  id_mem_to_reg;
    wire [31:0] id_imm;
    wire [31:0] id_rs1_data;
    wire [31:0] id_rs2_data;

    // -------------------------------------------------------------------------
    // WB Stage (3-way write-back MUX)
    // -------------------------------------------------------------------------
    wire [31:0] wb_write_data_eff;

    core_wb_stage u_wb (
        .mem_to_reg_i (mem_wb_mem_to_reg),
        .alu_result_i (mem_wb_alu_result),
        .mem_rdata_i  (mem_wb_mem_rdata),
        .pc_plus_4_i  (mem_wb_pc + 32'd4),
        .rd_din_o     (wb_write_data_eff)
    );

    wire wb_reg_write_eff = mem_wb_reg_write;
    wire [4:0] wb_rd_eff  = mem_wb_rd;

    core_id_stage core_ID (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),
        .instr_i         (if_id_instr),
        .rd_din_i        (wb_write_data_eff),
        .wb_rd_i         (wb_rd_eff),
        .wb_reg_write_i  (wb_reg_write_eff),

        .opcode_o        (id_opcode),
        .rd_o            (id_rd),
        .funct3_o        (id_funct3),
        .rs1_o           (id_rs1),
        .rs2_o           (id_rs2),
        .funct7_o        (id_funct7),
        .mem_read_o      (id_mem_read),
        .mem_write_o     (id_mem_write),
        .reg_write_o     (id_reg_write),
        .mem_to_reg_o    (id_mem_to_reg),
        .imm_o           (id_imm),
        .rs1_dout_o      (id_rs1_data),
        .rs2_dout_o      (id_rs2_data)
    );

    wire wb_bypass_rs1 = wb_reg_write_eff && (wb_rd_eff != 5'd0) && (wb_rd_eff == id_rs1);
    wire wb_bypass_rs2 = wb_reg_write_eff && (wb_rd_eff != 5'd0) && (wb_rd_eff == id_rs2);

    wire ex_mem_dmem_fwd_rs1 = ASYNC_DMEM_RD && ex_mem_mem_read && (ex_mem_rd != 5'b0)
        && (ex_mem_rd == id_rs1);
    wire ex_mem_dmem_fwd_rs2 = ASYNC_DMEM_RD && ex_mem_mem_read && (ex_mem_rd != 5'b0)
        && (ex_mem_rd == id_rs2);

    wire [31:0] id_rs1_after_rf = id_rs1_data;
    wire [31:0] id_rs1_after_wb = wb_bypass_rs1 ? wb_write_data_eff : id_rs1_after_rf;
    wire [31:0] id_rs1_data_fix  = ex_mem_dmem_fwd_rs1 ? dmem_rd_data_i : id_rs1_after_wb;
    wire [31:0] id_rs2_after_rf = id_rs2_data;
    wire [31:0] id_rs2_after_wb = wb_bypass_rs2 ? wb_write_data_eff : id_rs2_after_rf;
    wire [31:0] id_rs2_data_fix  = ex_mem_dmem_fwd_rs2 ? dmem_rd_data_i : id_rs2_after_wb;

    // Load-use: stall IF/ID+PC until load result is reachable (MEM/WB bypass to ID)
    // For LW in EX/MEM, clear stall when MEM/WB holds the completed load (same rd)
    // and IF/ID still names that register (so WB→ID bypass supplies the operand).
    wire mem_wb_holds_ex_mem_load =
        ex_mem_mem_read && (ex_mem_rd != 5'b0)
        && (mem_wb_mem_to_reg == 2'b01) && mem_wb_reg_write
        && (mem_wb_rd == ex_mem_rd)
        && ((ex_mem_rd == id_rs1) || (ex_mem_rd == id_rs2));

    wire load_use_p1_base =
        id_ex_mem_read && (id_ex_rd != 5'b0)
        && ((id_ex_rd == id_rs1) || (id_ex_rd == id_rs2));
    // With async DMEM, the LW in EX/MEM is the same instruction as the LW still
    // registered in ID/EX (same rd); dmem_rd_data_i + MEM→ID bypass feeds IF/ID.
    wire load_use_p1_clear_async =
        ASYNC_DMEM_RD && ex_mem_mem_read && (ex_mem_rd != 5'b0)
        && (ex_mem_rd == id_ex_rd);
    wire load_use_p1 = load_use_p1_base && !load_use_p1_clear_async;

    wire load_use_hazard =
        load_use_p1
        || (!ASYNC_DMEM_RD && ex_mem_mem_read && (ex_mem_rd != 5'b0)
            && ((ex_mem_rd == id_rs1) || (ex_mem_rd == id_rs2))
            && !mem_wb_holds_ex_mem_load);

    wire load_ex_mem_raw_hazard =
        ex_mem_mem_read && (ex_mem_rd != 5'b0)
        && ((ex_mem_rd == id_ex_rs1_addr) || (ex_mem_rd == id_ex_rs2_addr));

    wire stall = load_use_hazard || load_ex_mem_raw_hazard;

    // IF/ID waits on a load still in EX/MEM (MEM-stage RAW): do not freeze EX/MEM
    // while ID/EX is a bubble — that traps the LW in EX/MEM forever with no way
    // for mem_wb_holds to ever latch the completed load.
    wire load_use_part2_ifid =
        ex_mem_mem_read && (ex_mem_rd != 5'b0)
        && ((ex_mem_rd == id_rs1) || (ex_mem_rd == id_rs2));

    // -------------------------------------------------------------------------
    // IF Stage (PC, IMEM addr, IF/ID register all encapsulated)
    // -------------------------------------------------------------------------
    wire        branch_taken;
    wire [31:0] branch_target;

    core_if_stage u_if (
        .clk_i           (clk_i),
        .rst_ni          (rst_ni),
        .stall_i         (stall),
        .branch_taken_i  (branch_taken),
        .branch_target_i (branch_target),
        .imem_rd_data_i  (imem_rd_data_i),
        .imem_addr_o     (imem_addr_o),
        .imem_read_o     (imem_read_o),
        .if_id_pc_o      (if_id_pc),
        .if_id_instr_o   (if_id_instr)
    );


    // -------------------------------------------------------------------------
    // ID/EX Pipeline Register
    // -------------------------------------------------------------------------
    // Do not bubble ID/EX when it holds an LW that IF/ID is waiting on (load-use
    // part 1). Bubbling would NOP out the second LW before it reaches EX/MEM,
    // breaking patterns like LW; LW; BLT (tb_core bubble sort).
    wire id_ex_bubble = branch_taken || (load_use_hazard && !id_ex_mem_read);

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            id_ex_pc         <= 32'b0;
            id_ex_rs1_data   <= 32'b0;
            id_ex_rs2_data   <= 32'b0;
            id_ex_imm        <= 32'b0;
            id_ex_rs1_addr   <= 5'b0;
            id_ex_rs2_addr   <= 5'b0;
            id_ex_rd         <= 5'b0;
            id_ex_opcode     <= 7'b0;
            id_ex_funct3     <= 3'b0;
            id_ex_funct7     <= 7'b0;
            id_ex_reg_write  <= 1'b0;
            id_ex_mem_to_reg <= 2'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
        end else if (stall && load_ex_mem_raw_hazard) begin
            // LW in EX/MEM, dependent op in EX: hold ID/EX one cycle for MEM/WB bypass.
            id_ex_pc         <= id_ex_pc;
            id_ex_rs1_data   <= id_ex_rs1_data;
            id_ex_rs2_data   <= id_ex_rs2_data;
            id_ex_imm        <= id_ex_imm;
            id_ex_rs1_addr   <= id_ex_rs1_addr;
            id_ex_rs2_addr   <= id_ex_rs2_addr;
            id_ex_rd         <= id_ex_rd;
            id_ex_opcode     <= id_ex_opcode;
            id_ex_funct3     <= id_ex_funct3;
            id_ex_funct7     <= id_ex_funct7;
            id_ex_reg_write  <= id_ex_reg_write;
            id_ex_mem_to_reg <= id_ex_mem_to_reg;
            id_ex_mem_read   <= id_ex_mem_read;
            id_ex_mem_write  <= id_ex_mem_write;
        end else if (stall && id_ex_mem_read && (id_ex_rd != 5'b0)
                    && ((id_ex_rd == id_rs1) || (id_ex_rd == id_rs2))) begin
            // Load-use part 1: hold LW in ID/EX while IF/ID waits (see id_ex_bubble).
            id_ex_pc         <= id_ex_pc;
            id_ex_rs1_data   <= id_ex_rs1_data;
            id_ex_rs2_data   <= id_ex_rs2_data;
            id_ex_imm        <= id_ex_imm;
            id_ex_rs1_addr   <= id_ex_rs1_addr;
            id_ex_rs2_addr   <= id_ex_rs2_addr;
            id_ex_rd         <= id_ex_rd;
            id_ex_opcode     <= id_ex_opcode;
            id_ex_funct3     <= id_ex_funct3;
            id_ex_funct7     <= id_ex_funct7;
            id_ex_reg_write  <= id_ex_reg_write;
            id_ex_mem_to_reg <= id_ex_mem_to_reg;
            id_ex_mem_read   <= id_ex_mem_read;
            id_ex_mem_write  <= id_ex_mem_write;
        end else if (id_ex_bubble) begin
            id_ex_pc         <= 32'b0;
            id_ex_rs1_data   <= 32'b0;
            id_ex_rs2_data   <= 32'b0;
            id_ex_imm        <= 32'b0;
            id_ex_rs1_addr   <= 5'b0;
            id_ex_rs2_addr   <= 5'b0;
            id_ex_rd         <= 5'b0;
            id_ex_opcode     <= 7'b0;
            id_ex_funct3     <= 3'b0;
            id_ex_funct7     <= 7'b0;
            id_ex_reg_write  <= 1'b0;
            id_ex_mem_to_reg <= 2'b0;
            id_ex_mem_read   <= 1'b0;
            id_ex_mem_write  <= 1'b0;
        end else begin
            id_ex_pc         <= if_id_pc;
            id_ex_rs1_data   <= id_rs1_data_fix;
            id_ex_rs2_data   <= id_rs2_data_fix;
            id_ex_imm        <= id_imm;
            id_ex_rs1_addr   <= id_rs1;
            id_ex_rs2_addr   <= id_rs2;
            id_ex_rd         <= id_rd;
            id_ex_opcode     <= id_opcode;
            id_ex_funct3     <= id_funct3;
            id_ex_funct7     <= id_funct7;
            id_ex_reg_write  <= id_reg_write;
            id_ex_mem_to_reg <= id_mem_to_reg;
            id_ex_mem_read   <= id_mem_read;
            id_ex_mem_write  <= id_mem_write;
        end
    end


    // -------------------------------------------------------------------------
    // EX Stage + forwarding
    // -------------------------------------------------------------------------
    wire [31:0] ex_rs1_val;
    wire [31:0] ex_rs2_val;
    wire [31:0] ex_alu_result;

    forwarding_unit u_fwd (
        .rs1_i                 (id_ex_rs1_addr),
        .rs2_i                 (id_ex_rs2_addr),
        .id_ex_rs1_data_i      (id_ex_rs1_data),
        .id_ex_rs2_data_i      (id_ex_rs2_data),
        .ex_mem_reg_write_i    (ex_mem_reg_write),
        .ex_mem_mem_read_i     (ex_mem_mem_read),
        .ex_mem_rd_i           (ex_mem_rd),
        .ex_mem_alu_result_i   (ex_mem_alu_result),
        .ex_mem_pc_i           (ex_mem_pc),
        .ex_mem_mem_to_reg_i   (ex_mem_mem_to_reg),
        .mem_wb_reg_write_i    (mem_wb_reg_write),
        .mem_wb_rd_i           (mem_wb_rd),
        .mem_wb_mem_to_reg_i   (mem_wb_mem_to_reg),
        .mem_wb_pc_i           (mem_wb_pc),
        .mem_wb_alu_i          (mem_wb_alu_result),
        .mem_wb_mem_rdata_i    (mem_wb_mem_rdata),
        .rs1_fwd_o             (ex_rs1_val),
        .rs2_fwd_o             (ex_rs2_val)
    );

    core_ex_stage u_ex (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .opcode_i     (id_ex_opcode),
        .funct3_i     (id_ex_funct3),
        .funct7_i     (id_ex_funct7),
        .rs1_dout_i   (ex_rs1_val),
        .rs2_dout_i   (ex_rs2_val),
        .imm_i        (id_ex_imm),
        .pc_i         (id_ex_pc),
        .alu_result_o (ex_alu_result)
    );

    branch_unit u_br (
        .opcode_i       (id_ex_opcode),
        .funct3_i       (id_ex_funct3),
        .pc_i           (id_ex_pc),
        .rs1_dout_i     (ex_rs1_val),
        .rs2_dout_i     (ex_rs2_val),
        .imm_i          (id_ex_imm),
        .branch_taken_o (branch_taken),
        .pc_branch_o    (branch_target)
    );


    // -------------------------------------------------------------------------
    // EX/MEM Pipeline Register
    // -------------------------------------------------------------------------
    // Freeze EX/MEM only while stalling with LW already out of ID/EX (bubble there);
    // first stall cycle must still shift LW from EX into EX/MEM
    // Freeze EX/MEM only on classic load-use (ID/EX bubbled to NOP so EX/MEM still
    // holds an LW). When load-use part 1 *holds* an LW in ID/EX, do NOT freeze —
    // the LW already in EX/MEM must retire into MEM/WB.
    wire load_use_part1_ifid =
        id_ex_mem_read && (id_ex_rd != 5'b0)
        && ((id_ex_rd == id_rs1) || (id_ex_rd == id_rs2));
    wire freeze_ex_mem = stall && !id_ex_mem_read && !load_ex_mem_raw_hazard
        && !load_use_part1_ifid && !load_use_part2_ifid;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ex_mem_pc         <= 32'b0;
            ex_mem_alu_result <= 32'b0;
            ex_mem_store_data <= 32'b0;
            ex_mem_rd         <= 5'b0;
            ex_mem_reg_write  <= 1'b0;
            ex_mem_mem_to_reg <= 2'b0;
            ex_mem_mem_read   <= 1'b0;
            ex_mem_mem_write  <= 1'b0;
        end else if (!freeze_ex_mem) begin
            ex_mem_pc         <= id_ex_pc;
            ex_mem_alu_result <= ex_alu_result;
            ex_mem_store_data <= ex_rs2_val;
            ex_mem_rd         <= id_ex_rd;
            ex_mem_reg_write  <= id_ex_reg_write;
            ex_mem_mem_to_reg <= id_ex_mem_to_reg;
            ex_mem_mem_read   <= id_ex_mem_read;
            ex_mem_mem_write  <= id_ex_mem_write;
        end
    end


    // -------------------------------------------------------------------------
    // MEM Stage (DMEM driven only from EX/MEM)
    // -------------------------------------------------------------------------
    assign dmem_addr_o    = ex_mem_alu_result;
    assign dmem_read_o    = ex_mem_mem_read;
    assign dmem_write_o   = ex_mem_mem_write;
    assign dmem_wr_data_o = ex_mem_store_data;


    // -------------------------------------------------------------------------
    // MEM/WB Pipeline Register
    // -------------------------------------------------------------------------
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            mem_wb_pc         <= 32'b0;
            mem_wb_alu_result <= 32'b0;
            mem_wb_mem_rdata  <= 32'b0;
            mem_wb_rd         <= 5'b0;
            mem_wb_reg_write  <= 1'b0;
            mem_wb_mem_to_reg <= 2'b0;
        end else begin
            mem_wb_pc         <= ex_mem_pc;
            mem_wb_alu_result <= ex_mem_alu_result;
            mem_wb_mem_rdata  <= dmem_rd_data_i;
            mem_wb_rd         <= ex_mem_rd;
            mem_wb_reg_write  <= ex_mem_reg_write;
            mem_wb_mem_to_reg <= ex_mem_mem_to_reg;
        end
    end

endmodule
