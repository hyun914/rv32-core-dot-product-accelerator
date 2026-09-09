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

    // 1. IF Stage (IMEM sync 1-cycle latency)

    reg  [31:0] pc_reg;
    reg  [31:0] pc_fetch_reg;

    wire [31:0] pc_plus_4 = pc_reg + 32'd4;

    wire        branch_taken;
    wire [31:0] branch_target;
    wire [31:0] pc_next = branch_taken ? branch_target : pc_plus_4;


    wire stall = 1'b0;


    reg squash_fetch;
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) squash_fetch <= 1'b0;
        else         squash_fetch <= branch_taken;
    end

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            pc_reg       <= 32'b0;
            pc_fetch_reg <= 32'b0;
        end else if (!stall) begin
            pc_fetch_reg <= pc_reg;
            pc_reg       <= pc_next;
        end
    end

    assign imem_addr_o = pc_reg;
    assign imem_read_o = 1'b1;


    // 2. IF/ID Pipeline Register

    reg [31:0] if_id_pc;
    reg [31:0] if_id_instr;

    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            if_id_pc    <= 32'b0;
            if_id_instr <= 32'h00000013; // NOP
        end else if (branch_taken) begin
            if_id_pc    <= 32'b0;
            if_id_instr <= 32'h00000013; // flush
        end else if (!stall) begin
            if (squash_fetch) begin
                if_id_pc    <= 32'b0;
                if_id_instr <= 32'h00000013; // NOP
            end else begin
                if_id_pc    <= pc_fetch_reg;
                if_id_instr <= imem_rd_data_i;
            end
        end
    end


    // 3. ID Stage

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

    // 4. WB regs + LOAD pending WB (sync DMEM)
    reg [31:0] ex_wb_pc;
    reg [31:0] ex_wb_alu_result;
    reg [4:0]  ex_wb_rd;
    reg        ex_wb_reg_write;
    reg [1:0]  ex_wb_mem_to_reg;

    reg        load_wb_valid;
    reg [4:0]  load_wb_rd;

    wire        wb_reg_write_eff = ex_wb_reg_write | load_wb_valid;
    wire [4:0]  wb_rd_eff        = load_wb_valid ? load_wb_rd : ex_wb_rd;

    wire [31:0] wb_write_data_eff =
        load_wb_valid                    ? dmem_rd_data_i :
        (ex_wb_mem_to_reg == 2'b10)       ? (ex_wb_pc + 32'd4) :
                                            ex_wb_alu_result;

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

    // WB->ID bypass (effective WB: load pending을 포함해야된다......후)
    wire wb_bypass_rs1 = wb_reg_write_eff && (wb_rd_eff != 5'd0) && (wb_rd_eff == id_rs1);
    wire wb_bypass_rs2 = wb_reg_write_eff && (wb_rd_eff != 5'd0) && (wb_rd_eff == id_rs2);

    wire [31:0] id_rs1_data_fix = wb_bypass_rs1 ? wb_write_data_eff : id_rs1_data;
    wire [31:0] id_rs2_data_fix = wb_bypass_rs2 ? wb_write_data_eff : id_rs2_data;

    // 5. ID/EX Pipeline Register
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
        end else if (branch_taken) begin
            // flush / bubble
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
        end else if (!stall) begin
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

    // 6. EX Stage + forwarding
    wire forward_a, forward_b;

    forwarding_unit u_fwd (
        .rs1_i           (id_ex_rs1_addr),
        .rs2_i           (id_ex_rs2_addr),
        .wb_reg_write_i  (wb_reg_write_eff),
        .wb_rd_i         (wb_rd_eff),
        .forward_a_o     (forward_a),
        .forward_b_o     (forward_b)
    );

    wire [31:0] ex_rs1_val = forward_a ? wb_write_data_eff : id_ex_rs1_data;
    wire [31:0] ex_rs2_val = forward_b ? wb_write_data_eff : id_ex_rs2_data;
    wire [31:0] ex_alu_result;

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

    // 7. Memory interface
    assign dmem_addr_o    = ex_alu_result;
    assign dmem_read_o    = id_ex_mem_read;   
    assign dmem_write_o   = id_ex_mem_write;
    assign dmem_wr_data_o = ex_rs2_val;

    // 8. WB regs update (ALU/JAL immediate, LOAD pending)
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ex_wb_pc         <= 32'b0;
            ex_wb_alu_result <= 32'b0;
            ex_wb_rd         <= 5'b0;
            ex_wb_reg_write  <= 1'b0;
            ex_wb_mem_to_reg <= 2'b0;

            load_wb_valid    <= 1'b0;
            load_wb_rd       <= 5'b0;
        end else begin
            load_wb_valid <= id_ex_mem_read;
            load_wb_rd    <= id_ex_rd;

            ex_wb_pc         <= id_ex_pc;
            ex_wb_alu_result <= ex_alu_result;
            ex_wb_rd         <= id_ex_rd;
            ex_wb_mem_to_reg <= id_ex_mem_to_reg;
            ex_wb_reg_write  <= id_ex_reg_write & ~id_ex_mem_read;
        end
    end

endmodule
