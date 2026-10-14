.section .init
    .global _start

_start:
    # 1. Nạp Stack cho User (Dành cho các hàm C bình thường)
    la sp, _user_stack_top

    # 2. Nạp Stack cho Kernel (Dành cho quá trình cất Context khi có Ngắt/Lỗi)
    la t0, _kernel_stack_top
    csrw mscratch, t0

    # ========================================================
    # NÂNG CẤP: Thiết lập địa chỉ nhảy tới khi xảy ra Ngắt/Lỗi
    # ========================================================
    la t0, default_trap_handler
    csrw mtvec, t0

    # 3. Vòng lặp dọn dẹp vùng .bss thành các số 0
    la t0, _sbss      # Lấy địa chỉ bắt đầu bss
    la t1, _ebss      # Lấy địa chỉ kết thúc bss
    
clear_bss_loop:
    bge t0, t1, bss_done # Nếu quét hết vùng thì thoát
    sw zero, 0(t0)       # Ghi số 0 vào RAM
    addi t0, t0, 4       # Nhảy sang ô tiếp theo
    j clear_bss_loop

bss_done:
    # 4. Nhảy vào chương trình C
    call main

    # ========================================================
    # NÂNG CẤP: Bẫy an toàn khi main() kết thúc
    # ========================================================
infinity_loop:
    j infinity_loop      # Chống trôi PC khi chương trình C return

# ========================================================
# TRAP HANDLER MẶC ĐỊNH (Xử lý Ngoại lệ / Ngắt)
# ========================================================
.align 4
default_trap_handler:
    # Trong môi trường RTOS thực tế, đoạn này sẽ lưu thanh ghi vào Stack.
    # Còn ở bước mô phỏng này, nếu có lỗi phần cứng (Bus Error, Illegal Instr), 
    # ta cho CPU kẹt tại đây để dễ dàng nhìn thấy lỗi trên Waveform.
    j default_trap_handler