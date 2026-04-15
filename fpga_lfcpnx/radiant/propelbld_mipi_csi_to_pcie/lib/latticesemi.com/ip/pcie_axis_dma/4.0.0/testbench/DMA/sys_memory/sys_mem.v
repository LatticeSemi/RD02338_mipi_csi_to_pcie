module sys_mem #

( //--begin_param--
//----------------------------
// Parameters
//----------------------------
parameter                     USE_EBR   = 1,
parameter                     MEM_DEPTH = 1024,
parameter                     INITMODE  = 0, // {0 - initialize to all 0,
                                             //  1 - initialize to all 1,
                                             //  2 - use initilization file}
                                             //  3 - no initialization}
parameter                     INIT_FMT  = "HEX",   // init file data format {"BINARY" or "BIN", "HEXADECIMAL" or "HEX"}
parameter                     INITFILE  = "none",
parameter					  NO_LANES = 4,
parameter 					  DATA_WIDTH = 128

) //--end_param--

( //--begin_ports--
input                         		ahbl_hclk_i,
input                         		ahbl_hresetn_i,

// ----------------------------
// AHB-Lite Master Interface 0
// ----------------------------
input                         		ahbl_s0_hsel_i,
input                         		ahbl_s0_hready_i,
input       [31:0]            		ahbl_s0_haddr_i,
input       [2:0]             		ahbl_s0_hburst_i,
input       [2:0]             		ahbl_s0_hsize_i,
input       [1:0]             		ahbl_s0_htrans_i,
input                         		ahbl_s0_hwrite_i,
input       [DATA_WIDTH-1:0]  		ahbl_s0_hwdata_i,
		
output wire                   		ahbl_s0_hreadyout_o,
output wire                   		ahbl_s0_hresp_o,
output wire [DATA_WIDTH-1:0]  		ahbl_s0_hrdata_o,

// ----------------------------
// AHB-Lite Master Interface 1
// ----------------------------
input                         		ahbl_s1_hsel_i,
input                         		ahbl_s1_hready_i,
input       [31:0]            		ahbl_s1_haddr_i,
input       [2:0]             		ahbl_s1_hburst_i,
input       [2:0]             		ahbl_s1_hsize_i,
input       [1:0]             		ahbl_s1_htrans_i,
input                         		ahbl_s1_hwrite_i,
input       [NO_LANES*64-1:0]       ahbl_s1_hwdata_i,

output wire                   		ahbl_s1_hreadyout_o,
output wire                   		ahbl_s1_hresp_o,
output wire [NO_LANES*64-1:0]       ahbl_s1_hrdata_o,

//----------------------------
// register interface
//----------------------------
output reg                    dma_done_status,
output reg                    dma_err_status ,
output reg                    dma_abor_status,
input  [7:0]                  num_of_descr,
output reg                    dma_compl,
input                         start_dma

); //--end_ports--

wire [127:0] ahbl_s1_hrdata_o_prev;

function [31:0] clog2;
  input [31:0] value;
  reg   [31:0] num;
begin
  num = value - 1;
  for (clog2=0; num>0; clog2=clog2+1) num = num>>1;
end
endfunction


//--------------------------------------------------------------------------
//--- Local Parameters/Defines ---
//--------------------------------------------------------------------------
localparam                    AWID = clog2(MEM_DEPTH);
localparam                    WORD_AWID = (AWID > 30)? 30 : AWID;

