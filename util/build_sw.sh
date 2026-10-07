#!/usr/bin/env bash
# Build the C firmware and produce hello_world's demo.vmem (RAM image baked into the bitstream).
set -euo pipefail
export PATH="$HOME/tools/rv32/bin:$HOME/.local/bin:$PATH"
cd "$(dirname "$0")/.."
cmake -S sw/c -B sw/c/build -DCMAKE_BUILD_TYPE=Release >/dev/null
cmake --build sw/c/build --target demo -j"$(nproc)"
elf=sw/c/build/demo/hello_world/demo
riscv32-unknown-elf-objcopy -O binary "$elf" "$elf.bin"
python3 util/bin2vmem.py "$elf.bin" "$elf.vmem"
riscv32-unknown-elf-size "$elf"
echo "vmem: $elf.vmem ($(wc -l < "$elf.vmem") lines)"
