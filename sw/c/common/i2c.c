#include "i2c.h"

#include "dev_access.h"

// Long enough for a byte at 100 kHz with a slow, stretching target.
#define I2C_TIMEOUT 100000

static int i2c_cmd(uint32_t base, uint32_t cmd) {
  DEV_WRITE(base + I2C_CMD_REG, cmd);
  for (uint32_t n = 0; n < I2C_TIMEOUT; n++) {
    uint32_t status = DEV_READ(base + I2C_STATUS_REG);
    if (!(status & I2C_STATUS_BUSY)) {
      return (status & I2C_STATUS_NACK) ? I2C_ERR_NACK : 0;
    }
  }
  return I2C_ERR_TIMEOUT;
}

// Release the bus after a failed transfer.
static int i2c_abort(uint32_t base, int err) {
  if (err != I2C_ERR_TIMEOUT) i2c_cmd(base, I2C_CMD_STOP);
  return err;
}

void i2c_init(uint32_t base, uint32_t prescale) { DEV_WRITE(base + I2C_PRESCALE_REG, prescale); }

int i2c_write(uint32_t base, uint8_t addr, const uint8_t *data, uint32_t len) {
  uint32_t last = len ? 0 : I2C_CMD_STOP;
  int err       = i2c_cmd(base, I2C_CMD_START | I2C_CMD_WRITE | last | (addr << 1));
  if (err) return i2c_abort(base, err);
  for (uint32_t i = 0; i < len; i++) {
    last = (i == len - 1) ? I2C_CMD_STOP : 0;
    err  = i2c_cmd(base, I2C_CMD_WRITE | last | data[i]);
    if (err) return i2c_abort(base, err);
  }
  return 0;
}

int i2c_read(uint32_t base, uint8_t addr, uint8_t *data, uint32_t len) {
  int err = i2c_cmd(base, I2C_CMD_START | I2C_CMD_WRITE | (addr << 1) | 1);
  if (err) return i2c_abort(base, err);
  for (uint32_t i = 0; i < len; i++) {
    uint32_t last = (i == len - 1) ? (I2C_CMD_NACK | I2C_CMD_STOP) : 0;
    err           = i2c_cmd(base, I2C_CMD_READ | last);
    if (err) return i2c_abort(base, err);
    data[i] = DEV_READ(base + I2C_RX_REG) & 0xFF;
  }
  if (len == 0) i2c_cmd(base, I2C_CMD_STOP);
  return 0;
}

int i2c_read_reg(uint32_t base, uint8_t addr, uint8_t reg, uint8_t *data, uint32_t len) {
  int err = i2c_cmd(base, I2C_CMD_START | I2C_CMD_WRITE | (addr << 1));
  if (err) return i2c_abort(base, err);
  err = i2c_cmd(base, I2C_CMD_WRITE | reg);
  if (err) return i2c_abort(base, err);
  return i2c_read(base, addr, data, len);  // starts with a repeated START
}
