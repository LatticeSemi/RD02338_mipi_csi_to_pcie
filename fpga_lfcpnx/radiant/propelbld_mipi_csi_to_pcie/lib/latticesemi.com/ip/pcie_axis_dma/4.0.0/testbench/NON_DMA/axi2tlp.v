`timescale 1ps/1ps
module axi2tlp #(
	parameter DATA_WIDTH = 128
)(
	input clk,
	input rst_n,
	input m0_tvalid_o,
	input [DATA_WIDTH-1:0] m0_tdata_o,
	input m0_tlast_o,
	input m0_tready_i,
	output [DATA_WIDTH-1:0] link0_rx_data_o,
	output link0_rx_valid_o,
	output link0_rx_sop_o,
	output link0_rx_eop_o
);
	reg m0_tvalid_o_d,m0_tlast_o_d,m0_tready_i_d;
	//assign link0_rx_sop_o = ((m0_tvalid_o==1'b1 && m0_tvalid_o_d==1'b0 && m0_tready_i==1'b1) || (m0_tready_i==1'b1 && m0_tready_i_d==1'b0 && m0_tvalid_o==1'b1)) ? 1'b1 : 1'b0;
	assign link0_rx_sop_o = (m0_tvalid_o==1'b1 && m0_tvalid_o_d==1'b0 && m0_tready_i==1'b1) ? 1'b1 : 1'b0;
    assign link0_rx_eop_o = m0_tlast_o; //Added by msanthi : To esnure the end of the TLP packet is registered by the rx engine.
    assign link0_rx_data_o = m0_tdata_o;
	assign link0_rx_valid_o = m0_tvalid_o;
	
	always @(posedge clk) begin
		if(~rst_n) begin
			m0_tvalid_o_d <= 1'b0;
			m0_tlast_o_d <= 1'b0;
			m0_tready_i_d <= 1'b0;
		end 
		else begin
			m0_tlast_o_d <= m0_tlast_o;
			m0_tvalid_o_d <= m0_tvalid_o;
			m0_tready_i_d <= m0_tready_i;
		end 
	end 
endmodule