`timescale 1ns / 1ps
// ==============================================================================
// MODULE: pipe_reg_if_id
// DESCRIPTION: Pipeline Register separating Stage 1 (IF) and Stage 2 (ID/EX)
// ARCHITECTURE: RISC-V 32-bit IoT & AI Accelerator Core (Phase 3 Option B)
// ==============================================================================

module pipe_reg_if_id #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input  wire                  i_clk,
    input  wire                  i_rst_n,

    // ==========================================
    // PIPELINE FLOW CONTROL
    // ==========================================
    input  wire                  i_stall,        // Freeze register state
    input  wire                  i_flush,        // Clear instruction (Inject NOP)

    // ==========================================
    // INPUTS FROM STAGE 1 (IF)
    // ==========================================
    input  wire                  i_valid,        // Instruction valid flag from IF
    input  wire [ADDR_WIDTH-1:0] i_pc,           // Program Counter of current instruction
    input  wire [ADDR_WIDTH-1:0] i_pc_plus_4,     // PC + 4 link address
    input  wire [DATA_WIDTH-1:0] i_instr,        // Raw 32-bit instruction from SRAM Port 1
    input  wire                  i_pred_taken,   // Static BTFN branch prediction flag

    // ==========================================
    // REGISTERED OUTPUTS TO STAGE 2 (ID/EX)
    // ==========================================
    output reg                   o_valid,
    output reg  [ADDR_WIDTH-1:0] o_pc,
    output reg  [ADDR_WIDTH-1:0] o_pc_plus_4,
    output reg  [DATA_WIDTH-1:0] o_instr,
    output reg                   o_pred_taken,

    // Dedicated low-fanout registers for forwarding unit
    (* keep = "true" *) output reg [4:0] o_fwd_rs1,
    (* keep = "true" *) output reg [4:0] o_fwd_rs2
);

    `include "riscv_core_defines.vh"

    // =========================================================================
    // SYNCHRONOUS REGISTER UPDATES
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_valid      <= 1'b0;
            o_pc         <= RESET_VEC;
            o_pc_plus_4  <= RESET_VEC;
            o_instr      <= INST_NOP; // NOP = addi x0, x0, 0 (32'h0000_0013)
            o_pred_taken <= 1'b0;
            o_fwd_rs1    <= 5'b0;
            o_fwd_rs2    <= 5'b0;
        end else if (i_flush) begin
            o_valid      <= 1'b0;
            o_pc         <= RESET_VEC;
            o_pc_plus_4  <= RESET_VEC;
            o_instr      <= INST_NOP;
            o_pred_taken <= 1'b0;
            o_fwd_rs1    <= 5'b0;
            o_fwd_rs2    <= 5'b0;
        end else if (!i_stall) begin
            o_valid      <= i_valid;
            o_pc         <= i_pc;
            o_pc_plus_4  <= i_pc_plus_4;
            o_instr      <= i_instr;
            o_pred_taken <= i_pred_taken;
            o_fwd_rs1    <= i_instr[`RS1_FIELD];
            o_fwd_rs2    <= i_instr[`RS2_FIELD];
        end
    end

endmodule
