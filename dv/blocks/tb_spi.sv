// Block test for the SPI master (mode 0, 12.5 MHz from 50 MHz) at SPI_BASE.
// MOSI is looped back to MISO, as with a jumper on the board.
// Registers: +0 TX (write pushes a byte), +4 status (bit 0 TX full,
// bit 1 TX empty, bit 2 RX valid), +8 RX (last received byte).
module tb_spi;
  logic        clk = 1'b0, rst_n = 1'b0;
  logic        req = 1'b0, we = 1'b0;
  logic [3:0]  be = '0;
  logic [31:0] addr = '0, wdata = '0;
  logic        rvalid, err;
  logic [31:0] rdata;
  logic        sck, mosi;

  assign err = 1'b0;  // the SPI block has no err output

  always #10 clk = ~clk;

  `include "bus_tasks.svh"

  localparam logic [31:0] TX     = soc_pkg::SPI_BASE + 32'h0;
  localparam logic [31:0] STATUS = soc_pkg::SPI_BASE + 32'h4;
  localparam logic [31:0] RX     = soc_pkg::SPI_BASE + 32'h8;
  localparam int          SckPeriod = 4;  // system clocks per SCK cycle

  spi_top dut (
    .clk_i          (clk),
    .rst_ni         (rst_n),
    .device_req_i   (req),
    .device_addr_i  (addr),
    .device_we_i    (we),
    .device_be_i    (be),
    .device_wdata_i (wdata),
    .device_rvalid_o(rvalid),
    .device_rdata_o (rdata),
    .spi_rx_i       (mosi),
    .spi_tx_o       (mosi),
    .sck_o          (sck),
    .byte_data_o    ()
  );

  // Wire monitor, one sample per system clock. Records what a mode-0 device
  // would see: one bit per SCK rising edge, and MOSI must not move on that edge.
  byte unsigned seen[$];
  logic [7:0]   shift;
  int           nbits = 0, last_rise = -1, cyc = 0;
  int           hold_errs = 0, period_errs = 0;
  logic         sck_q = 1'b0, mosi_q = 1'b1;

  always @(posedge clk) begin
    #1;
    cyc++;
    if (rst_n && sck && !sck_q) begin
      if (mosi != mosi_q) hold_errs++;
      if (nbits % 8 != 0 && cyc - last_rise != SckPeriod) period_errs++;
      last_rise = cyc;
      shift = {shift[6:0], mosi};
      nbits++;
      if (nbits % 8 == 0) seen.push_back(shift);
    end
    sck_q  = sck;
    mosi_q = mosi;
  end

  task automatic wait_status(input int bitn, input bit val, input int limit = 100000);
    logic [31:0] r;
    int n = 0;
    do begin bus_read(STATUS, r); n++; end while (r[bitn] != val && n < limit);
    check(r[bitn] == val, $sformatf("status bit %0d never became %0d", bitn, val));
  endtask

  initial begin
    logic [31:0] r;
    byte unsigned sent[$];

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (5) @(negedge clk);

    // Idle state: SCK low (CPOL = 0), MOSI high, FIFO empty, nothing received.
    check(!sck, "SCK not low at idle");
    check(mosi, "MOSI not high at idle");
    bus_read(STATUS, r);
    check(r[2:0] == 3'b010, $sformatf("status after reset %b, expected 010", r[2:0]));

    // One byte at a time: wire bits, timing and loopback read-back.
    for (int v = 0; v < 256; v += 37) begin
      bus_write(TX, v);
      wait_status(2, 1'b1);
      bus_read(RX, r);
      check(r[7:0] == v[7:0], $sformatf("loopback read %h, sent %h", r[7:0], v[7:0]));
      bus_read(STATUS, r);
      check(!r[2], "RX valid not cleared by reading RX");
      sent.push_back(v[7:0]);
    end
    check(!sck, "SCK not low between bytes");

    // Burst of 200 bytes through the 127-entry FIFO, polling the full flag the
    // way the driver does. The FIFO must fill, and every byte go out in order.
    begin
      bit saw_full = 1'b0;
      for (int i = 0; i < 200; i++) begin
        bus_read(STATUS, r);
        while (r[0]) begin saw_full = 1'b1; bus_read(STATUS, r); end
        bus_write(TX, (i * 7 + 3) & 8'hFF);
        sent.push_back((i * 7 + 3) & 8'hFF);
      end
      check(saw_full, "TX full never set during a 200-byte burst");
    end
    wait_status(1, 1'b1);
    repeat (20 * SckPeriod) @(negedge clk);  // let the last byte finish
    bus_read(RX, r);
    check(r[7:0] == sent[$], $sformatf("RX after burst %h, expected %h", r[7:0], sent[$]));

    // Only byte lane 0 pushes into the FIFO.
    bus_write(TX, 32'h55, 4'b0010);
    repeat (40 * SckPeriod) @(negedge clk);

    check(seen.size() == sent.size(),
          $sformatf("%0d bytes on the wire, expected %0d", seen.size(), sent.size()));
    for (int i = 0; i < sent.size() && i < seen.size(); i++)
      check(seen[i] == sent[i], $sformatf("wire byte %0d = %h, expected %h", i, seen[i], sent[i]));
    check(hold_errs == 0, $sformatf("MOSI changed on %0d SCK rising edges (no hold time)", hold_errs));
    check(period_errs == 0, $sformatf("%0d SCK periods were not %0d clocks", period_errs, SckPeriod));
    check(!sck, "SCK not low at the end");

    finish("tb_spi");
  end

  initial begin
    #20ms;
    $display("FAIL tb_spi: timeout");
    $finish;
  end
endmodule
