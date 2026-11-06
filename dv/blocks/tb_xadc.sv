// Block test for the XADC interface at XADC_BASE, against a DRP model.
// Registers: +0 TEMP, +4 VCCINT, +8 VCCAUX, +C VCCBRAM, +10 VPVN, +14 FLAGS,
// +18 SCANS. All read-only.
module tb_xadc;
  logic        clk = 1'b0, rst_n = 1'b0;
  logic        req = 1'b0, we = 1'b0;
  logic [3:0]  be = '0;
  logic [31:0] addr = '0, wdata = '0;
  logic        rvalid, err;
  logic [31:0] rdata;

  assign err = 1'b0;  // the XADC block has no err output

  always #10 clk = ~clk;

  `include "bus_tasks.svh"

  localparam logic [31:0] Base = soc_pkg::XADC_BASE;
  localparam logic [6:0]  DrpAddr [6] = '{7'h00, 7'h01, 7'h02, 7'h06, 7'h03, 7'h3F};
  localparam string       Name [6] = '{"TEMP", "VCCINT", "VCCAUX", "VCCBRAM", "VPVN", "FLAGS"};

  logic        den, drdy;
  logic [6:0]  daddr;
  logic [15:0] dout;

  xadc_host dut (
    .clk_i          (clk),
    .rst_ni         (rst_n),
    .device_req_i   (req),
    .device_addr_i  (addr),
    .device_we_i    (we),
    .device_be_i    (be),
    .device_wdata_i (wdata),
    .device_rvalid_o(rvalid),
    .device_rdata_o (rdata),
    .drp_en_o       (den),
    .drp_addr_o     (daddr),
    .drp_rdy_i      (drdy),
    .drp_do_i       (dout)
  );

  xadc_model #(.Latency(5)) xadc (
    .clk_i  (clk),
    .rst_ni (rst_n),
    .den_i  (den),
    .daddr_i(daddr),
    .drdy_o (drdy),
    .do_o   (dout)
  );

  // Only status registers may be read: the configuration (0x40 and up) and
  // anything unexpected must be left alone.
  int bad_addr = 0;
  always @(posedge clk) if (rst_n && den && !(daddr inside {7'h00, 7'h01, 7'h02, 7'h03, 7'h06, 7'h3F})) bad_addr++;

  task automatic wait_scans(input int n);
    logic [31:0] r0, r;
    bus_read(Base + 32'h18, r0);
    do bus_read(Base + 32'h18, r); while (r - r0 < n);
  endtask

  logic [31:0] r, s0, s1;

  initial begin
    repeat (20) @(negedge clk);
    rst_n = 1'b1;

    // Before the first DRDY nothing has been read.
    bus_read(Base + 32'h18, r);
    check(r == 0, $sformatf("SCANS %0d straight after reset", r));

    // After a full pass every register holds the model's value.
    wait_scans(2);
    for (int i = 0; i < 6; i++) begin
      bus_read(Base + 4 * i, r);
      check(r == {16'h0, xadc.regs[DrpAddr[i]]},
            $sformatf("%s = %h, want %h", Name[i], r, xadc.regs[DrpAddr[i]]));
    end

    // New values appear within one pass.
    for (int i = 0; i < 6; i++) xadc.regs[DrpAddr[i]] = 16'hA000 + 16'(i * 16'h111);
    wait_scans(2);
    for (int i = 0; i < 6; i++) begin
      bus_read(Base + 4 * i, r);
      check(r == 32'hA000 + i * 32'h111, $sformatf("%s = %h after update", Name[i], r));
    end

    // A pass costs six DRP reads of Latency + 2 clocks: SCANS keeps counting.
    bus_read(Base + 32'h18, s0);
    repeat (6 * 7 * 10) @(negedge clk);
    bus_read(Base + 32'h18, s1);
    check(s1 - s0 >= 9 && s1 - s0 <= 11, $sformatf("%0d passes in 420 clocks, want about 10", s1 - s0));

    // Writes are ignored, unused offsets read 0, reads never stall.
    bus_write(Base, 32'hFFFF_FFFF);
    bus_read(Base, r);
    check(r == 32'hA000, "write changed TEMP");
    bus_read(Base + 32'h1C, r);
    check(r == 0, "offset 0x1C reads non-zero");
    bus_read(Base + 32'h800, r);
    check(r == 0, "offset 0x800 reads non-zero");

    check(xadc.reset_dens == 0, $sformatf("DEN high on %0d clocks during reset", xadc.reset_dens));
    check(xadc.protocol_errs == 0, $sformatf("%0d DEN pulses while a read was pending", xadc.protocol_errs));
    check(bad_addr == 0, $sformatf("%0d DRP reads outside the status registers", bad_addr));
    // Every pass is exactly six DRP reads (one more may be in flight).
    bus_read(Base + 32'h18, r);
    check(xadc.reads >= 6 * r && xadc.reads <= 6 * r + 6,
          $sformatf("%0d DRP reads for %0d passes", xadc.reads, r));

    finish("tb_xadc");
  end

  initial begin
    #5ms;
    $display("FAIL tb_xadc: timeout");
    $finish;
  end
endmodule
