# Kế Hoạch Triển Khai Chi Tiết - Giai Đoạn 5 (PHASE 5)
## Khắc Phục Các Lỗi Phần Cứng Mức P0 Về Đường Dữ Liệu (Datapath), Chuyển Tiếp (Forwarding) & Khóa Xung Đột Bộ Nhân (Multiplier Interlock)

**Dự án:** RISC-V 32-bit IoT & AI Accelerator Core (`riscv_core_top`)  
**Giai đoạn:** Phase 5 (Triển khai Bước 1 trong lộ trình đóng kín tính đúng đắn vi kiến trúc)  
**Mục tiêu chính:** Khắc phục triệt để 4 lỗi phần cứng mức P0 (`P0-1`, `P0-2`, `P0-3`, `P0-4`) đã được thẩm tra và xác nhận trong báo cáo kiểm toán, tái lập tính đúng đắn cho luồng dữ liệu đọc/ghi CSR, chuyển tiếp `JAL/JALR` và khóa liên động Load-to-Use đi vào bộ nhân.

---

## 1. Bối Cảnh & Mục Tiêu Của Phase 5

### 1.1. Hiện Trạng Kỹ Thuật Trước Khi Bước Vào Phase 5
Qua quá trình kiểm toán chi tiết và kiểm chứng chu kỳ xung nhịp (cycle-accurate verification), 4 lỗi nghiêm trọng thuộc tầng Datapath và Forwarding đang trực tiếp phá vỡ tính đúng đắn kiến trúc của CPU:
1. **P0-1 (Lệch tầng đường ống khi đọc CSR):** Khối `csr.v` nhận điều khiển từ Tầng 3 nhưng ngõ ra `w_csr_data` bị nối ngược về Tầng 2, chốt qua `pipe_reg_ex_mem` một chu kỳ trước khi lệnh CSR kịp tới Tầng 3. Hệ quả là mọi lệnh đọc CSR đều trả về `0x0000_0000` hoặc dữ liệu cũ vào thanh ghi đích `rd`.
2. **P0-2 (Ngõ vào ghi CSR lấy nhầm `rs2` thay vì `rs1`):** Cổng `u_csr.i_rs1_data` trong `core_top.v` nối vào `w_ex_mem_store_data` (vốn mang dữ liệu `rs2`). Do lệnh khởi tạo `csrw mscratch, t0` có trường `instr[24:20] = 5'd0` (`x0`), thanh ghi `mscratch` bị ghi âm thầm giá trị `0` thay vì địa chỉ stack `_kernel_stack_top`.
3. **P0-3 (Xung đột Load-to-Use đi vào Bộ nhân chốt sai toán hạng):** Trong `stage_id_ex.v`, tín hiệu khởi động `i_mul_valid` không bị khóa bởi `~w_stall_load_use`. Khi lệnh `LW` liền trước lệnh `MUL` có phụ thuộc dữ liệu RAW, bộ nhân khởi động ngay trong chu kỳ stall và chốt địa chỉ RAM của lệnh `LW` thay vì chờ dữ liệu đọc về.
4. **P0-4 (Forwarding Tầng 3 bỏ qua `PC+4`/`CSR` và chứa logic chết `FWD_MEM_WB`):** `forwarding_unit.v` thiết kế 2 mức nhưng cả 2 đều nối chung vào tín hiệu Tầng 3. Đồng thời, `FWD_EX_MEM` chỉ chuyển tiếp `w_ex_mem_result` thay vì `w_wb_data`, khiến lệnh đọc `rd` (`ra`) liền sau `JAL/JALR` nhận giá trị `0x0000_0000` thay vì `PC+4`.

### 1.2. Mục Tiêu Cụ Thể Của Phase 5
- [ ] **Sửa P0-1**: Đấu nối trực tiếp ngõ ra tổ hợp đọc CSR `w_csr_data` từ `u_csr` vào cổng chọn ghi trả `i_csr_data` của `stage_mem_wb.v` ở Tầng 3. Loại bỏ việc chốt trung gian qua `stage_id_ex.v` và `pipe_reg_ex_mem.v`.
- [ ] **Sửa P0-2**: Bổ sung đường dẫn dữ liệu `rs1` (đã chuyển tiếp) từ Tầng 2 chốt qua `pipe_reg_ex_mem.v` sang Tầng 3 (`w_ex_mem_rs1_data`) và nối vào `u_csr.i_rs1_data`.
- [ ] **Sửa P0-3**: Khóa cổng `u_multiplier.i_mul_valid` bằng `~w_stall_load_use` trong `stage_id_ex.v`.
- [ ] **Sửa P0-4**: Chuyển tiếp giá trị ghi trả hoàn chỉnh `w_wb_data` (chứa kết quả ALU, `PC+4` hoặc dữ liệu CSR) từ Tầng 3 về Tầng 2. Tinh gọn `forwarding_unit.v`, loại bỏ hoàn toàn nhánh chết `FWD_MEM_WB`.
- [ ] **Bảo toàn 100% các tính năng hiện có**: Đảm bảo các bài kiểm thử cơ sở cũ trong `tb/` không bị suy thoái (zero regression).

