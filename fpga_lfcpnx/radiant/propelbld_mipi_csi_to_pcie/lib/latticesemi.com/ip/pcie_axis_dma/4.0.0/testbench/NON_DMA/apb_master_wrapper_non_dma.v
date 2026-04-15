
module apb_master_wrapper_non_dma #(
    parameter SIM         = 0,
	parameter PCIE_CSR_BASE_ADDR = 32'hC520_0000
	)
	(
    output reg    			config_done,
    // apb interface
    input            		apb_clk_i,
	input            		apb_reset_n_i,
	output 		[31:0]    	apb_addr_o,
	output          		apb_sel_o,
	output          		apb_enable_o,
	output          		apb_write_o,
	output 		[31:0]    	apb_wdata_o,
	input  		[31:0]     	apb_rdata_i,
	input            		apb_ready_i,
	input            		apb_slverr_i,
	input                   gen_no,
	input       [2:0]       max_payload,
	output  reg [15:0]      read_data_id
);

reg [50:0] config_space [26:0];

reg 			gen_lane_cap;
wire [31:0] 	w_data_apb; 
wire [31:0] 	addr_apb  ; 
reg  [7:0] 		num_descr_d;
reg  [7:0]		num_descr_2d;
wire 			wr_en_apb ; 
wire 			rd_en_apb ; 
reg  [31:0] 	w_data_reconfig;
reg  [31:0] 	addr_reconfig;
reg 			rdy_apb_d;
reg  [4:0] 		reconfig_counter;
reg 			wr_en_reconfig;
reg 			rd_en_reconfig;
wire [31:0] 	rd_data_apb;
wire [31:0] 	wr_data_sync;
wire [31:0] 	reg_address_sync;
wire 			wr_en_pulse;
reg 			wr_en_sync;



