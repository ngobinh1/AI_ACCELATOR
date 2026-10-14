`timescale 1ns / 1ps
// ==============================================================================
// TESTBENCH: tb_isa_compliance
// DESCRIPTION: Directed ISA Compliance Testbench covering remaining RV32I base
//              instructions:
//              - LUI, AUIPC
//              - SLL, SLLI, SRL, SRLI, SRA, SRAI
//              - XOR, XORI, OR, ORI, AND, ANDI
//              - SLT, SLTI, SLTU, SLTIU
//              - BLTU, BGEU (taken & not-taken)
//              - SB, SH, SW, LB, LBU, LH, LHU, LW
// ==============================================================================

module tb_isa_compliance;

    reg clk;
    reg rst_n;

    // APB dummy slave signals
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

    // Bookkeeping
    integer test_count  = 0;
    integer pass_count  = 0;
    integer error_count = 0;
    integer k;

    task check_reg;
        input [4:0]    reg_idx;
        input [31:0]   expected_val;
        input [1023:0] test_name;
        reg   [31:0]   actual_val;
        begin
            test_count = test_count + 1;
            actual_val = u_CPU.u_stage_id_ex.u_register_file.r_regs[reg_idx];
            if (actual_val === expected_val) begin
                $display(" [PASS] Test %2d: %-32s | x%02d = 0x%08h (%0d)", 
                         test_count, test_name, reg_idx, actual_val, $signed(actual_val));
                pass_count = pass_count + 1;
            end else begin
                $display(" [FAIL] Test %2d: %-32s | x%02d Exp: 0x%08h (%0d), Got: 0x%08h (%0d)", 
                         test_count, test_name, reg_idx, expected_val, $signed(expected_val), actual_val, $signed(actual_val));
                error_count = error_count + 1;
            end
        end
    endtask

    task check_mem;
        input [31:0]   word_idx;
        input [31:0]   expected_val;
        input [1023:0] test_name;
        reg   [31:0]   actual_val;
        begin
            test_count = test_count + 1;
            actual_val = u_CPU.u_sram_2kb.mem[word_idx];
            if (actual_val === expected_val) begin
                $display(" [PASS] Test %2d: %-32s | mem[%0d] = 0x%08h", 
                         test_count, test_name, word_idx, actual_val);
                pass_count = pass_count + 1;
            end else begin
                $display(" [FAIL] Test %2d: %-32s | mem[%0d] Exp: 0x%08h, Got: 0x%08h", 
                         test_count, test_name, word_idx, expected_val, actual_val);
                error_count = error_count + 1;
            end
        end
    endtask

    initial begin
        $display("================================================================================");
        $display("   PHASE 7: RV32I DIRECTED ISA COMPLIANCE VERIFICATION SUITE                    ");
        $display("================================================================================");

        // Clear SRAM
        for (k = 0; k < 512; k = k + 1) begin
            u_CPU.u_sram_2kb.mem[k] = 32'd0;
        end

        // Load assembled RV32I test program into SRAM
        u_CPU.u_sram_2kb.mem[ 0] = 32'h123450b7; // 0x00: lui    ra, 0x12345
        u_CPU.u_sram_2kb.mem[ 1] = 32'h00001117; // 0x04: auipc  sp, 0x1
        u_CPU.u_sram_2kb.mem[ 2] = 32'h00f00213; // 0x08: li     tp, 15
        u_CPU.u_sram_2kb.mem[ 3] = 32'h03300293; // 0x0c: li     t0, 51
        u_CPU.u_sram_2kb.mem[ 4] = 32'h00527333; // 0x10: and    t1, tp, t0
        u_CPU.u_sram_2kb.mem[ 5] = 32'h00527393; // 0x14: andi   t2, tp, 5
        u_CPU.u_sram_2kb.mem[ 6] = 32'h00526433; // 0x18: or     s0, tp, t0
        u_CPU.u_sram_2kb.mem[ 7] = 32'h02026493; // 0x1c: ori    s1, tp, 32
        u_CPU.u_sram_2kb.mem[ 8] = 32'h00524533; // 0x20: xor    a0, tp, t0
        u_CPU.u_sram_2kb.mem[ 9] = 32'h05524593; // 0x24: xori   a1, tp, 85
        u_CPU.u_sram_2kb.mem[10] = 32'h00421613; // 0x28: slli   a2, tp, 0x4
        u_CPU.u_sram_2kb.mem[11] = 32'h00200193; // 0x2c: li     gp, 2
        u_CPU.u_sram_2kb.mem[12] = 32'h003216b3; // 0x30: sll    a3, tp, gp
        u_CPU.u_sram_2kb.mem[13] = 32'h00265713; // 0x34: srli   a4, a2, 0x2
        u_CPU.u_sram_2kb.mem[14] = 32'h003657b3; // 0x38: srl    a5, a2, gp
        u_CPU.u_sram_2kb.mem[15] = 32'hff000813; // 0x3c: li     a6, -16
        u_CPU.u_sram_2kb.mem[16] = 32'h40285893; // 0x40: srai   a7, a6, 0x2
        u_CPU.u_sram_2kb.mem[17] = 32'h40385933; // 0x44: sra    s2, a6, gp
        u_CPU.u_sram_2kb.mem[18] = 32'hff600213; // 0x48: li     tp, -10
        u_CPU.u_sram_2kb.mem[19] = 32'h00500293; // 0x4c: li     t0, 5
        u_CPU.u_sram_2kb.mem[20] = 32'h005229b3; // 0x50: slt    s3, tp, t0
        u_CPU.u_sram_2kb.mem[21] = 32'h0042aa33; // 0x54: slt    s4, t0, tp
        u_CPU.u_sram_2kb.mem[22] = 32'h00022a93; // 0x58: slti   s5, tp, 0
        u_CPU.u_sram_2kb.mem[23] = 32'h0002ab13; // 0x5c: slti   s6, t0, 0
        u_CPU.u_sram_2kb.mem[24] = 32'h00523bb3; // 0x60: sltu   s7, tp, t0
        u_CPU.u_sram_2kb.mem[25] = 32'h0042bc33; // 0x64: sltu   s8, t0, tp
        u_CPU.u_sram_2kb.mem[26] = 32'h00a2bc93; // 0x68: sltiu  s9, t0, 10
        u_CPU.u_sram_2kb.mem[27] = 32'h00a23d13; // 0x6c: sltiu  s10, tp, 10
        u_CPU.u_sram_2kb.mem[28] = 32'h00000d93; // 0x70: li     s11, 0
        u_CPU.u_sram_2kb.mem[29] = 32'h00000e13; // 0x74: li     t3, 0
        u_CPU.u_sram_2kb.mem[30] = 32'h06526663; // 0x78: bltu   tp, t0, fail_trap (not taken)
        u_CPU.u_sram_2kb.mem[31] = 32'h0042e463; // 0x7c: bltu   t0, tp, bltu_ok (taken)
        u_CPU.u_sram_2kb.mem[32] = 32'h0640006f; // 0x80: j      fail_trap
        u_CPU.u_sram_2kb.mem[33] = 32'h00100d93; // 0x84: li     s11, 1
        u_CPU.u_sram_2kb.mem[34] = 32'h0442fe63; // 0x88: bgeu   t0, tp, fail_trap (not taken)
        u_CPU.u_sram_2kb.mem[35] = 32'h00527463; // 0x8c: bgeu   tp, t0, bgeu_ok (taken)
        u_CPU.u_sram_2kb.mem[36] = 32'h0540006f; // 0x90: j      fail_trap
        u_CPU.u_sram_2kb.mem[37] = 32'h00100e13; // 0x94: li     t3, 1
        u_CPU.u_sram_2kb.mem[38] = 32'h30000213; // 0x98: li     tp, 768 (0x300)
        u_CPU.u_sram_2kb.mem[39] = 32'h112232b7; // 0x9c: lui    t0, 0x11223
        u_CPU.u_sram_2kb.mem[40] = 32'h34428293; // 0xa0: addi   t0, t0, 836 (0x11223344)
        u_CPU.u_sram_2kb.mem[41] = 32'h00522023; // 0xa4: sw     t0, 0(tp)
        u_CPU.u_sram_2kb.mem[42] = 32'h0aa00293; // 0xa8: li     t0, 170 (0xAA)
        u_CPU.u_sram_2kb.mem[43] = 32'h00520023; // 0xac: sb     t0, 0(tp)
        u_CPU.u_sram_2kb.mem[44] = 32'h05500293; // 0xb0: li     t0, 85 (0x55)
        u_CPU.u_sram_2kb.mem[45] = 32'h005200a3; // 0xb4: sb     t0, 1(tp)
        u_CPU.u_sram_2kb.mem[46] = 32'h000102b7; // 0xb8: lui    t0, 0x10
        u_CPU.u_sram_2kb.mem[47] = 32'hedc28293; // 0xbc: addi   t0, t0, -292 (0x0000FEDC)
        u_CPU.u_sram_2kb.mem[48] = 32'h00521123; // 0xc0: sh     t0, 2(tp)
        u_CPU.u_sram_2kb.mem[49] = 32'h00024e83; // 0xc4: lbu    t4, 0(tp)
        u_CPU.u_sram_2kb.mem[50] = 32'h00020f03; // 0xc8: lb     t5, 0(tp)
        u_CPU.u_sram_2kb.mem[51] = 32'h00120f83; // 0xcc: lb     t6, 1(tp)
        u_CPU.u_sram_2kb.mem[52] = 32'h00225203; // 0xd0: lhu    tp, 2(tp)
        u_CPU.u_sram_2kb.mem[53] = 32'h30000193; // 0xd4: li     gp, 768 (0x300)
        u_CPU.u_sram_2kb.mem[54] = 32'h00219283; // 0xd8: lh     t0, 2(gp)
        u_CPU.u_sram_2kb.mem[55] = 32'h0001a183; // 0xdc: lw     gp, 0(gp)
        u_CPU.u_sram_2kb.mem[56] = 32'h0000006f; // 0xe0: j      done (self-loop)
        u_CPU.u_sram_2kb.mem[57] = 32'hfff00d93; // 0xe4: fail_trap: li s11, -1
        u_CPU.u_sram_2kb.mem[58] = 32'hffdff06f; // 0xe8: j      fail_trap

        // Reset pulse
        rst_n = 0;
        #30;
        rst_n = 1;

        // Wait until core reaches self-loop at 0xe0
        wait (u_CPU.w_id_ex_pc == 32'h000000e0 && u_CPU.w_id_ex_valid);
        #40; // Allow final instructions to retire through pipeline

        $display("--------------------------------------------------------------------------------");
        $display(" RUNNING VERIFICATION CHECKS:");
        $display("--------------------------------------------------------------------------------");

        // Upper Immediates
        check_reg(5'd1,  32'h12345000, "LUI (Load Upper Immediate)");
        check_reg(5'd2,  32'h00001004, "AUIPC (Add Upper Imm to PC)");

        // Logic Operations
        check_reg(5'd6,  32'd3,        "AND (x4 & x5 = 15 & 51)");
        check_reg(5'd7,  32'd5,        "ANDI (x4 & 5 = 15 & 5)");
        check_reg(5'd8,  32'd63,       "OR (x4 | x5 = 15 | 51)");
        check_reg(5'd9,  32'd47,       "ORI (x4 | 32 = 15 | 32)");
        check_reg(5'd10, 32'd60,       "XOR (x4 ^ x5 = 15 ^ 51)");
        check_reg(5'd11, 32'd90,       "XORI (x4 ^ 85 = 15 ^ 85)");

        // Shift Operations
        check_reg(5'd12, 32'd240,      "SLLI (15 << 4)");
        check_reg(5'd13, 32'd60,       "SLL (15 << 2)");
        check_reg(5'd14, 32'd60,       "SRLI (240 >> 2)");
        check_reg(5'd15, 32'd60,       "SRL (240 >> 2)");
        check_reg(5'd17, 32'hfffffffc, "SRAI (-16 >>> 2 = -4)");
        check_reg(5'd18, 32'hfffffffc, "SRA (-16 >>> 2 = -4)");

        // Set Less Than
        check_reg(5'd19, 32'd1,        "SLT signed (-10 < 5)");
        check_reg(5'd20, 32'd0,        "SLT signed (5 < -10)");
        check_reg(5'd21, 32'd1,        "SLTI signed (-10 < 0)");
        check_reg(5'd22, 32'd0,        "SLTI signed (5 < 0)");
        check_reg(5'd23, 32'd0,        "SLTU unsigned (0xFFFFFFF6 < 5)");
        check_reg(5'd24, 32'd1,        "SLTU unsigned (5 < 0xFFFFFFF6)");
        check_reg(5'd25, 32'd1,        "SLTIU unsigned (5 < 10)");
        check_reg(5'd26, 32'd0,        "SLTIU unsigned (0xFFFFFFF6 < 10)");

        // Unsigned Branches
        check_reg(5'd27, 32'd1,        "BLTU unsigned branch taken");
        check_reg(5'd28, 32'd1,        "BGEU unsigned branch taken");

        // Sub-word Memory Writes (SRAM inspection at 0x300, word index 192)
        check_mem(32'd192, 32'hfedc55aa, "SW/SB/SH composite word at 0x300");

        // Sub-word Memory Reads
        check_reg(5'd29, 32'h000000aa, "LBU byte 0 unsigned (0xAA)");
        check_reg(5'd30, 32'hffffffaa, "LB byte 0 signed (0xAA -> sign ext)");
        check_reg(5'd31, 32'h00000055, "LB byte 1 signed (0x55)");
        check_reg(5'd4,  32'h0000fedc, "LHU halfword 1 unsigned (0xFEDC)");
        check_reg(5'd5,  32'hfffffedc, "LH halfword 1 signed (0xFEDC -> sign ext)");
        check_reg(5'd3,  32'hfedc55aa, "LW word from 0x300");

        $display("--------------------------------------------------------------------------------");
        $display(" TEST RESULTS SUMMARY: %0d / %0d PASSED", pass_count, test_count);
        $display("--------------------------------------------------------------------------------");

        if (error_count == 0 && pass_count == test_count) begin
            $display("\n >>> ALL %0d RV32I DIRECTED ISA COMPLIANCE TESTS PASSED (100%%)! <<<\n", test_count);
        end else begin
            $display("\n >>> %0d TESTS FAILED! <<<\n", error_count);
        end

        $finish;
    end

    // Timeout watchdog
    initial begin
        #50000;
        $display("\n [ERROR] TIMEOUT: Simulation did not reach completion self-loop!");
        $finish;
    end

endmodule
