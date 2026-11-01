// Block test for the I2C controller at I2C_BASE, against two behavioural
// targets on one bus: an EEPROM-like device at 0x50 and a slow one at 0x51
// that stretches the clock. Registers: +0 PRESCALE, +4 CMD, +8 STATUS, +C RX.
module tb_i2c;
  logic        clk = 1'b0, rst_n = 1'b0;
  logic        req = 1'b0, we = 1'b0;
  logic [3:0]  be = '0;
  logic [31:0] addr = '0, wdata = '0;
  logic        rvalid, err;
  logic [31:0] rdata;

  assign err = 1'b0;  // the I2C block has no err output

  always #10 clk = ~clk;

  `include "bus_tasks.svh"

  localparam logic [31:0] PRESCALE = soc_pkg::I2C_BASE + 32'h0;
  localparam logic [31:0] CMD      = soc_pkg::I2C_BASE + 32'h4;
  localparam logic [31:0] STATUS   = soc_pkg::I2C_BASE + 32'h8;
  localparam logic [31:0] RX       = soc_pkg::I2C_BASE + 32'hC;

  localparam logic [31:0] START = 32'h100, STOP = 32'h200, WR = 32'h400,
                          RD = 32'h800, NACK = 32'h1000;
  localparam int          Div = 8;         // quarter period used for most tests
  localparam int          StretchClk = 60;

  // Open-drain bus: a line is low if anyone pulls it low.
  logic m_scl_oe, m_sda_oe, t0_scl, t0_sda, t1_scl, t1_sda;
  wire  scl = ~(m_scl_oe | t0_scl | t1_scl);
  wire  sda = ~(m_sda_oe | t0_sda | t1_sda);

  i2c_host dut (
    .clk_i          (clk),
    .rst_ni         (rst_n),
    .device_req_i   (req),
    .device_addr_i  (addr),
    .device_we_i    (we),
    .device_be_i    (be),
    .device_wdata_i (wdata),
    .device_rvalid_o(rvalid),
    .device_rdata_o (rdata),
    .scl_i          (scl),
    .scl_oe_o       (m_scl_oe),
    .sda_i          (sda),
    .sda_oe_o       (m_sda_oe)
  );

  i2c_target #(.Addr(7'h50)) eeprom (
    .clk_i(clk), .rst_ni(rst_n), .scl_i(scl), .sda_i(sda),
    .scl_low_o(t0_scl), .sda_low_o(t0_sda)
  );

  i2c_target #(.Addr(7'h51), .Stretch(StretchClk)) slow (
    .clk_i(clk), .rst_ni(rst_n), .scl_i(scl), .sda_i(sda),
    .scl_low_o(t1_scl), .sda_low_o(t1_sda)
  );

  // Wire monitor, one sample per system clock.
  //  - SDA driven by the controller must be stable for a quarter period
  //    before SCL rises (setup) and must not move on the clock SCL falls (hold).
  //  - Unstretched SCL high and low phases are each at least two quarters.
  //  - START and STOP are counted from the wires.
  int cyc = 0, last_sda = 0, last_scl = 0, last_rise = 0;
  int setup_errs = 0, hold_errs = 0, high_errs = 0, low_errs = 0;
  int min_period = 1 << 30, max_period = 0, nrise = 0;
  int quarter = Div;
  int stretch_low = 0, nstretch = 0;  // SCL low time of each stretched bit
  bit stretched_bit = 0;
  logic scl_q = 1'b1, sda_q = 1'b1;

  always @(posedge clk) begin
    #1;
    cyc++;
    if (rst_n) begin
      if (scl && !scl_q) begin
        if (cyc - last_sda < quarter && !stretched_bit) setup_errs++;
        if (cyc - last_scl < 2 * quarter && !stretched_bit) low_errs++;
        if (last_rise != 0 && !stretched_bit) begin
          if (cyc - last_rise < min_period) min_period = cyc - last_rise;
          if (cyc - last_rise > max_period) max_period = cyc - last_rise;
        end
        if (stretched_bit) begin
          nstretch++;
          if (stretch_low == 0 || cyc - last_scl < stretch_low) stretch_low = cyc - last_scl;
        end
        last_rise = cyc;
        last_scl  = cyc;
        nrise++;
        stretched_bit = 0;
      end
      if (!scl && scl_q) begin
        if (cyc - last_scl < 2 * quarter) high_errs++;
        last_scl = cyc;
      end
      if (sda != sda_q) begin
        // A target changes SDA the clock after SCL falls; the controller waits
        // a quarter. Either way SDA never changes on the falling clock itself.
        if (!scl && cyc == last_scl) hold_errs++;
        last_sda = cyc;
      end
      if (t1_scl) stretched_bit = 1;
      if (!dut.busy) last_rise = 0;  // periods are measured within one command
    end
    scl_q = scl;
    sda_q = sda;
  end

  task automatic wait_idle(input int limit = 100000);
    logic [31:0] r;
    int n = 0;
    do begin
      bus_read(STATUS, r);
      n++;
    end while (r[0] && n < limit);
    check(!r[0], "controller still busy");
  endtask

  task automatic cmd(input logic [31:0] c);
    bus_write(CMD, c);
    wait_idle();
  endtask

  task automatic expect_ack(input string what);
    logic [31:0] r;
    bus_read(STATUS, r);
    check(!r[1], $sformatf("NACK on %s", what));
  endtask

  task automatic read_byte(input bit last, output logic [7:0] b);
    logic [31:0] r;
    cmd(RD | (last ? (NACK | STOP) : 32'h0));
    bus_read(RX, r);
    b = r[7:0];
  endtask

  logic [31:0] r;
  logic [7:0]  b;
  int          t0, t_slow, t_fast, s0, p0;

  initial begin
    t0_scl = 0; t0_sda = 0; t1_scl = 0; t1_sda = 0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    // Reset state: 100 kHz from 50 MHz, idle, bus released.
    bus_read(PRESCALE, r);
    check(r == 32'd125, $sformatf("PRESCALE reset %0d, want 125", r));
    bus_read(STATUS, r);
    check(r == 0, $sformatf("STATUS reset %h, want 0", r));
    check(scl && sda, "bus not released after reset");

    // At the reset rate one SCL period is at least 500 clocks: 100 kHz or less.
    cmd(START | WR | 32'hA0);
    expect_ack("address 0x50 at 100 kHz");
    cmd(STOP);
    check(min_period >= 4 * 125, $sformatf("SCL period %0d clocks at reset rate, want >= 500", min_period));
    check(min_period <= 4 * 125 + 8, $sformatf("SCL period %0d clocks at reset rate, want about 500", min_period));

    // Faster bus for the rest of the test.
    bus_write(PRESCALE, Div);
    bus_read(PRESCALE, r);
    check(r == Div, "PRESCALE did not take the new value");
    min_period = 1 << 30; max_period = 0;

    // Write four bytes at 0x10: START addr+W, pointer, data..., STOP.
    s0 = eeprom.starts; p0 = eeprom.stops;
    cmd(START | WR | 32'hA0);  expect_ack("address 0x50 write");
    cmd(WR | 32'h10);          expect_ack("pointer");
    for (int i = 0; i < 4; i++) begin
      cmd(WR | (32'hC0 + i) | (i == 3 ? STOP : 0));
      expect_ack($sformatf("data byte %0d", i));
    end
    for (int i = 0; i < 4; i++)
      check(eeprom.mem[8'h10 + i] == 8'hC0 + i,
            $sformatf("mem[%h] = %h, want %h", 8'h10 + i, eeprom.mem[8'h10 + i], 8'hC0 + i));
    check(eeprom.starts - s0 == 1 && eeprom.stops - p0 == 1, "write: wrong START/STOP count");
    check(scl && sda, "bus not released after STOP");

    // Read them back with a repeated START, plus two pattern bytes after them.
    s0 = eeprom.starts;
    cmd(START | WR | 32'hA0);  expect_ack("address 0x50 write");
    cmd(WR | 32'h10);          expect_ack("pointer");
    cmd(START | WR | 32'hA1);  expect_ack("address 0x50 read");
    for (int i = 0; i < 6; i++) begin
      read_byte(i == 5, b);
      check(b == (i < 4 ? 8'hC0 + i : 8'(8'h14 + i - 4) ^ 8'h5A),
            $sformatf("read byte %0d = %h", i, b));
    end
    check(eeprom.starts - s0 == 2, "repeated START not seen on the wires");
    check(eeprom.bytes_tx == 6, $sformatf("target sent %0d bytes, want 6", eeprom.bytes_tx));
    check(scl && sda, "bus not released after read");

    // Timing at Div = 8, from every unstretched bit so far.
    check(min_period >= 4 * Div, $sformatf("SCL period %0d clocks, want >= %0d", min_period, 4 * Div));
    check(max_period <= 4 * Div + 8, $sformatf("SCL period %0d clocks, want about %0d", max_period, 4 * Div));
    check(setup_errs == 0, $sformatf("%0d SDA setup violations", setup_errs));
    check(hold_errs == 0, $sformatf("%0d SDA changes on a falling SCL", hold_errs));
    check(high_errs == 0, $sformatf("%0d short SCL high phases", high_errs));
    check(low_errs == 0, $sformatf("%0d short SCL low phases", low_errs));

    // Nobody at 0x31: NACK is reported, then cleared by the next command.
    cmd(START | WR | 32'h62);
    bus_read(STATUS, r);
    check(r[1], "no NACK from an empty address");
    cmd(STOP);
    bus_read(STATUS, r);
    check(!r[1], "NACK not cleared by the next command");
    check(scl && sda, "bus not released after NACK and STOP");

    // Slow target: it holds SCL low for StretchClk clocks after each ACK. The
    // data must still be right, the controller must wait out every stretch,
    // and the transfer must take longer than the same one to the fast target.
    t0 = cyc;
    cmd(START | WR | 32'hA2);  expect_ack("address 0x51 write");
    cmd(WR | 32'h80);          expect_ack("slow pointer");
    cmd(WR | 32'h3C | STOP);   expect_ack("slow data");
    t_slow = cyc - t0;
    check(slow.mem[8'h80] == 8'h3C, $sformatf("slow mem = %h, want 3C", slow.mem[8'h80]));
    t0 = cyc;
    cmd(START | WR | 32'hA0);
    cmd(WR | 32'h80);
    cmd(WR | 32'h3C | STOP);
    t_fast = cyc - t0;
    check(nstretch >= 3, $sformatf("%0d stretched bits seen, want 3", nstretch));
    check(stretch_low >= StretchClk,
          $sformatf("SCL low for %0d clocks during a stretch, want >= %0d", stretch_low, StretchClk));
    check(t_slow > t_fast, $sformatf("stretch did not slow the transfer: %0d vs %0d", t_slow, t_fast));
    cmd(START | WR | 32'hA2);
    cmd(WR | 32'h80);
    cmd(START | WR | 32'hA3);  expect_ack("address 0x51 read");
    read_byte(1'b1, b);
    check(b == 8'h3C, $sformatf("slow read %h, want 3C", b));

    // A command written while busy is ignored.
    s0 = eeprom.bytes_rx;
    bus_write(CMD, START | WR | 32'hA0);
    bus_write(CMD, WR | 32'h11);  // busy: must be dropped
    wait_idle();
    cmd(WR | 32'h20);
    cmd(WR | 32'h77 | STOP);
    check(eeprom.mem[8'h20] == 8'h77, "byte after a dropped command went astray");
    check(eeprom.bytes_rx - s0 == 2, $sformatf("target got %0d bytes, want 2", eeprom.bytes_rx - s0));

    // Unused offsets read 0; byte-wide writes to CMD are ignored.
    bus_read(soc_pkg::I2C_BASE + 32'h10, r);
    check(r == 0, "unused offset reads non-zero");
    bus_write(CMD, START | WR | 32'hA0, 4'b0001);
    bus_read(STATUS, r);
    check(!r[0], "byte-wide CMD write started a transfer");

    finish("tb_i2c");
  end

  initial begin
    #50ms;
    $display("FAIL tb_i2c: timeout");
    $finish;
  end
endmodule
