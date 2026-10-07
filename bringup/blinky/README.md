# Blinky

A minimal design that checks Vivado, the part number, the pin constraints and the clock before the CPU is involved. LED0 blinks at about 1.5 Hz, and LED1 follows SW0.

```powershell
cd C:\work\space-am-soc\bringup\blinky

# Build only
C:\Xilinx\2025.1\Vivado\bin\vivado.bat -mode batch -source build.tcl

# Build and program the board
C:\Xilinx\2025.1\Vivado\bin\vivado.bat -mode batch -source build.tcl -tclargs program

# Open as a project in the Vivado GUI
C:\Xilinx\2025.1\Vivado\bin\vivado.bat -mode gui -source open_gui.tcl
```

Outputs go to `out/`. The bitstream is `out/blinky.bit`, with utilisation and timing reports next to it.
