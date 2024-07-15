// This AXI module is non-compliant. It can't handle 8B aligned accesses and strobes of
// the 4 most significant bytes.


module plic_axi_wrapper #(
    parameter int ADDR_WIDTH         = 64,
    parameter int DATA_WIDTH         = 64,
    parameter int PARAMETER_BITWIDTH = 7,   // width of the internal parameter e.g. priorities
    parameter int NUM_TARGETS        = 2,   // number of target slices
    parameter int NUM_SOURCES        = 64,   // number of sources = number of gateways
    localparam int Bpw = DATA_WIDTH / 8  // how many bytes a data word consist of
) (
    input  logic                   clk_i,
    input  logic                   rst_ni,
    input  logic [NUM_SOURCES-1:0] irq_sources_i,
    output logic [NUM_TARGETS-1:0] eip_targets_o,

    // AXI4-Lite
    input  logic                  axi_arvalid,
    input  logic [ADDR_WIDTH-1:0] axi_araddr,
    output logic                  axi_arready,

    input  logic                  axi_awvalid,
    input  logic [ADDR_WIDTH-1:0] axi_awaddr,
    output logic                  axi_awready,

    input  logic                  axi_wvalid,
    input  logic [DATA_WIDTH-1:0] axi_wdata,
    input  logic [       Bpw-1:0] axi_wstrb,
    output logic                  axi_wready,

    input  logic                  axi_rready,
    output logic                  axi_rvalid,
    output logic [DATA_WIDTH-1:0] axi_rdata,
    output logic [           1:0] axi_rresp,

    input  logic                  axi_bready,
    output logic                  axi_bvalid,
    output logic [           1:0] axi_bresp
);
  logic [31:0] addr;
  logic        en, we, error;
  logic [3:0]  be;
  logic [31:0] rdata, wdata;

  typedef enum logic [2:0] {
    Idle,
    WriteSecond,
    ReadSecond,
    WriteResp,
    ReadResp
  } state_t;
  state_t state_d, state_q;
  logic [DATA_WIDTH-1:0] rword_d, rword_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin : p_plic_regs
    if (!rst_ni) begin
      state_q <= Idle;
      rword_q <= '0;
    end else begin
      state_q <= state_d;
      rword_q <= rword_d;
    end
  end

  assign axi_rdata = rword_q;

  always_comb begin : p_plic_if
    // AXI-lite
    axi_awready = 1'b1;
    axi_wready  = 1'b1;
    axi_arready = 1'b1;

    axi_rvalid  = 1'b0;
    axi_rresp   = 2'b0;
    axi_bvalid  = 1'b0;
    axi_bresp   = 2'b0;

    // PLIC
    en          = 1'b0;
    we          = 1'b0;
    addr = 'b0;
    wdata = 'b0;
    be = 'b0;

    rword_d     = rword_q;

    // default
    state_d     = state_q;

    unique case (state_q)
      Idle: begin
        if (axi_wvalid && axi_awvalid) begin
          en = 1'b1;
          we = 1'b1;
          addr  = axi_awaddr[31:0];
          be    = axi_wstrb[3:0];
          wdata = axi_wdata[31:0];
          state_d = WriteResp;
        end else if (axi_arvalid) begin
          en = 1'b1;
          addr  = axi_araddr[31:0];
          rword_d[31:0]  = rdata;
          rword_d[63:32] = 'b0;
          state_d = ReadResp;
        end
      end
      WriteResp: begin
        axi_awready = 1'b0;
        axi_wready  = 1'b0;
        axi_arready = 1'b0;
        if (axi_bready) begin
          axi_bresp = 2'b0;
          if (error) begin
            axi_bresp = 2'b10; //SLVERR
          end
          axi_bvalid = 1'b1;
          state_d = Idle;
        end
      end
      ReadResp: begin
        axi_awready = 1'b0;
        axi_wready  = 1'b0;
        axi_arready = 1'b0;
        if (axi_rready) begin
          if (error) begin
            axi_rresp = 2'b10; // SLVERR
          end
          axi_rvalid  = 1'b1;
          state_d = Idle;
        end
      end
      default: state_d = Idle;
    endcase
  end

  plic #(
      .PARAMETER_BITWIDTH(PARAMETER_BITWIDTH),
      .NUM_TARGETS(NUM_TARGETS),
      .NUM_SOURCES(NUM_SOURCES)
  ) plic_inst (
      .clk_i,
      .rst_ni,
      .irq_sources_i,
      .eip_targets_o,

      .addr,
      .en,
      .wdata,
      .we,
      .be,
      .rdata,
      .error
  );

  // initial begin
  //   assert (ADDR_WIDTH == 64)
  //   else $error("Only address width of 64b supported for now");

  //   assert (DATA_WIDTH == 64)
  //   else $error("Only address width of 64b supported for now");
  // end
endmodule
