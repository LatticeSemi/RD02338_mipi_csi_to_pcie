`timescale 1ps/1ps
`include "./ed_top_includes.sv"

module axist_dma_ed_top  #(
    parameter SIM             = 0,
    parameter WIDTH           = 4,   //  1:X1; 2:X2; 4:X4[Lane width]
    parameter DATA_WIDTH      = 128, // 512    //  Data width of design limited to 128bits
    parameter DW_ALIGN_RAM    = 1,   // mem inst with 1 SEG per dw //x4=1, x1,x8=0
    parameter SERIES_PATTERN  = 1,
    parameter NUM_PACKETS     = 4,
    parameter IMAGE_PATTERN   = 1'b0, // 1: image pattern. 0: incremental pattern.
    parameter PER_BYTE_INCR   = 1'b1, // Used when IMAGE_PATTERN == 1'b0. 1: Incremented per byte. 0: Incremented per 32-byte.
    parameter IMAGE_PATTERN_ONCE = 1'b1, // 1: Used when IMAGE_PATTERN == 1. 1: Send image pattern once. 0: Send repeatedly.
    parameter [16:0] STREAM_SIZE = 17'b0_0100_0000_0000_0000 // 16 KB for a stream.
)
(

input 					refclkp_i,               
input 					refclkn_i,
input       [WIDTH-1:0]	link0_rxp_i,                  			  // serial line RX+
input       [WIDTH-1:0]	link0_rxn_i,                  			  // serial line RX-
output      [WIDTH-1:0]	link0_txp_o,                  			  // serial line TX+
output      [WIDTH-1:0]	link0_txn_o,                  			  // serial line TX-
input   				ed_perst_n_i,
input 					ed_usr_rst_n,
input [WIDTH-1:0]             refret_i,
input [WIDTH-1:0]             rext_i,
input   				clk_user,
output					linkup_done,
input                         usr_vector_done_set,
    //output  	[6:0] 		segment_out, 
    //output  	[2:0] 		segment_en, 
output  				clk_sel,
output  				pcie_sel,
output  				pcie_sw1_pd,
output  				pcie_sw2_pd
);

// PCIE IP Parameters
`include "../dut_params.v"

logic  		                      clk_100;
logic  		                      clk_125;
logic  		                      usr_lmmi_clk_i;
logic  		                      sys_clk_i;
logic  		                      sys_clk_int;
logic                             link0_aux_clk_i;
logic  		                      lock_ip;
logic                             link0_perst_n_i;
logic                             link0_rst_usr_n_i;
logic                             link0_user_aux_power_detected_i;
logic                             link0_user_transactions_pending_i;
logic                             link0_rx_credit_init_i;
logic                             [11:0] link0_rx_credit_nh_i;
logic                             link0_rx_credit_nh_inf_i;
logic                             link0_rx_credit_return_i;

logic  		                      link0_rx_ready_i;
logic  		                      link0_rx_valid_o;
logic  		[1:0]                 link0_rx_sel_o;
logic  		[12:0]                link0_rx_cmd_data_o;
logic  		                      link0_rx_sop_o;
logic  		[DATA_WIDTH-1:0]      link0_rx_data_o;
logic  		[DATA_WIDTH/8-1:0]    link0_rx_datap_o;
logic  		                      link0_rx_eop_o;
logic  		                      link0_rx_err_ecrc_o;
logic  		[1:0]                 link0_rx_f_o;
logic  		                      link0_tx_valid_i;
logic  		                      link0_tx_eop_i;
logic  		                      link0_tx_eop_n_i;
logic  		                      link0_tx_sop_i;
logic  		[DATA_WIDTH-1:0]      link0_tx_data_i;
logic  		[DATA_WIDTH/8-1:0]    link0_tx_datap_i;
logic  		                      link0_tx_ready_o;

//Others
logic  		                      config_done;
logic  		                      clk_usr_o;
logic 			                  rst_n; //System level reset - Active Low
logic			                  link0_pl_link_up_o;
logic			                  link0_dl_link_up_o;
logic			                  link0_tl_link_up_o;
logic			                  link0_pl_link_up;
logic			                  link0_dl_link_up;
logic			                  link0_tl_link_up;
logic			                  u_pl_link_up_o;
logic			                  u_dl_link_up_o;
logic			                  u_tl_link_up_o;
logic 			                  usr_lmmi_resetn_i; 
logic                             rstn_meta;
logic	                          rstn_clk2;

logic clk_usr_i_250MHz, clk_usr_i_125MHz, clk_usr_i_62_5MHz;
logic rst_sync_clk;

// CPNX Gen3 will use 125MHz clock as reset synchronizer clock
assign rst_sync_clk = (DEVICE_FAMILY =="LFCPNX" || SUPPORTED_LFMXO5_PCIEX4==1) ? sys_clk_int : sys_clk_i;

assign link0_user_aux_power_detected_i = 1'b0;
assign link0_user_transactions_pending_i = 1'b0;
assign link0_rx_credit_init_i = 1'b1;
assign link0_rx_credit_nh_i = 12'h0000;
assign link0_rx_credit_nh_inf_i = 1'b1;
assign link0_rx_credit_return_i = 1'b1;

generate 
if (DEVICE_FAMILY == "LAV-AT") begin : AVANT

    assign link0_aux_clk_i = usr_lmmi_clk_i;
    assign link0_perst_n_i =  rstn_clk2; //nwai : Timing violation related to LTR enablement fixed by modifying reset to use a sync reset
    assign link0_rst_usr_n_i = rstn_clk2;
    assign clk_100 = clk_user;

    wire m0_tready_i ; 
    assign m0_tready_i      =  link0_rx_ready_i;
    wire m0_tvalid_o ; 
    wire m0_tlast_o ; 
    wire [64*WIDTH-1:0] m0_tdata_o ; 
    wire [8*WIDTH-1:0] m0_tstrb_o ; 
    wire [8*WIDTH-1:0] m0_tkeep_o ; 
    wire [7:0] m0_tid_o ; 
    wire [3:0] m0_tdest_o ; 

    wire s0_tready_o ; 
    logic vc_tx_ready_o;
    assign vc_tx_ready_o    =  (USR_DAT_IF_TYPE == "TLP") ? link0_tx_ready_o : s0_tready_o;
    wire s0_tvalid_i ; 
    wire s0_tlast_i ; 
    wire [64*WIDTH-1:0] s0_tdata_i ; 
    wire [8*WIDTH-1:0] s0_tstrb_i ; 
    wire [8*WIDTH-1:0] s0_tkeep_i ; 
    wire [7:0] s0_tid_i ; 
    wire [9:0] s0_tdest_i ; 
    //wire usr_clk_usr_o;

    //LMMI interface for Avant
    logic  		[31:0]	              usr_lmmi_rdata_o;
    logic  		[0:0]	              usr_lmmi_rdata_valid_o;
    logic  		[0:0]	              usr_lmmi_ready_o;
    logic  		[0:0]	              usr_lmmi_request_i;
    logic  				              usr_lmmi_wr_rdn_i;
    logic  		[23:0] 	              usr_lmmi_offset_i;
    logic  		[31:0] 	              usr_lmmi_wdata_i;


   //assign linkup_done = link0_pl_link_up & link0_dl_link_up & link0_tl_link_up; //todo check linkup is active high/low
    
    LMMI_app lmmi_app_inst (
    .clk 								(usr_lmmi_clk_i),
	.rst_n 								(usr_lmmi_resetn_i),
	.usr_lmmi_request_o					(usr_lmmi_request_i),
    .usr_lmmi_wr_rdn_o 					(usr_lmmi_wr_rdn_i),
    .usr_lmmi_wdata_o  					(usr_lmmi_wdata_i),
    .usr_lmmi_offset_o 					(usr_lmmi_offset_i),
    .usr_lmmi_rdata_i  					(usr_lmmi_rdata_o),
    .usr_lmmi_rdata_valid_i				(usr_lmmi_rdata_valid_o),
    .usr_lmmi_ready_i      				(usr_lmmi_ready_o),
	.config_done  						(config_done)
    );

    pcie_app  # (
    .DATA_WIDTH							(DATA_WIDTH),
	.DW_ALIGN_RAM                       (DW_ALIGN_RAM) // KD
	)
	application_layer_inst (
    .clk 								(sys_clk_i),
	.rst_n 								(rstn_clk2),
	.vc_rx_ready_o						(link0_rx_ready_i),
	.vc_rx_valid_i 						(link0_rx_valid_o),
	.vc_rx_sel_i 						(link0_rx_sel_o),
	.vc_rx_cmd_data_i 					(link0_rx_cmd_data_o),
	.vc_rx_sop_i 						(link0_rx_sop_o),
	.vc_rx_data_i 						(link0_rx_data_o),
	.vc_rx_datap_i 						(link0_rx_datap_o),
	.vc_rx_eop_i 						(link0_rx_eop_o),
	.vc_rx_err_ecrc_i 					(link0_rx_err_ecrc_o),
	.vc_rx_f_i 							(link0_rx_f_o),
	.vc_tx_valid_o 						(link0_tx_valid_i),
	.vc_tx_eop_o   						(link0_tx_eop_i ),
	.vc_tx_eop_n_o 						(link0_tx_eop_n_i),
	.vc_tx_sop_o 						(link0_tx_sop_i),
	.vc_tx_data_o 						(link0_tx_data_i),
	.vc_tx_datap_o 						(link0_tx_datap_i),
	.vc_tx_ready_i 						(link0_tx_ready_o),
	.completer_id_i 					(16'd100),
	.bar_0_address                      (32'b0),
	.bar_1_address                      (32'b0),
	.write_data_check					(),
	.rd_data_counter				    ()
	);

    // PCIE IP Instantiation
    `include "../dut_inst.v"
    
    if(USR_DAT_IF_TYPE == "AXI_STREAM") begin : AXI_STREAM
 
        axi2tlp #(
           .DATA_WIDTH(DATA_WIDTH)
           )
        axi_2_tlp(
          .clk                   (sys_clk_i),
          .rst_n                 (rstn_clk2),
          .m0_tvalid_o           (m0_tvalid_o),
          .m0_tdata_o            (m0_tdata_o),
          .m0_tlast_o            (m0_tlast_o),
          .m0_tready_i           (m0_tready_i),
          .link0_rx_data_o       (link0_rx_data_o),
          .link0_rx_valid_o      (link0_rx_valid_o),
          .link0_rx_sop_o        (link0_rx_sop_o),
          .link0_rx_eop_o        (link0_rx_eop_o)
        );

        tlp2axi #(
          .DATA_WIDTH(DATA_WIDTH)
          )
        tlp_2_axi(
          .clk                   (sys_clk_i),
          .rst_n                 (rstn_clk2),
          .vc_tx_valid_i         (link0_tx_valid_i),
          .vc_tx_eop_i           (link0_tx_eop_i),
          .vc_tx_data_i          (link0_tx_data_i),
          .s0_tvalid_i           (s0_tvalid_i),
          .s0_tlast_i            (s0_tlast_i),
          .s0_tdata_i            (s0_tdata_i),
          .s0_tstrb_i            (s0_tstrb_i),
          .s0_tkeep_i            (s0_tkeep_i),
          .s0_tid_i              (s0_tid_i),
          .s0_tdest_i            (s0_tdest_i)
        );
    end


