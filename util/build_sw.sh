#!/usr/bin/env bash
# Build the C firmware and produce RAM images (.vmem, baked into the bitstream) for
# hello_world (sw/c/build/demo/hello_world/demo.vmem) and the peripheral test
# (sw/c/build/tests/periph_test.vmem). Also builds periph_test_sim for Verilator.
set -euo pipefail
export PATH="$HOME/tools/rv32/bin:$HOME/.local/bin:$PATH"
cd "$(dirname "$0")/.."
cmake -S sw/c -B sw/c/build -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build sw/c/build --target demo periph_test periph_test_sim -j"$(nproc)"
for elf in sw/c/build/demo/hello_world/demo sw/c/build/tests/periph_test; do
  riscv32-unknown-elf-objcopy -O binary "$elf" "$elf.bin"
  python3 util/bin2vmem.py "$elf.bin" "$elf.vmem"
  riscv32-unknown-elf-size "$elf"
  echo "vmem: $elf.vmem ($(wc -l < "$elf.vmem") lines)"
done
