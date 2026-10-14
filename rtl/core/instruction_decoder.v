`timescale 1ns / 1ps
module instruction_decoder (
    input  wire [31:0] i_instr,

    // ==========================================
    // 1. ALU Control & Operand Routing
    // ==========================================
    output reg  [3:0]  o_alu_ctrl,
    output reg         o_alu_src,      // 0: RS2, 1: IMM
    output reg  [1:0]  o_alu_src_a,    // 00: RS1, 01: PC, 10: ZERO (LUI)
    output wire        o_alu_enable,   // Power-gating signal
    output reg  [2:0]  o_imm_src,      
    output reg         o_mul_valid,    // Trigger Booth Multiplier
    output reg  [1:0]  o_mul_type,     // 00:MUL, 01:MULH, 10:MULHSU, 11:MULHU
    output reg         o_simd_valid,   // Trigger SIMD Dot-Product Unit (smdot.i8)

    // ==========================================
    // 2. Memory Access Control
    // ==========================================
    output reg         o_mem_read,
    output reg         o_mem_write,
    output reg  [1:0]  o_mem_size,     // 00: Byte, 01: Half, 10: Word
    output reg         o_mem_uns,      // 1: Unsigned load (LBU, LHU)

    // ==========================================
    // 3. Write-Back Control
    // ==========================================
    output reg         o_reg_write,
    output reg  [1:0]  o_result_src,   // 00: ALU, 01: Mem, 10: PC+4, 11: CSR

    // ==========================================
    // 4. Branch & Jump Control
    // ==========================================
    output reg         o_branch,
    output reg  [2:0]  o_branch_type,  // Pass func3 to EX comparator
    output reg         o_jump,         // For JAL
    output reg         o_jalr_en,      // For JALR

    // ==========================================
    // 5. System, CSR & Power Management
    // ==========================================
    output reg         o_csr_read,
    output reg         o_csr_write,
    output reg         o_is_ecall,
    output reg         o_is_ebreak,
    output reg         o_is_mret,
    output reg         o_sleep_req,    // For WFI (Wait for Interrupt)
    output reg         o_illegal_instr,

    // ==========================================
    // 6. Operand Usage Indicators (Phase 3 Forwarding)
    // ==========================================
    output wire        o_rs1_used,
    output wire        o_rs2_used
);
    `include "riscv_core_defines.vh"
    // ==========================================
    // INSTRUCTION FIELD EXTRACTION
    // ==========================================
    wire [6:0]  w_opcode = i_instr[`OPCODE_FIELD];
    wire [2:0]  w_func3  = i_instr[`FUNC3_FIELD];
    wire [6:0]  w_func7  = i_instr[`FUNC7_FIELD];
    wire [11:0] w_func12 = i_instr[31:20];

    // ==========================================
    // MAIN DECODE LOGIC (COMBINATIONAL)
    // ==========================================
    always @(*) begin
        // STEP 1: DEFAULT ASSIGNMENTS (Prevent Latches)
        o_alu_ctrl    = 4'b0000;
        o_alu_src     = 1'b0;
        o_alu_src_a   = 2'b00;
        o_imm_src     = 3'b000;
        
        o_mul_valid   = 1'b0;
        o_mul_type    = 2'b00;
        o_simd_valid  = 1'b0;

        o_mem_read    = 1'b0;
        o_mem_write   = 1'b0;
        o_mem_size    = 2'b00;
        o_mem_uns     = 1'b0;
        
        o_reg_write   = 1'b0;
        o_result_src  = 2'b00;
        
        o_branch      = 1'b0;
        o_branch_type = 3'b000;
        o_jump        = 1'b0;
        o_jalr_en     = 1'b0;
        
        o_csr_read    = 1'b0;
        o_csr_write   = 1'b0;
        o_is_ecall      = 1'b0;
        o_is_ebreak     = 1'b0;
        o_is_mret       = 1'b0;
        o_sleep_req     = 1'b0;
        o_illegal_instr = 1'b0;

        // STEP 2: OPCODE DECODING
        case (w_opcode)
            
            // --------------------------------------------------------
            // R-Type (Register-Register / RV32M / SIMD)
            // --------------------------------------------------------
            OP_ARITHR: begin
                o_reg_write = 1'b1;
                o_alu_src   = 1'b0;   // B = RS2
                
                if (w_func7 == 7'b0000001) begin
                    // RV32M Hardware Multiplier
                    case (w_func3)
                        3'b000: begin o_mul_valid = 1'b1; o_mul_type = 2'b00; end // MUL
                        3'b001: begin o_mul_valid = 1'b1; o_mul_type = 2'b01; end // MULH
                        3'b010: begin o_mul_valid = 1'b1; o_mul_type = 2'b10; end // MULHSU
                        3'b011: begin o_mul_valid = 1'b1; o_mul_type = 2'b11; end // MULHU
                        default: begin
                            o_reg_write     = 1'b0;
                            o_illegal_instr = 1'b1; // DIV/DIVU/REM/REMU
                        end
                    endcase
                end else if (w_func7 == F7_SIMD_DOT && w_func3 == F3_SIMD_DOT) begin
                    // Packed SIMD 4x INT8 Dot-Product (smdot.i8)
                    o_simd_valid = 1'b1;
                end else begin
                    // Standard RV32I ALU Operations
                    case (w_func3)
                        F3_ADD:  o_alu_ctrl = (i_instr[`SUBTYPE_BIT]) ? ALU_SUB : ALU_ADD;
                        F3_SLL:  o_alu_ctrl = ALU_SLL;
                        F3_SLT:  o_alu_ctrl = ALU_SLT;
                        F3_SLTU: o_alu_ctrl = ALU_SLTU;
                        F3_XOR:  o_alu_ctrl = ALU_XOR;
                        F3_OR:   o_alu_ctrl = ALU_OR;
                        F3_AND:  o_alu_ctrl = ALU_AND;
                        F3_SR:   o_alu_ctrl = (i_instr[`SUBTYPE_BIT]) ? ALU_SRA : ALU_SRL;
                        default: o_alu_ctrl = ALU_ADD;
                    endcase
                end
            end

            // --------------------------------------------------------
            // I-Type (Register-Immediate)
            // --------------------------------------------------------
            OP_ARITHI: begin
                o_reg_write = 1'b1;
                o_alu_src   = 1'b1;   // B = IMM
                o_imm_src   = 3'b000;
                
                case (w_func3)
                    F3_ADD:  o_alu_ctrl = ALU_ADD;
                    F3_SLL:  o_alu_ctrl = ALU_SLL;
                    F3_SLT:  o_alu_ctrl = ALU_SLT;
                    F3_SLTU: o_alu_ctrl = ALU_SLTU;
                    F3_XOR:  o_alu_ctrl = ALU_XOR;
                    F3_OR:   o_alu_ctrl = ALU_OR;
                    F3_AND:  o_alu_ctrl = ALU_AND;
                    F3_SR:   o_alu_ctrl = (i_instr[`SUBTYPE_BIT]) ? ALU_SRA : ALU_SRL;
                    default: o_alu_ctrl = ALU_ADD;
                endcase
            end

            // --------------------------------------------------------
            // Load Instructions
            // --------------------------------------------------------
            OP_LOAD: begin
                o_reg_write  = 1'b1;
                o_alu_src    = 1'b1;     
                o_imm_src    = 3'b000;
                o_mem_read   = 1'b1;
                o_result_src = 2'b01;  // Write-back from Memory
                o_alu_ctrl   = ALU_ADD;
                o_mem_size   = w_func3[1:0]; 
                o_mem_uns    = w_func3[2];
            end

            // --------------------------------------------------------
            // Store Instructions
            // --------------------------------------------------------
            OP_STORE: begin
                o_alu_src   = 1'b1;
                o_imm_src   = 3'b001; 
                o_mem_write = 1'b1;
                o_alu_ctrl  = ALU_ADD;
                o_mem_size  = w_func3[1:0];
            end

            // --------------------------------------------------------
            // Branch Instructions
            // --------------------------------------------------------
            OP_BRANCH: begin
                o_branch      = 1'b1;
                o_branch_type = w_func3; 
                o_imm_src     = 3'b010;
                o_alu_ctrl    = ALU_SUB; // Use ALU subtraction for comparison
            end

            // --------------------------------------------------------
            // Jump & Link (JAL)
            // --------------------------------------------------------
            OP_JAL: begin
                o_reg_write  = 1'b1;
                o_result_src = 2'b10;  // Write-back PC+4
                o_jump       = 1'b1;
                o_imm_src    = 3'b100;
            end

            // --------------------------------------------------------
            // Jump & Link Register (JALR)
            // --------------------------------------------------------
            OP_JALR: begin
                o_reg_write  = 1'b1;
                o_result_src = 2'b10;  // Write-back PC+4
                o_jalr_en    = 1'b1;
                o_alu_src    = 1'b1;   // Target = RS1 + IMM
                o_imm_src    = 3'b000;
                o_alu_ctrl   = ALU_ADD;
            end

            // --------------------------------------------------------
            // LUI (Load Upper Immediate)
            // --------------------------------------------------------
            OP_LUI: begin
                o_reg_write = 1'b1;
                o_alu_src_a = 2'b10;   // A = ZERO
                o_alu_src   = 1'b1;    // B = IMM
                o_imm_src   = 3'b011;
                o_alu_ctrl  = ALU_ADD;
            end

            // --------------------------------------------------------
            // AUIPC (Add Upper Immediate to PC)
            // --------------------------------------------------------
            OP_AUIPC: begin
                o_reg_write = 1'b1;
                o_alu_src_a = 2'b01;   // A = PC
                o_alu_src   = 1'b1;    // B = IMM
                o_imm_src   = 3'b011;
                o_alu_ctrl  = ALU_ADD;
            end

            // --------------------------------------------------------
            // System, Exceptions & CSR
            // --------------------------------------------------------
            OP_SYSTEM: begin
                if (w_func3 == F3_PRIV) begin
                    case (w_func12)
                        12'b0000_0000_0000: o_is_ecall      = 1'b1;
                        12'b0000_0000_0001: o_is_ebreak     = 1'b1;
                        12'b0011_0000_0010: o_is_mret       = 1'b1;
                        12'b0001_0000_0101: o_sleep_req     = 1'b1; // WFI
                        default:            o_illegal_instr = 1'b1;
                    endcase
                end else if (w_func3 == F3_CSRRW  || w_func3 == F3_CSRRS  || w_func3 == F3_CSRRC ||
                             w_func3 == F3_CSRRWI || w_func3 == F3_CSRRSI || w_func3 == F3_CSRRCI) begin
                    o_reg_write  = 1'b1;
                    o_result_src = 2'b11;  // Write-back from CSR
                    o_csr_read   = 1'b1;
                    o_csr_write  = 1'b1;
                    
                    // Hardware Optimization: Skip write if RS1 = x0
                    if ((i_instr[`RS1_FIELD] == 5'd0) && (w_func3 != F3_CSRRW) && (w_func3 != F3_CSRRWI)) begin
                        o_csr_write = 1'b0;
                    end
                end else begin
                    o_illegal_instr = 1'b1;
                end
            end

            // --------------------------------------------------------
            // Memory Fence
            // --------------------------------------------------------
            OP_FENCE: begin
                // Handled as NOP in single-issue architecture
            end

            default: begin
                o_illegal_instr = 1'b1;
            end
        endcase
    end


    // ==========================================
    // ALU POWER GATING (DYNAMIC CLOCK/DATA GATING)
    // ==========================================
    assign o_alu_enable = (w_opcode == OP_ARITHR) | 
                          (w_opcode == OP_ARITHI) |
                          (w_opcode == OP_LOAD)   | 
                          (w_opcode == OP_STORE)  | 
                          (w_opcode == OP_BRANCH) |
                          (w_opcode == OP_LUI)    | 
                          (w_opcode == OP_AUIPC)  | 
                          (w_opcode == OP_JALR);

    // ==========================================
    // OPERAND USAGE LOGIC (PHASE 3 FORWARDING & HAZARDS)
    // ==========================================
    assign o_rs1_used = (w_opcode == OP_ARITHR) | 
                        (w_opcode == OP_ARITHI) | 
                        (w_opcode == OP_LOAD)   | 
                        (w_opcode == OP_STORE)  | 
                        (w_opcode == OP_BRANCH) | 
                        (w_opcode == OP_JALR)   | 
                        (w_opcode == OP_SYSTEM);

    assign o_rs2_used = (w_opcode == OP_ARITHR) | 
                        (w_opcode == OP_STORE)  | 
                        (w_opcode == OP_BRANCH);

endmodule