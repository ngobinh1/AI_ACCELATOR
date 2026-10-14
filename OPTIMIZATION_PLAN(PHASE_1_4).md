# Kế Hoạch Tối Ưu Hóa Hiệu Năng RTL (OPTIMIZATION_PLAN.md)
**Dự án:** RISC-V 32-bit IoT & AI Accelerator Core  
**Mục tiêu:** Giảm chỉ số CPI (Cycles Per Instruction), tăng IPC (Instructions Per Cycle) và nâng cao tần số hoạt động cực đại ($F_{max}$) cho các tác vụ Edge AI & IoT.

---

## 📌 Tổng Quan Lộ Trình Triển Khai (Roadmap Summary)

```
+-------------------------------------------------------------------------------+
| PHASE 1: Quick Wins (0-Cycle JAL & Static Branch Prediction)                  |
| -> Giảm Branch Penalty, tăng IPC ngay lập tức mà không phá vỡ cấu trúc RTL    |
+---------------------------------------+---------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
| PHASE 2: Math & AI Acceleration (1-Cycle Multiplier & Packed SIMD 4x INT8)    |
| -> Tăng tốc phép nhân 17x, tăng tốc ma trận & tích chập AI 4x                 |
+---------------------------------------+---------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
| PHASE 3: Pipeline Restructuring (3-Stage Pipeline & Forwarding Network)       |
| -> Tách đường trễ tới hạn (Critical Path), tăng Fmax lên 150MHz - 200MHz      |
+---------------------------------------+---------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
| PHASE 4: Code Density & Memory Bandwidth (RV32C & Instruction Prefetch)       |
| -> Giảm 30% bộ nhớ mã lệnh, tăng gấp đôi băng thông đọc lệnh từ SRAM/Flash    |
+-------------------------------------------------------------------------------+
```

---

## Giai Đoạn 1: Quick Wins & Tối Ưu Hóa Rẽ Nhánh (Phase 1)
*Độ phức tạp: Thấp | Thời gian dự kiến: Nhanh | Mục tiêu: Giảm Branch/Jump Penalty* - **[ĐÃ HOÀN THÀNH - CPI giảm từ 1.506 -> 1.398, Clock Cycles giảm từ 503 -> 467]**

### 1.1. Early Jump Resolution (Lệnh JAL 0-chu kỳ)
- [x] **Hiện trạng:** Lệnh `JAL` phải đi qua Tầng 1 sang Tầng 2 mới tính toán $PC + imm$ và kích hoạt nhảy, làm flush 1 lệnh sau nó (mất 1 chu kỳ).
- [x] **Giải pháp:** Trong `rtl/core/stage_if.v`, nhận diện trực tiếp `opcode == OP_JAL` ngay tại tầng IF/ID, trích xuất `imm_j` và chuyển hướng $PC$ ngay trong chu kỳ tiếp theo.
- [x] **Kết quả kỳ vọng:** Lệnh `JAL` có độ trễ 0-cycle stall (thực thi hoàn hảo 1 IPC).

### 1.2. Bộ Dự Đoán Rẽ Nhánh Tĩnh BTFN (Backward Taken, Forward Not Taken)
- [x] **Hiện trạng:** Mọi lệnh Branch (`BEQ`, `BNE`, `BLT`, `BGE`...) đều mặc định đoán "Not Taken". Khi vào các vòng lặp (`for`, `while`), nhánh nhảy lùi luôn bị đoán sai $\rightarrow$ tốn 1 chu kỳ Flush mỗi vòng lặp.
- [x] **Giải pháp:**
  - Nếu `imm[31] == 1` (Nhánh nhảy lùi - Vòng lặp): Dự đoán **TAKEN** $\rightarrow$ Fetch ngay địa chỉ $PC + imm$.
  - Nếu `imm[31] == 0` (Nhánh nhảy tiến - Câu lệnh `if/else`): Dự đoán **NOT TAKEN** $\rightarrow$ Fetch $PC + 4$.
  - Nếu Tầng 2 đánh giá dự đoán sai $\rightarrow$ Mới kích hoạt cơ chế Rollback/Flush.
