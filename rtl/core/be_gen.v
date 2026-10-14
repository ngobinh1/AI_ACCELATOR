`timescale 1ns / 1ps
module be_gen (
    input  wire [1:0] i_mem_size,  // From Decoder: 00:Byte, 01:Half, 10:Word
    input  wire [1:0] i_addr_lsb,  // 2 LSBs of ALU calculated address
    output reg  [3:0] o_we_mask    // 4-bit Write Enable Mask for SRAM
);
    `include "riscv_core_defines.vh"
    // =========================================================================
    // COMBINATIONAL MASK GENERATION
    // =========================================================================
    always @(*) begin
        // Default assignment to prevent latches
        o_we_mask = 4'b0000;
        
        case (i_mem_size)
            // Word Access (32-bit): All bytes enabled
            2'b10: o_we_mask = 4'b1111;
            
            // Half-word Access (16-bit): Gated by address bit [1]
            2'b01: o_we_mask = (i_addr_lsb[1]) ? 4'b1100 : 4'b0011;
            
            // Byte Access (8-bit): Gated by both address bits [1:0]
            2'b00: begin
                case (i_addr_lsb)
                    2'b00:   o_we_mask = 4'b0001; // Byte 0
                    2'b01:   o_we_mask = 4'b0010; // Byte 1
                    2'b10:   o_we_mask = 4'b0100; // Byte 2
                    2'b11:   o_we_mask = 4'b1000; // Byte 3
                    default: o_we_mask = 4'b0000;
                endcase
            end
            
            default: o_we_mask = 4'b0000;
        endcase
    end

endmodule