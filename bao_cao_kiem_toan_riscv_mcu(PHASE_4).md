# Báo Cáo Kiểm Toán Toàn Diện Kiến Trúc, RTL, Kiểm Chứng (Verification), SoC và Thiết Kế Vật Lý (Physical Design): `riscv_core_top`

## 1. Tóm Tắt Điều Hành (Executive Summary)

Qua quá trình kiểm tra chi tiết từng dòng mã nguồn và mô phỏng chính xác theo từng chu kỳ xung nhịp (cycle-accurate reconstruction) trên toàn bộ kho mã nguồn `RISCV_IOT_AIACCELATOR`, chúng tôi phát hiện **sự sai lệch kiến trúc lớn giữa tài liệu (`README.md` và `SPEC.md`) so với mã RTL thực tế (`rtl/`)**, cùng với **sáu lỗi phần cứng mức P0 (chặn đứng tính đúng đắn chức năng)** phát sinh trong quá trình nâng cấp đường ống qua nhiều giai đoạn.

### Các Phát Hiện Cốt Lõi

1. **Độ Lệch Lớn Giữa Tài Liệu và RTL Thực Tế**:
   - `README.md` mô tả **phiên bản gốc Phase 0** (đường ống 2 tầng `IF/ID` $\rightarrow$ `EX/MEM/WB`, tập lệnh RV32I + bộ nhân RV32M 17 chu kỳ, không có khối Forwarding riêng, Bubble Sort chạy 503 chu kỳ). Tài liệu này thậm chí vẫn liệt kê các tệp trong cây thư mục (`rtl/core/pipe_reg_id_ex.v`, `rtl/core/stage_ex.v`) **đã bị xóa khỏi kho mã nguồn**.
   - `SPEC.md` (v2.0.0) mô tả **trạng thái trung gian Phase 2** (đường ống 2 tầng với bộ nhân tổ hợp 1 chu kỳ 33×33, sử dụng `stage_if_id`, `pipe_reg_id_ex` và `stage_ex`).
   - **Mã RTL thực tế (`rtl/`)** hiện thực hóa **kiến trúc Phase 4** (chỉ được ghi nhận trong `PHASE3_PLAN.md`, `PHASE4_PLAN.md` và `PROJECT_PHASES_SUMMARY.md`): **đường ống 3 tầng (`Stage 1: IF` $\rightarrow$ `pipe_reg_if_id` $\rightarrow$ `Stage 2: ID/EX` $\rightarrow$ `pipe_reg_ex_mem` $\rightarrow$ `Stage 3: MEM/WB`)** tích hợp hàng đợi nạp lệnh trước (Prefetch FIFO) 2 từ 32-bit, bộ giải nén lệnh 16-bit **RV32C** 0 chu kỳ (`rvc_decompressor.v`), giải quyết sớm lệnh nhảy `JAL` (Early JAL), dự đoán nhánh tĩnh BTFN với đường phục hồi đoán sai 2 chu kỳ, **bộ nhân tuần tự 8 chu kỳ** dịch-cộng 4-bit/chu kỳ (`booth_multiplier_32b.v`), **khối tính tích vô hướng SIMD 4×INT8** (`simd_mac_unit.v`, lệnh `smdot.i8`), và khối chuyển tiếp dữ liệu 3 tầng (`forwarding_unit.v`).
2. **Các Lỗi Đúng Đắn RTL Mức P0 (Showstopper Bugs) Được Phát Hiện**:
   - **P0-1 (Lệch tầng đường ống khi đọc CSR)**: Khối `CSR_Unit` (`csr.v`) nhận các tín hiệu điều khiển và địa chỉ từ Tầng 3 (`w_ex_mem_*`), nhưng ngõ ra dữ liệu đọc tổ hợp `w_csr_data` lại được nối ngược về Tầng 2 (`stage_id_ex.i_csr_data`), chốt qua thanh ghi `pipe_reg_ex_mem` (`w_ex_mem_csr_data`) **một chu kỳ trước khi** lệnh CSR kịp tới `CSR_Unit`, rồi mới đưa vào bộ chọn ghi trả ở `stage_mem_wb`. Hệ quả là **mọi lệnh đọc CSR (`csrr`, `csrrw`, `csrrs`, `csrrc`) đều ghi trả `0x00000000`** (hoặc giá trị CSR của lệnh liền trước) vào thanh ghi đích `rd`.
   - **P0-2 (Ngõ vào dữ liệu ghi CSR bị nối nhầm sang `rs2` thay vì `rs1`)**: Trong `core_top.v` (dòng 517), cổng `u_csr.i_rs1_data` được nối vào `w_ex_mem_store_data` (vốn mang **dữ liệu `rs2`** đã chuyển tiếp, tức `instr[24:20] = csr_addr[4:0]`, chứ KHÔNG PHẢI dữ liệu `rs1`). Khi `Start.S` thực thi lệnh `csrw mscratch, t0` (`0x34029073`), trường `instr[24:20]` bằng `5'd0` (`x0`), nên **thanh ghi `mscratch` bị ghi âm thầm giá trị `0x00000000` thay vì `t0` (`0x800`)**. (Lệnh `csrw mtvec, t0` tại địa chỉ `0x305` chỉ tình cờ chạy đúng vì mã địa chỉ `12'h305` có 5 bit thấp `[4:0] == 5'd5`, trùng khớp ngẫu nhiên với chỉ số thanh ghi `t0 = x5`!).
   - **P0-3 (Xung đột Load-to-Use đi vào Bộ nhân làm chốt sai toán hạng)**: Trong `stage_id_ex.v` (dòng 292), tín hiệu khởi động `u_multiplier.i_mul_valid` được gán bằng `w_mul_valid & i_valid` mà không bị khóa bởi `~w_stall_load_use`. Khi lệnh `LW` ở Tầng 3 đi liền trước lệnh `MUL` ở Tầng 2 có phụ thuộc dữ liệu RAW, `booth_multiplier_32b` khởi chạy ngay trong chu kỳ stall và chốt `w_fwd_rs1_data` (`w_ex_mem_result`, tức **địa chỉ bộ nhớ của lệnh `LW`**) thay vì đợi 1 chu kỳ để nhận dữ liệu đọc từ RAM.
   - **P0-4 (Bộ chọn Forwarding từ Tầng 3 bỏ qua kết quả `PC+4` / `CSR` và chứa logic chết `FWD_MEM_WB`)**: `forwarding_unit.v` thiết kế 2 mức ưu tiên chuyển tiếp (`FWD_EX_MEM` và `FWD_MEM_WB`), nhưng trong `core_top.v` (dòng 293–300) **cả hai mức này đều được nối vào cùng tín hiệu của Tầng 3 (`w_ex_mem_rd_addr` và `w_wb_rd_addr`)**, khiến nhánh `FWD_MEM_WB` trở thành logic chết 100% không bao giờ chạy tới. Nghiêm trọng hơn, `FWD_EX_MEM` chỉ chuyển tiếp `w_ex_mem_result` (ngõ ra ALU/MUL/SIMD) thay vì `w_wb_data`, nên nếu lệnh đầu tiên tại đích nhảy của `JAL rd, target` đọc ngay thanh ghi `rd` (`ra`), nó sẽ nhận giá trị `0x00000000` thay vì `PC+4`.
   - **P0-5 (Ngắt bất đồng bộ làm mất lệnh đang ở Tầng 3 và làm hỏng `mepc` khi gặp bong bóng đường ống)**: Khi ngắt `i_ext_irq` hoặc `i_timer_irq` kích hoạt `o_trap_taken = 1`, `hazard_unit.v` (dòng 127) kéo `o_wb_en = 0` (hủy bỏ việc ghi trả Register File của lệnh đang nằm ở Tầng 3), trong khi `csr.v` (dòng 129) lại lưu `mepc <= w_ex_mem_pc_plus_4` (PC của lệnh *kế tiếp*). Do đó, **lệnh ở Tầng 3 bị xóa sổ vĩnh viễn và không bao giờ được thực thi lại khi `MRET`**. Hơn nữa, `o_int_req` không kiểm tra `w_ex_mem_valid`, nên nếu ngắt xảy ra đúng lúc Tầng 3 đang chứa bong bóng NOP (`w_ex_mem_valid == 0`), `mepc` sẽ bị ghi đè bằng `RESET_VEC` (`0x00000000`).
   - **P0-6 (Vòng lặp tổ hợp lưỡng ổn giữa `hazard_unit` và `apb_bridge`)**: Tín hiệu `w_hz_mem_en` (`~o_trap_taken`) khóa cổng `i_bus_read`/`i_bus_wstrb` đi vào `apb_bridge`; khối này lại điều khiển tổ hợp `o_dmem_ready` (`w_apb_ready`), truyền ngược về `w_mem_busy` và `o_trap_taken` (`i_int_req & ~w_mem_busy`) trong `hazard_unit`, tạo thành vòng phản hồi tổ hợp không qua thanh ghi (đang bị che giấu trong `Makefile` bằng cờ `-Wno-UNOPTFLAT`).
