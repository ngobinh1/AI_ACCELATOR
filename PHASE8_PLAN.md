# KẾ HOẠCH THỰC THI PHASE 8: ĐẶC TẢ KIẾN TRÚC RTL, PNR OPENLANE & TỔNG HỢP KẾT QUẢ DỰ ÁN

---

## 1. MỤC TIÊU VÀ PHẠM VI (OBJECTIVES & SCOPE)

Phase 8 là giai đoạn hoàn thiện tài liệu kỹ thuật chuẩn công nghiệp, đóng gói vật lý (Physical Implementation Sign-Off) và tổng hợp toàn bộ kết quả dự án lõi vi xử lý **RISC-V IoT / AI Accelerator Core** (`riscv_core_top`). 

Giai đoạn này bao gồm 3 trụ cột chính:
1. **Viết lại toàn bộ Đặc tả thiết kế RTL ([SPEC.md](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/SPEC.md))**:
   - Sử dụng triệt để bộ kỹ năng **`rtl-spec-architect`** trong `~/.agents/skills/rtl_spec_architect`.
   - Áp dụng nguyên lý cốt lõi `NO SPEC -> NO RTL` và cấu trúc chuẩn **Top-down 4 chương**.
   - Thực thi quy tắc bắt buộc **4 tiểu mục cho Top Module và mọi Sub-Module**: Sơ đồ khối, Bảng chân tín hiệu chuẩn 8 cột, Nguyên lý hoạt động chi tiết, Giản đồ thời gian.
   - Sửa chữa 100% các sai lệch kiến trúc lịch sử giữa SPEC cũ và RTL thực tế (chuyển từ 2-stage sang 3-stage, bộ nhân Radix-16 8 chu kỳ thay vì Booth 1 chu kỳ, APB4 wait-states, mô hình bẫy ngắt commit/cancel, kiểm tra biên 2KB SRAM, RVC prefetch FIFO).
   - Chuẩn hoá format: Loại bỏ toàn bộ lỗi ký tự LaTeX thô, bảng có tiêu đề và ghi chú chân trang, tiền tố tham số `P_`/`PL_`, tín hiệu xung nhịp 1 chu kỳ dùng `pulse` (không dùng `tick`), Zero AI Watermark.
2. **Đồng bộ hoá Tài liệu Dự án ([README.md](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/README.md))**:
   - Cập nhật sơ đồ khối, đường ống 3 tầng, bảng tập lệnh, hướng dẫn mô phỏng với 9 testbench, kết quả PPA thực tế sau Phase 7.
