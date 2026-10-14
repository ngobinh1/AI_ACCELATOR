`timescale 1ns / 1ps
// ==============================================================================
// TOP MODULE: riscv_core_top
// ARCHITECTURE: 3-Stage Decoupled Elastic Pipeline with Full Data Forwarding
//               (Stage 1: IF, Stage 2: ID/EX, Stage 3: MEM/WB)
// ISA: RV32I + RV32M + Zicsr + Packed SIMD 4x INT8 Dot-Product (smdot.i8)
// ==============================================================================

module riscv_core_top (
`ifdef USE_POWER_PINS
    inout  wire        vccd1,
    inout  wire        vssd1,
`endif
    input  wire        i_clk,
    input  wire        i_rst_n,

    // ==========================================
    // EXTERNAL INTERRUPTS
    // ==========================================
    input  wire        i_ext_irq,
    input  wire        i_timer_irq,

    // ==========================================
    // APB MASTER INTERFACE
    // ==========================================
    output wire [31:0] o_apb_paddr,
    output wire        o_apb_pwrite,
    output wire [3:0]  o_apb_pstrb,    
    output wire        o_apb_psel,
    output wire        o_apb_penable,
    output wire [31:0] o_apb_pwdata,
    
    input  wire [31:0] i_apb_prdata,   
    input  wire        i_apb_pready,
    input  wire        i_apb_pslverr
);
    `include "riscv_core_defines.vh"

    // =========================================================================
    // WIRE DECLARATIONS
    // =========================================================================

    // 1. STAGE 1 (IF) SIGNALS
    wire [31:0] w_if_pc, w_if_pc_plus_4;
    wire [31:0] w_if_instr;
    wire        w_if_pred_taken;
    wire        w_if_valid;

    // 1.1. PIPE_REG_IF_ID -> STAGE 2 (ID/EX) SIGNALS
    wire [31:0] w_id_pc, w_id_pc_plus_4;
    wire [31:0] w_id_instr;
    wire        w_id_pred_taken;
    wire        w_id_valid;

    // 2. FORWARDING UNIT SIGNALS
    wire [4:0]  w_id_fwd_rs1, w_id_fwd_rs2;
    wire [1:0]  w_fwd_a;
    wire [1:0]  w_fwd_b;
    wire [1:0]  w_fwd_store;
    wire        w_stall_load_use;

    // 3. STAGE 2 (ID/EX) SIGNALS -> PIPE_REG_EX_MEM
    wire [4:0]  w_id_rs1_addr, w_id_rs2_addr;
    wire        w_id_rs1_used, w_id_rs2_used;

    wire        w_id_ex_branch_taken;
    wire        w_id_ex_branch_mispredict;
    wire [31:0] w_id_ex_branch_recovery_tgt;
    wire        w_id_ex_jalr_en;
    wire [31:0] w_id_ex_jalr_tgt;

    wire        w_id_ex_valid;
    wire [31:0] w_id_ex_pc, w_id_ex_pc_plus_4;
    wire [31:0] w_id_ex_result;
    (* keep = "true" *) wire [31:0] w_id_ex_mem_addr;
    wire [31:0] w_id_ex_store_data;
    wire [4:0]  w_id_ex_rd_addr;
    wire        w_id_ex_reg_write;
    wire [1:0]  w_id_ex_result_src;
    wire        w_id_ex_mem_read, w_id_ex_mem_write;
    wire [1:0]  w_id_ex_mem_size;
    wire        w_id_ex_mem_uns;

    wire [31:0] w_id_ex_rs1_data;
    wire [11:0] w_id_ex_csr_addr;
    wire [2:0]  w_id_ex_csr_op;
    wire        w_id_ex_csr_read, w_id_ex_csr_write;
    wire        w_id_ex_is_ecall, w_id_ex_is_ebreak, w_id_ex_is_mret, w_id_ex_sleep_req;
    wire        w_id_ex_illegal_instr;
    wire [31:0] w_id_ex_instr;
    wire        w_id_mul_busy;

    // 4. PIPE_REG_EX_MEM -> STAGE 3 (MEM/WB)
    wire        w_ex_mem_valid;
    wire [31:0] w_ex_mem_pc, w_ex_mem_pc_plus_4;
    wire [31:0] w_ex_mem_result;
    wire [31:0] w_ex_mem_store_data;
    wire [4:0]  w_ex_mem_rs1_addr;
    wire [4:0]  w_ex_mem_rd_addr;
    wire        w_ex_mem_reg_write;
    wire [1:0]  w_ex_mem_result_src;
    wire        w_ex_mem_mem_read, w_ex_mem_mem_write;
    wire [1:0]  w_ex_mem_size;
    wire        w_ex_mem_uns;

    wire [31:0] w_ex_mem_rs1_data;
    wire [11:0] w_ex_mem_csr_addr;
    wire [2:0]  w_ex_mem_csr_op;
    wire        w_ex_mem_csr_read, w_ex_mem_csr_write;
    wire        w_ex_mem_is_ecall, w_ex_mem_is_ebreak, w_ex_mem_is_mret, w_ex_mem_sleep_req;
    wire        w_ex_mem_illegal_instr;
    wire [31:0] w_ex_mem_instr;

    // 5. STAGE 3 (MEM/WB) -> REGISTER FILE & FORWARDING UNIT
    wire        w_wb_we;
    wire [4:0]  w_wb_rd_addr;
    wire [31:0] w_wb_data;

    // 6. MEMORY INTERFACE (SRAM PORT 0 & APB)
    wire [31:0] w_dmem_addr;
    wire [31:0] w_dmem_wdata;
    wire [3:0]  w_dmem_we;
    wire        w_ex_is_device;

    wire [31:0] w_sram_dmem_rdata;
    wire [31:0] w_apb_rdata;
    wire        w_apb_ready;
    wire        w_apb_bus_error;
    wire        w_sram_oob_error = ~w_ex_is_device & (w_dmem_addr[31:11] != 21'd0) & (w_ex_mem_mem_read | w_ex_mem_mem_write) & w_ex_mem_valid;
    wire        w_mem_bus_error  = w_apb_bus_error | w_sram_oob_error;

    wire [31:0] w_dmem_rdata_mux = w_ex_is_device ? w_apb_rdata : w_sram_dmem_rdata;
    wire        w_dmem_ready_mux = w_ex_is_device ? w_apb_ready : 1'b1;

    // 6.1. EXTERNAL INTERRUPT SYNCHRONIZATION
    wire        w_ext_irq_sync;
    wire        w_timer_irq_sync;


    // 7. SRAM PORT 1 (INSTRUCTION FETCH)
    wire [31:0] w_imem_addr;
    wire        w_imem_cen;
    wire [31:0] w_imem_rdata;

    // 8. HAZARD UNIT CONTROL
    wire        w_hz_trap_taken;
    wire        w_hz_stall_pc;
    wire        w_hz_stall_if_id, w_hz_flush_if_id;
    wire        w_hz_flush_id_ex;
    wire        w_hz_stall_ex_mem, w_hz_flush_ex_mem;
    wire        w_hz_mem_en, w_hz_wb_en;

    // Simulation & Testbench Backward Compatibility Aliases
    wire        w_hz_stall_pipe        = w_hz_stall_pc;
    wire        w_ex_branch_taken      = w_id_ex_branch_taken;
    wire        w_ex_branch_mispredict = w_id_ex_branch_mispredict;

    // 9. CSR UNIT
    wire        w_csr_exc_req, w_csr_int_req;
    wire [31:0] w_csr_data, w_csr_pc;
    wire        w_csr_pc_sel;

    // =========================================================================
    // SRAM PORT 0 ACCESS (INITIATED FROM STAGE 2 ID/EX FOR 1-CYCLE SYNCHRONOUS SRAM)
    // =========================================================================
    wire        w_id_is_device     = (w_id_ex_mem_addr[31:24] == 8'h40);
    wire        w_id_sram_in_range = (w_id_ex_mem_addr[31:11] == 21'd0);
    wire        w_id_sram_req      = (w_id_ex_mem_read | w_id_ex_mem_write) & ~w_id_is_device & w_id_sram_in_range & w_id_ex_valid & ~w_hz_stall_pc;

    wire [3:0]  w_id_raw_we_mask;
    be_gen u_id_be_gen (
        .i_mem_size (w_id_ex_mem_size),
        .i_addr_lsb (w_id_ex_mem_addr[1:0]),
        .o_we_mask  (w_id_raw_we_mask)
    );

    wire [31:0] w_id_sram_wdata;
    st_align u_id_st_align (
        .i_mem_size  (w_id_ex_mem_size),
        .i_addr_lsb  (w_id_ex_mem_addr[1:0]),
        .i_rs2_data  (w_id_ex_store_data),
        .o_mem_wdata (w_id_sram_wdata)
    );

    wire        w_sram_csb0   = ~w_id_sram_req;
    wire        w_sram_web0   = ~(w_id_ex_mem_write & w_id_sram_req);
    wire [3:0]  w_sram_wmask0 = (w_id_ex_mem_write & w_id_sram_req) ? w_id_raw_we_mask : 4'b0000;
    (* keep = "true" *) wire [8:0]  w_sram_addr0  = w_id_ex_mem_addr[10:2];
    wire [31:0] w_sram_din0   = w_id_sram_wdata;

    // =========================================================================
    // 1. INTERNAL SRAM MACRO (2KB DUAL-PORT 1RW1R)
    // =========================================================================
    sky130_sram_2kbyte_1rw1r_32x512_8 u_sram_2kb (
`ifdef USE_POWER_PINS
        .vccd1  (vccd1),
        .vssd1  (vssd1),
`endif
        // Port 0: Data Memory (RW initiated from Stage 2, resolved in Stage 3)
        .clk0   (i_clk),
        .csb0   (w_sram_csb0),
        .web0   (w_sram_web0),
        .wmask0 (w_sram_wmask0),
        .addr0  (w_sram_addr0),
        .din0   (w_sram_din0),
        .dout0  (w_sram_dmem_rdata),
        
        // Port 1: Instruction Memory (RO from Stage 1)
        .clk1   (i_clk),
        .csb1   (w_imem_cen),
        .addr1  (w_imem_addr[10:2]),
        .dout1  (w_imem_rdata)
    );

    // =========================================================================
    // 2. APB BRIDGE (MEMORY-MAPPED I/O IN STAGE 3)
    // =========================================================================
    apb_bridge u_apb_bridge (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        
        .i_bus_read    (w_ex_mem_mem_read & w_ex_is_device & w_hz_mem_en),
        .i_bus_wstrb   (w_ex_is_device ? w_dmem_we : 4'b0000),
        .i_addr        (w_dmem_addr),
        .i_wdata       (w_dmem_wdata),
        
        .o_cpu_rdata   (w_apb_rdata),
        .o_dmem_ready  (w_apb_ready),
        .o_bus_error   (w_apb_bus_error),
        
        .o_apb_paddr   (o_apb_paddr),
        .o_apb_pwrite  (o_apb_pwrite),
        .o_apb_pstrb   (o_apb_pstrb),
        .o_apb_psel    (o_apb_psel),
        .o_apb_penable (o_apb_penable),
        .o_apb_pwdata  (o_apb_pwdata),
        .i_apb_prdata  (i_apb_prdata),
        .i_apb_pready  (i_apb_pready),
        .i_apb_pslverr (i_apb_pslverr)
    );

    // =========================================================================
    // 3. STAGE 1: INSTRUCTION FETCH (IF)
    // =========================================================================
    stage_if u_stage_if (
        .i_clk                     (i_clk),
        .i_rst_n                   (i_rst_n),
        
        .i_stall                   (w_hz_stall_pc),
        .i_flush                   (1'b0),
        
        .i_csr_pc_sel              (w_csr_pc_sel),
        .i_csr_pc                  (w_csr_pc),
        .i_jalr_en                 (w_id_ex_jalr_en),
        .i_jalr_target             (w_id_ex_jalr_tgt),
        .i_branch_mispredict       (w_id_ex_branch_mispredict),
        .i_branch_recovery_target  (w_id_ex_branch_recovery_tgt),
        
        .o_imem_addr               (w_imem_addr),
        .o_imem_cen                (w_imem_cen),
        .i_instr                   (w_imem_rdata),
        
        .o_pc                      (w_if_pc),
        .o_pc_plus_4               (w_if_pc_plus_4),
        .o_instr                   (w_if_instr),
        .o_pred_taken              (w_if_pred_taken),
        .o_valid                   (w_if_valid)
    );

    // =========================================================================
    // 3.1. PIPELINE REGISTER 1: IF / ID_EX (pipe_reg_if_id)
    // =========================================================================
    pipe_reg_if_id u_pipe_reg_if_id (
        .i_clk                     (i_clk),
        .i_rst_n                   (i_rst_n),
        
        .i_stall                   (w_hz_stall_if_id),
        .i_flush                   (w_hz_flush_if_id),
        
        .i_valid                   (w_if_valid),
        .i_pc                      (w_if_pc),
        .i_pc_plus_4               (w_if_pc_plus_4),
        .i_instr                   (w_if_instr),
        .i_pred_taken              (w_if_pred_taken),
        
        .o_valid                   (w_id_valid),
        .o_pc                      (w_id_pc),
        .o_pc_plus_4               (w_id_pc_plus_4),
        .o_instr                   (w_id_instr),
        .o_pred_taken              (w_id_pred_taken),
        .o_fwd_rs1                 (w_id_fwd_rs1),
        .o_fwd_rs2                 (w_id_fwd_rs2)
    );

    // =========================================================================
    // 4. DATA FORWARDING UNIT
    // =========================================================================
    forwarding_unit u_fwd (
        .i_id_ex_rs1        (w_id_fwd_rs1),
        .i_id_ex_rs2        (w_id_fwd_rs2),
        .i_id_ex_rs1_used   (w_id_rs1_used),
        .i_id_ex_rs2_used   (w_id_rs2_used),
        .i_id_ex_valid      (w_id_valid),
        
        .i_ex_mem_rd        (w_ex_mem_rd_addr),
        .i_ex_mem_reg_write (w_ex_mem_reg_write),
        .i_ex_mem_mem_read  (w_ex_mem_mem_read),
        .i_ex_mem_valid     (w_ex_mem_valid),
        
        .o_forward_a        (w_fwd_a),
        .o_forward_b        (w_fwd_b),
        .o_forward_store    (w_fwd_store),
        .o_stall_load_use   (w_stall_load_use)
    );

    // =========================================================================
    // 5. STAGE 2: INSTRUCTION DECODE & EXECUTE (ID/EX)
    // =========================================================================
    stage_id_ex u_stage_id_ex (
        .i_clk                     (i_clk),
        .i_rst_n                   (i_rst_n),
        .i_stall                   (w_hz_stall_pc),
        .i_stall_load_use          (w_stall_load_use),
        .i_flush                   (w_hz_flush_id_ex),
        
        .i_valid                   (w_id_valid),
        .i_pc                      (w_id_pc),
        .i_pc_plus_4               (w_id_pc_plus_4),
        .i_instr                   (w_id_instr),
        .i_pred_taken              (w_id_pred_taken),
        
        .i_forward_a               (w_fwd_a),
        .i_forward_b               (w_fwd_b),
        .i_forward_store           (w_fwd_store),
        .i_fwd_ex_mem_data         (w_wb_data),
        .i_fwd_mem_wb_data         (w_wb_data),
        
        .i_wb_we                   (w_wb_we),
        .i_wb_rd_addr              (w_wb_rd_addr),
        .i_wb_data                 (w_wb_data),
        
        .o_rs1_addr                (w_id_rs1_addr),
        .o_rs2_addr                (w_id_rs2_addr),
        .o_rs1_used                (w_id_rs1_used),
        .o_rs2_used                (w_id_rs2_used),
        
        .o_branch_taken            (w_id_ex_branch_taken),
        .o_branch_mispredict       (w_id_ex_branch_mispredict),
        .o_branch_recovery_target  (w_id_ex_branch_recovery_tgt),
        .o_jalr_en_out             (w_id_ex_jalr_en),
        .o_jalr_target             (w_id_ex_jalr_tgt),
        
        .o_valid                   (w_id_ex_valid),
        .o_pc                      (w_id_ex_pc),
        .o_pc_plus_4               (w_id_ex_pc_plus_4),
        .o_ex_result               (w_id_ex_result),
        .o_mem_addr                (w_id_ex_mem_addr),
        .o_store_data              (w_id_ex_store_data),
        .o_rs1_data                (w_id_ex_rs1_data),
        .o_rd_addr                 (w_id_ex_rd_addr),
        .o_reg_write               (w_id_ex_reg_write),
        .o_result_src              (w_id_ex_result_src),
        .o_mem_read                (w_id_ex_mem_read),
        .o_mem_write               (w_id_ex_mem_write),
        .o_mem_size                (w_id_ex_mem_size),
        .o_mem_uns                 (w_id_ex_mem_uns),
        
        .o_csr_addr                (w_id_ex_csr_addr),
        .o_csr_op                  (w_id_ex_csr_op),
        .o_csr_read                (w_id_ex_csr_read),
        .o_csr_write               (w_id_ex_csr_write),
        .o_is_ecall                (w_id_ex_is_ecall),
        .o_is_ebreak               (w_id_ex_is_ebreak),
        .o_is_mret                 (w_id_ex_is_mret),
        .o_sleep_req               (w_id_ex_sleep_req),
        .o_illegal_instr           (w_id_ex_illegal_instr),
        .o_instr                   (w_id_ex_instr),
        .o_mul_busy                (w_id_mul_busy)
    );

    // =========================================================================
    // 6. PIPELINE REGISTER (STAGE 2 ID/EX -> STAGE 3 MEM/WB)
    // =========================================================================
    pipe_reg_ex_mem u_pipe_reg_ex_mem (
        .i_clk           (i_clk),
        .i_rst_n         (i_rst_n),
        
        .i_stall         (w_hz_stall_ex_mem),
        .i_flush         (w_hz_flush_ex_mem),
        
        .i_valid         (w_id_ex_valid),
        .i_pc            (w_id_ex_pc),
        .i_pc_plus_4     (w_id_ex_pc_plus_4),
        .i_ex_result     (w_id_ex_result),
        .i_store_data    (w_id_ex_store_data),
        .i_rs1_data      (w_id_ex_rs1_data),
        .i_rs1_addr      (w_id_rs1_addr),
        .i_rd_addr       (w_id_ex_rd_addr),
        .i_reg_write     (w_id_ex_reg_write),
        .i_result_src    (w_id_ex_result_src),
        .i_mem_read      (w_id_ex_mem_read),
        .i_mem_write     (w_id_ex_mem_write),
        .i_mem_size      (w_id_ex_mem_size),
        .i_mem_uns       (w_id_ex_mem_uns),
        
        .i_csr_addr      (w_id_ex_csr_addr),
        .i_csr_op        (w_id_ex_csr_op),
        .i_csr_read      (w_id_ex_csr_read),
        .i_csr_write     (w_id_ex_csr_write),
        .i_is_ecall      (w_id_ex_is_ecall),
        .i_is_ebreak     (w_id_ex_is_ebreak),
        .i_is_mret       (w_id_ex_is_mret),
        .i_sleep_req     (w_id_ex_sleep_req),
        .i_illegal_instr (w_id_ex_illegal_instr),
        .i_instr         (w_id_ex_instr),
        
        .o_valid         (w_ex_mem_valid),
        .o_pc            (w_ex_mem_pc),
        .o_pc_plus_4     (w_ex_mem_pc_plus_4),
        .o_ex_result     (w_ex_mem_result),
        .o_store_data    (w_ex_mem_store_data),
        .o_rs1_data      (w_ex_mem_rs1_data),
        .o_rs1_addr      (w_ex_mem_rs1_addr),
        .o_rd_addr       (w_ex_mem_rd_addr),
        .o_reg_write     (w_ex_mem_reg_write),
        .o_result_src    (w_ex_mem_result_src),
        .o_mem_read      (w_ex_mem_mem_read),
        .o_mem_write     (w_ex_mem_mem_write),
        .o_mem_size      (w_ex_mem_size),
        .o_mem_uns       (w_ex_mem_uns),
        
        .o_csr_addr      (w_ex_mem_csr_addr),
        .o_csr_op        (w_ex_mem_csr_op),
        .o_csr_read      (w_ex_mem_csr_read),
        .o_csr_write     (w_ex_mem_csr_write),
        .o_is_ecall      (w_ex_mem_is_ecall),
        .o_is_ebreak     (w_ex_mem_is_ebreak),
        .o_is_mret       (w_ex_mem_is_mret),
        .o_sleep_req     (w_ex_mem_sleep_req),
        .o_illegal_instr (w_ex_mem_illegal_instr),
        .o_instr         (w_ex_mem_instr)
    );


    // =========================================================================
    // 7. STAGE 3: MEMORY ACCESS & WRITE-BACK (MEM/WB)
    // =========================================================================
    stage_mem_wb u_stage_mem_wb (
        .i_valid         (w_ex_mem_valid),
        .i_pc            (w_ex_mem_pc),
        .i_pc_plus_4     (w_ex_mem_pc_plus_4),
        .i_ex_result     (w_ex_mem_result),
        .i_store_data    (w_ex_mem_store_data),
        .i_rd_addr       (w_ex_mem_rd_addr),
        .i_reg_write     (w_ex_mem_reg_write),
        .i_result_src    (w_ex_mem_result_src),
        
        .i_mem_read      (w_ex_mem_mem_read),
        .i_mem_write     (w_ex_mem_mem_write),
        .i_mem_size      (w_ex_mem_size),
        .i_mem_uns       (w_ex_mem_uns),
        .i_csr_data      (w_csr_data),
        
        .i_mem_en        (w_hz_mem_en),
        .i_wb_en         (w_hz_wb_en),
        
        .i_dmem_rdata    (w_dmem_rdata_mux),
        
        .o_dmem_addr     (w_dmem_addr),
        .o_dmem_wdata    (w_dmem_wdata),
        .o_dmem_we       (w_dmem_we),
        .o_is_device_bus (w_ex_is_device),
        
        .o_wb_we         (w_wb_we),
        .o_wb_rd_addr    (w_wb_rd_addr),
        .o_wb_data       (w_wb_data)
    );

    // =========================================================================
    // 8. HAZARD CONTROLLER
    // =========================================================================
    hazard_unit u_hazard (
        .i_clk               (i_clk),
        .i_rst_n             (i_rst_n),
        
        .i_branch_mispredict (w_id_ex_branch_mispredict),
        .i_jalr_en           (w_id_ex_jalr_en),
        .i_stall_load_use    (w_stall_load_use),
        .i_mul_busy          (w_id_mul_busy),
        
        .i_ex_mem_valid      (w_ex_mem_valid),
        .i_ex_mem_mem_read   (w_ex_mem_mem_read),
        .i_ex_mem_mem_write  (w_ex_mem_mem_write),
        .i_dmem_ready        (w_dmem_ready_mux),
        
        .i_exc_req           (w_csr_exc_req),
        .i_int_req           (w_csr_int_req),
        .i_mret              (w_ex_mem_is_mret),
        
        .o_trap_taken        (w_hz_trap_taken),
        .o_stall_pc          (w_hz_stall_pc),
        .o_stall_if_id       (w_hz_stall_if_id),
        .o_flush_if_id       (w_hz_flush_if_id),
        .o_flush_id_ex       (w_hz_flush_id_ex),
        .o_stall_ex_mem      (w_hz_stall_ex_mem),
        .o_flush_ex_mem      (w_hz_flush_ex_mem),
        
        .o_mem_en            (w_hz_mem_en),
        .o_wb_en             (w_hz_wb_en)
    );

    // =========================================================================
    // 8.1. EXTERNAL INTERRUPT 2-FF SYNCHRONIZERS (METASTABILITY HARDENING)
    // =========================================================================
    sync_2ff #(.WIDTH(1), .RST_VAL(0)) u_sync_ext_irq (
        .i_clk   (i_clk),
        .i_rst_n (i_rst_n),
        .i_async (i_ext_irq),
        .o_sync  (w_ext_irq_sync)
    );

    sync_2ff #(.WIDTH(1), .RST_VAL(0)) u_sync_timer_irq (
        .i_clk   (i_clk),
        .i_rst_n (i_rst_n),
        .i_async (i_timer_irq),
        .o_sync  (w_timer_irq_sync)
    );

    // =========================================================================
    // 9. CSR UNIT (PRIVILEGED MACHINE-MODE CONTROL)
    // =========================================================================
    CSR_Unit u_csr (
        .i_clk             (i_clk),
        .i_rst_n           (i_rst_n),
        
        .i_ext_irq         (w_ext_irq_sync),
        .i_timer_irq       (w_timer_irq_sync),
        
        .i_is_ecall        (w_ex_mem_is_ecall),
        .i_is_ebreak       (w_ex_mem_is_ebreak),
        .i_illegal_instr   (w_ex_mem_illegal_instr),
        .i_instr           (w_ex_mem_instr),
        .i_bus_error       (w_mem_bus_error),
        .i_mem_write       (w_ex_mem_mem_write),
        .i_valid           (w_ex_mem_valid),
        
        .i_trap_taken      (w_hz_trap_taken),
        .o_exc_req         (w_csr_exc_req),
        .o_int_req         (w_csr_int_req),
        
        .i_alu_result      (w_ex_mem_result),
        .i_pc              (w_ex_mem_pc),
        .i_next_commit_pc  (w_ex_mem_pc_plus_4),
        .i_rs1_data        (w_ex_mem_rs1_data),
        .i_rs1_addr        (w_ex_mem_rs1_addr),
        
        .i_csr_addr        (w_ex_mem_csr_addr),
        .i_csr_write       (w_ex_mem_csr_write),
        .i_csr_read        (w_ex_mem_csr_read),
        .i_csr_op          (w_ex_mem_csr_op),
        .i_is_mret         (w_ex_mem_is_mret),
        
        .o_csr_data        (w_csr_data),
        .o_csr_pc          (w_csr_pc),
        .o_csr_pc_sel      (w_csr_pc_sel)
    );

endmodule