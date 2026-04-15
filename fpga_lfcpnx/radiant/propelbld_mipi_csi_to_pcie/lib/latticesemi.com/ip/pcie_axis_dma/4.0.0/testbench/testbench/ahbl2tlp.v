`timescale 1ps/1ps

module ahbl2tlp #(
	parameter DATA_WIDTH = 128
)(
	input clk,
	input rst_n,
	input [1:0] m0_w_htrans_o,
	input [DATA_WIDTH-1:0] m0_w_hwdata_o,
	input m0_w_hwrite_o,
	input m0_w_hready_i,
	input [31:0]m0_w_haddr_o,
	output [DATA_WIDTH-1:0] link0_rx_data_o,
	output reg link0_rx_valid_o,
	output link0_rx_sop_o,
	output link0_rx_eop_o
);
	wire [7:0] addr_inc;
	wire write_sop;
	reg read_sop;
	wire [31:0] last_data;
	reg [31:0]m0_w_haddr_o_d;
	assign addr_inc = (DATA_WIDTH/8);
	reg [1:0] m0_w_htrans_o_d;
	reg [1:0] m0_w_htrans_o_2d;
	reg m0_w_hready_i_d;
	
	assign link0_rx_eop_o = (m0_w_htrans_o_d == 2'b11 && ((m0_w_htrans_o == 2'b10) || (m0_w_htrans_o == 2'b00))) ? 1'b1 : 1'b0;
	assign link0_rx_data_o = m0_w_hwdata_o;
	assign last_data = (m0_w_haddr_o_d != m0_w_haddr_o) ? m0_w_haddr_o_d : last_data;
	assign write_sop = (((last_data == 32'hffff_0000)) & (m0_w_hready_i == 1'b1)) ? 1'b1 : 1'b0;
	assign link0_rx_sop_o = (write_sop || read_sop);
	
	always @(posedge clk) begin
		if(~rst_n) begin
			m0_w_htrans_o_d <= 1'b0;
			read_sop <= 1'b0;
			m0_w_hready_i_d <= 1'b0;
			link0_rx_valid_o <= 1'b0;
			m0_w_haddr_o_d <= 32'b0;
		end 
		begin
			m0_w_htrans_o_d  <= m0_w_htrans_o;			
			m0_w_htrans_o_2d  <= m0_w_htrans_o_d;			
			m0_w_hready_i_d  <= m0_w_hready_i;	
			m0_w_haddr_o_d  <= m0_w_haddr_o;	
			link0_rx_valid_o <= m0_w_htrans_o[1];	
			
			if((m0_w_haddr_o == 32'hffff_1000) && (m0_w_htrans_o == 2'd2)) begin
				read_sop <= 1'b1;
			end 
			else begin
				read_sop <= 1'b0;
			end 
		end 
	end 

endmodule 