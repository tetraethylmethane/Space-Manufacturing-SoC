#!/usr/bin/env bash
# Generate (but don't build) the Vivado project for the Boolean Board with FuseSoC in WSL.
# The build itself runs in Windows Vivado (util/build_boolean.ps1), so SRAMInitFile is a
# Windows path. Usage: setup_synth_boolean.sh [path/to/app.vmem relative to repo root]
set -euo pipefail
export PATH="$HOME/tools/rv32/bin:$HOME/.local/bin:$PATH"
cd "$(dirname "$0")/.."
vmem=${1:-sw/c/build/demo/hello_world/demo.vmem}
[ -f "$vmem" ] || { echo "missing $vmem - run util/build_sw.sh first"; exit 1; }
winvmem="C:/work/space-am-soc/$vmem"
fusesoc --cores-root=. run --target=synth_boolean --setup lowrisc:ibex:demo_system \
  --SRAMInitFile="$winvmem"
ls build/lowrisc_ibex_demo_system_0/synth_boolean-vivado/
