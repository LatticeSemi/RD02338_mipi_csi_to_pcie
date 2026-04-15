
`timescale 1ps/1ps


module tb_dma_application_layer  #(
    parameter SIM = 1,
	parameter NO_LANES = 4,
	parameter PCIE_CSR_BASE_ADDR = 32'hC520_0000
)
(
// reset interface
input                         perst_n_i,              // Resets both PHY and LL core //D17
input                         usr_rst_n,
// APB interface
output reg                    clock_flag,
input                         clk_125,
output                        dma_done_o,
output 						  sys_clk,
output 						  clk_usr_div2,
output 						  clk_ps_90,   
output 						  c_apb_pclk,
output 						  c_apb_preset_n,
output 						  c_apb_psel,
output 						  c_apb_penable,
output 						  c_apb_pwrite,
output 						  m_w_hready,
output 						  m_w_hresp,
output 						  m_r_hresp,
output 						  m_r_hready,
input 						  c_apb_pready,
input 						  m_w_hwrite,
input 						  m_r_hwrite,
input 						  c_apb_pslverr,
output        				 [31:0] c_apb_paddr,
output        				 [31:0] c_apb_pwdata,
input        				 [31:0] c_apb_prdata,
output        				 [NO_LANES*64 - 1:0]m_w_hrdata,
output        				 [NO_LANES*64 - 1:0]m_r_hrdata,
input         				 [NO_LANES*64 - 1:0]m_w_hwdata,
input         				 [NO_LANES*64 - 1:0]m_r_hwdata,
input         				 [31:0]	m_w_haddr,
input         				 [31:0]	m_r_haddr,
input 						 [2:0]	m_w_hburst,
input 						 [2:0]	m_r_hburst,
input 						 [2:0]	m_w_hsize,
input 						 [2:0]	m_r_hsize,
input 						 [1:0]	m_w_htrans,
input 						 [1:0]	m_r_htrans,
input 						 		clk_usr_o,
input 						 [1:0]	gen_no,
input 						 [2:0]	lane_no,
output							    rst_usr_n_i

);

wire  								checker_flag			  ;
wire        [NO_LANES*64-1:0]       m_w_hrdata_i        	  ;
wire                          		m_w_hready_i        	  ;
wire                          		m_w_hresp_i         	  ;
wire        [NO_LANES*64-1:0]       m_r_hrdata_i        	  ;
wire                          		m_r_hready_i        	  ;
wire                          		m_r_hresp_i         	  ;
wire        [31:0]            		c_apb_paddr_i       	  ;
wire                          		c_apb_psel_i        	  ;
wire                          		c_apb_penable_i     	  ;
wire                          		c_apb_pwrite_i      	  ;
wire        [31:0]            		c_apb_pwdata_i      	  ;
wire        [31:0]            		c_apb_prdata_o      	  ;
wire                          		c_apb_pready_o      	  ;
wire                          		c_apb_pslverr_o     	  ;
wire        [31:0]            		m_w_haddr_o         	  ;
wire        [2:0]             		m_w_hburst_o        	  ;
wire        [2:0]             		m_w_hsize_o         	  ;
wire        [1:0]             		m_w_htrans_o        	  ;
wire        [NO_LANES*64-1:0]       m_w_hwdata_o        	  ;
wire                          		m_w_hwrite_o        	  ;
wire        [31:0]            		m_r_haddr_o         	  ;
wire        [2:0]             		m_r_hburst_o        	  ;
wire                          		m_r_hmastlock_o     	  ;
wire        [3:0]             		m_r_hprot_o         	  ;
wire        [2:0]             		m_r_hsize_o         	  ;
wire        [1:0]             		m_r_htrans_o        	  ;
wire        [NO_LANES*64-1:0]       m_r_hwdata_o        	  ;
wire                          		m_r_hwrite_o        	  ;
wire        [31:0]            		m_w_s0_haddr_o      	  ;
wire        [2:0]             		m_w_s0_hburst_o     	  ;
wire        [2:0]             		m_w_s0_hsize_o      	  ;
wire        [1:0]             		m_w_s0_htrans_o     	  ;
wire        [31:0]            		m_w_s0_hwdata_o     	  ;
wire                          		m_w_s0_hwrite_o     	  ;
wire        [31:0]            		m_r_s0_haddr_o      	  ;
wire        [2:0]             		m_r_s0_hburst_o     	  ;
wire        [2:0]             		m_r_s0_hsize_o      	  ;
wire        [1:0]             		m_r_s0_htrans_o     	  ;
wire        [31:0]            		m_r_s0_hwdata_o     	  ;
wire                          		m_r_s0_hwrite_o     	  ;
wire        [31:0]            		m_w_s0_hrdata_i     	  ;
wire                          		m_w_s0_hready_i     	  ;
wire                          		m_w_s0_hresp_i      	  ;
wire        [31:0]            		m_r_s0_hrdata_i     	  ;
wire                          		m_r_s0_hready_i     	  ;
wire                          		m_r_s0_hresp_i      	  ;
															  
wire        [31:0]            		m_w_s1_haddr_o      	  ;
wire        [2:0]             		m_w_s1_hburst_o     	  ;
wire        [2:0]             		m_w_s1_hsize_o      	  ;
wire        [1:0]             		m_w_s1_htrans_o     	  ;
wire        [NO_LANES*64-1:0]       m_w_s1_hwdata_o     	  ;
wire                          		m_w_s1_hwrite_o     	  ;
wire        [31:0]            		m_r_s1_haddr_o      	  ;
wire        [2:0]             		m_r_s1_hburst_o     	  ;
wire        [2:0]             		m_r_s1_hsize_o      	  ;
wire        [1:0]             		m_r_s1_htrans_o     	  ;
wire        [NO_LANES*64-1:0]       m_r_s1_hwdata_o     	  ;
wire                          		m_r_s1_hwrite_o     	  ;
wire        [NO_LANES*64-1:0]       m_w_s1_hrdata_i     	  ;
wire                          		m_w_s1_hready_i     	  ;
wire                          		m_w_s1_hresp_i      	  ;
wire        [NO_LANES*64-1:0]       m_r_s1_hrdata_i     	  ;
	                                                          
	                                                          
wire                          		m_r_s1_hready_i     	  ;
wire                          		m_r_s1_hresp_i      	  ;
															  
wire        [31:0]            		m_w_s2_haddr_o      	  ;
wire        [2:0]             		m_w_s2_hburst_o     	  ;
wire        [2:0]             		m_w_s2_hsize_o      	  ;
wire        [1:0]             		m_w_s2_htrans_o     	  ;
wire        [NO_LANES*64-1:0]       m_w_s2_hwdata_o     	  ;
wire                          		m_w_s2_hwrite_o     	  ;
wire        [31:0]            		m_r_s2_haddr_o      	  ;
wire        [2:0]             		m_r_s2_hburst_o     	  ;
wire        [2:0]             		m_r_s2_hsize_o      	  ;
wire        [1:0]             		m_r_s2_htrans_o     	  ;
wire        [NO_LANES*64-1:0]       m_r_s2_hwdata_o     	  ;
wire                          		m_r_s2_hwrite_o     	  ;
wire        [NO_LANES*64-1:0]       m_w_s2_hrdata_i     	  ;
wire                          		m_w_s2_hready_i     	  ;
wire                          		m_w_s2_hresp_i      	  ;
wire        [NO_LANES*64-1:0]       m_r_s2_hrdata_i     	  ;
wire                          		m_r_s2_hready_i     	  ;
wire                          		m_r_s2_hresp_i      	  ;
wire 		[1:0]					data_type				  ;
wire 								DMA_read_checker		  ;
wire 								DMA_read_checker_valid	  ;
wire 		[31:0] 					DMA_read_size			  ;
                                                              
wire 								DMA_read_size_valid		  ;
                                                              
reg 								c_apb_preset_n_i		  ;
wire 								config_done				  ;
reg 		[31:0] 					counter 				  ;
wire 								rst_n					  ;
wire 								dma_abor_status			  ;
wire 								dma_done_status			  ;
wire 								dma_err_status 			  ;
wire 		[31:0] 					fixed_pattern			  ;
wire 								dma_done				  ;
wire 								start_dma				  ;
wire 		[31:0] 					DMA_read_byte_count		  ;
wire 		[31:0] 					DMA_write_size			  ;
wire 								DMA_write_size_valid	  ;
reg 								c_apb_pclk_i			  ;
                                                              
wire 								wr_done					  ;
wire 								wr_en					  ;
wire 								rd_done					  ;
wire 								rd_en					  ;
wire 		[31:0] 					register_address		  ;
wire 		[31:0] 					wr_data					  ;
wire 								msi_assert				  ;
wire 								clk_usr_div2_i			  ;
wire 								sys_clk_i				  ;
wire 								pll_lock_ip				  ;
wire 								clk_ps_90_i				  ;
reg  								clk_250					  ;
wire 								clk_250_90				  ;
reg  								clk_62_5				  ;
wire 								clk_62_5_90				  ;
reg  								clk_31_25				  ;
wire 								clk_125_90				  ;
reg 								rstn_meta				  ;
reg									rstn_clk2				  ;
reg 								clock_flag_apb			  ;
reg 		[31:0] 					counter_apb				  ;
wire 		[7:0] 					num_descr;
wire 		[31:0] 					DMA_read_byte_chunk;
wire 								clear_read_byte_chunk_reg ;
wire 								READ_DATA_CHECK			  ;
 
wire 								rst_usr_n				  ;
wire 		[2:0]				    type_of_testcase		  ;
wire 		[31:0] 					sys_mem_wr_addr			  ;
wire 		[31:0] 					sys_mem_rd_addr			  ;

assign rst_usr_n = rst_usr_n_i;
assign rst_usr_n_i = perst_n_i&pll_lock_ip;
parameter DATA_WIDTH = (NO_LANES == 1) ? 64 : 128;


assign pll_lock_ip 	  = 	usr_rst_n;
assign c_apb_preset_n = 	c_apb_preset_n_i;



debounce # (
    . SIM   (SIM)
)
debounce_inst 
(
    .clk      (clk_125),
	.pb_in_n  (usr_rst_n),
	.pb_out   (rst_n)
);

// 62.5 MHz Clock
initial
begin
	clk_62_5 = 0;
	forever
	begin
		#(8000);
		clk_62_5 = ~clk_62_5;
	end
end
	
// 31.25 MHz Clock 
initial
begin
	clk_31_25 = 0;
	forever
	begin
		#(16000);
		clk_31_25 = ~clk_31_25;
	end
end

// 250 MHz Clock 
initial
begin
	clk_250 = 0;
	forever
	begin
		#(2000);
		clk_250 = ~clk_250;
	end
end	

	
assign #4000 clk_62_5_90 = 		clk_62_5;	// 90 degree shift		
assign #2000 clk_125_90  =  	clk_125;  	// 90 degree shift
assign #1000 clk_250_90  =  	clk_250;  	// 90 degree shift

	
assign sys_clk_i   		 = 		(usr_rst_n == 1'b1)?((gen_no == 2) ?  clk_250 : ((gen_no == 1) ? clk_125 : clk_62_5)) : 0; 
assign clk_ps_90_i 		 = 		(usr_rst_n == 1'b1)?((gen_no == 2) ?  clk_250_90 : ((gen_no == 1) ? clk_125_90 : clk_62_5_90)) : 0; 
assign clk_usr_div2_i    = 		(usr_rst_n == 1'b1)?((gen_no == 2) ?  clk_125 : ((gen_no == 1) ? clk_62_5 : clk_31_25)) : 0; 



always @(posedge clk_usr_div2_i or negedge rst_n)
begin 
	if (~rst_n) 
    begin 
		rstn_meta   <= 1'b0;
		rstn_clk2   <= 1'b0;
	end 
	else 
	begin 
		rstn_meta   <= 1'b1;
		rstn_clk2   <=rstn_meta;
	end 
end 

// 50Mhz Clock 
initial
begin
	c_apb_pclk_i = 0;
	forever
	begin
		#(10000);
		c_apb_pclk_i = ~c_apb_pclk_i;
	end
end	
	



GSR GSR_inst (.GSR_N (perst_n_i),.CLK(clk_125));


assign c_apb_pclk 	  	= 		c_apb_pclk_i;
assign c_apb_psel 	  	= 		c_apb_psel_i;
assign c_apb_penable  	= 		c_apb_penable_i;
assign c_apb_pwrite   	= 		c_apb_pwrite_i;
assign c_apb_paddr	  	=	    c_apb_paddr_i;
assign c_apb_pwdata   	=		c_apb_pwdata_i;
assign c_apb_prdata_o 	= 		c_apb_prdata;
assign c_apb_pready_o   = 		c_apb_pready;
assign c_apb_pslverr_o  =		c_apb_pslverr;
assign m_w_hready 		=		m_w_hready_i;
assign m_w_hresp 		= 		m_w_hresp_i;
assign m_r_hresp 		= 		m_r_hresp_i;
assign m_w_hrdata 		= 		m_w_hrdata_i;
assign m_r_hrdata 		= 		m_r_hrdata_i;
assign m_w_haddr_o 		= 		m_w_haddr;
assign m_r_haddr_o 		= 		m_r_haddr;
assign m_w_hburst_o 	= 		m_w_hburst;
assign m_r_hburst_o 	= 		m_r_hburst;
assign m_w_hsize_o 		= 		m_w_hsize;
assign m_r_hsize_o 		= 		m_r_hsize;
assign m_w_htrans_o 	= 		m_w_htrans;
assign m_r_htrans_o 	= 		m_r_htrans;
assign m_w_hwrite_o 	= 		m_w_hwrite;
assign m_r_hwrite_o 	= 		m_r_hwrite;
assign m_w_hwdata_o 	= 		m_w_hwdata;
assign m_r_hwdata_o 	= 		m_r_hwdata;
assign m_r_hready 		=	    m_r_hready_i;
assign sys_clk 			= 		sys_clk_i;	
assign clk_usr_div2 	= 		clk_usr_div2_i;
assign clk_ps_90  		= 		clk_ps_90_i;
assign sys_mem_wr_addr  = 		m_w_s1_haddr_o - 32'h00001000;
assign sys_mem_rd_addr  = 		m_r_s1_haddr_o - 32'h00001000;



ahb_arb #(  
	.NO_LANES(NO_LANES)
)
ahb_arb_writing_port (
    .ahbl_hclk_i           (clk_usr_div2_i),
	.ahbl_hresetn_i        (rstn_clk2),
	.ahbl_m_haddr_i        (m_w_haddr_o),
	.ahbl_m_hburst_i       (m_w_hburst_o),
	.ahbl_m_hsize_i        (m_w_hsize_o),
	.ahbl_m_htrans_i       (m_w_htrans_o),
	.ahbl_m_hwrite_i       (m_w_hwrite_o),
	.ahbl_m_hwdata_i       (m_w_hwdata_o),
	.ahbl_m_hready_o       (m_w_hready_i),
	.ahbl_m_hresp_o        (m_w_hresp_i),
	.ahbl_m_hrdata_o       (m_w_hrdata_i),
	
	// AHB interface for slave 0
	.ahbl_s0_hsel_o        (m_w_ahbl_s0_hsel_o),
	.ahbl_s0_haddr_o       (m_w_s0_haddr_o),
	.ahbl_s0_hburst_o      (m_w_s0_hburst_o),
	.ahbl_s0_hsize_o       (m_w_s0_hsize_o),
	.ahbl_s0_htrans_o      (m_w_s0_htrans_o),
	.ahbl_s0_hwrite_o      (m_w_s0_hwrite_o),
	.ahbl_s0_hwdata_o      (m_w_s0_hwdata_o),
	.ahbl_s0_hready_i      (m_w_s0_hready_i),
	.ahbl_s0_hresp_i       (m_w_s0_hresp_i),
	.ahbl_s0_hrdata_i      (m_w_s0_hrdata_i),
	
	// AHB interface for slave 1
	.ahbl_s1_hsel_o        (m_w_ahbl_s1_hsel_o),
	.ahbl_s1_haddr_o       (m_w_s1_haddr_o),
	.ahbl_s1_hburst_o      (m_w_s1_hburst_o),
	.ahbl_s1_hsize_o       (m_w_s1_hsize_o),
	.ahbl_s1_htrans_o      (m_w_s1_htrans_o),
	.ahbl_s1_hwrite_o      (m_w_s1_hwrite_o),
	.ahbl_s1_hwdata_o      (m_w_s1_hwdata_o),
	.ahbl_s1_hready_i      (m_w_s1_hready_i),
	.ahbl_s1_hresp_i       (m_w_s1_hresp_i),
	.ahbl_s1_hrdata_i      (m_w_s1_hrdata_i),
	
	// AHB interface for slave 2
	.ahbl_s2_hsel_o        (m_w_ahbl_s2_hsel_o),
	.ahbl_s2_haddr_o       (m_w_s2_haddr_o),
	.ahbl_s2_hburst_o      (m_w_s2_hburst_o),
	.ahbl_s2_hsize_o       (m_w_s2_hsize_o),
	.ahbl_s2_htrans_o      (m_w_s2_htrans_o),
	.ahbl_s2_hwrite_o      (m_w_s2_hwrite_o),
	.ahbl_s2_hwdata_o      (m_w_s2_hwdata_o),
	.ahbl_s2_hready_i      (m_w_s2_hready_i),
	.ahbl_s2_hresp_i       (m_w_s2_hresp_i),
	.ahbl_s2_hrdata_i      (m_w_s2_hrdata_i)
);

ahb_arb #(  
	.NO_LANES(NO_LANES)
) ahb_arb_reading_port (
    .ahbl_hclk_i           (clk_usr_div2_i),
	.ahbl_hresetn_i        (rstn_clk2),
	.ahbl_m_haddr_i        (m_r_haddr_o[31:0]),
	.ahbl_m_hburst_i       (m_r_hburst_o[2:0]),
	.ahbl_m_hsize_i        (m_r_hsize_o[2:0]),
	.ahbl_m_htrans_i       (m_r_htrans_o[1:0]),
	.ahbl_m_hwrite_i       (m_r_hwrite_o),
	.ahbl_m_hwdata_i       (m_r_hwdata_o),
	.ahbl_m_hready_o       (m_r_hready_i),
	.ahbl_m_hresp_o        (m_r_hresp_i),
	.ahbl_m_hrdata_o       (m_r_hrdata_i),
	
	// AHB interface for slave 0
	.ahbl_s0_hsel_o        (m_r_ahbl_s0_hsel_o),
	.ahbl_s0_haddr_o       (m_r_s0_haddr_o),
	.ahbl_s0_hburst_o      (m_r_s0_hburst_o),
	.ahbl_s0_hsize_o       (m_r_s0_hsize_o),
	.ahbl_s0_htrans_o      (m_r_s0_htrans_o),
	.ahbl_s0_hwrite_o      (m_r_s0_hwrite_o),
	.ahbl_s0_hwdata_o      (m_r_s0_hwdata_o),
	.ahbl_s0_hready_i      (m_r_s0_hready_i),
	.ahbl_s0_hresp_i       (m_r_s0_hresp_i),
	.ahbl_s0_hrdata_i      (m_r_s0_hrdata_i),
	
	// AHB interface for slave 1
	.ahbl_s1_hsel_o        (m_r_ahbl_s1_hsel_o),
	.ahbl_s1_haddr_o       (m_r_s1_haddr_o[31:0]),
	.ahbl_s1_hburst_o      (m_r_s1_hburst_o[2:0]),
	.ahbl_s1_hsize_o       (m_r_s1_hsize_o[2:0]),
	.ahbl_s1_htrans_o      (m_r_s1_htrans_o[1:0]),
	.ahbl_s1_hwrite_o      (m_r_s1_hwrite_o),
	.ahbl_s1_hwdata_o      (m_r_s1_hwdata_o),
	.ahbl_s1_hready_i      (m_r_s1_hready_i),
	.ahbl_s1_hresp_i       (m_r_s1_hresp_i),
	.ahbl_s1_hrdata_i      (m_r_s1_hrdata_i),
	
	// AHB interface for slave 2
	.ahbl_s2_hsel_o        (m_r_ahbl_s2_hsel_o),
	.ahbl_s2_haddr_o       (m_r_s2_haddr_o[31:0]),
	.ahbl_s2_hburst_o      (m_r_s2_hburst_o[2:0]),
	.ahbl_s2_hsize_o       (m_r_s2_hsize_o[2:0]),
	.ahbl_s2_htrans_o      (m_r_s2_htrans_o[1:0]),
	.ahbl_s2_hwrite_o      (m_r_s2_hwrite_o),
	.ahbl_s2_hwdata_o      (m_r_s2_hwdata_o),
	.ahbl_s2_hready_i      (m_r_s2_hready_i),
	.ahbl_s2_hresp_i       (m_r_s2_hresp_i),
	.ahbl_s2_hrdata_i      (m_r_s2_hrdata_i)
);


register_space #(
	.PCIE_CSR_BASE_ADDR(PCIE_CSR_BASE_ADDR)
)
 reg_space_inst (
    .ahbl_w_hclk_i      		  (clk_usr_div2_i),
	.ahbl_w_hresetn_i   		  (rstn_clk2),
	.ahbl_w_hsel_i      		  (m_w_ahbl_s0_hsel_o),
	.ahbl_w_haddr_i     		  (m_w_s0_haddr_o),
	.ahbl_w_hburst_i    		  (m_w_s0_hburst_o),
	.ahbl_w_hsize_i     		  (m_w_s0_hsize_o),
	.ahbl_w_htrans_i    		  (m_w_s0_htrans_o),
	.ahbl_w_hwrite_i    		  (m_w_s0_hwrite_o),
	.ahbl_w_hwdata_i    		  (m_w_s0_hwdata_o),
	.ahbl_w_hready_o    		  (m_w_s0_hready_i),
	.ahbl_w_hresp_o     		  (m_w_s0_hresp_i),
	.ahbl_w_hrdata_o			  (m_w_s0_hrdata_i),
	// AHB Lite read int		  erface
	.ahbl_r_hsel_i      		  (m_r_ahbl_s0_hsel_o),
	.ahbl_r_haddr_i     		  (m_r_s0_haddr_o),
	.ahbl_r_hburst_i    		  (m_r_s0_hburst_o),
	.ahbl_r_hsize_i     		  (m_r_s0_hsize_o),
	.ahbl_r_htrans_i    		  (m_r_s0_htrans_o),
	.ahbl_r_hwrite_i    		  (m_r_s0_hwrite_o),
	.ahbl_r_hwdata_i    		  (m_r_s0_hwdata_o),
	.ahbl_r_hready_o    		  (m_r_s0_hready_i),
	.ahbl_r_hresp_o     		  (m_r_s0_hresp_i),
	.ahbl_r_hrdata_o    		  (m_r_s0_hrdata_i),
	.update_desc_ptr    		  (start_dma),
	.dma_done           		  (dma_compl),
	.num_descr          		  (num_descr),
	.dma_abor_status    		  (dma_abor_status),
	.dma_done_status    		  (dma_done_status),
	.dma_err_status     		  (dma_err_status),
	.wr_done            		  (wr_done         ),
	.register_address   		  (register_address),
	.wr_data            		  (wr_data         ),
	.wr_en              		  (wr_en           ),
	.rd_en              		  (rd_en           ),
	.rd_done            		  (rd_done),
	.DMA_read_byte_count 		  (DMA_read_byte_count),
	.clear_read_byte_chunk_reg 	  (clear_read_byte_chunk_reg),
	.DMA_read_byte_chunk  		  (DMA_read_byte_chunk),
	.fixed_pattern      		  (fixed_pattern),
	.DMA_write_size     		  (DMA_write_size),
	.DMA_read_size     			  (DMA_read_size),
	.DMA_write_size_valid 		  (DMA_write_size_valid),
	.DMA_read_size_valid 		  (DMA_read_size_valid),
	.DMA_read_checker  			  (DMA_read_checker),
	.DMA_read_checker_valid  	  (DMA_read_checker_valid),
	.DMA_direction      		  (DMA_direction),
	.data_type         			  (data_type),
	.msi_assert        			  (msi_assert),
	.READ_DATA_CHECK 			  (READ_DATA_CHECK),
	.type_of_testcase			(type_of_testcase)
);


apb_master_wrapper  # (
    . SIM   (SIM),
	.PCIE_CSR_BASE_ADDR(PCIE_CSR_BASE_ADDR)
)backdoor_apb_inst (
    .config_done 		(config_done	 ),
	.num_descr   		(num_descr		 ),
	.clk_usr_i   		(clk_usr_div2_i	 ),
    //apb interface
    .apb_clk_i 			(c_apb_pclk_i	 ),
	.apb_reset_n_i 		(c_apb_preset_n_i),
	.apb_addr_o 		(c_apb_paddr_i	 ),
	.apb_sel_o 			(c_apb_psel_i	 ),
	.apb_enable_o 		(c_apb_penable_i ),
	.apb_write_o 		(c_apb_pwrite_i	 ),
	.apb_wdata_o 		(c_apb_pwdata_i	 ),
	.apb_rdata_i 		(c_apb_prdata_o	 ),
	.apb_ready_i 		(c_apb_pready_o	 ),
	.apb_slverr_i 		(c_apb_pslverr_o ),
	.dma_done   		(dma_done),
	.wr_done         	(wr_done         ),
	.register_address	(register_address),
	.wr_data         	(wr_data         ),
	.rd_en              (rd_en           ),
	.rd_done            (rd_done		 ),
	.wr_en           	(wr_en           ),
	.gen_no				(gen_no			 ),
	.lane_no			(lane_no		 )
);




 always @(posedge c_apb_pclk_i or negedge perst_n_i)
 begin 
	 if (~perst_n_i) 
     begin 
		 c_apb_preset_n_i   <= 1'b0;
	 end 
	 else 
	 begin 
		 c_apb_preset_n_i   <= 1'b1;
	 end 
 end 



always @(posedge clk_usr_o) begin 
    if (!rst_n) 
	begin  
	    counter <= 32'd0;
		clock_flag <= 1'b0;
	end 
	else 
	begin 
	    if (counter == 250000000) 
		begin 
		    counter   <= 32'd0;
			clock_flag <= ~clock_flag;
		end 
		else 
		begin 
		    counter   <= counter + 1'b1;
			clock_flag <= clock_flag;
		end 	
	end 
end 



//	SYS-MEM : Stores Descriptor DATA 

sys_mem # (
     // Parameters 
     .MEM_DEPTH                             (1024), //2048
     .INITMODE                              (0), 
     .INIT_FMT                              ("HEX"), 
     .INITFILE                              ("none"),
	 .NO_LANES								(NO_LANES),
	 .DATA_WIDTH							(DATA_WIDTH)
	 )
u_sys_mem 
    ( 
     // Inputs 
     .ahbl_hclk_i                           (clk_usr_div2_i), 
     .ahbl_hresetn_i                        (rstn_clk2), 
     .ahbl_s0_hsel_i                        (m_w_ahbl_s1_hsel_o), 
     .ahbl_s0_hready_i                      (1'b1), 
     .ahbl_s0_haddr_i                       (sys_mem_wr_addr),
     .ahbl_s0_hburst_i                      (m_w_s1_hburst_o[2:0]),
     .ahbl_s0_hsize_i                       (m_w_s1_hsize_o[2:0]), 
     .ahbl_s0_htrans_i                      (m_w_s1_htrans_o[1:0]),
     .ahbl_s0_hwrite_i                      (m_w_s1_hwrite_o), 
     .ahbl_s0_hwdata_i                      (m_w_s1_hwdata_o[DATA_WIDTH-1:0]), 
     .ahbl_s1_hsel_i                        (m_r_ahbl_s1_hsel_o), 
     .ahbl_s1_hready_i                      (1'b1), 
     .ahbl_s1_haddr_i                       (sys_mem_rd_addr),
     .ahbl_s1_hburst_i                      (m_r_s1_hburst_o[2:0]),
     .ahbl_s1_hsize_i                       (m_r_s1_hsize_o[2:0]), 
     .ahbl_s1_htrans_i                      (m_r_s1_htrans_o[1:0]),
     .ahbl_s1_hwrite_i                      (m_r_s1_hwrite_o), 
     .ahbl_s1_hwdata_i                      (m_r_s1_hwdata_o[(NO_LANES*64-1):0]),
     // Outputs 
     .ahbl_s0_hreadyout_o                   (m_w_s1_hready_i), 
     .ahbl_s0_hresp_o                       (m_w_s1_hresp_i), 
     .ahbl_s0_hrdata_o                      (m_w_s1_hrdata_i[DATA_WIDTH-1:0]), 
     .ahbl_s1_hreadyout_o                   (m_r_s1_hready_i), 
     .ahbl_s1_hresp_o                       (m_r_s1_hresp_i), 
     .ahbl_s1_hrdata_o                      (m_r_s1_hrdata_i[(NO_LANES*64-1):0]),
	 
	 // register interface
	 .dma_done_status                       (dma_done_status),
	 .dma_err_status                        (dma_err_status ),
	 .dma_abor_status                       (dma_abor_status),
	 .num_of_descr                          (num_descr),
	 .dma_compl                             (dma_compl),
	 .start_dma                             (start_dma)
    );
		
		
// FIFO - WRAPPER Module : Incremental or Fixed Data is generated / stored 		
		
fifo_wrapper  #(
	.NO_LANES(NO_LANES)
)
fifo_wrapper_inst (
	.clk_i  					(clk_usr_div2_i			  ),
	.rstn_i 					(rstn_clk2				  ),
    // writing port 			                          
    .m_w_ahbl_s2_hsel_i 		(m_w_ahbl_s2_hsel_o 	  ),
    .m_w_s2_haddr_i     		(m_w_s2_haddr_o			  ),
    .m_w_s2_hburst_i    		(m_w_s2_hburst_o		  ),
    .m_w_s2_hsize_i     		(m_w_s2_hsize_o			  ),
    .m_w_s2_htrans_i    		(m_w_s2_htrans_o		  ),
    .m_w_s2_hwrite_i    		(m_w_s2_hwrite_o		  ),
    .m_w_s2_hwdata_i    		(m_w_s2_hwdata_o		  ),
    .m_w_s2_hready_o    		(m_w_s2_hready_i		  ),
    .m_w_s2_hresp_o     		(m_w_s2_hresp_i			  ),
    .m_w_s2_hrdata_o    		(m_w_s2_hrdata_i		  ),
				                                          
	//reading port			                              
    .m_r_ahbl_s2_hsel_i 		(m_r_ahbl_s2_hsel_o 	  ),
    .m_r_s2_haddr_i     		(m_r_s2_haddr_o			  ),
    .m_r_s2_hburst_i    		(m_r_s2_hburst_o		  ),
    .m_r_s2_hsize_i     		(m_r_s2_hsize_o			  ),
    .m_r_s2_htrans_i    		(m_r_s2_htrans_o		  ),
    .m_r_s2_hwrite_i    		(m_r_s2_hwrite_o		  ),
    .m_r_s2_hwdata_i    		(m_r_s2_hwdata_o		  ),
    .m_r_s2_hready_o    		(m_r_s2_hready_i		  ),
    .m_r_s2_hresp_o     		(m_r_s2_hresp_i			  ),
    .m_r_s2_hrdata_o    		(m_r_s2_hrdata_i		  ),
	                                                      
	.start_dma        			(start_dma				  ),
	.DMA_read_byte_count 		(DMA_read_byte_count	  ),
	.clear_read_byte_chunk_reg  (clear_read_byte_chunk_reg),
	.DMA_read_byte_chunk   		(DMA_read_byte_chunk	  ),
	.fixed_pattern       		(fixed_pattern			  ),
	.dma_done           		(dma_compl				  ),
	.DMA_write_size     		(DMA_write_size			  ),
	.DMA_write_size_valid 		(DMA_write_size_valid	  ),
	.DMA_read_size      		(DMA_read_size			  ),
	.DMA_read_size_valid 		(DMA_read_size_valid	  ),
	.DMA_read_checker  			(DMA_read_checker		  ),
	.DMA_read_checker_valid  	(DMA_read_checker_valid	  ),
	.data_type         			(data_type				  ),
	.READ_DATA_CHECK_COMPLETE	(READ_DATA_CHECK		  ),
	.num_descr					(num_descr				  ),
	.DMA_direction      		(DMA_direction),
	.type_of_testcase			(type_of_testcase)
);

always @(posedge c_apb_pclk_i or negedge c_apb_preset_n_i) begin 
    if (!c_apb_preset_n_i) 
	begin  
	    counter_apb <= 32'd0;
		clock_flag_apb <= 1'b0;
	end 
	else 
	begin 
	    if (counter_apb == 112000000) 
		begin 
		    counter_apb   <= 32'd0;
			clock_flag_apb <= ~clock_flag_apb;
		end 
		else 
		begin 
		    counter_apb   <= counter_apb + 1'b1;
			clock_flag_apb <= clock_flag_apb;
		end 	
	end 
end

assign dma_done_o = dma_compl;

endmodule 