always @(posedge apb_clk_i) 
begin 
    if (!apb_reset_n_i)
	begin 
    // PCIe core reset
     config_space[0]  	<= 	{19'h0f004, 32'h0001_0001}; 	
	//for negotiation in gen2
     config_space[1]  	<= 	{19'h04020, {13'h0000,3'd1,15'h0000,gen_no}};
	//to reduce timeouts
	 config_space[2] 	<= 	{19'h02000, 32'h0000_0003};
	 config_space[3] 	<= 	{19'h03000, 32'h0000_0001};
	 config_space[4] 	<= 	{19'h04000, 32'h0000_0001};
    // disable multifunction
     config_space[5]  	<= 	{19'h05008, 32'h0000_0001};
     config_space[6]  	<= 	{19'h06008, 32'h0000_0001};
     config_space[7]  	<= 	{19'h07008, 32'h0000_0001};
    // disable MSI-X	
     config_space[8]  	<= 	{19'h040f0, 32'h0007_0001};
    // setting vendor id and device id
     config_space[9]  	<= 	{19'h04040, 32'h9C3E_1204};
    // enable BAR0
     config_space[10]  	<=  {19'h04060, 32'hFFF8_0000};//512KB
     config_space[11]  	<= 	{19'h04064, 32'hFFF8_0000};//512KB
    //Disable other bar
     config_space[12]  	<= 	{19'h04068, 32'h0000_0000};
     config_space[13] 	<= 	{19'h0406C, 32'h0000_0000};
     config_space[14] 	<= 	{19'h04070, 32'h0000_0000};
     config_space[15] 	<= 	{19'h04074, 32'h0000_0000};
     config_space[16] 	<= 	{19'h04078, 32'h0000_0000};
	 //Maxpayload size
	 config_space[17] <= {19'h04084, {28'h0000_000,1'b0,max_payload}};
    //disable resizable BAR capability
     config_space[18] 	<= 	{19'h041a0, 32'h0000_0000};
    //disable ATS capability
     config_space[19] 	<= 	{19'h041c0, 32'h0000_0000};
    //Disable atomic op capability
     config_space[20] 	<= 	{19'h041cc, 32'h0000_0000};
    //enable LL core generation of ECRC when TD bit is 1
     config_space[21] 	<= 	{19'h031c4, 32'h0000_0000};
	// class code and revision id 
     config_space[22] 	<= 	{19'h04048, 32'h0105_2010};
	// enabling msi capability
     config_space[23] 	<= 	{19'h040E8, 32'h0000_0032};
	// enable interrupts
     config_space[24] 	<= 	{19'h04050, 32'h0000_0000};
	
    /* after doing this configuration wait for the phy pll to be stabilised 
    poll register 17'h0f200 till rd_data[4] == 1'b1 */
	 config_space[25] <= {19'h0f200, 32'h0000_0000};

    //release PCIe LL reset after configuration;
	 config_space[26] <= {19'h0f004, 32'h0000_0000};
	 // config_space[26] <= {19'h04034, 32'h0000_0000};
	
	end 
	else 
	begin 
	    config_space [0]    <= config_space[0];
	    config_space [1]    <= config_space[1];
	    config_space [2]    <= config_space[2];
	    config_space [3]    <= config_space[3];
	    config_space [4]    <= config_space[4];
	    config_space [5]    <= config_space[5];
	    config_space [6]    <= config_space[6];
	    config_space [7]    <= config_space[7];
	    config_space [8]    <= config_space[8];
	    config_space [9]    <= config_space[9];
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

wire rdy_apb;
wire rdy_apb_redge;


reg [4:0] reconfig_counter_1;
reg config_done_1;
reg config_done_2;

assign rdy_apb_redge   = rdy_apb & (!rdy_apb_d);
always @(posedge apb_clk_i)
begin 
    if (!apb_reset_n_i) 
	begin 
	    config_done           <= 1'b0;
		reconfig_counter      <= 5'd0;
		config_done_1         <= 1'b0;
		reconfig_counter_1    <= 5'd0;
		config_done_2         <= 1'b0;
		rdy_apb_d             <= 1'b0;
		rd_en_reconfig        <= 1'b0;
		wr_en_reconfig        <= 1'b0;
		addr_reconfig         <= 32'd0;
		w_data_reconfig       <= 32'd0;
		num_descr_d           <= 8'h00;
		num_descr_2d          <= 8'h00;
	end 
	else 
	begin
	    if (reconfig_counter >= 26 ) 
		begin 
		    config_done    <= 1'b1;
		end 
		else
		begin 
		    config_done    <= 1'b0;
		end 
   	    rdy_apb_d        <= rdy_apb;
	    
		if (rdy_apb_redge && (reconfig_counter <= 26))
		begin 
			reconfig_counter      <= reconfig_counter + 1'b1;
			w_data_reconfig       <= config_space[reconfig_counter][31:0];
			// addr_reconfig         <= {CSR_ADDRESS,config_space[reconfig_counter] [50:32]} ;	
			addr_reconfig         <= (PCIE_CSR_BASE_ADDR) | ({13'd0,config_space[reconfig_counter] [50:32]}) ;	
			if ((reconfig_counter <= 24) || (reconfig_counter > 25 )) begin 
			    wr_en_reconfig    <= 1'b1;
			    rd_en_reconfig    <= 1'b0;
			end 
			else 
			begin 
			    wr_en_reconfig     <= 1'b0;
			    rd_en_reconfig     <= 1'b1;
			end 
		end
        else if (config_done_2 && rdy_apb_redge && (reconfig_counter_1 <= 26))  
		begin 
		    reconfig_counter_1      <= reconfig_counter_1 + 1'b1;
			addr_reconfig           <= (PCIE_CSR_BASE_ADDR) | ({13'd0,config_space[reconfig_counter_1] [50:32]}) ;
		    wr_en_reconfig          <= 1'b0;
			rd_en_reconfig          <= 1'b1;
			
			if (reconfig_counter_1 == 26)
			begin 
			    config_done_1    <= 1'b1;
				read_data_id     <= config_space[reconfig_counter_1][15:0];
			end 
			else
			begin
			    config_done_1    <= 1'b0;
			end 
		end		
		else 
		begin 
		    rd_en_reconfig   <= 1'b0;
		    wr_en_reconfig   <= 1'b0;
		    reconfig_counter <= reconfig_counter;
			reconfig_counter_1 <= reconfig_counter_1;
		end
        if (config_done & apb_ready_i ) 
		begin 
		    config_done_2    <= 1'b1;
		end 
		else
		begin 
		    config_done_2    <= config_done_2;
		end		
	end 
end 


assign w_data_apb    = w_data_reconfig;
assign addr_apb      = addr_reconfig  ;
assign wr_en_apb     = wr_en_reconfig ;
assign rd_en_apb     = rd_en_reconfig ;


apb_master_non_dma apb_master_inst (
    // 
    .wdata_i 		(w_data_apb),                // synchronise these signal with respect to apb_clk
    .addr_i 		(addr_apb),                  // synchronise these signal with respect to apb_clk
    .rdata_o 		(rd_data_apb),               // synchronise these signal with respect to apb_clk
    .rdata_valid_o  (rd_data_valid_apb),         // synchronise these signal with respect to apb_clk
    .rdy_o  		(rdy_apb),                   // synchronise these signal with respect to apb_clk
    .wr_i 			(wr_en_apb),                 // synchronise these signal with respect to apb_clk
    .rd_i 			(rd_en_apb),                 // synchronise these signal with respect to apb_clk
    .slverr 		(),                          // synchronise these signal with respect to apb_clk
	// apb interface
    .apb_clk_i 		(apb_clk_i),
    .apb_reset_n_i  (apb_reset_n_i),
    .apb_addr_o 	(apb_addr_o),
	.apb_sel_o  	(apb_sel_o),
	.apb_enable_o 	(apb_enable_o),
	.apb_write_o  	(apb_write_o),
	.apb_wdata_o  	(apb_wdata_o),
	.apb_rdata_i  	(apb_rdata_i),
	.apb_ready_i  	(apb_ready_i),
	.apb_slverr_i 	(apb_slverr_i)
);


endmodule
