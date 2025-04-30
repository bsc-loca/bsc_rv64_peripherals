//!
//! **PROJECT:**             System_Verilog_Hardware_Common_Lib
//!
//! **LANGUAGE:**            SystemVerilog
//!
//! **FILE:**                clint.sv
//!
//! **AUTHOR(S):**
//!
//!   - Alejandro Tafalla - alejandro.tafalla@bsc.es
//!
//! **CONTRIBUTORS:**
//!
//!   - Alejandro Iznardo - alejandro.iznardo@bsc.es
//!
//! **REVISION:**
//!   * 0.0.1 - Initial release. 24/04/2024
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
//! This is Core-Local Interrupt Controller. It follows the RISC-V ACLINT v1.0 spec. The ACLINT provides
//! a timer with individual programmable interrupts for each hart and a means of sending Inter-Processor
//! interrupts by writing to a register.

// Original License Header
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
// Date: 15/07/2017
// Description: A RISC-V privilege spec 1.11 (WIP) compatible CLINT (core local interrupt controller)
//

// Platforms provide a real-time counter, exposed as a memory-mapped machine-mode register, mtime. mtime must run at
// constant frequency, and the platform must provide a mechanism for determining the timebase of mtime (device tree).

// Edited at Barcelona Supercomputing Center by Alejandro Tafalla

module clint #(
    parameter int           NR_CORES    = 1,            //! Number of cores therefore also the number of timecmp registers and timer interrupts
    parameter logic [63:0]  TIME_CMP_RST_VALUE = 64'b0, //! Reset value for mtime comparison register.

    parameter int   ADDR_WIDTH  = 64,
    parameter int   DATA_WIDTH  = 64,

    localparam int  BPW         = (DATA_WIDTH / 8)
) (
    input  logic                  clk_i,
    input  logic                  rstn_i,

    // Bus interface
    input  logic [ADDR_WIDTH-1:0] sri_addr_i,   //! register interface address
    input  logic                  sri_en_i,     //! register interface enable
    input  logic [DATA_WIDTH-1:0] sri_wdata_i,  //! register interface data to write
    input  logic                  sri_we_i,     //! register interface write enable
    input  logic [BPW-1:0]        sri_be_i,     //! register interface byte enable (write mask)
    output logic [DATA_WIDTH-1:0] sri_rdata_o,  //! register interface read data
    output logic                  sri_error_o,  //! register interface error

    input  logic                  rtc_i,        //! Real-time clock in (usually 32.768 kHz)
    output logic [NR_CORES-1:0]   timer_irq_o,  //! Timer interrupts
    output logic [NR_CORES-1:0]   ipi_o,        //! software interrupt (a.k.a inter-process-interrupt)
    output logic [63:0]           time_o        //! timer register output
);

  // -------------
  // Assertions
  // --------------
  //pragma translate_off
