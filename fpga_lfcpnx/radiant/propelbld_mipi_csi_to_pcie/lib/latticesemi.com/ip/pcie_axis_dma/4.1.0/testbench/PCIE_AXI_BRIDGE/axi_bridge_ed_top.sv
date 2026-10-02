`timescale 1ps/1ps

module axi_bridge_ed_top  #(
    parameter SIM       = 0,
    parameter NUM_LANES = 4,
    parameter AXI_BRIDGE_DATA_WIDTH = 32
)
(
    input 			refclkp_i,               
    input 			refclkn_i,
    input       [NUM_LANES-1:0]	link0_rxp_i,  // serial line RX+
    input       [NUM_LANES-1:0]	link0_rxn_i,  // serial line RX-
    output wire [NUM_LANES-1:0]	link0_txp_o,  // serial line TX+
    output wire [NUM_LANES-1:0]	link0_txn_o,  // serial line TX-
    input   			ed_perst_n_i,
    input 			ed_usr_rst_n,
    input  	[NUM_LANES-1:0]	refret_i,
    input       [NUM_LANES-1:0]	rext_i,
    input   			clk_user,
    output			linkup_done,
    output reg 			clock_flag,
    output  	[6:0] 		segment_out,
    output  	[2:0] 		segment_en,
    output  			clk_sel,
    output  			pcie_sel,
    output  			pcie_sw1_pd,
    output  			pcie_sw2_pd,
    input   			uncorr_int_err_req_i_n_button
);

`include "../dut_params.v"

