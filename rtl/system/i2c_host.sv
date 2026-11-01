// I2C controller (single master) at soc_pkg::I2C_BASE.
//
// Registers, all 32-bit:
//   +0x0 PRESCALE  rw  system clocks per quarter SCL period, bits [15:0].
//                      Reset 125: 100 kHz from 50 MHz. 32 gives 390 kHz.
//   +0x4 CMD       w   one bus operation, in this order:
//                        bit 8  START (repeated start if the bus is held)
//                        bit 10 WRITE the byte in bits [7:0], then read ACK
//                        bit 11 READ a byte, then send bit 12 as the ACK
//                               (0 = ACK, 1 = NACK for the last byte)
//                        bit 9  STOP
//                      WRITE wins if both WRITE and READ are set. A write to
//                      CMD while BUSY is ignored.
//   +0x8 STATUS    r   bit 0 BUSY, bit 1 NACK (the target did not ACK the
//                      last byte written; cleared by the next command).
//   +0xC RX        r   last byte read.
// Other offsets read as 0 and ignore writes.
//
// SCL and SDA are open drain: *_oe_o high pulls the line low, low releases it.
// A target may hold SCL low (clock stretching); the controller waits for SCL
// to read high before timing the high phase. Arbitration is not supported.
module i2c_host #(
  parameter int unsigned AddrWidth = 32,
  parameter int unsigned DataWidth = 32,
  parameter int unsigned RegAddr   = 12
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic                 device_req_i,
  input  logic [AddrWidth-1:0] device_addr_i,
  input  logic                 device_we_i,
  input  logic [3:0]           device_be_i,
  input  logic [DataWidth-1:0] device_wdata_i,
  output logic                 device_rvalid_o,
  output logic [DataWidth-1:0] device_rdata_o,

  input  logic scl_i,
  output logic scl_oe_o,
  input  logic sda_i,
  output logic sda_oe_o
);

  localparam logic [RegAddr-1:0] PrescaleReg = RegAddr'('h0);
  localparam logic [RegAddr-1:0] CmdReg      = RegAddr'('h4);
  localparam logic [RegAddr-1:0] StatusReg   = RegAddr'('h8);
  localparam logic [RegAddr-1:0] RxReg       = RegAddr'('hC);

  typedef enum logic [1:0] {
    Idle,
    Start,
    Bits,
    Stop
  } state_e;

  state_e      state_q;
  logic [15:0] prescale_q;
  logic [15:0] div_q;
  logic [1:0]  quarter_q;  // position within one SCL period, see the timer below
  logic [3:0]  bit_q;      // 0..8 within a byte, 8 is the ACK slot
  logic [8:0]  shift_q;    // bits still to send, MSB first, ACK slot last
  logic [7:0]  rx_q, rx_shift_q;
  logic        do_write_q, do_read_q, do_stop_q, nack_q;
  logic        scl_oe_q, sda_oe_q;

  // Inputs come from pads, so synchronise them.
  logic [1:0] scl_sync_q, sda_sync_q;
  logic       scl_in, sda_in;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      scl_sync_q <= 2'b11;
      sda_sync_q <= 2'b11;
    end else begin
      scl_sync_q <= {scl_sync_q[0], scl_i};
      sda_sync_q <= {sda_sync_q[0], sda_i};
    end
  end
  assign scl_in = scl_sync_q[1];
  assign sda_in = sda_sync_q[1];

  logic [RegAddr-1:0] reg_addr;
  logic               cmd_write, busy;

  assign reg_addr  = device_addr_i[RegAddr-1:0];
  assign busy      = (state_q != Idle);
  assign cmd_write = device_req_i & device_we_i & (reg_addr == CmdReg) &
                     (&device_be_i[1:0]) & ~busy;

  // Quarter-period timer. Each quarter's action happens as it ends:
  //   end of 0: set SDA (SCL low)      end of 1: release SCL
  //   end of 2: sample SDA (mid-high)  end of 3: pull SCL low
  // SCL is released when quarter 2 starts, so in quarter 2 the timer only runs
  // once SCL reads high: a stretching target still gets a full high phase.
  logic tick;
  assign tick = (div_q == 16'd1);

  // The next state after a finished START or byte.
  function automatic state_e after_start(logic wr, logic rd, logic stop);
    if (wr || rd) return Bits;
    if (stop)     return Stop;
    return Idle;
  endfunction

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q    <= Idle;
      prescale_q <= 16'd125;
      div_q      <= 16'd125;
      quarter_q  <= '0;
      bit_q      <= '0;
      shift_q    <= '1;
      rx_q       <= '0;
      rx_shift_q <= '0;
      do_write_q <= 1'b0;
      do_read_q  <= 1'b0;
      do_stop_q  <= 1'b0;
      nack_q     <= 1'b0;
      scl_oe_q   <= 1'b0;
      sda_oe_q   <= 1'b0;
    end else begin
      if (device_req_i && device_we_i && reg_addr == PrescaleReg && &device_be_i[1:0]) begin
        prescale_q <= (device_wdata_i[15:0] == '0) ? 16'd1 : device_wdata_i[15:0];
      end

      if (state_q == Idle) begin
        div_q     <= prescale_q;
        quarter_q <= '0;
        if (cmd_write) begin
          do_write_q <= device_wdata_i[10];
          do_read_q  <= device_wdata_i[11] & ~device_wdata_i[10];
          do_stop_q  <= device_wdata_i[9];
          nack_q     <= 1'b0;
          bit_q      <= '0;
          // Read: release SDA for 8 bits, then drive the requested ACK.
          shift_q    <= device_wdata_i[10] ? {device_wdata_i[7:0], 1'b1}
                                           : {8'hFF, device_wdata_i[12]};
          if (device_wdata_i[8]) begin
            state_q <= Start;
          end else begin
            state_q <= after_start(device_wdata_i[10], device_wdata_i[11], device_wdata_i[9]);
          end
        end
      end else if (!tick) begin
        if (!(quarter_q == 2'd2 && !scl_in)) div_q <= div_q - 16'd1;
      end else begin
        div_q     <= prescale_q;
        quarter_q <= quarter_q + 2'd1;
        unique case (state_q)
          // Release SDA, release SCL, pull SDA low while SCL is high, then SCL low.
          Start: begin
            unique case (quarter_q)
              2'd0: sda_oe_q <= 1'b0;
              2'd1: scl_oe_q <= 1'b0;
              2'd2: sda_oe_q <= 1'b1;
              2'd3: begin
                scl_oe_q <= 1'b1;
                state_q  <= after_start(do_write_q, do_read_q, do_stop_q);
              end
              default: ;
            endcase
          end
          // One bit per four quarters; the ninth bit is the ACK slot.
          Bits: begin
            unique case (quarter_q)
              2'd0: sda_oe_q <= ~shift_q[8];
              2'd1: scl_oe_q <= 1'b0;
              2'd2: begin
                if (bit_q == 4'd8) begin
                  if (do_write_q) nack_q <= sda_in;
                end else begin
                  rx_shift_q <= {rx_shift_q[6:0], sda_in};
                end
              end
              2'd3: begin
                scl_oe_q <= 1'b1;
                shift_q  <= {shift_q[7:0], 1'b1};
                bit_q    <= bit_q + 4'd1;
                if (bit_q == 4'd8) begin
                  if (do_read_q) rx_q <= rx_shift_q;
                  state_q <= do_stop_q ? Stop : Idle;
                end
              end
              default: ;
            endcase
          end
          // SDA low while SCL is low, release SCL, then release SDA.
          Stop: begin
            unique case (quarter_q)
              2'd0: sda_oe_q <= 1'b1;
              2'd1: scl_oe_q <= 1'b0;
              2'd2: sda_oe_q <= 1'b0;
              2'd3: state_q  <= Idle;  // bus free time
              default: ;
            endcase
          end
          default: state_q <= Idle;
        endcase
      end
    end
  end

  assign scl_oe_o = scl_oe_q;
  assign sda_oe_o = sda_oe_q;

  // Bus response: rvalid one cycle after every request, read data registered.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      device_rvalid_o <= 1'b0;
      device_rdata_o  <= '0;
    end else begin
      device_rvalid_o <= device_req_i;
      device_rdata_o  <= '0;
      if (device_req_i && !device_we_i) begin
        unique case (reg_addr)
          PrescaleReg: device_rdata_o <= {(DataWidth-16)'('0), prescale_q};
          StatusReg:   device_rdata_o <= {(DataWidth-2)'('0), nack_q, busy};
          RxReg:       device_rdata_o <= {(DataWidth-8)'('0), rx_q};
          default:     device_rdata_o <= '0;
        endcase
      end
    end
  end

  logic [AddrWidth-1-RegAddr:0] unused_device_addr;
  logic [1:0]                   unused_device_be;
  logic [DataWidth-1-16:0]      unused_device_wdata;

  assign unused_device_addr  = device_addr_i[AddrWidth-1:RegAddr];
  assign unused_device_be    = device_be_i[3:2];
  assign unused_device_wdata = device_wdata_i[DataWidth-1:16];

endmodule
