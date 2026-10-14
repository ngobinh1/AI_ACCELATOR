# RISC-V IoT & AI Accelerator Core

[![Language](https://img.shields.io/badge/Language-Verilog--2001-blue.svg)](#)
[![ISA](https://img.shields.io/badge/ISA-RV32IC__Zicsr__M%20%2B%20SIMD-green.svg)](#)
[![Simulator](https://img.shields.io/badge/Simulator-QuestaSim%20%7C%20Verilator-orange.svg)](#)
[![Technology](https://img.shields.io/badge/PDK-SkyWater%20130nm-red.svg)](#)
[![Verification](https://img.shields.io/badge/Regression-9%2F9%20PASS%20(100%25)-brightgreen.svg)](#)

Lõi vi xử lý RISC-V 32-bit hiệu năng cao với kiến trúc đường ống 3 tầng tuyến tính (**3-Stage Linear Pipeline**), tích hợp bộ nhân tuần tự Radix-16 8 chu kỳ (RV32M), bộ tăng tốc AI Packed SIMD 4x INT8 1 chu kỳ (`smdot.i8`), bộ giải nén tập lệnh nén 16-bit RV32C, khối CSR Machine-Mode tích hợp mô hình bẫy ngắt an toàn, bộ nhớ nội bộ 2KB Dual-Port SRAM SkyWater 130nm có bảo vệ biên phần cứng, và cầu nối bus AMBA 4 APB Master hỗ trợ wait-states dành cho các ứng dụng Edge IoT và AI Accelerator.

---

## 🌟 Tính Năng Nổi Bật (Key Features)

- **Tập lệnh hoàn chỉnh (ISA):**
  - **RV32I Base Integer:** Đầy đủ 40 lệnh số nguyên cơ bản (Arithmetic, Logic, Shifts, Branches, Jumps, Sub-word Memory Access).
  - **RV32M Extension:** 4 lệnh nhân phần cứng 32x32 (`MUL`, `MULH`, `MULHSU`, `MULHU`). Các lệnh chia/lấy dư (`DIV/REM`) được bẫy chính xác thành ngoại lệ Illegal Instruction (`mcause = 2`).
  - **RV32C Extension:** Bộ giải nén song song `rvc_decompressor` kết hợp hàng đợi đệm Prefetch FIFO 2-word, nạp và thực thi trực tiếp các lệnh nén 16-bit.
  - **Zicsr Privileged Extension:** Hệ thống thanh ghi Machine-Mode CSR đầy đủ (`mstatus`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, `mvendorid`, `marchid`, `mimpid`, `mhartid`).
  - **Custom Packed SIMD 4x INT8 (`smdot.i8`):** Thực hiện 4 phép nhân số nguyên 8-bit có dấu và cộng dồn cây nhị phân trong **1 chu kỳ clock duy nhất**, tăng tốc suy luận mạng nơ-ron sâu gấp **11.85 lần**.

- **Đường ống 3 tầng tuyến tính (3-Stage Decoupled Pipeline):**
  - **Tầng 1 (IF - Instruction Fetch):** Quản lý PC, Prefetch FIFO 2-word, giải mã lệnh nén RVC và thanh ghi địa chỉ chuyển hướng rẽ nhánh 2 chu kỳ (`r_redirect_target`).
  - **Tầng 2 (ID/EX - Instruction Decode & Execute):** Giải mã lệnh, đọc tập thanh ghi bất đồng bộ (Async Read Register File), sinh số tức thời Imm Gen, tính toán ALU (bộ cộng chia sẻ 33-bit), bộ nhân tuần tự Radix-16 8 chu kỳ, khối SIMD MAC, bộ so sánh nhánh tức thời và phát hiện xung đột sớm.
  - **Tầng 3 (MEM/WB - Memory Access & Write-Back):** Căn chỉnh dữ liệu đọc/ghi (Load/Store Align), sinh mặt nạ byte `be_gen`, giao tiếp SRAM Port 0, cầu nối bus AMBA 4 APB Master, khối CSR Unit và bộ chọn ghi trả Write-Back MUX (`w_wb_data`).

- **Cơ chế Chuyển tiếp Dữ liệu & Quản lý Xung đột:**
  - **Single-Stage Forwarding Unit:** Chuyển tiếp trực tiếp dữ liệu ghi trả hoàn chỉnh `w_wb_data` từ Tầng 3 về Tầng 2, giải quyết toàn diện kết quả ALU, dữ liệu Load, kết quả Nhân, dữ liệu CSR và địa chỉ JAL link `PC+4`.
  - **Khóa an toàn bộ nhân (Multiplier Stall Gating):** Khóa kích hoạt bộ nhân khi gặp xung đột Load-to-Use stall, ngăn ngừa chốt sai toán hạng nạp.
  - **Khử vòng lặp tổ hợp APB:** Điều khiển bus request độc lập với tín hiệu bẫy ngoại lệ (`o_mem_en = ~i_exc_req`), đạt **0 cảnh báo UNOPTFLAT** trên Verilator.

- **Mô hình Bẫy Ngắt An Toàn (Safe Trap & Interrupt Commit Model):**
  - **Ngắt bất đồng bộ (Async IRQ):** Cho phép lệnh hiện tại tại Tầng 3 commit hoàn tất (`o_wb_en = 1`), lưu `mepc = PC+4`, và xóa các tầng trước. Ngắt chỉ được chấp nhận khi lệnh Tầng 3 hợp lệ (`i_valid = 1`), không bẫy ngắt trên bong bóng NOP.
  - **Ngoại lệ đồng bộ (Sync Exception):** Ngắt bỏ ghi trả Tầng 3 (`o_wb_en = 0`), lưu `mepc = PC` của lệnh gây lỗi.
  - **Bộ đồng bộ hóa 2 tầng Flip-Flop (`sync_2ff`):** Đồng bộ hóa an toàn chống siêu ổn định cho `i_ext_irq` và `i_timer_irq`.

- **Hệ thống Bộ nhớ & Bus Ngoại vi:**
  - **Internal SRAM (2KB):** Macro OpenRAM SkyWater 130nm Dual-Port 1RW1R (`sky130_sram_2kbyte_1rw1r_32x512_8`).
  - **Hardware 2KB Bounds Check:** Mạch giám sát địa chỉ phần cứng phát hiện truy cập SRAM ngoài biên 2KB (`addr >= 2048` không thuộc MMIO) và phát sinh ngoại lệ Load/Store Access Fault (`mcause = 5 / 7`), lưu địa chỉ vi phạm vào `mtval`.
  - **AMBA 4 APB Master Bridge:** FSM 3 trạng thái (`S_IDLE`, `S_SETUP`, `S_ACCESS`), hỗ trợ wait-states (`i_apb_pready`), báo lỗi slave (`i_apb_pslverr`) và mặt nạ byte `o_apb_pstrb`.

---

## 📁 Cấu Trúc Thư Mục (Project Layout)

```
RISCV_IOT_AIACCELATOR/
├── rtl/                                  # Mã nguồn phần cứng (RTL Design)
│   ├── defines/                          # Định nghĩa Opcodes, Constants & Localparams
│   │   └── riscv_core_defines.vh
│   ├── core/                             # Lõi CPU và các module Pipeline
│   │   ├── core_top.v                    # Top-level Module lõi riscv_core_top
│   │   ├── stage_if.v                    # Tầng 1: Instruction Fetch, FIFO & RVC
│   │   ├── pipe_reg_if_id.v              # Thanh ghi ngăn cách Tầng 1 -> Tầng 2
│   │   ├── stage_id_ex.v                 # Tầng 2: Decode & Execute Datapath
│   │   ├── pipe_reg_ex_mem.v             # Thanh ghi ngăn cách Tầng 2 -> Tầng 3
│   │   ├── stage_mem_wb.v                # Tầng 3: Memory Access & Write-Back MUX
│   │   ├── instruction_decoder.v         # Bộ giải mã lệnh RV32I/M, SIMD & CSR
│   │   ├── register_file.v               # Tập thanh ghi 32x32-bit (x0 - x31)
│   │   ├── imm_gen.v                     # Bộ sinh Immediate (I, S, B, U, J)
│   │   ├── alu.v                         # ALU 32-bit với bộ cộng chia sẻ 33-bit
│   │   ├── booth_multiplier_32b.v        # Bộ nhân Radix-16 8 chu kỳ Shift-Add
│   │   ├── simd_mac_unit.v               # Bộ tăng tốc Packed SIMD 4x INT8 (smdot.i8)
│   │   ├── branch_comparator.v           # Bộ đánh giá điều kiện rẽ nhánh
│   │   ├── forwarding_unit.v             # Khối chuyển tiếp dữ liệu Single-Stage
│   │   ├── hazard_unit.v                 # Khối điều phối xung đột, Stall/Flush & Trap
│   │   ├── csr.v                         # Khối Machine-Mode CSR & Trap Controller
│   │   ├── sync_2ff.v                    # Bộ đồng bộ hóa ngắt ngoài 2 tầng Flip-Flop
│   │   ├── rvc_decompressor.v            # Bộ giải mã lệnh nén 16-bit RV32C
│   │   ├── be_gen.v                      # Khối sinh mặt nạ byte Byte-Enable Mask
│   │   ├── st_align.v                    # Khối căn chỉnh dữ liệu ghi (Store Align)
│   │   └── load_align.v                  # Khối căn chỉnh & mở rộng dữ liệu đọc (Load Align)
│   ├── bus/                              # Giao tiếp Bus ngoại vi
│   │   └── apb_bridge.v                  # Cầu nối chuẩn AMBA 4 APB Master
│   └── memory/                           # Mô hình bộ nhớ nội bộ
│       └── sky130_sram_2kbyte_1rw1r_32x512_8.v  # Macro SRAM 2KB OpenRAM Sky130
├── tb/                                   # Hệ thống Testbench kiểm chứng (9 Testbenches)
│   ├── tb_bubble_sort.v                  # Testbench thực thi firmware Bubble Sort
│   ├── tb_phase2_math_ai.v               # Testbench kiểm chứng Multiplier & SIMD MAC
│   ├── tb_phase3_hazards.v               # Testbench kiểm chứng Load-use & Branch penalty
│   ├── tb_rvc_decompressor.v             # Testbench kiểm chứng giải mã lệnh nén 16-bit
│   ├── tb_rvc_pipeline.v                 # Testbench kiểm chứng thực thi xen kẽ RVC
│   ├── tb_ai_benchmark.v                 # Testbench đo lường hiệu năng AI Kernel
│   ├── tb_phase5_datapath_p0.v           # Testbench nghiệm thu đóng kín 4 lỗi Datapath P0
│   ├── tb_phase6_control_traps.v         # Testbench nghiệm thu bẫy ngắt & APB P0
│   └── tb_isa_compliance.v               # Testbench kiểm chứng toàn bộ tập lệnh RV32I
├── firmware/                             # Phần mềm nhúng C / Assembly
│   ├── Start.S                           # Khởi tạo Stack, Trap Vector và dọn BSS
│   ├── bublesoft.c                       # Thuật toán sắp xếp nổi bọt (Bubble Sort)
│   ├── link.ld                           # Linker script cấu hình bộ nhớ cấp phát động
│   ├── firmware.elf                      # Tệp thực thi nhị phân ELF
│   ├── firmware.asm                      # Tệp mã máy dịch ngược (Disassembly)
│   └── memfile.hex                       # Tệp mã máy Hex nạp vào SRAM mô phỏng
├── config.json                           # Cấu hình Tape-out Physical OpenLane Sky130
├── riscv_core_top.sdc                    # Ràng buộc thời gian SDC (12.0 ns target)
├── Makefile                              # Tệp tự động hóa build & simulation suite
├── SPEC.md                               # Đặc tả kiến trúc RTL hoàn chỉnh (V3.0)
└── README.md                             # Tài liệu hướng dẫn sử dụng và báo cáo tổng quan
```

---

## 🛠️ Yêu Cầu Môi Trường (Prerequisites)

Để biên dịch firmware, chạy mô phỏng và PnR vật lý, hệ thống cần:
- **RISC-V GNU Toolchain:** `riscv64-unknown-elf-gcc`, `objcopy`, `objdump` (hỗ trợ `-march=rv32ic_zicsr`).
- **Bộ mô phỏng HDL (Simulator):** Siemens QuestaSim / ModelSim (`vlog`, `vsim`, `vlib`, `vmap`).
- **Bộ kiểm tra tĩnh mã nguồn (Linter):** Verilator (phiên bản >= 5.024).
- **Bộ công cụ thiết kế vật lý ASIC:** OpenLane v2 (OpenROAD, Yosys, Magic, KLayout) cùng SkyWater 130nm PDK.

---

## 🚀 Hướng Dẫn Sử Dụng (Quick Start)

Dự án cung cấp file [Makefile](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/Makefile) quản lý tập trung toàn bộ các tác vụ:

### 1. Xem danh sách lệnh hỗ trợ
```bash
make help
```

### 2. Biên dịch Firmware C/Assembly
Biên dịch chương trình C và Assembly thành file ELF, file Disassembly `.asm` và file Verilog Hex `.hex` với cờ căn chỉnh loop và hàm:
```bash
make firmware
# hoặc lệnh rút gọn:
make fw
```

### 3. Chạy Mô Phỏng Firmware Bubble Sort (Batch Mode)
Biên dịch RTL, Testbench và chạy thuật toán sắp xếp mảng:
```bash
make sim
```

### 4. Chạy Toàn Bộ Bộ Kiểm Chứng Hồi Quy (9 Testbenches)
Chạy tự động toàn bộ 9 testbench kiểm chứng chức năng:
```bash
make sim-all
```

### 5. Chạy Từng Testbench Chuyên Biệt
```bash
make sim-phase5    # Kiểm tra đóng kín lỗi Datapath P0-1 .. P0-4
make sim-phase6    # Kiểm tra bẫy ngắt P0-5, APB P0-6, DIV trap P0-7, EBREAK, mtval, Bounds check
make sim-isa       # Kiểm tra 31 test cases tập lệnh cơ sở RV32I (LUI, AUIPC, Shifts, Logic, SLT, Branch, Sub-word Mem)
```

### 6. Chạy Mô Phỏng Giao Diện Đồ Họa (GUI Mode với Waveform)
```bash
make sim-gui
```

### 7. Kiểm Tra Cú Pháp & Linting Tĩnh (Verilator)
Kiểm tra tĩnh trên 24 module RTL không còn cờ tắt cảnh báo `-Wno-UNOPTFLAT`:
```bash
make lint
```

### 8. Dọn Dẹp File Tạm
```bash
make clean        # Dọn dẹp artifacts mô phỏng (work, log, wlf)
make clean-all    # Dọn dẹp toàn bộ (bao gồm firmware binaries)
```

---

## 📊 Kết Quả Mô Phỏng Thực Tế (Simulation Benchmark)

Thuật toán sắp xếp nổi bọt mảng 10 phần tử `{42, 15, 77, 8, 23, 57, 86, 11, 43, 64}` đạt kết quả đo lường thực tế:

```text
========================================
   BAT DAU MO PHONG BUBBLE SORT CORE    
========================================
[TB] Phat hien my_array tai word index mem[44] (byte addr 0x0b0)
 -> Swap lan 1:  [15, 15, 77, 8, 23, 57, 86, 11, 43, 64]
 -> Swap lan 2:  [15, 42, 77, 8, 23, 57, 86, 11, 43, 64]
 ...
 -> Swap lan 44: [8, 11, 15, 23, 42, 43, 57, 64, 77, 86]
 -> Ket qua cuoi cung: [8, 11, 15, 23, 42, 43, 57, 64, 77, 86]
[TEST PASSED] Bubble Sort thanh cong, mang duoc sap xep hoan hao!

========================================
    PHAT HIEN CHUONG TRINH HOAN TAT     
-> Core da dung tai infinity_loop (PC = 0x32)
========================================
        PERFORMANCE REPORT              
========================================
 1. Total Clock Cycles     : 470
 2. Total Instructions     : 344
 3. Total Branch Taken     : 72
 4. Branch Mispredictions  : 38
----------------------------------------
 -> CPI (Cycles/Instr)     : 1.366
 -> IPC (Instr/Cycle)      : 0.732
========================================
```

---

## 📖 Tài Liệu Kiến Trúc Tham Khảo (Documentation)
Mọi chi tiết về cấu trúc phần cứng từng tầng, sơ đồ khối 22 sub-modules, bảng chân tín hiệu 8 cột, phương trình logic, giản đồ thời gian và ma trận truy xuất yêu cầu RTM vui lòng tham khảo tài liệu [SPEC.md](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/SPEC.md).
