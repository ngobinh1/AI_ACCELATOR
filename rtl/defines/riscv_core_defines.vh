// ==============================================================================
// FILE: riscv_core_defines.vh
// DESCRIPTION: Global definitions, Opcodes, and Parameters for RISC-V RV32I/M
// ==============================================================================

`ifndef RISCV_FIELD_DEFINES_VH
`define RISCV_FIELD_DEFINES_VH

// ==============================================================================
// 1. INSTRUCTION FIELD SLICES (Trích xuất bit mã máy)
// ==============================================================================
`define OPCODE_FIELD   6:0
`define RD_FIELD       11:7
`define FUNC3_FIELD    14:12
`define RS1_FIELD      19:15
`define RS2_FIELD      24:20
`define FUNC7_FIELD    31:25
`define SUBTYPE_BIT    30    // Bit phân biệt ADD/SUB hoặc SRL/SRA

`endif // RISCV_FIELD_DEFINES_VH

// ==============================================================================
// 2. CONSTANTS
// ==============================================================================
localparam [31:0] RESET_VEC = 32'h0000_0000;
localparam [31:0] INST_NOP  = 32'h0000_0013; // addi x0, x0, 0

// ==============================================================================
// 3. MAJOR OPCODES (Inst[6:0])
// ==============================================================================
localparam [6:0] OP_LUI    = 7'b0110111, // U-type
                 OP_AUIPC  = 7'b0010111, // U-type
                 OP_JAL    = 7'b1101111, // J-type
                 OP_JALR   = 7'b1100111, // I-type
                 OP_BRANCH = 7'b1100011, // B-type
                 OP_LOAD   = 7'b0000011, // I-type
                 OP_STORE  = 7'b0100011, // S-type
                 OP_ARITHI = 7'b0010011, // I-type (ADDI, XORI...)
                 OP_ARITHR = 7'b0110011, // R-type (ADD, SUB...)
                 OP_FENCE  = 7'b0001111, // Memory Fence
                 OP_SYSTEM = 7'b1110011; // ECALL, EBREAK, CSR

// ==============================================================================
// 4. FUNC3 DEFINITIONS (Inst[14:12])
// ==============================================================================
// Branch (OP_BRANCH)
localparam [2:0] F3_BEQ  = 3'b000,
                 F3_BNE  = 3'b001,
                 F3_BLT  = 3'b100,
                 F3_BGE  = 3'b101,
                 F3_BLTU = 3'b110,
                 F3_BGEU = 3'b111;

// Load (OP_LOAD)
localparam [2:0] F3_LB   = 3'b000,
                 F3_LH   = 3'b001,
                 F3_LW   = 3'b010,
                 F3_LBU  = 3'b100,
                 F3_LHU  = 3'b101;

// Store (OP_STORE)
localparam [2:0] F3_SB   = 3'b000,
                 F3_SH   = 3'b001,
                 F3_SW   = 3'b010;

// Arithmetic (OP_ARITHR / OP_ARITHI)
localparam [2:0] F3_ADD  = 3'b000, // ADD/SUB
                 F3_SLL  = 3'b001, // SLL
                 F3_SLT  = 3'b010, // SLT
                 F3_SLTU = 3'b011, // SLTU
                 F3_XOR  = 3'b100, // XOR
                 F3_SR   = 3'b101, // SRL/SRA
                 F3_OR   = 3'b110, // OR
                 F3_AND  = 3'b111; // AND

// SIMD Packed INT8 Acceleration (smdot.i8 in OP_ARITHR)
localparam [6:0] F7_SIMD_DOT = 7'b0000100;
localparam [2:0] F3_SIMD_DOT = 3'b100;

// CSR (OP_SYSTEM)
localparam [2:0] F3_PRIV   = 3'b000, // ECALL, EBREAK, MRET
                 F3_CSRRW  = 3'b001,
                 F3_CSRRS  = 3'b010,
                 F3_CSRRC  = 3'b011,
                 F3_CSRRWI = 3'b101,
                 F3_CSRRSI = 3'b110,
                 F3_CSRRCI = 3'b111;

// ==============================================================================
// 5. ALU CONTROL CODES
// ==============================================================================
// Khử toàn bộ Magic Numbers trong ALU.v
localparam [3:0] ALU_ADD  = 4'b0000,
                 ALU_SUB  = 4'b1000,
                 ALU_SLL  = 4'b0001,
                 ALU_SLT  = 4'b0010,
                 ALU_SLTU = 4'b0011,
                 ALU_XOR  = 4'b0100,
                 ALU_SRL  = 4'b0101,
                 ALU_SRA  = 4'b1101,
                 ALU_OR   = 4'b0110,
                 ALU_AND  = 4'b0111;

// ==============================================================================
// 6. MACHINE-MODE CSR ADDRESSES (Chỉ giữ lại các thanh ghi cần thiết)
// ==============================================================================
localparam [11:0] CSR_MSTATUS = 12'h300,
                  CSR_MIE     = 12'h304,
                  CSR_MTVEC   = 12'h305,
                  CSR_MSCRATCH= 12'h340,
                  CSR_MEPC    = 12'h341,
                  CSR_MCAUSE  = 12'h342,
                  CSR_MTVAL   = 12'h343,
                  CSR_MIP     = 12'h344;

// ==============================================================================
// 7. EXCEPTION & INTERRUPT CAUSES 
// ==============================================================================
localparam [31:0] EXC_INST_ADDR_MISALIGNED = 32'd0,
                  EXC_ILLEGAL_INST         = 32'd2,
                  EXC_BREAKPOINT           = 32'd3,
                  EXC_LOAD_ADDR_MISALIGNED = 32'd4,
                  EXC_STORE_ADDR_MISALIGNED= 32'd6,
                  EXC_ECALL_FROM_MMODE     = 32'd11;
