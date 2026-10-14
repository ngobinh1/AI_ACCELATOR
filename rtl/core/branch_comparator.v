module branch_comparator (
    input  wire       i_branch_en,    
    input  wire [2:0] i_branch_type,  
    
    input  wire       i_zero,
    input  wire       i_negative,
    input  wire       i_carry,        
    input  wire       i_overflow,     
    
    output reg        o_branch_taken  
);
    `include "riscv_core_defines.vh"
    reg r_cond_met;

    always @(*) begin
        r_cond_met = 1'b0;
        
        // CHỈ TÍNH TOÁN CỜ KHI DÚNG LÀ LỆNH BRANCH
        if (i_branch_en) begin
            case (i_branch_type)
                F3_BEQ:  r_cond_met = i_zero;                  
                F3_BNE:  r_cond_met = ~i_zero;                 
                F3_BLT:  r_cond_met = (i_negative ^ i_overflow);
                F3_BGE:  r_cond_met = ~(i_negative ^ i_overflow);
                F3_BLTU: r_cond_met = ~i_carry;
                F3_BGEU: r_cond_met = i_carry;
                default: r_cond_met = 1'b0;
            endcase
            o_branch_taken = r_cond_met;
        end else begin
            // KHÔNG PHẢI BRANCH -> BẮT BUỘC RA 0 (Tránh lan truyền X từ ALU)
            o_branch_taken = 1'b0;
        end
    end

endmodule