end else if ( (DEVICE_FAMILY == "LFD2NX" || DEVICE_FAMILY == "LIFCL" || SUPPORTED_LFMXO5_PCIEX1 == 1 ) && USR_DAT_IF_TYPE =="TLP") begin : LIFCL
    
    //LMMI_App specific
    logic [2:0] max_payload;
    logic generation;
    assign generation = (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 1) ? 1 : 0;
    assign max_payload    = LINK0_FTL_PCIE_DEV_CAP_MAX_PAYLOAD_SIZE_SUPPORTED;//0-128bytes,1-256bytes,2-512bytes
    assign link0_aux_clk_i = usr_lmmi_clk_i;
    assign link0_perst_n_i = ed_perst_n_i & lock_ip;
    assign link0_rst_usr_n_i = ed_usr_rst_n & lock_ip;
    assign clk_100 = clk_user;

    logic        usr_lmmi_request_i;
    logic        usr_lmmi_wr_rdn_i; 
    logic [31:0] usr_lmmi_wdata_i;  
    logic [16:2] usr_lmmi_offset_i;
    logic [31:0] usr_lmmi_rdata_o;
    logic        usr_lmmi_rdata_valid_o;
    logic        usr_lmmi_ready_o;
    
    //assign usr_lmmi_request_i   = 1'b0;
    //assign usr_lmmi_wr_rdn_i    = 1'b0;
    //assign usr_lmmi_wdata_i     = 32'b0;
    //assign usr_lmmi_offset_i    = 15'b0;
    
    LMMI_app lmmi_app_inst 
    (
      .clk                   (usr_lmmi_clk_i),
      .rst_n                 (usr_lmmi_resetn_i),
      //LMMI interface
      .u_dl_link_up_i        (u_tl_link_up_o),
      .usr_lmmi_request_o    (usr_lmmi_request_i),
      .usr_lmmi_wr_rdn_o     (usr_lmmi_wr_rdn_i),
      .usr_lmmi_wdata_o      (usr_lmmi_wdata_i),
      .usr_lmmi_offset_o     (usr_lmmi_offset_i),
      .usr_lmmi_rdata_i      (usr_lmmi_rdata_o),
      .usr_lmmi_rdata_valid_i(usr_lmmi_rdata_valid_o),
      .usr_lmmi_ready_i      (usr_lmmi_ready_o),
      //completer id for tx engine
      .completer_id_o        (),
      .config_done           (),
      .gen_no                (generation),
      .max_payload           (max_payload)
    );
        
    logic ucfg_valid_i      ;
    logic ucfg_wr_rd_n_i    ;
    logic [9:0]  ucfg_addr_i       ;
    logic [2:0]  ucfg_f_i          ;
    logic [3:0]  ucfg_wr_be_i      ;
    logic [31:0] ucfg_wr_data_i    ;
    
    assign ucfg_valid_i                = 1'b0;
    assign ucfg_wr_rd_n_i              = 1'b0;
    assign ucfg_addr_i                 = 10'd0;
    assign ucfg_f_i                    = 3'b000;
    assign ucfg_wr_be_i                = 4'd0;
    assign ucfg_wr_data_i              = 32'd0;
    
    // assign link0_txp_o = txp_o;
    // assign link0_txn_o = txn_o;
    // assign rxp_i = link0_rxp_i;
    // assign rxn_i = link0_rxn_i;
    
    // PCIE IP Instantiation
    `include "../dut_inst.v"
    
    pcie_app application_layer_inst (
    .clk 								(sys_clk_i),
	.rst_n 								(rstn_clk2),
	.vc_rx_ready_o						(link0_rx_ready_i),
	.vc_rx_valid_i 						(link0_rx_valid_o),
	.vc_rx_sel_i 						(link0_rx_sel_o),
	.vc_rx_cmd_data_i 					(link0_rx_cmd_data_o),
	.vc_rx_sop_i 						(link0_rx_sop_o),
	.vc_rx_data_i 						(link0_rx_data_o),
	.vc_rx_datap_i 						(link0_rx_datap_o),
	.vc_rx_eop_i 						(link0_rx_eop_o),
	.vc_rx_err_ecrc_i 					(link0_rx_err_ecrc_o),
	.vc_rx_f_i 							(link0_rx_f_o),
	.vc_tx_valid_o 						(link0_tx_valid_i),
	.vc_tx_eop_o   						(link0_tx_eop_i),
	.vc_tx_eop_n_o 						(link0_tx_eop_n_i),
	.vc_tx_sop_o 						(link0_tx_sop_i),
	.vc_tx_data_o 						(link0_tx_data_i),
	.vc_tx_datap_o 						(link0_tx_datap_i),
	.vc_tx_ready_i 						(link0_tx_ready_o)
	//.completer_id_i 					(16'd100),
    //.segment_out                        ()
	// .bar_0_address                      (32'b0),
	// .bar_1_address                      (32'b0),
	// .write_data_check					(),
	// .rd_data_counter				    ()
	);
    
    
end else if ( (DEVICE_FAMILY == "LFD2NX" || DEVICE_FAMILY == "LIFCL" || SUPPORTED_LFMXO5_PCIEX1 == 1) && USR_DAT_IF_TYPE =="AXI_STREAM") begin
    
    assign link0_aux_clk_i = usr_lmmi_clk_i;
    assign link0_perst_n_i = ed_perst_n_i & lock_ip;
    assign link0_rst_usr_n_i = ed_usr_rst_n & lock_ip;
    assign clk_100 = clk_user;

    // logic        usr_lmmi_request_i;
    // logic        usr_lmmi_wr_rdn_i; 
    // logic [31:0] usr_lmmi_wdata_i;  
    // logic [16:2] usr_lmmi_offset_i;
    
    // assign usr_lmmi_request_i   = 1'b0;
    // assign usr_lmmi_wr_rdn_i    = 1'b0;
    // assign usr_lmmi_wdata_i     = 32'b0;
    // assign usr_lmmi_offset_i    = 15'b0;
    
    /*LMMI_app lmmi_app_inst 
    (
      .clk                   (usr_lmmi_clk_i),
      .rst_n                 (usr_lmmi_resetn_i),
      //LMMI interface
      .u_dl_link_up_i        (u_tl_link_up_o),
      .usr_lmmi_request_o    (usr_lmmi_request_i),
      .usr_lmmi_wr_rdn_o     (usr_lmmi_wr_rdn_i),
      .usr_lmmi_wdata_o      (usr_lmmi_wdata_i),
      .usr_lmmi_offset_o     (usr_lmmi_offset_i),
      .usr_lmmi_rdata_i      (usr_lmmi_rdata_o),
      .usr_lmmi_rdata_valid_i(usr_lmmi_rdata_valid_o),
      .usr_lmmi_ready_i      (usr_lmmi_ready_o),
      //completer id for tx engine
      .completer_id_o        (),
      .config_done           (),
      .gen_no                (generation),
      .max_payload           (max_payload)
    );
    */
    
    //APB CSR interface being used to configure the core and overcome the modelling issues on the SW primitive
    logic         c_apb_pclk_i;
    logic         c_apb_preset_n_i;
    logic  [31:0] c_apb_paddr_i;
    logic         c_apb_psel_i;
    logic         c_apb_penable_i;
    logic         c_apb_pwrite_i;
    logic  [31:0] c_apb_pwdata_i;
    logic  [31:0] c_apb_prdata_o;
    logic         c_apb_pready_o;
    logic         c_apb_pslverr_o;
    
    //Both APB and LMMI interface able to work at 100MHz so let's reuse LMMI clock and reset
    assign c_apb_pclk_i = usr_lmmi_clk_i;
    assign c_apb_preset_n_i = usr_lmmi_resetn_i;
    
    apb_master_wrapper_non_dma apb_master_wrapper_non_dma_inst 
    (
      .config_done    (),
      .apb_clk_i      (c_apb_pclk_i),  //msanthi : NEED TO SETTLE THE CLOCK AND RESET for APB before can test
      .apb_reset_n_i  (c_apb_preset_n_i),
      .apb_addr_o     (c_apb_paddr_i),
      .apb_sel_o      (c_apb_psel_i),
      .apb_enable_o   (c_apb_penable_i),
      .apb_write_o    (c_apb_pwrite_i),
      .apb_wdata_o    (c_apb_pwdata_i),
      .apb_rdata_i    (c_apb_prdata_o),
      .apb_ready_i    (c_apb_pready_o),
      .apb_slverr_i   (c_apb_pslverr_o),
      .gen_no         (generation),
      .read_data_id   (),
      .max_payload    (max_payload)
    );
    
    logic ucfg_valid_i      ;
    logic ucfg_wr_rd_n_i    ;
    logic [9:0]  ucfg_addr_i       ;
    logic [2:0]  ucfg_f_i          ;
    logic [3:0]  ucfg_wr_be_i      ;
    logic [31:0] ucfg_wr_data_i    ;
    
    assign ucfg_valid_i                = 1'b0;
    assign ucfg_wr_rd_n_i              = 1'b0;
    assign ucfg_addr_i                 = 10'd0;
    assign ucfg_f_i                    = 3'b000;
    assign ucfg_wr_be_i                = 4'd0;
    assign ucfg_wr_data_i              = 32'd0;
    
    // assign link0_txp_o = txp_o;
    // assign link0_txn_o = txn_o;
    // assign rxp_i = link0_rxp_i;
    // assign rxn_i = link0_rxn_i;
    
    //AXISTREAM data interface specific
    logic m0_tready_i ; 
	logic m0_tvalid_o ; 
	logic m0_tlast_o ; 
	logic [64*WIDTH-1:0] m0_tdata_o ; 
	logic [15:0] m0_tstrb_o ; 
	logic [15:0] m0_tkeep_o ; 
	logic [7:0] m0_tid_o ; 
	logic [3:0] m0_tdest_o ; 
	logic s0_tready_o ; 
	logic s0_tvalid_i ; 
	logic s0_tlast_i ; 
	logic [64*WIDTH-1:0] s0_tdata_i ; 
	logic [DATA_WIDTH/8 - 1:0] s0_tstrb_i ; 
	logic [DATA_WIDTH/8 - 1:0] s0_tkeep_i ; 
	logic [7:0] s0_tid_i ; 
	logic [3:0] s0_tdest_i ; 
    
    assign m0_tready_i = link0_rx_ready_i;
    assign link0_tx_ready_o = s0_tready_o;
    
    // PCIE IP Instantiation
    `include "../dut_inst.v"
    
    pcie_app application_layer_inst (
    .clk 								(sys_clk_i),
	.rst_n 								(rstn_clk2),
	.vc_rx_ready_o						(link0_rx_ready_i),
	.vc_rx_valid_i 						(link0_rx_valid_o),
	.vc_rx_sel_i 						(link0_rx_sel_o),
	.vc_rx_cmd_data_i 					(link0_rx_cmd_data_o),
	.vc_rx_sop_i 						(link0_rx_sop_o),
	.vc_rx_data_i 						(link0_rx_data_o),
	.vc_rx_datap_i 						(link0_rx_datap_o),
	.vc_rx_eop_i 						(link0_rx_eop_o),
	.vc_rx_err_ecrc_i 					(link0_rx_err_ecrc_o),
	.vc_rx_f_i 							(link0_rx_f_o),
	.vc_tx_valid_o 						(link0_tx_valid_i),
	.vc_tx_eop_o   						(link0_tx_eop_i),
	.vc_tx_eop_n_o 						(link0_tx_eop_n_i),
	.vc_tx_sop_o 						(link0_tx_sop_i),
	.vc_tx_data_o 						(link0_tx_data_i),
	.vc_tx_datap_o 						(link0_tx_datap_i),
	.vc_tx_ready_i 						(link0_tx_ready_o)
	//.completer_id_i 					(16'd100),
    //.segment_out                        ()
	// .bar_0_address                      (32'b0),
	// .bar_1_address                      (32'b0),
	// .write_data_check					(),
	// .rd_data_counter				    ()
	);
    
    axi2tlp #(
           .DATA_WIDTH(DATA_WIDTH)
           )
    axi_2_tlp(
          .clk                   (sys_clk_i),
          .rst_n                 (rstn_clk2),
          .m0_tvalid_o           (m0_tvalid_o),
          .m0_tdata_o            (m0_tdata_o),
          .m0_tlast_o            (m0_tlast_o),
          .m0_tready_i           (m0_tready_i),
          .link0_rx_data_o       (link0_rx_data_o),
          .link0_rx_valid_o      (link0_rx_valid_o),
          .link0_rx_sop_o        (link0_rx_sop_o),
          .link0_rx_eop_o        (link0_rx_eop_o)
          );

    tlp2axi #(
          .DATA_WIDTH(DATA_WIDTH)
          )
    tlp_2_axi(
          .clk                   (sys_clk_i),
          .rst_n                 (rstn_clk2),
          .vc_tx_valid_i         (link0_tx_valid_i),
          .vc_tx_eop_i           (link0_tx_eop_i),
          .vc_tx_data_i          (link0_tx_data_i),
          .s0_tvalid_i           (s0_tvalid_i),
          .s0_tlast_i            (s0_tlast_i),
          .s0_tdata_i            (s0_tdata_i),
          .s0_tstrb_i            (s0_tstrb_i),
          .s0_tkeep_i            (s0_tkeep_i),
          .s0_tid_i              (s0_tid_i),
          .s0_tdest_i            (s0_tdest_i)
          );
          


