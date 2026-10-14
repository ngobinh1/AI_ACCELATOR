`timescale 1ns / 1ps
// ==============================================================================
// MODULE: stage_mem_wb
// DESCRIPTION: Stage 3: Data Memory Access, Alignment & Final Write-Back
// ARCHITECTURE: RISC-V 32-bit IoT & AI Accelerator Core (Phase 3)
// ==============================================================================

module stage_mem_wb #(
    parameter DATA_WIDTH     = 32,
    parameter ADDR_WIDTH     = 32,
    parameter REG_ADDR_WIDTH = 5
)(
    // ==========================================
    // 1. INPUTS FROM STAGE 2 (pipe_reg_ex_mem)
    // ==========================================
    input  wire                      i_valid,
    input  wire [ADDR_WIDTH-1:0]     i_pc,
    input  wire [ADDR_WIDTH-1:0]     i_pc_plus_4,
    input  wire [DATA_WIDTH-1:0]     i_ex_result,    // Memory address or ALU/MUL/SIMD result
    input  wire [DATA_WIDTH-1:0]     i_store_data,   // Forwarded store data from RS2
    input  wire [REG_ADDR_WIDTH-1:0] i_rd_addr,
    input  wire                      i_reg_write,
    input  wire [1:0]                i_result_src,   // 00: EX_Res, 01: Mem, 10: PC+4, 11: CSR
    
    input  wire                      i_mem_read,
    input  wire                      i_mem_write,
    input  wire [1:0]                i_mem_size,     // 00: Byte, 01: Halfword, 10: Word
    input  wire                      i_mem_uns,      // 1: Unsigned, 0: Signed
    input  wire [DATA_WIDTH-1:0]     i_csr_data,

    // ==========================================
    // 2. GATING SIGNALS FROM HAZARD UNIT
    // ==========================================
    input  wire                      i_mem_en,       // Memory phase enable
    input  wire                      i_wb_en,        // Write-back enable

    // ==========================================
    // 3. EXTERNAL DATA MEMORY / APB BUS INTERFACE
    // ==========================================
    input  wire [DATA_WIDTH-1:0]     i_dmem_rdata,   // Raw data from SRAM Port 0 or APB

    output wire [ADDR_WIDTH-1:0]     o_dmem_addr,    // Memory address
    output wire [DATA_WIDTH-1:0]     o_dmem_wdata,   // Byte-aligned store data
    output wire [3:0]                o_dmem_we,      // Byte write enable mask
    output wire                      o_is_device_bus,// High if MMIO space (0x4000_0000 - 0x40FF_FFFF)

    // ==========================================
    // 4. WRITE-BACK OUTPUTS (To Register File & Forwarding Unit)
    // ==========================================
    output wire                      o_wb_we,        // Final validated write enable
    output wire [REG_ADDR_WIDTH-1:0] o_wb_rd_addr,   // Final destination register
    output reg  [DATA_WIDTH-1:0]     o_wb_data       // Final multiplexed write-back data
);

    // =========================================================================
    // 1. MEMORY ADDRESS & MMIO DETECTION
    // =========================================================================
    assign o_dmem_addr     = i_ex_result;
    assign o_is_device_bus = (i_ex_result[31:24] == 8'h40);

    // =========================================================================
    // 2. STORE ALIGNMENT & BYTE ENABLE MASK GENERATION
    // =========================================================================
    wire [3:0] w_raw_we_mask;

    be_gen u_be_gen (
        .i_mem_size (i_mem_size),
        .i_addr_lsb (i_ex_result[1:0]),
        .o_we_mask  (w_raw_we_mask)
    );

    // Gate memory write enable with valid and hazard enable
    assign o_dmem_we = (i_mem_write & i_valid & i_mem_en) ? w_raw_we_mask : 4'b0000;

    st_align u_st_align (
        .i_mem_size  (i_mem_size),
        .i_addr_lsb  (i_ex_result[1:0]),
        .i_rs2_data  (i_store_data),
        .o_mem_wdata (o_dmem_wdata)
    );

    // =========================================================================
    // 3. LOAD ALIGNMENT & SIGN EXTENSION
    // =========================================================================
    wire [DATA_WIDTH-1:0] w_formatted_rdata;

    load_align u_load_align (
        .i_mem_rdata      (i_dmem_rdata),
        .i_addr_lsb       (i_ex_result[1:0]),
        .i_mem_size       (i_mem_size),
        .i_mem_uns        (i_mem_uns),
        .o_formatted_data (w_formatted_rdata)
    );

    // =========================================================================
    // 4. FINAL WRITE-BACK MULTIPLEXER
    // =========================================================================
    always @(*) begin
        case (i_result_src)
            2'b00:   o_wb_data = i_ex_result;       // ALU, Multiplier, SIMD MAC
            2'b01:   o_wb_data = w_formatted_rdata; // Formatted Memory Load Data
            2'b10:   o_wb_data = i_pc_plus_4;       // PC+4 Link Address (JAL/JALR)
            2'b11:   o_wb_data = i_csr_data;        // CSR Read Data
            default: o_wb_data = i_ex_result;
        endcase
    end

    // Gated register write enable to protect Register File
    assign o_wb_we      = i_reg_write & i_valid & i_wb_en;
    assign o_wb_rd_addr = i_rd_addr;

endmodule
