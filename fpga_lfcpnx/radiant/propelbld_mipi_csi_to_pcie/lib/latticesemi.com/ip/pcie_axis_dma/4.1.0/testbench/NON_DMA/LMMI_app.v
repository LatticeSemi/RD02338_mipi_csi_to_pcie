module LMMI_app #(
    parameter NUM_OF_LANES = 1
) (
    input clk,
    input rst_n,
    output reg [4:0] usr_lmmi_request_o,
    output reg usr_lmmi_wr_rdn_o , 
    output reg [31:0] usr_lmmi_wdata_o ,
    output reg [16:0] usr_lmmi_offset_o, 
    input [63:0] usr_lmmi_rdata_i ,
    input [4:0] usr_lmmi_rdata_valid_i ,
    input [4:0] usr_lmmi_ready_i,
    output reg config_done
);
reg init_start;
// As initial configuration of the PCIe ep IP is required; so to configure the IP a register space is created. 
// Data at that register space will be used to configure the IP.
// defined an array of 49 bit register; Upper 17 bit will be used as the address of the register; lower 64 bit will be used as the value at that register (8|8|8|8|32) ---> lane1|lane2|lane3|lane4|link layer
reg [80:0] config_space [5:0] ;

always @(posedge clk) 
begin 
    if (!rst_n)
	begin 
	   init_start <= 1'b0;   
	end 
	else 	
	begin 
	    if(init_start == 1'b0) begin 
                // PCIe core reset
                      config_space[0] <= {17'h0f004, 32'h0, 32'h0001_0001};
                /* after doing this configuration wait for the phy pll to be stabilised 
                poll register 17'h07F for all the lanes one by one and check 5th bit on each lane to get the status */ 
                //release PCIe LL reset after configuration; 
		if(NUM_OF_LANES==4)begin
                      config_space[1] <= {17'h7f, 32'h0, 32'h0000_0000};
                      config_space[2] <= {17'h7f, 32'h0, 32'h0000_0000};
                      config_space[3] <= {17'h7f, 32'h0, 32'h0000_0000};
                      config_space[4] <= {17'h7f, 32'h0, 32'h0000_0000};
                      config_space[5] <= {17'h0f004, 32'h0, 32'h0000_0000};
                end else if (NUM_OF_LANES==2) begin
                      config_space[1] <= {17'h7f, 32'h0, 32'h0000_0000};
                      config_space[2] <= {17'h7f, 32'h0, 32'h0000_0000};
                      config_space[3] <= {17'h0f004, 32'h0, 32'h0000_0000};   
                end else begin//lane=1
                      config_space[1] <= {17'h7f, 32'h0, 32'h0000_0000}; 
                      config_space[2] <= {17'h0f004, 32'h0, 32'h0000_0000};  
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
	    if ((state == ready_wait) && (usr_lmmi_ready_i[0]) && (LMMI_write)) begin 
                counter   <= counter + 5'd1;
                if (NUM_OF_LANES==4) begin
                    if (counter == 5)  config_done    <= 1'b1;
                    else               config_done    <= config_done;
                end else if(NUM_OF_LANES==2) begin
                    if (counter == 3)  config_done    <= 1'b1;
                    else               config_done    <= config_done; 			 
                end else begin //lane=1
                    if (counter == 2)  config_done    <= 1'b1;
                    else               config_done    <= config_done;			           
                end
            end else if ((state == read_wait) && (usr_lmmi_rdata_valid_i[1]) && (LMMI_read)) begin
            //lane 1 PLL lock status Check
                if (&usr_lmmi_rdata_i[36] != 1'b1) 
                    counter   <= counter;
                else 
                    counter   <= counter + 1'b1;	

            end else if ((state == read_wait) && (usr_lmmi_rdata_valid_i[2]) && (LMMI_read)) begin 
            //lane 2 PLL lock status Check
                if (&usr_lmmi_rdata_i[44] != 1'b1) 
                   counter    <= counter;
                else 
                   counter    <= counter + 1'b1;
            end else if ((state == read_wait) && (usr_lmmi_rdata_valid_i[3]) && (LMMI_read)) begin 
            //lane 3 PLL lock status Check
               if (&usr_lmmi_rdata_i[52] != 1'b1) 
                   counter    <= counter;
               else 
                   counter    <= counter + 1'b1;		
            end else if ((state == read_wait) && (usr_lmmi_rdata_valid_i[4]) && (LMMI_read)) begin 
            //lane 4 PLL lock status Check
               if (&usr_lmmi_rdata_i[60] != 1'b1) 
                   counter    <= counter;
               else 
                   counter    <= counter + 1'b1;			
            end
	
            else begin 
		    counter   <= counter;
            end

		if (NUM_OF_LANES==4) begin
		      if ((state == ready_wait) && (usr_lmmi_ready_i))
		      begin 
		          LMMI_write    <= 1'b0;
		          LMMI_read     <= 1'b0;
		      end 
		      else if ((counter  == 5'd0) || (counter == 5'd5)) 
		      begin 
		          LMMI_write    <= 1'b1;
		      	  LMMI_read     <= 1'b0;
		      end 
		      else if ((counter >= 5'd1) && (counter <= 5'd4))
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
		else if (NUM_OF_LANES==2) begin
		      if ((state == ready_wait) && (usr_lmmi_ready_i))
		      begin 
		          LMMI_write    <= 1'b0;
		          LMMI_read     <= 1'b0;
		      end 
		      else if ((counter  == 5'd0) || (counter == 5'd3)) 
		      begin 
		          LMMI_write    <= 1'b1;
		      	  LMMI_read     <= 1'b0;
		      end 
		      else if ((counter == 5'd1) || (counter == 5'd2))
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
		else begin //lane=1
		      if ((state == ready_wait) && (usr_lmmi_ready_i))
		      begin 
		          LMMI_write    <= 1'b0;
		          LMMI_read     <= 1'b0;
		      end 
		      else if ((counter  == 5'd0) || (counter == 5'd2)) 
		      begin 
		          LMMI_write    <= 1'b1;
		      	  LMMI_read     <= 1'b0;
		      end 
		      else if (counter == 5'd1)
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
	end  else begin 
	    case (state) 
                rst_state : begin 
                if (LMMI_read || LMMI_write) begin 
                    state                 <= rqst_assrt;
                end else begin 
                    state                 <= rst_state;
                end 
                usr_lmmi_request_o    <= 5'b0;
                usr_lmmi_wr_rdn_o     <= 1'b0;
                usr_lmmi_wdata_o      <= 32'd0;
                usr_lmmi_offset_o     <= 17'd0;
                end //rst_state
			
                rqst_assrt : begin 
                  state                 <= ready_wait;
                  if (NUM_OF_LANES==4) begin
                    if(counter == 5'd1)
                        usr_lmmi_request_o    <= 5'h2;				  
                    else if(counter == 5'd2)  
                        usr_lmmi_request_o    <= 5'h4;
                    else if(counter == 5'd3)   
                        usr_lmmi_request_o    <= 5'h8;	
                    else if(counter == 5'd4)   
                        usr_lmmi_request_o    <= 5'h10;					  
                    else 
                        usr_lmmi_request_o    <= 5'h1;

                  end else if (NUM_OF_LANES==2) begin
                    if(counter == 5'd1)
                        usr_lmmi_request_o    <= 5'h2;				  
                    else if(counter == 5'd2)  
                        usr_lmmi_request_o    <= 5'h4;	
                    else 
                        usr_lmmi_request_o    <= 5'h1;						 
                  end else begin  //lane=1
                    if(counter == 5'd1)
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
                    if (usr_lmmi_ready_i) begin 
                        usr_lmmi_request_o    <= 5'b0;
                        usr_lmmi_wr_rdn_o     <= 1'b0;
                        if (LMMI_read)    
                            state    <= read_wait;
                        else
                            state    <= rst_state;
                    end else 
                        state    <= ready_wait;
                end // ready_wait
			
                read_wait : begin 
                    if (usr_lmmi_rdata_valid_i[1] || usr_lmmi_rdata_valid_i[2] || usr_lmmi_rdata_valid_i[3] || usr_lmmi_rdata_valid_i[4]) begin 
                        state       <= rst_state;
                        read_data   <= usr_lmmi_rdata_i;
                    end else  
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
