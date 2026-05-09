SHELL := /bin/bash
.SHELLFLAGS := -euo pipefail -c
.ONESHELL:

PROJECT_ROOT := $(abspath .)
BUILD_DIR := $(PROJECT_ROOT)/build
RTL_DIR := $(PROJECT_ROOT)/rtl
TB_DIR := $(PROJECT_ROOT)/tb
SIM_VCS_DIR := $(PROJECT_ROOT)/sim/vcs
TOOL_ENV := $(PROJECT_ROOT)/tools/ece411.sh

TOP ?= packet_tb
SIMV_NAME ?= simv
SIMV := $(BUILD_DIR)/$(SIMV_NAME)
VERDI ?= verdi

CLOCK_PERIOD_PS ?= 1000
SIM_TIMEOUT ?= 200
DUMP_FSDB ?= 0

RTL_SRCS := $(sort $(abspath $(wildcard $(RTL_DIR)/*.sv)))
TB_SRCS := $(sort $(abspath $(wildcard $(TB_DIR)/*.sv)))
SRCS := $(RTL_SRCS) $(TB_SRCS)

MSG_CONFIG := $(SIM_VCS_DIR)/messages.config
XPROP_CONFIG := $(SIM_VCS_DIR)/xprop.config

VCS_FLAGS := \
	-licqueue \
	-full64 \
	-lca \
	-sverilog \
	-timescale=1ps/1ps \
	-debug_access+all \
	-kdb \
	-suppress=LCA_FEATURES_ENABLED \
	-msg_config=$(MSG_CONFIG) \
	-xprop=$(XPROP_CONFIG) \
	-xprop=flowctrl \
	-assert svaext \
	+define+DW_SUPPRESS_WARN \
	+incdir+$(TB_DIR)

SIM_FLAGS := \
	-exitstatus \
	-suppress=ASLR_DETECTED_INFO

.PHONY: all compile sim verdi waves clean help check-sources

all: sim

compile: $(SIMV)

$(SIMV): $(SRCS) $(MSG_CONFIG) $(XPROP_CONFIG) $(TOOL_ENV)
	mkdir -p "$(BUILD_DIR)"
	source "$(TOOL_ENV)"
	cd "$(BUILD_DIR)"
	vcs $(SRCS) $(VCS_FLAGS) -top "$(TOP)" -o "$(SIMV_NAME)" -l compile.log

sim: $(SIMV)
	source "$(TOOL_ENV)"
	cd "$(BUILD_DIR)"
	"./$(SIMV_NAME)" $(SIM_FLAGS) \
		+CLOCK_PERIOD_PS="$(CLOCK_PERIOD_PS)" \
		+SIM_TIMEOUT="$(SIM_TIMEOUT)" \
		+DUMP_FSDB="$(DUMP_FSDB)" \
		-l simulation.log

verdi: DUMP_FSDB=1
verdi: $(SIMV)
	sim_status=0
	source "$(TOOL_ENV)"
	cd "$(BUILD_DIR)"
	"./$(SIMV_NAME)" $(SIM_FLAGS) \
		+CLOCK_PERIOD_PS="$(CLOCK_PERIOD_PS)" \
		+SIM_TIMEOUT="$(SIM_TIMEOUT)" \
		+DUMP_FSDB="$(DUMP_FSDB)" \
		-l simulation.log || sim_status=$$?
	if [ ! -s dump.fsdb ]; then
		printf 'ERROR: dump.fsdb was not created; not launching Verdi.\n' >&2
		if [ "$$sim_status" -eq 0 ]; then
			exit 1
		fi
		exit "$$sim_status"
	fi
	if [ "$$sim_status" -ne 0 ]; then
		printf 'Simulation exited with status %s; opening dump.fsdb for debug.\n' "$$sim_status"
	fi
	$(VERDI) -ssf dump.fsdb
	exit "$$sim_status"

waves: verdi

check-sources:
	test -n "$(RTL_SRCS)"
	test -n "$(TB_SRCS)"
	@printf 'RTL sources:\n%s\n\nTB sources:\n%s\n' "$(RTL_SRCS)" "$(TB_SRCS)"

clean:
	rm -rf "$(BUILD_DIR)"

help:
	@printf 'Targets:\n'
	@printf '  make compile       Elaborate %s with VCS\n' "$(TOP)"
	@printf '  make sim           Compile and run the self-checking testbench\n'
	@printf '  make verdi         Run sim and open dump.fsdb in Verdi\n'
	@printf '  make waves         Alias for make verdi\n'
	@printf '  make clean         Remove build artifacts\n\n'
	@printf 'Useful overrides:\n'
	@printf '  TOP=%s CLOCK_PERIOD_PS=%s SIM_TIMEOUT=%s DUMP_FSDB=%s\n' \
		"$(TOP)" "$(CLOCK_PERIOD_PS)" "$(SIM_TIMEOUT)" "$(DUMP_FSDB)"
