/* Linker script for riscv-arch-test on the Ibex demo system.
 *
 * Matches the sim_riscof FuseSoC target: 4 MiB of RAM at 0x00400000 (some
 * tests are larger than the 128 KiB the FPGA build has). Ibex boots at
 * 0x00400080, the boot address plus 0x80. That word holds a jump to the test
 * at 0x00401000, leaving the first 4 KiB free for the trap vector table the
 * test framework may install at mtvec.
 *
 * The image must start exactly at the RAM base: the simulator's --meminit
 * loads an ELF relative to its lowest address.
 */
OUTPUT_ARCH("riscv")
ENTRY(rvtest_entry_point)

MEMORY
{
  ram : ORIGIN = 0x00400000, LENGTH = 4M
}

SECTIONS
{
  .boot 0x00400000 :
  {
    LONG(0)
    . = 0x80;
    LONG(0x7810006F)   /* jal x0, +0xF80: 0x00400080 -> 0x00401000 */
  } > ram

  .text.init 0x00401000 : { *(.text.init) } > ram
  . = ALIGN(0x100);
  .text : { *(.text) } > ram
  . = ALIGN(0x100);
  .data : { *(.data) } > ram
  .data.string : { *(.data.string) } > ram
  .bss : { *(.bss) } > ram
  _end = .;
}
