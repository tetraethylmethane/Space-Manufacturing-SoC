// XADC interface at soc_pkg::XADC_BASE: on-chip temperature and supplies.
//
// The XADC runs its own sequencer continuously. This block reads its status
// registers over the DRP port, one after another, into shadow registers, so
// a bus read always answers in one cycle with the latest sample.
//
// Registers, read-only (writes are ignored, other offsets read 0):
//   +0x00 TEMP     die temperature    } raw XADC values: the 12-bit code
//   +0x04 VCCINT   core supply        } is in bits [15:4].
//   +0x08 VCCAUX   auxiliary supply   } temp (C) = code * 503.975 / 4096 - 273.15
//   +0x0C VCCBRAM  block RAM supply   } supply (V) = code * 3 / 4096
//   +0x10 VPVN     dedicated analogue input VP-VN, 0 to 1 V (code / 4096)
//   +0x14 FLAGS    XADC flag register (alarms, over-temperature)
//   +0x18 SCANS    number of complete passes over the registers above
//
// The DRP side connects to the XADC primitive on the FPGA and to a model in
// simulation (see ibex_demo_system.sv).
module xadc_host #(
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

  // DRP, clocked by clk_i. Reads only.
  output logic        drp_en_o,
  output logic [6:0]  drp_addr_o,
  input  logic        drp_rdy_i,
  input  logic [15:0] drp_do_i
);

  localparam int NumRegs = 6;
  // DRP status register addresses, in bus order.
  localparam logic [6:0] DrpAddr [NumRegs] = '{7'h00, 7'h01, 7'h02, 7'h06, 7'h03, 7'h3F};

  logic [15:0] shadow_q [NumRegs];
  logic [31:0] scans_q;
  logic [2:0]  idx_q;
  logic        wait_q, den_q;
  logic [4:0]  start_q;

  // Poll: issue one DRP read, wait for DRDY, store it, move on.
  // DEN is a registered pulse, so it is never high in reset: a read latched
  // by the XADC during reset would answer late and shift every later result
  // into the next register. The first read also waits a few clocks after
  // reset so the XADC is out of its own reset.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      idx_q    <= '0;
      wait_q   <= 1'b0;
      den_q    <= 1'b0;
      start_q  <= '0;
      scans_q  <= '0;
      shadow_q <= '{default: '0};
    end else if (!(&start_q)) begin
      start_q <= start_q + 5'd1;
    end else if (!wait_q) begin
      den_q  <= 1'b1;
      wait_q <= 1'b1;
    end else if (den_q) begin
      den_q <= 1'b0;
    end else if (drp_rdy_i) begin
      shadow_q[idx_q] <= drp_do_i;
      wait_q          <= 1'b0;
      if (idx_q == 3'(NumRegs - 1)) begin
        idx_q   <= '0;
        scans_q <= scans_q + 32'd1;
      end else begin
        idx_q <= idx_q + 3'd1;
      end
    end
  end

  assign drp_en_o   = den_q;  // one-cycle pulse starts each read
  assign drp_addr_o = DrpAddr[idx_q];

  logic [RegAddr-1:0] reg_addr;
  logic [RegAddr-3:0] word;
  assign reg_addr = device_addr_i[RegAddr-1:0];
  assign word     = reg_addr[RegAddr-1:2];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      device_rvalid_o <= 1'b0;
      device_rdata_o  <= '0;
    end else begin
      device_rvalid_o <= device_req_i;
      device_rdata_o  <= '0;
      if (device_req_i && !device_we_i) begin
        if (word < (RegAddr-2)'(NumRegs)) begin
          device_rdata_o <= {16'h0, shadow_q[word[2:0]]};
        end else if (word == (RegAddr-2)'(NumRegs)) begin
          device_rdata_o <= scans_q;
        end
      end
    end
  end

  logic [AddrWidth-1-RegAddr:0] unused_device_addr;
  logic [1:0]                   unused_reg_addr;
  logic [3:0]                   unused_device_be;
  logic [DataWidth-1:0]         unused_device_wdata;

  assign unused_device_addr  = device_addr_i[AddrWidth-1:RegAddr];
  assign unused_reg_addr     = reg_addr[1:0];
  assign unused_device_be    = device_be_i;
  assign unused_device_wdata = device_wdata_i;

endmodule
