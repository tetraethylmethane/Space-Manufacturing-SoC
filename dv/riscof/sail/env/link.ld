OUTPUT_ARCH( "riscv" )
ENTRY(sail_reset)

SECTIONS
{
  /* As on Ibex, keep the start of RAM free: the test framework copies its
     trap trampoline to the mtvec base when mtvec cannot be moved. The reset
     stub sits well past the trampoline. */
  .text.reset 0x80000800 : { *(.text.reset) }
  .text.init 0x80001000 : { *(.text.init) }
  . = ALIGN(0x1000);
  .tohost : { *(.tohost) }
  . = ALIGN(0x1000);
  .text : { *(.text) }
  . = ALIGN(0x1000);
  .data : { *(.data) }
  .data.string : { *(.data.string)}
  .bss : { *(.bss) }
  _end = .;
}

