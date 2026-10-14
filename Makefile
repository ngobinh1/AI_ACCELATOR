# ==============================================================================
# RISC-V 32-bit IoT / AI Accelerator Core Makefile
# ==============================================================================
# Description: Unified build, simulation, linting, and firmware compilation flow
# ==============================================================================

SHELL       := /bin/bash
PROJECT_DIR := $(shell pwd)

# ------------------------------------------------------------------------------
# Directory Configuration
# ------------------------------------------------------------------------------
RTL_DIR     := rtl
TB_DIR      := tb
FW_DIR      := firmware
SIM_DIR     := sim
WORK_DIR    := $(SIM_DIR)/work

# ------------------------------------------------------------------------------
# Toolchain Definitions
# ------------------------------------------------------------------------------
# RISC-V GCC Toolchain
RISCV_PREFIX  ?= riscv64-unknown-elf-
RISCV_GCC     := $(RISCV_PREFIX)gcc
RISCV_OBJCOPY := $(RISCV_PREFIX)objcopy
RISCV_OBJDUMP := $(RISCV_PREFIX)objdump

# Simulator Tools (QuestaSim / ModelSim & Verilator)
VLIB          := vlib
VMAP          := vmap
VLOG          := vlog
VSIM          := vsim
VERILATOR     := verilator
GTKWAVE       := gtkwave

