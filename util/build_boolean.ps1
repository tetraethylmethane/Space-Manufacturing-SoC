# Build the Boolean Board bitstream with Windows Vivado from the project FuseSoC generated in WSL.
# Run util/setup_synth_boolean.sh (WSL) first. Program afterwards with: build_boolean.ps1 -Program
param([switch]$Program)
$ErrorActionPreference = 'Stop'
$vivado = 'C:\Xilinx\2025.1\Vivado\bin\vivado.bat'
$work   = Join-Path $PSScriptRoot '..\build\lowrisc_ibex_demo_system_0\synth_boolean-vivado'
$name   = 'lowrisc_ibex_demo_system_0'
Set-Location $work

if ($Program) {
  & $vivado -nojournal -log program.log -mode batch -source "${name}_pgm.tcl" -tclargs xc7s50csga324-1 "$name.bit"
  exit $LASTEXITCODE
}

if (-not (Test-Path "$name.xpr")) {
  & $vivado -nojournal -log project.log -mode batch -source "$name.tcl"
  if ($LASTEXITCODE -ne 0) { throw 'project creation failed' }
}
& $vivado -nojournal -log build.log -mode batch -source "${name}_run.tcl" "$name.xpr"
exit $LASTEXITCODE
