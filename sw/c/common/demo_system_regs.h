// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef DEMO_SYSTEM_REGS_H__
#define DEMO_SYSTEM_REGS_H__

// Base addresses from the frozen memory map (doc/bus-and-memory-map.md,
// rtl/system/soc_pkg.sv). Change all three places together.
#define GPIO_BASE 0x10000000

#define UART0_BASE 0x10001000

#define TIMER_BASE 0x10002000

#define I2C_BASE 0x10003000

#define SPI0_BASE 0x10004000

#define PWM_BASE 0x10005000

#define XADC_BASE 0x10007000

// Verilator only: character output and $finish.
#define SIM_CTRL_BASE 0x1000F000
#define SIM_CTRL_OUT 0x0
#define SIM_CTRL_CTRL 0x8

#endif
