`timescale 1ns / 1ps
// ==============================================================================
// TESTBENCH: tb_phase6_control_traps
// DESCRIPTION: Verification Suite for Phase 6 Control, Traps, Interrupts & APB:
//              - P0-5: Async interrupt commit & mepc preservation
//              - P0-6: APB Bridge wait-states & combinational loop removal
//              - P0-7: Illegal instruction trap on DIV/REM opcodes
//              - R-16: EBREAK instruction decoding & breakpoint trap
//              - R-17: mtval read/write and mtvec direct mode vector masking
//              - R-12: 2KB SRAM bounds check & memory access fault trap
// ==============================================================================

module tb_phase6_control_traps;

    reg clk;
    reg rst_n;
    reg ext_irq;
    reg timer_irq;

    // APB Slave signals
    wire [31:0] apb_paddr, apb_pwdata;
    wire [3:0]  apb_pstrb;
    wire        apb_pwrite, apb_psel, apb_penable;
    reg  [31:0] apb_prdata;
    reg         apb_pready;
    reg         apb_pslverr;

    // APB Slave model with 2-cycle wait states
    reg [2:0]   r_apb_wait;
    reg [31:0]  r_apb_mem;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_apb_wait   <= 3'd0;
            apb_pready   <= 1'b0;
            apb_prdata   <= 32'd0;
            apb_pslverr  <= 1'b0;
            r_apb_mem    <= 32'hFEED_FACE;
        end else begin
            if (apb_psel && apb_penable) begin
                if (r_apb_wait < 3'd2) begin
                    r_apb_wait <= r_apb_wait + 3'd1;
                    apb_pready <= 1'b0;
                end else begin
                    apb_pready <= 1'b1;
                    r_apb_wait <= 3'd0;
                    if (apb_pwrite) begin
                        r_apb_mem <= apb_pwdata;
                    end else begin
                        apb_prdata <= r_apb_mem;
                    end
                end
            end else begin
                r_apb_wait <= 3'd0;
                apb_pready <= 1'b0;
            end
        end
    end

    // DUT Instantiation
    riscv_core_top u_CPU (
        .i_clk         (clk),
        .i_rst_n       (rst_n),
        .i_ext_irq     (ext_irq),
        .i_timer_irq   (timer_irq),
        .o_apb_paddr   (apb_paddr),
        .o_apb_pwrite  (apb_pwrite),
        .o_apb_pstrb   (apb_pstrb),
        .o_apb_psel    (apb_psel),
        .o_apb_penable (apb_penable),
        .o_apb_pwdata  (apb_pwdata),
        .i_apb_prdata  (apb_prdata),
        .i_apb_pready  (apb_pready),
        .i_apb_pslverr (apb_pslverr)
    );

    // Clock generator (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Verification bookkeeping
    integer test_count  = 0;
    integer pass_count  = 0;
    integer error_count = 0;

    task check_reg;
        input [4:0]    reg_idx;
        input [31:0]   expected_val;
        input [1023:0] test_name;
        reg   [31:0]   actual_val;
        begin
            test_count = test_count + 1;
            actual_val = u_CPU.u_stage_id_ex.u_register_file.r_regs[reg_idx];
            if (actual_val === expected_val) begin
                $display(" [PASS] Test %0d: %0s | x%0d = 0x%08h (%0d)", 
                         test_count, test_name, reg_idx, actual_val, actual_val);
                pass_count = pass_count + 1;
            end else begin
                $display(" [FAIL] Test %0d: %0s | x%0d Expected: 0x%08h, Got: 0x%08h", 
                         test_count, test_name, reg_idx, expected_val, actual_val);
                error_count = error_count + 1;
            end
        end
    endtask

    task check_mem;
        input [10:0]   word_idx;
        input [31:0]   expected_val;
        input [1023:0] test_name;
        reg   [31:0]   actual_val;
        begin
            test_count = test_count + 1;
            actual_val = u_CPU.u_sram_2kb.mem[word_idx];
            if (actual_val === expected_val) begin
                $display(" [PASS] Test %0d: %0s | Mem[0x%03h] = 0x%08h", 
                         test_count, test_name, (word_idx << 2), actual_val);
                pass_count = pass_count + 1;
            end else begin
                $display(" [FAIL] Test %0d: %0s | Mem[0x%03h] Expected: 0x%08h, Got: 0x%08h", 
                         test_count, test_name, (word_idx << 2), expected_val, actual_val);
                error_count = error_count + 1;
            end
        end
    endtask


    integer k;

    // Interrupt injection control:
    // When PC reaches 0x58 (csrs mstatus, 8), trigger external interrupt.
    // Deassert when PC enters trap handler at 0x100.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ext_irq <= 1'b0;
        end else begin
            if (u_CPU.w_id_ex_pc == 32'h58 && u_CPU.w_id_ex_valid) begin
                ext_irq <= 1'b1;
            end
            if (u_CPU.w_id_pc == 32'h100) begin
                ext_irq <= 1'b0;
            end
        end
    end

    initial begin
        $display("================================================================================");
        $display("   PHASE 6: CONTROL, TRAPS, INTERRUPTS & APB VERIFICATION SUITE                 ");
        $display("================================================================================");

        // Clear SRAM memory
        for (k = 0; k < 512; k = k + 1) begin
            u_CPU.u_sram_2kb.mem[k] = 32'd0;
        end

        timer_irq = 1'b0;

        // =====================================================================
        // ASSEMBLE PROGRAM INTO INSTRUCTION MEMORY (u_sram_2kb)
        // =====================================================================

        // 0x00: li   x1, 0x100
        u_CPU.u_sram_2kb.mem[0]  = 32'h10000093;
        // 0x04: csrw mtvec, x1
        u_CPU.u_sram_2kb.mem[1]  = 32'h30509073;
        // 0x08: li   x2, 0x123
        u_CPU.u_sram_2kb.mem[2]  = 32'h12300113;
        // 0x0C: csrw mtval, x2
        u_CPU.u_sram_2kb.mem[3]  = 32'h34311073;
        // 0x10: csrr x3, mtval (CHECK 1: x3 = 0x123)
        u_CPU.u_sram_2kb.mem[4]  = 32'h343021f3;

        // 0x14: li   x4, 0x101 (mtvec Direct Mode with Mode bit 0 = 1)
        u_CPU.u_sram_2kb.mem[5]  = 32'h10100213;
        // 0x18: csrw mtvec, x4
        u_CPU.u_sram_2kb.mem[6]  = 32'h30521073;

        // 0x1C: li   x5, 0 (CHECK 2: must remain 0 after DIV illegal trap)
        u_CPU.u_sram_2kb.mem[7]  = 32'h00000293;
        // 0x20: li   x6, 20
        u_CPU.u_sram_2kb.mem[8]  = 32'h01400313;
        // 0x24: li   x7, 4
        u_CPU.u_sram_2kb.mem[9]  = 32'h00400393;
        // 0x28: div  x5, x6, x7 (Illegal instruction - Traps to mtvec aligned 0x100!)
        u_CPU.u_sram_2kb.mem[10] = 32'h027342b3;
        // 0x2C: nop (Target of mret return)
        u_CPU.u_sram_2kb.mem[11] = 32'h00000013;

        // 0x30: ebreak (Breakpoint - Traps to mtvec!)
        u_CPU.u_sram_2kb.mem[12] = 32'h00100073;
        // 0x34: nop (Target of mret return)
        u_CPU.u_sram_2kb.mem[13] = 32'h00000013;

        // 0x38: li   x1, 0x100
        u_CPU.u_sram_2kb.mem[14] = 32'h10000093;
        // 0x3C: csrw mtvec, x1
        u_CPU.u_sram_2kb.mem[15] = 32'h30509073;
        // 0x40: li   x8, 0x180 (Word 96)
        u_CPU.u_sram_2kb.mem[16] = 32'h18000413;
        // 0x44: li   x9, 0x77
        u_CPU.u_sram_2kb.mem[17] = 32'h07700493;
        // 0x48: lui  x12, 1
        u_CPU.u_sram_2kb.mem[18] = 32'h00001637;
        // 0x4C: addi x12, x12, -2048 (x12 = 0x800, MEIE)
        u_CPU.u_sram_2kb.mem[19] = 32'h80060613;
        // 0x50: csrw mie, x12
        u_CPU.u_sram_2kb.mem[20] = 32'h30461073;
        // 0x54: li   x13, 8 (MIE bit)
        u_CPU.u_sram_2kb.mem[21] = 32'h00800693;
        // 0x58: csrs mstatus, x13 (Enable interrupts)
        u_CPU.u_sram_2kb.mem[22] = 32'h3006a073;

        // 0x5C: sw   x9, 0(x8) (Commits to RAM[0x180] before interrupt jumps!)
        u_CPU.u_sram_2kb.mem[23] = 32'h00942023;
        // 0x60: addi x10, x0, 0x88 (Executed after mret!)
        u_CPU.u_sram_2kb.mem[24] = 32'h08800513;
        // 0x64: addi x11, x0, 0x99
        u_CPU.u_sram_2kb.mem[25] = 32'h09900593;
        // 0x68: csrc mstatus, x13 (Disable interrupts)
        u_CPU.u_sram_2kb.mem[26] = 32'h3006b073;

        // 0x6C: lui  x20, 1
        u_CPU.u_sram_2kb.mem[27] = 32'h00001a37;
        // 0x70: addi x20, x20, -2048 (x20 = 0x800, 2048 bytes - out of bounds!)
        u_CPU.u_sram_2kb.mem[28] = 32'h800a0a13;
        // 0x74: lw   x21, 0(x20) (Memory access fault trap: mcause = 5, mtval = 0x800)
        u_CPU.u_sram_2kb.mem[29] = 32'h000a2a83;
        // 0x78: nop (Target of mret return)
        u_CPU.u_sram_2kb.mem[30] = 32'h00000013;

        // 0x7C: lui  x22, 0x40000 (x22 = 0x4000_0000 APB MMIO)
        u_CPU.u_sram_2kb.mem[31] = 32'h40000b37;
        // 0x80: lui  x23, 0xD
        u_CPU.u_sram_2kb.mem[32] = 32'h0000dbb7;
        // 0x84: addi x23, x23, -1282 (x23 = 0xCAFE)
        u_CPU.u_sram_2kb.mem[33] = 32'hafeb8b93;
        // 0x88: sw   x23, 0(x22) (Store to APB with 2 wait states)
        u_CPU.u_sram_2kb.mem[34] = 32'h017b2023;
        // 0x8C: lw   x24, 0(x22) (Load from APB with 2 wait states)
        u_CPU.u_sram_2kb.mem[35] = 32'h000b2c03;
        // 0x90: nop
        u_CPU.u_sram_2kb.mem[36] = 32'h00000013;

        // 0x94: hang: j hang
        u_CPU.u_sram_2kb.mem[37] = 32'h0000006f;

        // =====================================================================
        // TRAP HANDLER AT 0x100 (WORD 64)
        // =====================================================================
        // 0x100: csrr t3, mcause (x28 = mcause)
        u_CPU.u_sram_2kb.mem[64] = 32'h34202e73;
        // 0x104: csrr t4, mepc   (x29 = mepc)
        u_CPU.u_sram_2kb.mem[65] = 32'h34102ef3;
        // 0x108: csrr t5, mtval  (x30 = mtval)
        u_CPU.u_sram_2kb.mem[66] = 32'h34302f73;
        // 0x10C: addi t6, t6, 1  (x31 = trap counter)
        u_CPU.u_sram_2kb.mem[67] = 32'h001f8f93;
        // 0x110: bltz t3, +16    (if interrupt, skip adding 4 to mepc -> jump to 0x120)
        u_CPU.u_sram_2kb.mem[68] = 32'h000e4863;
        // 0x114: addi t4, t4, 4  (advance mepc past faulting instruction)
        u_CPU.u_sram_2kb.mem[69] = 32'h004e8e93;
        // 0x118: csrw mepc, t4
        u_CPU.u_sram_2kb.mem[70] = 32'h341e9073;
        // 0x11C: nop
        u_CPU.u_sram_2kb.mem[71] = 32'h00000013;
        // 0x120: mret
        u_CPU.u_sram_2kb.mem[72] = 32'h30200073;

        // Reset sequence (Falling edge of clock at #20)
        rst_n = 1'b0;
        #20;
        rst_n = 1'b1;

        // Wait until core reaches hang loop at PC = 0x94
        wait(u_CPU.w_id_ex_pc == 32'h94 && u_CPU.w_id_ex_valid);
        #100; // Let pipeline settle

        $display("--------------------------------------------------------------------------------");
        $display(" VERIFYING RESULTS:");
        $display("--------------------------------------------------------------------------------");

        // 1. Check mtval write/read (R-17)
        check_reg(5'd3, 32'h123, "Part 1: mtval Write/Read (R-17)");

        // 2. Check DIV illegal instruction trap (P0-7)
        // x5 must NOT be incremented or added (x6 + x7 = 24), must remain 0
        check_reg(5'd5, 32'h0, "Part 2A: DIV does NOT execute ADD (P0-7)");

        // 3. Check Async Interrupt Commit (P0-5)
        // Mem[0x180] (Word 96) must be written with 0x77
        check_mem(11'd96, 32'h77, "Part 3A: SW committed before interrupt taken (P0-5)");

        // Instructions following SW must execute cleanly after mret
        check_reg(5'd10, 32'h88, "Part 3B: ADDI x10 executed after MRET (P0-5)");
        check_reg(5'd11, 32'h99, "Part 3C: ADDI x11 executed (P0-5)");

        // 4. Check APB MMIO read with wait states (P0-6)
        check_reg(5'd24, 32'hCAFE, "Part 4: APB MMIO Store and Load with Wait States (P0-6)");

        // 5. Check Total Traps Handled
        // Expected: 4 traps:
        // Trap 1: Illegal instruction (DIV)
        // Trap 2: Breakpoint (EBREAK)
        // Trap 3: External Interrupt
        // Trap 4: Memory Access Fault (SRAM > 2KB)
        check_reg(5'd31, 32'd4, "Part 5: Total Trap Count (DIV, EBREAK, IRQ, OOB)");

        // 6. Check last trap was OOB Access Fault (mcause = 5, mtval = 0x800)
        check_reg(5'd28, 32'd5, "Part 6A: Last Trap mcause == EXC_LOAD_ACCESS_FAULT (R-12)");
        check_reg(5'd30, 32'h800, "Part 6B: Last Trap mtval == Out-of-bounds Addr 0x800 (R-12)");

        $display("================================================================================");
        $display(" TEST SUMMARY: Total Tests: %0d | Passed: %0d | Errors: %0d", 
                 test_count, pass_count, error_count);
        $display("================================================================================");

        if (error_count == 0) begin
            $display(" >>> [SUCCESS] ALL PHASE 6 CONTROL & TRAPS TESTS PASSED 100%%! <<< \n");
        end else begin
            $display(" >>> [FAILURE] SOME PHASE 6 TESTS FAILED! <<<\n");
        end

        $finish;
    end

    // Safety timeout
    initial begin
        #50000;
        $display("\n[ERROR] TIMEOUT: Simulation ran too long!");
        $finish;
    end

endmodule
