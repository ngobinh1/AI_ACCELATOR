onerror {resume}
quietly WaveActivateNextPane {} 0

# ==============================================================================
# CLOCK & RESET
# ==============================================================================
add wave -noupdate -divider {Clock & Reset}
add wave -noupdate /tb_bubble_sort/clk
add wave -noupdate /tb_bubble_sort/rst_n

# ==============================================================================
# PIPELINE CONTROL & HAZARDS
# ==============================================================================
add wave -noupdate -divider {Pipeline Control & Hazard}
add wave -noupdate /tb_bubble_sort/u_CPU/w_hz_stall_pc
add wave -noupdate /tb_bubble_sort/u_CPU/w_hz_stall_pipe
add wave -noupdate /tb_bubble_sort/u_CPU/w_hz_flush_pipe
add wave -noupdate /tb_bubble_sort/u_CPU/w_hz_trap_taken
add wave -noupdate /tb_bubble_sort/u_CPU/u_hazard/r_state

# ==============================================================================
# STAGE 1: INSTRUCTION FETCH & DECODE (IF/ID)
# ==============================================================================
add wave -noupdate -divider {Stage 1: IF / ID}
add wave -noupdate -radix hexadecimal /tb_bubble_sort/u_CPU/u_stage_if_id/o_pc
add wave -noupdate -radix hexadecimal /tb_bubble_sort/u_CPU/u_stage_if_id/i_instr
add wave -noupdate /tb_bubble_sort/u_CPU/u_stage_if_id/o_valid
add wave -noupdate -radix unsigned /tb_bubble_sort/u_CPU/u_stage_if_id/o_rs1_addr
add wave -noupdate -radix hexadecimal /tb_bubble_sort/u_CPU/u_stage_if_id/o_rs1_data
add wave -noupdate -radix unsigned /tb_bubble_sort/u_CPU/u_stage_if_id/o_rs2_addr
add wave -noupdate -radix hexadecimal /tb_bubble_sort/u_CPU/u_stage_if_id/o_rs2_data
add wave -noupdate -radix unsigned /tb_bubble_sort/u_CPU/u_stage_if_id/o_rd_addr
add wave -noupdate -radix hexadecimal /tb_bubble_sort/u_CPU/u_stage_if_id/o_imm_ext

# ==============================================================================
# STAGE 2: EXECUTE, MEMORY & WRITE-BACK (EX)
# ==============================================================================
add wave -noupdate -divider {Stage 2: EX / MEM / WB}
add wave -noupdate -radix hexadecimal /tb_bubble_sort/u_CPU/w_id_ex_pc
add wave -noupdate /tb_bubble_sort/u_CPU/w_id_ex_valid
add wave -noupdate -radix hexadecimal /tb_bubble_sort/u_CPU/u_stage_ex/w_alu_result
add wave -noupdate /tb_bubble_sort/u_CPU/u_stage_ex/o_branch_taken
add wave -noupdate -radix hexadecimal /tb_bubble_sort/u_CPU/u_stage_ex/o_branch_target
add wave -noupdate /tb_bubble_sort/u_CPU/w_ex_reg_write_final
add wave -noupdate -radix unsigned /tb_bubble_sort/u_CPU/w_ex_rd_addr_final
add wave -noupdate -radix hexadecimal /tb_bubble_sort/u_CPU/w_ex_wb_data

# ==============================================================================
# INTERNAL SRAM (2KB)
# ==============================================================================
add wave -noupdate -divider {Internal SRAM 2KB}
add wave -noupdate /tb_bubble_sort/u_CPU/u_sram_2kb/csb0
add wave -noupdate /tb_bubble_sort/u_CPU/u_sram_2kb/web0
add wave -noupdate -radix binary /tb_bubble_sort/u_CPU/u_sram_2kb/wmask0
add wave -noupdate -radix hexadecimal /tb_bubble_sort/u_CPU/u_sram_2kb/addr0
add wave -noupdate -radix hexadecimal /tb_bubble_sort/u_CPU/u_sram_2kb/din0
add wave -noupdate -radix hexadecimal /tb_bubble_sort/u_CPU/u_sram_2kb/dout0
add wave -noupdate /tb_bubble_sort/u_CPU/u_sram_2kb/csb1
add wave -noupdate -radix hexadecimal /tb_bubble_sort/u_CPU/u_sram_2kb/addr1
add wave -noupdate -radix hexadecimal /tb_bubble_sort/u_CPU/u_sram_2kb/dout1

# ==============================================================================
# PERFORMANCE METRICS
# ==============================================================================
add wave -noupdate -divider {Performance Metrics}
add wave -noupdate -radix decimal /tb_bubble_sort/total_cycles
add wave -noupdate -radix decimal /tb_bubble_sort/total_instructions
add wave -noupdate -radix decimal /tb_bubble_sort/branch_taken_count
add wave -noupdate -radix decimal /tb_bubble_sort/swap_count

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 300
configure wave -valuecolwidth 120
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ns
update
