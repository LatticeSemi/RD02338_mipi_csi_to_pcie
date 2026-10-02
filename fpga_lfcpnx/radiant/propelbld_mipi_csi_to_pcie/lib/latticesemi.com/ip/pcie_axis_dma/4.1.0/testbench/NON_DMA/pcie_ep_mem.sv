
`timescale 1ps/1ps

module pcie_ep_mem #(
    parameter DATA_WIDTH     = 32,
	parameter SERIES_PATTERN = 1,
	parameter NUM_PACKETS    = 16,
	parameter BAR1_UNUSED   = 1,    // KD: use only bar 0
	parameter MEM_BYTES     = 4096, // KD: total memory size in bytes
	parameter DW_ALIGN_RAM  = 0     // KD: multi segment ram
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
	input [(DATA_WIDTH/32)-1:0] wr_dw_en, // KD
	input                       wr_en_last, // KD 
	input      [31:0]           req_addr,
	//read port 
	input      [13:0]           rd_addr,
	input                       vc_tx_ready,
	input      [3:0]            rd_be,
	input                       rd_en,
	input                       rd_en_last, // KD
	output reg [DATA_WIDTH-1:0] rd_data,
    output reg                  write_data_check,
	input                       vc_rx_valid_i,
    input      [31:0]           bar_0_address,
    input      [31:0]           bar_1_address
);
// KD
localparam ADD_BIT_HIGH = $clog2(MEM_BYTES) - 1; // total mem byte address msb 
localparam N_SEG  = DATA_WIDTH/32;    // number of 1dw segment in DW_ALIGN_RAM mode
localparam DW_ALIGN_SEL_BITS = $clog2(DATA_WIDTH/32); // selector bit size for different segment

reg vc_rx_valid_i_d;
reg vc_rx_valid_i_2d;
reg vc_rx_valid_i_3d;

// KD
wire wr_en_1st;
reg [7:0] wr_be_d;
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

// KD
reg [N_SEG-1:0] wr_en_ram_x;
reg [(4*N_SEG)-1:0] wr_be_ram_x;
reg [N_SEG-1:0][10:0] addr_ram_x;
wire [N_SEG-1:0] wr_fbe_pos, wr_lbe_pos;
wire [(2*N_SEG)-1:0] tmp_wr_dw_en_ram, wr_dw_en_clone;
wire [(2*N_SEG)-1:0] tmp_wr_fbe_pos_ram, wr_fbe_pos_clone;
wire [(2*N_SEG)-1:0] tmp_wr_lbe_pos_ram, wr_lbe_pos_clone;
wire [(2*DATA_WIDTH)-1:0] tmp_wr_data_ram, wr_data_clone, rd_data_clone;
reg  [DW_ALIGN_SEL_BITS+1:2] addr_ram_d, addr_ram_2d;
wire [13:0] addr_rd;
wire [13:0] addr_wr;
reg  [13:0] addr_wr_d;

reg [13:0] wr_addr_d;
reg [13:0] wr_addr_2d;
reg [13:0] wr_addr_3d;

// KD
reg [DATA_WIDTH-1:0] wr_data_d;
reg [DATA_WIDTH-1:0] rd_data_i_d ;
reg [DATA_WIDTH-1:0] rd_data_i_delay;
reg [DATA_WIDTH-1:0] rd_data_i_delay_1;

reg clk_en_flag_0;
reg clk_en_flag_1;

reg wr_en_ram_0;
reg wr_en_ram_1;

reg [DATA_WIDTH-1:0] wr_data_ram_0;
reg [DATA_WIDTH-1:0] wr_data_ram_1;

// KD wire[13:0] addr_ram;
reg [13:0] addr_ram;
reg [13:0] addr_ram_0;
reg [13:0] addr_ram_1;

reg wr_en_ram;
reg wr_en_ram_d;
reg rd_en_2d;
reg [DATA_WIDTH-1:0] rd_data_ram; // KD
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
generate 

// KD if(DATA_WIDTH == 512)
if((DATA_WIDTH == 512) || (DATA_WIDTH == 256) || (DATA_WIDTH == 128) || (DATA_WIDTH == 64))
begin 

/* KD: there are bugs here. can only work for fbe must be 0xF. no real use
   case for read byte enable anyway. return all data are good
always @(*) 
begin 
    if (rd_en_redge) 
	begin 
	    if (rd_be[0]) rd_data[127:0]     = rd_data_i_d[127:0];
		else          rd_data[127:0]     = 128'b0;
	    if (rd_be[1]) rd_data[256:128]   = rd_data_i_d[256:128];
		else          rd_data[256:128]   = 128'b0;                    
		if (rd_be[2]) rd_data[384:257]  = rd_data_i_d[384:257];
		else          rd_data[384:257]  = 128'b0;                      
		if (rd_be[3]) rd_data[511:385]  = rd_data_i_d[511:385];
		else          rd_data[511:385]  = 128'b0;                       
	end 
	else 
	begin 
	    rd_data   <= rd_data_i_d;
	end 
end 
*/
assign rd_data = rd_data_i_d;

if (ADD_BIT_HIGH < 13) begin // KD
assign addr_cntr[13:ADD_BIT_HIGH+1] = '0;
assign addr_ram [13:ADD_BIT_HIGH+1] = '0; 
assign addr_wr  [13:ADD_BIT_HIGH+1] = '0;
assign addr_rd  [13:ADD_BIT_HIGH+1] = '0;
end

always @(*)begin
if (rd_en & clk_en_flag_0) begin
    // if(addr_cntr==14'h000)
    if(addr_cntr[ADD_BIT_HIGH:0]=={(ADD_BIT_HIGH+1){1'b0}})
	   rd_data_i_d = rd_data_i;
    // KD else if(addr_cntr_d == addr_cntr)
    else if(addr_cntr_d[ADD_BIT_HIGH:0] == addr_cntr[ADD_BIT_HIGH:0])
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

assign wr_busy     = wr_en | wr_en_d;
assign wr_en_redge = wr_en & (~wr_en_d);
assign wr_en_fedge = (~wr_en) & (wr_en_d);
assign rd_en_fedge = (~rd_en) & (rd_en_d);
assign rd_en_redge = (rd_en) & (~rd_en_d);
// KD assign addr_wr     = (addr_cntr + wr_addr_2d[13:0]);
// KD assign addr_ram    = (wr_en_ram) ? addr_wr_d : (addr_cntr + rd_addr[13:0]);
assign addr_wr[ADD_BIT_HIGH:0] = addr_cntr[ADD_BIT_HIGH:0] + wr_addr[ADD_BIT_HIGH:0];
assign addr_rd[ADD_BIT_HIGH:0] = addr_cntr[ADD_BIT_HIGH:0] + rd_addr[ADD_BIT_HIGH:0];
assign wr_en_1st = ~(| addr_cntr[ADD_BIT_HIGH:0]) & wr_en;

always @(posedge clk) begin
  addr_cntr_d       <= addr_cntr;
  addr_wr_d         <= addr_wr;
  wr_addr_d         <= wr_addr;
  wr_addr_2d        <= wr_addr_d;
  wr_addr_3d        <= wr_addr_2d;

  // KD wr_en_d           <= wr_en;
  wr_data_d         <= wr_data; 
  wr_en_redge_d     <= wr_en_redge;
  rd_en_d           <= rd_en;
  rd_en_redge_d     <= rd_en_redge;
  rd_data_i_delay   <= rd_data_i;
  if (BAR1_UNUSED==0) begin // KD
    rd_data_i_delay_1 <= rd_data_i_1;
  end // KD
end   
  
always @(posedge clk) begin 
    if (~rst_n) begin 
	    // KD
	    wr_en_d <= '0; 
	    wr_be_d <= '0;
	    // KD addr_cntr     <= 14'd0;
	    addr_cntr[ADD_BIT_HIGH:0] <= '0;
	    addr_ram [ADD_BIT_HIGH:0] <= '0;
	    wr_data_ram <= '0;                                  
	    wr_en_ram   <= 1'b0;    

       // Flopping them to 0 upon reset - msanthi
       // Future optimization is to remove this and assign based on the formula in line 440
       // That will reduce the number of flops being used.
       for (int d=0; d<N_SEG; d++) begin
            addr_ram_x [d] <= 11'b0;
       end
       
	end 
	else begin 
	    // KD     	
	    wr_en_d <= wr_en;
	    wr_be_d <= wr_be;
	    
            if (wr_en_last | rd_en_last) addr_cntr[ADD_BIT_HIGH:0] <= '0;
	    else if (wr_en | rd_en) addr_cntr[ADD_BIT_HIGH:0] <= addr_cntr[ADD_BIT_HIGH:0] + (DATA_WIDTH/8); 

	    addr_ram [ADD_BIT_HIGH:0] <= wr_en? addr_wr [ADD_BIT_HIGH:0] : addr_rd [ADD_BIT_HIGH:0];
            wr_en_ram   <= wr_en;

	    addr_ram_d [DW_ALIGN_SEL_BITS+1:2] <= addr_ram[DW_ALIGN_SEL_BITS+1:2];
	    addr_ram_2d[DW_ALIGN_SEL_BITS+1:2] <= addr_ram_d[DW_ALIGN_SEL_BITS+1:2];

	    if (DW_ALIGN_RAM) begin
	      rd_data_ram[DATA_WIDTH-1:0] <= rd_data_clone >> {addr_ram_2d[DW_ALIGN_SEL_BITS+1:2],5'h00};
              wr_data_ram[DATA_WIDTH-1:0] <= tmp_wr_data_ram[(2*DATA_WIDTH)-1:DATA_WIDTH];

              for (int d=0; d<N_SEG; d++) begin
	        wr_en_ram_x[d] <= tmp_wr_dw_en_ram[N_SEG + d];
	        wr_be_ram_x[(d*4)+:4] <= tmp_wr_fbe_pos_ram[N_SEG + d]? wr_be_d[3:0] :
		                         tmp_wr_lbe_pos_ram[N_SEG + d]?	wr_be_d[7:4] : 
					 ~tmp_wr_dw_en_ram[N_SEG + d]? 4'h0 :
					 4'hF;

                addr_ram_x [d] <= wr_en? (addr_wr[DW_ALIGN_SEL_BITS+1:2] <= d)? addr_wr[ADD_BIT_HIGH:DW_ALIGN_SEL_BITS+2] : (addr_wr[ADD_BIT_HIGH:DW_ALIGN_SEL_BITS+2] + 1) : 
			                 (addr_rd[DW_ALIGN_SEL_BITS+1:2] <= d)? addr_rd[ADD_BIT_HIGH:DW_ALIGN_SEL_BITS+2] : (addr_rd[ADD_BIT_HIGH:DW_ALIGN_SEL_BITS+2] + 1);
              end  
            end
	    else begin
	      wr_data_ram <= wr_data;	    
            end

            /* KD
	    if (wr_en_d) begin 
		    if (wr_en_fedge )  					addr_cntr      <= 14'd0;
			else if(vc_rx_valid_i_d)              addr_cntr      <= addr_cntr + 14'd64;
			else 								addr_cntr 	   <= addr_cntr;
			wr_data_ram    <= wr_data;                                  
			wr_en_ram      <= 1'b1;
		end // if wr_en
		
		else if (~vc_tx_ready) begin                                         
	         addr_cntr   <= addr_cntr ;
		end 
		
   		else if (rd_en) begin 
		    addr_cntr     <= addr_cntr  + 14'd64;
		end 		  
		   
		else if (rd_en_fedge) begin 
			  addr_cntr   <= 14'd0;
		end 
		
		else begin 
		    addr_cntr     <= addr_cntr;
	        wr_data_ram   <= 512'd0;                                 
	        wr_en_ram     <= 1'b0;                                
		end 
	    */
	end 
end 

/*
always @(posedge clk) begin 

if(~rst_n)
   begin 
   clk_en_flag_0 <=1'b0;
   clk_en_flag_1 <=1'b0;
   end
else 
   begin
   if (req_addr == bar_0_address)
   begin
   clk_en_flag_0 <=1'b1;
   clk_en_flag_1 <=1'b0;
   end
   else if (req_addr == bar_1_address)
   begin
   clk_en_flag_0 <=1'b0;
   clk_en_flag_1 <=1'b1;
   end
   else
   begin
   clk_en_flag_0 <=clk_en_flag_0;
   clk_en_flag_1 <=clk_en_flag_1;
   end
end

end
*/

// KD optimized bar1 away
if (BAR1_UNUSED==0) begin // KD
always @(posedge clk) begin 

if(~rst_n)
   begin 
   clk_en_flag_0 <=1'b0;
   clk_en_flag_1 <=1'b0;
   end
else 
   begin
    clk_en_flag_0 <=1'b1;
    clk_en_flag_1 <=1'b0;
   end
end

always @(*)begin
if (clk_en_flag_0==1)
   begin
    wr_en_ram_0   = wr_en_ram;
	wr_data_ram_0 = wr_data_ram;
	addr_ram_0    = addr_ram;
   end
else if (clk_en_flag_1==1)
   begin
    wr_en_ram_1   = wr_en_ram;
	wr_data_ram_1 = wr_data_ram;
	addr_ram_1    = addr_ram;
   end 
else 
   begin
    wr_en_ram_0   = 1'b0;
	wr_data_ram_0 = 512'd0;
	addr_ram_0    = 14'd0;
    wr_en_ram_1   = 1'b0;
    wr_data_ram_1 = 512'd0;
	addr_ram_1    = 14'd0;
   end
end
end 
else begin
  assign clk_en_flag_0 = 1;
  assign clk_en_flag_1 = 0;
  assign wr_en_ram_0   = wr_en_ram;
  assign wr_data_ram_0 = wr_data_ram;
  // KD assign addr_ram_0    = addr_ram;
  assign addr_ram_0[ADD_BIT_HIGH:0] = addr_ram[ADD_BIT_HIGH:0];

end // KD	

// KD
if (BAR1_UNUSED==1) begin 
  assign rd_data_i_1 = '0;
end	
//==================================
if (DW_ALIGN_RAM) begin
  wire [DATA_WIDTH-1:0] tmp_rd_data;
  assign tmp_wr_data_ram    = wr_data_clone  << {addr_wr[DW_ALIGN_SEL_BITS+1:2],5'h00};
  assign tmp_wr_dw_en_ram   = wr_dw_en_clone <<  addr_wr[DW_ALIGN_SEL_BITS+1:2];
  assign tmp_wr_fbe_pos_ram = wr_fbe_pos_clone << addr_wr[DW_ALIGN_SEL_BITS+1:2]; 
  assign tmp_wr_lbe_pos_ram = wr_lbe_pos_clone << addr_wr[DW_ALIGN_SEL_BITS+1:2]; 

  assign wr_data_clone    = {wr_data,  wr_data};
  assign wr_dw_en_clone   = {wr_dw_en, wr_dw_en};
  assign wr_fbe_pos_clone = {wr_fbe_pos, wr_fbe_pos};
  assign wr_lbe_pos_clone = {wr_lbe_pos, wr_lbe_pos};

  assign wr_fbe_pos = {{(N_SEG-1){1'b0}}, wr_en_1st}; // dw pos where 1st be
  assign wr_lbe_pos = wr_en_last << ($countones(wr_dw_en) - 1);  // dw pos where last be. right shift 1

  assign rd_data_clone   = {tmp_rd_data, tmp_rd_data};
  assign rd_data_i = rd_data_ram;

  for (genvar d=0; d<N_SEG; d++) begin

    //assign addr_ram_x[d][10:ADD_BIT_HIGH-(DW_ALIGN_SEL_BITS+2)+1] = '0; //Equation enhanced by KD to ensure that there is no overlap with functional assignment from earlier

    ep_mem_ram_32bit bar0_memory_inst (
      .clk_i(clk),
      .rst_i(1'b0),
      .clk_en_i(1'b1),
      .ben_i(wr_be_ram_x[(d*4)+:4]),
      .wr_en_i(wr_en_ram_x[d]),
      .wr_data_i(wr_data_ram[(d*32)+:32]),
      .addr_i(addr_ram_x[d]),                                    
      .rd_data_o(tmp_rd_data[(d*32)+:32])
    );

  end // d
end	
else if(DATA_WIDTH == 512) begin
ep_mem_ram_512bit bar0_memory_inst (
    .clk_i(clk),
    .rst_i(1'b0),
    .clk_en_i(clk_en_flag_0),                                                
    .wr_en_i(wr_en_ram_0), 
    .wr_data_i(wr_data_ram_0),                                          
    //KD .addr_i({3'd0,addr_ram_0[13:5]}),                                    
    .addr_i(addr_ram_0[11:6]),                                    
    .rd_data_o(rd_data_i )                                              
);

// KD optimized bar1 away
if (BAR1_UNUSED==0) begin
ep_mem_ram_512bit bar1_memory_inst (
    .clk_i(clk),
    .rst_i(1'b0),
    .clk_en_i(clk_en_flag_1),                                                 
    .wr_en_i(wr_en_ram_1), 
    .wr_data_i(wr_data_ram_1),                                          
    .addr_i({3'd0,addr_ram_1[13:5]}),                                    
    .rd_data_o(rd_data_i_1)                                              
);
end 
end // 512
//==================================
else if(DATA_WIDTH == 256) begin
ep_mem_ram_256bit bar0_memory_inst (
    .clk_i(clk),
    .rst_i(1'b0),
    .clk_en_i(clk_en_flag_0),
    .wr_en_i(wr_en_ram_0),
    .wr_data_i(wr_data_ram_0),
    .addr_i(addr_ram_0[11:5]),
    .rd_data_o(rd_data_i )
);
end // 256
//==================================
else if(DATA_WIDTH == 128) begin
ep_mem_ram_128bit bar0_memory_inst (
    .clk_i(clk),
    .rst_i(1'b0),
    .clk_en_i(clk_en_flag_0),
    .wr_en_i(wr_en_ram_0),
    .wr_data_i(wr_data_ram_0),
    .addr_i(addr_ram_0[11:4]),
    .rd_data_o(rd_data_i )
);
end // 128
//==================================
else if(DATA_WIDTH == 64) begin
ep_mem_ram_64bit bar0_memory_inst (
    .clk_i(clk),
    .rst_i(1'b0),
    .clk_en_i(clk_en_flag_0),
    .wr_en_i(wr_en_ram_0),
    .wr_data_i(wr_data_ram_0),
    .addr_i(addr_ram_0[11:3]),
    .rd_data_o(rd_data_i )
);
end // 64
//==================================
end // 512,256,128,64

// KD old code below to be removed
else if(DATA_WIDTH == 256)
begin 

always @(*) 
begin 
    if (rd_en_redge) 
	begin 
	    if (rd_be[0]) rd_data[63:0]     = rd_data_i_d[63:0];
		else          rd_data[63:0]     = 64'b0;
	    if (rd_be[1]) rd_data[127:64]   = rd_data_i_d[127:64];
		else          rd_data[127:64]   = 64'b0;                    
		if (rd_be[2]) rd_data[191:128]  = rd_data_i_d[191:128];
		else          rd_data[191:128]  = 64'b0;                      
		if (rd_be[3]) rd_data[255:192]  = rd_data_i_d[255:192];
		else          rd_data[255:192]  = 64'b0;                       
	end 
	else 
	begin 
	    rd_data   <= rd_data_i_d;
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

assign wr_busy     = wr_en | wr_en_d;
assign wr_en_redge = wr_en & (~wr_en_d);
assign wr_en_fedge = (~wr_en) & (wr_en_d);
assign rd_en_fedge = (~rd_en) & (rd_en_d);
assign rd_en_redge = (rd_en) & (~rd_en_d);
assign addr_wr     = (addr_cntr + wr_addr_2d[13:0]);
assign addr_ram    = (wr_en_ram) ? addr_wr_d : (addr_cntr + rd_addr[13:0]);

always @(posedge clk) begin
  addr_cntr_d       <= addr_cntr;
  addr_wr_d         <= addr_wr;
  wr_addr_d         <= wr_addr;
  wr_addr_2d        <= wr_addr_d;
  wr_addr_3d        <= wr_addr_2d;
  wr_en_d           <= wr_en;
  wr_en_redge_d     <= wr_en_redge;
  rd_en_d           <= rd_en;
  rd_en_redge_d     <= rd_en_redge;
  rd_data_i_delay   <= rd_data_i;
  rd_data_i_delay_1 <= rd_data_i_1;
end   
  
always @(posedge clk) begin 
    if (~rst_n) begin 
	    addr_cntr     <= 14'd0;
	    wr_data_ram   <= 256'd0;                                  
	    wr_en_ram     <= 1'b0;                                   	
	end 
	else begin 
	    if (wr_en_d) begin 
		    if (wr_en_fedge )  					addr_cntr      <= 14'd0;
			else if(vc_rx_valid_i_d)              addr_cntr      <= addr_cntr + 14'd32;
			else 								addr_cntr 	   <= addr_cntr;
			wr_data_ram    <= wr_data;                                  
			wr_en_ram      <= 1'b1;
		end // if wr_en
		
		else if (~vc_tx_ready) begin                                         
	         addr_cntr   <= addr_cntr ;
		end 
		
   		else if (rd_en) begin 
		    addr_cntr     <= addr_cntr  + 14'd32;
		end 		  
		   
		else if (rd_en_fedge) begin 
			  addr_cntr   <= 14'd0;
		end 
		
		else begin 
		    addr_cntr     <= addr_cntr;
	        wr_data_ram   <= 256'd0;                                 
	        wr_en_ram     <= 1'b0;                                
		end 
	end 
end 


always @(posedge clk) begin 

if(~rst_n)
   begin 
   clk_en_flag_0 <=1'b0;
   clk_en_flag_1 <=1'b0;
   end
else 
   begin
   if (req_addr == bar_0_address)
   begin
   clk_en_flag_0 <=1'b1;
   clk_en_flag_1 <=1'b0;
   end
   else if (req_addr == bar_1_address)
   begin
   clk_en_flag_0 <=1'b0;
   clk_en_flag_1 <=1'b1;
   end
   else
   begin
   clk_en_flag_0 <=clk_en_flag_0;
   clk_en_flag_1 <=clk_en_flag_1;
   end
end

end

always @(*)begin
if (clk_en_flag_0==1)
   begin
    wr_en_ram_0   = wr_en_ram;
	wr_data_ram_0 = wr_data_ram;
	addr_ram_0    = addr_ram;
   end
else if (clk_en_flag_1==1)
   begin
    wr_en_ram_1   = wr_en_ram;
	wr_data_ram_1 = wr_data_ram;
	addr_ram_1    = addr_ram;
   end 
else 
   begin
    wr_en_ram_0   = 1'b0;
	wr_data_ram_0 = 256'd0;
	addr_ram_0    = 14'd0;
    wr_en_ram_1   = 1'b0;
    wr_data_ram_1 = 256'd0;
	addr_ram_1    = 14'd0;
   end
end
   
ep_mem_ram_256bit bar0_memory_inst (
    .clk_i(clk),
    .rst_i(1'b0),
    .clk_en_i(clk_en_flag_0),                                                
    .wr_en_i(wr_en_ram_0), 
    .wr_data_i(wr_data_ram_0),                                          
    .addr_i({3'd0,addr_ram_0[13:5]}),                                    
    .rd_data_o(rd_data_i )                                              
);

ep_mem_ram_256bit bar1_memory_inst (
    .clk_i(clk),
    .rst_i(1'b0),
    .clk_en_i(clk_en_flag_1),                                                 
    .wr_en_i(wr_en_ram_1), 
    .wr_data_i(wr_data_ram_1),                                          
    .addr_i({3'd0,addr_ram_1[13:5]}),                                    
    .rd_data_o(rd_data_i_1)                                              
);

end

else if(DATA_WIDTH == 128)
begin 

always @(*) 
begin 
    if (rd_en_redge) 
	begin 
	    if (rd_be[0]) rd_data[31:0]     = rd_data_i_d[31:0];
		else          rd_data[31:0]     = 32'b0;
	    if (rd_be[1]) rd_data[63:32]    = rd_data_i_d[63:32];
		else          rd_data[63:32]    = 32'b0;
	    if (rd_be[2]) rd_data[97:64]    = rd_data_i_d[97:64];
		else          rd_data[95:64]    = 32'b0;
	    if (rd_be[3]) rd_data[127:96]   = rd_data_i_d[127:96];
		else          rd_data[127:96]   = 32'b0;                       
	end 
	else 
	begin 
	    rd_data   <= rd_data_i_d;
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

assign wr_busy     = wr_en | wr_en_d;
assign wr_en_redge = wr_en & (~wr_en_d);
assign wr_en_fedge = (~wr_en) & (wr_en_d);
assign rd_en_fedge = (~rd_en) & (rd_en_d);
assign rd_en_redge = (rd_en) & (~rd_en_d);
assign addr_wr     = (addr_cntr + wr_addr_2d[13:0]);
assign addr_ram    = (wr_en_ram) ? addr_wr_d : (addr_cntr + rd_addr[13:0]);

always @(posedge clk) begin
  addr_cntr_d       <= addr_cntr;
  addr_wr_d         <= addr_wr;
  wr_addr_d         <= wr_addr;
  wr_addr_2d        <= wr_addr_d;
  wr_en_d           <= wr_en;
  wr_en_redge_d     <= wr_en_redge;
  rd_en_d           <= rd_en;
  rd_en_redge_d     <= rd_en_redge;
  rd_data_i_delay   <= rd_data_i;
  rd_data_i_delay_1 <= rd_data_i_1;
end   
  
always @(posedge clk) begin 
    if (~rst_n) begin 
	    addr_cntr     <= 14'd0;
	    wr_data_ram   <= 128'd0;                                  
	    wr_en_ram     <= 1'b0;
		//byte_en       <= 16'hFFFF;                                    	
	end 
	else begin 
	    if (wr_en_d) begin 
		    if (wr_en_fedge )  					addr_cntr      <= 14'd0;
			else if(vc_rx_valid_i_d)              addr_cntr      <= addr_cntr + 14'd16;
			else 								addr_cntr 	   <= addr_cntr;
			wr_data_ram    <= wr_data;                                  
			wr_en_ram      <= 1'b1;
		end // if wr_en
		
		else if (~vc_tx_ready) begin                                         
	         addr_cntr   <= addr_cntr ;
		end 
		
   		else if (rd_en) begin 
		    addr_cntr     <= addr_cntr  + 14'd16;
		end 		  
		   
		else if (rd_en_fedge) begin 
			  addr_cntr   <= 14'd0;
		end 
		
		else begin 
		    addr_cntr     <= addr_cntr;
	        wr_data_ram   <= 128'd0;                                 
	        wr_en_ram     <= 1'b0;                                
		end 
	end 
end 


always @(posedge clk) begin 

if(~rst_n)
   begin 
   clk_en_flag_0 <=1'b0;
   clk_en_flag_1 <=1'b0;
   end
else 
   begin
   if (req_addr == bar_0_address)
   begin
   clk_en_flag_0 <=1'b1;
   clk_en_flag_1 <=1'b0;
   end
   else if (req_addr == bar_1_address)
   begin
   clk_en_flag_0 <=1'b0;
   clk_en_flag_1 <=1'b1;
   end
   else
   begin
   clk_en_flag_0 <=clk_en_flag_0;
   clk_en_flag_1 <=clk_en_flag_1;
   end
end

end

always @(*)begin
if (clk_en_flag_0==1)
   begin
    wr_en_ram_0   = wr_en_ram;
	wr_data_ram_0 = wr_data_ram;
	addr_ram_0    = addr_ram;
   end
else if (clk_en_flag_1==1)
   begin
    wr_en_ram_1   = wr_en_ram;
	wr_data_ram_1 = wr_data_ram;
	addr_ram_1    = addr_ram;
   end 
else 
   begin
    wr_en_ram_0   = 1'b0;
	wr_data_ram_0 = 128'd0;
	addr_ram_0    = 14'd0;
    wr_en_ram_1   = 1'b0;
    wr_data_ram_1 = 128'd0;
	addr_ram_1    = 14'd0;
   end
end
   
ep_mem_ram_128bit bar0_memory_inst (
    .clk_i(clk),
    .rst_i(1'b0),
    .clk_en_i(clk_en_flag_0),                                                
    .wr_en_i(wr_en_ram_0), 
    .wr_data_i(wr_data_ram_0),                                          
    .addr_i({2'd0,addr_ram_0[13:4]}),                                    
    .rd_data_o(rd_data_i )                                              
);

ep_mem_ram_128bit bar1_memory_inst (
    .clk_i(clk),
    .rst_i(1'b0),
    .clk_en_i(clk_en_flag_1),                                                 
    .wr_en_i(wr_en_ram_1), 
    .wr_data_i(wr_data_ram_1),                                          
    .addr_i({2'd0,addr_ram_1[13:4]}),                                    
    .rd_data_o(rd_data_i_1)                                              
);

end

else if(DATA_WIDTH == 64)
begin

always @(*) 
begin 
    if (rd_en_redge) 
	begin 
	    if (rd_be[0]) rd_data[15:0]     = rd_data_i_d[15:0];
		else          rd_data[15:0]     = 16'b0;
	    if (rd_be[1]) rd_data[31:16]    = rd_data_i_d[31:16];
		else          rd_data[31:16]    = 16'b0;
	    if (rd_be[2]) rd_data[47:32]    = rd_data_i_d[47:32];
		else          rd_data[47:32]    = 16'b0;
	    if (rd_be[3]) rd_data[63:48]    = rd_data_i_d[63:48];
		else          rd_data[63:48]    = 16'b0;                         
	end 
	else 
	begin 
	    rd_data   <= rd_data_i_d;
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
assign addr_wr     = (addr_cntr + wr_addr_d[13:0]);
assign addr_ram    = (wr_en_ram) ? addr_wr_d : (addr_cntr + rd_addr[13:0]);

always @(posedge clk) begin
  addr_cntr_d       <= addr_cntr;
  wr_addr_d         <= wr_addr;
  wr_en_d           <= wr_en;
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
	    wr_data_ram   <= 64'd0;                                        
	    wr_en_ram     <= 1'b0;                                        		
	end 
	else begin 
	    if (wr_en_d) begin 
		    if (wr_en_fedge )  					addr_cntr      <= 14'd0;
			else if(vc_rx_valid_i_d)              addr_cntr      <= addr_cntr + 14'd8;
			else 								addr_cntr 	   <= addr_cntr;
			wr_data_ram    <= wr_data;                                    
			wr_en_ram      <= 1'b1;
		end // if wr_en
		
		else if (~vc_tx_ready) begin                                         
	         addr_cntr   <= addr_cntr ;
		end 
		
   		else if (rd_en) begin 
		    addr_cntr     <= addr_cntr  + 14'd8;
		end 		  
		   
		else if (rd_en_fedge) begin 
			  addr_cntr   <= 14'd0;
		end 
		
		else begin 
		    addr_cntr     <= addr_cntr;
	        wr_data_ram   <= 64'd0;                                     
	        wr_en_ram     <= 1'b0;                                
		end 
	end 
end 

always @(posedge clk) begin 
if(~rst_n)
   begin 
   clk_en_flag_0 <=1'b0;
   clk_en_flag_1 <=1'b0;
   end
else 
   begin
   if (req_addr == bar_0_address)
   begin
   clk_en_flag_0 <=1'b1;
   clk_en_flag_1 <=1'b0;
   end
   else if (req_addr == bar_1_address)
   begin
   clk_en_flag_0 <=1'b0;
   clk_en_flag_1 <=1'b1;
   end
   else
   begin
   clk_en_flag_0 <=clk_en_flag_0;
   clk_en_flag_1 <=clk_en_flag_1;
   end
end
end

always @(*)begin
if (clk_en_flag_0==1)
   begin
    wr_en_ram_0   = wr_en_ram;
	wr_data_ram_0 = wr_data_ram;
	addr_ram_0    = addr_ram;
   end
else if (clk_en_flag_1==1)
   begin
    wr_en_ram_1   = wr_en_ram;
	wr_data_ram_1 = wr_data_ram;
	addr_ram_1    = addr_ram;
   end 
else 
   begin
    wr_en_ram_0   = 1'b0;
	wr_data_ram_0 = 64'd0;
	addr_ram_0    = 14'd0;
    wr_en_ram_1   = 1'b0;
    wr_data_ram_1 = 64'd0;
	addr_ram_1    = 14'd0;
   end
end

ep_mem_ram_64bit bar0_memory_inst (
    .clk_i(clk),
    .rst_i(1'b0),
    .clk_en_i(clk_en_flag_0),                                                
    .wr_en_i(wr_en_ram_0), 
    .wr_data_i(wr_data_ram_0),                                          
    .addr_i({1'd0,addr_ram_0[13:3]}),                                    
    .rd_data_o(rd_data_i )                                              
);
	
//ep_mem_ram_64bit_1 bar1_memory_inst (
ep_mem_ram_64bit bar1_memory_inst (
    .clk_i(clk),
    .rst_i(1'b0),
    .clk_en_i(clk_en_flag_1),                                                 
    .wr_en_i(wr_en_ram_1), 
    .wr_data_i(wr_data_ram_1),                                          
    .addr_i({1'd0,addr_ram_1[13:3]}),                                    
    .rd_data_o(rd_data_i_1) 
);
 
end 

else //DATA_WIDTH == 32
begin

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
assign addr_ram    = (wr_en_ram) ? addr_wr_d : (addr_cntr + rd_addr[13:0]);


always @(posedge clk) begin
  addr_cntr_d       <= addr_cntr;
  wr_en_d           <= wr_en;
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
	    if (wr_en_d) begin 
		    if (wr_en_fedge )  					addr_cntr      <= 14'd0;
			else if(vc_rx_valid_i_d)              addr_cntr      <= addr_cntr + 14'd4;
			else 								addr_cntr 	   <= addr_cntr;
			wr_data_ram    <= wr_data;
			wr_en_ram      <= 1'b1;
	    end // if wr_en
		
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
   end
else 
   begin
    if (req_addr == bar_0_address)
    begin
    clk_en_flag_0 <=1'b1;
    clk_en_flag_1 <=1'b0;
    end
    else if (req_addr == bar_1_address)
    begin
    clk_en_flag_0 <=1'b0;
    clk_en_flag_1 <=1'b1;
    end
    else
    begin
    clk_en_flag_0 <=clk_en_flag_0;
    clk_en_flag_1 <=clk_en_flag_1;
    end
   end
end

always @(*)begin
if (clk_en_flag_0==1)
   begin
    wr_en_ram_0   = wr_en_ram;
	wr_data_ram_0 = wr_data_ram;
	addr_ram_0    = addr_ram;
   end
else if (clk_en_flag_1==1)
   begin
    wr_en_ram_1   = wr_en_ram;
	wr_data_ram_1 = wr_data_ram;
	addr_ram_1    = addr_ram;
   end 
else 
   begin
    wr_en_ram_0   = 1'b0;
	wr_data_ram_0 = 32'd0;
	addr_ram_0    = 14'd0;
    wr_en_ram_1   = 1'b0;
    wr_data_ram_1 = 32'd0;
	addr_ram_1    = 14'd0;
   end
end

ep_mem_ram_32bit bar0_memory_inst (
    .clk_i(clk),
    .rst_i(1'b0),
    .clk_en_i(clk_en_flag_0),                                                
    .wr_en_i(wr_en_ram_0), 
    .wr_data_i(wr_data_ram_0),                                          
    .addr_i(addr_ram_0[13:2]),                                    
    .rd_data_o(rd_data_i)                                              
);

ep_mem_ram_32bit bar1_memory_inst (
    .clk_i(clk),
    .rst_i(1'b0),
    .clk_en_i(clk_en_flag_1),                                                
    .wr_en_i(wr_en_ram_1), 
    .wr_data_i(wr_data_ram_1),                                          
    .addr_i(addr_ram_1[13:2]),                                    
    .rd_data_o(rd_data_i_1)                                              
);

end 

endgenerate

endmodule
