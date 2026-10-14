`timescale 1ns / 1ps
module st_align (
    input  wire [1:0]  i_mem_size,  // From Decoder: 00:Byte, 01:Half, 10:Word
    input  wire [1:0]  i_addr_lsb,  // 2 LSBs of ALU calculated address
    input  wire [31:0] i_rs2_data,  // Unaligned store data from RS2 register
    output reg  [31:0] o_mem_wdata  // Aligned 32-bit data to memory bus
);
    `include "riscv_core_defines.vh"
    // =========================================================================
    // COMBINATIONAL DATA ALIGNMENT (SHIFT LOGIC)
    // =========================================================================
    always @(*) begin    
        // Default catch-all
        o_mem_wdata = i_rs2_data;

        case (i_mem_size)
            // Word Access: Pass through directly
            2'b10: o_mem_wdata = i_rs2_data;
            
            // Half-word Access: Replicate lower 16-bit to upper half if address bit [1] is high
            2'b01: o_mem_wdata = (i_addr_lsb[1]) ? {i_rs2_data[15:0], 16'd0} : 
                                                   {16'd0, i_rs2_data[15:0]};
            
            // Byte Access: Shift byte to its designated slot based on address bits [1:0]
            2'b00: begin
                case (i_addr_lsb)
                    2'b00:   o_mem_wdata = {24'd0, i_rs2_data[7:0]};         // Byte 0 slot
                    2'b01:   o_mem_wdata = {16'd0, i_rs2_data[7:0], 8'd0};   // Byte 1 slot
                    2'b10:   o_mem_wdata = {8'd0,  i_rs2_data[7:0], 16'd0};  // Byte 2 slot
                    2'b11:   o_mem_wdata = {i_rs2_data[7:0], 24'd0};         // Byte 3 slot
                    default: o_mem_wdata = i_rs2_data;
                endcase
            end
            
            default: o_mem_wdata = i_rs2_data;
        endcase
    end

endmodule