3. **Tuyên Bố Sign-off Vật Lý so với Thực Tế Cấu Hình `config.json`**:
   - Mặc dù `PROJECT_PHASES_SUMMARY.md` tuyên bố "0 DRC, 0 LVS, Tape-out Ready", tệp `config.json` (dòng 36–41) lại đặt `"RUN_MAGIC_DRC": false`, `"RUN_KLAYOUT_DRC": false`, `"RUN_KLAYOUT_XOR": false`, và `"RUN_LVS": false`. Các bước kiểm tra DRC sign-off và đối sánh mạch LVS (Netgen) thực chất đã bị tắt trong cấu hình OpenLane.

## 02. Kiểm Kê Kho Mã Nguồn (Repository Inventory)

Toàn bộ các tệp trong kho mã nguồn đã được kiểm tra đệ quy. Kho lưu trữ không chứa thư mục `.git` hay kịch bản CI (`.github/`), nhưng có sẵn thư viện biên dịch QuestaSim 2021.2 (`sim/work/`), tệp dạng sóng (`vsim.wlf`) và nhật ký chạy mô phỏng (`transcript`).

| Danh mục | Tệp tin | Mục đích | Trạng thái |
|----------|---------|----------|------------|
| **Lõi CPU (Top & Defines)** | `rtl/core/core_top.v`<br>`rtl/defines/riscv_core_defines.vh` | Module đỉnh 3 tầng (`riscv_core_top`) tích hợp IF, ID/EX, MEM/WB, Hazard, Forwarding, CSR, SRAM 2KB và APB Master; định nghĩa hằng số/opcode toàn cục. | Đã hiện thực (RTL Phase 4); có lỗi P0 về đấu nối CSR/forwarding/SRAM; include guard trong `.vh` đóng sớm. |
| **Các tầng Pipeline & Thanh ghi** | `rtl/core/stage_if.v`<br>`rtl/core/pipe_reg_if_id.v`<br>`rtl/core/stage_id_ex.v`<br>`rtl/core/pipe_reg_ex_mem.v`<br>`rtl/core/stage_mem_wb.v`<br>`rtl/core/rvc_decompressor.v` | Tầng 1 (Prefetch FIFO 2 từ, căn chỉnh lệch từ, giải nén RV32C, Early JAL, dự đoán nhánh BTFN); thanh ghi IF/ID; Tầng 2 (Decode, RF, Fwd, ALU, Mul, SIMD, Branch comp); thanh ghi EX/MEM; Tầng 3 (Load/Store align, WB mux). | Đã hiện thực (đường ống 3 tầng). Lưu ý: `README.md` & `SPEC.md` vẫn tham chiếu tới các tệp 2 tầng cũ đã xóa (`stage_if_id.v`, `pipe_reg_id_ex.v`, `stage_ex.v`). |
| **Giải mã lệnh & Sinh số tức thời** | `rtl/core/instruction_decoder.v`<br>`rtl/core/imm_gen.v`<br>`rtl/core/branch_comparator.v` | Bộ giải mã tổ hợp RV32I/M/Zicsr/`smdot.i8` kèm khóa toán hạng ALU và cờ báo dùng `rs1`/`rs2`; bộ mở rộng dấu I/S/B/U/J; bộ so sánh 6 điều kiện rẽ nhánh. | Đã hiện thực; thiếu phát hiện lệnh bất hợp lệ (illegal instruction) và thiếu giải mã `EBREAK`. |
| **Tập thanh ghi (Register File)** | `rtl/core/register_file.v` | Tập thanh ghi 32×32-bit ghi đồng bộ, đọc bất đồng bộ (`x0` cứng bằng 0). | Đã hiện thực; cơ chế Write-Before-Read nội bộ nêu trong comment/README/SPEC đã bị gỡ bỏ khỏi RTL. |
| **ALU & Khối AI SIMD** | `rtl/core/alu.v`<br>`rtl/core/simd_mac_unit.v` | ALU 32-bit dùng chung bộ cộng/trừ 33-bit và sinh cờ (`Z, N, C, V`); khối tính tích vô hướng 4×INT8 có dấu trong 1 chu kỳ (`smdot.i8`). | Đã hiện thực và hoạt động đúng. |
| **Bộ nhân (Multiplier)** | `rtl/core/booth_multiplier_32b.v` | Bộ nhân dịch-cộng tuần tự 8 chu kỳ không dấu 32×4-bit kèm tiền/hậu xử lý dấu bù 2 cho `MUL`, `MULH`, `MULHSU`, `MULHU`. | Đã hiện thực (thực chất là dịch-cộng Radix-16 không dấu 4-bit/chu kỳ chứ không phải mã hóa Booth như tên module); có lỗi P0 khi gặp xung đột Load-Use. |
| **Khối CSR & Bẫy/Ngắt** | `rtl/core/csr.v` | Các thanh ghi CSR Machine-mode (`mstatus`, `mie`, `mtvec`, `mscratch`, `mepc`, `mcause`, `mtval`, `mip`), xử lý `ECALL`, `MRET`, ngắt ngoài/timer và lỗi bus APB. | Đã hiện thực nhưng có các lỗi P0 (lệch tầng đọc CSR, nối nhầm `rs2` vào `i_rs1_data`, mất lệnh Tầng 3 / hỏng `mepc` khi có IRQ, `mtval` không ghi được). |
| **Khối Hazard & Forwarding** | `rtl/core/hazard_unit.v`<br>`rtl/core/forwarding_unit.v` | Bộ điều khiển stall/flush đường ống 3 tầng và bộ phát hiện xung đột RAW / khóa liên động Load-Use. | Đã hiện thực nhưng có lỗi P0 (nhánh `FWD_MEM_WB` chết, chuyển tiếp sai cho `JAL`/`JALR`/`CSR`, vòng lặp tổ hợp với `apb_bridge`, thanh ghi `r_flush_id_ex` thừa). |
| **Bộ nhớ & Căn chỉnh dữ liệu** | `rtl/memory/sky130_sram_2kbyte_1rw1r_32x512_8.v`<br>`rtl/core/be_gen.v`<br>`rtl/core/st_align.v`<br>`rtl/core/load_align.v` | Mô hình hành vi của Macro OpenRAM SkyWater 130nm 2KB Dual-Port 1RW1R (chốt địa chỉ ở `posedge`, đọc/ghi mảng ở `negedge`); bộ sinh byte-enable; bộ dịch byte khi ghi; bộ trích xuất và mở rộng dấu khi đọc. | Đã hiện thực; `be_gen` và `st_align` đang bị khởi tạo lặp 2 lần (ở Tầng 2 trong `core_top.v` cho SRAM và ở Tầng 3 trong `stage_mem_wb.v` cho APB). |
| **Giao tiếp Bus** | `rtl/bus/apb_bridge.v` | Cầu nối AMBA APB Master (`S_IDLE`, `S_SETUP`, `S_ACCESS`) cho vùng MMIO `0x4000_0000`–`0x40FF_FFFF`. | Đã hiện thực; bị vòng lặp tổ hợp với `hazard_unit` khi `i_int_req=1`. |
| **Testbench & Kiểm chứng** | `tb/tb_bubble_sort.v`<br>`tb/tb_phase2_math_ai.v`<br>`tb/tb_phase3_hazards.v`<br>`tb/tb_rvc_decompressor.v`<br>`tb/tb_rvc_pipeline.v`<br>`tb/tb_ai_benchmark.v` | 6 testbench Verilog kiểm tra firmware Bubble Sort, kiểm thử đơn vị cho `booth_multiplier_32b` & `simd_mac_unit`, kiểm thử có hướng cho xung đột RAW/Load-Use/Branch, bộ giải nén RVC, đường ống RVC và benchmark AI 16 phần tử INT8. | Các bài kiểm thử có hướng hoạt động tốt; **0 bài kiểm thử** cho CSR, bẫy, ngắt, cầu APB, `LB`/`LH`/`SB`/`SH`, `LUI`/`AUIPC`/`JALR`, hoặc truy cập lệch địa chỉ. |
| **Phần mềm nhúng (Firmware)** | `firmware/Start.S`<br>`firmware/bublesoft.c`<br>`firmware/link.ld`<br>`firmware/firmware.elf`<br>`firmware/firmware_rvc.elf`<br>`firmware/firmware_aligned.elf`<br>`firmware/firmware.asm`<br>`firmware/firmware_rvc.asm`<br>`firmware/memfile.hex`<br>`firmware/memfile_rvc.hex`<br>`firmware/memfile_aligned.hex` | Mã khởi động Assembly, thuật toán Bubble Sort 10 phần tử bằng C, linker script 2KB, và các tệp thực thi RV32IC (`memfile.hex` và `memfile_rvc.hex` giống hệt nhau; `memfile_aligned.hex` chèn thêm lệnh 16-bit `c.nop` tại `0x6e` để căn lề đích vòng lặp trong về `0x70`). | Chạy đúng Bubble Sort; lệnh `csrw mscratch, t0` trong `Start.S` bị ghi sai thành `0` trên phần cứng do lỗi P0-2. |
| **Mô phỏng & Tệp tham khảo** | `sim/wave.do`<br>`sim/ibex_prefetch_buffer.sv`<br>`sim/ibex_fetch_fifo.sv`<br>`sim/work/*`<br>`transcript`<br>`vsim.wlf` | Kịch bản sóng QuestaSim (đã lỗi thời: trỏ tới phân cấp 2 tầng cũ `u_stage_if_id`, `u_stage_ex`, `u_hazard/r_state`), 2 tệp SystemVerilog tham khảo từ lõi lowRISC Ibex không được sử dụng, thư viện biên sẵn QuestaSim và log chạy trên `memfile_aligned.hex`. | `wave.do` bị lỗi đường dẫn tín hiệu so với RTL hiện tại; `ibex_*.sv` là tệp tham khảo dư thừa. |
| **Hệ thống Build & Vật lý** | `Makefile`<br>`config.json`<br>`riscv_core_top.sdc` | Makefile quản lý biên dịch/mô phỏng/lint (`-march=rv32ic_zicsr`), cấu hình OpenLane 2 (`CLOCK_PERIOD: 12.0`), và ràng buộc thời gian STA (`12.0 ns` = 83.33 MHz). | Hoạt động; `Makefile` đang tắt các cảnh báo Verilator quan trọng (`-Wno-UNOPTFLAT`, `-Wno-UNUSED`, `-Wno-UNDRIVEN`); `config.json` tắt kiểm tra DRC/LVS. |
| **Tài liệu (Documentation)** | `README.md`<br>`SPEC.md`<br>`OPTIMIZATION_PLAN.md`<br>`PHASE1_PLAN.md`<br>`PHASE2_PLAN.md`<br>`PHASE3_PLAN.md`<br>`PHASE4_PLAN.md`<br>`PROJECT_PHASES_SUMMARY.md` | Tổng quan dự án, đặc tả chi tiết từng module, và kế hoạch/báo cáo tổng kết qua 4 giai đoạn tối ưu hóa. | Mâu thuẫn nghiêm trọng giữa các tài liệu (`README.md` = Phase 0, `SPEC.md` = Phase 2, `PROJECT_PHASES_SUMMARY.md` = Phase 4). |

