
module fifo_wrapper
#(
	parameter NO_LANES = 4
)
 (
    input clk_i,
	input rstn_i,
	
	// writing port 
    input 								m_w_ahbl_s2_hsel_i,
    input 		[31:0]					m_w_s2_haddr_i    ,
    input 		[2:0] 					m_w_s2_hburst_i   ,
    input 		[2:0] 					m_w_s2_hsize_i    ,
    input 		[1:0] 					m_w_s2_htrans_i   ,
    input 								m_w_s2_hwrite_i   ,
    input 		[NO_LANES*64-1:0] 		m_w_s2_hwdata_i   ,                            
    output 								m_w_s2_hready_o   ,                  
    output 								m_w_s2_hresp_o    ,
    output 		[NO_LANES*64-1:0] 		m_w_s2_hrdata_o   ,                 
		
	//read port	
    input 								m_r_ahbl_s2_hsel_i,
    input 		[31:0]  				m_r_s2_haddr_i    ,
    input 		[2:0]   				m_r_s2_hburst_i   ,
    input 		[2:0]   				m_r_s2_hsize_i    ,
    input 		[1:0] 					m_r_s2_htrans_i   ,
    input 								m_r_s2_hwrite_i   ,
    input 		[NO_LANES*64-1:0] 		m_r_s2_hwdata_i   ,                 
    output 								m_r_s2_hready_o   ,                 
    output 								m_r_s2_hresp_o    ,                 
    output reg  [NO_LANES*64-1:0] 		m_r_s2_hrdata_o	  ,                 
	input      							start_dma		  ,
	output reg 	[31:0] 					DMA_read_byte_count,
	output reg 	[31:0] 					DMA_read_byte_chunk,
	input 								clear_read_byte_chunk_reg,
	input 		[31:0] 					fixed_pattern,
	input 								dma_done,
	input 		[31:0] 					DMA_write_size,
	input 								DMA_write_size_valid,
	input 		[31:0]				    DMA_read_size,
	input 								DMA_read_size_valid,
	output reg 							DMA_read_checker,
	output 								DMA_read_checker_valid,
	input 								data_type,
	output reg 							READ_DATA_CHECK_COMPLETE,
	input 		[7:0]				    num_descr,
	input 								DMA_direction,
	input 		[2:0]					type_of_testcase
);

reg 						multiple_read_write;
wire 	[31:0]				dw_per_desc;
reg 	[31:0] 				wr_data_wr;
wire 	[NO_LANES*64-1:0] 	rd_data_rd;
reg 	[31:0] 				m_r_s2_haddr_d;
wire 	[NO_LANES*64-1:0] 	rd_data;
wire 						rd_data_valid;
reg 	[31:0] 				rd_data_wr_fifo_d;
reg 						wr_en_wr;
wire 						rd_en_wr;
wire 						rd_done_check;
reg 						rd_en_rd_d;
reg 	[NO_LANES*64-1:0] 	incremental_pattern_seed;
integer 					idx,read_data_counter;
reg 	[1:0] 				byte_count;
reg 						counter;
reg 	[NO_LANES*64-1:0] 	rd_data_d;
reg 	[1:0] 				DMA_read_data_counter;
reg 						READ_DATA_IS_CORRECT;
reg 						READ_DATA_IS_INCORRECT;
reg 	[NO_LANES*64-1:0]	READ_DATA_CHECKER;
reg 						m_w_s2_hwrite_i_d;
reg 						m_w_s2_hwrite_i_2d;
reg 						DESCRIPTOR_START;
reg 						hwrite_rising_edge;
reg 	[NO_LANES*64-1:0]	m_w_s2_hwdata_i_d;
reg 	[NO_LANES*64-1:0]	m_w_s2_hwdata_i_2d;
reg 						DMA_write_size_valid_d;
	
	
reg 	[1:0] 				m_w_s2_htrans_i_d;
reg 	[1:0] 				m_w_s2_htrans_i_2d;
integer						i;

