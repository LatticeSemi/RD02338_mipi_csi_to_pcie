`timescale 1ps/1ps

module pcie_ep_mem_32bit #(
    parameter DATA_WIDTH     = 32,
	parameter SERIES_PATTERN = 1,
	parameter NUM_PACKETS    = 16
	)
	(
    input                       clk,
	input                       rst_n,
	// write port 
    input      [DATA_WIDTH-1:0] wr_data,                                        
    input                       wr_en,
	output                      wr_busy,
	input      [13:0]           wr_addr,
	input      [7:0]            wr_be,
	//input      [31:0]           req_addr,
	//read port 
	input      [13:0]           rd_addr,
	input                       vc_tx_ready,
	input      [3:0]            rd_be,
	input                       rd_en,
	output reg [DATA_WIDTH-1:0] rd_data,
    output reg                  write_data_check,
	input                       vc_rx_valid_i,
	input      [12:0]           vc_rx_cmd_data
);

reg vc_rx_valid_i_d;
reg vc_rx_valid_i_2d;
reg vc_rx_valid_i_3d;
reg [31:0] wr_data_d;
reg wr_en_d;
wire wr_en_redge;
reg wr_en_redge_d;
wire wr_en_fedge;

reg rd_en_d;
wire rd_en_redge;
reg rd_en_redge_d;
wire rd_en_fedge;

reg [13:0] addr_cntr;
reg [13:0] addr_cntr_d;
reg        write_en;
wire [13:0] addr_wr;
reg  [13:0] addr_wr_d;

reg [13:0] wr_addr_d;
reg [13:0] wr_addr_2d;
reg [13:0] wr_addr_3d;

reg [DATA_WIDTH-1:0] rd_data_i_d ;
reg [DATA_WIDTH-1:0] rd_data_i_delay;
reg [DATA_WIDTH-1:0] rd_data_i_delay_1;

reg clk_en_flag_0;
reg clk_en_flag_1;

reg wr_en_ram_0;
reg wr_en_ram_1;

reg [DATA_WIDTH-1:0] wr_data_ram_0;
reg [DATA_WIDTH-1:0] mem_wr_data_ram_0;
reg [DATA_WIDTH-1:0] mem_wr_data_ram_1;
reg [DATA_WIDTH-1:0] wr_data_ram_1;

wire[13:0] addr_ram;
reg [13:0] addr_ram_0;
reg [13:0] addr_ram_1;

reg wr_en_ram;
reg wr_en_ram_d;
reg rd_en_2d;
reg [DATA_WIDTH-1:0] wr_data_ram;     // The data is delayed by two(2) clock cycle as of data from PCIe IP 
reg [DATA_WIDTH-1:0] wr_data_ram_d;
wire [DATA_WIDTH-1:0] rd_data_i;
wire [DATA_WIDTH-1:0] rd_data_i_1;

wire [3:0]inc_data;
assign inc_data = (DATA_WIDTH/32);
wire [DATA_WIDTH-1:0] incremental_data;
assign incremental_data = (SERIES_PATTERN) ? ({(DATA_WIDTH/32){28'h0000_000,inc_data}}) : ({(DATA_WIDTH/32){32'h0000_0000}});
reg incorrect_write_data;
integer counter_packet;

//Write data Checker logic

always @(posedge clk) begin
	if(~rst_n) begin
		counter_packet <= 0;
		incorrect_write_data <= 1'b0;
		write_data_check <= 1'b0;
		wr_data_ram_d <= {(DATA_WIDTH){1'b0}};
		wr_en_ram_d   <= 1'b0;
		vc_rx_valid_i_d  <= 1'b0;
		vc_rx_valid_i_2d <= 1'b0;
		vc_rx_valid_i_3d <= 1'b0;
	end 
	else begin
		wr_data_ram_d <= wr_data_ram;
		wr_en_ram_d   <= wr_en_ram;		
		vc_rx_valid_i_d <= vc_rx_valid_i;
		vc_rx_valid_i_2d <= vc_rx_valid_i_d;
		vc_rx_valid_i_3d <= vc_rx_valid_i_2d;
		
		if((wr_en_ram_d == 1'b1 && wr_en_ram == 1'b1) && (wr_data_ram != wr_data_ram_d + incremental_data)&&(vc_rx_valid_i_3d == 1'b1)) begin
			incorrect_write_data <= 1'b1;
		end 
		else begin
			incorrect_write_data <= incorrect_write_data;
		end 
		
		if(wr_en_ram_d == 1'b1 && wr_en_ram == 1'b0) begin
			counter_packet <= counter_packet + 1;
		end 
		else begin
			counter_packet <= counter_packet;
		end 
		
		if((counter_packet == NUM_PACKETS) && (incorrect_write_data == 1'b0)) begin
			write_data_check <= 1'b1;
		end 
		else begin
			write_data_check <= write_data_check;
		end 
		
		if((counter_packet == NUM_PACKETS) && (wr_en_ram_d == 1'b0 && wr_en_ram == 1'b1)) begin
			wr_data_ram_d <= {(DATA_WIDTH){1'b0}};
			wr_en_ram_d   <= 1'b0;
			counter_packet <= 0;
			incorrect_write_data <= 1'b0;
			write_data_check <= 1'b0;
		end 

	end 
end

//RAM Logic
always @(*) 
begin 
    if (rd_en_redge_d) 
	begin 
	    if (rd_be[0]) rd_data[7:0]     = rd_data_i_d[7:0];
		else          rd_data[7:0]     = 8'b0;
	    if (rd_be[1]) rd_data[15:8]    = rd_data_i_d[15:8];
		else          rd_data[15:8]    = 8'b0;
	    if (rd_be[2]) rd_data[23:16]   = rd_data_i_d[23:16];
		else          rd_data[23:16]   = 8'b0;
	    if (rd_be[3]) rd_data[31:24]   = rd_data_i_d[31:24];
		else          rd_data[31:24]   = 8'b0;
	end 
	else 
	begin 
	    rd_data   = rd_data_i_d;
	end 
end 

always @(*)begin
if (rd_en & clk_en_flag_0) begin
    if(addr_cntr==14'h000)
	   rd_data_i_d = rd_data_i;
    else if(addr_cntr_d == addr_cntr)
       rd_data_i_d = rd_data_i_delay;                                   
    else 
       rd_data_i_d = rd_data_i;                                          
end
if (rd_en & clk_en_flag_1) begin
    if(addr_cntr==14'h000)
	   rd_data_i_d = rd_data_i_1;
    else if(addr_cntr_d == addr_cntr)
       rd_data_i_d = rd_data_i_delay_1;                                   
    else 
       rd_data_i_d = rd_data_i_1;                                          
end 
end

assign wr_busy  = wr_en | wr_en_d;
assign wr_en_redge = wr_en & (~wr_en_d);
assign wr_en_fedge = (~wr_en) & (wr_en_d);
assign rd_en_fedge = (~rd_en) & (rd_en_d);
assign rd_en_redge = (rd_en) & (~rd_en_d);                
assign addr_wr     = (addr_cntr + wr_addr[13:0]);
assign addr_ram    = (wr_en_ram) ? addr_wr : (addr_cntr + rd_addr[13:0]);


always @(posedge clk) begin
  addr_cntr_d       <= addr_cntr;
  wr_en_d           <= wr_en;
  write_en          <= wr_en;
  wr_en_redge_d     <= wr_en_redge;
  rd_en_d           <= rd_en;
  rd_en_redge_d     <= rd_en_redge;
  addr_wr_d         <= addr_wr;
  rd_data_i_delay   <= rd_data_i;
  rd_data_i_delay_1 <= rd_data_i_1;
end   
  
always @(posedge clk) begin 
    if (~rst_n) begin 
	    addr_cntr     <= 14'd0;
	    wr_data_ram   <= 32'd0;
	    wr_en_ram     <= 1'b0;
		
	end 
	else begin 
	    if(wr_en_d)begin
           wr_data_ram    <= wr_data;
		   wr_en_ram      <= 1'b1;		
		  if (wr_en_fedge )begin   					
		    addr_cntr      <= 14'd0;
			wr_en_ram      <= 1'b0;
		  end else if(vc_rx_valid_i_d)begin 
		    addr_cntr  <= addr_cntr + 14'd4;
		  end else addr_cntr <= addr_cntr;
		end 
		
	    else if (~vc_tx_ready) begin            
	         addr_cntr   <= addr_cntr ;
		end 
		
   		else if (rd_en) begin 
		    addr_cntr     <= addr_cntr  + 14'd4;
		end 
		
		else if (rd_en_fedge) begin                                
			  addr_cntr   <= 14'd0;
		end 
		
		else begin 
		    addr_cntr     <= addr_cntr;
	        wr_data_ram   <= 32'd0;
	        wr_en_ram     <= 1'b0;
		end 
	end 
end 

always @(posedge clk) begin 
if(~rst_n)
   begin 
   clk_en_flag_0 <=1'b0;
   clk_en_flag_1 <=1'b0;
   wr_data_d     <=0;
   end
else 
   begin
    wr_data_d <= wr_data;
    //if (vc_rx_cmd_data[0] == 1)
    //if (req_addr == bar_0_address)
    //begin
    clk_en_flag_0 <=1'b1;
    clk_en_flag_1 <=1'b0;
    //end
    // else if (vc_rx_cmd_data[1] == 1)
    //else if (req_addr == bar_1_address)
    //begin
    //clk_en_flag_0 <=1'b0;
    //clk_en_flag_1 <=1'b1;
    // end
    // else
    // begin
    	// clk_en_flag_0 <=clk_en_flag_0;
    	// clk_en_flag_1 <=clk_en_flag_1;
    // end
   end
end

always @(*)begin
if (clk_en_flag_0==1)
   begin
    wr_en_ram_0       = wr_en_d;
	mem_wr_data_ram_0 = wr_data_d;
	addr_ram_0        = addr_ram;
   end
else if (clk_en_flag_1==1)
   begin
    	wr_en_ram_1       = wr_en_d;
	mem_wr_data_ram_1 = wr_data_d;
	addr_ram_1        = addr_ram;
   end 
else 
   begin
    	wr_en_ram_0       = 1'b0;
	mem_wr_data_ram_0 = 32'd0;
	addr_ram_0        = 14'd0;
    	wr_en_ram_1       = 1'b0;
    	mem_wr_data_ram_1 = 32'd0;
	addr_ram_1        = 14'd0;
   end
end

ep_mem_ram_32bit bar0_memory_inst (
    .clk_i(clk),
    .rst_i(1'b0),
    .ben_i(4'hF),
    .clk_en_i(clk_en_flag_0),                                                
    .wr_en_i(wr_en_ram_0), 
    .wr_data_i(mem_wr_data_ram_0),                                          
    .addr_i(addr_ram_0[13:2]),                                    
    .rd_data_o(rd_data_i)                                              
);

ep_mem_ram_32bit bar1_memory_inst (
    .clk_i(clk),
    .rst_i(1'b0),
    .ben_i(4'hF),
    .clk_en_i(clk_en_flag_1),                                                
    .wr_en_i(wr_en_ram_1), 
    .wr_data_i(mem_wr_data_ram_1),                                          
    .addr_i(addr_ram_1[13:2]),                                    
    .rd_data_o(rd_data_i_1)                                              
);

endmodule
