// Behavioural I2C target for simulation, shaped like a small EEPROM.
//
// It answers at address Addr. After the address byte, a write sets the
// register pointer with its first data byte and stores any further bytes at
// the pointer, which then increments. A read returns bytes from the pointer
// onwards until the controller sends NACK. Any other address gets no ACK.
//
// It samples the bus on the system clock, so it needs the bus to be several
// clocks per quarter period. With Stretch > 0 it holds SCL low for that many
// clocks after every ACK it gives, as a slow device would.
module i2c_target #(
  parameter logic [6:0] Addr    = 7'h50,
  parameter int         Stretch = 0
) (
  input  logic clk_i,
  input  logic rst_ni,
  input  logic scl_i,
  input  logic sda_i,
  output logic scl_low_o,
  output logic sda_low_o
);

  typedef enum logic [2:0] {
    Idle,     // not addressed: wait for START
    AddrByte, // receiving the address byte
    Ack,      // driving our ACK
    RxByte,   // receiving a data byte
    TxByte,   // sending a data byte
    MAck      // reading the controller's ACK
  } state_e;

  state_e     state_q;
  logic [7:0] mem [256];
  logic [7:0] ptr_q, shift_q;
  logic [3:0] nbits_q;
  logic       rw_q, first_q, scl_q, sda_q;
  int         stretch_q;

  // Counters the testbench can read.
  int starts = 0, stops = 0, bytes_rx = 0, bytes_tx = 0;

  logic scl_rise, scl_fall, start_cond, stop_cond;
  assign scl_rise   =  scl_i & ~scl_q;
  assign scl_fall   = ~scl_i &  scl_q;
  assign start_cond =  scl_i &  scl_q & ~sda_i &  sda_q;
  assign stop_cond  =  scl_i &  scl_q &  sda_i & ~sda_q;

  assign scl_low_o = (stretch_q > 0);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q   <= Idle;
      ptr_q     <= '0;
      shift_q   <= '0;
      nbits_q   <= '0;
      rw_q      <= 1'b0;
      first_q   <= 1'b0;
      scl_q     <= 1'b1;
      sda_q     <= 1'b1;
      sda_low_o <= 1'b0;
      stretch_q <= 0;
    end else begin
      scl_q <= scl_i;
      sda_q <= sda_i;
      if (stretch_q > 0) stretch_q <= stretch_q - 1;

      if (start_cond) begin
        starts    <= starts + 1;
        state_q   <= AddrByte;
        nbits_q   <= '0;
        sda_low_o <= 1'b0;
      end else if (stop_cond) begin
        stops     <= stops + 1;
        state_q   <= Idle;
        sda_low_o <= 1'b0;
      end else if (scl_rise) begin
        unique case (state_q)
          AddrByte, RxByte: begin
            shift_q <= {shift_q[6:0], sda_i};
            nbits_q <= nbits_q + 4'd1;
          end
          MAck: if (sda_i) state_q <= Idle;  // NACK: the read is over
          default: ;
        endcase
      end else if (scl_fall) begin
        unique case (state_q)
          AddrByte: if (nbits_q == 4'd8) begin
            if (shift_q[7:1] == Addr) begin
              sda_low_o <= 1'b1;
              rw_q      <= shift_q[0];
              first_q   <= 1'b1;
              state_q   <= Ack;
            end else begin
              state_q <= Idle;
            end
          end
          RxByte: if (nbits_q == 4'd8) begin
            if (first_q) begin
              ptr_q <= shift_q;
            end else begin
              mem[ptr_q] <= shift_q;
              ptr_q      <= ptr_q + 8'd1;
            end
            first_q   <= 1'b0;
            bytes_rx  <= bytes_rx + 1;
            sda_low_o <= 1'b1;
            state_q   <= Ack;
          end
          Ack: begin
            stretch_q <= Stretch;
            if (rw_q) begin
              shift_q   <= mem[ptr_q] << 1;
              sda_low_o <= ~mem[ptr_q][7];
              ptr_q     <= ptr_q + 8'd1;
              nbits_q   <= 4'd1;
              bytes_tx  <= bytes_tx + 1;
              state_q   <= TxByte;
            end else begin
              sda_low_o <= 1'b0;
              nbits_q   <= '0;
              state_q   <= RxByte;
            end
          end
          TxByte: begin
            if (nbits_q == 4'd8) begin
              sda_low_o <= 1'b0;
              state_q   <= MAck;
            end else begin
              sda_low_o <= ~shift_q[7];
              shift_q   <= shift_q << 1;
              nbits_q   <= nbits_q + 4'd1;
            end
          end
          MAck: begin  // controller ACKed: send the next byte
            shift_q   <= mem[ptr_q] << 1;
            sda_low_o <= ~mem[ptr_q][7];
            ptr_q     <= ptr_q + 8'd1;
            nbits_q   <= 4'd1;
            bytes_tx  <= bytes_tx + 1;
            state_q   <= TxByte;
          end
          default: ;
        endcase
      end
    end
  end

  // Fill memory with a known pattern so reads have something to return.
  initial for (int i = 0; i < 256; i++) mem[i] = 8'(i) ^ 8'h5A;

endmodule
