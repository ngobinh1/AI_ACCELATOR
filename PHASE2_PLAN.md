# Kế Hoạch Triển Khai Chi Tiết - Giai Đoạn 2 (PHASE 2)
## Math & AI Acceleration: Single-Cycle Multiplier & Packed SIMD Dot-Product (`smdot.i8`)

**Dự án:** RISC-V 32-bit IoT & AI Accelerator Core  
**Thời gian thực hiện dự kiến:** Giai đoạn 2  
**Mục tiêu chính:** Nâng cấp khối tính toán số học (Arithmetic Datapath) và tích hợp tập lệnh tăng tốc trí tuệ nhân tạo (Edge AI Acceleration), đưa lệnh nhân về độ trễ 1 chu kỳ và tăng tốc các phép toán tích vô hướng ma trận / mạng nơ-ron (INT8 Dot-Product MAC) lên gấp nhiều lần.

---

## 1. Tổng Quan & Mục Đích Của Giai Đoạn 2

### 1.1. Bối Cảnh Hiện Trạng & Điểm Nghẽn Hiệu Năng
Sau khi hoàn thành Giai đoạn 1 (Quick Wins với 0-cycle JAL và bộ dự đoán nhánh tĩnh BTFN), chỉ số CPI của lõi đã giảm từ `1.506` xuống `1.398`. Tuy nhiên, khi phân tích sâu cấu trúc vi kiến trúc, hai điểm nghẽn lớn nhất kìm hãm hiệu năng xử lý toán học và AI vẫn tồn tại:

1. **Bộ nhân Booth Radix-2 đa chu kỳ (`booth_multiplier_32b.v`):**
   - Đang sử dụng FSM tuần tự với bộ đếm 5-bit đếm đủ 17 chu kỳ xung nhịp (`r_counter == 16`) để tính toán một phép nhân 32-bit $\times$ 32-bit $\rightarrow$ 64-bit.
   - Mỗi khi gặp lệnh nhân RV32M (`MUL`, `MULH`, `MULHSU`, `MULHU`), `hazard_unit.v` bắt buộc phải chuyển sang trạng thái `S_WAIT_MUL`, khóa toàn bộ đường ống (Stall 16 chu kỳ). Điều này làm suy giảm nghiêm trọng IPC/CPI trong các thuật toán xử lý tín hiệu DSP, đồ họa và số học phức tạp.

2. **Thiếu tập lệnh chuyên dụng cho suy luận AI (Edge AI Inference):**
   - Các mô hình học sâu hiện đại trên thiết bị nhúng (CNN, MobileNet, TinyML, INT8 Quantized Neural Networks) dành hơn **85% - 90%** tổng thời gian tính toán cho các phép tính Tích Vô Hướng (Dot-Product / GEMM / Conv2D):
     $$\text{Dot-Product} = \sum_{i=0}^{N-1} A_i \times B_i = A_0 B_0 + A_1 B_1 + A_2 B_2 + A_3 B_3 + \dots$$
   - Trên tập lệnh cơ bản RV32I/M, để tính tích vô hướng của 4 cặp số 8-bit (`int8_t`), vi xử lý phải thực hiện:
     * 4 lệnh dịch bit/mặt nạ trích xuất từng byte (`SRL`, `ANDI`).
     * 4 lệnh nhân `MUL` (tốn $4 \times 17 = 68$ chu kỳ).
     * 3 lệnh cộng dồn `ADD`.
     * $\rightarrow$ **Tổng cộng tốn hơn 75 - 85 chu kỳ clock cho chỉ 4 phép nhân cộng INT8!**

