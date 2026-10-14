`timescale 1ns / 1ps
// ==============================================================================
// MODULE: forwarding_unit
// DESCRIPTION: Data Forwarding Unit & Load-to-Use Hazard Detection for 3-Stage Pipeline
// ARCHITECTURE: RISC-V 32-bit IoT & AI Accelerator Core (Phase 5)
// ==============================================================================

module forwarding_unit (
    // =========================================================================
    // 1. STAGE 2 (ID/EX) OPERAND SOURCE ADDRESSES & USAGE
    // =========================================================================
    input  wire [4:0]  i_id_ex_rs1,          // RS1 register address in ID/EX stage
    input  wire [4:0]  i_id_ex_rs2,          // RS2 register address in ID/EX stage
    input  wire        i_id_ex_rs1_used,     // High if instruction actively uses RS1
    input  wire        i_id_ex_rs2_used,     // High if instruction actively uses RS2
    input  wire        i_id_ex_valid,        // Valid bit of instruction in ID/EX

    // =========================================================================
    // 2. STAGE 3 (EX/MEM) FORWARDING CANDIDATE (Instruction N-1)
    // =========================================================================
    input  wire [4:0]  i_ex_mem_rd,          // RD destination register in EX/MEM
    input  wire        i_ex_mem_reg_write,   // Register write enable in EX/MEM
    input  wire        i_ex_mem_mem_read,    // High if instruction in EX/MEM is Load (LW/LH/LB)
    input  wire        i_ex_mem_valid,       // Valid bit in EX/MEM

    // =========================================================================
    // 3. FORWARDING CONTROL MULTIPLEXER SELECTORS
    // =========================================================================
    // 2'b00: FWD_NONE   - Use Register File asynchronous read data
    // 2'b10: FWD_EX_MEM - Forward from Stage 3 (Inst N-1 complete Write-Back data w_wb_data)
    output reg  [1:0]  o_forward_a,          // Forwarding selector for ALU Operand A
    output reg  [1:0]  o_forward_b,          // Forwarding selector for ALU Operand B
    output reg  [1:0]  o_forward_store,      // Forwarding selector for Store Data (SW/SH/SB)

    // =========================================================================
    // 4. LOAD-TO-USE INTERLOCK HAZARD DETECTION
    // =========================================================================
    output wire        o_stall_load_use      // 1-cycle stall required for Load-to-Use
);

    // =========================================================================
    // FORWARDING SELECTOR ENCODINGS
    // =========================================================================
    localparam [1:0] FWD_NONE   = 2'b00;
    localparam [1:0] FWD_EX_MEM = 2'b10;

    // =========================================================================
    // OPERAND A FORWARDING LOGIC (From Stage 3 to Stage 2)
    // =========================================================================
    always @(*) begin
        if (i_ex_mem_valid && i_ex_mem_reg_write && 
            (i_ex_mem_rd != 5'd0) && (i_ex_mem_rd == i_id_ex_rs1)) begin
            o_forward_a = FWD_EX_MEM;
        end else begin
            o_forward_a = FWD_NONE;
        end
    end

    // =========================================================================
    // OPERAND B FORWARDING LOGIC (From Stage 3 to Stage 2 ALU Operand B)
    // =========================================================================
    always @(*) begin
        if (i_ex_mem_valid && i_ex_mem_reg_write && 
            (i_ex_mem_rd != 5'd0) && (i_ex_mem_rd == i_id_ex_rs2)) begin
            o_forward_b = FWD_EX_MEM;
        end else begin
            o_forward_b = FWD_NONE;
        end
    end

    // =========================================================================
    // STORE DATA FORWARDING LOGIC (From Stage 3 to Stage 2 Store Data RS2)
    // =========================================================================
    always @(*) begin
        if (i_ex_mem_valid && i_ex_mem_reg_write && 
            (i_ex_mem_rd != 5'd0) && (i_ex_mem_rd == i_id_ex_rs2)) begin
            o_forward_store = FWD_EX_MEM;
        end else begin
            o_forward_store = FWD_NONE;
        end
    end

    // =========================================================================
    // LOAD-TO-USE HAZARD DETECTION
    // =========================================================================
    // Condition:
    // 1. Instruction currently in EX/MEM is a Load instruction (mem_read == 1).
    // 2. Its destination rd is not x0.
    // 3. Instruction currently in ID/EX is valid and actively reads rs1 or rs2 matching rd.
    wire w_rs1_conflict = i_id_ex_rs1_used && (i_id_ex_rs1 == i_ex_mem_rd);
    wire w_rs2_conflict = i_id_ex_rs2_used && (i_id_ex_rs2 == i_ex_mem_rd);

    assign o_stall_load_use = i_ex_mem_valid && i_ex_mem_mem_read && 
                              (i_ex_mem_rd != 5'd0) && i_id_ex_valid && 
                              (w_rs1_conflict | w_rs2_conflict);

endmodule
