`timescale 1ns/1ps

// OPCODES
`define OPCODE_R            7'b0110011
`define OPCODE_I            7'b0010011
`define OPCODE_BRANCH       7'b1100011
`define OPCODE_STORE        7'b0100011
`define OPCODE_LOAD         7'b0000011
`define OPCODE_JALR         7'b1100111
`define OPCODE_JAL          7'b1101111
`define OPCODE_AUIPC        7'b0010111
`define OPCODE_LUI          7'b0110111

// FUNCT3 (ALU)
`define FUNCT3_ADD_SUB      3'b000
`define FUNCT3_SLL          3'b001
`define FUNCT3_SLT          3'b010
`define FUNCT3_SLTU         3'b011
`define FUNCT3_XOR          3'b100
`define FUNCT3_SRL_SRA      3'b101
`define FUNCT3_OR           3'b110
`define FUNCT3_AND          3'b111
// FUNCT3 (BRANCH)
`define BRANCH_BEQ          3'b000
`define BRANCH_BNE          3'b001
`define BRANCH_BLT          3'b100
`define BRANCH_BGE          3'b101
// FUNCT7 
`define FUNCT7_SUB 			7'b0100000
`define FUNCT7_ADD 			7'b0000000
`define FUNCT7_SRA 			7'b0100000
`define FUNCT7_SRL 			7'b0000000




module alu_ctrl_unit (
    input [6:0] opcode_i,
    input [6:0] funct7_i,
    input [2:0] funct3_i,
    output reg [3:0] alu_ctrl_o
);
    localparam ALU_ADD  = 4'b0000;
    localparam ALU_AND  = 4'b0001;
    localparam ALU_OR   = 4'b0010;
    localparam ALU_XOR  = 4'b0011;
    localparam ALU_SLL  = 4'b0100;
    localparam ALU_SRL  = 4'b0101;
    localparam ALU_SRA  = 4'b0110;
    localparam ALU_SUB  = 4'b0111;
    localparam ALU_SLTU = 4'b1000;
    localparam ALU_SLT  = 4'b1001;


    always @(*) begin
        alu_ctrl_o = 4'bxxxx;
        case (opcode_i)
            `OPCODE_R: begin
                case (funct3_i)
                    `FUNCT3_ADD_SUB: begin
                        if (funct7_i == `FUNCT7_SUB) begin
                            alu_ctrl_o = ALU_SUB; //sub
                        end else begin
                            alu_ctrl_o = ALU_ADD; //add
                        end
                    end
		    `FUNCT3_AND: begin
		        alu_ctrl_o = ALU_AND; //and
		    end
		    `FUNCT3_OR: begin
			alu_ctrl_o = ALU_OR; //or
		    end
		    `FUNCT3_XOR: begin
			alu_ctrl_o = ALU_XOR; //XOR
		    end
		    `FUNCT3_SLL: begin
			alu_ctrl_o = ALU_SLL; //SLL
		    end
		    `FUNCT3_SRL_SRA: begin
			if (funct7_i == `FUNCT7_SRA) begin
			    alu_ctrl_o = ALU_SRA; //SRA
			end else begin
			    alu_ctrl_o = ALU_SRL; //SRL
			end
		    end
		    `FUNCT3_SLT: begin
			alu_ctrl_o = ALU_SLT; //slt
		    end
		    `FUNCT3_SLTU: begin
			alu_ctrl_o = ALU_SLTU; //sltu
		    end
		endcase
	       end

            `OPCODE_I: begin
		case (funct3_i)
			`FUNCT3_ADD_SUB: begin
				alu_ctrl_o = ALU_ADD; //addi
			end
			`FUNCT3_AND: begin
				alu_ctrl_o = ALU_AND; //andi
			end
			`FUNCT3_OR: begin
				alu_ctrl_o = ALU_OR; //ori
			end
			`FUNCT3_XOR: begin
				alu_ctrl_o = ALU_XOR; // xori
			end
			`FUNCT3_SLL: begin
				alu_ctrl_o = ALU_SLL; //slli
			end
			`FUNCT3_SRL_SRA: begin
				if (funct7_i == `FUNCT7_SRL) begin
					alu_ctrl_o = ALU_SRL; //srli
				end else begin
					alu_ctrl_o = ALU_SRA; //srai
				end
			end
			`FUNCT3_SLT: begin
				alu_ctrl_o = ALU_SLT; //slti
			end
			`FUNCT3_SLTU: begin
				alu_ctrl_o = ALU_SLTU;
			end
		endcase
	    end

		`OPCODE_LOAD,
		`OPCODE_STORE: begin
			alu_ctrl_o = ALU_ADD; //lw,sw are always add
		end

		`OPCODE_BRANCH: begin
			case(funct3_i)
				`BRANCH_BEQ, `BRANCH_BNE: alu_ctrl_o = ALU_SUB;
				`BRANCH_BLT, `BRANCH_BGE: alu_ctrl_o = ALU_SLT;
				
			endcase
		end

		`OPCODE_JAL,
		`OPCODE_JALR: begin
			alu_ctrl_o = ALU_ADD;
		end

		`OPCODE_LUI,
		`OPCODE_AUIPC: begin
			alu_ctrl_o = ALU_ADD;
		end
		
		default: begin
			alu_ctrl_o = ALU_ADD;
		end
	endcase
  end
endmodule
