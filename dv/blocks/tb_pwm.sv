// Block test for the PWM wrapper (12 channels at PWM_BASE).
// Channel i: pulse width at +8i, counter maximum at +8i+4. The period is
// max+1 cycles and the output is high for min(width, max+1) of them.
module tb_pwm;
  localparam int N = 12;

  logic         clk = 1'b0, rst_n = 1'b0;
  logic         req = 1'b0, we = 1'b0;
  logic [3:0]   be = '0;
  logic [31:0]  addr = '0, wdata = '0;
  logic         rvalid, err;
  logic [31:0]  rdata;
  logic [N-1:0] pwm;

  assign err = 1'b0;  // the PWM block has no err output

  always #10 clk = ~clk;

  `include "bus_tasks.svh"

  localparam logic [31:0] BASE = soc_pkg::PWM_BASE;

  pwm_wrapper #(.PwmWidth(N), .PwmCtrSize(8)) dut (
    .clk_i          (clk),
    .rst_ni         (rst_n),
    .device_req_i   (req),
    .device_addr_i  (addr),
    .device_we_i    (we),
    .device_be_i    (be),
    .device_wdata_i (wdata),
    .device_rvalid_o(rvalid),
    .device_rdata_o (rdata),
    .pwm_o          (pwm)
  );

  task automatic set_pwm(input int ch, input int max, input int width);
    bus_write(BASE + 8 * ch + 4, max);
    bus_write(BASE + 8 * ch, width);
  endtask

  // Count high cycles of every channel over a window.
  task automatic measure(input int cycles, output int high[N]);
    for (int i = 0; i < N; i++) high[i] = 0;
    repeat (cycles) begin
      @(posedge clk);
      for (int i = 0; i < N; i++) high[i] += pwm[i];
    end
  endtask

  // Expected high cycles of a channel over `periods` full periods.
  function automatic int expect_high(int max, int width, int periods);
    if (max == 0) return 0;
    return (width > max + 1 ? max + 1 : width) * periods;
  endfunction

  int max_of[N], width_of[N];

  // Measure over a window that is a whole number of every period used below.
  task automatic check_all(input string what);
    int high[N];
    int window = 25600;  // multiple of 100, 256, 64, 50, 8 and 2
    repeat (600) @(negedge clk);  // let every counter wrap at least twice
    measure(window, high);
    for (int i = 0; i < N; i++) begin
      int period = max_of[i] + 1;
      int exp = (max_of[i] == 0) ? 0 : expect_high(max_of[i], width_of[i], window / period);
      check(high[i] == exp,
            $sformatf("%s: ch%0d max=%0d width=%0d high %0d of %0d cycles, expected %0d",
                      what, i, max_of[i], width_of[i], high[i], window, exp));
    end
  endtask

  initial begin
    logic [31:0] r;
    int high[N];

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    // Out of reset every channel is off.
    measure(300, high);
    for (int i = 0; i < N; i++) check(high[i] == 0, $sformatf("ch%0d not low after reset", i));

    // A different setting per channel, covering the edge cases:
    // 25%, 50%, 0 width, full width, width above max, max = 0, tiny and full-scale periods.
    max_of   = '{99, 99, 99, 99, 99,  0, 255, 255, 255, 7, 63, 1};
    width_of = '{25, 50,  0, 100, 200, 10,  1, 128, 255, 3, 63, 1};
    for (int i = 0; i < N; i++) set_pwm(i, max_of[i], width_of[i]);
    check_all("initial");

    // Writing one channel leaves the others alone.
    max_of[4] = 49; width_of[4] = 10;
    set_pwm(4, max_of[4], width_of[4]);
    check_all("after changing ch4");

    // Only the low 8 bits are used.
    max_of[0] = 99; width_of[0] = 25;
    set_pwm(0, 32'h0000_0163, 32'hFFFF_FF19);  // 0x63 = 99, 0x19 = 25
    check_all("upper bits ignored");

    // Turning a channel off with max = 0.
    max_of[1] = 0;
    bus_write(BASE + 8 + 4, 0);
    check_all("ch1 off");

    // Reads answer on time and return 0 (the block is write-only).
    bus_read(BASE, r);
    check(r == 0, $sformatf("read returned %h, expected 0", r));

    finish("tb_pwm");
  end

  initial begin
    #50ms;
    $display("FAIL tb_pwm: timeout");
    $finish;
  end
endmodule
