module display_controller (
    input clk,
    input rstn,
    input [6:0] segment_DIG0,
    input [6:0] segment_DIG1,
    input [6:0] segment_DIG2,
    output reg [6:0] segment_out,
    output reg [2:0] segment_en
);

reg [8:0] counter = 9'd0;
reg [2:0] shift = 3'b001;

reg [2:0] shift_d;
reg [2:0] shift_2d;
reg [2:0] shift_3d;

reg [6:0] segment_out_d = 7'd0;
reg [6:0] segment_out_2d = 7'd0;

reg en_pulse_d;
reg en_pulse_2d;

reg [2:0] segment_en_reg0;
reg [2:0] segment_en_reg1;
reg [2:0] segment_en_reg2;
reg [2:0] segment_en_reg3;


reg [6:0] segment_out_reg0;
reg [6:0] segment_out_reg1;
reg [6:0] segment_out_reg2;
reg [6:0] segment_out_reg3;

always @(posedge clk)
    begin 
        if (counter[8])
            counter    <= 9'd0;
        else 
            counter    <= counter + 1'b1;
    end 

assign en_pulse  = counter[7];

always @(posedge clk) begin 
    if (counter[8])
        shift          <= {shift[1:0] ,shift[2]};
    else 
        shift          <= shift;
end

// added on 20th august 
always @(posedge clk) begin 

     shift_d <= shift;
     
     segment_en_reg0     <= (en_pulse) ? shift_d : 3'b000;
     segment_en_reg1     <= segment_en_reg0;
     segment_en_reg2     <= segment_en_reg1;
     segment_en_reg3     <= segment_en_reg2;
     segment_en          <= segment_en_reg3;
    
     segment_out_reg0      <= (shift_d[0] & en_pulse) ? segment_DIG0 : segment_out_d;
     segment_out_d    <= (shift_d[1] & en_pulse) ? segment_DIG1 : segment_out_2d;
    
     segment_out_2d   <= (shift_d[2] & en_pulse) ? segment_DIG2 : 7'd0;
    
     segment_out_reg1 <= segment_out_reg0;
     segment_out_reg2 <= segment_out_reg1;
     segment_out_reg3 <= segment_out_reg2;
     segment_out      <= segment_out_reg3;
     
     
    end  
  //end 
endmodule