## 03. Đối Chiếu Tính Nhất Quán README / SPEC / RTL

Bảng dưới đây kiểm chứng từng tính năng được tuyên bố trong `README.md` và `SPEC.md` đối chiếu trực tiếp với mã RTL, testbench và firmware thực tế.

| Tính năng | Tuyên bố trong README/SPEC | Bằng chứng RTL | Bằng chứng Testbench (TB) | Bằng chứng Firmware | Trạng thái thực tế | Mức rủi ro |
|-----------|----------------------------|----------------|---------------------------|---------------------|--------------------|------------|
| **Độ sâu & Cấu trúc Đường ống** | `README.md` (dòng 15) & `SPEC.md` (dòng 68): Đường ống 2 tầng (`stage_if_id` $\rightarrow$ `pipe_reg_id_ex` $\rightarrow$ `stage_ex`). | `core_top.v` (dòng 233–460): **Đường ống 3 tầng** (`stage_if` $\rightarrow$ `pipe_reg_if_id` $\rightarrow$ `stage_id_ex` $\rightarrow$ `pipe_reg_ex_mem` $\rightarrow$ `stage_mem_wb`). | `tb_phase3_hazards.v` kiểm thử đường ống 3 tầng. `sim/wave.do` vẫn trỏ vào các module 2 tầng cũ đã xóa. | N/A | **LỆCH TÀI LIỆU** (RTL là 3 tầng; README/SPEC mô tả thiết kế 2 tầng cũ). | **P2** |
| **Độ đầy đủ tập lệnh RV32I** | `README.md` (dòng 14) & `SPEC.md` (dòng 63, 89): Hỗ trợ 100% RV32I Base Integer (40 lệnh). | `instruction_decoder.v` giải mã LUI, AUIPC, JAL, JALR, 6 lệnh Branch, 5 lệnh Load, 3 lệnh Store, 19 lệnh ALU, FENCE (như NOP), ECALL. **Không giải mã `EBREAK`** (bị xem như NOP). | Chỉ có `ADDI`, `ADD`, `SUB`, `LW`, `SW`, `BEQ`, `BNE`, `BGE`, `SLLI`, `JAL`, `JALR` (`ret`) được chạy trong TB. | `Start.S` & `bublesoft.c` dùng 14 lệnh. | **HỖ TRỢ MỘT PHẦN / CHƯA KIỂM CHỨNG ĐẦY ĐỦ** (Thiếu `EBREAK`; >50% lệnh RV32I chưa có test mô phỏng). | **P1** |
| **Tập lệnh nén RV32C (16-bit)** | Không được nhắc tới trong `README.md` hay `SPEC.md` (chỉ có trong `PHASE4_PLAN.md` & `Makefile` dòng 61). | `rvc_decompressor.v` & `stage_if.v` (dòng 100–125) hiện thực 27 lệnh RV32C + Prefetch FIFO 2 từ + bộ căn chỉnh lệnh vắt qua 2 từ nhớ. | `tb_rvc_decompressor.v` (31 unit test) & `tb_rvc_pipeline.v` (6 pipeline test). | Biên dịch với cờ `-march=rv32ic_zicsr`; `firmware.asm` dùng nhiều lệnh RVC. | **ĐÃ CÓ TRONG RTL, THIẾU TRONG README/SPEC** (Ngõ ra `o_illegal_instr` đang bị bỏ trống trong `stage_if.v` dòng 120). | **P1** |
| **Độ đầy đủ phần mở rộng RV32M** | `README.md` (dòng 14) & `SPEC.md` (dòng 64): Hỗ trợ RV32M (`MUL`, `MULH`, `MULHSU`, `MULHU`). | `instruction_decoder.v` (dòng 106–114) & `booth_multiplier_32b.v` hiện thực `MUL`, `MULH`, `MULHSU`, `MULHU`. **Không có `DIV`, `DIVU`, `REM`, `REMU`** (nhánh `default: o_alu_ctrl = ALU_ADD` khiến lệnh chia âm thầm chạy phép cộng `ADD`!). | `tb_phase2_math_ai.v` kiểm thử 8 trường hợp `MUL*`. Không có kiểm thử phép chia. | Không dùng trong `bublesoft.c`. | **CHỈ HỖ TRỢ `Zmmul`**; nguy hiểm hơn, các opcode `DIV`/`REM` (`funct7=1, funct3=4..7`) âm thầm thực thi phép cộng `ADD` thay vì tạo bẫy! | **P0** |
| **Kiến trúc & Độ trễ Bộ nhân** | `README.md` (dòng 18): Booth Radix-4 17 chu kỳ. `SPEC.md` (dòng 39, 1217): Bộ nhân tổ hợp 1 chu kỳ 33×33. | `booth_multiplier_32b.v` (dòng 60–108): **Bộ nhân tuần tự 8 chu kỳ** dịch-cộng không dấu 32×4-bit (`r_cnt` 0..7 ở `S_CALC`, 1 chu kỳ `S_DONE` = tổng 9 chu kỳ, stall 8 chu kỳ). | `tb_phase2_math_ai.v` chờ tín hiệu `while (!test_mul_ready)`. | N/A | **LỆCH TÀI LIỆU + LỖI P0**: Không phải 17 chu kỳ cũng không phải 1 chu kỳ; thực tế là dịch-cộng 8 chu kỳ (tổng 9 chu kỳ), và bị sai kết quả khi gặp xung đột Load-Use (`stage_id_ex.v` dòng 292). | **P0** |
| **Độ đầy đủ Zicsr & Thanh ghi CSR** | `README.md` (dòng 14) & `SPEC.md` (dòng 65, 1827): Đầy đủ Machine-Mode CSR (`CSRRW/S/C`, `CSRRWI/SI/CI`, 8 thanh ghi CSR). | `csr.v` hiện thực 8 địa chỉ CSR (`0x300..0x344`), nhưng `core_top.v` (dòng 333, 395, 445, 517) chốt `o_csr_data` sớm 1 tầng và nối nhầm `w_ex_mem_store_data` (`rs2`) vào `i_rs1_data`! Ngoài ra `mtval` (`0x343`) không có nhánh ghi trong `csr.v` (dòng 143). | **0 bài kiểm thử CSR** trong toàn bộ `tb/*.v`. | `Start.S` gọi `csrw mscratch, t0` (bị ghi `0`!) và `csrw mtvec, t0`. | **LỖI NGHIÊM TRỌNG TRONG RTL (P0)** — Đọc CSR luôn trả về `0` (hoặc dữ liệu cũ) vào `rd`, còn ghi CSR bằng thanh ghi lại lấy giá trị của `rs2` (`csr_addr[4:0]`) thay vì `rs1`! | **P0** |
| **Lệnh hệ thống ECALL / MRET / WFI** | `README.md` (dòng 14, 24) & `SPEC.md` (dòng 65): Hỗ trợ `ECALL`, `MRET`, `WFI`. | `instruction_decoder.v` (dòng 238–244) giải mã cả 3 lệnh. `ECALL` và `MRET` nối vào `csr.v` ở Tầng 3; **`o_sleep_req` (`WFI`) là dây cụt** (`w_ex_mem_sleep_req` trong `core_top.v` dòng 425). | **0 bài kiểm thử** cho `ECALL`, `MRET`, `WFI` trong `tb/`. | Không dùng trong `bublesoft.c`. | **CHƯA KIỂM CHỨNG / MỘT PHẦN** (`WFI` chạy như lệnh NOP, ngõ ra `w_ex_mem_sleep_req` bỏ trống). | **P1** |
| **Xử lý Ngắt & Bẫy Ngoại lệ** | `README.md` (dòng 24) & `SPEC.md` (dòng 103, 1920): Xử lý `i_ext_irq`, `i_timer_irq`, `ECALL`, `Bus Error` với `mepc`, `mcause`, `mtval`. | `csr.v` (dòng 99–141) & `hazard_unit.v` (dòng 71, 127): Khi có IRQ, `o_wb_en` bị kéo về `0` (hủy ghi trả của lệnh ở Tầng 3), nhưng `mepc` lại lưu `w_ex_mem_pc_plus_4` (nhảy qua luôn lệnh ở Tầng 3!). Ngoài ra `o_int_req` không kiểm tra `i_valid`. | **0 bài kiểm thử ngắt hoặc ngoại lệ** trong `tb/` (`i_ext_irq` và `i_timer_irq` đều nối cứng `1'b0` trong cả 6 TB). | `default_trap_handler` trong `Start.S` chỉ là vòng lặp vô tận (`j default_trap_handler`), chưa từng được kích hoạt. | **LỖI TRONG RTL (P0) & CHƯA KIỂM THỬ** — Khi nhận ngắt bất đồng bộ sẽ làm mất lệnh ở Tầng 3 hoặc ghi đè `mepc` bằng `0x0` nếu Tầng 3 đang là bong bóng. | **P0** |
| **Lệnh bất hợp lệ & Truy cập lệch địa chỉ** | `riscv_core_defines.vh` (dòng 119–123) định nghĩa `EXC_INST_ADDR_MISALIGNED`, `EXC_ILLEGAL_INST`, `EXC_LOAD/STORE_ADDR_MISALIGNED`. Comment trong `Start.S` (dòng 44) nhắc tới `Illegal Instr`. | Cả `instruction_decoder.v` lẫn `csr.v` đều không hiện thực ngoại lệ lệnh bất hợp lệ hay lệch địa chỉ. `rvc_decompressor.v` có sinh `o_illegal_instr` nhưng bị bỏ trống (`w_illegal_rvc` trong `stage_if.v` dòng 115). | Chỉ kiểm thử đơn vị ở cổng `rvc_decompressor` (`tb_rvc_decompressor.v` dòng 57). | N/A | **KHÔNG HỖ TRỢ** — Lệnh bất hợp lệ âm thầm chạy như `NOP` (hoặc `ADD` đối với `DIV`/`REM`). | **P1** |
| **Căn chỉnh Load/Store & Byte Enable** | `README.md` (dòng 48–50) & `SPEC.md` (dòng 99): Hỗ trợ đọc/ghi Byte, Halfword, Word và tạo mặt nạ byte. | `be_gen.v`, `st_align.v`, `load_align.v` căn chỉnh đúng cho `LB/LBU/SB`, `LH/LHU/SH` căn lề chẵn (`addr[0]==0`), và `LW/SW` căn lề 4 byte (`addr[1:0]==00`). Truy cập `LH/SH` tại `addr[0]==1` hoặc `LW/SW` tại `addr[1:0]!=00` không tách chu kỳ cũng không báo lỗi. | Chỉ có `LW` và `SW` căn lề 4 byte được kiểm thử trong `tb/`. **Các lệnh `LB`, `LH`, `LBU`, `LHU`, `SB`, `SH` chưa từng được chạy mô phỏng.** | Firmware chỉ dùng `lw` và `sw`. | **MỚI KIỂM CHỨNG MỘT PHẦN** (Logic căn chỉnh byte/halfword tự nhiên viết đúng, nhưng 0% được kiểm thử mô phỏng; không hỗ trợ truy cập dữ liệu vắt qua 2 từ nhớ). | **P1** |
| **Register File & Write-Before-Read** | `README.md` (dòng 19) & `SPEC.md` (dòng 817): RF 32×32 có tích hợp Write-Before-Read nội bộ. | `register_file.v` (dòng 51–52): Đọc bất đồng bộ thuần túy (`r_regs[i_rs1_addr]`), **không có mux Write-Before-Read nội bộ** (đã bỏ khi thêm `forwarding_unit.v` ở Phase 3, dù comment ở dòng 47 vẫn còn). | Đã kiểm thử qua `tb_phase3_hazards.v`. | Được dùng trong mọi firmware. | **LỆCH TÀI LIỆU** (Được thay bằng `forwarding_unit.v` từ Tầng 3, ngoại trừ lỗi P0-4 khi chuyển tiếp kết quả `JAL`/`JALR`/`CSR`). | **P0** |
| **Giải quyết Nhánh & Nhảy (Branch/Jump)** | `SPEC.md` (dòng 94–95): Early JAL 0 chu kỳ tại IF; dự đoán nhánh tĩnh BTFN với hình phạt đoán sai 1 chu kỳ. | `stage_if.v` (dòng 53–64, 129–146) & `hazard_unit.v` (dòng 93–104): Early JAL tốn 0 chu kỳ; khôi phục đoán sai BTFN và `JALR` **được chốt qua thanh ghi `r_redirect_target` (phạt `2 chu kỳ`)**. | Đã kiểm thử trong `tb_phase3_hazards.v` và `tb_bubble_sort.v`. | Dùng trong `Start.S` & `bublesoft.c`. | **LỆCH TÀI LIỆU** (`SPEC.md` ghi phạt 1 chu kỳ; RTL Phase 3/4 thực tế phạt 2 chu kỳ cho BRMP/JALR, cộng thêm +1 chu kỳ nếu đích nhảy là lệnh 32-bit nằm ở địa chỉ nửa từ lẻ). | **P2** |
| **ALU cộng 33-bit dùng chung & Power Gating** | `README.md` (dòng 17, 20) & `SPEC.md` (dòng 105, 1184): Bộ cộng/trừ 33-bit dùng chung; khóa toán hạng động qua `o_alu_enable`. | `alu.v` (dòng 29) dùng một bộ cộng 33-bit duy nhất `w_sum_res`. `stage_id_ex.v` (dòng 260–262) ép `w_gated_src_a/b` về `0` khi `~(w_alu_enable & i_valid)`. | Đã kiểm thử một phần các phép toán ALU. | Dùng trong firmware. | **KHỚP RTL** (Lưu ý: đây là kỹ thuật **khóa toán hạng đầu vào / operand isolation** để giảm công suất chuyển mạch, không phải ngắt nguồn cell hay clock gating). | **P3** |
| **Tích hợp SRAM 2KB Dual-Port Sky130** | `README.md` (dòng 22) & `SPEC.md` (dòng 98): Port 0 cho Data RW, Port 1 cho Instruction Fetch. | `core_top.v` (dòng 155–201): Port 0 được kích hoạt ngay từ Tầng 2 (`ID/EX`) để đọc/ghi 1 chu kỳ; Port 1 được điều khiển từ Tầng 1 (`IF`). Giải mã địa chỉ bỏ qua `addr[31:11]` (trừ vùng `0x40xx_xxxx`). | Được kiểm thử trong mọi TB. | Vừa vặn trong 2KB (chỉ dùng ~212 byte code+data + stack). | **ĐẠT MỘT PHẦN** — Chạy đúng cho truy cập thông thường, nhưng thiếu kiểm tra giới hạn `addr[31:11] == 0` (bị lặp bóng/alias khắp 4GB) và thiếu kiểm tra đụng độ khi Port 0 ghi trùng địa chỉ Port 1 đang đọc. | **P1** |
| **Cầu nối APB3/APB4 Master** | `README.md` (dòng 23) & `SPEC.md` (dòng 100–101): APB3/APB4 Master ánh xạ vùng `0x4000_0000`–`0x40FF_FFFF`, hỗ trợ wait-state và `PSLVERR`. | `apb_bridge.v` hiện thực `S_IDLE`, `S_SETUP`, `S_ACCESS` với `o_apb_pstrb` (APB4) và `i_apb_pslverr`. Thiếu `PPROT` (APB4). Có **vòng lặp tổ hợp** với `hazard_unit` (`w_hz_mem_en` $\leftrightarrow$ `o_dmem_ready`). | **0 bài kiểm thử APB** trong `tb/` (`i_apb_pready=1`, `i_apb_pslverr=0` bị gán cứng trong cả 6 TB). | Không dùng trong firmware. | **CHƯA KIỂM THỬ & CÓ VÒNG LẶP TỔ HỢP P0** (`apb_bridge.v` dòng 80 $\leftrightarrow$ `hazard_unit.v` dòng 71, 126). | **P0** |
| **Kết quả Benchmark Bubble Sort** | `README.md` (dòng 148–153): 503 chu kỳ, 334 lệnh, 72 nhánh, CPI = 1.506. `SPEC.md` (dòng 138): 467 chu kỳ, CPI = 1.398. | Mô phỏng chính xác trên RTL hiện tại: `memfile.hex` chạy hết **496 chu kỳ** (334 lệnh, 72 nhánh nhảy, 38 đoán sai, **CPI = 1.485**); `memfile_aligned.hex` (`transcript`) chạy hết **469 chu kỳ** (343 lệnh, **CPI = 1.367**). | `tb_bubble_sort.v` & `transcript`. | `bublesoft.c` | **SỐ LIỆU TRONG README & SPEC ĐÃ CŨ** (RTL hiện tại đạt 496 chu kỳ trên `memfile.hex` và 469 chu kỳ trên `memfile_aligned.hex`). | **P3** |

