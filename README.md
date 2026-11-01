# Space Manufacturing SoC

A fault-tolerant RISC-V system-on-chip to control an autonomous, closed-loop 3D printer designed for in-space manufacturing.

This is my capstone research project at Thapar Institute of Engineering and Technology, supervised by Dr. Sujit Kumar Patel. The proposal in [doc/proposal](doc/proposal/) explains the motivation, the research questions and the full plan.

## Hardware

| | |
|---|---|
| Board | RealDigital Boolean Board |
| FPGA | AMD Spartan-7 XC7S50 (`xc7s50csga324-1`) |
| CPU | lowRISC Ibex (RV32IMC) |
| Tools | Vivado 2025.1, RISC-V GCC, FuseSoC, Verilator |

The SoC starts from lowRISC's [ibex-demo-system](https://github.com/lowRISC/ibex-demo-system), which already has a Boolean Board target. The radiation-tolerance features (ECC, scrubbing, lockstep, watchdogs) and the printer peripherals will be added on top of it.

## Status

Phase 1 of 6, working towards the month-2 review.

- [x] Toolchain set up; LED test design running on the board
- [x] Ibex bitstream for the Boolean Board, with hello-world in on-chip RAM
- [x] Ibex running hello-world in Verilator simulation
- [x] Ibex printing over UART on the Boolean Board (115,200 baud)
- [x] `riscv-arch-test` 3.9.1 passing under RISCOF against Sail (92/92: I, M, C, Zifencei, privilege)
- [x] CI running on every push (firmware, simulator, hello-world, block and peripheral tests)
- [x] Bus interface and memory map frozen ([spec](doc/bus-and-memory-map.md))
- [x] Timer, PWM and SPI tested: block testbenches and a whole-system firmware test, both in CI ([testing](doc/testing.md))
- [x] I²C master written and tested the same way, with clock stretching
- [ ] Timer, PWM, SPI and I²C checked on the board

## Repository layout

```
bringup/     small designs for checking the board and tools (start here)
data/        pin constraints for each supported board
doc/         project documentation, proposal and upstream notes
dv/          Verilator testbenches: verilator/ the whole system, blocks/ one
             peripheral each, riscof/ the compliance setup
rtl/         SoC RTL: fpga/ holds board top levels, system/ the SoC
sw/c/        firmware (C), built with CMake; tests/ holds the peripheral test
util/        build, programming and helper scripts
vendor/      vendored lowRISC IP (Ibex, primitives); don't edit directly
```

## Getting started

[doc/getting-started.md](doc/getting-started.md) covers installing the tools, building the firmware and bitstream, and programming the board.

To run the compliance tests, install RISCOF (`pip install riscof`), put the Sail RISC-V simulator in `~/tools/sail` and clone `riscv-arch-test` at tag 3.9.1 into `~/riscv-arch-test`. Then run `util/run_riscof.sh`. It builds a simulator with 4 MiB of RAM on first use and writes a report to `~/space-am-soc-riscof/report.html`. Pass a sub-suite such as `rv32i_m/I` to run only part of it.

## Documentation

- [Getting started](doc/getting-started.md): setup, build and programming
- [Build guide](doc/build-guide.md): the staged plan for building and hardening the SoC
- [Bus interface and memory map](doc/bus-and-memory-map.md): the frozen contract every block is written against
- [Testing](doc/testing.md): block testbenches, the peripheral test, and what to check on the board
- [Research proposal](doc/proposal/proposal.pdf), with LaTeX sources in the same folder
- [Upstream ibex-demo-system README](doc/ibex-demo-system.md)

## License

Apache License 2.0, inherited from ibex-demo-system. See [LICENSE](LICENSE). Vendored IP under `vendor/` keeps its original licenses.
