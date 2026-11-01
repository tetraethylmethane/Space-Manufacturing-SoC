// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// This is the top level SystemVerilog file that connects the IO on the board to the Ibex Demo System.
module top_boolean (
  // These inputs are defined in data/pins_boolean.xdc
  input               IO_CLK,
  input               IO_RST,
  input  [15:0]       SW,
  input  [3:1]        BTN,
  output [15:0]       LED,
  output [5:0]        RGB_LED,
  input               UART_RX,
  output              UART_TX,
  output              SPI_MOSI,
  input               SPI_MISO,
  output              SPI_SCK,
  inout               I2C_SCL,
  inout               I2C_SDA
);
  parameter SRAMInitFile = "";

  logic clk_sys, rst_sys_n;
  logic i2c_scl_oe, i2c_sda_oe;

  // I2C pads are open drain: pull low or let the pull-up win.
  assign I2C_SCL = i2c_scl_oe ? 1'b0 : 1'bz;
  assign I2C_SDA = i2c_sda_oe ? 1'b0 : 1'bz;

  // Instantiating the Ibex Demo System.
  ibex_demo_system #(
    .GpiWidth(20),
    .GpoWidth(16),
    .PwmWidth(6),
    .SRAMInitFile(SRAMInitFile)
  ) u_ibex_demo_system (
    //input
    .clk_sys_i(clk_sys),
    .rst_sys_ni(rst_sys_n),
    .gp_i({SW, BTN}),
    .uart_rx_i(UART_RX),

    //output
    .gp_o(LED),
    .pwm_o(RGB_LED),
    .uart_tx_o(UART_TX),

    .spi_rx_i(SPI_MISO),
    .spi_tx_o(SPI_MOSI),
    .spi_sck_o(SPI_SCK),

    .i2c_scl_i(I2C_SCL),
    .i2c_scl_oe_o(i2c_scl_oe),
    .i2c_sda_i(I2C_SDA),
    .i2c_sda_oe_o(i2c_sda_oe),

    .trst_ni(1'b1),
    .tms_i(),
    .tck_i(),
    .td_i(),
    .td_o()
  );

  logic IO_RST_N;
  assign IO_RST_N = ~IO_RST;

  // Generating the system clock and reset for the FPGA.
  // Boolean has a 100 MHz clock.
  clkgen_xil7series clkgen(
    .IO_CLK,
    .IO_RST_N,
    .clk_sys,
    .rst_sys_n
  );

endmodule
