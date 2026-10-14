`timescale 1ns / 1ps

module tb_bubble_sort;
    // ==========================================
    // 1. KHAI BÁO TÍN HIỆU
    // ==========================================
    reg clk;
    reg rst_n; 
    
    // Các biến phục vụ tính toán hiệu năng (Performance Metrics)
    integer total_cycles = 0;       
    integer branch_taken_count = 0; 
    integer branch_mispredict_count = 0;
    integer total_instructions = 0; 
    real    cpi = 0.0;              
    real    branch_acc = 0.0;
    integer swap_count = 0; 

    // Các dây dummy để nối vào chân ngoại vi APB
    wire [31:0] apb_paddr, apb_pwdata;
    wire [3:0]  apb_pstrb;
    wire        apb_pwrite, apb_psel, apb_penable;

    // ==========================================
    // 2. KHỞI TẠO LÕI RISC-V (DUT)
    // ==========================================
    riscv_core_top u_CPU (
        .i_clk         (clk),
        .i_rst_n       (rst_n),
        
        .i_ext_irq     (1'b0), 
        .i_timer_irq   (1'b0), 
        
        // Nối các tín hiệu APB Master ra dummy wires
        .o_apb_paddr   (apb_paddr),
        .o_apb_pwrite  (apb_pwrite),
        .o_apb_pstrb   (apb_pstrb),
        .o_apb_psel    (apb_psel),
        .o_apb_penable (apb_penable),
        .o_apb_pwdata  (apb_pwdata),
        
        // Trả về dữ liệu 0 và luôn báo Ready để tránh kẹt Bus
        .i_apb_prdata  (32'd0),   
        .i_apb_pready  (1'b1),
        .i_apb_pslverr (1'b0)
    );

    // ==========================================
    // 3. TẠO XUNG NHỊP VÀ NẠP FIRMWARE
    // ==========================================
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // Xung nhịp 100MHz
    end

    reg [1023:0] hex_file;
    initial begin
        // Nạp Firmware (File Hex)
        if (!$value$plusargs("HEX_FILE=%s", hex_file)) begin
            hex_file = "firmware/memfile.hex";
        end
        $readmemh(hex_file, u_CPU.u_sram_2kb.mem);
        
        $display("========================================");
        $display("   BAT DAU MO PHONG BUBBLE SORT CORE    ");
        $display("========================================");
        
        rst_n = 0;
        #20; 
        rst_n = 1;
        
        // Timeout chống treo[cite: 21]
        #1000000;
        $display("\n[LỖI] TIMEOUT: Chuong trinh chay qua lau!");
        $finish;
    end 

    integer arr_start_idx = 44;
    integer scan_i;
    reg [31:0] r_prev_pc = 32'hffffffff;
    integer    consecutive_same_pc = 0;
    integer    k;
    reg        is_sorted;

    initial begin
        #1;
        for (scan_i = 0; scan_i < 500; scan_i = scan_i + 1) begin
            if (u_CPU.u_sram_2kb.mem[scan_i] == 32'd42 && u_CPU.u_sram_2kb.mem[scan_i+1] == 32'd15) begin
                arr_start_idx = scan_i;
            end
        end
        $display("[TB] Phat hien my_array tai word index mem[%0d] (byte addr 0x%03h)", arr_start_idx, arr_start_idx * 4);
    end

    // ==========================================
    // 4. BỘ GIÁM SÁT VÀ PHÂN TÍCH HIỆU NĂNG 
    // ==========================================
   always @(posedge clk) begin
        if (rst_n == 1'b1) begin
            total_cycles = total_cycles + 1;
            
            // A. ĐẾM LỆNH THỰC THI (RETIRED)
            // Lệnh chỉ được tính là hoàn thành khi ở Tầng EX, có cờ Valid và không bị Stall
            if (u_CPU.w_id_ex_valid == 1'b1 && u_CPU.w_hz_stall_pipe == 1'b0) begin
                total_instructions = total_instructions + 1;

                if (u_CPU.w_id_ex_pc == r_prev_pc) begin
                    consecutive_same_pc = consecutive_same_pc + 1;
                end else begin
                    consecutive_same_pc = 0;
                    r_prev_pc = u_CPU.w_id_ex_pc;
                end
            end

            // Đếm số lần rẽ nhánh thành công (Branch/Jump)
            if (u_CPU.w_ex_branch_taken == 1'b1 && u_CPU.w_hz_stall_pipe == 1'b0) begin
                branch_taken_count = branch_taken_count + 1;
            end

            // Đếm số lần dự đoán sai nhánh (Branch Misprediction)
            if (u_CPU.w_ex_branch_mispredict == 1'b1 && u_CPU.w_hz_stall_pipe == 1'b0) begin
                branch_mispredict_count = branch_mispredict_count + 1;
            end

            // B. THEO DÕI TIẾN ĐỘ SẮP XẾP (Dựa vào địa chỉ lệnh Store khi Swap)
            if ((u_CPU.w_id_ex_pc == 32'h00000082 || u_CPU.w_id_ex_pc == 32'h0000007e || u_CPU.w_id_ex_pc == 32'h0000008c || u_CPU.w_id_ex_pc == 32'h0000007c) && u_CPU.w_id_ex_valid == 1'b1 && u_CPU.w_hz_stall_pipe == 1'b0) begin
                swap_count = swap_count + 1;
                
                if (swap_count > 1) begin
                    $display(" -> Swap lan %0d: [%0d, %0d, %0d, %0d, %0d, %0d, %0d, %0d, %0d, %0d]", 
                        (swap_count - 1), 
                        $signed(u_CPU.u_sram_2kb.mem[arr_start_idx]), $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 1]), 
                        $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 2]), $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 3]), 
                        $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 4]), $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 5]), 
                        $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 6]), $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 7]), 
                        $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 8]), $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 9])
                    );
                end
            end   
            
            // ========================================================
            // C. BẮT ĐIỀU KIỆN KẾT THÚC CHƯƠNG TRÌNH[cite: 21]
            // ========================================================
            if (((u_CPU.w_id_ex_pc == 32'h00000038 || u_CPU.w_id_ex_pc == 32'h00000032) || (consecutive_same_pc >= 5)) && u_CPU.w_id_ex_valid == 1'b1 && u_CPU.w_hz_stall_pipe == 1'b0) begin
                
                // In nốt trạng thái mảng hoàn hảo cuối cùng
                $display(" -> Ket qua cuoi cung: [%0d, %0d, %0d, %0d, %0d, %0d, %0d, %0d, %0d, %0d]", 
                    $signed(u_CPU.u_sram_2kb.mem[arr_start_idx]), $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 1]), 
                    $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 2]), $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 3]), 
                    $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 4]), $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 5]), 
                    $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 6]), $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 7]), 
                    $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 8]), $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 9])
                );

                // Kiểm tra tính đúng đắn của mảng đã sắp xếp
                is_sorted = 1'b1;
                for (k = 0; k < 9; k = k + 1) begin
                    if ($signed(u_CPU.u_sram_2kb.mem[arr_start_idx + k]) > $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + k + 1])) begin
                        is_sorted = 1'b0;
                    end
                end

                if (is_sorted && $signed(u_CPU.u_sram_2kb.mem[arr_start_idx]) == 8 && $signed(u_CPU.u_sram_2kb.mem[arr_start_idx + 9]) == 86) begin
                    $display("[TEST PASSED] Bubble Sort thanh cong, mang duoc sap xep hoan hao!");
                end else begin
                    $display("[TEST FAILED] Mang sap xep chua dung hoac du lieu loi!");
                end

                // --- Kết thúc và in báo cáo ---
                $display("\n========================================");
                $display("    PHAT HIEN CHUONG TRINH HOAN TAT     ");
                $display("-> Core da dung tai infinity_loop (PC = 0x%02h)", u_CPU.w_id_ex_pc);
                
                cpi = $itor(total_cycles) / $itor(total_instructions);                    
                
                $display("========================================");
                $display("        PERFORMANCE REPORT              ");
                $display("========================================");
                $display(" 1. Total Clock Cycles     : %0d", total_cycles);
                $display(" 2. Total Instructions     : %0d", total_instructions);
                $display(" 3. Total Branch Taken     : %0d", branch_taken_count);
                $display(" 4. Branch Mispredictions  : %0d", branch_mispredict_count);
                $display("----------------------------------------");
                $display(" -> CPI (Cycles/Instr)     : %0.3f", cpi);
                $display(" -> IPC (Instr/Cycle)      : %0.3f", 1.0/cpi);
                $display("========================================\n");                  
                
                $finish;
            end
        end
    end
endmodule