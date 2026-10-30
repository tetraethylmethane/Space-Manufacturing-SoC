// Target macros for riscv-arch-test on the Ibex demo system (Verilator).
//
// At the end of a test the signature is printed through the simulator control
// block (0x20000) as one 8-digit hex word per line, which is the format RISCOF
// compares, and the simulation is stopped by writing 1 to 0x20008.

#ifndef _COMPLIANCE_MODEL_H
#define _COMPLIANCE_MODEL_H

#define SIM_CTRL_BASE 0x20000

#define RVMODEL_DATA_SECTION

#define RVMODEL_HALT                                                          \
  la t0, begin_signature;                                                     \
  la t1, end_signature;                                                       \
  li t2, SIM_CTRL_BASE;                                                       \
11:                                                                           \
  bgeu t0, t1, 15f;                                                           \
  lw t3, 0(t0);                                                               \
  li t4, 8;                                                                   \
12:                                                                           \
  srli t5, t3, 28;                                                            \
  slli t3, t3, 4;                                                             \
  li t6, 10;                                                                  \
  blt t5, t6, 13f;                                                            \
  addi t5, t5, 39;                                                            \
13:                                                                           \
  addi t5, t5, 48;                                                            \
  sw t5, 0(t2);                                                               \
  addi t4, t4, -1;                                                            \
  bnez t4, 12b;                                                               \
  li t5, 10;                                                                  \
  sw t5, 0(t2);                                                               \
  addi t0, t0, 4;                                                             \
  j 11b;                                                                      \
15:                                                                           \
  li t5, 1;                                                                   \
  sw t5, 8(t2);                                                               \
16:                                                                           \
  j 16b;

#define RVMODEL_BOOT

#define RVMODEL_DATA_BEGIN                                                    \
  RVMODEL_DATA_SECTION                                                        \
  .align 4;                                                                   \
  .global begin_signature; begin_signature:

#define RVMODEL_DATA_END                                                      \
  .align 4;                                                                   \
  .global end_signature; end_signature:

#define RVMODEL_IO_INIT
#define RVMODEL_IO_WRITE_STR(_R, _STR)
#define RVMODEL_IO_CHECK()
#define RVMODEL_IO_ASSERT_GPR_EQ(_S, _R, _I)
#define RVMODEL_IO_ASSERT_SFPR_EQ(_F, _R, _I)
#define RVMODEL_IO_ASSERT_DFPR_EQ(_D, _R, _I)

#define RVMODEL_SET_MSW_INT
#define RVMODEL_CLEAR_MSW_INT
#define RVMODEL_CLEAR_MTIMER_INT
#define RVMODEL_CLEAR_MEXT_INT

#endif // _COMPLIANCE_MODEL_H
