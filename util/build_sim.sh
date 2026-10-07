#!/usr/bin/env bash
# Build the Verilator simulator. Output goes to ~/space-am-soc-sim (the WSL filesystem),
# because compiling over /mnt/c is several times slower.
set -euo pipefail
export PATH="$HOME/tools/rv32/bin:$HOME/.local/bin:$PATH"
cd "$(dirname "$0")/.."
fusesoc --cores-root=. run --build-root="$HOME/space-am-soc-sim" \
  --target=sim --tool=verilator --setup --build lowrisc:ibex:demo_system
echo "Simulator: $HOME/space-am-soc-sim/sim-verilator/Vtop_verilator"
