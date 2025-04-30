//!
//! **PROJECT:**             System_Verilog_Hardware_Common_Lib
//!
//! **LANGUAGE:**            SystemVerilog
//!
//! **FILE:**                plic.sv
//!
//! **AUTHOR(S):**
//!
//!   - Alejandro Tafalla - alejandro.tafalla@bsc.es
//!
//! **CONTRIBUTORS:**
//!
//!   -
//!
//! **REVISION:**
//!   * 0.0.1 - Initial release. 24/04/2024
//!
//!
//! *Library compliance:*
//!
//! | Doc | Schematic | TB | ASRT |Params. Val.| Sintesys test| Unify Interface| Functional Model |
//! |-----|-----------|----|------|------------|--------------|----------------|------------------|
//! |  ✔  |     ✔     |  x |   x  |     x      |       x      |        x       |         x        |
//!
//!

//! Module Functionality
//! --------------------
//! This is an interrupt controller compliant with the RISC-V Platform-Level Interrupt Controller v1.0 specification.
//! It provides a register based interface for configuring the priorities, enables and mappings of each interrupt to
//! each hart.
//! The basic architecture is the following: For each incoming interrupt there's a Gateway that handles the masking of
//! the interrupt while it is being handled by a core . The gateways output is collected by a comparison selector for
//! each target core, where the IRQ with the most priority is selected and compared against the threshold priority
//! value. If it's greater, the External Interrupt Pending signal is asserted. The PLIC Interface is in charge of
//! keeping the state of the controller, storing the arrays of priorities, thresholds and interrupt enables. The
//! Claim-Complete tracker remembers which core has claimed which interrupt and drives the gateways for masking.

