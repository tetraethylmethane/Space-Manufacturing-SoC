// Stage-1 bring-up: proves Vivado + part + constraints + clock before Ibex is involved.
// LED[0] blinks at ~1.5 Hz from the 100 MHz oscillator. LED[1] mirrors SW[0].
module blinky (
  input  logic       IO_CLK,
  input  logic [0:0] SW,
  output logic [1:0] LED
);
  logic [25:0] count = '0;

  always_ff @(posedge IO_CLK) count <= count + 1'b1;

  assign LED[0] = count[25];
  assign LED[1] = SW[0];
endmodule
