# Create (or reopen) a Vivado project for blinky so it can be inspected in the GUI.
#   vivado -mode gui -source open_gui.tcl
set here [file dirname [file normalize [info script]]]
set proj [file join $here vivado_proj blinky.xpr]

if {[file exists $proj]} {
  open_project $proj
} else {
  create_project blinky [file join $here vivado_proj] -part xc7s50csga324-1
  add_files -norecurse [file join $here blinky.sv]
  add_files -fileset constrs_1 -norecurse [file join $here blinky.xdc]
  set_property top blinky [current_fileset]
}
