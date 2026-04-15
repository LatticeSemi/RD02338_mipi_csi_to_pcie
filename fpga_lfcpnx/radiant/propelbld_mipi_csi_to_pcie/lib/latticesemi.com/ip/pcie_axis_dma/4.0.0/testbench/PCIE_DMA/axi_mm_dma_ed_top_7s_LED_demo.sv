`timescale 1ps/1ps

module aximm_dma_ed_top_7s_LED_demo #(
    parameter SIM       = 0,
    parameter ED_NUM_USR_INT = 4
    //parameter DMA_BYPASS_EN = 1,
    //parameter DMA_BYPASS_IF_TYPE = "AXI_LITE" // "AXI_MM" or "AXI_LITE"
    //parameter WIDTH     = 4,     //  1 : X1 ; 2   : X2 ;   4  : X4 [Lane width]
    //parameter DATAWIDTH = 128    // 32 : X1 ; 64  : X2 ;   128: x4 [Data width]
)
(
    input                   refclkp_i,               
    input                   refclkn_i,
    input       [3:0]   link0_rxp_i,                  // serial line RX+
    input       [3:0]   link0_rxn_i,                  // serial line RX-
    output wire [3:0]   link0_txp_o,                  // serial line TX+
    output wire [3:0]   link0_txn_o,                  // serial line TX-
    input                   perst_n_i,
    input                   usr_rst_n,
    input       [3:0]       refret_i,
    input       [3:0]       rext_i,
    input                   clk_125,
    output                  linkup_done,
    output reg              clock_flag,
    output                  clk_sel,
    output                  pcie_sel,
    output                  pcie_sw1_pd,
    output                  pcie_sw2_pd,
    
    //7 segment LCD output 
    output [6:0] segment_out,
    output [2:0] segment_en,
    output logic LED_1,
    output logic LED_2,
    output logic LED_3,
    output logic LED_4,
    output logic LED_5,
    
    input [ED_NUM_USR_INT-1:0] usr_int_req_i_n_button
);

`include "../dut_params.v"
localparam WIDTH = 4;

reg rstn_meta,rstn_meta2;
reg rstn_clk2;
reg rstn_clk3;
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
wire [255:0] m0_dma_axi_wdata_o;
wire [31:0] m0_dma_axi_wstrb_o;
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
wire [255:0] m0_dma_axi_rdata_i;
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

wire [ED_NUM_USR_INT-1:0] usr_int_req_i_n;
wire [ED_NUM_USR_INT-1:0] usr_int_req_i;
wire clk_7s_62_5MHz;
wire clk_125_gen;

generate

   if (ED_NUM_USR_INT != 0) begin: USR_INT
      for (genvar i = 0; i < ED_NUM_USR_INT; i++) begin: INT_NUM
         debounce # (
            .SIM   (SIM)
         ) debounce_usr_interrupt_inst 
         (
            .clk      (clk_125_gen),
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
    .clk      (clk_125),
    .pb_in_n  (usr_rst_n),
    .pb_out   (rst_n)
);

pll_250_and_7sclk pll_250_and_7sclk_inst (
        .clki_i(clk_125),
        .rstn_i(usr_rst_n),
        .clkop_o(clk_250),
        .clkos_o(clk_125_gen),
        .clkos2_o(clk_7s_62_5MHz),
        .lock_o(lock_ip));

always @(posedge clk_125_gen or negedge rst_n)
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

//generates reset for 7 segement LCD
always @(posedge clk_7s_62_5MHz or negedge rst_n)
begin 
    if (~rst_n) 
    begin 
        rstn_meta2 <= 1'b0;
        rstn_clk3 <= 1'b0;
    end 
    else 
    begin 
        rstn_meta2 <= 1'b1;
        rstn_clk3 <=rstn_meta2;
    end 
end 

always @(posedge usr_lmmi_clk_i)
begin 
    if (~perst_n_i) 
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
assign link0_perst_n_i = perst_n_i & lock_ip;
assign link0_rst_usr_n_i = perst_n_i & lock_ip;
assign clk_usr_o = link0_clk_usr_o;
assign sys_clk_i = (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 2) ? clk_250 : clk_125_gen;
assign clk_usr_div2_i = (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 2) ? clk_125_gen : 1'b0;

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

