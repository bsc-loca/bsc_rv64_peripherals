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
//-- Title      : Find Maximun
//-- File       : plic_find_max.sv
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
//-- Description: Find the element with the largest priority
//-------------------------------------------------------------------------------
//-- Revisions  :
//-- Date        Version  Author   Description
//-- 2018-03-31  2.0      tbenz    Created header
//-- 2024-02-20  3.0      atafalla Refactoring, fix linting issues
//-------------------------------------------------------------------------------

module plic_find_max #(
    parameter int NUM_OPERANDS      = 2,
    parameter int ID_BITWIDTH       = 4,
    parameter int PRIORITY_BITWIDTH = 3
) (
    input  logic [PRIORITY_BITWIDTH-1:0] priorities_i           [NUM_OPERANDS],
    input  logic [      ID_BITWIDTH-1:0] identifiers_i          [NUM_OPERANDS],
    output logic [PRIORITY_BITWIDTH-1:0] largest_priority_o,
    output logic [      ID_BITWIDTH-1:0] identifier_of_largest_o
);

  localparam int MaxStage = ($clog2(NUM_OPERANDS) - 1);
  localparam int NumOperandsAligned = 2 ** (MaxStage + 1);

  logic [NumOperandsAligned-1:0][PRIORITY_BITWIDTH-1:0] priority_stages  [MaxStage + 2];
  logic [NumOperandsAligned-1:0][      ID_BITWIDTH-1:0] identifier_stages[MaxStage + 2];

  for (genvar operand = 0; operand < NumOperandsAligned; operand++) begin: g_operands_aligned
    if (operand < NUM_OPERANDS) begin
      assign priority_stages[0][operand]   = priorities_i[operand];
      assign identifier_stages[0][operand] = identifiers_i[operand];
    end else begin
      assign priority_stages[0][operand]   = '0;
      assign identifier_stages[0][operand] = '0;
    end
  end

  for (genvar comparator_stage = MaxStage; comparator_stage >= 0; comparator_stage--) begin: g_comp_stage
    for (genvar stage_index = 0; stage_index < (2 ** comparator_stage); stage_index++) begin: g_comp
      plic_comparator #(
          .ID_BITWIDTH      (ID_BITWIDTH),
          .PRIORITY_BITWIDTH(PRIORITY_BITWIDTH)
      ) comp_instance (
          .left_priority_i       (priority_stages[MaxStage-comparator_stage][2*stage_index]),
          .right_priority_i      (priority_stages[MaxStage-comparator_stage][2*stage_index+1]),
          .left_identifier_i     (identifier_stages[MaxStage-comparator_stage][2*stage_index]),
          .right_identifier_i    (identifier_stages[MaxStage-comparator_stage][2*stage_index+1]),
          .larger_priority_o     (priority_stages[MaxStage-(comparator_stage-1)][stage_index]),
          .identifier_of_larger_o(identifier_stages[MaxStage-(comparator_stage-1)][stage_index])
      );
    end
  end

  assign largest_priority_o      = priority_stages[MaxStage+1][0];
  assign identifier_of_largest_o = identifier_stages[MaxStage+1][0];
endmodule
