`timescale 1ns / 1ps

module imm_gen (
    input  wire [31:0] i_instr,
    input  wire [2:0]  i_imm_src,
    output reg  [31:0] o_imm_ext
);

    // =========================================================================
    // IMMEDIATE FORMAT SELECTORS
    // =========================================================================
    localparam [2:0] IMM_I = 3'b000,
                     IMM_S = 3'b001,
                     IMM_B = 3'b010,
                     IMM_U = 3'b011,
                     IMM_J = 3'b100;

    // =========================================================================
    // COMBINATIONAL IMMEDIATE EXTRACTION
    // =========================================================================
    always @(*) begin
        // Default assignment to prevent latches
        o_imm_ext = 32'd0;
        
        case (i_imm_src)
            // I-Type: Load, ALU Immediate, JALR
            IMM_I: o_imm_ext = {{20{i_instr[31]}}, i_instr[31:20]};
            
            // S-Type: Store (sb, sh, sw)
            IMM_S: o_imm_ext = {{20{i_instr[31]}}, i_instr[31:25], i_instr[11:7]};
            
            // B-Type: Branch (beq, bne, blt, bge, bltu, bgeu)
            IMM_B: o_imm_ext = {{20{i_instr[31]}}, i_instr[7], i_instr[30:25], i_instr[11:8], 1'b0};
            
            // U-Type: LUI, AUIPC
            IMM_U: o_imm_ext = {i_instr[31:12], 12'd0};
            
            // J-Type: JAL
            IMM_J: o_imm_ext = {{12{i_instr[31]}}, i_instr[19:12], i_instr[20], i_instr[30:21], 1'b0};
            
            default: o_imm_ext = 32'd0;
        endcase
    end

endmodule