//--------------------------------------------------------------------------
//--- Combinational Wire/Reg ---
//--------------------------------------------------------------------------
reg                           			RdA_nxt;              // To inst_mem_model of mem_model.v
reg                           			RdB_nxt;              // To inst_mem_model of mem_model.v
reg                           			WrA_nxt;              // To inst_mem_model of mem_model.v
reg                           			WrB_nxt;              // To inst_mem_model of mem_model.v
reg         [AWID-1:0]        			AddressA_nxt;         // To inst_mem_model of mem_model.v
reg         [AWID-1:0]        			AddressB_nxt;         // To inst_mem_model of mem_model.v
/*AUTOREGINPUT*/
/*AUTOWIRE*/
wire        [DATA_WIDTH-1:0]            DatA;             // From inst_mem_model of mem_model.v
wire        [DATA_WIDTH-1:0]            DatB;             // From inst_mem_model of mem_model.v
wire                          			det_RdA;
wire                          			det_RdB;
reg                           			dma_compl_d;

//--------------------------------------------------------------------------
//--- Registers ---
//--------------------------------------------------------------------------
reg         [AWID-1:0]        			AddressA;         // To inst_mem_model of mem_model.v
reg         [AWID-1:0]        			AddressB;         // To inst_mem_model of mem_model.v
reg                           			RdA;              // To inst_mem_model of mem_model.v
reg                           			RdB;              // To inst_mem_model of mem_model.v
reg                           			RdB_d;              // To inst_mem_model of mem_model.v
reg                           			WrA;              // To inst_mem_model of mem_model.v
reg                           			WrB;              // To inst_mem_model of mem_model.v
reg         [3:0]             			BEnA;             // To inst_mem_model of mem_model.v
reg         [3:0]             			BEnB;             // To inst_mem_model of mem_model.v
reg         [DATA_WIDTH-1:0]            DatA_q;           // From inst_mem_model of mem_model.v
reg         [DATA_WIDTH-1:0]            DatB_q;           // From inst_mem_model of mem_model.v

/* This block is sniffing out the status bits so that software can be notified by one bit only.*/
reg 		[15:0]						ahbl_s0_haddr_i_d;
reg 		[7:0] 						desc_served_counter;
reg 		[1:0] 						ahbl_s0_htrans_i_d;

