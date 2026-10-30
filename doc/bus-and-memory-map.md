# Bus interface and memory map

Frozen on 30 October 2026 for the month-2 gate. Every block written from now on
targets the bus below and sits at the address given here. The values live in
three places that must agree: this document, `rtl/system/soc_pkg.sv` and
`sw/c/common/demo_system_regs.h`.

To change anything here, write the reason under [Changes](#changes), get it
reviewed, and update all three places in the same commit.

## Bus

There are two hosts and one shared bus. The Ibex data port has priority, and
the debug module comes second. Instruction fetch does not use this bus: it has
its own port into RAM, and into the debug module for debugging. Code can
therefore only run from RAM.

Each device sees five request signals and returns three response signals. They
are defined as `soc_pkg::bus_req_t` and `soc_pkg::bus_rsp_t`.

| Signal | Width | Direction | Meaning |
|---|---|---|---|
| `req` | 1 | to device | Access this cycle |
| `addr` | 32 | to device | Byte address, full width (decode your offset from the low bits) |
| `we` | 1 | to device | 1 = write, 0 = read |
| `be` | 4 | to device | Byte enables for writes |
| `wdata` | 32 | to device | Write data |
| `rvalid` | 1 | from device | Response, exactly one cycle after `req` |
| `rdata` | 32 | from device | Read data, valid with `rvalid` |
| `err` | 1 | from device | Access fault, valid with `rvalid` |

Rules for every device:

1. **Answer in one cycle.** Raise `rvalid` on the cycle after every `req`, for
   reads and writes alike. The bus has no wait states and no `gnt` on the
   device side.
2. **Slow blocks don't stall the bus.** A device that cannot produce data in
   one cycle (QSPI streamer, camera, I²C) buffers it in a FIFO and exposes a
   status register that firmware polls, or raises an interrupt.
3. **Registers are 32-bit and word-aligned.** Writes honour `be`. Reads return
   the whole word.
4. **Use `err` for real faults only:** a write to a read-only register, or an
   offset with no register behind it. The core turns `err` into a load or
   store access fault.
5. **Accesses outside every window fault.** If no device claims an address,
   the bus answers with `err`. Firmware can rely on that.
6. **Each block gets its own testbench.** Drive the block through these eight
   signals in Verilator without the core. Write the testbench before the
   block.

Ibex itself is the only part that knows which core is underneath. If the core
ever changes, an adapter between that core's interface and this bus is the
only new RTL.

## Memory map

Every window is a power of two and aligned to its size. A device is selected by
`(addr & ~(size - 1)) == base`.

| Base | Size | Block | Status |
|---|---|---|---|
| `0x0000_0000` | 128 KiB | Instruction RAM (BRAM); Ibex boots at `0x0000_0080` | Populated, holds code and data for now |
| `0x0002_0000` | 128 KiB | Data RAM (BRAM) | Reserved |
| `0x0004_0000` | 128 KiB | Frame buffer (BRAM), 75 KiB used for 320×240 greyscale | Reserved |
| `0x1000_0000` | 4 KiB | GPIO: LEDs, switches, buttons | Populated |
| `0x1000_1000` | 4 KiB | UART | Populated |
| `0x1000_2000` | 4 KiB | Timer (`mtime` at +0x0, `mtimecmp` at +0x8) | Populated |
| `0x1000_3000` | 4 KiB | I²C master | Reserved |
| `0x1000_4000` | 4 KiB | SPI master | Populated |
| `0x1000_5000` | 4 KiB | PWM (heaters) | Populated |
| `0x1000_6000` | 4 KiB | Step/dir motion | Reserved |
| `0x1000_7000` | 4 KiB | XADC interface | Reserved |
| `0x1000_8000` | 4 KiB | Camera capture control | Reserved |
| `0x1000_9000` | 4 KiB | QSPI weight streamer | Reserved |
| `0x1000_F000` | 4 KiB | Simulation control (Verilator only) | Populated |
| `0x1001_0000` | 4 KiB | Error counters / FDIR (WP2) | Reserved |
| `0x1001_1000` | 4 KiB | Watchdog (WP2) | Reserved |
| `0x1001_2000` | 4 KiB | Scrubber control (WP2) | Reserved |
| `0x1001_3000` | 4 KiB | SEM IP interface (WP2) | Reserved |
| `0x1A11_0000` | 64 KiB | Debug module (JTAG) | Populated |

Everything else is unmapped and faults.

Notes:

- **Data and code share the IRAM window for now.** The linker script keeps
  both in the first 128 KiB, with the stack in its top 8 KiB. When the data RAM
  is populated, only `sw/common/link.ld` changes.
- **The frame buffer window is 128 KiB** because a 75 KiB buffer needs a
  power-of-two window. The 53 KiB left over is not backed by memory.
- **Simulation control** prints characters to the Verilator log (byte write
  to +0x0) and ends the simulation (write 1 to +0x8). On the FPGA it does
  nothing.
- **The compliance build is the one exception.** The `sim_riscof` target moves
  RAM to `0x0040_0000` with 4 MiB, because some `riscv-arch-test` tests are
  larger than 128 KiB. That address is unmapped in the real map, so the two
  never meet.

## Changes

| Date | Change | Reason |
|---|---|---|
| 30 Oct 2026 | Frozen. Moved from the upstream demo-system layout (RAM at `0x0010_0000`, peripherals at `0x8000_xxxx`) to this map. Frame buffer window widened from 64 KiB to 128 KiB. Simulation control moved to `0x1000_F000`; debug module kept at `0x1A11_0000`. | Month-2 gate. The 64 KiB window could not hold the 75 KiB frame buffer. The old simulation-control address would have landed inside the data RAM. |
