// Block test for the timer (mtime / mtimecmp at TIMER_BASE).
module tb_timer;
  logic        clk = 1'b0, rst_n = 1'b0;
  logic        req = 1'b0, we = 1'b0;
  logic [3:0]  be = '0;
  logic [31:0] addr = '0, wdata = '0;
  logic        rvalid, err, irq;
  logic [31:0] rdata;

  always #10 clk = ~clk;  // 50 MHz

  `include "bus_tasks.svh"

  localparam logic [31:0] BASE     = soc_pkg::TIMER_BASE;
  localparam logic [31:0] MTIME    = BASE + 32'h0;
  localparam logic [31:0] MTIMEH   = BASE + 32'h4;
  localparam logic [31:0] MTIMECMP = BASE + 32'h8;
  localparam logic [31:0] MTIMECMPH= BASE + 32'hC;

  timer #(.DataWidth(32), .AddressWidth(32)) dut (
    .clk_i         (clk),
    .rst_ni        (rst_n),
    .timer_req_i   (req),
    .timer_addr_i  (addr),
    .timer_we_i    (we),
    .timer_be_i    (be),
    .timer_wdata_i (wdata),
    .timer_rvalid_o(rvalid),
    .timer_rdata_o (rdata),
    .timer_err_o   (err),
    .timer_intr_o  (irq)
  );

  task automatic set_cmp(input logic [63:0] t);
    // Same order as the firmware driver: park the low word high first so the
    // compare never passes through a smaller value.
    bus_write(MTIMECMP, 32'hFFFF_FFFF);
    bus_write(MTIMECMPH, t[63:32]);
    bus_write(MTIMECMP, t[31:0]);
  endtask

  initial begin
    logic [31:0] r0, r1, hi, lo;
    logic        e;
    int          n;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    // mtime counts one per cycle: two reads 100 idle cycles apart are
    // 102 apart (each access takes two cycles).
    bus_read(MTIME, r0);
    repeat (100) @(negedge clk);
    bus_read(MTIME, r1);
    check(r1 - r0 == 102, $sformatf("mtime advanced %0d in 102 cycles", r1 - r0));
    bus_read(MTIME, r0);
    bus_read(MTIME, r1);
    check(r1 - r0 == 2, $sformatf("back-to-back reads %0d apart, expected 2", r1 - r0));

    // mtimecmp resets to 0, so the interrupt is pending out of reset.
    check(irq, "interrupt not pending after reset with mtimecmp = 0");

    // Register write and read-back, including byte enables.
    bus_write(MTIMECMPH, 32'h1234_5678);
    bus_read(MTIMECMPH, r0);
    check(r0 == 32'h1234_5678, $sformatf("mtimecmph read %h", r0));
    bus_write(MTIMECMP, 32'hFFFF_FFFF);
    bus_write(MTIMECMP, 32'h0000_00A5, 4'b0001);
    bus_read(MTIMECMP, r0);
    check(r0 == 32'hFFFF_FFA5, $sformatf("byte write to mtimecmp gave %h", r0));
    bus_write(MTIMEH, 32'h0000_0007);
    bus_read(MTIMEH, r0);
    check(r0 == 32'h7, $sformatf("mtimeh read %h after writing 7", r0));
    bus_write(MTIME, 32'd1000);
    bus_read(MTIME, r0);
    check(r0 == 32'd1001, $sformatf("mtime read %0d right after writing 1000", r0));

    // A write to mtimecmp clears the interrupt; it fires when mtime reaches it.
    bus_write(MTIMEH, 32'h0);
    bus_write(MTIME, 32'h0);
    set_cmp(64'd500);
    check(!irq, "interrupt still set after writing mtimecmp");
    n = 0;
    while (!irq && n < 1000) begin @(posedge clk); n++; end
    bus_read(MTIME, r0);
    // mtime was ~8 at the last write; irq follows mtime >= mtimecmp by one cycle.
    check(irq, "interrupt never fired");
    check(r0 >= 500 && r0 <= 506, $sformatf("interrupt seen with mtime = %0d, expected ~501", r0));

    // The interrupt is sticky: moving mtime back does not clear it.
    bus_write(MTIME, 32'h0);
    repeat (5) @(negedge clk);
    check(irq, "interrupt cleared by an mtime write");
    set_cmp(64'hFFFF_FFFF_FFFF_FFFF);
    check(!irq, "interrupt not cleared by an mtimecmp write");

    // The high compare word matters: low word passed but high word not.
    bus_write(MTIMEH, 32'h0);
    bus_write(MTIME, 32'h0);
    set_cmp({32'd1, 32'd0});
    repeat (200) @(negedge clk);
    check(!irq, "interrupt fired with mtimecmph = 1 and mtimeh = 0");

    // Carry from mtime into mtimeh.
    bus_write(MTIMEH, 32'h0);
    bus_write(MTIME, 32'hFFFF_FF00);
    repeat (300) @(negedge clk);
    bus_read(MTIMEH, hi);
    bus_read(MTIME, lo);
    check(hi == 32'd1, $sformatf("mtimeh = %0d after low word wrapped", hi));
    check(lo < 32'd200, $sformatf("mtime = %0d after wrap", lo));
    check(irq, "interrupt not raised once mtime passed {1, 0}");

    // Offsets with no register answer with err; mapped offsets do not.
    bus_access(1'b0, BASE + 32'h10, '0, 4'hf, r0, e);
    check(e, "no err on read from unmapped offset 0x10");
    bus_access(1'b0, BASE + 32'h3FC, '0, 4'hf, r0, e);
    check(e, "no err on read from unmapped offset 0x3FC");
    bus_access(1'b0, MTIME, '0, 4'hf, r0, e);
    check(!e, "err on read from mtime");

    finish("tb_timer");
  end

  initial begin
    #5ms;
    $display("FAIL tb_timer: timeout");
    $finish;
  end
endmodule