`ifndef VERILATOR
  // Static assertion check for appropriate bus width
  initial begin
    assert (NR_CORES < 4095)
    else $error("Number of cores must be less than 4095");
  end
`endif
  //pragma translate_on

  localparam int ADDR_SEL_WIDTH = (NR_CORES == 1) ? 1 : $clog2(NR_CORES);

  // register offset
  localparam logic [15:0] MSIP_BASE     = 16'h0;
  localparam logic [15:0] MTIMECMP_BASE = 16'h4000;
  localparam logic [15:0] MTIME_BASE    = 16'hbff8;

  // actual registers
  logic [63:0]               mtime_n,    mtime_q;
  logic [NR_CORES-1:0][63:0] mtimecmp_n, mtimecmp_q;
  logic [NR_CORES-1:0]       msip_n,     msip_q;

  // increase the timer
  logic increase_timer;

  logic [ADDR_SEL_WIDTH-1:0] hart_idx;

  assign hart_idx = sri_addr_i[ADDR_SEL_WIDTH-1+$clog2(BPW):$clog2(BPW)];
  assign time_o   = mtime_q;

  typedef enum logic [2:0] {
    MSIP_R,
    MSIP_W,
    MTIME_R,
    MTIME_W,
    MTIMECMP_R,
    MTIMECMP_W,
    ERROR
  } mode_sel_t;

  mode_sel_t mode;

  // Register address decoding
  always_comb begin : mode_sel
    if (sri_en_i) begin
      case (sri_addr_i[15:0]) inside
        [MSIP_BASE : MSIP_BASE + 4 * 12'(NR_CORES)]: begin
          if (sri_we_i) mode = MSIP_W;
          else mode = MSIP_R;
        end

        [MTIMECMP_BASE : MTIMECMP_BASE + 8 * 12'(NR_CORES)]: begin
          if (sri_we_i) mode = MTIMECMP_W;
          else mode = MTIMECMP_R;
        end

        [MTIME_BASE : MTIME_BASE + 4]: begin
          if (sri_we_i) mode = MTIME_W;
          else mode = MTIME_R;
        end
        default: mode = ERROR;
      endcase
    end
    else begin
      mode = ERROR;
    end
  end

  // Register Update Logic
  always_comb begin
    // Default assignments
    sri_rdata_o = {DATA_WIDTH{1'b0}};
    sri_error_o = 1'b0;
    mtime_n     = mtime_q;
    mtimecmp_n  = mtimecmp_q;
    msip_n      = msip_q;

    // RTC says we should increase the timer
    if (increase_timer) mtime_n = mtime_q + 1;

    // written from APB bus - gets priority
    case (mode)
      MSIP_R: begin
        sri_rdata_o = {{((DATA_WIDTH/2)-1){1'b0}}, msip_q[hart_idx], {((DATA_WIDTH/2)-1){1'b0}}, msip_q[hart_idx]}; // replicate data for 64b bus
      end
      MSIP_W: begin
        // MSIP registers are 4B
        if (sri_be_i[0]) begin
          msip_n[sri_addr_i[ADDR_SEL_WIDTH-1+2:2]] = sri_wdata_i[32*sri_addr_i[2]]; // select bit 0 or 32 depending on address (for 64b buses)
        end
      end

      MTIMECMP_R: begin
        sri_rdata_o = mtimecmp_q[hart_idx];
      end

      MTIMECMP_W: begin
        for (integer byte_in_word = 0; byte_in_word < BPW; byte_in_word++) begin
          if (sri_be_i[byte_in_word]) begin
            mtimecmp_n[hart_idx][8*(byte_in_word)+:8] = sri_wdata_i[8*(byte_in_word)+:8];
          end
        end
      end

      MTIME_R: begin
        sri_rdata_o = mtime_q;
      end

      MTIME_W: begin
        for (integer byte_in_word = 0; byte_in_word < BPW; byte_in_word++) begin
          if (sri_be_i[byte_in_word]) begin
            mtime_n[8*(byte_in_word)+:8] = sri_wdata_i[8*(byte_in_word)+:8];
          end
        end
      end

      ERROR: begin
        sri_error_o = 1'b1;
      end
      default: begin
        sri_error_o = 1'b1;
      end
    endcase
  end

  // -----------------------------
  // IRQ Generation
  // -----------------------------
  // The mtime register has a 64-bit precision on all RV32, RV64, and RV128 systems. Platforms provide a 64-bit
  // memory-mapped machine-mode timer compare register (mtimecmp), which causes a timer interrupt to be posted when the
  // mtime register contains a value greater than or equal (mtime >= mtimecmp) to the value in the mtimecmp register.
  // The interrupt remains posted until it is cleared by writing the mtimecmp register. The interrupt will only be taken
  // if interrupts are enabled and the MTIE bit is set in the mie register.
  always_comb begin : irq_gen
    // check that the mtime cmp register is set to a meaningful value
    for (int unsigned i = 0; i < NR_CORES; i++) begin
      if (mtime_q >= mtimecmp_q[i]) begin
        timer_irq_o[i] = 1'b1;
      end
      else begin
        timer_irq_o[i] = 1'b0;
      end
    end
  end

  // -----------------------------
  // RTC time tracking facilities
  // -----------------------------
  // 1. Put the RTC input through a classic two stage edge-triggered synchronizer to filter out any
  //    metastability effects (or at least make them unlikely :-))
  localparam int STAGES = 2;

  logic [STAGES-1:0] reg_q;

  always_ff @(posedge clk_i, negedge rstn_i) begin
    if (!rstn_i) begin
      reg_q <= {STAGES{1'b0}};
    end
    else begin
      reg_q <= {reg_q[STAGES-2:0], rtc_i};
    end
  end

  assign increase_timer = reg_q[STAGES-2] & (~reg_q[STAGES-1]);

  // Registers
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (~rstn_i) begin
      mtime_q    <= 64'b0;
      for (int i=0; i<NR_CORES; i++) begin
        mtimecmp_q[i] <= TIME_CMP_RST_VALUE;
      end
      msip_q     <= {NR_CORES{1'b0}};
    end
    else begin
      mtime_q    <= mtime_n;
      mtimecmp_q <= mtimecmp_n;
      msip_q     <= msip_n;
    end
  end

  assign ipi_o = msip_q;


endmodule