---

## 2. Thiết Kế Chi Tiết & Giải Pháp Kỹ Thuật (Detailed Technical Design)

```mermaid
flowchart TD
    subgraph STAGE_2 ["TẦNG 2: stage_id_ex.v"]
        DEC["Bộ Giải Mã & Imm Gen"]
        RF["Register File (Đọc Bất Đồng Bộ)"]
        FWD_MUX["MUX Chuyển Tiếp (rs1, rs2, store)"]
        ALU_UNIT["ALU 33-bit / SIMD"]
        MUL_UNIT["Bộ Nhân Tuần Tự 8-chu kỳ\n(booth_multiplier_32b)"]
        
        STALL_CHECK{"w_stall_load_use == 1?"}
        STALL_CHECK -->|Yes| MUL_GATE["Khóa i_mul_valid = 0\n(Sửa lỗi P0-3)"]
        STALL_CHECK -->|No| MUL_RUN["Bật i_mul_valid bình thường"]
    end

    subgraph PIPE_REG ["VÁCH NGĂN: pipe_reg_ex_mem.v"]
        REG_RS1["Chốt Thêm Toán Hạng rs1 Đã Fwd\n(w_id_ex_rs1_data -> w_ex_mem_rs1_data)\n(Sửa lỗi P0-2)"]
        REG_CTRL["Chốt Control Signals (Mem, WB, CSR Addr/En)"]
        DEL_CSR_REG["LOẠI BỎ: Chốt r_csr_data cũ\n(Sửa lỗi P0-1)"]
    end

    subgraph STAGE_3 ["TẦNG 3: stage_mem_wb.v & csr.v"]
        CSR_MOD["CSR Unit (csr.v)\nNhận w_ex_mem_rs1_data & addr\nSinh w_csr_data tổ hợp"]
        MEM_ALIGN["SRAM Data / APB Load Alignment"]
        WB_MUX["MUX Ghi Trả (stage_mem_wb)\n00: EX_Result\n01: Mem_Data\n10: PC+4\n11: w_csr_data (Nối trực tiếp!)"]
        WB_OUT["w_wb_data (Dữ liệu commit cuối cùng)"]
    end

    subgraph FORWARDING ["KHỐI CHUYỂN TIẾP: forwarding_unit.v"]
        FWD_UNIT["Forwarding Unit Đơn Tầng (Tầng 3 -> Tầng 2)\nChuyển tiếp w_wb_data\n(Sửa lỗi P0-4: Hỗ trợ PC+4 / CSR / ALU)"]
    end

    STAGE_2 --> PIPE_REG
    PIPE_REG --> STAGE_3
    CSR_MOD -->|w_csr_data (Direct)| WB_MUX
    WB_MUX --> WB_OUT
    WB_OUT -->|Forwarding Bus| FWD_UNIT
    FWD_UNIT -->|fwd_data| FWD_MUX
```

---

### 2.1. Chi Tiết Sửa Lỗi P0-1 (Đường Dữ Liệu Đọc CSR)

#### Nguyên nhân kỹ thuật:
Hiện tại, `core_top.v` nối cổng `u_stage_id_ex.i_csr_data (w_csr_data)` ở dòng 333, sau đó `stage_id_ex` truyền thẳng ra `o_csr_data` (dòng 385), rồi đưa vào `u_pipe_reg_ex_mem.i_csr_data` ở dòng 395 để chốt thành `w_ex_mem_csr_data`. Nhưng các tín hiệu điều khiển `w_ex_mem_csr_read`, `w_ex_mem_csr_addr` kích hoạt `u_csr` chỉ có hiệu lực ở Tầng 3. Do đó, dữ liệu đọc được chốt trước 1 chu kỳ, khi lệnh CSR còn chưa tới Tầng 3.