# ------------------------------------------------------------------------------
# Source Files
# ------------------------------------------------------------------------------
RTL_INCDIR    := $(RTL_DIR)/defines
RTL_DEFINES   := $(wildcard $(RTL_DIR)/defines/*.vh)
RTL_CORE_SRCS := $(wildcard $(RTL_DIR)/core/*.v)
RTL_BUS_SRCS  := $(wildcard $(RTL_DIR)/bus/*.v)
RTL_MEM_SRCS  := $(wildcard $(RTL_DIR)/memory/*.v)
RTL_SRCS      := $(RTL_CORE_SRCS) $(RTL_BUS_SRCS) $(RTL_MEM_SRCS)

TB_SRCS       := $(wildcard $(TB_DIR)/*.v)
TOP_TB        := tb_bubble_sort

# Firmware Files
FW_START_S    := $(FW_DIR)/Start.S
FW_C_SRCS     := $(wildcard $(FW_DIR)/*.c)
FW_LDSCRIPT   := $(FW_DIR)/link.ld
FW_ELF        := $(FW_DIR)/firmware.elf
FW_HEX        := $(FW_DIR)/memfile.hex
FW_ASM        := $(FW_DIR)/firmware.asm

# ------------------------------------------------------------------------------
# Compiler & Simulator Flags
# ------------------------------------------------------------------------------
# RISC-V GCC Flags (RV32IC with Zicsr extension - Phase 4)
RISCV_ARCH    := rv32ic_zicsr
RISCV_ABI     := ilp32
RISCV_CFLAGS  := -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) -O2 \
                 -falign-loops=4 -falign-functions=4 \
                 -static -mcmodel=medany -fvisibility=hidden \
                 -nostdlib -nostartfiles -T $(FW_LDSCRIPT) \
                 -Wall -Wextra


# QuestaSim Flags
VLOG_FLAGS    := -work $(WORK_DIR) +incdir+$(RTL_INCDIR) +incdir+$(RTL_DIR)/core
VSIM_FLAGS    := -lib $(WORK_DIR) -c -do "run -all; quit"
VSIM_GUI_FLAGS:= -lib $(WORK_DIR) -gui -do "do $(SIM_DIR)/wave.do; run -all"

# ------------------------------------------------------------------------------
# Default Target
# ------------------------------------------------------------------------------
.PHONY: all
all: firmware compile sim

# ------------------------------------------------------------------------------
# Help Target
# ------------------------------------------------------------------------------
.PHONY: help
help:
	@echo "========================================================================"
	@echo "   RISC-V IoT / AI Accelerator Core - Build & Simulation Management     "
	@echo "========================================================================"
	@echo " Usage: make [TARGET]"
	@echo ""
	@echo " Simulation Targets (QuestaSim):"
	@echo "   make sim          : Run simulation in batch (console) mode"
	@echo "   make sim-gui      : Run simulation in GUI mode with waveforms"
	@echo "   make compile      : Compile RTL and Testbench sources into work library"
	@echo ""
	@echo " Firmware Targets:"
	@echo "   make firmware     : Compile C and assembly firmware into ELF, ASM, and HEX"
	@echo "   make fw           : Alias for make firmware"
	@echo "   make clean-fw     : Remove generated firmware binaries"
	@echo ""
	@echo " Quality Assurance / Linting:"
	@echo "   make lint         : Run static linting with Verilator"
	@echo ""
	@echo " Cleaning Targets:"
	@echo "   make clean        : Remove simulation outputs, logs, and work directory"
	@echo "   make clean-all    : Clean both simulation and firmware artifacts"
	@echo "========================================================================"

# ------------------------------------------------------------------------------
# Firmware Compilation
# ------------------------------------------------------------------------------
.PHONY: firmware fw clean-fw
firmware: $(FW_HEX) $(FW_ASM)
fw: firmware

$(FW_ELF): $(FW_START_S) $(FW_C_SRCS) $(FW_LDSCRIPT)
	@echo "[FW] Compiling RISC-V Firmware: $(FW_C_SRCS) $(FW_START_S)..."
	@$(RISCV_GCC) $(RISCV_CFLAGS) $(FW_START_S) $(FW_C_SRCS) -o $@

$(FW_ASM): $(FW_ELF)
	@echo "[FW] Generating Disassembly: $@..."
	@$(RISCV_OBJDUMP) -d $< > $@

$(FW_HEX): $(FW_ELF)
	@echo "[FW] Generating Verilog Memory Hex: $@..."
	@$(RISCV_OBJCOPY) -O verilog --verilog-data-width=4 $< $@
	@echo "[FW] Firmware Build Complete!"

clean-fw:
	@echo "[FW] Cleaning firmware build artifacts..."
	@rm -f $(FW_ELF) $(FW_ASM) $(FW_HEX)

# ------------------------------------------------------------------------------
# RTL & TB Compilation (QuestaSim)
# ------------------------------------------------------------------------------
$(WORK_DIR):
	@echo "[SIM] Creating work library directory: $(WORK_DIR)..."
	@mkdir -p $(SIM_DIR)
	@$(VLIB) $(WORK_DIR)
	@$(VMAP) work $(WORK_DIR)

.PHONY: compile
compile: $(WORK_DIR) $(RTL_SRCS) $(TB_SRCS)
	@echo "[SIM] Compiling RTL and TB sources with QuestaSim vlog..."
	@$(VLOG) $(VLOG_FLAGS) $(RTL_SRCS) $(TB_SRCS)

# ------------------------------------------------------------------------------
# Simulation Run (Batch Mode)
# ------------------------------------------------------------------------------
.PHONY: sim sim-phase5 sim-phase6 sim-isa sim-all
sim: compile $(FW_HEX)
	@echo "[SIM] Running simulation (Batch mode)..."
	@$(VSIM) $(VSIM_FLAGS) +HEX_FILE=$(FW_HEX) $(TOP_TB)

sim-phase5: compile
	@echo "[SIM] Running Phase 5 Datapath & Forwarding P0 Testbench..."
	@$(VSIM) $(VSIM_FLAGS) tb_phase5_datapath_p0

sim-phase6: compile
	@echo "[SIM] Running Phase 6 Control, Traps, Interrupts & APB Testbench..."
	@$(VSIM) $(VSIM_FLAGS) tb_phase6_control_traps

sim-isa: compile
	@echo "[SIM] Running RV32I Directed ISA Compliance Testbench..."
	@$(VSIM) $(VSIM_FLAGS) tb_isa_compliance

sim-all: compile $(FW_HEX)
	@echo "[SIM] Running Full Regression Suite (9 Testbenches)..."
	@$(VSIM) $(VSIM_FLAGS) +HEX_FILE=$(FW_HEX) tb_bubble_sort
	@$(VSIM) $(VSIM_FLAGS) tb_phase2_math_ai
	@$(VSIM) $(VSIM_FLAGS) tb_phase3_hazards
	@$(VSIM) $(VSIM_FLAGS) tb_rvc_decompressor
	@$(VSIM) $(VSIM_FLAGS) tb_rvc_pipeline
	@$(VSIM) $(VSIM_FLAGS) tb_ai_benchmark
	@$(VSIM) $(VSIM_FLAGS) tb_phase5_datapath_p0
	@$(VSIM) $(VSIM_FLAGS) tb_phase6_control_traps
	@$(VSIM) $(VSIM_FLAGS) tb_isa_compliance
	@echo "[SIM] ALL 9 REGRESSION TESTBENCHES COMPLETED SUCCESSFULLY!"

# ------------------------------------------------------------------------------
# Simulation Run (GUI Mode)
# ------------------------------------------------------------------------------
.PHONY: sim-gui gui
sim-gui gui: compile $(FW_HEX)
	@echo "[SIM] Launching QuestaSim GUI with waveforms..."
	@$(VSIM) $(VSIM_GUI_FLAGS) +HEX_FILE=$(FW_HEX) $(TOP_TB)

# ------------------------------------------------------------------------------
# Linting (Verilator)
# ------------------------------------------------------------------------------
.PHONY: lint
lint:
	@echo "[LINT] Running Verilator lint check on RTL..."
	@$(VERILATOR) --lint-only -Wall \
		+incdir+$(RTL_INCDIR) \
		+incdir+$(RTL_DIR)/core \
		-Wno-DECLFILENAME \
		-Wno-UNUSED \
		-Wno-UNDRIVEN \
		-Wno-EOFNEWLINE \
		-Wno-BLKSEQ \
		-Wno-MULTITOP \
		$(RTL_SRCS)
	@echo "[LINT] Lint completed successfully!"


# ------------------------------------------------------------------------------
# Clean Targets
# ------------------------------------------------------------------------------
.PHONY: clean clean-all
clean:
	@echo "[SIM] Cleaning simulation artifacts..."
	@rm -rf $(WORK_DIR) transcript vsim.wlf $(SIM_DIR)/vsim.wlf modelsim.ini
	@rm -f *.log *.vstf

clean-all: clean clean-fw
	@echo "[CLEAN] Cleaned all build and simulation artifacts."
