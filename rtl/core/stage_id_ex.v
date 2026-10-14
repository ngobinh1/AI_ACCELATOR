`timescale 1ns / 1ps
// ==============================================================================
// MODULE: stage_id_ex
// DESCRIPTION: Stage 2: Instruction Decode, Operand Fetch, Forwarding, ALU,
//              Multiplier, Packed SIMD MAC, and Branch Evaluation.
// ARCHITECTURE: RISC-V 32-bit IoT & AI Accelerator Core (Phase 3)
// ==============================================================================

module stage_id_ex #(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 32,
    parameter REG_ADDR_WIDTH = 5
)(
    input  wire                      i_clk,
    input  wire                      i_rst_n,
    input  wire                      i_stall,           // Freeze stage execution (suppress redirects)
    input  wire                      i_stall_load_use,  // Load-to-Use stall flag (gates multiplier start)
    input  wire                      i_flush,           // Pipeline flush signal

    // ==========================================
    // 1. INPUTS FROM STAGE 1 (pipe_reg_if_id)
    // ==========================================
    input  wire                      i_valid,           // Instruction valid from IF
    input  wire [ADDR_WIDTH-1:0]     i_pc,
    input  wire [ADDR_WIDTH-1:0]     i_pc_plus_4,
    input  wire [DATA_WIDTH-1:0]     i_instr,
    input  wire                      i_pred_taken,      // Branch predicted taken flag

    // ==========================================
    // 2. FORWARDING SELECTORS & FORWARDED DATA
    // ==========================================
    input  wire [1:0]                i_forward_a,       // 00: RF, 10: EX/MEM, 01: MEM/WB
    input  wire [1:0]                i_forward_b,       // 00: RF, 10: EX/MEM, 01: MEM/WB
    input  wire [1:0]                i_forward_store,   // Forwarding for Store data
    input  wire [DATA_WIDTH-1:0]     i_fwd_ex_mem_data, // From pipe_reg_ex_mem
    input  wire [DATA_WIDTH-1:0]     i_fwd_mem_wb_data, // From Stage 3 Write-Back MUX

    // ==========================================
    // 3. WRITE-BACK INTERFACE (From Stage 3 to Register File)
    // ==========================================
    input  wire                      i_wb_we,           // Register write enable
    input  wire [REG_ADDR_WIDTH-1:0] i_wb_rd_addr,      // Destination register rd
    input  wire [DATA_WIDTH-1:0]     i_wb_data,         // Write-back data

    // ==========================================
    // 4. OUTPUTS TO FORWARDING UNIT
    // ==========================================
    output wire [REG_ADDR_WIDTH-1:0] o_rs1_addr,
    output wire [REG_ADDR_WIDTH-1:0] o_rs2_addr,
    output wire                      o_rs1_used,
    output wire                      o_rs2_used,

    // ==========================================
    // 5. CONTROL FLOW REDIRECTS (To Stage 1 & Hazard Unit)
    // ==========================================
    output wire                      o_branch_taken,
    output wire                      o_branch_mispredict,
    output wire [ADDR_WIDTH-1:0]     o_branch_recovery_target,
    output wire                      o_jalr_en_out,
    output wire [ADDR_WIDTH-1:0]     o_jalr_target,

    // ==========================================
    // 6. OUTPUTS TO STAGE 3 (pipe_reg_ex_mem)
    // ==========================================
    output wire                      o_valid,
    output wire [ADDR_WIDTH-1:0]     o_pc,
    output wire [ADDR_WIDTH-1:0]     o_pc_plus_4,
    output wire [DATA_WIDTH-1:0]     o_ex_result,       // Multiplexed ALU / MUL / SIMD
    (* keep = "true" *) output wire [ADDR_WIDTH-1:0]     o_mem_addr,        // Dedicated Memory Address (directly from ALU for Data Memory)
    output wire [DATA_WIDTH-1:0]     o_store_data,      // Forwarded Store Data
    output wire [DATA_WIDTH-1:0]     o_rs1_data,        // Forwarded RS1 Data (for CSR write)
    output wire [REG_ADDR_WIDTH-1:0] o_rd_addr,
    output wire                      o_reg_write,
    output wire [1:0]                o_result_src,

    output wire                      o_mem_read,
    output wire                      o_mem_write,
    output wire [1:0]                o_mem_size,
    output wire                      o_mem_uns,

    output wire [11:0]               o_csr_addr,
    output wire [2:0]                o_csr_op,
    output wire                      o_csr_read,
    output wire                      o_csr_write,
    output wire                      o_is_ecall,
    output wire                      o_is_ebreak,
    output wire                      o_is_mret,
    output wire                      o_sleep_req,
    output wire                      o_illegal_instr,
    output wire [DATA_WIDTH-1:0]     o_instr,
    output wire                      o_mul_busy
);

    `include "riscv_core_defines.vh"

    // =========================================================================
    // 1. INSTRUCTION FIELD EXTRACTION
    // =========================================================================
    wire [4:0]  w_rs1_addr = i_instr[`RS1_FIELD];
    wire [4:0]  w_rs2_addr = i_instr[`RS2_FIELD];
    wire [4:0]  w_rd_addr  = i_instr[`RD_FIELD];

    assign o_rs1_addr = w_rs1_addr;
    assign o_rs2_addr = w_rs2_addr;
    assign o_rd_addr  = w_rd_addr;

    // =========================================================================
    // 2. INSTRUCTION DECODER
    // =========================================================================
    wire [3:0]  w_alu_ctrl;
    wire        w_alu_src;
    wire [1:0]  w_alu_src_a;
    wire        w_alu_enable;
    wire [2:0]  w_imm_src;

    wire        w_mul_valid;
    wire [1:0]  w_mul_type;
    wire        w_simd_valid;

    wire        w_mem_read, w_mem_write;
    wire [1:0]  w_mem_size;
    wire        w_mem_uns;

    wire        w_reg_write;
    wire [1:0]  w_result_src;

    wire        w_branch;
    wire [2:0]  w_branch_type;
    wire        w_jump;
    wire        w_jalr_en;

    wire        w_csr_read, w_csr_write;
    wire        w_is_ecall, w_is_ebreak, w_is_mret, w_sleep_req;
    wire        w_illegal_instr;
    wire        w_id_rs1_used, w_id_rs2_used;

    instruction_decoder u_decoder (
        .i_instr         (i_instr),
        
        .o_alu_ctrl      (w_alu_ctrl),
        .o_alu_src       (w_alu_src),
        .o_alu_src_a     (w_alu_src_a),
        .o_alu_enable    (w_alu_enable),
        .o_imm_src       (w_imm_src),
        
        .o_mul_valid     (w_mul_valid),
        .o_mul_type      (w_mul_type),
        .o_simd_valid    (w_simd_valid),
        
        .o_mem_read      (w_mem_read),
        .o_mem_write     (w_mem_write),
        .o_mem_size      (w_mem_size),
        .o_mem_uns       (w_mem_uns),
        
        .o_reg_write     (w_reg_write),
        .o_result_src    (w_result_src),
        
        .o_branch        (w_branch),
        .o_branch_type   (w_branch_type),
        .o_jump          (w_jump),
        .o_jalr_en       (w_jalr_en),
        
        .o_csr_read      (w_csr_read),
        .o_csr_write     (w_csr_write),
        .o_is_ecall      (w_is_ecall),
        .o_is_ebreak     (w_is_ebreak),
        .o_is_mret       (w_is_mret),
        .o_sleep_req     (w_sleep_req),
        .o_illegal_instr (w_illegal_instr),

        .o_rs1_used      (w_id_rs1_used),
        .o_rs2_used      (w_id_rs2_used)
    );


    // =========================================================================
    // 3. IMMEDIATE GENERATOR
    // =========================================================================
    wire [DATA_WIDTH-1:0] w_imm_ext;

    imm_gen u_imm_gen (
        .i_instr   (i_instr),
        .i_imm_src (w_imm_src),
        .o_imm_ext (w_imm_ext)
    );

    // =========================================================================
    // 4. REGISTER FILE (READ IN STAGE 2, SYNCHRONOUS WRITE FROM STAGE 3)
    // =========================================================================
    wire [DATA_WIDTH-1:0] w_rf_rs1_data;
    wire [DATA_WIDTH-1:0] w_rf_rs2_data;

    register_file #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (REG_ADDR_WIDTH)
    ) u_register_file (
        .i_clk      (i_clk),
        .i_we       (i_wb_we),
        .i_rs1_addr (w_rs1_addr),
        .i_rs2_addr (w_rs2_addr),
        .i_rd_addr  (i_wb_rd_addr),
        .i_wdata    (i_wb_data),
        .o_rs1_data (w_rf_rs1_data),
        .o_rs2_data (w_rf_rs2_data)
    );

    // =========================================================================
    // 5. DATA FORWARDING MULTIPLEXERS
    // =========================================================================
    reg [DATA_WIDTH-1:0] w_fwd_rs1_data;
    reg [DATA_WIDTH-1:0] w_fwd_rs2_data;
    reg [DATA_WIDTH-1:0] w_fwd_store_data;

    // Operand A Forwarding MUX
    always @(*) begin
        case (i_forward_a)
            2'b10:   w_fwd_rs1_data = i_fwd_ex_mem_data; // Forward from EX/MEM
            2'b01:   w_fwd_rs1_data = i_fwd_mem_wb_data; // Forward from MEM/WB
            default: w_fwd_rs1_data = w_rf_rs1_data;     // From Register File
        endcase
    end

    // Operand B Forwarding MUX (For ALU calculation)
    always @(*) begin
        case (i_forward_b)
            2'b10:   w_fwd_rs2_data = i_fwd_ex_mem_data; // Forward from EX/MEM
            2'b01:   w_fwd_rs2_data = i_fwd_mem_wb_data; // Forward from MEM/WB
            default: w_fwd_rs2_data = w_rf_rs2_data;     // From Register File
        endcase
    end

    // Store Data Forwarding MUX (For Memory Store Data RS2)
    always @(*) begin
        case (i_forward_store)
            2'b10:   w_fwd_store_data = i_fwd_ex_mem_data; // Forward from EX/MEM
            2'b01:   w_fwd_store_data = i_fwd_mem_wb_data; // Forward from MEM/WB
            default: w_fwd_store_data = w_rf_rs2_data;     // From Register File
        endcase
    end

    assign o_store_data = w_fwd_store_data;

    // =========================================================================
    // 6. ALU OPERAND ROUTING & POWER GATING
    // =========================================================================
    reg  [DATA_WIDTH-1:0] w_raw_src_a;
    reg  [DATA_WIDTH-1:0] w_raw_src_b;

    always @(*) begin
        case (w_alu_src_a)
            2'b00:   w_raw_src_a = w_fwd_rs1_data;
            2'b01:   w_raw_src_a = i_pc;
            2'b10:   w_raw_src_a = 32'd0; // LUI
            default: w_raw_src_a = w_fwd_rs1_data;
        endcase
    end

    always @(*) begin
        if (w_alu_src) w_raw_src_b = w_imm_ext;
        else           w_raw_src_b = w_fwd_rs2_data;
    end

    wire w_alu_active = w_alu_enable & i_valid;
    wire [DATA_WIDTH-1:0] w_gated_src_a = w_alu_active ? w_raw_src_a : 32'd0;
    wire [DATA_WIDTH-1:0] w_gated_src_b = w_alu_active ? w_raw_src_b : 32'd0;

    // =========================================================================
    // 7. ARITHMETIC & LOGIC UNIT (ALU)
    // =========================================================================
    wire [DATA_WIDTH-1:0] w_alu_result;
    wire                  w_zero, w_negative, w_carry, w_overflow;

    alu u_alu (
        .i_a        (w_gated_src_a),
        .i_b        (w_gated_src_b),
        .i_alu_ctrl (w_alu_ctrl),
        .o_result   (w_alu_result),
        .o_zero     (w_zero),
        .o_negative (w_negative),
        .o_carry    (w_carry),
        .o_overflow (w_overflow)
    );

    // =========================================================================
    // 8. HARDWARE MULTIPLIER (8-CYCLE SEQUENTIAL 32x32 -> 64-bit)
    // =========================================================================
    wire        w_mul_ready;
    wire        w_mul_busy;
    wire [63:0] w_mul_product;
    reg  [DATA_WIDTH-1:0] w_mul_result;

    wire        w_mul_start = w_mul_valid & i_valid & ~i_stall_load_use;

    booth_multiplier_32b u_multiplier (
        .i_clk          (i_clk),
        .i_rst_n        (i_rst_n),
        .i_mul_valid    (w_mul_start),
        .i_flush        (i_flush),
        .o_ready        (w_mul_ready),
        .o_busy         (w_mul_busy),
        .i_multiplicand (w_fwd_rs1_data),
        .i_multiplier   (w_fwd_rs2_data),
        .i_is_signed_a  (~w_mul_type[1]),
        .i_is_signed_b  (~w_mul_type[1] | (w_mul_type == 2'b10)),
        .o_product      (w_mul_product)
    );

    assign o_mul_busy = w_mul_valid & i_valid & ~w_mul_ready & ~i_stall_load_use;

    always @(*) begin
        case (w_mul_type)
            2'b00:   w_mul_result = w_mul_product[31:0];  // MUL
            default: w_mul_result = w_mul_product[63:32]; // MULH, MULHSU, MULHU
        endcase
    end

    // =========================================================================
    // 9. PACKED SIMD INT8 DOT-PRODUCT UNIT (smdot.i8)
    // =========================================================================
    wire [DATA_WIDTH-1:0] w_simd_result;

    simd_mac_unit u_simd_mac (
        .i_rs1         (w_fwd_rs1_data),
        .i_rs2         (w_fwd_rs2_data),
        .o_simd_result (w_simd_result)
    );

    // =========================================================================
    // 10. EX RESULT MULTIPLEXER (ALU / MUL / SIMD)
    // =========================================================================
    reg [DATA_WIDTH-1:0] w_ex_result;
    always @(*) begin
        if (w_simd_valid)     w_ex_result = w_simd_result;
        else if (w_mul_valid) w_ex_result = w_mul_result;
        else                  w_ex_result = w_alu_result;
    end

    assign o_ex_result = w_ex_result;
    assign o_mem_addr  = w_alu_result;

    // =========================================================================
    // 11. INSTRUCTION ACTIVE VALIDATION (FLUSH GATING)
    // =========================================================================
    wire w_inst_active = i_valid & (~i_flush);

    assign o_rs1_used  = w_id_rs1_used & w_inst_active;
    assign o_rs2_used  = w_id_rs2_used & w_inst_active;

    // =========================================================================
    // 12. BRANCH & JUMP EVALUATION
    // =========================================================================
    wire w_actual_branch_taken;

    branch_comparator u_branch_comp (
        .i_branch_en    (w_branch & w_inst_active),
        .i_branch_type  (w_branch_type),
        .i_zero         (w_zero),
        .i_negative     (w_negative),
        .i_carry        (w_carry),
        .i_overflow     (w_overflow),
        .o_branch_taken (w_actual_branch_taken)
    );

    assign o_branch_taken = w_actual_branch_taken;

    // Branch misprediction detection (suppressed when stalled)
    assign o_branch_mispredict = (w_branch & w_inst_active & ~i_stall) && (w_actual_branch_taken != i_pred_taken);

    // Recovery target: If predicted Taken but actual is Not Taken -> PC + 4
    //                  If predicted Not Taken but actual is Taken -> PC + imm
    assign o_branch_recovery_target = i_pred_taken ? i_pc_plus_4 : (i_pc + w_imm_ext);

    // JALR target: (rs1 + imm) & ~1 (suppressed when stalled)
    assign o_jalr_en_out = w_jalr_en & w_inst_active & ~i_stall;
    assign o_jalr_target = {w_alu_result[31:1], 1'b0};

    // =========================================
    // 13. OUTPUTS TO PIPELINE REGISTER (pipe_reg_ex_mem)
    // =========================================
    assign o_valid       = w_inst_active;
    assign o_pc          = i_pc;
    assign o_pc_plus_4   = i_pc_plus_4;
    assign o_reg_write   = w_reg_write & w_inst_active;
    assign o_result_src  = w_result_src;
    assign o_mem_read    = w_mem_read  & w_inst_active;
    assign o_mem_write   = w_mem_write & w_inst_active;
    assign o_mem_size    = w_mem_size;
    assign o_mem_uns     = w_mem_uns;

    assign o_rs1_data    = w_fwd_rs1_data;
    assign o_csr_addr    = i_instr[31:20];
    assign o_csr_op      = i_instr[14:12];
    assign o_csr_read    = w_csr_read  & w_inst_active;
    assign o_csr_write   = w_csr_write & w_inst_active;
    assign o_is_ecall       = w_is_ecall       & w_inst_active;
    assign o_is_ebreak      = w_is_ebreak      & w_inst_active;
    assign o_is_mret        = w_is_mret        & w_inst_active;
    assign o_sleep_req      = w_sleep_req      & w_inst_active;
    assign o_illegal_instr  = w_illegal_instr  & w_inst_active;
    assign o_instr          = i_instr;

endmodule