end else if ((DEVICE_FAMILY == "LFCPNX" || SUPPORTED_LFMXO5_PCIEX4 ==1) && USR_DAT_IF_TYPE =="TLP" && ~(((LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 1) | (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 0)) & (WIDTH == 1))) begin :LFCPNX_Enhanced_Application_Layer
    
    wire [1:0] generation;
    assign generation  = (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 2)? 2'd2 : ((LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 1) ? 2'd1 : 2'd0);
    assign link0_aux_clk_i = usr_lmmi_clk_i;
    assign link0_perst_n_i = ed_perst_n_i & lock_ip;
    assign link0_rst_usr_n_i = ed_usr_rst_n & lock_ip;
    assign clk_125 = clk_user;
    
    wire acjtag_mode_i;
    wire use_refmux_i;
    wire sd_pll_refclk_i;
    wire diffioclksel_i;
    wire [1:0]clksel_i;

    assign acjtag_mode_i   =  1'b0;
    assign use_refmux_i    =  1'b0;
    assign sd_pll_refclk_i =  1'b0;
    assign diffioclksel_i  =  1'b0;
    assign clksel_i        =  2'b0;
    

    logic    [4:0]    usr_lmmi_request_i;
    logic        usr_lmmi_wr_rdn_i; 
    logic [31:0] usr_lmmi_wdata_i;  
    logic [16:0] usr_lmmi_offset_i;
    
    logic [63:0] usr_lmmi_rdata_o ;
    logic [4:0] usr_lmmi_rdata_valid_o ;
    logic [4:0] usr_lmmi_ready_o;
    
    //assign usr_lmmi_request_i   = 1'b0;
    //assign usr_lmmi_wr_rdn_i    = 1'b0;
    //assign usr_lmmi_wdata_i     = 32'b0;
    //assign usr_lmmi_offset_i    = 15'b0;
    
    LMMI_app_old #(
          .NUM_OF_LANES(WIDTH)
	) lmmi_app_inst
    (
      .clk                   (usr_lmmi_clk_i),
      .rst_n                 (usr_lmmi_resetn_i),
      //LMMI interface
      .usr_lmmi_request_o    (usr_lmmi_request_i),
      .usr_lmmi_wr_rdn_o     (usr_lmmi_wr_rdn_i),
      .usr_lmmi_wdata_o      (usr_lmmi_wdata_i),
      .usr_lmmi_offset_o     (usr_lmmi_offset_i),
      .usr_lmmi_rdata_i      (usr_lmmi_rdata_o),
      .usr_lmmi_rdata_valid_i(usr_lmmi_rdata_valid_o),
      .usr_lmmi_ready_i      (usr_lmmi_ready_o),
      //completer id for tx engine
      .config_done           (),
      .gen_no                (generation),
      .lane_no               (WIDTH)
    );
            
    wire ucfg_link_i;   
    wire ucfg_valid_i;  
    wire ucfg_wr_rd_n_i;
    wire [11:2] ucfg_addr_i;   
    wire [2:0]  ucfg_f_i;      
    wire [3:0]  ucfg_wr_be_i;  
    wire [31:0] ucfg_wr_data_i;

    
    assign ucfg_link_i         = 1'b0;
    //assign ucfg_valid_i                = 1'b0;
    //assign ucfg_wr_rd_n_i              = 1'b0;
    //assign ucfg_addr_i                 = 10'd0;
    assign ucfg_f_i                    = 3'b000;
    assign ucfg_wr_be_i                = 4'd0;
    //assign ucfg_wr_data_i              = 32'd0;
    
    logic [15:0] completer_id_i;
    
    ucfg_app ucfg_app_inst (
                        .clk           (sys_clk_i),                 
	                    .rst_n         (rstn_clk2),
	                    .u_tl_linkup   (link0_tl_link_up_o),
	                    .ucfg_ready_i  (ucfg_ready_o),
                        .ucfg_wr_rd_n_o(ucfg_wr_rd_n_i),
                        .ucfg_valid_o  (ucfg_valid_i),
                        .ucfg_addr_o   (ucfg_addr_i),
                        .ucfg_rdata_i  (ucfg_rd_data_o),
                        .ucfg_rd_done_i(ucfg_rd_done_o),           
                        .ucfg_wr_data_o(ucfg_wr_data_i),
	                    .read_data     (read_data_id_tlp)	                    
                       );
    
    assign completer_id_i =  read_data_id_tlp;

    
    // PCIE IP Instantiation
    `include "../dut_inst.v"
    
    //msanthi : Moving to the new PCIe Application layer for better customer experience and leverage Keng dar time investment
    //msanthi : Only con is doesn't support 1x1 bifurcation. 
    pcie_app  # (
    .DATA_WIDTH							(DATA_WIDTH),
    .NUM_OF_LANES                       (WIDTH),
    .SERIES_PATTERN                     (SERIES_PATTERN),
    .NUM_PACKETS                        (NUM_PACKETS),
    .DW_ALIGN_RAM                       (DW_ALIGN_RAM), // KD
    .DEVICE_FAMILY                      (DEVICE_FAMILY),
    .LINK0_FTL_INITIAL_TARGET_LINK_SPEED (LINK0_FTL_INITIAL_TARGET_LINK_SPEED)
	)
	application_layer_inst (
        .clk 							(sys_clk_int),
	.clk_250                                                (clk_usr_i_250MHz),
	.rst_n 							(rstn_clk2),
	.vc_rx_ready_o						(link0_rx_ready_i),
	.vc_rx_valid_i 						(link0_rx_valid_o),
	.vc_rx_sel_i 						(link0_rx_sel_o),
	.vc_rx_cmd_data_i 					(link0_rx_cmd_data_o),
	.vc_rx_sop_i 						(link0_rx_sop_o),
	.vc_rx_data_i 						(link0_rx_data_o),
	.vc_rx_datap_i 						(link0_rx_datap_o),
	.vc_rx_eop_i 						(link0_rx_eop_o),
	.vc_rx_err_ecrc_i 					(link0_rx_err_ecrc_o),
	.vc_rx_f_i 							(link0_rx_f_o),
	.vc_tx_valid_o 						(link0_tx_valid_i),
	.vc_tx_eop_o   						(link0_tx_eop_i),
	.vc_tx_eop_n_o 						(link0_tx_eop_n_i),
	.vc_tx_sop_o 						(link0_tx_sop_i),
	.vc_tx_data_o 						(link0_tx_data_i),
	.vc_tx_datap_o 						(link0_tx_datap_i),
	.vc_tx_ready_i 						(link0_tx_ready_o),
	.completer_id_i 					(completer_id_i),
	.bar_0_address                      (32'b0),
	.bar_1_address                      (32'b0),
	.write_data_check					(),
	.rd_data_counter				    ()
	);
    

end else if ((DEVICE_FAMILY == "LFCPNX"|| SUPPORTED_LFMXO5_PCIEX4 ==1) && USR_DAT_IF_TYPE =="TLP" && WIDTH == 1) begin :LFCPNX_Legacy_Application_Layer

    wire [1:0] generation;
    assign generation  = (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 2)? 2'd2 : ((LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 1) ? 2'd1 : 2'd0);
    assign link0_aux_clk_i = usr_lmmi_clk_i;
    assign link0_perst_n_i = ed_perst_n_i & lock_ip;
    assign link0_rst_usr_n_i = ed_usr_rst_n & lock_ip;
    assign clk_125 = clk_user;

    wire acjtag_mode_i;
    wire use_refmux_i;
    wire sd_pll_refclk_i;
    wire diffioclksel_i;
    wire [1:0]clksel_i;

    assign acjtag_mode_i   =  1'b0;
    assign use_refmux_i    =  1'b0;
    assign sd_pll_refclk_i =  1'b0;
    assign diffioclksel_i  =  1'b0;
    assign clksel_i        =  2'b0;
    
    logic    [4:0]    usr_lmmi_request_i;
    logic        usr_lmmi_wr_rdn_i; 
    logic [31:0] usr_lmmi_wdata_i;  
    logic [16:0] usr_lmmi_offset_i;
    
    logic [63:0] usr_lmmi_rdata_o ;
    logic [4:0] usr_lmmi_rdata_valid_o ;
    logic [4:0] usr_lmmi_ready_o;
    
    //assign usr_lmmi_request_i   = 1'b0;
    //assign usr_lmmi_wr_rdn_i    = 1'b0;
    //assign usr_lmmi_wdata_i     = 32'b0;
    //assign usr_lmmi_offset_i    = 15'b0;
    
    LMMI_app_old #(
          .NUM_OF_LANES(WIDTH)
	) lmmi_app_inst
    (
      .clk                   (usr_lmmi_clk_i),
      .rst_n                 (usr_lmmi_resetn_i),
      //LMMI interface
      .usr_lmmi_request_o    (usr_lmmi_request_i),
      .usr_lmmi_wr_rdn_o     (usr_lmmi_wr_rdn_i),
      .usr_lmmi_wdata_o      (usr_lmmi_wdata_i),
      .usr_lmmi_offset_o     (usr_lmmi_offset_i),
      .usr_lmmi_rdata_i      (usr_lmmi_rdata_o),
      .usr_lmmi_rdata_valid_i(usr_lmmi_rdata_valid_o),
      .usr_lmmi_ready_i      (usr_lmmi_ready_o),
      //completer id for tx engine
      .config_done           (),
      .gen_no                (generation),
      .lane_no               (WIDTH)
    );
            
    wire ucfg_link_i;   
    wire ucfg_valid_i;  
    wire ucfg_wr_rd_n_i;
    wire [11:2] ucfg_addr_i;   
    wire [2:0]  ucfg_f_i;      
    wire [3:0]  ucfg_wr_be_i;  
    wire [31:0] ucfg_wr_data_i;
    
    assign ucfg_link_i         = 1'b0;
    assign ucfg_valid_i                = 1'b0;
    assign ucfg_wr_rd_n_i              = 1'b0;
    assign ucfg_addr_i                 = 10'd0;
    assign ucfg_f_i                    = 3'b000;
    assign ucfg_wr_be_i                = 4'd0;
    assign ucfg_wr_data_i              = 32'd0;
    
    //logic [15:0] completer_id_i;
    
    // ucfg_app ucfg_app_inst (
                        // .clk           (sys_clk_i),                 
	                    // .rst_n         (rstn_clk2),
	                    // .u_tl_linkup   (link0_tl_link_up_o),
	                    // .ucfg_ready_i  (ucfg_ready_o),
                        // .ucfg_wr_rd_n_o(ucfg_wr_rd_n_i),
                        // .ucfg_valid_o  (ucfg_valid_i),
                        // .ucfg_addr_o   (ucfg_addr_i),
                        // .ucfg_rdata_i  (ucfg_rd_data_o),
                        // .ucfg_rd_done_i(ucfg_rd_done_o),           
                        // .ucfg_wr_data_o(ucfg_wr_data_i),
	                    // .read_data     (read_data_id_tlp)	                    
                       // );
    
    // assign completer_id_i =  read_data_id_tlp;

    
    // PCIE IP Instantiation
    `include "../dut_inst.v"
    
    //msanthi : Moving to the new PCIe Application layer for better customer experience and leverage Keng dar time investment
    //msanthi : Only con is doesn't support 1x1 bifurcation. 
    pcie_app_32bit  # (
	)
	application_layer_inst (
    .clk 								(sys_clk_i),
	.rst_n 								(rstn_clk2),
	.vc_rx_ready_o						(link0_rx_ready_i),
	.vc_rx_valid_i 						(link0_rx_valid_o),
	.vc_rx_sel_i 						(link0_rx_sel_o),
	.vc_rx_cmd_data_i 					(link0_rx_cmd_data_o),
	.vc_rx_sop_i 						(link0_rx_sop_o),
	.vc_rx_data_i 						(link0_rx_data_o),
	.vc_rx_datap_i 						(link0_rx_datap_o),
	.vc_rx_eop_i 						(link0_rx_eop_o),
	.vc_rx_err_ecrc_i 					(link0_rx_err_ecrc_o),
	.vc_rx_f_i 							(link0_rx_f_o),
	.vc_tx_valid_o 						(link0_tx_valid_i),
	.vc_tx_eop_o   						(link0_tx_eop_i),
	.vc_tx_eop_n_o 						(link0_tx_eop_n_i),
	.vc_tx_sop_o 						(link0_tx_sop_i),
	.vc_tx_data_o 						(link0_tx_data_i),
	.vc_tx_datap_o 						(link0_tx_datap_i),
	.vc_tx_ready_i 						(link0_tx_ready_o)
	//.completer_id_i 					(completer_id_i),
	//.bar_0_address                      (32'b0),
	//.bar_1_address                      (32'b0),
	//.write_data_check					(),
	//.rd_data_counter				    ()
	);


