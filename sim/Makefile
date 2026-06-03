# ==============================================================================
# File        : Makefile
# Project     : AXI4 VIP
# Author      : Huy Le
# Description : QuestaSim simulation Makefile for Linux.
#               Supports parallel regressions, random seeding, code/functional 
#               coverage collection, and merging results into HTML reports.
# ==============================================================================

# ==============================================================================
# 1. Path Definitions & File List
# ==============================================================================
SRC_DIR      = ../src
REPORT_DIR   = ./report
LOG_DIR      = $(REPORT_DIR)/logs
COV_DIR      = $(REPORT_DIR)/coverage
COV_HTML_DIR = $(REPORT_DIR)/cov_html

# Compilation Source Files (in correct compile order)
SV_SOURCES = \
    $(SRC_DIR)/axi4_if.sv \
    $(SRC_DIR)/axi4_pkg.sv \
    $(SRC_DIR)/axi4_test_pkg.sv \
    $(SRC_DIR)/sva/axi4_sva.sv \
    $(SRC_DIR)/tb_top.sv

# ==============================================================================
# 2. Configurable Variables (Can be overridden via command line)
# ==============================================================================
TESTNAME      ?= axi4_wr_rd_test
SEED          ?= random # Set to 'random' or a specific integer (e.g., 42)
UVM_VERBOSITY ?= UVM_LOW
NUM_RUNS      ?= 5 # Number of iterations per test in regression
USE_COVERAGE  ?= 1 # 1: Enable coverage collection, 0: Disable for speed

# Additional user-defined simulator arguments
PLUSARGS      += +DUMP_VCD

# List of tests to run during a regression
TEST_LIST     ?= axi4_wr_rd_test

# ==============================================================================
# 3. Simulator Flags & Conditional Options
# ==============================================================================
VLOG_FLAGS = -sv -work work -timescale 1ns/1ps +incdir+$(SRC_DIR) -l $(LOG_DIR)/compile.log
VOPT_FLAGS = +acc -work work -l $(LOG_DIR)/optimize.log
VSIM_FLAGS = -c -work work -l $(LOG_DIR)/run.log

# Coverage collection settings
ifeq ($(USE_COVERAGE),1)
    VLOG_FLAGS += -cover sbcet
    VOPT_FLAGS += -cover sbcet
    VSIM_FLAGS += -coverage
endif

# Dynamic Seed Generation
ifeq ($(SEED),random)
    GEN_SEED = $(shell shuf -i 1-99999999 -n 1)
else
    GEN_SEED = $(SEED)
endif

# ==============================================================================
# 4. Main Targets
# ==============================================================================
.PHONY: help compile optimize run regress merge_cov cov_report gui clean

help:
	@echo "========================================================================"
	@echo "                      AXI4 VIP Simulation Makefile                      "
	@echo "========================================================================"
	@echo "Usage:"
	@echo "  make run             - Run a single simulation (CLI mode)"
	@echo "  make gui             - Run a single simulation (GUI mode with wave window)"
	@echo "  make regress         - Run multiple simulation runs in parallel"
	@echo "  make merge_cov       - Merge all coverage databases (.ucdb)"
	@echo "  make cov_report      - Merge and generate HTML coverage report"
	@echo "  make clean           - Remove all generated files & simulation libraries"
	@echo ""
	@echo "Variables (Override via command line, e.g., 'make run TESTNAME=my_test'):"
	@echo "  TESTNAME=<name>      - Set UVM test name (default: $(TESTNAME))"
	@echo "  SEED=<int/random>    - Set simulation seed (default: $(SEED))"
	@echo "  UVM_VERBOSITY=<val>  - Set verbosity level (default: $(UVM_VERBOSITY))"
	@echo "  NUM_RUNS=<int>       - Iterations per test in regression (default: $(NUM_RUNS))"
	@echo "  USE_COVERAGE=<0/1>   - Enable/disable code coverage (default: $(USE_COVERAGE))"
	@echo "  TEST_LIST=\"t1 t2\"  - List of tests for regression (default: \"$(TEST_LIST)\")"
	@echo "========================================================================"

# Compile phase
compile:
	@mkdir -p $(LOG_DIR)
	@echo "[COMPILE] Creating library and compiling sources..."
	@vlib work
	@vmap work work
	vlog $(VLOG_FLAGS) $(SV_SOURCES)

# Optimize phase (Standard industry Questa flow using vopt)
optimize: compile
	@echo "[OPTIMIZE] Generating optimized model 'opt_tb_top'..."
	vopt $(VOPT_FLAGS) tb_top -o opt_tb_top

# Run a single simulation batch
run: optimize
	@mkdir -p $(LOG_DIR) $(COV_DIR)
	@echo "[RUN] Executing: $(TESTNAME) | SEED=$(GEN_SEED)"
	vsim $(VSIM_FLAGS) -sv_seed $(GEN_SEED) \
		+UVM_TESTNAME=$(TESTNAME) \
		+UVM_VERBOSITY=$(UVM_VERBOSITY) \
		$(PLUSARGS) \
		-do "if {[string equal [design visibility] \"port\"] || [string equal [design visibility] \"none\"]} { \
		       coverage save -onexit $(COV_DIR)/$(TESTNAME)_seed_$(GEN_SEED).ucdb; \
		     }; run -all; quit -f" \
		opt_tb_top

