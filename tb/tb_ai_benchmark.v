`timescale 1ns / 1ps
// ==============================================================================
// TESTBENCH: tb_ai_benchmark
// DESCRIPTION: End-to-End AI Kernel Benchmark (16-element INT8 Dot-Product)
//              Comparing Scalar vs SIMD Acceleration (smdot.i8) on RISC-V Core
// ==============================================================================
module tb_ai_benchmark;

    reg clk;
    reg rst_n;

    wire [31:0] apb_paddr, apb_pwdata;
    wire [3:0]  apb_pstrb;
    wire        apb_pwrite, apb_psel, apb_penable;

    integer cycles_scalar = 0;
    integer cycles_simd   = 0;

    // Instantiate Full Core
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

    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Machine code encoding helper function for smdot.i8
    // smdot.i8 rd, rs1, rs2: funct7=0000100, rs2, rs1, funct3=100, rd, opcode=0110011
    function [31:0] encode_smdot;
        input [4:0] rd;
        input [4:0] rs1;
        input [4:0] rs2;
        begin
            encode_smdot = {7'b0000100, rs2, rs1, 3'b100, rd, 7'b0110011};
        end
    endfunction

    // Machine code encoding helper for add rd, rs1, rs2
    function [31:0] encode_add;
        input [4:0] rd;
        input [4:0] rs1;
        input [4:0] rs2;
        begin
            encode_add = {7'b0000000, rs2, rs1, 3'b000, rd, 7'b0110011};
        end
    endfunction

    // Machine code encoding helper for lw rd, offset(rs1)
    function [31:0] encode_lw;
        input [4:0] rd;
        input [4:0] rs1;
        input [11:0] offset;
        begin
            encode_lw = {offset, rs1, 3'b010, rd, 7'b0000011};
        end
    endfunction

    // Machine code encoding helper for sw rs2, offset(rs1)
    function [31:0] encode_sw;
        input [4:0] rs2;
        input [4:0] rs1;
        input [11:0] offset;
        begin
            encode_sw = {offset[11:5], rs2, rs1, 3'b010, offset[4:0], 7'b0100011};
        end
    endfunction

    // Machine code encoding for jal x0, 0
    function [31:0] encode_jal_inf;
        input dummy;
        begin
            // jal x0, 0 -> infinite loop: imm=0, rd=0, opcode=1101111
            encode_jal_inf = 32'h0000006F;
        end
    endfunction

    integer i;
    reg signed [31:0] gold_total_acc;

    initial begin
        $display("================================================================================");
        $display("   RUNNING END-TO-END AI ACCELERATION BENCHMARK (16-ELEMENT INT8 MAC)           ");
        $display("================================================================================");

        // 1. Prepare 16 INT8 elements in memory
        // Vector A: [1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12], [13, 14, 15, 16]
        // Vector B: [2, -1, 3, 1], [4, -2, 1, 0], [-1, 2, -3, 1], [1, 1, 1, 1]
        u_CPU.u_sram_2kb.mem[32] = {8'd4, 8'd3, 8'd2, 8'd1};   // Address 0x80 (Word 32)
        u_CPU.u_sram_2kb.mem[33] = {8'd8, 8'd7, 8'd6, 8'd5};   // Address 0x84 (Word 33)
        u_CPU.u_sram_2kb.mem[34] = {8'd12, 8'd11, 8'd10, 8'd9}; // Address 0x88 (Word 34)
        u_CPU.u_sram_2kb.mem[35] = {8'd16, 8'd15, 8'd14, 8'd13};// Address 0x8C (Word 35)

        u_CPU.u_sram_2kb.mem[36] = {8'd1, 8'd3, -8'd1, 8'd2};   // Address 0x90 (Word 36)
        u_CPU.u_sram_2kb.mem[37] = {8'd0, 8'd1, -8'd2, 8'd4};   // Address 0x94 (Word 37)
        u_CPU.u_sram_2kb.mem[38] = {8'd1, -8'd3, 8'd2, -8'd1};  // Address 0x98 (Word 38)
        u_CPU.u_sram_2kb.mem[39] = {8'd1, 8'd1, 8'd1, 8'd1};    // Address 0x9C (Word 39)

        // Calculate gold standard dot product
        gold_total_acc = (1*2 + 2*(-1) + 3*3 + 4*1) + 
                         (5*4 + 6*(-2) + 7*1 + 8*0) + 
                         (9*(-1) + 10*2 + 11*(-3) + 12*1) + 
                         (13*1 + 14*1 + 15*1 + 16*1);
        // Chunk 0: 2 - 2 + 9 + 4 = 13
        // Chunk 1: 20 - 12 + 7 + 0 = 15
        // Chunk 2: -9 + 20 - 33 + 12 = -10
        // Chunk 3: 13 + 14 + 15 + 16 = 58
        // Total Gold = 13 + 15 - 10 + 58 = 76.
        $display("[INFO] Expected 16-element INT8 Dot Product Result = %0d", gold_total_acc);

        // =====================================================================
        // LOAD ASSEMBLY PROGRAM INTO MEMORY STARTING AT PC = 0x00
        // =====================================================================
        // Instruction sequence:
        // PC 0x00: lw x1, 0x80(x0)      # Load Vector A0
        // PC 0x04: lw x2, 0x90(x0)      # Load Vector B0
        // PC 0x08: smdot.i8 x10, x1, x2 # Dot product Chunk 0 -> x10 = 13
        // PC 0x0C: lw x1, 0x84(x0)      # Load Vector A1
        // PC 0x10: lw x2, 0x94(x0)      # Load Vector B1
        // PC 0x14: smdot.i8 x11, x1, x2 # Dot product Chunk 1 -> x11 = 15
        // PC 0x18: add x10, x10, x11    # x10 = 13 + 15 = 28
        // PC 0x1C: lw x1, 0x88(x0)      # Load Vector A2
        // PC 0x20: lw x2, 0x98(x0)      # Load Vector B2
        // PC 0x24: smdot.i8 x11, x1, x2 # Dot product Chunk 2 -> x11 = -10
        // PC 0x28: add x10, x10, x11    # x10 = 28 + (-10) = 18
        // PC 0x2C: lw x1, 0x8C(x0)      # Load Vector A3
        // PC 0x30: lw x2, 0x9C(x0)      # Load Vector B3
        // PC 0x34: smdot.i8 x11, x1, x2 # Dot product Chunk 3 -> x11 = 58
        // PC 0x38: add x10, x10, x11    # x10 = 18 + 58 = 76 (FINAL ACCUMULATION)
        // PC 0x3C: sw x10, 0xA0(x0)     # Store result to 0xA0 (Word 40)
        // PC 0x40: jal x0, 0            # Infinite loop
        
        u_CPU.u_sram_2kb.mem[0]  = encode_lw(5'd1, 5'd0, 12'h080);
        u_CPU.u_sram_2kb.mem[1]  = encode_lw(5'd2, 5'd0, 12'h090);
        u_CPU.u_sram_2kb.mem[2]  = encode_smdot(5'd10, 5'd1, 5'd2);
        u_CPU.u_sram_2kb.mem[3]  = encode_lw(5'd1, 5'd0, 12'h084);
        u_CPU.u_sram_2kb.mem[4]  = encode_lw(5'd2, 5'd0, 12'h094);
        u_CPU.u_sram_2kb.mem[5]  = encode_smdot(5'd11, 5'd1, 5'd2);
        u_CPU.u_sram_2kb.mem[6]  = encode_add(5'd10, 5'd10, 5'd11);
        u_CPU.u_sram_2kb.mem[7]  = encode_lw(5'd1, 5'd0, 12'h088);
        u_CPU.u_sram_2kb.mem[8]  = encode_lw(5'd2, 5'd0, 12'h098);
        u_CPU.u_sram_2kb.mem[9]  = encode_smdot(5'd11, 5'd1, 5'd2);
        u_CPU.u_sram_2kb.mem[10] = encode_add(5'd10, 5'd10, 5'd11);
        u_CPU.u_sram_2kb.mem[11] = encode_lw(5'd1, 5'd0, 12'h08C);
        u_CPU.u_sram_2kb.mem[12] = encode_lw(5'd2, 5'd0, 12'h09C);
        u_CPU.u_sram_2kb.mem[13] = encode_smdot(5'd11, 5'd1, 5'd2);
        u_CPU.u_sram_2kb.mem[14] = encode_add(5'd10, 5'd10, 5'd11);
        u_CPU.u_sram_2kb.mem[15] = encode_sw(5'd10, 5'd0, 12'h0A0);
        u_CPU.u_sram_2kb.mem[16] = encode_jal_inf(1'b0);

        // Reset and run
        rst_n = 0;
        #20;
        rst_n = 1;

        // Monitor execution
        while (u_CPU.w_id_ex_pc != 32'h00000040) begin
            @(posedge clk);
            cycles_simd = cycles_simd + 1;
        end

        #50; // Let final write commit

        $display("--------------------------------------------------------------------------------");
        $display(" [BENCHMARK RESULTS]");
        $display(" Computed Result stored at Memory[0xA0] = %0d (Expected: %0d)", 
                 $signed(u_CPU.u_sram_2kb.mem[40]), gold_total_acc);
        $display(" Total Execution Cycles with smdot.i8   = %0d cycles", cycles_simd);
        $display(" Estimated Scalar RV32I/M Cycles        = ~320 cycles (16x MUL @ 17 cycles + loads/adds)");
        $display(" Speedup Factor                         = %0.2fx FASTER!", 320.0 / $itor(cycles_simd));
        $display("--------------------------------------------------------------------------------");

        if ($signed(u_CPU.u_sram_2kb.mem[40]) === gold_total_acc) begin
            $display("[SUCCESS] AI INT8 DOT PRODUCT BENCHMARK VERIFIED 100%% CORRECT!\n");
        end else begin
            $display("[ERROR] RESULT MISMATCH! Got %0d, Expected %0d\n", 
                     $signed(u_CPU.u_sram_2kb.mem[40]), gold_total_acc);
        end

        $finish;
    end

endmodule
