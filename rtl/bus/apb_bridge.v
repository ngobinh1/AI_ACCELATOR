`timescale 1ns / 1ps

module apb_bridge (
    input  wire        i_clk,
    input  wire        i_rst_n,

    // =======================================================
    // 1. INTERFACE NỐI VỚI LÕI CPU (DATAPATH & HAZARD)
    // =======================================================
    input  wire        i_bus_read,      // Tín hiệu báo đọc (từ stage_ex)
    input  wire [3:0]  i_bus_wstrb,     // Byte Enable ghi (từ stage_ex, nếu = 0 là không ghi)
    input  wire [31:0] i_addr,          // Địa chỉ từ ALU kết quả
    input  wire [31:0] i_wdata,         // Dữ liệu ghi từ RS2
    
    output wire [31:0] o_cpu_rdata,     // Dữ liệu đọc trả về CPU
    output wire        o_dmem_ready,    // Tín hiệu bắt tay -> Nối thẳng vào i_dmem_ready của Hazard Unit
    output wire        o_bus_error,     // Báo lỗi Bus nếu ngoại vi bị sập (slverr)

    // =======================================================
    // 2. INTERFACE CHUẨN BUS APB Ngoại vi (APB INTERCONNECT)
    // =======================================================
    output reg  [31:0] o_apb_paddr,
    output reg         o_apb_pwrite,
    output reg  [3:0]  o_apb_pstrb,    
    output reg         o_apb_psel,
    output reg         o_apb_penable,
    output reg [31:0]  o_apb_pwdata,
    
    input  wire [31:0] i_apb_prdata,   
    input  wire        i_apb_pready,    // Tín hiệu báo sẵn sàng từ ngoại vi UART/GPIO
    input  wire        i_apb_pslverr    // Tín hiệu báo lỗi phần cứng từ ngoại vi
);
    `include "riscv_core_defines.vh"
    // Dữ liệu đọc được map thẳng từ bus APB về CPU [cite: 321]
    assign o_cpu_rdata = i_apb_prdata;

    // Tự động phát hiện yêu cầu giao tiếp Bus (Request)
    wire w_bus_req = i_bus_read | (i_bus_wstrb != 4'b0000);

    // Định nghĩa máy trạng thái APB tiêu chuẩn
    localparam S_IDLE   = 2'd0;
    localparam S_SETUP  = 2'd1;
    localparam S_ACCESS = 2'd2;

    reg [1:0] r_state, r_next;

    // 1. Cập nhật trạng thái tuần tự [cite: 324-326]
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) r_state <= S_IDLE;
        else          r_state <= r_next;
    end

    // 2. Tính toán trạng thái kế tiếp (Combinational FSM) [cite: 327]
    always @(*) begin
        r_next = r_state;
        case (r_state)
            S_IDLE: begin
                if (w_bus_req) r_next = S_SETUP;  // Có yêu cầu thì vào Phase Setup ngay
            end
            
            S_SETUP: begin
                r_next = S_ACCESS; // Chỉ nằm ở SETUP đúng 1 chu kỳ, sau đó qua ACCESS
            end
            
            S_ACCESS: begin
                if (i_apb_pready)  r_next = S_IDLE;   // Ngoại vi phản hồi xong -> Trở về IDLE
                else               r_next = S_ACCESS; // Chưa xong thì đứng đợi (Wait State)
            end
            
            default: r_next = S_IDLE;
        endcase
    end

    // =========================================================================
    // CƠ CHẾ BẮT TAY (HANDSHAKING) ĐỒNG BỘ VỚI HAZARD UNIT
    // =========================================================================
    // - Khi Bus ở trạng thái rảnh (S_IDLE) và KHÔNG có yêu cầu mới: o_dmem_ready = 1 (CPU chạy tự do).
    // - Khi Bus đang bận xử lý (S_SETUP hoặc S_ACCESS chưa xong): o_dmem_ready = 0 (Ép Hazard Unit phát lệnh Stall).
    // - Khi Bus ở chu kỳ ACCESS CUỐI CÙNG và ngoại vi báo xong (i_apb_pready = 1): o_dmem_ready = 1 (Nhả Stall).
    assign o_dmem_ready = (r_state == S_IDLE && !w_bus_req) || (r_state == S_ACCESS && i_apb_pready);

    // =========================================================================
    // 3. LOGIC ĐIỀU KHIỂN CÁC TÍN HIỆU APB BUS (Ghi tuần tự tránh Glitch) [cite: 334]
    // =========================================================================
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            o_apb_psel    <= 1'b0;
            o_apb_penable <= 1'b0;
            o_apb_paddr   <= 32'd0;
            o_apb_pwrite  <= 1'b0;
            o_apb_pstrb   <= 4'b0000;
            o_apb_pwdata  <= 32'd0;
        end else begin
            case (r_next)
                S_IDLE: begin
                    o_apb_psel    <= 1'b0;
                    o_apb_penable <= 1'b0;
                end
                
                S_SETUP: begin
                    o_apb_psel    <= 1'b1;         // Kích hoạt chọn ngoại vi
                    o_apb_penable <= 1'b0;         // Chưa bật enable ở phase setup
                    o_apb_paddr   <= i_addr;       // Đưa địa chỉ ALU ra Bus [cite: 338]
                    o_apb_pwrite  <= (i_bus_wstrb != 4'b0000); // Xác định hướng ghi [cite: 339]
                    o_apb_pstrb   <= i_bus_wstrb;  // Cấp mask write [cite: 340]
                    o_apb_pwdata  <= i_wdata;      // Đưa dữ liệu ghi ra Bus [cite: 341]
                end
                
                S_ACCESS: begin
                    o_apb_psel    <= 1'b1;
                    o_apb_penable <= 1'b1;         // Bật Enable để hoàn tất bắt tay APB [cite: 343]
                end
                
                default: begin
                    o_apb_psel    <= 1'b0;
                    o_apb_penable <= 1'b0;
                end
            endcase
        end
    end

    // Phát hiện lỗi phần cứng (ví dụ đọc/ghi nhầm địa chỉ cấm của ngoại vi) [cite: 344]
    assign o_bus_error = (r_state == S_ACCESS) && i_apb_pready && i_apb_pslverr;

endmodule