## 04. Kiến Trúc Thực Tế (Actual Architecture)

### Tái Cấu Trúc Vi Kiến Trúc Từ Mã Nguồn RTL

Bỏ qua các chú thích và tài liệu cũ, bộ vi xử lý thực tế đang được hiện thực hóa trong thư mục `rtl/` là một **Lõi Vi Xử Lý RISC-V Đường Ống 3 Tầng Thực Thi Tuần Tự (`IF` $\rightarrow$ `ID/EX` $\rightarrow$ `MEM/WB`)** tích hợp hàng đợi nạp lệnh trước 2 từ 32-bit, bộ giải nén tổ hợp RV32C 0 chu kỳ, dự đoán rẽ nhánh tĩnh BTFN, mạng chuyển tiếp dữ liệu ALU/MUL/SIMD từ Tầng 3 về Tầng 2, bộ nhân tuần tự 8 chu kỳ, và khối tính tích vô hướng SIMD 4×INT8 trong 1 chu kỳ.

```
====================================================================================================
                  SƠ ĐỒ ĐƯỜNG ỐNG 3 TẦNG THỰC TẾ ĐƯỢC HIỆN THỰC TRONG RTL
====================================================================================================

  [Macro SRAM Dual-Port 2KB Sky130 (1RW1R: Port 1 = IMEM RO, Port 0 = DMEM RW, Xuất dữ liệu sườn âm)]
         | Port 1 (dout1)                                             ^ Port 0 (csb0, web0,
         v                                                            |  addr0, din0, wmask0)
+----------------------------------+                         +-------------------------------------+
| TẦNG 1: IF (stage_if.v)          |                         | TẦNG 2: ID/EX (stage_id_ex.v)       |
| - 2x32b Prefetch FIFO            |                         | - instruction_decoder & imm_gen     |
| - Căn chỉnh lệnh lệch từ(r_pc[1])|                         | - register_file (Đọc bất đồng bộ)   |
| - rvc_decompressor (16b -> 32b)  |   +-----------------+   | - MUX Forwarding (A, B, Store)      |
| - Bộ cộng Early JAL (nhảy 0-cyc) |-->| pipe_reg_if_id  |-->| - ALU 33b dùng chung (Khóa toán hạng)|
| - Dự đoán nhánh tĩnh BTFN        |   | (Stall / Flush) |   | - booth_multiplier_32b (FSM 8 chu kỳ)|
| - Thanh ghi chốt Redirect        |   +-----------------+   | - simd_mac_unit (1-cyc 4xINT8 MAC)  |
|   (r_redirect_target, 2-cyc BRMP)|                         | - branch_comparator & Bộ cộng Recov |
+----------------------------------+                         | - Phát lệnh Đọc/Ghi SRAM Port 0!    |
         ^                                                   +-------------------------------------+
         | Chuyển hướng PC (2-cyc BRMP/JALR,                          |
         |                  1-cyc Trap/MRET)                          v
         |                                                   +-----------------+
         |                                                   | pipe_reg_ex_mem |
         |                                                   | (Stall / Flush) |
         |                                                   +-----------------+
         |                                                            |
         |   +--------------------------------------------------------+
         |   |
         |   v
+--------------------------------------------------------------------------------------------------+
| TẦNG 3: MEM/WB (stage_mem_wb.v) + CSR_Unit (csr.v) + apb_bridge (apb_bridge.v)                   |
| - Nhận dữ liệu đọc dout0 từ SRAM Port 0 (đã phát từ Tầng 2) HOẶC khởi chạy giao dịch APB MMIO    |
| - load_align (Trích xuất & mở rộng dấu Byte/Halfword/Word)                                       |
| - MUX Ghi trả cuối cùng (00: EX_Result, 01: Load_Data, 10: PC+4, 11: CSR_Data [LỖI: trễ 1 tầng]) |
| - Ghi vào register_file ở sườn lên i_clk; CSR_Unit xử lý ECALL, MRET, IRQs, Bus Error            |
+--------------------------------------------------------------------------------------------------+
```

