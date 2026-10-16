`timescale 1ns/1ps

// EX stage: forwarding, ALU, branch resolution, DMEM request, and the EX/MEM
// pipeline register.
//   wb_*_i     : WB result, the MEM/WB forwarding source (EX/MEM forwarding
//                uses this stage's own EX/MEM register)
//   branch_*_o : Branch Unit -> IF (redirect) and IF/ID, ID/EX (flush)
//   mem_*_o    : DMEM request. Synchronous DMEM latches it on the EX->MEM
//                edge; it reaches the DMEM ports through the MEM stage.
module core_ex_stage (
    input         clk_i,
    input         rst_ni,
    // ID/EX
    input  [31:0] pc_i,
    input  [31:0] rs1_data_i,
    input  [31:0] rs2_data_i,
    input  [31:0] imm_i,
    input  [4:0]  rs1_i,
    input  [4:0]  rs2_i,
    input  [4:0]  rd_i,
    input  [6:0]  opcode_i,
    input  [2:0]  funct3_i,
    input  [6:0]  funct7_i,
    input         reg_write_i,
    input  [1:0]  mem_to_reg_i,
    input         mem_read_i,
    input         mem_write_i,
    // WB
    input         wb_reg_write_i,
    input  [4:0]  wb_rd_i,
    input  [31:0] wb_write_data_i,

    output        branch_taken_o,
    output [31:0] branch_target_o,
    // DMEM request
    output [31:0] mem_addr_o,
    output [31:0] mem_wr_data_o,
    output        mem_read_o,
    output        mem_write_o,
    // EX/MEM
    output reg [31:0] ex_mem_pc_o,        // waveform/debug only
    output reg [31:0] ex_mem_result_o,    // ALU result, or PC+4 for JAL/JALR
    output reg [4:0]  ex_mem_rd_o,
    output reg        ex_mem_reg_write_o,
    output reg [1:0]  ex_mem_mem_to_reg_o
);
    reg [3:0]  alu_op;
    reg [31:0] alu_in1, alu_in2;
    reg [31:0] alu_result;

    // Forwarding
    wire [1:0] forward_a, forward_b;

    forwarding_unit u_fwd (
        .opcode_i            (opcode_i),
        .rs1_i               (rs1_i),
        .rs2_i               (rs2_i),
        .ex_mem_reg_write_i  (ex_mem_reg_write_o),
        .ex_mem_rd_i         (ex_mem_rd_o),
        .mem_wb_reg_write_i  (wb_reg_write_i),
        .mem_wb_rd_i         (wb_rd_i),
        .forward_a_o         (forward_a),
        .forward_b_o         (forward_b)
    );

    wire [31:0] rs1_val = (forward_a == 2'b10) ? ex_mem_result_o :
                          (forward_a == 2'b01) ? wb_write_data_i :
                                                 rs1_data_i;
    wire [31:0] rs2_val = (forward_b == 2'b10) ? ex_mem_result_o :
                          (forward_b == 2'b01) ? wb_write_data_i :
                                                 rs2_data_i;

    // ALU Control
    always @(*) begin
        alu_op = 4'b0000; // default ADD
        case (opcode_i)
            7'b0110011: begin // R-type
                case (funct3_i)
                    3'b000: alu_op = (funct7_i == 7'b0100000) ? 4'b0011 : 4'b0000; // SUB/ADD
                    3'b001: alu_op = 4'b0100; // SLL
                    3'b010: alu_op = 4'b0101; // SLT
                    3'b011: alu_op = 4'b0110; // SLTU
                    3'b100: alu_op = 4'b0010; // XOR
                    3'b101: alu_op = (funct7_i == 7'b0100000) ? 4'b0111 : 4'b1000; // SRA/SRL
                    3'b110: alu_op = 4'b0001; // OR
                    3'b111: alu_op = 4'b1001; // AND
                    default: alu_op = 4'b0000;
                endcase
            end
            7'b0010011: begin // I-type (ADDI...)
                case (funct3_i)
                    3'b000: alu_op = 4'b0000;
                    3'b010: alu_op = 4'b0101; // SLTI
                    3'b011: alu_op = 4'b0110;
                    3'b100: alu_op = 4'b0010;
                    3'b110: alu_op = 4'b0001;
                    3'b111: alu_op = 4'b1001;
                    3'b001: alu_op = 4'b0100;
                    3'b101: alu_op = (funct7_i == 7'b0100000) ? 4'b0111 : 4'b1000;
                    default: alu_op = 4'b0000;
                endcase
            end
            // BRANCH (필수!)
            7'b1100011: begin
                case (funct3_i)
                    3'b000, 3'b001: alu_op = 4'b0011; // BEQ, BNE -> SUB
                    3'b100, 3'b101: alu_op = 4'b0101; // BLT, BGE -> SLT
                    default: alu_op = 4'b0011;
                endcase
            end
            7'b0110111: alu_op = 4'b1010; // LUI
            default: alu_op = 4'b0000;
        endcase
    end

    // ALU Mux
    always @(*) begin
        alu_in1 = rs1_val;
        alu_in2 = rs2_val;
        case (opcode_i)
            7'b0010011, 7'b0000011, 7'b0100011, 7'b1100111: alu_in2 = imm_i; // I, Load, Store, JALR
            7'b0110111: begin alu_in1 = 32'b0; alu_in2 = imm_i; end // LUI
            7'b0010111: begin alu_in1 = pc_i; alu_in2 = imm_i; end // AUIPC
            default: ;
        endcase
    end

    // ALU Op
    always @(*) begin
        case (alu_op)
            4'b0000: alu_result = alu_in1 + alu_in2;
            4'b0001: alu_result = alu_in1 | alu_in2;
            4'b0010: alu_result = alu_in1 ^ alu_in2;
            4'b0011: alu_result = alu_in1 - alu_in2;
            4'b0100: alu_result = alu_in1 << alu_in2[4:0];
            4'b0101: alu_result = ($signed(alu_in1) < $signed(alu_in2)) ? 32'd1 : 32'd0;
            4'b0110: alu_result = (alu_in1 < alu_in2) ? 32'd1 : 32'd0;
            4'b0111: alu_result = $signed(alu_in1) >>> alu_in2[4:0];
            4'b1000: alu_result = alu_in1 >> alu_in2[4:0];
            4'b1001: alu_result = alu_in1 & alu_in2;
            4'b1010: alu_result = alu_in2; // LUI Pass
            default: alu_result = 32'b0;
        endcase
    end

    // Branch Unit
    branch_unit u_br (
        .opcode_i       (opcode_i),
        .funct3_i       (funct3_i),
        .pc_i           (pc_i),
        .rs1_dout_i     (rs1_val),
        .rs2_dout_i     (rs2_val),
        .imm_i          (imm_i),
        .branch_taken_o (branch_taken_o),
        .pc_branch_o    (branch_target_o)
    );

    // JAL/JALR write PC+4. Selecting it here (in parallel with the ALU) lets
    // EX/MEM and MEM/WB carry one final result, so forwarding needs no adder.
    wire [31:0] result = (mem_to_reg_i == 2'b10) ? (pc_i + 32'd4) : alu_result;

    // DMEM request
    assign mem_addr_o    = alu_result;
    assign mem_wr_data_o = rs2_val;
    assign mem_read_o    = mem_read_i;
    assign mem_write_o   = mem_write_i;

    // EX/MEM Pipeline Register
    always @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ex_mem_pc_o         <= 32'b0;
            ex_mem_result_o     <= 32'b0;
            ex_mem_rd_o         <= 5'b0;
            ex_mem_reg_write_o  <= 1'b0;
            ex_mem_mem_to_reg_o <= 2'b0;
        end else begin
            ex_mem_pc_o         <= pc_i;
            ex_mem_result_o     <= result;
            ex_mem_rd_o         <= rd_i;
            ex_mem_reg_write_o  <= reg_write_i;
            ex_mem_mem_to_reg_o <= mem_to_reg_i;
        end
    end

endmodule
