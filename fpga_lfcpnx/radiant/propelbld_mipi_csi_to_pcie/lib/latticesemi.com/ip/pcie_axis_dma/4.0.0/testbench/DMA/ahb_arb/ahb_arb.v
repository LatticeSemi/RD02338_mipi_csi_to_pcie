// This module is selecting the slaves on the basis of address 
`timescale 1ps / 1ps


//************************************
//            Module Definition      *
//************************************

module ahb_arb #(
    parameter S0_BASE = 32'h0000,  // Slave 0 base address
	parameter S1_BASE = 32'h1000,  // Slave 1 base address
	parameter S2_BASE = 32'h3000,   // Slave 2 base address
	parameter NO_LANES = 4
)
(
   // AHB interface for master (pcie interface)
    input          					ahbl_hclk_i,
	input          					ahbl_hresetn_i, 
	input 		[31:0]   			ahbl_m_haddr_i,  
	input 		[2:0]    			ahbl_m_hburst_i,  
	input 		[2:0]    			ahbl_m_hsize_i, 
	input 		[1:0]    			ahbl_m_htrans_i,  
	input          					ahbl_m_hwrite_i, 
	input 		[NO_LANES*64-1:0]   ahbl_m_hwdata_i, 
	output reg        				ahbl_m_hready_o, 
	output reg        				ahbl_m_hresp_o,
	output reg	[NO_LANES*64-1:0] 	ahbl_m_hrdata_o,  
	
	// AHB interface for slave 0
	output reg        				ahbl_s0_hsel_o,
	output  	[31:0] 				ahbl_s0_haddr_o,  
	output  	[2:0]  				ahbl_s0_hburst_o,   
	output  	[2:0]  				ahbl_s0_hsize_o, 
	output reg  [1:0]  				ahbl_s0_htrans_o,  
	output reg        				ahbl_s0_hwrite_o, 
	output  	[31:0] 				ahbl_s0_hwdata_o,
	input 		        			ahbl_s0_hready_i,
	input 		        			ahbl_s0_hresp_i,
	input 		[31:0]  			ahbl_s0_hrdata_i,
	
	// AHB interface for slave 1
	output reg         				ahbl_s1_hsel_o,
	output  	[31:0]  			ahbl_s1_haddr_o,  
	output  	[2:0]   			ahbl_s1_hburst_o,   
	output  	[2:0]   			ahbl_s1_hsize_o, 
	output reg 	[1:0] 			    ahbl_s1_htrans_o,  
	output reg         				ahbl_s1_hwrite_o, 
	output  	[NO_LANES*64-1:0]   ahbl_s1_hwdata_o,
	input          					ahbl_s1_hready_i,
	input          					ahbl_s1_hresp_i,
	input 		[NO_LANES*64-1:0]   ahbl_s1_hrdata_i,
	
	//AHB interface for slave 2
	output reg         				ahbl_s2_hsel_o,
	output  	[31:0]  			ahbl_s2_haddr_o,  
	output  	[2:0]   			ahbl_s2_hburst_o,   
	output  	[2:0]   			ahbl_s2_hsize_o, 
	output reg 	[1:0]   			ahbl_s2_htrans_o,  
	output reg          			ahbl_s2_hwrite_o, 
	output  	[NO_LANES*64-1:0]  	ahbl_s2_hwdata_o,
	input          					ahbl_s2_hready_i,
	input          					ahbl_s2_hresp_i,
	input 		[NO_LANES*64-1:0]   ahbl_s2_hrdata_i
);
reg s0_sel;
reg s1_sel;
reg s2_sel;
/*wire ahbl_m_hready_o_bri;
wire ahbl_m_hresp_o_bri;
wire [255:0] ahbl_m_hrdata_o_bri;
wire ahbl_s1_hsel_o_bri;
wire [1:0]  ahbl_s1_htrans_o_bri;
wire ahbl_s1_hwrite_o_bri;*/


//**************************************************************************
//     Selecting slave on the basis of address received from AHB master    *
//**************************************************************************
//
always @(*)
begin 
	s0_sel <= (ahbl_m_haddr_i[31:12] >= S0_BASE[31:12]) ? 1'b1 : 1'b0;
    s1_sel <= ((ahbl_m_haddr_i[31:12] >= S1_BASE[31:12])&(ahbl_m_haddr_i[31:12] < S2_BASE[31:12])) ? 1'b1 : 1'b0;
	s2_sel <= (ahbl_m_haddr_i[31:12] >= S2_BASE[31:12]) ? 1'b1 : 1'b0;
end 




//
//**************************************************************************
//             Muxing data on the basis of selected slave                  *
//**************************************************************************
assign ahbl_s2_hwdata_o           = ahbl_m_hwdata_i;
assign ahbl_s2_haddr_o            = ahbl_m_haddr_i;
assign ahbl_s2_hburst_o           = ahbl_m_hburst_i;
assign ahbl_s2_hsize_o            = ahbl_m_hsize_i;
assign ahbl_s1_hwdata_o           = ahbl_m_hwdata_i;
assign ahbl_s1_haddr_o            = ahbl_m_haddr_i;
assign ahbl_s1_hburst_o           = ahbl_m_hburst_i;
assign ahbl_s1_hsize_o            = ahbl_m_hsize_i;
assign ahbl_s0_hwdata_o           = ahbl_m_hwdata_i;
assign ahbl_s0_haddr_o            = ahbl_m_haddr_i;
assign ahbl_s0_hburst_o           = ahbl_m_hburst_i;
assign ahbl_s0_hsize_o            = ahbl_m_hsize_i;


always @(*)
begin 
    casex ({s0_sel,s1_sel,s2_sel})
	3'bxx1: // S2
	begin 
	    ahbl_s2_hsel_o             <= 1'b1;
		ahbl_s2_htrans_o           <= ahbl_m_htrans_i;
		ahbl_s2_hwrite_o           <= ahbl_m_hwrite_i;	
		
		ahbl_s0_hsel_o             <= 1'b0;
		ahbl_s0_htrans_o           <= 'b0;
		ahbl_s0_hwrite_o           <= 'b0;	
		
		ahbl_s1_hsel_o             <= 1'b0;
		ahbl_s1_htrans_o           <= 'b0;
		ahbl_s1_hwrite_o           <= 'b0;
		
	end 
	3'bx10: // S1
	begin 
	    ahbl_s1_hsel_o             <= 1'b1;
		ahbl_s1_htrans_o           <= ahbl_m_htrans_i;
		ahbl_s1_hwrite_o           <= ahbl_m_hwrite_i;
		
		ahbl_s0_hsel_o             <= 1'b0;
		ahbl_s0_htrans_o           <= 'b0;
		ahbl_s0_hwrite_o           <= 'b0;
		ahbl_s2_hsel_o             <= 1'b0;
		ahbl_s2_htrans_o           <= 'b0;
		ahbl_s2_hwrite_o           <= 'b0;
	end 
	3'b100: //S0
	begin 
	    ahbl_s0_hsel_o             <= 1'b1;
		ahbl_s0_htrans_o           <= ahbl_m_htrans_i;
		ahbl_s0_hwrite_o           <= ahbl_m_hwrite_i ;
		
		ahbl_s1_hsel_o             <= 1'b0;
		ahbl_s1_htrans_o           <= 'b0;
		ahbl_s1_hwrite_o           <= 'b0;
		
		ahbl_s2_hsel_o             <= 1'b0;
		ahbl_s2_htrans_o           <= 'b0;
		ahbl_s2_hwrite_o           <= 'b0;
		
	end 
	default: 
	begin 
	    ahbl_s1_hsel_o             <= 'b0;
		ahbl_s1_htrans_o           <= 'b0;
		ahbl_s1_hwrite_o           <= 'b0;
		
		ahbl_s0_hsel_o             <= 'b0;
		ahbl_s0_htrans_o           <= 'b0;
		ahbl_s0_hwrite_o           <= 'b0;
		
		ahbl_s2_hsel_o             <= 'b0;
		ahbl_s2_htrans_o           <= 'b0;
		ahbl_s2_hwrite_o           <= 'b0;
		
	end
	endcase
end 

reg s0_sel_d;
reg s1_sel_d;
reg s2_sel_d;


always @(*)
begin 
    casex ({s0_sel_d,s1_sel_d,s2_sel_d})
	    3'bxx1: // S2
	    begin 
		    ahbl_m_hready_o            <= ahbl_s2_hready_i;
		    ahbl_m_hresp_o             <= ahbl_s2_hresp_i;
		    ahbl_m_hrdata_o            <= ahbl_s2_hrdata_i;
		end 
	    3'bx10: // S1
	    begin 
		    ahbl_m_hready_o            <= ahbl_s1_hready_i;
		    ahbl_m_hresp_o             <= ahbl_s1_hresp_i;
		    ahbl_m_hrdata_o            <= ahbl_s1_hrdata_i;
		end 
	    3'b100: //S0
	    begin 
		    ahbl_m_hready_o            <= ahbl_s0_hready_i;
		    ahbl_m_hresp_o             <= ahbl_s0_hresp_i;
		    ahbl_m_hrdata_o            <= {224'b0,ahbl_s0_hrdata_i};
		end 
	    default:
	    begin 
		    ahbl_m_hready_o            <= 'b0;
		       ahbl_m_hresp_o             <= 'b0;
		       ahbl_m_hrdata_o            <= 'b0;
		end 
	endcase
end 

always @(posedge ahbl_hclk_i or negedge ahbl_hresetn_i)
begin 
    if (!ahbl_hresetn_i)
	begin 
	    s0_sel_d            <= 1'b0;
	    s1_sel_d            <= 1'b0;
	    s2_sel_d            <= 1'b0;
	end 
	else 
	begin
	    s0_sel_d            <= s0_sel;
	    s1_sel_d            <= s1_sel;
	    s2_sel_d            <= s2_sel;
	end 
end 
endmodule