### 1.2. Mục Đích Cốt Lõi Của Giai Đoạn 2
- [x] **Hiện thực hóa Bộ Nhân 1 Chu Kỳ (Single-Cycle Combinational Multiplier):** Thay thế FSM 17 chu kỳ bằng mảng nhân tổ hợp / cây cộng hiệu năng cao, cho phép các lệnh nhân `MUL`, `MULH`, `MULHSU`, `MULHU` hoàn thành trong **1 chu kỳ clock duy nhất (0-cycle stall)**.
- [x] **Thiết kế và Tích hợp Tập Lệnh Packed SIMD 4x INT8 Dot-Product (`smdot.i8`):** Đóng gói 4 phần tử INT8 trong một thanh ghi 32-bit, thực hiện đồng thời 4 phép nhân 8-bit và 3 phép cộng trong **1 chu kỳ clock**, tăng tốc độ xử lý các lớp mạng nơ-ron lên **tối thiểu 4x - 8x** (thực tế đo được **11.85x**).
- [x] **Tối Giản Hóa Khối Điều Khiển Hazard Unit:** Loại bỏ hoàn toàn trạng thái `S_WAIT_MUL` trong `hazard_unit.v`. Đường ống thực thi số học trở nên trơn tru (Non-blocking Arithmetic Pipeline).
- [x] **Kiểm Chứng Vật Lý Toàn Diện Trên OpenLane 2 (SkyWater 130nm):** Đạt **0 DRC errors**, hoàn thành 100% flow PNR với KLayout GDSII ($41\text{ MB}$) và $F_{max} = 38.26\text{ MHz}$ tại typical corner.

---

## 2. Phân Tích Kỹ Thuật & Giải Pháp Kiến Trúc

### 2.1. Sơ Đồ Khối Vi Kiến Trúc Tầng Thực Thi (EX Stage Datapath)

```mermaid
flowchart TD
    subgraph STAGE1["TẦNG 1: IF / ID Stage"]
        DEC["Instruction Decoder"] -->|i_mul_valid, i_mul_type| EX_CTRL["EX Stage Controls"]
        DEC -->|i_simd_valid, i_simd_type| EX_CTRL
        RF["Register File"] -->|RS1 Data (32-bit)| RS1_BUS["rs1_data [31:0]"]
        RF -->|RS2 Data (32-bit)| RS2_BUS["rs2_data [31:0]"]
    end

    subgraph STAGE2["TẦNG 2: EX Stage (Math & AI Execution)"]
        RS1_BUS --> ALU["ALU 32-bit\n(ADD, SUB, SLL, SLT, XOR, SRL, SRA, OR, AND)"]
        RS2_BUS --> ALU

        RS1_BUS --> MUL32["Single-Cycle Multiplier 32x32\n(Signed/Unsigned Combinational)\n-> 64-bit Product in 1 Cycle"]
        RS2_BUS --> MUL32

        RS1_BUS --> SIMD_MAC["Packed SIMD MAC Unit (smdot.i8)\n- 4x Parallel 8x8 Multipliers\n- 2-Level 16b/32b Adder Tree\n-> Sum(A_i * B_i) in 1 Cycle"]
        RS2_BUS --> SIMD_MAC

        ALU --> EX_MUX["EX Result Multiplexer"]
        MUL32 -->|w_mul_result| EX_MUX
        SIMD_MAC -->|w_simd_result| EX_MUX
    end

    subgraph WB_STAGE["Write-Back & Memory Interface"]
        EX_MUX --> WB_MUX["Final Write-Back MUX\n(ALU / MUL / SIMD / Load / PC+4 / CSR)"]
        WB_MUX -->|o_wb_data| RF_WB["Ghi trả Register File (rd)"]
    end

    subgraph HAZARD["Hazard Unit"]
        EX_CTRL -->|o_ex_ready = 1'b1| HU["Hazard Unit (No Multiplier Stall)"]
    end
```

---

### 2.2. Chi Tiết Kiến Trúc Bộ Nhân 1 Chu Kỳ (Single-Cycle Multiplier)
- **Cơ chế mở rộng dấu 33-bit $\times$ 33-bit:**
  Để xử lý đồng thời 4 chế độ nhân có dấu/không dấu chỉ với 1 khối nhân phần cứng:
  * $A_{\text{ext}}[32:0] = \{ (i\_is\_signed\_a \ \& \ i\_multiplicand[31]), \ i\_multiplicand \}$
  * $B_{\text{ext}}[32:0] = \{ (i\_is\_signed\_b \ \& \ i\_multiplier[31]), \ i\_multiplier \}$
  * Phép nhân có dấu 33-bit:
    $$P[65:0] = \$signed(A_{\text{ext}}) \times \$signed(B_{\text{ext}})$$
  * Kết quả chuẩn 64-bit: $o\_product[63:0] = P[63:0]$.
