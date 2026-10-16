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

    // DMEM read is assumed combinational (data valid in the same cycle as the
    // address). The load-use handling below relies on this.

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

    // MEM->ID bypass: a load in EX/MEM has its data on dmem_rd_data_i this
    // cycle, so the instruction in ID takes it directly into ID/EX.
    wire ex_mem_dmem_fwd_rs1 = ex_mem_mem_read && (ex_mem_rd != 5'b0)
        && (ex_mem_rd == id_rs1);
    wire ex_mem_dmem_fwd_rs2 = ex_mem_mem_read && (ex_mem_rd != 5'b0)
        && (ex_mem_rd == id_rs2);

    wire [31:0] id_rs1_after_rf = id_rs1_data;
    wire [31:0] id_rs1_after_wb = wb_bypass_rs1 ? wb_write_data_eff : id_rs1_after_rf;
    wire [31:0] id_rs1_data_fix  = ex_mem_dmem_fwd_rs1 ? dmem_rd_data_i : id_rs1_after_wb;
    wire [31:0] id_rs2_after_rf = id_rs2_data;
    wire [31:0] id_rs2_after_wb = wb_bypass_rs2 ? wb_write_data_eff : id_rs2_after_rf;
    wire [31:0] id_rs2_data_fix  = ex_mem_dmem_fwd_rs2 ? dmem_rd_data_i : id_rs2_after_wb;

    // Load-use: LW in EX (ID/EX) and the instruction in ID reads its rd.
    // The load data only exists once the LW reaches MEM, so stall PC + IF/ID
    // for one cycle and send a bubble into ID/EX. On the next cycle the LW is
    // in EX/MEM and the MEM->ID bypass above supplies the operand.
    wire load_use_hazard =
        id_ex_mem_read && (id_ex_rd != 5'b0)
        && ((id_ex_rd == id_rs1) || (id_ex_rd == id_rs2));

    wire stall = load_use_hazard;

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
    // Bubble ID/EX on a taken branch (flush) or a load-use stall. The LW itself
    // has already moved on to EX/MEM, so the bubble only replaces the stalled
    // instruction's slot.
    wire id_ex_bubble = branch_taken || load_use_hazard;

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
    // EX/MEM never stalls: on a load-use stall the LW moves on into EX/MEM
    // while the bubble enters ID/EX behind it.
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
        end else begin
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
