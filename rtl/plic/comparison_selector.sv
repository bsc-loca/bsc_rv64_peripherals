
//!
//! **PROJECT:**             System_Verilog_Hardware_Common_Lib
//!
//! **LANGUAGE:**            Verilog, SystemVerilog
//!
//! **FILE:**                comparison_selector.sv
//!
//! **AUTHOR(S):**
//!
//!   - Jonnatan Mendoza Escobar     - jonnatan.mendoza@bsc.es (JM)
//!
//! **CONTRIBUTORS:**
//!
//!   - Example Contributor          - email.contributor@bsc.es (EC)
//!
//! **REVISION:**
//!   * 0.01 - Initial release. (JM) 13/Jan/2022
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
//! Parameterizable Greatest/Smallest selector, the code implements a binary tree of comparisons
//! to select one register, type for registers and ids are also parametric.

module comparison_selector #(

    parameter logic MTHAN_LTHAN       = 1'b1,       //! HIGH(1'b1): Greatest Selector, LOW(1'b0): Smallest Selector
    parameter logic DEFAULT_PRIORITY  = 1'b1,       //! HIGH(1'b1): Greatest Port Priority, LOW(1'b0): Smallest Port Priority (IN CASE OF EQUAL VALUES)
    parameter       N_PORTS           = 8,          //! Number of input ports to compare and select from.
    parameter       ID_SIZE           = 3,          //! Data sizes for each port ID.
    parameter       DATA_WIDTH        = 8,

    //! Parameter express if a register must be placed after a comparison layer, each bit of the array set the corresponding
    //! layer regs being the LSB the one that correspond to the first layer. So, for an 8 elements input there are at most 3
    //! layers, being the last one the direct output.
    parameter  bit [$clog2(N_PORTS)-1:0] REG_PATTERN = {1'b0,1'b1,1'b0},
    
    localparam type  REG_SIZE_TYP_T  = logic[DATA_WIDTH-1:0]  //! Data type for each port comparation register.
    )(
    
    /* verilator lint_off UNUSED */
    input logic                 clk_i,                              //! System Clock.
    input logic                 rstn_i,                             //! Asynchronous reset active low.
    /* verilator lint_on UNUSED */

    input logic                 flush_i,

    input  logic[0:0]           comp_en_i           [N_PORTS-1:0],  //! Array of enables/valids aligned to the comparison regs, if set the corresponding comparison reg will be take into account for the comparison.
    input  REG_SIZE_TYP_T       comparation_regs_i  [N_PORTS-1:0],  //! Unpacked array of elemts to be compared and selected.
    input  logic [ID_SIZE-1:0]  ids_of_regs_i       [N_PORTS-1:0],  //! ID number that relates each comparation_regs_i input.

    output logic [0:0]          valid_o,
    output REG_SIZE_TYP_T       selected_value_o,                    //! Result of the selection tree process.
    output logic [ID_SIZE-1:0]  selected_id_o                        //! ID of the selected element.
    );

   localparam TREE_DEPTH = $clog2(N_PORTS);

   localparam B2_PORT_WIDTH    = 2**$clog2(N_PORTS);
   localparam SPLIT_PORT_WIDTH = B2_PORT_WIDTH/2;

   logic[0:0]           valid_d;
   REG_SIZE_TYP_T       selected_value_d;
   logic [ID_SIZE-1:0]  selected_id_d;

   generate
       
        if(TREE_DEPTH <= 1) begin   // Final leaf
        
            logic comp_result, both_valid;
            assign both_valid = comp_en_i[0] && comp_en_i[1];
            
            localparam LEFT_IDX  = (DEFAULT_PRIORITY) ? 0 : 1;
            localparam RIGHT_IDX = (DEFAULT_PRIORITY) ? 1 : 0;

            if (MTHAN_LTHAN) begin
                assign comp_result = (both_valid) ? comparation_regs_i[LEFT_IDX] > comparation_regs_i[RIGHT_IDX] : comp_en_i[LEFT_IDX];
            end else begin
                assign comp_result = (both_valid) ? comparation_regs_i[LEFT_IDX] < comparation_regs_i[RIGHT_IDX] : comp_en_i[LEFT_IDX];
            end

            // Comparation of final leaf
            // Mux selection
            assign valid_d = comp_en_i[0] || comp_en_i[1];


            if (DEFAULT_PRIORITY) begin
                assign selected_value_d = (comp_result) ? comparation_regs_i[0] : comparation_regs_i[1] ;
                assign selected_id_d    = (comp_result) ? ids_of_regs_i[0]      : ids_of_regs_i[1];
            end else begin
                assign selected_value_d = (comp_result) ? comparation_regs_i[1] : comparation_regs_i[0] ;
                assign selected_id_d    = (comp_result) ? ids_of_regs_i[1]      : ids_of_regs_i[0];
            end

            if (REG_PATTERN[0] == 1'b1) begin

                logic[0:0]           valid_q;
                REG_SIZE_TYP_T       selected_value_q;
                logic [ID_SIZE-1:0]  selected_id_q; 

                always_ff @(posedge clk_i or negedge rstn_i) begin : proc_result_value_q
                    if(~rstn_i) begin
                        valid_q          <= 1'b0;
                        selected_value_q <= {$bits(REG_SIZE_TYP_T){1'b0}};
                        selected_id_q    <= {ID_SIZE{1'b0}};
                    end else if (flush_i) begin
                        valid_q          <= 1'b0;
                        selected_value_q <= {$bits(REG_SIZE_TYP_T){1'b0}};
                        selected_id_q    <= {ID_SIZE{1'b0}};
                    end else begin
                        valid_q          <= valid_d;
                        selected_value_q <= selected_value_d;
                        selected_id_q    <= selected_id_d;
                    end
                end
                // Output with register
                assign valid_o          = valid_q;         
                assign selected_value_o = selected_value_q;
                assign selected_id_o    = selected_id_q;   
            end else begin
                // Direct combinational output
                always_comb begin
                    if (flush_i) begin
                        valid_o          = 1'b0;
                        selected_value_o = {$bits(REG_SIZE_TYP_T){1'b0}};
                        selected_id_o    = {ID_SIZE{1'b0}};
                    end else begin
                        valid_o          = valid_d;
                        selected_value_o = selected_value_d;
                        selected_id_o    = selected_id_d;
                    end
                end
            end

        end else begin  // if $clog2(N_PORTS) > 1 then split in 2 the ports and apply recursion

            REG_SIZE_TYP_T lsport;      // less significant port register
            REG_SIZE_TYP_T msport;      // more significant port register

            logic [ID_SIZE-1:0] lsid;   // less significant id
            logic [ID_SIZE-1:0] msid;   // more significant id

            logic ls_valid;             // less significant valid
            logic ms_valid;             // more significant valid

            // Lower part of port
            comparison_selector #(
                .MTHAN_LTHAN       (MTHAN_LTHAN),
                .DEFAULT_PRIORITY  (DEFAULT_PRIORITY),
                .N_PORTS           (SPLIT_PORT_WIDTH),
                .ID_SIZE           (ID_SIZE),
                .DATA_WIDTH        (DATA_WIDTH),
                .REG_PATTERN       (REG_PATTERN[$clog2(SPLIT_PORT_WIDTH)-1:0])
            ) comparison_selector_inst_l (

                .clk_i              (clk_i),
                .rstn_i             (rstn_i),

                .flush_i            (flush_i),

                .comp_en_i          (comp_en_i[SPLIT_PORT_WIDTH-1:0]),
                .comparation_regs_i (comparation_regs_i[SPLIT_PORT_WIDTH-1:0]),
                .ids_of_regs_i      (ids_of_regs_i[SPLIT_PORT_WIDTH-1:0]),

                .valid_o            (ls_valid),
                .selected_value_o   (lsport),
                .selected_id_o      (lsid)
            );

            logic [0:0]          b2_ms_en_port   [SPLIT_PORT_WIDTH-1:0];
            REG_SIZE_TYP_T       b2_ms_regs_port [SPLIT_PORT_WIDTH-1:0];            // if we have a number that is not multiple of base 2
            logic [ID_SIZE-1:0]  b2_ms_ids_port  [SPLIT_PORT_WIDTH-1:0];            // we must compleate the tree with identity values

            assign   b2_ms_en_port[N_PORTS-SPLIT_PORT_WIDTH -1:0]  =          comp_en_i[N_PORTS-1:SPLIT_PORT_WIDTH];
            assign b2_ms_regs_port[N_PORTS-SPLIT_PORT_WIDTH -1:0]  = comparation_regs_i[N_PORTS-1:SPLIT_PORT_WIDTH];
            assign  b2_ms_ids_port[N_PORTS-SPLIT_PORT_WIDTH -1:0]  =      ids_of_regs_i[N_PORTS-1:SPLIT_PORT_WIDTH];

            if (MTHAN_LTHAN) begin
                for (genvar i = N_PORTS-SPLIT_PORT_WIDTH ; i < SPLIT_PORT_WIDTH ; i++) begin
                    assign b2_ms_en_port[i]   = 1'b0;   
                    assign b2_ms_regs_port[i] = {$bits(REG_SIZE_TYP_T){1'b0}};
                    assign b2_ms_ids_port[i]  = i[ID_SIZE-1:0] + SPLIT_PORT_WIDTH[ID_SIZE-1:0];
                end
            end else begin
                for (genvar i = N_PORTS-SPLIT_PORT_WIDTH ; i < SPLIT_PORT_WIDTH ; i++) begin
                    assign b2_ms_en_port[i]   = 1'b0;   
                    assign b2_ms_regs_port[i] = {$bits(REG_SIZE_TYP_T){1'b1}};
                    assign b2_ms_ids_port[i]  = i[ID_SIZE-1:0] + SPLIT_PORT_WIDTH[ID_SIZE-1:0];
                    //assign b2_ms_ids_port[i]= {$bits(logic [ID_SIZE-1:0]){1'b1}};
                end
            end


            // Higer part of the por
            comparison_selector #(
                .MTHAN_LTHAN       (MTHAN_LTHAN),
                .DEFAULT_PRIORITY  (DEFAULT_PRIORITY),
                .N_PORTS           (SPLIT_PORT_WIDTH),
                .ID_SIZE           (ID_SIZE),
                .DATA_WIDTH        (DATA_WIDTH),
                .REG_PATTERN       (REG_PATTERN[$clog2(SPLIT_PORT_WIDTH)-1:0])
            ) comparison_pipeline_selector_inst_m (

                .clk_i              (clk_i),
                .rstn_i             (rstn_i),

                .flush_i            (flush_i),

                .comp_en_i          (b2_ms_en_port),
                .comparation_regs_i (b2_ms_regs_port),
                .ids_of_regs_i      (b2_ms_ids_port),

                .valid_o            (ms_valid),
                .selected_value_o   (msport),
                .selected_id_o      (msid)
            );


            // Final Comparation
            logic fcomp_result, both_valid ;
            assign both_valid = ls_valid && ms_valid;
            

            if (MTHAN_LTHAN) begin
                if (DEFAULT_PRIORITY) begin
                    assign fcomp_result = (both_valid) ? lsport > msport : ls_valid;
                end else begin
                    assign fcomp_result = (both_valid) ? msport > lsport : ms_valid;
                end
            end
            else begin
                if (DEFAULT_PRIORITY) begin
                    assign fcomp_result = (both_valid) ? lsport < msport : ls_valid;
                end else begin
                    assign fcomp_result = (both_valid) ? msport < lsport : ms_valid;
                end
            end
            
            // Mux selection
            assign valid_d          = ms_valid || ls_valid;

            if (DEFAULT_PRIORITY) begin
                assign selected_value_d = (fcomp_result) ? lsport : msport;
                assign selected_id_d    = (fcomp_result) ? lsid   : msid;
            end else begin
                assign selected_value_d = (fcomp_result) ? msport : lsport;
                assign selected_id_d    = (fcomp_result) ? msid   : lsid;
            end

            if (REG_PATTERN[TREE_DEPTH-1] == 1'b1) begin

                logic[0:0]           valid_q;
                REG_SIZE_TYP_T       selected_value_q;
                logic [ID_SIZE-1:0]  selected_id_q; 

                always_ff @(posedge clk_i or negedge rstn_i) begin : proc_result_value_q
                    if(~rstn_i) begin
                        valid_q          <= 1'b0;
                        selected_value_q <= {$bits(REG_SIZE_TYP_T){1'b0}};
                        selected_id_q    <= {ID_SIZE{1'b0}};
                    end else if (flush_i) begin
                        valid_q          <= 1'b0;
                        selected_value_q <= {$bits(REG_SIZE_TYP_T){1'b0}};
                        selected_id_q    <= {ID_SIZE{1'b0}};
                    end else begin
                        valid_q          <= valid_d;
                        selected_value_q <= selected_value_d;
                        selected_id_q    <= selected_id_d;
                    end
                end
                // Output with register
                assign valid_o          = valid_q;         
                assign selected_value_o = selected_value_q;
                assign selected_id_o    = selected_id_q;   
            end else begin
                // Direct combinational output
                always_comb begin
                    if (flush_i) begin
                        valid_o          = 1'b0;
                        selected_value_o = {$bits(REG_SIZE_TYP_T){1'b0}};
                        selected_id_o    = {ID_SIZE{1'b0}};
                    end else begin
                        valid_o          = valid_d;
                        selected_value_o = selected_value_d;
                        selected_id_o    = selected_id_d;
                    end
                end
            end
               

        end

   endgenerate

endmodule