dma_local_mem  # (
    .DEVICE_FAMILY ("LFCPNX"),
    .AWID_WIDTH(3),      //ARID_WIDTH & AWID_WIDTH
    .ARID_WIDTH(3),      //ARID_WIDTH & AWID_WIDTH
    .AXI_WIDTH(256)          //AXI_WIDTH
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
    .clk           (clk_125_gen),
    .rst_n         (rstn_clk2)
);

generate
if (DMA_BYPASS_EN == 1) begin: DMA_BYP
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
       .clk           (clk_125_gen),
       .rst_n         (rstn_clk2)
   );
end
endgenerate

// PCIE IP Instantiation
`include "../dut_inst.v"

logic [11:0]    targeted_bar1_address;
logic [6:0] segment_DIG0,segment_DIG1,segment_DIG2;

//Detection that bar1 address0 being addressed during Write Address Phase. Any BAR1 MemWr will go through the AXI-L interface
always @(posedge clk_125_gen) begin
    if (~rstn_clk2) begin
        targeted_bar1_address <= 12'b0;
    end else begin
        targeted_bar1_address <= (m0_axil_awready_i & m0_axil_awvalid_o) ? m0_axil_awaddr_o[11:0] : targeted_bar1_address ; 
    end
end 

display_controller display_controller_inst (
     .clk (clk_7s_62_5MHz),
     .rstn (rstn_clk3),
     .segment_DIG0 (segment_DIG0), //If we see glitches, need to clock cross properly but since it is a constant value, should be fine
     .segment_DIG1 (segment_DIG1),
     .segment_DIG2 (segment_DIG2),
     .segment_out  (segment_out),
     .segment_en   (segment_en)
 );


always @(posedge clk_125_gen) begin 
    if (~rstn_clk2) begin 
        segment_DIG0   <= 7'd0;
        segment_DIG1   <= 7'd0;
        segment_DIG2   <= 7'd0;
        LED_1          <= 1'b1; //Active Low so I am turning off the LED at the start upon reset
        LED_2          <= 1'b1; //Active Low so I am turning off the LED at the start upon reset
        LED_3          <= 1'b1; //Active Low so I am turning off the LED at the start upon reset
        LED_4          <= 1'b1; //Active Low so I am turning off the LED at the start upon reset
        LED_5          <= 1'b1; //Active Low so I am turning off the LED at the start upon reset
    end
    else 
    begin 
        case (targeted_bar1_address)
        // Displaying the things written in BAR1 Address 0 in seven segment LCD where [6:0] maps to the 7 segments of the LCD
        12'h0: begin
            if (m0_axil_wvalid_o && m0_axil_wready_i) begin
                segment_DIG0 <= (m0_axil_wstrb_o[0]) ? m0_axil_wdata_o[6:0] : segment_DIG0;
                segment_DIG1 <= (m0_axil_wstrb_o[1]) ? m0_axil_wdata_o[14:8] : segment_DIG1;
                segment_DIG2 <= (m0_axil_wstrb_o[2]) ? m0_axil_wdata_o[22:16] : segment_DIG2;
            end
        end
        //lighting up LED's to show customer that MemWr to BAR1 in DMA Bypass mode is functional
        12'h4: begin
            if (m0_axil_wvalid_o && m0_axil_wready_i) begin
                LED_1 <= (m0_axil_wstrb_o[0]) ? m0_axil_wdata_o[0] : LED_1;
            end
        end
        12'h8: begin
            if (m0_axil_wvalid_o && m0_axil_wready_i) begin
                LED_2 <= (m0_axil_wstrb_o[0]) ? m0_axil_wdata_o[0] : LED_2;
            end
        end
        12'hC: begin
            if (m0_axil_wvalid_o && m0_axil_wready_i) begin
                LED_3 <= (m0_axil_wstrb_o[0]) ? m0_axil_wdata_o[0] : LED_3;
            end
        end
        12'h10: begin
            if (m0_axil_wvalid_o && m0_axil_wready_i) begin
                LED_4 <= (m0_axil_wstrb_o[0]) ? m0_axil_wdata_o[0] : LED_4;
            end
        end
        12'h14: begin
            if (m0_axil_wvalid_o && m0_axil_wready_i) begin
                LED_5 <= (m0_axil_wstrb_o[0]) ? m0_axil_wdata_o[0] : LED_5;
            end
        end
        default: begin
            // Default case if needed
        end
        endcase
    end 
end 

endmodule

`include "debounce.v"
`include "pll_250_and_7sclk.v"
`include "LMMI_app.v"
`include "dma_local_mem.sv"
`include "dma_flopq.sv"
`include "display_controller.v"
