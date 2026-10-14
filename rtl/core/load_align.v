`timescale 1ns / 1ps

module load_align (
    input  wire [31:0] i_mem_rdata,       // Raw 32-bit read data from RAM or Bus
    input  wire [1:0]  i_addr_lsb,        // 2 LSBs of address (alu_result[1:0])
    input  wire [1:0]  i_mem_size,        // Access size: 00 (Byte), 01 (Half), 10 (Word)
    input  wire        i_mem_uns,         // Extension type: 1 = Unsigned, 0 = Signed
    
    output reg  [31:0] o_formatted_data   // Formatted 32-bit data for Register File
);

    // Internal combinational signals
    reg [7:0]  w_extracted_byte;
    reg [15:0] w_extracted_half;

    always @(*) begin
        // =======================================================
        // STEP 1: DATA EXTRACTION (BYTE / HALFWORD SLICING)
        // =======================================================
        // Byte extraction for LB / LBU instructions
        case (i_addr_lsb)
            2'b00: w_extracted_byte = i_mem_rdata[7:0];
            2'b01: w_extracted_byte = i_mem_rdata[15:8];
            2'b10: w_extracted_byte = i_mem_rdata[23:16];
            2'b11: w_extracted_byte = i_mem_rdata[31:24];
        endcase

        // Halfword extraction for LH / LHU instructions
        if (i_addr_lsb[1]) w_extracted_half = i_mem_rdata[31:16];
        else               w_extracted_half = i_mem_rdata[15:0];

        // =======================================================
        // STEP 2: SIGN / ZERO EXTENSION & ALIGNMENT
        // =======================================================
        // Default assignment to prevent latch synthesis
        o_formatted_data = i_mem_rdata; 

        case (i_mem_size)
            // Byte Access (LB / LBU)
            2'b00: begin 
                if (i_mem_uns) 
                    o_formatted_data = {24'd0, w_extracted_byte};
                else           
                    o_formatted_data = {{24{w_extracted_byte[7]}}, w_extracted_byte};
            end
            
            // Halfword Access (LH / LHU)
            2'b01: begin 
                if (i_mem_uns) 
                    o_formatted_data = {16'd0, w_extracted_half};
                else           
                    o_formatted_data = {{16{w_extracted_half[15]}}, w_extracted_half};
            end
            
            // Word Access (LW)
            2'b10: begin 
                o_formatted_data = i_mem_rdata;
            end
            
            default: o_formatted_data = i_mem_rdata;
        endcase
    end

endmodule