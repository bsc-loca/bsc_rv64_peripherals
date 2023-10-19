/* -----------------------------------------------
* Project Name   : Perte
* File           : plic_wrap.sv
* Organization   : Barcelona Supercomputing Center
* Author(s)      : Alejandro Tafalla Quílez
* Email(s)       : alejandro.tafalla@bsc.es
* References     :
* -----------------------------------------------
* Description:
*  Wrapper for Ariane's PLIC. It implements a
*  simple AXI4-Lite state machine to convert to a
*  custom register-like interface.
*  The state machine was taken from https://github.com/openhwgroup/cva6/blob/20dec24d1b75ace4d54c63a7475233a8966c12dc/corev_apu/openpiton/riscv_peripherals.sv#L646-L744
* -----------------------------------------------
* Revision History
*  Revision   | Author     | Commit | Description
*  0.0        | atafalla   |
* -----------------------------------------------
*/

module plic_wrap #(
    parameter int ADDR_WIDTH         = 64,
    parameter int DATA_WIDTH         = 64,
    parameter int ID_BITWIDTH        = -1,  // width of the gateway identifiers
    parameter int PARAMETER_BITWIDTH = 1,   // width of the internal parameter e.g. priorities
    parameter int NUM_TARGETS        = 1,   // number of target slices
    parameter int NUM_SOURCES        = 1    // number of sources = number of gateways
) (
    input  logic                   clk_i,
    input  logic                   rst_ni,
    input  logic [NUM_SOURCES-1:0] irq_sources_i,
    output logic [NUM_TARGETS-1:0] eip_targets_o,

    axi_lite_if.in axi
);

  typedef enum logic [2:0] {
    Idle,
    WriteSecond,
    ReadSecond,
    WriteResp,
    ReadResp
  } state_t;
  state_t state_d, state_q;

  logic [DATA_WIDTH-1:0] rword_d, rword_q;

  reg_bus_if #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) reg_intf (
      .clk_i(clk_i)
  );

  assign rword_d = (reg_intf.valid && !reg_intf.write) ? reg_intf.rdata : rword_q;
  assign axi.r_data = rword_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin : p_plic_regs
    if (!rst_ni) begin
      state_q <= Idle;
      rword_q <= '0;
    end else begin
      state_q <= state_d;
      rword_q <= rword_d;
    end
  end

  // AXI State machine taken from https://github.com/openhwgroup/cva6/blob/20dec24d1b75ace4d54c63a7475233a8966c12dc/corev_apu/openpiton/riscv_peripherals.sv#L646-L744
  // this is a simplified AXI statemachine, since the
  // W and AW requests always arrive at the same time here
  always_comb begin : p_plic_if
    automatic logic [ADDR_WIDTH-1:0] waddr, raddr;
    // AXI-lite
    axi.aw_ready   = reg_intf.ready;
    axi.w_ready    = reg_intf.ready;
    axi.ar_ready   = reg_intf.ready;

    axi.r_valid    = 1'b0;
    axi.r_resp     = '0;
    axi.b_valid    = 1'b0;
    axi.b_resp     = '0;

    // PLIC
    reg_intf.valid = (axi.w_valid && axi.aw_valid) || axi.ar_valid;
    reg_intf.wstrb = axi.w_strb;
    reg_intf.write = 1'b0;
    reg_intf.wdata = axi.w_data[ADDR_WIDTH-1:0];
    reg_intf.addr  = axi.aw_addr[ADDR_WIDTH-1:0];

    // default
    state_d        = state_q;

    unique case (state_q)
      Idle: begin
        axi.b_valid = axi.b_ready;
        axi.r_valid = axi.r_ready;

        if (axi.w_valid && axi.aw_valid && reg_intf.ready) begin
          reg_intf.write = 1'b1;
          reg_intf.wstrb = axi.w_strb[3:0];
          state_d = WriteResp;
        end else if (axi.ar_valid && reg_intf.ready) begin
          reg_intf.addr = axi.ar_addr[ADDR_WIDTH-1:0];

          state_d = ReadResp;
        end
      end
      WriteResp: begin
        axi.aw_ready = 1'b0;
        axi.w_ready  = 1'b0;
        axi.ar_ready = 1'b0;
        if (axi.b_ready) begin
          axi.b_valid = 1'b1;
          state_d     = Idle;
        end
      end
      ReadResp: begin
        axi.aw_ready = 1'b0;
        axi.w_ready  = 1'b0;
        axi.ar_ready = 1'b0;
        if (axi.r_ready) begin
          axi.r_valid = 1'b1;
          state_d     = Idle;
        end
      end
      default: state_d = Idle;
    endcase
  end

  plic #(
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH),
      .ID_BITWIDTH(ID_BITWIDTH),
      .PARAMETER_BITWIDTH(PARAMETER_BITWIDTH),
      .NUM_TARGETS(NUM_TARGETS),
      .NUM_SOURCES(NUM_SOURCES)
  ) plic (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .irq_sources_i(irq_sources_i),
      .eip_targets_o(eip_targets_o),
      .external_bus_io(reg_intf)
  );

endmodule
;