# Launch Questa GUI with full AXI4 waveform view
gui: optimize
	@mkdir -p $(LOG_DIR)
	@echo "[GUI] Launching QuestaSim GUI for: $(TESTNAME)"
	vsim -gui -work work \
		+UVM_TESTNAME=$(TESTNAME) \
		+UVM_VERBOSITY=$(UVM_VERBOSITY) \
		$(PLUSARGS) \
		-do "\
			add wave -divider {System}; \
			add wave -color Yellow sim:/tb_top/intf/clk; \
			add wave -color Yellow sim:/tb_top/intf/rst_n; \
			add wave -divider {AW Channel}; \
			add wave -hex sim:/tb_top/intf/AWID sim:/tb_top/intf/AWADDR sim:/tb_top/intf/AWLEN; \
			add wave -hex sim:/tb_top/intf/AWSIZE sim:/tb_top/intf/AWBURST; \
			add wave sim:/tb_top/intf/AWVALID sim:/tb_top/intf/AWREADY; \
			add wave -divider {W Channel}; \
			add wave -hex sim:/tb_top/intf/WDATA sim:/tb_top/intf/WSTRB; \
			add wave sim:/tb_top/intf/WLAST sim:/tb_top/intf/WVALID sim:/tb_top/intf/WREADY; \
			add wave -divider {B Channel}; \
			add wave -hex sim:/tb_top/intf/BID sim:/tb_top/intf/BRESP; \
			add wave sim:/tb_top/intf/BVALID sim:/tb_top/intf/BREADY; \
			add wave -divider {AR Channel}; \
			add wave -hex sim:/tb_top/intf/ARID sim:/tb_top/intf/ARADDR sim:/tb_top/intf/ARLEN; \
			add wave -hex sim:/tb_top/intf/ARSIZE sim:/tb_top/intf/ARBURST; \
			add wave sim:/tb_top/intf/ARVALID sim:/tb_top/intf/ARREADY; \
			add wave -divider {R Channel}; \
			add wave -hex sim:/tb_top/intf/RID sim:/tb_top/intf/RDATA sim:/tb_top/intf/RRESP; \
			add wave sim:/tb_top/intf/RLAST sim:/tb_top/intf/RVALID sim:/tb_top/intf/RREADY; \
			run -all" \
		opt_tb_top &

# ==============================================================================
# 5. Regression Harness (Supports parallel execution, e.g., 'make -j8 regress')
# ==============================================================================
# Generate a list of execution targets: e.g., axi4_wr_rd_test_run_1, axi4_wr_rd_test_run_2
REGRESS_TARGETS = $(foreach test,$(TEST_LIST),$(foreach idx,$(shell seq 1 $(NUM_RUNS)),$(test)_run_$(idx)))

# Regression runner entrypoint
regress: optimize
	@echo "[REGRESS] Starting parallel regression for tests: $(TEST_LIST)"
	@echo "          Running $(NUM_RUNS) iterations per test..."
	@mkdir -p $(LOG_DIR) $(COV_DIR)
	@$(MAKE) $(REGRESS_TARGETS)
	@echo "[REGRESS] Parallel regression complete! Run 'make cov_report' to generate coverage."

# Individual run target handler
$(REGRESS_TARGETS):
	@test_name=$(word 1,$(subst _run_, ,$@)); \
	run_idx=$(word 2,$(subst _run_, ,$@)); \
	seed=$$(shuf -i 1-99999999 -n 1); \
	log_file=$(LOG_DIR)/$${test_name}_run_$${run_idx}_seed_$${seed}.log; \
	ucdb_file=$(COV_DIR)/$${test_name}_run_$${run_idx}_seed_$${seed}.ucdb; \
	echo "[REGRESS-RUN] $$test_name | Iteration: $$run_idx | Seed: $$seed"; \
	vsim $(VSIM_FLAGS) -sv_seed $$seed \
		+UVM_TESTNAME=$$test_name \
		+UVM_VERBOSITY=$(UVM_VERBOSITY) \
		$(PLUSARGS) \
		-l $$log_file \
		-do "coverage save -onexit $$ucdb_file; run -all; quit -f" \
		opt_tb_top > /dev/null 2>&1; \
	if grep -q -E "UVM_ERROR\s*:\s*[1-9]" $$log_file || grep -q -E "UVM_FATAL\s*:\s*[1-9]" $$log_file; then \
		echo "              ==> $$test_name (Run $$run_idx) [FAILED] - Log: $$log_file"; \
	else \
		echo "              ==> $$test_name (Run $$run_idx) [PASSED]"; \
	fi

# ==============================================================================
# 6. Coverage Post-Processing
# ==============================================================================
# Merge all generated UCDB databases
merge_cov:
	@echo "[COV] Merging all coverage databases in $(COV_DIR) into $(COV_DIR)/merged.ucdb..."
	@mkdir -p $(COV_DIR)
	@if [ "$$(ls -A $(COV_DIR)/*.ucdb 2>/dev/null)" ]; then \
		vcover merge $(COV_DIR)/merged.ucdb $(COV_DIR)/*.ucdb; \
		echo "[COV] Coverage databases successfully merged."; \
	else \
		echo "[COV] ERROR: No .ucdb files found in $(COV_DIR) to merge!"; \
		exit 1; \
	fi

# Generate the HTML Report
cov_report: merge_cov
	@echo "[COV] Generating HTML coverage report in $(COV_HTML_DIR)..."
	@mkdir -p $(COV_HTML_DIR)
	vcover report -html -htmldir $(COV_HTML_DIR) -verbose $(COV_DIR)/merged.ucdb
	@echo "========================================================================"
	@echo "[COV] HTML Report successfully generated!"
	@echo "      Open in browser: $(COV_HTML_DIR)/index.html"
	@echo "========================================================================"

# ==============================================================================
# 7. Clean up
# ==============================================================================
clean:
	@echo "[CLEAN] Removing all simulation outputs and libraries..."
	rm -rf work transcript vsim.wlf vsim_stacktrace.vstf modelsim.ini
	rm -rf $(REPORT_DIR)
	rm -rf *.vcd *.ucdb