- [x] **File đã sửa:** `rtl/core/stage_if.v`, `rtl/core/pipe_reg_id_ex.v`, `rtl/core/stage_ex.v`, `rtl/core/hazard_unit.v`, `rtl/core/core_top.v`.

---

## Giai Đoạn 2: Nâng Cấp Khối Tính Toán & Tăng Tốc AI (Phase 2)
*Độ phức tạp: Trung bình | Mục tiêu: Tăng tốc toán học & suy luận AI (Edge AI Inference)* - **[ĐÃ HOÀN THÀNH - Dot-Product tăng tốc 11.85x, 0-cycle Stall Multiplier, Fmax = 38.26 MHz]**

### 2.1. Bộ Nhân 1 Chu Kỳ (Single-Cycle Combinational Multiplier)
- [x] **Hiện trạng:** `rtl/core/booth_multiplier_32b.v` dùng thuật toán lặp 17 chu kỳ, gây stall nghiêm trọng khi chạy DSP/AI.
- [x] **Giải pháp:**
  - Thiết kế lại bộ nhân sử dụng mảng nhân tổ hợp 33x33 $\rightarrow$ 66-bit signed/unsigned cho ra kết quả trong **1 chu kỳ clock**.
  - Tối ưu hóa cờ `o_ex_ready = 1'b1` để `hazard_unit` không bao giờ phải stall lõi khi nhân (loại bỏ hoàn toàn trạng thái `S_WAIT_MUL`).
- [x] **File đã sửa:** `rtl/core/booth_multiplier_32b.v`, `rtl/core/stage_ex.v`, `rtl/core/hazard_unit.v`.

### 2.2. Tập Lệnh Packed SIMD (4x INT8 Dot-Product MAC)
- [x] **Mục tiêu:** Tăng tốc thuật toán lượng tử hóa mạng nơ-ron (Quantized Neural Networks - INT8).
- [x] **Đặc tả phần cứng:**
  - Bổ sung lệnh custom (mã hóa theo chuẩn RV32P / Custom-0): `smdot.i8 rd, rs1, rs2` (`opcode=7'b0110011, funct3=3'b100, funct7=7'b0000100`).
  - Thực hiện 4 phép nhân 8-bit có dấu song song và cây cộng cân bằng 2 cấp:
    $$\text{Result} = (A_0 \times B_0) + (A_1 \times B_1) + (A_2 \times B_2) + (A_3 \times B_3)$$
  - Tạo mới module chuyên dụng `rtl/core/simd_mac_unit.v`.
- [x] **File đã sửa:** `rtl/defines/riscv_core_defines.vh`, `rtl/core/instruction_decoder.v`, `rtl/core/simd_mac_unit.v`, `rtl/core/stage_if.v`, `rtl/core/pipe_reg_id_ex.v`, `rtl/core/stage_ex.v`, `rtl/core/core_top.v`, `config.json`.

---

## Giai Đoạn 3: Tái Cấu Trúc Pipeline 3-Tầng (Phase 3)
*Độ phức tạp: Cao | Mục tiêu: Tăng tần số xung nhịp cực đại ($F_{max}$) lên gấp đôi*

### 3.1. Phân Tách Đường Ống 3-Stage (`IF` -> `ID/EX` -> `MEM/WB`)
- [ ] **Mục tiêu:** Cắt đôi Critical Path của Tầng 2 hiện tại (`ALU -> SRAM/APB -> Load Align -> WB MUX`).
- [ ] **Cấu trúc mới:**
  - **Stage 1 (IF):** Fetch lệnh từ SRAM Port 1.
  - **Stage 2 (ID/EX):** Giải mã, đọc Register File, tính toán ALU, bộ nhân, so sánh nhánh.
  - **Stage 3 (MEM/WB):** Truy cập bộ nhớ dữ liệu (SRAM Port 0 / APB) và ghi trả Register File.

