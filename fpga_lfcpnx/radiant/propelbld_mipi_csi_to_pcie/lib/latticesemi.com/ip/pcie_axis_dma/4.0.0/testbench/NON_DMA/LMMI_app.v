module LMMI_app (
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
reg [80:0] config_space [4:0] ;
reg fastsim_done;

localparam FPGA_HW = 1'b1;

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
	    // disabling ASPM (L0s and L1)
			 config_space[1] <= {17'h04088, 32'h0, 32'h0000_0000};
        /* after doing this configuration wait for the phy pll to be stabilised 
        poll register 17'h07F to get the pll_locked status */           
             config_space[2] <= {17'h7f, 32'h0, 32'h0000_0000};          
        //release PCIe LL reset after configuration;
             config_space[3] <= {17'h0f004, 32'h0, 32'h0000_0000};
	         init_start      <= 1'b1;
	    end 
	    else 
	    begin
	    config_space [0]   <= config_space[0];
	    config_space [1]   <= config_space[1];
	    config_space [2]   <= config_space[2];
	    config_space [3]   <= config_space[3];
	end 
 end 
 
end 
reg [63:0] read_data;
localparam rst_state   = 6'b000001;
localparam rqst_assrt  = 6'b000010;
localparam ready_wait  = 6'b000100;
localparam read_wait   = 6'b001000;
localparam fastsim1    = 6'b010000;
localparam fastsim2    = 6'b100000;

reg [5:0] state;
reg [5:0] counter;

reg LMMI_read;
reg LMMI_write;

always @(posedge clk)
begin 
    if (!rst_n) 
	begin 
	    counter         <= 6'd0;
		LMMI_read       <= 1'b0;
		LMMI_write      <= 1'b0;
		config_done     <= 1'b0;
	end 
	else 
	begin 
	    if ((state == ready_wait) && (usr_lmmi_ready_i[0]) && (LMMI_write))
		begin 
		    counter   <= counter + 6'd1;
			if (counter == 3)  config_done    <= 1'b1;
			else                config_done    <= config_done;
		end
		else if ((state == read_wait) && (usr_lmmi_rdata_valid_i[1]) && (LMMI_read))  //lane 1 PLL lock status Check
		begin 
		   if (&usr_lmmi_rdata_i[36] != 1'b1) 
			    counter    <= counter;
			else 
			    counter    <= counter + 1'b1;												
		end 	
		else  
		begin 
		    counter   <= counter;
		end 
		if ((state == ready_wait) && (usr_lmmi_ready_i))
		begin 
		    LMMI_write    <= 1'b0;
		    LMMI_read     <= 1'b0;
		end 
		else if ((counter   <= 6'd1) || (counter == 6'd3)) 
		begin 
		    LMMI_write    <= 1'b1;
			LMMI_read     <= 1'b0;
		end 
		else if ((counter == 6'd2))
		begin 
			LMMI_write    <= 1'b0;
			LMMI_read     <= 1'b1;
		end 
		else 
		begin 
		    LMMI_read     <= LMMI_read;
			LMMI_write    <= LMMI_write;
		end 
	end 
end 

always @(posedge clk)
begin 
    if (!rst_n) 
	begin 
	    state                 <= rst_state;
		usr_lmmi_request_o    <= 5'b0;
		fastsim_done <= 1'b0;
	end 
	else 
	begin 
	    case (state) 
		    rst_state : begin
			    if (~fastsim_done & ~FPGA_HW) begin
                               state <= fastsim1;
			       usr_lmmi_request_o    <= 5'b1;
                               usr_lmmi_wr_rdn_o     <= 1'b1;
                               usr_lmmi_wdata_o      <= 32'h3;
                               usr_lmmi_offset_o     <= 17'h2000;
		            end

			    else begin
			       if (LMMI_read || LMMI_write) begin 
				    state                 <= rqst_assrt;
			       end 
	                       else begin 
			            state                 <= rst_state;
	                       end 
		               usr_lmmi_request_o    <= 5'b0;
	                       usr_lmmi_wr_rdn_o     <= 1'b0;
	                       usr_lmmi_wdata_o      <= 32'd0;
	                       usr_lmmi_offset_o     <= 17'd0;
		            end
			end //rst_state

			fastsim1: begin
                           if (usr_lmmi_ready_i[0]) begin
                               state <= fastsim2;
                               usr_lmmi_request_o    <= 5'b1;
                               usr_lmmi_wr_rdn_o     <= 1'b1;
                               usr_lmmi_wdata_o      <= 32'h1;
                               usr_lmmi_offset_o     <= 17'h4000;
		           end
			   else begin
		              state <= fastsim1;
			   end
	                end

			fastsim2: begin
                           if (usr_lmmi_ready_i[0]) begin
                               state <= rst_state;
                               usr_lmmi_request_o    <= 5'b0;
                               usr_lmmi_wr_rdn_o     <= 1'b0;
                               usr_lmmi_wdata_o      <= 32'h0;
                               usr_lmmi_offset_o     <= 17'h0;
                               fastsim_done <= 1'b1;
                           end
                           else begin
                              state <= fastsim2;
                           end
	                end
			
			rqst_assrt : begin 
			    state                 <= ready_wait;
				if (counter == 6'd2)
			      usr_lmmi_request_o    <= 5'h2;				   
				else 
                   usr_lmmi_request_o    <= 5'h1;				
		        usr_lmmi_offset_o     <= config_space[counter][80:64];
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
			    if (usr_lmmi_rdata_valid_i[1])
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
