
`timescale 1ps/1ps

module pcie_tx_engine_32bit
#(
    parameter INTERFACE = "TLP"
)(
	input clk,
	input rst_n,
	// tx TLP interface
    output reg vc_tx_valid_o ,
    output reg vc_tx_eop_o ,
    output  vc_tx_eop_n_o, 
    output reg vc_tx_sop_o ,
    output reg [31:0] vc_tx_data_o ,
    output [3:0] vc_tx_datap_o ,
    input vc_tx_ready_i ,
	//completer id from ucfg space.
	input [15:0] completer_id,
	// rx TLP info for handshaking
	input    req_compl,
	output reg  compl_done,
	
	input [2:0]   req_tc,    // Memory Read TC
    input         req_td,    // Memory Read TD
    input         req_ep,    // Memory Read EP
    input [1:0]   req_attr,  // Memory Read Attribute
    input [9:0]   req_len,   // Memory Read Length (1DW)
    input [15:0]  req_rid,   // Memory Read Requestor ID
    input [9:0]   req_tag,   // Memory Read Tag
    input [7:0]   req_be,    // Memory Read Byte Enables
    input [31:0]  req_addr,  // Memory Read Address
	// memory interface.
	output [13:0] rd_addr,
	output [3:0]  rd_be,
	output reg    rd_en,
	input [31:0]  rd_data,
	output reg [9:0] read_data_counter
);
localparam CPLD_FMT_TYPE   = 7'b10_01010;
localparam rst_state       = 4'b0000;
localparam send_DW1        = 4'b0001;
localparam send_DW2        = 4'b0010;
localparam send_DW3        = 4'b0100;
localparam send_Data       = 4'b1000;
localparam send_dw_tlp     = 4'b0011;
reg [3:0] state ;
reg [11:0] byte_count;

reg [6:0] lower_addr;
reg [9:0] dw_counter;

assign rd_be = req_be[3:0];
assign rd_addr = {req_addr [13:2] , 2'b00};
assign vc_tx_eop_n_o  = 1'b0;
assign vc_tx_datap_o[0] = ^(vc_tx_data_o[7:0]);
assign vc_tx_datap_o[1] = ^(vc_tx_data_o[15:8]);
assign vc_tx_datap_o[2] = ^(vc_tx_data_o[23:16]);
assign vc_tx_datap_o[3] = ^(vc_tx_data_o[31:24]);

  always @ (rd_be) begin
    casex (rd_be[3:0])
      4'b1xx1 : byte_count = 12'h004;
      4'b01x1 : byte_count = 12'h003;
      4'b1x10 : byte_count = 12'h003;
      4'b0011 : byte_count = 12'h002;
      4'b0110 : byte_count = 12'h002;
      4'b1100 : byte_count = 12'h002;
      4'b0001 : byte_count = 12'h001;
      4'b0010 : byte_count = 12'h001;
      4'b0100 : byte_count = 12'h001;
      4'b1000 : byte_count = 12'h001;
      4'b0000 : byte_count = 12'h001;
    endcase
  end
  
    always @ (rd_be or req_addr) begin
    casex ( rd_be[3:0])
       4'b0000 : lower_addr = {req_addr[6:2], 2'b00};
       4'bxxx1 : lower_addr = {req_addr[6:2], 2'b00};
       4'bxx10 : lower_addr = {req_addr[6:2], 2'b01};
       4'bx100 : lower_addr = {req_addr[6:2], 2'b10};
       4'b1000 : lower_addr = {req_addr[6:2], 2'b11};
       4'bxxxx : lower_addr = 7'h0;
    endcase // casex ({compl_wd, rd_be[3:0]})
    end
	
always @(posedge clk) begin 
    if (!rst_n) begin 
	    vc_tx_eop_o       <= 1'b0;
		vc_tx_sop_o       <= 1'b0;
		vc_tx_valid_o     <= 1'b0;
		vc_tx_data_o      <= 32'd0;
		dw_counter        <= 10'd0;
		read_data_counter <= 10'd0;
		compl_done        <= 1'b0;
		state             <= rst_state;
		rd_en             <= 1'b0;
	end
	else 
	begin 
	    case(state) 
		    rst_state : begin 
			    if (req_compl) 
				begin 
					vc_tx_eop_o       <= 1'b0;
		            vc_tx_sop_o       <= 1'b0;
		            vc_tx_valid_o     <= 1'b0;
		            vc_tx_data_o      <= 32'd0;
					//state             <= (INTERFACE == "TLP") ? send_dw_tlp : send_DW1;
                    state             <= send_DW1; //Mohan : Follow ordinary TLP sending flow
				end 
				else // if req_compl
				begin 
				    vc_tx_eop_o       <= 1'b0;
		            vc_tx_sop_o       <= 1'b0;
		            vc_tx_valid_o     <= 1'b0;
		            vc_tx_data_o      <= 32'd0;
					state             <= rst_state;
				end 
				rd_en             <= 1'b0;
				compl_done        <= 1'b0;
				dw_counter        <= 10'd0;
				read_data_counter <= 10'd0;
			end // rst_state
			send_dw_tlp : begin 
			    if(vc_tx_ready_i)begin 
				  vc_tx_eop_o            <= 1'b0;
		          vc_tx_sop_o            <= 1'b0;
		          vc_tx_valid_o          <= 1'b1;
				  vc_tx_data_o[7:0]      <= completer_id[15:8];
				  vc_tx_data_o[15:8]     <= completer_id[7:0];
				  vc_tx_data_o[23:16]    <= {4'b0000,byte_count[11:8]};
				  vc_tx_data_o[31:24]    <= byte_count[7:0];
				  state                  <= send_DW3;
				  rd_en                  <= 1'b1;
				end 
				else 
				begin 
				  vc_tx_eop_o            <= 1'b0;
		          vc_tx_sop_o            <= 1'b1;
		          vc_tx_valid_o          <= 1'b1;
				  vc_tx_data_o[7:0]      <= {1'b0,CPLD_FMT_TYPE};
				  vc_tx_data_o[15:8]     <= {req_tag[9],req_tc,req_tag[8],3'b000};
				  vc_tx_data_o[23:16]    <= {1'b1,req_ep,req_attr,2'b00,req_len[9:8]};
				  vc_tx_data_o[31:24]    <= req_len[7:0];
			      rd_en                  <= 1'b0;
				end 
				  compl_done             <= 1'b0;
				  dw_counter             <= 10'd0;
			end //send_DW1
			send_DW1 : begin 
			    if (vc_tx_ready_i) 
				begin 
				    vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b1;
		            vc_tx_valid_o          <= 1'b1;
				    vc_tx_data_o[7:0]      <= {1'b0,CPLD_FMT_TYPE};
				    vc_tx_data_o[15:8]     <= {req_tag[9],req_tc,req_tag[8],3'b000};
				    vc_tx_data_o[23:16]    <= {1'b0,req_ep,req_attr,2'b00,req_len[9:8]};
				    vc_tx_data_o[31:24]    <= req_len[7:0];
					rd_en                  <= 1'b0;
					state                  <= send_DW2;
				end 
				else
				begin 
				    state                  <= send_DW1;
					vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b0;
					rd_en                  <= 1'b0;
				end 
				compl_done        <= 1'b0;
				read_data_counter <= read_data_counter + 1;
				dw_counter        <= 0;
			end //send_DW1
			
			send_DW2 : begin 
			    if (vc_tx_ready_i) 
				begin 
				    vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b1;
				    vc_tx_data_o[7:0]      <= completer_id[15:8];
				    vc_tx_data_o[15:8]     <= completer_id[7:0];
				    vc_tx_data_o[23:16]    <= {4'b0000,byte_count[11:8]};
				    vc_tx_data_o[31:24]    <= byte_count[7:0];
					state                  <= send_DW3;
					rd_en                  <= 1'b1;//mod
				end 
				else 
				begin 
				    state                  <= send_DW2;
					vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b0;
					rd_en                  <= 1'b0;
				end 
				compl_done        <= 1'b0;
				read_data_counter <= read_data_counter + 1;
				dw_counter        <= 0;
			end // send_DW2
			
			send_DW3 : begin 
			    if (vc_tx_ready_i) 
				begin 
				    vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b1;
				    vc_tx_data_o[7:0]      <= req_rid[15:8];
				    vc_tx_data_o[15:8]     <= req_rid[7:0];
				    vc_tx_data_o[23:16]    <= req_tag[7:0];
				    vc_tx_data_o[31:24]    <= {1'b0,lower_addr};
					state                  <= send_Data;
					rd_en                  <= 1'b1;
				end 
				else 
				begin 
				    state                  <= send_DW3;
					vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b0;
					rd_en              <= 1'b0;
				end 
				compl_done        <= 1'b0;
				read_data_counter <= read_data_counter + 1;
				dw_counter        <= 0;
			end // send_DW3
			
			send_Data : begin 
			    if (vc_tx_ready_i) 
				begin 
				    if (req_len == dw_counter + 1'b1) begin 
					    vc_tx_sop_o       <= 1'b0;
		                vc_tx_valid_o     <= 1'b1;
						vc_tx_data_o      <= rd_data;
						compl_done        <= 1'b1;
						vc_tx_eop_o       <= 1'b1;
						state             <= rst_state;
						rd_en             <= 1'b0;
						dw_counter        <= 10'd0;
						read_data_counter <= 0;
					end // if only one or last DW
					else if (req_len > dw_counter) begin 
					    vc_tx_sop_o            <= 1'b0;
		                vc_tx_valid_o          <= 1'b1;
						vc_tx_data_o           <= rd_data;
						compl_done             <= 1'b0;
						vc_tx_eop_o            <= 1'b0;
      					state                  <= send_Data;
						rd_en                  <= 1'b1;
						dw_counter             <= dw_counter + 1'b1;
						read_data_counter      <= read_data_counter + 1'b1;
					end // if req_len > dw_counter
					else begin 
					    state                  <= rst_state;
					    vc_tx_eop_o            <= 1'b0;
		                vc_tx_sop_o            <= 1'b0;
		                vc_tx_valid_o          <= 1'b0;
					    rd_en                  <= 1'b0;
						compl_done             <= 1'b0;
				        dw_counter             <= dw_counter;
				        read_data_counter      <= read_data_counter;
					end 
				end // if ready
				else 
				begin 
				    state             <= send_Data;
				    dw_counter        <= 10'd0;
				    read_data_counter <= 10'd0;
				end 
			end //send_Data
			
			default : begin 
			    state             <= rst_state;
				dw_counter        <= 10'd0;
				read_data_counter <= 10'd0;
				rd_en         <= 1'b0;
			end 
		endcase
		
	end
end 

endmodule
