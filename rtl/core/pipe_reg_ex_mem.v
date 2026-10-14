`timescale 1ns / 1ps
// ==============================================================================
// MODULE: pipe_reg_ex_mem
// DESCRIPTION: Pipeline Register separating Stage 2 (ID/EX) and Stage 3 (MEM/WB)
// ARCHITECTURE: RISC-V 32-bit IoT & AI Accelerator Core (Phase 3)
// ==============================================================================

module pipe_reg_ex_mem #(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 32,
    parameter REG_ADDR_WIDTH = 5
)(
    input  wire                      i_clk,
    input  wire                      i_rst_n,

    // ==========================================
    // PIPELINE FLOW CONTROL
    // ==========================================
    input  wire                      i_stall,        // Freeze register contents
    input  wire                      i_flush,        // Clear control signals (Inject NOP)

    // ==========================================
    // INSTRUCTION STATUS & PC INPUTS
    // ==========================================
    input  wire                      i_valid,
    input  wire [ADDR_WIDTH-1:0]     i_pc,
    input  wire [ADDR_WIDTH-1:0]     i_pc_plus_4,

    // ==========================================
    // EXECUTION RESULTS & MEMORY OPERANDS
    // ==========================================
    input  wire [DATA_WIDTH-1:0]     i_ex_result,    // ALU / Multiplier / SIMD MAC result
    input  wire [DATA_WIDTH-1:0]     i_store_data,   // Forwarded RS2 store data
    input  wire [DATA_WIDTH-1:0]     i_rs1_data,     // Forwarded RS1 data (used for CSR write)
    input  wire [REG_ADDR_WIDTH-1:0] i_rs1_addr,     // Source register rs1 (used for CSR zimm)
    input  wire [REG_ADDR_WIDTH-1:0] i_rd_addr,      // Destination register rd
    input  wire                      i_reg_write,    // Register write enable
    input  wire [1:0]                i_result_src,   // 00: EX_Res, 01: Mem, 10: PC+4, 11: CSR

    // ==========================================
    // MEMORY ACCESS CONTROLS
    // ==========================================
    input  wire                      i_mem_read,
    input  wire                      i_mem_write,
    input  wire [1:0]                i_mem_size,     // 00: Byte, 01: Halfword, 10: Word
    input  wire                      i_mem_uns,      // 1: Unsigned, 0: Signed

    // ==========================================
    // CSR & SYSTEM CONTROLS
    // ==========================================
    input  wire [11:0]               i_csr_addr,
    input  wire [2:0]                i_csr_op,
    input  wire                      i_csr_read,
    input  wire                      i_csr_write,
    input  wire                      i_is_ecall,
    input  wire                      i_is_ebreak,
    input  wire                      i_is_mret,
    input  wire                      i_sleep_req,
    input  wire                      i_illegal_instr,
    input  wire [DATA_WIDTH-1:0]     i_instr,

    // ==========================================
    // REGISTERED OUTPUTS (To Stage 3 MEM/WB)
    // ==========================================
    output reg                       o_valid,
    output reg  [ADDR_WIDTH-1:0]     o_pc,
    output reg  [ADDR_WIDTH-1:0]     o_pc_plus_4,

    output reg  [DATA_WIDTH-1:0]     o_ex_result,
    output reg  [DATA_WIDTH-1:0]     o_store_data,
    output reg  [DATA_WIDTH-1:0]     o_rs1_data,
    output reg  [REG_ADDR_WIDTH-1:0] o_rs1_addr,
    output reg  [REG_ADDR_WIDTH-1:0] o_rd_addr,
    output reg                       o_reg_write,
    output reg  [1:0]                o_result_src,

    output reg                       o_mem_read,
    output reg                       o_mem_write,
    output reg  [1:0]                o_mem_size,
    output reg                       o_mem_uns,

    output reg  [11:0]               o_csr_addr,
    output reg  [2:0]                o_csr_op,
    output reg                       o_csr_read,
    output reg                       o_csr_write,
    output reg                       o_is_ecall,
    output reg                       o_is_ebreak,
    output reg                       o_is_mret,
    output reg                       o_sleep_req,
    output reg                       o_illegal_instr,
    output reg  [DATA_WIDTH-1:0]     o_instr
);


    `include "riscv_core_defines.vh"

    // =========================================================================
    // SYNCHRONOUS REGISTER UPDATES
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_valid       <= 1'b0;
            o_pc          <= RESET_VEC;
            o_pc_plus_4   <= RESET_VEC;
            o_ex_result   <= {DATA_WIDTH{1'b0}};
            o_store_data  <= {DATA_WIDTH{1'b0}};
            o_rs1_data    <= {DATA_WIDTH{1'b0}};
            o_rs1_addr    <= {REG_ADDR_WIDTH{1'b0}};
            o_rd_addr     <= {REG_ADDR_WIDTH{1'b0}};
            o_reg_write   <= 1'b0;
            o_result_src  <= 2'b00;

            o_mem_read    <= 1'b0;
            o_mem_write   <= 1'b0;
            o_mem_size    <= 2'b00;
            o_mem_uns     <= 1'b0;

            o_csr_addr    <= 12'd0;
            o_csr_op      <= 3'b000;
            o_csr_read    <= 1'b0;
            o_csr_write   <= 1'b0;
            o_is_ecall      <= 1'b0;
            o_is_ebreak     <= 1'b0;
            o_is_mret       <= 1'b0;
            o_sleep_req     <= 1'b0;
            o_illegal_instr <= 1'b0;
            o_instr         <= INST_NOP;
        end else if (i_flush) begin
            // Clear valid and control flags on flush (Bubble injection)
            o_valid       <= 1'b0;
            o_pc          <= RESET_VEC;
            o_pc_plus_4   <= RESET_VEC;
            o_ex_result   <= {DATA_WIDTH{1'b0}};
            o_store_data  <= {DATA_WIDTH{1'b0}};
            o_rs1_data    <= {DATA_WIDTH{1'b0}};
            o_rs1_addr    <= {REG_ADDR_WIDTH{1'b0}};
            o_rd_addr     <= {REG_ADDR_WIDTH{1'b0}};
            o_reg_write   <= 1'b0;
            o_result_src  <= 2'b00;

            o_mem_read    <= 1'b0;
            o_mem_write   <= 1'b0;
            o_mem_size    <= 2'b00;
            o_mem_uns     <= 1'b0;

            o_csr_addr      <= 12'd0;
            o_csr_op        <= 3'b000;
            o_csr_read      <= 1'b0;
            o_csr_write     <= 1'b0;
            o_is_ecall      <= 1'b0;
            o_is_ebreak     <= 1'b0;
            o_is_mret       <= 1'b0;
            o_sleep_req     <= 1'b0;
            o_illegal_instr <= 1'b0;
            o_instr         <= INST_NOP;
        end else if (!i_stall) begin
            // Normal pipeline advance
            o_valid       <= i_valid;
            o_pc          <= i_pc;
            o_pc_plus_4   <= i_pc_plus_4;
            o_ex_result   <= i_ex_result;
            o_store_data  <= i_store_data;
            o_rs1_data    <= i_rs1_data;
            o_rs1_addr    <= i_rs1_addr;
            o_rd_addr     <= i_rd_addr;
            o_reg_write   <= i_reg_write;
            o_result_src  <= i_result_src;

            o_mem_read    <= i_mem_read;
            o_mem_write   <= i_mem_write;
            o_mem_size    <= i_mem_size;
            o_mem_uns     <= i_mem_uns;

            o_csr_addr      <= i_csr_addr;
            o_csr_op        <= i_csr_op;
            o_csr_read      <= i_csr_read;
            o_csr_write     <= i_csr_write;
            o_is_ecall      <= i_is_ecall;
            o_is_ebreak     <= i_is_ebreak;
            o_is_mret       <= i_is_mret;
            o_sleep_req     <= i_sleep_req;
            o_illegal_instr <= i_illegal_instr;
            o_instr         <= i_instr;
        end

    end

endmodule