- **Lựa chọn ngõ ra theo phân loại lệnh RV32M:**
  * `MUL` (`mul_type == 2'b00`): Chọn 32-bit thấp $P[31:0]$.
  * `MULH` / `MULHSU` / `MULHU` (`mul_type != 2'b00`): Chọn 32-bit cao $P[63:32]$.
- **Đặc tính thời gian (Timing & Handshake):**
  * Tín hiệu `o_ready` luôn được gán bằng `1'b1` (tính toán tổ hợp thuần túy trong chu kỳ hiện tại).
  * `o_ex_ready` của `stage_ex.v` luôn ở mức cao $\rightarrow$ Pipeline không bao giờ bị nghẽn do phép nhân.

---

### 2.3. Chi Tiết Kiến Trúc Tập Lệnh Packed SIMD 4x INT8 (`smdot.i8`)

#### A. Định Dạng Mã Lệnh (Instruction Encoding)
Lệnh `smdot.i8` được mã hóa theo chuẩn **R-type** trong không gian mở rộng tiêu chuẩn của RISC-V:

```
 31          25 24        20 19        15 14      12 11         7 6            0
+--------------+------------+------------+----------+------------+--------------+
|   funct7     |    rs2     |    rs1     |  funct3  |     rd     |    opcode    |
|   0000100    |  src_reg2  |  src_reg1  |   100    |  dest_reg  |   0110011    |
+--------------+------------+------------+----------+------------+--------------+
  (7-bit: 0x04)   (5-bit)      (5-bit)    (3-bit:0x4)   (5-bit)    (OP_ARITHR)
```

#### B. Định Dạng Dữ Liệu Toán Hạng (Packed INT8 Vector Format)
Mỗi thanh ghi 32-bit chứa 4 phần tử số nguyên 8-bit có dấu dạng bù 2 (`int8_t` trong khoảng $[-128, +127]$):
- $RS1 = \{A_3[7:0], \ A_2[7:0], \ A_1[7:0], \ A_0[7:0]\}$ trong đó:
  * Byte 0: $A_0 = RS1[7:0]$
  * Byte 1: $A_1 = RS1[15:8]$
  * Byte 2: $A_2 = RS1[23:16]$
  * Byte 3: $A_3 = RS1[31:24]$
- $RS2 = \{B_3[7:0], \ B_2[7:0], \ B_1[7:0], \ B_0[7:0]\}$ tương tự.

#### C. Vi Kiến Trúc Khối Tính Toán SIMD MAC (`simd_mac_unit.v`)

```mermaid
flowchart TD
    RS1["RS1 [31:0]"] --> SPLIT_A["Tách 4x INT8: A3, A2, A1, A0"]
    RS2["RS2 [31:0]"] --> SPLIT_B["Tách 4x INT8: B3, B2, B1, B0"]

    SPLIT_A --> M0["MUL0: A0 * B0 (8b x 8b -> 16b signed)"]
    SPLIT_B --> M0
    SPLIT_A --> M1["MUL1: A1 * B1 (8b x 8b -> 16b signed)"]
    SPLIT_B --> M1
    SPLIT_A --> M2["MUL2: A2 * B2 (8b x 8b -> 16b signed)"]
    SPLIT_B --> M2
    SPLIT_A --> M3["MUL3: A3 * B3 (8b x 8b -> 16b signed)"]
    SPLIT_B --> M3

    M0 -->|P0 [15:0]| ADD_L1_A["Adder L1_A: P0 + P1"]
    M1 -->|P1 [15:0]| ADD_L1_A
    M2 -->|P2 [15:0]| ADD_L1_B["Adder L1_B: P2 + P3"]
    M3 -->|P3 [15:0]| ADD_L1_B

    ADD_L1_A -->|S01 [16:0]| SEXT_A["Sign-Extend 32-bit"]
    ADD_L1_B -->|S23 [16:0]| SEXT_B["Sign-Extend 32-bit"]

    SEXT_A --> ADD_L2["Adder L2: S01 + S23"]
    SEXT_B --> ADD_L2

    ADD_L2 --> RESULT["Result [31:0] -> Write-Back rd"]
```

- **Công thức toán học:**
  $$\text{Result}[31:0] = (\$signed(A_0) \times \$signed(B_0)) + (\$signed(A_1) \times \$signed(B_1)) + (\$signed(A_2) \times \$signed(B_2)) + (\$signed(A_3) \times \$signed(B_3))$$
