module dma_tx_2_to_1_new #(
   parameter TLP_WIDTH = 128, // TLP interface width
   parameter TX_TLP_DC_FIFO_DEPTH = 64, // DC FIFO Depth
   parameter TX_TLP_DC_FIFO_REGMODE = "noreg",
   parameter DEVICE_FAMILY = "common",
   parameter TX_TLP_DC_FIFO_IMPL = "EBR"
)
(
   input logic clk_i,
   input logic clk_fast_i,
   input logic rst_n_i,
   input logic rst_fast_n_i, // Reset of clk_fast_i

   // Module Inlet
   //input logic [(2 * TLP_TOTAL_WIDTH)-1:0] tx_tlp_dc_fifo_datain,
   input logic [(2*TLP_WIDTH)-1:0] tx_data_i,
   input logic [(TLP_WIDTH/4)-1:0] tx_datap_i,
   input logic tx_sop_i,
   input logic tx_eop_i,
   input logic tx_valid_i,
   output logic txready_o, /* synthesis syn_preserve=1 */

   // From TLP interface
   input logic tx_ready_i,

   // To TLP interface
   output logic [TLP_WIDTH-1:0] tx_data_o,
   output logic tx_valid_o,
   output logic [((TLP_WIDTH/8)-1):0] tx_datap_o,
   output logic tx_sop_o,
   output logic tx_eop_o
) /* synthesis LATTICE_IP_MODULE=1 */ ;

   localparam TLP_TOTAL_WIDTH = TLP_WIDTH + (TLP_WIDTH/8) + 2 + 6; // 6 datavalid. However, 2 datavalid need to go to final pipe stage to make it modular 4

   logic [(2*TLP_TOTAL_WIDTH)-1:0] tx_tlp_dc_fifo_datain;
   logic txready_int_nxt, txready_int; /* synthesis syn_preserve=1 */
   logic tx_tlp_dc_fifo_rd_en, tx_tlp_dc_fifo_rd_en_2, tx_tlp_dc_fifo_rd_en_f;
   logic [5:0] tx_tlp_dc_fifo_rd_en_ff;  /* synthesis syn_preserve=1 */
   logic tx_tlp_dc_fifo_rd_en_fff;
   logic [TLP_TOTAL_WIDTH-1:0] tx_tlp_dc_fifo_dataout, tx_tlp_dc_fifo_dataout_f, tx_tlp_dc_fifo_dataout_ff;
   logic [TLP_TOTAL_WIDTH-1:0] tx_dcfifo_data_flop2_datain;
   logic tx_tlp_dc_fifo_rden_data_and;
   logic tx_tlp_dc_fifo_inst0_empty, tx_tlp_dc_fifo_inst1_empty;
   logic tx_tlp_dc_fifo_inst0_empty_f, tx_tlp_dc_fifo_inst1_empty_f;
   logic tx_tlp_dc_fifo_inst0_afull, tx_tlp_dc_fifo_inst1_afull;
   logic not_tx_pipestg_afull, not_tx_pipestg_afull_f;
   logic not_tx_pipestg_afull_2, not_tx_pipestg_afull_3;
   logic [1:0] nc_valid;
   logic tx_pipestg_afull;
   logic tx_pipestg_2_full;

   logic [TLP_WIDTH-1:0] tx_data_int;
   logic tx_valid_int;
   logic [((TLP_WIDTH/8)-1):0] tx_datap_int;
   logic tx_sop_int;
   logic tx_eop_int;
   logic tx_ready_int;
   logic tlp_intf128_wren;
   logic [1:0] nc_data_valid;

   logic [1:0] tx_eop_in;
   logic tx_datavalid_upper;
   logic eop_at_upper, eop_at_upper_8dw, eop_at_upper_4dw, eop_at_upper_2dw;
   logic [2:0] tlp_fmt;
   logic [4:0] tlp_type;
   logic [7:0] tlp_length;
   logic [2:0] hdr_size;
   logic [2:0] total_dw; // 3 bits are sufficient
   logic eop_upper_flag;
   logic eop_upper_flag_set, eop_upper_flag_set_8dw, eop_upper_flag_set_4dw, eop_upper_flag_set_2dw;
   logic eop_upper_flag_clr;

   assign tlp_intf128_wren = tx_valid_i & txready_int;

   // 2-segment derivation
   assign tlp_fmt = tx_data_i[7:5];
   assign tlp_type = tx_data_i[4:0];
   assign tlp_length = tx_data_i[31:24];
   assign eop_at_upper_8dw = (tx_sop_i & tlp_fmt[1] & (tlp_type == 'b01010) & (tlp_length != 'd1)) | // CplD != 1DW
	                     (tx_sop_i & tlp_fmt[1] & (tlp_type == 'b00000) & ~(~tlp_fmt[0] & (tlp_length == 'd1))); // MWr and not "3dw header with 1dw data"
   assign eop_at_upper_4dw = (tx_sop_i & tlp_fmt[1] & (tlp_type == 'b01010) & (tlp_length == 'd1)) | // CplD = 1DW
                             (tx_sop_i & (tlp_fmt == 'b010) & (tlp_type == 'b00000) & (tlp_length == 'd1)) | // MWr 3dw header with 1dw data
			     (tx_sop_i & (tlp_fmt[2:1] == 'b00) & (tlp_type == 'b00000)); // MRd (4dw header and 3dw header)
   assign eop_at_upper_2dw = 1'b0; // Not possible

   assign eop_at_upper = (TLP_WIDTH == 128) ? eop_at_upper_8dw : (TLP_WIDTH == 64) ? eop_at_upper_4dw : eop_at_upper_2dw;
   assign hdr_size = tlp_fmt[0] ? 'd4 :'d3;
   assign total_dw = hdr_size[2:0] + tlp_length[2:0];
   assign eop_upper_flag_set_8dw = tlp_fmt[1] & ((total_dw[2:0] == 'd0) | (total_dw[2:0] > 'd4)) & tx_sop_i & ~tx_eop_i & tx_valid_i;
   assign eop_upper_flag_set_4dw = tlp_fmt[1] & ((total_dw[1:0] == 'd0) | (total_dw[1:0] == 'd3)) & tx_sop_i & ~tx_eop_i & tx_valid_i;
   assign eop_upper_flag_set_2dw = (tlp_fmt[1] & (total_dw[0] == 1'b0) & tx_sop_i & ~tx_eop_i & tx_valid_i) |
	                           ((tlp_fmt == 3'b001) & (tlp_type == 'b00000) & tx_sop_i & ~tx_eop_i & tx_valid_i); // MRd 4dw header
   assign eop_upper_flag_set = (TLP_WIDTH == 128) ? eop_upper_flag_set_8dw : (TLP_WIDTH == 64) ? eop_upper_flag_set_4dw : eop_upper_flag_set_2dw;
   assign eop_upper_flag_clr = tx_eop_i & tx_valid_i & txready_o;
   assign tx_eop_in[0] = tx_eop_i & ~(eop_at_upper | eop_upper_flag);
   assign tx_eop_in[1] = tx_eop_i & (eop_at_upper | eop_upper_flag);
   assign tx_datavalid_upper = ~tx_eop_in[0];

   assign tx_tlp_dc_fifo_datain =
          {{6{tx_datavalid_upper}}, tx_eop_in[1], 1'b0,     tx_datap_i[(TLP_WIDTH/4)-1:(TLP_WIDTH/8)], tx_data_i[(2*TLP_WIDTH)-1:TLP_WIDTH],
           6'b111111,               tx_eop_in[0], tx_sop_i, tx_datap_i[(TLP_WIDTH/8)-1:0],             tx_data_i[TLP_WIDTH-1:0]};
   
   // 2-to-1 frequency converter

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
      if (TLP_WIDTH != 0) begin: TLP_INTF_128 // nwai: temp always enable
         pmi_fifo_dc #(
            .pmi_data_width_w(TLP_TOTAL_WIDTH),
            .pmi_data_width_r(TLP_TOTAL_WIDTH / 2),
            .pmi_data_depth_w(TX_TLP_DC_FIFO_DEPTH), // Write depth = 0.5x Read depth because Write width = 2x Read width
            .pmi_data_depth_r(2 * TX_TLP_DC_FIFO_DEPTH),
            // Not used .pmi_full_flag(),
            // Not used .pmi_empty_flag(),
            .pmi_almost_full_flag(TX_TLP_DC_FIFO_DEPTH - 8), // was -4
            .pmi_almost_empty_flag(4),
            .pmi_regmode(TX_TLP_DC_FIFO_REGMODE),
	    .pmi_oreg_impl("EBR"),
            .pmi_resetmode("async"), // TODO: To check
            .pmi_family(DEVICE_FAMILY),
            .pmi_implementation(TX_TLP_DC_FIFO_IMPL),
            .module_type("pmi_fifo_dc")
         ) tx_tlp_dc_fifo_inst0
         (
            // Input
            .Data({tx_tlp_dc_fifo_datain[((TLP_TOTAL_WIDTH/2)+TLP_TOTAL_WIDTH-1):(TLP_TOTAL_WIDTH)], tx_tlp_dc_fifo_datain[(TLP_TOTAL_WIDTH/2)-1:0]}),
            .WrClock(clk_i),
            .RdClock(clk_fast_i),
            .WrEn(tlp_intf128_wren), // PV fix
            .RdEn(tx_tlp_dc_fifo_rd_en),
            .Reset(~rst_n_i), // TODO: To check
            .RPReset(~rst_fast_n_i), // TODO: To check
            // Output
            .Q(tx_tlp_dc_fifo_dataout[(TLP_TOTAL_WIDTH/2)-1:0]),
            .Empty(tx_tlp_dc_fifo_inst0_empty),
            .Full(),
            .AlmostEmpty(),
            .AlmostFull(tx_tlp_dc_fifo_inst0_afull)
         );

         pmi_fifo_dc #(
            .pmi_data_width_w(TLP_TOTAL_WIDTH),
            .pmi_data_width_r(TLP_TOTAL_WIDTH / 2),
            .pmi_data_depth_w(TX_TLP_DC_FIFO_DEPTH), // Write depth = 0.5x Read depth because Write width = 2x Read width
            .pmi_data_depth_r(2 * TX_TLP_DC_FIFO_DEPTH),
            // Not used .pmi_full_flag(),
            // Not used .pmi_empty_flag(),
            .pmi_almost_full_flag(TX_TLP_DC_FIFO_DEPTH - 8), // was -4
            .pmi_almost_empty_flag(4),
            .pmi_regmode(TX_TLP_DC_FIFO_REGMODE),
	    .pmi_oreg_impl("EBR"),
            .pmi_resetmode("async"), // TODO: To check
            .pmi_family(DEVICE_FAMILY),
            .pmi_implementation(TX_TLP_DC_FIFO_IMPL),
            .module_type("pmi_fifo_dc")
         ) tx_tlp_dc_fifo_inst1
         (
            // Input
            .Data({tx_tlp_dc_fifo_datain[(2*TLP_TOTAL_WIDTH)-1:((TLP_TOTAL_WIDTH/2)+TLP_TOTAL_WIDTH)], tx_tlp_dc_fifo_datain[TLP_TOTAL_WIDTH-1:(TLP_TOTAL_WIDTH/2)]}),
            .WrClock(clk_i),
            .RdClock(clk_fast_i),
            .WrEn(tlp_intf128_wren), // PV fix
            .RdEn(tx_tlp_dc_fifo_rd_en_2),
            .Reset(~rst_n_i), // TODO: To check
            .RPReset(~rst_fast_n_i), // TODO: To check
            // Output
            .Q(tx_tlp_dc_fifo_dataout[TLP_TOTAL_WIDTH-1:(TLP_TOTAL_WIDTH/2)]),
            .Empty(tx_tlp_dc_fifo_inst1_empty),
            .Full(),
            .AlmostEmpty(),
            .AlmostFull(tx_tlp_dc_fifo_inst1_afull)
         );
      end
      //if (TLP_WIDTH == 64) begin: TLP_INTF_64
         // TODO
      //end
   endgenerate

   assign txready_int_nxt = ~tx_tlp_dc_fifo_inst0_afull & ~tx_tlp_dc_fifo_inst1_afull;

   always_ff @(posedge clk_i or negedge rst_n_i) begin
      if (~rst_n_i) begin
          txready_o <= '0;
	  txready_int <= '0;
	  eop_upper_flag <= 1'b0;
      end
      else begin
         txready_o <= txready_int_nxt;
	 txready_int <= txready_int_nxt;
	 eop_upper_flag <= (eop_upper_flag | eop_upper_flag_set) & ~eop_upper_flag_clr;
      end
   end

   assign tx_tlp_dc_fifo_rd_en = ~tx_tlp_dc_fifo_inst0_empty & ~tx_tlp_dc_fifo_inst1_empty & not_tx_pipestg_afull_2;
   assign tx_tlp_dc_fifo_rd_en_2 = ~tx_tlp_dc_fifo_inst0_empty & ~tx_tlp_dc_fifo_inst1_empty & not_tx_pipestg_afull_3;

   always_ff @(posedge clk_fast_i or negedge rst_fast_n_i) begin
      if (~rst_fast_n_i) begin
          //tx_tlp_dc_fifo_rd_en_f <= '0;
          tx_tlp_dc_fifo_rd_en_ff[5:0] <= '0;
	  tx_tlp_dc_fifo_rd_en_fff <= 1'b0;
	  tx_tlp_dc_fifo_inst0_empty_f <= 1'b0;
	  tx_tlp_dc_fifo_inst1_empty_f <= 1'b0;
	  not_tx_pipestg_afull_f <= 1'b0;
      end
      else begin
         //tx_tlp_dc_fifo_rd_en_f <= ~tx_tlp_dc_fifo_inst0_empty & ~tx_tlp_dc_fifo_inst1_empty & not_tx_pipestg_afull;
         tx_tlp_dc_fifo_rd_en_ff[5:0] <= {6{tx_tlp_dc_fifo_rd_en_f}};
	 tx_tlp_dc_fifo_rd_en_fff <= tx_tlp_dc_fifo_rd_en_ff[5];
	 tx_tlp_dc_fifo_inst0_empty_f <= tx_tlp_dc_fifo_inst0_empty;
         tx_tlp_dc_fifo_inst1_empty_f <= tx_tlp_dc_fifo_inst1_empty;
         not_tx_pipestg_afull_f <= not_tx_pipestg_afull;
      end
   end

   // Timing fix:
   assign tx_tlp_dc_fifo_rd_en_f = ~tx_tlp_dc_fifo_inst0_empty_f & ~tx_tlp_dc_fifo_inst1_empty_f & not_tx_pipestg_afull_f;

   dma_flop_stg #(
      .RESETTABLE(1'b0),
      .WIDTH(TLP_TOTAL_WIDTH/2)
   ) tx_dcfifo_data_flop1_a
   (
      .clk_i(clk_fast_i),
      .rst_n_i(rst_fast_n_i),
      .data_i(tx_tlp_dc_fifo_dataout[(TLP_TOTAL_WIDTH/2)-1:0]),
      .data_o(tx_tlp_dc_fifo_dataout_f[(TLP_TOTAL_WIDTH/2)-1:0])
   );

   dma_flop_stg #(
      .RESETTABLE(1'b0),
      .WIDTH(TLP_TOTAL_WIDTH/2)
   ) tx_dcfifo_data_flop1_b
   (
      .clk_i(clk_fast_i),
      .rst_n_i(rst_fast_n_i),
      .data_i(tx_tlp_dc_fifo_dataout[TLP_TOTAL_WIDTH-1:(TLP_TOTAL_WIDTH/2)]),
      .data_o(tx_tlp_dc_fifo_dataout_f[TLP_TOTAL_WIDTH-1:(TLP_TOTAL_WIDTH/2)])
   );

   //
   assign tx_dcfifo_data_flop2_datain = (TX_TLP_DC_FIFO_REGMODE == "reg") ? tx_tlp_dc_fifo_dataout : tx_tlp_dc_fifo_dataout_f;

   dma_flop_stg #(
      .RESETTABLE(1'b0),
      .WIDTH(TLP_TOTAL_WIDTH)
   ) tx_dcfifo_data_flop2
   (
      .clk_i(clk_fast_i),
      .rst_n_i(rst_fast_n_i),
      .data_i(tx_dcfifo_data_flop2_datain),
      .data_o(tx_tlp_dc_fifo_dataout_ff)
   );

assign tx_tlp_dc_fifo_rden_data_and = (tx_tlp_dc_fifo_rd_en_fff & tx_tlp_dc_fifo_dataout_ff[TLP_TOTAL_WIDTH-1]);
   dma_fifo #(
      .FIFO_WIDTH(TLP_TOTAL_WIDTH-4),
      .FIFO_DEPTH(8),
      .PIPESTG_EN(1'b0),
      .FIFO_REGMODE("noreg"), // "reg", "noreg"
      .FIFO_IMPL("LUT"), // "LUT", "EBR", "HARD_IP"
      .AFULL_FLAG(3),
      .DEVICE_FAMILY(DEVICE_FAMILY)
   ) tx_pipestg
   (
      // Clock and reset
      .clk_i(clk_fast_i),
      .rst_n_i(rst_fast_n_i),
      // Inlet
      .wr_en_i(tx_tlp_dc_fifo_rden_data_and),
      .data_i(tx_tlp_dc_fifo_dataout_ff[TLP_TOTAL_WIDTH-4-1:0]),
      .almost_full_o(tx_pipestg_afull),
      .full_o(),
      // Outlet
      .data_o({nc_data_valid, tx_eop_int, tx_sop_int, tx_datap_int, tx_data_int}),
//      .data_o({tx_eop_int, tx_sop_int, tx_datap_int, tx_data_int}),
      .valid_o(tx_valid_int),
      .ready_i(tx_ready_int)
   );

   assign not_tx_pipestg_afull = ~tx_pipestg_afull;
   assign not_tx_pipestg_afull_2 = ~tx_pipestg_afull;
   assign not_tx_pipestg_afull_3 = ~tx_pipestg_afull;

   /*dma_skid_fifo #(
      .WIDTH(TLP_TOTAL_WIDTH-6)
   ) tx_pipestg_2 (
      .clk_i(clk_fast_i),
      .rst_n_i(rst_fast_n_i),
      .idata_i({tx_eop_int, tx_sop_int, tx_datap_int, tx_data_int}),
      .ivalid_i(tx_valid_int),
      .iready_o(tx_ready_int),
      .odata_o({tx_eop_o, tx_sop_o, tx_datap_o, tx_data_o}),
      .ovalid_o(tx_valid_o),
      .oready_i(tx_ready_i)
   );*/

   shreg_pipe_2stg #(
      .WIDTH(TLP_TOTAL_WIDTH-6)
   ) tx_pipestg_2
   (
      .clk_i(clk_fast_i),
      .rst_n_i(rst_fast_n_i),
      .data_i({tx_eop_int, tx_sop_int, tx_datap_int, tx_data_int}),
      .valid_i(tx_valid_int),
      .ready_o(tx_ready_int),
      .data_o({tx_eop_o, tx_sop_o, tx_datap_o, tx_data_o}),
      .valid_o(tx_valid_o),
      .ready_i(tx_ready_i)
   ); 

endmodule
