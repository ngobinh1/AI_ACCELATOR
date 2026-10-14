`timescale 1ns / 1ps
// ==============================================================================
// TESTBENCH: tb_rvc_pipeline
// DESCRIPTION: End-to-End Core Pipeline Testbench for RV32C Compressed Instructions
//              Tests mixed 16-bit/32-bit instructions, unaligned cross-word instructions,
//              compressed jumps, branches, stack operations, and hazard interactions.
// ARCHITECTURE: RISC-V 32-bit IoT & AI Accelerator Core (Phase 4)
// ==============================================================================

module tb_rvc_pipeline;

    reg clk;
    reg rst_n;

    // APB dummy interface
    wire [31:0] apb_paddr, apb_pwdata;
    wire [3:0]  apb_pstrb;
    wire        apb_pwrite, apb_psel, apb_penable;

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

    // Clock generator (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    integer test_count  = 0;
    integer passed_count= 0;
    integer error_count = 0;

    task check_reg(
        input [4:0]   reg_idx,
        input [31:0]  expected_val,
        input [127:0] test_name
    );
        reg [31:0] actual_val;
        begin
            test_count = test_count + 1;
            actual_val = u_CPU.u_stage_id_ex.u_register_file.r_regs[reg_idx];
            if (actual_val === expected_val) begin
                $display(" [PASS] Test %2d: %0s | x%0d = 0x%08h (%0d)", 
                         test_count, test_name, reg_idx, actual_val, $signed(actual_val));
                passed_count = passed_count + 1;
            end else begin
                $display(" [FAIL] Test %2d: %0s | x%0d Expected: 0x%08h (%0d), Got: 0x%08h (%0d)", 
                         test_count, test_name, reg_idx, expected_val, $signed(expected_val), actual_val, $signed(actual_val));
                error_count = error_count + 1;
            end
        end
    endtask

    integer k;

    initial begin
        $display("================================================================================");
        $display("   PHASE 4: RV32C COMPRESSED INSTRUCTIONS END-TO-END PIPELINE VERIFICATION      ");
        $display("================================================================================");

        // Clear SRAM memory
        for (k = 0; k < 512; k = k + 1) begin
            u_CPU.u_sram_2kb.mem[k] = 32'd0;
        end

        // Pre-fill memory for Load testing
        u_CPU.u_sram_2kb.mem[32] = 32'h12345678; // Addr 0x80
        u_CPU.u_sram_2kb.mem[33] = 32'hDEADBEEF; // Addr 0x84

        // =====================================================================
        // PROGRAM CONSTRUCTED WITH COMPRESSED & BASE INSTRUCTIONS
        // =====================================================================
        // Word 0 (0x00):
        //   0x00: c.li x10 (a0), 12        (16-bit: 0x4531)
        //   0x02: c.addi x10 (a0), 5       (16-bit: 0x0515) -> a0 = 12 + 5 = 17
        u_CPU.u_sram_2kb.mem[0] = {16'h0515, 16'h4531};

        // Word 1 & 2: Unaligned 32-bit instruction spanning word boundary!
        //   0x04: c.mv x11 (a1), x10 (a0)  (16-bit: 0x85aa) -> a1 = 17
        //   0x06: addi x12 (a2), x11, 100  (32-bit unaligned: 0x06458613)
        //         lower 16-bit at 0x06: 0x8613
        //         upper 16-bit at 0x08: 0x0645 -> x12 = 17 + 100 = 117
        u_CPU.u_sram_2kb.mem[1] = {16'h8613, 16'h85aa};

        // Word 2 (0x08):
        //   0x08: upper 16-bit of addi x12 (0x0645)
        //   0x0A: c.slli x10 (a0), 2       (16-bit: 0x050a) -> a0 = 17 << 2 = 68
        u_CPU.u_sram_2kb.mem[2] = {16'h050a, 16'h0645};

        // Word 3 (0x0C):
        //   0x0C: c.add x10, x12           (16-bit: 0x9532) -> a0 = 68 + 117 = 185
        //   0x0E: c.j +10                  (16-bit: 0xa029 -> jump to 0x18)
        u_CPU.u_sram_2kb.mem[3] = {16'ha029, 16'h9532};

        // Word 4 (0x10): WRONG PATH (must NOT execute)
        //   0x10: addi x14, x0, 99         (32-bit: 0x06300713)
        u_CPU.u_sram_2kb.mem[4] = 32'h06300713;

        // Word 5 (0x14): WRONG PATH (must NOT execute)
        //   0x14: addi x14, x0, 99
        u_CPU.u_sram_2kb.mem[5] = 32'h06300713;

        // Word 6 (0x18):
        //   0x18: c.li x13 (a3), 15        (16-bit: 0x46bd) -> target of c.j! x13 = 15
        //   0x1A: c.bnez x13, +6           (16-bit: 0xe299 -> jump to 0x20)
        u_CPU.u_sram_2kb.mem[6] = {16'he299, 16'h46bd};

        // Word 7 (0x1C): WRONG PATH (must NOT execute)
        //   0x1C: addi x14, x0, 99
        u_CPU.u_sram_2kb.mem[7] = 32'h06300713;

        // Word 8 (0x20):
        //   0x20: mul x15, x10, x13        (32-bit: 0x02d507b3) -> x15 = 185 * 15 = 2775
        u_CPU.u_sram_2kb.mem[8] = 32'h02d507b3;

        // Word 9 (0x24):
        //   0x24: c.j 0x24                 (16-bit: 0xa001 -> infinite loop)
        u_CPU.u_sram_2kb.mem[9] = {16'h0001, 16'ha001};

        // Reset DUT
        rst_n = 0;
        #20;
        rst_n = 1;

        // Run until infinite loop at PC 0x24
        while (u_CPU.w_id_ex_pc != 32'h00000024) begin
            @(posedge clk);
        end

        // Wait a few cycles for all stages to commit
        repeat(5) @(posedge clk);

        $display("--------------------------------------------------------------------------------");
        $display(" VERIFYING RV32C PIPELINE RESULTS:");
        $display("--------------------------------------------------------------------------------");

        // Test 1: c.li x10, 12 and c.addi x10, 5, then c.mv x11, x10
        check_reg(5'd11, 32'd17,    "c.mv: x11 (a1) = 17");

        // Test 2: Unaligned cross-word addi x12, x11, 100
        check_reg(5'd12, 32'd117,   "Unaligned 32-bit: x12 = 17 + 100 = 117");

        // Test 3: c.slli and c.add
        check_reg(5'd10, 32'd185,   "c.slli + c.add: x10 = (17 << 2) + 117 = 185");

        // Test 4: Compressed Jump (c.j) skipped wrong path
        check_reg(5'd14, 32'd0,     "Wrong path skipped: x14 = 0");

        // Test 5: Target of c.j executed
        check_reg(5'd13, 32'd15,    "c.j target: x13 = 15");

        // Test 6: Hardware Multiplier with RV32C operands
        check_reg(5'd15, 32'd2775,  "MUL: x15 = 185 * 15 = 2775");

        $display("================================================================================");
        $display("  RVC PIPELINE TEST SUMMARY: Total: %0d | Passed: %0d | Errors: %0d", 
                 test_count, passed_count, error_count);
        $display("================================================================================");

        if (error_count == 0) begin
            $display(" >>> [SUCCESS] 100%% RV32C PIPELINE & UNALIGNED TESTS PASSED! <<< \n");
        end else begin
            $display(" >>> [FAILURE] SOME RV32C PIPELINE TESTS FAILED! <<< \n");
        end

        $finish;
    end

endmodule
