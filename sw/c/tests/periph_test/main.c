// Peripheral test: timer, PWM, SPI, I2C and XADC, run on the whole system.
//
// Prints "PASS <block>" or "FAIL <block>: <reason>" per block over the UART,
// then "periph_test: ALL PASS" or "periph_test: FAILED".
//
// The simulation build (periph_test_sim) relies on the loopbacks in
// dv/verilator/top_verilator.sv: SPI MOSI drives MISO, PWM channels 0-7
// drive the GPIO inputs, an EEPROM-like I2C target answers at 0x50, and an
// XADC model returns fixed readings (45.0 C, 1.00 V, 1.80 V, 1.00 V). It
// halts the simulator when done.
//
// The board build (periph_test) needs a jumper from PMODA pin 1 (MOSI) to
// pin 2 (MISO). It skips the PWM measurement (the GPIO inputs are switches
// there). With nothing on the I2C pins it only checks that an empty address
// gets no ACK, which fails if SCL or SDA is stuck low. The XADC readings must
// be within the Spartan-7 operating ranges. Afterwards it keeps running: the timer interrupt toggles LED 4
// once a second and prints the tick count, and the RGB LEDs fade.

#include <stdbool.h>

#include "demo_system.h"
#include "dev_access.h"
#include "i2c.h"
#include "pwm.h"
#include "spi.h"
#include "timer.h"
#include "xadc.h"

static int failures;

static void putdec(uint32_t v) {
  char buf[11];
  int i = 0;
  do {
    buf[i++] = '0' + v % 10;
    v /= 10;
  } while (v);
  while (i) putchar(buf[--i]);
}

static void fail(const char *block, const char *why, uint32_t got, uint32_t expected) {
  puts("FAIL ");
  puts(block);
  puts(": ");
  puts(why);
  puts(" (got ");
  putdec(got);
  puts(", expected ");
  putdec(expected);
  puts(")\n");
  failures++;
}

static void pass(const char *block) {
  puts("PASS ");
  puts(block);
  putchar('\n');
}

static bool within(uint32_t got, uint32_t expected, uint32_t tol) {
  return got + tol >= expected && got <= expected + tol;
}

// ---------------------------------------------------------------- timer ---

#define TICK_CYCLES 5000
#define NUM_TICKS 11

static volatile uint32_t ticks;
static volatile uint32_t tick_cycle[NUM_TICKS];
static volatile uint32_t bad_cause;
static uint64_t next_cmp;
static uint64_t tick_period;

static void set_timecmp(uint64_t t) {
  DEV_WRITE(TIMER_BASE + TIMER_MTIMECMP_REG, -1);
  DEV_WRITE(TIMER_BASE + TIMER_MTIMECMPH_REG, t >> 32);
  DEV_WRITE(TIMER_BASE + TIMER_MTIMECMP_REG, t);
}

void tick_handler(void) __attribute__((interrupt));

void tick_handler(void) {
  if (ticks < NUM_TICKS) {
    tick_cycle[ticks] = get_mcycle();
  }
  if (get_mcause() != 0x80000007) {
    bad_cause++;
  }
  // Advance by a fixed step from the last compare, not from "now", so
  // interrupt latency does not accumulate.
  next_cmp += tick_period;
  set_timecmp(next_cmp);
  ticks++;
}

static void wait_cycles(uint32_t n) {
  uint32_t start = get_mcycle();
  while (get_mcycle() - start < n) {
  }
}

