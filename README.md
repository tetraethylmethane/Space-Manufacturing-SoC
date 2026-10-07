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
- [ ] Ibex confirmed printing over UART on hardware
- [ ] `riscv-arch-test` passing under RISCOF
- [ ] CI running on every push
- [ ] Bus interface and memory map frozen

## Repository layout

```
bringup/     small designs for checking the board and tools (start here)
data/        pin constraints for each supported board
doc/         project documentation, proposal and upstream notes
dv/          Verilator simulation testbench
rtl/         SoC RTL: fpga/ holds board top levels, system/ the SoC
sw/c/        firmware (C), built with CMake
util/        build, programming and helper scripts
vendor/      vendored lowRISC IP (Ibex, primitives); don't edit directly
```

## Getting started

[doc/getting-started.md](doc/getting-started.md) covers installing the tools, building the firmware and bitstream, and programming the board.

## Documentation

- [Getting started](doc/getting-started.md): setup, build and programming
- [Build guide](doc/build-guide.md): the staged plan for building and hardening the SoC
- [Research proposal](doc/proposal/proposal.pdf), with LaTeX sources in the same folder
- [Upstream ibex-demo-system README](doc/ibex-demo-system.md)

## License

Apache License 2.0, inherited from ibex-demo-system. See [LICENSE](LICENSE). Vendored IP under `vendor/` keeps its original licenses.
