// This module represents the register space
`timescale 1ps / 1ps

//*******************************
//       Module definition      *
//*******************************


module register_space #(
	parameter PCIE_CSR_BASE_ADDR = 32'hC520_0000
)
(
	// AHB Lite write interface
	input         		ahbl_w_hclk_i,
	input         		ahbl_w_hresetn_i,
	input         		ahbl_w_hsel_i,
	input 		[31:0]  ahbl_w_haddr_i,
	input 		[2:0]   ahbl_w_hburst_i,
	input 		[2:0]   ahbl_w_hsize_i,
	input 		[1:0]   ahbl_w_htrans_i,
	input       	    ahbl_w_hwrite_i,
	input 		[31:0]  ahbl_w_hwdata_i,
	output 		        ahbl_w_hready_o,
	output 		        ahbl_w_hresp_o,
	output 		[31:0]  ahbl_w_hrdata_o,

	// AHB Lite read interface
	input         ahbl_r_hsel_i,
	input 		[31:0]  ahbl_r_haddr_i,
	input 		[2:0]   ahbl_r_hburst_i,
	input 		[2:0]   ahbl_r_hsize_i,
	input 		[1:0]   ahbl_r_htrans_i,
	input 		        ahbl_r_hwrite_i,
	input 		[31:0]  ahbl_r_hwdata_i,
	output        		ahbl_r_hready_o,
	output        		ahbl_r_hresp_o,
	output reg  [31:0]  ahbl_r_hrdata_o,
	///
	output        		update_desc_ptr,
	input         		dma_done,
	output reg 	[7:0]   num_descr,
	input 				dma_abor_status,
	input 				dma_done_status,
	input 				dma_err_status,
	input         		wr_done,
	input         		rd_done,
	output reg  [31:0]  register_address,
	output reg  [31:0]  wr_data,
	output reg 			wr_en,
	output reg 			rd_en,
	input 		[31:0]  DMA_read_byte_count,
	// input rd_checker,
	input 		[31:0]  DMA_read_byte_chunk,
	output reg 			clear_read_byte_chunk_reg,
	output reg  [31:0]  fixed_pattern,
	output reg  [31:0]  DMA_write_size,
	output reg 			DMA_write_size_valid,
	output reg  [31:0] 	DMA_read_size,
	output reg 			DMA_read_size_valid,
	input 				DMA_read_checker,
	input 				DMA_read_checker_valid,
	output reg 			DMA_direction,
	output reg 			data_type,
	output 				msi_assert,
	input 				READ_DATA_CHECK,
	output reg	[2:0]	type_of_testcase			
);

reg 					rd_checker;
reg 					rd_done_d;
reg 					rd_done_2d;
reg 					wr_done_d;
reg 					wr_done_2d;
reg 			[31:0]  ahbl_w_haddr_i_d;
reg 			[31:0]  performance_counter;
reg 					dma_done_d;
reg 					dma_done_2d;
wire 					dma_done_redge;
reg 					start_DMA_read;
reg 					start_DMA_write;
reg 					soft_ip_rst_d;
wire 					soft_ip_rst_redge;
wire 					soft_ip_rst_fedge;
reg 					update_desc_ptr_d;
reg 					soft_ip_rst;
reg 			[5:0] 	soft_reset_wait_counter;
reg 					start_counter;
reg 			[15:0]  counter;
reg 			[1:0] 	ahbl_w_htrans_i_d;
// reg DMA_direction;

assign soft_ip_rst_redge = soft_ip_rst & (~soft_ip_rst_d);
assign soft_ip_rst_fedge = (~soft_ip_rst) & (soft_ip_rst_d);

assign ahbl_w_hready_o  = 1'b1;
assign ahbl_w_hresp_o   = 1'b0;
assign ahbl_w_hrdata_o  = 32'd0;
assign ahbl_r_hready_o  = 1'b1;
assign ahbl_r_hresp_o   = 1'b0;
reg dma_start_flag;

assign dma_done_redge = dma_done & (!dma_done_d);
always @(posedge ahbl_w_hclk_i or negedge ahbl_w_hresetn_i)
begin
    if (~ahbl_w_hresetn_i)
	begin
        soft_reset_wait_counter     <= 6'h00;
		soft_ip_rst                 <= 1'b0;
	end
	else
	begin
		// generating a flag for soft reset, so that on the rising edge we can assert the soft reset and for falling edge we can
		// de-assert the soft reset.
	    if (dma_done_redge)
		begin
		    soft_ip_rst     <= 1'b1;//1'b1-soft reset works:1'b0-soft reset not works
		end
		else if (soft_reset_wait_counter[5])
		begin
		    soft_ip_rst     <= 1'b0;
		end
		else
		begin
		    soft_ip_rst     <= soft_ip_rst;
		end


		if (soft_ip_rst)
		    soft_reset_wait_counter    <= soft_reset_wait_counter + 1'b1;
		else
		    soft_reset_wait_counter    <= 6'h00;
	end
end

always @(posedge ahbl_w_hclk_i or negedge ahbl_w_hresetn_i)
begin
    if (~ahbl_w_hresetn_i)
	begin
	    performance_counter     <= 32'd0;
		dma_start_flag          <= 1'b0;
	end
	else
	begin
	    if (update_desc_ptr_d)
		begin
		    dma_start_flag      <= 1'b1;
		end
		else if ((dma_done & DMA_direction & DMA_read_checker_valid) || (dma_done & (!DMA_direction)))
		begin
		    dma_start_flag      <= 1'b0;
		end
		else
		begin
            dma_start_flag      <= dma_start_flag;
		end

	    if (update_desc_ptr)
			performance_counter     <= 32'd0;
		else if ((dma_done & DMA_direction & DMA_read_checker_valid) || (dma_done & (!DMA_direction)))
		    performance_counter     <= performance_counter;
		else if (dma_start_flag)
		    performance_counter     <= performance_counter + 1'b1;
		else
		    performance_counter     <= 32'd0;
	end
end


always @(posedge ahbl_w_hclk_i or negedge ahbl_w_hresetn_i)
begin
    if (~ahbl_w_hresetn_i)
	begin
	    register_address                  <= 32'd0;
		wr_data                           <= 32'd0;
		wr_en                             <= 1'b0;
		rd_en                             <=1'b0;
	end
	else
	begin
	    if (soft_ip_rst_redge)
		begin
		    register_address       <= (PCIE_CSR_BASE_ADDR | 32'h0002_8004); //32'hC5228004;
			wr_data                <= 32'h80000001;
			wr_en                  <= 1'b1;
			rd_en                  <=1'b0;
		end
		else if (soft_ip_rst_fedge)
		begin
		    register_address       <= (PCIE_CSR_BASE_ADDR | 32'h0002_8004); //32'hC5228004;
			wr_data                <= 32'h80000000;
			wr_en                  <= 1'b1;
			rd_en                  <=1'b0;
		end
		else if (update_desc_ptr)				// update_desc_ptr = start_dma
		begin
		    register_address       <= (PCIE_CSR_BASE_ADDR | 32'h0002_8018); //32'hC5228018;
			wr_data                <= {24'h000000,num_descr};
			wr_en                  <= 1'b1;
		end
		else if (counter == 16'h01ff)
		begin
		    register_address       <= (PCIE_CSR_BASE_ADDR | 32'h0002_801C); //32'hC522801C;
			rd_en                  <= 1'b0;
		end
		else
		begin
			if (rd_done_2d )
			begin
			    rd_en               <= 1'b0;
			end
			else
			begin
			    rd_en               <= rd_en;
			end
		    if (wr_done_2d )
			begin
			    wr_en               <= 1'b0;
			end
			else
			begin
			    wr_en               <= wr_en;
			end
		end
	end
end

always @(posedge ahbl_w_hclk_i or negedge ahbl_w_hresetn_i)
begin
    if (~ahbl_w_hresetn_i)
	begin
		counter    <=16'h0;
		start_counter <=1'b0;
	end
	else
	begin
		if((ahbl_w_hwdata_i == 32'hfbe) || (ahbl_w_hwdata_i == 32'h13fe) || (ahbl_w_hwdata_i == 32'h17fe) ||(ahbl_w_hwdata_i == 32'h3fe) || (ahbl_w_hwdata_i == 32'h7fe) || (ahbl_w_hwdata_i == 32'hbfe))
		begin
			counter    <= 16'h0;
			start_counter <=1'b1;
		end
		else if(counter == 16'h200)
		begin
			counter    <= 16'h0;
			start_counter <=1'b0;
		end
	    else if(start_counter  == 1'b1)
		begin
			counter <= counter +1'b1;
		end
		else
		begin
			counter <= counter;
			start_counter <=start_counter;
		end
	end
end

assign update_desc_ptr = start_DMA_read | start_DMA_write;

assign msi_assert = (dma_done & DMA_direction & DMA_read_checker_valid) | (dma_done & (!DMA_direction));




always @(posedge ahbl_w_hclk_i or negedge ahbl_w_hresetn_i)
begin
    if (~ahbl_w_hresetn_i)
	begin
		ahbl_w_haddr_i_d    <= 32'h00000000;
		start_DMA_read      <= 1'b0;
		start_DMA_write     <= 1'b0;
		update_desc_ptr_d   <= 1'b0;
		soft_ip_rst_d       <= 1'b0;
        ahbl_w_htrans_i_d   <= 2'b00;
		wr_done_d           <= 1'b0;
		wr_done_2d          <= 1'b0;
		dma_done_d          <= 1'b0;
		dma_done_2d         <= 1'b0;
		rd_done_2d          <= 1'b0;
		rd_done_d           <= 1'b0;
		num_descr           <= 8'h00;
		clear_read_byte_chunk_reg     <= 1'b0;
		fixed_pattern       <= 32'h55AA55AA;
		DMA_write_size      <= 32'd0;
		DMA_read_size      <= 32'd0;
		DMA_write_size_valid  <= 32'd0;
		DMA_read_size_valid  <= 32'd0;
		DMA_direction        <= 1'b0;  // 0 means DMA write ; 1 means DMA read
		data_type            <= 1'b0;  // 0 means fixed pattern and 1 means incremental pattern
	end
	else
	begin
	    if (start_DMA_read & (!start_DMA_write))
		begin
		    DMA_direction        <= 1'b1;
		end
		else if ((!start_DMA_read) & start_DMA_write)
		begin
		    DMA_direction        <= 1'b0;
		end
		else
		begin
		    DMA_direction        <= DMA_direction;
		end
		update_desc_ptr_d                    <= update_desc_ptr;
		soft_ip_rst_d                        <= soft_ip_rst;
		rd_done_d                            <= rd_done;
		rd_done_2d                           <= rd_done_d;
		wr_done_d                            <= wr_done;
		wr_done_2d                           <= wr_done_d;
	    dma_done_d                           <= dma_done;
	    dma_done_2d                          <= dma_done_d;
	    ahbl_w_haddr_i_d                     <= ahbl_w_haddr_i;
		ahbl_w_htrans_i_d                    <= ahbl_w_htrans_i;
		DMA_write_size                       <= DMA_write_size;
		DMA_read_size                        <= DMA_read_size;
		data_type                            <= data_type;
	    if (ahbl_w_hwrite_i && ahbl_w_hsel_i && ((ahbl_w_htrans_i_d == 2) || (ahbl_w_htrans_i_d == 3)) ) begin
		    DMA_write_size_valid  <= 1'b0;
		    DMA_read_size_valid   <= 1'b0;
	        case (ahbl_w_haddr_i_d[15:0])
				16'h0008:
				begin
				    num_descr            <= ahbl_w_hwdata_i[7:0];
				end

				16'h000C:
				begin
					start_DMA_write      <= ahbl_w_hwdata_i[0];
		    	    start_DMA_read       <= ahbl_w_hwdata_i[1];
				end

				16'h001C:
				begin
				    fixed_pattern          <= ahbl_w_hwdata_i;
				end

				16'h0020:
				begin
				    DMA_write_size        <= ahbl_w_hwdata_i;
				    DMA_write_size_valid  <= 1'b1;

				end

				16'h0024:
				begin
				    DMA_read_size        <= ahbl_w_hwdata_i;
				    DMA_read_size_valid  <= 1'b1;
				end

				16'h0028:
				begin
				    data_type        <= ahbl_w_hwdata_i[0];
				end
				
				16'h002C:
				begin
				    type_of_testcase        <= ahbl_w_hwdata_i[2:0];
				end


		    	default:
		    	begin
				    start_DMA_write      <= 1'b0;
				    start_DMA_read       <= 1'b0;
					fixed_pattern        <= fixed_pattern;
		    	end
		    endcase
		end
		else
		begin
		    start_DMA_write      <= 1'b0;
		    start_DMA_read       <= 1'b0;
			DMA_write_size_valid <= 1'b0;
			DMA_read_size_valid  <= 1'b0;
		    num_descr            <= num_descr;
			fixed_pattern        <= fixed_pattern;
		end

		if (!ahbl_r_hwrite_i & ahbl_r_hsel_i)
		begin
		    clear_read_byte_chunk_reg     <= 1'b0;
		    case (ahbl_r_haddr_i[15:0])
			    16'h0000 :
				begin
				    ahbl_r_hrdata_o     <= {25'd0,(dma_done & DMA_direction & DMA_read_checker_valid), 1'b0 ,1'b0,1'b0,dma_abor_status, dma_err_status,(dma_done & (!DMA_direction)), 1'b0};
				end
				16'h0004 :
				begin
				    ahbl_r_hrdata_o     <= performance_counter;
				end
				16'h0010 :
				begin
				    ahbl_r_hrdata_o     <= DMA_read_byte_count;
				end

				16'h0014 :
				begin
				    ahbl_r_hrdata_o     <= 32'h24091717;
				end

				16'h0018 :
				begin
				    ahbl_r_hrdata_o      <= DMA_read_byte_chunk;
					clear_read_byte_chunk_reg      <= 1'b1;
				end

				16'h001C:
				begin
				    ahbl_r_hrdata_o      <= fixed_pattern;
				end

				16'h0020:
				begin
				    ahbl_r_hrdata_o      <= DMA_write_size;
				end

				16'h0024:
				begin
				    ahbl_r_hrdata_o      <= DMA_read_size;
				end

				16'h0028:
				begin
				    ahbl_r_hrdata_o      <= {31'b0,data_type};
				end

				16'h003C: begin
					ahbl_r_hrdata_o		 <= {31'b0,READ_DATA_CHECK};
				end

				default :
				begin
				    ahbl_r_hrdata_o     <= 32'd0;
				end
			endcase
		end
		else
		begin
		    clear_read_byte_chunk_reg     <= 1'b0;
		end
	end
end


endmodule