### Phân Loại Kiến Trúc: Gọi Là "Đường Ống 2 Tầng Đàn Hồi / Tách Rời (2-Stage Decoupled/Elastic Pipeline)" Có Chính Xác Không?

**Không — thuật ngữ này không còn phản ánh đúng mã nguồn RTL hiện tại vì hai lý do kỹ thuật:**
1. **Đây là đường ống 3 tầng, không phải 2 tầng**: Mạch có hai vách ngăn thanh ghi đường ống đồng bộ tách biệt rõ rệt 3 tầng (`stage_if` $\rightarrow$ `pipe_reg_if_id` $\rightarrow$ `stage_id_ex` $\rightarrow$ `pipe_reg_ex_mem` $\rightarrow$ `stage_mem_wb`), cộng thêm một hàng đợi Prefetch FIFO 2 từ ở `stage_if`.
2. **Đây là Đường Ống Khóa Liên Động (Interlocked Pipeline) Kèm Hàng Đợi Nạp Trước (Prefetch FIFO), KHÔNG PHẢI "Đường Ống Đàn Hồi / Tách Rời (Elastic/Decoupled Pipeline)"**:
   - Thuật ngữ kỹ thuật chính xác: **Đường Ống 3 Tầng Thực Thi Tuần Tự Có Khóa Liên Động (3-Stage In-Order Interlocked Pipeline), Tích Hợp Bộ Đệm Nạp Lệnh Trước 2 Từ (2-Word Instruction Prefetch FIFO), Dự Đoán Nhánh Tĩnh BTFN và Các Khối Thực Thi Đa Chu Kỳ (Bộ Nhân Lặp & Cầu APB)**.

## 05. Phân Tích Đường Ống và Xung Đột (Pipeline & Hazard Analysis)

### Ma Trận Xung Đột Đầy Đủ (Hazard Matrix)