- **Miền giá trị đầu ra:**
  * Mỗi tích $P_i \in [-128 \times 127, -128 \times -128] = [-16256, +16384]$ (vừa vặn trong 16-bit signed).
  * Tổng 4 tích $S \in [-65024, +65536]$ (vừa vặn trong 18-bit signed và được mở rộng dấu ra 32-bit `rd` mà **không bao giờ bị tràn số**).

---

## 3. Danh Mục Các Công Việc Cần Thực Hiện Ở Giai Đoạn 2

### Nhiệm Vụ 1: Hiện Thực Hóa Bộ Nhân Tổ Hợp 1 Chu Kỳ (`single_cycle_multiplier.v` / `booth_multiplier_32b.v`)
* **File mục tiêu:** `rtl/core/booth_multiplier_32b.v` (hoặc tái cấu trúc thành `multiplier_32b.v`), `rtl/core/stage_ex.v`.
* **Công việc kỹ thuật:**
  1. Thay thế toàn bộ FSM tuần tự (`IDLE`, `CALC`, `r_counter`) bằng logic tổ hợp hiệu năng cao.
  2. Triển khai phép nhân có dấu/không dấu dựa trên mở rộng 33-bit:
     ```verilog
     wire [32:0] w_a_ext = { (i_is_signed_a & i_multiplicand[31]), i_multiplicand };
     wire [32:0] w_b_ext = { (i_is_signed_b & i_multiplier[31]),   i_multiplier };
     wire signed [65:0] w_prod_full = $signed(w_a_ext) * $signed(w_b_ext);
     assign o_product = w_prod_full[63:0];
     assign o_ready   = 1'b1; // Luôn sẵn sàng trong 1 chu kỳ
     ```
  3. Đảm bảo tổng hợp logic sinh ra cây cộng tổ hợp tối ưu diện tích và độ trễ trên SkyWater 130nm.

---

### Nhiệm Vụ 2: Thiết Kế Khối Packed SIMD Dot-Product Unit (`simd_mac_unit.v`)
* **File mục tiêu:** Tạo mới `rtl/core/simd_mac_unit.v` (hoặc tích hợp trong `rtl/core/alu.v`).
* **Công việc kỹ thuật:**
  1. Khởi tạo 4 bộ nhân song song 8-bit có dấu:
     ```verilog
     wire signed [7:0]  w_a0 = i_rs1[7:0],   w_b0 = i_rs2[7:0];
     wire signed [7:0]  w_a1 = i_rs1[15:8],  w_b1 = i_rs2[15:8];
     wire signed [7:0]  w_a2 = i_rs1[23:16], w_b2 = i_rs2[23:16];
     wire signed [7:0]  w_a3 = i_rs1[31:24], w_b3 = i_rs2[31:24];

     wire signed [15:0] w_p0 = w_a0 * w_b0;
     wire signed [15:0] w_p1 = w_a1 * w_b1;
     wire signed [15:0] w_p2 = w_a2 * w_b2;
     wire signed [15:0] w_p3 = w_a3 * w_b3;
     ```
  2. Cây cộng 2 tầng tối ưu đường trễ (Balanced Adder Tree):
     ```verilog
     wire signed [16:0] w_sum_01 = w_p0 + w_p1;
     wire signed [16:0] w_sum_23 = w_p2 + w_p3;
     wire signed [31:0] w_dot_result = {{15{w_sum_01[16]}}, w_sum_01} + 
                                       {{15{w_sum_23[16]}}, w_sum_23};
     assign o_simd_result = w_dot_result;
     ```

---

### Nhiệm Vụ 3: Cập Nhật Bộ Giải Mã & File Định Nghĩa Toàn Cục
* **File mục tiêu:** `rtl/defines/riscv_core_defines.vh`, `rtl/core/instruction_decoder.v`.
* **Công việc kỹ thuật:**
  1. Trong `riscv_core_defines.vh`:
     - Bổ sung định nghĩa mã máy cho `smdot.i8`:
       ```verilog
       localparam [6:0] F7_SIMD_DOT = 7'b0000100;
       localparam [2:0] F3_SIMD_DOT = 3'b100;
       localparam [3:0] ALU_SIMD_DOT = 4'b1110; // Cờ điều khiển nếu tích hợp trong ALU
       ```
  2. Trong `instruction_decoder.v`:
     - Giải mã lệnh R-type khi `w_opcode == OP_ARITHR`:
       ```verilog
       if (w_func7 == F7_SIMD_DOT && w_func3 == F3_SIMD_DOT) begin
           o_reg_write   = 1'b1;
           o_alu_src     = 1'b0; // RS2
           o_simd_valid  = 1'b1; // Kích hoạt khối SIMD
       end
       ```

