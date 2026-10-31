#!/usr/bin/env bash
# Build and run the block testbenches in dv/blocks with Verilator.
# Usage: run_block_tests.sh [timer|pwm|spi ...]   (default: all)
# Exits non-zero if any testbench fails to build or does not print PASS.
set -uo pipefail
repo="$(cd "$(dirname "$0")/.." && pwd)"
out="$HOME/space-am-soc-blocks"
prim="$repo/vendor/lowrisc_ip/ip/prim/rtl"

common=("$repo/rtl/system/soc_pkg.sv")
declare -A srcs=(
  [timer]="$repo/vendor/lowrisc_ibex/shared/rtl/timer.sv"
  [pwm]="$repo/rtl/system/pwm.sv $repo/rtl/system/pwm_wrapper.sv"
  [spi]="$prim/prim_util_pkg.sv $prim/prim_count_pkg.sv $prim/prim_count.sv $prim/prim_fifo_sync_cnt.sv $prim/prim_fifo_sync.sv $repo/rtl/system/spi_host.sv $repo/rtl/system/spi_top.sv"
)

blocks=("$@")
[ ${#blocks[@]} -eq 0 ] && blocks=(timer pwm spi)

failed=0
for b in "${blocks[@]}"; do
  dir="$out/$b"
  mkdir -p "$dir"
  # shellcheck disable=SC2086
  if ! verilator --binary --timing -Wno-fatal -Wno-lint -Wno-style -j 2 \
        --top-module "tb_$b" -Mdir "$dir" -I"$repo/dv/blocks" -I"$prim" \
        "${common[@]}" ${srcs[$b]} "$repo/dv/blocks/tb_$b.sv" > "$dir/build.log" 2>&1; then
    echo "FAIL tb_$b: build failed, see $dir/build.log"
    failed=1
    continue
  fi
  "$dir/Vtb_$b" | tee "$dir/run.log"
  grep -q "^PASS tb_$b" "$dir/run.log" || failed=1
done
exit $failed
