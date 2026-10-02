
`timescale 1ps/1ps

module pcie_rx_engine #(
   parameter DATA_WIDTH = 32,
   parameter NUM_OF_LANES = 1,
   parameter MIN_GEN = 1 // 1,2,3,4
)
(
input                        clk,
input                        rst_n,
// rx TLP interface
// output                       vc_rx_ready_o ,
output reg                   vc_rx_ready_o ,
input                        vc_rx_valid_i ,
input     [1:0]              vc_rx_sel_i ,      // 0 posted request, 1 non posted , 2 completion, 3 reserved
input     [12:0]             vc_rx_cmd_data_i ,
input                        vc_rx_sop_i ,
input     [DATA_WIDTH-1:0]   vc_rx_data_i,
input     [DATA_WIDTH/8-1:0] vc_rx_datap_i,
input vc_rx_eop_i ,
input                        vc_rx_err_ecrc_i,
input     [1:0]              vc_rx_f_i,          // function indicator from func 0 to function3 as only 4 function are supported
// rx TLP info                                   
output reg                   req_compl,          
input                        compl_done,         	
output reg [2:0]             req_tc,             // Memory Read TC
output reg                   req_td,             // Memory Read TD
output reg                   req_ep,             // Memory Read EP
output reg [1:0]             req_attr,           // Memory Read Attribute
output reg [9:0]             req_len,            // Memory Read Length (1DW)
output reg [15:0]            req_rid,            // Memory Read Requestor ID
output reg [9:0]             req_tag,            // Memory Read Tag
output reg [7:0]             req_be,             // Memory Read Byte Enables //DWBE
output reg [31:0]            req_addr,           // Memory Read Address
// memory interface.
output reg [DATA_WIDTH-1:0]  wr_data,         
output reg                   wr_en,
output reg [(DATA_WIDTH/32)-1:0] wr_dw_en, // KD
output reg                   wr_en_last,   // KD
input                        wr_busy
);

// KD
localparam FIRST_PYLD_DW = (DATA_WIDTH >= 128)? 3 : 1;

reg [4:0] state;
// encoding for state machine
localparam rst_state            = 5'b00000;
localparam sample_DW2           = 5'b00001;
localparam sample_DW3           = 5'b00010;
localparam sample_DW4           = 5'b00100;
localparam wait_state           = 5'b01000;
localparam sample_Data          = 5'b10000;
localparam wait_ready_state     = 5'b11000;
localparam wait_first_data_state= 5'b11100; 
// combination of format and type {FMT{1:0],TYPE[4:0]}
localparam MEM_RD32_FMT_TYPE    = 7'b00_00000;
localparam MEM_WR32_FMT_TYPE    = 7'b10_00000;
localparam MEM_RD64_FMT_TYPE    = 7'b01_00000;
localparam MEM_WR64_FMT_TYPE    = 7'b11_00000;

//reg [1:0] counter;
reg [6:0] tlp_type;
reg [9:0] DW_cntr;

reg [511:0] wr_data_512;
reg [255:0] wr_data_256;
reg [127:0] wr_data_128;
reg [63:0]  wr_data_64;
reg [31:0]  wr_data_32;

wire[31:0] data_word_1;
wire[31:0] data_word_2;
wire[31:0] data_word_3;
wire[31:0] data_word_4;
wire[31:0] data_word_5;
wire[31:0] data_word_6;
wire[31:0] data_word_7;
wire[31:0] data_word_8;
wire[31:0] data_word_9;
wire[31:0] data_word_10;
wire[31:0] data_word_11;
wire[31:0] data_word_12;
wire[31:0] data_word_13;
wire[31:0] data_word_14;
wire[31:0] data_word_15;
wire[31:0] data_word_16;

// reg vc_rx_valid_i_d;
reg vc_rx_eop_i_d; // KD
reg [DATA_WIDTH-1:0] vc_rx_data_i_d;

// Eg: @250MHz Gen1x1 need 8 clk to form each 64b, MPS = 64 * 64b = 512B
// MPS 512B
// WIDTH Gen      AccClk2MPS  
// 64    1,2,3,4  512,256,128,64
// 128   1,2,3,4  256,128,64, 32
// 256   1,2,3,4  128,64, 32, 16
// 512   1,2,3,4  64, 32, 16, 8
// reg [9:0] vc_rx_valid_dly_cnt;
wire vc_rx_ready_o_set;
wire vc_rx_ready_o_clr;
wire vc_rx_valid_accept;

assign vc_rx_ready_o_set  = (state == rst_state) & vc_rx_valid_i & vc_rx_sop_i; 
assign vc_rx_ready_o_clr  = vc_rx_valid_accept & vc_rx_eop_i; 
assign vc_rx_valid_accept = vc_rx_ready_o & vc_rx_valid_i; 

always @(posedge clk) begin
  if(!rst_n) begin
    vc_rx_ready_o  <= 1'b0;
    vc_rx_eop_i_d  <= 1'd0; 	  
    vc_rx_data_i_d <= '0;
  end  
  else begin
    vc_rx_ready_o <= vc_rx_ready_o_clr? 1'b0 : vc_rx_ready_o_set? 1'b1 : vc_rx_ready_o;

    if (vc_rx_ready_o) begin
      vc_rx_eop_i_d  <= vc_rx_eop_i;
      vc_rx_data_i_d <= vc_rx_data_i;
    end
  end  
end

/*
always @(posedge clk) begin 
vc_rx_valid_i_d <= vc_rx_valid_i;
vc_rx_data_i_d  <= vc_rx_data_i;
end
*/

generate 

// KD if(DATA_WIDTH == 512)
if(DATA_WIDTH >= 64) begin 
assign data_word_1[31:0]   = vc_rx_data_i[31:0];
assign data_word_2[31:0]   = vc_rx_data_i[63:32];
// KD
if(DATA_WIDTH >= 128) begin
assign data_word_3[31:0]   = vc_rx_data_i[95:64];
assign data_word_4[31:0]   = vc_rx_data_i[127:96];
end // KD
// KD
if(DATA_WIDTH >= 256) begin
assign data_word_5[31:0]   = vc_rx_data_i[159:128];
assign data_word_6[31:0]   = vc_rx_data_i[191:160];
assign data_word_7[31:0]   = vc_rx_data_i[223:192];
assign data_word_8[31:0]   = vc_rx_data_i[255:224];
end // KD
// KD
if(DATA_WIDTH >= 512) begin
assign data_word_9[31:0]   = vc_rx_data_i[287:256];
assign data_word_10[31:0]   = vc_rx_data_i[319:288];
assign data_word_11[31:0]   = vc_rx_data_i[351:320];
assign data_word_12[31:0]   = vc_rx_data_i[383:352];
assign data_word_13[31:0]   = vc_rx_data_i[415:384];
assign data_word_14[31:0]   = vc_rx_data_i[447:416];
assign data_word_15[31:0]   = vc_rx_data_i[479:448];
assign data_word_16[31:0]   = vc_rx_data_i[511:480];
end // KD

// KD: the base module will not work properly for the case of throttling.
// delay the start after each vc_rx_valid
// assign vc_rx_ready_o = (state == wait_state) ? 1'b0 : 1'b1;

/* KD
always @(posedge clk) begin 
    if(!rst_n)
	wr_data <= 512'd0;
    else 
        wr_data <= wr_data_512;
    end 		
*/
assign wr_data = wr_data_512;
    
always @(posedge clk) begin 
    if (!rst_n)
	begin 
	    req_tc       <= 3'b0;	
        req_td       <= 1'b0;
        req_ep       <= 1'b0;
        req_attr     <= 2'b0;
        req_len      <= 10'b0;
        req_rid      <= 16'b0;
        req_tag      <= 10'b0;
        req_be       <= 8'b0;
        req_addr     <= 32'b0;
	    state        <= rst_state;
		tlp_type     <= 7'b0;
		DW_cntr      <= 10'd0;
		wr_data_512  <= 512'd0;
		wr_en        <= 1'b0;
		wr_dw_en     <= '0;   // KD
		wr_en_last   <= 1'b0; // KD
		req_compl    <= 1'b0;
		
	end 
	else
	begin 
	   
	    case (state)
		    rst_state : begin 
		      wr_en      <= 1'b0; // KD
		      wr_dw_en   <= '0;   // KD
		      wr_en_last <= 1'b0; // KD

	            // KD if (vc_rx_valid_i) 
	            if (vc_rx_valid_accept) 
		        begin 
				    
		            if (vc_rx_sop_i) begin 
		        	    casex(vc_rx_data_i[6:0])
						
						    7'bx000000  : begin // mwr32 and mrd32
							    tlp_type     <= data_word_1[6:0];
								req_tc       <= data_word_1[14:12];
								req_td       <= data_word_1[23];
								req_ep       <= data_word_1[22];
								req_attr     <= data_word_1[21:20];
								req_len      <= {data_word_1[17:16], data_word_1[31:24]};
								req_rid      <= {data_word_2[7:0],data_word_2[15:8]};
								req_tag      <= {data_word_1[15], data_word_1[11], data_word_2[23:16]};
								req_be       <= data_word_2[31:24];
								// KD
								if (DATA_WIDTH > 64) begin 
								req_addr     <= {data_word_3[7:0],data_word_3[15:8],data_word_3[23:16],data_word_3[31:26],2'b00};
							        end // KD
								if ((vc_rx_data_i[6:0] == MEM_RD32_FMT_TYPE)) begin 
								
							           // KD		
								   if (DATA_WIDTH > 64) begin
					                           state          <= wait_state;
						                       req_compl      <= 1'b1;			   
                                                                   end
								   else begin
								     state <= sample_DW3;
						                     req_compl <= 1'b0;			   
                                                                   end
					            end // if tlp type is memory read					            
					            else if ((vc_rx_data_i[6:0] == MEM_WR32_FMT_TYPE)) begin 
   						                        // KD state          <= sample_Data;		
   						                        state <= (DATA_WIDTH > 64)? sample_Data : sample_DW3;		
									req_compl      <= 1'b0;
                                                			//KD wr_en<=1'b0;								
						                        //KD DW_cntr<=10'd1;	//KK: TODO: to check for 256-bit data width. May be 1 to 5 DW
									DW_cntr <= {data_word_1[17:16], data_word_1[31:24]};
							    end //for tlp type of memory write							    
								else 
                                begin
								    state           <= rst_state;             
								end 
								
							end // if rx tlp is memory read or memory write						
							
							default : begin // if other tlps
							    state    <= rst_state;
							end
						endcase
		        	end // if sop 
		        	else
		        	    state    <= rst_state;
		        end // if valid
				else 
				    state    <= rst_state;
			end // rst_state
          
		        // KD	
		        sample_DW3 : begin
                          if (DATA_WIDTH==64) begin
		          if (vc_rx_valid_accept) begin		  
                            req_addr     <= {data_word_1[7:0],data_word_1[15:8],data_word_1[23:16],data_word_1[31:26],2'b00};
			    if ((tlp_type == MEM_RD32_FMT_TYPE)) begin
         		      state <= wait_state;
                              req_compl <= 1'b1;
		            end
			    else if ((tlp_type == MEM_WR32_FMT_TYPE)) begin
                              state <= sample_Data;
                              req_compl <= 1'b0;
		            end  
		          end    
			  end
			end

			sample_Data : begin 
			  if (vc_rx_valid_accept | vc_rx_eop_i_d) begin // KD
			    //if (vc_rx_valid_i) begin	//KK: uncomment 
				    //if (req_len == DW_icntr + 10'd1) begin
				    // KD if ((req_len - DW_cntr) < 16) begin
				    wr_data_512 <= {vc_rx_data_i[(FIRST_PYLD_DW*32)-1:0],vc_rx_data_i_d[DATA_WIDTH-1:(FIRST_PYLD_DW*32)]};
				    if (DW_cntr <= (DATA_WIDTH/32)) begin
						// KD wr_data_512 <= {vc_rx_data_i[95:0],vc_rx_data_i_d[511:96]};
						wr_en       <= 1'b1; 
						wr_dw_en    <= (1 << DW_cntr) - 1;
				                wr_en_last  <= 1'b1;
						DW_cntr     <= 10'd0;
						state       <= wait_state;
					end // if only one or last DW 
					// KD else if (req_len > DW_cntr) begin 
					else begin 
					        wr_en         <= 1'b1;
						wr_dw_en      <= '1;
				                wr_en_last    <= 1'b0;
						// KD wr_data_512   <= {vc_rx_data_i[95:0],vc_rx_data_i_d[511:96]};
						state         <= sample_Data;
						// KD DW_cntr       <= DW_cntr + 10'd8;
						DW_cntr       <= DW_cntr - (DATA_WIDTH/32);
					end // if req_len > DW_cntr
					/* KD
					else begin
					        wr_en         <= 1'b0;
						state         <= wait_state;
						DW_cntr       <= DW_cntr;
					end 
					*/
			//	end // if valid	//KK: uncomment
				//else 
				 //   state    <= sample_Data;
			  end // KD   
			  else begin // KD
		            wr_en    <= 1'b0; // KD		  
			    wr_dw_en <= '0;   // KD
			  end // KD   

			end // sample_Data
						
			wait_state : begin 
				req_compl       <= 1'b0;
				wr_en           <= 1'b0;
				wr_dw_en        <= '0; // KD
	                        wr_en_last      <= 1'b0; // KD
			    DW_cntr         <= 10'd0;
				
				if ((tlp_type == MEM_RD32_FMT_TYPE) && compl_done)        state       <= rst_state; 
				// KD else if ((tlp_type == MEM_WR32_FMT_TYPE) && (!wr_busy))   state       <= rst_state; 
			        else if ((tlp_type == MEM_WR32_FMT_TYPE) && (!wr_busy)) begin
			      	  state      <= rst_state; 
			        end  
				// KD else                                                      state       <= wait_state;
								
			end //wait_state
			
			default : begin 
			    state          <= rst_state;
				DW_cntr        <= 10'd0;
			end  // default
		endcase
			
	end 
end 
end 

// KD old code below to be removed
else if(DATA_WIDTH == 256)
begin 
assign data_word_1[31:0]   = vc_rx_data_i[31:0];
assign data_word_2[31:0]   = vc_rx_data_i[63:32];
assign data_word_3[31:0]   = vc_rx_data_i[95:64];
assign data_word_4[31:0]   = vc_rx_data_i[127:96];
assign data_word_5[31:0]   = vc_rx_data_i[159:128];
assign data_word_6[31:0]   = vc_rx_data_i[191:160];
assign data_word_7[31:0]   = vc_rx_data_i[223:192];
assign data_word_8[31:0]   = vc_rx_data_i[255:224];

assign vc_rx_ready_o = (state == wait_state) ? 1'b0 : 1'b1;

always @(posedge clk) begin 
    if(!rst_n)
	    wr_data <= 256'd0;
    else 
        wr_data <= wr_data_256;
    end 		
 
always @(posedge clk) begin 
    if (!rst_n)
	begin 
	    req_tc       <= 3'b0;	
        req_td       <= 1'b0;
        req_ep       <= 1'b0;
        req_attr     <= 2'b0;
        req_len      <= 10'b0;
        req_rid      <= 16'b0;
        req_tag      <= 10'b0;
        req_be       <= 8'b0;
        req_addr     <= 32'b0;
	    state        <= rst_state;
		tlp_type     <= 7'b0;
		DW_cntr      <= 10'd0;
		wr_data_256  <= 256'd0;
		wr_en        <= 1'b0;
		req_compl    <= 1'b0;
		
	end 
	else
	begin 
	   
	    case (state)
		    rst_state : begin 
	            if (vc_rx_valid_i) 
		        begin 
				    
		            if (vc_rx_sop_i) begin 
		        	    casex(vc_rx_data_i[6:0])
						
						    7'bx000000  : begin // mwr32 and mrd32
							    tlp_type     <= data_word_1[6:0];
								req_tc       <= data_word_1[14:12];
								req_td       <= data_word_1[23];
								req_ep       <= data_word_1[22];
								req_attr     <= data_word_1[21:20];
								req_len      <= {data_word_1[17:16], data_word_1[31:24]};
								req_rid      <= {data_word_2[7:0],data_word_2[15:8]};
								req_tag      <= {data_word_1[15], data_word_1[11], data_word_2[23:16]};
								req_be       <= data_word_2[31:24];
								req_addr     <= {data_word_3[7:0],data_word_3[15:8],data_word_3[23:16],data_word_3[31:26],2'b00};
							
								if ((vc_rx_data_i[6:0] == MEM_RD32_FMT_TYPE)) begin 
					                           state          <= wait_state;
						                       req_compl      <= 1'b1;			   
					            end // if tlp type is memory read					            
					            else if ((vc_rx_data_i[6:0] == MEM_WR32_FMT_TYPE)) begin 
   						                        state          <= sample_Data;		
									req_compl      <= 1'b0;
                                                			wr_en<=1'b0;								
						                        DW_cntr<=10'd1;	//KK: TODO: to check for 256-bit data width. May be 1 to 5 DW
							    end //for tlp type of memory write							    
								else 
                                begin
								    state           <= rst_state;             
								end 
								
							end // if rx tlp is memory read or memory write						
							
							default : begin // if other tlps
							    state    <= rst_state;
							end
						endcase
		        	end // if sop 
		        	else
		        	    state    <= rst_state;
		        end // if valid
				else 
				    state    <= rst_state;
			end // rst_state
            
			sample_Data : begin 
			    //if (vc_rx_valid_i) begin	//KK: uncomment 
				    //if (req_len == DW_icntr + 10'd1) begin
				    if ((req_len - DW_cntr) < 4) begin
						wr_data_256 <= {vc_rx_data_i[95:0],vc_rx_data_i_d[255:96]};
						wr_en       <= 1'b1; 
						DW_cntr     <= 10'd0;
						state       <= wait_state;
					end // if only one or last DW 
					else if (req_len > DW_cntr) begin 
					        wr_en         <= 1'b1;
						wr_data_256   <= {vc_rx_data_i[95:0],vc_rx_data_i_d[255:96]};
						state         <= sample_Data;
						DW_cntr       <= DW_cntr + 10'd8;
					end // if req_len > DW_cntr
					else begin
					        wr_en         <= 1'b0;
						state         <= wait_state;
						DW_cntr       <= DW_cntr;
					end 
			//	end // if valid	//KK: uncomment
				//else 
				 //   state    <= sample_Data;
			end // sample_Data
						
			wait_state : begin 
				req_compl       <= 1'b0;
				wr_en           <= 1'b0;
			    DW_cntr         <= 10'd0;
				
				if ((tlp_type == MEM_RD32_FMT_TYPE) && compl_done)        state       <= rst_state; 
				else if ((tlp_type == MEM_WR32_FMT_TYPE) && (!wr_busy))   state       <= rst_state; 
				else                                                      state       <= wait_state;
								
			end //wait_state
			
			default : begin 
			    state          <= rst_state;
				DW_cntr        <= 10'd0;
			end  // default
		endcase
			
	end 
end 
end 

else if(DATA_WIDTH == 128)
begin 
//if (NUM_OF_LANES == 4) begin
assign data_word_1[31:0]   = vc_rx_data_i[31:0];
assign data_word_2[31:0]   = vc_rx_data_i[63:32];
assign data_word_3[31:0]   = vc_rx_data_i[95:64];
assign data_word_4[31:0]   = vc_rx_data_i[127:96];

assign vc_rx_ready_o = (state == wait_state) ? 1'b0 : 1'b1;

always @(posedge clk) begin 
    if(!rst_n)
	    wr_data <= 128'd0;
    else 
        wr_data <= wr_data_128;
    end 		
 
always @(posedge clk) begin 
    if (!rst_n)
	begin 
	    req_tc       <= 3'b0;	
        req_td       <= 1'b0;
        req_ep       <= 1'b0;
        req_attr     <= 2'b0;
        req_len      <= 10'b0;
        req_rid      <= 16'b0;
        req_tag      <= 10'b0;
        req_be       <= 8'b0;
        req_addr     <= 32'b0;
	    state        <= rst_state;
		tlp_type     <= 7'b0;
		DW_cntr      <= 10'd0;
		wr_data_128  <= 128'd0;
		wr_en        <= 1'b0;
		req_compl    <= 1'b0;
		
	end 
	else
	begin 
	   
	    case (state)
		    rst_state : begin 
	            if (vc_rx_valid_i) 
		        begin 
				    
		            if (vc_rx_sop_i) begin 
		        	    casex(vc_rx_data_i[6:0])
						
						    7'bx000000  : begin // mwr32 and mrd32
							    tlp_type     <= data_word_1[6:0];
								req_tc       <= data_word_1[14:12];
								req_td       <= data_word_1[23];
								req_ep       <= data_word_1[22];
								req_attr     <= data_word_1[21:20];
								req_len      <= {data_word_1[17:16], data_word_1[31:24]};
								req_rid      <= {data_word_2[7:0],data_word_2[15:8]};
								req_tag      <= {data_word_1[15], data_word_1[11], data_word_2[23:16]};
								req_be       <= data_word_2[31:24];
								req_addr     <= {data_word_3[7:0],data_word_3[15:8],data_word_3[23:16],data_word_3[31:26],2'b00};
							
						    if ((vc_rx_data_i[6:0] == MEM_RD32_FMT_TYPE)) begin 
					               state          	<= wait_state;
						       req_compl	<= 1'b1;			   
					            end // if tlp type is memory read					            
					            else if ((vc_rx_data_i[6:0] == MEM_WR32_FMT_TYPE)) begin 
   						       state       	<= sample_Data;		
						       req_compl	<= 1'b0;
                                                       wr_en 		<= 1'b0;		
						       DW_cntr 		<= 10'd1; //KK: change to 1 as 1st valid has 1 DW data. Orig: 10'd0
						    end //for tlp type of memory write							    
						    else begin
						       state            <= rst_state;             
						    end 
								
							end // if rx tlp is memory read or memory write						
							
							default : begin // if other tlps
							    state    <= rst_state;
							end
						endcase
		        	end // if sop 
		        	else
		        	    state    <= rst_state;
		        end // if valid
				else 
				    state    <= rst_state;
			end // rst_state
            
			sample_Data : begin 
			   if (vc_rx_valid_i) begin 
				    //if (req_len == DW_cntr + 10'd4) begin
				       //if (req_len == DW_cntr + 10'd1) begin
				       if ((req_len - DW_cntr) < 4) begin //KK: if less that 4DW left, this is the last data phase
						wr_data_128 <= {vc_rx_data_i[95:0],vc_rx_data_i_d[127:96]};
						wr_en       <= 1'b1; 
						DW_cntr     <= 10'd0;
						state       <= wait_state;
					end // if only one or last DW 
					else if (req_len > DW_cntr) begin 
					        wr_en         <= 1'b1;
						wr_data_128   <= {vc_rx_data_i[95:0],vc_rx_data_i_d[127:96]};
						state         <= sample_Data;
						DW_cntr       <= DW_cntr + 10'd4;
					end // if req_len > DW_cntr
					else begin
					        wr_en         <= 1'b0;
						state         <= wait_state;
						DW_cntr       <= DW_cntr;
					end 
			   end // if valid
			      else 
			         state    <= sample_Data;
			end // sample_Data
						
			wait_state : begin 
				req_compl       <= 1'b0;
				wr_en           <= 1'b0;
			    	DW_cntr         <= 10'd0;
				
				if ((tlp_type == MEM_RD32_FMT_TYPE) && compl_done)        state       <= rst_state; 
				else if ((tlp_type == MEM_WR32_FMT_TYPE) && (!wr_busy))   state       <= rst_state; 
				else                                                      state       <= wait_state;
								
			end //wait_state
			
			default : begin 
			    state          <= rst_state;
				DW_cntr        <= 10'd0;
			end  // default
		endcase
			
	end 
end

end 

else if(DATA_WIDTH == 64)
begin 
assign data_word_1[31:0]   = vc_rx_data_i[31:0];
assign data_word_2[31:0]   = vc_rx_data_i[63:32];

assign vc_rx_ready_o = (state == wait_state) ? 1'b0 : 1'b1;

always @(posedge clk) begin 
    if(!rst_n)
	    wr_data <= 64'd0;
    else 
        wr_data <= wr_data_64;
    end 		
 
always @(posedge clk) begin 
    if (!rst_n)
	begin 
	    req_tc       <= 3'b0;	
        req_td       <= 1'b0;
        req_ep       <= 1'b0;
        req_attr     <= 2'b0;
        req_len      <= 10'b0;
        req_rid      <= 16'b0;
        req_tag      <= 10'b0;
        req_be       <= 8'b0;
        req_addr     <= 32'b0;
	    state        <= rst_state;
		tlp_type     <= 7'b0;
		DW_cntr      <= 10'd0;
		wr_data_64   <= 64'd0;
		wr_en        <= 1'b0;
		req_compl    <= 1'b0;
		
	end 
	else
	begin 
	   
	    case (state)
		    rst_state : begin 
	            if (vc_rx_valid_i) 
		        begin 
				    
		            if (vc_rx_sop_i) begin 
		        	    casex(vc_rx_data_i[6:0])
						
						    7'bx000000  : begin // mwr32 and mrd32
							    tlp_type     <= data_word_1[6:0];
								req_tc       <= data_word_1[14:12];
								req_td       <= data_word_1[23];
								req_ep       <= data_word_1[22];
								req_attr     <= data_word_1[21:20];
								req_len      <= {data_word_1[17:16], data_word_1[31:24]};
								req_rid      <= {data_word_2[7:0],data_word_2[15:8]};
								req_tag      <= {data_word_1[15], data_word_1[11], data_word_2[23:16]};
								req_be       <= data_word_2[31:24];
								state        <= sample_DW2;
							end // if rx tlp is memory read or memory write						
							
							default : begin // if other tlps
							    state    <= rst_state;
							end
						endcase
		        	end // if sop 
		        	else
		        	    state    <= rst_state;
		        end // if valid
				else 
				    state    <= rst_state;
			end // rst_state
            
			sample_DW2 : begin 
			    if (vc_rx_valid_i) begin 
			        req_addr     <= {data_word_1[7:0],data_word_1[15:8],data_word_1[23:16],data_word_1[31:26],2'b00};
					if ((tlp_type == MEM_RD32_FMT_TYPE)) begin  
					    state          <= wait_state;
						req_compl      <= 1'b1;
					end // if tlp type is memory read
					else if ((tlp_type == MEM_WR32_FMT_TYPE)) begin 
					    state          <= sample_Data;
						req_compl      <= 1'b0;
						DW_cntr        <= 10'd0; //KK: TODO: to check for 64-bit data width
					end 
					else 
					   state  <= sample_DW2;
				end // 
				else 
				    state    <= sample_DW2;
			end
			
			sample_Data : begin 
			    if (vc_rx_valid_i) begin 
//				    if (req_len == DW_cntr + 10'd2) begin
						//wr_data_64  <= {vc_rx_data_i[31:0],vc_rx_data_i_d[63:32]};    izzat
			            if (req_len == DW_cntr + 10'd1) begin
					    wr_data_64  <= {vc_rx_data_i[31:0],vc_rx_data_i_d[63:32]};
   						wr_en       <= 1'b1; 
						DW_cntr     <= 10'd0;
						state       <= wait_state;
					end // if only one or last DW 
					else if (req_len > DW_cntr) begin 
					    wr_en         <= 1'b1;
						wr_data_64   <= {vc_rx_data_i[31:0],vc_rx_data_i_d[63:32]};
						state         <= sample_Data;
						DW_cntr       <= DW_cntr + 10'd2;
					end // if req_len > DW_cntr
					else begin
					    wr_en         <= 1'b0;
						state         <= wait_state;
						DW_cntr       <= DW_cntr;
					end 
				end // if valid
				else 
				    state    <= sample_Data;
			end // sample_Data
						
			wait_state : begin 
				req_compl       <= 1'b0;
				wr_en           <= 1'b0;
				DW_cntr         <= 10'd0;
				if ((tlp_type == MEM_RD32_FMT_TYPE) && compl_done)        state       <= rst_state; 
				else if ((tlp_type == MEM_WR32_FMT_TYPE) && (!wr_busy))   state       <= rst_state; 
				else                                                      state       <= wait_state;
			end //wait_state
			
			default : begin 
			    state          <= rst_state;
				DW_cntr        <= 10'd0;
			end  // default
		endcase
			
	end 
end 
end 

else //DATA_WIDTH == 32
begin 
assign vc_rx_ready_o = (state == wait_state) ? 1'b0 : 1'b1;

always @(posedge clk) begin 
    if(!rst_n)
	    wr_data <=32'd0;
    else 
        wr_data <=wr_data_32;
    end 		

always @(posedge clk) begin 
    if (!rst_n)
	begin 
	    req_tc       <= 3'b0;
        req_td       <= 1'b0;
        req_ep       <= 1'b0;
        req_attr     <= 2'b0;
        req_len      <= 10'b0;
        req_rid      <= 16'b0;
        req_tag      <= 10'b0;
        req_be       <= 8'b0;
        req_addr     <= 32'b0;
	    state        <= rst_state;
		tlp_type     <= 7'b0;
		DW_cntr      <= 10'd0;
		wr_data_32   <= 32'd0;
		wr_en        <= 1'b0;
		req_compl    <= 1'b0;
		
	end 
	else
	begin 
	    case (state)
		    rst_state : begin 
	            if (vc_rx_valid_i) 
		        begin 
		            if (vc_rx_sop_i) begin 
		        	    casex (vc_rx_data_i [6:0])
						    // MEM_RD32_FMT_TYPE || MEM_WR32_FMT_TYPE  : begin 
						    7'bx000000  : begin // mwr32 and mrd32
							        tlp_type     <= vc_rx_data_i [6:0];
								req_tc       <= vc_rx_data_i[14:12];
								req_tag[9:8] <= {vc_rx_data_i[15],vc_rx_data_i[11]};
								req_td       <= vc_rx_data_i[23];
								req_ep       <= vc_rx_data_i[22];
								req_attr     <= vc_rx_data_i[21:20];
								req_len      <= {vc_rx_data_i[17:16], vc_rx_data_i[31:24]};
								state        <= sample_DW2;
							end // if rx tlp is memory read or memory write
							default : begin // if other tlps
							    state    <= rst_state;
							end
						endcase
		        	end // if sop 
		        	else
		        	    state    <= rst_state;
		        end // if valid
				else 
				    state    <= rst_state;
			end // rst_state
			
			sample_DW2 : begin 
			    if (vc_rx_valid_i) begin 
			            req_rid       <= {vc_rx_data_i[7:0], vc_rx_data_i[15:8]};
				    req_tag[7:0]  <= vc_rx_data_i[23:16];
				    req_be        <= vc_rx_data_i[31:24];    // {last_be,first_be}
				    state         <= sample_DW3;
				end // 
				else 
				    state         <= sample_DW2;
			end // sample_DW2
			
			sample_DW3 : begin 
			    if (vc_rx_valid_i) begin 
			        req_addr       <= {vc_rx_data_i[7:0], vc_rx_data_i[15:8], vc_rx_data_i[23:16], vc_rx_data_i[31:26], 2'b00};
					if ((tlp_type == MEM_RD32_FMT_TYPE)) begin  
					    state          <= wait_state;
						req_compl      <= 1'b1;
					end // if tlp type is memory read
					else if ((tlp_type == MEM_WR32_FMT_TYPE)) begin 
					    state          <= sample_Data;
						req_compl      <= 1'b0;
						DW_cntr        <= 10'd0; //KK: TODO: to check for 32-bit data width
					end 
					else 
					   state  <= sample_DW3;
				end // 
				else 
				    state    <= sample_DW3;
			end // sample_DW3
			
			sample_Data : begin 
			    if (vc_rx_valid_i) begin 
				    if (req_len == DW_cntr + 1'b1) begin 
						wr_data_32       <= vc_rx_data_i;
   						    state     <= wait_state; 
							wr_en <= 1'b1; 
						   DW_cntr       <= 10'd0;
					end // if only one or last DW 
					else if (req_len > DW_cntr) begin 
					    wr_en         <= 1'b1;
						wr_data_32       <= vc_rx_data_i;
						state         <= sample_Data;
						DW_cntr       <= DW_cntr + 1'b1;
					end // if req_len > DW_cntr
					else begin
					    wr_en         <= 1'b0;
						state         <= wait_state;
						DW_cntr       <= DW_cntr;
					end 
				end // if valid
				else 
				    state    <= sample_Data;
			end // sample_Data
			
			wait_state : begin 
			    req_compl       <= 1'b0;
				wr_en           <= 1'b0;
				if ((tlp_type == MEM_RD32_FMT_TYPE) && compl_done)        state       <= rst_state; 
				else if ((tlp_type == MEM_WR32_FMT_TYPE) && (!wr_busy))   state       <= rst_state; 
				else                                                      state       <= wait_state;
				DW_cntr        <= 10'd0;
			end //wait_state
			
			default : begin 
			    state   <= rst_state;
				DW_cntr        <= 10'd0;
			end  // default
		endcase
			
	end 
end 

end

endgenerate 

endmodule

