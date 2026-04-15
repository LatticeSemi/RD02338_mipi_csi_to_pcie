
`timescale 1ps/1ps

module pcie_app #(
    parameter DATA_WIDTH     = 512,
    parameter NUM_OF_LANES    = 1,
    parameter SERIES_PATTERN = 1,
    parameter NUM_PACKETS    = 16,
    parameter MPS_BYTES    = 512,  // KD 
    parameter MEM_BYTES    = 4096, // KD in byte
    parameter DW_ALIGN_RAM = 0,     // mem inst with 1 SEG per dw
    parameter DEVICE_FAMILY = "LFCPNX",
    parameter LINK0_FTL_INITIAL_TARGET_LINK_SPEED = 2
)(
    input                     clk,
    input                     clk_250,
    input                     rst_n,
    // rx TLP interface
    output                    vc_rx_ready_o ,
    input                     vc_rx_valid_i ,
    input [1:0]               vc_rx_sel_i ,
    input [12:0]              vc_rx_cmd_data_i ,
    input                     vc_rx_sop_i ,
    input [DATA_WIDTH-1:0]    vc_rx_data_i,
    input [DATA_WIDTH/8-1:0]  vc_rx_datap_i,
    input                     vc_rx_eop_i ,
    input                     vc_rx_err_ecrc_i,
    input [1:0]               vc_rx_f_i ,
    // tx TLP interface
    output                    vc_tx_valid_o ,
    output                    vc_tx_eop_o ,
    output                    vc_tx_eop_n_o, 
    output                    vc_tx_sop_o ,
    output [DATA_WIDTH-1:0]   vc_tx_data_o ,
    output [DATA_WIDTH/8-1:0] vc_tx_datap_o ,
    input vc_tx_ready_i ,
    // completer id from UCFG app
    input [15:0]              completer_id_i,
    output wire               write_data_check,
    output [31:0]             rd_data_counter,
    input [31:0]              bar_0_address,
    input [31:0]              bar_1_address
);

   // CPNX Gen3 requires TLP Adapter to close timing
   localparam DATA_WIDTH_INT = ((DEVICE_FAMILY == "LFCPNX") & (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 2)) ? (2*DATA_WIDTH) : DATA_WIDTH;

wire [DATA_WIDTH-1 : 0] vc_tx_data_o_check;
wire vc_tx_valid_o_check;
reg [DATA_WIDTH-1 : 0] vc_tx_data_o_check_d;
reg vc_tx_valid_o_check_d;
wire req_compl;
// KD 
wire [(DATA_WIDTH_INT/32)-1:0] wr_dw_en;
wire wr_en_last;
wire compl_done;

wire [2:0] req_tc;
wire req_td;
wire req_ep;
wire [1:0] req_attr;
wire [9:0] req_len;
wire [15:0] req_rid;
wire [7:0] req_tag;
wire [7:0] req_be;
wire [31:0] req_addr;
wire [DATA_WIDTH_INT-1:0] wr_data;                                               
wire wr_en;
wire wr_busy;
wire [13:0] rd_addr;
wire [3:0] rd_be;
wire [DATA_WIDTH_INT-1:0] rd_data;                                             
wire rd_en ;

reg rst_n_rx ; /* synthesis syn_preserve=1 */
reg rst_n_tx ; /* synthesis syn_preserve=1 */
reg rst_n_mem ; /* synthesis syn_preserve=1 */

  wire vc_rx_ready_int;
  wire vc_rx_valid_int;
  wire [1:0] vc_rx_sel_int;
  wire [12:0] vc_rx_cmd_data_int;
  wire vc_rx_sop_int;
  wire [DATA_WIDTH_INT-1:0] vc_rx_data_int;
  wire [DATA_WIDTH_INT/8-1:0] vc_rx_datap_int;
  wire vc_rx_eop_int;
  wire vc_rx_err_ecrc_int;
  wire [1:0] vc_rx_f_int;

  wire vc_tx_valid_int;
  wire vc_tx_eop_int;
  wire vc_tx_sop_int;
  wire [DATA_WIDTH_INT-1:0] vc_tx_data_int;
  wire [DATA_WIDTH_INT/8-1:0] vc_tx_datap_int;
  wire vc_tx_ready_int;


always @(posedge clk)
begin 
rst_n_rx <= rst_n;
rst_n_tx <= rst_n;
rst_n_mem <= rst_n;
end 

   generate
      if ((DEVICE_FAMILY == "LFCPNX") & (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 2)) begin: W_TLP_ADAPTER
         dma_rx_1_to_2_new #(
            .TLP_WIDTH(DATA_WIDTH), // TLP interface width
            .RX_TLP_DC_FIFO_DEPTH(32), // DC FIFO Depth
            .RX_TLP_DC_FIFO_REGMODE("noreg"),
            .RX_TLP_DC_FIFO_IMPL("EBR"),
            .DEVICE_FAMILY(DEVICE_FAMILY)
         ) rx_1_to_2 (
            .clk_i(clk),
            .clk_fast_i(clk_250),
            .rst_n_i(rst_n),
            .rst_fast_n_i(rst_n), // Reset of clk_fast_i
            // To TLP interface
            .rx_ready_o(vc_rx_ready_o),
            // From TLP interface
            .rx_data_i(vc_rx_data_i),
            .rx_valid_i(vc_rx_valid_i),
            .rx_datap_i(vc_rx_datap_i),
            .rx_sop_i(vc_rx_sop_i),
            .rx_eop_i(vc_rx_eop_i),
            .rx_sel_i(vc_rx_sel_i),
            .rx_cmd_data_i(vc_rx_cmd_data_i),
            .rx_err_ecrc_i(vc_rx_err_ecrc_i),
            .rx_f_i(vc_rx_f_i),
            // Module Outlet
            .rx_data_o(vc_rx_data_int),
            .rx_datap_o(vc_rx_datap_int),
            .rx_sop_o(vc_rx_sop_int),
            .rx_eop_o(vc_rx_eop_int),
            .rx_sel_o(vc_rx_sel_int),
            .rx_cmd_data_o(vc_rx_cmd_data_int),
            .rx_err_ecrc_o(vc_rx_err_ecrc_int),
            .rx_f_o(vc_rx_f_int),
            .rx_valid_o(vc_rx_valid_int),
            .rx_ready_i(vc_rx_ready_int)
         );

	 dma_tx_2_to_1_new #(
            .TLP_WIDTH(DATA_WIDTH), // TLP interface width
            .TX_TLP_DC_FIFO_DEPTH(16), // DC FIFO Depth
            .TX_TLP_DC_FIFO_REGMODE("reg"),
            .DEVICE_FAMILY(DEVICE_FAMILY),
            .TX_TLP_DC_FIFO_IMPL("EBR")
         ) tx_2_to_1 (
            .clk_i(clk),
            .clk_fast_i(clk_250),
            .rst_n_i(rst_n),
            .rst_fast_n_i(rst_n),
            // Module Inlet
            .tx_data_i(vc_tx_data_int),
            .tx_datap_i(vc_tx_datap_int),
            .tx_sop_i(vc_tx_sop_int),
            .tx_eop_i(vc_tx_eop_int),
            .tx_valid_i(vc_tx_valid_int),
            .txready_o(vc_tx_ready_int),
            // From TLP interface
            .tx_ready_i(vc_tx_ready_i),
            // To TLP interface
            .tx_data_o(vc_tx_data_o),
            .tx_valid_o(vc_tx_valid_o),
            .tx_datap_o(vc_tx_datap_o),
            .tx_sop_o(vc_tx_sop_o),
            .tx_eop_o(vc_tx_eop_o)
         );
      end
      else begin: WO_TLP_ADAPTER
         assign vc_rx_data_int = vc_rx_data_i;
         assign vc_rx_datap_int = vc_rx_datap_i;
         assign vc_rx_sop_int = vc_rx_sop_i;
         assign vc_rx_eop_int = vc_rx_eop_i;
         assign vc_rx_sel_int = vc_rx_sel_i;
         assign vc_rx_cmd_data_int = vc_rx_cmd_data_i;
         assign vc_rx_err_ecrc_int = vc_rx_err_ecrc_i;
         assign vc_rx_f_int = vc_rx_f_i;
         assign vc_rx_valid_int = vc_rx_valid_i;
         assign vc_rx_ready_o = vc_rx_ready_int;

         assign vc_tx_valid_o = vc_tx_valid_int;
         assign vc_tx_eop_o = vc_tx_eop_int;
         assign vc_tx_sop_o = vc_tx_sop_int;
         assign vc_tx_data_o = vc_tx_data_int;
         assign vc_tx_datap_o = vc_tx_datap_int;
         assign vc_tx_ready_int = vc_tx_ready_i;

      end
   endgenerate

   assign vc_tx_eop_n_o = 1'b0;

pcie_rx_engine #(
                 .DATA_WIDTH(DATA_WIDTH_INT),
		 .NUM_OF_LANES(NUM_OF_LANES)
	            )
rx_engine_inst (
                 .clk                (clk              ),
	             .rst_n              (rst_n_rx         ),
                 // rx TLP interface
                 .vc_rx_ready_o      (vc_rx_ready_int    ),
                 .vc_rx_valid_i      (vc_rx_valid_int    ),
                 .vc_rx_sel_i        (vc_rx_sel_int      ),
                 .vc_rx_cmd_data_i   (vc_rx_cmd_data_int ),
                 .vc_rx_sop_i        (vc_rx_sop_int      ),
                 .vc_rx_data_i       ( vc_rx_data_int    ),
                 .vc_rx_datap_i      (vc_rx_datap_int    ),
                 .vc_rx_eop_i        (vc_rx_eop_int      ),
                 .vc_rx_err_ecrc_i   (vc_rx_err_ecrc_int ),
                 .vc_rx_f_i          (vc_rx_f_int        ),
	             //rx TLP info for handshaking
	             .req_compl          (req_compl        ),
	             .compl_done         (compl_done       ),
		     // KD
		     .wr_dw_en           (wr_dw_en         ), // KD 
	             .wr_en_last         (wr_en_last       ), // KD
	             .req_tc             (req_tc           ),
	             .req_td             (req_td           ),
	             .req_ep             (req_ep           ),
	             .req_attr           (req_attr         ),
	             .req_len            (req_len          ),
	             .req_rid            (req_rid          ),
	             .req_tag            (req_tag          ),
	             .req_be             (req_be           ),
	             .req_addr           (req_addr         ),
	             // memory interface
	             .wr_data            (wr_data          ),
	             .wr_en              (wr_en            ),
	             .wr_busy            (wr_busy          )
	             );

pcie_tx_engine # (
    .DATA_WIDTH(DATA_WIDTH_INT),
    .NUM_OF_LANES(NUM_OF_LANES),
    .MPS_BYTES(MPS_BYTES),      // KD
    .DW_ALIGN_RAM(DW_ALIGN_RAM) // KD
	)
	tx_engine_inst (
    .clk (clk),
	.rst_n (rst_n_tx),
    // tx TLP interface
    .vc_tx_valid_o_d (vc_tx_valid_int),
    .vc_tx_eop_o_d (vc_tx_eop_int),
    .vc_tx_eop_n_o_d (), 
    .vc_tx_sop_o_d (vc_tx_sop_int),
    .vc_tx_data_o_d (vc_tx_data_int),
    // KD .vc_tx_datap_o (vc_tx_datap_o),
    .vc_tx_datap_o_d (vc_tx_datap_int),
    .vc_tx_ready_i (vc_tx_ready_int),
    .rd_data_counter (rd_data_counter),
	// rx TLP info for handshaking
	.req_compl (req_compl),
	// KD .compl_done (compl_done),
	.e2e_compl_done (compl_done),
	.req_tc (req_tc),
	.req_td (req_td),
	.req_ep (req_ep),
	.req_attr (req_attr),
	.req_len (req_len),
	.req_rid (req_rid),
	.req_tag (req_tag),
	.req_be (req_be),
	.req_addr (req_addr),
	// memory interface
	.rd_addr(rd_addr),
	.rd_be (rd_be),
	.rd_data (rd_data),
	.rd_en (rd_en),
	// completer id from UCFG app
	.completer_id (completer_id_i)
);

pcie_ep_mem # (
    .DATA_WIDTH(DATA_WIDTH_INT),
	.SERIES_PATTERN(SERIES_PATTERN),
	.NUM_PACKETS(NUM_PACKETS),
        .MEM_BYTES(MEM_BYTES),      // KD
        .DW_ALIGN_RAM(DW_ALIGN_RAM) // KD	
	)
	pcie_ep_mem_inst(
    .clk (clk),
	.rst_n (rst_n_mem),
	// write port 
	.wr_addr (req_addr[13:0]),
	.wr_be (req_be),
	.wr_data (wr_data),
	.wr_en  (wr_en),
	.wr_dw_en (wr_dw_en), // KD
	.wr_en_last (wr_en_last), // KD
	.wr_busy (wr_busy),
	.req_addr(req_addr),
	// read port 
	.vc_tx_ready(vc_tx_ready_int),
	.rd_addr(rd_addr),
	.rd_be (rd_be),
	.rd_en (rd_en),
	.rd_en_last (compl_done), // KD
	.rd_data (rd_data),	
	.write_data_check(write_data_check),
	.vc_rx_valid_i(vc_rx_valid_int),
	.bar_0_address  (bar_0_address),
	.bar_1_address  (bar_1_address)	
);
endmodule
