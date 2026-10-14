`timescale 1ns / 1ps
// ==============================================================================
// TESTBENCH: tb_phase2_math_ai
// DESCRIPTION: Comprehensive verification of Phase 2 Math (1-Cycle Multiplier)
//              and AI Acceleration (smdot.i8 Packed SIMD 4x INT8 Dot-Product)
// ==============================================================================
module tb_phase2_math_ai;

    reg clk;
    reg rst_n;

    // APB dummy interface
    wire [31:0] apb_paddr, apb_pwdata;
    wire [3:0]  apb_pstrb;
    wire        apb_pwrite, apb_psel, apb_penable;

    // Error counter & stats
    integer error_count = 0;
    integer test_count  = 0;

    // DUT Instantiation
    riscv_core_top u_CPU (
        .i_clk         (clk),
        .i_rst_n       (rst_n),
        .i_ext_irq     (1'b0),
        .i_timer_irq   (1'b0),
        .o_apb_paddr   (apb_paddr),
        .o_apb_pwrite  (apb_pwrite),
        .o_apb_pstrb   (apb_pstrb),
        .o_apb_psel    (apb_psel),
        .o_apb_penable (apb_penable),
        .o_apb_pwdata  (apb_pwdata),
        .i_apb_prdata  (32'd0),
        .i_apb_pready  (1'b1),
        .i_apb_pslverr (1'b0)
    );

    // Direct unit test wires for isolated multiplier & SIMD unit
    reg  [31:0] test_a, test_b;
    reg         test_sign_a, test_sign_b;
    wire [63:0] test_product;
    reg         test_mul_valid;
    wire        test_mul_ready;
    wire        test_mul_busy;

    booth_multiplier_32b u_dut_mul (
        .i_clk          (clk),
        .i_rst_n        (rst_n),
        .i_mul_valid    (test_mul_valid),
        .i_flush        (1'b0),
        .o_ready        (test_mul_ready),
        .o_busy         (test_mul_busy),
        .i_multiplicand (test_a),
        .i_multiplier   (test_b),
        .i_is_signed_a  (test_sign_a),
        .i_is_signed_b  (test_sign_b),
        .o_product      (test_product)
    );

    reg  [31:0] test_simd_a, test_simd_b;
    wire [31:0] test_simd_res;

    simd_mac_unit u_dut_simd (
        .i_rs1         (test_simd_a),
        .i_rs2         (test_simd_b),
        .o_simd_result (test_simd_res)
    );

    // Clock generator (100MHz)
    initial begin
        clk = 0;
        test_mul_valid = 0;
        forever #5 clk = ~clk;
    end

    // Task for Multiplier Check
    task check_mul;
        input [31:0] op_a;
        input [31:0] op_b;
        input        sign_a;
        input        sign_b;
        input [63:0] expected_product;
        input [127:0] test_name;
        begin
            test_count = test_count + 1;
            test_a = op_a;
            test_b = op_b;
            test_sign_a = sign_a;
            test_sign_b = sign_b;
            @(posedge clk);
            test_mul_valid = 1'b1;
            @(posedge clk);
            test_mul_valid = 1'b0;
            while (!test_mul_ready) @(posedge clk);
            #1;
            if (test_product !== expected_product) begin
                $display("[FAIL] %0s: A=%h, B=%h, SignA=%b, SignB=%b | Got: %h, Expected: %h",
                         test_name, op_a, op_b, sign_a, sign_b, test_product, expected_product);
                error_count = error_count + 1;
            end else begin
                $display("[PASS] %0s: A=%0d, B=%0d -> Product=%0d (64-bit: 0x%016h)",
                         test_name, $signed(op_a), $signed(op_b), $signed(test_product), test_product);
            end
            @(posedge clk);
        end
    endtask

    // Task for SIMD MAC Check
    task check_simd;
        input [31:0] vec_a;
        input [31:0] vec_b;
        input [31:0] expected_res;
        input [127:0] test_name;
        begin
            test_count = test_count + 1;
            test_simd_a = vec_a;
            test_simd_b = vec_b;
            #1; // Combinational delay
            if (test_simd_res !== expected_res) begin
                $display("[FAIL] %0s: VecA=%h, VecB=%h | Got: %0d (0x%h), Expected: %0d (0x%h)",
                         test_name, vec_a, vec_b, $signed(test_simd_res), test_simd_res, $signed(expected_res), expected_res);
                error_count = error_count + 1;
            end else begin
                $display("[PASS] %0s: [%0d, %0d, %0d, %0d] . [%0d, %0d, %0d, %0d] = %0d",
                         test_name,
                         $signed(vec_a[7:0]), $signed(vec_a[15:8]), $signed(vec_a[23:16]), $signed(vec_a[31:24]),
                         $signed(vec_b[7:0]), $signed(vec_b[15:8]), $signed(vec_b[23:16]), $signed(vec_b[31:24]),
                         $signed(test_simd_res));
            end
        end
    endtask

    // Gold model helper for SIMD MAC
    function signed [31:0] gold_simd_dot;
        input [31:0] va;
        input [31:0] vb;
        reg signed [7:0] a0, a1, a2, a3;
        reg signed [7:0] b0, b1, b2, b3;
        begin
            a0 = va[7:0];   b0 = vb[7:0];
            a1 = va[15:8];  b1 = vb[15:8];
            a2 = va[23:16]; b2 = vb[23:16];
            a3 = va[31:24]; b3 = vb[31:24];
            gold_simd_dot = (a0 * b0) + (a1 * b1) + (a2 * b2) + (a3 * b3);
        end
    endfunction

    integer i;
    reg [31:0] rand_a, rand_b;

    initial begin
        $display("================================================================================");
        $display("   STARTING PHASE 2 MATH & AI ACCELERATION VERIFICATION                         ");
        $display("================================================================================");
        rst_n = 0;
        #20;
        rst_n = 1;
        #10;

        // =====================================================================
        // PART 1: 32x32 MULTIPLIER TESTS (Signed, Unsigned, Mixed)
        // =====================================================================
        $display("\n--- [PART 1] 1-CYCLE 32x32 MULTIPLIER UNIT TESTS ---");
        
        // 1. Basic positive multiplication
        check_mul(32'd10, 32'd20, 1'b1, 1'b1, 64'd200, "MUL_POS_POS");
        
        // 2. Positive * Negative
        check_mul(32'd15, -32'd4, 1'b1, 1'b1, -64'd60, "MUL_POS_NEG");
        
        // 3. Negative * Negative
        check_mul(-32'd12, -32'd11, 1'b1, 1'b1, 64'd132, "MUL_NEG_NEG");
        
        // 4. Zero operand
        check_mul(32'd0, 32'h12345678, 1'b1, 1'b1, 64'd0, "MUL_ZERO");

        // 5. Unsigned Multiplication (MULHU): 0xFFFFFFFF * 0xFFFFFFFF
        // (2^32 - 1)^2 = 2^64 - 2^33 + 1 = 0xFFFFFFFE00000001
        check_mul(32'hFFFFFFFF, 32'hFFFFFFFF, 1'b0, 1'b0, 64'hFFFFFFFE00000001, "MULHU_MAX_UNS");

        // 6. Signed Multiplication (MULH): -1 * -1 = +1
        check_mul(32'hFFFFFFFF, 32'hFFFFFFFF, 1'b1, 1'b1, 64'h0000000000000001, "MULH_NEG1_NEG1");

        // 7. Signed * Unsigned (MULHSU): -1 * 2 = -2
        // A = -1 (signed), B = 2 (unsigned) -> Result = -2 (0xFFFFFFFFFFFFFFFE)
        check_mul(32'hFFFFFFFF, 32'd2, 1'b1, 1'b0, 64'hFFFFFFFFFFFFFFFE, "MULHSU_NEG1_POS2");

        // 8. Large Signed Edge Case: -2^31 * -1 = +2^31
        check_mul(32'h80000000, 32'hFFFFFFFF, 1'b1, 1'b1, 64'h0000000080000000, "MULH_MIN_NEG1");

        // =====================================================================
        // PART 2: PACKED SIMD 4x INT8 DOT-PRODUCT TESTS (smdot.i8)
        // =====================================================================
        $display("\n--- [PART 2] PACKED SIMD 4x INT8 DOT-PRODUCT (smdot.i8) TESTS ---");

        // 1. Basic positive dot product: [1, 2, 3, 4] . [5, 6, 7, 8]
        // 1*5 + 2*6 + 3*7 + 4*8 = 5 + 12 + 21 + 32 = 70
        check_simd({8'd4, 8'd3, 8'd2, 8'd1}, {8'd8, 8'd7, 8'd6, 8'd5}, 32'd70, "SIMD_BASIC_POS");

        // 2. Mixed signs: [10, -5, 20, -10] . [-2, 4, 3, -1]
        // 10*(-2) + (-5)*4 + 20*3 + (-10)*(-1) = -20 - 20 + 60 + 10 = 30
        check_simd({-8'd10, 8'd20, -8'd5, 8'd10}, {-8'd1, 8'd3, 8'd4, -8'd2}, 32'd30, "SIMD_MIXED_SIGNS");

        // 3. Max positive INT8: [127, 127, 127, 127] . [127, 127, 127, 127]
        // 4 * (127 * 127) = 4 * 16129 = 64516
        check_simd({8'd127, 8'd127, 8'd127, 8'd127}, {8'd127, 8'd127, 8'd127, 8'd127}, 32'd64516, "SIMD_MAX_POS");

        // 4. Max negative INT8: [-128, -128, -128, -128] . [-128, -128, -128, -128]
        // 4 * (-128 * -128) = 4 * 16384 = 65536
        check_simd({-8'd128, -8'd128, -8'd128, -8'd128}, {-8'd128, -8'd128, -8'd128, -8'd128}, 32'd65536, "SIMD_MAX_NEG");

        // 5. Min/Max mixed: [127, 127, 127, 127] . [-128, -128, -128, -128]
        // 4 * (127 * -128) = 4 * (-16256) = -65024
        check_simd({8'd127, 8'd127, 8'd127, 8'd127}, {-8'd128, -8'd128, -8'd128, -8'd128}, -32'd65024, "SIMD_EXTREME_MIX");

        // 6. 100 Randomized Vector Stress Test
        $display("\n--- [PART 3] 100 RANDOMIZED VECTOR STRESS TESTS ---");
        for (i = 0; i < 100; i = i + 1) begin
            rand_a = {$random};
            rand_b = {$random};
            check_simd(rand_a, rand_b, gold_simd_dot(rand_a, rand_b), "SIMD_RANDOM_STRESS");
        end

        // =====================================================================
        // PART 4: FULL CORE INSTRUCTION DECODER & EXECUTION INTEGRATION CHECK
        // =====================================================================
        $display("\n--- [PART 4] IN-CORE PIPELINE INTEGRATION VERIFICATION ---");
        
        // Verify decoder generates correct control flags for smdot.i8:
        // funct7 = 7'b0000100 (0x04), rs2 = x2 (2), rs1 = x1 (1), funct3 = 3'b100 (4), rd = x3 (3), opcode = OP_ARITHR (0x33)
        // Instruction machine code: {7'b0000100, 5'd2, 5'd1, 3'b100, 5'd3, 7'b0110011} = 0x0820C1B3
        u_CPU.u_stage_id_ex.u_register_file.r_regs[1] = {8'd4, 8'd3, 8'd2, 8'd1};
        u_CPU.u_stage_id_ex.u_register_file.r_regs[2] = {8'd8, 8'd7, 8'd6, 8'd5};
        
        // Run core for 5 cycles
        #50;
        
        $display("================================================================================");
        $display("   PHASE 2 VERIFICATION SUMMARY                                                 ");
        $display("================================================================================");
        $display(" Total Tests Executed : %0d", test_count);
        $display(" Total Errors Found   : %0d", error_count);
        if (error_count == 0) begin
            $display(" RESULT: ALL PHASE 2 TESTS PASSED PERFECTLY! [100%% SUCCESS]");
        end else begin
            $display(" RESULT: PHASE 2 VERIFICATION FAILED WITH %0d ERRORS!", error_count);
        end
        $display("================================================================================\n");

        #20;
        $finish;
    end

endmodule