localparam SGDMA_DATA_WIDTH = 64;
localparam MEM_DEPTH_BRIDGE = ('h10000 / (SGDMA_DATA_WIDTH/8)); //64KB divide by (Bypass AXI width in Byte)
localparam UPSIZE_AWUSER_WIDTH = 1;
localparam UPSIZE_ARUSER_WIDTH = 8;
localparam DOWNSIZE_ARUSER_WIDTH = 8;
localparam DOWNSIZE_RUSER_WIDTH = 1;

wire clk_usr_i_125MHz;
wire clk_250;
wire lock_ip;
wire config_done;
reg rstn_meta;
reg rstn_clk2;
wire sys_clk_i;
wire acjtag_mode_i;
wire use_refmux_i;
wire sd_pll_refclk_i;
wire diffioclksel_i;
wire [1:0] clksel_i;
wire link0_aux_clk_i;
wire link0_perst_n_i;
wire link0_rst_usr_n_i;
wire link0_clk_usr_o;
wire link0_pl_link_up_o;
wire link0_dl_link_up_o;
wire link0_tl_link_up_o;
wire link0_user_aux_power_detected_i;
wire [0:0] link0_user_transactions_pending_i;
wire usr_lmmi_clk_i;
reg usr_lmmi_resetn_i;
wire [4:0] usr_lmmi_request_i;
wire usr_lmmi_wr_rdn_i;
wire [31:0] usr_lmmi_wdata_i;
wire [16:0] usr_lmmi_offset_i;
wire [63:0] usr_lmmi_rdata_o;
wire [4:0] usr_lmmi_rdata_valid_o;
wire [4:0] usr_lmmi_ready_o;
wire clk_usr_div2_i;

   // AXI4-MM DMA Bypass (Manager)
   // AXI Address Write Channel
   logic [DMA_AXI_ID_WIDTH-1:0] m0_aximm_awid_o;
   logic [63:0] m0_aximm_awaddr_o;
   logic [7:0] m0_aximm_awlen_o;
   logic [2:0] m0_aximm_awsize_o;
   logic [1:0] m0_aximm_awburst_o;
   logic m0_aximm_awlock_o; // Not supported.
   logic [3:0] m0_aximm_awcache_o; // Not supported.
   logic [0:0] m0_aximm_awuser_o;
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
   logic [DMA_AXI_ID_WIDTH-1:0] m0_aximm_bid_i;
   logic [1:0] m0_aximm_bresp_i;
   logic m0_aximm_bvalid_i;
   logic m0_aximm_bready_o;
   // AXI Read Address Channel
   logic m0_aximm_arready_i;
   logic [DMA_AXI_ID_WIDTH-1:0] m0_aximm_arid_o;
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
   logic [DMA_AXI_ID_WIDTH-1:0] m0_aximm_rid_i;
   logic [31:0] m0_aximm_rdata_i;
   logic [1:0] m0_aximm_rresp_i;
   logic m0_aximm_rlast_i;
   logic m0_aximm_rvalid_i;
   logic m0_aximm_rready_o;

    // AXI4-MM DMA Bypass (Subordinate)
    // AXI Write Address Channel
    logic [DMA_AXI_ID_WIDTH-1:0] s0_aximm_awid_i;
    logic [63:0] s0_aximm_awaddr_i;
    logic [7:0] s0_aximm_awlen_i;
    logic [2:0] s0_aximm_awsize_i;
    logic [1:0] s0_aximm_awburst_i;
    logic s0_aximm_awlock_i; // Not supported.
    logic [3:0] s0_aximm_awcache_i; // Not supported.
    logic [2:0] s0_aximm_awprot_i; // Not supported.
    logic s0_aximm_awvalid_i;
    logic s0_aximm_awready_o;
    // AXI Write Channel
    logic [AXI_BRIDGE_DATA_WIDTH-1:0] s0_aximm_wdata_i;
    logic [(AXI_BRIDGE_DATA_WIDTH/8)-1:0] s0_aximm_wstrb_i;
    logic s0_aximm_wlast_i;
    logic s0_aximm_wvalid_i;
    logic s0_aximm_wready_o;
    // AXI Write Response Channel
    logic [DMA_AXI_ID_WIDTH-1:0] s0_aximm_bid_o;
    logic [1:0] s0_aximm_bresp_o;
    logic s0_aximm_bvalid_o;
    logic s0_aximm_bready_i;
    // AXI Read Address Channel
    logic [DMA_AXI_ID_WIDTH-1:0] s0_aximm_arid_i;
    logic [63:0] s0_aximm_araddr_i;
    logic [7:0] s0_aximm_arlen_i;
    logic [2:0] s0_aximm_arsize_i;
    logic [1:0] s0_aximm_arburst_i;
    logic s0_aximm_arlock_i;
    logic [3:0] s0_aximm_arcache_i;
    logic [2:0] s0_aximm_arprot_i;
    logic [3:0] s0_aximm_arqos_i; // Not supported.
    logic [7:0] s0_aximm_aruser_i; // Not supported.
    logic s0_aximm_arvalid_i;
    logic s0_aximm_arready_o;
    // AXI Read Data Channel
    logic [DMA_AXI_ID_WIDTH-1:0] s0_aximm_rid_o;
    logic [AXI_BRIDGE_DATA_WIDTH-1:0] s0_aximm_rdata_o;
    logic [1:0] s0_aximm_rresp_o;
    logic s0_aximm_rlast_o;
    logic [0:0] s0_aximm_ruser_o;
    logic s0_aximm_rvalid_o;
    logic s0_aximm_rready_i;

   // User Interrupt
   logic [NUM_USR_INT-1:0] usr_int_req_i;
   logic [NUM_USR_INT-1:0] usr_int_ack_o;

   // MM-MM SGDMA : AXI-MM Manager Interface to RAM
   logic [DMA_AXI_ID_WIDTH-1:0]       m_fpga_awid_o;
   logic [63:0]                       m_fpga_awaddr_o;
   logic [7:0]                        m_fpga_awlen_o;
 //logic [2:0]                        m_fpga_awsize_o;
 //logic [1:0]                        m_fpga_awburst_o;
 //logic                              m_fpga_awlock_o;
 //logic [3:0]                        m_fpga_awcache_o;
 //logic [2:0]                        m_fpga_awprot_o;
   logic                              m_fpga_awvalid_o;
   logic                              m_fpga_awready_i;
   logic [SGDMA_DATA_WIDTH-1:0]       m_fpga_wdata_o;
   logic [(SGDMA_DATA_WIDTH/8)-1:0]   m_fpga_wstrb_o;
   logic                              m_fpga_wlast_o;
   logic                              m_fpga_wvalid_o;
   logic                              m_fpga_wready_i;
   logic [DMA_AXI_ID_WIDTH-1:0]       m_fpga_bid_i;
   logic [1:0]                        m_fpga_bresp_i;
   logic                              m_fpga_bvalid_i;
   logic                              m_fpga_bready_o;
   logic [DMA_AXI_ID_WIDTH-1:0]       m_fpga_arid_o;
   logic [63:0]                       m_fpga_araddr_o;
   logic [7:0]                        m_fpga_arlen_o;
 //logic [2:0]                        m_fpga_arsize_o;
 //logic [1:0]                        m_fpga_arburst_o;
 //logic                              m_fpga_arlock_o;
 //logic [3:0]                        m_fpga_arcache_o;
 //logic [2:0]                        m_fpga_arprot_o;
   logic                              m_fpga_arvalid_o;
   logic                              m_fpga_arready_i;
   logic [DMA_AXI_ID_WIDTH-1:0]       m_fpga_rid_i;
   logic [SGDMA_DATA_WIDTH-1:0]       m_fpga_rdata_i;
   logic [1:0]                        m_fpga_rresp_i;
   logic                              m_fpga_rlast_i;
   logic                              m_fpga_rvalid_i;
   logic                              m_fpga_rready_o;

   // DWC interface between SGDMA
   // AXI-MM 64-bit manager (to SGDMA)
   // AW Channel (Write Address)
   logic [DMA_AXI_ID_WIDTH-1:0]        mng_m_axi_awid;
   logic [63:0]                        mng_m_axi_awaddr;
   logic [7:0]                         mng_m_axi_awlen;
   logic [2:0]                         mng_m_axi_awsize;
   logic [1:0]                         mng_m_axi_awburst;
   logic [2:0]                         mng_m_axi_awprot;
   logic                               mng_m_axi_awlock;
   logic [3:0]                         mng_m_axi_awcache;
   logic [UPSIZE_AWUSER_WIDTH-1:0]     mng_m_axi_awuser;
   logic                               mng_m_axi_awvalid;
   logic                               mng_m_axi_awready;
   // W Channel (Write Data)
   logic [63:0]                        mng_m_axi_wdata;
   logic [7:0]                         mng_m_axi_wstrb;
   logic                               mng_m_axi_wlast;
   logic                               mng_m_axi_wvalid;
   logic                               mng_m_axi_wready;
   // B Channel (Write Response)
   logic [DMA_AXI_ID_WIDTH-1:0]        mng_m_axi_bid;
   logic [1:0]                         mng_m_axi_bresp;
   logic                               mng_m_axi_bvalid;
   logic                               mng_m_axi_bready;
   // AR Channel (Read Address)
   logic [DMA_AXI_ID_WIDTH-1:0]        mng_m_axi_arid;
   logic [63:0]                        mng_m_axi_araddr;
   logic [7:0]                         mng_m_axi_arlen;
   logic [2:0]                         mng_m_axi_arsize;
   logic [1:0]                         mng_m_axi_arburst;
   logic [2:0]                         mng_m_axi_arprot;
   logic                               mng_m_axi_arlock;
   logic [3:0]                         mng_m_axi_arcache;
   logic [3:0]                         mng_m_axi_arqos;
   logic [UPSIZE_ARUSER_WIDTH-1:0]     mng_m_axi_aruser;
   logic                               mng_m_axi_arvalid;
   logic                               mng_m_axi_arready;
   // R Channel (Read Data)
   logic [DMA_AXI_ID_WIDTH-1:0]        mng_m_axi_rid;
   logic [63:0]                        mng_m_axi_rdata;
   logic [1:0]                         mng_m_axi_rresp;
   logic                               mng_m_axi_rlast;
   logic                               mng_m_axi_rvalid;
   logic                               mng_m_axi_rready;

   // AXI-MM 64-bit subordinate (from SGDMA)
   // AW Channel (Write Address)
   logic [DMA_AXI_ID_WIDTH-1:0]        sub_s_axi_awid;
   logic [63:0]                        sub_s_axi_awaddr;
   logic [7:0]                         sub_s_axi_awlen;
   logic [2:0]                         sub_s_axi_awsize;
   logic [1:0]                         sub_s_axi_awburst;
   logic [2:0]                         sub_s_axi_awprot;
   logic                               sub_s_axi_awlock;
   logic [3:0]                         sub_s_axi_awcache;
   logic                               sub_s_axi_awvalid;
   logic                               sub_s_axi_awready;
   // W Channel (Write Data)
   logic [63:0]                        sub_s_axi_wdata;
   logic [7:0]                         sub_s_axi_wstrb;
   logic                               sub_s_axi_wlast;
   logic                               sub_s_axi_wvalid;
   logic                               sub_s_axi_wready;
   // B Channel (Write Response)
   logic [DMA_AXI_ID_WIDTH-1:0]        sub_s_axi_bid;
   logic [1:0]                         sub_s_axi_bresp;
   logic                               sub_s_axi_bvalid;
   logic                               sub_s_axi_bready;
   // AR Channel (Read Address)
   logic [DMA_AXI_ID_WIDTH-1:0]        sub_s_axi_arid;
   logic [63:0]                        sub_s_axi_araddr;
   logic [7:0]                         sub_s_axi_arlen;
   logic [2:0]                         sub_s_axi_arsize;
   logic [1:0]                         sub_s_axi_arburst;
   logic [2:0]                         sub_s_axi_arprot;
   logic                               sub_s_axi_arlock;
   logic [3:0]                         sub_s_axi_arcache;
   logic [3:0]                         sub_s_axi_arqos;
   logic [DOWNSIZE_ARUSER_WIDTH-1:0]   sub_s_axi_aruser;
   logic                               sub_s_axi_arvalid;
   logic                               sub_s_axi_arready;
   // R Channel (Read Data)
   logic [DMA_AXI_ID_WIDTH-1:0]        sub_s_axi_rid;
   logic [63:0]                        sub_s_axi_rdata;
   logic [1:0]                         sub_s_axi_rresp;
   logic                               sub_s_axi_rlast;
   logic [DOWNSIZE_RUSER_WIDTH-1:0]    sub_s_axi_ruser;
   logic                               sub_s_axi_rvalid;
   logic                               sub_s_axi_rready;

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

   // AER Interrupt
   logic uncorr_int_err_req_i_n;
   logic uncorr_int_err_req_i;
   logic uncorr_int_err_ack_o;


debounce # (
    . SIM   (SIM)
) debounce_aer_interrupt_inst (
    .clk      (clk_usr_i_125MHz),
    .pb_in_n  (uncorr_int_err_req_i_n_button),
    .pb_out   (uncorr_int_err_req_i_n)
);

