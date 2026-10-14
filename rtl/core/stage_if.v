`timescale 1ns / 1ps
// ==============================================================================
// MODULE: stage_if
// DESCRIPTION: Pure Instruction Fetch Stage with Early JAL & RV32C Decompressor
// SPECIFICATION: RV32I / RV32C (16-bit Compressed Instructions) + BTFN Predictor
// ARCHITECTURE: RISC-V 32-bit IoT & AI Accelerator Core (Phase 4)
// ==============================================================================

module stage_if #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 32
)(
    input  wire                  i_clk,
    input  wire                  i_rst_n,
    
    // ==========================================
    // 1. PIPELINE CONTROL
    // ==========================================
    input  wire                  i_stall,           // Freeze PC and valid bit
    input  wire                  i_flush,           // Clear valid bit
    
    // ==========================================
    // 2. CONTROL FLOW TARGETS (From ID/EX & CSR)
    // ==========================================
    input  wire                  i_csr_pc_sel,      // Priority 1: Trap / Exception / Interrupt
    input  wire [ADDR_WIDTH-1:0] i_csr_pc,
    input  wire                  i_jalr_en,         // Priority 2: JALR target
    input  wire [ADDR_WIDTH-1:0] i_jalr_target,
    input  wire                  i_branch_mispredict, // Priority 3: Branch mispredict recovery
    input  wire [ADDR_WIDTH-1:0] i_branch_recovery_target,
    
    // ==========================================
    // 3. SYNCHRONOUS IMEM (SRAM PORT 1) INTERFACE
    // ==========================================
    output wire [ADDR_WIDTH-1:0] o_imem_addr,
    output wire                  o_imem_cen,        // Active-low chip enable
    input  wire [DATA_WIDTH-1:0] i_instr,           // Raw instruction from SRAM
    
    // ==========================================
    // 4. OUTPUTS TO PIPELINE REGISTER (pipe_reg_if_id)
    // ==========================================
    output wire [ADDR_WIDTH-1:0] o_pc,
    output wire [ADDR_WIDTH-1:0] o_pc_plus_4,       // Sequential PC (PC+2 for RVC, PC+4 for RV32I)
    output wire [DATA_WIDTH-1:0] o_instr,          // Standard 32-bit RV32I instruction
    output wire                  o_pred_taken,      // Branch predicted taken flag
    output wire                  o_valid            // Valid instruction flag
);
    `include "riscv_core_defines.vh"

    // =========================================================================
    // 1. REDIRECT REGISTER FROM STAGE 2 (BRMP PIPELINING)
    // =========================================================================
    reg                   r_redirect_valid;
    reg [ADDR_WIDTH-1:0]  r_redirect_target;

    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_redirect_valid  <= 1'b0;
            r_redirect_target <= {ADDR_WIDTH{1'b0}};
        end else if (!i_stall) begin
            r_redirect_valid  <= i_branch_mispredict | i_jalr_en;
            r_redirect_target <= i_branch_mispredict ? i_branch_recovery_target : {i_jalr_target[ADDR_WIDTH-1:1], 1'b0};
        end
    end

    // High-priority redirect (traps, registered BRMP/JALR from ID/EX)
    wire                  w_squash_curr = i_csr_pc_sel | r_redirect_valid;

    // Early redirect from IF (early JAL and static branch prediction BTFN)
    wire                  w_if_redirect;
    wire [ADDR_WIDTH-1:0] w_if_target;

    wire                  w_redirect = w_squash_curr | w_if_redirect;
    wire [ADDR_WIDTH-1:0] w_redirect_target = i_csr_pc_sel    ? i_csr_pc :
                                             r_redirect_valid ? r_redirect_target :
                                                                w_if_target;

    // =========================================================================
    // 2. PREFETCH FIFO & ADDRESS REGISTERS
    // =========================================================================
    reg [31:0]            r_fifo_data [1:0];
    reg [1:0]             r_fifo_valid;
    reg [ADDR_WIDTH-1:0]  r_pc;
    reg [ADDR_WIDTH-1:0]  r_fetch_addr;
    reg                   r_in_flight;

    // SRAM incoming data
    wire                  w_in_valid = r_in_flight & (~w_squash_curr);
    wire [31:0]           w_in_rdata = i_instr;

    // Head word (word containing current instruction at r_pc)
    wire [31:0]           w_head_word  = r_fifo_valid[0] ? r_fifo_data[0] : w_in_rdata;
    wire                  w_head_valid = r_fifo_valid[0] | w_in_valid;

    // Second word (word following head word, needed if r_pc is unaligned and inst is 32-bit)
    wire [31:0]           w_second_word  = r_fifo_valid[1] ? r_fifo_data[1] : w_in_rdata;
    wire                  w_second_valid = r_fifo_valid[1] | (r_fifo_valid[0] & w_in_valid);

    // =========================================================================
    // 3. INSTRUCTION ALIGNER & ZERO-CYCLE RVC DECOMPRESSOR
    // =========================================================================
    wire                  w_unaligned = r_pc[1];
    wire [15:0]           w_hw0 = w_unaligned ? w_head_word[31:16] : w_head_word[15:0];
    wire                  w_is_rvc = (w_hw0[1:0] != 2'b11);

    // Validity check
    wire                  w_instr_data_valid = w_unaligned ? (w_is_rvc ? w_head_valid : w_second_valid)
                                                           : w_head_valid;

    // Uncompressed 32-bit form
    wire [31:0]           w_raw_instr = w_unaligned ? {w_second_word[15:0], w_hw0} : w_head_word;

    // RVC Decompressor
    wire [31:0]           w_decomp_instr;
    wire                  w_illegal_rvc;

    rvc_decompressor u_rvc_dec (
        .i_c_instr      (w_hw0),
        .o_decomp_instr (w_decomp_instr),
        .o_illegal_instr(w_illegal_rvc)
    );

    wire [31:0]           w_final_instr = w_is_rvc ? w_decomp_instr : w_raw_instr;
    wire [ADDR_WIDTH-1:0] w_pc_plus_seq = r_pc + (w_is_rvc ? 32'd2 : 32'd4);

    // =========================================================================
    // 4. EARLY JUMP & STATIC BRANCH PREDICTION (BTFN)
    // =========================================================================
    wire [31:0] w_imm_j = {{12{w_final_instr[31]}}, w_final_instr[19:12], w_final_instr[20], w_final_instr[30:21], 1'b0};
    wire [31:0] w_imm_b = {{20{w_final_instr[31]}}, w_final_instr[7], w_final_instr[30:25], w_final_instr[11:8], 1'b0};

    wire w_is_jal    = w_instr_data_valid && (~w_squash_curr) && (w_final_instr[`OPCODE_FIELD] == OP_JAL);
    wire w_is_branch = w_instr_data_valid && (~w_squash_curr) && (w_final_instr[`OPCODE_FIELD] == OP_BRANCH);

    // BTFN: Backward Taken (imm[31]==1), Forward Not Taken (imm[31]==0)
    wire w_pred_taken = w_is_branch && (w_imm_b[31] == 1'b1);

    wire [ADDR_WIDTH-1:0] w_jal_target    = r_pc + w_imm_j;
    wire [ADDR_WIDTH-1:0] w_branch_target = r_pc + w_imm_b;

    // Instruction Fire condition (instruction is accepted to pipe_reg_if_id)
    wire w_instr_fire = w_instr_data_valid && (~i_stall) && (~i_flush) && (~w_squash_curr);

    // Early redirect from IF
    assign w_if_redirect = (w_is_jal | w_pred_taken) & w_instr_fire;
    assign w_if_target   = w_is_jal ? w_jal_target : w_branch_target;

    // FIFO Pop condition:
    // If aligned (r_pc[1]==0) and RVC: do not pop, upper halfword remains in head word!
    // Otherwise: pop head word!
    wire w_pop_fifo = w_instr_fire && (w_unaligned | (~w_is_rvc));

    // =========================================================================
    // 5. SRAM FETCH FLOW CONTROL
    // =========================================================================
    wire [1:0] w_fifo_count = (r_fifo_valid == 2'b11) ? 2'd2 :
                             (r_fifo_valid == 2'b01) ? 2'd1 : 2'd0;
    wire [1:0] w_next_count = w_fifo_count - (w_pop_fifo ? 2'd1 : 2'd0) + (w_in_valid ? 2'd1 : 2'd0);
    wire       w_fetch_req  = (w_next_count < 2'd2);

    assign o_imem_addr = (!i_rst_n)   ? RESET_VEC :
                         w_redirect   ? {w_redirect_target[ADDR_WIDTH-1:2], 2'b00} :
                                        r_fetch_addr;
    assign o_imem_cen  = (!i_rst_n)   ? 1'b0 :
                         w_redirect   ? 1'b0 :
                                        ~w_fetch_req;

    // =========================================================================
    // 6. SEQUENTIAL STATE UPDATES
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            r_fifo_valid    <= 2'b00;
            r_fifo_data[0]  <= 32'd0;
            r_fifo_data[1]  <= 32'd0;
            r_pc            <= RESET_VEC;
            r_fetch_addr    <= RESET_VEC + 32'd4;
            r_in_flight     <= 1'b1;
        end else if (w_redirect) begin
            // Flush FIFO on any redirect
            r_fifo_valid    <= 2'b00;
            r_pc            <= w_redirect_target;
            r_fetch_addr    <= {w_redirect_target[ADDR_WIDTH-1:2], 2'b00} + 32'd4;
            r_in_flight     <= 1'b1;
        end else begin
            // PC advancement
            if (w_instr_fire) begin
                r_pc <= w_pc_plus_seq;
            end

            // SRAM Fetch tracking
            if (w_fetch_req) begin
                r_fetch_addr <= r_fetch_addr + 32'd4;
                r_in_flight  <= 1'b1;
            end else begin
                r_in_flight  <= 1'b0;
            end

            // FIFO updates
            case (r_fifo_valid)
                2'b00: begin
                    if (w_in_valid && !w_pop_fifo) begin
                        r_fifo_data[0] <= w_in_rdata;
                        r_fifo_valid   <= 2'b01;
                    end
                end

                2'b01: begin
                    if (w_pop_fifo && w_in_valid) begin
                        r_fifo_data[0] <= w_in_rdata;
                        r_fifo_valid   <= 2'b01;
                    end else if (w_pop_fifo && !w_in_valid) begin
                        r_fifo_valid   <= 2'b00;
                    end else if (!w_pop_fifo && w_in_valid) begin
                        r_fifo_data[1] <= w_in_rdata;
                        r_fifo_valid   <= 2'b11;
                    end
                end

                2'b11: begin
                    if (w_pop_fifo && w_in_valid) begin
                        r_fifo_data[0] <= r_fifo_data[1];
                        r_fifo_data[1] <= w_in_rdata;
                        r_fifo_valid   <= 2'b11;
                    end else if (w_pop_fifo && !w_in_valid) begin
                        r_fifo_data[0] <= r_fifo_data[1];
                        r_fifo_valid   <= 2'b01;
                    end
                end

                default: begin
                    r_fifo_valid <= 2'b00;
                end
            endcase
        end
    end

    // =========================================================================
    // 7. OUTPUTS TO PIPELINE REGISTER (pipe_reg_if_id)
    // =========================================================================
    assign o_pc         = r_pc;
    assign o_pc_plus_4  = w_pc_plus_seq;
    assign o_instr      = w_final_instr;
    assign o_pred_taken = w_pred_taken;
    assign o_valid      = w_instr_data_valid & (~w_squash_curr) & (~i_flush);

endmodule