// SoC-wide definitions: the device bus interface and the address map.
//
// Both are frozen as of the month-2 gate (see doc/bus-and-memory-map.md).
// Change them only through a written decision in that document.
package soc_pkg;

  // ---------------------------------------------------------------------------
  // Device bus
  // ---------------------------------------------------------------------------
  // What every device sees. A device answers each request with rvalid exactly
  // one cycle later, for reads and writes alike; there are no wait states.
  // rdata is only looked at for reads. err turns the access into a load or
  // store access fault in the core.

  typedef struct packed {
    logic        req;    // access this cycle
    logic [31:0] addr;   // byte address, full 32 bits
    logic        we;     // 1 = write
    logic [3:0]  be;     // byte enables, for writes
    logic [31:0] wdata;
  } bus_req_t;

  typedef struct packed {
    logic        rvalid; // the cycle after req
    logic [31:0] rdata;
    logic        err;
  } bus_rsp_t;

  // ---------------------------------------------------------------------------
  // Address map
  // ---------------------------------------------------------------------------
  // Each region is a power-of-two window aligned to its size, so a device is
  // selected with (addr & ~(SIZE - 1)) == BASE. A window may be larger than
  // what is populated in it; see the document for current population.

  // Memory
  localparam logic [31:0] IRAM_BASE     = 32'h0000_0000;  // boot address
  localparam logic [31:0] IRAM_SIZE     = 32'h0002_0000;  // 128 KiB
  localparam logic [31:0] DRAM_BASE     = 32'h0002_0000;
  localparam logic [31:0] DRAM_SIZE     = 32'h0002_0000;  // 128 KiB
  localparam logic [31:0] FBUF_BASE     = 32'h0004_0000;
  localparam logic [31:0] FBUF_SIZE     = 32'h0002_0000;  // 128 KiB window, 75 KiB used

  // Peripherals, 4 KiB each
  localparam logic [31:0] PERIPH_SIZE   = 32'h0000_1000;
  localparam logic [31:0] GPIO_BASE     = 32'h1000_0000;
  localparam logic [31:0] UART_BASE     = 32'h1000_1000;
  localparam logic [31:0] TIMER_BASE    = 32'h1000_2000;
  localparam logic [31:0] I2C_BASE      = 32'h1000_3000;
  localparam logic [31:0] SPI_BASE      = 32'h1000_4000;
  localparam logic [31:0] PWM_BASE      = 32'h1000_5000;
  localparam logic [31:0] MOTION_BASE   = 32'h1000_6000;
  localparam logic [31:0] XADC_BASE     = 32'h1000_7000;
  localparam logic [31:0] CAMERA_BASE   = 32'h1000_8000;
  localparam logic [31:0] QSPI_BASE     = 32'h1000_9000;
  localparam logic [31:0] SIM_CTRL_BASE = 32'h1000_F000;  // simulation only

  // Fault-tolerance blocks (WP2), reserved now so the map does not move
  localparam logic [31:0] FDIR_BASE     = 32'h1001_0000;  // error counters
  localparam logic [31:0] WDOG_BASE     = 32'h1001_1000;
  localparam logic [31:0] SCRUB_BASE    = 32'h1001_2000;
  localparam logic [31:0] SEM_BASE      = 32'h1001_3000;

  // Debug module (RISC-V debug spec; JTAG access only)
  localparam logic [31:0] DEBUG_BASE    = 32'h1A11_0000;
  localparam logic [31:0] DEBUG_SIZE    = 32'h0001_0000;  // 64 KiB

endpackage