| Lệnh sản sinh (Tầng 3: `EX/MEM`) | Lệnh tiêu thụ (Tầng 2: `ID/EX`) | Loại xung đột | Hành động bắt buộc | Hiện thực RTL hiện tại | Đúng hay Sai? |
|----------------------------------|---------------------------------|---------------|--------------------|------------------------|---------------|
| **ALU / SIMD (`ADD`, `smdot.i8`...)** | ALU / Branch / JALR / Store (`rs1`, `rs2`) | Xung đột dữ liệu RAW | Chuyển tiếp kết quả ALU/SIMD từ Tầng 3 (`w_ex_mem_result`) về Tầng 2 (0 chu kỳ stall). | `forwarding_unit.v` xuất `FWD_EX_MEM (2'b10)` $\rightarrow$ `stage_id_ex.v` chọn `i_fwd_ex_mem_data` (`w_ex_mem_result`). | **ĐÚNG** |
| **Bộ nhân (`MUL`, `MULH*`)** | ALU / Branch / JALR / Store (`rs1`, `rs2`) | Đa chu kỳ + Xung đột RAW | Stall Tầng 1 & 2 trong 8 chu kỳ (`S_CALC` 0..7) tới khi `o_ready=1` ở `S_DONE`, sau đó chuyển tiếp `w_ex_mem_result` từ Tầng 3 ở chu kỳ kế. | `hazard_unit.v` stall theo `i_mul_busy` (8 chu kỳ) và flush `pipe_reg_ex_mem`; ở chu kỳ 9 kết quả `MUL` chốt sang `pipe_reg_ex_mem` và chuyển tiếp qua `FWD_EX_MEM`. | **ĐÚNG** |
| **Lệnh Load (`LW`, `LH`, `LB`, `LHU`, `LBU`)** | ALU / Branch / JALR / Store / SIMD (`rs1`, `rs2`) | Xung đột RAW Load-to-Use | Stall Tầng 1 & 2 đúng 1 chu kỳ, flush `pipe_reg_ex_mem`, đợi Load ghi vào RF, rồi đọc từ RF ở chu kỳ tiếp theo. | `forwarding_unit.v` bật `o_stall_load_use = 1` trong 1 chu kỳ; `register_file` ghi `o_wb_data` tại sườn lên; chu kỳ kế đọc RF (`FWD_NONE`). | **ĐÚNG** |
| **Lệnh Load (`LW`, `LH`, `LB`, `LHU`, `LBU`)** | Bộ nhân (`MUL`, `MULH*`) | Load-to-Use + Khởi chạy Bộ nhân | Stall Tầng 1 & 2 trong 1 chu kỳ VÀ phải ngắt `u_multiplier.i_mul_valid` trong chu kỳ stall đó! | `stage_id_ex.v` (dòng 292) nối `i_mul_valid = w_mul_valid & i_valid` (KHÔNG khóa bởi `~w_stall_load_use`!). Bộ nhân chạy ngay trong chu kỳ stall và chốt nhầm `w_ex_mem_result` (địa chỉ của lệnh Load!). | **SAI (Lỗi P0-3)** |
| **Lệnh Nhảy liên kết (`JAL`, `JALR`)** | Mọi lệnh đọc `rd` (`ra`) ngay ở chu kỳ liền kề | Xung đột RAW trên `PC+4` | Chuyển tiếp `w_ex_mem_pc_plus_4` (hoặc `w_wb_data`) từ Tầng 3 về Tầng 2. | `forwarding_unit.v` bật `FWD_EX_MEM`, chuyển tiếp `w_ex_mem_result` (`0` với `JAL`, địa chỉ đích với `JALR`) thay vì `w_ex_mem_pc_plus_4`! | **SAI (Lỗi P0-4)** |
| **Lệnh CSR (`CSRRW/S/C*`)** | Mọi lệnh đọc `rd` | Đọc CSR + Xung đột RAW | Đọc CSR đúng tầng và chuyển tiếp dữ liệu CSR (`w_csr_data`). | `core_top.v` (dòng 333, 395) chốt `w_csr_data` ở Tầng 2 trước khi `CSR_Unit` nhận được địa chỉ `w_ex_mem_csr_addr` ở Tầng 3, đồng thời chuyển tiếp nhầm `w_ex_mem_result` (`0`). | **SAI (Lỗi P0-1 & P0-4)** |
| **Lệnh ALU / Load / Mul ($N-1$ hoặc $N-2$)** | Lệnh ghi CSR (`CSRRW`, `CSRRS`, `CSRRC`) | Xung đột RAW trên `rs1` ghi vào CSR | Truyền `rs1` đã chuyển tiếp (`w_fwd_rs1_data`) từ Tầng 2 sang `CSR_Unit.i_rs1_data` ở Tầng 3. | `core_top.v` (dòng 517) nối `u_csr.i_rs1_data` vào `w_ex_mem_store_data` (**vốn là `w_fwd_store_data` = `rs2`, KHÔNG PHẢI `rs1`!**). | **SAI (Lỗi P0-2)** |
| **Rẽ nhánh đoán sai hoặc `JALR` ở Tầng 2** | Các lệnh trẻ hơn ở Tầng 1 (`IF` & `pipe_reg_if_id`) | Xung đột điều khiển (Control Hazard) | Flush `pipe_reg_if_id` và Prefetch FIFO của `stage_if`, chuyển hướng PC về địa chỉ khôi phục/JALR. | Chuyển hướng qua thanh ghi chốt 2 chu kỳ (`r_redirect_valid` trong `stage_if.v` dòng 56, `r_redirect_pipe_flush` trong `hazard_unit.v` dòng 95). | **ĐÚNG** (Phạt 2 chu kỳ; +1 chu kỳ nếu đích là lệnh 32-bit lệch nửa từ). |
| **Ngắt bất đồng bộ (`i_ext_irq`, `i_timer_irq`)** | Lệnh đang nằm ở Tầng 3 (`EX/MEM`) | Xung đột Bẫy / Commit | Hoặc cho phép lệnh Tầng 3 hoàn tất ghi trả (`o_wb_en=1`) và lưu `mepc = PC_stage2`, HOẶC hủy Tầng 3 (`o_wb_en=0`, nếu chưa ghi SRAM) và lưu `mepc = PC_stage3`. | `hazard_unit.v` (dòng 127) ép `o_wb_en = 0` (hủy ghi trả Tầng 3), nhưng `csr.v` (dòng 129) lại lưu `mepc = w_ex_mem_pc_plus_4` (bỏ qua lệnh Tầng 3!). Đồng thời không kiểm tra `w_ex_mem_valid == 0`. | **SAI (Lỗi P0-5)** |
| **Truy cập APB MMIO ở Tầng 3 (`EX/MEM`)** | Yêu cầu ngắt đang chờ trong `CSR_Unit` | Tương tác Stall Bus và Cấp phép Ngắt | Trì hoãn ngắt (`~w_mem_busy`) mà không tạo vòng lặp tổ hợp trên `w_hz_mem_en`. | `w_hz_mem_en` (`~o_trap_taken`) khóa ngõ vào yêu cầu của `apb_bridge`, làm thay đổi tổ hợp `o_dmem_ready` $\rightarrow$ `w_mem_busy` $\rightarrow$ `o_trap_taken` $\rightarrow$ `w_hz_mem_en`. | **SAI (Vòng lặp tổ hợp P0-6)** |

## 06. Đánh Giá Tuân Thủ Tập Lệnh (ISA Compliance)

Toàn bộ 40 lệnh RV32I, 8 lệnh RV32M, 27 lệnh RV32C, 6 lệnh Zicsr và 4 lệnh System đã được kiểm toán chi tiết. Kết quả:
- **Hỗ trợ đầy đủ & Đã kiểm chứng (Supported & Verified)**: `AUIPC`, `BNE`, `BGE`, `LW`, `SW`, `ADDI`, `SLLI`, `ADD`, `smdot.i8`, cùng 8 lệnh RVC trong đường ống.
- **Lỗi nặng (Incorrect / Broken - P0)**: `DIV`/`DIVU`/`REM`/`REMU` (chạy thành `ADD`), `CSRRW`/`CSRRS`/`CSRRC` (đọc ra `0`, ghi nhầm `rs2`), `CSRRWI`/`CSRRSI`/`CSRRCI` (đọc ra `0`), `JAL`/`JALR` (forwarding sai ra `0` nếu lệnh đầu tại đích đọc `rd`), `MUL*` (sai khi gặp xung đột Load-Use).
- **Thiếu kiểm chứng (Not Verified - 0% TB coverage)**: `LUI`, `BEQ`, `BLT`, `BLTU`, `BGEU`, `LB`, `LH`, `LBU`, `LHU`, `SB`, `SH`, `SLTI`, `SLTIU`, `XORI`, `ORI`, `ANDI`, `SRLI`, `SRAI`, `SUB`, `SLL`, `SLT`, `SLTU`, `XOR`, `SRL`, `SRA`, `OR`, `AND`, `ECALL`, `MRET`.
- **Chạy sai chuẩn (Treated as NOP)**: `EBREAK`, `c.ebreak`, các opcode bất hợp lệ.

## 07. Phân Tích CSR / Bẫy (Trap) / Ngắt (Interrupt)

- **Bản đồ 8 thanh ghi CSR**: `mstatus (0x300)`, `mie (0x304)`, `mtvec (0x305)`, `mscratch (0x340)`, `mepc (0x341)`, `mcause (0x342)`, `mtval (0x343)`, `mip (0x344)`.
- **4 Lỗi cốt lõi**:
  1. `w_csr_data` bị chốt sớm 1 tầng trong `core_top.v` khiến đọc CSR luôn trả về `0`.
  2. `u_csr.i_rs1_data` bị nối nhầm vào `w_ex_mem_store_data` (`rs2`), làm lệnh `csrw mscratch, t0` ghi `0`.
  3. Khi có ngắt bất đồng bộ, `o_wb_en = 0` hủy ghi trả của lệnh Tầng 3 nhưng `mepc` lại lưu `PC+4`, làm mất vĩnh viễn lệnh ở Tầng 3; nếu Tầng 3 là bong bóng thì `mepc` bị gán `0x0000_0000`.
  4. `mtval` bị thiếu khỏi nhánh ghi; `mtvec` nhảy trực tiếp mà không che 2 bit chế độ `mtvec[1:0]`.

## 08. Hệ Thống Bộ Nhớ (Memory System)

- **SRAM 2 KB Dual-Port 1RW1R**: Macro OpenRAM Sky130 chốt địa chỉ sườn lên và xuất dữ liệu sườn âm. Lệnh đọc/ghi SRAM Port 0 được phát ngay từ Tầng 2 (`ID/EX`), giúp lệnh Store hoàn tất trong 1 chu kỳ và lệnh Load có dữ liệu ở Tầng 3 với 0 chu kỳ stall.
- **Lặp bóng bộ nhớ (Memory Aliasing)**: Do giải mã chỉ xét `addr[31:24] == 8'h40`, toàn bộ không gian 4 GB còn lại đều bị lấy modulo `addr[10:2]` trỏ vào 2 KB SRAM! Trỏ nhầm địa chỉ `0x0000_0800` (đỉnh kernel stack) sẽ ghi đè vào `0x0000_0000` (`_start` trong `.text`).
- **Phân bổ bộ nhớ từ `firmware.elf`**: `.text` chiếm 168 B (8.2%), `.data` chiếm 40 B (2.0%), stack cấp phát 16 B. Tổng tĩnh 224 B (10.9%), rất an toàn trong 2 KB; tuy nhiên dòng `.data 0x000000e0` trong `link.ld` đang khóa trần mã lệnh ở mức $\le 224	ext{ bytes}$.

## 09. Phân Tích Giao Thức APB (APB Analysis)

