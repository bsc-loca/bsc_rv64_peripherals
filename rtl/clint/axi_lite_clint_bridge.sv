// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the “License”); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
// Author: Florian Zaruba, ETH Zurich
// Date: 17/07/2017
// Description: AXI Lite compatible interface
//

// Edited at Barcelona Supercomputing Center by Alejandro Tafalla
// 9/10/23: Formatting, Expanded AXI ports from struct type

module axi_lite_clint_bridge #(
    parameter int unsigned AXI_ADDR_WIDTH = 64,
    parameter int unsigned AXI_DATA_WIDTH = 64,
    parameter int unsigned AXI_ID_WIDTH   = 10
) (
    input logic clk_i,  // Clock
    input logic rst_ni, // Asynchronous reset active low

    // AXI Signals
    // address write
    axi_lite_if.in axi,

    output logic [    AXI_ADDR_WIDTH-1:0] address_o,
    output logic                          en_o,       // transaction is valid
    output logic                          we_o,       // write
    output logic [(AXI_DATA_WIDTH/8)-1:0] be_o,       // byte enable write
    input  logic [    AXI_DATA_WIDTH-1:0] data_i,     // data
    output logic [    AXI_DATA_WIDTH-1:0] data_o
);

  // The RLAST signal is not required, and is considered asserted for every transfer on the read data channel.
  typedef enum logic [1:0] {
    IDLE,
    READ,
    WRITE,
    WRITE_B
  } state_t;
  state_t state_q, state_d;

  // address register
  logic [AXI_ADDR_WIDTH-1:0] address_n, address_q;

  // pass through read data on the read data channel
  assign axi.r_data = data_i;
  // // we do not support any errors so set response flag to all zeros
  assign b.resp = 2'b0;
  assign r.resp = 2'b0;
  // output data which we want to write to the slave
  assign data_o = axi.w_data;
  assign be_o = axi.w_strb;
  // ------------------------
  // AXI4-Lite State Machine
  // ------------------------
  always_comb begin
    // default signal assignment
    state_d      = state_q;
    address_n    = address_q;
    // trans_id_n = trans_id_q;

    // we'll answer a write request only if we got address and data
    axi.aw_ready = 1'b0;
    axi.w_ready  = 1'b0;
    axi.b_valid  = 1'b0;

    axi.ar_ready = 1'b0;
    axi.r_valid  = 1'b0;

    address_o    = '0;
    we_o         = 1'b0;
    en_o         = 1'b0;

    case (state_q)
      // we are ready to accept a new request
      IDLE: begin
        // we've git a valid write request, we also know that we have asserted the aw_ready
        if (axi.aw_valid) begin
          axi.aw_ready = 1'b1;
          // this costs performance but the interconnect does not obey the AXI standard
          // e.g.: we could wait for aw_valid && w_valid to do the transaction.
          state_d = WRITE;
          // save address
          address_n = axi.aw_addr;
          // save the transaction id for reflection
          // trans_id_n = aw.id;

          // we've got a valid read request, we also know that we have asserted the ar_ready
        end else if (axi.ar_valid) begin
          axi.ar_ready = 1'b1;
          state_d = READ;
          // save address
          address_n = axi.ar_addr;
          // save the transaction id for reflection
          // trans_id_n = ar.id;

        end
      end
      // We've got a read request at least one cycle earlier
      // so data_i will already contain the data we'd like tor read
      READ: begin
        // enable the ram-like
        en_o        = 1'b1;
        // further assert the correct address
        address_o   = address_q;
        // the read is valid
        axi.r_valid = 1'b1;
        // check if we got a valid r_ready and go back to IDLE
        if (axi.r_ready) state_d = IDLE;
      end
      // We've got a write request at least one cycle earlier
      // wait here for the data
      WRITE: begin
        if (axi.w_valid) begin
          axi.w_ready = 1'b1;
          // use the latched address
          address_o = address_q;
          en_o = 1'b1;
          we_o = 1'b1;
          // close this request
          state_d = WRITE_B;
        end
      end

      WRITE_B: begin
        axi.b_valid = 1'b1;
        // we've already performed the write here so wait for the ready signal
        if (axi.b_ready) state_d = IDLE;
      end
      default: ;

    endcase
  end

  // ------------------------
  // Registers
  // ------------------------
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q   <= IDLE;
      address_q <= '0;
      // trans_id_q <= '0;
    end else begin
      state_q   <= state_d;
      address_q <= address_n;
      // trans_id_q <= trans_id_n;
    end
  end

  // ------------------------
  // Assertions
  // ------------------------
  // Listen for illegal transactions
  //pragma translate_off
  // `ifndef VERILATOR
  //   // check that burst length is just one
  //   assert property (@(posedge clk_i) ar_valid |-> ((ar_len == 8'b0)))
  //   else begin
  //     $error(
  //         "AXI Lite does not support bursts larger than 1 or byte length unequal to the native bus size");
  //     $stop();
  //   end
  //   // do the same for the write channel
  //   assert property (@(posedge clk_i) aw_valid |-> ((aw.len == 8'b0)))
  //   else begin
  //     $error(
  //         "AXI Lite does not support bursts larger than 1 or byte length unequal to the native bus size");
  //     $stop();
  //   end
  // `endif
  //pragma translate_on
endmodule