assign uncorr_int_err_req_i = ~uncorr_int_err_req_i_n;


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

debounce # (
    . SIM   (SIM)
) debounce_inst 
(
    .clk      (clk_user),
    .pb_in_n  (ed_usr_rst_n),
    .pb_out   (rst_n)
);

generate
   if (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 2) begin: PLL_250
      pll_250 pll_250_inst (
         .clki_i(clk_user),
         .rstn_i(ed_usr_rst_n),
         .clkop_o(clk_250),
         .clkos_o(clk_usr_i_125MHz),
         .lock_o(lock_ip)
      );
   end
   else if (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 1) begin: PLL_125
      pll_125 pll_125_inst (
         .clki_i(clk_user),
         .rstn_i(ed_usr_rst_n),
         .clkop_o(clk_usr_i_125MHz),
         .lock_o(lock_ip)
      );
   end
   else begin: PLL_62P5
      pll_62p5 pll_62p5_inst (
         .clki_i(clk_user),
         .rstn_i(ed_usr_rst_n),
         .clkop_o(clk_usr_i_125MHz),
         .lock_o(lock_ip)
      );
   end
endgenerate

always @(posedge clk_usr_i_125MHz or negedge rst_n)
begin 
    if (~rst_n) 
    begin 
        rstn_meta <= 1'b0;
        rstn_clk2 <= 1'b0;
    end 
    else 
    begin 
        rstn_meta <= 1'b1;
        rstn_clk2 <=rstn_meta;
    end 