static void test_timer(void) {
  int before = failures;

  // mtime and mcycle both count the system clock.
  uint32_t t0 = (uint32_t)timer_read(), c0 = get_mcycle();
  wait_cycles(20000);
  uint32_t t1 = (uint32_t)timer_read(), c1 = get_mcycle();
  if (!within(t1 - t0, c1 - c0, 40)) {
    fail("timer", "mtime and mcycle disagree over 20000 cycles", t1 - t0, c1 - c0);
  }

  // Periodic interrupt: NUM_TICKS interrupts, TICK_CYCLES apart.
  install_exception_handler(7, &tick_handler);
  ticks = 0;
  bad_cause = 0;
  tick_period = TICK_CYCLES;
  next_cmp = timer_read() + TICK_CYCLES;
  set_timecmp(next_cmp);
  enable_interrupts(TIMER_IRQ);
  set_global_interrupt_enable(1);

  uint32_t start = get_mcycle();
  while (ticks < NUM_TICKS && get_mcycle() - start < 20 * NUM_TICKS * TICK_CYCLES) {
  }
  disable_interrupts(TIMER_IRQ);

  if (ticks < NUM_TICKS) {
    fail("timer", "too few interrupts", ticks, NUM_TICKS);
  } else {
    for (int i = 1; i < NUM_TICKS; i++) {
      uint32_t gap = tick_cycle[i] - tick_cycle[i - 1];
      if (!within(gap, TICK_CYCLES, 50)) {
        fail("timer", "interrupt spacing in cycles", gap, TICK_CYCLES);
        break;
      }
    }
    uint32_t span = tick_cycle[NUM_TICKS - 1] - tick_cycle[0];
    if (!within(span, (NUM_TICKS - 1) * TICK_CYCLES, 50)) {
      fail("timer", "cycles across all interrupts", span, (NUM_TICKS - 1) * TICK_CYCLES);
    }
  }
  if (bad_cause) {
    fail("timer", "interrupts with wrong mcause", bad_cause, 0);
  }

  // Masked: a due compare must not interrupt until mie.MTIE is set again.
  uint32_t seen = ticks;
  set_timecmp(timer_read() + 100);
  wait_cycles(2000);
  if (ticks != seen) {
    fail("timer", "interrupt taken while masked", ticks - seen, 0);
  }
  enable_interrupts(TIMER_IRQ);
  wait_cycles(200);
  disable_interrupts(TIMER_IRQ);
  if (ticks != seen + 1) {
    fail("timer", "pending interrupt not taken once unmasked", ticks - seen, 1);
  }

  if (failures == before) pass("timer");
}

// ------------------------------------------------------------------ PWM ---

#ifdef PERIPH_TEST_SIM
#define PWM_MAX 100  // period 101 cycles; 101 is prime, so the sampling
                     // loop sweeps every phase evenly
#define PWM_SAMPLES (101 * 100)

static void test_pwm(void) {
  int before = failures;
  static const uint32_t width[8] = {0, 25, 50, 75, 101, 10, 90, 200};
  uint32_t high[8] = {0};

  for (int i = 0; i < 8; i++) {
    set_pwm(PWM_FROM_ADDR_AND_INDEX(PWM_BASE, i), PWM_MAX, width[i]);
  }
  wait_cycles(1000);

  for (int n = 0; n < PWM_SAMPLES; n++) {
    uint32_t in = read_gpio(GPIO_IN);
    for (int i = 0; i < 8; i++) high[i] += (in >> i) & 1;
  }

  for (int i = 0; i < 8; i++) {
    uint32_t on = width[i] > PWM_MAX + 1 ? PWM_MAX + 1 : width[i];
    uint32_t expected = PWM_SAMPLES / (PWM_MAX + 1) * on;
    if (!within(high[i], expected, PWM_SAMPLES / 50)) {  // 2 %
      fail("pwm", "high samples on a channel", high[i], expected);
    }
  }

  for (int i = 0; i < 8; i++) {
    set_pwm(PWM_FROM_ADDR_AND_INDEX(PWM_BASE, i), 0, 0);
  }
  if (failures == before) pass("pwm");
}
#endif

// ------------------------------------------------------------------ SPI ---

static void test_spi(void) {
  int before = failures;
  spi_t spi;
  spi_init(&spi, SPI_FROM_BASE_ADDR(SPI0_BASE), 0);

  for (uint32_t v = 0; v < 256; v++) {
    int r = spi_xfer_byte(&spi, v, 10000);
    if (r < 0) {
      fail("spi", "no byte back (is PMODA pin 1 jumpered to pin 2?)", v, v);
      break;
    }
    if ((uint32_t)r != v) {
      fail("spi", "loopback byte differs", r, v);
      break;
    }
  }
  if (failures == before) pass("spi");
}

// ------------------------------------------------------------------ I2C ---

#define I2C_EEPROM 0x50  // simulation target
#define I2C_NOBODY 0x31  // no device at this address in sim or on the board