assign m_w_s2_hrdata_o   = {(NO_LANES*64-1){1'b0}};
assign m_r_s2_hresp_o    = 1'b0;
assign m_r_s2_hready_o   = 1'b1;
assign rd_en_wr          = (m_r_s2_haddr_i != m_r_s2_haddr_d) ? m_r_ahbl_s2_hsel_i : 1'b0;
assign dw_per_desc       = (rstn_i)?((DMA_write_size_valid)?((DMA_write_size)/(num_descr*4)):dw_per_desc):32'b0;

always @(posedge clk_i or negedge rstn_i)
begin 
    if (!rstn_i) 
	begin 
	    wr_en_wr     <= 1'b0;
		wr_data_wr   <= 32'd0;
		m_r_s2_haddr_d <= 32'd0;
		incremental_pattern_seed    <= {(NO_LANES*64-1){1'b0}};
		m_r_s2_hrdata_o             <= {(NO_LANES*64-1){1'b0}};
		multiple_read_write			<= 1'b0;
		DMA_write_size_valid_d			<= 1'b0;
	end 
	else 
	begin 
		DMA_write_size_valid_d <= DMA_write_size_valid;
		if(DMA_write_size_valid == 1'b1  &&  DMA_write_size_valid_d == 1'b0) begin
			multiple_read_write <= 1'b1;
		end 
		else begin
			multiple_read_write <= multiple_read_write;
		end 
	
	    if (m_r_ahbl_s2_hsel_i)
	        m_r_s2_haddr_d       	<= m_r_s2_haddr_i;
		else 
		    m_r_s2_haddr_d       	<= m_r_s2_haddr_d;
			
		if (DMA_write_size_valid && (!multiple_read_write || (type_of_testcase != 3'b101)))
   		begin 
			if(NO_LANES == 4) begin
				if(dw_per_desc == 1) begin
					 incremental_pattern_seed             <= {fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern};
				end
				else if(dw_per_desc == 2) begin
					incremental_pattern_seed             <= {fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,(fixed_pattern + 32'h1),fixed_pattern};
				end 
				else if(dw_per_desc == 4) begin
					incremental_pattern_seed             <= {fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,(fixed_pattern + 32'h3),(fixed_pattern + 32'h2),(fixed_pattern + 32'h1),fixed_pattern};					
				end 
				else begin
					incremental_pattern_seed    		<= {(fixed_pattern +32'h7),(fixed_pattern+32'h6),(fixed_pattern+32'h5),(fixed_pattern+32'h4),(fixed_pattern+32'h3),(fixed_pattern+32'h2),(fixed_pattern+32'h1),(fixed_pattern)};
				end 
			end
			else if(NO_LANES == 2) begin
				if(dw_per_desc == 1) begin
					incremental_pattern_seed              <= {fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern};
				end 
				else if(dw_per_desc == 2) begin
					incremental_pattern_seed              <= {fixed_pattern,fixed_pattern,(fixed_pattern + 32'h1),fixed_pattern};
				end 
				else begin
					incremental_pattern_seed    			<= {(fixed_pattern+32'h3),(fixed_pattern+32'h2),(fixed_pattern+32'h1),(fixed_pattern)};
				end 
			end 
			else begin
				if(dw_per_desc == 1) begin
					incremental_pattern_seed             <= {fixed_pattern,fixed_pattern};
				end
				else begin
					incremental_pattern_seed    <= {(fixed_pattern+1'b1),fixed_pattern};
				end
			end 
			counter <=1;
		end
		else if (rd_en_wr && (!data_type))
	    begin 
			if(NO_LANES == 4) begin
				if(dw_per_desc == 1) begin
					m_r_s2_hrdata_o             <= {32'h0,32'h0,32'h0,32'h0,32'h0,32'h0,32'h0,fixed_pattern};
				end
				else if(dw_per_desc == 2) begin
					m_r_s2_hrdata_o             <= {32'h0,32'h0,32'h0,32'h0,32'h0,32'h0,fixed_pattern,fixed_pattern};
				end 
				else if(dw_per_desc == 4) begin
					m_r_s2_hrdata_o             <= {32'h0,32'h0,32'h0,32'h0,fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern};					
				end 
				else begin
					m_r_s2_hrdata_o             <= {fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern};
				end 
				 
			end
			else if(NO_LANES == 2) begin
				if(dw_per_desc == 1) begin
					m_r_s2_hrdata_o              <= {32'h0,32'h0,32'h0,fixed_pattern};
				end 
				else if(dw_per_desc == 2) begin
					m_r_s2_hrdata_o              <= {32'h0,32'h0,fixed_pattern,fixed_pattern};
				end 
				else begin
					m_r_s2_hrdata_o              <= {fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern};
				end 
						
			end 
			else begin
				if(dw_per_desc == 1) begin
					m_r_s2_hrdata_o          	<= {32'h0,fixed_pattern};
				end
				else begin
					m_r_s2_hrdata_o             <= {fixed_pattern,fixed_pattern};
				end
					
			end  
		end 
		//else if (!DMA_write_size_valid && counter)
		
		else if (rd_en_wr && (data_type))
		begin 
		    m_r_s2_hrdata_o             	<= incremental_pattern_seed;
			if(NO_LANES == 4) begin
				if(dw_per_desc == 1) begin
					incremental_pattern_seed    <= incremental_pattern_seed + 256'h1;
				end
				else if(dw_per_desc == 2) begin
					incremental_pattern_seed    <= incremental_pattern_seed + 256'h0000000000000000000000000000000000000000000000000000000200000002;
				end 
				else if(dw_per_desc == 4) begin
					incremental_pattern_seed    <= incremental_pattern_seed + 256'h0000000000000000000000000000000000000004000000040000000400000004;
				end 
				else begin
					incremental_pattern_seed    <= incremental_pattern_seed + 256'h0000000800000008000000080000000800000008000000080000000800000008;
				end
			end
			else if(NO_LANES == 2) begin
				if(dw_per_desc == 1) begin
					incremental_pattern_seed    <= incremental_pattern_seed +128'h1;
				end 
				else if(dw_per_desc == 2) begin
					incremental_pattern_seed    <= incremental_pattern_seed +128'h00000000000000000000000200000002;
				end 
				else begin
					incremental_pattern_seed    <= incremental_pattern_seed +128'h00000004000000040000000400000004;			
				end 
			end
			else begin
				if(dw_per_desc == 1) begin
					incremental_pattern_seed    <= incremental_pattern_seed + 64'h0000000000000001;
				end 
				else begin
					incremental_pattern_seed    <= incremental_pattern_seed + 64'h0000000200000002;
				end
			end 
		end 
		else 
		begin 
		    incremental_pattern_seed  		<= incremental_pattern_seed;
		    m_r_s2_hrdata_o           		<= m_r_s2_hrdata_o;
		end 
	end 
end 



// delaying the data by one clock cycle
always @(posedge clk_i or negedge rstn_i)
begin 
    if ((!rstn_i) | DMA_read_size_valid)
	begin 
	    rd_data_d             <= {(NO_LANES*64-1){1'b0}};
		DMA_read_data_counter <= 2'b00;
	end 
	else 
	begin 
	    if(rd_data_valid)
		begin 
		    rd_data_d    <= rd_data;
			if (DMA_read_data_counter[1] == 1'b1)
			    DMA_read_data_counter <= DMA_read_data_counter;
			else 
			    DMA_read_data_counter <= DMA_read_data_counter + 1'b1;
		end 
		else 
		begin 
		    rd_data_d    <= rd_data_d;
			DMA_read_data_counter <= DMA_read_data_counter;
		end 
	end 
end 
// DMA read ; checking the data 
always @(posedge clk_i or negedge rstn_i)
begin 
    if ((!rstn_i) | DMA_read_size_valid)
	begin 
	    DMA_read_checker   <= 1'b0;
	end 
	else 
	begin 
	    if (DMA_read_checker)            DMA_read_checker <= 1'b1;
		else if(NO_LANES == 4) begin
			if (((rd_data_d+256'h0000000800000008000000080000000800000008000000080000000800000008 != rd_data) & DMA_read_data_counter[1]) &(rd_data_valid) & (data_type))   DMA_read_checker <= 1'b1; // incremental counter checker 
			else if ((({fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern} != rd_data) & DMA_read_data_counter[1]) &(rd_data_valid) & (!data_type))   DMA_read_checker <= 1'b1;    // fixed pattern checker
			else    DMA_read_checker <= DMA_read_checker;
		end 
		else if(NO_LANES == 2) begin
			if (((rd_data_d+128'h00000004000000040000000400000004 != rd_data) & DMA_read_data_counter[1]) &(rd_data_valid) & (data_type))   DMA_read_checker <= 1'b1; // incremental counter checker 
			else if ((({fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern} != rd_data) & DMA_read_data_counter[1]) &(rd_data_valid) & (!data_type))   DMA_read_checker <= 1'b1;    // fixed pattern checker
			else   DMA_read_checker <= DMA_read_checker;
		end 
		else begin
			if (((rd_data_d+64'h0000000200000002 != rd_data) & DMA_read_data_counter[1]) &(rd_data_valid) & (data_type))   DMA_read_checker <= 1'b1; // incremental counter checker 
			else if ((({fixed_pattern,fixed_pattern} != rd_data) & DMA_read_data_counter[1]) &(rd_data_valid) & (!data_type))   DMA_read_checker <= 1'b1;    // fixed pattern checker
			else                             DMA_read_checker <= DMA_read_checker;
		end
end 
end
assign DMA_read_checker_valid   = rd_done_check;
wire [31:0]DMA_read_size_up;
wire [31:0]DMA_read_size_lane_4;
wire [31:0]DMA_read_size_lane_2;
wire [31:0]DMA_read_size_lane_1;
assign DMA_read_size_lane_4 = ((NO_LANES == 4)&(dw_per_desc >= 8)) ? DMA_read_size : num_descr*(32'd32);
assign DMA_read_size_lane_2 = ((NO_LANES == 2)&(dw_per_desc >= 4)) ? DMA_read_size : num_descr*(32'd16);
assign DMA_read_size_lane_1 = ((NO_LANES == 1)&(dw_per_desc >= 2)) ? DMA_read_size : num_descr*(32'd8);
assign DMA_read_size_up = ((NO_LANES == 4) ? DMA_read_size_lane_4 : ((NO_LANES == 2) ? DMA_read_size_lane_2 : ((NO_LANES == 1)? DMA_read_size_lane_1 : 32'b0)));

always @(posedge clk_i or negedge rstn_i) begin
	if(rstn_i == 1'b0) begin
		m_w_s2_hwdata_i_d <= {(NO_LANES*64-1){1'b0}};
		m_w_s2_hwdata_i_2d <= {(NO_LANES*64-1){1'b0}};
		m_w_s2_htrans_i_d <= 2'b0;
		m_w_s2_htrans_i_2d <= 2'b0;
		read_data_counter <= 0;
		READ_DATA_IS_INCORRECT <= 0;
		READ_DATA_CHECK_COMPLETE <= 0;
	end 
	else begin
		m_w_s2_hwdata_i_d <= m_w_s2_hwdata_i;
		m_w_s2_htrans_i_d <= m_w_s2_htrans_i;
		m_w_s2_htrans_i_2d <= m_w_s2_htrans_i_d;
		
		if(DMA_direction == 1'b1) begin
			if((m_w_s2_htrans_i_d[1] == 1'b1) & (m_w_s2_htrans_i_2d[1] == 1'b1)) begin
				if(data_type == 1'b1) begin
					if(NO_LANES == 4) begin
						if((m_w_s2_hwdata_i != m_w_s2_hwdata_i_d + 256'h0000000800000008000000080000000800000008000000080000000800000008) & (dw_per_desc >= 8)) begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end
						else if((m_w_s2_hwdata_i != m_w_s2_hwdata_i_d + 256'h0000000000000000000000000000000000000004000000040000000400000004) & (dw_per_desc == 4)) begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end
						else if((m_w_s2_hwdata_i != m_w_s2_hwdata_i_d + 256'h0000000000000000000000000000000000000000000000000000000200000002) & (dw_per_desc == 2))begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end
						else if((m_w_s2_hwdata_i != m_w_s2_hwdata_i_d + 256'h1) & (dw_per_desc == 1)) begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end
					end
					if(NO_LANES == 2) begin
						if((m_w_s2_hwdata_i != m_w_s2_hwdata_i_d + 128'h00000004000000040000000400000004) & (dw_per_desc >= 4)) begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end
						else if((m_w_s2_hwdata_i != m_w_s2_hwdata_i_d + 128'h00000000000000000000000200000002) & (dw_per_desc == 2))begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end
						else if((m_w_s2_hwdata_i != m_w_s2_hwdata_i_d + 128'h1) & (dw_per_desc == 1)) begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end					
					end 
					if(NO_LANES == 1) begin
						if((m_w_s2_hwdata_i != m_w_s2_hwdata_i_d + 64'h0000000200000002) & (dw_per_desc >= 2))begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end
						else if((m_w_s2_hwdata_i != m_w_s2_hwdata_i_d + 64'h1) & (dw_per_desc == 1)) begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end					
					end 				
					else begin
						READ_DATA_IS_INCORRECT <= READ_DATA_IS_INCORRECT;
					end
				end			
				else begin
					if(NO_LANES == 4) begin
						if((m_w_s2_hwdata_i != {(2*NO_LANES){32'h22446688}}) & (dw_per_desc >= 8)) begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end
						else if((m_w_s2_hwdata_i[127:0] != {fixed_pattern,fixed_pattern,fixed_pattern,fixed_pattern}) & (dw_per_desc == 4)) begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end
						else if((m_w_s2_hwdata_i[63:0] != {fixed_pattern,fixed_pattern}) & (dw_per_desc == 2))begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end
						else if((m_w_s2_hwdata_i[31:0] != {fixed_pattern}) & (dw_per_desc == 1)) begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end
					end
					else if(NO_LANES == 2) begin
						if((m_w_s2_hwdata_i != {(2*NO_LANES){32'h22446688}}) & (dw_per_desc >= 4)) begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end
						else if((m_w_s2_hwdata_i[63:0] != {fixed_pattern,fixed_pattern}) & (dw_per_desc == 2))begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end
						else if((m_w_s2_hwdata_i[31:0] != {fixed_pattern}) & (dw_per_desc == 1)) begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end					
					end 
					else if(NO_LANES == 1) begin
						if((m_w_s2_hwdata_i != {(2*NO_LANES){32'h22446688}}) & (dw_per_desc >= 2))begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end
						else if((m_w_s2_hwdata_i[31:0] != {fixed_pattern}) & (dw_per_desc == 1)) begin
							READ_DATA_IS_INCORRECT <= 1'b1;
						end					
					end 	
					else begin
						READ_DATA_IS_INCORRECT <= READ_DATA_IS_INCORRECT;
					end
				end
			end
			
			if(m_w_s2_htrans_i[1] == 1'b1) begin
				read_data_counter <= read_data_counter + 1;
			end
			else begin
				read_data_counter <= read_data_counter;
			end
			
			if((read_data_counter == (DMA_read_size_up/(NO_LANES*8))-1) & (READ_DATA_IS_INCORRECT == 1'b0)) begin
				READ_DATA_CHECK_COMPLETE <= 1'b1;
			end 
			else if((read_data_counter == (DMA_read_size_up/(NO_LANES*8))-1) & (READ_DATA_IS_INCORRECT == 1'b1)) begin
				READ_DATA_CHECK_COMPLETE <= 1'b0;
			end
			else begin
				READ_DATA_CHECK_COMPLETE <= READ_DATA_CHECK_COMPLETE;
			end
		end 
	end 
end



  dpram_wrapper  
  #(
  .NO_LANES(NO_LANES)
  )DMA_read_RAM
  (
    .clk_i (clk_i),
	.rstn_i (rstn_i),
	.m_w_s2_haddr_i (m_w_s2_haddr_i),
	.m_w_s2_htrans_i (m_w_s2_htrans_i),
	.m_w_s2_hwdata_i (m_w_s2_hwdata_i),
	.m_w_s2_hready_o (m_w_s2_hready_o),
	.m_w_s2_hresp_o  (m_w_s2_hresp_o),
	.DMA_read_size   (DMA_read_size),
	.DMA_read_size_valid (DMA_read_size_valid),
	.rd_data         (rd_data),
	.rd_data_valid   (rd_data_valid),
	.rd_done_check   (rd_done_check) 
	
);
endmodule
