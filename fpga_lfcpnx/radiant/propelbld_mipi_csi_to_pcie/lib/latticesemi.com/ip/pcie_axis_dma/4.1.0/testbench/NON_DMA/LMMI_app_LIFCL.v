module LMMI_app_LIFCL 
(
  input             clk,
  input             rst_n,
  input             u_dl_link_up_i,
  output reg        usr_lmmi_request_o,
  output reg        usr_lmmi_wr_rdn_o , 
  output reg [31:0] usr_lmmi_wdata_o ,
  output reg [16:2] usr_lmmi_offset_o, 
  input [31:0]      usr_lmmi_rdata_i ,
  input             usr_lmmi_rdata_valid_i ,
  input             usr_lmmi_ready_i,
  output reg [15:0] completer_id_o,
  output reg        config_done,
  input             gen_no,
  input      [2:0]  max_payload
);

// As initial configuration of the PCIe ep IP is required; so to configure the IP a register space is created. 
// Data at that register space will be used to configure the IP.
// defined an array of 49 bit register; Upper 17 bit will be used as the address of the register; lower 32 bit will be used as the value at that register;
reg [48:0] config_space [22:0] ;

always @(posedge clk) 
begin 
    if (!rst_n)
	begin 
    // PCIe core reset
     config_space[0] <= {17'h0f004, 32'h0001_0001};
	 //for negotiation in gen2
     config_space[1] <= {17'h04020, {31'h0001_0000,gen_no}};
    // disable multifunction
     config_space[2] <= {17'h05008, 32'h0000_0001};
     config_space[3] <= {17'h06008, 32'h0000_0001};
     config_space[4] <= {17'h07008, 32'h0000_0001};
    // disable MSI-X
     config_space[5] <= {17'h040f0, 32'h0007_0001};
    // setting vendor id and device id
     config_space[6] <= {17'h04040, 32'h9C1D_1204};
    // enable BAR0&1
     config_space[7] <= {17'h04060, 32'hFFF8_0000};//512KB
     config_space[8] <= {17'h04064, 32'hFFF8_0000};//512KB
	//Disable other bar 
     config_space[9] <= {17'h04068, 32'h0000_0000};
     config_space[10] <= {17'h0406C, 32'h0000_0000};
     config_space[11] <= {17'h04070, 32'h0000_0000};
     config_space[12] <= {17'h04074, 32'h0000_0000};
     config_space[13] <= {17'h04078, 32'h0000_0000};
	 //Maxpayload size
	 config_space[14] <= {17'h04084, {28'h0000_000,1'b0,max_payload}};
    //disable resizable BAR capability
     config_space[15] <= {17'h041a0, 32'h0000_0000};
    //disable ATS capability
     config_space[16] <= {17'h041c0, 32'h0000_0000};
    //Disable atomic op capability
     config_space[17] <= {17'h041cc, 32'h0000_0000};
    //enable LL core generation of ECRC when TD bit is 1
     config_space[18] <= {17'h031c4, 32'h0000_0001};
     // Class code and revision ids 
     config_space[19] <= {19'h04048, 32'h0880_0010};
    /* after doing this configuration wait for the phy pll to be stabilised 
    poll register 17'h0f200 till rd_data[4] == 1'b1 */
     config_space[20] <= {17'h0f200, 32'h0000_0000};
    
    //release PCIe LL reset after configuration;
     config_space[21] <= {17'h0f004, 32'h0000_0000};
    // to get the completer id
     config_space[22] <= {17'h04034, 32'h0000_0000};
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
	end 
 end 
//Wire and Reg Declarations
reg [31:0] read_data;
reg        LMMI_read;
reg        LMMI_write;
reg [3:0]  state;
reg [4:0]  counter;
wire       u_dl_link_up_redge;

//Parameter Declarations
localparam rst_state   = 4'b0001;
localparam rqst_assrt  = 4'b0010;
localparam ready_wait  = 4'b0100;
localparam read_wait   = 4'b1000;
(* ASYNC_REG = "TRUE" *) reg u_dl_link_up_d;
(* ASYNC_REG = "TRUE" *) reg u_dl_link_up_2d;
(* ASYNC_REG = "TRUE" *) reg u_dl_link_up_3d;


// assign u_dl_link_up_redge = u_dl_link_up_2d && (!u_dl_link_up_3d);
assign u_dl_link_up_redge = 1'b0;

always @(posedge clk)
begin 
    if (!rst_n) 
	begin 
	    counter         <= 5'd0;
		u_dl_link_up_d  <= 1'b0;
		LMMI_read       <= 1'b0;
		LMMI_write      <= 1'b0;
		config_done     <= 1'b0;
		completer_id_o  <= 16'h0000;
	end 
	else 
	begin 
	    if ((counter == 5'd22) && (usr_lmmi_rdata_valid_i))
		begin 
		    completer_id_o    <= usr_lmmi_rdata_i[15:0];
		end 
		else 
		begin 
		    completer_id_o    <= completer_id_o;
		end 
	    u_dl_link_up_d    <= u_dl_link_up_i;
	    u_dl_link_up_2d   <= u_dl_link_up_d;
	    u_dl_link_up_3d   <= u_dl_link_up_2d;
	    if ((state == ready_wait) && (usr_lmmi_ready_i) && (LMMI_write))
		begin 
		    counter   <= counter + 5'd1;
			if (counter == 21)  config_done    <= 1'b1;
			else                config_done    <= config_done;
		end
		else if ((state == read_wait) && (usr_lmmi_rdata_valid_i) && (LMMI_read))  
		begin 
		    if (usr_lmmi_rdata_i[4] != 1'b1) 
			    counter    <= counter;
			else 
			    counter    <= counter + 1'b1;
		end 
		else  
		begin 
		    counter   <= counter;
		end 
		
		if (u_dl_link_up_redge)
		begin
		    LMMI_read     <= 1'b1;
			LMMI_write    <= 1'b0;
		end 
		else if ((state == ready_wait) && (usr_lmmi_ready_i))
		begin 
		    LMMI_write    <= 1'b0;
		    LMMI_read     <= 1'b0;
		end 
		else if ((counter   <= 5'd19) || (counter == 5'd21)) 
		begin 
		    LMMI_write    <= 1'b1;
			LMMI_read     <= 1'b0;
		end 
		else if (counter == 5'd20)
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

always @(posedge clk)
begin 
    if (!rst_n) 
	begin 
	    state                 <= rst_state;
		usr_lmmi_request_o    <= 1'b0;
	    usr_lmmi_wr_rdn_o     <= 1'b0;
	    usr_lmmi_wdata_o      <= 32'd0;
	    usr_lmmi_offset_o     <= 15'd0;
		read_data             <= 32'd0;
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
		        usr_lmmi_request_o    <= 1'b0;
	            usr_lmmi_wr_rdn_o     <= 1'b0;
	            usr_lmmi_wdata_o      <= 32'd0;
	            usr_lmmi_offset_o     <= 15'd0;
			end //rst_state
			
			rqst_assrt : begin 
			    state                 <= ready_wait;
			    usr_lmmi_request_o    <= 1'b1;
		        usr_lmmi_offset_o     <= config_space[counter][48:34];
				if (LMMI_write) 
		            usr_lmmi_wr_rdn_o     <= 1'b1;
				else 
				    usr_lmmi_wr_rdn_o     <= 1'b0;
		        usr_lmmi_wdata_o      <= config_space[counter][31:0];
			end // rqst_assrt
			
		    ready_wait : begin 
			    if (usr_lmmi_ready_i) 
				begin 
				    usr_lmmi_request_o    <= 1'b0;
					usr_lmmi_wr_rdn_o     <= 1'b0;
				    if (LMMI_read)    state    <= read_wait;
					else              state    <= rst_state;
				end 
				else 
				    state             <= ready_wait;
			end // ready_wait
			
			read_wait : begin 
			    if (usr_lmmi_rdata_valid_i)
				begin 
				    state       <= rst_state;
					read_data   <= usr_lmmi_rdata_i;
				end 
				else  
				    state       <= read_wait;
			end // read_wait
			
			default : begin 
			    state                 <= rst_state;
		        usr_lmmi_request_o    <= 1'b0;
	            usr_lmmi_wr_rdn_o     <= 1'b0;
	            usr_lmmi_wdata_o      <= 32'd0;
	            usr_lmmi_offset_o     <= 15'd0;
			end // default
		
		endcase
	end 
end 

endmodule
