module tlp2ahbl #(
	parameter DATA_WIDTH = 128,
	parameter CSR_ADDRESS = 13'h18a4 
)
(
	input clk,
	input rst_n,
	output [31:0] s0_haddr_i,
    output [2:0] s0_hburst_i,
    output s0_hmastlock_i,
    output [3:0] s0_hprot_i, 
    output [2:0] s0_hsize_i, 
    output reg [1:0] s0_htrans_i, 
    output s0_hwrite_i,
    output s0_hreadyin_i,
    output s0_hsel_i,
    output [DATA_WIDTH-1:0] s0_hwdata_i,
	input vc_tx_valid_i,
	input vc_tx_eop_i,
	input vc_tx_sop_i,
	input [DATA_WIDTH-1:0] vc_tx_data_i,
	input [31:0] rd_data_counter
);
	wire HSIZE;
	reg [31:0]rd_data_counter_d;
	reg [DATA_WIDTH-1:0] vc_tx_data_i_d;	
	reg [31:0]rd_data_counter_2d;
	reg [DATA_WIDTH-1:0] vc_tx_data_i_2d;
	reg vc_tx_sop_i_d;
	reg vc_tx_eop_i_d;
	reg sop_detected;
	assign HSIZE = (DATA_WIDTH == 256) ? 5 : ((DATA_WIDTH == 128) ? 4 : 3);
	assign s0_hwdata_i = vc_tx_data_i_2d;
	assign s0_haddr_i = {CSR_ADDRESS,3'b011,4'h0,rd_data_counter_2d[9:0],2'b00};
	assign s0_hsel_i = 1'b1;
	assign s0_hreadyin_i = 1'b1;
	assign s0_hwrite_i = 1'b1;
	assign s0_hburst_i = 1'b1;
	assign s0_hsize_i = HSIZE;
	assign s0_hmastlock_i = 1'b0;
	assign s0_hprot_i = 4'd3;
		
		
	always @(posedge clk) begin
		if(~rst_n) begin
			rd_data_counter_d <= 32'h0;
			vc_tx_data_i_d <= {(DATA_WIDTH){1'b0}};
			sop_detected <= 1'b0;
			s0_htrans_i <= 2'b0;
		end 
		else begin
			rd_data_counter_d <= rd_data_counter;
			vc_tx_data_i_d <= vc_tx_data_i;			
			rd_data_counter_2d <= rd_data_counter_d;
			vc_tx_data_i_2d <= vc_tx_data_i_d;
			vc_tx_sop_i_d <= vc_tx_sop_i;
			vc_tx_eop_i_d <= vc_tx_eop_i;
			if(vc_tx_sop_i_d == 1'b0 && vc_tx_sop_i == 1'b1) begin
				sop_detected <= 1'b1;
				s0_htrans_i <= 2'd2;
			end 
			else if(sop_detected==1'b1 && vc_tx_eop_i_d == 1'b1 && vc_tx_eop_i == 1'b0) begin
				s0_htrans_i <= 2'd0;
				sop_detected <= 1'b0;
			end 
			else if(sop_detected == 1'b1) begin
				s0_htrans_i <= 2'd3;
				sop_detected <= sop_detected;
			end 
			else begin
				sop_detected <= sop_detected;
			end 
		end 
	end 

endmodule 
