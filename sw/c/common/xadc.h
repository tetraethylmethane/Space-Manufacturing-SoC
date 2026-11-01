#ifndef XADC_H__
#define XADC_H__

#include <stdint.h>

#include "dev_access.h"

// Register offsets from XADC_BASE (doc/bus-and-memory-map.md). Read-only.
#define XADC_TEMP 0x00
#define XADC_VCCINT 0x04
#define XADC_VCCAUX 0x08
#define XADC_VCCBRAM 0x0C
#define XADC_VPVN 0x10
#define XADC_FLAGS 0x14
#define XADC_SCANS 0x18

// The 12-bit conversion result sits in bits [15:4].
static inline uint32_t xadc_code(uint32_t base, uint32_t reg) {
  return (DEV_READ(base + reg) >> 4) & 0xFFF;
}

// Die temperature in millidegrees Celsius: code * 503.975 / 4096 - 273.15.
static inline int32_t xadc_temp_mc(uint32_t base) {
  return (int32_t)((xadc_code(base, XADC_TEMP) * 503975u) / 4096u) - 273150;
}

// Supply voltage in millivolts: code * 3 V / 4096. For VCCINT, VCCAUX, VCCBRAM.
static inline uint32_t xadc_supply_mv(uint32_t base, uint32_t reg) {
  return (xadc_code(base, reg) * 3000u) / 4096u;
}

// Passes the block has made over all registers; use it to wait for fresh data.
static inline uint32_t xadc_scans(uint32_t base) { return DEV_READ(base + XADC_SCANS); }

#endif  // XADC_H__
