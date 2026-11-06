// Behavioural model of the XADC DRP port, for simulation only.
//
// Answers a read Latency clocks after DEN with the value in regs[], which
// starts with plausible readings and can be changed by a testbench. It counts
// protocol errors: a DEN while a read is still outstanding, and (reset_dens)
// a DEN while in reset, which the real XADC latches and answers late.
module xadc_model #(
  parameter int Latency = 5
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        den_i,
  input  logic [6:0]  daddr_i,
  output logic        drdy_o,
  output logic [15:0] do_o
);

  logic [15:0] regs [128];
  int          protocol_errs = 0, reads = 0, reset_dens = 0;

  always @(posedge clk_i) if (!rst_ni && den_i) reset_dens <= reset_dens + 1;
  int          count_q;
  logic [6:0]  addr_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      count_q <= 0;
      addr_q  <= '0;
      drdy_o  <= 1'b0;
      do_o    <= '0;
    end else begin
      drdy_o <= 1'b0;
      if (den_i) begin
        if (count_q != 0) protocol_errs <= protocol_errs + 1;
        addr_q  <= daddr_i;
        count_q <= Latency;
      end else if (count_q == 1) begin
        drdy_o  <= 1'b1;
        do_o    <= regs[addr_q];
        reads   <= reads + 1;
        count_q <= 0;
      end else if (count_q != 0) begin
        count_q <= count_q - 1;
      end
    end
  end

  // Codes are 12 bits in [15:4]: 45.0 C, 1.00 V, 1.80 V, 1.00 V, 0.25 V.
  initial begin
    for (int i = 0; i < 128; i++) regs[i] = 16'h0;
    regs[7'h00] = 16'(2586 << 4);  // (45 + 273.15) * 4096 / 503.975
    regs[7'h01] = 16'(1365 << 4);  // 1.00 V * 4096 / 3
    regs[7'h02] = 16'(2458 << 4);  // 1.80 V
    regs[7'h06] = 16'(1365 << 4);  // 1.00 V
    regs[7'h03] = 16'(1024 << 4);  // 0.25 V on VP-VN (1 V full scale)
    regs[7'h3F] = 16'h0000;        // no alarms
  end

endmodule
