`timescale 1ns / 1ps
// ==============================================================================
// TESTBENCH: tb_phase3_hazards
// DESCRIPTION: Comprehensive Hazard, Forwarding, and Pipeline Verification Suite
//              Phase 3 (3-Stage Decoupled Pipeline)
// ==============================================================================

module tb_phase3_hazards;

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

    // =========================================================================
    // INSTRUCTION ENCODING HELPERS
    // =========================================================================
    function [31:0] encode_addi;
        input [4:0]  rd;
        input [4:0]  rs1;
        input [11:0] imm;
        begin
            encode_addi = {imm, rs1, 3'b000, rd, 7'b0010011};
        end
    endfunction

    function [31:0] encode_add;
        input [4:0] rd;
        input [4:0] rs1;
        input [4:0] rs2;
        begin
            encode_add = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
        end
    endfunction

    function [31:0] encode_sub;
        input [4:0] rd;
        input [4:0] rs1;
        input [4:0] rs2;
        begin
            encode_sub = {7'b0100000, rs2, rs1, 3'b000, rd, 7'b0110011};
        end
    endfunction

    function [31:0] encode_mul;
        input [4:0] rd;
        input [4:0] rs1;
        input [4:0] rs2;
        begin
            encode_mul = {7'b0000001, rs2, rs1, 3'b000, rd, 7'b0110011};
        end
    endfunction

    function [31:0] encode_lw;
        input [4:0]  rd;
        input [4:0]  rs1;
        input [11:0] offset;
        begin
            encode_lw = {offset, rs1, 3'b010, rd, 7'b0000011};
        end
    endfunction

    function [31:0] encode_sw;
        input [4:0]  rs2;
        input [4:0]  rs1;
        input [11:0] offset;
        begin
            encode_sw = {offset[11:5], rs2, rs1, 3'b010, offset[4:0], 7'b0100011};
        end
    endfunction

    function [31:0] encode_beq;
        input [4:0]  rs1;
        input [4:0]  rs2;
        input [12:0] offset;
        begin
            encode_beq = {offset[12], offset[10:5], rs2, rs1, 3'b000, offset[4:1], offset[11], 7'b1100011};
        end
    endfunction

    function [31:0] encode_bne;
        input [4:0]  rs1;
        input [4:0]  rs2;
        input [12:0] offset;
        begin
            encode_bne = {offset[12], offset[10:5], rs2, rs1, 3'b001, offset[4:1], offset[11], 7'b1100011};
        end
    endfunction

    function [31:0] encode_jal;
        input [4:0]  rd;
        input [20:0] offset;
        begin
            encode_jal = {offset[20], offset[10:1], offset[11], offset[19:12], rd, 7'b1101111};
        end
    endfunction

    integer error_count = 0;
    integer test_count  = 0;

    task check_reg;
        input [4:0]        reg_idx;
        input [31:0]       expected_val;
        input [8*32-1:0]   test_name;
        reg   [31:0]       actual_val;
        begin
            test_count = test_count + 1;
            actual_val = u_CPU.u_stage_id_ex.u_register_file.r_regs[reg_idx];
            if (actual_val === expected_val) begin
                $display(" [PASS] Test %0d: %0s | x%0d = 0x%08h (%0d)", 
                         test_count, test_name, reg_idx, actual_val, $signed(actual_val));
            end else begin
                $display(" [FAIL] Test %0d: %0s | x%0d Expected: 0x%08h (%0d), Got: 0x%08h (%0d)", 
                         test_count, test_name, reg_idx, expected_val, $signed(expected_val), actual_val, $signed(actual_val));
                error_count = error_count + 1;
            end
        end
    endtask

    task check_mem;
        input [31:0]       word_idx;
        input [31:0]       expected_val;
        input [8*32-1:0]   test_name;
        reg   [31:0]       actual_val;
        begin
            test_count = test_count + 1;
            actual_val = u_CPU.u_sram_2kb.mem[word_idx];
            if (actual_val === expected_val) begin
                $display(" [PASS] Test %0d: %0s | Mem[%0d] = 0x%08h (%0d)", 
                         test_count, test_name, word_idx, actual_val, $signed(actual_val));
            end else begin
                $display(" [FAIL] Test %0d: %0s | Mem[%0d] Expected: 0x%08h, Got: 0x%08h", 
                         test_count, test_name, word_idx, expected_val, actual_val);
                error_count = error_count + 1;
            end
        end
    endtask

    integer k;

    initial begin
        $display("================================================================================");
        $display("   PHASE 3: PIPELINE HAZARDS & FORWARDING VERIFICATION SUITE                    ");
        $display("================================================================================");

        // Clear memory
        for (k = 0; k < 512; k = k + 1) begin
            u_CPU.u_sram_2kb.mem[k] = 32'd0;
        end

        // Pre-load data in memory for Load tests
        u_CPU.u_sram_2kb.mem[32] = 32'h12345678; // Addr 0x80 (Word 32)
        u_CPU.u_sram_2kb.mem[33] = 32'hAABBCCDD; // Addr 0x84 (Word 33)

        // =====================================================================
        // ASSEMBLE PROGRAM INTO INSTRUCTION MEMORY
        // =====================================================================
        // Test 1: EX-to-EX RAW Forwarding (ALU -> ALU consecutive)
        // 0x00: addi x1, x0, 10      # x1 = 10
        // 0x04: addi x2, x1, 5       # x2 = x1 + 5 = 15 (EX-to-EX FwdA)
        // 0x08: addi x3, x2, 20      # x3 = x2 + 20 = 35 (EX-to-EX FwdA)
        u_CPU.u_sram_2kb.mem[0]  = encode_addi(5'd1, 5'd0, 12'd10);
        u_CPU.u_sram_2kb.mem[1]  = encode_addi(5'd2, 5'd1, 12'd5);
        u_CPU.u_sram_2kb.mem[2]  = encode_addi(5'd3, 5'd2, 12'd20);

        // Test 2: MEM-to-EX Forwarding (2 cycles apart)
        // 0x0C: addi x4, x0, 100     # x4 = 100
        // 0x10: addi x0, x0, 0       # NOP
        // 0x14: addi x5, x4, 50      # x5 = x4 + 50 = 150 (MEM-to-EX FwdA)
        u_CPU.u_sram_2kb.mem[3]  = encode_addi(5'd4, 5'd0, 12'd100);
        u_CPU.u_sram_2kb.mem[4]  = encode_addi(5'd0, 5'd0, 12'd0);
        u_CPU.u_sram_2kb.mem[5]  = encode_addi(5'd5, 5'd4, 12'd50);

        // Test 3: Load-to-Use Hazard (1-cycle interlock stall)
        // 0x18: lw x6, 0x80(x0)      # x6 = 0x12345678
        // 0x1C: addi x7, x6, 1       # Load-to-Use stall 1 cycle -> x7 = 0x12345679
        u_CPU.u_sram_2kb.mem[6]  = encode_lw(5'd6, 5'd0, 12'h080);
        u_CPU.u_sram_2kb.mem[7]  = encode_addi(5'd7, 5'd6, 12'd1);

        // Test 4: Independent instruction after Load (0 stall)
        // 0x20: lw x8, 0x84(x0)      # x8 = 0xAABBCCDD
        // 0x24: addi x9, x0, 42      # Independent -> 0-cycle stall -> x9 = 42
        u_CPU.u_sram_2kb.mem[8]  = encode_lw(5'd8, 5'd0, 12'h084);
        u_CPU.u_sram_2kb.mem[9]  = encode_addi(5'd9, 5'd0, 12'd42);

        // Test 5: Store Data Forwarding (RAW into SW store data)
        // 0x28: addi x10, x0, 99     # x10 = 99
        // 0x2C: sw x10, 0x88(x0)     # Store x10 to 0x88 (Fwd Store Data from EX/MEM)
        // 0x30: lw x11, 0x88(x0)     # Load back into x11 -> x11 = 99
        u_CPU.u_sram_2kb.mem[10] = encode_addi(5'd10, 5'd0, 12'd99);
        u_CPU.u_sram_2kb.mem[11] = encode_sw(5'd10, 5'd0, 12'h088);
        u_CPU.u_sram_2kb.mem[12] = encode_lw(5'd11, 5'd0, 12'h088);

        // Test 6: Branch Misprediction Recovery (forward branch mispredicts, skips fall-through)
        // 0x34: addi x12, x0, 1      # x12 = 1
        // 0x38: addi x13, x0, 2      # x13 = 2
        // 0x3C: bne x12, x13, +12    # 1 != 2 -> TAKEN, jump to 0x48 (+12 bytes)
        // 0x40: addi x14, x0, 99     # WRONG PATH (must NOT execute!)
        // 0x44: addi x14, x0, 99     # WRONG PATH (must NOT execute!)
        // 0x48: addi x15, x0, 77     # TARGET -> x15 = 77
        u_CPU.u_sram_2kb.mem[13] = encode_addi(5'd12, 5'd0, 12'd1);
        u_CPU.u_sram_2kb.mem[14] = encode_addi(5'd13, 5'd0, 12'd2);
        u_CPU.u_sram_2kb.mem[15] = encode_bne(5'd12, 5'd13, 13'd12);
        u_CPU.u_sram_2kb.mem[16] = encode_addi(5'd14, 5'd0, 12'd99);
        u_CPU.u_sram_2kb.mem[17] = encode_addi(5'd14, 5'd0, 12'd99);
        u_CPU.u_sram_2kb.mem[18] = encode_addi(5'd15, 5'd0, 12'd77);

        // Test 7: Hardware Multiplier EX-to-EX Forwarding
        // 0x4C: mul x16, x1, x2      # x16 = 10 * 15 = 150
        // 0x50: addi x17, x16, 10    # x17 = x16 + 10 = 160 (EX-to-EX from Multiplier!)
        u_CPU.u_sram_2kb.mem[19] = encode_mul(5'd16, 5'd1, 5'd2);
        u_CPU.u_sram_2kb.mem[20] = encode_addi(5'd17, 5'd16, 12'd10);

        // 0x54: jal x0, 0            # Infinite loop stop
        u_CPU.u_sram_2kb.mem[21] = encode_jal(5'd0, 21'd0);

        // Reset DUT
        rst_n = 0;
        #20;
        rst_n = 1;

        // Run until infinite loop at PC 0x54
        while (u_CPU.w_id_ex_pc != 32'h00000054) begin
            @(posedge clk);
        end

        // Wait a few cycles for all stages to commit
        repeat(5) @(posedge clk);

        $display("--------------------------------------------------------------------------------");
        $display(" VERIFYING RESULTS:");
        $display("--------------------------------------------------------------------------------");

        // Test 1: EX-to-EX Forwarding
        check_reg(5'd1, 32'd10, "EX-to-EX: x1 = 10");
        check_reg(5'd2, 32'd15, "EX-to-EX: x2 = x1 + 5 = 15");
        check_reg(5'd3, 32'd35, "EX-to-EX: x3 = x2 + 20 = 35");

        // Test 2: MEM-to-EX Forwarding
        check_reg(5'd4, 32'd100, "MEM-to-EX: x4 = 100");
        check_reg(5'd5, 32'd150, "MEM-to-EX: x5 = x4 + 50 = 150");

        // Test 3: Load-to-Use Hazard Stall
        check_reg(5'd6, 32'h12345678, "Load: x6 = Mem[0x80]");
        check_reg(5'd7, 32'h12345679, "Load-to-Use Stall: x7 = x6 + 1");

        // Test 4: Independent instruction after Load
        check_reg(5'd8, 32'hAABBCCDD, "Independent Load: x8 = Mem[0x84]");
        check_reg(5'd9, 32'd42,       "Independent Exec: x9 = 42");

        // Test 5: Store Data Forwarding
        check_reg(5'd10, 32'd99,      "Store Data: x10 = 99");
        check_mem(32'd34, 32'd99,     "Store Data Forwarding: Mem[0x88] == 99");
        check_reg(5'd11, 32'd99,      "Store-then-Load: x11 == 99");

        // Test 6: Branch Mispredict & Wrong Path Suppression
        check_reg(5'd14, 32'd0,       "Branch Skip Wrong Path: x14 must remain 0");
        check_reg(5'd15, 32'd77,      "Branch Target: x15 == 77");

        // Test 7: Multiplier EX-to-EX Forwarding
        check_reg(5'd16, 32'd150,     "Multiplier 1-cycle: x16 = 10 * 15 = 150");
        check_reg(5'd17, 32'd160,     "Multiplier EX-to-EX: x17 = 150 + 10 = 160");

        $display("================================================================================");
        $display(" TEST SUMMARY: Total Tests: %0d | Errors: %0d", test_count, error_count);
        $display("================================================================================");

        if (error_count == 0) begin
            $display(" >>> [SUCCESS] ALL PHASE 3 HAZARD & FORWARDING TESTS PASSED 100%%! <<<\n");
        end else begin
            $display(" >>> [ERROR] HAZARD TESTS FAILED WITH %0d ERRORS! <<<\n", error_count);
        end

        $finish;
    end

endmodule
