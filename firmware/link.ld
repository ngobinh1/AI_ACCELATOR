MEMORY
{
    /* Bóp lại đúng 2KB (2048 bytes) cho khớp với SRAM Sky130 */
    MEM (rwx) : ORIGIN = 0x00000000, LENGTH = 2K
}

SECTIONS
{
    /* 1. Vùng chứa Mã lệnh (Code) */
    .text : { 
        *(.init)      /* ÉP BUỘC đoạn khởi động phải nằm ở ĐẦU TIÊN (0x000) */
        *(.text*)     /* Các hàm C (main, logic...) nằm theo sau */
        . = ALIGN(4); 
    } > MEM

    /* 2. Vùng chứa Hằng số (Read-only data) */
    .rodata : {
        *(.rodata*)
        *(.srodata*)  
        . = ALIGN(4);
    } > MEM

    /* 3. Vùng chứa Biến toàn cục có sẵn giá trị (Cấp phát động căn lề 4 bytes) */
    .data : ALIGN(4) { 
        _sdata = .;
        _my_array_start = .;
        *(.data*) 
        *(.sdata*)    
        . = ALIGN(4); 
        _edata = .;
    } > MEM

    /* 4. Vùng chứa Biến toàn cục khởi tạo bằng 0 (.bss) */
    .bss : { 
        /* CẮM MỐC BẮT ĐẦU VÙNG BSS */
        _sbss = .;    

        *(.bss*)  
        *(.sbss*)
        . = ALIGN(4); 

        /* CẮM MỐC KẾT THÚC VÙNG BSS */
        _ebss = .;    
    } > MEM
    
    /* ======================================================== */
    /* 5. QUY HOẠCH NGĂN XẾP (STACK) TRÊN SÀN 2KB               */
    /* ======================================================== */
    
    /* Kernel Stack: Nằm ở đỉnh RAM (0x0800). */
    _kernel_stack_top = ORIGIN(MEM) + LENGTH(MEM); 
    
    /* User Stack: Nằm dưới Kernel Stack.
       Chỉ cấp 384 bytes cho Kernel (thay vì 1024) để tiết kiệm RAM. 
       _user_stack_top sẽ bắt đầu từ 0x0800 - 0x0180 = 0x0680 */
    _user_stack_top = _kernel_stack_top - 384; 
}