#!/usr/bin/env bash

# Local, make-friendly version of /class/ece411/ece411.sh.
# It is safe to source from non-interactive recipes.

if ! type module >/dev/null 2>&1 && [ -f /etc/profile.d/modules.sh ]; then
    # shellcheck source=/dev/null
    source /etc/profile.d/modules.sh
fi

if type module >/dev/null 2>&1; then
    module load Synopsys_x86-64/2024 >/dev/null 2>&1 || true
fi

export ECE411_GUI_TIMEOUT="${ECE411_GUI_TIMEOUT:-1h}"

export OPENRAM="${OPENRAM:-/class/ece411/OpenRAM}"
export FREEPDK45="${FREEPDK45:-/class/ece411/freepdk-45nm}"
export CBP2016="${CBP2016:-/class/ece411/cbp2016}"
export DW="${DW:-/software/Synopsys-2024_x86_64/icc/W-2024.09/dw}"
export UVM_HOME="${UVM_HOME:-/software/Synopsys-2024_x86_64/vcs/W-2024.09/etc/uvm-1.2}"

export PATH="${PATH:-}:/class/ece391/rhel8/bin:/class/ece411/riscv/bin:/class/ece411/verilator/bin:/class/ece411/cacti"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:/class/ece411/riscv/lib:/class/ece411/riscv/lib64"
