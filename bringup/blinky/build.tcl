# Non-project Vivado flow for the blinky bring-up design.
#   Build:   vivado -mode batch -source build.tcl
#   Program: vivado -mode batch -source build.tcl -tclargs program
set here [file dirname [file normalize [info script]]]
set out  [file join $here out]
file mkdir $out

read_verilog -sv [file join $here blinky.sv]
read_xdc         [file join $here blinky.xdc]

synth_design -top blinky -part xc7s50csga324-1
opt_design
place_design
route_design

report_utilization    -file [file join $out utilization.rpt]
report_timing_summary -file [file join $out timing.rpt]
write_bitstream -force [file join $out blinky.bit]

if {[lindex $argv 0] eq "program"} {
  open_hw_manager
  connect_hw_server
  open_hw_target
  set dev [lindex [get_hw_devices xc7s50*] 0]
  current_hw_device $dev
  set_property PROGRAM.FILE [file join $out blinky.bit] $dev
  program_hw_devices $dev
  close_hw_manager
}
