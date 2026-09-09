`timescale 1ns/1ps

module dot_product_8mul (
    input  wire        clk,
    input  wire        rst_n,           // Active-low Reset

    // EX Stage Data Input (rs1 레지스터에서 읽어온 32비트 데이터)
    input  wire [31:0] data_i,

    // Decoder Control Signals (ID 단계에서 넘어오는 제어 신호들)
    input  wire        load_a_en_i,     // 1: Vector A 버퍼 로드
    input  wire        load_b_en_i,     // 1: Vector B 버퍼 로드
    input  wire        load_idx_i,      // 0: 하위 4개(0~3) 로드, 1: 상위 4개(4~7) 로드
    input  wire        compute_en_i,    // 1: 내적 계산 및 결과 출력 신호

    // EX/WB Stage Output (내적 연산 최종 결과)
    output wire [31:0] result_o
);

    reg [31:0] result_r;  // compute_en_i 시 클럭에 저장, 그 외에는 이전 값 유지

    // 1. 내부 버퍼 선언 (Signed INT8, 오버플로우/음수 완벽 대응)
    reg signed [7:0] buf_a [0:7];
    reg signed [7:0] buf_b [0:7];

    // 2. 조합 논리(Combinational) 연산 — 선언 및 정의를 always 블록 위에 두어 Declare-before-Use 보장
    wire signed [15:0] mul_res [0:7];   // 8bit * 8bit = 16bit (오버플로우 방지)
    wire signed [19:0] add_tree_l1 [0:3]; // 1단계 덧셈 (16bit + 16bit)
    wire signed [19:0] add_tree_l2 [0:1]; // 2단계 덧셈
    wire signed [19:0] final_sum;         // 최종 내적 결과 (최대 19bit 필요)

    genvar j;
    generate
        for (j = 0; j < 8; j = j + 1) begin : mult_gen
            assign mul_res[j] = buf_a[j] * buf_b[j];
        end
    endgenerate
    /*
    assign mul_res[0] = buf_a[0] * buf_b[0];
    assign mul_res[1] = buf_a[1] * buf_b[1];
    assign mul_res[2] = buf_a[2] * buf_b[2];
    ...
    assign mul_res[7] = buf_a[7] * buf_b[7];
    
    */

    assign add_tree_l1[0] = mul_res[0] + mul_res[1];
    assign add_tree_l1[1] = mul_res[2] + mul_res[3];
    assign add_tree_l1[2] = mul_res[4] + mul_res[5];
    assign add_tree_l1[3] = mul_res[6] + mul_res[7];

    assign add_tree_l2[0] = add_tree_l1[0] + add_tree_l1[1];
    assign add_tree_l2[1] = add_tree_l1[2] + add_tree_l1[3];

    assign final_sum = add_tree_l2[0] + add_tree_l2[1];

    // compute_en_i 당 cycle에 EX가 결과를 쓰려면 조합 논리로 출력 (파이프라인 스톨 불필요)
    assign result_o = compute_en_i ? $signed(final_sum) : result_r;

    integer i;

    // ==========================================
    // [순차 회로] 버퍼 데이터 적재 및 결과 출력
    // ==========================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 8; i = i + 1) begin
                buf_a[i] <= 8'sd0;
                buf_b[i] <= 8'sd0;
            end
            result_r <= 32'd0;
        end else begin
            // Vector A 로드 (32비트 안에 8비트 4개가 패킹되어 들어옴)
            if (load_a_en_i) begin
                if (load_idx_i == 1'b0) begin
                    buf_a[0] <= data_i[7:0];
                    buf_a[1] <= data_i[15:8];
                    buf_a[2] <= data_i[23:16];
                    buf_a[3] <= data_i[31:24];
                end else begin
                    buf_a[4] <= data_i[7:0];
                    buf_a[5] <= data_i[15:8];
                    buf_a[6] <= data_i[23:16];
                    buf_a[7] <= data_i[31:24];
                end
            end

            // Vector B 로드
            if (load_b_en_i) begin
                if (load_idx_i == 1'b0) begin
                    buf_b[0] <= data_i[7:0];
                    buf_b[1] <= data_i[15:8];
                    buf_b[2] <= data_i[23:16];
                    buf_b[3] <= data_i[31:24];
                end else begin
                    buf_b[4] <= data_i[7:0];
                    buf_b[5] <= data_i[15:8];
                    buf_b[6] <= data_i[23:16];
                    buf_b[7] <= data_i[31:24];
                end
            end

            if (compute_en_i) begin
                result_r <= $signed(final_sum);
            end
        end
    end

endmodule
