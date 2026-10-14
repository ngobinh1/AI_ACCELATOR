`timescale 1ns / 1ps
// ==============================================================================
// MODULE: simd_mac_unit
// DESCRIPTION: 4x INT8 Packed SIMD Dot-Product Unit (smdot.i8) for Edge AI
// ==============================================================================
module simd_mac_unit (
    input  wire [31:0] i_rs1,
    input  wire [31:0] i_rs2,
    output wire [31:0] o_simd_result
);

    // =========================================================================
    // 1. BYTE SLICING (4x 8-bit SIGNED INTEGERS)
    // =========================================================================
    wire signed [7:0] w_a0 = i_rs1[7:0];
    wire signed [7:0] w_a1 = i_rs1[15:8];
    wire signed [7:0] w_a2 = i_rs1[23:16];
    wire signed [7:0] w_a3 = i_rs1[31:24];

    wire signed [7:0] w_b0 = i_rs2[7:0];
    wire signed [7:0] w_b1 = i_rs2[15:8];
    wire signed [7:0] w_b2 = i_rs2[23:16];
    wire signed [7:0] w_b3 = i_rs2[31:24];

    // =========================================================================
    // 2. PARALLEL 8x8 SIGNED MULTIPLIERS (16-bit SIGNED OUTPUTS)
    // =========================================================================
    wire signed [15:0] w_prod0 = w_a0 * w_b0;
    wire signed [15:0] w_prod1 = w_a1 * w_b1;
    wire signed [15:0] w_prod2 = w_a2 * w_b2;
    wire signed [15:0] w_prod3 = w_a3 * w_b3;

    // =========================================================================
    // 3. BALANCED 2-LEVEL ADDER TREE (NO OVERFLOW)
    // =========================================================================
    // Layer 1: Two 17-bit signed additions
    wire signed [16:0] w_sum_01 = {w_prod0[15], w_prod0} + {w_prod1[15], w_prod1};
    wire signed [16:0] w_sum_23 = {w_prod2[15], w_prod2} + {w_prod3[15], w_prod3};

    // Layer 2: Final 32-bit sign-extended accumulation
    wire signed [31:0] w_final_sum = {{15{w_sum_01[16]}}, w_sum_01} + 
                                     {{15{w_sum_23[16]}}, w_sum_23};

    assign o_simd_result = w_final_sum;

endmodule