end else if ((DEVICE_FAMILY == "LFCPNX"|| SUPPORTED_LFMXO5_PCIEX4 ==1) && USR_DAT_IF_TYPE =="AXI_STREAM" && (EN_AXI_DMA == 1)) begin : PCIE_AXIST_DMA

    wire acjtag_mode_i;
    wire use_refmux_i;
    wire sd_pll_refclk_i;
    wire diffioclksel_i;
    wire [1:0]clksel_i;
    wire link0_clk_usr_o;
    wire clk_usr_div2_i;
    logic [4:0]  usr_lmmi_request_i;
    logic        usr_lmmi_wr_rdn_i; 
    logic [31:0] usr_lmmi_wdata_i;  
    logic [16:0] usr_lmmi_offset_i;
    logic [63:0] usr_lmmi_rdata_o ;
    logic [4:0] usr_lmmi_rdata_valid_o ;
    logic [4:0] usr_lmmi_ready_o;

    logic tx0_dma_axist_tready_o;
    logic tx0_dma_axist_tvalid_i;
    logic tx0_dma_axist_tlast_i;
    logic [255:0] tx0_dma_axist_tdata_i;
    logic [0:0] usr_int_req_i, usr_int_ack_o;
    logic reg_usr_int_first_tlast;
    assign reg_usr_int_first_tlast = (SIM == 1) ? usr_vector_done_set :1'b0;

    // AXI4-lite DMA Bypass
    wire [63:0] m0_axil_awaddr_o;
    wire [7:0] m0_axil_awlen_o;
    wire [2:0] m0_axil_awsize_o;
    wire [1:0] m0_axil_awburst_o;
    wire m0_axil_awlock_o;
    wire [3:0] m0_axil_awcache_o;
    wire [2:0] m0_axil_awprot_o;
    wire m0_axil_awvalid_o;
    wire m0_axil_awready_i;
    wire [31:0] m0_axil_wdata_o;
    wire [3:0] m0_axil_wstrb_o;
    wire m0_axil_wlast_o;
    wire m0_axil_wvalid_o;
    wire m0_axil_wready_i;
    wire [2:0] m0_axil_bid_i;
    wire [1:0] m0_axil_bresp_i;
    wire m0_axil_bvalid_i;
    wire m0_axil_bready_o;
    wire [2:0] m0_axil_arid_o;
    wire [63:0] m0_axil_araddr_o;
    wire [7:0] m0_axil_arlen_o;
    wire [2:0] m0_axil_arsize_o;
    wire [1:0] m0_axil_arburst_o;
    wire m0_axil_arlock_o;
    wire [3:0] m0_axil_arcache_o;
    wire [2:0] m0_axil_arprot_o;
    wire m0_axil_arvalid_o;
    wire m0_axil_arready_i;
    wire [2:0] m0_axil_rid_i;
    wire [31:0] m0_axil_rdata_i;
    wire [1:0] m0_axil_rresp_i;
    wire m0_axil_rlast_i;
    wire m0_axil_rvalid_i;
    wire m0_axil_rready_o;
    wire [3:0] m0_axil_arqos_o;
    wire [7:0] m0_axil_aruser_o;

    // AXI4-MM DMA Bypass
    // AXI Address Write Channel
    logic [7:0] m0_aximm_awid_o;
    logic [63:0] m0_aximm_awaddr_o;
    logic [7:0] m0_aximm_awlen_o;
    logic [2:0] m0_aximm_awsize_o;
    logic [1:0] m0_aximm_awburst_o;
    logic m0_aximm_awlock_o; // Not supported.
    logic [3:0] m0_aximm_awcache_o; // Not supported.
    logic [2:0] m0_aximm_awprot_o; // Not supported.
    logic [3:0] m0_aximm_awregion_o; // Not supported.
    logic m0_aximm_awvalid_o;
    logic m0_aximm_awready_i;
    // AXI Write Channel
    logic [31:0] m0_aximm_wdata_o;
    logic [3:0] m0_aximm_wstrb_o;
    logic m0_aximm_wlast_o;
    logic [7:0] m0_aximm_wuser_o; // Not supported.
    logic m0_aximm_wvalid_o;
    logic  m0_aximm_wready_i;
    // AXI Write Response Channel
    logic [7:0] m0_aximm_bid_i;
    logic [1:0] m0_aximm_bresp_i;
    logic m0_aximm_bvalid_i;
    logic m0_aximm_bready_o;
    // AXI Read Address Channel
    logic m0_aximm_arready_i;
    logic [7:0] m0_aximm_arid_o;
    logic [63:0] m0_aximm_araddr_o;
    logic [7:0] m0_aximm_arlen_o;
    logic [2:0] m0_aximm_arsize_o;
    logic [1:0] m0_aximm_arburst_o;
    logic m0_aximm_arvalid_o;
    logic [2:0] m0_aximm_arprot_o; // Not supported.
    logic [3:0] m0_aximm_arqos_o; // Not supported.
    logic [3:0] m0_aximm_arcache_o; // Not supported
    logic m0_aximm_arlock_o; // Not supported.
    logic [7:0] m0_aximm_aruser_o; // Not supported.
    // AXI Read Data Channel
    logic [7:0] m0_aximm_rid_i;
    logic [31:0] m0_aximm_rdata_i;
    logic [1:0] m0_aximm_rresp_i;
    logic m0_aximm_rlast_i;
    logic m0_aximm_rvalid_i;
    logic m0_aximm_rready_o;

       // Debug Signals
    logic dbg_link0_rx_ready_o;
    logic dbg_link0_rx_valid_o;
    logic [1:0] dbg_link0_rx_sel_o;
    logic [12:0] dbg_link0_rx_cmd_data_o;
    logic dbg_link0_rx_sop_o;
    logic [63:0] dbg_link0_rx_data_o;
    logic [7:0] dbg_link0_rx_datap_o;
    logic dbg_link0_rx_eop_o;
    logic dbg_link0_rx_err_ecrc_o;
    logic [1:0] dbg_link0_rx_f_o;
    logic dbg_link0_tx_valid_o;
    logic [63:0] dbg_link0_tx_data_o;
    logic [7:0] dbg_link0_tx_datap_o;
    logic dbg_link0_tx_eop_o;
    logic dbg_link0_tx_eop_n_o;
    logic dbg_link0_tx_sop_o;
    logic dbg_link0_tx_ready_o;

    assign clk_125         =  clk_user;
    assign clk_usr_div2_i  =  clk_usr_i_125MHz;
    assign acjtag_mode_i   =  1'b0;
    assign use_refmux_i    =  1'b0;
    assign sd_pll_refclk_i =  1'b0;
    assign diffioclksel_i  =  1'b0;
    assign clksel_i        =  2'b0;
    assign link0_aux_clk_i =  1'b0;
    assign clk_usr_o       =  link0_clk_usr_o;
    assign link0_perst_n_i = ed_perst_n_i & lock_ip;
    assign link0_rst_usr_n_i = ed_usr_rst_n & lock_ip;

    OSCA #(
        .HF_CLK_DIV("9")
    ) ep_OSC (
        //Inputs                   
        .HFOUTEN(1'b1), 
        .HFSDSCEN(1'b0), 
        //Outputs                  
        .HFCLKOUT(usr_lmmi_clk_i),
        .LFCLKOUT (),
        .HFCLKCFG (),
        .HFSDCOUT ()
    );

    LMMI_app lmmi_app_inst (
        .clk (usr_lmmi_clk_i),
        .rst_n (usr_lmmi_resetn_i),
        .usr_lmmi_request_o(lmmi_request),
        .usr_lmmi_wr_rdn_o (lmmi_wr_rdn),
        .usr_lmmi_wdata_o  (lmmi_wdata),
        .usr_lmmi_offset_o (lmmi_offset),
        .usr_lmmi_rdata_i  (lmmi_rdata),
        .usr_lmmi_rdata_valid_i(lmmi_rdata_valid),
        .usr_lmmi_ready_i      (lmmi_ready),
        .config_done  (config_done)
    );

    axist_generator #(
        .IMAGE_PATTERN(IMAGE_PATTERN), // 1: image pattern. 0: incremental pattern.
        .PER_BYTE_INCR(PER_BYTE_INCR), // Used when IMAGE_PATTERN == 1'b0. 1: Incremented per byte. 0: Incremented per 32-byte.
        .IMAGE_PATTERN_ONCE(IMAGE_PATTERN_ONCE), // 1: Used when IMAGE_PATTERN == 1. 1: Send image pattern once. 0: Send repeatedly.
        .STREAM_SIZE(STREAM_SIZE)      // 16 KB for a stream.
    ) axist_generator_inst (
        .clk_i(clk_usr_i_125MHz),
        .rst_n_i(rstn_clk2),
        .tx_dma_axist_tready_i(tx0_dma_axist_tready_o),
        .tx_dma_axist_tvalid_o(tx0_dma_axist_tvalid_i),
        .tx_dma_axist_tlast_o(tx0_dma_axist_tlast_i),
        .tx_dma_axist_tdata_o(tx0_dma_axist_tdata_i),
        .usr_int_req_o(usr_int_req_i),
        .usr_int_ack_i(usr_int_ack_o),
        .reg_usr_int_first_tlast(reg_usr_int_first_tlast) // TODO
    );

   // PCIE IP Instantiation
`include "../dut_inst.v"

if ((DMA_BYPASS_EN == 1) & (DMA_BYPASS_IF_TYPE == "AXI_LITE")) begin: AXI4L_DMA_BYP

   dma_local_mem  # (
       .DEVICE_FAMILY ("LFCPNX"),
       .AWID_WIDTH(3),      // ARID_WIDTH & AWID_WIDTH
       .ARID_WIDTH(3),      // ARID_WIDTH & AWID_WIDTH
       .AXI_WIDTH(32),      // AXI_WIDTH
       .CHK_U_ADDR_EN(0),   // Dont check because upper can be BAR address
       .CHK_L_ADDR_EN(0)    // Dont check becasue alignment requirement is only for DMA RAM.
   )
   dma_byp_ram_inst (
       //AW
       .axi_awid_o     ('0),
       .axi_awaddr_o   (m0_axil_awaddr_o),
       .axi_awlen_o    ('0), // 0 means 1 beat
       .axi_awvalid_o  (m0_axil_awvalid_o),
       .axi_awready_i  (m0_axil_awready_i),
       //W
       .axi_wdata_o    (m0_axil_wdata_o),
       .axi_wstrb_o    (m0_axil_wstrb_o),
       .axi_wlast_o    (1'b1),
       .axi_wvalid_o   (m0_axil_wvalid_o),
       .axi_wready_i   (m0_axil_wready_i),
       //B
       .axi_bid_i      (),
       .axi_bresp_i    (m0_axil_bresp_i),
       .axi_bvalid_i   (m0_axil_bvalid_i),
       .axi_bready_o   (m0_axil_bready_o),
       //AR
       .axi_arready_i  (m0_axil_arready_i),
       .axi_arid_o     ('0),
       .axi_araddr_o   (m0_axil_araddr_o),
       .axi_arlen_o    ('0), // 0 means 1 beat
       .axi_arvalid_o  (m0_axil_arvalid_o),
       //R
       .axi_rid_i      (),
       .axi_rdata_i    (m0_axil_rdata_i),
       .axi_rresp_i    (m0_axil_rresp_i),
       .axi_rlast_i    (),
       .axi_rvalid_i   (m0_axil_rvalid_i),
       .axi_rready_o   (m0_axil_rready_o),
       //KD end
       .clk           (clk_usr_i_125MHz),
       .rst_n         (rstn_clk2)
   );
end

if ((DMA_BYPASS_EN == 1) & (DMA_BYPASS_IF_TYPE == "AXI_MM")) begin: AXI4MM_DMA_BYP

   dma_local_mem  # (
       .DEVICE_FAMILY ("LFCPNX"),
       .AWID_WIDTH(3),      // ARID_WIDTH & AWID_WIDTH
       .ARID_WIDTH(3),      // ARID_WIDTH & AWID_WIDTH
       .AXI_WIDTH(32),      // AXI_WIDTH
       .CHK_U_ADDR_EN(0),   // Dont check because upper can be BAR address
       .CHK_L_ADDR_EN(0)    // Dont check becasue alignment requirement is only for DMA RAM.
   )
   dma_byp_ram_inst (
       //AW
       .axi_awid_o     (m0_aximm_awid_o[2:0]),
       .axi_awaddr_o   (m0_aximm_awaddr_o),
       .axi_awlen_o    (m0_aximm_awlen_o),
       .axi_awvalid_o  (m0_aximm_awvalid_o),
       .axi_awready_i  (m0_aximm_awready_i),
       //W
       .axi_wdata_o    (m0_aximm_wdata_o),
       .axi_wstrb_o    (m0_aximm_wstrb_o),
       .axi_wlast_o    (m0_aximm_wlast_o),
       .axi_wvalid_o   (m0_aximm_wvalid_o),
       .axi_wready_i   (m0_aximm_wready_i),
       //B
       .axi_bid_i      (m0_aximm_bid_i[2:0]),
       .axi_bresp_i    (m0_aximm_bresp_i),
       .axi_bvalid_i   (m0_aximm_bvalid_i),
       .axi_bready_o   (m0_aximm_bready_o),
       //AR
       .axi_arready_i  (m0_aximm_arready_i),
       .axi_arid_o     (m0_aximm_arid_o[2:0]),
       .axi_araddr_o   (m0_aximm_araddr_o),
       .axi_arlen_o    (m0_aximm_arlen_o),
       .axi_arvalid_o  (m0_aximm_arvalid_o),
       //R
       .axi_rid_i      (m0_aximm_rid_i[2:0]),
       .axi_rdata_i    (m0_aximm_rdata_i),
       .axi_rresp_i    (m0_aximm_rresp_i),
       .axi_rlast_i    (m0_aximm_rlast_i),
       .axi_rvalid_i   (m0_aximm_rvalid_i),
       .axi_rready_o   (m0_aximm_rready_o),
       //KD end
       .clk           (clk_usr_i_125MHz),
       .rst_n         (rstn_clk2)
   );
end


end 
endgenerate

assign clk_sel = 1'b1;
assign pcie_sel = 1'b0;
assign pcie_sw1_pd = 1'b0;
assign pcie_sw2_pd = 1'b0;
//Passing linkup done through a NOT gate as LED's are active low.
assign linkup_done = ~((link0_pl_link_up & link0_dl_link_up & link0_tl_link_up) || (link0_pl_link_up_o & link0_dl_link_up_o & link0_tl_link_up_o));

always @(posedge rst_sync_clk or negedge rst_n)
begin 
	if (~rst_n) 
    begin 
		rstn_meta   <= 1'b0;
		rstn_clk2   <= 1'b0;
	end 
	else 
	begin 
		rstn_meta   <= 1'b1;
		rstn_clk2   <=rstn_meta;
	end 
end 

always @(posedge usr_lmmi_clk_i)
begin 
	if (~ed_perst_n_i) 
    begin 
		usr_lmmi_resetn_i   <= 1'b0;
	end 
	else 
	begin 
		usr_lmmi_resetn_i   <= 1'b1;
	end 
end 


debounce # (
    . SIM   		(SIM)
)	
debounce_inst 	
(	
	.clk      		(clk_user),
	.pb_in_n  		(ed_usr_rst_n),
	.pb_out   		(rst_n)
);	

generate 
if (DEVICE_FAMILY == "LAV-AT") begin

  pll_clk pll_clk_inst (	
	.clki_i  							(clk_100),
    .rstn_i  							(ed_usr_rst_n),
    .clkop_o 							(sys_clk_i), //250MHz
    .lock_o  							(lock_ip)
  );	

  osc_ip  osc_ip_inst (	
    .en_i         						(1'b1),
	.clk_sel_i                          (1'b0),
	.clk_out_o 						    (usr_lmmi_clk_i) //100MHz
  );

end else if (DEVICE_FAMILY =="LFCPNX" || SUPPORTED_LFMXO5_PCIEX4 == 1 ) begin

    if (USR_DAT_IF_TYPE =="AXI_STREAM" && (EN_AXI_DMA == 1) ) begin
        pll_250 pll_250_inst (
            .clki_i(clk_125),
            .rstn_i(ed_usr_rst_n),
            .clkop_o(clk_250),
            .clkos_o(clk_usr_i_125MHz),
            .lock_o(lock_ip)
        );
        assign sys_clk_i = clk_250;
        assign sys_clk_int = clk_usr_i_125MHz;

    end else if (USR_DAT_IF_TYPE =="TLP") begin
        pll_cnx pll_cnx_inst(.clki_i(clk_125),
            .rstn_i(ed_usr_rst_n),
            .clkop_o(usr_lmmi_clk_i),
            .clkos_o(clk_usr_i_125MHz),
            .clkos2_o(clk_usr_i_62_5MHz),
            .clkos3_o(clk_usr_i_250MHz),
            .lock_o(lock_ip));

        assign sys_clk_i = (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 2) ? clk_usr_i_250MHz : (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 1) ? clk_usr_i_125MHz : clk_usr_i_62_5MHz;
        assign sys_clk_int = ((LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 2) | (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 1)) ? clk_usr_i_125MHz : clk_usr_i_62_5MHz;
    end

end else if (DEVICE_FAMILY == "LFD2NX" || DEVICE_FAMILY == "LIFCL" ) begin
    pll_cnx pll_cnx_inst(.clki_i(clk_100),
        .rstn_i(ed_usr_rst_n),
        .clkop_o(usr_lmmi_clk_i), //100MHz
        .clkos_o(clk_usr_i_125MHz), //125MHz
        .clkos2_o(clk_usr_i_62_5MHz), //62.5MHz
        .lock_o(lock_ip));

    assign clk_usr_i = clk_usr_i_125MHz;
    assign sys_clk_i = clk_usr_i;

end else if ( SUPPORTED_LFMXO5_PCIEX1 == 1 ) begin

    pll_machxo5 pll_machxo5_inst(.clki_i(clk_125),
        .rstn_i(ed_usr_rst_n),
        .clkop_o(usr_lmmi_clk_i), //100MHz
        .clkos_o(clk_usr_i_125MHz), //125MHz
        .clkos2_o(clk_usr_i_62_5MHz), //62.5MHz
        .lock_o(lock_ip));

    assign clk_usr_i = clk_usr_i_125MHz;
    assign sys_clk_i = clk_usr_i;


end
endgenerate


endmodule

