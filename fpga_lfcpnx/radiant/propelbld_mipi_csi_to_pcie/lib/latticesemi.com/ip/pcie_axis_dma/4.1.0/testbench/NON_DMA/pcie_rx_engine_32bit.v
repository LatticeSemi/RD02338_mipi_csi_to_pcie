`timescale 1ps/1ps
module pcie_rx_engine_32bit 
(
  input              clk,
  input              rst_n,
  // Rx TLP interface
  output             vc_rx_ready_o ,
  input              vc_rx_valid_i ,
  input [1:0]        vc_rx_sel_i ,  // 0 posted request, 1 non posted , 2 completion, 3 reserved
  input [12:0]       vc_rx_cmd_data_i ,
  input              vc_rx_sop_i ,
  input [31:0]       vc_rx_data_i,
  input [3:0]        vc_rx_datap_i,
  input              vc_rx_eop_i ,
  input              vc_rx_err_ecrc_i,
  input [1:0]        vc_rx_f_i , // function indicator from func 0 to function3 as only 4 function are supported
  //Rx TLP info 
  output reg         req_compl,
  input              compl_done,
  output reg [2:0]   req_tc,    // Memory Read TC
  output reg         req_td,    // Memory Read TD
  output reg         req_ep,    // Memory Read EP
  output reg [1:0]   req_attr,  // Memory Read Attribute
  output reg [9:0]   req_len,   // Memory Read Length (1DW)
  output reg [15:0]  req_rid,   // Memory Read Requestor ID
  output reg [9:0]   req_tag,   // Memory Read Tag
  output reg [7:0]   req_be,    // Memory Read Byte Enables
  output reg [31:0]  req_addr,  // Memory Read Address
  //Memory interface.
  output reg [31:0]  wr_data,
  output reg         wr_en,
  input              wr_busy
);
// encoding for state machine
localparam rst_state            = 5'b00000;
localparam sample_DW2           = 5'b00001;
localparam sample_DW3           = 5'b00010;
localparam sample_DW4           = 5'b00100;
localparam wait_state           = 5'b01000;
localparam sample_Data          = 5'b10000;
// combination of format and type {FMT{1:0],TYPE[4:0]}
localparam MEM_RD32_FMT_TYPE    = 7'b00_00000;
localparam MEM_WR32_FMT_TYPE    = 7'b10_00000;
localparam MEM_RD64_FMT_TYPE    = 7'b01_00000;
localparam MEM_WR64_FMT_TYPE    = 7'b11_00000;

//Reg Declarations
reg [4:0] state;
reg [6:0] tlp_type;
reg [9:0] DW_cntr;

assign vc_rx_ready_o = (state == wait_state) ? 1'b0 : 1'b1;

always @(posedge clk) 
begin 
  if(!rst_n)begin 
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
	wr_data      <= 32'd0;
	wr_en        <= 1'b0;
	req_compl    <= 1'b0;
  end 
  else begin 
    case (state)
	rst_state : begin 
	            if(vc_rx_valid_i)begin 
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
				    end // if Rx TLP is memory read or memory write
					default : begin // if other tlps
				      state        <= rst_state;
					end
				    endcase
		        	end // if sop 
		        	else state     <= rst_state;
		          end // if valid
				  else   state     <= rst_state;
			    end // rst_state
    sample_DW2 : begin 
			     if(vc_rx_valid_i)begin 
			           req_rid         <= {vc_rx_data_i[7:0], vc_rx_data_i[15:8]};
				   req_tag[7:0]    <= vc_rx_data_i[23:16];
				   req_be          <= vc_rx_data_i[31:24]; 
				   state           <= sample_DW3;
				end  
				else state         <= sample_DW2;
			    end // sample_DW2
	sample_DW3 : begin 
			    if(vc_rx_valid_i)begin 
			       req_addr        <= {vc_rx_data_i[7:0], vc_rx_data_i[15:8], vc_rx_data_i[23:16], vc_rx_data_i[31:26], 2'b00};
				if((tlp_type == MEM_RD32_FMT_TYPE)) begin 
				   state           <= wait_state;
				   req_compl       <= 1'b1;
				end 
				else if ((tlp_type == MEM_WR32_FMT_TYPE)) begin
				   state           <= sample_Data;
				   req_compl       <= 1'b0;
				   DW_cntr         <= 10'd0;
				end 
				end 
				else state         <= sample_DW3;
			end // sample_DW3
    sample_Data : begin 
			    if(vc_rx_valid_i)begin 
				    if(req_len == DW_cntr + 1'b1) begin 
					  wr_data      <= vc_rx_data_i;
   					  state        <= wait_state; 
					  wr_en        <= 1'b1; 
					  DW_cntr      <= 10'd0;
					end // if only one or last DW 
					else if (req_len > DW_cntr) begin 
					    wr_en      <= 1'b1;
						wr_data    <= vc_rx_data_i;
						state      <= sample_Data;
						DW_cntr    <= DW_cntr + 1'b1;
					end // if req_len > DW_cntr
					else begin
					    wr_en      <= 1'b0;
						state      <= wait_state;
						DW_cntr    <= DW_cntr;
					end 
				end // if valid
				else    state      <= sample_Data;
			end // sample_Data
	wait_state : begin 
			    req_compl       <= 1'b0;
				wr_en           <= 1'b0;
				if ((tlp_type == MEM_RD32_FMT_TYPE) && compl_done)        state       <= rst_state; 
				else if ((tlp_type == MEM_WR32_FMT_TYPE) && (!wr_busy))   state       <= rst_state; 
				else                                                      state       <= wait_state;
				DW_cntr         <= 10'd0;
			end //wait_state
			default : begin 
			    state          <= rst_state;
				DW_cntr        <= 10'd0;
			end  // default
		endcase
			
	end 
end 

endmodule