---

### Nhiệm Vụ 4: Tái Cấu Trúc Tầng Thực Thi & Khối Điều Khiển Hazard Unit
* **File mục tiêu:** `rtl/core/stage_ex.v`, `rtl/core/hazard_unit.v`, `rtl/core/pipe_reg_id_ex.v`.
* **Công việc kỹ thuật:**
  1. Trong `stage_ex.v`:
     - Đấu nối module `simd_mac_unit` (hoặc logic SIMD trong ALU).
     - Đưa kết quả SIMD vào bộ chọn kết quả thực thi `w_ex_result`:
       ```verilog
       always @(*) begin
           if (i_simd_valid)      w_ex_result = w_simd_result;
           else if (i_mul_valid)  w_ex_result = w_mul_result;
           else                   w_ex_result = w_alu_result;
       end
       ```
     - Cập nhật `o_ex_ready = 1'b1` vì không còn trạng thái đa chu kỳ nào tại khối tính toán.
  2. Trong `hazard_unit.v`:
     - Loại bỏ trạng thái `S_WAIT_MUL` khỏi FSM.
     - Khối FSM chỉ còn quản lý trạng thái `S_IDLE_EX` và `S_MEM` (khi đọc SRAM hoặc chờ APB bus phản hồi), giúp logic điều khiển đơn giản, nhanh hơn và tiết kiệm diện tích.

---

### Nhiệm Vụ 5: Tích Hợp Lõi Tổng & Cấu Hình Layout
* **File mục tiêu:** `rtl/core/core_top.v`, `config.json`.
* **Công việc kỹ thuật:**
  1. Cập nhật `core_top.v` với các dây nối tín hiệu SIMD mới.
  2. Cập nhật danh sách file `VERILOG_FILES` trong `config.json` nếu có thêm module mới (`simd_mac_unit.v`).

---

### Nhiệm Vụ 6: Xây Dựng Bộ Testbench Xác Thực & Firmware AI Inference Benchmark
* **File mục tiêu:** Tạo mới `testbench/tb_phase2_math_ai.v`, `software/ai_dot_product_benchmark/`.
* **Công việc kỹ thuật:**
  1. **Unit Testbench (`tb_phase2_math_ai.v`):**
     - Kiểm thử toàn diện 4 lệnh nhân `MUL`, `MULH`, `MULHSU`, `MULHU` với các trường hợp số học đặc biệt (số 0, số âm lớn nhất $-2^{31}$, số dương lớn nhất $2^{31}-1$, tích tràn bit).
     - Kiểm thử lệnh `smdot.i8` với các vector INT8 ngẫu nhiên và vector góc biên ($[-128, -128, -128, -128] \times [-128, -128, -128, -128]$).
     - Xác thực kết quả phần cứng so với mô hình toán học mẫu (Gold Standard Model).
  2. **AI Inference Benchmark (Firmware C / ASM):**
     - Viết hàm tích chập 1D / 2D và nhân ma trận 4x4, 8x8 dạng INT8:
       * Phiên bản 1: Sử dụng thuần tập lệnh chuẩn RV32I/M (Baseline).
       * Phiên bản 2: Sử dụng tập lệnh tăng tốc `smdot.i8` (Phase 2 Accelerated).
     - Đo lường và so sánh chính xác số chu kỳ xung nhịp thực thi.

---

