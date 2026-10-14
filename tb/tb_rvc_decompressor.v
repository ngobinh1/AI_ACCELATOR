`timescale 1ns / 1ps
// ==============================================================================
// TESTBENCH: tb_rvc_decompressor
// DESCRIPTION: Comprehensive Unit Testbench for RVC Compressed Instruction Expander
// ARCHITECTURE: RISC-V 32-bit IoT & AI Accelerator Core (Phase 4)
// ==============================================================================

module tb_rvc_decompressor;

    reg  [15:0] r_c_instr;
    wire [31:0] w_decomp_instr;
    wire        w_illegal_instr;

    integer total_tests  = 0;
    integer passed_tests = 0;
    integer failed_tests = 0;

    // Instantiate Unit Under Test (UUT)
    rvc_decompressor u_uut (
        .i_c_instr      (r_c_instr),
        .o_decomp_instr (w_decomp_instr),
        .o_illegal_instr(w_illegal_instr)
    );

    // Verification Task
    task check_decomp(
        input [15:0] c_in,
        input [31:0] expected_out,
        input        expected_illegal,
        input [127:0] test_name
    );
        begin
            r_c_instr = c_in;
            #5; // Allow combinational logic to propagate
            total_tests = total_tests + 1;

            if ((w_decomp_instr == expected_out) && (w_illegal_instr == expected_illegal)) begin
                $display("[PASS] Test %2d: %s | C: 0x%04h -> RV32I: 0x%08h", 
                         total_tests, test_name, c_in, w_decomp_instr);
                passed_tests = passed_tests + 1;
            end else begin
                $display("[FAIL] Test %2d: %s | C: 0x%04h | Got: 0x%08h (Ill: %b) | Expected: 0x%08h (Ill: %b)", 
                         total_tests, test_name, c_in, w_decomp_instr, w_illegal_instr, expected_out, expected_illegal);
                failed_tests = failed_tests + 1;
            end
        end
    endtask

    initial begin
        $display("================================================================================");
        $display("   RUNNING RVC DECOMPRESSOR COMPREHENSIVE UNIT TESTBENCH                        ");
        $display("================================================================================");

        // ---------------------------------------------------------------------
        // 1. ILLEGAL / RESERVED INSTRUCTIONS
        // ---------------------------------------------------------------------
        check_decomp(16'h0000, 32'h00000013, 1'b1, "All-Zeros Reserved");

        // ---------------------------------------------------------------------
        // ---------------------------------------------------------------------
        // 2. QUADRANT 0 INSTRUCTIONS
        // ---------------------------------------------------------------------
        // c.addi4spn a0 (x10), 16 -> addi x10, x2, 16
        check_decomp(16'h0808, 32'h01010513, 1'b0, "c.addi4spn a0, 16");

        // c.addi4spn a0 (x10), 4 -> addi x10, x2, 4
        check_decomp(16'h0048, 32'h00410513, 1'b0, "c.addi4spn a0, 4");

        // c.lw a0 (x10), 4(a1 (x11)) -> lw x10, 4(x11)
        check_decomp(16'h41c8, 32'h0045a503, 1'b0, "c.lw a0, 4(a1)");

        // c.sw a0 (x10), 4(a1 (x11)) -> sw x10, 4(x11)
        check_decomp(16'hc1c8, 32'h00a5a223, 1'b0, "c.sw a0, 4(a1)");

        // ---------------------------------------------------------------------
        // 3. QUADRANT 1 INSTRUCTIONS
        // ---------------------------------------------------------------------
        // c.nop -> addi x0, x0, 0
        check_decomp(16'h0001, 32'h00000013, 1'b0, "c.nop");

        // c.addi a0 (x10), 5 -> addi x10, x10, 5
        check_decomp(16'h0515, 32'h00550513, 1'b0, "c.addi a0, 5");

        // c.addi a0 (x10), -5 -> addi x10, x10, -5
        check_decomp(16'h156d, 32'hffb50513, 1'b0, "c.addi a0, -5");

        // c.li a0 (x10), 12 -> addi x10, x0, 12
        check_decomp(16'h4531, 32'h00c00513, 1'b0, "c.li a0, 12");

        // c.lui a0 (x10), 0x10 -> lui x10, 0x10
        check_decomp(16'h6541, 32'h00010537, 1'b0, "c.lui a0, 0x10");

        // c.addi16sp 32 -> addi x2, x2, 32
        check_decomp(16'h6105, 32'h02010113, 1'b0, "c.addi16sp 32");

        // c.addi16sp -32 -> addi x2, x2, -32
        check_decomp(16'h713d, 32'hfe010113, 1'b0, "c.addi16sp -32");

        // c.srli a0 (x10), 3 -> srli x10, x10, 3
        check_decomp(16'h810d, 32'h00355513, 1'b0, "c.srli a0, 3");

        // c.srai a0 (x10), 3 -> srai x10, x10, 3
        check_decomp(16'h850d, 32'h40355513, 1'b0, "c.srai a0, 3");

        // c.andi a0 (x10), 7 -> andi x10, x10, 7
        check_decomp(16'h891d, 32'h00757513, 1'b0, "c.andi a0, 7");

        // c.sub a0 (x10), a1 (x11) -> sub x10, x10, x11
        check_decomp(16'h8d0d, 32'h40b50533, 1'b0, "c.sub a0, a1");

        // c.xor a0 (x10), a1 (x11) -> xor x10, x10, x11
        check_decomp(16'h8d2d, 32'h00b54533, 1'b0, "c.xor a0, a1");

        // c.or a0 (x10), a1 (x11) -> or x10, x10, x11
        check_decomp(16'h8d4d, 32'h00b56533, 1'b0, "c.or a0, a1");

        // c.and a0 (x10), a1 (x11) -> and x10, x10, x11
        check_decomp(16'h8d6d, 32'h00b57533, 1'b0, "c.and a0, a1");

        // c.j offset=16 -> jal x0, 16
        check_decomp(16'ha801, 32'h0100006f, 1'b0, "c.j 16");

        // c.jal offset=16 -> jal x1, 16
        check_decomp(16'h2801, 32'h010000ef, 1'b0, "c.jal 16");

        // c.beqz a0 (x10), offset=16 -> beq x10, x0, 16
        check_decomp(16'hc901, 32'h00050863, 1'b0, "c.beqz a0, 16");

        // c.bnez a0 (x10), offset=16 -> bne x10, x0, 16
        check_decomp(16'he901, 32'h00051863, 1'b0, "c.bnez a0, 16");

        // ---------------------------------------------------------------------
        // 4. QUADRANT 2 INSTRUCTIONS
        // ---------------------------------------------------------------------
        // c.slli a0 (x10), 4 -> slli x10, x10, 4
        // expected slli x10, x10, 4 = 0x00451513
        check_decomp(16'h0512, 32'h00451513, 1'b0, "c.slli a0, 4");

        // c.lwsp a0 (x10), 16(sp) -> lw x10, 16(x2)
        // expected lw x10, 16(x2) = 0x01012503
        check_decomp(16'h4542, 32'h01012503, 1'b0, "c.lwsp a0, 16(sp)");

        // c.swsp a0 (x10), 16(sp) -> sw x10, 16(x2)
        // expected sw x10, 16(x2) = 0x00a12823
        check_decomp(16'hc82a, 32'h00a12823, 1'b0, "c.swsp a0, 16(sp)");

        // c.jr a0 (x10) -> jalr x0, 0(x10)
        // expected jalr x0, 0(x10) = 0x00050067
        check_decomp(16'h8502, 32'h00050067, 1'b0, "c.jr a0");

        // c.jalr a0 (x10) -> jalr x1, 0(x10)
        // expected jalr x1, 0(x10) = 0x000500e7
        check_decomp(16'h9502, 32'h000500e7, 1'b0, "c.jalr a0");

        // c.mv a0 (x10), a1 (x11) -> add x10, x0, x11
        // expected add x10, x0, x11 = 0x00b00533
        check_decomp(16'h852e, 32'h00b00533, 1'b0, "c.mv a0, a1");

        // c.add a0 (x10), a1 (x11) -> add x10, x10, x11
        // expected add x10, x10, x11 = 0x00b50533
        check_decomp(16'h952e, 32'h00b50533, 1'b0, "c.add a0, a1");

        // c.ebreak -> ebreak (0x00100073)
        check_decomp(16'h9002, 32'h00100073, 1'b0, "c.ebreak");

        // =====================================================================
        // TEST SUMMARY
        // =====================================================================
        $display("================================================================================");
        $display("   TEST RESULTS: Total = %0d | Passed = %0d | Failed = %0d", 
                 total_tests, passed_tests, failed_tests);
        $display("================================================================================");

        if (failed_tests == 0) begin
            $display(">>> [SUCCESS] 100%% RV32C INSTRUCTION DECOMPRESSION TESTS PASSED! <<<");
        end else begin
            $display(">>> [FAILURE] SOME RV32C DECOMPRESSION TESTS FAILED! <<<");
        end
        $finish;
    end

endmodule