end 

always @(posedge usr_lmmi_clk_i)
begin 
    if (~ed_perst_n_i) 
    begin 
        usr_lmmi_resetn_i <= 1'b0;
    end 
    else 
    begin 
        usr_lmmi_resetn_i <= 1'b1;
    end 
end 

assign clk_sel = 1'b1;     
assign pcie_sel = 1'b0;   
assign pcie_sw1_pd = 1'b0;	
assign pcie_sw2_pd = 1'b0;

assign acjtag_mode_i   =  1'b0;
assign use_refmux_i    =  1'b0;
assign sd_pll_refclk_i =  1'b0;
assign diffioclksel_i  =  1'b0;
assign clksel_i        =  2'b0;
assign link0_aux_clk_i = 1'b0;
assign link0_user_aux_power_detected_i = 1'b0;
assign link0_user_transactions_pending_i = 1'b0;
assign link0_perst_n_i = ed_perst_n_i & lock_ip;
assign link0_rst_usr_n_i = ed_perst_n_i & lock_ip;
assign clk_usr_o = link0_clk_usr_o;
assign sys_clk_i = (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 2) ? clk_250 : clk_usr_i_125MHz;
assign clk_usr_div2_i = (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 2) ? clk_usr_i_125MHz : 1'b0;

assign linkup_done = link0_pl_link_up_o & link0_dl_link_up_o & link0_tl_link_up_o;

//Do not remove reset sequence flow trigger in LMMI_app for CPNX, refer [UCSIP-10839].
LMMI_app #(
      .NUM_OF_LANES(LINK0_NUMLANES)
) lmmi_app_inst (
      .clk                   (usr_lmmi_clk_i),
      .rst_n                 (usr_lmmi_resetn_i),
      .usr_lmmi_request_o    (usr_lmmi_request_i),
      .usr_lmmi_wr_rdn_o     (usr_lmmi_wr_rdn_i),
      .usr_lmmi_wdata_o      (usr_lmmi_wdata_i),
      .usr_lmmi_offset_o     (usr_lmmi_offset_i),
      .usr_lmmi_rdata_i      (usr_lmmi_rdata_o),
      .usr_lmmi_rdata_valid_i(usr_lmmi_rdata_valid_o),
      .usr_lmmi_ready_i      (usr_lmmi_ready_o),
      .config_done           (config_done)
);

generate

