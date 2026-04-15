module mux_synchronizer #(
    parameter DATA_WIDTH = 8
)
(
    input 								clkA,	
	input 								clkB,
	input 								rstn,
	input 	   [DATA_WIDTH - 1:0] 		data_in,
	input  								data_in_valid,
	output reg [DATA_WIDTH - 1:0] 		data_out,
	output reg 							data_out_valid
);

reg data_in_valid_d;
reg data_in_valid_2d;

(*ASYNC_REG="TRUE"*) reg data_in_valid_stretch_d;
(*ASYNC_REG="TRUE"*) reg data_in_valid_stretch_2d;
wire data_in_valid_b;

assign data_in_valid_stretch = data_in_valid | data_in_valid_d | data_in_valid_2d;
always @(posedge clkA or negedge rstn)
begin 
    if (!rstn)
	begin
	    data_in_valid_d    <= 1'b0;
	    data_in_valid_2d   <= 1'b0;
	end 
	else 
	begin 
	    data_in_valid_d      <= data_in_valid;
	    data_in_valid_2d     <= data_in_valid_d;
	end 
end 

assign data_in_valid_b       = data_in_valid_stretch_d & (!data_in_valid_stretch_2d);
always @(posedge clkB or negedge rstn) 
begin 
    if (!rstn)
	begin
	    data_in_valid_stretch_d      <= 1'b0;
	    data_in_valid_stretch_2d     <= 1'b0;
	    data_out                     <= 'b0;
		data_out_valid               <= 1'b0;
	end 
	else 
	begin 
	    data_in_valid_stretch_d      <= data_in_valid_stretch;
	    data_in_valid_stretch_2d     <= data_in_valid_stretch_d;
	    if (data_in_valid_b)
		begin 
	        data_out             <= data_in;
			data_out_valid       <= 1'b1;
		end 
		else 
		begin 
		    data_out             <= data_out;
		    data_out_valid       <= 1'b0;
		end 
	end 
end 
endmodule