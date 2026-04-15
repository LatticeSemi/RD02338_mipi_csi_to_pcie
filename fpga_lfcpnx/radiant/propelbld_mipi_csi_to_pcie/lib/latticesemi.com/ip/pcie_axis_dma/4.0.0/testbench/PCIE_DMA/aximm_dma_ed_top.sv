`timescale 1ps/1ps

module aximm_dma_ed_top  #(
    parameter SIM       = 0,
    parameter NUM_LANES = 4
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
    input       [3:0] 		usr_int_req_i_n_button
);

`include "../dut_params.v"
localparam LOCAL_NUM_USR_INT = (NUM_USR_INT >= 4) ? 4 : NUM_USR_INT;
localparam MEM_DEPTH = ( 'h20000 / (DMA_AXI_WIDTH/8)) ; //128KB divide by (AXI width in Byte)

wire clk_usr_i_125MHz;
wire clk_250;
wire lock_ip;

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
wire [2:0] m0_dma_axi_awid_o;
wire [63:0] m0_dma_axi_awaddr_o;
wire [7:0] m0_dma_axi_awlen_o;
wire [2:0] m0_dma_axi_awsize_o;
wire [1:0] m0_dma_axi_awburst_o;
wire m0_dma_axi_awlock_o;
wire [3:0] m0_dma_axi_awcache_o;
wire [2:0] m0_dma_axi_awprot_o;
wire m0_dma_axi_awvalid_o;
wire m0_dma_axi_awready_i;
wire [DMA_AXI_WIDTH-1:0] m0_dma_axi_wdata_o;
wire [(DMA_AXI_WIDTH/8)-1:0] m0_dma_axi_wstrb_o;
wire m0_dma_axi_wlast_o;
wire m0_dma_axi_wvalid_o;
wire m0_dma_axi_wready_i;
wire [2:0] m0_dma_axi_bid_i;
wire [1:0] m0_dma_axi_bresp_i;
wire m0_dma_axi_bvalid_i;
wire m0_dma_axi_bready_o;
wire [2:0] m0_dma_axi_arid_o;
wire [63:0] m0_dma_axi_araddr_o;
wire [7:0] m0_dma_axi_arlen_o;
wire [2:0] m0_dma_axi_arsize_o;
wire [1:0] m0_dma_axi_arburst_o;
wire m0_dma_axi_arlock_o;
wire [3:0] m0_dma_axi_arcache_o;
wire [2:0] m0_dma_axi_arprot_o;
wire m0_dma_axi_arvalid_o;
wire m0_dma_axi_arready_i;
wire [2:0] m0_dma_axi_rid_i;
wire [DMA_AXI_WIDTH-1:0] m0_dma_axi_rdata_i;
wire [1:0] m0_dma_axi_rresp_i;
wire m0_dma_axi_rlast_i;
wire m0_dma_axi_rvalid_i;
wire m0_dma_axi_rready_o;
wire [3:0] m0_dma_axi_arqos_o;
wire [7:0] m0_dma_axi_aruser_o;

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

   // User Interrupt
   logic [3:0] usr_int_req_i_n;
   logic [NUM_USR_INT-1:0] usr_int_req_i;

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

generate

   if (LOCAL_NUM_USR_INT != 0) begin: USR_INT
      for (genvar i = 0; i < LOCAL_NUM_USR_INT; i++) begin: INT_NUM
         debounce # (
            .SIM   (SIM)
         ) debounce_usr_interrupt_inst
         (
            .clk      (clk_usr_i_125MHz),
            .pb_in_n  (usr_int_req_i_n_button[i]),
            .pb_out   (usr_int_req_i_n[i])
         );

         assign usr_int_req_i[i] = ~usr_int_req_i_n[i];
      end
   end

endgenerate

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

