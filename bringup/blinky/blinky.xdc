# Subset of data/pins_boolean.xdc used by the blinky bring-up design.
create_clock -add -name gclk -period 10.00 -waveform {0 5} [get_ports { IO_CLK }];
set_property -dict {PACKAGE_PIN F14 IOSTANDARD LVCMOS33} [get_ports {IO_CLK}]
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

set_property -dict {PACKAGE_PIN V2 IOSTANDARD LVCMOS33} [get_ports {SW[0]}]
set_property -dict {PACKAGE_PIN G1 IOSTANDARD LVCMOS33} [get_ports {LED[0]}]
set_property -dict {PACKAGE_PIN G2 IOSTANDARD LVCMOS33} [get_ports {LED[1]}]
