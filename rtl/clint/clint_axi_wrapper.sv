module clint_axi_wrapper #(
    parameter int NR_CORES   = 1,
    parameter int ADDR_WIDTH = 64,
    parameter int DATA_WIDTH = 64,
    localparam int Bpw = DATA_WIDTH / 8
) (
    input logic clk_i,
    input logic rst_ni,

    input  logic                rtc_i,        // Real-time clock in (usually 32.768 kHz)
    output logic [NR_CORES-1:0] timer_irq_o,  // Timer interrupts
    output logic [NR_CORES-1:0] ipi_o,        // software interrupt (a.k.a inter-process-interrupt)
    output logic [63:0]         time_o,

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

    input  logic       axi_bready,
    output logic       axi_bvalid,
    output logic [1:0] axi_bresp
);
  logic [ADDR_WIDTH-1:0] addr;
  logic en, we, error;
  logic [Bpw-1:0] be;
  logic [DATA_WIDTH-1:0] rdata, wdata;

  typedef enum logic [1:0] {
    IDLE,
    READ,
    WRITE,
    WRITE_B
  } state_t;
  state_t state_q, state_d;

  // address register
  logic [ADDR_WIDTH-1:0] address_n, address_q;

  // pass through read data on the read data channel
  assign axi_rdata = rdata;
  // output data which we want to write to the slave
  assign wdata = axi_wdata;
  assign be = axi_wstrb;

  // ------------------------
  // AXI4-Lite State Machine
  // ------------------------
  always_comb begin
    // default signal assignment
    state_d     = state_q;
    address_n   = address_q;

    // we'll answer a write request only if we got address and data
    axi_awready = 1'b0;
    axi_wready  = 1'b0;
    axi_bvalid  = 1'b0;
    axi_bresp   = 2'b0;

    axi_arready = 1'b0;
    axi_rvalid  = 1'b0;
    axi_rresp   = 2'b0;

    addr        = '0;
    we          = 1'b0;
    en          = 1'b0;

    case (state_q)
      // we are ready to accept a new request
      IDLE: begin
        // we've git a valid write request, we also know that we have asserted the awready
        if (axi_awvalid) begin
          axi_awready = 1'b1;
          // this costs performance but the interconnect does not obey the AXI standard
          // e.g.: we could wait for awvalid && wvalid to do the transaction.
          state_d = WRITE;
          // save address
          address_n = axi_awaddr;

          // we've got a valid read request, we also know that we have asserted the arready
        end else if (axi_arvalid) begin
          axi_arready = 1'b1;
          state_d = READ;
          // save address
          address_n = axi_araddr;
        end
      end
      // We've got a read request at least one cycle earlier
      // so data_i will already contain the data we'd like tor read
      READ: begin
        // enable the ram-like
        en         = 1'b1;
        // further assert the correct address
        addr       = address_q;
        // the read is valid
        axi_rvalid = 1'b1;
        if (error) begin
          axi_rresp = 2'b10; //SLVERR
        end
        // check if we got a valid rready and go back to IDLE
        if (axi_rready) state_d = IDLE;
      end
      // We've got a write request at least one cycle earlier
      // wait here for the data
      WRITE: begin
        if (axi_wvalid) begin
          axi_wready = 1'b1;
          // use the latched address
          addr = address_q;
          en = 1'b1;
          we = 1'b1;
          // close this request
          state_d = WRITE_B;
        end
      end

      WRITE_B: begin
        axi_bvalid = 1'b1;
        if (error) begin
          axi_bresp = 2'b10; //SLVERR
        end
        // we've already performed the write here so wait for the ready signal
        if (axi_bready) state_d = IDLE;
      end
      default: state_d = IDLE;
    endcase
  end

  // ------------------------
  // Registers
  // ------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q   <= IDLE;
      address_q <= '0;
    end else begin
      state_q   <= state_d;
      address_q <= address_n;
    end
  end

  clint #(
      .NR_CORES(NR_CORES),
      .ADDR_WIDTH(ADDR_WIDTH),
      .DATA_WIDTH(DATA_WIDTH)
  ) clint_inst (
      .clk_i          (clk_i),
      .rstn_i         (rst_ni),

      .sri_addr_i     (addr),
      .sri_en_i       (en),
      .sri_wdata_i    (wdata),
      .sri_we_i       (we), 
      .sri_be_i       (be),
      .sri_rdata_o    (rdata),
      .sri_error_o    (error),

      .rtc_i          (rtc_i),
      .timer_irq_o    (timer_irq_o),
      .ipi_o          (ipi_o),
      .time_o         (time_o)
  );

endmodule
