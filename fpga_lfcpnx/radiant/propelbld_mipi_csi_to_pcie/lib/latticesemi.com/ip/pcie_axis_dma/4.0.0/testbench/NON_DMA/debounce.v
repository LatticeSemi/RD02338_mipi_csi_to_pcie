module debounce # (
    parameter SIM    = 0
)(
    input    clk,     // input clock
	input    pb_in_n,   // push button input which is to be debounce
	output   pb_out   // output debounced signal
);

localparam debounce_counter = 32'd100000000;
localparam debounce_counter_o = 32'd000000100;
reg pb_flag;
reg [31:0] stable_pulse_counter;
reg debounced_sig_int;
(* ASYNC_REG="TRUE" *)reg debounced_sig_int_d ;
(* ASYNC_REG="TRUE" *)reg debounced_sig_int_2d;
(* ASYNC_REG="TRUE" *)reg debounced_sig_int_3d;

// generating a active low signal whose assertion is asynchronous but de-assertion is synchronous.
always @(posedge clk or negedge pb_in_n)
begin 
    if (!pb_in_n)
	    pb_flag      <= 1'b0;
	else 
	    pb_flag      <= 1'b1;
end 


//counting the active low signal
generate 
if (SIM ==0) begin 
always @(posedge clk or negedge pb_flag)
begin 
    if (!pb_flag)
	begin 
	    stable_pulse_counter     <= debounce_counter;
	end 
	else 
	begin 
	    if (stable_pulse_counter == 0)
		    stable_pulse_counter   <= 0;
		else 
		    stable_pulse_counter     <= stable_pulse_counter - 1'b1;
    end 
end 
end 
else 
begin 
always @(posedge clk or negedge pb_flag)
begin 
    if (!pb_flag)
	begin 
	    stable_pulse_counter     <= debounce_counter_o;
	end 
	else 
	begin 
	    if (stable_pulse_counter == 0)
		    stable_pulse_counter   <= 0;
		else 
		    stable_pulse_counter     <= stable_pulse_counter - 1'b1;
    end 	
end 
end
endgenerate

// asynchronous assertion and synchronous de-assertion pulse after debouncing 
always @(*)
begin 
    if (stable_pulse_counter == 0)
	    debounced_sig_int    = 1'b1;
	else 
	    debounced_sig_int    = 1'b0;
end 

// synchronising the pulse 
always @(posedge clk)
begin 
    debounced_sig_int_d        <= debounced_sig_int;
    debounced_sig_int_2d       <= debounced_sig_int_d;
    debounced_sig_int_3d       <= debounced_sig_int_2d;
end 

assign pb_out  = debounced_sig_int_3d;

endmodule