### Nhiệm Vụ 7: Thực Hiện Quy Trình Layout & Tổng Hợp PPA Trên OpenLane 2
* **File mục tiêu:** `config.json`, `riscv_core_top.sdc`, `runs/`.
* **Công việc kỹ thuật:**
  1. Chạy toàn bộ flow OpenLane 2 (Synthesis $\rightarrow$ Placement $\rightarrow$ CTS $\rightarrow$ Routing $\rightarrow$ RCX $\rightarrow$ STA $\rightarrow$ GDSII Streamout).
  2. Trích xuất bảng so sánh PPA chi tiết:
     - **Tần số cực đại ($F_{max}$):** Đánh giá tác động của bộ nhân tổ hợp 32x32 và khối SIMD lên Critical Path.
     - **Diện tích silicon (Area):** So sánh số lượng Standard Cell và diện tích $\mu m^2$ tăng thêm.
     - **Công suất tiêu thụ (Power):** Đo lường công suất động (Dynamic Power) và rò (Leakage Power).

---

## 4. Bảng Theo Dõi Tín Hiệu & Sửa Đổi Module (Signal Traceability Matrix)

| Module | Tên Tín Hiệu Thêm Mới / Sửa Đổi | Hướng | Mô Tả Chức Năng |
| :--- | :--- | :---: | :--- |
| `riscv_core_defines.vh` | `F7_SIMD_DOT`, `F3_SIMD_DOT` | Parameter | Mã hóa trường mã máy funct7, funct3 cho lệnh `smdot.i8` |
| `instruction_decoder.v` | `o_simd_valid` | Output | Báo hiệu lệnh hiện tại là lệnh tăng tốc SIMD |
| `pipe_reg_id_ex.v` | `i_simd_valid` / `o_simd_valid` | In / Out | Truyền tín hiệu điều khiển SIMD qua thanh ghi đường ống |
| `simd_mac_unit.v` | `i_rs1`, `i_rs2`, `o_simd_result` | In / Out | Module tính toán song song 4x INT8 MAC tổ hợp |
| `booth_multiplier_32b.v` | `o_ready` | Output | Luôn giữ mức `1'b1` (Hoàn thành trong 1 chu kỳ) |
| `stage_ex.v` | `i_simd_valid`, `w_simd_result` | Internal | Tích hợp khối SIMD và multiplex kết quả ghi trả |
| `hazard_unit.v` | Xóa bỏ `S_WAIT_MUL` | FSM | Loại bỏ hoàn toàn stall chu kỳ nhân |
| `core_top.v` | Interconnect wires | Internal | Đấu nối tín hiệu điều khiển và dữ liệu SIMD |

---

## 5. Tiêu Chí Nghiệm Thu (Acceptance Criteria)

1. **Độ chính xác chức năng (Functional Correctness):**
   - Vượt qua 100% test case kiểm thử bộ nhân 32-bit và SIMD Dot-Product trên Testbench chuẩn (`make sim`).
   - Kết quả tính toán của `smdot.i8` khớp chính xác 100% với mô hình tính toán số học chuẩn bù 2.
2. **Chất lượng mã nguồn (Linting Signoff):**
   - Lệnh `make lint` với Verilator hoàn thành với **0 cảnh báo / 0 lỗi** (Clean linting).
3. **Hiệu năng tăng tốc AI (Performance Speedup):**
   - Giảm độ trễ lệnh nhân từ 17 chu kỳ xuống **1 chu kỳ**.
   - Tăng tốc độ tính toán Kernel tích vô hướng ma trận INT8 tối thiểu **4x** so với phiên bản baseline RV32I/M.
4. **Physical Implementation Signoff (OpenLane 2):**
   - Hoàn thành trọn vẹn 100% flow PNR trên tiến trình SkyWater 130nm.
   - Đạt **0 lỗi DRC**, **0 lỗi LVS**, và không có vi phạm Power Grid.
   - Xuất file GDSII layout hoàn chỉnh tương thích chuẩn sản xuất.

---

## 6. Kỳ Vọng Kết Quả Benchmark So Với Baseline

