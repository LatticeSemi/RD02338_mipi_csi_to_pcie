module ucfg_app (
    input             clk,
	input             rst_n,
	input             u_tl_linkup,
   output reg         ucfg_valid_o,
   output reg         ucfg_wr_rd_n_o , 
   output reg [31:0]  ucfg_wr_data_o ,
   output reg [11:2]  ucfg_addr_o, 
   input      [31:0]  ucfg_rdata_i ,
   input              ucfg_rd_done_i ,
   input              ucfg_ready_i,
   output reg [15:0] read_data
); 

reg init_start;
reg [3:0]   state;
reg [4:0]   counter;

reg u_tl_linkup_d;
reg [31:0] ucfg_rdata_i_d;
reg ucfg_rd_done_i_d;
reg ucfg_ready_i_d;


always @(posedge clk)
begin
u_tl_linkup_d <= u_tl_linkup;
ucfg_rdata_i_d <= ucfg_rdata_i;
ucfg_rd_done_i_d <= ucfg_rd_done_i;
ucfg_ready_i_d <= ucfg_ready_i;
end 

// this interface is to pass on the completer id to the transmitted TLP packet  
reg [41:0] config_space [0:0] ;

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
		// completer ID 
             config_space[0] <= {10'h5f, 32'h0000_0000};
	         init_start      <= 1'b1;
	    end 
	    else 
	    begin
	    config_space [0]   <= config_space[0];
	end 
 end 
 
end 

localparam rst_state   = 4'b0001;
localparam rqst_assrt  = 4'b0010;
localparam ready_wait  = 4'b0100;
localparam read_wait   = 4'b1000;

reg ucfg_read;
reg ucfg_write;
reg config_done;


always @(posedge clk)
begin 
    if (!rst_n) 
	begin 
	    counter         <= 5'd0;
		ucfg_read       <= 1'b0;
		ucfg_write      <= 1'b0;
		config_done    <= 1'b0;
	end 
	else 
	begin 
	    //1st conditional block
	    if ((state==ready_wait && ucfg_ready_i_d && ucfg_write) || (state==read_wait && ucfg_rd_done_i_d && ucfg_read))
		begin 
		  if (counter === 0)begin
		     config_done <= 1'b1;
		     counter <= counter;
          end 
          else begin 
            config_done <= 1'b0;		  
		    counter   <= counter + 5'd1;
		  end 
		end 
		
		else  
		begin 
		    config_done <= config_done;
		    counter   <= counter;
		end 
		//2nd conditional block
		if ((state == ready_wait) && (ucfg_ready_i_d))
		begin 
         ucfg_write    <= 1'b0;
         ucfg_read     <= 1'b0;
		end 

		else if (counter == 5'd0 && u_tl_linkup_d)
		begin 
		    ucfg_read     <= 1'b1;
			ucfg_write    <= 1'b0;
		end 
		
		else 
		begin 
		    ucfg_read     <= ucfg_read;
		    ucfg_write    <= ucfg_write;
		end 
		
	end 
end 

always @(posedge clk or negedge rst_n)
begin 
    if (!rst_n) 
	begin 
	    state                 <= rst_state;
		ucfg_valid_o          <= 1'b0;
	end 
	else 
	begin 
	    case (state) 
		    rst_state : begin 
			    if ((ucfg_read || ucfg_write) && ~config_done) begin 
				    state                 <= rqst_assrt;
				end 
				else 
				begin 
			        state                 <= rst_state;
				end 
		        ucfg_valid_o       <= 5'b0;
	            ucfg_wr_rd_n_o     <= 1'b0;
	            ucfg_wr_data_o     <= 32'd0;
	            ucfg_addr_o        <= 10'd0;
			end //rst_state
			
			rqst_assrt : begin 
			    state                 <= ready_wait;
			    ucfg_valid_o    <= 1'b1;
		        ucfg_addr_o    <= config_space[counter][41:32];
            if (ucfg_write) 
               ucfg_wr_rd_n_o   <= 1'b1;
            else 
               ucfg_wr_rd_n_o   <= 1'b0;
              ucfg_wr_data_o      <= config_space[counter][31:0];
			end // rqst_assrt
			
		    ready_wait : begin 
              if (ucfg_ready_i_d) begin 
                   ucfg_valid_o    <= 1'b0;
                   ucfg_wr_rd_n_o  <= 1'b0;
                   if (ucfg_read)         state    <= read_wait;
			       else                   state    <= rst_state;
		      end 
		      else 
			    	state             <= ready_wait;
		      end // ready_wait
			
			read_wait : begin 
			    if (ucfg_rd_done_i_d)
				begin 
				    state       <= rst_state;
					read_data   <= ucfg_rdata_i_d[15:0];
				end 
				else  
				    state       <= read_wait;
			end // read_wait
			
			default : begin 
			    state                 <= rst_state;
                ucfg_valid_o          <= 1'b0;
                ucfg_wr_rd_n_o        <= 1'b0;
                ucfg_wr_data_o        <= 32'd0;
                ucfg_addr_o           <= 10'd0;
			end // default
		
		endcase
	end 
end 

endmodule
