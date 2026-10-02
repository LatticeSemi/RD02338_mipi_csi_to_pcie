module dpram_wrapper # (
    parameter MEM_DEPTH = 16384,
	parameter MEM_PART   = 16, // memory segregation// can be 4,8,16
	parameter NO_LANES = 4
)
(
    input clk_i,
	input rstn_i,
	// writing port 
    input 		[31:0]		 		m_w_s2_haddr_i    ,
    input 		[1:0] 		 		m_w_s2_htrans_i   ,
    input 		[NO_LANES*64-1:0] 	m_w_s2_hwdata_i   ,
    output 							m_w_s2_hready_o   , 
    output 							m_w_s2_hresp_o    ,
	input 		[31:0] 				DMA_read_size,
	input 							DMA_read_size_valid,
	output reg 	[NO_LANES*64-1:0] 	rd_data,
	output reg 						rd_data_valid,
	output 							rd_done_check
);

function [31:0] clog2;
  input [31:0] value;
  reg   [31:0] num;
begin
  num = value - 1;
  for (clog2=0; num>0; clog2=clog2+1) num = num>>1;
end
endfunction
wire 						rd_addr_less_than_size;
wire [NO_LANES*64-1:0]	 	rd_data_i;
reg							wr_en;
localparam         AWID     = clog2(MEM_DEPTH);                            //14   
localparam  [31:0] ADDR_RANGE = ((MEM_DEPTH * 32)/MEM_PART);//4            //65536 - 0x10000  // 0x8000......for mem_part = 16
localparam         MEM_PART_DEPTH = (MEM_DEPTH/MEM_PART);                  // 2048 - 0x00800  // 0x00400......for mem_part = 16
reg 	[NO_LANES*64-1:0] wr_data;
reg 	[AWID-1:0] wr_addr;
reg 	[NO_LANES*64-1:0] local_ram_addr;
reg 	[AWID-1:0] rd_addr;
wire 				mem_sel;
reg mem_sel_d;
reg [1:0] m_w_s2_htrans_i_d;
reg [14:0] DW_counter_mem_part [MEM_PART-1:0];
wire [MEM_PART-1 : 0] mem_part_sel;
reg [MEM_PART-1 : 0] mem_part_sel_d;
reg [MEM_PART-1 : 0] mem_part_sel_2d;
wire [16:0] mem_part_depth_range [MEM_PART*2:0];
reg [MEM_PART-1:0] full_LRAM;
reg [MEM_PART-1:0] rd_en;
wire rd_en_ored;
wire [31:0] m_w_s2_haddr_q;
reg [31:0] m_w_s2_haddr_d;
reg [1:0] m_w_s2_htrans_q;
reg [NO_LANES*64-1:0] m_w_s2_hwdata_q;
assign rd_done_check = ((DMA_read_size == rd_addr) && (|(rd_addr)))? 1'b1 : 1'b0;
assign m_w_s2_hready_o  = 1'b1;
assign m_w_s2_hresp_o   = 1'b0;

assign m_w_s2_haddr_q = m_w_s2_haddr_i - 16'h3000;
always @(posedge clk_i )
begin 
    m_w_s2_haddr_d    <= m_w_s2_haddr_q;
	m_w_s2_htrans_q   <= m_w_s2_htrans_i;
	m_w_s2_hwdata_q   <= m_w_s2_hwdata_i;
end 
// generating the size value 
genvar i;
generate
for(i=0; i <= MEM_PART; i = i +1) begin : range
assign 	mem_part_depth_range[i] = (MEM_PART_DEPTH * i);
end 
endgenerate

genvar idx;
generate 
for (idx =0;idx < MEM_PART; idx = idx +1) begin : generate_mem_flag_instance
// selection or LRAM on the basis of addresses 
// Address decoding
assign 	mem_part_sel[idx] = ((m_w_s2_haddr_d[17:12] >= ((ADDR_RANGE[17:12] * idx))) & (m_w_s2_haddr_d[17:12] < ((ADDR_RANGE[17:12] * (idx+1))))) ? 1'b1 : 1'b0;
//16:12,16:11;

always @(posedge clk_i)
begin
    mem_part_sel_d[idx]  <= mem_part_sel[idx];
	mem_part_sel_2d[idx]  <= mem_part_sel_d[idx];
end
// Counting number of locations on the basis of address selection
always @(posedge clk_i or negedge rstn_i)
begin 
    if ((!rstn_i) | DMA_read_size_valid)
	    DW_counter_mem_part[idx]     <= 15'd0; 
	else 
	begin 
	    if (wr_en & (mem_part_sel[idx] | mem_part_sel_d[idx] | mem_part_sel_2d[idx] ))
		    DW_counter_mem_part[idx]     <= DW_counter_mem_part[idx] + 1'b1;
		else 
		    DW_counter_mem_part[idx]     <= DW_counter_mem_part[idx];
	end 
