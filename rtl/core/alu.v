`timescale 1ns / 1ps
module alu (
    input  wire [31:0] i_a,           // Operand A
    input  wire [31:0] i_b,           // Operand B
    input  wire [3:0]  i_alu_ctrl,    // ALU Control signal from Decoder
    
    output reg  [31:0] o_result,      // 32-bit computation result
    output wire        o_zero,        // High if Result == 0
    output wire        o_negative,    // High if Result < 0 (MSB is 1)
    output wire        o_carry,       // Carry out from addition / Borrow from subtraction
    output wire        o_overflow     // Signed overflow flag
);
    `include "riscv_core_defines.vh"
    // =========================================================================
    // RESOURCE OPTIMIZATION: SHARED ADDER / SUBTRACTOR
    // =========================================================================
    // Instead of instantiating separate adders and subtractors for arithmetic
    // and comparisons, we use a single 33-bit adder.
    
    wire        w_is_sub;
    wire [32:0] w_sum_res;
    
    // Subtraction is required for SUB, SLT, and SLTU instructions
    assign w_is_sub = (i_alu_ctrl == ALU_SUB) | 
                      (i_alu_ctrl == ALU_SLT) | 
                      (i_alu_ctrl == ALU_SLTU);

    // 2's Complement Addition: A + (~B) + 1 if subtracting, else A + B
    assign w_sum_res = {1'b0, i_a} + {1'b0, (w_is_sub ? ~i_b : i_b)} + {32'd0, w_is_sub};

    // =========================================================================
    // RESULT MULTIPLEXER (COMBINATIONAL LOGIC)
    // =========================================================================
    always @(*) begin
        // Default assignment to prevent latch inference
        o_result = 32'd0;
        
        case (i_alu_ctrl)
            // Arithmetic Operations
            ALU_ADD:  o_result = w_sum_res[31:0];
            ALU_SUB:  o_result = w_sum_res[31:0];
            
            // Shift Operations
            ALU_SLL:  o_result = i_a << i_b[4:0];
            ALU_SRL:  o_result = i_a >> i_b[4:0];
            ALU_SRA:  o_result = $signed(i_a) >>> i_b[4:0];
            
            // Logical Operations
            ALU_XOR:  o_result = i_a ^ i_b;
            ALU_OR:   o_result = i_a | i_b;
            ALU_AND:  o_result = i_a & i_b;
            
            // Set Less Than (Signed): 
            // If signs differ, negative operand is smaller. If same, check subtractor borrow.
            ALU_SLT:  o_result = {31'd0, (i_a[31] != i_b[31]) ? i_a[31] : w_sum_res[31]};
            
            // Set Less Than (Unsigned):
            // Simply invert the carry-out (borrow) from the 33-bit subtractor.
            ALU_SLTU: o_result = {31'd0, ~w_sum_res[32]};
            
            // Default catch-all
            default:  o_result = 32'd0;
        endcase
    end

    // =========================================================================
    // STATUS FLAGS GENERATION
    // =========================================================================
    
    // Zero flag: Critical for BEQ / BNE evaluations
    assign o_zero     = (o_result == 32'd0);
    
    // Negative flag: Sign bit of the result
    assign o_negative = o_result[31];
    
    // Carry flag: Extracted from the 33rd bit of the shared adder
    // Only meaningful during ADD or SUB operations
    assign o_carry    = w_sum_res[32];
    
    // Overflow flag: Occurs if two inputs with the same sign produce a result 
    // with a different sign (Addition), or inputs with different signs produce 
    // a result with a sign different from Operand A (Subtraction).
    assign o_overflow = (i_alu_ctrl == ALU_ADD) ? (~(i_a[31] ^ i_b[31]) & (i_a[31] ^ o_result[31])) :
                        (i_alu_ctrl == ALU_SUB) ? ( (i_a[31] ^ i_b[31]) & (i_a[31] ^ o_result[31])) : 1'b0;

endmodule