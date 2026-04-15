
`timescale 1ps/1ps

module pcie_tx_engine #(
    parameter DATA_WIDTH = 32,
    parameter NUM_OF_LANES = 1,
    parameter MPS_BYTES    = 512, // KD
    parameter DW_ALIGN_RAM = 0    // KD: additional read latency due to address flop
	)
	(
	input                   clk,
	input                   rst_n,
	// tx TLP interface
    output                  vc_tx_valid_o_d ,
    output                  vc_tx_eop_o_d ,
    output                  vc_tx_eop_n_o_d, 
    output                  vc_tx_sop_o_d ,
    output                  [DATA_WIDTH-1:0] vc_tx_data_o_d ,
    output                  [DATA_WIDTH/8-1:0] vc_tx_datap_o_d ,
	output  reg 			[31:0] rd_data_counter,
    input                   vc_tx_ready_i ,
	//completer id from ucfg space
	input [15:0]            completer_id,
	// rx TLP info for handshaking
	input                   req_compl,
	// KD output reg              compl_done,	
	output                  e2e_compl_done,	
	input [2:0]             req_tc,                                 // Memory Read TC
    input                   req_td,                                 // Memory Read TD
    input                   req_ep,                                 // Memory Read EP
    input [1:0]             req_attr,                               // Memory Read Attribute
    input [9:0]             req_len,                                // Memory Read Length (1DW)
    input [15:0]            req_rid,                                // Memory Read Requestor ID
    input [7:0]             req_tag,                                // Memory Read Tag
    input [7:0]             req_be,                                 // Memory Read Byte Enables
    input [31:0]            req_addr,                               // Memory Read Address
	// memory interface.
	output [13:0]           rd_addr,
	output [3:0]            rd_be,
	output                  rd_en,  
	input [DATA_WIDTH-1:0]  rd_data                                          
);

// KD
localparam FIRST_PYLD_DW = (DATA_WIDTH >= 128)? 3 : 1;
localparam ADD_BIT_LOW  = $clog2(DATA_WIDTH/8);
localparam TXQ_DEPTH = (MPS_BYTES*8/DATA_WIDTH);
localparam CONST_1 = 1;
localparam CONST_2 = 2;
localparam CONST_3 = 3;
localparam CONST_4 = 4;
localparam CONST_5 = 5;
localparam CONST_6 = 6;

localparam CPLD_FMT_TYPE = 7'b10_01010;
localparam rst_state = 4'b0000;
localparam send_wait_state  = 4'b0001;
localparam send_DW1  = 4'b0010;
localparam send_DW2  = 4'b0011;
localparam send_DW3  = 4'b0100;
localparam send_Data = 4'b1000;

reg [3:0] state ;

// KD
reg [11:0] singledw_byte_count;
reg [11:0] byte_count;
reg [6:0] lower_addr;
reg [9:0] dw_counter;

reg vc_tx_valid_o ;
reg vc_tx_eop_o ;
wire vc_tx_eop_n_o;
reg vc_tx_sop_o ;
reg [DATA_WIDTH-1:0] vc_tx_data_o ;
// KD 
reg [(DATA_WIDTH/8)-1:0] vc_tx_datap_o ;

reg vc_tx_ready_i_d;
wire vc_tx_ready_edge;

reg [DATA_WIDTH-1:0] rd_data_d;
reg [DATA_WIDTH-1:0] rd_data_2d;

reg rd_en_sig;
// KD the original module here never handle throttling properly
// will make the FSM not to thrrole for the update to support MPS_BYTES
// add a Queue at next stage to handle the txtlp intf throttling 
// assign rd_en = vc_tx_ready_i&rd_en_sig;
reg compl_done; // KD 
reg rd_en_sig_d, rd_en_sig_2d, rd_en_sig_3d; // KD: rd latency
assign rd_en = rd_en_sig;
// KD
wire [3:0] raw_lbe, raw_fbe;
assign raw_lbe = req_be[7:4];
assign raw_fbe = req_be[3:0];

assign rd_be = req_be[3:0];
assign vc_tx_eop_n_o  = 1'b0;

// KD
wire txq_empty;
reg compl_pend_flag;
assign e2e_compl_done = compl_pend_flag & txq_empty;

always @(posedge clk) begin
    if (!rst_n) begin
        rd_en_sig_d  <= 1'b0;
        rd_en_sig_2d <= 1'b0;
	rd_en_sig_3d <= 1'b0;
        compl_pend_flag <= 1'b0;
    end
    else begin
        rd_en_sig_d  <= rd_en_sig;
	rd_en_sig_2d <= rd_en_sig_d;
	rd_en_sig_3d <= rd_en_sig_2d;
        compl_pend_flag <= compl_done? 1'b1 : e2e_compl_done? 1'b0 : compl_pend_flag;
    end
end

generate 
// KD if(DATA_WIDTH==512)
if((DATA_WIDTH==512) || (DATA_WIDTH==256) || (DATA_WIDTH==128) || (DATA_WIDTH==64))
begin 

// KD assign rd_addr = {req_addr [13:5] , 5'b00000}; 
// KD assign rd_addr = {req_addr[13:ADD_BIT_LOW], {ADD_BIT_LOW{1'b0}}}; 
assign rd_addr = {req_addr[13:2], 2'b00}; 

assign vc_tx_datap_o[0]  = ^(vc_tx_data_o[7:0]);
assign vc_tx_datap_o[1]  = ^(vc_tx_data_o[15:8]);
assign vc_tx_datap_o[2]  = ^(vc_tx_data_o[23:16]);
assign vc_tx_datap_o[3]  = ^(vc_tx_data_o[31:24]);
assign vc_tx_datap_o[4]  = ^(vc_tx_data_o[39:32]);
assign vc_tx_datap_o[5]  = ^(vc_tx_data_o[47:40]);
assign vc_tx_datap_o[6]  = ^(vc_tx_data_o[55:48]);
assign vc_tx_datap_o[7]  = ^(vc_tx_data_o[63:56]);

// KD
if((DATA_WIDTH==512) || (DATA_WIDTH==256) || (DATA_WIDTH==128))
begin
assign vc_tx_datap_o[8]  = ^(vc_tx_data_o[71:64]);
assign vc_tx_datap_o[9]  = ^(vc_tx_data_o[79:72]);
assign vc_tx_datap_o[10] = ^(vc_tx_data_o[87:80]);
assign vc_tx_datap_o[11] = ^(vc_tx_data_o[95:88]);
assign vc_tx_datap_o[12] = ^(vc_tx_data_o[103:96]);
assign vc_tx_datap_o[13] = ^(vc_tx_data_o[111:104]);
assign vc_tx_datap_o[14] = ^(vc_tx_data_o[119:112]);
assign vc_tx_datap_o[15] = ^(vc_tx_data_o[127:120]);
end // KD

// KD
if((DATA_WIDTH==512) || (DATA_WIDTH==256))
begin
assign vc_tx_datap_o[16] = ^(vc_tx_data_o[135:128]);
assign vc_tx_datap_o[17] = ^(vc_tx_data_o[143:136]);
assign vc_tx_datap_o[18] = ^(vc_tx_data_o[151:144]);
assign vc_tx_datap_o[19] = ^(vc_tx_data_o[159:152]);
assign vc_tx_datap_o[20] = ^(vc_tx_data_o[167:160]);
assign vc_tx_datap_o[21] = ^(vc_tx_data_o[175:168]);
assign vc_tx_datap_o[22] = ^(vc_tx_data_o[183:176]);
assign vc_tx_datap_o[23] = ^(vc_tx_data_o[191:184]);
assign vc_tx_datap_o[24] = ^(vc_tx_data_o[199:192]);
assign vc_tx_datap_o[25] = ^(vc_tx_data_o[207:200]);
assign vc_tx_datap_o[26] = ^(vc_tx_data_o[215:208]);
assign vc_tx_datap_o[27] = ^(vc_tx_data_o[223:216]);
assign vc_tx_datap_o[28] = ^(vc_tx_data_o[231:224]);
assign vc_tx_datap_o[29] = ^(vc_tx_data_o[239:232]);
assign vc_tx_datap_o[30] = ^(vc_tx_data_o[247:240]);
assign vc_tx_datap_o[31] = ^(vc_tx_data_o[255:248]);
end // KD

// KD
if((DATA_WIDTH==512))
begin
assign vc_tx_datap_o[32]  = ^(vc_tx_data_o[263:256]);
assign vc_tx_datap_o[33]  = ^(vc_tx_data_o[271:264]);
assign vc_tx_datap_o[34]  = ^(vc_tx_data_o[279:272]);
assign vc_tx_datap_o[35]  = ^(vc_tx_data_o[287:280]);
assign vc_tx_datap_o[36]  = ^(vc_tx_data_o[295:288]);
assign vc_tx_datap_o[37]  = ^(vc_tx_data_o[303:296]);
assign vc_tx_datap_o[38]  = ^(vc_tx_data_o[311:304]);
assign vc_tx_datap_o[39]  = ^(vc_tx_data_o[319:312]);
assign vc_tx_datap_o[40]  = ^(vc_tx_data_o[327:320]);
assign vc_tx_datap_o[41]  = ^(vc_tx_data_o[335:328]);
assign vc_tx_datap_o[42] = ^(vc_tx_data_o[343:336]);
assign vc_tx_datap_o[43] = ^(vc_tx_data_o[351:344]);
assign vc_tx_datap_o[44] = ^(vc_tx_data_o[359:352]);
assign vc_tx_datap_o[45] = ^(vc_tx_data_o[367:360]);
assign vc_tx_datap_o[46] = ^(vc_tx_data_o[375:368]);
assign vc_tx_datap_o[47] = ^(vc_tx_data_o[383:376]);
assign vc_tx_datap_o[48] = ^(vc_tx_data_o[391:384]);
assign vc_tx_datap_o[49] = ^(vc_tx_data_o[399:392]);
assign vc_tx_datap_o[50] = ^(vc_tx_data_o[407:400]);
assign vc_tx_datap_o[51] = ^(vc_tx_data_o[415:408]);
assign vc_tx_datap_o[52] = ^(vc_tx_data_o[423:416]);
assign vc_tx_datap_o[53] = ^(vc_tx_data_o[431:424]);
assign vc_tx_datap_o[54] = ^(vc_tx_data_o[439:432]);
assign vc_tx_datap_o[55] = ^(vc_tx_data_o[447:440]);
assign vc_tx_datap_o[56] = ^(vc_tx_data_o[455:448]);
assign vc_tx_datap_o[57] = ^(vc_tx_data_o[463:456]);
assign vc_tx_datap_o[58] = ^(vc_tx_data_o[471:464]);
assign vc_tx_datap_o[59] = ^(vc_tx_data_o[479:472]);
assign vc_tx_datap_o[60] = ^(vc_tx_data_o[487:480]);
assign vc_tx_datap_o[61] = ^(vc_tx_data_o[495:488]);
assign vc_tx_datap_o[62] = ^(vc_tx_data_o[503:496]);
assign vc_tx_datap_o[63] = ^(vc_tx_data_o[511:504]);
/*
assign vc_tx_datap_o[32]  = ^(vc_tx_data_o[264:256]);
assign vc_tx_datap_o[33]  = ^(vc_tx_data_o[272:265]);
assign vc_tx_datap_o[34]  = ^(vc_tx_data_o[280:273]);
assign vc_tx_datap_o[35]  = ^(vc_tx_data_o[288:281]);
assign vc_tx_datap_o[36]  = ^(vc_tx_data_o[296:289]);
assign vc_tx_datap_o[37]  = ^(vc_tx_data_o[304:297]);
assign vc_tx_datap_o[38]  = ^(vc_tx_data_o[312:305]);
assign vc_tx_datap_o[39]  = ^(vc_tx_data_o[320:313]);
assign vc_tx_datap_o[40]  = ^(vc_tx_data_o[328:321]);
assign vc_tx_datap_o[41]  = ^(vc_tx_data_o[336:329]);
assign vc_tx_datap_o[42] = ^(vc_tx_data_o[344:337]);
assign vc_tx_datap_o[43] = ^(vc_tx_data_o[352:345]);
assign vc_tx_datap_o[44] = ^(vc_tx_data_o[360:353]);
assign vc_tx_datap_o[45] = ^(vc_tx_data_o[368:361]);
assign vc_tx_datap_o[46] = ^(vc_tx_data_o[376:369]);
assign vc_tx_datap_o[47] = ^(vc_tx_data_o[384:377]);
assign vc_tx_datap_o[48] = ^(vc_tx_data_o[392:385]);
assign vc_tx_datap_o[49] = ^(vc_tx_data_o[400:393]);
assign vc_tx_datap_o[50] = ^(vc_tx_data_o[408:401]);
assign vc_tx_datap_o[51] = ^(vc_tx_data_o[416:409]);
assign vc_tx_datap_o[52] = ^(vc_tx_data_o[424:417]);
assign vc_tx_datap_o[53] = ^(vc_tx_data_o[432:425]);
assign vc_tx_datap_o[54] = ^(vc_tx_data_o[440:433]);
assign vc_tx_datap_o[55] = ^(vc_tx_data_o[448:441]);
assign vc_tx_datap_o[56] = ^(vc_tx_data_o[456:449]);
assign vc_tx_datap_o[57] = ^(vc_tx_data_o[464:457]);
assign vc_tx_datap_o[58] = ^(vc_tx_data_o[472:465]);
assign vc_tx_datap_o[59] = ^(vc_tx_data_o[480:473]);
assign vc_tx_datap_o[60] = ^(vc_tx_data_o[488:481]);
assign vc_tx_datap_o[61] = ^(vc_tx_data_o[496:489]);
assign vc_tx_datap_o[62] = ^(vc_tx_data_o[504:497]);
assign vc_tx_datap_o[63] = ^(vc_tx_data_o[511:505]);
*/
end // KD

/*
assign vc_tx_valid_o_d    = vc_tx_valid_o ;
assign vc_tx_eop_o_d      = vc_tx_eop_o ;
assign vc_tx_eop_n_o_d    = vc_tx_eop_n_o; 
assign vc_tx_sop_o_d      = vc_tx_sop_o ;
assign vc_tx_data_o_d     = vc_tx_data_o ;

assign vc_tx_ready_edge   = (vc_tx_ready_i) & (~vc_tx_ready_i_d);
*/

// KD insert a queue to handle the vc_tx_ready_i
// 3 = eop, eop_n, sop
wire txq0_bus_valid;
wire [7:0] txq_bus_valid;
wire [7:0] txq_bus_ready;
wire [2:0] txq_bus_attr; 
wire [(8*(8+64))-1:0] txq_bus; 

assign txq_empty = ~(vc_tx_valid_o_d | txq_bus_valid[0]); // as long as avail, do not accept any new rx tlp 

  // per fabric LANE. eg: 512/8 = 64/lane
  pcie_flopq #(.WIDTH( 3 + 8 + 64), .DEPTH(TXQ_DEPTH)) txq0 (
    .clk(clk), .rst_n(rst_n),
    .ivalid(vc_tx_valid_o), .iready(),
    .idata({vc_tx_eop_o,  vc_tx_eop_n_o,  vc_tx_sop_o,   vc_tx_datap_o  [(0*8)+:8], vc_tx_data_o  [(0*64)+:64]}),
    .odata({txq_bus_attr[2:0], txq_bus[(0*72)+:72]}),
    .ovalid(txq_bus_valid[0]), .oready(txq_bus_ready[0])
  );
  pcie_flopq #(.WIDTH( 3 + 8 + 64), .DEPTH(2)) txq0skid (
    .clk(clk), .rst_n(rst_n),
    .ivalid(txq_bus_valid[0]), .iready(txq_bus_ready[0]),
    .idata({txq_bus_attr[2:0], txq_bus[(0*72)+:72]}),
    .odata({vc_tx_eop_o_d,vc_tx_eop_n_o_d,vc_tx_sop_o_d, vc_tx_datap_o_d[(0*8)+:8], vc_tx_data_o_d[(0*64)+:64]}),
    .ovalid(vc_tx_valid_o_d), .oready(vc_tx_ready_i)
  );

  // per fabric LANE. eg: 512/8 = 64/lane
  for (genvar x=1; x<(DATA_WIDTH/64); x++) begin	
  pcie_flopq #(.WIDTH( 8 + 64 ), .DEPTH(TXQ_DEPTH)) txqx (
    .clk(clk), .rst_n(rst_n),
    .ivalid(vc_tx_valid_o), .iready(),  
    .idata({vc_tx_datap_o  [(x*8)+:8], vc_tx_data_o  [(x*64)+:64]}),
    .odata(txq_bus[(x*72)+:72]),
    .ovalid(txq_bus_valid[x]), .oready(txq_bus_ready[x])
  );      
  pcie_flopq #(.WIDTH( 8 + 64 ), .DEPTH(2)) txqxskid (
    .clk(clk), .rst_n(rst_n),
    .ivalid(txq_bus_valid[x]), .iready(txq_bus_ready[x]),
    .idata(txq_bus[(x*72)+:72]),
    .odata({vc_tx_datap_o_d[(x*8)+:8], vc_tx_data_o_d[(x*64)+:64]}),
    .ovalid(), .oready(vc_tx_ready_i)
  );
  end
  
/* KD
 always @ (rd_be) begin
    casex (rd_be[3:0])
      4'b1xx1 : byte_count = 12'h004;
      4'b01x1 : byte_count = 12'h003;
      4'b1x10 : byte_count = 12'h003;
      4'b0011 : byte_count = 12'h002;
      4'b0110 : byte_count = 12'h002;
      4'b1100 : byte_count = 12'h002;
      4'b0001 : byte_count = 12'h001;
      4'b0010 : byte_count = 12'h001;
      4'b0100 : byte_count = 12'h001;
      4'b1000 : byte_count = 12'h001;
      4'b0000 : byte_count = 12'h001;
    endcase
  end
*/
       assign byte_count[11:$clog2(MPS_BYTES)+2]  = '0;
       assign byte_count[$clog2(MPS_BYTES)+1:0] = (raw_fbe[0] & raw_lbe[3])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} :
                                            (raw_fbe[0] & raw_lbe[2])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} - CONST_1[$clog2(MPS_BYTES)+1:0] :
                                            (raw_fbe[0] & raw_lbe[1])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} - CONST_2[$clog2(MPS_BYTES)+1:0] :
                                            (raw_fbe[0] & raw_lbe[0])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} - CONST_3[$clog2(MPS_BYTES)+1:0] :

                                            (raw_fbe[1] & raw_lbe[3])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} - CONST_1[$clog2(MPS_BYTES)+1:0] :
                                            (raw_fbe[1] & raw_lbe[2])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} - CONST_2[$clog2(MPS_BYTES)+1:0] :
                                            (raw_fbe[1] & raw_lbe[1])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} - CONST_3[$clog2(MPS_BYTES)+1:0] :
                                            (raw_fbe[1] & raw_lbe[0])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} - CONST_4[$clog2(MPS_BYTES)+1:0] :

                                            (raw_fbe[2] & raw_lbe[3])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} - CONST_2[$clog2(MPS_BYTES)+1:0] :
                                            (raw_fbe[2] & raw_lbe[2])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} - CONST_3[$clog2(MPS_BYTES)+1:0] :
                                            (raw_fbe[2] & raw_lbe[1])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} - CONST_4[$clog2(MPS_BYTES)+1:0] :
                                            (raw_fbe[2] & raw_lbe[0])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} - CONST_5[$clog2(MPS_BYTES)+1:0] :

                                            (raw_fbe[3] & raw_lbe[3])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} - CONST_3[$clog2(MPS_BYTES)+1:0] :
                                            (raw_fbe[3] & raw_lbe[2])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} - CONST_4[$clog2(MPS_BYTES)+1:0] :
                                            (raw_fbe[3] & raw_lbe[1])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} - CONST_5[$clog2(MPS_BYTES)+1:0] :
                                            (raw_fbe[3] & raw_lbe[0])? {req_len[$clog2(MPS_BYTES)-1:0], 2'b00} - CONST_6[$clog2(MPS_BYTES)+1:0] :

                                            singledw_byte_count[$clog2(MPS_BYTES)+1:0];

       assign singledw_byte_count[11:3] = '0;
       assign singledw_byte_count[2:0] = (raw_fbe[3] & raw_fbe[0])? 3'b100 :
                                         (raw_fbe[2] & raw_fbe[0])? 3'b011 :
                                         (raw_fbe[3] & raw_fbe[1])? 3'b011 :
                                         (raw_fbe[1] & raw_fbe[0])? 3'b010 :
                                         (raw_fbe[2] & raw_fbe[1])? 3'b010 :
                                         (raw_fbe[3] & raw_fbe[2])? 3'b010 : 3'b001;
					    
end // 512,256,128,64

// KD if(DATA_WIDTH==512)
if(DATA_WIDTH >= 64)
begin

always @ (rd_be or req_addr) begin
    casex ( rd_be[3:0])
       4'b0000 : lower_addr = {req_addr[6:2], 2'b00};
       4'bxxx1 : lower_addr = {req_addr[6:2], 2'b00};
       4'bxx10 : lower_addr = {req_addr[6:2], 2'b01};
       4'bx100 : lower_addr = {req_addr[6:2], 2'b10};
       4'b1000 : lower_addr = {req_addr[6:2], 2'b11};
       4'bxxxx : lower_addr = 7'h0;
    endcase // casex ({compl_wd, rd_be[3:0]})
end

always @(posedge clk) begin
	rd_data_d         <= rd_data;
	rd_data_2d        <= rd_data_d;
	vc_tx_ready_i_d   <= vc_tx_ready_i;
end
	 	
always @(posedge clk) begin 
    if (!rst_n) begin 
	    vc_tx_eop_o       <= 1'b0;
		vc_tx_sop_o       <= 1'b0;
		vc_tx_valid_o     <= 1'b0;
		vc_tx_data_o      <= 512'd0;
		dw_counter        <= 10'd0;
		compl_done        <= 1'b0;
		state             <= rst_state;
		rd_en_sig             <= 1'b0;	
	end
	else 
	begin 
	    
	    case (state) 
		    rst_state : begin 
			    if (req_compl) 
				begin 
					vc_tx_eop_o       <= 1'b0;
		            vc_tx_sop_o       <= 1'b0;
		            vc_tx_valid_o     <= 1'b0;
		            // KD optional vc_tx_data_o      <= 512'd0;
                    rd_en_sig         <= 1'b1;			
					rd_data_counter	  <= 32'h0;					
					state             <= send_wait_state;				  
					// state <= (DATA_WIDTH==64)? send_DW1 :  send_wait_state;				  
				end 
				else // if req_compl
				begin 
				    vc_tx_eop_o       <= 1'b0;
		            vc_tx_sop_o       <= 1'b0;
		            vc_tx_valid_o     <= 1'b0;
		            // KD optional vc_tx_data_o      <= 512'd0;
					rd_en_sig         <= 1'b0;
					state             <= rst_state;
				end 
				compl_done        <= 1'b0;
				dw_counter        <= 10'd0;
								
			end // rst_state
			
			send_wait_state : begin 
			        vc_tx_eop_o           <= 1'b0 ;
		            vc_tx_sop_o           <= 1'b0 ;
		            vc_tx_valid_o         <= 1'b0 ;
				    // KD optional vc_tx_data_o          <= 512'b0;
                    rd_en_sig             <= 1'b1;		
					rd_data_counter		  <= 32'hFFFF_0000;
                          // KD
			  if (((DW_ALIGN_RAM ==0) & ( ((DATA_WIDTH > 64) & rd_en_sig_2d) | ((DATA_WIDTH==64) & rd_en_sig_d) )) | 
		              ((DW_ALIGN_RAM > 0) & ( ((DATA_WIDTH > 64) & rd_en_sig_3d) | ((DATA_WIDTH==64) & rd_en_sig_2d) ))) begin
			      state <= send_DW1;
                          end
			end //send_wait_state
			
			send_DW1 : begin 
			    // KD if (vc_tx_ready_i)     
				// KD begin 
				    // KD vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b1;
		            vc_tx_valid_o          <= 1'b1;
				    vc_tx_data_o[7:0]      <= {1'b0,CPLD_FMT_TYPE};
				    vc_tx_data_o[15:8]     <= {1'b0,req_tc,4'b0000};
				    vc_tx_data_o[23:16]    <= {1'b0,req_ep,req_attr,2'b00,req_len[9:8]};   //req_td = 1'b0
				    vc_tx_data_o[31:24]    <= req_len[7:0];
			            vc_tx_data_o[39:32]    <= completer_id[15:8];
				    vc_tx_data_o[47:40]    <= completer_id[7:0];
				    vc_tx_data_o[55:48]    <= {4'b0000,byte_count[11:8]};
				    vc_tx_data_o[63:56]    <= byte_count[7:0];

				    // KD
				    if (DATA_WIDTH > 64) begin
				    vc_tx_data_o[71:64]    <= req_rid[15:8];
				    vc_tx_data_o[79:72]    <= req_rid[7:0];
				    vc_tx_data_o[87:80]    <= req_tag;
				    vc_tx_data_o[95:88]    <= {1'b0,lower_addr};
				    // KD vc_tx_data_o[511:96]   <= rd_data[415:0];
				    vc_tx_data_o[DATA_WIDTH-1:(FIRST_PYLD_DW*32)] <= rd_data[DATA_WIDTH-(FIRST_PYLD_DW*32)-1:0];
			            end

				  // KD  	
				  if (DATA_WIDTH==64) begin
                                    dw_counter             <= req_len[9:0] - 10'd1;
                                    vc_tx_eop_o            <= 1'b0;
                                    state                  <= send_DW3;
                                  end
				  else if ((req_len + 10'd3) > (DATA_WIDTH/32)) begin
				    dw_counter             <= req_len[9:0] - ((DATA_WIDTH/32) - 10'd3);
				    vc_tx_eop_o            <= 1'b0;
                                    state                  <= send_Data;
	                          end				          
				  else begin					  
				    compl_done             <= 1'b1;   
				    vc_tx_eop_o            <= 1'b1;      
				    state                  <= rst_state; 
			          end   
				    rd_en_sig              <= 1'b1;
					// KD rd_data_counter        <= rd_data_counter + 32'h16;
					rd_data_counter <= rd_data_counter + (DATA_WIDTH/32);
					// KD dw_counter <= 10'd1;
					// KD end // vc_tx_ready_i
				/* KD	
				else
				begin 
				    state                  <= send_DW1;
					vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b0;
					rd_en_sig              <= 1'b0;
				end 
				*/
			end //send_DW1

			// KD
			send_DW3 : begin
                          vc_tx_sop_o <= 1'b0;
                          if (DATA_WIDTH==64) begin
                            vc_tx_data_o[7:0]   <= req_rid[15:8];
                            vc_tx_data_o[15:8]  <= req_rid[7:0];
                            vc_tx_data_o[23:16] <= req_tag;
                            vc_tx_data_o[31:24] <= {1'b0,lower_addr};
                            vc_tx_data_o[DATA_WIDTH-1:32]   <= rd_data[DATA_WIDTH-32-1:0];

			    if ((req_len + 10'd1) > (DATA_WIDTH/32)) begin
                              dw_counter  <= req_len[9:0] - ((DATA_WIDTH/32) - 10'd1);
                              vc_tx_eop_o <= 1'b0;
                              state       <= send_Data;
                            end
                            else begin
                              compl_done  <= 1'b1;
                              vc_tx_eop_o <= 1'b1;
                              state       <= rst_state;
                            end
			  end	     
                        end

			send_Data : begin
			
				/* KD
				if (req_len <= dw_counter + 10'd1) begin 
					rd_en_sig              <= 1'b0;
				end // if only one or last DW
				else if (req_len > dw_counter) begin 
				    rd_en_sig              <= 1'b1;
				end // if req_len > dw_counter
				else begin 
					rd_en_sig              <= 1'b0;
				end
			        else begin
				    rd_en_sig              <= 1'b1;
			        end    
				*/
			        rd_en_sig <= 1'b1; // KD
					
			    // KD if (vc_tx_ready_i) 
				// KD begin 
				    // KD if ((req_len - dw_counter) < 16) begin 
				    vc_tx_data_o <= {rd_data[DATA_WIDTH-(FIRST_PYLD_DW*32)-1:0],rd_data_d[DATA_WIDTH-1:DATA_WIDTH-(FIRST_PYLD_DW*32)]};
				    if (dw_counter <= (DATA_WIDTH/32)) begin 
					        vc_tx_sop_o            <= 1'b0;
		                                // KD vc_tx_valid_o          <= 1'b0;
		                                vc_tx_valid_o          <= 1'b1; // final phase
						// KD vc_tx_data_o           <= {rd_data[415:0],rd_data_d[511:416]};
						compl_done             <= 1'b1;
						vc_tx_eop_o            <= 1'b1;
						state                  <= rst_state;
						dw_counter             <= 10'd0;
					end // if only one or last DW
					// KD else if (req_len > dw_counter) begin 
					else begin 
					        vc_tx_sop_o            <= 1'b0;
		                                // KD vc_tx_valid_o          <= 1'b0;
		                                vc_tx_valid_o          <= 1'b1; // more phase
						// KD vc_tx_data_o           <= {rd_data[159:0],rd_data_d[511:416]};
						compl_done             <= 1'b0;
						vc_tx_eop_o            <= 1'b0;
      					state                  <= send_Data;					
						// KD dw_counter             <= dw_counter + 10'd16;
						dw_counter             <= dw_counter - (DATA_WIDTH/32);
						// KD if(req_len + 10'd16 == rd_data_counter ) begin
						if(req_len + (DATA_WIDTH/32) == rd_data_counter ) begin
							rd_data_counter             <= 32'h0;
						end else begin
							// KD rd_data_counter             <= rd_data_counter + 32'd16;
							rd_data_counter             <= rd_data_counter + (DATA_WIDTH/32);
						end
					end // if req_len > dw_counter
					/* KD
					else begin 
					    state                  <= rst_state;
					    vc_tx_eop_o            <= 1'b0;
		                vc_tx_sop_o            <= 1'b0;
		                vc_tx_valid_o          <= 1'b0;
						compl_done             <= 1'b0;
				        dw_counter             <= dw_counter;
						rd_data_counter        <= rd_data_counter;
					end 
					*/
				// KD end // if ready
				/* KD 
				else 
				begin 
					rd_data_counter   <= rd_data_counter;
				    state             <= send_Data;
				    dw_counter        <= dw_counter;			
				end 
				*/
			end //send_Data
			
			default : begin 
			    state             <= rst_state;
				dw_counter        <= 10'd0;
				rd_en_sig         <= 1'b0;
			end 
		endcase
	end
end 
end 

// KD old code below to be removed
else if(DATA_WIDTH==256)
begin 
 
assign rd_addr = {req_addr [13:5] , 5'b00000}; 
 
assign vc_tx_datap_o[0]  = ^(vc_tx_data_o[7:0]);
assign vc_tx_datap_o[1]  = ^(vc_tx_data_o[15:8]);
assign vc_tx_datap_o[2]  = ^(vc_tx_data_o[23:16]);
assign vc_tx_datap_o[3]  = ^(vc_tx_data_o[31:24]);
assign vc_tx_datap_o[4]  = ^(vc_tx_data_o[39:32]);
assign vc_tx_datap_o[5]  = ^(vc_tx_data_o[47:40]);
assign vc_tx_datap_o[6]  = ^(vc_tx_data_o[55:48]);
assign vc_tx_datap_o[7]  = ^(vc_tx_data_o[63:56]);
assign vc_tx_datap_o[8]  = ^(vc_tx_data_o[71:64]);
assign vc_tx_datap_o[9]  = ^(vc_tx_data_o[79:72]);
assign vc_tx_datap_o[10] = ^(vc_tx_data_o[87:80]);
assign vc_tx_datap_o[11] = ^(vc_tx_data_o[95:88]);
assign vc_tx_datap_o[12] = ^(vc_tx_data_o[103:96]);
assign vc_tx_datap_o[13] = ^(vc_tx_data_o[111:104]);
assign vc_tx_datap_o[14] = ^(vc_tx_data_o[119:112]);
assign vc_tx_datap_o[15] = ^(vc_tx_data_o[127:120]);
assign vc_tx_datap_o[16] = ^(vc_tx_data_o[135:128]);
assign vc_tx_datap_o[17] = ^(vc_tx_data_o[143:136]);
assign vc_tx_datap_o[18] = ^(vc_tx_data_o[151:144]);
assign vc_tx_datap_o[19] = ^(vc_tx_data_o[159:152]);
assign vc_tx_datap_o[20] = ^(vc_tx_data_o[167:160]);
assign vc_tx_datap_o[21] = ^(vc_tx_data_o[175:168]);
assign vc_tx_datap_o[22] = ^(vc_tx_data_o[183:176]);
assign vc_tx_datap_o[23] = ^(vc_tx_data_o[191:184]);
assign vc_tx_datap_o[24] = ^(vc_tx_data_o[199:192]);
assign vc_tx_datap_o[25] = ^(vc_tx_data_o[207:200]);
assign vc_tx_datap_o[26] = ^(vc_tx_data_o[215:208]);
assign vc_tx_datap_o[27] = ^(vc_tx_data_o[223:216]);
assign vc_tx_datap_o[28] = ^(vc_tx_data_o[231:224]);
assign vc_tx_datap_o[29] = ^(vc_tx_data_o[239:232]);
assign vc_tx_datap_o[30] = ^(vc_tx_data_o[247:240]);
assign vc_tx_datap_o[31] = ^(vc_tx_data_o[255:248]);
 
assign vc_tx_valid_o_d    = vc_tx_valid_o ;
assign vc_tx_eop_o_d      = vc_tx_eop_o ;
assign vc_tx_eop_n_o_d    = vc_tx_eop_n_o; 
assign vc_tx_sop_o_d      = vc_tx_sop_o ;
assign vc_tx_data_o_d     = vc_tx_data_o ;

assign vc_tx_ready_edge   = (vc_tx_ready_i) & (~vc_tx_ready_i_d);

	
 always @ (rd_be) begin
    casex (rd_be[3:0])
      4'b1xx1 : byte_count = 12'h004;
      4'b01x1 : byte_count = 12'h003;
      4'b1x10 : byte_count = 12'h003;
      4'b0011 : byte_count = 12'h002;
      4'b0110 : byte_count = 12'h002;
      4'b1100 : byte_count = 12'h002;
      4'b0001 : byte_count = 12'h001;
      4'b0010 : byte_count = 12'h001;
      4'b0100 : byte_count = 12'h001;
      4'b1000 : byte_count = 12'h001;
      4'b0000 : byte_count = 12'h001;
    endcase
  end
  
always @ (rd_be or req_addr) begin
    casex ( rd_be[3:0])
       4'b0000 : lower_addr = {req_addr[6:2], 2'b00};
       4'bxxx1 : lower_addr = {req_addr[6:2], 2'b00};
       4'bxx10 : lower_addr = {req_addr[6:2], 2'b01};
       4'bx100 : lower_addr = {req_addr[6:2], 2'b10};
       4'b1000 : lower_addr = {req_addr[6:2], 2'b11};
       4'bxxxx : lower_addr = 7'h0;
    endcase // casex ({compl_wd, rd_be[3:0]})
end

always @(posedge clk) begin
	rd_data_d         <= rd_data;
	rd_data_2d        <= rd_data_d;
	vc_tx_ready_i_d   <= vc_tx_ready_i;
end
	 	
always @(posedge clk) begin 
    if (!rst_n) begin 
	    vc_tx_eop_o       <= 1'b0;
		vc_tx_sop_o       <= 1'b0;
		vc_tx_valid_o     <= 1'b0;
		vc_tx_data_o      <= 256'd0;
		dw_counter        <= 10'd0;
		compl_done        <= 1'b0;
		state             <= rst_state;
		rd_en_sig             <= 1'b0;	
	end
	else 
	begin 
	    
	    case (state) 
		    rst_state : begin 
			    if (req_compl) 
				begin 
					vc_tx_eop_o       <= 1'b0;
		            vc_tx_sop_o       <= 1'b0;
		            vc_tx_valid_o     <= 1'b0;
		            vc_tx_data_o      <= 256'd0;
                    rd_en_sig         <= 1'b1;			
					rd_data_counter	  <= 32'h0;					
					state             <= send_wait_state;				  
				end 
				else // if req_compl
				begin 
				    vc_tx_eop_o       <= 1'b0;
		            vc_tx_sop_o       <= 1'b0;
		            vc_tx_valid_o     <= 1'b0;
		            vc_tx_data_o      <= 256'd0;
					rd_en_sig         <= 1'b0;
					state             <= rst_state;
				end 
				compl_done        <= 1'b0;
				dw_counter        <= 10'd0;
								
			end // rst_state
			
			send_wait_state : begin 
			        vc_tx_eop_o           <= 1'b0 ;
		            vc_tx_sop_o           <= 1'b0 ;
		            vc_tx_valid_o         <= 1'b0 ;
				    vc_tx_data_o          <= 128'b0;
                    rd_en_sig             <= 1'b1;		
					rd_data_counter		  <= 32'hFFFF_0000;
					state                 <= send_DW1;
			end //send_wait_state
			
			send_DW1 : begin 
			    if (vc_tx_ready_i)     
				begin 
				    vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b1;
		            vc_tx_valid_o          <= 1'b1;
				    vc_tx_data_o[7:0]      <= {1'b0,CPLD_FMT_TYPE};
				    vc_tx_data_o[15:8]     <= {1'b0,req_tc,4'b0000};
				    vc_tx_data_o[23:16]    <= {1'b0,req_ep,req_attr,2'b00,req_len[9:8]};   //req_td = 1'b0
				    vc_tx_data_o[31:24]    <= req_len[7:0];
			            vc_tx_data_o[39:32]    <= completer_id[15:8];
				    vc_tx_data_o[47:40]    <= completer_id[7:0];
				    vc_tx_data_o[55:48]    <= {4'b0000,byte_count[11:8]};
				    vc_tx_data_o[63:56]    <= byte_count[7:0];
				    vc_tx_data_o[71:64]    <= req_rid[15:8];
				    vc_tx_data_o[79:72]    <= req_rid[7:0];
				    vc_tx_data_o[87:80]    <= req_tag;
				    vc_tx_data_o[95:88]    <= {1'b0,lower_addr};
				    vc_tx_data_o[255:96]   <= rd_data[159:0];
				    compl_done             <= 1'b1;   
				    vc_tx_eop_o            <= 1'b1;      
				    state                  <= rst_state; 
				    rd_en_sig              <= 1'b1;
					rd_data_counter        <= rd_data_counter + 32'h8;
					dw_counter <= 10'd1;
					end
				else
				begin 
				    state                  <= send_DW1;
					vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b0;
					rd_en_sig              <= 1'b0;
				end 
			end //send_DW1

			send_Data : begin
			
				if (req_len == dw_counter + 10'd1) begin 
					rd_en_sig              <= 1'b0;
				end // if only one or last DW
				else if (req_len > dw_counter) begin 
				    rd_en_sig              <= 1'b1;
				end // if req_len > dw_counter
				else begin 
					rd_en_sig              <= 1'b0;
				end
					
			    if (vc_tx_ready_i) 
				begin 
				    if ((req_len - dw_counter) < 8) begin 
					        vc_tx_sop_o            <= 1'b0;
		                                vc_tx_valid_o          <= 1'b0;
						vc_tx_data_o           <= {rd_data[159:0],rd_data_d[255:160]};
						compl_done             <= 1'b1;
						vc_tx_eop_o            <= 1'b1;
						state                  <= rst_state;
						dw_counter             <= 10'd0;
					end // if only one or last DW
					else if (req_len > dw_counter) begin 
					        vc_tx_sop_o            <= 1'b0;
		                                vc_tx_valid_o          <= 1'b0;
						vc_tx_data_o           <= {rd_data[159:0],rd_data_d[255:160]};
						compl_done             <= 1'b0;
						vc_tx_eop_o            <= 1'b0;
      					state                  <= send_Data;					
						dw_counter             <= dw_counter + 10'd8;
						if(req_len + 10'd08 == rd_data_counter ) begin
							rd_data_counter             <= 32'h0;
						end else begin
							rd_data_counter             <= rd_data_counter + 32'd8;
						end
					end // if req_len > dw_counter
					else begin 
					    state                  <= rst_state;
					    vc_tx_eop_o            <= 1'b0;
		                vc_tx_sop_o            <= 1'b0;
		                vc_tx_valid_o          <= 1'b0;
						compl_done             <= 1'b0;
				        dw_counter             <= dw_counter;
						rd_data_counter        <= rd_data_counter;
					end 
				end // if ready
				else 
				begin 
					rd_data_counter   <= rd_data_counter;
				    state             <= send_Data;
				    dw_counter        <= dw_counter;			
				end 
			end //send_Data
			
			default : begin 
			    state             <= rst_state;
				dw_counter        <= 10'd0;
				rd_en_sig         <= 1'b0;
			end 
		endcase
	end
end 
end 

else if(DATA_WIDTH==128)
begin 
//if (NUM_OF_LANES == 4) begin 
assign rd_addr = {req_addr [13:4] , 4'b0000};
 
assign vc_tx_datap_o[0]  = ^(vc_tx_data_o[7:0]);
assign vc_tx_datap_o[1]  = ^(vc_tx_data_o[15:8]);
assign vc_tx_datap_o[2]  = ^(vc_tx_data_o[23:16]);
assign vc_tx_datap_o[3]  = ^(vc_tx_data_o[31:24]);
assign vc_tx_datap_o[4]  = ^(vc_tx_data_o[39:32]);
assign vc_tx_datap_o[5]  = ^(vc_tx_data_o[47:40]);
assign vc_tx_datap_o[6]  = ^(vc_tx_data_o[55:48]);
assign vc_tx_datap_o[7]  = ^(vc_tx_data_o[63:56]);
assign vc_tx_datap_o[8]  = ^(vc_tx_data_o[71:64]);
assign vc_tx_datap_o[9]  = ^(vc_tx_data_o[79:72]);
assign vc_tx_datap_o[10] = ^(vc_tx_data_o[87:80]);
assign vc_tx_datap_o[11] = ^(vc_tx_data_o[95:88]);
assign vc_tx_datap_o[12] = ^(vc_tx_data_o[103:96]);
assign vc_tx_datap_o[13] = ^(vc_tx_data_o[111:104]);
assign vc_tx_datap_o[14] = ^(vc_tx_data_o[119:112]);
assign vc_tx_datap_o[15] = ^(vc_tx_data_o[127:120]);
 
assign vc_tx_valid_o_d    = vc_tx_valid_o ;
assign vc_tx_eop_o_d      = vc_tx_eop_o ;
assign vc_tx_eop_n_o_d    = vc_tx_eop_n_o; 
assign vc_tx_sop_o_d      = vc_tx_sop_o ;
assign vc_tx_data_o_d     = vc_tx_data_o ;

assign vc_tx_ready_edge   = (vc_tx_ready_i) & (~vc_tx_ready_i_d);


 always @ (rd_be) begin
    casex (rd_be[3:0])
      4'b1xx1 : byte_count = 12'h004;
      4'b01x1 : byte_count = 12'h003;
      4'b1x10 : byte_count = 12'h003;
      4'b0011 : byte_count = 12'h002;
      4'b0110 : byte_count = 12'h002;
      4'b1100 : byte_count = 12'h002;
      4'b0001 : byte_count = 12'h001;
      4'b0010 : byte_count = 12'h001;
      4'b0100 : byte_count = 12'h001;
      4'b1000 : byte_count = 12'h001;
      4'b0000 : byte_count = 12'h001;
    endcase
  end
  
always @ (rd_be or req_addr) begin
    casex ( rd_be[3:0])
       4'b0000 : lower_addr = {req_addr[6:2], 2'b00};
       4'bxxx1 : lower_addr = {req_addr[6:2], 2'b00};
       4'bxx10 : lower_addr = {req_addr[6:2], 2'b01};
       4'bx100 : lower_addr = {req_addr[6:2], 2'b10};
       4'b1000 : lower_addr = {req_addr[6:2], 2'b11};
       4'bxxxx : lower_addr = 7'h0;
    endcase // casex ({compl_wd, rd_be[3:0]})
end
	
always @(posedge clk) begin
	rd_data_d         <= rd_data;
	rd_data_2d        <= rd_data_d;
	vc_tx_ready_i_d   <= vc_tx_ready_i;
end
	 	
always @(posedge clk) begin 
    if (!rst_n) begin 
	    vc_tx_eop_o       <= 1'b0;
		vc_tx_sop_o       <= 1'b0;
		vc_tx_valid_o     <= 1'b0;
		vc_tx_data_o      <= 128'd0;
		dw_counter        <= 10'd0;
		compl_done        <= 1'b0;
		state             <= rst_state;
		rd_en_sig             <= 1'b0;	
	end
	else 
	begin 
	    
	    case (state) 
		    rst_state : begin 
			    if (req_compl) 
				begin 
				   vc_tx_eop_o       <= 1'b0;
		                   vc_tx_sop_o       <= 1'b0;
		            	   vc_tx_valid_o     <= 1'b0;
		            	   vc_tx_data_o      <= 128'd0;
                            	   rd_en_sig         <= 1'b1;
				   state             <= send_wait_state;				  
				end 
				else // if req_compl
				begin 
				    vc_tx_eop_o       <= 1'b0;
		            	    vc_tx_sop_o       <= 1'b0;
		            	    vc_tx_valid_o     <= 1'b0;
		            	    vc_tx_data_o      <= 128'd0;
				    rd_en_sig         <= 1'b0;
				    state             <= rst_state;
				end 
				compl_done        <= 1'b0;
				dw_counter        <= 10'd0; 
								
			end // rst_state
			
		   send_wait_state : begin 
		   	vc_tx_eop_o           <= 1'b0 ;
		        vc_tx_sop_o           <= 1'b0 ;
		        vc_tx_valid_o         <= 1'b0 ;
			vc_tx_data_o          <= 128'b0;
                    	rd_en_sig             <= 1'b1;		
			rd_data_counter	      <= 32'hFFFF_0000;
			state                 <= send_DW1;
		   end //send_wait_state
			
			send_DW1 : begin 
			    if (vc_tx_ready_i)     
				begin 
				    vc_tx_eop_o            <= 1'b0;
		            	    vc_tx_sop_o            <= 1'b1;
		            	    vc_tx_valid_o          <= 1'b1;
				    vc_tx_data_o[7:0]      <= {1'b0,CPLD_FMT_TYPE};
				    vc_tx_data_o[15:8]     <= {1'b0,req_tc,4'b0000};
				    vc_tx_data_o[23:16]    <= {1'b0,req_ep,req_attr,2'b00,req_len[9:8]};   //req_td = 1'b0
				    vc_tx_data_o[31:24]    <= req_len[7:0];
			            vc_tx_data_o[39:32]    <= completer_id[15:8];
				    vc_tx_data_o[47:40]    <= completer_id[7:0];
				    vc_tx_data_o[55:48]    <= {4'b0000,byte_count[11:8]};
				    vc_tx_data_o[63:56]    <= byte_count[7:0];
				    vc_tx_data_o[71:64]    <= req_rid[15:8];
				    vc_tx_data_o[79:72]    <= req_rid[7:0];
				    vc_tx_data_o[87:80]    <= req_tag;
				    vc_tx_data_o[95:88]    <= {1'b0,lower_addr};
				    vc_tx_data_o[127:96]   <= rd_data[31:0];
				    compl_done             <= 1'b0;   
				    vc_tx_eop_o            <= 1'b0;      
				    state                  <= send_Data; 
				    rd_en_sig              <= 1'b1;
				    rd_data_counter        <= rd_data_counter + 32'h4;
				    dw_counter        	   <= 10'd1; //KK: change to 1 as 1st valid has 1 DW data. 
				end
				else
				begin 
				    state                  <= send_DW1;
					vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b0;
					rd_en_sig              <= 1'b0;
				end 
			end //send_DW1

			send_Data : begin
			
				//if (req_len == dw_counter + 10'd4) begin 
				//
				if (req_len == dw_counter + 10'd1) begin
				    rd_en_sig              <= 1'b0;
				end // if only one or last DW
				else if (req_len > dw_counter) begin 
				    rd_en_sig              <= 1'b1;
				end // if req_len > dw_counter
				else begin 
				    rd_en_sig              <= 1'b0;
				end
					
			    if (vc_tx_ready_i) begin 
				 //   if (req_len == dw_counter + 10'd4) begin 
			       //if (req_len == dw_counter + 10'd1) begin
			       if ((req_len - dw_counter) < 4) begin //KK: if less that 4DW left, this is the last data phase
					    	vc_tx_sop_o            <= 1'b0;
		                		vc_tx_valid_o          <= 1'b1;
						vc_tx_data_o           <= {rd_data[31:0],rd_data_d[127:32]};
						compl_done             <= 1'b1;
						vc_tx_eop_o            <= 1'b1;
						state                  <= rst_state;
						dw_counter             <= 10'd0;
				end // if only one or last DW
				else if (req_len > dw_counter) begin 
					    	vc_tx_sop_o            <= 1'b0;
		                		vc_tx_valid_o          <= 1'b1;
						vc_tx_data_o           <= {rd_data[31:0],rd_data_d[127:32]};
						compl_done             <= 1'b0;
						vc_tx_eop_o            <= 1'b0;
      						state                  <= send_Data;					
						dw_counter             <= dw_counter + 10'd4;
						if(req_len + 10'd4 == rd_data_counter) begin
							rd_data_counter             <= 32'h0;
						end else begin
							rd_data_counter             <= rd_data_counter + 32'd4;
						end
				end // if req_len > dw_counter
				else begin 
				   state                  <= rst_state;
				   vc_tx_eop_o            <= 1'b0;
		                   vc_tx_sop_o            <= 1'b0;
		                   vc_tx_valid_o          <= 1'b0;
				   compl_done             <= 1'b0;
				   dw_counter             <= dw_counter;
				   rd_data_counter        <= rd_data_counter;
				end 
				end // if ready
				else begin 
				    rd_data_counter   <= rd_data_counter;
				    state             <= send_Data;
				    dw_counter        <= dw_counter;			
				end 
			end //send_Data
			
			default : begin 
			    state             <= rst_state;
				dw_counter        <= 10'd0;
				rd_en_sig         <= 1'b0;
			end 
		endcase
	end
end 

end 

else if(DATA_WIDTH==64)
begin 

assign rd_addr = {req_addr [13:3] , 3'b000};

assign vc_tx_datap_o[0]  = ^(vc_tx_data_o[7:0]);
assign vc_tx_datap_o[1]  = ^(vc_tx_data_o[15:8]);
assign vc_tx_datap_o[2]  = ^(vc_tx_data_o[23:16]);
assign vc_tx_datap_o[3]  = ^(vc_tx_data_o[31:24]);
assign vc_tx_datap_o[4]  = ^(vc_tx_data_o[39:32]);
assign vc_tx_datap_o[5]  = ^(vc_tx_data_o[47:40]);
assign vc_tx_datap_o[6]  = ^(vc_tx_data_o[55:48]);
assign vc_tx_datap_o[7]  = ^(vc_tx_data_o[63:56]);
 
assign vc_tx_valid_o_d    = vc_tx_valid_o ;
assign vc_tx_eop_o_d      = vc_tx_eop_o ;
assign vc_tx_eop_n_o_d    = vc_tx_eop_n_o; 
assign vc_tx_sop_o_d      = vc_tx_sop_o ;
assign vc_tx_data_o_d     = vc_tx_data_o ;

assign vc_tx_ready_edge   = (vc_tx_ready_i) & (~vc_tx_ready_i_d);

 always @ (rd_be) begin
    casex (rd_be[3:0])
      4'b1xx1 : byte_count = 12'h004;
      4'b01x1 : byte_count = 12'h003;
      4'b1x10 : byte_count = 12'h003;
      4'b0011 : byte_count = 12'h002;
      4'b0110 : byte_count = 12'h002;
      4'b1100 : byte_count = 12'h002;
      4'b0001 : byte_count = 12'h001;
      4'b0010 : byte_count = 12'h001;
      4'b0100 : byte_count = 12'h001;
      4'b1000 : byte_count = 12'h001;
      4'b0000 : byte_count = 12'h001;
    endcase
  end
  
 always @ (rd_be or req_addr) begin
    casex ( rd_be[3:0])
       4'b0000 : lower_addr = {req_addr[6:2], 2'b00};
       4'bxxx1 : lower_addr = {req_addr[6:2], 2'b00};
       4'bxx10 : lower_addr = {req_addr[6:2], 2'b01};
       4'bx100 : lower_addr = {req_addr[6:2], 2'b10};
       4'b1000 : lower_addr = {req_addr[6:2], 2'b11};
       4'bxxxx : lower_addr = 7'h0;
    endcase // casex ({compl_wd, rd_be[3:0]})
    end
	
always @(posedge clk) begin
	rd_data_d         <= rd_data;
	vc_tx_ready_i_d   <= vc_tx_ready_i;
end
 	
always @(posedge clk) begin 
    if (!rst_n) begin 
	    vc_tx_eop_o       <= 1'b0;
		vc_tx_sop_o       <= 1'b0;
		vc_tx_valid_o     <= 1'b0;
		vc_tx_data_o      <= 128'd0;
		dw_counter        <= 10'd0;
		compl_done        <= 1'b0;
		state             <= rst_state;
		rd_en_sig         <= 1'b0;		
	end
	else 
	begin
	    case (state) 
		    rst_state : begin
			    if (req_compl) 
				begin 
					vc_tx_eop_o       <= 1'b0;
		            vc_tx_sop_o       <= 1'b0;
		            vc_tx_valid_o     <= 1'b0;
		            vc_tx_data_o      <= 64'd0;
                    rd_en_sig         <= 1'b1;					
					state             <= send_DW1;    			
					rd_data_counter	  <= 32'h0;
				end 
				else // if req_compl
				begin 
				    vc_tx_eop_o       <= 1'b0;
		            vc_tx_sop_o       <= 1'b0;
		            vc_tx_valid_o     <= 1'b0;
		            vc_tx_data_o      <= 64'd0;
					rd_en_sig         <= 1'b0;
					state             <= rst_state;
				end 
				compl_done        <= 1'b0;
				dw_counter        <= 10'd0;
								
			end // rst_state
			
			send_DW1 : begin 
			    if (vc_tx_ready_i) 
				    
				begin 
				    vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b1;
		            vc_tx_valid_o          <= 1'b1;
				    vc_tx_data_o[7:0]      <= {1'b0,CPLD_FMT_TYPE};
				    vc_tx_data_o[15:8]     <= {1'b0,req_tc,4'b0000};
				    vc_tx_data_o[23:16]    <= {1'b0,req_ep,req_attr,2'b00,req_len[9:8]};
				    vc_tx_data_o[31:24]    <= req_len[7:0];
			        vc_tx_data_o[39:32]    <= completer_id[15:8];
				    vc_tx_data_o[47:40]    <= completer_id[7:0];
				    vc_tx_data_o[55:48]    <= {4'b0000,byte_count[11:8]};
				    vc_tx_data_o[63:56]    <= byte_count[7:0];
					compl_done             <= 1'b0;    
				    vc_tx_eop_o            <= 1'b0;   
				    state                  <= send_DW3;  
				    rd_en_sig              <= 1'b1;
					rd_data_counter		   <= rd_data_counter + 2;
					end
				else
				begin 
				    state                  <= send_DW1;
					vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b0;
					rd_en_sig              <= 1'b0;
				end 
			end //send_DW1

			send_DW3 : begin 
			    if (vc_tx_ready_i) 
				begin 
				    vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b1;
				    vc_tx_data_o[7:0]      <= req_rid[15:8];
				    vc_tx_data_o[15:8]     <= req_rid[7:0];
				    vc_tx_data_o[23:16]    <= req_tag;
				    vc_tx_data_o[31:24]    <= {1'b0,lower_addr};
					vc_tx_data_o[63:32]    <= rd_data[31:0]; 
					state                  <= send_Data;
					rd_en_sig              <= 1'b1;
					rd_data_counter		   <= rd_data_counter + 2;
					
				end 
				else 
				begin 
				    state                  <= send_DW3;
					vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b0;
					rd_en_sig              <= 1'b0;
				end 
				compl_done        <= 1'b0;
				dw_counter        <= 10'd0;
			end // send_DW3
			
			send_Data : begin
			
				if (req_len == dw_counter + 10'd2) begin 
					rd_en_sig           <= 1'b0;
				end // if only one or last DW
				else if (req_len > dw_counter) begin 
					rd_en_sig           <= 1'b1;
				end // if req_len > dw_counter
				else begin 
					rd_en_sig           <= 1'b0;
				end 
					
			    if (vc_tx_ready_i) 
				begin 
				    //izzat if (req_len == dw_counter + 10'd2) begin
				    if (req_len == dw_counter + 10'd1) begin 
					    vc_tx_sop_o            <= 1'b0;
		                vc_tx_valid_o          <= 1'b1;
						//izzat vc_tx_data_o           <= {rd_data[31:0],rd_data_d[63:32]};						
						vc_tx_data_o           <= {rd_data[31:0],rd_data_d[63:32]};
						compl_done             <= 1'b1;
						vc_tx_eop_o            <= 1'b1;
						state                  <= rst_state;
						dw_counter             <= 10'd0;
					end // if only one or last DW
					else if (req_len > dw_counter) begin 
					    vc_tx_sop_o            <= 1'b0;
		                vc_tx_valid_o          <= 1'b1;
						vc_tx_data_o           <= {rd_data[31:0],rd_data_d[63:32]};				
						compl_done             <= 1'b0;
						vc_tx_eop_o            <= 1'b0;
      					state                  <= send_Data;					
						dw_counter             <= dw_counter + 10'd2;
						if(req_len + 10'd2 == rd_data_counter) begin
							rd_data_counter             <= 32'h0;
						end else begin
							rd_data_counter             <= rd_data_counter + 32'd2;
						end
					end // if req_len > dw_counter
					else begin 
					    state                  <= rst_state;
					    vc_tx_eop_o            <= 1'b0;
		                vc_tx_sop_o            <= 1'b0;
		                vc_tx_valid_o          <= 1'b0;
						compl_done             <= 1'b0;
				        dw_counter             <= dw_counter;
						rd_data_counter		   <= rd_data_counter;
					end 
				end // if ready
				else 
				begin 
					rd_data_counter		   <= rd_data_counter;
				    state             <= send_Data;
				    dw_counter        <= dw_counter;			
				end 
			end //send_Data
			
			default : begin 
			    state             <= rst_state;
				dw_counter        <= 10'd0;
				rd_en_sig         <= 1'b0;
			end 
		endcase
	end
end 
end 

else //For DATA_WIDTH==32
begin 
 
assign rd_addr = {req_addr [13:2] , 2'b00}; 
 
assign vc_tx_datap_o[0] = ^(vc_tx_data_o[7:0]);
assign vc_tx_datap_o[1] = ^(vc_tx_data_o[15:8]);
assign vc_tx_datap_o[2] = ^(vc_tx_data_o[23:16]);
assign vc_tx_datap_o[3] = ^(vc_tx_data_o[31:24]);

assign vc_tx_valid_o_d  = vc_tx_valid_o ;
assign vc_tx_eop_o_d    = vc_tx_eop_o ;
assign vc_tx_eop_n_o_d  = vc_tx_eop_n_o; 
assign vc_tx_sop_o_d    = vc_tx_sop_o ;
assign vc_tx_data_o_d   = vc_tx_data_o ;

assign vc_tx_ready_edge = (vc_tx_ready_i) & (~vc_tx_ready_i_d);

  always @ (rd_be) begin
    casex (rd_be[3:0])
      4'b1xx1 : byte_count = 12'h004;
      4'b01x1 : byte_count = 12'h003;
      4'b1x10 : byte_count = 12'h003;
      4'b0011 : byte_count = 12'h002;
      4'b0110 : byte_count = 12'h002;
      4'b1100 : byte_count = 12'h002;
      4'b0001 : byte_count = 12'h001;
      4'b0010 : byte_count = 12'h001;
      4'b0100 : byte_count = 12'h001;
      4'b1000 : byte_count = 12'h001;
      4'b0000 : byte_count = 12'h001;
	  default : byte_count = 12'h000;
    endcase
  end
  
    always @ (rd_be or req_addr) begin
    casex ( rd_be[3:0])
       4'b0000 : lower_addr = {req_addr[6:2], 2'b00};
       4'bxxx1 : lower_addr = {req_addr[6:2], 2'b00};
       4'bxx10 : lower_addr = {req_addr[6:2], 2'b01};
       4'bx100 : lower_addr = {req_addr[6:2], 2'b10};
       4'b1000 : lower_addr = {req_addr[6:2], 2'b11};
       4'bxxxx : lower_addr = 7'h0;
	   default : lower_addr = 7'h0;
    endcase // casex ({compl_wd, rd_be[3:0]})
    end
	
always @(posedge clk) begin 
    if (!rst_n) begin 
	    vc_tx_eop_o       <= 1'b0;
		vc_tx_sop_o       <= 1'b0;
		vc_tx_valid_o     <= 1'b0;
		vc_tx_data_o      <= 32'd0;
		dw_counter        <= 10'd0;
		compl_done        <= 1'b0;
		state             <= rst_state;
		rd_en_sig         <= 1'b0;
		vc_tx_ready_i_d   <= vc_tx_ready_i;
		rd_data_d         <= rd_data;
	end
	else 
	begin 
	    case (state) 
		    rst_state : begin 
			    if (req_compl) 
				begin 
					vc_tx_eop_o       <= 1'b0;
		            vc_tx_sop_o       <= 1'b0;
		            vc_tx_valid_o     <= 1'b0;
		            vc_tx_data_o      <= 32'd0;
					state             <= send_DW1;
				end 
				else // if req_compl
				begin 
				    vc_tx_eop_o       <= 1'b0;
		            vc_tx_sop_o       <= 1'b0;
		            vc_tx_valid_o     <= 1'b0;
		            vc_tx_data_o      <= 32'd0;
					state             <= rst_state;
				end 
				rd_en_sig         <= 1'b0;
				compl_done        <= 1'b0;
				dw_counter        <= 10'd0;
			end // rst_state
			
			send_DW1 : begin 
			    if (vc_tx_ready_i) 
				begin 
				    vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b1;
		            vc_tx_valid_o          <= 1'b1;
				    vc_tx_data_o[7:0]      <= {1'b0,CPLD_FMT_TYPE};
				    vc_tx_data_o[15:8]     <= {1'b0,req_tc,4'b0000};
				    vc_tx_data_o[23:16]    <= {1'b0,req_ep,req_attr,2'b00,req_len[9:8]};
				    vc_tx_data_o[31:24]    <= req_len[7:0];
					rd_en_sig              <= 1'b0;
					state                  <= send_DW2;
				end 
				else
				begin 
				    state                  <= send_DW1;
					vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b0;
					rd_en_sig              <= 1'b0;
				end 
				compl_done        <= 1'b0;
				dw_counter        <= 10'd0;
			end //send_DW1
			
			send_DW2 : begin 
			    if (vc_tx_ready_i) 
				begin 
				    vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b1;
				    vc_tx_data_o[7:0]      <= completer_id[15:8];
				    vc_tx_data_o[15:8]     <= completer_id[7:0];
				    vc_tx_data_o[23:16]    <= {4'b0000,byte_count[11:8]};
				    vc_tx_data_o[31:24]    <= byte_count[7:0];
					state                  <= send_DW3;
					rd_en_sig              <= 1'b1;
				end 
				else 
				begin 
				    state                  <= send_DW2;
					vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b0;
					rd_en_sig              <= 1'b0;
				end 
				compl_done        <= 1'b0;
				dw_counter        <= 10'd0;
			end // send_DW2
			
			send_DW3 : begin 
			    if (vc_tx_ready_i) 
				begin 
				    vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b1;
				    vc_tx_data_o[7:0]      <= req_rid[15:8];
				    vc_tx_data_o[15:8]     <= req_rid[7:0];
				    vc_tx_data_o[23:16]    <= req_tag;
				    vc_tx_data_o[31:24]    <= {1'b0,lower_addr};
					state                  <= send_Data;
					rd_en_sig              <= 1'b1;
					
				end 
				else 
				begin 
				    state                  <= send_DW3;
					vc_tx_eop_o            <= 1'b0;
		            vc_tx_sop_o            <= 1'b0;
		            vc_tx_valid_o          <= 1'b0;
					rd_en_sig              <= 1'b0;
				end 
				compl_done        <= 1'b0;
				dw_counter        <= 10'd0;
			end // send_DW3
			
			send_Data : begin 
				if (req_len == dw_counter + 1'b1) begin 
				   rd_en_sig            <= 1'b0;
				end // if only one or last DW
				else if (req_len > dw_counter) begin 
					rd_en_sig           <= 1'b1;
				end // if req_len > dw_counter
				else begin 
					rd_en_sig           <= 1'b0;
				end 
					
			    if (vc_tx_ready_i) 
				begin 
				    if (req_len == dw_counter + 1'b1) begin 
					    vc_tx_sop_o            <= 1'b0;
		                vc_tx_valid_o          <= 1'b1;
						
						if (vc_tx_ready_edge)
						vc_tx_data_o           <= rd_data_d;
						else
						vc_tx_data_o           <= rd_data;
						
						compl_done             <= 1'b1;
						vc_tx_eop_o            <= 1'b1;
						state                  <= rst_state;
						dw_counter             <= 10'd0;
					end // if only one or last DW
					else if (req_len > dw_counter) begin 
					    vc_tx_sop_o            <= 1'b0;
		                vc_tx_valid_o          <= 1'b1;
				
				        if (vc_tx_ready_edge) 
						vc_tx_data_o           <= rd_data_d;
						else
						vc_tx_data_o           <= rd_data;
				
						compl_done             <= 1'b0;
						vc_tx_eop_o            <= 1'b0;
      					state                  <= send_Data;
						dw_counter             <= dw_counter + 1'b1;
					end // if req_len > dw_counter
					else begin 
					    state                  <= rst_state;
					    vc_tx_eop_o            <= 1'b0;
		                vc_tx_sop_o            <= 1'b0;
		                vc_tx_valid_o          <= 1'b0;
						compl_done             <= 1'b0;
				        dw_counter             <= dw_counter;
					end 
				end // if ready
				else 
				begin 
				    state             <= send_Data;
				    dw_counter        <= dw_counter;					
				end 
			end //send_Data
			
			default : begin 
			    state             <= rst_state;
				dw_counter        <= 10'd0;
				rd_en_sig         <= 1'b0;
			end 
		endcase
	end
end 
end 

endgenerate 

endmodule