- **`apb_bridge.v`**: Hiện thực FSM 3 trạng thái (`S_IDLE`, `S_SETUP`, `S_ACCESS`) với ngõ ra chốt D-FF chống nhiễu, hỗ trợ wait-state và `PSLVERR` (tạo bẫy `mcause = 5/7`, `mepc = PC`, `mtval = addr`).
- **Khiếm khuyết**:
  1. Vòng lặp tổ hợp với `hazard_unit.v` khi có ngắt chờ (P0-6, bị che bởi `-Wno-UNOPTFLAT`).
  2. Chỉ có 1 đường `PSEL` duy nhất, chưa có bộ giải mã nhiều slave ngoại vi.
  3. Không có bộ đếm timeout nếu slave treo cứng `PREADY=0`.
  4. 0% kiểm thử mô phỏng trong testbench.

## 10. Đánh Giá Chất Lượng RTL (RTL Quality)

- **Vòng lặp tổ hợp**: Giữa `hazard_unit` và `apb_bridge` qua `w_hz_mem_en` và `o_dmem_ready`.
- **Logic chết**: Nhánh `FWD_MEM_WB` trong `forwarding_unit.v`; thanh ghi `r_flush_id_ex` trong `hazard_unit.v`; khởi tạo lặp 2 lần `be_gen`/`st_align`; `w_illegal_rvc` và `w_ex_mem_sleep_req` bị bỏ trống.
- **Không chuẩn tổng hợp**: Dùng toán tử 4 trạng thái `===` trong `stage_if.v`; `register_file.v` dùng khối `initial` và không có reset phần cứng `i_rst_n`.
- **Lỗi Header**: Include guard trong `riscv_core_defines.vh` đóng quá sớm ở dòng 20.

## 11. Phân Tích Hiệu Năng (Performance Analysis)

- **Số liệu tái hiện thực tế**:
  - `firmware/memfile.hex` (mặc định): **496 chu kỳ**, 334 lệnh, **CPI = 1.485** (khớp chính xác số liệu Phase 4 trong `PROJECT_PHASES_SUMMARY.md`).
  - `firmware/memfile_aligned.hex` (`transcript`): **469 chu kỳ**, 343 lệnh, **CPI = 1.367** (nhờ chèn `c.nop` tại `0x6e` giúp căn lề 4-byte cho đích vòng lặp trong, loại bỏ hoàn toàn 36 chu kỳ stall nạp lệch từ).
- **Phân rã CPI trên `memfile.hex` (496 chu kỳ)**:
  - Lệnh cơ sở (1.0 CPI): 334 chu kỳ.
  - Phạt đoán sai nhánh (2 cyc × 38 lần): +76 chu kỳ (+0.228 CPI).
  - Stall Load-to-Use (1 cyc × 45 lần): +45 chu kỳ (+0.135 CPI).
  - Stall nạp đích nhánh 32-bit lệch nửa từ (1 cyc × 36 lần): +36 chu kỳ (+0.108 CPI).
  - Phạt `ret` (`JALR`) (2 cyc × 2 lần): +4 chu kỳ (+0.012 CPI).
  - Nạp đầy sau reset: +1 chu kỳ.
- **Khuyến nghị tối ưu 0 chi phí phần cứng**: Thêm `-falign-loops=4 -falign-functions=4` vào `Makefile` (giảm ngay 36 chu kỳ, CPI $ightarrow 1.367$) và tái lập lịch lệnh `addi` xen vào giữa `lw` và `bge` trong C/ASM (giảm 45 chu kỳ, CPI $ightarrow 1.23$).

## 12. Đánh Giá Độ Trưởng Thành Kiểm Chứng (Verification Maturity)

- **Điểm xếp hạng: Cấp độ 1 (Level 1 — Chỉ Có Kiểm Thử Có Hướng Cơ Bản)**.
- Có 6 testbench kiểm thử Bubble Sort, RVC, ALU/Load-Use cơ bản và SIMD `smdot.i8`.
- **Khoảng trống 0%**: Hoàn toàn chưa có kiểm thử cho CSR, Bẫy, Ngắt, Cầu APB, đọc/ghi Byte/Halfword và bộ kiểm thử chuẩn `riscv-tests`. 0 assertion SVA trong mã nguồn.

## 13. Kiến Trúc Kiểm Chứng Đề Xuất (Recommended Verification Architecture)

Mô hình 3 tầng:
1. **Tầng 1**: VIP giao thức APB4 Slave (kiểm tra wait-state, `PSTRB`, `PSLVERR`) + Testbench bơm ngắt/bẫy ngẫu nhiên.
2. **Tầng 2**: Bộ kiểm thử chuẩn quốc tế `riscv-tests` (`rv32ui`, `rv32um` [Zmmul], `rv32uc`, `rv32mi`).
3. **Tầng 3**: Module giám sát RVFI không xâm lấn (`rvfi_monitor.sv` gắn qua `bind`) đối sánh từng lệnh (lockstep) với mô hình tham chiếu ISS C++/Python hoặc Spike.

## 14. Kiến Trúc MCU/SoC (MCU/SoC Architecture)

- **Đánh giá**: Mới là lõi CPU + 2 KB SRAM + cổng APB Master thô.
- **Phân loại ngoại vi**:
  - **Bắt buộc phải có (P0 cho Silicon)**: Bootloader ROM / SPI Slave Loader vào SRAM (để nạp mã sau reset vì SRAM 2 KB là bộ nhớ khả biến); Bộ giải mã APB Interconnect; Machine Timer (`mtime`/`mtimecmp`); UART (in log/nạp firmware); GPIO (16 chân).
  - **Nên có**: SPI Master (đọc Flash ngoài); Watchdog Timer; Mạch ngắt xung nhịp khi ngủ `WFI`.
  - **Chưa cần**: PLIC/DMA/RTC/Crypto phần cứng.

## 15. Đánh Giá Tuyên Bố Tăng Tốc AI (AI Accelerator Assessment)

- **Thực tế**: Không có bộ tăng tốc AI độc lập hay NPU.
- **Thực tế trong RTL**: Lõi tích hợp một lệnh tùy biến SIMD 4×INT8 duy nhất (`smdot.i8 rd, rs1, rs2`) qua `simd_mac_unit.v` chạy trong 1 chu kỳ (tăng tốc $14.55	imes$ trên kernel tích vô hướng).
- **Khuyến nghị**: Giữ vững và hoàn thiện hướng `smdot.i8` này (thêm thanh ghi tích lũy nội bộ `smmac.i8`), không nên phức tạp hóa bằng bộ tăng tốc APB hay DMA vì dung lượng SRAM chỉ có 2 KB.

## 16. Mức Độ Sẵn Sàng Thiết Kế Vật Lý ASIC Trên Sky130

- **Hiện trạng tổng hợp**: 20 module RTL tổng hợp sạch sang `sky130_fd_sc_hd`; SRAM 2 KB gắn dưới dạng macro cứng OpenRAM.
- **Rủi ro vật lý**:
  - Thiếu bộ đồng bộ nhả reset trên `i_rst_n` và thiếu mạch đồng bộ 2-FF trên `i_ext_irq`/`i_timer_irq`.
  - Đường nửa chu kỳ từ chân xuất dữ liệu sườn âm `negedge` của SRAM (`dout1` và `dout0`) là điểm nghẽn timing gắt gao nhất ($T_{	ext{clk}}/2$).
  - Trong `config.json`, các cờ `RUN_MAGIC_DRC`, `RUN_KLAYOUT_DRC`, `RUN_LVS` và `RUN_POST_CTS_RESIZER_TIMING` đang bị đặt `false`!

## 17. Đánh Giá Bảo Mật & Độ Tin Cậy (Security/Reliability)

- **Xếp hạng: Nguyên mẫu cơ bản (Dưới mức an toàn của MCU thực tế)**.
- Lệnh bất hợp lệ không tạo bẫy; `DIV`/`REM` chạy thành `ADD`; SRAM 2 KB bị lặp bóng đè khắp 4 GB (nguy cơ stack overflow ghi đè hỏng mã lệnh); cầu APB bị treo vĩnh viễn nếu slave không trả `PREADY`; chân ngắt ngoài thiếu mạch chống siêu ổn định (metastability).

## 18. Đánh Giá Tài Liệu (Documentation Assessment)

- `README.md` (Phase 0), `SPEC.md` (Phase 2), `sim/wave.do` (Phase 0) và `PROJECT_PHASES_SUMMARY.md` (Phase 4) mâu thuẫn nghiêm trọng.
- **Khuyến nghị**: Tinh gọn lại còn 4 tài liệu chuẩn xác: `README.md`, `SPEC.md` (v4.0 phản ánh đúng RTL 3 tầng), `VERIFICATION_PLAN.md` và `ASIC_SIGNOFF.md`.

## 19. Sổ Đăng Ký Rủi Ro (Risk Register)