### 3.2. Mạng Chuyển Tiếp Dữ Liệu Đầy Đủ (Data Forwarding Network)
- [ ] **EX-to-EX Forwarding:** Chuyển kết quả ALU của lệnh $N-1$ về đầu vào ALU của lệnh $N$.
- [ ] **MEM-to-EX Forwarding:** Chuyển dữ liệu đọc từ Memory về đầu vào ALU của lệnh sau.
- [ ] **Load Hazard Interlock:** Chỉ stall 1 chu kỳ duy nhất nếu lệnh kế tiếp sử dụng ngay kết quả của lệnh `LW` (Load-to-Use hazard).
- [ ] **File cần sửa:** Tạo mới `rtl/core/forwarding_unit.v`, sửa `stage_if.v`, `stage_ex.v`, `hazard_unit.v`.

---

## Giai Đoạn 4: Tối Ưu Hóa Mật Độ Mã Lệnh & Băng Thông (Phase 4)
*Độ phức tạp: Trung bình - Cao | Mục tiêu: Tiết kiệm SRAM và tăng băng thông đọc lệnh*

### 4.1. Bộ Giải Mã Tập Lệnh Nén RV32C (16-bit Compressed Instructions)
- [ ] Giải mã các lệnh 16-bit thông dụng (`c.lw`, `c.sw`, `c.add`, `c.li`, `c.j`, `c.beqz`...).
- [ ] Chuyển đổi lệnh 16-bit thành lệnh 32-bit tương đương trước khi đưa vào bộ giải mã chính.
- [ ] Giúp tiết kiệm 25% - 30% dung lượng SRAM 2KB.

### 4.2. Bộ Đệm Nạp Lệnh Trước (Instruction Prefetch Buffer)
- [ ] Tận dụng cổng đọc 32-bit từ SRAM để nạp cùng lúc hai lệnh 16-bit vào hàng đợi FIFO (2-word hoặc 4-word FIFO buffer).
- [ ] Đảm bảo tầng thực thi luôn có sẵn lệnh mà không bị gián đoạn.

---

## 📋 Bảng Phân Công & Theo Dõi Tệp Mã Nguồn

| Module / Tệp | Vai Trò Hiện Tại | Các Hạng Mục Cần Chỉnh Sửa | Giai Đoạn |
| :--- | :--- | :--- | :---: |
| [`stage_if.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/stage_if.v) | IF/ID Stage | Thêm logic tính sớm JAL, bộ dự đoán nhánh tĩnh BTFN | Phase 1 |
| [`hazard_unit.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/hazard_unit.v) | Hazard Controller | Hỗ trợ branch miss-prediction recovery, tối ưu stall | Phase 1, 3 |
| [`booth_multiplier_32b.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/booth_multiplier_32b.v) | Booth Multiplier | Chuyển thành Single-cycle Array Multiplier | Phase 2 |
| [`instruction_decoder.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/instruction_decoder.v) | Decoder | Thêm giải mã lệnh SIMD `smdot.i8` và lệnh RV32C | Phase 2, 4 |
| [`stage_ex.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/stage_ex.v) | EX Stage | Tích hợp bộ tính SIMD dot-product, tái cấu trúc pipeline | Phase 2, 3 |
| [`forwarding_unit.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/) | *(Chưa có)* | Tạo mới module chuyển tiếp dữ liệu giải quyết xung đột RAW | Phase 3 |

---

## 🎯 Tiêu Chí Đo Lường Thành Công (Success Metrics)

Mọi thay đổi sẽ được benchmark và kiểm chứng thông qua Testbench chuẩn:

1. **Chỉ số CPI (Cycles Per Instruction):** Giảm từ mức hiện tại `~1.506` xuống mục tiêu `< 1.20`.
2. **Số chu kỳ thực thi thuật toán Bubble Sort:** Giảm từ `503 chu kỳ` xuống `< 350 chu kỳ`.
3. **Hiệu năng xử lý AI Dot-Product (100 phép nhân cộng INT8):** Tăng tốc tối thiểu **4x**.
4. **Kiểm tra Formal & Simulation:** Vượt qua 100% test case với `make lint` (Verilator) và `make sim` (QuestaSim) với 0 lỗi logic.
