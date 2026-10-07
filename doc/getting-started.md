# Getting started

The tools are split across two environments:

- **Windows** runs Vivado: synthesis, bitstreams and board programming.
- **WSL (Ubuntu 24.04)** runs everything else: the RISC-V compiler, FuseSoC and Verilator.

Keep the repository outside OneDrive or any other synced folder, because sync interferes with Vivado builds. These notes assume `C:\work\space-am-soc` (`/mnt/c/work/space-am-soc` from WSL).

## 1. One-time setup

**Windows**

- Install Vivado ML Standard 2025.1, which is free and covers the XC7S50.
- If Vivado can't see the board, install the cable drivers from an Administrator prompt:
  `C:\Xilinx\2025.1\data\xicom\cable_drivers\nt64\install_drivers_wrapper.bat`

**WSL**

```bash
sudo apt update
sudo apt install -y verilator srecord python3-pip libelf-dev pkg-config cmake
# If apt hangs, plain HTTP may be blocked on your network. Switch to an HTTPS mirror:
#   sudo sed -i 's#http://\(archive\|security\).ubuntu.com/ubuntu/\?#https://mirrors.edge.kernel.org/ubuntu/#' /etc/apt/sources.list.d/ubuntu.sources

# RISC-V GCC. 20250710-1 is the last lowRISC release that ships GCC.
mkdir -p ~/tools && cd ~/tools
curl -LO https://github.com/lowRISC/lowrisc-toolchains/releases/download/20250710-1/lowrisc-toolchain-gcc-rv32imcb-x86_64-20250710-1.tar.xz
tar -xf lowrisc-toolchain-gcc-rv32imcb-x86_64-20250710-1.tar.xz
ln -s ~/tools/lowrisc-toolchain-gcc-rv32imcb-x86_64-20250710-1 ~/tools/rv32
echo 'export PATH="$HOME/tools/rv32/bin:$HOME/.local/bin:$PATH"' >> ~/.bashrc

# FuseSoC and Python dependencies
cd /mnt/c/work/space-am-soc
./util/setup_wsl_python.sh
```

## 2. Check the board

Before involving the CPU, build and load the LED test in [bringup/blinky](../bringup/blinky/). If LED0 blinks, the tools, part and pin constraints are all correct.

## 3. Simulate

Run firmware on the RTL in Verilator before spending half an hour on a bitstream.

```bash
# WSL
./util/build_sw.sh      # if you haven't built the firmware yet
./util/build_sim.sh     # compile the simulator (first run takes a few minutes)
./util/run_sim.sh       # run hello_world for 60 s and print the UART output
```

You should see `Hello World! 00000001` and so on, one line per timer tick. The simulator runs at roughly 0.7 million cycles a second, so each tick takes about 7 s.

To run a different program for a different time, pass them as arguments: `./util/run_sim.sh path/to/elf 120`. The full logs are in `~/space-am-soc-sim/run/`.

## 4. Build the SoC

The firmware is compiled into the bitstream's on-chip RAM, so the CPU starts running it as soon as the board is programmed. Neither JTAG nor OpenOCD is needed.

```bash
# WSL: compile the firmware and generate the Vivado project
./util/build_sw.sh
./util/setup_synth_boolean.sh
```

```powershell
# Windows: build the bitstream (expect 30-40 minutes)
powershell -ExecutionPolicy Bypass -File C:\work\space-am-soc\util\build_boolean.ps1
```

The bitstream is written to `build\lowrisc_ibex_demo_system_0\synth_boolean-vivado\lowrisc_ibex_demo_system_0.bit`.

If you change only the firmware, rerun all three steps. The RAM contents are fixed at synthesis time.

## 5. Program and run

Program the board with either of these:

- `build_boolean.ps1 -Program`
- In Vivado: **Hardware Manager → Open target → Auto Connect**, then right-click `xc7s50_0` and choose **Program Device**.

Then open the board's COM port (see Device Manager) at **115200 baud, 8N1**. You should see:

```
Hello World! 0000001A   Input Value: 00000000
```

On the board, the green LEDs step along and the RGB LEDs fade. The switches change the input value, and the middle button resets the CPU.

## Script reference

| Script | Where | What it does |
|---|---|---|
| `util/setup_wsl_python.sh` | WSL | Installs FuseSoC and the Python dependencies |
| `util/build_sw.sh` | WSL | Compiles the firmware and writes `demo.vmem` |
| `util/bin2vmem.py` | WSL | Converts a binary to `.vmem` (replaces `srec_cat`) |
| `util/build_sim.sh` | WSL | Builds the Verilator simulator |
| `util/run_sim.sh` | WSL | Runs a firmware ELF in simulation and shows the UART output |
| `util/setup_synth_boolean.sh` | WSL | Generates the Vivado project with FuseSoC |
| `util/build_boolean.ps1` | Windows | Builds the bitstream; `-Program` loads it onto the board |
