`timescale 1ns / 1ps
// ==============================================================================
// MODULE: rvc_decompressor
// DESCRIPTION: Zero-Cycle Combinational RISC-V Compressed Instruction Expander
// SPECIFICATION: RISC-V "C" Extension (RV32C / RVC Standard)
// ARCHITECTURE: RISC-V 32-bit IoT & AI Accelerator Core (Phase 4)
// ==============================================================================

module rvc_decompressor (
    input  wire [15:0] i_c_instr,          // 16-bit compressed instruction
    output reg  [31:0] o_decomp_instr,     // 32-bit standard RV32I uncompressed instruction
    output reg         o_illegal_instr     // 1 if invalid / reserved compressed instruction
);

    // =========================================================================
    // FIELD EXTRACTION & CONSTANT DEFINITIONS
    // =========================================================================
    wire [1:0] op     = i_c_instr[1:0];
    wire [2:0] funct3 = i_c_instr[15:13];

    // Standard and Compressed Register Addressing
    // c_rs1' and c_rs2' map to x8 - x15 (s0/fp, s1, a0 - a5)
    wire [4:0] rd     = i_c_instr[11:7];
    wire [4:0] rs2    = i_c_instr[6:2];
    wire [4:0] c_rd_s = {2'b01, i_c_instr[4:2]};   // x8 + inst[4:2]
    wire [4:0] c_rs1_s= {2'b01, i_c_instr[9:7]};   // x8 + inst[9:7]
    wire [4:0] c_rs2_s= {2'b01, i_c_instr[4:2]};   // x8 + inst[4:2]

    // Standard RISC-V Base Opcodes
    localparam [6:0] OP_LUI    = 7'b0110111;
    localparam [6:0] OP_AUIPC  = 7'b0010111;
    localparam [6:0] OP_JAL    = 7'b1101111;
    localparam [6:0] OP_JALR   = 7'b1100111;
    localparam [6:0] OP_BRANCH = 7'b1100011;
    localparam [6:0] OP_LOAD   = 7'b0000011;
    localparam [6:0] OP_STORE  = 7'b0100011;
    localparam [6:0] OP_IMM    = 7'b0010011;
    localparam [6:0] OP_REG    = 7'b0110011;
    localparam [6:0] OP_SYSTEM = 7'b1110011;

    // Immediate Reconstruction Logic
    // c.addi4spn: nzuimm[9:2]
    wire [9:0] imm_addi4spn = {i_c_instr[10:7], i_c_instr[12:11], i_c_instr[5], i_c_instr[6], 2'b00};

    // c.lw / c.sw: uimm[6:2]
    wire [6:0] imm_lsw = {i_c_instr[5], i_c_instr[12:10], i_c_instr[6], 2'b00};

    // c.addi / c.li / c.andi: imm[5:0] sign-extended
    wire [31:0] imm_ci = {{26{i_c_instr[12]}}, i_c_instr[12], i_c_instr[6:2]};

    // c.addi16sp: nzimm[9:4] sign-extended
    wire [31:0] imm_addi16sp = {{22{i_c_instr[12]}}, i_c_instr[12], i_c_instr[4:3], i_c_instr[5], i_c_instr[2], i_c_instr[6], 4'b0000};

    // c.lui: nzimm[17:12]
    wire [31:0] imm_lui = {{14{i_c_instr[12]}}, i_c_instr[12], i_c_instr[6:2], 12'b0};

    // c.j / c.jal: offset[11:1] sign-extended
    wire [31:0] imm_cj = {{20{i_c_instr[12]}}, i_c_instr[12], i_c_instr[8], i_c_instr[10:9], i_c_instr[6], i_c_instr[7], i_c_instr[2], i_c_instr[11], i_c_instr[5:3], 1'b0};

    // c.beqz / c.bnez: offset[8:1] sign-extended
    wire [31:0] imm_cb = {{23{i_c_instr[12]}}, i_c_instr[12], i_c_instr[6:5], i_c_instr[2], i_c_instr[11:10], i_c_instr[4:3], 1'b0};

    // c.lwsp: uimm[7:2]
    wire [31:0] imm_lwsp = {24'b0, i_c_instr[3:2], i_c_instr[12], i_c_instr[6:4], 2'b00};

    // c.swsp: uimm[7:2]
    wire [31:0] imm_swsp = {24'b0, i_c_instr[8:7], i_c_instr[12:9], 2'b00};

    // =========================================================================
    // COMBINATIONAL DECOMPRESSION MAPPING
    // =========================================================================
    always @(*) begin
        o_decomp_instr  = 32'h00000013; // Default: NOP (addi x0, x0, 0)
        o_illegal_instr = 1'b0;

        case (op)
            // =================================================================
            // QUADRANT 0 (op = 2'b00)
            // =================================================================
            2'b00: begin
                case (funct3)
                    // c.addi4spn: addi rd', x2, nzuimm
                    3'b000: begin
                        if (imm_addi4spn == 10'd0) begin
                            o_illegal_instr = 1'b1; // nzuimm == 0 is reserved
                        end else begin
                            o_decomp_instr = {2'b0, imm_addi4spn, 5'd2, 3'b000, c_rd_s, OP_IMM};
                        end
                    end

                    // c.lw: lw rd', offset(rs1')
                    3'b010: begin
                        o_decomp_instr = {5'b0, imm_lsw, c_rs1_s, 3'b010, c_rd_s, OP_LOAD};
                    end

                    // c.sw: sw rs2', offset(rs1')
                    3'b110: begin
                        o_decomp_instr = {5'b0, imm_lsw[6:5], c_rs2_s, c_rs1_s, 3'b010, imm_lsw[4:0], OP_STORE};
                    end

                    default: begin
                        o_illegal_instr = 1'b1;
                    end
                endcase
            end

            // =================================================================
            // QUADRANT 1 (op = 2'b01)
            // =================================================================
            2'b01: begin
                case (funct3)
                    // c.nop / c.addi: addi rd, rd, nzimm
                    3'b000: begin
                        // If rd == 0: c.nop (addi x0, x0, 0)
                        o_decomp_instr = {imm_ci[11:0], rd, 3'b000, rd, OP_IMM};
                    end

                    // c.jal: jal x1, offset (RV32C only)
                    3'b001: begin
                        o_decomp_instr = {imm_cj[20], imm_cj[10:1], imm_cj[11], imm_cj[19:12], 5'd1, OP_JAL};
                    end

                    // c.li: addi rd, x0, imm
                    3'b010: begin
                        if (rd == 5'd0) begin
                            o_illegal_instr = 1'b1; // rd = 0 is HINT / reserved
                        end else begin
                            o_decomp_instr = {imm_ci[11:0], 5'd0, 3'b000, rd, OP_IMM};
                        end
                    end

                    // c.addi16sp / c.lui
                    3'b011: begin
                        if (rd == 5'd2) begin
                            // c.addi16sp: addi x2, x2, nzimm
                            if (imm_addi16sp == 32'd0) begin
                                o_illegal_instr = 1'b1; // nzimm == 0 is reserved
                            end else begin
                                o_decomp_instr = {imm_addi16sp[11:0], 5'd2, 3'b000, 5'd2, OP_IMM};
                            end
                        end else if (rd != 5'd0) begin
                            // c.lui: lui rd, nzimm
                            if (imm_lui == 32'd0) begin
                                o_illegal_instr = 1'b1; // nzimm == 0 is reserved
                            end else begin
                                o_decomp_instr = {imm_lui[31:12], rd, OP_LUI};
                            end
                        end else begin
                            o_illegal_instr = 1'b1; // rd = 0 is reserved
                        end
                    end

                    // Sub-functions: c.srli, c.srai, c.andi, Arithmetic
                    3'b100: begin
                        case (i_c_instr[11:10])
                            // c.srli: srli rs1', rs1', shamt
                            2'b00: begin
                                if (i_c_instr[12] != 1'b0) begin
                                    o_illegal_instr = 1'b1; // shamt[5] must be 0 for RV32
                                end else begin
                                    o_decomp_instr = {7'b0000000, i_c_instr[6:2], c_rs1_s, 3'b101, c_rs1_s, OP_IMM};
                                end
                            end

                            // c.srai: srai rs1', rs1', shamt
                            2'b01: begin
                                if (i_c_instr[12] != 1'b0) begin
                                    o_illegal_instr = 1'b1; // shamt[5] must be 0 for RV32
                                end else begin
                                    o_decomp_instr = {7'b0100000, i_c_instr[6:2], c_rs1_s, 3'b101, c_rs1_s, OP_IMM};
                                end
                            end

                            // c.andi: andi rs1', rs1', imm
                            2'b10: begin
                                o_decomp_instr = {imm_ci[11:0], c_rs1_s, 3'b111, c_rs1_s, OP_IMM};
                            end

                            // ALU Register-Register operations
                            2'b11: begin
                                if (i_c_instr[12] == 1'b0) begin
                                    case (i_c_instr[6:5])
                                        2'b00: o_decomp_instr = {7'b0100000, c_rs2_s, c_rs1_s, 3'b000, c_rs1_s, OP_REG}; // c.sub
                                        2'b01: o_decomp_instr = {7'b0000000, c_rs2_s, c_rs1_s, 3'b100, c_rs1_s, OP_REG}; // c.xor
                                        2'b10: o_decomp_instr = {7'b0000000, c_rs2_s, c_rs1_s, 3'b110, c_rs1_s, OP_REG}; // c.or
                                        2'b11: o_decomp_instr = {7'b0000000, c_rs2_s, c_rs1_s, 3'b111, c_rs1_s, OP_REG}; // c.and
                                    endcase
                                end else begin
                                    o_illegal_instr = 1'b1; // Reserved in RV32
                                end
                            end
                        endcase
                    end

                    // c.j: jal x0, offset
                    3'b101: begin
                        o_decomp_instr = {imm_cj[20], imm_cj[10:1], imm_cj[11], imm_cj[19:12], 5'd0, OP_JAL};
                    end

                    // c.beqz: beq rs1', x0, offset
                    3'b110: begin
                        o_decomp_instr = {imm_cb[12], imm_cb[10:5], 5'd0, c_rs1_s, 3'b000, imm_cb[4:1], imm_cb[11], OP_BRANCH};
                    end

                    // c.bnez: bne rs1', x0, offset
                    3'b111: begin
                        o_decomp_instr = {imm_cb[12], imm_cb[10:5], 5'd0, c_rs1_s, 3'b001, imm_cb[4:1], imm_cb[11], OP_BRANCH};
                    end
                endcase
            end

            // =================================================================
            // QUADRANT 2 (op = 2'b10)
            // =================================================================
            2'b10: begin
                case (funct3)
                    // c.slli: slli rd, rd, shamt
                    3'b000: begin
                        if (rd == 5'd0 || i_c_instr[12] != 1'b0) begin
                            o_illegal_instr = 1'b1; // rd = 0 is HINT; shamt[5] must be 0 for RV32
                        end else begin
                            o_decomp_instr = {7'b0000000, i_c_instr[6:2], rd, 3'b001, rd, OP_IMM};
                        end
                    end

                    // c.lwsp: lw rd, offset(x2)
                    3'b010: begin
                        if (rd == 5'd0) begin
                            o_illegal_instr = 1'b1; // rd = 0 is reserved
                        end else begin
                            o_decomp_instr = {imm_lwsp[11:0], 5'd2, 3'b010, rd, OP_LOAD};
                        end
                    end

                    // Control transfers & Register moves
                    3'b100: begin
                        if (i_c_instr[12] == 1'b0) begin
                            if (rs2 == 5'd0) begin
                                // c.jr: jalr x0, 0(rs1)
                                if (rd == 5'd0) begin
                                    o_illegal_instr = 1'b1; // rs1 = 0 is reserved
                                end else begin
                                    o_decomp_instr = {12'b0, rd, 3'b000, 5'd0, OP_JALR};
                                end
                            end else begin
                                // c.mv: add rd, x0, rs2
                                if (rd == 5'd0) begin
                                    o_illegal_instr = 1'b1; // rd = 0 is HINT
                                end else begin
                                    o_decomp_instr = {7'b0000000, rs2, 5'd0, 3'b000, rd, OP_REG};
                                end
                            end
                        end else begin
                            if (rs2 == 5'd0) begin
                                if (rd == 5'd0) begin
                                    // c.ebreak: ebreak
                                    o_decomp_instr = 32'h00100073;
                                end else begin
                                    // c.jalr: jalr x1, 0(rs1)
                                    o_decomp_instr = {12'b0, rd, 3'b000, 5'd1, OP_JALR};
                                end
                            end else begin
                                // c.add: add rd, rd, rs2
                                if (rd == 5'd0) begin
                                    o_illegal_instr = 1'b1; // rd = 0 is HINT
                                end else begin
                                    o_decomp_instr = {7'b0000000, rs2, rd, 3'b000, rd, OP_REG};
                                end
                            end
                        end
                    end

                    // c.swsp: sw rs2, offset(x2)
                    3'b110: begin
                        o_decomp_instr = {imm_swsp[11:5], rs2, 5'd2, 3'b010, imm_swsp[4:0], OP_STORE};
                    end

                    default: begin
                        o_illegal_instr = 1'b1;
                    end
                endcase
            end

            default: begin
                o_illegal_instr = 1'b1;
            end
        endcase
    end

endmodule
