`timescale 1ps/1ps
module tlp2axi #(
	parameter DATA_WIDTH = 128
	)
   (
		input clk,
		input rst_n,
		input vc_tx_valid_i,
		input vc_tx_eop_i,
		input [DATA_WIDTH-1:0] vc_tx_data_i,
		output s0_tvalid_i,
		output s0_tlast_i, 
		output [DATA_WIDTH-1:0] s0_tdata_i,
		output [DATA_WIDTH/8 - 1:0] s0_tstrb_i, 
		output [DATA_WIDTH/8 - 1:0] s0_tkeep_i, 
		output [7:0] s0_tid_i,
		output [3:0] s0_tdest_i 
	);
	
	assign s0_tvalid_i = vc_tx_valid_i;
	assign s0_tlast_i = vc_tx_eop_i;
	assign s0_tdata_i = vc_tx_data_i;
	assign s0_tstrb_i = (DATA_WIDTH == 256) ? 32'hffffffff : ((DATA_WIDTH == 128) ? 16'hffff : 8'hff);
	assign s0_tkeep_i = (DATA_WIDTH == 256) ? 32'hffffffff : ((DATA_WIDTH == 128) ? 16'hffff : 8'hff);
	assign s0_tid_i = 8'h0;
	assign s0_tdest_i = 4'h0;
	
endmodule