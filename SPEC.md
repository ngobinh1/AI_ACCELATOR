# ĐẶC TẢ THIẾT KẾ KIẾN TRÚC RTL
# TÊN HỆ THỐNG / IP CORE: `riscv_core_top`

---

## THÔNG TIN TÀI LIỆU
- **Tên dự án:** RISC-V 32-bit IoT & AI Accelerator Core (RV32IC_Zicsr + Packed SIMD INT8)
- **Mã tài liệu:** SPEC-RISCV-AIACCEL-V3.0
- **Chuẩn ngôn ngữ:** IEEE 1364-2001 (Verilog-2001) / IEEE 1800-2017 Synthesizable SystemVerilog
- **Mục tiêu công nghệ:** SkyWater 130nm Open PDK (`sky130_fd_sc_hd`) / OpenRAM Macro 2KB Dual-Port 1RW1R
- **Trạng thái:** APPROVED FOR RTL IMPLEMENTATION & TAPE-OUT SIGNOFF
- **Phiên bản:** 3.0.0
- **Ngày phát hành:** 2026-10-14

---

## MỤC LỤC
1. [CHƯƠNG 1: TỔNG QUAN HỆ THỐNG VÀ KIẾN TRÚC THIẾT KẾ](#chương-1-tổng-quan-hệ-thống-và-kiến-trúc-thiết-kế)
   - 1.1 Tổng quan về thiết kế
   - 1.2 Phân loại yêu cầu thiết kế (Requirement Classification)
   - 1.3 Đặc điểm kiến trúc & Đột phá tối ưu PPA
   - 1.4 Sơ đồ kiến trúc tổng quan (Architecture Overview)
   - 1.5 Bảng tham số kiến trúc (Design Parameters)
2. [CHƯƠNG 2: TOP MODULE – `riscv_core_top`](#chương-2-top-module--riscv_core_top)
   - 2.1 Sơ đồ khối Top Module (Top-Level Block Diagram)
   - 2.2 Bảng chân tín hiệu ngoại vi Top Module (External Interface Table)
   - 2.3 Nguyên lý hoạt động tổng thể & Mối quan hệ tương tác giữa các Sub-module
   - 2.4 Bảng kết nối nội bộ giữa các Sub-module (Internal Interconnect Table)
   - 2.5 Giản đồ thời gian tổng thể Top Module (Top-Level Timing Diagrams)
3. [CHƯƠNG 3: ĐẶC TẢ CHI TIẾT TỪNG SUB-MODULE](#chương-3-đặc-tả-chi-tiết-từng-sub-module)
   - 3.1 Module: `stage_if`
   - 3.2 Module: `pipe_reg_if_id`
   - 3.3 Module: `stage_id_ex`
   - 3.4 Module: `instruction_decoder`
   - 3.5 Module: `register_file`
   - 3.6 Module: `imm_gen`
   - 3.7 Module: `alu`
   - 3.8 Module: `booth_multiplier_32b`
   - 3.9 Module: `simd_mac_unit`
   - 3.10 Module: `branch_comparator`
   - 3.11 Module: `pipe_reg_ex_mem`
   - 3.12 Module: `stage_mem_wb`
   - 3.13 Module: `be_gen`
   - 3.14 Module: `st_align`
   - 3.15 Module: `load_align`
   - 3.16 Module: `forwarding_unit`
   - 3.17 Module: `hazard_unit`
   - 3.18 Module: `csr`
   - 3.19 Module: `sync_2ff`
   - 3.20 Module: `apb_bridge`
   - 3.21 Module: `rvc_decompressor`
   - 3.22 Module: `sky130_sram_2kbyte_1rw1r_32x512_8`
4. [CHƯƠNG 4: MA TRẬN TRUY XUẤT YÊU CẦU (RTM) & KẾ HOẠCH KIỂM CHỨNG](#chương-4-ma-trận-truy-xuất-yêu-cầu-rtm--kế-hoạch-kiểm-chứng)
   - 4.1 Ma trận truy xuất yêu cầu kiểm tra (Requirement Traceability Matrix - RTM)
   - 4.2 Chi tiết các Test Cases kiểm chứng chức năng (Functional Verification Plan)
   - 4.3 Kết quả kiểm chứng mô phỏng & Báo cáo độ phủ (Verification Scorecard)

---

# CHƯƠNG 1: TỔNG QUAN HỆ THỐNG VÀ KIẾN TRÚC THIẾT KẾ

## 1.1 Tổng quan về thiết kế

Lõi vi xử lý `riscv_core_top` là một IP Core vi xử lý 32-bit hoàn chỉnh, được tối ưu hóa cho các hệ thống nhúng thông minh Internet of Things (IoT) và các bộ tăng tốc tính toán trí tuệ nhân tạo tại biên (Edge AI / TinyML). Kiến trúc tuân thủ chuẩn tập lệnh RISC-V quốc tế với các đặc tả kỹ thuật:

1. **Bộ tập lệnh tích hợp:**
   - **RV32I Base Integer Instructions:** Đầy đủ 40 lệnh số nguyên cơ bản (Arithmetic, Logic, Shifts, Branches, Jumps, Loads, Stores, Upper Immediates).
   - **RV32M Standard Extension (Hardware Multiplier):** 4 lệnh nhân số học 32-bit có dấu và không dấu (`MUL`, `MULH`, `MULHSU`, `MULHU`). Các lệnh chia/lấy dư (`DIV`, `DIVU`, `REM`, `REMU`) không hỗ trợ phần cứng được bẫy chính xác thành ngoại lệ Illegal Instruction (`mcause = 2`).
   - **RV32C Standard Extension (Compressed Instructions):** Hỗ trợ toàn diện lệnh nén 16-bit thông qua bộ giải mã lệnh nén song song `rvc_decompressor` kết hợp hàng đợi đệm nạp lệnh 2-word Prefetch FIFO.
   - **Zicsr Privileged Extension:** Hệ thống thanh ghi Machine-Mode CSR (`mstatus`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`, `mvendorid`, `marchid`, `mimpid`, `mhartid`) cùng các lệnh điều khiển hệ thống (`CSRRW`, `CSRRS`, `CSRRC`, `CSRRWI`, `CSRRSI`, `CSRRCI`, `ECALL`, `EBREAK`, `MRET`, `WFI`).
   - **Custom Packed SIMD 4x INT8 Extension:** Lệnh tăng tốc chuyên dụng suy luận mạng nơ-ron sâu `smdot.i8` thực hiện tích vô hướng 4 phần tử số nguyên 8-bit có dấu trong 1 chu kỳ clock duy nhất.

2. **Kiến trúc đường ống 3 tầng tuyến tính (3-Stage Decoupled Pipeline):**
   - **Tầng 1 (IF - Instruction Fetch):** Quản lý con trỏ chương trình PC, hàng đợi đệm nạp lệnh Prefetch FIFO 2 từ nhớ (64-bit), bộ giải mã lệnh nén RVC 16-bit tức thời, và thanh ghi chuyển hướng rẽ nhánh 2 chu kỳ (`r_redirect_target`).
   - **Tầng 2 (ID/EX - Instruction Decode & Execute):** Giải mã lệnh đầy đủ, đọc tập thanh ghi bất đồng bộ 32x32 (Async Read Register File), sinh số tức thời đa định dạng Imm Gen, tính toán ALU với bộ cộng chia sẻ 33-bit, bộ nhân tuần tự 8 chu kỳ Radix-16 Shift-Add, khối tăng tốc SIMD MAC 4x INT8, bộ so sánh nhánh tức thời, và bộ phát hiện xung đột dữ liệu sớm.
   - **Tầng 3 (MEM/WB - Memory Access & Write-Back):** Giao tiếp bộ nhớ dữ liệu Port 0 của 2KB SRAM, khối căn chỉnh dữ liệu đọc/ghi (Load/Store Alignment), khối sinh mặt nạ byte (Byte Enable Gen), cầu nối bus ngoại vi AMBA 4 APB Master hỗ trợ wait-states, khối thanh ghi đặc quyền CSR Unit tích hợp mô hình bẫy ngắt commit an toàn, và bộ chọn ghi trả Write-Back MUX về Register File.

3. **Hệ thống bộ nhớ và bus ngoại vi:**
   - **Macro SRAM 2KB Dual-Port 1RW1R (`sky130_sram_2kbyte_1rw1r_32x512_8`):** Cho phép truy cập đồng thời Port 1 (đọc mã lệnh tại Tầng IF) và Port 0 (đọc/ghi dữ liệu tại Tầng MEM) mà không gây xung đột cấu trúc. Tích hợp mạch kiểm tra biên phần cứng 2KB (Hardware 2KB Bounds Check) phát hiện lỗi truy cập ngoài dải địa chỉ và kích hoạt ngoại lệ Access Fault.
   - **Cầu nối ngoại vi AMBA 4 APB Master (`apb_bridge`):** Chuyển đổi yêu cầu đọc/ghi trong không gian địa chỉ MMIO (`0x4000_0000` .. `0x40FF_FFFF`) thành giao thức APB hoàn chỉnh với 3 trạng thái FSM (`S_IDLE`, `S_SETUP`, `S_ACCESS`), hỗ trợ tín hiệu chờ `i_apb_pready`, phản hồi lỗi bus `i_apb_pslverr`, và mặt nạ byte `o_apb_pstrb`. Khử hoàn toàn vòng lặp tổ hợp (Combinational Feedback Loop) bằng cách ngắt bus request khi có ngoại lệ đồng bộ (`o_mem_en = ~i_exc_req`).

4. **Đồng bộ hóa ngắt và an toàn tín hiệu:**
   - Tín hiệu ngắt ngoài `i_ext_irq` và ngắt định thời `i_timer_irq` được bảo vệ bằng khối đồng bộ hóa 2 tầng Flip-Flop (`sync_2ff`) với thuộc tính chống siêu ổn định `ASYNC_REG = "TRUE"`.

---

## 1.2 Phân loại yêu cầu thiết kế (Requirement Classification)

**Bảng 1.1: Bảng phân loại yêu cầu thiết kế hệ thống (Requirement Classification)**

| Mã Yêu Cầu | Nhóm Chức Năng | Phân Loại | Chi Tiết Yêu Cầu Kỹ Thuật |
| :--- | :--- | :---: | :--- |
| `REQ-ISA-01` | RV32I Base Integer | `STANDARDS-COMPLIANT` | Hỗ trợ 100% tập lệnh RV32I Base Integer Instructions theo chuẩn RISC-V Unprivileged ISA Volume I v2.2. |
| `REQ-ISA-02` | RV32M Multiplier | `STANDARDS-COMPLIANT` | Hỗ trợ 4 lệnh nhân `MUL`, `MULH`, `MULHSU`, `MULHU`. Bẫy các lệnh `DIV`, `DIVU`, `REM`, `REMU` thành ngoại lệ Illegal Instruction (`mcause = 2`). |
| `REQ-ISA-03` | RV32C Compressed | `STANDARDS-COMPLIANT` | Hỗ trợ giải mã và thực thi lệnh nén 16-bit RV32C thông qua bộ giải mã song song `rvc_decompressor`. |
| `REQ-ISA-04` | Zicsr Privileged CSR | `STANDARDS-COMPLIANT` | Hỗ trợ hệ thống thanh ghi Machine-Mode CSR và các lệnh thao tác CSR theo chuẩn RISC-V Privileged Architecture Volume II v1.10. |
| `REQ-ISA-05` | Custom AI Extension | `CUSTOM-EXTENSION` | Hỗ trợ lệnh Packed SIMD 4x INT8 Dot-Product (`smdot.i8`) với mã hóa R-Type (`opcode=7'b0110011, funct3=3'b100, funct7=7'b0000100`). |
| `REQ-PIPE-01` | Pipeline Architecture | `ARCHITECTURAL` | Thiết kế đường ống 3 tầng tuyến tính (`stage_if`, `stage_id_ex`, `stage_mem_wb`) ngăn cách bởi hai thanh ghi `pipe_reg_if_id` và `pipe_reg_ex_mem`. |
| `REQ-PIPE-02` | Forwarding Architecture | `PERFORMANCE-OPT` | Khối chuyển tiếp dữ liệu Single-Stage Forwarding chuyển trực tiếp kết quả ghi trả tầng 3 (`w_wb_data`) về tầng 2, giải quyết triệt để dữ liệu JAL link `PC+4`, CSR, ALU, và Load. |
| `REQ-PIPE-03` | Branch Penalty | `PERFORMANCE-OPT` | Xử lý rẽ nhánh sai với tổn thất 2 chu kỳ clock thông qua thanh ghi địa chỉ chuyển hướng `r_redirect_target` tại tầng IF. |
| `REQ-MATH-01` | Multiplier Architecture | `HARDWARE-OPT` | Bộ nhân số học tuần tự 8 chu kỳ Radix-16 Shift-Add (4-bit/chu kỳ), tích hợp cổng khóa stall load-to-use (`w_mul_valid & i_valid & ~w_stall_load_use`). |
| `REQ-MATH-02` | SIMD MAC Unit | `PERFORMANCE-OPT` | Khối SIMD MAC thực hiện 4 phép nhân 8x8 có dấu và cây cộng 2 cấp trong 1 chu kỳ clock duy nhất. |
| `REQ-MEM-01` | Dual-Port SRAM | `MEMORY-SUBSYSTEM` | Tích hợp Macro 2KB Dual-Port SRAM OpenRAM Sky130 (Port 0: Data RW, Port 1: Instruction RO) truy cập song song không gây xung đột cấu trúc. |
| `REQ-MEM-02` | SRAM Bounds Check | `SECURITY-SAFETY` | Mạch kiểm tra địa chỉ phần cứng phát hiện truy cập SRAM vượt dải 2KB (`addr >= 2048` không thuộc MMIO) và phát sinh ngoại lệ Load/Store Access Fault (`mcause = 5 / 7`). |
| `REQ-MEM-03` | Data Alignment | `DATA-ALIGNMENT` | Hỗ trợ nạp và lưu dữ liệu Byte, Halfword, Word tự do với mở rộng dấu (`LB`, `LH`) và bù 0 (`LBU`, `LHU`). |
| `REQ-BUS-01` | AMBA 4 APB Bridge | `BUS-INTERFACE` | Triển khai cầu nối Master AMBA 4 APB với 3 trạng thái FSM (`S_IDLE`, `S_SETUP`, `S_ACCESS`), hỗ trợ wait-states (`i_apb_pready`) và mặt nạ byte `o_apb_pstrb`. |
| `REQ-BUS-02` | Combinational Loop Free | `RELIABILITY` | Khử bỏ hoàn toàn vòng lặp tổ hợp APB bằng cách tách biệt điều khiển ghi nhớ và bẫy ngoại lệ (`o_mem_en = ~i_exc_req`). |
| `REQ-CSR-01` | Trap Commit Model | `PRIVILEGED-SYSTEM` | Phân định rõ ràng: Ngắt bất đồng bộ cho phép Tầng 3 commit hoàn tất (`o_wb_en = 1`) và lưu `mepc = PC+4`; Ngoại lệ đồng bộ hủy ghi trả Tầng 3 (`o_wb_en = 0`) và lưu `mepc = PC`. |
| `REQ-CSR-02` | IRQ Bubble Gate | `PRIVILEGED-SYSTEM` | Ngắt bất đồng bộ bắt buộc phải được khóa bởi cờ hiệu lệnh hợp lệ `i_valid`, tuyệt đối không bẫy ngắt khi pipeline đang có bóng bóng NOP. |
| `REQ-CSR-03` | Vector Masking | `STANDARDS-COMPLIANT` | Thanh ghi `mtvec` ở chế độ Direct Mode (`mode = 2'b00`) bắt buộc xóa 2 bit thấp về 0 (`{mtvec[31:2], 2'b00}`). Thanh ghi `mtval` hỗ trợ đầy đủ quyền đọc/ghi. |
| `REQ-SYNC-01` | Interrupt Synchronizer | `CLOCK-DOMAIN-CROSSING` | Đồng bộ hóa 2 tầng Flip-Flop chống siêu ổn định cho các chân ngắt ngoài bất đồng bộ `i_ext_irq` và `i_timer_irq`. |
| `REQ-PHY-01` | Physical Signoff | `PHYSICAL-SIGNOFF` | Đạt chuẩn Sign-off OpenLane trên tiến trình SkyWater 130nm: WNS Setup >= 0, WNS Hold >= 0, 0 DRC violations. |

*Ghi chú: Toàn bộ 20 yêu cầu kỹ thuật trên được quản lý và kiểm chứng tự động qua Ma trận truy xuất yêu cầu RTM tại Chương 4.*

---

## 1.3 Đặc điểm kiến trúc & Đột phá tối ưu PPA

Kiến trúc lõi `riscv_core_top` được thiết kế tối ưu hóa hài hòa trên 3 phương diện PPA (Power - Performance - Area):

1. **Đột phá về Hiệu năng (Performance):**
   - **Bộ nhân Radix-16 Shift-Add 8 chu kỳ:** Tốc độ nhân tăng hơn gấp đôi so với bộ nhân lặp 17 chu kỳ truyền thống (giảm từ 17 chu kỳ xuống 8 chu kỳ), đồng thời tiết kiệm 70% diện tích so với bộ nhân tổ hợp 1 chu kỳ. Tích hợp cơ chế khóa interlock ngăn ngừa chốt sai toán hạng khi gặp xung đột Load-to-Use.
   - **Tăng tốc suy luận mạng nơ-ron với lệnh `smdot.i8`:** Thực hiện trọn vẹn 4 phép nhân INT8 và cộng dồn trong **1 chu kỳ clock**, mang lại tốc độ xử lý nhanh hơn **11.85 lần** so với chuỗi lệnh RV32I vô hướng.
   - **Tối ưu hóa đường ống 3 tầng tuyến tính:** Rút ngắn đường trễ tổ hợp (Critical Timing Path) tại tầng giải mã và thực thi, cho phép nâng tần số hoạt động lên **83.33 MHz** (chu kỳ xung nhịp 12.0 ns) trên tiến trình SkyWater 130nm.
   - **Tối ưu hóa biên dịch và căn chỉnh loop:** Thêm cờ biên dịch `-falign-loops=4 -falign-functions=4` kết hợp cấp phát động `.data`, giúp thuật toán Bubble Sort đạt hiệu năng vượt trội: **470 chu kỳ**, chỉ số **CPI = 1.366** (so với 496 chu kỳ và CPI = 1.485 trước tối ưu).

2. **Đột phá về Công suất tiêu thụ (Power Efficiency):**
   - **Khóa toán hạng động (Dynamic Operand Gating):** Tín hiệu điều khiển `o_alu_enable` tự động khóa toán hạng đầu vào của ALU khi lệnh hiện tại không yêu cầu tính toán số học, ngăn chặn chuyển mạch ký sinh trong mảng logic logic 33-bit và giảm đến 30% công suất động của ALU.
   - **Kiểm soát cổng xung nhịp bộ nhân:** Bộ nhân chỉ nhận xung và chuyển mạch khi có cờ `w_mul_valid & i_valid & ~w_stall_load_use`.

3. **Đột phá về Diện tích và Tái sử dụng Tài nguyên (Area Efficiency):**
   - **Mạch cộng/trừ 33-bit chia sẻ duy nhất:** Module `alu.v` sử dụng chung 1 bộ cộng 33-bit (`w_sum_res`) cho tất cả các phép toán `ADD`, `SUB`, so sánh có dấu `SLT` và không dấu `SLTU`, tiết kiệm hơn 45% cổng logic so với thiết kế dùng các khối số học rời rạc.
   - **Macro SRAM 2KB Dual-Port OpenRAM:** Cung cấp 2048 byte bộ nhớ nội bộ mật độ cao cho cả nạp lệnh và đọc/ghi dữ liệu, tích hợp mạch bảo vệ biên phần cứng.

**Bảng 1.2: So sánh chỉ tiêu PPA và hiệu năng giữa các phiên bản kiến trúc**

| Chỉ Tiêu Đánh Giá | Phiên Bản Cơ Sở (Phase 0) | Phiên Bản Sau Kiểm Toán & Tối Ưu (Phase 7/8) | Mức Độ Cải Thiện Đạt Được |
| :--- | :---: | :---: | :---: |
| **Cấu trúc đường ống (Pipeline)** | 2 tầng không hoàn chỉnh | **3 tầng tuyến tính (`IF`, `ID/EX`, `MEM/WB`)** | 🟢 Cấu trúc chuẩn công nghiệp |
| **Độ trễ bộ nhân `MUL/MULH`** | 17 chu kỳ clock (FSM lặp) | **8 chu kỳ clock (Radix-16 Shift-Add)** | 🚀 Nhanh hơn 2.12x |
| **Xung đột Load-to-Use -> MUL** | Sai kết quả (P0-3) | **Khóa an toàn 1 chu kỳ stall** | 🟢 Đúng 100% chức năng |
| **Cơ chế chuyển tiếp JAL Link rd** | Bị mất dữ liệu `PC+4` (P0-4) | **Chuyển tiếp đầy đủ `w_wb_data`** | 🟢 Đúng 100% chức năng |
| **Xử lý ngắt bất đồng bộ** | Mất lệnh Stage 3 (P0-5) | **Commit Stage 3 & lưu `mepc = PC+4`** | 🟢 Không mất lệnh |
| **Vòng lặp tổ hợp bus APB** | Kẹt vòng lặp (P0-6) | **Khử hoàn toàn vòng lặp tổ hợp** | 🟢 0 lỗi UNOPTFLAT Verilator |
| **Lệnh chia DIV/REM phần cứng** | Chạy sai thành ADD (P0-7) | **Bẫy ngoại lệ Illegal Instruction** | 🟢 Đúng chuẩn RISC-V |
| **Số chu kỳ thực thi Bubble Sort** | 496 chu kỳ | **470 chu kỳ** | 🚀 Giảm 26 chu kỳ (-5.2%) |
| **Chỉ số CPI (Bubble Sort)** | 1.485 CPI | **1.366 CPI** | 🚀 Cải thiện 8.0% IPC |
| **Số lượng Testbench vượt qua** | 6 testbench | **9/9 Testbenches (100% PASS)** | 🟢 Hoàn tất 100% kiểm chứng |
| **Cảnh báo Linting (Verilator)** | Nhiều cảnh báo UNOPTFLAT | **0 Errors, 0 Warnings** | 🟢 Mã nguồn sạch hoàn toàn |
| **Chu kỳ xung nhịp mục tiêu PnR** | 14.0 ns (71.4 MHz) | **12.0 ns (83.33 MHz)** | 🟢 Tăng tần số tối đa |

*Ghi chú: Số liệu đo lường thực tế từ môi trường mô phỏng chu kỳ lệnh QuestaSim 2021.2 và trình tổng hợp Yosys / OpenLane v2.3.10.*

---

## 1.4 Sơ đồ kiến trúc tổng quan (Architecture Overview)

Kiến trúc tổng thể của hệ thống lõi vi xử lý `riscv_core_top` được cấu trúc thành 3 phân vùng chính:
1. **Lõi xử lý trung tâm (Core Pipeline):** Bao gồm Tầng 1 `stage_if` (Fetch, Prefetch FIFO, RVC Decompressor), Thanh ghi ngăn cách `pipe_reg_if_id`, Tầng 2 `stage_id_ex` (Decoder, Register File, Imm Gen, ALU, 8-cycle Multiplier, SIMD MAC, Branch Comparator), Thanh ghi ngăn cách `pipe_reg_ex_mem`, Tầng 3 `stage_mem_wb` (Memory Aligners, Byte Enable, CSR Unit, Write-Back MUX), cùng hai khối điều phối trung tâm `forwarding_unit` và `hazard_unit`.
2. **Khối đồng bộ hóa ngắt ngoại vi:** Module `sync_2ff` nhận các tín hiệu ngắt ngoài bất đồng bộ `i_ext_irq` và `i_timer_irq`, đồng bộ hóa qua 2 tầng Flip-Flop trước khi cấp vào lõi.
3. **Hệ thống bộ nhớ và bus ngoại vi:** Macro SRAM 2KB Dual-Port OpenRAM (`sky130_sram_2kbyte_1rw1r_32x512_8`) và Cầu nối bus AMBA 4 APB Master (`apb_bridge`).

Sự phối hợp giữa các phân vùng diễn ra tuần tự và đồng bộ qua từng sườn dương xung nhịp `i_clk`:
- Tầng IF liên tục nạp các từ mã lệnh 32-bit từ Port 1 của Macro SRAM tại địa chỉ `o_imem_addr`. Hàng đợi Prefetch FIFO tiếp nhận dữ liệu và chuyển tiếp qua bộ giải mã lệnh nén `rvc_decompressor`. Các lệnh nén 16-bit được mở rộng thành 32-bit trước khi đưa vào thanh ghi đường ống `pipe_reg_if_id`.
- Tầng ID/EX tiếp nhận mã lệnh đã giải nén, thực hiện đọc thanh ghi đồng thời từ `register_file`, trích xuất số tức thời qua `imm_gen`, và thực hiện tính toán số học trên `alu`, `booth_multiplier_32b` hoặc `simd_mac_unit`. Bộ so sánh nhánh `branch_comparator` đánh giá điều kiện rẽ nhánh và chuyển hướng tầng IF nếu điều kiện thỏa mãn.
- Tầng MEM/WB hoàn tất các giao dịch đọc/ghi dữ liệu bộ nhớ qua Port 0 của SRAM hoặc qua cầu nối `apb_bridge`, cập nhật thanh ghi đặc quyền trong `csr`, và chuyển kết quả ghi trả `w_wb_data` về tập thanh ghi `register_file` cũng như chuyển tiếp tức thời qua `forwarding_unit`.

---

## 1.5 Bảng tham số kiến trúc (Design Parameters)

**Bảng 1.3: Bảng tham số kiến trúc thiết kế hệ thống (Design Parameters)**

| Tên Tham Số | Kiểu Dữ Liệu | Giá Trị Mặc Định | Giá Trị Mô Phỏng | Phân Loại | Ý Nghĩa Chức Năng | Module Bị Ảnh Hưởng |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- |
| `P_DATA_WIDTH` | `integer` | `32` | `32` | Kiến trúc | Độ rộng đường dữ liệu và thanh ghi RISC-V | Toàn bộ hệ thống |
| `P_ADDR_WIDTH` | `integer` | `32` | `32` | Kiến trúc | Độ rộng không gian địa chỉ bộ nhớ | Toàn bộ hệ thống |
| `P_REG_ADDR_W` | `integer` | `5` | `5` | Kiến trúc | Độ rộng địa chỉ tập thanh ghi (32 thanh ghi x0..x31) | `register_file`, `stage_id_ex`, `forwarding_unit` |
| `P_RESET_VEC` | `32-bit hex` | `32'h0000_0000` | `32'h0000_0000` | Cấu hình | Địa chỉ khởi động nạp lệnh sau Reset | `stage_if`, `pipe_reg_if_id` |
| `P_INST_NOP` | `32-bit hex` | `32'h0000_0013` | `32'h0000_0013` | Cấu hình | Mã máy lệnh NOP chuẩn (`addi x0, x0, 0`) | `stage_if`, `instruction_decoder` |
| `P_SRAM_ADDR_W` | `integer` | `9` | `9` | Bộ nhớ | Độ rộng địa chỉ từ nhớ SRAM (512 từ = 2048 bytes) | `sky130_sram_2kbyte_1rw1r_32x512_8` |
| `P_SRAM_SIZE` | `integer` | `2048` | `2048` | Bộ nhớ | Dung lượng bộ nhớ nội bộ SRAM tính theo byte | `riscv_core_top` |
| `P_NUM_WMASKS` | `integer` | `4` | `4` | Bộ nhớ | Số lượng tín hiệu byte write enable cho SRAM | `sky130_sram_2kbyte_1rw1r_32x512_8`, `be_gen` |
| `P_MMIO_BASE` | `8-bit hex` | `8'h40` | `8'h40` | Bộ nhớ | Byte cao nhất của không gian địa chỉ ngoại vi MMIO (`0x4000_0000`) | `core_top`, `apb_bridge` |
| `P_CLK_PERIOD` | `real` | `12.0` | `10.0` | Vật lý | Chu kỳ xung nhịp danh định tính bằng nano giây (ns) | `riscv_core_top.sdc`, `config.json` |

*Ghi chú: Toàn bộ tham số cấu hình được chuẩn hóa tiền tố P_ cho module parameters và PL_ cho local parameters nội bộ theo quy tắc kỹ thuật.*

---

# CHƯƠNG 2: TOP MODULE – `riscv_core_top`

## 2.1 Sơ đồ khối Top Module (Top-Level Block Diagram)

Top module `riscv_core_top` bao bọc toàn bộ hệ thống lõi xử lý, macro bộ nhớ SRAM 2KB, cầu nối bus APB và bộ đồng bộ ngắt ngoại vi trong một ranh giới duy nhất.

Cấu trúc giao tiếp ngoại vi của Top Module gồm các cổng:
- Cổng xung nhịp và reset: `i_clk`, `i_rst_n`.
- Cổng ngắt ngoại vi bất đồng bộ: `i_ext_irq`, `i_timer_irq`.
- Cổng bus AMBA 4 APB Master: `o_apb_paddr`, `o_apb_pwrite`, `o_apb_pstrb`, `o_apb_psel`, `o_apb_penable`, `o_apb_pwdata`, `i_apb_prdata`, `i_apb_pready`, `i_apb_pslverr`.

---

## 2.2 Bảng chân tín hiệu ngoại vi Top Module (External Interface Table)

**Bảng 2.1: Bảng chân tín hiệu ngoại vi Top Module (External Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_clk` | Input | 1 | Clock | `i_clk` | Nguồn xung nhịp chính điều khiển toàn bộ lõi xử lý và SRAM | Tần số danh định 83.33 MHz (chu kỳ 12 ns) | N/A |
| `i_rst_n` | Input | 1 | Reset | Async | Tín hiệu reset toàn hệ thống, tích cực mức thấp (Active-Low) | Bất đồng bộ, thời gian kích hoạt tối thiểu 20 ns | N/A |
| `i_ext_irq` | Input | 1 | Logic | Async | Tín hiệu yêu cầu ngắt ngoài từ ngoại vi IoT (External Interrupt) | Bất kỳ, được lọc qua bộ đồng bộ `sync_2ff` | `1'b0` |
| `i_timer_irq` | Input | 1 | Logic | Async | Tín hiệu yêu cầu ngắt từ bộ đếm thời gian (Timer Interrupt) | Bất kỳ, được lọc qua bộ đồng bộ `sync_2ff` | `1'b0` |
| `o_apb_paddr` | Output | 32 | Data | `i_clk` | Đường địa chỉ bus APB phát tới các ngoại vi MMIO | Có hiệu lực khi `o_apb_psel = 1` | `32'd0` |
| `o_apb_pwrite` | Output | 1 | Control | `i_clk` | Tín hiệu hướng truyền dữ liệu APB: 1 = Ghi (Write), 0 = Đọc (Read) | Có hiệu lực trong pha SETUP và ACCESS | `1'b0` |
| `o_apb_pstrb` | Output | 4 | Control | `i_clk` | Mặt nạ byte strobe APB4 xác định byte hợp lệ khi ghi dữ liệu | Có hiệu lực khi `o_apb_pwrite = 1` | `4'b0000` |
| `o_apb_psel` | Output | 1 | Control | `i_clk` | Tín hiệu chọn thiết bị ngoại vi APB (Peripheral Select) | Tích cực mức cao khi CPU truy xuất dải địa chỉ MMIO | `1'b0` |
| `o_apb_penable` | Output | 1 | Control | `i_clk` | Tín hiệu kích hoạt truyền nhận APB trong pha thứ hai (ACCESS phase) | Tích cực mức cao ở chu kỳ thứ hai của giao dịch | `1'b0` |
| `o_apb_pwdata` | Output | 32 | Data | `i_clk` | Đường dữ liệu ghi APB phát từ lõi tới ngoại vi MMIO | Có hiệu lực khi `o_apb_psel = 1` và `o_apb_pwrite = 1` | `32'd0` |
| `i_apb_prdata` | Input | 32 | Data | `i_clk` | Đường dữ liệu đọc APB do thiết bị ngoại vi trả về cho lõi | Có hiệu lực khi `o_apb_psel = 1`, `o_apb_penable = 1`, `i_apb_pready = 1` | N/A |
| `i_apb_pready` | Input | 1 | Control | `i_clk` | Tín hiệu báo sẵn sàng từ slave APB, cho phép kéo dài chu kỳ chờ | Mức 1 báo hoàn tất giao dịch; Mức 0 giữ nguyên trạng thái chờ | N/A |
| `i_apb_pslverr` | Input | 1 | Control | `i_clk` | Tín hiệu báo lỗi truyền nhận từ slave APB | Tích cực mức 1 khi phát sinh lỗi truy cập slave | N/A |

*Ghi chú: Toàn bộ tín hiệu vào bất đồng bộ được đồng bộ hóa trước khi đưa vào logic nội bộ. Bus APB tuân thủ chuẩn AMBA 4 APB Protocol.*

---

## 2.3 Nguyên lý hoạt động tổng thể & Mối quan hệ tương tác giữa các Sub-module

Lõi `riscv_core_top` vận hành theo cơ chế đường ống 3 tầng tuyến tính liên tục với sự phối hợp chặt chẽ giữa các khối chức năng:

1. **Giai đoạn Nạp Lệnh (Tầng 1 - `stage_if`):**
   - Con trỏ chương trình PC trỏ vào Port 1 của Macro SRAM (`sky130_sram_2kbyte_1rw1r_32x512_8`). Từ nhớ 32-bit đọc về được nạp vào hàng đợi Prefetch FIFO 2-word.
   - Bộ giải mã lệnh nén song song `rvc_decompressor` kiểm tra các bit nhận diện `instr[1:0]`. Nếu là lệnh nén 16-bit (`instr[1:0] != 2'b11`), lệnh được mở rộng ngay trong chu kỳ đó thành lệnh 32-bit tiêu chuẩn. PC tăng tương ứng 2 byte hoặc 4 byte.
   - Nếu có tín hiệu chuyển hướng rẽ nhánh từ Tầng 2 (`w_ex_branch_taken`), địa chỉ đích được chốt vào thanh ghi `r_redirect_target` và áp dụng với độ trễ 2 chu kỳ.
   - Lệnh và cờ hợp lệ được chốt vào thanh ghi đường ống `pipe_reg_if_id`.

2. **Giai đoạn Giải Mã & Thực Thi (Tầng 2 - `stage_id_ex`):**
   - Bộ giải mã `instruction_decoder` phân tích mã opcode, funct3, funct7 để sinh toàn bộ vector điều khiển cho ALU, bộ nhân, khối SIMD, bộ nhớ và CSR.
   - Tập thanh ghi `register_file` cung cấp 2 toán hạng đọc `rs1_data` và `rs2_data` theo phương thức đọc bất đồng bộ (Asynchronous Read).
   - Bộ chuyển tiếp dữ liệu `forwarding_unit` so sánh địa chỉ đọc `rs1_addr`, `rs2_addr` với địa chỉ ghi trả từ Tầng 3 `w_ex_mem_rd_addr`. Nếu phát hiện xung đột dữ liệu RAW (Read-After-Write), dữ liệu ghi trả hoàn chỉnh `w_wb_data` (chứa kết quả ALU, dữ liệu Load, kết quả nhân, dữ liệu CSR, hoặc địa chỉ JAL link `PC+4`) được chuyển tiếp tức thời, triệt tiêu chu kỳ chờ.
   - Khối `alu` thực hiện tính toán số học/logic; Khối `booth_multiplier_32b` thực hiện nhân số học tuần tự 8 chu kỳ; Khối `simd_mac_unit` thực hiện tính tích vô hướng 4x INT8; Khối `branch_comparator` đánh giá điều kiện rẽ nhánh.
   - Kết quả tính toán và các tín hiệu điều khiển được chốt vào thanh ghi đường ống `pipe_reg_ex_mem`.

3. **Giai đoạn Truy Xuất Bộ Nhớ & Ghi Trả (Tầng 3 - `stage_mem_wb`):**
   - Nếu lệnh truy xuất bộ nhớ nội bộ (địa chỉ nhỏ hơn 2KB), dữ liệu được ghi hoặc đọc qua Port 0 của SRAM với sự căn chỉnh của `st_align` / `load_align` và mặt nạ byte `be_gen`.
   - Nếu địa chỉ truy cập rơi vào dải MMIO (`0x4000_0000` .. `0x40FF_FFFF`), yêu cầu được chuyển sang cầu nối `apb_bridge` để phát giao dịch AMBA 4 APB ra ngoài.
   - Nếu có thao tác đọc/ghi thanh ghi đặc quyền hoặc phát sinh bẫy ngắt/ngoại lệ, khối `csr` tiếp nhận và xử lý.
   - Dữ liệu hoàn chỉnh cuối cùng được lựa chọn qua bộ chọn Write-Back MUX (`w_wb_data`) và ghi vào `register_file` tại sườn dương xung nhịp tiếp theo nếu `w_wb_en = 1`.

4. **Cơ chế Điều Phối Xung Đột & Bẫy Ngắt (Hazard & Trap Coordination):**
   - Khối `hazard_unit` giám sát các tình huống nghẽn:
     - **Load-to-Use Hazard:** Khi lệnh Tầng 3 là lệnh nạp `LW` và lệnh Tầng 2 cần sử dụng dữ liệu nạp, `hazard_unit` phát tín hiệu `o_stall_load_use = 1`, giữ nguyên Tầng 1 và Tầng 2 trong 1 chu kỳ clock.
     - **Multiplier Busy:** Khi bộ nhân đang tính toán 8 chu kỳ (`w_mul_busy = 1`), đường ống bị giữ lại cho đến khi có cờ `w_mul_done`.
     - **APB Busy:** Khi cầu nối APB đang bận giao dịch hoặc slave kéo dài chu kỳ chờ (`w_apb_busy = 1`), đường ống tự động dừng chờ.
     - **Bẫy Ngắt Bất Đồng Bộ (Async IRQ):** Cho phép lệnh hiện tại ở Tầng 3 commit hoàn tất (`o_wb_en = 1`), lưu `mepc = PC+4`, và xóa (flush) Tầng 1, Tầng 2.
     - **Ngoại Lệ Đồng Bộ (Sync Exception):** Ngắt bỏ ghi trả Tầng 3 (`o_wb_en = 0`), hủy yêu cầu bus (`o_mem_en = 0`), lưu `mepc = PC`, và nhảy vào vector xử lý bẫy.

---

## 2.4 Bảng kết nối nội bộ giữa các Sub-module (Internal Interconnect Table)

**Bảng 2.2: Bảng kết nối bus nội bộ giữa các Sub-module trong Top Module**

| Tên Bus Nội Bộ | Độ Rộng | Khối Nguồn (Driver) | Khối Nhận (Receiver) | Chức Năng Chi Tiết |
| :--- | :---: | :--- | :--- | :--- |
| `w_if_pc` | 32 | `stage_if` | `pipe_reg_if_id` | Giá trị con trỏ chương trình PC hiện tại của lệnh nạp |
| `w_if_instr` | 32 | `stage_if` | `pipe_reg_if_id` | Mã lệnh 32-bit hoàn chỉnh (đã giải nén nếu là lệnh 16-bit RVC) |
| `w_if_valid` | 1 | `stage_if` | `pipe_reg_if_id` | Cờ báo lệnh nạp hợp lệ tại tầng IF |
| `w_id_pc` | 32 | `pipe_reg_if_id` | `stage_id_ex` | Địa chỉ PC chuyển sang tầng giải mã và thực thi |
| `w_id_instr` | 32 | `pipe_reg_if_id` | `stage_id_ex` | Mã lệnh chuyển sang tầng giải mã và thực thi |
| `w_id_valid` | 1 | `pipe_reg_if_id` | `stage_id_ex` | Cờ hợp lệ của lệnh tại tầng giải mã |
| `w_ex_result` | 32 | `stage_id_ex` | `pipe_reg_ex_mem` | Kết quả tính toán từ ALU, Bộ nhân, hoặc SIMD MAC |
| `w_ex_store_data`| 32 | `stage_id_ex` | `pipe_reg_ex_mem` | Dữ liệu từ thanh ghi rs2 chuẩn bị ghi vào bộ nhớ |
| `w_ex_rs1_data` | 32 | `stage_id_ex` | `pipe_reg_ex_mem` | Dữ liệu thanh ghi rs1 phục vụ lệnh CSR |
| `w_ex_rd_addr` | 5 | `stage_id_ex` | `pipe_reg_ex_mem` | Địa chỉ thanh ghi đích rd cần ghi trả |
| `w_ex_mem_result`| 32 | `pipe_reg_ex_mem` | `stage_mem_wb`, `core_top` | Kết quả tính toán đã chốt tại Tầng 3 (Địa chỉ bộ nhớ) |
| `w_wb_data` | 32 | `stage_mem_wb` | `stage_id_ex` (RF & FWD) | Dữ liệu ghi trả hoàn chỉnh chuyển tiếp về Register File và Forwarding |
| `w_wb_en` | 1 | `hazard_unit` | `stage_id_ex` (RF) | Tín hiệu cho phép ghi tập thanh ghi đã được bảo vệ bẫy ngoại lệ |
| `w_fwd_a_mux` | 1 | `forwarding_unit` | `stage_id_ex` | Tín hiệu chọn chuyển tiếp dữ liệu cho toán hạng A |
| `w_fwd_b_mux` | 1 | `forwarding_unit` | `stage_id_ex` | Tín hiệu chọn chuyển tiếp dữ liệu cho toán hạng B |
| `w_hz_stall_pc` | 1 | `hazard_unit` | `stage_if` | Tín hiệu đóng băng con trỏ chương trình PC |
| `w_hz_flush_pipe`| 1 | `hazard_unit` | `pipe_reg_if_id`, `pipe_reg_ex_mem` | Tín hiệu xóa đường ống khi rẽ nhánh hoặc phát sinh bẫy ngắt |
| `w_sram_oob_err`| 1 | `core_top` (Logic) | `stage_mem_wb` (CSR) | Tín hiệu báo lỗi truy cập vượt quá biên dung lượng 2KB SRAM |
| `w_ext_irq_sync`| 1 | `sync_2ff` | `stage_mem_wb` (CSR) | Tín hiệu ngắt ngoài đã được đồng bộ hóa an toàn |
| `w_tmr_irq_sync`| 1 | `sync_2ff` | `stage_mem_wb` (CSR) | Tín hiệu ngắt định thời đã được đồng bộ hóa an toàn |

*Ghi chú: Toàn bộ kết nối nội bộ tuân thủ quy tắc một nguồn lái (Single-driver) và không có đường dây treo lơ lửng.*

---

## 2.5 Giản đồ thời gian tổng thể Top Module (Top-Level Timing Diagrams)

Chu kỳ hoạt động của đường ống 3 tầng tuyến tính khi thực thi chuỗi lệnh liên tiếp không có xung đột:

1. **Chu kỳ T1:** Lệnh `Inst_0` được nạp tại Tầng 1 (`stage_if`).
2. **Chu kỳ T2:** Lệnh `Inst_0` chuyển sang Tầng 2 (`stage_id_ex`) để giải mã và tính toán ALU; Đồng thời lệnh `Inst_1` được nạp tại Tầng 1.
3. **Chu kỳ T3:** Lệnh `Inst_0` chuyển sang Tầng 3 (`stage_mem_wb`) để truy xuất bộ nhớ/CSR và ghi trả Register File; Lệnh `Inst_1` thực thi tại Tầng 2; Lệnh `Inst_2` được nạp tại Tầng 1.
4. **Chu kỳ T4:** Lệnh `Inst_0` hoàn tất ghi trả; Lệnh `Inst_1` ghi trả tại Tầng 3; Đường ống đạt thông lượng tối đa **1 lệnh / chu kỳ clock (IPC = 1.0)**.

Trong trường hợp phát sinh xung đột dữ liệu Load-to-Use, Tầng 3 (`LW`) sẽ giữ lại Tầng 2 và Tầng 1 đúng **1 chu kỳ clock**, sau đó chuyển tiếp trực tiếp dữ liệu nạp `w_wb_data` vào toán hạng Tầng 2 mà không cần thông qua thanh ghi trung gian.


---

# CHƯƠNG 3: ĐẶC TẢ CHI TIẾT TỪNG SUB-MODULE

---

## 3.1 Module: `stage_if`
**Chức năng:** Tầng Nạp Lệnh (Instruction Fetch) chịu trách nhiệm quản lý con trỏ chương trình PC, điều phối hàng đợi đệm nạp lệnh 2 từ nhớ Prefetch FIFO, tích hợp bộ giải nén lệnh 16-bit `rvc_decompressor` song song, và tiếp nhận lệnh chuyển hướng rẽ nhánh hoặc bẫy ngắt từ các tầng sau.

### 3.1.1 Sơ đồ khối (Block Diagram)
Khối `stage_if` bao gồm con trỏ chương trình PC, bộ đệm Prefetch FIFO 2-word (64-bit), bộ giải mã lệnh nén `rvc_decompressor`, và thanh ghi lưu địa chỉ đích chuyển hướng rẽ nhánh 2 chu kỳ `r_redirect_target`.

### 3.1.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.1: Bảng chân tín hiệu module `stage_if` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_clk` | Input | 1 | Clock | `i_clk` | Nguồn xung nhịp cấp cho tầng IF | Tần số danh định | N/A |
| `i_rst_n` | Input | 1 | Reset | Async | Tín hiệu reset tích cực mức thấp | Chuẩn hệ thống | N/A |
| `i_stall_pc` | Input | 1 | Control | `i_clk` | Tín hiệu đóng băng con trỏ PC từ Hazard Unit | Mức 1: Giữ nguyên PC hiện tại | `1'b0` |
| `i_flush_pipe` | Input | 1 | Control | `i_clk` | Tín hiệu xóa hàng đợi đệm và pipeline khi rẽ nhánh | Mức 1: Xóa bộ đệm prefetch | `1'b0` |
| `i_branch_taken` | Input | 1 | Control | `i_clk` | Cờ báo điều kiện rẽ nhánh thành công từ Tầng 2 | Mức 1: Chuyển hướng nạp lệnh | `1'b0` |
| `i_branch_target`| Input | 32 | Data | `i_clk` | Địa chỉ đích của lệnh rẽ nhánh hoặc lệnh nhảy | Có hiệu lực khi `i_branch_taken = 1` | `32'd0` |
| `i_imem_rdata` | Input | 32 | Data | `i_clk` | Dữ liệu mã lệnh 32-bit đọc về từ Port 1 của SRAM | Đồng bộ theo xung nhịp | N/A |
| `o_imem_addr` | Output | 32 | Data | `i_clk` | Địa chỉ nạp lệnh phát tới Port 1 của SRAM | Luôn hợp lệ khi nạp lệnh | `32'd0` |
| `o_pc` | Output | 32 | Data | `i_clk` | Giá trị PC của lệnh hiện tại cấp sang Tầng 2 | Có hiệu lực khi `o_valid = 1` | `32'd0` |
| `o_instr` | Output | 32 | Data | `i_clk` | Mã lệnh 32-bit hoàn chỉnh (đã giải nén nếu là RVC) | Có hiệu lực khi `o_valid = 1` | `32'h00000013` |
| `o_is_compressed`| Output | 1 | Control | `i_clk` | Cờ báo lệnh hiện tại có gốc là lệnh nén 16-bit | Có hiệu lực khi `o_valid = 1` | `1'b0` |
| `o_valid` | Output | 1 | Control | `i_clk` | Cờ báo lệnh nạp ra hợp lệ chuyển sang `pipe_reg_if_id` | Mức 1 khi lệnh sẵn sàng | `1'b0` |

*Ghi chú: Tầng IF tự động căn chỉnh bước tăng PC là +2 nếu là lệnh nén RVC và +4 nếu là lệnh RV32I 32-bit.*

### 3.1.3 Nguyên lý hoạt động (Operating Principle)
- **Quản lý con trỏ PC và nạp lệnh:**
  - Trong điều kiện bình thường không stall:
    - Nếu lệnh hiện tại là lệnh nén 16-bit (`o_is_compressed = 1`): `next_pc = r_pc + 32'd2`.
    - Nếu lệnh hiện tại là lệnh 32-bit tiêu chuẩn: `next_pc = r_pc + 32'd4`.
  - Khi có tín hiệu chuyển hướng rẽ nhánh (`i_branch_taken = 1`): Địa chỉ `i_branch_target` được chốt vào thanh ghi `r_redirect_target`, kích hoạt xóa hàng đợi prefetch và nạp lệnh mới từ địa chỉ đích với độ trễ 2 chu kỳ clock.
  - Khi có tín hiệu đóng băng `i_stall_pc = 1`: Giá trị PC được giữ nguyên.
- **Hàng đợi đệm Prefetch FIFO:** Đệm 2 từ nhớ 32-bit giúp duy trì dòng nạp lệnh liên tục bất chấp các lệnh nén 16-bit nằm vắt ngang qua ranh giới từ nhớ 32-bit.

### 3.1.4 Giản đồ thời gian (Timing Diagram)
- **Chu kỳ T1:** `o_imem_addr = 0x0000_0000`, SRAM trả về `i_imem_rdata = Word_0`.
- **Chu kỳ T2:** `Word_0` được nạp vào FIFO; Nếu là lệnh RVC 16-bit, giải mã ngay và xuất `o_instr`, `o_valid = 1`, `o_pc = 0x0000_0000`. Con trỏ PC chuyển sang `0x0000_0002`.
- **Chu kỳ T3:** Nửa trên của `Word_0` được đưa vào bộ giải nén, xuất `o_pc = 0x0000_0002`.

---

## 3.2 Module: `pipe_reg_if_id`
**Chức năng:** Thanh ghi trung gian ngăn cách giữa Tầng 1 (IF) và Tầng 2 (ID/EX). Chốt giữ an toàn mã lệnh, địa chỉ PC và các cờ trạng thái, tích hợp khả năng đóng băng (Stall) và xóa lệnh (Flush).

### 3.2.1 Sơ đồ khối (Block Diagram)
Bao gồm các thanh ghi D-Flip-Flop chốt đồng bộ có chân kích hoạt cho phép nạp (Enable) và chân xóa đồng bộ (Synchronous Clear / Flush).

### 3.2.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.2: Bảng chân tín hiệu module `pipe_reg_if_id` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_clk` | Input | 1 | Clock | `i_clk` | Xung nhịp đồng bộ | Tần số danh định | N/A |
| `i_rst_n` | Input | 1 | Reset | Async | Reset bất đồng bộ tích cực mức thấp | Chuẩn hệ thống | N/A |
| `i_stall` | Input | 1 | Control | `i_clk` | Tín hiệu đóng băng thanh ghi từ Hazard Unit | Mức 1: Giữ nguyên giá trị cũ | `1'b0` |
| `i_flush` | Input | 1 | Control | `i_clk` | Tín hiệu xóa thanh ghi đường ống khi rẽ nhánh/bẫy | Mức 1: Xóa thành lệnh NOP | `1'b0` |
| `i_pc` | Input | 32 | Data | `i_clk` | Địa chỉ PC từ tầng IF | Có hiệu lực khi `i_valid = 1` | `32'd0` |
| `i_instr` | Input | 32 | Data | `i_clk` | Mã lệnh 32-bit từ tầng IF | Có hiệu lực khi `i_valid = 1` | `32'h00000013` |
| `i_is_compressed`| Input | 1 | Control | `i_clk` | Cờ báo lệnh nén từ tầng IF | Có hiệu lực khi `i_valid = 1` | `1'b0` |
| `i_valid` | Input | 1 | Control | `i_clk` | Cờ báo dữ liệu nạp hợp lệ | Mức 1 khi tầng IF có lệnh | `1'b0` |
| `o_pc` | Output | 32 | Data | `i_clk` | Địa chỉ PC chốt sang tầng ID/EX | Hợp lệ khi `o_valid = 1` | `32'd0` |
| `o_instr` | Output | 32 | Data | `i_clk` | Mã lệnh 32-bit chốt sang tầng ID/EX | Hợp lệ khi `o_valid = 1` | `32'h00000013` |
| `o_is_compressed`| Output | 1 | Control | `i_clk` | Cờ báo lệnh nén chốt sang tầng ID/EX | Hợp lệ khi `o_valid = 1` | `1'b0` |
| `o_valid` | Output | 1 | Control | `i_clk` | Cờ hợp lệ chốt sang tầng ID/EX | Mức 1 báo lệnh hợp lệ | `1'b0` |

*Ghi chú: Ưu tiên điều khiển: Reset bất đồng bộ > Flush đồng bộ > Stall.*

### 3.2.3 Nguyên lý hoạt động (Operating Principle)
- Phương trình chuyển trạng thái thanh ghi tại sườn dương `i_clk`:
  - `if (!i_rst_n)`: `o_pc <= 32'd0; o_instr <= 32'h0000_0013; o_valid <= 1'b0; o_is_compressed <= 1'b0;`
  - `else if (i_flush)`: `o_pc <= 32'd0; o_instr <= 32'h0000_0013; o_valid <= 1'b0; o_is_compressed <= 1'b0;` (Chèn bong bóng NOP).
  - `else if (!i_stall)`: `o_pc <= i_pc; o_instr <= i_instr; o_valid <= i_valid; o_is_compressed <= i_is_compressed;`
  - `else`: Giữ nguyên giá trị cũ.

### 3.2.4 Giản đồ thời gian (Timing Diagram)
- Khi `i_stall = 1`: Tại sườn dương `i_clk`, toàn bộ đầu ra `o_pc`, `o_instr`, `o_valid` không thay đổi.
- Khi `i_flush = 1`: Tại sườn dương `i_clk`, `o_instr` lập tức nhận mã lệnh NOP `32'h0000_0013` và `o_valid = 0`.

---

## 3.3 Module: `stage_id_ex`
**Chức năng:** Tầng Giải Mã & Thực Thi (ID/EX). Tích hợp bộ giải mã lệnh, tập thanh ghi, bộ sinh số tức thời, bộ chọn toán hạng chuyển tiếp (Forwarding MUX), khối tính toán ALU, bộ nhân tuần tự Radix-16, khối SIMD MAC và bộ so sánh nhánh.

### 3.3.1 Sơ đồ khối (Block Diagram)
Tầng ID/EX kết nối bộ giải mã `instruction_decoder`, tập thanh ghi `register_file`, `imm_gen`, bộ chọn toán hạng A và B nhận dữ liệu chuyển tiếp từ `forwarding_unit`, lái tới 3 khối tính toán: `alu`, `booth_multiplier_32b`, `simd_mac_unit`, cùng bộ đánh giá nhánh `branch_comparator`.

### 3.3.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.3: Bảng chân tín hiệu module `stage_id_ex` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_clk` | Input | 1 | Clock | `i_clk` | Xung nhịp hệ thống | Tần số danh định | N/A |
| `i_rst_n` | Input | 1 | Reset | Async | Reset bất đồng bộ tích cực mức thấp | Chuẩn hệ thống | N/A |
| `i_pc` | Input | 32 | Data | `i_clk` | Địa chỉ PC từ thanh ghi `pipe_reg_if_id` | Đồng bộ theo lệnh | `32'd0` |
| `i_instr` | Input | 32 | Data | `i_clk` | Mã lệnh 32-bit từ thanh ghi `pipe_reg_if_id` | Đồng bộ theo lệnh | `32'h00000013` |
| `i_valid` | Input | 1 | Control | `i_clk` | Cờ báo lệnh hợp lệ tại tầng ID | Mức 1: Lệnh hợp lệ | `1'b0` |
| `i_wb_data` | Input | 32 | Data | `i_clk` | Dữ liệu ghi trả từ Tầng 3 và Forwarding Unit | Đồng bộ write-back | `32'd0` |
| `i_wb_en` | Input | 1 | Control | `i_clk` | Tín hiệu cho phép ghi tập thanh ghi từ Hazard Unit | Mức 1: Cho phép ghi | `1'b0` |
| `i_wb_rd_addr` | Input | 5 | Data | `i_clk` | Địa chỉ thanh ghi đích cần ghi trả | Hợp lệ khi `i_wb_en = 1` | `5'd0` |
| `i_fwd_a_mux` | Input | 1 | Control | `i_clk` | Tín hiệu chọn dữ liệu chuyển tiếp cho toán hạng A | 1: Dùng `i_wb_data`, 0: Dùng RF | `1'b0` |
| `i_fwd_b_mux` | Input | 1 | Control | `i_clk` | Tín hiệu chọn dữ liệu chuyển tiếp cho toán hạng B | 1: Dùng `i_wb_data`, 0: Dùng RF | `1'b0` |
| `i_stall_load_use`| Input | 1 | Control | `i_clk` | Tín hiệu báo xung đột Load-to-Use để khóa bộ nhân | 1: Khóa kích hoạt bộ nhân | `1'b0` |
| `o_ex_result` | Output | 32 | Data | `i_clk` | Kết quả tính toán từ ALU, Bộ nhân, hoặc SIMD MAC | Hợp lệ khi hoàn tất tính | `32'd0` |
| `o_store_data` | Output | 32 | Data | `i_clk` | Dữ liệu từ toán hạng B chuẩn bị ghi vào bộ nhớ | Chuyển sang Tầng 3 | `32'd0` |
| `o_rs1_data` | Output | 32 | Data | `i_clk` | Dữ liệu toán hạng rs1 sau chuyển tiếp (phục vụ CSR) | Chuyển sang Tầng 3 | `32'd0` |
| `o_branch_taken` | Output | 1 | Control | `i_clk` | Cờ báo điều kiện rẽ nhánh thỏa mãn | Cấp về Tầng 1 | `1'b0` |
| `o_branch_target`| Output | 32 | Data | `i_clk` | Địa chỉ đích rẽ nhánh (`PC + Imm` hoặc JALR) | Cấp về Tầng 1 | `32'd0` |
| `o_mul_busy` | Output | 1 | Control | `i_clk` | Cờ báo bộ nhân đang bận tính toán 8 chu kỳ | Cấp cho Hazard Unit | `1'b0` |
| `o_rd_addr` | Output | 5 | Data | `i_clk` | Địa chỉ thanh ghi đích rd của lệnh hiện tại | Chuyển sang Tầng 3 | `5'd0` |

*Ghi chú: Toàn bộ toán hạng A và B được kiểm tra chuyển tiếp dữ liệu trước khi cấp vào các khối tính toán số học.*

### 3.3.3 Nguyên lý hoạt động (Operating Principle)
- **Lựa chọn toán hạng chuyển tiếp (Forwarding MUX):**
  - `src_a_fwd = (i_fwd_a_mux) ? i_wb_data : rf_rs1_data;`
  - `src_b_fwd = (i_fwd_b_mux) ? i_wb_data : rf_rs2_data;`
- **Khóa an toàn bộ nhân (Multiplier Stall Gating - Fix P0-3):**
  - Tín hiệu kích hoạt bộ nhân được khóa bằng phương trình: `u_mul_valid = dec_mul_valid & i_valid & (~i_stall_load_use);`
  - Nhờ đó, khi có xung đột Load-to-Use, bộ nhân không khởi động trong chu kỳ stall, toán hạng được chuyển tiếp chính xác dữ liệu nạp từ Tầng 3 ở chu kỳ tiếp theo trước khi kích hoạt nhân.
- **Tính toán kết quả Tầng 2:**
  - Nếu `dec_simd_valid`: `o_ex_result = simd_result;`
  - Nếu `dec_mul_valid`: `o_ex_result = mul_result;`
  - Ngược lại: `o_ex_result = alu_result;`

### 3.3.4 Giản đồ thời gian (Timing Diagram)
- Lệnh `ADD x3, x1, x2` vào Tầng 2: Đọc toán hạng x1, x2 từ Register File; Tính `x1 + x2` qua ALU trong cùng 1 chu kỳ clock; Chốt kết quả vào `pipe_reg_ex_mem` tại sườn dương tiếp theo.
- Lệnh `MUL x5, x1, x2`: Kích hoạt `o_mul_busy = 1` trong 8 chu kỳ clock; Hazard Unit dừng pipeline; Sau 8 chu kỳ, cờ `w_mul_done = 1` xuất kết quả 64-bit và giải phóng pipeline.

---

## 3.4 Module: `instruction_decoder`
**Chức năng:** Bộ giải mã lệnh tổ hợp hoàn chỉnh. Phân tích mã lệnh 32-bit để tạo ra toàn bộ các tín hiệu điều khiển cho đường dữ liệu RV32I, phần mở rộng nhân RV32M, tăng tốc AI SIMD MAC, tập lệnh Zicsr và phát hiện ngoại lệ lệnh bất hợp pháp (Illegal Instruction).

### 3.4.1 Sơ đồ khối (Block Diagram)
Khối logic tổ hợp thuần túy nhận mã lệnh `i_instr[31:0]`, phân tách thành các trường `opcode[6:0]`, `funct3[2:0]`, `funct7[6:0]`, `funct12[11:0]` và giải mã qua bảng chân lý.

### 3.4.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.4: Bảng chân tín hiệu module `instruction_decoder` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_instr` | Input | 32 | Data | Combinational| Mã lệnh 32-bit cần giải mã | Luôn hợp lệ | N/A |
| `o_alu_ctrl` | Output | 4 | Control | Combinational| Mã điều khiển thao tác ALU (ADD, SUB, SLL, SLT, XOR, SRL, SRA, OR, AND) | Định nghĩa theo defines | `4'b0000` |
| `o_alu_src` | Output | 1 | Control | Combinational| Chọn nguồn toán hạng B: 0 = Thanh ghi RS2, 1 = Số tức thời Imm | Luôn hợp lệ | `1'b0` |
| `o_alu_src_a` | Output | 2 | Control | Combinational| Chọn nguồn toán hạng A: 00 = RS1, 01 = PC, 10 = Zero (LUI) | Luôn hợp lệ | `2'b00` |
| `o_imm_src` | Output | 3 | Control | Combinational| Chọn định dạng số tức thời cho Imm Gen (I, S, B, U, J) | Luôn hợp lệ | `3'b000` |
| `o_reg_write` | Output | 1 | Control | Combinational| Cờ cho phép ghi vào tập thanh ghi đích rd | 1: Cho phép ghi | `1'b0` |
| `o_result_src` | Output | 2 | Control | Combinational| Chọn nguồn ghi trả Write-Back: 00 = ALU/MUL, 01 = Memory, 10 = PC+4, 11 = CSR | Luôn hợp lệ | `2'b00` |
| `o_mem_read` | Output | 1 | Control | Combinational| Cờ yêu cầu đọc bộ nhớ (lệnh Load) | 1: Đọc bộ nhớ | `1'b0` |
| `o_mem_write` | Output | 1 | Control | Combinational| Cờ yêu cầu ghi bộ nhớ (lệnh Store) | 1: Ghi bộ nhớ | `1'b0` |
| `o_mem_size` | Output | 2 | Control | Combinational| Kích thước truy cập bộ nhớ: 00 = Byte, 01 = Halfword, 10 = Word | Luôn hợp lệ | `2'b00` |
| `o_mem_uns` | Output | 1 | Control | Combinational| Mở rộng không dấu khi đọc bộ nhớ (LBU, LHU) | 1: Không dấu | `1'b0` |
| `o_mul_valid` | Output | 1 | Control | Combinational| Cờ kích hoạt bộ nhân RV32M | 1: Thực thi lệnh nhân | `1'b0` |
| `o_mul_type` | Output | 2 | Control | Combinational| Chế độ nhân: 00 = MUL, 01 = MULH, 10 = MULHSU, 11 = MULHU | Có hiệu lực khi mul_valid | `2'b00` |
| `o_simd_valid` | Output | 1 | Control | Combinational| Cờ kích hoạt khối Packed SIMD 4x INT8 `smdot.i8` | 1: Thực thi lệnh SIMD | `1'b0` |
| `o_branch` | Output | 1 | Control | Combinational| Cờ báo lệnh rẽ nhánh có điều kiện | 1: Lệnh Branch | `1'b0` |
| `o_branch_type` | Output | 3 | Control | Combinational| Loại lệnh rẽ nhánh (BEQ, BNE, BLT, BGE, BLTU, BGEU) | Có hiệu lực khi branch = 1 | `3'b000` |
| `o_jump` | Output | 1 | Control | Combinational| Cờ báo lệnh nhảy vô điều kiện JAL | 1: Lệnh JAL | `1'b0` |
| `o_jalr_en` | Output | 1 | Control | Combinational| Cờ báo lệnh nhảy qua thanh ghi JALR | 1: Lệnh JALR | `1'b0` |
| `o_csr_read` | Output | 1 | Control | Combinational| Cờ yêu cầu đọc thanh ghi CSR | 1: Đọc CSR | `1'b0` |
| `o_csr_write` | Output | 1 | Control | Combinational| Cờ yêu cầu ghi thanh ghi CSR | 1: Ghi CSR | `1'b0` |
| `o_is_ecall` | Output | 1 | Control | Combinational| Cờ phát hiện lệnh gọi môi trường ECALL | 1: Lệnh ECALL | `1'b0` |
| `o_is_ebreak` | Output | 1 | Control | Combinational| Cờ phát hiện lệnh bẫy gỡ lỗi EBREAK | 1: Lệnh EBREAK | `1'b0` |
| `o_is_mret` | Output | 1 | Control | Combinational| Cờ phát hiện lệnh quay về từ ngắt MRET | 1: Lệnh MRET | `1'b0` |
| `o_sleep_req` | Output | 1 | Control | Combinational| Cờ phát hiện lệnh chờ ngắt WFI (Wait-for-Interrupt) | 1: Lệnh WFI | `1'b0` |
| `o_illegal_instr`| Output | 1 | Control | Combinational| Cờ báo lệnh bất hợp pháp (Opcode lạ hoặc DIV/REM) | 1: Ngoại lệ Illegal | `1'b0` |

*Ghi chú: Toàn bộ logic giải mã là tổ hợp thuần túy (Combinational), không chứa chốt latch và không có xung nhịp.*

### 3.4.3 Nguyên lý hoạt động (Operating Principle)
- **Xử lý lệnh nhân/chia RV32M (Fix P0-7):**
  - Khi `opcode == OP_ARITHR` và `funct7 == 7'b0000001`:
    - `funct3 = 3'b000 .. 3'b011`: Kích hoạt bộ nhân `o_mul_valid = 1`, đặt `o_mul_type = funct3[1:0]`.
    - `funct3 = 3'b100 .. 3'b111` (lệnh `DIV`, `DIVU`, `REM`, `REMU`): Do phần cứng không có bộ chia, bộ giải mã lập tức vô hiệu hóa ghi thanh ghi `o_reg_write = 0` và kích hoạt cờ ngoại lệ `o_illegal_instr = 1`. Lệnh bị bẫy an toàn thành ngoại lệ `mcause = 2` thay vì chạy sai thành phép cộng.
- **Giải mã lệnh EBREAK (Fix R-16):**
  - Khi `opcode == OP_SYSTEM`, `funct3 == 3'b000`, `funct12 == 12'h001`: Kích hoạt cờ `o_is_ebreak = 1`, phát sinh bẫy Breakpoint Trap (`mcause = 3`).
- **Tối ưu hóa bỏ qua ghi CSR khi rs1 = x0:**
  - Nếu lệnh `CSRRS` hoặc `CSRRC` có `rs1 == 5'd0`, cờ `o_csr_write` tự động hạ về 0, chuyển lệnh thành thao tác đọc CSR thuần túy (CSR Read-Only) mà không kích hoạt ghi đè.

### 3.4.4 Giản đồ thời gian (Timing Diagram)
Logic tổ hợp giải mã lệnh hoàn tất trong thời gian trễ lan truyền dưới **1.5 ns** kể từ khi mã lệnh đầu vào `i_instr` ổn định.

---

## 3.5 Module: `register_file`
**Chức năng:** Tập thanh ghi đa năng 32 thanh ghi 32-bit (x0 đến x31). Hỗ trợ 2 cổng đọc bất đồng bộ độc lập (`rs1`, `rs2`) và 1 cổng ghi đồng bộ tại sườn dương xung nhịp (`rd`). Thanh ghi x0 được nối cứng cố định giá trị bằng 0.

### 3.5.1 Sơ đồ khối (Block Diagram)
Gồm mảng 31 thanh ghi 32-bit (từ x1 đến x31) chốt đồng bộ theo sườn dương xung nhịp, kết hợp mạch multiplexer 32-to-1 giải mã địa chỉ đọc `rs1_addr` và `rs2_addr`.

### 3.5.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.5: Bảng chân tín hiệu module `register_file` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_clk` | Input | 1 | Clock | `i_clk` | Xung nhịp đồng bộ cổng ghi | Tần số danh định | N/A |
| `i_rst_n` | Input | 1 | Reset | Async | Reset bất đồng bộ tích cực mức thấp | Chuẩn hệ thống | N/A |
| `i_rs1_addr` | Input | 5 | Data | Combinational| Địa chỉ thanh ghi đọc cổng 1 | 0 .. 31 | `5'd0` |
| `i_rs2_addr` | Input | 5 | Data | Combinational| Địa chỉ thanh ghi đọc cổng 2 | 0 .. 31 | `5'd0` |
| `i_rd_addr` | Input | 5 | Data | `i_clk` | Địa chỉ thanh ghi đích cần ghi | 0 .. 31 | `5'd0` |
| `i_wr_en` | Input | 1 | Control | `i_clk` | Tín hiệu cho phép ghi vào thanh ghi `rd` | 1: Cho phép ghi | `1'b0` |
| `i_wr_data` | Input | 32 | Data | `i_clk` | Dữ liệu ghi vào thanh ghi `rd` | Có hiệu lực khi `i_wr_en = 1` | `32'd0` |
| `o_rs1_data` | Output | 32 | Data | Combinational| Dữ liệu đọc ra từ cổng 1 | Luôn phản ánh giá trị tức thời | `32'd0` |
| `o_rs2_data` | Output | 32 | Data | Combinational| Dữ liệu đọc ra từ cổng 2 | Luôn phản ánh giá trị tức thời | `32'd0` |

*Ghi chú: Đọc là bất đồng bộ (Asynchronous Read). Ghi là đồng bộ sườn dương (Synchronous Write). Thanh ghi x0 luôn trả về 0.*

### 3.5.3 Nguyên lý hoạt động (Operating Principle)
- **Đọc dữ liệu bất đồng bộ:**
  - `o_rs1_data = (i_rs1_addr == 5'd0) ? 32'd0 : r_regs[i_rs1_addr];`
  - `o_rs2_data = (i_rs2_addr == 5'd0) ? 32'd0 : r_regs[i_rs2_addr];`
- **Ghi dữ liệu đồng bộ sườn dương:**
  - Tại sườn dương `i_clk`:
    - Nếu `i_wr_en && (i_rd_addr != 5'd0)`: `r_regs[i_rd_addr] <= i_wr_data;`
- **Khử xung đột dữ liệu:** Xung đột đọc/ghi cùng chu kỳ được giải quyết triệt để thông qua khối chuyển tiếp `forwarding_unit` bên ngoài.

### 3.5.4 Giản đồ thời gian (Timing Diagram)
Dữ liệu đọc `o_rs1_data`, `o_rs2_data` phản ánh giá trị thanh ghi ngay trong chu kỳ hiện tại. Tại sườn dương `i_clk`, nếu `i_wr_en = 1`, thanh ghi đích nhận giá trị mới từ chu kỳ tiếp theo.

---

## 3.6 Module: `imm_gen`
**Chức năng:** Bộ sinh và mở rộng dấu số tức thời (Immediate Generator) tổ hợp thuần túy. Hỗ trợ trích xuất và định dạng 5 loại số tức thời cơ bản của chuẩn RISC-V: I-type, S-type, B-type, U-type, J-type.

### 3.6.1 Sơ đồ khối (Block Diagram)
Khối logic tổ hợp trích xuất các trường bit phân tán từ lệnh `i_instr[31:7]` và ghép nối có mở rộng bit dấu `i_instr[31]`.

### 3.6.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.6: Bảng chân tín hiệu module `imm_gen` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_instr` | Input | 32 | Data | Combinational| Mã lệnh đầu vào chứa các bit số tức thời | Luôn hợp lệ | N/A |
| `i_imm_src` | Input | 3 | Control | Combinational| Mã chọn loại định dạng số tức thời từ Decoder | 000..100 | `3'b000` |
| `o_imm` | Output | 32 | Data | Combinational| Giá trị số tức thời 32-bit đã được mở rộng dấu | Luôn phản ánh tức thời | `32'd0` |

*Ghi chú: Toàn bộ quá trình ghép bit và mở rộng dấu là tổ hợp thuần túy.*

### 3.6.3 Nguyên lý hoạt động (Operating Principle)
- Bảng ghép nối các trường bit theo mã chọn `i_imm_src`:
  - `IMM_I (3'b000)`: `o_imm = {{20{i_instr[31]}}, i_instr[31:20]};`
  - `IMM_S (3'b001)`: `o_imm = {{20{i_instr[31]}}, i_instr[31:25], i_instr[11:7]};`
  - `IMM_B (3'b010)`: `o_imm = {{19{i_instr[31]}}, i_instr[31], i_instr[7], i_instr[30:25], i_instr[11:8], 1'b0};`
  - `IMM_U (3'b011)`: `o_imm = {i_instr[31:12], 12'b0};`
  - `IMM_J (3'b100)`: `o_imm = {{11{i_instr[31]}}, i_instr[31], i_instr[19:12], i_instr[20], i_instr[30:21], 1'b0};`
  - Mặc định: `o_imm = 32'd0;`

### 3.6.4 Giản đồ thời gian (Timing Diagram)
Thời gian trễ truyền lan của khối `imm_gen` dưới **0.5 ns**.

---

## 3.7 Module: `alu`
**Chức năng:** Khối số học & logic (ALU) 32-bit. Thực hiện các phép tính số học (cộng, trừ), logic (AND, OR, XOR), dịch bit (SLL, SRL, SRA), và so sánh (SLT, SLTU). Sử dụng kiến trúc bộ cộng chia sẻ 33-bit để tối ưu hóa diện tích silicon.

### 3.7.1 Sơ đồ khối (Block Diagram)
Bao gồm một bộ cộng 33-bit chia sẻ duy nhất (`w_sum_res`), mạch dịch bit đa năng và khối ghép multiplexer chọn kết quả theo mã điều khiển `i_alu_ctrl[3:0]`.

### 3.7.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.7: Bảng chân tín hiệu module `alu` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_a` | Input | 32 | Data | Combinational| Toán hạng A đầu vào | Luôn hợp lệ | `32'd0` |
| `i_b` | Input | 32 | Data | Combinational| Toán hạng B đầu vào | Luôn hợp lệ | `32'd0` |
| `i_alu_ctrl` | Input | 4 | Control | Combinational| Mã điều khiển phép tính ALU từ Decoder | 0..9 | `4'b0000` |
| `o_result` | Output | 32 | Data | Combinational| Kết quả tính toán 32-bit | Luôn phản ánh tức thời | `32'd0` |
| `o_zero` | Output | 1 | Flag | Combinational| Cờ báo kết quả tính bằng 0 (Zero Flag) | Tích cực mức 1 khi result = 0 | `1'b1` |
| `o_negative` | Output | 1 | Flag | Combinational| Cờ báo kết quả âm (Negative Flag / Bit dấu MSB) | Bằng `o_result[31]` | `1'b0` |
| `o_carry` | Output | 1 | Flag | Combinational| Cờ nhớ Carry-out từ bộ cộng 33-bit | Bằng `w_sum_res[32]` | `1'b0` |
| `o_overflow` | Output | 1 | Flag | Combinational| Cờ tràn số có dấu (Signed Overflow Flag) | Tính theo điều kiện tràn | `1'b0` |

*Ghi chú: Toàn bộ cờ trạng thái được sinh đồng thời với kết quả tính toán.*

### 3.7.3 Nguyên lý hoạt động (Operating Principle)
- **Bộ cộng chia sẻ 33-bit (Resource Sharing Adder):**
  - Nhận diện thao tác trừ: `w_is_sub = (i_alu_ctrl == ALU_SUB) | (i_alu_ctrl == ALU_SLT) | (i_alu_ctrl == ALU_SLTU);`
  - Thực hiện bù 2: `w_sum_res = {1'b0, i_a} + {1'b0, (w_is_sub ? ~i_b : i_b)} + {32'd0, w_is_sub};`
- **Các thao tác tính toán:**
  - `ALU_ADD / ALU_SUB`: `o_result = w_sum_res[31:0];`
  - `ALU_SLL`: `o_result = i_a << i_b[4:0];`
  - `ALU_SRL`: `o_result = i_a >> i_b[4:0];`
  - `ALU_SRA`: `o_result = $signed(i_a) >>> i_b[4:0];`
  - `ALU_XOR`: `o_result = i_a ^ i_b;`
  - `ALU_OR`: `o_result = i_a | i_b;`
  - `ALU_AND`: `o_result = i_a & i_b;`
  - `ALU_SLT` (So sánh có dấu): `o_result = {31'd0, (i_a[31] != i_b[31]) ? i_a[31] : w_sum_res[31]};`
  - `ALU_SLTU` (So sánh không dấu): `o_result = {31'd0, ~w_sum_res[32]};` (Đảo cờ nhớ carry-out).

### 3.7.4 Giản đồ thời gian (Timing Diagram)
Thời gian trễ lan truyền của phép cộng 33-bit và bộ dịch bit là **2.8 ns**, đáp ứng chu kỳ xung nhịp 12.0 ns.

---

## 3.8 Module: `booth_multiplier_32b`
**Chức năng:** Bộ nhân số học tuần tự 8 chu kỳ Radix-16 Shift-Add. Xử lý 4 bit toán hạng trong mỗi chu kỳ clock, hỗ trợ đầy đủ 4 chế độ nhân 32x32 sinh kết quả 64-bit: `MUL` (32 bit thấp), `MULH` (32 bit cao có dấu), `MULHSU` (32 bit cao hỗn hợp có dấu/không dấu), và `MULHU` (32 bit cao không dấu).

### 3.8.1 Sơ đồ khối (Block Diagram)
Bao gồm FSM điều khiển 8 chu kỳ, thanh ghi tích lũy 68-bit (Accumulator), bộ cộng 64-bit, mạch sinh bội số 0..15 lần toán hạng nhân, và bộ đếm chu kỳ 3-bit.

### 3.8.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.8: Bảng chân tín hiệu module `booth_multiplier_32b` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_clk` | Input | 1 | Clock | `i_clk` | Xung nhịp đồng bộ | Tần số danh định | N/A |
| `i_rst_n` | Input | 1 | Reset | Async | Reset bất đồng bộ tích cực mức thấp | Chuẩn hệ thống | N/A |
| `i_mul_valid` | Input | 1 | Control | `i_clk` | Tín hiệu xung kích hoạt bắt đầu phép nhân | Mức 1 ở chu kỳ đầu tiên | `1'b0` |
| `i_mul_type` | Input | 2 | Control | `i_clk` | Loại lệnh nhân: 00 = MUL, 01 = MULH, 10 = MULHSU, 11 = MULHU | Cùng lúc với mul_valid | `2'b00` |
| `i_a` | Input | 32 | Data | `i_clk` | Toán hạng nhân A (Multiplicand) | Chốt khi mul_valid = 1 | `32'd0` |
| `i_b` | Input | 32 | Data | `i_clk` | Toán hạng nhân B (Multiplier) | Chốt khi mul_valid = 1 | `32'd0` |
| `o_result` | Output | 32 | Data | `i_clk` | Kết quả 32-bit (chọn 32 bit thấp hoặc cao tùy `mul_type`) | Có hiệu lực khi mul_done = 1 | `32'd0` |
| `o_mul_done` | Output | 1 | Flag | `i_clk` | Cờ xung báo hoàn tất phép nhân sau 8 chu kỳ | Tích cực mức 1 đúng 1 chu kỳ | `1'b0` |
| `o_mul_busy` | Output | 1 | Control | `i_clk` | Cờ báo bộ nhân đang bận, yêu cầu Hazard Unit dừng pipeline | Mức 1 trong suốt 8 chu kỳ | `1'b0` |

*Ghi chú: Bộ nhân được bảo vệ bởi cổng khóa load-to-use stall từ tầng ID/EX, đảm bảo toán hạng đầu vào luôn đúng.*

### 3.8.3 Nguyên lý hoạt động (Operating Principle)
- **FSM điều khiển 3 trạng thái:**
  - `S_IDLE`: Chờ cờ kích hoạt `i_mul_valid = 1`. Khi có lệnh nhân, chốt toán hạng A, B, chuyển đổi dấu nếu là phép nhân có dấu, nạp bộ đếm `cycle_cnt = 0`, chuyển sang `S_CALC`, phát `o_mul_busy = 1`.
  - `S_CALC`: Thực hiện lặp trong 8 chu kỳ clock. Trong mỗi chu kỳ, lấy 4 bit của toán hạng B (Radix-16), cộng tích lũy giá trị tương ứng vào thanh ghi tích lũy và dịch phải 4 bit. Bộ đếm `cycle_cnt` tăng từ 0 đến 7.
  - `S_DONE`: Khi `cycle_cnt == 7`, hoàn tất bù 2 dấu kết quả (nếu có), phát xung `o_mul_done = 1`, hạ `o_mul_busy = 0`, xuất kết quả 32-bit tương ứng vào `o_result`.

### 3.8.4 Giản đồ thời gian (Timing Diagram)
- **Chu kỳ T0:** Nhận `i_mul_valid = 1`. `o_mul_busy` lên mức 1.
- **Chu kỳ T1 .. T7:** `o_mul_busy = 1`, Hazard Unit duy trì `w_hz_stall_pipe = 1`.
- **Chu kỳ T8:** `o_mul_done = 1`, `o_result` có giá trị hợp lệ, `o_mul_busy = 0`. Pipeline tiếp tục nạp lệnh mới.

---

## 3.9 Module: `simd_mac_unit`
**Chức năng:** Bộ tăng tốc AI Packed SIMD 4x INT8 Dot-Product chuyên dụng (`smdot.i8`). Nhận 2 thanh ghi 32-bit, chia thành 4 cặp số nguyên 8-bit có dấu, thực hiện 4 phép nhân song song và cộng dồn cây nhị phân 2 cấp sinh kết quả 32-bit trong 1 chu kỳ clock duy nhất.

### 3.9.1 Sơ đồ khối (Block Diagram)
Bao gồm 4 bộ nhân 8x8 có dấu song song (`$signed(A_i) * $signed(B_i)` sinh kết quả 16-bit) và cây cộng dồn 2 cấp (Cấp 1: hai bộ cộng 16-bit; Cấp 2: một bộ cộng 32-bit mở rộng dấu).

### 3.9.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.9: Bảng chân tín hiệu module `simd_mac_unit` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_rs1_data` | Input | 32 | Data | Combinational| Dữ liệu thanh ghi RS1 chứa 4 phần tử INT8: `[B3, B2, B1, B0]` | Luôn hợp lệ | `32'd0` |
| `i_rs2_data` | Input | 32 | Data | Combinational| Dữ liệu thanh ghi RS2 chứa 4 phần tử INT8: `[B3, B2, B1, B0]` | Luôn hợp lệ | `32'd0` |
| `o_simd_result`| Output | 32 | Data | Combinational| Kết quả tích vô hướng 32-bit có dấu | Luôn phản ánh tức thời | `32'd0` |

*Ghi chú: Khối SIMD MAC là tổ hợp thuần túy 1 chu kỳ, độ trễ lan truyền dưới 3.2 ns.*

### 3.9.3 Nguyên lý hoạt động (Operating Principle)
- **Tách 4 byte có dấu:**
  - `a0 = $signed(i_rs1_data[7:0]);   b0 = $signed(i_rs2_data[7:0]);`
  - `a1 = $signed(i_rs1_data[15:8]);  b1 = $signed(i_rs2_data[15:8]);`
  - `a2 = $signed(i_rs1_data[23:16]); b2 = $signed(i_rs2_data[23:16]);`
  - `a3 = $signed(i_rs1_data[31:24]); b3 = $signed(i_rs2_data[31:24]);`
- **4 phép nhân 8x8 có dấu song song:**
  - `p0 = a0 * b0;  p1 = a1 * b1;  p2 = a2 * b2;  p3 = a3 * b3;` (Kết quả mỗi phép nhân là 16-bit có dấu).
- **Cây cộng dồn 2 cấp:**
  - Cấp 1: `sum_low = p0 + p1; sum_high = p2 + p3;`
  - Cấp 2: `o_simd_result = {{15{sum_low[16]}}, sum_low} + {{15{sum_high[16]}}, sum_high};` (Kết quả 32-bit).

### 3.9.4 Giản đồ thời gian (Timing Diagram)
Toán hạng đầu vào ổn định tại đầu chu kỳ clock, kết quả `o_simd_result` đạt mức ổn định sau **3.2 ns** và chốt vào `pipe_reg_ex_mem` tại sườn dương tiếp theo (1 IPC, 0 chu kỳ stall).

---

## 3.10 Module: `branch_comparator`
**Chức năng:** Bộ đánh giá điều kiện rẽ nhánh tổ hợp. Tiếp nhận các cờ trạng thái từ ALU (`o_zero`, `o_negative`, `o_carry`, `o_overflow`) và mã lệnh nhánh `i_branch_type[2:0]` để quyết định nhánh có được thực thi hay không (`o_branch_taken`).

### 3.10.1 Sơ đồ khối (Block Diagram)
Mạch logic tổ hợp thuần túy kiểm tra các điều kiện cờ logic tương ứng với từng kiểu nhánh trong tập lệnh RISC-V.

### 3.10.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.10: Bảng chân tín hiệu module `branch_comparator` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_branch_en` | Input | 1 | Control | Combinational| Cờ cho phép đánh giá nhánh từ Decoder | 1: Lệnh hiện tại là nhánh | `1'b0` |
| `i_branch_type` | Input | 3 | Control | Combinational| Loại lệnh nhánh từ funct3 (BEQ, BNE, BLT, BGE, BLTU, BGEU) | Có hiệu lực khi branch_en | `3'b000` |
| `i_zero` | Input | 1 | Flag | Combinational| Cờ Zero từ ALU | Luôn hợp lệ | N/A |
| `i_negative` | Input | 1 | Flag | Combinational| Cờ Negative từ ALU | Luôn hợp lệ | N/A |
| `i_carry` | Input | 1 | Flag | Combinational| Cờ Carry từ bộ cộng/trừ 33-bit của ALU | Luôn hợp lệ | N/A |
| `i_overflow` | Input | 1 | Flag | Combinational| Cờ Overflow từ ALU | Luôn hợp lệ | N/A |
| `o_branch_taken` | Output | 1 | Control | Combinational| Quyết định rẽ nhánh: 1 = Nhánh nhảy, 0 = Không nhảy | Có hiệu lực khi branch_en | `1'b0` |

*Ghi chú: Nếu `i_branch_en = 0`, đầu ra bắt buộc ép về 0 để tránh lan truyền cờ ngẫu nhiên từ ALU.*

### 3.10.3 Nguyên lý hoạt động (Operating Principle)
- Phương trình logic đánh giá điều kiện:
  - `F3_BEQ  (3'b000)`: `r_cond_met = i_zero;`
  - `F3_BNE  (3'b001)`: `r_cond_met = ~i_zero;`
  - `F3_BLT  (3'b100)`: `r_cond_met = (i_negative ^ i_overflow);` (So sánh có dấu).
  - `F3_BGE  (3'b101)`: `r_cond_met = ~(i_negative ^ i_overflow);`
  - `F3_BLTU (3'b110)`: `r_cond_met = ~i_carry;` (So sánh không dấu, mượn cờ carry-out).
  - `F3_BGEU (3'b111)`: `r_cond_met = i_carry;`
- Đầu ra cuối cùng: `o_branch_taken = i_branch_en ? r_cond_met : 1'b0;`

### 3.10.4 Giản đồ thời gian (Timing Diagram)
Thời gian trễ đánh giá rẽ nhánh dưới **0.8 ns** kể từ khi cờ ALU xuất hiện.

---

## 3.11 Module: `pipe_reg_ex_mem`
**Chức năng:** Thanh ghi đường ống ngăn cách Tầng 2 (ID/EX) và Tầng 3 (MEM/WB). Chốt giữ toàn bộ kết quả tính toán, toán hạng dữ liệu lưu bộ nhớ, địa chỉ thanh ghi đích rd, mã lệnh gốc và các tín hiệu điều khiển bẫy ngoại lệ.

### 3.11.1 Sơ đồ khối (Block Diagram)
Tập hợp các thanh ghi D-Flip-Flop chốt đồng bộ tại sườn dương `i_clk`, hỗ trợ đóng băng bằng `i_stall` và xóa bằng `i_flush`.

### 3.11.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.11: Bảng chân tín hiệu module `pipe_reg_ex_mem` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_clk` | Input | 1 | Clock | `i_clk` | Xung nhịp đồng bộ | Tần số danh định | N/A |
| `i_rst_n` | Input | 1 | Reset | Async | Reset bất đồng bộ tích cực mức thấp | Chuẩn hệ thống | N/A |
| `i_stall` | Input | 1 | Control | `i_clk` | Tín hiệu đóng băng từ Hazard Unit | Mức 1: Giữ nguyên trạng thái | `1'b0` |
| `i_flush` | Input | 1 | Control | `i_clk` | Tín hiệu xóa đường ống từ Hazard Unit | Mức 1: Xóa thành NOP | `1'b0` |
| `i_pc` | Input | 32 | Data | `i_clk` | Giá trị PC của lệnh từ Tầng 2 | Hợp lệ khi i_valid = 1 | `32'd0` |
| `i_instr` | Input | 32 | Data | `i_clk` | Mã lệnh 32-bit gốc từ Tầng 2 | Hợp lệ khi i_valid = 1 | `32'h00000013` |
| `i_valid` | Input | 1 | Control | `i_clk` | Cờ báo lệnh hợp lệ từ Tầng 2 | Mức 1 khi lệnh hợp lệ | `1'b0` |
| `i_result` | Input | 32 | Data | `i_clk` | Kết quả tính toán từ Tầng 2 (Địa chỉ bộ nhớ / Kết quả ALU) | Đồng bộ theo lệnh | `32'd0` |
| `i_store_data` | Input | 32 | Data | `i_clk` | Dữ liệu từ toán hạng RS2 chuẩn bị ghi bộ nhớ | Đồng bộ theo lệnh | `32'd0` |
| `i_rs1_data` | Input | 32 | Data | `i_clk` | Dữ liệu từ toán hạng RS1 sau chuyển tiếp (phục vụ CSR) | Đồng bộ theo lệnh | `32'd0` |
| `i_rd_addr` | Input | 5 | Data | `i_clk` | Địa chỉ thanh ghi đích rd | 0 .. 31 | `5'd0` |
| `i_reg_write` | Input | 1 | Control | `i_clk` | Cờ yêu cầu ghi tập thanh ghi | 1: Cho phép ghi | `1'b0` |
| `i_mem_read` | Input | 1 | Control | `i_clk` | Cờ yêu cầu đọc bộ nhớ (Load) | 1: Đọc bộ nhớ | `1'b0` |
| `i_mem_write` | Input | 1 | Control | `i_clk` | Cờ yêu cầu ghi bộ nhớ (Store) | 1: Ghi bộ nhớ | `1'b0` |
| `i_mem_size` | Input | 2 | Control | `i_clk` | Kích thước truy cập bộ nhớ: Byte/Half/Word | Luôn hợp lệ | `2'b00` |
| `i_mem_uns` | Input | 1 | Control | `i_clk` | Mở rộng dấu không dấu khi đọc bộ nhớ | 1: Không dấu | `1'b0` |
| `i_result_src` | Input | 2 | Control | `i_clk` | Nguồn dữ liệu ghi trả Write-Back | 00..11 | `2'b00` |
| `i_csr_read` | Input | 1 | Control | `i_clk` | Cờ yêu cầu đọc thanh ghi CSR | 1: Đọc CSR | `1'b0` |
| `i_csr_write` | Input | 1 | Control | `i_clk` | Cờ yêu cầu ghi thanh ghi CSR | 1: Ghi CSR | `1'b0` |
| `i_is_ecall` | Input | 1 | Control | `i_clk` | Cờ nhận diện lệnh ECALL | 1: Lệnh ECALL | `1'b0` |
| `i_is_ebreak` | Input | 1 | Control | `i_clk` | Cờ nhận diện lệnh EBREAK | 1: Lệnh EBREAK | `1'b0` |
| `i_is_mret` | Input | 1 | Control | `i_clk` | Cờ nhận diện lệnh MRET | 1: Lệnh MRET | `1'b0` |
| `i_sleep_req` | Input | 1 | Control | `i_clk` | Cờ nhận diện lệnh WFI | 1: Lệnh WFI | `1'b0` |
| `i_illegal_instr`| Input | 1 | Control | `i_clk` | Cờ nhận diện lệnh bất hợp pháp (Illegal Instruction) | 1: Lệnh bất hợp pháp | `1'b0` |
| `o_pc` | Output | 32 | Data | `i_clk` | Giá trị PC chốt sang Tầng 3 | Hợp lệ khi o_valid = 1 | `32'd0` |
| `o_instr` | Output | 32 | Data | `i_clk` | Mã lệnh 32-bit gốc chốt sang Tầng 3 | Hợp lệ khi o_valid = 1 | `32'h00000013` |
| `o_valid` | Output | 1 | Control | `i_clk` | Cờ lệnh hợp lệ chốt sang Tầng 3 | Mức 1 báo lệnh hợp lệ | `1'b0` |
| `o_result` | Output | 32 | Data | `i_clk` | Kết quả tính toán chốt sang Tầng 3 | Đồng bộ theo lệnh | `32'd0` |
| `o_store_data` | Output | 32 | Data | `i_clk` | Dữ liệu lưu bộ nhớ chốt sang Tầng 3 | Đồng bộ theo lệnh | `32'd0` |
| `o_rs1_data` | Output | 32 | Data | `i_clk` | Dữ liệu RS1 chốt sang Tầng 3 | Đồng bộ theo lệnh | `32'd0` |
| `o_rd_addr` | Output | 5 | Data | `i_clk` | Địa chỉ thanh ghi đích rd chốt sang Tầng 3 | 0 .. 31 | `5'd0` |
| `o_reg_write` | Output | 1 | Control | `i_clk` | Cờ ghi tập thanh ghi chốt sang Tầng 3 | 1: Cho phép ghi | `1'b0` |
| `o_mem_read` | Output | 1 | Control | `i_clk` | Cờ đọc bộ nhớ chốt sang Tầng 3 | 1: Đọc bộ nhớ | `1'b0` |
| `o_mem_write` | Output | 1 | Control | `i_clk` | Cờ ghi bộ nhớ chốt sang Tầng 3 | 1: Ghi bộ nhớ | `1'b0` |
| `o_mem_size` | Output | 2 | Control | `i_clk` | Kích thước bộ nhớ chốt sang Tầng 3 | Luôn hợp lệ | `2'b00` |
| `o_mem_uns` | Output | 1 | Control | `i_clk` | Mở rộng không dấu chốt sang Tầng 3 | 1: Không dấu | `1'b0` |
| `o_result_src` | Output | 2 | Control | `i_clk` | Nguồn ghi trả chốt sang Tầng 3 | 00..11 | `2'b00` |
| `o_csr_read` | Output | 1 | Control | `i_clk` | Cờ đọc CSR chốt sang Tầng 3 | 1: Đọc CSR | `1'b0` |
| `o_csr_write` | Output | 1 | Control | `i_clk` | Cờ ghi CSR chốt sang Tầng 3 | 1: Ghi CSR | `1'b0` |
| `o_is_ecall` | Output | 1 | Control | `i_clk` | Cờ ECALL chốt sang Tầng 3 | 1: Lệnh ECALL | `1'b0` |
| `o_is_ebreak` | Output | 1 | Control | `i_clk` | Cờ EBREAK chốt sang Tầng 3 | 1: Lệnh EBREAK | `1'b0` |
| `o_is_mret` | Output | 1 | Control | `i_clk` | Cờ MRET chốt sang Tầng 3 | 1: Lệnh MRET | `1'b0` |
| `o_sleep_req` | Output | 1 | Control | `i_clk` | Cờ WFI chốt sang Tầng 3 | 1: Lệnh WFI | `1'b0` |
| `o_illegal_instr`| Output | 1 | Control | `i_clk` | Cờ Illegal chốt sang Tầng 3 | 1: Lệnh bất hợp pháp | `1'b0` |

*Ghi chú: Thanh ghi chốt toàn bộ cờ ngoại lệ để đảm bảo bẫy ngoại lệ được phát sinh chính xác tại ranh giới Tầng 3.*

### 3.11.3 Nguyên lý hoạt động (Operating Principle)
- Khi `i_flush = 1`: Toàn bộ các cờ điều khiển ghi `o_reg_write`, `o_mem_write`, `o_mem_read`, `o_csr_write`, `o_valid` được xóa về 0, biến lệnh thành bong bóng NOP vô hại.
- Khi `i_stall = 1`: Giữ nguyên toàn bộ giá trị đầu ra.
- Trong điều kiện bình thường: Chuyển toàn bộ dữ liệu và cờ điều khiển từ Tầng 2 sang Tầng 3 tại sườn dương xung nhịp `i_clk`.

### 3.11.4 Giản đồ thời gian (Timing Diagram)
Chuyển trạng thái đồng bộ hoàn hảo tại sườn dương `i_clk`.


---

## 3.12 Module: `stage_mem_wb`
**Chức năng:** Tầng Truy Xuất Bộ Nhớ & Ghi Trả (MEM/WB). Điều phối truy xuất dữ liệu đọc/ghi qua Port 0 của SRAM hoặc qua cầu nối ngoại vi APB, thực hiện căn chỉnh dữ liệu đọc/ghi, quản lý khối thanh ghi CSR, xử lý bẫy ngắt và lựa chọn kết quả ghi trả cuối cùng `w_wb_data` về Register File.

### 3.12.1 Sơ đồ khối (Block Diagram)
Tầng MEM/WB kết nối giao tiếp Port 0 của Macro SRAM, module `be_gen`, `st_align`, `load_align`, module `apb_bridge`, module `csr` và bộ chọn Write-Back MUX 4-to-1 (`w_wb_data`).

### 3.12.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.12: Bảng chân tín hiệu module `stage_mem_wb` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_clk` | Input | 1 | Clock | `i_clk` | Xung nhịp đồng bộ | Tần số danh định | N/A |
| `i_rst_n` | Input | 1 | Reset | Async | Reset bất đồng bộ tích cực mức thấp | Chuẩn hệ thống | N/A |
| `i_pc` | Input | 32 | Data | `i_clk` | Địa chỉ PC từ thanh ghi `pipe_reg_ex_mem` | Đồng bộ theo lệnh | `32'd0` |
| `i_instr` | Input | 32 | Data | `i_clk` | Mã lệnh gốc từ thanh ghi `pipe_reg_ex_mem` | Đồng bộ theo lệnh | `32'h00000013` |
| `i_valid` | Input | 1 | Control | `i_clk` | Cờ báo lệnh hợp lệ tại Tầng 3 | Mức 1 khi lệnh hợp lệ | `1'b0` |
| `i_result` | Input | 32 | Data | `i_clk` | Địa chỉ bộ nhớ hoặc kết quả tính toán từ Tầng 2 | Đồng bộ theo lệnh | `32'd0` |
| `i_store_data` | Input | 32 | Data | `i_clk` | Dữ liệu từ toán hạng RS2 cần lưu vào bộ nhớ | Đồng bộ theo lệnh | `32'd0` |
| `i_rs1_data` | Input | 32 | Data | `i_clk` | Dữ liệu từ toán hạng RS1 sau chuyển tiếp (phục vụ CSR) | Đồng bộ theo lệnh | `32'd0` |
| `i_rd_addr` | Input | 5 | Data | `i_clk` | Địa chỉ thanh ghi đích rd | 0 .. 31 | `5'd0` |
| `i_mem_read` | Input | 1 | Control | `i_clk` | Cờ yêu cầu đọc bộ nhớ | 1: Đọc bộ nhớ | `1'b0` |
| `i_mem_write` | Input | 1 | Control | `i_clk` | Cờ yêu cầu ghi bộ nhớ | 1: Ghi bộ nhớ | `1'b0` |
| `i_mem_size` | Input | 2 | Control | `i_clk` | Kích thước bộ nhớ: 00 = Byte, 01 = Half, 10 = Word | Luôn hợp lệ | `2'b00` |
| `i_mem_uns` | Input | 1 | Control | `i_clk` | Mở rộng không dấu khi đọc bộ nhớ | 1: Không dấu | `1'b0` |
| `i_result_src` | Input | 2 | Control | `i_clk` | Chọn nguồn ghi trả Write-Back | 00..11 | `2'b00` |
| `i_csr_read` | Input | 1 | Control | `i_clk` | Cờ đọc CSR | 1: Đọc CSR | `1'b0` |
| `i_csr_write` | Input | 1 | Control | `i_clk` | Cờ ghi CSR | 1: Ghi CSR | `1'b0` |
| `i_is_ecall` | Input | 1 | Control | `i_clk` | Cờ phát hiện ECALL | 1: ECALL | `1'b0` |
| `i_is_ebreak` | Input | 1 | Control | `i_clk` | Cờ phát hiện EBREAK | 1: EBREAK | `1'b0` |
| `i_is_mret` | Input | 1 | Control | `i_clk` | Cờ phát hiện MRET | 1: MRET | `1'b0` |
| `i_sleep_req` | Input | 1 | Control | `i_clk` | Cờ phát hiện WFI | 1: WFI | `1'b0` |
| `i_illegal_instr`| Input | 1 | Control | `i_clk` | Cờ phát hiện lệnh bất hợp pháp | 1: Illegal Instr | `1'b0` |
| `i_sram_rdata` | Input | 32 | Data | `i_clk` | Dữ liệu thô đọc từ Port 0 của SRAM | Đồng bộ theo chu kỳ đọc | N/A |
| `i_sram_oob_err`| Input | 1 | Control | `i_clk` | Cờ báo lỗi địa chỉ vượt quá biên 2KB SRAM | 1: Ngoài dải 2KB | `1'b0` |
| `i_ext_irq_sync`| Input | 1 | Control | `i_clk` | Tín hiệu ngắt ngoài đã đồng bộ qua `sync_2ff` | Mức 1: Có ngắt ngoài | `1'b0` |
| `i_tmr_irq_sync`| Input | 1 | Control | `i_clk` | Tín hiệu ngắt timer đã đồng bộ qua `sync_2ff` | Mức 1: Có ngắt timer | `1'b0` |
| `o_wb_data` | Output | 32 | Data | Combinational| Dữ liệu ghi trả hoàn chỉnh cấp cho RF và Forwarding | Luôn phản ánh tức thời | `32'd0` |
| `o_dmem_ready` | Output | 1 | Control | Combinational| Cờ báo hệ thống bộ nhớ/bus đã sẵn sàng dữ liệu | 1: Sẵn sàng, 0: Đang bận | `1'b1` |
| `o_trap_taken` | Output | 1 | Control | Combinational| Cờ báo bẫy ngắt/ngoại lệ được kích hoạt | 1: Kích hoạt bẫy | `1'b0` |
| `o_trap_pc` | Output | 32 | Data | Combinational| Địa chỉ vector nhảy khi bẫy hoặc quay về từ `mret` | Cấp về Tầng 1 | `32'd0` |

*Ghi chú: Khối tích hợp trọn vẹn đường dữ liệu ghi trả Write-Back và mạch bẫy ngắt an toàn.*

### 3.12.3 Nguyên lý hoạt động (Operating Principle)
- **Lựa chọn dữ liệu ghi trả (Write-Back MUX):**
  - `case (i_result_src)`
    - `2'b00`: `o_wb_data = i_result;` (Kết quả ALU, Bộ nhân, hoặc SIMD)
    - `2'b01`: `o_wb_data = formatted_mem_rdata;` (Dữ liệu đọc bộ nhớ qua `load_align`)
    - `2'b10`: `o_wb_data = i_pc + 32'd4;` (Địa chỉ liên kết JAL / JALR link address)
    - `2'b11`: `o_wb_data = w_csr_rdata;` (Dữ liệu đọc từ thanh ghi đặc quyền CSR)
- **Định tuyến bộ nhớ nội bộ vs ngoại vi MMIO:**
  - Nếu `i_result[31:24] == 8'h40`: Kích hoạt yêu cầu bus `apb_bridge`.
  - Ngược lại: Định tuyến vào Port 0 của Macro SRAM với địa chỉ word `i_result[10:2]`. Nếu `i_sram_oob_err = 1` và có yêu cầu đọc/ghi, kích hoạt ngoại lệ Access Fault.
- **Xử lý bẫy ngắt & ngoại lệ:** Kết nối với khối `csr`, bảo toàn nguyên tắc: Ngắt ngoài commit lệnh hiện tại, ngoại lệ hủy lệnh hiện tại.

### 3.12.4 Giản đồ thời gian (Timing Diagram)
Lệnh nạp `LW`: Đầu chu kỳ T3, địa chỉ đưa vào SRAM; Cuối chu kỳ T3, dữ liệu được căn chỉnh qua `load_align` và xuất hiện tại `o_wb_data`; Chốt vào Register File tại sườn dương tiếp theo.

---

## 3.13 Module: `be_gen`
**Chức năng:** Khối sinh mặt nạ byte ghi (Byte Enable Generator) tổ hợp thuần túy. Tạo ra vector 4-bit `o_we_mask` điều khiển từng byte trong từ nhớ 32-bit của SRAM dựa trên kích thước truy cập (`mem_size`) và 2 bit địa chỉ thấp (`addr[1:0]`).

### 3.13.1 Sơ đồ khối (Block Diagram)
Mạch giải mã tổ hợp nhận `i_mem_size[1:0]` và `i_addr_lsb[1:0]` xuất `o_we_mask[3:0]`.

### 3.13.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.13: Bảng chân tín hiệu module `be_gen` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_mem_size` | Input | 2 | Control | Combinational| Kích thước ghi: 00 = Byte (8b), 01 = Half (16b), 10 = Word (32b) | Luôn hợp lệ | `2'b00` |
| `i_addr_lsb` | Input | 2 | Data | Combinational| 2 bit thấp nhất của địa chỉ ghi (`addr[1:0]`) | Luôn hợp lệ | `2'b00` |
| `o_we_mask` | Output | 4 | Control | Combinational| Mặt nạ 4-bit byte write enable cấp cho SRAM hoặc APB | Luôn phản ánh tức thời | `4'b0000` |

*Ghi chú: Tránh tạo latch bằng cách gán mặc định o_we_mask = 4'b0000.*

### 3.13.3 Nguyên lý hoạt động (Operating Principle)
- Phương trình logic sinh mặt nạ byte:
  - Truy xuất Word (32-bit, `mem_size == 2'b10`): `o_we_mask = 4'b1111;`
  - Truy xuất Halfword (16-bit, `mem_size == 2'b01`):
    - `addr[1] == 1`: `o_we_mask = 4'b1100;` (Nửa từ trên)
    - `addr[1] == 0`: `o_we_mask = 4'b0011;` (Nửa từ dưới)
  - Truy xuất Byte (8-bit, `mem_size == 2'b00`):
    - `addr[1:0] == 2'b00`: `o_we_mask = 4'b0001;` (Byte 0)
    - `addr[1:0] == 2'b01`: `o_we_mask = 4'b0010;` (Byte 1)
    - `addr[1:0] == 2'b10`: `o_we_mask = 4'b0100;` (Byte 2)
    - `addr[1:0] == 2'b11`: `o_we_mask = 4'b1000;` (Byte 3)

### 3.13.4 Giản đồ thời gian (Timing Diagram)
Độ trễ lan truyền tổ hợp dưới **0.3 ns**.

---

## 3.14 Module: `st_align`
**Chức năng:** Khối căn chỉnh dữ liệu ghi bộ nhớ (Store Data Alignment) tổ hợp thuần túy. Dịch chuyển các byte hoặc halfword từ thanh ghi nguồn RS2 vào đúng vị trí byte tương ứng trong từ nhớ 32-bit chuẩn bị phát lên bus bộ nhớ.

### 3.14.1 Sơ đồ khối (Block Diagram)
Mạch multiplexer tổ hợp dịch bit toán hạng dữ liệu `i_rs2_data` theo kích thước `i_mem_size` và 2 bit địa chỉ thấp `i_addr_lsb`.

### 3.14.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.14: Bảng chân tín hiệu module `st_align` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_mem_size` | Input | 2 | Control | Combinational| Kích thước ghi: 00 = Byte, 01 = Halfword, 10 = Word | Luôn hợp lệ | `2'b00` |
| `i_addr_lsb` | Input | 2 | Data | Combinational| 2 bit thấp của địa chỉ ghi (`addr[1:0]`) | Luôn hợp lệ | `2'b00` |
| `i_rs2_data` | Input | 32 | Data | Combinational| Dữ liệu thô từ thanh ghi RS2 | Luôn hợp lệ | `32'd0` |
| `o_mem_wdata` | Output | 32 | Data | Combinational| Dữ liệu 32-bit đã căn chỉnh đưa vào SRAM hoặc APB | Luôn phản ánh tức thời | `32'd0` |

*Ghi chú: Đảm bảo dữ liệu byte/halfword được nhân bản vào đúng vị trí byte lane.*

### 3.14.3 Nguyên lý hoạt động (Operating Principle)
- Truy xuất Word: `o_mem_wdata = i_rs2_data;`
- Truy xuất Halfword: `o_mem_wdata = (i_addr_lsb[1]) ? {i_rs2_data[15:0], 16'd0} : {16'd0, i_rs2_data[15:0]};`
- Truy xuất Byte:
  - `i_addr_lsb == 2'b00`: `o_mem_wdata = {24'd0, i_rs2_data[7:0]};`
  - `i_addr_lsb == 2'b01`: `o_mem_wdata = {16'd0, i_rs2_data[7:0], 8'd0};`
  - `i_addr_lsb == 2'b10`: `o_mem_wdata = {8'd0,  i_rs2_data[7:0], 16'd0};`
  - `i_addr_lsb == 2'b11`: `o_mem_wdata = {i_rs2_data[7:0], 24'd0};`

### 3.14.4 Giản đồ thời gian (Timing Diagram)
Độ trễ tổ hợp dưới **0.4 ns**.

---

## 3.15 Module: `load_align`
**Chức năng:** Khối căn chỉnh & mở rộng dữ liệu đọc bộ nhớ (Load Data Alignment). Trích xuất byte hoặc halfword từ từ nhớ 32-bit đọc về từ SRAM/APB, đồng thời thực hiện mở rộng có dấu (`LB`, `LH`) hoặc mở rộng bù 0 (`LBU`, `LHU`) thành từ 32-bit hoàn chỉnh trước khi ghi trả về Register File.

### 3.15.1 Sơ đồ khối (Block Diagram)
Gồm bộ trích xuất byte lane theo `i_addr_lsb` và mạch mở rộng dấu / bù 0 theo cờ `i_mem_uns`.

### 3.15.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.15: Bảng chân tín hiệu module `load_align` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_mem_rdata` | Input | 32 | Data | Combinational| Dữ liệu thô 32-bit đọc về từ SRAM hoặc APB | Luôn hợp lệ | `32'd0` |
| `i_addr_lsb` | Input | 2 | Data | Combinational| 2 bit thấp của địa chỉ đọc (`addr[1:0]`) | Luôn hợp lệ | `2'b00` |
| `i_mem_size` | Input | 2 | Control | Combinational| Kích thước đọc: 00 = Byte, 01 = Halfword, 10 = Word | Luôn hợp lệ | `2'b00` |
| `i_mem_uns` | Input | 1 | Control | Combinational| Kiểu mở rộng: 1 = Mở rộng bù 0 (Unsigned), 0 = Mở rộng dấu (Signed) | Luôn hợp lệ | `1'b0` |
| `o_formatted_data`| Output | 32 | Data | Combinational| Dữ liệu 32-bit hoàn chỉnh đã căn chỉnh và mở rộng | Luôn phản ánh tức thời | `32'd0` |

*Ghi chú: Hỗ trợ đầy đủ 5 lệnh nạp RV32I: LB, LH, LW, LBU, LHU.*

### 3.15.3 Nguyên lý hoạt động (Operating Principle)
- **Bước 1: Trích xuất Byte / Halfword:**
  - Byte: Trích xuất `raw_byte = i_mem_rdata[8*i_addr_lsb +: 8]`.
  - Halfword: Trích xuất `raw_half = (i_addr_lsb[1]) ? i_mem_rdata[31:16] : i_mem_rdata[15:0]`.
- **Bước 2: Mở rộng dấu / Bù 0:**
  - `i_mem_size == 2'b00` (Byte): `o_formatted_data = i_mem_uns ? {24'd0, raw_byte} : {{24{raw_byte[7]}}, raw_byte};`
  - `i_mem_size == 2'b01` (Halfword): `o_formatted_data = i_mem_uns ? {16'd0, raw_half} : {{16{raw_half[15]}}, raw_half};`
  - `i_mem_size == 2'b10` (Word): `o_formatted_data = i_mem_rdata;`

### 3.15.4 Giản đồ thời gian (Timing Diagram)
Độ trễ tổ hợp dưới **0.5 ns**, dữ liệu sẵn sàng ngay trong chu kỳ đọc bộ nhớ.

---

## 3.16 Module: `forwarding_unit`
**Chức năng:** Khối chuyển tiếp dữ liệu đường ống (Single-Stage Forwarding Unit) tổ hợp thuần túy. Phát hiện xung đột dữ liệu RAW giữa kết quả ghi trả từ Tầng 3 (`w_wb_data`) và các toán hạng đọc tại Tầng 2 (`rs1`, `rs2`), sinh tín hiệu chọn `o_forward_a_mux` và `o_forward_b_mux`.

### 3.16.1 Sơ đồ khối (Block Diagram)
Khối so sánh địa chỉ thanh ghi đọc Tầng 2 và thanh ghi ghi Tầng 3, kết hợp cờ cho phép ghi `reg_write`.

### 3.16.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.16: Bảng chân tín hiệu module `forwarding_unit` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_id_rs1_addr` | Input | 5 | Data | Combinational| Địa chỉ thanh ghi đọc RS1 tại Tầng 2 | 0 .. 31 | `5'd0` |
| `i_id_rs2_addr` | Input | 5 | Data | Combinational| Địa chỉ thanh ghi đọc RS2 tại Tầng 2 | 0 .. 31 | `5'd0` |
| `i_mem_rd_addr` | Input | 5 | Data | Combinational| Địa chỉ thanh ghi đích RD tại Tầng 3 (Stage 3 Commit) | 0 .. 31 | `5'd0` |
| `i_mem_reg_write`| Input | 1 | Control | Combinational| Cờ cho phép ghi Register File từ Tầng 3 | 1: Có ghi trả | `1'b0` |
| `o_forward_a_mux`| Output | 1 | Control | Combinational| Điều khiển chọn chuyển tiếp toán hạng A: 1 = Chọn `w_wb_data`, 0 = Chọn RF | Luôn hợp lệ | `1'b0` |
| `o_forward_b_mux`| Output | 1 | Control | Combinational| Điều khiển chọn chuyển tiếp toán hạng B: 1 = Chọn `w_wb_data`, 0 = Chọn RF | Luôn hợp lệ | `1'b0` |

*Ghi chú: Không bao giờ chuyển tiếp cho thanh ghi x0 (x0 luôn có giá trị 0 cố định).*

### 3.16.3 Nguyên lý hoạt động (Operating Principle)
- Phương trình logic chuyển tiếp (Fix P0-4):
  - `o_forward_a_mux = i_mem_reg_write && (i_mem_rd_addr != 5'd0) && (i_mem_rd_addr == i_id_rs1_addr);`
  - `o_forward_b_mux = i_mem_reg_write && (i_mem_rd_addr != 5'd0) && (i_mem_rd_addr == i_id_rs2_addr);`
- Dữ liệu chuyển tiếp được nối trực tiếp với bus `w_wb_data` (chứa đầy đủ kết quả ALU, dữ liệu Load, kết quả Nhân, dữ liệu CSR, hoặc JAL link `PC+4`), giải quyết triệt để lỗi chuyển tiếp mất địa chỉ link của lệnh JAL.

### 3.16.4 Giản đồ thời gian (Timing Diagram)
Thời gian trễ so sánh và sinh cờ chuyển tiếp dưới **0.4 ns**.

---

## 3.17 Module: `hazard_unit`
**Chức năng:** Khối quản lý xung đột và điều phối đường ống (Hazard Unit) tổ hợp. Giám sát toàn bộ các nguyên nhân nghẽn đường ống (Load-to-Use stall, Multiplier busy stall, APB busy stall, Branch misprediction flush, Trap/Interrupt coordination), sinh các tín hiệu đóng băng `o_stall_pc`, `o_stall_pipe`, xóa `o_flush_pipe`, cho phép ghi `o_wb_en`, và cho phép truy xuất bộ nhớ `o_mem_en`.

### 3.17.1 Sơ đồ khối (Block Diagram)
Khối logic tổ hợp tiếp nhận các cờ bận từ bộ nhân, APB, bộ giải mã và CSR, giải mã các điều kiện xung đột và khử vòng lặp tổ hợp APB.

### 3.17.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.17: Bảng chân tín hiệu module `hazard_unit` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_rst_n` | Input | 1 | Reset | Async | Reset bất đồng bộ tích cực mức thấp | Chuẩn hệ thống | N/A |
| `i_branch_taken` | Input | 1 | Control | Combinational| Cờ báo rẽ nhánh thành công từ Tầng 2 | 1: Rẽ nhánh | `1'b0` |
| `i_trap_taken` | Input | 1 | Control | Combinational| Cờ báo bẫy ngắt hoặc ngoại lệ từ CSR Unit | 1: Có bẫy | `1'b0` |
| `i_exc_req` | Input | 1 | Control | Combinational| Cờ báo yêu cầu ngoại lệ đồng bộ (Sync Exception) | 1: Có ngoại lệ | `1'b0` |
| `i_dmem_ready` | Input | 1 | Control | Combinational| Cờ báo hệ thống bộ nhớ SRAM/APB đã sẵn sàng | 1: Sẵn sàng, 0: Đang bận | `1'b1` |
| `i_mul_busy` | Input | 1 | Control | Combinational| Cờ báo bộ nhân đang bận tính toán 8 chu kỳ | 1: Bộ nhân bận | `1'b0` |
| `i_stall_load_use`| Input | 1 | Control | Combinational| Cờ phát hiện xung đột nạp-dùng Load-to-Use | 1: Có xung đột nạp | `1'b0` |
| `o_stall_pc` | Output | 1 | Control | Combinational| Tín hiệu đóng băng con trỏ PC tại Tầng IF | 1: Đóng băng PC | `1'b0` |
| `o_stall_pipe` | Output | 1 | Control | Combinational| Tín hiệu đóng băng thanh ghi `pipe_reg_if_id`, `pipe_reg_ex_mem` | 1: Đóng băng pipe | `1'b0` |
| `o_flush_pipe` | Output | 1 | Control | Combinational| Tín hiệu xóa đường ống khi rẽ nhánh hoặc bẫy ngắt | 1: Xóa pipe | `1'b0` |
| `o_mem_en` | Output | 1 | Control | Combinational| Tín hiệu cho phép truy xuất bộ nhớ và phát lệnh APB | 1: Cho phép truy xuất | `1'b1` |
| `o_wb_en` | Output | 1 | Control | Combinational| Tín hiệu cho phép ghi trả tập thanh ghi Register File | 1: Cho phép ghi trả | `1'b1` |

*Ghi chú: Khử hoàn toàn vòng lặp tổ hợp APB bằng cách tách biệt `o_mem_en` và `i_dmem_ready` thông qua `~i_exc_req`.*

### 3.17.3 Nguyên lý hoạt động (Operating Principle)
- **Khử vòng lặp tổ hợp APB (Fix P0-6):**
  - Tín hiệu `o_mem_en` được gán: `o_mem_en = ~i_exc_req;`
  - Nhờ đó, đường truyền tín hiệu `i_dmem_ready -> w_mem_busy -> o_trap_taken` KHÔNG còn quay ngược trở lại điều khiển `o_mem_en`, triệt tiêu hoàn toàn vòng lặp tổ hợp phản hồi (Combinational Loop).
- **Mô hình Commit an toàn khi có Bẫy/Ngắt (Fix P0-5):**
  - Tín hiệu `o_wb_en` được điều khiển theo phương trình: `o_wb_en = (~w_mem_busy) & (~i_exc_req);`
  - Khi có ngắt bất đồng bộ (`i_int_req = 1`, `i_exc_req = 0`), Tầng 3 được phép ghi trả hoàn tất `o_wb_en = 1` và `o_mem_en = 1`. Lệnh hiện tại được commit và `mepc` lưu giá trị lệnh kế tiếp `PC+4`.
  - Khi có ngoại lệ đồng bộ (`i_exc_req = 1`), ghi trả Tầng 3 bị hủy `o_wb_en = 0` và `mepc` lưu địa chỉ lệnh lỗi `PC`.
- **Đóng băng và Xóa đường ống:**
  - `w_mem_busy = ~i_dmem_ready;`
  - `w_stall_cond = i_stall_load_use | i_mul_busy | w_mem_busy;`
  - `o_stall_pc = w_stall_cond;`
  - `o_stall_pipe = w_stall_cond;`
  - `o_flush_pipe = i_branch_taken | i_trap_taken;`

### 3.17.4 Giản đồ thời gian (Timing Diagram)
Thời gian trễ lan truyền tổ hợp giải mã xung đột dưới **1.2 ns**.

---

## 3.18 Module: `csr`
**Chức năng:** Khối thanh ghi đặc quyền Machine-Mode CSR và điều khiển bẫy ngắt (CSR & Trap Controller). Quản lý toàn bộ thanh ghi đặc quyền RISC-V, xử lý ngắt bất đồng bộ (Timer, External) và ngoại lệ đồng bộ (Illegal Instruction, Breakpoint, ECALL, Memory Access Fault), hỗ trợ lệnh `MRET` và `WFI`.

### 3.18.1 Sơ đồ khối (Block Diagram)
Bao gồm mảng thanh ghi đặc quyền 32-bit (`mstatus`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`), mạch phát hiện ngắt/ngoại lệ, bộ chọn vector địa chỉ nhảy `o_trap_pc` và logic khôi phục cờ ngắt khi `MRET`.

### 3.18.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.18: Bảng chân tín hiệu module `csr` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_clk` | Input | 1 | Clock | `i_clk` | Xung nhịp đồng bộ | Tần số danh định | N/A |
| `i_rst_n` | Input | 1 | Reset | Async | Reset bất đồng bộ tích cực mức thấp | Chuẩn hệ thống | N/A |
| `i_pc` | Input | 32 | Data | `i_clk` | Địa chỉ PC của lệnh tại Tầng 3 | Đồng bộ theo lệnh | `32'd0` |
| `i_instr` | Input | 32 | Data | `i_clk` | Mã lệnh gốc tại Tầng 3 | Đồng bộ theo lệnh | `32'h00000013` |
| `i_valid` | Input | 1 | Control | `i_clk` | Cờ báo lệnh Tầng 3 hợp lệ (Khóa ngắt khi gặp bong bóng NOP) | Mức 1: Lệnh hợp lệ | `1'b0` |
| `i_csr_addr` | Input | 12 | Data | `i_clk` | Địa chỉ thanh ghi CSR (12-bit) từ lệnh | Luôn hợp lệ | `12'd0` |
| `i_csr_read` | Input | 1 | Control | `i_clk` | Cờ yêu cầu đọc thanh ghi CSR | 1: Đọc CSR | `1'b0` |
| `i_csr_write` | Input | 1 | Control | `i_clk` | Cờ yêu cầu ghi thanh ghi CSR | 1: Ghi CSR | `1'b0` |
| `i_rs1_data` | Input | 32 | Data | `i_clk` | Dữ liệu ghi CSR từ toán hạng RS1 sau chuyển tiếp (Fix P0-2) | Có hiệu lực khi csr_write | `32'd0` |
| `i_ext_irq` | Input | 1 | Control | `i_clk` | Tín hiệu ngắt ngoài đã được đồng bộ qua `sync_2ff` | Mức 1: Có ngắt ngoài | `1'b0` |
| `i_timer_irq` | Input | 1 | Control | `i_clk` | Tín hiệu ngắt định thời đã đồng bộ qua `sync_2ff` | Mức 1: Có ngắt timer | `1'b0` |
| `i_is_ecall` | Input | 1 | Control | `i_clk` | Cờ phát hiện lệnh ECALL từ Tầng 3 | 1: Lệnh ECALL | `1'b0` |
| `i_is_ebreak` | Input | 1 | Control | `i_clk` | Cờ phát hiện lệnh EBREAK từ Tầng 3 (Fix R-16) | 1: Lệnh EBREAK | `1'b0` |
| `i_is_mret` | Input | 1 | Control | `i_clk` | Cờ phát hiện lệnh quay về MRET từ Tầng 3 | 1: Lệnh MRET | `1'b0` |
| `i_sleep_req` | Input | 1 | Control | `i_clk` | Cờ phát hiện lệnh WFI | 1: Lệnh WFI | `1'b0` |
| `i_illegal_instr`| Input | 1 | Control | `i_clk` | Cờ phát hiện lệnh bất hợp pháp từ Tầng 3 (Fix P0-7) | 1: Lệnh bất hợp pháp | `1'b0` |
| `i_mem_access_fault`| Input| 1 | Control | `i_clk` | Cờ phát hiện lỗi truy cập bộ nhớ ngoài biên 2KB (Fix R-12) | 1: Ngoài biên 2KB | `1'b0` |
| `o_csr_rdata` | Output | 32 | Data | Combinational| Dữ liệu đọc từ thanh ghi CSR chuyển về Write-Back MUX (Fix P0-1)| Luôn phản ánh tức thời | `32'd0` |
| `o_trap_pc` | Output | 32 | Data | Combinational| Địa chỉ vector chuyển hướng nhảy (mtvec hoặc mepc) | Cấp về Tầng 1 | `32'd0` |
| `o_trap_taken` | Output | 1 | Control | Combinational| Cờ báo bẫy ngắt/ngoại lệ được kích hoạt trong chu kỳ này | Cấp cho Hazard Unit | `1'b0` |
| `o_int_req` | Output | 1 | Control | Combinational| Cờ báo có yêu cầu ngắt bất đồng bộ được chấp nhận | Cấp cho Hazard Unit | `1'b0` |
| `o_exc_req` | Output | 1 | Control | Combinational| Cờ báo có yêu cầu ngoại lệ đồng bộ được chấp nhận | Cấp cho Hazard Unit | `1'b0` |

*Ghi chú: Khối CSR được định vị chính xác tại Tầng 3 (MEM/WB), giải quyết triệt để lỗi chốt dữ liệu sớm P0-1 và lỗi toán hạng RS2 P0-2.*

### 3.18.3 Nguyên lý hoạt động (Operating Principle)
- **Đọc dữ liệu CSR tức thời tại Tầng 3 (Fix P0-1):**
  - Dữ liệu `o_csr_rdata` được đọc trực tiếp từ thanh ghi CSR tương ứng với địa chỉ `i_csr_addr` và đưa thẳng vào Write-Back MUX tại Tầng 3, không qua chốt trung gian, loại bỏ hoàn toàn hiện tượng đọc dữ liệu cũ hoặc bằng 0.
- **Toán hạng ghi CSR từ RS1 (Fix P0-2):**
  - Chân `i_rs1_data` được nối với bus dữ liệu toán hạng RS1 sau chuyển tiếp (thay vì nối nhầm với store data của RS2).
- **Khóa ngắt khi gặp bong bóng NOP (Fix P0-5):**
  - `o_int_req = (w_is_ext_irq | w_is_tmr_irq) & i_valid;`
  - Đảm bảo ngắt chỉ được tiếp nhận khi Tầng 3 có lệnh hợp lệ (`i_valid = 1`), không bao giờ bẫy ngắt khi pipeline đang bị flush.
- **Lưu trữ `mepc` và vector nhảy:**
  - Nếu là ngắt bất đồng bộ (`o_int_req = 1`): `mepc <= i_pc + 32'd4;` (Lệnh Tầng 3 commit hoàn tất, sau ngắt sẽ chạy lệnh kế).
  - Nếu là ngoại lệ đồng bộ (`o_exc_req = 1`): `mepc <= i_pc;` (Lệnh Tầng 3 bị hủy, sau bẫy sẽ thực thi lại lệnh lỗi).
- **Căn chỉnh địa chỉ vector `mtvec` (Fix R-17):**
  - Khi ghi `mtvec`: Ở chế độ Direct Mode (`mode == 2'b00`), 2 bit thấp bị ép về 0: `r_mtvec <= {i_rs1_data[31:2], 2'b00};`
- **Hỗ trợ đầy đủ quyền đọc/ghi `mtval` (Fix R-17):**
  - Cho phép phần mềm ghi trực tiếp vào `mtval` qua địa chỉ `12'h343`. Khi phát sinh ngoại lệ Illegal Instruction, phần cứng tự động ghi mã lệnh lỗi vào `mtval`. Khi phát sinh ngoại lệ Access Fault, phần cứng tự động ghi địa chỉ lỗi ngoài biên vào `mtval`.

### 3.18.4 Giản đồ thời gian (Timing Diagram)
- Khi phát sinh ngoại lệ: Tại sườn dương `i_clk`, `mepc` chốt địa chỉ `i_pc`, `mcause` nhận mã lỗi, `o_trap_taken = 1` chuyển hướng con trỏ PC về `mtvec`.
- Khi thực thi lệnh `MRET`: Tại sườn dương `i_clk`, cờ `mstatus.MIE` được khôi phục từ `MPIE`, `o_trap_pc = mepc`, PC nhảy về địa chỉ lưu trong `mepc`.

---

## 3.19 Module: `sync_2ff`
**Chức năng:** Khối đồng bộ hóa 2 tầng Flip-Flop (Two-Flip-Flop Synchronizer) chống hiện tượng siêu ổn định (Metastability) cho các tín hiệu ngắt bất đồng bộ đi từ bên ngoài chip vào lõi vi xử lý.

### 3.19.1 Sơ đồ khối (Block Diagram)
Gồm 2 tầng D-Flip-Flop mắc nối tiếp, được gán thuộc tính tổng hợp `ASYNC_REG = "TRUE"` để các công cụ PnR (OpenROAD / Vivado) tự động đặt các cell kề nhau và bảo toàn đường trễ.

### 3.19.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.19: Bảng chân tín hiệu module `sync_2ff` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_clk` | Input | 1 | Clock | `i_clk` | Xung nhịp đồng bộ của lõi CPU | Tần số danh định | N/A |
| `i_rst_n` | Input | 1 | Reset | Async | Reset bất đồng bộ tích cực mức thấp | Chuẩn hệ thống | N/A |
| `i_async_signal`| Input | 1 | Logic | Async | Tín hiệu bất đồng bộ từ bên ngoài chip (`i_ext_irq`, `i_timer_irq`)| Bất kỳ | `1'b0` |
| `o_sync_signal` | Output | 1 | Logic | `i_clk` | Tín hiệu đã được đồng bộ hóa hoàn toàn vào miền clock `i_clk` | Luôn hợp lệ | `1'b0` |

*Ghi chú: Độ trễ lan truyền đồng bộ hóa là đúng 2 chu kỳ clock của i_clk.*

### 3.19.3 Nguyên lý hoạt động (Operating Principle)
- Phương trình chuyển trạng thái 2 tầng:
  - `always @(posedge i_clk or negedge i_rst_n)`
    - `if (!i_rst_n) begin r_meta <= 1'b0; r_sync <= 1'b0; end`
    - `else begin r_meta <= i_async_signal; r_sync <= r_meta; end`
  - `assign o_sync_signal = r_sync;`

### 3.19.4 Giản đồ thời gian (Timing Diagram)
Tín hiệu bất đồng bộ chuyển mức tại thời điểm ngẫu nhiên; Tầng 1 (`r_meta`) hấp thụ hiện tượng siêu ổn định; Tầng 2 (`r_sync`) xuất tín hiệu sạch sau đúng **2 chu kỳ clock**.

---

## 3.20 Module: `apb_bridge`
**Chức năng:** Cầu nối bus ngoại vi AMBA 4 APB Master. Chuyển đổi các yêu cầu đọc/ghi bộ nhớ trong dải địa chỉ MMIO (`0x4000_0000` .. `0x40FF_FFFF`) thành giao dịch chuẩn bus APB, hỗ trợ chu kỳ chờ linh hoạt thông qua tín hiệu `i_apb_pready`, phát hiện lỗi bus `i_apb_pslverr` và hỗ trợ mặt nạ byte `o_apb_pstrb`.

### 3.20.1 Sơ đồ khối (Block Diagram)
Bao gồm máy trạng thái hữu hạn FSM 3 trạng thái (`S_IDLE`, `S_SETUP`, `S_ACCESS`), các thanh ghi chốt địa chỉ, dữ liệu ghi, mặt nạ byte strobe và cờ báo bận `o_apb_busy`.

### 3.20.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.20: Bảng chân tín hiệu module `apb_bridge` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_clk` | Input | 1 | Clock | `i_clk` | Xung nhịp đồng bộ hệ thống | Tần số danh định | N/A |
| `i_rst_n` | Input | 1 | Reset | Async | Reset bất đồng bộ tích cực mức thấp | Chuẩn hệ thống | N/A |
| `i_bus_req` | Input | 1 | Control | `i_clk` | Tín hiệu yêu cầu mở giao dịch bus từ Tầng 3 | Mức 1: Có yêu cầu MMIO | `1'b0` |
| `i_bus_write` | Input | 1 | Control | `i_clk` | Hướng truyền dữ liệu: 1 = Ghi, 0 = Đọc | Có hiệu lực khi bus_req = 1 | `1'b0` |
| `i_bus_addr` | Input | 32 | Data | `i_clk` | Địa chỉ truy xuất ngoại vi MMIO | Có hiệu lực khi bus_req = 1 | `32'd0` |
| `i_bus_wdata` | Input | 32 | Data | `i_clk` | Dữ liệu cần ghi ra ngoại vi MMIO | Có hiệu lực khi bus_write = 1 | `32'd0` |
| `i_bus_wstrb` | Input | 4 | Control | `i_clk` | Mặt nạ byte ghi (PSTRB) từ `be_gen` | Có hiệu lực khi bus_write = 1 | `4'b0000` |
| `o_bus_rdata` | Output | 32 | Data | `i_clk` | Dữ liệu đọc từ ngoại vi MMIO trả về cho Tầng 3 | Có hiệu lực khi bus_done = 1 | `32'd0` |
| `o_bus_done` | Output | 1 | Flag | `i_clk` | Cờ xung báo hoàn tất giao dịch APB | Mức 1 đúng 1 chu kỳ | `1'b0` |
| `o_bus_err` | Output | 1 | Flag | `i_clk` | Cờ báo phát sinh lỗi từ slave (`pslverr`) | Kích hoạt khi có lỗi slave | `1'b0` |
| `o_apb_busy` | Output | 1 | Control | `i_clk` | Cờ báo cầu nối đang bận, yêu cầu Hazard Unit dừng pipeline | Mức 1 trong suốt giao dịch | `1'b0` |
| `o_apb_paddr` | Output | 32 | Data | `i_clk` | Đường địa chỉ bus APB phát tới các slave | Chuẩn AMBA APB | `32'd0` |
| `o_apb_pwrite` | Output | 1 | Control | `i_clk` | Hướng bus APB: 1 = Ghi, 0 = Đọc | Chuẩn AMBA APB | `1'b0` |
| `o_apb_pstrb` | Output | 4 | Control | `i_clk` | Mặt nạ byte lane APB4 | Chuẩn AMBA APB | `4'b0000` |
| `o_apb_psel` | Output | 1 | Control | `i_clk` | Tín hiệu chọn slave APB (PSEL) | Chuẩn AMBA APB | `1'b0` |
| `o_apb_penable`| Output | 1 | Control | `i_clk` | Tín hiệu kích hoạt truyền nhận APB (PENABLE) | Chuẩn AMBA APB | `1'b0` |
| `o_apb_pwdata` | Output | 32 | Data | `i_clk` | Đường dữ liệu ghi APB (PWDATA) | Chuẩn AMBA APB | `32'd0` |
| `i_apb_prdata` | Input | 32 | Data | `i_clk` | Đường dữ liệu đọc APB từ slave (PRDATA) | Hợp lệ khi PREADY = 1 | N/A |
| `i_apb_pready` | Input | 1 | Control | `i_clk` | Tín hiệu báo sẵn sàng từ slave APB (PREADY) | Mức 1: Hoàn tất; Mức 0: Chờ | N/A |
| `i_apb_pslverr`| Input | 1 | Control | `i_clk` | Tín hiệu báo lỗi truyền nhận từ slave APB (PSLVERR) | Mức 1: Báo lỗi slave | N/A |

*Ghi chú: Hỗ trợ đầy đủ chuẩn AMBA 4 APB Protocol, cho phép slave chèn không giới hạn chu kỳ chờ (Wait-States).*

### 3.20.3 Nguyên lý hoạt động (Operating Principle)
- **FSM 3 trạng thái chuẩn AMBA APB:**
  - `S_IDLE (2'b00)`:
    - Khi nhận `i_bus_req = 1`: Chốt địa chỉ, dữ liệu, mặt nạ byte, phát `o_apb_psel = 1`, `o_apb_penable = 0`, `o_apb_busy = 1`, chuyển sang `S_SETUP`.
  - `S_SETUP (2'b01)`:
    - Sau đúng 1 chu kỳ, giữ nguyên `o_apb_psel = 1`, kích hoạt `o_apb_penable = 1`, chuyển sang `S_ACCESS`.
  - `S_ACCESS (2'b10)`:
    - Giữ `o_apb_psel = 1`, `o_apb_penable = 1`.
    - Kiểm tra tín hiệu báo sẵn sàng `i_apb_pready`:
      - Nếu `i_apb_pready == 1'b0`: Giữ nguyên trạng thái `S_ACCESS` (Chèn chu kỳ chờ Wait-State).
      - Nếu `i_apb_pready == 1'b1`: Hoàn tất giao dịch. Nếu là lệnh đọc, chốt `o_bus_rdata <= i_apb_prdata`; Chốt cờ lỗi `o_bus_err <= i_apb_pslverr`; Phát xung `o_bus_done <= 1'b1`; Hạ `o_apb_busy <= 1'b0`, `o_apb_psel <= 1'b0`, `o_apb_penable <= 1'b0`, chuyển về `S_IDLE`.

### 3.20.4 Giản đồ thời gian (Timing Diagram)
- **Chu kỳ T1 (SETUP phase):** `PSEL = 1`, `PENABLE = 0`, `PADDR`, `PWDATA` xuất hiện.
- **Chu kỳ T2 (ACCESS phase):** `PENABLE = 1`. Nếu slave kéo `PREADY = 0`, giữ nguyên trạng thái.
- **Chu kỳ T3:** `PREADY = 1`, dữ liệu đọc được chốt, `PSEL = 0`, `PENABLE = 0`, hoàn tất giao dịch trong 2 chu kỳ cơ sở (+ số chu kỳ wait-state).

---

## 3.21 Module: `rvc_decompressor`
**Chức năng:** Bộ giải mã và giải nén lệnh nén 16-bit RISC-V (RV32C) tổ hợp thuần túy. Nhận lệnh nén 16-bit `i_c_instr[15:0]`, chuyển đổi tức thời thành mã lệnh 32-bit tiêu chuẩn tương đương của tập lệnh RV32I.

### 3.21.1 Sơ đồ khối (Block Diagram)
Mạch logic tổ hợp giải mã phân loại theo 3 góc quadrant mã lệnh nén: `Q0 (2'b00)`, `Q1 (2'b01)`, `Q2 (2'b10)`.

### 3.21.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.21: Bảng chân tín hiệu module `rvc_decompressor` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `i_c_instr` | Input | 16 | Data | Combinational| Mã lệnh nén 16-bit đầu vào | Luôn hợp lệ | `16'd0` |
| `o_decomp_instr`| Output | 32 | Data | Combinational| Mã lệnh 32-bit RV32I tiêu chuẩn tương đương | Luôn phản ánh tức thời | `32'h00000013` |
| `o_illegal_instr`| Output | 1 | Flag | Combinational| Cờ báo lệnh nén không hợp lệ (Reserved / Illegal C-opcode) | 1: Lệnh nén không hợp lệ | `1'b0` |

*Ghi chú: Toàn bộ quá trình giải nén thực hiện trong 1 chu kỳ tổ hợp, độ trễ lan truyền dưới 1.2 ns.*

### 3.21.3 Nguyên lý hoạt động (Operating Principle)
- **Giải mã theo góc Quadrant (2 bit thấp `instr[1:0]`):**
  - **Quadrant 0 (`2'b00`):**
    - `C.ADDI4SPN`: Chuyển thành `addi rd', sp, nzuimm`.
    - `C.LW`: Chuyển thành `lw rd', offset(rs1')`.
    - `C.SW`: Chuyển thành `sw rs2', offset(rs1')`.
  - **Quadrant 1 (`2'b01`):**
    - `C.NOP / C.ADDI`: Chuyển thành `addi rd, rd, imm`.
    - `C.JAL (RV32C)`: Chuyển thành `jal ra, offset`.
    - `C.LI`: Chuyển thành `addi rd, x0, imm`.
    - `C.LUI / C.ADDI16SP`: Chuyển thành `lui rd, imm` hoặc `addi sp, sp, imm`.
    - `C.SRLI / C.SRAI / C.ANDI / C.SUB / C.XOR / C.OR / C.AND`: Chuyển thành các lệnh ALU RV32I tương ứng.
    - `C.J`: Chuyển thành `jal x0, offset`.
    - `C.BEQZ / C.BNEZ`: Chuyển thành `beq rs1', x0, offset` / `bne rs1', x0, offset`.
  - **Quadrant 2 (`2'b10`):**
    - `C.SLLI`: Chuyển thành `slli rd, rd, shamt`.
    - `C.LWSP`: Chuyển thành `lw rd, offset(sp)`.
    - `C.JR / C.MV`: Chuyển thành `jalr x0, 0(rs1)` hoặc `add rd, x0, rs2`.
    - `C.EBREAK / C.JALR / C.ADD`: Chuyển thành `ebreak`, `jalr ra, 0(rs1)` hoặc `add rd, rd, rs2`.
    - `C.SWSP`: Chuyển thành `sw rs2, offset(sp)`.

### 3.21.4 Giản đồ thời gian (Timing Diagram)
Lệnh nén 16-bit vào đầu chu kỳ nạp lệnh, xuất mã 32-bit hoàn chỉnh sau **1.2 ns** để cấp trực tiếp cho `pipe_reg_if_id`.

---

## 3.22 Module: `sky130_sram_2kbyte_1rw1r_32x512_8`
**Chức năng:** Macro bộ nhớ nội bộ SRAM 2KB Dual-Port 1RW1R trên tiến trình SkyWater 130nm do OpenRAM tạo ra. Cung cấp 512 từ nhớ 32-bit (2048 bytes), hỗ trợ 2 cổng truy cập độc lập song song: Port 0 (1RW - Đọc/Ghi dữ liệu Tầng MEM) và Port 1 (1R - Đọc mã lệnh Tầng IF).

### 3.22.1 Sơ đồ khối (Block Diagram)
Khối macro cứng vật lý (Hard Macro) tích hợp mảng nhớ SRAM, mạch giải mã địa chỉ, bộ khuếch đại cảm biến (Sense Amplifiers) và mạch chốt địa chỉ/dữ liệu theo sườn xung nhịp.

### 3.22.2 Bảng chân tín hiệu (I/O Interface Table)
**Bảng 3.22: Bảng chân tín hiệu module `sky130_sram_2kbyte_1rw1r_32x512_8` (I/O Interface Table)**

| Tên chân tín hiệu | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset |
| :--- | :---: | :---: | :---: | :---: | :--- | :--- | :---: |
| `clk0` | Input | 1 | Clock | `i_clk` | Xung nhịp Port 0 (Data Access) | Tần số danh định | N/A |
| `csb0` | Input | 1 | Control | `i_clk` | Chip select Port 0, tích cực mức thấp (0 = Kích hoạt) | 0: Kích hoạt Port 0 | `1'b1` |
| `web0` | Input | 1 | Control | `i_clk` | Write enable Port 0, tích cực mức thấp (0 = Ghi, 1 = Đọc) | 0: Ghi, 1: Đọc | `1'b1` |
| `wmask0` | Input | 4 | Control | `i_clk` | Mặt nạ byte enable Port 0 (1 = Ghi byte tương ứng) | Có hiệu lực khi web0 = 0 | `4'b0000` |
| `addr0` | Input | 9 | Data | `i_clk` | Địa chỉ từ nhớ 9-bit Port 0 (0 .. 511 words) | 9-bit word address | `9'd0` |
| `din0` | Input | 32 | Data | `i_clk` | Dữ liệu 32-bit ghi vào Port 0 | Có hiệu lực khi web0 = 0 | `32'd0` |
| `dout0` | Output | 32 | Data | `i_clk` | Dữ liệu 32-bit đọc ra từ Port 0 | Hợp lệ sau khi đọc | N/A |
| `clk1` | Input | 1 | Clock | `i_clk` | Xung nhịp Port 1 (Instruction Fetch) | Tần số danh định | N/A |
| `csb1` | Input | 1 | Control | `i_clk` | Chip select Port 1, tích cực mức thấp (0 = Kích hoạt) | 0: Kích hoạt Port 1 | `1'b1` |
| `addr1` | Input | 9 | Data | `i_clk` | Địa chỉ từ nhớ 9-bit Port 1 (0 .. 511 words) | 9-bit word address | `9'd0` |
| `dout1` | Output | 32 | Data | `i_clk` | Dữ liệu 32-bit đọc ra từ Port 1 (Mã lệnh) | Hợp lệ sau khi nạp | N/A |

*Ghi chú: Địa chỉ đầu vào là địa chỉ từ nhớ 9-bit (`addr[10:2]`). Dung lượng vật lý chính xác 2048 bytes.*

### 3.22.3 Nguyên lý hoạt động (Operating Principle)
- **Hành vi xung nhịp và truy xuất:**
  - Macro chốt tín hiệu điều khiển `csb`, `web`, `wmask` và địa chỉ `addr` tại sườn dương xung nhịp (`posedge clk`).
  - Mảng nhớ nội bộ thực hiện đọc hoặc ghi tại sườn âm xung nhịp (`negedge clk`), bảo đảm thời gian thiết lập (Setup Time) và thời gian giữ (Hold Time) an toàn cho dữ liệu.
- **Mạch kiểm tra biên phần cứng 2KB (Hardware Bounds Check - Fix R-12):**
  - Tại `core_top.v`, địa chỉ truy cập dữ liệu được giám sát chặt chẽ:
    - `w_sram_oob_error = (w_mem_addr >= 32'd2048) & (w_mem_addr[31:24] != 8'h40);`
  - Nếu phần mềm truy xuất địa chỉ lớn hơn hoặc bằng 2048 byte và không thuộc dải MMIO (`0x4000_0000`), mạch tự động ngắt kết nối SRAM (`w_dmem_csb = 1'b1`) và phát tín hiệu `w_sram_oob_error = 1` kích hoạt ngoại lệ Load Access Fault (`mcause = 5`) hoặc Store Access Fault (`mcause = 7`), địa chỉ vi phạm được lưu tự động vào `mtval`.

### 3.22.4 Giản đồ thời gian (Timing Diagram)
- **Cổng 1 (Nạp lệnh):** Sườn dương T1 chốt `addr1`; Trước sườn dương T2, `dout1` ổn định sẵn sàng nạp vào thanh ghi đường ống.
- **Cổng 0 (Đọc dữ liệu):** Sườn dương T2 chốt `addr0`; Trước sườn dương T3, `dout0` ổn định cung cấp cho Write-Back MUX.
- Cả hai cổng hoạt động đồng thời 100% không xung đột.


---

# CHƯƠNG 4: MA TRẬN TRUY XUẤT YÊU CẦU (RTM) & KẾ HOẠCH KIỂM CHỨNG

## 4.1 Ma trận truy xuất yêu cầu kiểm tra (Requirement Traceability Matrix - RTM)

**Bảng 4.1: Ma trận truy xuất yêu cầu kỹ thuật (Requirement Traceability Matrix)**

| Mã Yêu Cầu | Tên Yêu Cầu Chức Năng | Module RTL Thực Thi | File Mã Nguồn RTL | Testbench Kiểm Chứng | Trạng Thái Kiểm Chứng |
| :--- | :--- | :--- | :--- | :--- | :---: |
| `REQ-ISA-01` | RV32I Base Integer ISA | `instruction_decoder`, `alu`, `load_align`, `st_align` | `rtl/core/instruction_decoder.v`, `alu.v` | `tb_isa_compliance.v`, `tb_bubble_sort.v` | **100% PASS** |
| `REQ-ISA-02` | RV32M Hardware Multiplier | `booth_multiplier_32b`, `instruction_decoder` | `rtl/core/booth_multiplier_32b.v` | `tb_phase2_math_ai.v`, `tb_phase5_datapath_p0.v` | **100% PASS** |
| `REQ-ISA-03` | RV32C Compressed Instructions | `rvc_decompressor`, `stage_if` | `rtl/core/rvc_decompressor.v`, `stage_if.v` | `tb_rvc_decompressor.v`, `tb_rvc_pipeline.v` | **100% PASS** |
| `REQ-ISA-04` | Zicsr Privileged Architecture | `csr`, `stage_mem_wb` | `rtl/core/csr.v`, `stage_mem_wb.v` | `tb_phase5_datapath_p0.v`, `tb_phase6_control_traps.v`| **100% PASS** |
| `REQ-ISA-05` | Custom Packed SIMD 4x INT8 | `simd_mac_unit`, `stage_id_ex` | `rtl/core/simd_mac_unit.v` | `tb_phase2_math_ai.v`, `tb_ai_benchmark.v` | **100% PASS** |
| `REQ-PIPE-01` | 3-Stage Linear Pipeline | `stage_if`, `pipe_reg_if_id`, `stage_id_ex`, `pipe_reg_ex_mem`, `stage_mem_wb` | `rtl/core/core_top.v` | `tb_bubble_sort.v`, `tb_phase3_hazards.v` | **100% PASS** |
| `REQ-PIPE-02` | Single-Stage Forwarding | `forwarding_unit`, `stage_id_ex` | `rtl/core/forwarding_unit.v` | `tb_phase5_datapath_p0.v` | **100% PASS** |
| `REQ-PIPE-03` | Branch Mispredict Penalty (2 cycles) | `branch_comparator`, `stage_if` | `rtl/core/branch_comparator.v`, `stage_if.v`| `tb_phase3_hazards.v`, `tb_bubble_sort.v` | **100% PASS** |
| `REQ-MATH-01` | Radix-16 Multiplier (8 cycles) | `booth_multiplier_32b`, `stage_id_ex` | `rtl/core/booth_multiplier_32b.v` | `tb_phase2_math_ai.v`, `tb_phase5_datapath_p0.v` | **100% PASS** |
| `REQ-MATH-02` | Single-Cycle SIMD MAC | `simd_mac_unit` | `rtl/core/simd_mac_unit.v` | `tb_phase2_math_ai.v`, `tb_ai_benchmark.v` | **100% PASS** |
| `REQ-MEM-01` | 2KB Dual-Port SRAM 1RW1R | `sky130_sram_2kbyte_1rw1r_32x512_8` | `rtl/memory/sky130_sram_*.v` | Toàn bộ 9 Testbenches | **100% PASS** |
| `REQ-MEM-02` | Hardware 2KB Bounds Check | `core_top`, `csr` | `rtl/core/core_top.v`, `csr.v` | `tb_phase6_control_traps.v` | **100% PASS** |
| `REQ-MEM-03` | Memory Data Alignment | `load_align`, `st_align`, `be_gen` | `rtl/core/load_align.v`, `st_align.v`, `be_gen.v`| `tb_isa_compliance.v`, `tb_bubble_sort.v` | **100% PASS** |
| `REQ-BUS-01` | AMBA 4 APB Master Bridge | `apb_bridge`, `stage_mem_wb` | `rtl/bus/apb_bridge.v` | `tb_phase6_control_traps.v` | **100% PASS** |
| `REQ-BUS-02` | Combinational Loop Free APB | `hazard_unit`, `core_top` | `rtl/core/hazard_unit.v` | `tb_phase6_control_traps.v`, `make lint` | **100% PASS** |
| `REQ-CSR-01` | Trap Commit Model (Async commit, Sync cancel)| `csr`, `hazard_unit` | `rtl/core/csr.v`, `hazard_unit.v` | `tb_phase6_control_traps.v` | **100% PASS** |
| `REQ-CSR-02` | IRQ Bubble Gate | `csr` | `rtl/core/csr.v` | `tb_phase6_control_traps.v` | **100% PASS** |
| `REQ-CSR-03` | mtvec Direct Mode Vector Masking & mtval RW | `csr` | `rtl/core/csr.v` | `tb_phase6_control_traps.v` | **100% PASS** |
| `REQ-SYNC-01` | 2-FF Interrupt Synchronizer | `sync_2ff` | `rtl/core/sync_2ff.v` | `tb_phase6_control_traps.v` | **100% PASS** |
| `REQ-PHY-01` | Physical PnR Tape-out Signoff | `riscv_core_top` | `config.json`, `riscv_core_top.sdc` | OpenLane v2.3.10 Flow | **100% PASS** |

*Ghi chú: Toàn bộ 20 yêu cầu kỹ thuật đều đạt 100% độ phủ kiểm chứng chức năng và vật lý.*

---

## 4.2 Chi tiết các Test Cases kiểm chứng chức năng (Functional Verification Plan)

Hệ thống kiểm chứng tự động bao gồm 9 testbench chuyên sâu bao phủ toàn diện từ cấp độ khối đến mức tích hợp hệ thống:

1. **`tb_bubble_sort` (System Firmware Sorting Benchmark):**
   - Nạp firmware biên dịch từ mã C `bublesoft.c` vào SRAM.
   - Quét động vị trí mảng `my_array` tại t=0 (tìm thấy tại byte address `0x0B0`, word index 44).
   - Kiểm tra thuật toán sắp xếp 10 phần tử: `[42, 15, 77, 8, 23, 57, 86, 11, 43, 64]` thành `[8, 11, 15, 23, 42, 43, 57, 64, 77, 86]`.
   - Kết quả đo lường: **470 chu kỳ**, **344 lệnh hoàn tất**, **CPI = 1.366**, **IPC = 0.732**.

2. **`tb_phase2_math_ai` (Math & AI Acceleration Unit Tests):**
   - Kiểm tra bộ nhân Radix-16 với 4 chế độ: `MUL`, `MULH`, `MULHSU`, `MULHU` cho các số dương, âm và hỗn hợp.
   - Kiểm tra bộ tăng tốc AI SIMD MAC `smdot.i8` cho các vector số nguyên 8-bit có dấu.

3. **`tb_phase3_hazards` (Pipeline Hazards & Stalls Tests):**
   - Kiểm tra xung đột nạp-dùng Load-to-Use stall (chèn 1 chu kỳ bong bóng an toàn).
   - Kiểm tra rẽ nhánh sai (Branch Misprediction) và đo lường tổn thất 2 chu kỳ clock phục hồi đường ống.

4. **`tb_rvc_decompressor` (RV32C Instruction Unit Tests):**
   - Kiểm tra giải mã độc lập 24 định dạng lệnh nén 16-bit phổ biến của chuẩn RV32C thành lệnh 32-bit RV32I tương đương.

5. **`tb_rvc_pipeline` (RVC Mixed-Width End-to-End Execution):**
   - Kiểm tra thực thi xen kẽ chuỗi lệnh 16-bit và 32-bit trong đường ống qua hàng đợi Prefetch FIFO 2-word, kiểm tra độ lệch địa chỉ byte lẻ.

6. **`tb_ai_benchmark` (AI Inference Deep Neural Network Layers):**
   - Đo lường hiệu năng tính toán tích vô hướng ma trận và các lớp mạng nơ-ron tích chập / dense layer, chứng minh hệ số tăng tốc 11.85x.

7. **`tb_phase5_datapath_p0` (Datapath & Forwarding P0 Bug Closure):**
   - Kiểm tra đóng kín 4 lỗi P0 datapath:
     - Part 1: Đọc CSR tại Tầng 3 và ghi CSR từ toán hạng RS1 sau chuyển tiếp (Fix P0-1, P0-2).
     - Part 2: Khóa kích hoạt bộ nhân khi có xung đột Load-to-Use stall (Fix P0-3).
     - Part 3: Chuyển tiếp kết quả ghi trả JAL link `PC+4` (Fix P0-4).
     - Part 4: Đọc CSR tức thời và chuyển tiếp liên tiếp.

8. **`tb_phase6_control_traps` (Control, Traps, Interrupts & APB P0 Bug Closure):**
   - Kiểm tra đóng kín các lỗi điều khiển và bẫy ngắt:
     - Part 1: Đọc/ghi `mtval` và xóa 2 bit thấp của `mtvec` ở Direct Mode (Fix R-17).
     - Part 2: Bẫy lệnh `DIV/REM` thành ngoại lệ Illegal Instruction `mcause = 2` (Fix P0-7).
     - Part 3: Ngắt ngoài bất đồng bộ cho phép Tầng 3 commit lệnh `SW` hoàn tất và lưu `mepc = PC+4` (Fix P0-5).
     - Part 4: Cầu nối APB giao dịch với slave có 2 chu kỳ chờ wait-states (Fix P0-6).
     - Part 5: Lệnh gỡ lỗi `EBREAK` bẫy thành Breakpoint Trap `mcause = 3` (Fix R-16).
     - Part 6: Truy cập ngoài biên 2KB SRAM bẫy thành Load/Store Access Fault `mcause = 5 / 7` và lưu địa chỉ lỗi vào `mtval` (Fix R-12).

9. **`tb_isa_compliance` (RV32I Directed ISA Compliance):**
   - Kiểm tra toàn diện 31 test cases cho toàn bộ tập lệnh cơ sở RV32I:
     - LUI, AUIPC.
     - AND, ANDI, OR, ORI, XOR, XORI.
     - SLL, SLLI, SRL, SRLI, SRA, SRAI.
     - SLT, SLTI, SLTU, SLTIU (Signed & Unsigned less-than comparisons).
     - BLTU, BGEU (Unsigned branches taken & not-taken).
     - SB, SH, SW, LB, LBU, LH, LHU, LW (Sub-word byte & halfword memory writes and sign/zero extended reads).

---

## 4.3 Kết quả kiểm chứng mô phỏng & Báo cáo độ phủ (Verification Scorecard)

**Bảng 4.2: Bảng điểm kiểm chứng mô phỏng (Verification Scorecard)**

| STT | Tên Testbench | Mục Tiêu Kiểm Chứng | Số Test Cases | Kết Quả Mô Phỏng | Thời Gian Mô Phỏng |
| :---: | :--- | :--- | :---: | :---: | :---: |
| 1 | `tb_bubble_sort` | Hệ thống thực thi firmware C sắp xếp mảng | 1 End-to-End | **PASS (100%)** | 4,715 ns |
| 2 | `tb_phase2_math_ai` | Bộ nhân Radix-16 & Khối SIMD MAC | 8 Unit Tests | **PASS (100%)** | 820 ns |
| 3 | `tb_phase3_hazards` | Xung đột Load-to-use & Nhánh sai | 6 Unit Tests | **PASS (100%)** | 640 ns |
| 4 | `tb_rvc_decompressor` | Giải nén 24 định dạng lệnh RVC 16-bit | 24 Unit Tests | **PASS (100%)** | 250 ns |
| 5 | `tb_rvc_pipeline` | Thực thi đường ống lệnh nén xen kẽ | 12 Pipeline Tests | **PASS (100%)** | 1,200 ns |
| 6 | `tb_ai_benchmark` | Tính toán ma trận trọng số AI INT8 | 4 Benchmark Tests | **PASS (100%)** | 2,150 ns |
| 7 | `tb_phase5_datapath_p0`| Khắc phục 4 lỗi P0-1, P0-2, P0-3, P0-4 | 10 Unit Tests | **PASS (100%)** | 620 ns |
| 8 | `tb_phase6_control_traps`| Khắc phục P0-5, P0-6, P0-7, R-12, R-16, R-17| 9 Unit Tests | **PASS (100%)** | 1,105 ns |
| 9 | `tb_isa_compliance` | Kiểm chứng toàn bộ tập lệnh cơ sở RV32I | 31 Unit Tests | **PASS (100%)** | 655 ns |
| **Tổng** | **Toàn Bộ 9 Testbenches** | **Kiểm chứng hoàn chỉnh hệ thống** | **105 Test Points** | **100% PASS** | **12,155 ns** |

*Ghi chú: Toàn bộ 9 testbench được tích hợp vào lệnh thực thi tự động `make sim-all` và kiểm tra tĩnh `make lint` với 0 lỗi, 0 cảnh báo.*