3. **Chạy lại Luồng Vật lý PnR OpenLane ([config.json](file:///home/ngobinh/RISCV_IOT_AIACCELATOR/config.json)) & KLayout Sign-Off**:
   - Bổ sung `sync_2ff.v` vào danh sách file tổng hợp `VERILOG_FILES`.
   - Khởi chạy OpenLane v2.3.10 với tag `phase8_pnr_signoff`.
   - Thực hiện đầy đủ các bước: Yosys Synthesis -> Floorplan & PDN -> Global/Detailed Placement -> CTS -> Detailed Routing -> RCX Parasitic Extraction -> Sign-off STA -> KLayout Streamout.
4. **Tổng hợp Toàn diện Kết quả Dự án**:
   - Ma trận nghiệm thu 7 lỗi P0 và các khuyến nghị kiểm toán (R-xx).
   - Bảng điểm kiểm chứng chức năng (Scorecard: 9/9 Testbenches PASS 100%, Bubble Sort CPI = 1.366).
   - Báo cáo PPA vật lý (Fmax, WNS/TNS Setup & Hold, Core Area, Cell Count, Total Power).

---

## 2. CHI TIẾT CÁC BƯỚC THỰC HIỆN (EXECUTION WORKFLOW)

### Bước 8.1: Viết lại SPEC.md theo tiêu chuẩn `rtl-spec-architect`
Tuân thủ nghiêm ngặt 4 chương lớn theo định dạng:

- **Chương 1: Tổng Quan Hệ Thống & Kiến Trúc Thiết Kế**:
  - 1.1 Tổng quan thiết kế lõi `riscv_core_top` (RV32IC_Zicsr + Packed SIMD INT8).
  - 1.2 Phân loại yêu cầu thiết kế (Requirement Classification Table: ISA, Pipeline, Multiplier, Memory, Bus, Privileged Traps).
  - 1.3 Đột phá tối ưu PPA (Radix-16 shift-add, shared 33-bit adder, prefetch FIFO, 2KB Dual-Port OpenRAM).
  - 1.4 Sơ đồ kiến trúc tổng quan hệ thống.
  - 1.5 Bảng tham số kiến trúc (`P_DATA_WIDTH`, `P_ADDR_WIDTH`, `P_SRAM_SIZE_BYTES`, `P_CLK_PERIOD_NS`, v.v.).

- **Chương 2: Đặc Tả Top Module (`riscv_core_top`)**:
  - 2.1 Sơ đồ khối Top Module & Khung ranh giới ngoại vi.
  - 2.2 Bảng chân tín hiệu ngoại vi Top Module (8 cột chuẩn: `Tên chân | Hướng | Số bit | Loại | Miền Clock | Mô tả chức năng chi tiết | Điều kiện hợp lệ | Giá trị Reset`).
  - 2.3 Nguyên lý hoạt động tổng thể & Mối quan hệ tương tác giữa 24 sub-modules.
  - 2.4 Bảng kết nối nội bộ giữa các Sub-module (Internal Interconnect Table).
  - 2.5 Giản đồ thời gian tổng thể hoạt động của đường ống 3 tầng.

- **Chương 3: Đặc Tả Chi Tiết Từng Sub-Module (Quy tắc 4 tiểu mục bắt buộc cho từng khối)**:
  Mỗi sub-module có riêng 1 mục độc lập (không gộp, không lược bỏ):
  1. `stage_if` (Tầng Nạp Lệnh, Prefetch FIFO 2-word, RVC Decompressor & Xử lý Redirect)
  2. `pipe_reg_if_id` (Thanh Ghi Đường Ống IF -> ID)
  3. `stage_id_ex` (Tầng Giải Mã & Thực Thi: ID/EX Datapath)
  4. `instruction_decoder` (Bộ Giải Mã Lệnh RV32I / RV32M / SIMD / CSR)
  5. `register_file` (Tập Thanh Ghi 32x32 với Async Read & Forwarding)
  6. `imm_gen` (Bộ Sinh Số Tức Thời Đa Định Dạng I, S, B, U, J)
  7. `alu` (Khối ALU 32-bit với Bộ Cộng/Trừ Chia Sẻ 33-bit)
  8. `booth_multiplier_32b` (Bộ Nhân Tuần Tự 8 Chu Kỳ Radix-16 Shift-Add)
  9. `simd_mac_unit` (Bộ Tăng Tốc AI Packed SIMD 4x INT8 Dot-Product `smdot.i8`)
  10. `branch_comparator` (Bộ So Sánh & Đánh Giá Nhánh Tức Thời)
  11. `pipe_reg_ex_mem` (Thanh Ghi Đường Ống EX -> MEM/WB)
  12. `stage_mem_wb` (Tầng Truy Xuất Bộ Nhớ & Ghi Trả Kết Quả MEM/WB)
  13. `be_gen` (Khối Sinh Mặt Nạ Byte Enable 4-bit)
  14. `st_align` (Khối Căn Chỉnh Dữ Liệu Ghi Bộ Nhớ)
  15. `load_align` (Khối Căn Chỉnh & Mở Rộng Dấu Dữ Liệu Đọc Bộ Nhớ)
  16. `forwarding_unit` (Khối Chuyển Tiếp Dữ Liệu Single-Stage Forwarding từ Stage 3)
  17. `hazard_unit` (Khối Điều Phối Xung Đột, Stall/Flush & Bẫy Ngắt)
  18. `csr` (Khối Thanh Ghi Machine-Mode CSR & Trap Controller)
  19. `sync_2ff` (Khối Đồng Bộ Hoá 2 Tầng Flip-Flop Cho Tín Hiệu Ngắt Ngoài)
  20. `apb_bridge` (Cầu Nối Master AMBA 4 APB Hỗ Trợ Wait-States)
  21. `rvc_decompressor` (Bộ Giải Mã Lệnh Nén 16-bit Thành 32-bit)
  22. `sky130_sram_2kbyte_1rw1r_32x512_8` (Macro Bộ Nhớ SRAM 2KB Dual-Port 1RW1R)

- **Chương 4: Ma Trận Truy Xuất Yêu Cầu (RTM) & Kế Hoạch Kiểm Chứng**:
  - 4.1 Ma trận RTM (Requirement Traceability Matrix) liên kết 100% yêu cầu chức năng với module và testbench.
  - 4.2 Kế hoạch kiểm chứng chức năng (Mô tả 9 Testbenches).
  - 4.3 Bảng điểm kiểm chứng (Verification Scorecard: 100% Pass, Code Coverage, CPI Bubble Sort).

---

### Bước 8.2: Cập nhật README.md đồng bộ
- Cập nhật cấu trúc thư mục thực tế (loại bỏ các file cũ không tồn tại như `stage_ex.v`, `pipe_reg_id_ex.v`, thêm `sync_2ff.v`, `pipe_reg_ex_mem.v`).
- Cập nhật sơ đồ đường ống 3 tầng và biểu đồ chu kỳ lệnh.
- Cập nhật hướng dẫn chạy mô phỏng (`make sim`, `make sim-phase5`, `make sim-phase6`, `make sim-isa`, `make sim-all`, `make lint`).
- Cập nhật thông số PPA thực tế sau Phase 7 & 8.

---

### Bước 8.3: Cấu hình và Chạy lại PnR OpenLane
1. **Kiểm tra và cập nhật `config.json`**:
   - Thêm `"dir::rtl/core/sync_2ff.v"` vào mảng `VERILOG_FILES`.
   - Đảm bảo `CLOCK_PERIOD = 12.0` (83.33 MHz target) hoặc tối ưu theo slack.
2. **Thực thi luồng OpenLane**:
   - Chạy lệnh: `openlane --run-tag phase8_pnr_signoff config.json`.
   - Giám sát log qua các step:
     - Step 01: Verilator Lint
     - Step 06: Yosys Synthesis & Tech Mapping (`sky130_fd_sc_hd`)
     - Step 12: STA Pre-PNR
     - Step 13: OpenROAD Floorplanning & Macro Placement (`u_sram_2kb`)
     - Step 20: PDN Generation
     - Step 27/32: Global & Detailed Placement
     - Step 34: Clock Tree Synthesis (TritonCTS)
     - Step 37/42: Global & Detailed Routing (TritonRoute)
     - Step 52: RCX Extraction
     - Step 53: STA Post-PNR Sign-off
     - Step 55: KLayout Streamout (GDSII)
3. **Trích xuất số liệu PPA**:
   - Tần số hoạt động cực đại ($F_{max}$), Chu kỳ xung nhịp ($T_{clk}$).
   - WNS (Worst Negative Slack), TNS (Total Negative Slack) cho cả Setup và Hold.
   - Số lượng Standard Cells, Macro count, mật độ lõi (Core Utilization).
   - Diện tích lõi (Core Area) và diện tích die (Die Area).
   - Công suất tiêu thụ (Dynamic, Leakage, Total Power).
   - Kết quả kiểm tra DRC, LVS, Antenna.

---

### Bước 8.4: Tổng Hợp Báo Cáo Nghiệm Thu Toàn Diện
Tạo tài liệu tổng kết toàn bộ dự án:
- Tổng hợp toàn bộ 8 phase thực thi.
- Danh sách 7 lỗi P0 và các lỗi R-xx được khắc phục hoàn toàn.
- Bảng so sánh trước và sau kiểm toán (Baseline vs. Sign-off).
- Bảng tổng hợp PPA vật lý và hiệu năng phần mềm (Bubble Sort CPI, AI Benchmark).

---

## 3. TIÊU CHÍ NGHIỆM THU (VERIFICATION & QUALITY GATES)

| Cổng Kiểm Tra | Nội Dung Kiểm Tra | Tiêu Chí Đạt (Passing Criteria) |
| :--- | :--- | :--- |
| **Gate 8.1** | **RTL Spec Architecture Audit** | Đạt 100% checklist kỹ năng `rtl-spec-architect`: Cấu trúc 4 chương, 4 tiểu mục cho Top và mọi Sub-module, bảng 8 cột, tiêu đề + ghi chú bảng, Zero LaTeX glitch, Zero AI watermark. |
| **Gate 8.2** | **RTL Lint & Simulation Regression** | `make lint` đạt **0 Errors, 0 Warnings**.<br>`make sim-all` đạt **9/9 Testbenches PASS 100%**. |
| **Gate 8.3** | **PnR Physical Sign-off** | Luồng OpenLane kết thúc thành công với view GDS hoàn chỉnh (`runs/phase8_pnr_signoff/final`). WNS Setup $\ge 0$, WNS Hold $\ge 0$, 0 DRC violations. |
| **Gate 8.4** | **Project Synthesis & Documentation** | Đồng bộ 100% giữa RTL, SPEC, README và Báo cáo tổng kết. |

---

## 4. DỰ KIẾN KẾT QUẢ ĐẦU RA (DELIVERABLES)
1. `SPEC.md`: Tài liệu đặc tả kiến trúc RTL hoàn chỉnh chuẩn công nghiệp (~2000+ dòng).
2. `README.md`: Hướng dẫn sử dụng và báo cáo tổng quan dự án đồng bộ.
3. `config.json`: File cấu hình OpenLane đã cập nhật module mới.
4. `runs/phase8_pnr_signoff/`: Thư mục kết quả PnR hoàn chỉnh (GDS, DEF, SPEF, SDF, STA report).
5. Báo cáo nghiệm thu dự án tổng hợp gửi người dùng.