always @(posedge ahbl_hclk_i or negedge ahbl_hresetn_i)
begin 
    if (!ahbl_hresetn_i) 
	begin 
	    ahbl_s0_haddr_i_d     <= 16'h0000;
		ahbl_s0_htrans_i_d    <= 2'b0;
		dma_done_status       <= 1'b0;
		dma_err_status        <= 1'b0;
		dma_abor_status       <= 1'b0;
		desc_served_counter   <= 8'd0;
		dma_compl             <= 1'b0;
		dma_compl_d             <= 1'b0;
	end 
	else 
	begin 
		dma_compl_d <= dma_compl;
	    if (start_dma)
		    dma_compl             <= 1'b0;
		else if ((num_of_descr == desc_served_counter) && (num_of_descr != 8'h0))
			dma_compl       <= 1'b1;
		else 
		    dma_compl         <= dma_compl;
	        ahbl_s0_haddr_i_d     <= ahbl_s0_haddr_i[15:0];
	        ahbl_s0_htrans_i_d    <=ahbl_s0_htrans_i;
		
		if (start_dma)
		begin 
		    dma_done_status       <= 1'b0;
		    dma_err_status        <= 1'b0;
		    dma_abor_status       <= 1'b0;
		    desc_served_counter   <= 8'd0;
		end 
		else if ((ahbl_s0_haddr_i_d[15:12] == 4'h1) && ((ahbl_s0_haddr_i_d[3:0] == 4'h0) || (ahbl_s0_haddr_i_d[3:0] == 4'h8)) && (ahbl_s0_hsel_i == 1'b1) && (ahbl_s0_htrans_i_d[1]== 1'b1))
		begin 
		    dma_done_status     <= dma_done_status | ahbl_s0_hwdata_i[0];
			dma_err_status      <= dma_err_status  | ahbl_s0_hwdata_i[1];
			dma_abor_status     <= dma_abor_status | ahbl_s0_hwdata_i[2];
			desc_served_counter <= desc_served_counter + 1'd1;
		end 
		else 
		begin 
		    dma_done_status     <= dma_done_status;
		    dma_err_status      <= dma_err_status ;
		    dma_abor_status     <= dma_abor_status;
			desc_served_counter <= desc_served_counter;
		end 
	end 
end 


assign ahbl_s0_hreadyout_o 		= 		~(det_RdA & WrA);
assign ahbl_s1_hreadyout_o 		= 		~(det_RdB & WrB);
assign ahbl_s0_hresp_o     		= 		1'b0;
assign ahbl_s1_hresp_o     		= 		1'b0;
assign ahbl_s0_hrdata_o    		= 		(RdA)? DatA : DatA_q;
assign ahbl_s1_hrdata_o_prev    = 		(NO_LANES == 4) ? ((RdB)? DatB : DatB_q) : 128'b0;
assign ahbl_s1_hrdata_o    		= 		(NO_LANES == 4) ? ((AddressB_nxt[0]) ? {ahbl_s1_hrdata_o_prev,128'b0} : {128'b0,ahbl_s1_hrdata_o_prev}) : ((RdB)? DatB : DatB_q);
assign det_RdA             		= 		~ahbl_s0_hwrite_i & ahbl_s0_htrans_i[1] & ahbl_s0_hsel_i;
assign det_RdB             		= 		~ahbl_s1_hwrite_i & ahbl_s1_htrans_i[1] & ahbl_s1_hsel_i;
//--------------------------------------------
//-- Combinational block --
//--------------------------------------------
always @* begin
  WrA_nxt =  ahbl_s0_hwrite_i & ahbl_s0_htrans_i[1] & ahbl_s0_hready_i & ahbl_s0_hsel_i;
  WrB_nxt =  ahbl_s1_hwrite_i & ahbl_s1_htrans_i[1] & ahbl_s1_hready_i & ahbl_s1_hsel_i;
  RdA_nxt =  det_RdA & ahbl_s0_hready_i & ahbl_s0_hreadyout_o;
  RdB_nxt =  det_RdB & ahbl_s1_hready_i & ahbl_s1_hreadyout_o;
  AddressA_nxt = (RdA_nxt & ~WrA)? ((NO_LANES == 1)? ({ahbl_s0_haddr_i[WORD_AWID+2:3]}) : ({ahbl_s0_haddr_i[WORD_AWID+3:4]})) : AddressA;
  AddressB_nxt = (RdB_nxt & ~WrB)? ((NO_LANES == 1)? ({ahbl_s1_haddr_i[WORD_AWID+2:3]}) : ({ahbl_s1_haddr_i[WORD_AWID+3:4]})) : AddressB;
end //--always @*--


//--------------------------------------------
//-- Sequential block --
//--------------------------------------------
always @(posedge ahbl_hclk_i or negedge ahbl_hresetn_i) begin
  if(~ahbl_hresetn_i) begin
    /*AUTORESET*/
    // Beginning of autoreset for uninitialized flops
    AddressA <= {AWID{1'b0}};
    AddressB <= {AWID{1'b0}};
    BEnA <= 4'h0;
    BEnB <= 4'h0;
    DatA_q <= {(DATA_WIDTH-1){1'b0}};
    DatB_q <= {(DATA_WIDTH-1){1'b0}};
    RdA <= 1'h0;
    RdB <= 1'h0;
    WrA <= 1'h0;
    WrB <= 1'h0;
    RdB_d <= 1'h0;
    // End of automatics
  end
  else begin
    AddressA <=  (WrA_nxt | RdA_nxt)? ((NO_LANES == 1)?({ahbl_s0_haddr_i[WORD_AWID+2:3]}) : ({ahbl_s0_haddr_i[WORD_AWID+3:4]})) : AddressA;
    AddressB <=  (dma_compl == 0 & dma_compl_d == 1)? 0 : ((WrB_nxt | RdB_nxt)? ((NO_LANES == 1)?({ahbl_s1_haddr_i[WORD_AWID+2:3]}) : ({ahbl_s1_haddr_i[WORD_AWID+3:4]})) : AddressB);
    WrA      <=  WrA_nxt;
    WrB      <=  WrB_nxt;
    RdA      <=  RdA_nxt;
    RdB      <=  RdB_nxt;
    RdB_d    <=  RdB;
    DatA_q   <=  ahbl_s0_hrdata_o;
    if(NO_LANES == 4) begin
    	DatB_q   <=  ahbl_s1_hrdata_o_prev;
    end 
    else begin
    	DatB_q   <=  ahbl_s1_hrdata_o;
    end 
    BEnA     <=  (ahbl_s0_haddr_i[1:0] == 2'd0)? ((ahbl_s0_hsize_i == 3'd0)? 4'h1 :
                                                  (ahbl_s0_hsize_i == 3'd1)? 4'h3 : 4'hF) :
                 (ahbl_s0_haddr_i[1:0] == 2'd1)? ((ahbl_s0_hsize_i == 3'd0)? 4'h2 :
                                                  (ahbl_s0_hsize_i == 3'd1)? 4'h6 : 4'hE) :
                 (ahbl_s0_haddr_i[1:0] == 2'd2)? ((ahbl_s0_hsize_i == 3'd0)? 4'h4 : 4'hC) :
                                                 4'h8;
    BEnB     <=  (ahbl_s1_haddr_i[1:0] == 2'd0)? ((ahbl_s1_hsize_i == 3'd0)? 4'h1 :
                                                  (ahbl_s1_hsize_i == 3'd1)? 4'h3 : 4'hF) :
                 (ahbl_s1_haddr_i[1:0] == 2'd1)? ((ahbl_s1_hsize_i == 3'd0)? 4'h2 :
                                                  (ahbl_s1_hsize_i == 3'd1)? 4'h6 : 4'hE) :
                 (ahbl_s1_haddr_i[1:0] == 2'd2)? ((ahbl_s1_hsize_i == 3'd0)? 4'h4 : 4'hC) :
                                                 4'h8;
  end
end 

//--------------------------------------------------------------------------
//--- Module Instantiation ---
//--------------------------------------------------------------------------
localparam DATA_DEPTH = (512*128)/DATA_WIDTH;
localparam ADDR_LANES = clog2(DATA_DEPTH);
localparam DATA_LANES = clog2(DATA_WIDTH);

tdpram_sys_memory  #(
		.ADDR_DEPTH_A (DATA_DEPTH						),
		.DATA_WIDTH_A (DATA_WIDTH						),
		.ADDR_DEPTH_B (DATA_DEPTH						),
		.DATA_WIDTH_B (DATA_WIDTH						),
		.ADDR_LANES	  (ADDR_LANES						),
		.DATA_WIDTH	  (DATA_LANES						)
	)
	sys_mem_tdp_inst
	(	.clk_a_i	  (ahbl_hclk_i 						),
        .clk_b_i	  (ahbl_hclk_i 						),
        .rst_a_i	  (~ahbl_hresetn_i 					),
        .rst_b_i	  (~ahbl_hresetn_i 					),
        .clk_en_a_i	  (1'b1 							),
        .clk_en_b_i	  (1'b1 							),
        .wr_en_a_i	  (WrA 								),
        .wr_en_b_i	  (WrB 								),
        .wr_data_a_i  (ahbl_s0_hwdata_i 				),
        .addr_a_i	  (AddressA_nxt[AWID-1:0] 			),
        .rd_data_a_o  (DatA[DATA_WIDTH-1:0] 			),
        .wr_data_b_i  (ahbl_s1_hwdata_i[DATA_WIDTH-1:0] ),
        .addr_b_i	  (AddressB_nxt[AWID-1:0]			),
        .rd_data_b_o  (DatB[DATA_WIDTH-1:0]  			)
		); 
		
    





endmodule //--sys_mem--



