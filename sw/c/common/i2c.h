#ifndef I2C_H__
#define I2C_H__

#include <stdint.h>

// Register offsets from I2C_BASE (doc/bus-and-memory-map.md).
#define I2C_PRESCALE_REG 0x0
#define I2C_CMD_REG 0x4
#define I2C_STATUS_REG 0x8
#define I2C_RX_REG 0xC

// CMD bits. One command runs START, then WRITE or READ, then STOP, skipping
// any that are not set.
#define I2C_CMD_START (1 << 8)
#define I2C_CMD_STOP (1 << 9)
#define I2C_CMD_WRITE (1 << 10)
#define I2C_CMD_READ (1 << 11)
#define I2C_CMD_NACK (1 << 12)  // with READ: NACK the byte (last of a read)

#define I2C_STATUS_BUSY (1 << 0)
#define I2C_STATUS_NACK (1 << 1)

// Quarter-period prescale for a given SCL rate.
#define I2C_PRESCALE(sysclk, scl_hz) ((sysclk) / (4 * (scl_hz)))

// Error codes. Functions return 0 on success.
#define I2C_ERR_NACK -1     // no ACK from the target
#define I2C_ERR_TIMEOUT -2  // controller still busy (SCL held low?)

void i2c_init(uint32_t base, uint32_t prescale);

// Write `len` bytes to the 7-bit address `addr`: START, address, data, STOP.
int i2c_write(uint32_t base, uint8_t addr, const uint8_t *data, uint32_t len);

// Read `len` bytes from `addr`: START, address, data (last one NACKed), STOP.
int i2c_read(uint32_t base, uint8_t addr, uint8_t *data, uint32_t len);

// Register read, the usual sensor pattern: write `reg`, repeated START, read.
int i2c_read_reg(uint32_t base, uint8_t addr, uint8_t reg, uint8_t *data, uint32_t len);

#endif  // I2C_H__
