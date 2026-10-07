#!/usr/bin/env bash
# Run a firmware ELF on the Verilator simulator and show the UART output.
# Usage: run_sim.sh [elf] [seconds]   (defaults: hello_world, 60 s)
set -uo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
elf="$(realpath "${1:-$repo/sw/c/build/demo/hello_world/demo}")"
secs="${2:-60}"
sim="$HOME/space-am-soc-sim/sim-verilator/Vtop_verilator"
run="$HOME/space-am-soc-sim/run"

mkdir -p "$run" && cd "$run"
rm -f ./*.log
timeout --signal=INT "$secs" "$sim" --meminit=ram,"$elf" > sim_stdout.txt 2>&1
echo "--- simulator ($run/sim_stdout.txt) ---"
tail -n 5 sim_stdout.txt
for f in ./*.log; do
  [ -f "$f" ] || continue
  echo "--- $f ---"
  head -n 20 "$f"
done
