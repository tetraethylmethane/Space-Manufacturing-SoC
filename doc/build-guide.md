# Building the Hardened RISC-V SoC

**Target:** RealDigital Boolean Board — AMD Spartan-7 XC7S50-CSGA324
**Core:** lowRISC Ibex (SystemVerilog)
**Scope:** WP0 preparation through WP2 hardening

---

## The one rule

**Never have two unproven things at once.** Every stage below must run before the
next begins. When something breaks — and it will — you want exactly one candidate
cause. Most FPGA projects fail because three new things were introduced together
and the bug could be in any of them.

---

## Stage 0 — Toolchain (2–3 days)

Nothing here is your code. The point is to prove the tools work before you have
anything of your own to blame.

| Tool | Purpose | Notes |
|---|---|---|
| Vivado ML Standard | Synthesis, P&R, bitstream | Free edition covers XC7S50. Large download; start it early. |
| RISC-V GCC (`riscv32-unknown-elf`) | Compiler | Use a prebuilt toolchain. Do not build from source. |
| Verilator | Fast RTL simulation | Where you will spend most debugging time. |
| FuseSoC | Build orchestration | Ibex uses it. `pip install fusesoc`. |
| Python 3, srecord, git | Utilities | |

**Exit criterion:** build and run Ibex's `simple_system` in Verilator, and see
hello-world print.

```bash
git clone https://github.com/lowRISC/ibex-demo-system.git
cd ibex-demo-system
pip3 install -r python-requirements.txt
fusesoc --cores-root=. run --target=sim --setup --build lowrisc:ibex:demo_system
```

If this fails, fix it now. Everything downstream assumes it works.

---

## Stage 1 — Port `ibex_demo_system` to the Boolean Board (2–3 weeks)

**Start from `ibex_demo_system`, not `simple_system`.** The demo system already
has a working FPGA flow, GPIO, UART, timer, SPI, PWM and a debug module. It
targets an Arty A7 — also a 7-series part — so the port is a retarget rather
than a rewrite.

### What actually changes

1. **Constraints file.** Get the master XDC from RealDigital's Boolean Board
   page and cut it down to the pins you use. Start with: 100 MHz clock, one
   LED, one button, UART TX/RX.
2. **Clock.** Boolean Board has a 100 MHz oscillator. Add a Clocking Wizard IP
   to generate your system clock. **Start at 25–50 MHz.** You can raise it once
   timing closes; starting fast wastes days on timing failures that tell you
   nothing.
3. **Memory.** Swap behavioural RAM for Xilinx block RAM. Either infer it with
   the right coding style or instantiate the Block Memory Generator. Budget:
   **337 KB total on this device** — see Stage 3.
4. **Board target.** Add a `boolean` target to the `.core` file, copying the
   Arty target and changing part number to `xc7s50csga324-1`.

### Order of bring-up

```
blink an LED from your own Verilog     → proves toolchain + constraints + clock
    ↓
Ibex boots, UART prints                → proves core + memory + bus
    ↓
riscv-arch-test passes under RISCOF    → proves the core is actually correct
    ↓
CI pipeline runs on every push         → proves you will notice when it breaks
```

**Do the LED first.** It is trivially simple and it isolates every environment
problem — wrong pin, wrong voltage standard, wrong part number — before Ibex is
in the picture.

### Exit criterion (this is the M2 gate)

- Ibex boots on hardware and prints over UART
- `riscv-arch-test` passes via RISCOF
- CI green on every push
- Bus adapter specified (Stage 2)

---

## Stage 2 — Freeze the bus adapter (3 days, before any peripheral)

This is the single highest-leverage step in the whole build, and it takes almost
no time. Do it **before** you write a single peripheral.

Ibex's memory interface is already simple, so adopt it verbatim as your internal
peripheral bus:

```systemverilog
// The only interface any of your modules ever sees.
typedef struct packed {
  logic        req;      // request valid
  logic [31:0] addr;
  logic        we;       // 1 = write
  logic [3:0]  be;       // byte enables
  logic [31:0] wdata;
} bus_req_t;

typedef struct packed {
  logic        gnt;      // request accepted
  logic        rvalid;   // rdata valid (1 cycle after gnt for simple slaves)
  logic [31:0] rdata;
  logic        err;
} bus_rsp_t;
```

**Rules:**
- Every module you write targets `bus_req_t` / `bus_rsp_t`.
- Exactly one module knows what core is underneath: `core_adapter.sv`.
- If you ever switch to NEORV32, you write a Wishbone bridge in that one file
  and nothing else changes.

Write a bus-functional model so peripherals can be tested in Verilator without
the core present. This is worth an afternoon and saves weeks.

### Memory map

