//!
//! **PROJECT:**             System_Verilog_Hardware_Common_Lib
//!
//! **LANGUAGE:**            SystemVerilog
//!
//! **FILE:**                plic_interface.sv
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
//!   * 0.0.1 - Initial release. 2024-12-03
//!
//!
//! *Library compliance:*
//!
//! | Doc | Schematic | TB | ASRT |Params. Val.| Sintesys test| Unify Interface| Functional Model |
//! |-----|-----------|----|------|------------|--------------|----------------|------------------|
//! |  ✔  |     x     |  x |   x  |     x      |       x      |        x       |         x        |
//!
//!

//! Module Functionality
//! --------------------
//! This module holds the configuration registers of the PLIC. It consists of an address decoder for
//! identifying the register sets (priority/threshold/claim-complete...).

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
//-- Title      : Register Interface
//-- File       : plic_interface.sv
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
    parameter int ADDR_WIDTH           = 32,                                    //! width of external address bus
    parameter int DATA_WIDTH           = 32,                                    //! width of external data bus
    parameter int PARAMETER_BITWIDTH   = 3,                                     //! width of the internal parameter e.g. priorities
    parameter int NUM_TARGETS          = 2,                                     //! number of target slices
    parameter int NUM_GATEWAYS         = 2,                                     //! number of gateways
    localparam int NUM_GATEWAY_BUNDLES = (NUM_GATEWAYS+1-1) / DATA_WIDTH + 1,   //! how many bundles we have to consider
    localparam int BPW = DATA_WIDTH / 8,                                        //! how many bytes a data word consist of
    localparam int ID_BITWIDTH = $clog2(NUM_GATEWAYS + 1)                       //the +1 is because counting starts from 1 and goes to NUM_GATEWAYS+1
) (
    input logic clk_i,                                                                      //! the clock signal
    input logic rstn_i,                                                                     //! asynchronous reset active low
    input  logic [ID_BITWIDTH-1:0]        id_of_largest_priority_i[NUM_TARGETS-1:0],        //! input array id of largest priority
    input  logic                          pending_array_i[NUM_GATEWAYS-1:0],                //! array with the interrupt pending , idx0 is gateway 1
    output logic [PARAMETER_BITWIDTH-1:0] thresholds_o[NUM_TARGETS-1:0],                    //! save internally the thresholds, communicate values over this port to the core
    output logic [PARAMETER_BITWIDTH-1:0] gateway_priorities_o[NUM_GATEWAYS-1:0],           //! save internally the the priorities, communicate values
    output logic                          irq_enables_o[NUM_GATEWAYS-1:0][NUM_TARGETS-1:0], //! communicate enable bits over this port
    output logic                          target_irq_claims_o[NUM_TARGETS-1:0],             //! claim signals
    output logic                          target_irq_completes_o[NUM_TARGETS-1:0],          //! complete signals
    output logic[ID_BITWIDTH-1:0]         target_irq_completes_id_o[NUM_TARGETS-1:0],       //! the id of the gateway to be completed

    // Bus interface
    input  logic [ADDR_WIDTH-1:0] addr_i,           //! address
    input  logic                  en_i,             //! bus enable
    input  logic [DATA_WIDTH-1:0] wdata_i,          //! write data input
    input  logic                  we_i,             //! write enable
    input  logic [       BPW-1:0] be_i,             //! byte enable
    output logic [DATA_WIDTH-1:0] rdata_o,          //! read data output
    output logic                  error_o           //! error signal
);
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
    logic [(ADDR_WIDTH - 12)-1:0] page_address;       //! the upper part of the address
    logic [11:0]                  page_offset;        //! the lowest 12 bit describes the page offset
    logic [9:0]                   page_word_offset;   //! the word address of each page offset
    logic [1:0]                   word_offset;        //! the byte in the word

    //bundle definitions
    logic [DATA_WIDTH-1:0] irq_pending_bundle[NUM_GATEWAY_BUNDLES];

    //registers
    logic [PARAMETER_BITWIDTH-1:0] thresholds_d[NUM_TARGETS-1:0];
    logic [PARAMETER_BITWIDTH-1:0] thresholds_q[NUM_TARGETS-1:0];

    logic [PARAMETER_BITWIDTH-1:0] priorities_d[NUM_GATEWAYS-1:0];
    logic [PARAMETER_BITWIDTH-1:0] priorities_q[NUM_GATEWAYS-1:0];

    logic [7:0] ena_bundles_d[NUM_GATEWAY_BUNDLES][NUM_TARGETS-1:0][(DATA_WIDTH/8)-1:0];
    logic [7:0] ena_bundles_q[NUM_GATEWAY_BUNDLES][NUM_TARGETS-1:0][(DATA_WIDTH/8)-1:0];

    logic pending_array_tmp[(NUM_GATEWAYS+1)-1:0];
    logic irq_enables_tmp[(NUM_GATEWAYS+1)-1:0][NUM_TARGETS-1:0];

    always_comb begin
        // assign addresses
        page_address = addr_i[ADDR_WIDTH-1:12];
        page_offset[11:0] = addr_i[11:0];
        page_word_offset = addr_i[11:2];
        word_offset = addr_i[1:0];
    end

    // wire up pending signals
    always_comb begin
        pending_array_tmp[0] = 1'b0;

        for (integer i = 1; i < (NUM_GATEWAYS + 1); ++i) begin
            pending_array_tmp[i] = pending_array_i[i-1];
        end
    end

    // bundle signals
    always_comb begin
        for (integer bundle = 0; bundle < NUM_GATEWAY_BUNDLES; bundle++) begin
            for (integer ip_bit = 0; ip_bit < DATA_WIDTH; ip_bit++) begin
                if (((bundle * DATA_WIDTH) + ip_bit) < (NUM_GATEWAYS + 1)) begin
                    irq_pending_bundle[bundle][ip_bit] = pending_array_tmp[(bundle*DATA_WIDTH)+ip_bit];
                end else begin
                    irq_pending_bundle[bundle][ip_bit] = '0;
                end
            end
        end
    end

    // wire up irq enables outputs
    always_comb begin
        for (integer i = 1; i < (NUM_GATEWAYS + 1); ++i) begin
            for (integer target = 0; target < NUM_TARGETS; ++target) begin
                irq_enables_o[i-1][target] = irq_enables_tmp[i][target];
            end
        end
    end

    // wire up irq enable ffs to tmp
    for (genvar bundle = 0; bundle < NUM_GATEWAY_BUNDLES; bundle++) begin
        for (genvar target = 0; target < NUM_TARGETS; target++) begin
            for (genvar byte_in_word = 0; byte_in_word < (DATA_WIDTH / 8); byte_in_word++) begin
                for (genvar enable_bit = 0; enable_bit < 8; enable_bit++) begin
                    if (((bundle * DATA_WIDTH) + (byte_in_word * 8) + enable_bit) < (NUM_GATEWAYS + 1)) begin
                        assign irq_enables_tmp[(bundle * DATA_WIDTH) + (byte_in_word * 8) + enable_bit][target] = ena_bundles_q[bundle][target][byte_in_word][enable_bit];
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
                if ((page_word_offset <= $unsigned(NUM_GATEWAYS)) && (page_word_offset > 0)) begin  //the gateway in question exists
                // set the current operation to be an access to the priority registers
                funct = PRI;
                end
                // we now access the IP Bits, read only
            end else if (page_address[13:0] == 1) begin
                // the page_word_offset tells us now, which word we have to consider,
                // the word, which includes the IP bit in question should be returned
                if (page_word_offset < $unsigned(NUM_GATEWAY_BUNDLES)) begin
                funct = IPA;
                end
                // access of the enable bits for each target
            end else if (page_address[13:9] == 0) begin
                // the bottom part page_word_offset now tells us which gateway bundle we have to consider
                // part of the page_address and the upper part of the page_word_offset give us the target nr.
                if (page_offset[6:$clog2(BPW)+1] < $unsigned(NUM_GATEWAY_BUNDLES)) begin
                if (({page_address[8:0], page_offset[11:7]} - 'd64) < $unsigned(NUM_TARGETS)) begin
                    funct = IEB;
                end
                end
                // priority / claim / complete
            end else begin
                // page address - 0h20 gives the target number
                if ((page_address[13:0] - 'h200) < $unsigned(NUM_TARGETS)) begin
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
        rdata_o = {DATA_WIDTH{1'b0}};
        error_o = 0;

        case (funct)
        PRI: begin
            // read case
            if (en_i & !we_i) begin
            rdata_o = {{(DATA_WIDTH - PARAMETER_BITWIDTH) {1'b0}}, priorities_q[page_word_offset-10'd1]};
            end else if (en_i & we_i) begin
            for (integer byte_in_word = 0; byte_in_word < BPW; byte_in_word++) begin
                if (be_i[byte_in_word]) begin
                for (integer b = 0; b < 8; b++) begin
                    if (((byte_in_word*8)+b) < PARAMETER_BITWIDTH) begin
                    priorities_d[page_word_offset-'d1][(byte_in_word*8)+b+:1] = wdata_i[(byte_in_word*8)+b+:1];
                    end
                end
                end
            end
            end
        end

        IPA: begin
            if (en_i & !we_i) begin
            rdata_o = irq_pending_bundle[page_word_offset];
            end else if (en_i & we_i) begin
            error_o = 1;
            end
        end

        IEB: begin
            // read case
            if (en_i & !we_i) begin
            for (integer byte_in_word = 0; byte_in_word < (DATA_WIDTH / 8); byte_in_word++) begin
                rdata_o[8*(byte_in_word)+:8] = ena_bundles_q[page_offset[6:$clog2(BPW)]][{page_address[8:0], page_offset[11:7]}-'d64][byte_in_word];
            end
            end else if (en_i & we_i) begin
            for (integer byte_in_word = 0; byte_in_word < (DATA_WIDTH / 8); byte_in_word++) begin
                if (be_i[byte_in_word]) begin
                ena_bundles_d[page_offset[6:$clog2(BPW)]]
                    [{page_address[8:0], page_offset[11:7]}-'d64][byte_in_word] =
                    wdata_i[8*(byte_in_word)+:8];
                end
            end
            end
        end
        THR: begin
            // read case
            if (en_i & !we_i) begin
            rdata_o = {{(DATA_WIDTH - PARAMETER_BITWIDTH) {1'b0}}, thresholds_q[page_address[13:0]-'h200]};
            // write case
            end else if ((be_i != 0) && we_i && en_i ) begin
            thresholds_d[page_address[13:0]-'h200] = wdata_i[PARAMETER_BITWIDTH-1:0];
            end
        end

        CCP: begin
            // read case
            if (en_i & !we_i) begin
            target_irq_claims_o[page_address[13:0]-'h200] = 1;
            rdata_o = {{(DATA_WIDTH - ID_BITWIDTH) {1'b0}}, id_of_largest_priority_i[page_address[13:0]-'h200]};
            // write case
            end else if (en_i & we_i) begin
            target_irq_completes_o[page_address[13:0]-'h200] = 1;
            target_irq_completes_id_o[page_address[13:0]-'h200] = wdata_i[ID_BITWIDTH-1:0];
            end
        end

        INV: begin
            if (en_i) begin
            error_o = 1;
            end
        end
        default: begin
            if (en_i) begin
            error_o = 1;
            end
        end
        endcase  // funct
    end

    for (genvar gateway = 0; gateway < NUM_GATEWAYS; ++gateway) begin
        always_ff @(posedge clk_i or negedge rstn_i) begin : proc_update_prio_ff
            if (~rstn_i) begin
                priorities_q[gateway] <= '0;
            end else begin
                priorities_q[gateway] <= priorities_d[gateway];
            end
        end
    end

    // store data in flip flops
    always_ff @(posedge clk_i or negedge rstn_i) begin : proc_update_ff
        if (~rstn_i) begin  // set all registers to 0
            for (integer bundle = 0; bundle < NUM_GATEWAY_BUNDLES; bundle++)
                for (integer target = 0; target < NUM_TARGETS; target++)
                    for (integer byte_in_word = 0; byte_in_word < (DATA_WIDTH / 8); byte_in_word++)
                        ena_bundles_q[bundle][target][byte_in_word] <= 0;

            for (integer target = 0; target < NUM_TARGETS; target++) begin
                thresholds_q[target]             <= 0;
            end
        end else begin
            thresholds_q             <= thresholds_d;
            for (integer bundle = 0; bundle < NUM_GATEWAY_BUNDLES; bundle++) begin
                for (integer target = 0; target < NUM_TARGETS; target++) begin 
                for (integer byte_in_word = 0; byte_in_word < (DATA_WIDTH / 8); byte_in_word++) begin
                    if ((bundle == 0) && (byte_in_word == 0)) begin
                        ena_bundles_q[bundle][target][byte_in_word] <= {ena_bundles_d[bundle][target][byte_in_word][7:1], 1'b0};
                    end else begin
                        ena_bundles_q[bundle][target][byte_in_word] <= ena_bundles_d[bundle][target][byte_in_word];
                    end
                end
                end
            end
        end
    end

  //assign outputs
  assign thresholds_o         = thresholds_q;
  assign gateway_priorities_o = priorities_q;

`ifndef SIMULATION
generate
    if(!((ADDR_WIDTH == 32) | (ADDR_WIDTH == 64)))
        $error("Address width has to bei either 32 or 64 bit");
    if(!((DATA_WIDTH == 32) | (DATA_WIDTH == 64)))
        $error("Data width has to bei either 32 or 64 bit");
    if(!(PARAMETER_BITWIDTH > 0))
        $error("PARAMETER_BITWIDTH has to be larger than 1");
    if(!(NUM_GATEWAYS > 0))
        $error("Num od Gateways has to be larger than 1");
    if(!(NUM_GATEWAYS < 512))
        $error("Num of Gateways has to be smaller than 512");
    if(!(NUM_TARGETS > 0))
        $error("Num Target slices has to be larger than 1");
    if(!(NUM_TARGETS < 15872))
        $error("Num target slices has to be smaller than 15872");
endgenerate
`endif

endmodule