#### Giải pháp hiện thực:
1. Trong [`rtl/core/stage_id_ex.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/stage_id_ex.v):
   - Xóa cổng ngõ vào `input wire [DATA_WIDTH-1:0] i_csr_data`.
   - Xóa cổng ngõ ra `output wire [DATA_WIDTH-1:0] o_csr_data`.
2. Trong [`rtl/core/pipe_reg_ex_mem.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/pipe_reg_ex_mem.v):
   - Xóa cổng `input wire [DATA_WIDTH-1:0] i_csr_data`.
   - Xóa cổng `output reg [DATA_WIDTH-1:0] o_csr_data`.
   - Xóa thanh ghi chốt `r_csr_data`.
3. Trong [`rtl/core/core_top.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/core_top.v):
   - Xóa dây `w_id_ex_csr_data` và `w_ex_mem_csr_data`.
   - Nối trực tiếp ngõ ra tổ hợp `w_csr_data` từ module `u_csr` vào cổng `u_stage_mem_wb.i_csr_data`:
     ```verilog
     .i_csr_data (w_csr_data),
     ```
   - Khi lệnh CSR tới Tầng 3, `w_ex_mem_csr_addr` và `w_ex_mem_csr_read` kích hoạt `u_csr` xuất dữ liệu `w_csr_data` trong cùng chu kỳ, đi thẳng vào MUX ghi trả `stage_mem_wb` và ghi vào Register File chính xác 100%.

---

### 2.2. Chi Tiết Sửa Lỗi P0-2 (Đường Dữ Liệu Ghi CSR)

#### Nguyên nhân kỹ thuật:
Tại `core_top.v` dòng 517:
```verilog
u_csr u_csr (
    ...
    .i_rs1_data (w_ex_mem_store_data), // SAI: w_ex_mem_store_data là RS2!
    .i_rs1_addr (w_ex_mem_rs1_addr),
    ...
);
```
`w_ex_mem_store_data` đến từ `w_fwd_store_data` ở Tầng 2, vốn được thiết kế cho dữ liệu ghi bộ nhớ (`SW/SH/SB`) từ thanh ghi `rs2`. Trường `instr[24:20]` trong lệnh CSR là 5 bit thấp của địa chỉ CSR chứ không phải số hiệu thanh ghi `rs1`.

#### Giải pháp hiện thực:
1. Trong [`rtl/core/stage_id_ex.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/stage_id_ex.v):
   - Xuất thêm đường dữ liệu `rs1` đã qua bộ chọn chuyển tiếp:
     ```verilog
     output wire [DATA_WIDTH-1:0] o_rs1_data
     assign o_rs1_data = w_fwd_rs1_data;
     ```
2. Trong [`rtl/core/pipe_reg_ex_mem.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/pipe_reg_ex_mem.v):
   - Thêm cổng `input wire [DATA_WIDTH-1:0] i_rs1_data`.
   - Thêm cổng `output reg [DATA_WIDTH-1:0] o_rs1_data`.
   - Chốt dữ liệu qua thanh ghi đồng bộ: `r_rs1_data <= i_rs1_data;`.
3. Trong [`rtl/core/core_top.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/core_top.v):
   - Khai báo wire `w_id_ex_rs1_data` và `w_ex_mem_rs1_data`.
   - Nối `u_csr.i_rs1_data (w_ex_mem_rs1_data)`.
   - Đảm bảo khi thực hiện `csrw mscratch, t0`, giá trị của `t0` từ Tầng 2 được chuyển tiếp chính xác sang Tầng 3 và ghi vào `mscratch`.

---

### 2.3. Chi Tiết Sửa Lỗi P0-3 (Khóa Khởi Động Bộ Nhân Khi Load-to-Use Stall)

#### Nguyên nhân kỹ thuật:
Tại `stage_id_ex.v` dòng 292:
```verilog
booth_multiplier_32b u_multiplier (
    .i_clk          (i_clk),
    .i_rst_n        (i_rst_n),
    .i_mul_valid    (w_mul_valid & i_valid), // THIẾU: Không bị khóa bởi w_stall_load_use!
    ...
);
```
Khi chuỗi lệnh `LW x5, 0(x1)` đi liền trước `MUL x6, x5, x2` xuất hiện:
- `forwarding_unit` phát hiện xung đột Load-to-Use và kéo `o_stall_load_use = 1`.
- `hazard_unit` đóng băng Tầng 1 và Tầng 2 (`o_stall_if = 1`, `o_stall_id_ex = 1`).
- Tuy nhiên, vì `i_valid` của Tầng 2 vẫn bằng 1, `u_multiplier` nhận `i_mul_valid = 1` ngay trong chu kỳ stall đầu tiên và chốt các toán hạng hiện tại. Lúc này, `w_fwd_rs1_data` nhận dữ liệu chuyển tiếp từ `w_ex_mem_result` của lệnh `LW` (vốn là **địa chỉ bộ nhớ**, chứ không phải dữ liệu nạp từ RAM!). Kết quả phép nhân bị sai hoàn toàn.

