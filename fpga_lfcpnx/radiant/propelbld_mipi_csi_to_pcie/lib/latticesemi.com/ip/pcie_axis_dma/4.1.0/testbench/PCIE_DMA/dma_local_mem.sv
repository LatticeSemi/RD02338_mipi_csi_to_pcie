module dma_local_mem # (
   //parameter DEVICE_FAMILY = "LFCPNX",
   parameter DEVICE_FAMILY = "common",
   parameter AWID_WIDTH = 3,
   parameter ARID_WIDTH = 3,
   parameter AXI_WIDTH  = 256, // 32*8, // 32 Bytes

   parameter MEM_REGMODE = "reg",
   parameter MEM_WIDTH   = AXI_WIDTH,
   parameter MEM_DEPTH   = 4096,

   parameter CHK_U_ADDR_EN = 1, // upper addr check [63:17]
   parameter CHK_L_ADDR_EN = 1  // lower addr check [4:0]
) (	
   input logic clk,
   input logic rst_n,

   // AXI Address Write Channel (DMA)
   output logic axi_awready_i,
   input  logic axi_awvalid_o,
   input  logic [AWID_WIDTH-1:0] axi_awid_o,
   input  logic [7:0] axi_awlen_o, // The number of transfer. 0x00 = 1 beat, â, 0xFF = 256 beats.
   input  logic [63:0] axi_awaddr_o,
   /*
   input  logic [2:0] axi_awsize_o, // 3'd0: 1B
                                    // 3'd1: 2B
                                    // 3'd2: 4B
                                    // 3'd3: 8B (supported if AXI_WIDTH >= 64)
                                    // 3'd4: 16B (supported if AXI_WIDTH >= 128)
                                    // 3'd5: 32B (supported if AXI_WIDTH = 256b)
   input  logic [1:0] axi_awburst_o, // Only support 2'b01 (INCR)
   input  logic axi_awlock_o, // Not supported. Driven 0.
   input  logic [3:0] axi_awcache_o, // Not supported. Driven 0.
   input  logic [2:0] axi_awprot_o, // Not supported. Driven 0.
   input  logic [3:0] axi_awregion_o, // Not supported. Driven 0.
   */

   // AXI Write Channel (DMA)
   output logic axi_wready_i,
   input  logic axi_wvalid_o,
   input  logic axi_wlast_o,
   input  logic [(AXI_WIDTH/8)-1:0] axi_wstrb_o,
   input  logic [AXI_WIDTH-1:0] axi_wdata_o,
   // input  logic [7:0] axi_wuser_o, // Not supported. Driven 0.

   // AXI Write Response Channel (DMA)
   input  logic axi_bready_o,
   output logic axi_bvalid_i,
   output logic [AWID_WIDTH-1:0] axi_bid_i,
   output logic [1:0] axi_bresp_i,

   // AXI Read Address Channel (DMA)
   output logic axi_arready_i,
   input  logic axi_arvalid_o,
   input  logic [ARID_WIDTH-1:0] axi_arid_o,
   input  logic [63:0] axi_araddr_o,
   input  logic [7:0] axi_arlen_o, // The number of transfer. 0x00 = 1 beat, â, 0xFF = 256 beats.
   /*
   input  logic [2:0] axi_arsize_o, // 3'd0: 1B
                                    // 3'd1: 2B
                                    // 3'd2: 4B
                                    // 3'd3: 8B (supported if AXI_WIDTH >= 64)
                                    // 3'd4: 16B (supported if AXI_WIDTH >= 128)
                                    // 3'd5: 32B (supported if AXI_WIDTH = 256b)
   input  logic [1:0] axi_arburst_o, // Only support 2'b01 (INCR)
   */

   // AXI Read Data Channel (DMA)
   input  logic axi_rready_o,
   output logic axi_rvalid_i,
   output logic [ARID_WIDTH-1:0] axi_rid_i,
   output logic [AXI_WIDTH-1:0] axi_rdata_i,
   output logic [1:0] axi_rresp_i,
   output logic axi_rlast_i
);
  localparam CONST_1 = 1;

  localparam ADDR_WIDTH = $clog2(MEM_DEPTH); 
  localparam ADDR_START_BIT = $clog2(AXI_WIDTH/8);
  localparam ADDR_END_BIT   = ADDR_START_BIT + ADDR_WIDTH - 1;

  localparam AWFIFO_WIDTH = AWID_WIDTH + 8 + ADDR_WIDTH + 1;
  localparam AWFIFO_DEPTH = 2;
  localparam BFIFO_WIDTH  = 1 + ARID_WIDTH; // 1 bit store only msb of addr attr that indicate if addr range is invalid
  localparam BFIFO_DEPTH  = 2;

  localparam ARFIFO_WIDTH = ARID_WIDTH + 8 + ADDR_WIDTH + 1;
  localparam ARADDR_DEPTH = 2;

  localparam RFIFO_ATTR_WIDTH = 1 + 1 + ARID_WIDTH; // 1 (last) + 1 (invalid addr. or_msb of addr) 
  localparam RFIFO_WIDTH  = RFIFO_ATTR_WIDTH + MEM_WIDTH;
  localparam RFIFO_DEPTH  = 8;
  
  //---------------
  // Write
  //---------------
  logic awfifo_ovalid, awfifo_oready, axi_wready_qualed; 
  logic [AWID_WIDTH-1:0] awfifo_awid;
  logic [7:0]            awfifo_awlen;
  logic [ADDR_WIDTH:0] awfifo_awaddr, axi_awaddr_o_pad; // include msb for invalid addr detect
  logic trk_wr_cnt_gt0;
  logic [7:0] trk_wr_cnt, trk_wr_cnt_nxt;
  logic bresp_wr_en, mem_wr_en;
  logic [ADDR_WIDTH:0] wr_addr, trk_wr_addr, trk_wr_addr_nxt; 
  logic [AWID_WIDTH-1:0] trk_awid, trk_awid_nxt;

  logic bfifo_free;

  // inlet check
  assign axi_awaddr_o_pad[ADDR_WIDTH]     = ( ((CHK_U_ADDR_EN==1) && (|axi_awaddr_o[63:ADDR_END_BIT+1])) || ((CHK_L_ADDR_EN==1) && (|axi_awaddr_o[ADDR_START_BIT-1:0])) )? 1'b1 : 1'b0; // mark the chk result into msb
  assign axi_awaddr_o_pad[ADDR_WIDTH-1:0] = axi_awaddr_o[ADDR_END_BIT:ADDR_START_BIT];

  //---------------
  // Write - AW FIFO
  //---------------
  // continue use 0 base awlen, the awvalid implies minimum 1
  dma_flopq #(.WIDTH(AWFIFO_WIDTH), .DEPTH(AWFIFO_DEPTH)) awfifo (
    .clk(clk), .rst_n(rst_n),
    .ivalid(axi_awvalid_o), .iready(axi_awready_i),  
    .idata({axi_awid_o [AWID_WIDTH-1:0], axi_awlen_o[7:0],  axi_awaddr_o_pad[ADDR_WIDTH:0]}),
    .odata({awfifo_awid[AWID_WIDTH-1:0], awfifo_awlen[7:0], awfifo_awaddr   [ADDR_WIDTH:0]}),
    .ovalid(awfifo_ovalid), .oready(awfifo_oready)
  );	  

  assign awfifo_oready = bfifo_free & (~trk_wr_cnt_gt0 & awfifo_ovalid) & axi_wvalid_o; // pre-allocate bfifo. 1st beat from awfifo and wvalid. (same time of 1st beat wdata, queue depth to absort the pipeline performance)
  assign axi_wready_i  = bfifo_free & ( trk_wr_cnt_gt0 | awfifo_ovalid);                // inprog or 1st beat. not qual with axi_wvalid_o (no boomerang)
  assign axi_wready_qualed = axi_wready_i & axi_wvalid_o;                               // qualed with axi_wvalid_o. actual wr will be performed

  assign trk_wr_cnt_gt0 = | trk_wr_cnt;
  assign trk_wr_cnt_nxt = (axi_wready_qualed & axi_wlast_o)? '0 :
	                  (axi_wready_qualed & trk_wr_cnt_gt0)? trk_wr_cnt[7:0] - CONST_1[7:0] :
		           awfifo_oready?                       awfifo_awlen[7:0] : // 1st wready happen at awfifo_oready. 0 base same as -1 from 1 base
		           trk_wr_cnt[7:0];

  assign mem_wr_en = awfifo_oready?     ~awfifo_awaddr[ADDR_WIDTH] :      // 1st beat & ~msb invalid addr
	             axi_wready_qualed? ~wr_addr      [ADDR_WIDTH] : '0;  // in prog  & ~msb invalid addr
	  
  assign bresp_wr_en = (awfifo_oready | axi_wready_qualed) & axi_wlast_o; // response at wlast

  assign wr_addr[ADDR_WIDTH:0] = awfifo_oready? awfifo_awaddr[ADDR_WIDTH:0] : // 1st beat
                                                trk_wr_addr  [ADDR_WIDTH:0];  // in prog

  // track next addr and keep msb stickly					    
  assign trk_wr_addr_nxt[ADDR_WIDTH:0] = awfifo_oready?     ( ({1'b0, awfifo_awaddr[ADDR_WIDTH-1:0]} + CONST_1[ADDR_WIDTH:0]) | {awfifo_awaddr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} ) :
			                 (axi_wready_qualed & !axi_wlast_o)? ( ({1'b0, trk_wr_addr  [ADDR_WIDTH-1:0]} + CONST_1[ADDR_WIDTH:0]) | {trk_wr_addr  [ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} ) : 
					                              trk_wr_addr  [ADDR_WIDTH:0]; 

  assign trk_awid_nxt[AWID_WIDTH-1:0] = awfifo_oready? awfifo_awid[AWID_WIDTH-1:0] : trk_awid[AWID_WIDTH-1:0]; 

  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      trk_wr_cnt  <= '0;
      trk_wr_addr <= '0;
      trk_awid    <= '0;
    end  
    else begin
      trk_wr_cnt  <= trk_wr_cnt_nxt;
      trk_wr_addr <= trk_wr_addr_nxt;
      trk_awid    <= trk_awid_nxt;
    end  
  end

  //---------------
  // Write - B FIFO
  //---------------
  dma_flopq #(.WIDTH(BFIFO_WIDTH), .DEPTH(BFIFO_DEPTH)) bfifo (
    .clk(clk), .rst_n(rst_n),
    .ivalid(bresp_wr_en), .iready(bfifo_free),
    .idata({wr_addr[ADDR_WIDTH], trk_awid_nxt[AWID_WIDTH-1:0]}), 
    .odata({axi_bresp_i[1],          axi_bid_i   [AWID_WIDTH-1:0]}), 
    .ovalid(axi_bvalid_i), .oready(axi_bready_o)
  );

  // bresp = 2'b10 for the case of invalid addr range
  assign axi_bresp_i[0] = '0; 

  //---------------
  // Read
  //---------------
  logic arfifo_ovalid, arfifo_oready;
  logic [ARID_WIDTH-1:0] arfifo_arid;
  logic [7:0]            arfifo_arlen, axi_arlen_o_qual;
  logic [ADDR_WIDTH:0] arfifo_araddr, axi_araddr_o_pad; // include msb for invalid addr detect
  logic trk_rd_cnt_gt0, trk_rd_cnt_gt1, rd_last;
  logic [7:0] trk_rd_cnt, trk_rd_cnt_nxt;
  logic rd_en, mem_rd_en;
  logic [ADDR_WIDTH:0] rd_addr, trk_rd_addr, trk_rd_addr_nxt;
  logic [ARID_WIDTH-1:0] trk_arid, trk_arid_nxt;

  logic [2:0] rd_en_dly;
  logic [2:0][RFIFO_ATTR_WIDTH-1:0] rd_attr_dly; 

  logic rfifo_free;

  // inlet check
  assign axi_araddr_o_pad[ADDR_WIDTH]     = ( ((CHK_U_ADDR_EN==1) && (|axi_araddr_o[63:ADDR_END_BIT+1])) || ((CHK_L_ADDR_EN==1) && (|axi_araddr_o[ADDR_START_BIT-1:0])) )? 1'b1 : 1'b0; // mark the chk result into msb
  assign axi_araddr_o_pad[ADDR_WIDTH-1:0] = axi_araddr_o[ADDR_END_BIT:ADDR_START_BIT];
  assign axi_arlen_o_qual = axi_araddr_o_pad[ADDR_WIDTH]? '0 : axi_arlen_o; // mark as final if addr check fail

  //---------------
  // Read - AR FIFO
  //---------------
  // continue use 0 base arlen, the arvalid implies minimum 1
  dma_flopq #(.WIDTH(ARFIFO_WIDTH), .DEPTH(ARADDR_DEPTH)) arfifo (
    .clk(clk), .rst_n(rst_n),
    .ivalid(axi_arvalid_o), .iready(axi_arready_i),
    .idata({axi_arid_o [ARID_WIDTH-1:0], axi_arlen_o_qual[7:0], axi_araddr_o_pad[ADDR_WIDTH:0]}),
    .odata({arfifo_arid[ARID_WIDTH-1:0], arfifo_arlen[7:0],     arfifo_araddr   [ADDR_WIDTH:0]}),
    .ovalid(arfifo_ovalid), .oready(arfifo_oready)
  );

  assign arfifo_oready = rfifo_free & (~trk_rd_cnt_gt0 & arfifo_ovalid); // not inprog, new ar valid

  assign trk_rd_cnt_gt1 = | trk_rd_cnt[7:1]; 
  assign trk_rd_cnt_gt0 = | trk_rd_cnt;
  assign trk_rd_cnt_nxt =  arfifo_oready?                                 arfifo_arlen[7:0] :              // 1st rvalid happen at arfifo_oready. 0 base same as -1 from 1 base
                          (trk_rd_cnt_gt1 & trk_rd_addr_nxt[ADDR_WIDTH])? 8'h01 :                          // addr violation mark as rlast    
                           rd_en?                                         trk_rd_cnt[7:0] - CONST_1[7:0] : // rd_en can only be asserted when trk_rd_cnt_gt0
                                                                          trk_rd_cnt[7:0];

  assign rd_en = arfifo_oready | (trk_rd_cnt_gt0 & rfifo_free);

  assign mem_rd_en = (MEM_REGMODE=="reg")? | rd_en_dly[2:0] : | rd_en_dly[1:0]; 

  assign rd_addr[ADDR_WIDTH:0] = arfifo_oready? arfifo_araddr[ADDR_WIDTH:0] : // 1st beat
                                                trk_rd_addr  [ADDR_WIDTH:0];  // in prog

  assign rd_last = arfifo_oready? ~(| arfifo_arlen[7:0]) : (trk_rd_cnt[7:0]==8'h01);

  // track next addr and keep msb stickly                                           
  assign trk_rd_addr_nxt[ADDR_WIDTH:0] = arfifo_oready? ( ({1'b0, arfifo_araddr[ADDR_WIDTH-1:0]} + CONST_1[ADDR_WIDTH:0]) | {arfifo_araddr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} ) :
                                         rd_en?         ( ({1'b0, trk_rd_addr  [ADDR_WIDTH-1:0]} + CONST_1[ADDR_WIDTH:0]) | {trk_rd_addr  [ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} ) :
                                                                  trk_rd_addr  [ADDR_WIDTH:0];

  assign trk_arid_nxt[AWID_WIDTH-1:0] = arfifo_oready? arfifo_arid[AWID_WIDTH-1:0] : trk_arid[AWID_WIDTH-1:0];


  assign rd_en_dly[0] = rd_en;
  assign rd_attr_dly[0] = {rd_last, rd_addr[ADDR_WIDTH], trk_arid_nxt[ARID_WIDTH-1:0]}; // rd_last, rd_addr msb invalid addr range, arid

  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      trk_rd_cnt       <= '0;
      trk_rd_addr      <= '0;
      trk_arid         <= '0;
      rd_en_dly  [2:1] <= '0;
      rd_attr_dly[2:1] <= '0;
    end
    else begin
      trk_rd_cnt     <= trk_rd_cnt_nxt;
      trk_rd_addr    <= trk_rd_addr_nxt;
      trk_arid       <= trk_arid_nxt;
      rd_en_dly  [2] <= rd_en_dly[1];
      rd_en_dly  [1] <= rd_en_dly[0];
      rd_attr_dly[1] <= rd_attr_dly[0];
      rd_attr_dly[2] <= rd_attr_dly[1];
    end
  end

  logic rfifo_valid;
  logic [RFIFO_ATTR_WIDTH-1:0] rfifo_attr; 
  logic [MEM_WIDTH-1:0]        rfifo_rdata;

  assign rfifo_valid = (MEM_REGMODE=="reg")? rd_en_dly[2]   : rd_en_dly[1];
  assign rfifo_attr  = (MEM_REGMODE=="reg")? rd_attr_dly[2] : rd_attr_dly[1]; 

  //---------------
  // Read - R FIFO
  //---------------
  dma_flopq #(.WIDTH(RFIFO_WIDTH), .DEPTH(RFIFO_DEPTH), .FULLLIMIT(RFIFO_DEPTH-2)) rfifo (
    .clk(clk), .rst_n(rst_n),
    .ivalid(rfifo_valid), .iready(rfifo_free),
    .idata({rfifo_attr[RFIFO_ATTR_WIDTH-1:0],                        rfifo_rdata[MEM_WIDTH-1:0]}),
    .odata({axi_rlast_i, axi_rresp_i[1], axi_rid_i[ARID_WIDTH-1:0],  axi_rdata_i[MEM_WIDTH-1:0]}), 
    .ovalid(axi_rvalid_i), .oready(axi_rready_o)
  );

  // rresp = 2'b10 for the case of invalid addr range
  assign axi_rresp_i[0] = '0; 
  
  //---------------
  // MEM
  //---------------
  pmi_ram_dp_be #(
    .pmi_family(DEVICE_FAMILY), // as long as not set to common, BYTE_ENABLE will be supported
    .pmi_byte_size(8),  
    .pmi_regmode(MEM_REGMODE), // read will take 2 clks
    .pmi_wr_addr_depth(MEM_DEPTH), .pmi_wr_addr_width($clog2(MEM_DEPTH)), .pmi_wr_data_width(MEM_WIDTH),
    .pmi_rd_addr_depth(MEM_DEPTH), .pmi_rd_addr_width($clog2(MEM_DEPTH)), .pmi_rd_data_width(MEM_WIDTH)
  ) mem (
    .Reset(~rst_n),
    .WrClock(clk), .WrClockEn(mem_wr_en), .WrAddress(wr_addr[ADDR_WIDTH-1:0]), .Data(axi_wdata_o), .WE(1'b1), .ByteEn(axi_wstrb_o),
    .RdClock(clk), .RdClockEn(mem_rd_en), .RdAddress(rd_addr[ADDR_WIDTH-1:0]), .Q(rfifo_rdata)
  );

endmodule