end 

// generating full signal on the basis of DW written into ram part//(DW_counter_mem_part[idx] + mem_part_depth_range[idx]) == mem_part_depth_range[idx+1]) 
always @(*)
begin 
    if ((((DW_counter_mem_part[idx]  + mem_part_depth_range[idx]) == mem_part_depth_range[idx+1]) || ((DW_counter_mem_part[idx]  + mem_part_depth_range[idx]) == (DMA_read_size[17:0]))) && (|(DW_counter_mem_part[idx])))
	    full_LRAM[idx] = 1'b1;
	else 
	    full_LRAM[idx] = 1'b0;
end 



// generating read enable signal for RAM
always @(posedge clk_i  or negedge rstn_i)
begin 
    if (!rstn_i)
	    rd_en[idx]   <= 1'b0;
	else 
	begin 
	    if (full_LRAM[idx] && rd_addr_less_than_size && (rd_addr < mem_part_depth_range[idx+1]) && (rd_addr >= mem_part_depth_range[idx]))
		    rd_en[idx]   <= 1'b1;
		else 
		    rd_en[idx]   <= 1'b0;
	end 
end 
end 
endgenerate

assign rd_addr_less_than_size = (rd_addr  < DMA_read_size);

// selecting this memory if any of the memory part is selected
assign mem_sel = |(mem_part_sel);
//delay statment
always @(posedge clk_i  or negedge rstn_i)
begin 
    if (!rstn_i)
	begin
	    m_w_s2_htrans_i_d   <= 2'b00;
		mem_sel_d           <= 1'b0;
	end
	else
    begin		
	    m_w_s2_htrans_i_d   <= m_w_s2_htrans_q;
		mem_sel_d           <= mem_sel;
	end
end 

//writing into ram
always @(posedge clk_i)
begin 
    if (mem_sel_d & (|(m_w_s2_htrans_i_d)))
	begin 
	    wr_en    <= 1'b1;
		wr_addr  <= local_ram_addr[AWID+4:5];
		wr_data  <=  m_w_s2_hwdata_q;
	end 
	else 
	begin 
	    wr_en    <= 1'b0;
	    wr_addr  <= {AWID{1'b0}};
	    wr_data  <= {(NO_LANES*64-1){1'b0}};
	end 
end 

always @(posedge clk_i)
    local_ram_addr <= m_w_s2_haddr_d;
	
// depending upon the read enable increment the address for read port.
assign rd_en_ored = |(rd_en);
reg rd_en_ored_d;
reg rd_data_valid_i;
always @(posedge clk_i or negedge rstn_i)
begin 
    if (!rstn_i)
	begin 
	    rd_addr          <= {AWID{1'b0}};
		rd_data_valid_i    <= 1'b0;
		rd_en_ored_d     <= 1'b0;
	end 
	else 
	begin 
	    rd_en_ored_d    <= (rd_en_ored & rd_addr_less_than_size);
	    rd_data_valid_i    <= rd_en_ored_d;
        if (DMA_read_size_valid)
		    rd_addr      <= {AWID{1'b0}};
		else if (rd_en_ored & rd_addr_less_than_size)
		    rd_addr      <= rd_addr + 1'b1;
		else 
		    rd_addr      <= rd_addr;
	end 
end 

always @(posedge clk_i)
begin 
    rd_data   <= rd_data_i;
	rd_data_valid <= rd_data_valid_i;
end 

localparam TOTAL_DATA_WIDTH = NO_LANES*64;
localparam DEPTH = (256*2048)/TOTAL_DATA_WIDTH;
localparam ADDR_LANES = clog2(DEPTH);
localparam DATA_WIDTH = clog2(TOTAL_DATA_WIDTH);

true_dp_ram  #(
	.ADDR_DEPTH_A(DEPTH),
	.DATA_WIDTH_A(TOTAL_DATA_WIDTH),
	.ADDR_DEPTH_B(DEPTH),
	.DATA_WIDTH_B(TOTAL_DATA_WIDTH),
	.ADDR_LANES  (ADDR_LANES),
	.DATA_WIDTH	(DATA_WIDTH)
)	
	TDPBRAM_inst
(
    .clk_a_i(clk_i ),
    .clk_b_i(clk_i ),
    .rst_a_i(~rstn_i ),
    .rst_b_i(~rstn_i ),
    .clk_en_a_i(1'b1 ),
    .clk_en_b_i(1'b1 ),
    .wr_en_a_i(wr_en ),
    .wr_en_b_i(1'b0 ),
    .wr_data_a_i(wr_data ),
    .addr_a_i   (wr_addr ),
    .rd_data_a_o( ),
    .wr_data_b_i( 64'd0),
    .addr_b_i   (rd_addr ),
    .rd_data_b_o(rd_data_i )
);




endmodule

