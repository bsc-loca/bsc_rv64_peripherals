// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.
//
//-------------------------------------------------------------------------------
//-- Title      : PLIC Core
//-- File       : plic_core.sv
//-- Author     : Gian Marti      <gimarti.student.ethz.ch>
//-- Author     : Thomas Kramer   <tkramer.student.ethz.ch>
//-- Author     : Thomas E. Benz  <tbenz.student.ethz.ch>
//-- Author     : Alejandro Tafalla <atafalla@bsc.es>
//-- Company    : Integrated Systems Laboratory, ETH Zurich
//-- Company    : Barcelona Supercomputing Center
//-- Created    : 2018-03-31
//-- Last update: 2024-02-20
//-- Platform   : ModelSim (simulation), Synopsys (synthesis)
//-- Standard   : SystemVerilog IEEE 1800-2012
//-------------------------------------------------------------------------------
//-- Description: PLIC Top-level
//-------------------------------------------------------------------------------
//-- Revisions  :
//-- Date        Version  Author   Description
//-- 2018-03-31  2.0      tbenz    Created header
//-- 2024-02-20  3.0      atafalla Refactoring, fix linting issues
//-------------------------------------------------------------------------------

module plic #(
    parameter int PARAMETER_BITWIDTH = 1,  // width of the internal parameter e.g. priorities
    parameter int NUM_TARGETS = 2,  // number of target slices
    parameter int NUM_SOURCES = 2,  // number of sources = number of gateways
    localparam int ADDR_WIDTH = 32,
    localparam int DATA_WIDTH = 32,
    localparam int Bpw = DATA_WIDTH / 8,  // how many bytes a data word consist of
    localparam int IdBitwidth    = $clog2(NUM_SOURCES+1)
) (
    input  logic                           clk_i,
    input  logic                           rst_ni,
    input  logic         [NUM_SOURCES-1:0] irq_sources_i,
    output logic         [NUM_TARGETS-1:0] eip_targets_o,

    // Bus interface
    input logic [ADDR_WIDTH-1:0]  addr,
    input logic                   en,
    input logic [DATA_WIDTH-1:0]  wdata,
    input logic                   we,
    input logic [Bpw-1:0]         be,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                  error
);

  // declare all local variables
  // gateway arrays always go from NUM_SOURCES to 1 because gateway ids start at 1
  logic gateway_irq_pendings[NUM_SOURCES];  //for pending irqs of the gateways
  logic gateway_claimed[NUM_SOURCES];  //if a gateway is claimed, it masks its irq
  logic gateway_completed[NUM_SOURCES];  //if a gateway is completed, it is reenabled
  logic [IdBitwidth-1:0] gateway_ids[NUM_SOURCES];  //ids of gateways
  logic [PARAMETER_BITWIDTH-1:0] gateway_priorities[NUM_SOURCES];  //priorities of gateways

  logic irq_enableds[NUM_SOURCES][NUM_TARGETS];
  logic [PARAMETER_BITWIDTH-1:0] target_thresholds[NUM_TARGETS];
  logic [IdBitwidth-1:0] identifier_of_largest_priority_per_target[NUM_TARGETS];

  logic target_irq_claims[NUM_TARGETS];
  logic target_irq_completes[NUM_TARGETS];
  logic [IdBitwidth-1:0] target_irq_completes_id[NUM_TARGETS];

  logic [NUM_SOURCES-1:0] irq_sources_int;

  generate
    for (genvar i = 0; i < NUM_SOURCES; i++) begin : g_irq_sync
        logic [1:0] reg_q;

        assign irq_sources_int[i] = reg_q[1];

        always_ff @(posedge clk_i) begin
          if (!rst_ni) begin
            reg_q <= 'h0;
          end else begin
            reg_q <= {reg_q[0], irq_sources_i[i]};
          end
        end
    end
  endgenerate

  //instantiate and connect gateways
  for (genvar counter = 0; counter < NUM_SOURCES; counter++) begin : gen_plic_gateway
    plic_gateway plic_gateway_instance (
        .clk_i        (clk_i),
        .rst_ni       (rst_ni),
        .irq_source_i (irq_sources_int[counter]),
        .claim_i      (gateway_claimed[counter]),
        .completed_i  (gateway_completed[counter]),
        .irq_pending_o(gateway_irq_pendings[counter])
    );
  end

  // assign ids to gateways
  for (genvar counter = 1; counter <= NUM_SOURCES; counter++) begin
    assign gateway_ids[counter-1] = IdBitwidth'(counter);

  end

  // instantiate and connect target slices
  for (genvar counter = 0; counter < NUM_TARGETS; counter++) begin : gen_plic_target_slice

    logic irq_enableds_slice[NUM_SOURCES];
    for (genvar inner_counter = 0; inner_counter < NUM_SOURCES; inner_counter++) begin
      assign irq_enableds_slice[inner_counter] = irq_enableds[inner_counter][counter];
    end

    plic_target_slice #(
        .PRIORITY_BITWIDTH(PARAMETER_BITWIDTH),
        .NUM_GATEWAYS     (NUM_SOURCES)
    ) plic_target_slice_instance (
        .interrupt_pending_i    (gateway_irq_pendings),
        .interrupt_priority_i   (gateway_priorities),
        .interrupt_id_i         (gateway_ids),
        .interrupt_enable_i     (irq_enableds_slice),
        .threshold_i            (target_thresholds[counter]),
        .ext_interrupt_present_o(eip_targets_o[counter]),
        .identifier_of_largest_o(identifier_of_largest_priority_per_target[counter])
    );
  end

  //instantiate and connect plic_interface
  plic_interface #(
      .ADDR_WIDTH        (ADDR_WIDTH),
      .DATA_WIDTH        (DATA_WIDTH),
      .PARAMETER_BITWIDTH(PARAMETER_BITWIDTH),
      .NUM_TARGETS       (NUM_TARGETS),
      .NUM_GATEWAYS      (NUM_SOURCES)
  ) plic_interface_instance (
      .clk_i,
      .rst_ni,
      .id_of_largest_priority_i (identifier_of_largest_priority_per_target),
      .pending_array_i          (gateway_irq_pendings),
      .thresholds_o             (target_thresholds),
      .gateway_priorities_o     (gateway_priorities),
      .irq_enables_o            (irq_enableds),
      .target_irq_claims_o      (target_irq_claims),
      .target_irq_completes_o   (target_irq_completes),
      .target_irq_completes_id_o(target_irq_completes_id),
      .addr,
      .en,
      .wdata,
      .we,
      .be,
      .rdata,
      .error
  );

  //instantiate and connect claim_complete_tracker
  plic_claim_complete_tracker #(
      .NUM_TARGETS (NUM_TARGETS),
      .NUM_GATEWAYS(NUM_SOURCES)
  ) plic_claim_complete_tracker_instance (
      .clk_i                                    (clk_i),
      .rst_ni                                   (rst_ni),
      .identifier_of_largest_priority_per_target(identifier_of_largest_priority_per_target),
      .target_irq_claims_i                      (target_irq_claims),
      .target_irq_completes_i                   (target_irq_completes),
      .target_irq_completes_identifier_i        (target_irq_completes_id),
      .gateway_irq_claims_o                     (gateway_claimed),
      .gateway_irq_completes_o                  (gateway_completed)
  );

  //pragma translate_off
`ifndef VERILATOR
  initial begin
    assert ((ADDR_WIDTH == 32) | (ADDR_WIDTH == 64))
    else $error("Address width has to bei either 32 or 64 bit");
    assert ((DATA_WIDTH == 32) | (DATA_WIDTH == 64))
    else $error("Data width has to bei either 32 or 64 bit");
    assert (PARAMETER_BITWIDTH > 0)
    else $error("PARAMETER_BITWIDTH has to be larger than 1");
    //assert(PARAMETER_BITWIDTH < 8)                  else $error("PARAMETER_BITWIDTH has to be smaller than 8");
    assert (NUM_SOURCES > 0)
    else $error("Num od Gateways has to be larger than 1");
    assert (NUM_SOURCES < 512)
    else $error("Num of Gateways has to be smaller than 512");
    assert (NUM_TARGETS > 0)
    else $error("Num Target slices has to be larger than 1");
    assert (NUM_TARGETS < 15872)
    else $error("Num target slices has to be smaller than 15872");
  end
`endif
  //pragma translate_on
endmodule
