// Shared bus driver and checks for the block testbenches.
//
// The including module must declare: clk, req, we, be, addr, wdata, rvalid,
// rdata, err (tie err to 0 for devices without one). Every access follows the
// frozen bus rules (doc/bus-and-memory-map.md): the request is held for one
// cycle and rvalid must arrive exactly one cycle later.

int errors = 0;
int checks = 0;

task automatic check(input bit cond, input string msg);
  checks++;
  if (!cond) begin
    errors++;
    $display("  FAIL: %s", msg);
  end
endtask

task automatic bus_access(input bit write, input logic [31:0] a, input logic [31:0] d,
                          input logic [3:0] b, output logic [31:0] r, output logic e);
  @(negedge clk);
  check(!rvalid, $sformatf("rvalid high with no request (addr %h)", a));
  req = 1'b1; we = write; addr = a; wdata = d; be = b;
  @(negedge clk);
  req = 1'b0; we = 1'b0;
  check(rvalid, $sformatf("no rvalid one cycle after request (addr %h)", a));
  r = rdata;
  e = err;
endtask

task automatic bus_write(input logic [31:0] a, input logic [31:0] d,
                         input logic [3:0] b = 4'hf);
  logic [31:0] r;
  logic e;
  bus_access(1'b1, a, d, b, r, e);
  check(!e, $sformatf("err on write to %h", a));
endtask

task automatic bus_read(input logic [31:0] a, output logic [31:0] r);
  logic e;
  bus_access(1'b0, a, '0, 4'hf, r, e);
  check(!e, $sformatf("err on read from %h", a));
endtask

task automatic finish(input string name);
  if (errors == 0) $display("PASS %s (%0d checks)", name, checks);
  else             $display("FAIL %s: %0d of %0d checks failed", name, errors, checks);
  $finish;
endtask
