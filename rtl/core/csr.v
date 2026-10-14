`timescale 1ns / 1ps

module CSR_Unit (
    input  wire        i_clk,
    input  wire        i_rst_n,
    
    // ==========================================
    // 1. NGUỒN NGOẠI LỆ VÀ NGẮT
    // ==========================================
    input  wire        i_ext_irq,        
    input  wire        i_timer_irq,      
    
    input  wire        i_is_ecall,      
    input  wire        i_is_ebreak,
    input  wire        i_illegal_instr,
    input  wire [31:0] i_instr,
    input  wire        i_bus_error,      
    input  wire        i_mem_write,      
    input  wire        i_valid,         

    // ==========================================
    // 2. BẮT TAY VỚI HAZARD UNIT
    // ==========================================
    input  wire        i_trap_taken,     
    output wire        o_exc_req,        
    output wire        o_int_req,        

    // ==========================================
    // 3. DỮ LIỆU TỪ TẦNG DATAPATH
    // ==========================================
    input  wire [31:0] i_alu_result,     // Bỏ ex_
    input  wire [31:0] i_pc,             // Bỏ ex_ (PC lệnh hiện tại)
    input  wire [31:0] i_next_commit_pc, 
    input  wire [31:0] i_rs1_data,       // Bỏ ex_
    input  wire [4:0]  i_rs1_addr,       // THÊM: Dùng làm zimm_data (Thay cho i_instr[19:15])
    
    // ==========================================
    // 4. ĐIỀU KHIỂN ĐỌC/GHI CSR
    // ==========================================
    input  wire [11:0] i_csr_addr,       // Bỏ ex_
    input  wire        i_csr_write,      // Bỏ ex_
    input  wire        i_csr_read,       // Bỏ ex_
    input  wire [2:0]  i_csr_op,         // MỞ RỘNG 3-BIT: Lấy luôn func3 để chứa cờ use_zimm
    input  wire        i_is_mret,        // Bỏ ex_
    
    // ==========================================
    // 5. OUTPUT CHUYỂN HƯỚNG LUỒNG VÀ DỮ LIỆU
    // ==========================================
    output wire [31:0] o_csr_data,      
    output wire [31:0] o_csr_pc,        
    output wire        o_csr_pc_sel     
);
    `include "riscv_core_defines.vh"
    // THANH GHI CSR
    reg [31:0] mstatus, mie, mtvec, mepc, mcause, mscratch, mtval;
    
    wire [31:0] mip = {20'd0, i_ext_irq, 3'd0, i_timer_irq, 7'd0}; 
    reg  [31:0] r_csr_rdata;

    // =========================================================================
    // 1. LOGIC ĐỌC CSR (TỔ HỢP)
    // =========================================================================
    always @(*) begin
        if (i_csr_read || i_csr_write) begin
            case (i_csr_addr)
                12'h300: r_csr_rdata = mstatus;
                12'h304: r_csr_rdata = mie;
                12'h305: r_csr_rdata = mtvec;
                12'h340: r_csr_rdata = mscratch;
                12'h341: r_csr_rdata = mepc;
                12'h342: r_csr_rdata = mcause;
                12'h343: r_csr_rdata = mtval;
                12'h344: r_csr_rdata = mip;
                default: r_csr_rdata = 32'd0;
            endcase
        end else begin
            r_csr_rdata = 32'd0;
        end
    end
    assign o_csr_data = r_csr_rdata;

    // =========================================================================
    // TÍNH TOÁN DỮ LIỆU GHI CSR (TINH GỌN KHÔNG CẦN i_instr)
    // =========================================================================
    wire        w_use_zimm   = i_csr_op[2];                 // Bit 14 của lệnh
    wire [31:0] w_zimm_data  = {27'd0, i_rs1_addr};         // rs1_addr thay cho bit 19:15
    wire [31:0] w_actual_rs1 = w_use_zimm ? w_zimm_data : i_rs1_data; 
    
    reg [31:0] w_next_csr_data;
    always @(*) begin
        case (i_csr_op[1:0])
            2'b01:   w_next_csr_data = w_actual_rs1;                   // CSRRW / CSRRWI
            2'b10:   w_next_csr_data = r_csr_rdata | w_actual_rs1;     // CSRRS / CSRRSI
            2'b11:   w_next_csr_data = r_csr_rdata & ~w_actual_rs1;    // CSRRC / CSRRCI
            default: w_next_csr_data = w_actual_rs1;
        endcase
    end

    // =========================================================================
    // 2. YÊU CẦU TRAP THÔ
    // =========================================================================
    wire w_is_ext_irq = mip[11] & mie[11] & mstatus[3]; 
    wire w_is_tmr_irq = mip[7]  & mie[7]  & mstatus[3]; 
    
    assign o_int_req = (w_is_ext_irq | w_is_tmr_irq) & i_valid;
    assign o_exc_req = (i_is_ecall | i_is_ebreak | i_illegal_instr | i_bus_error) & i_valid;

    wire w_mret_valid = i_is_mret & i_valid;

    assign o_csr_pc_sel = i_trap_taken | w_mret_valid;
    assign o_csr_pc     = (i_trap_taken) ? {mtvec[31:2], 2'b00} : 
                          (w_mret_valid) ? mepc  : 32'd0;

    // =========================================================================
    // 3. LOGIC GHI CSR & TRẠNG THÁI (TUẦN TỰ)
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            mstatus  <= 32'd0; mie      <= 32'd0;
            mtvec    <= 32'd0; mepc     <= 32'd0;
            mcause   <= 32'd0; mscratch <= 32'd0;
            mtval    <= 32'd0;
        end else begin

            if (i_trap_taken) begin
                if (o_exc_req) begin
                    mepc  <= i_pc; 
                    if (i_illegal_instr) begin
                        mcause <= 32'd2;
                        mtval  <= i_instr;
                    end else if (i_is_ebreak) begin
                        mcause <= 32'd3;
                        mtval  <= i_pc;
                    end else if (i_bus_error) begin
                        mcause <= (i_mem_write) ? 32'd7 : 32'd5;
                        mtval  <= i_alu_result;
                    end else if (i_is_ecall) begin
                        mcause <= 32'h0000_000B;
                        mtval  <= 32'd0;
                    end else begin
                        mcause <= 32'd0;
                        mtval  <= 32'd0;
                    end
                end else begin
                    mepc  <= i_next_commit_pc; 
                    mtval <= 32'd0;
                    if (w_is_ext_irq)      mcause <= 32'h8000_000B;
                    else if (w_is_tmr_irq) mcause <= 32'h8000_0007;
                end

                mstatus[7] <= mstatus[3]; 
                mstatus[3] <= 1'b0;       
                
            end else if (w_mret_valid) begin
                mstatus[3] <= mstatus[7]; 
                mstatus[7] <= 1'b1;       
                
            end else if (i_csr_write && i_valid) begin 
                case (i_csr_addr)
                    12'h300: mstatus  <= w_next_csr_data;
                    12'h304: mie      <= w_next_csr_data;
                    12'h305: mtvec    <= w_next_csr_data;
                    12'h340: mscratch <= w_next_csr_data;
                    12'h341: mepc     <= w_next_csr_data;
                    12'h342: mcause   <= w_next_csr_data;
                    12'h343: mtval    <= w_next_csr_data;
                    default: ;
                endcase
            end
        end
    end


endmodule