#### Giải pháp hiện thực:
Trong [`rtl/core/stage_id_ex.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/stage_id_ex.v):
1. Sửa tín hiệu kích hoạt bộ nhân tại dòng 292:
   ```verilog
   .i_mul_valid (w_mul_valid & i_valid & ~w_stall_load_use),
   ```
2. Cập nhật tín hiệu báo bận `o_mul_busy` tại dòng 303:
   ```verilog
   assign o_mul_busy = w_mul_valid & i_valid & ~w_stall_load_use & ~w_mul_ready;
   ```
3. Trong chu kỳ stall, bộ nhân ở trạng thái nghỉ `S_IDLE`. Ở chu kỳ kế tiếp, khi dữ liệu đọc từ RAM đã hoàn tất và ghi vào Register File, stall được nhả (`w_stall_load_use = 0`), bộ nhân mới bắt đầu chốt toán hạng chính xác và chuyển sang `S_CALC`.

---

### 2.4. Chi Tiết Sửa Lỗi P0-4 (Tái Cấu Trúc Khối Forwarding & Chuyển Tiếp `w_wb_data`)

#### Nguyên nhân kỹ thuật:
1. `core_top.v` dòng 326 nối:
   ```verilog
   .i_fwd_ex_mem_data (w_ex_mem_result), // Chỉ mang kết quả ALU/MUL/SIMD!
   .i_fwd_mem_wb_data (w_wb_data),
   ```
   Lệnh `JAL` hoặc `JALR` ghi trả giá trị `PC+4` vào thanh ghi liên kết `rd`. Giá trị `PC+4` này được sinh ra ở Tầng 3 trong MUX ghi trả `stage_mem_wb` (khi `result_src == 2'b10`). Do `forwarding_unit` kích hoạt mức ưu tiên `FWD_EX_MEM (2'b10)`, nó chọn `i_fwd_ex_mem_data` (`w_ex_mem_result`), kết quả là chuyển tiếp giá trị rác hoặc số 0 thay vì `PC+4`.
2. Trong `core_top.v` dòng 293-300:
   ```verilog
   .i_ex_mem_rd        (w_ex_mem_rd_addr),
   .i_ex_mem_reg_write (w_ex_mem_reg_write),
   ...
   .i_mem_wb_rd        (w_wb_rd_addr),        // w_wb_rd_addr == w_ex_mem_rd_addr
   .i_mem_wb_reg_write (w_wb_we),             // w_wb_we phụ thuộc trực tiếp w_ex_mem_reg_write
   ```
   Cả hai tầng đầu vào của `forwarding_unit` đều trỏ vào cùng một lệnh tại Tầng 3. Nhánh `FWD_MEM_WB (2'b01)` là logic chết 100%.

#### Giải pháp hiện thực:
1. Đổi nguồn chuyển tiếp của Tầng 3 trong [`rtl/core/core_top.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/core_top.v#L326):
   - Đưa trực tiếp `w_wb_data` (ngõ ra MUX ghi trả hoàn chỉnh của `stage_mem_wb`) vào cổng dữ liệu chuyển tiếp của Tầng 2.
2. Tinh gọn [`rtl/core/forwarding_unit.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/forwarding_unit.v):
   - Trong đường ống 3 tầng, chỉ cần 1 mức chuyển tiếp duy nhất từ Tầng 3 về Tầng 2 (`FWD_STAGE3` = 1'b1 / `FWD_NONE` = 1'b0).
   - Mã hóa gọn gàng:
     ```verilog
     // Chuyển tiếp toán hạng RS1
     if (i_ex_mem_reg_write && (i_ex_mem_rd != 5'd0) && (i_ex_mem_rd == i_id_ex_rs1))
         o_fwd_a = FWD_STAGE3;
     else
         o_fwd_a = FWD_NONE;
     ```
   - Tương tự cho `RS2` và `Store Data`.
   - Xóa bỏ các cổng đầu vào thừa `i_mem_wb_*`, giảm số chân kết nối và độ trễ đường truyền.

---

## 3. Danh Mục Các Tệp Mã Nguồn Cần Chỉnh Sửa

| Tệp tin | Vị trí thay đổi | Mục đích thay đổi | Mức tác động |
| :--- | :--- | :--- | :---: |
| [`rtl/core/stage_id_ex.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/stage_id_ex.v) | Dòng 292, 303; xóa `i_csr_data`, thêm `o_rs1_data` | Khóa bộ nhân khi có stall Load-to-Use; xuất `rs1` ra Tầng 3 | **P0-3, P0-2** |
| [`rtl/core/pipe_reg_ex_mem.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/pipe_reg_ex_mem.v) | Xóa chốt `r_csr_data`; thêm chốt `r_rs1_data` | Dẫn truyền đúng `rs1` đã fwd cho CSR; bỏ chốt CSR cũ | **P0-1, P0-2** |
| [`rtl/core/forwarding_unit.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/forwarding_unit.v) | Đơn giản hóa logic chọn FWD, dọn dead logic | Tối ưu hóa mạch chuyển tiếp đơn tầng | **P0-4** |
| [`rtl/core/core_top.v`](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/rtl/core/core_top.v) | Đấu nối lại `u_csr.i_rs1_data`, `u_stage_mem_wb.i_csr_data`, `i_fwd_*_data` | Liên kết đúng toàn bộ đường dữ liệu đã sửa | **P0-1, P0-2, P0-4** |

---

## 4. Kế Hoạch Kiểm Chứng & Xác Thực Của Phase 5 (Verification Plan)

Để đảm bảo các sửa đổi trong Phase 5 là chính xác tuyệt đối và không gây hồi quy (Zero Regression):

### 4.1. Bộ Kiểm Thử Đơn Vị & Tích Hợp Có Hướng Mới (`tb/tb_phase5_datapath_p0.v`)
Xây dựng một testbench chuyên biệt kiểm tra 4 kịch bản biên:
1. **Testcase 1 (CSR Read/Write P0-1, P0-2)**:
   - Nạp giá trị `0x1234_5678` vào thanh ghi `t0`.
   - Thực thi `csrw mscratch, t0`.
   - Đọc lại `csrr t1, mscratch`.
   - So sánh tự động: Xác nhận `t1 == 0x1234_5678` (chứng minh sửa xong cả P0-1 và P0-2).
2. **Testcase 2 (Load-to-Use -> Multiplier P0-3)**:
   - Ghi giá trị `15` vào ô nhớ SRAM `0x100`.
   - Nạp `LW t0, 0(s0)` (s0 = 0x100).
   - Lệnh kế tiếp ngay sau: `MUL t1, t0, s1` (với s1 = 4).
   - Kiểm tra: Xác nhận sau khi tính toán, `t1 == 60` (chứ không phải $0x100 \times 4 = 1024$).
3. **Testcase 3 (Early JAL / JALR Forwarding P0-4)**:
   - Thực thi `JAL ra, target_label`.
   - Lệnh đầu tiên tại đích nhảy: `ADDI t0, ra, 0` (đọc ngay `ra`).
   - Kiểm tra: `t0` phải bằng chính xác `PC_JAL + 4`.

### 4.2. Chạy Hồi Quy Các Testbench Hiện Hữu (Regression Suite)
Chạy toàn bộ 6 testbench cũ để đảm bảo kết quả không suy giảm:
- `make sim_bubble_sort` (xác nhận Bubble Sort 10 phần tử vẫn PASS).
- `make sim_math_ai` (xác nhận `booth_multiplier_32b` và `simd_mac_unit` PASS 100%).
- `make sim_hazards` (xác nhận các hazard ALU cũ PASS).
- `make sim_rvc_pipeline` (xác nhận đường ống nén RV32C PASS).

---

## 5. Tiêu Chí Hoàn Thành Phase 5 (Definition of Done)

1. [ ] Sửa xong toàn bộ 4 lỗi `P0-1`, `P0-2`, `P0-3`, `P0-4` trong 4 tệp RTL mục tiêu.
2. [ ] Testbench `tb/tb_phase5_datapath_p0.v` chạy trên QuestaSim đạt **PASS 100%** trên cả 3 testcase.
3. [ ] Toàn bộ 6 testbench hiện hữu trong `tb/` chạy đạt **100% PASS** (Zero Regression).
4. [ ] Không đưa bất kỳ AI watermark hay chú thích tự động nào vào mã nguồn theo quy tắc `~/.agents/AGENTS.md`.