static void test_i2c(void) {
  int before = failures;
  i2c_init(I2C_BASE, I2C_PRESCALE(SYSCLK_FREQ, 400000));

  uint8_t buf[5];
  int err = i2c_write(I2C_BASE, I2C_NOBODY, buf, 0);
  if (err != I2C_ERR_NACK) fail("i2c", "empty address was ACKed (SDA stuck low?)", err, I2C_ERR_NACK);

#ifdef PERIPH_TEST_SIM
  // Pointer 0x40, then four data bytes; read them back with a repeated START.
  const uint8_t out[5] = {0x40, 0xDE, 0xAD, 0xBE, 0xEF};
  err = i2c_write(I2C_BASE, I2C_EEPROM, out, 5);
  if (err) fail("i2c", "write to 0x50", err, 0);
  err = i2c_read_reg(I2C_BASE, I2C_EEPROM, 0x40, buf, 4);
  if (err) fail("i2c", "read from 0x50", err, 0);
  for (int i = 0; i < 4 && !err; i++) {
    if (buf[i] != out[i + 1]) fail("i2c", "read-back byte differs", buf[i], out[i + 1]);
  }
  // The byte after the written ones still holds the target's fill pattern.
  err = i2c_read_reg(I2C_BASE, I2C_EEPROM, 0x44, buf, 1);
  if (err || buf[0] != (0x44 ^ 0x5A)) fail("i2c", "pattern byte at 0x44", buf[0], 0x44 ^ 0x5A);
#endif
  if (failures == before) pass("i2c");
}

// ----------------------------------------------------------------- XADC ---

static void check_range(const char *what, int32_t v, int32_t lo, int32_t hi) {
  if (v < lo || v > hi) fail("xadc", what, (uint32_t)v, (uint32_t)lo);
}

static void test_xadc(void) {
  int before = failures;

  // Wait for two fresh passes so every register holds a real sample.
  uint32_t s0 = xadc_scans(XADC_BASE), n = 0;
  while (xadc_scans(XADC_BASE) - s0 < 2) {
    if (++n > 100000) {
      fail("xadc", "SCANS not counting", xadc_scans(XADC_BASE), s0 + 2);
      return;
    }
  }

  int32_t t = xadc_temp_mc(XADC_BASE);
  uint32_t vint = xadc_supply_mv(XADC_BASE, XADC_VCCINT);
  uint32_t vaux = xadc_supply_mv(XADC_BASE, XADC_VCCAUX);
  uint32_t vbram = xadc_supply_mv(XADC_BASE, XADC_VCCBRAM);
#ifdef PERIPH_TEST_SIM
  // The model's fixed readings, through the conversion formulas.
  check_range("temperature (mC)", t, 44500, 45500);
  check_range("VCCINT (mV)", vint, 995, 1005);
  check_range("VCCAUX (mV)", vaux, 1795, 1805);
  check_range("VCCBRAM (mV)", vbram, 995, 1005);
#else
  // Spartan-7 recommended ranges (VCCINT and VCCBRAM 1.0 V, VCCAUX 1.8 V,
  // each +-5 %); the die should be between room temperature and 85 C.
  check_range("temperature (mC)", t, 10000, 85000);
  check_range("VCCINT (mV)", vint, 950, 1050);
  check_range("VCCAUX (mV)", vaux, 1710, 1890);
  check_range("VCCBRAM (mV)", vbram, 950, 1050);
#endif
  puts("xadc: ");
  putdec(t / 1000);
  puts(" C, VCCINT ");
  putdec(vint);
  puts(" mV, VCCAUX ");
  putdec(vaux);
  puts(" mV, VCCBRAM ");
  putdec(vbram);
  puts(" mV\n");
  if (failures == before) pass("xadc");
}

// ----------------------------------------------------------------- main ---

int main(void) {
  puts("periph_test: start\n");
  test_timer();
#ifdef PERIPH_TEST_SIM
  test_pwm();
#endif
  test_spi();
  test_i2c();
  test_xadc();
  puts(failures ? "periph_test: FAILED\n" : "periph_test: ALL PASS\n");

#ifdef PERIPH_TEST_SIM
  // The UART has no TX-empty flag: wait long enough to drain a full 128-byte
  // FIFO (10 bits x 434 cycles per byte) before stopping the simulator.
  wait_cycles(600000);
  sim_halt();
#else
  // Board: visible checks that keep running.
  ticks = 0;
  tick_period = SYSCLK_FREQ;  // one second
  next_cmp = timer_read() + tick_period;
  set_timecmp(next_cmp);
  enable_interrupts(TIMER_IRQ);

  uint32_t last = 0, level = 0;
  int step = 1;
  while (1) {
    if (ticks != last) {
      last = ticks;
      set_outputs(GPIO_OUT, (last & 1) << 4);
      puts("tick ");
      putdec(last);
      putchar('\n');
    }
    // Fade the RGB LEDs (PWM channels 0-5) up and down.
    for (int i = 0; i < 6; i++) {
      set_pwm(PWM_FROM_ADDR_AND_INDEX(PWM_BASE, i), 255, (i & 1) ? 255 - level : level);
    }
    level += step;
    if (level == 0 || level == 255) step = -step;
    wait_cycles(100000);
  }
#endif
  return 0;
}
