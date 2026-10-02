module dma_rx_1_to_2_new #(
   parameter TLP_WIDTH = 128, // TLP interface width
   parameter TLP_TOTAL_WIDTH = TLP_WIDTH + (TLP_WIDTH/8) + 21, // DC FIFO inlet width
   parameter RX_TLP_DC_FIFO_DEPTH = 64, // DC FIFO Depth
   parameter RX_TLP_DC_FIFO_REGMODE = "reg",
   parameter RX_TLP_DC_FIFO_IMPL = "EBR",
   parameter DEVICE_FAMILY = "common"
)
(
   input logic clk_i,
   input logic clk_fast_i,
   input logic rst_n_i,
   input logic rst_fast_n_i, // Reset of clk_fast_i

   // To TLP interface
   output logic rx_ready_o,

   // From TLP interface
   input logic [TLP_WIDTH-1:0] rx_data_i,
   input logic rx_valid_i,
   input logic [((TLP_WIDTH/8)-1):0] rx_datap_i,
   input logic rx_sop_i,
   input logic rx_eop_i,
   input logic [1:0] rx_sel_i,
   input logic [12:0] rx_cmd_data_i,
   input logic rx_err_ecrc_i,
   input logic [1:0] rx_f_i,

   // Module Outlet
   output logic [(2*TLP_WIDTH)-1:0] rx_data_o,
   output logic [((TLP_WIDTH/4)-1):0] rx_datap_o,
   output logic  rx_sop_o,
   output logic [1:0] rx_eop_o,
   output logic [1:0] rx_sel_o,
   output logic [12:0] rx_cmd_data_o,
   output logic rx_err_ecrc_o,
   output logic [1:0] rx_f_o,

   output logic rx_valid_o,
   input logic rx_ready_i
);

   localparam LOW_LUT = 1'b0; // Solve MPW
   typedef enum logic [1:0] {LOW = 2'd0,
                             HIGH = 2'd1,
                             MAY_SKIP = 2'd2
                         } fsm_state;

   fsm_state cs_sm, ns_sm;

   logic rx_tlp_dc_fifo_wr_en;
   logic rx_tlp_dc_fifo_rd_en, rx_tlp_dc_fifo_rd_en_f;
   logic [5:0] rx_tlp_dc_fifo_rd_en_ff; /* synthesis syn_preserve=1 */
   logic [TLP_TOTAL_WIDTH-1:0] rx_tlp_dc_fifo_datain;
   logic [(2*TLP_TOTAL_WIDTH)-1:0] rx_tlp_dc_fifo_dataout;
   logic rx_tlp_dc_fifo_empty;
   logic rx_tlp_dc_fifo_afull;
   logic not_rx_pipestg_afull;
   logic rx_ready_int; //nwai

   logic [1:0] nc_rx_datavalid_o;
   logic [1:0] rx_eop_int;
   logic nc_rx_sop;
   logic [1:0] nc_rx_sel;
   logic [12:0] nc_rx_cmd_data;
   logic [1:0] rx_err_ecrc_int;
   logic [1:0] nc_rx_f;

   assign rx_eop_o = |rx_eop_int;
   assign rx_err_ecrc_o = |rx_err_ecrc_int;

   // FSM Combi
   always_comb begin

      ns_sm = cs_sm;

      case (cs_sm)

         LOW: begin
            //nwai if (rx_valid_i & rx_ready_o & ~rx_eop_i) begin
            if (rx_valid_i & rx_ready_int & ~rx_eop_i) begin //nwai
               ns_sm = HIGH;
	    end
	    //nwai else if (rx_valid_i & rx_ready_o & rx_eop_i) begin
	    else if (rx_valid_i & rx_ready_int & rx_eop_i) begin //nwai
               ns_sm = MAY_SKIP;
            end
	    else begin
	       ns_sm = cs_sm;
	    end
	 end

         HIGH: begin
            //nwai if (rx_valid_i & rx_ready_o) begin
            if (rx_valid_i & rx_ready_int) begin //nwai
               ns_sm = LOW;
            end
            else begin
               ns_sm = cs_sm;
            end
         end

	  MAY_SKIP: begin
            //nwai if (rx_ready_o) begin
            if (rx_ready_int) begin //nwai
               ns_sm = LOW;
            end
            else begin
               ns_sm = cs_sm;
            end
         end

	 default: begin
            ns_sm = LOW;
         end

      endcase

   end

   // 1-to-2 frequency converter

   // Parameter Definition
   //Name                        Value                             Default
   /*
   ------------------------------------------------------------------------------
   pmi_data_width_w            <integer>                                      8
   pmi_data_width_r            <integer>                                      8
   pmi_data_depth_w            <integer>                                    256
   pmi_data_depth_r            <integer>                                    256
   pmi_full_flag               <integer>                                    256
   pmi_empty_flag              <integer>                                      0
   pmi_almost_full_flag        <integer>                                    252
   pmi_almost_empty_flag       <integer>                                      4
   pmi_regmode               "reg"|"noreg"                                "reg"
   pmi_resetmode             "async" | "sync"                           "async"
   pmi_family              "iCE40UP" | "LIFCL"                         "common"
   pmi_implementation    "LUT" |"EBR" | "HARD_IP"                      "HARD_IP"
   module_type                 <string>                           "pmi_fifo_dc"
   ------------------------------------------------------------------------------*/

   generate
      if (TLP_WIDTH != 0) begin: TLP_INTF_128 // always true
         pmi_fifo_dc #(
            .pmi_data_width_w(TLP_TOTAL_WIDTH),
            .pmi_data_width_r(2 * TLP_TOTAL_WIDTH),
            .pmi_data_depth_w(2 * RX_TLP_DC_FIFO_DEPTH), // Write depth = 2x Read depth because Write width = 0.5x Read width
            .pmi_data_depth_r(RX_TLP_DC_FIFO_DEPTH),
            // Not used .pmi_full_flag(),
            // Not used .pmi_empty_flag(),
            .pmi_almost_full_flag((2 * RX_TLP_DC_FIFO_DEPTH) - 2), // Inlet signal is flopped once, and almost full is flopped once.
            .pmi_almost_empty_flag(4),
            .pmi_regmode(LOW_LUT ? "noreg" : "reg"),
            .pmi_oreg_impl("EBR"), // Solve MPW
            .pmi_resetmode("async"), // TODO: To check
            .pmi_family(DEVICE_FAMILY),
            .pmi_implementation(RX_TLP_DC_FIFO_IMPL),
            .module_type("pmi_fifo_dc")
         ) rx_tlp_dc_fifo_inst
         (
            // Input
            .Data(rx_tlp_dc_fifo_datain),
            .WrClock(clk_fast_i),
            .RdClock(clk_i),
            .WrEn(rx_tlp_dc_fifo_wr_en),
            .RdEn(rx_tlp_dc_fifo_rd_en),
            .Reset(~rst_fast_n_i), // TODO: To check
            .RPReset(~rst_n_i), // TODO: To check
            // Output
            .Q(rx_tlp_dc_fifo_dataout),
            .Empty(rx_tlp_dc_fifo_empty),
            .Full(),
            .AlmostEmpty(),
            .AlmostFull(rx_tlp_dc_fifo_afull)
         );
      end
      //if (TLP_WIDTH == 64) begin: TLP_INTF_64
         // TODO
      //end
   endgenerate

   // Fast clock
   always_ff @(posedge clk_fast_i or negedge rst_fast_n_i) begin
      if (~rst_fast_n_i) begin
          cs_sm <= LOW;
      end
      else begin
         cs_sm <= ns_sm;
      end
   end

   always_ff @(posedge clk_fast_i or negedge rst_fast_n_i) begin
      if (~rst_fast_n_i) begin
	  rx_tlp_dc_fifo_wr_en <= 1'b0;
	  rx_tlp_dc_fifo_datain <= '0;
	  //nwai rx_ready_o <= 1'b0;
	  rx_ready_int <= 1'b0; //nwai
      end
      else begin
	 //nwai rx_tlp_dc_fifo_wr_en <= (rx_valid_i | (cs_sm == MAY_SKIP)) & rx_ready_o;
	 rx_tlp_dc_fifo_wr_en <= (rx_valid_i | (cs_sm == MAY_SKIP)) & rx_ready_int; //nwai
	 //nwai rx_tlp_dc_fifo_datain <= {rx_f_i, rx_err_ecrc_i, rx_cmd_data_i, rx_sel_i, rx_eop_i, rx_sop_i, rx_datap_i, rx_data_i, rx_valid_i};
	 rx_tlp_dc_fifo_datain <= (cs_sm == MAY_SKIP) ? '0: //nwai
		                  {rx_f_i, rx_err_ecrc_i, rx_cmd_data_i, rx_sel_i, rx_eop_i, rx_sop_i, rx_datap_i, rx_data_i, rx_valid_i}; //nwai
         //nwai rx_ready_o <= ~rx_tlp_dc_fifo_afull;
	 rx_ready_int <= ~rx_tlp_dc_fifo_afull;
      end
   end

   assign rx_ready_o = (cs_sm != MAY_SKIP) & rx_ready_int; //nwai

   generate
   if (LOW_LUT) begin: LOWLUT

