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
//-- Title      : Target Slice
//-- File       : plic_target_slice.sv
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
//-- Description: Target Slice
//-------------------------------------------------------------------------------
//-- Revisions  :
//-- Date        Version  Author  Description
//-- 2018-03-31  2.0      tbenz   Created header
//-- 2024-02-20  3.0      atafalla Refactoring, fix linting issues
//-------------------------------------------------------------------------------

// Note: The gateways are expected to be ordered by their IDs (ascending).
// This resolves priority ties by choosing the gateway with the lower ID.
module plic_target_slice #(
    parameter int PRIORITY_BITWIDTH = 8,
    parameter int NUM_GATEWAYS      = 2,
    localparam int IdBitwidth = $clog2(NUM_GATEWAYS + 1) // the +1 is because counting starts from 1 and goes to NUM_GATEWAYS+1
) (
    // Input signals from gateways.
    input  logic                         clk_i,
    input  logic                         rst_ni,
    input  logic                         flush_cmp_pipeline_i,
    input  logic                         interrupt_pending_i    [NUM_GATEWAYS],
    input  logic [PRIORITY_BITWIDTH-1:0] interrupt_priority_i   [NUM_GATEWAYS],
    input  logic [       IdBitwidth-1:0] interrupt_id_i         [NUM_GATEWAYS],
    input  logic                         interrupt_enable_i     [NUM_GATEWAYS],
    input  logic [PRIORITY_BITWIDTH-1:0] threshold_i,
    output logic                         ext_interrupt_present_o,
    output logic [       IdBitwidth-1:0] identifier_of_largest_o
);
  logic [PRIORITY_BITWIDTH:0] interrupt_priority_masked[NUM_GATEWAYS];


  // Signals that represent the selected interrupt source.
  logic [PRIORITY_BITWIDTH:0] best_priority;
  logic [     IdBitwidth-1:0] best_id;
  logic                       best_valid;

  comparison_pipeline_selector_flush # (
    .MTHAN_LTHAN(1'b1),
    .N_PORTS(NUM_GATEWAYS),
    .ID_SIZE(IdBitwidth),
    .DATA_WIDTH(PRIORITY_BITWIDTH + 1),
    .REG_PATTERN({{($clog2(NUM_GATEWAYS)-1){1'b1}}, 1'b0})
  ) find_max_prio (
    .clk_i(clk_i),
    .rstn_i(rst_ni),

    .flush_i(flush_cmp_pipeline_i),

    .comp_en_i(interrupt_pending_i),
    .comparation_regs_i(interrupt_priority_masked),
    .ids_of_regs_i(interrupt_id_i),

    .valid_o(best_valid),
    .selected_value_o(best_priority),
    .selected_id_o(best_id)
  );

  // Compare the priority of the best interrupt source to the threshold.
  always_comb begin : proc_compare_threshold
    if (((best_priority - 1) > threshold_i) && (best_priority != '0)) begin
      ext_interrupt_present_o = best_valid;
      identifier_of_largest_o = best_id;
    end else begin
      if (((best_priority - 1) <= threshold_i) && (best_priority != '0)) begin
        ext_interrupt_present_o = 0;
        identifier_of_largest_o = best_id;
      end else begin
        ext_interrupt_present_o = 0;
        identifier_of_largest_o = 0;
      end
    end
  end

  always_comb begin : proc_mask_gateway_outputs
    for (int i = 0; i < NUM_GATEWAYS; i++) begin
      if (interrupt_enable_i[i] && interrupt_pending_i[i]) begin
        interrupt_priority_masked[i] = interrupt_priority_i[i] + 1;  //priority shift +1
      end else begin
        interrupt_priority_masked[i] = '0;
      end
    end
  end
endmodule
