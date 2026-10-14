`timescale 1ns / 1ps
// ==============================================================================
// MODULE: hazard_unit
// DESCRIPTION: 3-Stage Pipeline Hazard, Stall & Interlock Controller
// ARCHITECTURE: RISC-V 32-bit IoT & AI Accelerator Core (Phase 3)
// ==============================================================================

module hazard_unit (
    input  wire i_clk,
    input  wire i_rst_n,

    // ==========================================
    // 1. HAZARD INPUTS FROM STAGE 2 (ID/EX)
    // ==========================================
    input  wire i_branch_mispredict,    // Branch misprediction detected in ID/EX
    input  wire i_jalr_en,              // JALR jump redirect in ID/EX
    input  wire i_stall_load_use,       // Load-to-Use hazard flag from forwarding_unit
    input  wire i_mul_busy,             // 8-Cycle Multiplier busy computing

    // ==========================================
    // 2. MEMORY / BUS STATUS FROM STAGE 3 (MEM/WB)
    // ==========================================
    input  wire i_ex_mem_valid,         // Instruction in EX/MEM is valid
    input  wire i_ex_mem_mem_read,      // Reading data memory / MMIO
    input  wire i_ex_mem_mem_write,     // Writing data memory / MMIO
    input  wire i_dmem_ready,           // SRAM Port 0 or APB Bridge ready response

    // ==========================================
    // 3. PRIVILEGED CSR & TRAP REQUESTS
    // ==========================================
    input  wire i_exc_req,              // Synchronous exception request
    input  wire i_int_req,              // Asynchronous interrupt request
    input  wire i_mret,                 // Machine-mode return (MRET) from EX/MEM

    // ==========================================
    // 4. PIPELINE STALL & FLUSH OUTPUTS
    // ==========================================
    output wire o_trap_taken,           // Trap granted to CSR unit
    
    // Stage 1 (IF) Control
    output wire o_stall_pc,             // Freeze Program Counter
    
    // Stage 1 -> Stage 2 Register (pipe_reg_if_id) Control
    output wire o_stall_if_id,          // Freeze pipe_reg_if_id
    output wire o_flush_if_id,          // Flush pipe_reg_if_id (Inject NOP)
    
    // Stage 2 (ID/EX) Control
    output wire o_flush_id_ex,          // Flush Stage 2 combinational outputs
    
    // Stage 2 -> Stage 3 Register (pipe_reg_ex_mem) Control
    output wire o_stall_ex_mem,         // Freeze pipe_reg_ex_mem
    output wire o_flush_ex_mem,         // Flush pipe_reg_ex_mem (Inject NOP)
    
    // Stage 3 (MEM/WB) Gating
    output wire o_mem_en,               // Enable SRAM Port 0 / APB access
    output wire o_wb_en                 // Enable Register File write-back
);

    // =========================================================================
    // 1. MEMORY BUSY DETECTION (Multi-cycle APB MMIO Wait)
    // =========================================================================
    // Internal SRAM is single-cycle (i_dmem_ready = 1).
    // External APB access may take 2+ cycles (i_dmem_ready = 0 during wait).
    wire w_mem_busy = (i_ex_mem_mem_read | i_ex_mem_mem_write) & i_ex_mem_valid & (~i_dmem_ready);

    // =========================================================================
    // 2. TRAP & EXCEPTION GRANT LOGIC
    // =========================================================================
    // Exceptions take immediate precedence.
    // Interrupts are deferred until memory access completes to preserve memory integrity.
    assign o_trap_taken = i_exc_req | (i_int_req & ~w_mem_busy);

    // =========================================================================
    // 3. CONTROL FLOW REDIRECTION
    // =========================================================================
    wire w_redirect_id_ex = i_branch_mispredict | i_jalr_en;
    wire w_mret_active    = i_mret & i_ex_mem_valid;

    // =========================================================================
    // 4. STALL LOGIC (FREEZING STAGES)
    // =========================================================================
    // Freeze PC & Stage 1/Stage 2 when memory is busy, Load-to-Use hazard, OR Multiplier is computing
    assign o_stall_pc     = w_mem_busy | i_stall_load_use | i_mul_busy;
    assign o_stall_if_id  = w_mem_busy | i_stall_load_use | i_mul_busy;

    // Freeze EX/MEM register ONLY when memory is busy
    assign o_stall_ex_mem = w_mem_busy;

    // =========================================================================
    // 5. FLUSH LOGIC (INJECTING NOPS / BUBBLES)
    // =========================================================================
    // 2-Cycle Redirect Flush: Register redirect event for 2nd cycle pipe_reg_if_id flush
    reg r_redirect_pipe_flush;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_redirect_pipe_flush <= 1'b0;
        end else if (!o_stall_if_id) begin
            r_redirect_pipe_flush <= w_redirect_id_ex;
        end
    end

    // IF/ID register flush: on Branch Mispredict (2 cycles), JALR (2 cycles), MRET or Trap
    assign o_flush_if_id  = w_redirect_id_ex | r_redirect_pipe_flush | w_mret_active | o_trap_taken;

    // EX/MEM register flush: on Load-to-Use hazard, Multiplier computing (bubble insertion) or Trap
    assign o_flush_ex_mem = ((i_stall_load_use | i_mul_busy) & ~w_mem_busy) | o_trap_taken;

    assign o_flush_id_ex = o_trap_taken | w_mret_active;

    // =========================================================================
    // 6. PHASE GATING (PROTECTING MEMORY & REGISTER FILE)
    // =========================================================================
    assign o_mem_en = ~i_exc_req;
    assign o_wb_en  = (~w_mem_busy) & (~i_exc_req);

endmodule