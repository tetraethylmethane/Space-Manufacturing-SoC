# Testing

Each peripheral is tested at three levels: on its own, inside the whole system
in simulation, and on the board. The first two run in CI on every push.

## 1. Block testbenches

`dv/blocks/tb_<block>.sv` drives one block directly through the frozen bus
(`bus_tasks.svh` checks that every access gets `rvalid` one cycle later).
Each testbench checks itself and prints `PASS tb_<block>` or the failures.

```bash
bash util/run_block_tests.sh          # all blocks
bash util/run_block_tests.sh spi      # one block
```

Needs Verilator 5 (uses `--binary --timing`). Takes about a minute.

| Block | What is checked |
|---|---|
| Timer | `mtime` counts one per cycle; register read-back and byte writes; the interrupt fires when `mtime` reaches `mtimecmp`, stays set until `mtimecmp` is written, and respects the high word; carry into `mtimeh`; `err` on unmapped offsets |
| PWM | All 12 channels: high time and period exact over a long window, for 0 %, 25 %, 50 %, full and over-range widths, `max = 0` (off) and periods from 2 to 256 cycles; channels independent; upper bits ignored |
| SPI | Idle levels (mode 0); SCK at 4 clocks per bit; MSB first; MOSI never changes on a rising SCK edge; 200-byte burst through the FIFO arrives intact and in order; TX full and empty flags; loopback read-back through the RX register |

## 2. Peripheral test in simulation

`sw/c/tests/periph_test` exercises the same blocks through the core, with
interrupts and the real drivers. The Verilator top level loops SPI MOSI back to
MISO and feeds PWM channels 0–7 into the GPIO inputs so the firmware can
measure them.

```bash
bash util/build_sw.sh && bash util/build_sim.sh
bash util/run_sim.sh sw/c/build/tests/periph_test_sim 300
```

The UART log (`~/space-am-soc-sim/run/uart0.log`) ends with
`periph_test: ALL PASS`.

| Block | What is checked |
|---|---|
| Timer | `mtime` and `mcycle` agree; ten timer interrupts 5,000 cycles apart (±50); `mcause` correct; no interrupt while masked, and the pending one is taken when unmasked |
| PWM | Duty cycle of channels 0–7 measured by sampling the GPIO inputs, within 2 % |
| SPI | Bytes 0–255 sent and read back over the loopback |

## 3. On the board

Build the bitstream with the peripheral test in RAM instead of hello-world:

```bash
bash util/build_sw.sh
bash util/setup_synth_boolean.sh sw/c/build/tests/periph_test.vmem   # WSL
```
```powershell
.\util\build_boolean.ps1 -Program                                    # Windows
```

Put a jumper between pins 1 and 2 of Pmod connector J1 (MOSI to MISO). SCK is
on pin 3 if you want to look at it with a scope. Then open the UART at
115,200 baud and press reset. Expected:

- `PASS timer` and `PASS spi`, then `periph_test: ALL PASS`. Without the
  jumper, SPI fails with "no byte back" or wrong bytes.
- `tick 1`, `tick 2`, … once a second, with LED 4 toggling on each tick.
- Both RGB LEDs fading, in opposite directions.

The PWM measurement is skipped on the board because the GPIO inputs are the
switches there.

## Compliance

The core itself is checked with `riscv-arch-test` under RISCOF (92/92 against
Sail). See the README. It is not in CI because it needs Sail and takes several
minutes.
