#!/usr/bin/env bash
# Run riscv-arch-test on the Ibex Verilator model and compare against Sail, using RISCOF.
# Usage: run_riscof.sh [suite]   (default rv32i_m; e.g. rv32i_m/I for one extension)
# Needs: riscof (pip), Sail in ~/tools/sail,
#        riscv-arch-test 3.9.1 in ~/riscv-arch-test (or set ARCH_TEST_DIR).
set -euo pipefail
export PATH="$HOME/tools/rv32/bin:$HOME/tools/sail/bin:$HOME/.local/bin:$PATH"
repo="$(cd "$(dirname "$0")/.." && pwd)"
arch="${ARCH_TEST_DIR:-$HOME/riscv-arch-test}"
suite="${1:-rv32i_m}"
work="${RISCOF_WORK:-$HOME/space-am-soc-riscof}"

# The compliance build has 4 MiB of RAM (sim_riscof target); build it once.
sim="$HOME/space-am-soc-sim-riscof/sim_riscof-verilator/Vtop_verilator"
if [ ! -x "$sim" ]; then
  (cd "$repo" && fusesoc --cores-root=. run --build-root="$HOME/space-am-soc-sim-riscof" \
    --target=sim_riscof --tool=verilator --setup --build lowrisc:ibex:demo_system)
fi

cd "$repo/dv/riscof"
riscof run --config config.ini \
  --suite "$arch/riscv-test-suite/$suite" \
  --env "$arch/riscv-test-suite/env" \
  --work-dir "$work" --no-browser
echo "Report: $work/report.html"
