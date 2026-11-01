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
| XADC | Against a DRP model (`xadc_model.sv`): every register holds the model's value after a pass and follows changes; the pass counter runs at the expected rate; only status registers are read over DRP, one read at a time; writes ignored, unused offsets read 0 |
| I²C | Against two target models on one bus (`i2c_target.sv`, EEPROM-like, one of them stretching the clock): reset rate 100 kHz or slower; SCL period, high and low phases; SDA setup before SCL rises and no change as SCL falls; START, repeated START and STOP seen on the wires; multi-byte write and read-back; NACK reported for an empty address and cleared by the next command; clock stretching waited out; commands while busy dropped |

## 2. Peripheral test in simulation

`sw/c/tests/periph_test` exercises the same blocks through the core, with
interrupts and the real drivers. The Verilator top level loops SPI MOSI back to
MISO, feeds PWM channels 0–7 into the GPIO inputs so the firmware can
measure them, puts the I²C target model at address 0x50, and replaces the
XADC (which Verilator cannot simulate) with the same model as its block test.

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
| XADC | Readings converted by the driver match the model's 45.0 °C, 1.00 V, 1.80 V and 1.00 V |
| I²C | At 400 kHz: an empty address gets NACK; four bytes written to 0x50 and read back with a repeated START; the next byte still holds the model's fill pattern |

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
on pin 3 if you want to look at it with a scope. I²C is on the second row of
J1, opposite pins 1 and 2 (SCL opposite pin 1, SDA opposite pin 2); leave it
unconnected. Then open the UART at
115,200 baud and press reset. Expected:

- `PASS timer`, `PASS spi`, `PASS i2c` and `PASS xadc`, then
  `periph_test: ALL PASS`.
  Without the jumper, SPI fails with "no byte back" or wrong bytes. With no
  device connected, I²C only checks that an empty address gets no ACK; that
  fails if either line is stuck low. The XADC line prints the die temperature
  and the three supplies, which must be within the Spartan-7 ranges (1.0 V and
  1.8 V, ±5 %; 10–85 °C).
- `tick 1`, `tick 2`, … once a second, with LED 4 toggling on each tick.
- Both RGB LEDs fading, in opposite directions.

The PWM measurement is skipped on the board because the GPIO inputs are the
switches there.

## Compliance

The core itself is checked with `riscv-arch-test` under RISCOF (92/92 against
Sail). See the README. It is not in CI because it needs Sail and takes several
minutes.
