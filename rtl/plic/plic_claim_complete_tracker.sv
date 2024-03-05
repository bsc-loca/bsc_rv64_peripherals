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
//-- Title      : Claim - Complete - Tracker
//-------------------------------------------------------------------------------
//-- File       : plic_claim_complete_tracker.sv
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
//-- Description: Implements the control logic of the plic
//-------------------------------------------------------------------------------
//-- Revisions  :
//-- Date        Version  Author   Description
//-- 2018-03-31  2.0      tbenz    Created header
//-- 2024-02-20  3.0      atafalla Refactoring, fix linting issues
//-------------------------------------------------------------------------------

//FSM that receives interrupt claims and interrupt completes from targets
//and generates the fitting inerrupt claims and interrupt completes for sources
module plic_claim_complete_tracker #(
    parameter int NUM_TARGETS  = 2,
    parameter int NUM_GATEWAYS = 2,
    localparam int IdBitwidth = $clog2(NUM_GATEWAYS + 1)
) (
    input logic clk_i,  // Clock
    input logic rst_ni, // Asynchronous reset active low

    input logic [IdBitwidth-1:0] identifier_of_largest_priority_per_target[NUM_TARGETS],
    input logic                  target_irq_claims_i                      [NUM_TARGETS],
    input logic                  target_irq_completes_i                   [NUM_TARGETS],
    input logic [IdBitwidth-1:0] target_irq_completes_identifier_i        [NUM_TARGETS],

    output logic gateway_irq_claims_o   [NUM_GATEWAYS],
    output logic gateway_irq_completes_o[NUM_GATEWAYS]
);
  // claimed_gateways_q[target] is 0 if the target has not claimed the irq of any gateway
  // and the is the identifier of the claimed gateway otherwise
  // logic [IdBitwidth-1:0] claimed_gateways_q [NUM_TARGETS];

  // the +1 is because counting starts from 1 and goes to NUM_GATEWAYS+1
  logic [NUM_GATEWAYS:0] claim_array        [NUM_TARGETS];
  logic [NUM_GATEWAYS:0] save_claims_array_q[NUM_TARGETS];
  logic [NUM_GATEWAYS:0] complete_array     [NUM_TARGETS];

  // for handling claims
  for (genvar counter = 0; counter < NUM_TARGETS; counter++) begin: g_target_claim
    logic [IdBitwidth-1:0] id;
    logic [IdBitwidth-1:0] complete_id;
    assign complete_id = target_irq_completes_identifier_i[counter];
    assign id = identifier_of_largest_priority_per_target[counter];

    always_ff @(posedge clk_i) begin : proc_target
      if (~rst_ni) begin
        // claimed_gateways_q[counter]  <= '0;
        claim_array[counter]         <= '0;
        save_claims_array_q[counter] <= '0;
        complete_array[counter]      <= '0;
      end else begin
        // if a claim is issued, forward it to gateway with highest priority for the claiming target
        if (target_irq_claims_i[counter]) begin
          claim_array[counter][id]         <= 1'b1;

          // save claim for later when the complete-notification arrives
          save_claims_array_q[counter][id] <= 1'b1;

        end else begin
          // per default, all claims and completes are zero
          claim_array[counter]    <= '0;
          complete_array[counter] <= '0;


          // if a complete is issued, check if that gateway has previously been claimed by
          // this target and forward the
          // complete message to that gateway. if no claim has previously been issued, the
          // complete message is ignored
          if (target_irq_completes_i[counter] && save_claims_array_q[counter][complete_id]) begin
            complete_array[counter][complete_id]      <= 1'b1;
            save_claims_array_q[counter][complete_id] <= 1'b0;
          end
        end
      end
    end

  end

  // the outputs for an id are the ORs of all targets for that id
  always_comb begin : proc_result_computation
    for (integer gateway = 1; gateway <= NUM_GATEWAYS; gateway++) begin
      automatic logic is_claimed = '0;
      automatic logic is_completed = '0;

      for (integer target = 0; target < NUM_TARGETS; target++) begin
        is_claimed   = is_claimed | claim_array[target][gateway];
        is_completed = is_completed | complete_array[target][gateway];
      end

      gateway_irq_claims_o[gateway-1] = is_claimed;
      gateway_irq_completes_o[gateway-1] = is_completed;

      // if (is_claimed) begin
      //   gateway_irq_claims_o[gateway-1] = 1;
      // end else begin
      //   gateway_irq_claims_o[gateway-1] = 0;
      // end

      // if (is_completed) begin
      //   gateway_irq_completes_o[gateway-1] = 1;
      // end else begin
      //   gateway_irq_completes_o[gateway-1] = 0;
      // end
    end
  end

endmodule  //plic_claim_complete_tracker