Tổng hợp 18 rủi ro kỹ thuật chính yếu:
- **P0 (7 rủi ro)**: R-01 (Đọc CSR ra `0`), R-02 (Ghi CSR lấy `rs2`), R-03 (`LW` $ightarrow$ `MUL` chốt nhầm địa chỉ), R-04 (Forwarding Tầng 3 ra `0` cho `JAL`/`CSR`), R-05 (Ngắt làm mất lệnh Tầng 3 / xóa `mepc`), R-06 (Vòng lặp tổ hợp APB $\leftrightarrow$ Hazard), R-07 (`DIV`/`REM` chạy thành `ADD`).
- **P1 (5 rủi ro)**: R-08 (0% kiểm thử CSR/Trap/APB), R-09 (Thiếu mạch Boot nạp SRAM khi đúc chip), R-10 (Tắt DRC/LVS trong `config.json`), R-11 (Thiếu 2-FF đồng bộ chân ngắt/reset), R-12 (SRAM 2 KB lặp bóng khắp 4 GB).
- **P2 (5 rủi ro)**: R-13 (Gán cứng `.data 0x00E0` giới hạn code 224 B), R-14 (Phạt 36 chu kỳ nạp lệch nửa từ), R-15 (Đường nửa chu kỳ sườn âm SRAM), R-16 (Lệnh bất hợp lệ & `EBREAK` chạy như NOP), R-17 (`mtval` không ghi được & `mtvec` chưa che bit mode).
- **P3 (1 rủi ro)**: R-18 (Lệch tài liệu `README`/`SPEC`/`wave.do`).

## 20. Điểm Trưởng Thành Dự Án (Project Maturity Score)

- **Điểm tổng quan**:
  - ISA: **2.5/5** | Vi kiến trúc: **3.0/5** | Chất lượng RTL: **2.5/5** | Đúng đắn đường ống: **2.0/5**
  - Hệ thống bộ nhớ: **3.0/5** | Bus APB: **2.0/5** | CSR / Bẫy / Ngắt: **1.5/5** | Kiểm chứng: **1.0/5**
  - Firmware: **2.5/5** | Hiệu năng: **3.5/5** | Công suất: **2.5/5** | Sẵn sàng ASIC: **2.5/5**
  - Tài liệu: **2.0/5** | Độ hoàn thiện MCU: **1.0/5** | Bảo mật / Bền vững: **1.0/5**

## 21. So Sánh Các Hướng Đi Chiến Lược (Strategic Path Comparison)

So sánh 6 phương án: Tối ưu CPU (A), Đóng kín tính đúng đắn & Kiểm chứng (B), Mở rộng MCU/SoC (C), Tối ưu FPGA (D), Ký duyệt vật lý ngay (E), Thêm bộ tăng tốc AI độc lập (F).

## 22. Hướng Đi Khuyến Nghị (Recommended Direction)

**Chọn HƯỚNG B (Đóng Kín Tính Đúng Đắn & Kiểm Chứng Trước Tiên) $\longrightarrow$ Kế tiếp là Tích hợp Ngoại vi/Boot tối thiểu cho MCU (HƯỚNG C) $\longrightarrow$ Cuối cùng là Ký duyệt vật lý thực chất (HƯỚNG E).**

## 23. Lộ Trình Phát Triển (Development Roadmap)

- **Phase 0**: Đóng băng baseline và kiểm toán (Đã hoàn thành trong báo cáo này).
- **Phase 1**: Sửa dứt điểm 7 lỗi RTL mức P0/P1.
- **Phase 2**: Xây dựng testbench tự kiểm tra cho CSR/Trap/IRQ/APB và chạy bộ `riscv-tests`.
- **Phase 3**: Tinh chỉnh compiler/firmware (`-falign-loops=4`, gỡ `.data 0x00E0`).
- **Phase 4**: Ghép nối hệ thống MCU IoT tối thiểu (`mcu_soc_top`: UART, Timer, GPIO, Bootloader, APB Decoder).
- **Phase 5 & 6**: Bật đầy đủ Magic DRC, KLayout DRC/XOR, Netgen LVS và chạy STA 9 góc + GLS.

## 24. Mười Nhiệm Vụ Cần Làm Ngay (Immediate Next 10 Tasks)

1. Sửa lỗi đấu nối đọc/ghi CSR ở Tầng 3 và cho phép ghi `mtval` (R-01, R-02, R-17).
2. Sửa nguồn chuyển tiếp Tầng 3 (`w_wb_data`) và dọn nhánh chết `FWD_MEM_WB` (R-04).
3. Khóa tín hiệu chạy bộ nhân `i_mul_valid` khi đang có stall Load-to-Use (R-03).
4. Sửa cơ chế lưu `mepc`/commit Tầng 3 khi có ngắt và cắt vòng lặp tổ hợp APB $\leftrightarrow$ Hazard (R-05, R-06).
5. Bổ sung bẫy lệnh bất hợp lệ (`mcause=2`), `EBREAK` (`mcause=3`), lỗi vượt biên SRAM và sửa giải mã `DIV`/`REM` (R-07, R-12, R-16).
6. Làm sạch cảnh báo lint Verilator, sửa header guard, toán tử `===` và thêm 2-FF đồng bộ chân ngắt (R-11).
7. Xây dựng testbench tự kiểm tra `tb_csr_trap_irq.v` và `tb_apb_master.v` (R-08).
8. Xây dựng bộ test tuân thủ đầy đủ tập lệnh `tb_isa_compliance.v` (R-08).
9. Thêm `-falign-loops=4` vào `Makefile` và gỡ địa chỉ cố định `.data 0x00E0` trong `link.ld` (R-13, R-14).
10. Bật đầy đủ Magic/KLayout DRC, Netgen LVS trong `config.json` và đồng bộ hóa tài liệu `README`/`SPEC` (R-10, R-18).

## 25. Tiêu Chí Hoàn Thành (Definition of Done)

0 lỗi RTL P0/P1; 0 cảnh báo lint Verilator; 100% testbench mới và cũ PASS; Bubble Sort chạy tự động từ mã nguồn $\le 469$ chu kỳ; luồng OpenLane 2 bật đầy đủ Magic DRC = 0, Netgen LVS = 0; tài liệu khớp 100% với mã nguồn.

## 26. Các Câu Hỏi Cần Người Dùng Quyết Định (Questions Requiring User Decision)

1. Xử lý lệnh chia `DIV`/`REM`: Tạo bẫy lệnh bất hợp lệ (`mcause=2`) hay thiết kế thêm bộ chia 32 chu kỳ?
2. Độ trễ nhận ngắt: Xác nhận cho phép lệnh Tầng 3 hoàn tất ghi trả và lưu `mepc = PC+4` khi có ngắt bất đồng bộ?
3. Hành vi `WFI`: Giữ nguyên NOP hay cho khóa xung nhịp chờ ngắt `(mip & mie) != 0`?
4. Mục tiêu đích: Bảo vệ đồ án học thuật / minh chứng RTL-to-GDS hay gửi đúc chip MPW thực tế (cần thêm mạch nạp Bootloader)?

---

## Trả Lời Câu Hỏi Cuối Cùng (Final Question Answer)

> **"Nếu đây là dự án MCU IoT RISC-V của chính tôi và tôi có quỹ thời gian kỹ thuật hạn hẹp, tôi nên làm gì TIẾP THEO để tối đa hóa xác suất thu được một lõi MCU đúng đắn, được kiểm chứng tốt, tổng hợp được và có thể hiện thực hóa vật lý?"**

### Một Khuyến Nghị Chủ Đạo Duy Nhất

**Hãy thực hiện ngay Phase 1 + Phase 2 ("Đóng Kín Tính Đúng Đắn Của Lõi & Kiểm Chứng Tự Động Các Phân Hệ") trên đúng kiến trúc 3 tầng `riscv_core_top` hiện tại trước khi chạm vào bất kỳ tính năng mới, ngoại vi mới hay lượt chạy OpenLane nào.**

Sửa dứt điểm **sáu lỗi RTL mức P0 (`R-01` đến `R-06`) và bổ sung bẫy lệnh bất hợp lệ cho `DIV`/`REM` (`R-07`)**, sau đó khóa chặt các bản vá đó bằng hai testbench tự kiểm tra (`tb_csr_trap_irq.v` và `tb_apb_master.v`). Tuyệt đối không thay đổi cấu trúc đường ống 3 tầng, không thêm bộ dự đoán nhánh mới và không ghép thêm ngoại vi SoC cho tới khi 7 lỗi P0 đó đã được sửa xong và vượt qua kiểm chứng mô phỏng.

### Cột Mốc Thực Tế Đầu Tiên & Tiêu Chí Hoàn Thành (Milestone 1 Definition of Done)

- Sửa xong 7 lỗi P0 trong `core_top.v`, `stage_id_ex.v`, `pipe_reg_ex_mem.v`, `forwarding_unit.v`, `hazard_unit.v`, `csr.v` và `instruction_decoder.v`.
- `verilator --lint-only -Wall` (bỏ `-Wno-UNOPTFLAT` và `-Wno-UNUSED`) đạt **0 lỗi và 0 cảnh báo**.
- 6 testbench hiện có cộng với testbench mới `tb_csr_trap_irq.v` đạt 100% PASS, chứng minh thực nghiệm rằng đọc/ghi CSR (`mscratch`, `mtvec`), `LW` $ightarrow$ `MUL`, `JAL` $ightarrow$ `RS1`, `ECALL`, `EBREAK`, lệnh bất hợp lệ và ngắt bất đồng bộ đều chạy chính xác mà không làm hỏng trạng thái kiến trúc CPU.

FINAL STATUS:

REVIEW COMPLETE — NO RTL MODIFIED
