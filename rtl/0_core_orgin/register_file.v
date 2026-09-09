`timescale 1ns/1ps

module register_file(
    input               clk_i,
    input               rst_ni,
    input               reg_write_i,
    input       [4:0]   rs1_i,
    input       [4:0]   rs2_i,
    input       [4:0]   rd_i,
    input       [31:0]  rd_din_i,
    output wire [31:0]  rs1_dout_o,
    output wire [31:0]  rs2_dout_o
);

    reg [31:0] rf_data [0:31];
    reg [31:0] Rf_data [0:31]; // Testbench Compatibility
    integer i;

    // ★ [Write-First Logic] 읽기 포트가 쓰기 중인 데이터를 바로 바이패스
    assign rs1_dout_o = (rs1_i == 5'd0) ? 32'd0 :
                        (reg_write_i && (rs1_i == rd_i)) ? rd_din_i : rf_data[rs1_i];

    assign rs2_dout_o = (rs2_i == 5'd0) ? 32'd0 :
                        (reg_write_i && (rs2_i == rd_i)) ? rd_din_i : rf_data[rs2_i];

    // 쓰기는 하강 에지 (Negedge) 유지
    always @(negedge clk_i or negedge rst_ni) begin
        if(!rst_ni) begin
            for (i=0; i<32; i=i+1) begin
                rf_data[i] <= 32'd0;
                Rf_data[i] <= 32'd0;
            end
        end else begin
            rf_data[0] <= 32'd0;
            Rf_data[0] <= 32'd0;

            if (reg_write_i && (rd_i != 5'd0)) begin
                rf_data[rd_i] <= rd_din_i;
                Rf_data[rd_i] <= rd_din_i;
            end
        end
    end

endmodule