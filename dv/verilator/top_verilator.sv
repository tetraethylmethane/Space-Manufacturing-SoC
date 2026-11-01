// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// This is the top level that connects the demo system to the virtual devices.
module top_verilator #(
  parameter logic [31:0] MemSize  = 128 * 1024,
  parameter logic [31:0] MemStart = soc_pkg::IRAM_BASE
) (input logic clk_i, rst_ni);

  localparam ClockFrequency = 50_000_000;
  localparam BaudRate       = 115_200;

  logic uart_sys_rx, uart_sys_tx;

  // Test loopbacks: SPI MOSI drives MISO, and PWM channels 0-7 drive the GPIO
  // inputs so firmware can measure duty cycle (sw/c/tests/periph_test). An
  // EEPROM-like I2C target answers at 0x50 on an open-drain bus.
  logic        spi_loop;
  logic [11:0] pwm;
  logic        unused_pwm;
  assign unused_pwm = ^pwm[11:8];

  logic i2c_scl_oe, i2c_sda_oe, tgt_scl_low, tgt_sda_low, i2c_scl, i2c_sda;
  assign i2c_scl = ~(i2c_scl_oe | tgt_scl_low);
  assign i2c_sda = ~(i2c_sda_oe | tgt_sda_low);

  i2c_target #(.Addr(7'h50)) u_i2c_target (
    .clk_i,
    .rst_ni,
    .scl_i    (i2c_scl),
    .sda_i    (i2c_sda),
    .scl_low_o(tgt_scl_low),
    .sda_low_o(tgt_sda_low)
  );

  // Instantiating the Ibex Demo System.
  ibex_demo_system #(
    .GpiWidth       ( 8                   ),
    .GpoWidth       ( 16                  ),
    .PwmWidth       ( 12                  ),
    .ClockFrequency ( ClockFrequency      ),
    .BaudRate       ( BaudRate            ),
    .RegFile        ( ibex_pkg::RegFileFF ),
    .MemSize        ( MemSize             ),
    .MemStart       ( MemStart            )
  ) u_ibex_demo_system (
    //Input
    .clk_sys_i (clk_i),
    .rst_sys_ni(rst_ni),
    .uart_rx_i (uart_sys_rx),

    //Output
    .uart_tx_o(uart_sys_tx),

    // tie off JTAG
    .trst_ni(1'b1),
    .tms_i  (1'b0),
    .tck_i  (1'b0),
    .td_i   (1'b0),
    .td_o   (    ),

    // Remaining IO
    .gp_i      (pwm[7:0]),
    .gp_o      ( ),
    .pwm_o     (pwm),
    .spi_rx_i  (spi_loop),
    .spi_tx_o  (spi_loop),
    .spi_sck_o ( ),
    .i2c_scl_i   (i2c_scl),
    .i2c_scl_oe_o(i2c_scl_oe),
    .i2c_sda_i   (i2c_sda),
    .i2c_sda_oe_o(i2c_sda_oe)
  );

  // Virtual UART
  uartdpi #(
    .BAUD(BaudRate),
    .FREQ(ClockFrequency)
  ) u_uartdpi (
    .clk_i,
    .rst_ni,
    .active (1'b1       ),
    .tx_o   (uart_sys_rx),
    .rx_i   (uart_sys_tx)
  );
endmodule