| Base | Size | Region |
|---|---|---|
| `0x0000_0000` | 128 KB | Instruction RAM (BRAM) |
| `0x0002_0000` | 128 KB | Data RAM (BRAM) |
| `0x0004_0000` | 64 KB | Frame buffer (BRAM) |
| `0x1000_0000` | 4 KB | GPIO (LEDs, switches, buttons) |
| `0x1000_1000` | 4 KB | UART |
| `0x1000_2000` | 4 KB | Timer |
| `0x1000_3000` | 4 KB | I²C master |
| `0x1000_4000` | 4 KB | SPI master |
| `0x1000_5000` | 4 KB | PWM (heaters) |
| `0x1000_6000` | 4 KB | Step/dir motion |
| `0x1000_7000` | 4 KB | XADC interface |
| `0x1000_8000` | 4 KB | Camera capture control |
| `0x1000_9000` | 4 KB | QSPI weight streamer |
| `0x1001_0000` | 4 KB | **Error counters / FDIR** |
| `0x1001_1000` | 4 KB | **Watchdog** |
| `0x1001_2000` | 4 KB | **Scrubber control** |
| `0x1001_3000` | 4 KB | **SEM IP interface** |

Bold entries are WP2. Reserve the addresses now so the map does not move later.

---

## Stage 3 — Peripherals (6–8 weeks, easiest first)

Each is a small module with its own Verilator testbench. Write the testbench
first — not for purity, but because debugging a peripheral through the core is
miserable.

| Order | Module | Drives | Difficulty |
|---|---|---|---|
| 1 | GPIO | LEDs, switches | Trivial — proves the bus |
| 2 | Timer | Control loop tick | Easy |
| 3 | PWM | Heaters, via SSR | Easy |
| 4 | I²C master | MLX90640, BME280, AS5600 | Moderate — clock stretching, multi-byte |
| 5 | SPI master | MAX6675, ADXL345, HX711 | Moderate |
| 6 | XADC wrapper | Thermistors, load cell | Easy — hard macro, DRP interface |
| 7 | Step/dir generator | 4 stepper axes | Moderate — needs a Bresenham or DDA rate generator |
| 8 | Camera capture | OV7670 | **Hardest. Leave until last.** |
| 9 | QSPI streamer | Model weights from flash | Moderate |

### On the BRAM budget

**337 KB total. This is the binding constraint on the whole design.**

| Item | Size |
|---|---|
| Instruction memory | 128 KB |
| Data memory | 128 KB |
| Frame buffer, 320×240 greyscale | 75 KB |
| **Subtotal** | **331 KB** |

That is already tight. Consequences:

- **No double buffering** at 320×240. Process each frame as it arrives, or drop
  to 160×120 (19 KB) if you need two buffers.
- **Model weights stream from QSPI**, layer by layer. They are never resident.
- Watch what the ECC and scrubber cost when you add them in WP2 — ECC widens
  every word by ~12%.

Measure utilisation after every peripheral. Discovering you are out of BRAM at
month 8 is a bad way to find out.

### On the camera

The OV7670 has an 8-bit parallel interface: `D[7:0]`, `PCLK`, `HREF`, `VSYNC`,
`XCLK`, plus SCCB (I²C-like) for configuration. Roughly 14 signals — one full
30-pin Pmod connector.

Two things routinely go wrong here:
1. **Timing.** `PCLK` is an input clock from the camera. Treat the capture FSM as
   a separate clock domain and cross into the system domain through a FIFO.
   Do not try to sample it with your system clock.
2. **SCCB.** Similar to I²C but not identical (no ACK on some transactions).
   Many published register sets are wrong. Get a known-good register dump and
   start from it.

Capture greyscale directly by taking the Y bytes from YUV422 and discarding UV.
This halves your bandwidth and skips the debayering problem entirely.

---

## Stage 4 — Software (in parallel from Stage 3)

**Bare-metal C first.** Add FreeRTOS only when the control loops genuinely need
scheduling — probably around the time the outer inspection loop appears.

```
firmware/
  crt0.S              startup, stack, BSS clear
  link.ld             linker script matching the memory map
  drivers/            one .c/.h per peripheral
  control/            PID loops, motion planner, WCET-critical paths
  inspection/         inference, classical CV monitor
  fdir/               fault handling, alert service routines
```

Keep the control loop's worst-case execution time measurable from day one — put
a GPIO pin high on entry and low on exit and watch it on a scope. WCET is an RQ1
metric, so you want it instrumented before you need it.

### Inference: build it in software first

**You almost certainly do not need a hardware accelerator.**

Layer-cadence inspection runs once every 30–60 seconds, not at 30 fps. A small
int8 CNN is a few million MACs. At roughly 5 cycles per MAC in software on a
50 MHz core, that is around **one second per inference** — against a 30-second
budget.