if ((DMA_BYPASS_EN == 1) & (DMA_BYPASS_IF_TYPE == "AXI_MM") & (FULL_BRIDGE_EN == 1)) begin: AXI_BRIDGE

    mm2mm_sgdma_4pcie # (
        .DEVICE_FAMILY ("LFCPNX"),
        .AXI_ADDR_WIDTH (64),
        .AXI_DATA_WIDTH (SGDMA_DATA_WIDTH),
        .AXI_ID_WIDTH (DMA_AXI_ID_WIDTH)
    ) mm2mm_sgdma_inst (
        .clk_i               (clk_usr_i_125MHz),
        .rst_n_i             (rstn_clk2),

        .m_host_awaddr_o     (sub_s_axi_awaddr),
        .m_host_awid_o       (sub_s_axi_awid),
        .m_host_awlen_o      (sub_s_axi_awlen),
        .m_host_awsize_o     (sub_s_axi_awsize),
        .m_host_awburst_o    (sub_s_axi_awburst),
        .m_host_awlock_o     (sub_s_axi_awlock),
        .m_host_awcache_o    (sub_s_axi_awcache),
        .m_host_awprot_o     (sub_s_axi_awprot),
        .m_host_awvalid_o    (sub_s_axi_awvalid),
        .m_host_awready_i    (sub_s_axi_awready),
        .m_host_wdata_o      (sub_s_axi_wdata),
        .m_host_wstrb_o      (sub_s_axi_wstrb),
        .m_host_wlast_o      (sub_s_axi_wlast),
        .m_host_wvalid_o     (sub_s_axi_wvalid),
        .m_host_wready_i     (sub_s_axi_wready),
        .m_host_bid_i        (sub_s_axi_bid),
        .m_host_bresp_i      (sub_s_axi_bresp),
        .m_host_bvalid_i     (sub_s_axi_bvalid),
        .m_host_bready_o     (sub_s_axi_bready),
        .m_host_arid_o       (sub_s_axi_arid),
        .m_host_araddr_o     (sub_s_axi_araddr),
        .m_host_arlen_o      (sub_s_axi_arlen),
        .m_host_arsize_o     (sub_s_axi_arsize),
        .m_host_arburst_o    (sub_s_axi_arburst),
        .m_host_arlock_o     (sub_s_axi_arlock),
        .m_host_arcache_o    (sub_s_axi_arcache),
        .m_host_arprot_o     (sub_s_axi_arprot),
        .m_host_arvalid_o    (sub_s_axi_arvalid),
        .m_host_arready_i    (sub_s_axi_arready),
        .m_host_rid_i        (sub_s_axi_rid),
        .m_host_rdata_i      (sub_s_axi_rdata),
        .m_host_rresp_i      (sub_s_axi_rresp),
        .m_host_rlast_i      (sub_s_axi_rlast),
        .m_host_rvalid_i     (sub_s_axi_rvalid),
        .m_host_rready_o     (sub_s_axi_rready),

        .m_fpga_awid_o       (m_fpga_awid_o   ),
        .m_fpga_awaddr_o     (m_fpga_awaddr_o ),
        .m_fpga_awlen_o      (m_fpga_awlen_o  ),
//      .m_fpga_awsize_o     (m_fpga_awsize_o ),
//      .m_fpga_awburst_o    (m_fpga_awburst_o),
//      .m_fpga_awlock_o     (m_fpga_awlock_o ),
//      .m_fpga_awcache_o    (m_fpga_awcache_o),
//      .m_fpga_awprot_o     (m_fpga_awprot_o ),
        .m_fpga_awvalid_o    (m_fpga_awvalid_o),
        .m_fpga_awready_i    (m_fpga_awready_i),
        .m_fpga_wdata_o      (m_fpga_wdata_o  ),
        .m_fpga_wstrb_o      (m_fpga_wstrb_o  ),
        .m_fpga_wlast_o      (m_fpga_wlast_o  ),
        .m_fpga_wvalid_o     (m_fpga_wvalid_o ),
        .m_fpga_wready_i     (m_fpga_wready_i ),
        .m_fpga_bid_i        (m_fpga_bid_i    ),
        .m_fpga_bresp_i      (m_fpga_bresp_i  ),
        .m_fpga_bvalid_i     (m_fpga_bvalid_i ),
        .m_fpga_bready_o     (m_fpga_bready_o ),
        .m_fpga_arid_o       (m_fpga_arid_o   ),
        .m_fpga_araddr_o     (m_fpga_araddr_o ),
        .m_fpga_arlen_o      (m_fpga_arlen_o  ),
//      .m_fpga_arsize_o     (m_fpga_arsize_o ),
//      .m_fpga_arburst_o    (m_fpga_arburst_o),
//      .m_fpga_arlock_o     (m_fpga_arlock_o ),
//      .m_fpga_arcache_o    (m_fpga_arcache_o),
//      .m_fpga_arprot_o     (m_fpga_arprot_o ),
        .m_fpga_arvalid_o    (m_fpga_arvalid_o),
        .m_fpga_arready_i    (m_fpga_arready_i),
        .m_fpga_rid_i        (m_fpga_rid_i    ),
        .m_fpga_rdata_i      (m_fpga_rdata_i  ),
        .m_fpga_rresp_i      (m_fpga_rresp_i  ),
        .m_fpga_rlast_i      (m_fpga_rlast_i  ),
        .m_fpga_rvalid_i     (m_fpga_rvalid_i ),
        .m_fpga_rready_o     (m_fpga_rready_o ),

        .s_csr_awid_i        (mng_m_axi_awid),
        .s_csr_awaddr_i      (mng_m_axi_awaddr),
        .s_csr_awlen_i       (mng_m_axi_awlen),
        .s_csr_awsize_i      (mng_m_axi_awsize),
        .s_csr_awburst_i     (mng_m_axi_awburst),
        .s_csr_awlock_i      (mng_m_axi_awlock),
        .s_csr_awcache_i     (mng_m_axi_awcache),
        .s_csr_awprot_i      (mng_m_axi_awprot),
        .s_csr_awvalid_i     (mng_m_axi_awvalid),
        .s_csr_awready_o     (mng_m_axi_awready),
        .s_csr_wdata_i       (mng_m_axi_wdata),
        .s_csr_wstrb_i       (mng_m_axi_wstrb),
        .s_csr_wlast_i       (mng_m_axi_wlast),
        .s_csr_wvalid_i      (mng_m_axi_wvalid),
        .s_csr_wready_o      (mng_m_axi_wready),
        .s_csr_bid_o         (mng_m_axi_bid),
        .s_csr_bresp_o       (mng_m_axi_bresp),
        .s_csr_bvalid_o      (mng_m_axi_bvalid),
        .s_csr_bready_i      (mng_m_axi_bready),
        .s_csr_arid_i        (mng_m_axi_arid),
        .s_csr_araddr_i      (mng_m_axi_araddr),
        .s_csr_arlen_i       (mng_m_axi_arlen),
        .s_csr_arsize_i      (mng_m_axi_arsize),
        .s_csr_arburst_i     (mng_m_axi_arburst),
        .s_csr_arlock_i      (mng_m_axi_arlock),
        .s_csr_arcache_i     (mng_m_axi_arcache),
        .s_csr_arprot_i      (mng_m_axi_arprot),
        .s_csr_arvalid_i     (mng_m_axi_arvalid),
        .s_csr_arready_o     (mng_m_axi_arready),
        .s_csr_rid_o         (mng_m_axi_rid),
        .s_csr_rdata_o       (mng_m_axi_rdata),
        .s_csr_rresp_o       (mng_m_axi_rresp),
        .s_csr_rlast_o       (mng_m_axi_rlast),
        .s_csr_rvalid_o      (mng_m_axi_rvalid),
        .s_csr_rready_i      (mng_m_axi_rready),

        .usr_int_req_o       (usr_int_req_i[1:0]),
        .usr_int_ack_i       (usr_int_ack_o[1:0])
    );

    axi_dwc_top #(
        .ID_WIDTH  (DMA_AXI_ID_WIDTH),
        .UPSIZE_AWUSER_WIDTH   (UPSIZE_AWUSER_WIDTH),
        .UPSIZE_ARUSER_WIDTH   (UPSIZE_ARUSER_WIDTH),
        .DOWNSIZE_ARUSER_WIDTH (DOWNSIZE_ARUSER_WIDTH),
        .DOWNSIZE_RUSER_WIDTH  (DOWNSIZE_RUSER_WIDTH)
    ) axi_dwc_inst (
        .clk_i                 (clk_usr_i_125MHz),
        .rst_n_i               (rstn_clk2),
        // AXI-MM 32-bit subordinate (from AXI Bridge)
        .mng_s_axi_awid        (m0_aximm_awid_o     ),
        .mng_s_axi_awaddr      (m0_aximm_awaddr_o   ),
        .mng_s_axi_awlen       (m0_aximm_awlen_o    ),
        .mng_s_axi_awsize      (m0_aximm_awsize_o   ),
        .mng_s_axi_awburst     (m0_aximm_awburst_o  ),
        .mng_s_axi_awprot      (m0_aximm_awprot_o   ),
        .mng_s_axi_awlock      (m0_aximm_awlock_o   ),
        .mng_s_axi_awcache     (m0_aximm_awcache_o  ),
        .mng_s_axi_awuser      (m0_aximm_awuser_o   ),
        .mng_s_axi_awvalid     (m0_aximm_awvalid_o  ),
        .mng_s_axi_awready     (m0_aximm_awready_i  ),
        .mng_s_axi_wdata       (m0_aximm_wdata_o    ),
        .mng_s_axi_wstrb       (m0_aximm_wstrb_o    ),
        .mng_s_axi_wlast       (m0_aximm_wlast_o    ),
        .mng_s_axi_wvalid      (m0_aximm_wvalid_o   ),
        .mng_s_axi_wready      (m0_aximm_wready_i   ),
        .mng_s_axi_bid         (m0_aximm_bid_i),
        .mng_s_axi_bresp       (m0_aximm_bresp_i    ),
        .mng_s_axi_bvalid      (m0_aximm_bvalid_i   ),
        .mng_s_axi_bready      (m0_aximm_bready_o   ),
        .mng_s_axi_arid        (m0_aximm_arid_o),
        .mng_s_axi_araddr      (m0_aximm_araddr_o   ),
        .mng_s_axi_arlen       (m0_aximm_arlen_o    ),
        .mng_s_axi_arsize      (m0_aximm_arsize_o   ),
        .mng_s_axi_arburst     (m0_aximm_arburst_o  ),
        .mng_s_axi_arprot      (m0_aximm_arprot_o   ),
        .mng_s_axi_arlock      (m0_aximm_arlock_o   ),
        .mng_s_axi_arcache     (m0_aximm_arcache_o  ),
        .mng_s_axi_arqos       (m0_aximm_arqos_o    ),
        .mng_s_axi_aruser      (m0_aximm_aruser_o   ),
        .mng_s_axi_arvalid     (m0_aximm_arvalid_o  ),
        .mng_s_axi_arready     (m0_aximm_arready_i  ),
        .mng_s_axi_rid         (m0_aximm_rid_i),
        .mng_s_axi_rdata       (m0_aximm_rdata_i    ),
        .mng_s_axi_rresp       (m0_aximm_rresp_i    ),
        .mng_s_axi_rlast       (m0_aximm_rlast_i    ),
        .mng_s_axi_rvalid      (m0_aximm_rvalid_i   ),
        .mng_s_axi_rready      (m0_aximm_rready_o   ),
        // AXI-MM 64-bit manager (to SGDMA)
        .mng_m_axi_awid        (mng_m_axi_awid     ),
        .mng_m_axi_awaddr      (mng_m_axi_awaddr   ),
        .mng_m_axi_awlen       (mng_m_axi_awlen    ),
        .mng_m_axi_awsize      (mng_m_axi_awsize   ),
        .mng_m_axi_awburst     (mng_m_axi_awburst  ),
        .mng_m_axi_awprot      (mng_m_axi_awprot   ),
        .mng_m_axi_awlock      (mng_m_axi_awlock   ),
        .mng_m_axi_awcache     (mng_m_axi_awcache  ),
        .mng_m_axi_awuser      (mng_m_axi_awuser   ),
        .mng_m_axi_awvalid     (mng_m_axi_awvalid  ),
        .mng_m_axi_awready     (mng_m_axi_awready  ),
        .mng_m_axi_wdata       (mng_m_axi_wdata    ),
        .mng_m_axi_wstrb       (mng_m_axi_wstrb    ),
        .mng_m_axi_wlast       (mng_m_axi_wlast    ),
        .mng_m_axi_wvalid      (mng_m_axi_wvalid   ),
        .mng_m_axi_wready      (mng_m_axi_wready   ),
        .mng_m_axi_bid         (mng_m_axi_bid      ),
        .mng_m_axi_bresp       (mng_m_axi_bresp    ),
        .mng_m_axi_bvalid      (mng_m_axi_bvalid   ),
        .mng_m_axi_bready      (mng_m_axi_bready   ),
        .mng_m_axi_arid        (mng_m_axi_arid     ),
        .mng_m_axi_araddr      (mng_m_axi_araddr   ),
        .mng_m_axi_arlen       (mng_m_axi_arlen    ),
        .mng_m_axi_arsize      (mng_m_axi_arsize   ),
        .mng_m_axi_arburst     (mng_m_axi_arburst  ),
        .mng_m_axi_arprot      (mng_m_axi_arprot   ),
        .mng_m_axi_arlock      (mng_m_axi_arlock   ),
        .mng_m_axi_arcache     (mng_m_axi_arcache  ),
        .mng_m_axi_arqos       (mng_m_axi_arqos    ),
        .mng_m_axi_aruser      (mng_m_axi_aruser   ),
        .mng_m_axi_arvalid     (mng_m_axi_arvalid  ),
        .mng_m_axi_arready     (mng_m_axi_arready  ),
        .mng_m_axi_rid         (mng_m_axi_rid      ),
        .mng_m_axi_rdata       (mng_m_axi_rdata    ),
        .mng_m_axi_rresp       (mng_m_axi_rresp    ),
        .mng_m_axi_rlast       (mng_m_axi_rlast    ),
        .mng_m_axi_rvalid      (mng_m_axi_rvalid   ),
        .mng_m_axi_rready      (mng_m_axi_rready   ),
        // AXI-MM 64-bit subordinate (from SGDMA)
        .sub_s_axi_awid        (sub_s_axi_awid     ),
        .sub_s_axi_awaddr      (sub_s_axi_awaddr   ),
        .sub_s_axi_awlen       (sub_s_axi_awlen    ),
        .sub_s_axi_awsize      (sub_s_axi_awsize   ),
        .sub_s_axi_awburst     (sub_s_axi_awburst  ),
        .sub_s_axi_awprot      (sub_s_axi_awprot   ),
        .sub_s_axi_awlock      (sub_s_axi_awlock   ),
        .sub_s_axi_awcache     (sub_s_axi_awcache  ),
        .sub_s_axi_awvalid     (sub_s_axi_awvalid  ),
        .sub_s_axi_awready     (sub_s_axi_awready  ),
        .sub_s_axi_wdata       (sub_s_axi_wdata    ),
        .sub_s_axi_wstrb       (sub_s_axi_wstrb    ),
        .sub_s_axi_wlast       (sub_s_axi_wlast    ),
        .sub_s_axi_wvalid      (sub_s_axi_wvalid   ),
        .sub_s_axi_wready      (sub_s_axi_wready   ),
        .sub_s_axi_bid         (sub_s_axi_bid      ),
        .sub_s_axi_bresp       (sub_s_axi_bresp    ),
        .sub_s_axi_bvalid      (sub_s_axi_bvalid   ),
        .sub_s_axi_bready      (sub_s_axi_bready   ),
        .sub_s_axi_arid        (sub_s_axi_arid     ),
        .sub_s_axi_araddr      (sub_s_axi_araddr   ),
        .sub_s_axi_arlen       (sub_s_axi_arlen    ),
        .sub_s_axi_arsize      (sub_s_axi_arsize   ),
        .sub_s_axi_arburst     (sub_s_axi_arburst  ),
        .sub_s_axi_arprot      (sub_s_axi_arprot   ),
        .sub_s_axi_arlock      (sub_s_axi_arlock   ),
        .sub_s_axi_arcache     (sub_s_axi_arcache  ),
        .sub_s_axi_arqos       ('0),
        .sub_s_axi_aruser      ('0),
        .sub_s_axi_arvalid     (sub_s_axi_arvalid  ),
        .sub_s_axi_arready     (sub_s_axi_arready  ),
        .sub_s_axi_rid         (sub_s_axi_rid      ),
        .sub_s_axi_rdata       (sub_s_axi_rdata    ),
        .sub_s_axi_rresp       (sub_s_axi_rresp    ),
        .sub_s_axi_rlast       (sub_s_axi_rlast    ),
        .sub_s_axi_ruser       (sub_s_axi_ruser    ),
        .sub_s_axi_rvalid      (sub_s_axi_rvalid   ),
        .sub_s_axi_rready      (sub_s_axi_rready   ),
        // AXI-MM 32-bit manager (to AXI Bridge)
        .sub_m_axi_awid        (s0_aximm_awid_i     ),
        .sub_m_axi_awaddr      (s0_aximm_awaddr_i   ),
        .sub_m_axi_awlen       (s0_aximm_awlen_i    ),
        .sub_m_axi_awsize      (s0_aximm_awsize_i   ),
        .sub_m_axi_awburst     (s0_aximm_awburst_i  ),
        .sub_m_axi_awprot      (s0_aximm_awprot_i   ),
        .sub_m_axi_awlock      (s0_aximm_awlock_i   ),
        .sub_m_axi_awcache     (s0_aximm_awcache_i  ),
        .sub_m_axi_awvalid     (s0_aximm_awvalid_i  ),
        .sub_m_axi_awready     (s0_aximm_awready_o  ),
        .sub_m_axi_wdata       (s0_aximm_wdata_i    ),
        .sub_m_axi_wstrb       (s0_aximm_wstrb_i    ),
        .sub_m_axi_wlast       (s0_aximm_wlast_i    ),
        .sub_m_axi_wvalid      (s0_aximm_wvalid_i   ),
        .sub_m_axi_wready      (s0_aximm_wready_o   ),
        .sub_m_axi_bid         (s0_aximm_bid_o      ),
        .sub_m_axi_bresp       (s0_aximm_bresp_o    ),
        .sub_m_axi_bvalid      (s0_aximm_bvalid_o   ),
        .sub_m_axi_bready      (s0_aximm_bready_i   ),
        .sub_m_axi_arid        (s0_aximm_arid_i     ),
        .sub_m_axi_araddr      (s0_aximm_araddr_i   ),
        .sub_m_axi_arlen       (s0_aximm_arlen_i    ),
        .sub_m_axi_arsize      (s0_aximm_arsize_i   ),
        .sub_m_axi_arburst     (s0_aximm_arburst_i  ),
        .sub_m_axi_arprot      (s0_aximm_arprot_i   ),
        .sub_m_axi_arlock      (s0_aximm_arlock_i   ),
        .sub_m_axi_arcache     (s0_aximm_arcache_i  ),
        .sub_m_axi_arqos       (s0_aximm_arqos_i    ),
        .sub_m_axi_aruser      (s0_aximm_aruser_i   ),
        .sub_m_axi_arvalid     (s0_aximm_arvalid_i  ),
        .sub_m_axi_arready     (s0_aximm_arready_o  ),
        .sub_m_axi_rid         (s0_aximm_rid_o      ),
        .sub_m_axi_rdata       (s0_aximm_rdata_o    ),
        .sub_m_axi_rresp       (s0_aximm_rresp_o    ),
        .sub_m_axi_rlast       (s0_aximm_rlast_o    ),
        .sub_m_axi_ruser       (s0_aximm_ruser_o    ),
        .sub_m_axi_rvalid      (s0_aximm_rvalid_o   ),
        .sub_m_axi_rready      (s0_aximm_rready_i   )
    );

   dma_local_mem  # (
       .DEVICE_FAMILY ("LFCPNX"),
       .AWID_WIDTH(DMA_AXI_ID_WIDTH),      //ARID_WIDTH & AWID_WIDTH
       .ARID_WIDTH(DMA_AXI_ID_WIDTH),      //ARID_WIDTH & AWID_WIDTH
       .AXI_WIDTH(SGDMA_DATA_WIDTH),   //AXI_WIDTH
       .MEM_DEPTH(MEM_DEPTH_BRIDGE),
       .CHK_U_ADDR_EN(0), // Dont check because upper can be BAR address
       .CHK_L_ADDR_EN(0) // Dont check becasue alignment requirement is only for DMA RAM.
   )
    mm2mm_sgdma_ram_inst (
       //AW
       .axi_awid_o     (m_fpga_awid_o),
       .axi_awaddr_o   (m_fpga_awaddr_o),
       .axi_awlen_o    (m_fpga_awlen_o),
       .axi_awvalid_o  (m_fpga_awvalid_o),
       .axi_awready_i  (m_fpga_awready_i),
       //W
       .axi_wdata_o    (m_fpga_wdata_o),
       .axi_wstrb_o    (m_fpga_wstrb_o),
       .axi_wlast_o    (m_fpga_wlast_o),
       .axi_wvalid_o   (m_fpga_wvalid_o),
       .axi_wready_i   (m_fpga_wready_i),
       //B
       .axi_bid_i      (m_fpga_bid_i),
       .axi_bresp_i    (m_fpga_bresp_i),
       .axi_bvalid_i   (m_fpga_bvalid_i),
       .axi_bready_o   (m_fpga_bready_o),
       //AR
       .axi_arready_i  (m_fpga_arready_i),
       .axi_arid_o     (m_fpga_arid_o),
       .axi_araddr_o   (m_fpga_araddr_o),
       .axi_arlen_o    (m_fpga_arlen_o),
       .axi_arvalid_o  (m_fpga_arvalid_o),
       //R
       .axi_rid_i      (m_fpga_rid_i),
       .axi_rdata_i    (m_fpga_rdata_i),
       .axi_rresp_i    (m_fpga_rresp_i),
       .axi_rlast_i    (m_fpga_rlast_i),
       .axi_rvalid_i   (m_fpga_rvalid_i),
       .axi_rready_o   (m_fpga_rready_o),
       //KD end    
       .clk           (clk_usr_i_125MHz),
       .rst_n         (rstn_clk2)
   );
end

endgenerate

// PCIE IP Instantiation
`include "../dut_inst.v"

endmodule

// MM_MM_SGDMA Instantiation
`include "mm2mm_sgdma_4pcie.sv"

// DWC Instantiation
`include "../AXI_DWC/axi_dwc_top.sv"
`include "../AXI_DWC/axi_ar_downsize.sv"
`include "../AXI_DWC/axi_ar_upsize.sv"
`include "../AXI_DWC/axi_aw_downsize.sv"
`include "../AXI_DWC/axi_aw_upsize.sv"
`include "../AXI_DWC/axi_bresp_downsize.sv"
`include "../AXI_DWC/axi_bresp_upsize.sv"
`include "../AXI_DWC/axi_read_downsize.sv"
`include "../AXI_DWC/axi_read_upsize.sv"
`include "../AXI_DWC/axi_write_downsize.sv"
`include "../AXI_DWC/axi_write_upsize.sv"
`include "../AXI_DWC/axi_dwc.sv"

// Other ED logics instantiation
`include "../PCIE_DMA/LMMI_app.v"
`include "../PCIE_DMA/debounce.v"
`include "../PCIE_DMA/dma_flopq.sv"
`include "../PCIE_DMA/dma_local_mem.sv"
`include "../PCIE_DMA/pll_250.sv"
`include "../PCIE_DMA/pll_125.v"
`include "../PCIE_DMA/pll_62p5.v"
