// This module is generating the APB interface signals. It is taking data from the user interface and generating 
// the corresponding write or read transaction through APB interface.
//                    ____________
//                   |            |
//  user interface --| apb master |-- apb interface
//                   |____________|
//

`timescale 1ps / 1ps

//******************************
//    module definition        *
//******************************

module apb_master (
    //  user interface
	input [31:0]  wdata_i,   // input data to write through the APB interface.
	input [31:0]  addr_i,    
	output [31:0] rdata_o,  // data which is read through the APB interface.
	output reg       rdata_valid_o,   // active high signal indicating a valid out data.
	output reg       rdy_o,           // active high signal indicating that apb master is ready to take data.
	input         wr_i ,            // active high signal indicating a write transaction would be made through APB interface.
	input         rd_i,             // active high signal indicating a read transaction would be  made through APB interface.
	output reg       slverr,           // when '1' then error else no error.
	// APB interface
	input            apb_clk_i,
	input            apb_reset_n_i,
	output reg [31:0]    apb_addr_o,
	output reg           apb_sel_o,
	output reg           apb_enable_o,
	output reg           apb_write_o,
	output reg [31:0]    apb_wdata_o,
	input [31:0]     apb_rdata_i,
	input            apb_ready_i,
	input            apb_slverr_i
);

localparam      ST_APB_IDLE       = 3'd0 ;
localparam      ST_APB_WRITE      = 3'd1 ;
localparam      ST_APB_WAIT_WRITE = 3'd2 ;
localparam      ST_APB_READ       = 3'd3 ;
localparam      ST_APB_WAIT_READ  = 3'd4 ;
localparam      ST_APB_DONE       = 3'd5 ;
assign rdata_o         = apb_rdata_i;
reg [2:0] apb_sm;

always @(posedge apb_clk_i or negedge apb_reset_n_i)
begin 
    if (~apb_reset_n_i) 
	begin 
	    apb_sm             <= 3'h0;
	    apb_addr_o         <= 32'h0;
        apb_enable_o       <= 1'h0;
        apb_sel_o          <= 1'h0;
        apb_wdata_o        <= 32'h0;
        apb_write_o        <= 1'h0;
		rdy_o              <= 1'b0;
	end 
	else 
	begin 
	    case(apb_sm)
		    ST_APB_WRITE : begin
                apb_sm            <= ST_APB_WAIT_WRITE;
                apb_enable_o      <= 1'b1;
				rdy_o             <= 1'b0;
            end
			ST_APB_WAIT_WRITE : begin
			    rdy_o             <= 1'b0;
                if(apb_ready_i) begin
                  apb_sm          <= ST_APB_DONE;
                  apb_enable_o    <= 1'b0;
                  apb_sel_o       <= 1'b0;
                  slverr          <= apb_slverr_i;
                end
                else
                  apb_sm          <= ST_APB_WAIT_WRITE;
            end
			ST_APB_READ : begin
			    rdy_o             <= 1'b0;
                apb_sm            <= ST_APB_WAIT_READ;
                apb_enable_o      <= 1'b1;
            end
			ST_APB_WAIT_READ : begin
			    rdy_o             <= 1'b0;
                if(apb_ready_i) begin
                  apb_sm          <= ST_APB_DONE;
                  apb_enable_o    <= 1'b0;
                  apb_sel_o       <= 1'b0;
                  slverr          <= apb_slverr_i;
                  
                  rdata_valid_o   <= 1'b1;
                end
                else
                  apb_sm          <= ST_APB_WAIT_READ;
            end
			ST_APB_DONE : begin
			    rdy_o             <= 1'b1;
                if(wr_i | rd_i)
                  apb_sm         <= ST_APB_DONE;
                else begin
                  apb_sm         <= ST_APB_IDLE;
                  rdata_valid_o  <= 1'b0;
                  slverr         <= 1'b0;
                end
            end
			default : begin // ST_APB_IDLE
                case({wr_i, rd_i})
                  2'b00   : apb_sm   <= ST_APB_IDLE;
                  2'b10   : apb_sm   <= ST_APB_WRITE;
                  2'b01   : apb_sm   <= ST_APB_READ;
                  default : apb_sm   <= ST_APB_IDLE;
                endcase
                apb_sel_o         <= wr_i | rd_i;
                apb_addr_o        <= addr_i;
                apb_wdata_o       <= wdata_i;
                apb_write_o       <= wr_i;
                apb_enable_o      <= 1'b0;
				rdy_o             <= 1'b1;
            end
		endcase
	end 
end 
endmodule