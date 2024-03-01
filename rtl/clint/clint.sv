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
    parameter int unsigned NR_CORES       = 1, // Number of cores therefore also the number of timecmp registers and timer interrupts
    parameter int unsigned ADDR_WIDTH = 64,
    parameter int unsigned DATA_WIDTH = 64
) (
    input logic                       clk_i,      // Clock
    input logic                       rst_ni,     // Asynchronous reset active low

    // Bus interface
    input logic [ADDR_WIDTH-1:0]  addr,
    input logic                   en,
    input logic [DATA_WIDTH-1:0]  wdata,
    input logic                   we,
    input logic [7:0]             be,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                  error,

    input  logic                      rtc_i,        // Real-time clock in (usually 32.768 kHz)
    output logic [NR_CORES-1:0]       timer_irq_o,  // Timer interrupts
    output logic [NR_CORES-1:0]       ipi_o,        // software interrupt (a.k.a inter-process-interrupt)
    output logic [63:0]               time_o
);

  localparam int AddrSelWidth = (NR_CORES == 1) ? 1 : $clog2(NR_CORES);
  localparam int NBytes = DATA_WIDTH/8;

  // register offset
  localparam logic [15:0] MSIP_BASE     = 16'h0;
  localparam logic [15:0] MTIMECMP_BASE = 16'h4000;
  localparam logic [15:0] MTIME_BASE    = 16'hbff8;

  // actual registers
  logic [63:0] mtime_n, mtime_q;
  logic [NR_CORES-1:0][63:0] mtimecmp_n, mtimecmp_q;
  logic [NR_CORES-1:0] msip_n, msip_q;
  // increase the timer
  logic increase_timer;

  logic [AddrSelWidth-1:0] hart_idx;
  assign hart_idx = addr[AddrSelWidth-1+$clog2(NBytes):$clog2(NBytes)];
  assign time_o = mtime_q;

  typedef enum logic[2:0] {
    MSIP_R,
    MSIP_W,
    MTIME_R,
    MTIME_W,
    MTIMECMP_R,
    MTIMECMP_W,
    ERROR
  } mode_sel_t;

  mode_sel_t mode;

  // Decode address
  always_comb begin : mode_sel
    if (en) begin
      case (addr[15:0]) inside
        [MSIP_BASE : MSIP_BASE + 4 * 12'(NR_CORES)]: begin
          if (we) mode = MSIP_W;
          else mode = MSIP_R;
        end

        [MTIMECMP_BASE : MTIMECMP_BASE + 8 * 12'(NR_CORES)]: begin
          if (we) mode = MTIMECMP_W;
          else mode = MTIMECMP_R;
        end

        [MTIME_BASE : MTIME_BASE + 4]: begin
          if (we) mode = MTIME_W;
          else mode = MTIME_R;
        end
        default: mode = ERROR;
      endcase
    end
    else begin
      mode = ERROR;
    end
  end

  // -----------------------------
  // Register Update Logic
  // -----------------------------
  // APB register write logic
  always_comb begin
    // Default assignments
    rdata = 'b0;
    error = 0;
    mtime_n    = mtime_q;
    mtimecmp_n = mtimecmp_q;
    msip_n     = msip_q;

    // RTC says we should increase the timer
    if (increase_timer) mtime_n = mtime_q + 1;

    // written from APB bus - gets priority
    case (mode)
      MSIP_R: begin
        rdata = {{(DATA_WIDTH-1){1'b0}},msip_q[hart_idx]};
      end
      MSIP_W: begin
        // MSIP registers are 4B
        if (be[0]) begin
          msip_n[addr[AddrSelWidth-1+2:2]] = wdata[0];
        end
      end

      MTIMECMP_R: begin
        rdata = mtimecmp_q[hart_idx];
      end

      MTIMECMP_W: begin
        for (integer byte_in_word = 0; byte_in_word < NBytes; byte_in_word++) begin
          if (be[byte_in_word]) begin
            mtimecmp_n[hart_idx][8*(byte_in_word)+:8] = wdata[8*(byte_in_word)+:8];
          end
        end
      end

      MTIME_R: begin
        rdata = mtime_q;
      end

      MTIME_W: begin
        for (integer byte_in_word = 0; byte_in_word < NBytes; byte_in_word++) begin
          if (be[byte_in_word]) begin
            mtime_n[8*(byte_in_word)+:8] = wdata[8*(byte_in_word)+:8];
          end
        end
      end

      ERROR: begin
        error = 1;
      end
      default: begin
        error = 1;
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
      end else begin
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

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      reg_q <= 'h0;
    end else begin
      reg_q <= {reg_q[STAGES-2:0], rtc_i};
    end
  end

  assign increase_timer = reg_q[STAGES-1];

  // Registers
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (~rst_ni) begin
      mtime_q    <= 64'b0;
      mtimecmp_q <= 'b0;
      msip_q     <= '0;
    end else begin
      mtime_q    <= mtime_n;
      mtimecmp_q <= mtimecmp_n;
      msip_q     <= msip_n;
    end
  end

  assign ipi_o = msip_q;

  // -------------
  // Assertions
  // --------------
  //pragma translate_off
`ifndef VERILATOR
  // Static assertion check for appropriate bus width
  initial begin
    assert (ADDR_WIDTH == 64)
    else $error("Address width of 64 supported for now");
    assert (DATA_WIDTH == 64)
    else $error("Data width of 64 supported for now");
    assert (NR_CORES < 4095)
    else $error("Number of cores must be less than 4095");
  end
`endif
  //pragma translate_on

endmodule