LMMI_app lmmi_app_inst 
(
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

generate

if ((NUM_H2F_CHAN == 1) | (NUM_F2H_CHAN == 1)) begin: AXI_RAM
   dma_local_mem  # (
       .DEVICE_FAMILY ("LFCPNX"),
       .AWID_WIDTH(3),      //ARID_WIDTH & AWID_WIDTH
       .ARID_WIDTH(3),      //ARID_WIDTH & AWID_WIDTH
       .MEM_DEPTH(MEM_DEPTH),  //increase mem_depth for x1 case
       .AXI_WIDTH(DMA_AXI_WIDTH)          //AXI_WIDTH
   )
   application_layer_inst (
       //AW
       .axi_awid_o     (m0_dma_axi_awid_o),
       .axi_awaddr_o   (m0_dma_axi_awaddr_o),
       .axi_awlen_o    (m0_dma_axi_awlen_o),
       .axi_awvalid_o  (m0_dma_axi_awvalid_o),
       .axi_awready_i  (m0_dma_axi_awready_i),
       //W
       .axi_wdata_o    (m0_dma_axi_wdata_o),
       .axi_wstrb_o    (m0_dma_axi_wstrb_o),
       .axi_wlast_o    (m0_dma_axi_wlast_o),
       .axi_wvalid_o   (m0_dma_axi_wvalid_o),
       .axi_wready_i   (m0_dma_axi_wready_i),
       //B
       .axi_bid_i      (m0_dma_axi_bid_i),
       .axi_bresp_i    (m0_dma_axi_bresp_i),
       .axi_bvalid_i   (m0_dma_axi_bvalid_i),
       .axi_bready_o   (m0_dma_axi_bready_o),
       //AR
       .axi_arready_i  (m0_dma_axi_arready_i),
       .axi_arid_o     (m0_dma_axi_arid_o),
       .axi_araddr_o   (m0_dma_axi_araddr_o),
       .axi_arlen_o    (m0_dma_axi_arlen_o),
       .axi_arvalid_o  (m0_dma_axi_arvalid_o),
       //R
       .axi_rid_i      (m0_dma_axi_rid_i),
       .axi_rdata_i    (m0_dma_axi_rdata_i),
       .axi_rresp_i    (m0_dma_axi_rresp_i),
       .axi_rlast_i    (m0_dma_axi_rlast_i),
       .axi_rvalid_i   (m0_dma_axi_rvalid_i),
       .axi_rready_o   (m0_dma_axi_rready_o),
       //KD end	
       .clk           (clk_usr_i_125MHz),
       .rst_n         (rstn_clk2)
   );
end

if ((DMA_BYPASS_EN == 1) & (DMA_BYPASS_IF_TYPE == "AXI_LITE")) begin: AXI4L_DMA_BYP
   dma_local_mem  # (
       .DEVICE_FAMILY ("LFCPNX"),
       .AWID_WIDTH(3),      //ARID_WIDTH & AWID_WIDTH
       .ARID_WIDTH(3),      //ARID_WIDTH & AWID_WIDTH
       .AXI_WIDTH(32),          //AXI_WIDTH
       .CHK_U_ADDR_EN(0), // Dont check because upper can be BAR address
       .CHK_L_ADDR_EN(0) // Dont check becasue alignment requirement is only for DMA RAM.
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
       .AWID_WIDTH(3),      //ARID_WIDTH & AWID_WIDTH
       .ARID_WIDTH(3),      //ARID_WIDTH & AWID_WIDTH
       .AXI_WIDTH(32),          //AXI_WIDTH
       .CHK_U_ADDR_EN(0), // Dont check because upper can be BAR address
       .CHK_L_ADDR_EN(0) // Dont check becasue alignment requirement is only for DMA RAM.
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

endgenerate

// PCIE IP Instantiation
`include "../dut_inst.v"

endmodule

// Other ED logics instantiation
`include "LMMI_app.v"
`include "debounce.v"
`include "dma_flopq.sv"
`include "dma_local_mem.sv"
`include "pll_250.sv"
`include "pll_125.v"
`include "pll_62p5.v"