/*      dma_rd_en_manager rd_en_manager
      (
         .clk_i(clk_i),
         .rst_n_i(rst_n_i),
         .fifo_empty_i(rx_tlp_dc_fifo_empty),
         .source_rd_en_i(rx_ready_i),
         .avail_o(rx_valid_o),
         .rd_en_o(rx_tlp_dc_fifo_rd_en)
      );

      assign {rx_f_o[1], rx_err_ecrc_o[1], rx_cmd_data_o[1], rx_sel_o[1], rx_eop_o[1], rx_sop_o[1], rx_datap_o[1], rx_data_o[1], rx_datavalid_o[1],
               rx_f_o[0], rx_err_ecrc_o[0], rx_cmd_data_o[0], rx_sel_o[0], rx_eop_o[0], rx_sop_o[0], rx_datap_o[0], rx_data_o[0], rx_datavalid_o[0]} = rx_tlp_dc_fifo_dataout;
*/
   depth2_fifo_new #(
      .WIDTH(2 * TLP_TOTAL_WIDTH),
      .PIPESTG_EN(1'b1)
   ) rx_tlp_fifo (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .data_i(rx_tlp_dc_fifo_dataout),
      .empty_i(rx_tlp_dc_fifo_empty),
      .rd_en_o(rx_tlp_dc_fifo_rd_en),
      .data_o({nc_rx_f, rx_err_ecrc_int[1], nc_rx_cmd_data, nc_rx_sel, rx_eop_int[1], nc_rx_sop, rx_datap_o[((TLP_WIDTH/4)-1):(TLP_WIDTH/8)], rx_data_o[(2*TLP_WIDTH)-1:TLP_WIDTH], nc_rx_datavalid_o[1],
               rx_f_o, rx_err_ecrc_int[0], rx_cmd_data_o, rx_sel_o, rx_eop_int[0], rx_sop_o, rx_datap_o[((TLP_WIDTH/8)-1):0], rx_data_o[TLP_WIDTH-1:0], nc_rx_datavalid_o[0]}),
      .valid_o(rx_valid_o),
      .ready_i(rx_ready_i)
   );

   end
   else begin: HIGHLUT

   // Slow clock
   always_ff @(posedge clk_i or negedge rst_n_i) begin
      if (~rst_n_i) begin
          rx_tlp_dc_fifo_rd_en_f <= '0;
          rx_tlp_dc_fifo_rd_en_ff <= '0;
      end
      else begin
         rx_tlp_dc_fifo_rd_en_f <= rx_tlp_dc_fifo_rd_en;
         rx_tlp_dc_fifo_rd_en_ff <= {6{rx_tlp_dc_fifo_rd_en_f}};
      end
   end

   assign rx_tlp_dc_fifo_rd_en = ~rx_tlp_dc_fifo_empty & not_rx_pipestg_afull;

   shreg_pipe_ultimate #(
      .WIDTH(2 * TLP_TOTAL_WIDTH),
      .IN_FLOP_EN(1'b0), // Flop in EBR
      .USE_VALID(1'b0)
   ) rx_pipestg
   (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .data_i(rx_tlp_dc_fifo_dataout),
      .valid_i(6'b0),
      .wr_en_i(rx_tlp_dc_fifo_rd_en_ff[5:0]),
      .not_almost_full_o(not_rx_pipestg_afull), // -2
      .data_o({nc_rx_f, rx_err_ecrc_int[1], nc_rx_cmd_data, nc_rx_sel, rx_eop_int[1], nc_rx_sop, rx_datap_o[((TLP_WIDTH/4)-1):(TLP_WIDTH/8)], rx_data_o[(2*TLP_WIDTH)-1:TLP_WIDTH], nc_rx_datavalid_o[1],
               rx_f_o, rx_err_ecrc_int[0], rx_cmd_data_o, rx_sel_o, rx_eop_int[0], rx_sop_o, rx_datap_o[((TLP_WIDTH/8)-1):0], rx_data_o[TLP_WIDTH-1:0], nc_rx_datavalid_o[0]}),
      .valid_o(rx_valid_o),
      .ready_i(rx_ready_i)
   );

   end
   endgenerate

endmodule
