module LMMI_app_old #(
                  	parameter NUM_OF_LANES = 1
				  )
(
    input clk,
	input rst_n,
    output reg [4:0] usr_lmmi_request_o,
    output reg usr_lmmi_wr_rdn_o , 
    output reg [31:0] usr_lmmi_wdata_o ,
    output reg [16:0] usr_lmmi_offset_o, 
    input [63:0] usr_lmmi_rdata_i ,
    input [4:0] usr_lmmi_rdata_valid_i ,
    input [4:0] usr_lmmi_ready_i,
	output reg config_done,
	input [1:0] gen_no,
    input [2:0] lane_no
);
reg init_start;
// As initial confiugration of the PCIe ep IP is required; so to configure the IP a register space is created. 
// Data at that register space will be used to configure the IP.
// defined an array of 49 bit register; Upper 17 bit will be used as the address of the register; lower 64 bit will be used as the value at that register (8|8|8|8|32) ---> lane1|lane2|lane3|lane4|link layer for usr_lmmi_rdata_i 
reg [80:0] config_space [26:0] ;

always @(posedge clk) 
begin 
    if (!rst_n)
	begin 
	   init_start <= 1'b0;   
	end 
	else 	
	begin 
	    if(init_start == 1'b0)
		begin 
		// PCIe core reset
             config_space[0] <= {17'h0f004, 32'h0, 32'h0001_0001};
			 config_space[1] <= {17'h04020, 32'h0, {13'h0000,lane_no,14'h0000,gen_no}};     //Lane-1(1),2(2),4(3) and Gen-1(0),2(1),3(2) 
			 config_space[2] <= {17'h02000, 32'h0, 32'h0000_0003};
			 config_space[3] <= {17'h03000, 32'h0, 32'h0000_0001};
			 config_space[4] <= {17'h04000, 32'h0, 32'h0000_0001};			 
            // disable multifunction
             config_space[5] <= {17'h05008, 32'h0, 32'h0000_0001};
             config_space[6] <= {17'h06008, 32'h0, 32'h0000_0001};
             config_space[7] <= {17'h07008, 32'h0, 32'h0000_0001};
            // disable MSI-X
             config_space[8] <= {17'h040f0, 32'h0, 32'h0007_0001};
            // setting vendor id and device id
             config_space[9] <= {17'h04040, 32'h0, 32'h9C25_1204};
            // enable BAR 0&1
             config_space[10] <= {17'h04060, 32'h0, 32'hFFFF_8000};
			 config_space[11] <= {17'h04064, 32'h0, 32'hFFFF_8000};
            //Disable other bar            
             config_space[12] <= {17'h04068, 32'h0, 32'h0000_0000};
             config_space[13] <= {17'h0406C, 32'h0, 32'h0000_0000};
             config_space[14] <= {17'h04070, 32'h0, 32'h0000_0000};
             config_space[15] <= {17'h04074, 32'h0, 32'h0000_0000};
             config_space[16] <= {17'h04078, 32'h0, 32'h0000_0000};
            //disable resizable BAR capability
             config_space[17] <= {17'h041a0, 32'h0, 32'h0000_0000};
            //disable ATS capability
             config_space[18] <= {17'h041c0, 32'h0, 32'h0000_0000};
            //Disable atomic op capability
             config_space[19] <= {17'h041cc, 32'h0, 32'h0000_0000};
            //enable LL core generation of ECRC when TD bit is 1
            // config_space[16] <= {17'h031c4, 32'h0000_0001};
             config_space[20] <= {17'h031c4, 32'h0, 32'h0000_0000};
             // Class code and revision ids 
             config_space[21] <= {17'h04048, 32'h0, 32'h0880_0010};
            /* after doing this configuration wait for the phy pll to be stabilised 
            poll register 17'h07F for all the lanes one by one and check 5th bit on each lane to get the status */ 
	         //config_space[] <= {17'h0f200, 32'h0,32'h0000_0000};
             //release PCIe LL reset after configuration; 
			 
			 if(NUM_OF_LANES==4)begin
                      config_space[22] <= {17'h7f, 32'h0, 32'h0000_0000};
					  config_space[23] <= {17'h7f, 32'h0, 32'h0000_0000};
                      config_space[24] <= {17'h7f, 32'h0, 32'h0000_0000};
                      config_space[25] <= {17'h7f, 32'h0, 32'h0000_0000};
			          config_space[26] <= {17'h0f004, 32'h0, 32'h0000_0000};
			 end
			 else if(NUM_OF_LANES==2)begin
                      config_space[22] <= {17'h7f, 32'h0, 32'h0000_0000};
                      config_space[23] <= {17'h7f, 32'h0, 32'h0000_0000};
                      config_space[24] <= {17'h0f004, 32'h0, 32'h0000_0000};   
			 end
 			 else begin//lane=1
			          config_space[22] <= {17'h7f, 32'h0, 32'h0000_0000}; 
			          config_space[23] <= {17'h0f004, 32'h0, 32'h0000_0000};  
			 end
			 
	         init_start      <= 1'b1;
	    end 
	    else 
	    begin  
	    config_space [0]   <= config_space[0];
	    config_space [1]   <= config_space[1];
	    config_space [2]   <= config_space[2];
	    config_space [3]   <= config_space[3];
	    config_space [4]   <= config_space[4];
	    config_space [5]   <= config_space[5];
	    config_space [6]   <= config_space[6];
	    config_space [7]   <= config_space[7];
	    config_space [8]   <= config_space[8];
	    config_space [9]   <= config_space[9];
	    config_space [10]   <= config_space[10];
	    config_space [11]   <= config_space[11];
	    config_space [12]   <= config_space[12];
	    config_space [13]   <= config_space[13];
	    config_space [14]   <= config_space[14];
	    config_space [15]   <= config_space[15];
	    config_space [16]   <= config_space[16];
	    config_space [17]   <= config_space[17];
	    config_space [18]   <= config_space[18];
	    config_space [19]   <= config_space[19];
	    config_space [20]   <= config_space[20];
	    config_space [21]   <= config_space[21];
	    config_space [22]   <= config_space[22];
		config_space [23]   <= config_space[23];
		config_space [24]   <= config_space[24];
		config_space [25]   <= config_space[25];
		config_space [26]   <= config_space[26];
	end 
 end 
 
end 
reg [63:0] read_data;
localparam rst_state   = 4'b0001;
localparam rqst_assrt  = 4'b0010;
localparam ready_wait  = 4'b0100;
localparam read_wait   = 4'b1000;
reg [3:0] state;
reg [4:0] counter;

reg LMMI_read;
reg LMMI_write;


always @(posedge clk)
begin 
    if (!rst_n) 
	begin 
	    counter         <= 5'd0;
		LMMI_read       <= 1'b0;
		LMMI_write      <= 1'b0;
		config_done     <= 1'b0;
	end 
	else 
	begin 
	    if ((state == ready_wait) && (usr_lmmi_ready_i[0]) && (LMMI_write))
		begin 
		    counter   <= counter + 5'd1;
			
		    if(NUM_OF_LANES==4)begin
			        if (counter == 26)  config_done    <= 1'b1;
			        else                config_done    <= config_done;
			 end
			 else if(NUM_OF_LANES==2)begin
			        if (counter == 24)  config_done    <= 1'b1;
			        else                config_done    <= config_done; 			 
			 end
 			 else begin//lane=1
			        if (counter == 23)  config_done    <= 1'b1;
			        else                config_done    <= config_done;			           
			 end
			
		end
		else if ((state == read_wait) && (usr_lmmi_rdata_valid_i[1]) && (LMMI_read))  //lane 1 PLL lock status Check
		begin 
		   if (&usr_lmmi_rdata_i[36] != 1'b1) 
			    counter    <= counter;
			else 
			    counter    <= counter + 1'b1;												
		end
		
		else if ((state == read_wait) && (usr_lmmi_rdata_valid_i[2]) && (LMMI_read))  //lane 2 PLL lock status Check
				begin 
		   if (&usr_lmmi_rdata_i[44] != 1'b1) 
			    counter    <= counter;
			else 
			    counter    <= counter + 1'b1;												
		end 
		
		
		else if ((state == read_wait) && (usr_lmmi_rdata_valid_i[3]) && (LMMI_read))  //lane 3 PLL lock status Check
				begin 
		    if (&usr_lmmi_rdata_i[52] != 1'b1) 
			    counter    <= counter;
			else 
			    counter    <= counter + 1'b1;												
		end 
		
		else if ((state == read_wait) && (usr_lmmi_rdata_valid_i[4]) && (LMMI_read)) //lane 4 PLL lock status Check
				begin 
		   if (&usr_lmmi_rdata_i[60] != 1'b1) 
			    counter    <= counter;
			else 
			    counter    <= counter + 1'b1;													
		end 
		
		else  
		begin 
		    counter   <= counter;
		end 
		//Next step
		if(NUM_OF_LANES==4)begin
		      if ((state == ready_wait) && (usr_lmmi_ready_i))
		      begin 
		          LMMI_write    <= 1'b0;
		          LMMI_read     <= 1'b0;
		      end 
		      else if ((counter   <= 5'd21) || (counter == 5'd26)) 
		      begin 
		          LMMI_write    <= 1'b1;
		      	  LMMI_read     <= 1'b0;
		      end 
		      else if ((counter >= 5'd22) && (counter <= 5'd25))
		      begin 
		          LMMI_read     <= 1'b1;
		      	  LMMI_write    <= 1'b0;
		      end 		
		      else 
		      begin 
		          LMMI_read     <= LMMI_read;
		      	  LMMI_write    <= LMMI_write;
		      end 
		end
		else if(NUM_OF_LANES==2)begin
		      if ((state == ready_wait) && (usr_lmmi_ready_i))
		      begin 
		          LMMI_write    <= 1'b0;
		          LMMI_read     <= 1'b0;
		      end 
		      else if ((counter   <= 5'd21) || (counter == 5'd24)) 
		      begin 
		          LMMI_write    <= 1'b1;
		      	  LMMI_read     <= 1'b0;
		      end 
		      else if ((counter == 5'd22) || (counter == 5'd23))
		      begin 
		          LMMI_read     <= 1'b1;
		      	  LMMI_write    <= 1'b0;
		      end 		
		      else 
		      begin 
		          LMMI_read     <= LMMI_read;
		      	  LMMI_write    <= LMMI_write;
		      end		
		end
		else begin//lane=1
		      if ((state == ready_wait) && (usr_lmmi_ready_i))
		      begin 
		          LMMI_write    <= 1'b0;
		          LMMI_read     <= 1'b0;
		      end 
		      else if ((counter   <= 5'd21) || (counter == 5'd23)) 
		      begin 
		          LMMI_write    <= 1'b1;
		      	  LMMI_read     <= 1'b0;
		      end 
		      else if (counter == 5'd22)
		      begin 
		          LMMI_read     <= 1'b1;
		      	  LMMI_write    <= 1'b0;
		      end 		
		      else 
		      begin 
		          LMMI_read     <= LMMI_read;
		      	  LMMI_write    <= LMMI_write;
		      end		
		end
		
	end 
end 

always @(posedge clk)
begin 
    if (!rst_n) 
	begin 
	    state                 <= rst_state;
		usr_lmmi_request_o    <= 5'b0;
	end 
	else 
	begin 
	    case (state) 
		    rst_state : begin 
			    if (LMMI_read || LMMI_write) begin 
				    state                 <= rqst_assrt;
				end 
				else 
				begin 
			        state                 <= rst_state;
				end 
		        usr_lmmi_request_o    <= 5'b0;
	            usr_lmmi_wr_rdn_o     <= 1'b0;
	            usr_lmmi_wdata_o      <= 32'd0;
	            usr_lmmi_offset_o     <= 17'd0;
			end //rst_state
			
			rqst_assrt : begin 
			    state                 <= ready_wait;
				
				if(NUM_OF_LANES==4)begin
				      if(counter == 22)
			            usr_lmmi_request_o    <= 5'h2;				  
				      else if(counter == 23)  
				         usr_lmmi_request_o    <= 5'h4;
				      else if(counter == 24)   
                         usr_lmmi_request_o    <= 5'h8;	
                      else if(counter == 25)   
                         usr_lmmi_request_o    <= 5'h10;					  
				      else 
                         usr_lmmi_request_o    <= 5'h1;
				end
				else if(NUM_OF_LANES==2)begin
				      if(counter == 22)
			            usr_lmmi_request_o    <= 5'h2;				  
				      else if(counter == 23)  
				         usr_lmmi_request_o    <= 5'h4;	
				      else 
                         usr_lmmi_request_o    <= 5'h1;						 
			    end
				else begin//lane=1
				      if(counter == 22)
			            usr_lmmi_request_o    <= 5'h2;				
				      else 
                         usr_lmmi_request_o    <= 5'h1;				
			    end
				
		        usr_lmmi_offset_o     <= config_space[counter][80:64];
				   
				//Next step
				if (LMMI_write) 
		            usr_lmmi_wr_rdn_o     <= 1'b1;
				else 
				    usr_lmmi_wr_rdn_o     <= 1'b0;
		        usr_lmmi_wdata_o      <= config_space[counter][31:0];
			end // rqst_assrt
			
		    ready_wait : begin 
			    if (usr_lmmi_ready_i) 
				begin 
				    usr_lmmi_request_o    <= 5'b0;
					usr_lmmi_wr_rdn_o     <= 1'b0;
				    if (LMMI_read)    state    <= read_wait;
					else              state    <= rst_state;
				end 
				else 
				    state             <= ready_wait;
			end // ready_wait
			
			read_wait : begin 
			    if (usr_lmmi_rdata_valid_i[1] || usr_lmmi_rdata_valid_i[2] || usr_lmmi_rdata_valid_i[3] || usr_lmmi_rdata_valid_i[4])
				begin 
				    state       <= rst_state;
					read_data   <= usr_lmmi_rdata_i;
				end 
				else  
				    state       <= read_wait;
			end // read_wait
			
			default : begin 
			    state                 <= rst_state;
		        usr_lmmi_request_o    <= 5'b0;
	            usr_lmmi_wr_rdn_o     <= 1'b0;
	            usr_lmmi_wdata_o      <= 32'd0;
	            usr_lmmi_offset_o     <= 17'd0;
			end // default
		
		endcase
	end 
end 

endmodule