| Chỉ Số Đánh Giá | Trước Tối Ưu (Baseline) | Sau Giai Đoạn 2 (Phase 2 Kỳ Vọng) | Mức Độ Cải Thiện Dự Kiến |
| :--- | :---: | :---: | :---: |
| **Độ trễ lệnh nhân `MUL`** | 17 chu kỳ clock | **1 chu kỳ clock** | 🚀 **Nhanh hơn 17x** |
| **Số chu kỳ tính 4 phép nhân-cộng INT8** | ~75 - 85 chu kỳ | **1 chu kỳ (`smdot.i8`)** | 🚀 **Tăng tốc > 75x** |
| **CPI bài toán Ma trận / AI Kernel** | ~2.5 - 3.2 | **~1.1 - 1.3** | 🟢 **Giảm mạnh ~60%** |
| **Trạng thái FSM Stall tại Hazard Unit** | Phải stall khi nhân | **Không bao giờ stall khi tính toán** | 🟢 **Pipeline thông suốt** |
| **DRC Errors (TritonRoute)** | 0 DRC | **0 DRC** | Đạt chuẩn Tapeout |

---

## 7. Kết Quả Đo Lường Thực Nghiệm Thực Tế (Actual Experimental & Physical Signoff Results)

### 7.1. Kết Quả Mô Phỏng & Functional Verification
- **Unit Testbench (`tb_phase2_math_ai.v`):** Vượt qua **113/113 test case (100% PASS)** bao gồm các góc biên số học $0, \pm 1, -2^{31}, 2^{31}-1$, tích tràn bit, và 100 vector INT8 ngẫu nhiên.
- **AI Kernel Benchmark (`tb_ai_benchmark.v`):**
  * Tích vô hướng 16 phần tử INT8: **27 chu kỳ clock** (so với ~320 chu kỳ của scalar baseline) $\rightarrow$ **Tăng tốc thực tế 11.85x!**
  * Kết quả tính toán khớp chính xác 100% với mô hình toán học mẫu.
- **Sorting Benchmark (`tb_bubble_sort.v`):** Vượt qua với kết quả sắp xếp đúng 100% và CPI giữ vững ở mức $1.398$.
- **Linting Quality (`make lint`):** **0 Error / 0 Warning** trên toàn bộ 19 module RTL.

### 7.2. Kết Quả Layout Vật Lý & Signoff STA (OpenLane 2 trên SkyWater 130nm)
- **Tần số cực đại ($F_{max}$ sau Detailed Routing & SPEF Extraction):**
  * Typical Corner (`nom_tt_025C_1v80`): Setup Slack = $+1.863\text{ ns}$ tại $28.0\text{ ns} \rightarrow \mathbf{F_{max} = 38.26\text{ MHz}}$.
  * Fast Corner (`nom_ff_n40C_1v95`): Setup Slack = $+3.578\text{ ns} \rightarrow \mathbf{F_{max} = 40.95\text{ MHz}}$.
  * Max Cap Corner (`max_tt_025C_1v80`): Setup Slack = $+0.833\text{ ns} \rightarrow \mathbf{F_{max} = 36.81\text{ MHz}}$.
  * **Hold Time:** **0 Hold Violations** trên toàn bộ 9 PVT corners.
- **Độ tin cậy Physical & Routing:**
  * **DRC Errors sau Detailed Routing (TritonRoute):** **0 DRC Errors**.
  * **Power Grid Violations:** **0 Violations**.
  * **Worst IR Drop:** $0.27\text{ mV}$ (chỉ $0.015\%$ điện áp $1.8\text{V}$).
- **Diện tích & Tài nguyên Silicon:**
  * Standard Cell Logic Area: $215,064\mu m^2$ ($0.215\text{ mm}^2$).
  * Macro SRAM 2KB Area: $284,538\mu m^2$ ($0.285\text{ mm}^2$).
  * Total Cell Area: $499,602\mu m^2$ ($\mathbf{0.500\text{ mm}^2}$).
  * Die Area: $1245.25\mu m \times 1255.97\mu m = \mathbf{1.564\text{ mm}^2}$.
  * Tổng số Standard Cells: $34,733$ cells (12,185 logic/DFF gates).
- **Công suất tiêu thụ (@ 35.7 MHz, 1.8V, 25°C):**
  * Total Power: $\mathbf{7.60\text{ mW}}$ (Internal: $6.00\text{ mW}$, Switching: $1.57\text{ mW}$, Leakage: $35.79\mu\text{W}$).
- **File kết quả bàn giao:** [`runs/RUN_2026-09-29_22-04-11/final/klayout_gds/riscv_core_top.klayout.gds`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/runs/RUN_2026-09-29_22-04-11/final/klayout_gds/riscv_core_top.klayout.gds) ($41\text{ MB}$).

