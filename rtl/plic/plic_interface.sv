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
//-- Title      : Register Interface
//-- File       : plic_target_slice.sv
//-- Author     : Gian Marti      <gimarti.student.ethz.ch>
//-- Author     : Thomas Kramer   <tkramer.student.ethz.ch>
//-- Author     : Thomas E. Benz  <tbenz.student.ethz.ch>
//-- Company    : Integrated Systems Laboratory, ETH Zurich
//-- Company    : Barcelona Supercomputing Center
//-- Created    : 2018-03-31
//-- Last update: 2024-02-20
//-- Platform   : ModelSim (simulation), Synopsys (synthesis)
//-- Standard   : SystemVerilog IEEE 1800-2012
//-------------------------------------------------------------------------------
//-- Description: Implementation of the plic's register interface
//-------------------------------------------------------------------------------
//-- Revisions  :
//-- Date        Version  Author   Description
//-- 2018-03-31  2.0      tbenz    Created header
//-- 2024-02-20  3.0      atafalla Refactoring, fix linting issues
//-------------------------------------------------------------------------------

module plic_interface #(
    parameter int ADDR_WIDTH         = 32,  // width of external address bus
    parameter int DATA_WIDTH         = 32,  // width of external data bus
    parameter int PARAMETER_BITWIDTH = 3,   // width of the internal parameter e.g. priorities
    parameter int NUM_TARGETS        = 2,   // number of target slices
    parameter int NUM_GATEWAYS       = 2,    // number of gateways
    localparam int NumGatewayBundles = (NUM_GATEWAYS+1-1) / DATA_WIDTH + 1,     // how many bundles we have to consider
    localparam int BitsGatewaysBundles = $bits(NumGatewayBundles),
    localparam int Bpw = DATA_WIDTH / 8,  // how many bytes a data word consist of
    localparam int IdBitwidth = $clog2(NUM_GATEWAYS + 1) // the +1 is because counting starts from 1 and goes to NUM_GATEWAYS+1
) (
    input logic clk_i,  // the clock signal
    input logic rst_ni,  // asynchronous reset active low
    input  logic [IdBitwidth-1:0]        id_of_largest_priority_i[NUM_TARGETS],    // input array id of largest priority
    input  logic                          pending_array_i[NUM_GATEWAYS],            // array with the interrupt pending , idx0 is gateway 1
    output logic [PARAMETER_BITWIDTH-1:0] thresholds_o[NUM_TARGETS],                // save internally the thresholds, communicate values over this port to the core
    output logic [PARAMETER_BITWIDTH-1:0] gateway_priorities_o[NUM_GATEWAYS],       // save internally the the priorities, communicate values
    output logic                          irq_enables_o[NUM_GATEWAYS][NUM_TARGETS], // communicate enable bits over this port
    output logic target_irq_claims_o[NUM_TARGETS],  // claim signals
    output logic target_irq_completes_o[NUM_TARGETS],  // complete signals
    output logic[IdBitwidth-1:0]         target_irq_completes_id_o[NUM_TARGETS],   // the id of the gateway to be completed

    // Bus interface
    input  logic [ADDR_WIDTH-1:0] addr,
    input  logic                  en,
    input  logic [DATA_WIDTH-1:0] wdata,
    input  logic                  we,
    input  logic [       Bpw-1:0] be,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                  error
);
  localparam int BitsGatewayBundles = NumGatewayBundles==1 ? 1 : $clog2(NumGatewayBundles);
  //define ennumerated types
  // the address mapping will primarily check what
  // function should be performed
  typedef enum logic [2:0] {
    INV,  // Invalid
    PRI,  // priorities
    IPA,  // interrupt pending
    IEB,  // interrupt enable
    THR,  // threshold and claim/complete
    CCP   // claim/clear pulses
  } funct_t;
  funct_t funct;

  //internal signals
  logic [(ADDR_WIDTH - 12)-1:0] page_address;  // the upper part of the address
  logic [11:0] page_offset;  // the lowest 12 bit describes the page offset
  logic [9:0] page_word_offset;  // the word address of each page offset
  logic [1:0] word_offset;  // the byte in the word

  //bundle definitions
  logic [DATA_WIDTH-1:0] irq_pending_bundle[NumGatewayBundles];

  //registers
  logic [PARAMETER_BITWIDTH-1:0] thresholds_d[NUM_TARGETS];
  logic [PARAMETER_BITWIDTH-1:0] thresholds_q[NUM_TARGETS];

  logic [PARAMETER_BITWIDTH-1:0] priorities_d[NUM_GATEWAYS];
  logic [PARAMETER_BITWIDTH-1:0] priorities_q[NUM_GATEWAYS];

  logic [IdBitwidth-1:0] id_of_largest_priority_d[NUM_TARGETS];
  logic [IdBitwidth-1:0] id_of_largest_priority_q[NUM_TARGETS];

  logic [7:0] ena_bundles_d[NumGatewayBundles][NUM_TARGETS][DATA_WIDTH/8];
  logic [7:0] ena_bundles_q[NumGatewayBundles][NUM_TARGETS][DATA_WIDTH/8];

  logic pending_array_tmp[NUM_GATEWAYS+1];
  logic irq_enables_tmp[NUM_GATEWAYS+1][NUM_TARGETS];

  always_comb begin
    // assignments
    id_of_largest_priority_d = id_of_largest_priority_i;

    // assign addresses
    page_address = addr[ADDR_WIDTH-1:12];
    page_offset = addr[11:0];
    page_word_offset = addr[11:2];
    word_offset = addr[1:0];
  end

  // wire up pending signals
  always_comb begin
    pending_array_tmp[0] = 1'b0;

    for (integer i = 1; i < NUM_GATEWAYS + 1; ++i) begin
      pending_array_tmp[i] = pending_array_i[i-1];
    end
  end

  // bundle signals
  always_comb begin
    for (integer bundle = 0; bundle < NumGatewayBundles; bundle++) begin
      for (integer ip_bit = 0; ip_bit < DATA_WIDTH; ip_bit++) begin
        if ((bundle * DATA_WIDTH + ip_bit) < NUM_GATEWAYS + 1) begin
          irq_pending_bundle[bundle][ip_bit] = pending_array_tmp[bundle*DATA_WIDTH+ip_bit];
        end else begin
          irq_pending_bundle[bundle][ip_bit] = '0;
        end
      end
    end
  end

  // wire up irq enables outputs
  always_comb begin
    for (integer i = 1; i < NUM_GATEWAYS + 1; ++i) begin
      for (integer target = 0; target < NUM_TARGETS; ++target) begin
        irq_enables_o[i-1][target] = irq_enables_tmp[i][target];
      end
    end
  end

  // wire up irq enable ffs to tmp
  for (genvar bundle = 0; bundle < NumGatewayBundles; bundle++) begin
    for (genvar target = 0; target < NUM_TARGETS; target++) begin
      for (genvar byte_in_word = 0; byte_in_word < DATA_WIDTH / 8; byte_in_word++) begin
        for (genvar enable_bit = 0; enable_bit < 8; enable_bit++) begin
          if (bundle * DATA_WIDTH + byte_in_word * 8 + enable_bit < NUM_GATEWAYS + 1) begin
            assign irq_enables_tmp[bundle * DATA_WIDTH + byte_in_word * 8 + enable_bit][target] = ena_bundles_q[bundle][target][byte_in_word][enable_bit];
          end
        end
      end
    end
  end

  // determine the function to be performed
  always_comb begin : proc_address_map
    // default values
    funct = INV;
    // only aligned access is allowed:
    if (word_offset == '0) begin
      // we have now an word alligned access -> check out page offset to determine
      // what type of access this is.
      if (page_address[13:0] == 0) begin  // we access the gateway priority bits
        // the page_word_offset tells us now which gateway we consider
        // in order to grant or deny access, we have to check if the gateway
        // in question really exist.
        // Gateway 0 does not exist, so return an error
        if (page_word_offset <= $bits(page_word_offset)'(NUM_GATEWAYS) && page_word_offset > 0) begin  //the gateway in question exists
          // set the current operation to be an access to the priority registers
          funct = PRI;
        end
        // we now access the IP Bits, read only
      end else if (page_address[13:0] == 1) begin
        // the page_word_offset tells us now, which word we have to consider,
        // the word, which includes the IP bit in question should be returned
        if (page_word_offset < $bits(page_word_offset)'(NumGatewayBundles)) begin
          funct = IPA;
        end
        // access of the enable bits for each target
      end else if (page_address[13:9] == 0) begin
        // the bottom part page_word_offset now tells us which gateway bundle we have to consider
        // part of the page_address and the upper part of the page_word_offset give us the target nr.
        if (page_offset[6:$clog2(Bpw)] < (6-$clog2(Bpw)+1)'(NumGatewayBundles)) begin
          if (({page_address[8:0], page_offset[11:7]} - 14'd64) < 14'(NUM_TARGETS)) begin
            funct = IEB;
          end
        end
        // priority / claim / complete
      end else begin
        // page address - 0h20 gives the target number
        if (page_address[13:0] - 14'h200 < 14'(NUM_TARGETS)) begin
          // check lowest bit of the page_word_offset to get the exact function
          if (page_word_offset == 0) begin
            funct = THR;
          end else if (page_word_offset == 1) begin
            funct = CCP;
          end
        end
      end
    end
  end

  always_comb begin : proc_read_write
    for (integer target = 0; target < NUM_TARGETS; target++) begin
      target_irq_claims_o[target]       = '0;
      target_irq_completes_o[target]    = '0;
      target_irq_completes_id_o[target] = '0;
    end

    //just keep the values untouched as default
    priorities_d = priorities_q;
    ena_bundles_d = ena_bundles_q;
    thresholds_d = thresholds_q;
    rdata = {DATA_WIDTH{1'b0}};
    error = 0;

    case (funct)
      PRI: begin
        // read case
        if (en & !we) begin
          rdata = {{(DATA_WIDTH - PARAMETER_BITWIDTH) {1'b0}}, priorities_q[$clog2(NUM_GATEWAYS)'(page_word_offset-1)]};
        end else if (en & we) begin
          for (integer byte_in_word = 0; byte_in_word < Bpw; byte_in_word++) begin
            if (be[byte_in_word]) begin
              for (integer b = 0; b < 8; b++) begin
                if (byte_in_word*8+b < PARAMETER_BITWIDTH) begin
                  priorities_d[$clog2(NUM_GATEWAYS)'(page_word_offset-1)][byte_in_word*8+b+:1] = wdata[byte_in_word*8+b+:1];
                end
              end
            end
          end
        end
      end

      IPA: begin
        if (en & !we) begin
          rdata = irq_pending_bundle[BitsGatewayBundles'(page_word_offset)];
        end else if (en & we) begin
          error = 1;
        end
      end

      IEB: begin
        // read case
        if (en & !we) begin
          for (integer byte_in_word = 0; byte_in_word < DATA_WIDTH / 8; byte_in_word++) begin
            rdata[8*(byte_in_word)+:8] = ena_bundles_q[BitsGatewayBundles'(page_offset[6:$clog2(Bpw)])][$clog2(NUM_TARGETS)'({page_address[8:0], page_offset[11:7]}-64)][byte_in_word];
          end
        end else if (en & we) begin
          for (integer byte_in_word = 0; byte_in_word < DATA_WIDTH / 8; byte_in_word++) begin
            if (be[byte_in_word]) begin
              ena_bundles_d[BitsGatewayBundles'(page_offset[6:$clog2(Bpw)])]
                  [$clog2(NUM_TARGETS)'({page_address[8:0], page_offset[11:7]}-64)][byte_in_word] =
                  wdata[8*(byte_in_word)+:8];
            end
          end
        end
      end
      THR: begin
        // read case
        if (en & !we) begin
          rdata = {{(DATA_WIDTH - PARAMETER_BITWIDTH) {1'b0}}, thresholds_q[$clog2(NUM_TARGETS)'(page_address[13:0]-'h200)]};
          // write case
        end else if (be != 0) begin
          thresholds_d[$size(thresholds_d)'(page_address[13:0]-'h200)] = wdata[PARAMETER_BITWIDTH-1:0];
        end
      end

      CCP: begin
        // read case
        if (en & !we) begin
          target_irq_claims_o[IdBitwidth'(page_address[13:0]-'h200)] = 1;
          rdata = {{(DATA_WIDTH - IdBitwidth) {1'b0}}, id_of_largest_priority_q[IdBitwidth'(page_address[13:0]-'h200)]};
          // write case
        end else if (en & we) begin
          target_irq_completes_o[IdBitwidth'(page_address[13:0]-'h200)] = 1;
          target_irq_completes_id_o[IdBitwidth'(page_address[13:0]-'h200)] = wdata[IdBitwidth-1:0];
        end
      end

      INV: begin
        if (en) begin
          error = 1;
        end
      end
      default: begin
        if (en) begin
          error = 1;
        end
      end
    endcase  // funct
  end

  for (genvar gateway = 0; gateway < NUM_GATEWAYS; ++gateway) begin
    always_ff @(posedge clk_i or negedge rst_ni) begin : proc_update_prio_ff
      if (~rst_ni) begin
        priorities_q[gateway] <= '0;
      end else begin
        priorities_q[gateway] <= priorities_d[gateway];
      end
    end
  end

  // store data in flip flops
  always_ff @(posedge clk_i or negedge rst_ni) begin : proc_update_ff
    if (~rst_ni) begin  // set all registers to 0
      for (integer bundle = 0; bundle < NumGatewayBundles; bundle++)
        for (integer target = 0; target < NUM_TARGETS; target++)
          for (integer byte_in_word = 0; byte_in_word < DATA_WIDTH / 8; byte_in_word++)
            ena_bundles_q[bundle][target][byte_in_word] <= 0;

      for (integer target = 0; target < NUM_TARGETS; target++) begin
        thresholds_q[target]             <= 0;
        id_of_largest_priority_q[target] <= 0;
      end
    end else begin
      // ena_bundles_q            <= ena_bundles_d;
      thresholds_q             <= thresholds_d;
      id_of_largest_priority_q <= id_of_largest_priority_d;
      for (integer bundle = 0; bundle < NumGatewayBundles; bundle++) begin
        for (integer target = 0; target < NUM_TARGETS; target++) begin 
          for (integer byte_in_word = 0; byte_in_word < DATA_WIDTH / 8; byte_in_word++) begin
            if (bundle == 0 && byte_in_word == 0) begin
              ena_bundles_q[bundle][target][byte_in_word] <= {ena_bundles_d[bundle][target][byte_in_word][7:1], 1'b0};
            end else begin
              ena_bundles_q[bundle][target][byte_in_word] <= ena_bundles_d[bundle][target][byte_in_word];
            end
          end
        end
      end

      // for (int target = 0; target < NUM_TARGETS; ++target) begin
      //   ena_bundles_q[0][target][0][0] <= 1'b0;
      // end
    end
  end

  //assign outputs
  assign thresholds_o         = thresholds_q;
  assign gateway_priorities_o = priorities_q;

  // pragma translate_off
`ifndef VERILATOR
  initial begin
    assert ((ADDR_WIDTH == 32) | (ADDR_WIDTH == 64))
    else $error("Address width has to bei either 32 or 64 bit");
    assert ((DATA_WIDTH == 32) | (DATA_WIDTH == 64))
    else $error("Data width has to bei either 32 or 64 bit");
    assert (PARAMETER_BITWIDTH > 0)
    else $error("PARAMETER_BITWIDTH has to be larger than 1");
    //assert (PARAMETER_BITWIDTH<8)                else $error("PARAMETER_BITWIDTH has to be smaller than 8");
    assert (NUM_GATEWAYS > 0)
    else $error("Num od Gateways has to be larger than 1");
    assert (NUM_GATEWAYS < 512)
    else $error("Num of Gateways has to be smaller than 512");
    assert (NUM_TARGETS > 0)
    else $error("Num Target slices has to be larger than 1");
    assert (NUM_TARGETS < 15872)
    else $error("Num target slices has to be smaller than 15872");
  end
`endif
  // pragma translate_on

endmodule
