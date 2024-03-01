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
//-- Title      : Comperator
//-- File       : plic_comperator.sv
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
//-- Description: Comparator
//-------------------------------------------------------------------------------
//-- Revisions  :
//-- Date        Version  Author   Description
//-- 2018-03-31  2.0      tbenz    Created header
//-- 2024-02-20  3.0      atafalla Refactoring, fix linting issues, follow spec when equal priorities
//-------------------------------------------------------------------------------

// find larger operand (value and identifier)
// chooses the operand with largest ID on priority equality
module plic_comparator #(
    parameter int ID_BITWIDTH       = 1,
    parameter int PRIORITY_BITWIDTH = 1
) (
    input  logic [PRIORITY_BITWIDTH-1:0] left_priority_i,
    input  logic [PRIORITY_BITWIDTH-1:0] right_priority_i,
    input  logic [      ID_BITWIDTH-1:0] left_identifier_i,
    input  logic [      ID_BITWIDTH-1:0] right_identifier_i,
    output logic [PRIORITY_BITWIDTH-1:0] larger_priority_o,
    output logic [      ID_BITWIDTH-1:0] identifier_of_larger_o
);

  always_comb begin : proc_compare
    if (left_priority_i > right_priority_i) begin
      larger_priority_o      = left_priority_i;
      identifier_of_larger_o = left_identifier_i;
    end else if (left_priority_i < right_priority_i) begin
      larger_priority_o      = right_priority_i;
      identifier_of_larger_o = right_identifier_i;
    end else begin
      if (left_identifier_i > right_identifier_i) begin
        larger_priority_o      = left_priority_i;
        identifier_of_larger_o = left_identifier_i;
      end else begin
        larger_priority_o      = right_priority_i;
        identifier_of_larger_o = right_identifier_i;
      end
    end
  end

  //pragma translate_off
`ifndef VERILATOR
  initial begin
    assert (ID_BITWIDTH > 0)
    else $error("ID_BITWIDTH has to be larger than 0");
    assert (PRIORITY_BITWIDTH > 0)
    else $error("PRIORITY_BITWIDTH has to be larger than 0");
  end
`endif
  //pragma translate_on

endmodule
