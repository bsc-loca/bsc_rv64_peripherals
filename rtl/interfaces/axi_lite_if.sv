/// An AXI4-Lite interface.
// Code taken from Ariane Core (piton/design/chip/tile/ariane/core/include/axi_intf.sv)
// Moved out so we don't have a dependency on ariane repo

interface axi_lite_if #(
    parameter int AXI_ADDR_WIDTH = 64,
    parameter int AXI_DATA_WIDTH = 64
);

  localparam int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;

  typedef logic [AXI_ADDR_WIDTH-1:0] addr_t;
  typedef logic [AXI_DATA_WIDTH-1:0] data_t;
  typedef logic [AXI_STRB_WIDTH-1:0] strb_t;
  typedef logic [1:0] resp_t;
  typedef logic [1:0] prot_t;

  // AW channel
  addr_t aw_addr;
  prot_t aw_prot;
  logic  aw_valid;
  logic  aw_ready;

  data_t w_data;
  strb_t w_strb;
  logic  w_valid;
  logic  w_ready;

  resp_t b_resp;
  logic  b_valid;
  logic  b_ready;

  addr_t ar_addr;
  prot_t ar_prot;
  logic  ar_valid;
  logic  ar_ready;

  data_t r_data;
  resp_t r_resp;
  logic  r_valid;
  logic  r_ready;

  modport Master(
      output aw_addr, aw_prot, aw_valid,
      input aw_ready,
      output w_data, w_strb, w_valid,
      input w_ready,
      input b_resp, b_valid,
      output b_ready,
      output ar_addr, ar_prot, ar_valid,
      input ar_ready,
      input r_data, r_resp, r_valid,
      output r_ready
  );

  modport Slave(
      input aw_addr, aw_prot, aw_valid,
      output aw_ready,
      input w_data, w_strb, w_valid,
      output w_ready,
      output b_resp, b_valid,
      input b_ready,
      input ar_addr, ar_prot, ar_valid,
      output ar_ready,
      output r_data, r_resp, r_valid,
      input r_ready
  );

  /// The interface as an output (issuing requests, initiator, master).
  modport out(
      output aw_addr, aw_valid,
      input aw_ready,
      output w_data, w_strb, w_valid,
      input w_ready,
      input b_resp, b_valid,
      output b_ready,
      output ar_addr, ar_valid,
      input ar_ready,
      input r_data, r_resp, r_valid,
      output r_ready
  );

  /// The interface as an input (accepting requests, target, slave).
  modport in(
      input aw_addr, aw_valid,
      output aw_ready,
      input w_data, w_strb, w_valid,
      output w_ready,
      output b_resp, b_valid,
      input b_ready,
      input ar_addr, ar_valid,
      output ar_ready,
      output r_data, r_resp, r_valid,
      input r_ready
  );

endinterface  // axi_lite