// Original License Header
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
    parameter int PARAMETER_BITWIDTH  = 7,   //! width of the internal parameter e.g. priorities
    parameter int NUM_TARGETS         = 2,   //! Number of target slices
    parameter int NUM_SOURCES         = 4,   //! number of sources = number of gateways
    parameter int COMB_CMP_SEL        = 0,   //! Combinational selection of the highest priority IRQ

    // Do not edit
    localparam int ADDR_WIDTH = 32,
    localparam int DATA_WIDTH = 32,
    localparam int BPW = DATA_WIDTH / 8,     //! how many bytes a data word consist of
    localparam int ID_BITWIDTH    = $clog2(NUM_SOURCES+1)
) (
    input  logic                           clk_i,
    input  logic                           rstn_i,
    input  logic         [NUM_SOURCES-1:0] irq_sources_i,   //! interrupt sources inputs
    output logic         [NUM_TARGETS-1:0] eip_targets_o,   //! interrupt pending outputs

    // Bus interface
    input  logic [ADDR_WIDTH-1:0] sri_addr_i,               //! register interface address
    input  logic                  sri_en_i,                 //! register interface enable
    input  logic [DATA_WIDTH-1:0] sri_wdata_i,              //! register interface data to write
    input  logic                  sri_we_i,                 //! register interface write enable
    input  logic [BPW-1:0]        sri_be_i,                 //! register interface byte enable (write mask)
    output logic [DATA_WIDTH-1:0] sri_rdata_o,              //! register interface read data
    output logic                  sri_error_o               //! register interface error
);

  // declare all local variables
  // gateway arrays always go from NUM_SOURCES to 1 because gateway ids start at 1
  logic                           gateway_irq_pendings  [NUM_SOURCES-1:0];   //! for pending irqs of the gateways
  logic                           gateway_claimed       [NUM_SOURCES-1:0];   //! if a gateway is claimed, it masks its irq
  logic                           gateway_completed     [NUM_SOURCES-1:0];   //! if a gateway is completed, it is reenabled
  logic [ID_BITWIDTH-1:0]         gateway_ids           [NUM_SOURCES-1:0];   //! ids of gateways
  logic [PARAMETER_BITWIDTH-1:0]  gateway_priorities    [NUM_SOURCES-1:0];   //!priorities of gateways

  logic                           irq_enableds                              [NUM_SOURCES-1:0][NUM_TARGETS-1:0];
  logic [PARAMETER_BITWIDTH-1:0]  target_thresholds                         [NUM_TARGETS-1:0];
  logic [ID_BITWIDTH-1:0]         identifier_of_largest_priority_per_target [NUM_TARGETS-1:0];

  logic                   target_irq_claims       [NUM_TARGETS-1:0];
  logic                   target_irq_completes    [NUM_TARGETS-1:0];
  logic [ID_BITWIDTH-1:0] target_irq_completes_id [NUM_TARGETS-1:0];

  logic [NUM_TARGETS-1:0] flush_cmp_pipeline;
  logic                   flush_all_targets;

  // Generate flush signals
  for (genvar i=0; i < NUM_TARGETS; i++) begin
    assign flush_cmp_pipeline[i] = target_irq_claims[i] & eip_targets_o[i];
  end
  assign flush_all_targets = |flush_cmp_pipeline;

  logic [NUM_SOURCES-1:0] irq_sources_int;

  // IRQ synchronizer
  generate
    for (genvar i = 0; i < NUM_SOURCES; i++) begin : g_irq_sync
        logic [1:0] reg_q;

        assign irq_sources_int[i] = reg_q[1];

        always_ff @(posedge clk_i or negedge rstn_i) begin
          if (!rstn_i) begin
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
        .rstn_i       (rstn_i),
        .irq_source_i (irq_sources_int[counter]),
        .claim_i      (gateway_claimed[counter]),
        .completed_i  (gateway_completed[counter]),
        .irq_pending_o(gateway_irq_pendings[counter])
    );
  end

  // assign ids to gateways
  for (genvar counter = 1; counter <= NUM_SOURCES; counter++) begin
    assign gateway_ids[counter-1] = ID_BITWIDTH'(counter);

  end

  // instantiate and connect target slices
  for (genvar counter = 0; counter < NUM_TARGETS; counter++) begin : gen_plic_target_slice

    logic irq_enableds_slice[NUM_SOURCES-1:0];
    for (genvar inner_counter = 0; inner_counter < NUM_SOURCES; inner_counter++) begin
      assign irq_enableds_slice[inner_counter] = irq_enableds[inner_counter][counter];
    end

    plic_target_slice #(
        .PRIORITY_BITWIDTH      (PARAMETER_BITWIDTH),
        .NUM_GATEWAYS           (NUM_SOURCES),
        .COMB_CMP_SEL           (COMB_CMP_SEL)
    ) plic_target_slice_instance (
        .clk_i                  (clk_i),
        .rstn_i                 (rstn_i),
        .flush_cmp_pipeline_i   (flush_all_targets),
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
      .clk_i                    (clk_i),
      .rstn_i                   (rstn_i),
      .id_of_largest_priority_i (identifier_of_largest_priority_per_target),
      .pending_array_i          (gateway_irq_pendings),
      .thresholds_o             (target_thresholds),
      .gateway_priorities_o     (gateway_priorities),
      .irq_enables_o            (irq_enableds),
      .target_irq_claims_o      (target_irq_claims),
      .target_irq_completes_o   (target_irq_completes),
      .target_irq_completes_id_o(target_irq_completes_id),
      .addr_i                   (sri_addr_i),
      .en_i                     (sri_en_i),
      .wdata_i                  (sri_wdata_i),
      .we_i                     (sri_we_i),
      .be_i                     (sri_be_i),
      .rdata_o                  (sri_rdata_o),
      .error_o                  (sri_error_o)
  );

  //instantiate and connect claim_complete_tracker
  plic_claim_complete_tracker #(
      .NUM_TARGETS (NUM_TARGETS),
      .NUM_GATEWAYS(NUM_SOURCES)
  ) plic_claim_complete_tracker_instance (
      .clk_i                                    (clk_i),
      .rstn_i                                   (rstn_i),
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
    // assert ((ADDR_WIDTH == 32) | (ADDR_WIDTH == 64))
    // else $error("Address width has to bei either 32 or 64 bit");
    // assert ((DATA_WIDTH == 32) | (DATA_WIDTH == 64))
    // else $error("Data width has to bei either 32 or 64 bit");
    assert (PARAMETER_BITWIDTH > 0)
    else $error("PARAMETER_BITWIDTH has to be larger than 1");
    assert(PARAMETER_BITWIDTH < 32)
    else $error("PARAMETER_BITWIDTH has to be smaller than 8");
    assert (NUM_SOURCES >= 2)
    else $error("Num of sources has to be larger than 1");
    assert (NUM_SOURCES < 512)
    else $error("Num of sources has to be smaller than 512");
    assert (NUM_TARGETS > 0)
    else $error("Num of targets has to be larger than 1");
    assert (NUM_TARGETS < 15872)
    else $error("Num of targets has to be smaller than 15872");
  end
`endif
  //pragma translate_on
 
  `ifdef SARG_PITON_ILA
    (* dont_touch="true", mark_debug="true" *) logic         [NUM_SOURCES-1:0] dbg_irq_sources_i;
    (* dont_touch="true", mark_debug="true" *) logic         [NUM_TARGETS-1:0] dbg_eip_targets_o;
    (* dont_touch="true", mark_debug="true" *) logic [ADDR_WIDTH-1:0]          dbg_sri_addr_i;
    (* dont_touch="true", mark_debug="true" *) logic                           dbg_sri_en_i;
    (* dont_touch="true", mark_debug="true" *) logic [DATA_WIDTH-1:0]          dbg_sri_wdata_i;
    (* dont_touch="true", mark_debug="true" *) logic                           dbg_sri_we_i;
    (* dont_touch="true", mark_debug="true" *) logic [BPW-1:0]                 dbg_sri_be_i;
    (* dont_touch="true", mark_debug="true" *) logic [DATA_WIDTH-1:0]          dbg_sri_rdata_o;
    (* dont_touch="true", mark_debug="true" *) logic                           dbg_sri_error_o;

    always_comb begin
       dbg_irq_sources_i = irq_sources_i;
       dbg_eip_targets_o = eip_targets_o;
       dbg_sri_addr_i    = sri_addr_i;
       dbg_sri_en_i      = sri_en_i;
       dbg_sri_wdata_i   = sri_wdata_i;
       dbg_sri_we_i      = sri_we_i;
       dbg_sri_be_i      = sri_be_i;
       dbg_sri_rdata_o   = sri_rdata_o;
       dbg_sri_error_o   = sri_error_o;
    end

  `endif 
endmodule
