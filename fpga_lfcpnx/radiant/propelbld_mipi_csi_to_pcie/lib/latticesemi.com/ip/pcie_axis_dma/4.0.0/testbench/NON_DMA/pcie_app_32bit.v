
`timescale 1ps/1ps

module pcie_app_32bit #(
    parameter INTERFACE = "TLP"
)(
    input clk,
	input rst_n,
    // rx TLP interface
    output vc_rx_ready_o ,
    input vc_rx_valid_i ,
    input [1:0] vc_rx_sel_i ,
    input [12:0] vc_rx_cmd_data_i ,
    input vc_rx_sop_i ,
    input [31:0] vc_rx_data_i,
    input [3:0] vc_rx_datap_i,
    input vc_rx_eop_i ,
    input vc_rx_err_ecrc_i,
    input [1:0] vc_rx_f_i ,
	// tx TLP interface
    output vc_tx_valid_o ,
    output vc_tx_eop_o ,
    output vc_tx_eop_n_o, 
    output vc_tx_sop_o ,
    output [31:0] vc_tx_data_o ,
    output [3:0] vc_tx_datap_o ,
    input vc_tx_ready_i,
    // completer id from LMMI app
    input [15:0] completer_id_i

);
wire req_compl;
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
wire [31:0] wr_data;
wire wr_en;
wire wr_busy;
wire [13:0] rd_addr; //msanthi : Make the width uniform so that no high Z sent into RAM
wire [3:0] rd_be;
wire [31:0] rd_data;
wire rd_en ;
wire [14:0] segment;
assign segment_out = segment[6:0];


pcie_rx_engine_32bit rx_engine (
    .clk (clk),
	.rst_n (rst_n),
    // rx TLP interface
    .vc_rx_ready_o (vc_rx_ready_o) ,
    .vc_rx_valid_i (vc_rx_valid_i),
    .vc_rx_sel_i (vc_rx_sel_i),
    .vc_rx_cmd_data_i (vc_rx_cmd_data_i),
    .vc_rx_sop_i (vc_rx_sop_i),
    .vc_rx_data_i ( vc_rx_data_i),
    .vc_rx_datap_i (vc_rx_datap_i),
    .vc_rx_eop_i (vc_rx_eop_i),
    .vc_rx_err_ecrc_i (vc_rx_err_ecrc_i),
    .vc_rx_f_i (vc_rx_f_i),
	//rx TLP info for handshaking
	.req_compl (req_compl),
	.compl_done (compl_done),
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
	.wr_data (wr_data),
	.wr_en  (wr_en),
	.wr_busy (wr_busy)
	
);

pcie_tx_engine_32bit  #(
    .INTERFACE(INTERFACE)
) tx_engine
(
    .clk (clk),
	.rst_n (rst_n),
    // tx TLP interface
    .vc_tx_valid_o (vc_tx_valid_o),
    .vc_tx_eop_o (vc_tx_eop_o),
    .vc_tx_eop_n_o (vc_tx_eop_n_o), 
    .vc_tx_sop_o (vc_tx_sop_o),
    .vc_tx_data_o (vc_tx_data_o),
    .vc_tx_datap_o (vc_tx_datap_o),
    .vc_tx_ready_i (vc_tx_ready_i),
	// rx TLP info for handshaking
	.req_compl (req_compl),
	.compl_done (compl_done),
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
	.read_data_counter(read_data_counter),
    // completer id from UCFG app
	.completer_id (completer_id_i)
);


pcie_ep_mem_32bit ep_mem (
    .clk (clk),
	.rst_n (rst_n),
	// write port 
	.wr_addr (req_addr[13:0]), //msanthi : Made width the same as the req_addr wire to ensure no high Z sent to the RAM
	.wr_be (req_be),
	.wr_data (wr_data),
	.wr_en  (wr_en),
	.wr_busy (wr_busy),
	.vc_tx_ready(vc_tx_ready_i),
	.vc_rx_valid_i(vc_rx_valid_i),
	.vc_rx_cmd_data(vc_rx_cmd_data_i),
	// read port 
	.rd_addr(rd_addr),
	.rd_be (rd_be),
	.rd_data (rd_data),
	.rd_en (rd_en)
);
endmodule
