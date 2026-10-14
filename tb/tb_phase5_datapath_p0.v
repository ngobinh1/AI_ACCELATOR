`timescale 1ns / 1ps
// ==============================================================================
// TESTBENCH: tb_phase5_datapath_p0
// DESCRIPTION: Directed Unit & Pipeline Verification for Phase 5 P0 Bug Fixes:
//              - P0-1: CSR Read Datapath & Latching
//              - P0-2: CSR Write Datapath (RS1 vs RS2)
//              - P0-3: Multiplier Load-to-Use Stall Interlock
//              - P0-4: Forwarding of JAL/JALR Link Address (PC+4) and CSR Data
// ==============================================================================

module tb_phase5_datapath_p0;

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

    function [31:0] encode_jal;
        input [4:0]  rd;
        input [20:0] offset;
        begin
            encode_jal = {offset[20], offset[10:1], offset[11], offset[19:12], rd, 7'b1101111};
        end
    endfunction

    function [31:0] encode_csrrw;
        input [4:0]  rd;
        input [4:0]  rs1;
        input [11:0] csr;
        begin
            encode_csrrw = {csr, rs1, 3'b001, rd, 7'b1110011};
        end
    endfunction

    function [31:0] encode_csrrs;
        input [4:0]  rd;
        input [4:0]  rs1;
        input [11:0] csr;
        begin
            encode_csrrs = {csr, rs1, 3'b010, rd, 7'b1110011};
        end
    endfunction

    integer error_count = 0;
    integer test_count  = 0;

    task check_reg;
        input [4:0]        reg_idx;
        input [31:0]       expected_val;
        input [8*48-1:0]   test_name;
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

    task check_csr;
        input [31:0]       expected_val;
        input [8*48-1:0]   test_name;
        reg   [31:0]       actual_val;
        begin
            test_count = test_count + 1;
            actual_val = u_CPU.u_csr.mscratch;
            if (actual_val === expected_val) begin
                $display(" [PASS] Test %0d: %0s | mscratch = 0x%08h", 
                         test_count, test_name, actual_val);
            end else begin
                $display(" [FAIL] Test %0d: %0s | mscratch Expected: 0x%08h, Got: 0x%08h", 
                         test_count, test_name, expected_val, actual_val);
                error_count = error_count + 1;
            end
        end
    endtask

    integer k;

    initial begin
        $display("================================================================================");
        $display("   PHASE 5: DATAPATH, FORWARDING & MULTIPLIER P0 BUG VERIFICATION SUITE         ");
        $display("================================================================================");

        // Clear SRAM memory
        for (k = 0; k < 512; k = k + 1) begin
            u_CPU.u_sram_2kb.mem[k] = 32'd0;
        end

        // Pre-load data in memory for Load-to-Use -> Multiplier test
        // Word 64 = Address 0x100
        u_CPU.u_sram_2kb.mem[64] = 32'd15;

        // =====================================================================
        // ASSEMBLE PROGRAM INTO INSTRUCTION MEMORY (u_sram_2kb)
        // =====================================================================

        // ---------------------------------------------------------------------
        // PART 1: CSR WRITE & READ (P0-1 & P0-2)
        // ---------------------------------------------------------------------
        // 0x00: addi x5, x0, 0x789           # x5 = 0x00000789
        // 0x04: csrw mscratch, x5            # CSRRW x0, x5, 0x340 -> mscratch = 0x789
        // 0x08: csrr x6, mscratch            # CSRRS x6, x0, 0x340 -> x6 = mscratch = 0x789
        // 0x0C: addi x7, x0, 0x555           # x7 = 0x00000555
        // 0x10: csrrw x8, x7, 0x340          # CSRRW x8, x7, 0x340 -> x8 = 0x789, mscratch = 0x555
        u_CPU.u_sram_2kb.mem[0] = encode_addi(5'd5, 5'd0, 12'h789);
        u_CPU.u_sram_2kb.mem[1] = encode_csrrw(5'd0, 5'd5, 12'h340);
        u_CPU.u_sram_2kb.mem[2] = encode_csrrs(5'd6, 5'd0, 12'h340);
        u_CPU.u_sram_2kb.mem[3] = encode_addi(5'd7, 5'd0, 12'h555);
        u_CPU.u_sram_2kb.mem[4] = encode_csrrw(5'd8, 5'd7, 12'h340);

        // ---------------------------------------------------------------------
        // PART 2: LOAD-TO-USE INTERLOCK INTO MULTIPLIER (P0-3)
        // ---------------------------------------------------------------------
        // 0x14: addi x10, x0, 0x100          # x10 = 0x100 (Address of Word 64)
        // 0x18: addi x11, x0, 4              # x11 = 4
        // 0x1C: lw   x12, 0(x10)             # x12 = Mem[0x100] = 15
        // 0x20: mul  x13, x12, x11           # x13 = 15 * 4 = 60 (Load-to-MUL RAW Hazard!)
        u_CPU.u_sram_2kb.mem[5] = encode_addi(5'd10, 5'd0, 12'h100);
        u_CPU.u_sram_2kb.mem[6] = encode_addi(5'd11, 5'd0, 12'd4);
        u_CPU.u_sram_2kb.mem[7] = encode_lw  (5'd12, 5'd10, 12'd0);
        u_CPU.u_sram_2kb.mem[8] = encode_mul (5'd13, 5'd12, 5'd11);

        // ---------------------------------------------------------------------
        // PART 3: JAL LINK ADDRESS (PC+4) FORWARDING (P0-4)
        // ---------------------------------------------------------------------
        // 0x24: jal x1, +16                  # Jump to 0x34 (Word 13). x1 = PC+4 = 0x28
        // 0x28: addi x0, x0, 0               # NOP (Flushed by JAL)
        // 0x2C: addi x0, x0, 0               # NOP
        // 0x30: addi x0, x0, 0               # NOP
        // 0x34: addi x14, x1, 10             # Target: reads x1 immediately! x14 = 0x28 + 10 = 0x32
        u_CPU.u_sram_2kb.mem[9]  = encode_jal (5'd1, 21'd16);
        u_CPU.u_sram_2kb.mem[10] = encode_addi(5'd0, 5'd0, 12'd0);
        u_CPU.u_sram_2kb.mem[11] = encode_addi(5'd0, 5'd0, 12'd0);
        u_CPU.u_sram_2kb.mem[12] = encode_addi(5'd0, 5'd0, 12'd0);
        u_CPU.u_sram_2kb.mem[13] = encode_addi(5'd14, 5'd1, 12'd10);

        // ---------------------------------------------------------------------
        // PART 4: CSR READ FORWARDING TO ADJACENT INSTRUCTION (P0-4)
        // ---------------------------------------------------------------------
        // 0x38: csrr x15, mscratch           # CSRRS x15, x0, 0x340 -> x15 = 0x555
        // 0x3C: addi x16, x15, 1             # Reads x15 immediately! x16 = 0x555 + 1 = 0x556
        // 0x40: addi x0, x0, 0               # NOPs to allow commit
        // 0x44: addi x0, x0, 0
        u_CPU.u_sram_2kb.mem[14] = encode_csrrs(5'd15, 5'd0, 12'h340);
        u_CPU.u_sram_2kb.mem[15] = encode_addi(5'd16, 5'd15, 12'd1);
        u_CPU.u_sram_2kb.mem[16] = encode_addi(5'd0, 5'd0, 12'd0);
        u_CPU.u_sram_2kb.mem[17] = encode_addi(5'd0, 5'd0, 12'd0);
        u_CPU.u_sram_2kb.mem[18] = encode_addi(5'd0, 5'd0, 12'd0);

        // Reset sequence
        rst_n = 0;
        #20;
        rst_n = 1;

        // Run simulation for sufficient cycles
        // Multiplier takes 8 cycles + Load-use takes 1 cycle stall
        #600;

        $display("--------------------------------------------------------------------------------");
        $display(" VERIFYING RESULTS:");
        $display("--------------------------------------------------------------------------------");

        // Verification for Part 1 (P0-1 & P0-2)
        check_reg(5'd5, 32'h00000789, "Part 1A: Setup x5 = 0x789");
        check_csr(32'h00000555,       "Part 1B: CSR Write P0-2 (mscratch updated)");
        check_reg(5'd6, 32'h00000789, "Part 1C: CSR Read P0-1 (x6 = mscratch read data)");
        check_reg(5'd8, 32'h00000789, "Part 1D: CSRRW Swap (x8 = old mscratch)");

        // Verification for Part 2 (P0-3)
        check_reg(5'd12, 32'd15,      "Part 2A: Load Word (x12 = Mem[0x100])");
        check_reg(5'd13, 32'd60,      "Part 2B: Load-to-Use -> MUL Interlock (x13 = 15 * 4 = 60)");

        // Verification for Part 3 (P0-4)
        check_reg(5'd1,  32'h00000028, "Part 3A: JAL Link Address (x1 = PC+4 = 0x28)");
        check_reg(5'd14, 32'h00000032, "Part 3B: JAL Link FWD P0-4 (x14 = 0x28 + 10 = 0x32)");

        // Verification for Part 4 (P0-4 CSR Forwarding)
        check_reg(5'd15, 32'h00000555, "Part 4A: CSR Read (x15 = mscratch = 0x555)");
        check_reg(5'd16, 32'h00000556, "Part 4B: CSR Read Forwarding (x16 = 0x555 + 1 = 0x556)");

        $display("================================================================================");
        $display(" TEST SUMMARY: Total Tests: %0d | Errors: %0d", test_count, error_count);
        $display("================================================================================");

        if (error_count == 0) begin
            $display(" >>> [SUCCESS] ALL PHASE 5 DATAPATH & FORWARDING P0 TESTS PASSED 100%%! <<< \n");
        end else begin
            $display(" >>> [FAILURE] %0d TESTS FAILED! PLEASE REVIEW SIGNALS. <<< \n", error_count);
        end

        $finish;
    end

endmodule