So: write it in C, measure it, and build a DSP48 accelerator **only if
measurement says you must**. This removes the single hardest custom block from
the critical path. If it does turn out to be too slow, the XC7S50's 120 DSP
slices are there.

---

## Stage 5 — Hardening (WP2, months 4–7)

### Adopted from Ibex — parameters, not code

```systemverilog
ibex_top #(
  .SecureIbex   (1),          // lockstep, hardened PC, shadow CSRs, RF ECC
  .RegFile      (RegFileFPGA), // FPGA-optimised, not FF or latch
  .RV32M        (RV32MFast),
  .RV32B        (RV32BNone),
  .ICache       (1),
  .ICacheECC    (1),
  .PMPEnable    (1)
) u_core (...);
```

Bring out `alert_minor_o` and `alert_major_internal_o` — these are the signals
your FDIR layer subscribes to.

### Built by you

| Module | What it does |
|---|---|
| `ecc_enc` / `ecc_dec` | SECDED (Hsiao) on your BRAMs. Formal-verify these — they are small and high-value. |
| `bram_scrubber` | Walks memory during idle cycles, correcting single-bit errors before they accumulate into doubles. |
| `voter3` | Generic 3-input majority voter with mismatch flag. Apply selectively to peripheral control FSMs. |
| `watchdog` | Staged: task → application → core → system reset. |
| `error_counters` | Memory-mapped aggregator: Ibex alerts, ECC corrections, voter mismatches, scrubber hits. **This is the RQ3 dataset.** |
| `safety_envelope` | Hardware interlocks — over-temperature, bounded retry, containment. Must be inhibitable only by hardware. |

**Every one of these is behind a build-time parameter.** The configuration
ladder (C0–C4) is only measurable if each mechanism can be switched off
independently.

### SEM IP

From the Vivado IP catalog: Soft Error Mitigation, which supports Spartan-7.
Wire the command interface to a dedicated UART. Detection, correction,
classification, and — the reason it matters — **error injection**, which is your
configuration-memory fault campaign without beam time.

**Caution:** SEM owns the ICAP primitive. Nothing else in your design can use
ICAP. Decide this early.

---

## Stage 6 — The configuration ladder

Build the same design five times, changing one thing at a time:

| Config | Ibex settings | Your additions |
|---|---|---|
| **C0** | `SecureIbex=0` | none |
| **C1** | `SecureIbex=0` + RF ECC | BRAM ECC, scrubber |
| **C2** | `SecureIbex=0` + RF ECC, hardened PC, shadow CSRs | C1 + voters on peripheral FSMs |
| **C3** | `SecureIbex=1` (adds lockstep) | C2 |
| **C4** | Triplicated core | C2 |

Record for each: LUT / FF / BRAM / DSP utilisation, Fmax, power
(`report_power` + USB meter), control-loop WCET margin, and fault-injection
results.

**C4 may not fit.** That is a result, not a failure — report it.

---

## Month-2 gate checklist

This is the go/no-go. Be strict with yourself; that is the entire point of
having it.

- [ ] Vivado, GCC, Verilator, FuseSoC all working
- [ ] Own Verilog blinks an LED on the Boolean Board
- [ ] `ibex_demo_system` ported; Ibex boots and prints over UART
- [ ] `riscv-arch-test` passes under RISCOF
- [ ] CI runs on every push
- [ ] Bus adapter interface frozen and documented
- [ ] Memory map allocated, including WP2 addresses
- [ ] Resource utilisation report — know how much fabric is already gone

If the first four are not done by end of month 2, the project re-scopes or
stops. That is what the gate is for.

---

## Where the real risks are

| Risk | Why | What to do |
|---|---|---|
| **BRAM exhaustion** | 337 KB is genuinely small once code, data, frame buffer and ECC overhead are counted | Track utilisation from Stage 3. Drop to 160×120 if needed. |
| **Camera capture** | Clock domain crossing plus fiddly SCCB configuration | Leave until last. Start from a known-good register dump. |
| **Timing closure with lockstep** | Doubling core logic makes routing harder | Start at 25 MHz. Raise only when everything works. |
| **SEM/ICAP conflict** | SEM owns the primitive exclusively | Decide early; do not plan any other ICAP use. |
| **Scope creep in peripherals** | Each one feels small; there are nine | Testbench first, then integrate. Never two unproven things at once. |

---

## First week, concretely

1. Start the Vivado download.
2. Clone `ibex-demo-system`, get it running in Verilator.
3. Download the Boolean Board master XDC from RealDigital.
4. Write a 10-line Verilog LED blinker, synthesise it, load it, see it blink.
5. Only then start reading the demo system's FPGA target.

Step 4 is the real milestone. Everything after it is incremental.
