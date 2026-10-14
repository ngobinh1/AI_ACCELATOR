current_design riscv_core_top

create_clock -name i_clk -period 12.0000 [get_ports {i_clk}]
set_clock_transition 0.1500 [get_clocks {i_clk}]
set_clock_uncertainty 0.2500 [get_clocks {i_clk}]

set_input_delay 2.0000 -clock [get_clocks {i_clk}] [all_inputs -no_clocks]
set_output_delay 2.0000 -clock [get_clocks {i_clk}] [all_outputs]

set_max_transition 1.5000 [current_design]
set_max_fanout 12.0000 [current_design]
set_max_capacitance 0.2000 [current_design]

set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin Y [all_inputs -no_clocks]
set_load 0.0334 [all_outputs]
