// -------------------------------------------------------------------------
//
//  PROJECT: PCI Express Core
//  COMPANY: Northwest Logic, Inc.
//
// ------------------------- CONFIDENTIAL ----------------------------------
//
//                 Copyright 2014 by Northwest Logic, Inc.
//
//  All rights reserved.  No part of this source code may be reproduced or
//  transmitted in any form or by any means, electronic or mechanical,
//  including photocopying, recording, or any information storage and
//  retrieval system, without permission in writing from Northwest Logic, Inc.
//
//  Further, no use of this source code is permitted in any form or means
//  without a valid, written license agreement with Northwest Logic, Inc.
//
//                         Northwest Logic, Inc.
//                  1100 NW Compton Drive, Suite 100
//                      Beaverton, OR 97006, USA
//
//                       Ph.  +1 503 533 5800
//                       Fax. +1 503 533 5900
//                          www.nwlogic.com
//
// -------------------------------------------------------------------------

`timescale 1ps / 1ps



// -----------------------
// -- Module Definition --
// -----------------------

module tb_top #(

    // DMA Design parameters
    //   Minimum number of bytes in a descriptor is 4 bytes : Design Limitation.
    //   Number of Descriptor should be power of 2 bytes, i.e 4,8,16,32,64,128,etc : Design Limitation
    parameter DMA_TESTCASE_TYPE       = 3'b001,     // 3'b000 : DMA Write - Read ; 3'b001 : DMA Write ; 3'b010 : DMA Read ;
                                                    // 3'b101 : DMA Multiple Write Multiple Read with different data ; 3'b110 : DMA Multiple Write Multiple Read with same data
    parameter DMA_NUM_OF_DESCRIPTORS  = 255,        // Number of Descriptors : Maximum Descriptors possible = 255
    parameter DMA_BYTES_IN_DESCRIPTOR = 512,        // Number of bytes in one descriptor .
    parameter DMA_PATTERN             = 32'h0000_0001,// 32'h0000_0001 : Incremental Pattern / 32'h0000_0000 : Fixed Pattern (32'h2244_6688)
    parameter NUM_OP                  = 3,          // Number of times read and write operation needed to be performed 
    parameter DMA_FIXED_DATA          = 32'h1235_0000,

    // NON DMA Design parameters
    parameter NON_DMA_TESTCASE_TYPE  = 4'd2,        //0 -SINGLE BAR MEM_WRITE ; 1 -SINGLE BAR MEM_READ ; 2 -SINGLE BAR MEM_WRITE AND MEM_READ ;
                                                    //3 -TWO BAR CONCURRENT MEM_WRITE AND READ  ; 4 -CONFIGURE WRITE(0x0c register); 5 -CONFIGURE READ(0x0c register);
                                                    //6 -Single bar Multiple Write & Multiple Read transactions to incremental address with incremental data; 7 -Two bar Multiple Write & Multiple Read transactions to incremental address with incremental data
                                                    //8 -Single bar Multiple Write & Multiple Read transactions to same address with similar data; 9 -Two bar Multiple Write & Multiple Read transactions to same address with similar data
    parameter NON_DMA_SINGLE_BAR_SEL = 1'b0,        //This can be selected only when single bar operations are performed(ie;NON_DMA_TESTCASE_TYPE = 0,1,2,5 or 7)
                                                    //0-represents BAR0 , 1-represents BAR1.     										   
    parameter NON_DMA_SERIES_PATTERN = 1'b1,        //Writing data pattern : 1- For incremental pattern , 0- for fixed pattern
    parameter NON_DMA_FIXED_DATA     = 32'h12345678,//This can be altered but performs only when fixed pattern is selected(ie;NON_DMA_SERIES_PATTERN= 1'b0)
    parameter NON_DMA_NUM_DWORD      = 128,         //Number of DWORDS to be written/read to/from each packet 
                                                    //For TLP interface, "NON_DMA_NUM_DWORD" must be taken in multiples as follows :-      [Reason :- 1 byte is transmitted through each lane]
                                                    //(For x1:- 1,2,3,...; For x2:- 2,4,6,8,...; For x4:-4,8,12,....)
                                                    //For AHBL/AXI interface, "NON_DMA_NUM_DWORD" must be taken in multiples as follows :- [Reason :- 2 bytes are transmitted through each lane]
                                                    //(For x1:- 2,4,6,...; For x2:- 4,8,12,....; For x4:-8,16,24,...)
                                                    //Note that "NON_DMA_NUM_DWORD"	must be less than or equal to "MAX_PAYLOAD_SUPPORTED/4" selected in PCIe GUI										
    parameter NON_DMA_NUM_PACKETS    = 4,           //Total number of packets consisted in each BAR
                                                    //[NON_DMA_NUM_DWORD*NON_DMA_NUM_PACKETS <= 4096 DWORDS (ie;NON_DMA_TESTCASE_TYPE = 0,1,2 or 3)]
    parameter NUM_WRITES             = 4,           //Number of write transactions (ie;NON_DMA_TESTCASE_TYPE = 6,7,8 or 9)
                                                    //[NON_DMA_NUM_DWORD*NON_DMA_NUM_PACKETS*NUM_WRITES <= 4096 DWORDS(ie;NON_DMA_TESTCASE_TYPE = 6,7,8 or 9)]
    parameter NUM_READS              = 4            //Number of read  transactions (ie;NON_DMA_TESTCASE_TYPE = 6,7,8 or 9)
                                                    //Note that NUM_READS must be less than or equal to NUM_WRITES(ie; NUM_READS <=NUM_WRITES)
                                                    //If NUM_READS is more than NUM_WRITES, then default data is read (ie; Incremental data in RAM)
);

`include "../dut_params.v"

   // ----------------
   // -- Parameters --
   // ----------------
   `define DMA_ENABLE_OR_NOT  0

   // NOTE: Only values defined using parameter are expected to be changed by the user;
   // Do not alter values defined using localparam

    // Values from DUT_PARAMS
    // Values based on PCIe gui

   localparam   MAX_PAYLOAD_SUPPORTED = (LINK0_FTL_PCIE_DEV_CAP_MAX_PAYLOAD_SIZE_SUPPORTED == "512_BYTES")? 512 : ((LINK0_FTL_PCIE_DEV_CAP_MAX_PAYLOAD_SIZE_SUPPORTED == "256_BYTES") ? 256 : 128);
   localparam   DMA_MAX_SUPPORTED_SIZE = (DMA_BYTES_IN_DESCRIPTOR >= MAX_PAYLOAD_SUPPORTED) ? MAX_PAYLOAD_SUPPORTED : DMA_BYTES_IN_DESCRIPTOR;
   localparam   NON_DMA_MAX_SUPPORTED_SIZE = ((NON_DMA_NUM_DWORD) >= MAX_PAYLOAD_SUPPORTED/4) ? MAX_PAYLOAD_SUPPORTED/4 : (NON_DMA_NUM_DWORD);

   localparam PCIE_CSR_BASE_ADDR = {PCIE_CSR_BASEADR,19'b0};
   localparam DATA_WIDTH         = (USR_MST_IF_TYPE=="TLP") ? ((PCIE_BIFUR_SEL == 5)? 128 : ((PCIE_BIFUR_SEL == 1) ? 64 : ((PCIE_BIFUR_SEL == 2) ? 32 : 32 ))):
                                   ((USR_MST_IF_TYPE=="AHB_LITE"||"AXI_STREAM")? ((PCIE_BIFUR_SEL == 5)? 256 : ((PCIE_BIFUR_SEL == 1) ? 128 : ((PCIE_BIFUR_SEL == 2) ? 64 : 32 ))) : 32);
   localparam CSR_ADDRESS        = PCIE_CSR_BASEADR ;
   localparam NO_LANES           = (PCIE_BIFUR_SEL == 5) ? 4 : ((PCIE_BIFUR_SEL == 1) ? 2 : ((PCIE_BIFUR_SEL == 2) ? 1 : 0 ));  // Represents the Number of Lanes
   localparam GENERATION         = LINK0_FTL_INITIAL_TARGET_LINK_SPEED; // Generation PCIe
   localparam DATA_INTERFACE     = USR_MST_IF_TYPE;

   parameter   FINISH_STOP_N            = 0;    // On errors and simulation completion, $stop if FINISH_STOP_N==0 else $finish
   parameter   STOP_ON_ERR              = 0;    // Set to 1 to $stop simulation on errors (for tests with optional $stop code);
                                                // Note: During NWL command line regressions, $stop is automatically elevated to $finish by the regression flow for those simulators for which this is necessary
   parameter   DMA_BYPASS_7S_AND_LED_DEMO = 0; // Enable if you'd like to run hardware demo with 7-segment LCD and LED capabilities to demonstrate value written to BAR1 using DMA bypass mode
                                               // Set DMA_BYPASS_7S_AND_LED_DEMO param to enable the MSI-X test flow for soft bridge

   parameter   ACTIVITY_WDT_TIMEOUT    = 400_000;  // Simulation will halt after this many 100 MHz clocks with no high level transaction activity (default 2.0 mS) (0=disable)
   parameter   ABSOLUTE_WDT_TIMEOUT    = 100_000;  // Simulation will halt after this many microseconds (default 100 ms) (0=disable)
   localparam  NUM_LINKS_TB            = 1;

   // NUM_LANES indicates the number of PCI Express lanes supported by the core
   localparam  NUM_LANES               = NO_LANES;

   // BFM_NUM_LANES indicates the number of PCI Express lanes on the BFM
   //  if not specified, assume it is equal to NUM_LANES
   localparam  BFM_NUM_LANES           = NO_LANES;

   localparam  BFM_RCB_BYTES           = NO_LANES*128;

   localparam  MAX_NUM_LANES           = (BFM_NUM_LANES > NUM_LANES) ? BFM_NUM_LANES : NUM_LANES;

   // The following parameter controls the lanes that will be modelled as
   //   detecting/not detecting receivers; to cause a lane not to detect
   //   a receiver, set (1) the corresponding bit in PIPE_PHY_LANE_MASK;
   //     For example: PHY_LANE_MASK == 16'h800C : Lanes[15, 3:2] will
   //       emulate being disconnected
   //   Note: The serial transmit lines of lanes that are modelled as
   //   disconnected will output High-Z
   parameter   BFM_PHY_LANE_MASK       = 16'h0000;

   parameter   HALF_PERIOD_5G          = 100;  // 5 GHz
   parameter   HALF_PERIOD_2G5         = 200;  // 2.5 GHz

   parameter   BFM_MEM_SIZE_BITS       = 22;

   // The following parameters when == 1 emulate the inability for PHY to properly detect the active condition at 5G and 8G data rates; the active condition is only detected when an EIE low frequency pattern is on the serial lines
   parameter   RX_IDLE_ACTIVE_8G_ONLY_EIE  = 0; // Set to 1 to cause rx_elec_idle to be 0 at 8G speed only when EIEOS == {8{8'h00, 8'ff}} is received;                                            0 == Use emulated analog comparator
   parameter   RX_IDLE_ACTIVE_5G_ONLY_EIE  = 0; // Set to 1 to cause rx_elec_idle to be 0 at 5G speed only when EIE == symbols are received back-back; alternating pattern of 5 zeros and 5 ones; 0 == Use emulated analog comparator

   // Message levels
   parameter   MSGS_STD_OUT_ON         = 1;    // Set to enable logging TLP information to standard output
   parameter   MSGS_FILE_ON            = 1;    // Set to enable logging TLP information to file output
   parameter   VCD_DUMP                = 0;
   parameter   VCD_DEPTH               = 0;
   parameter   [63:0]   VCD_ON_TIME    = 0;
   parameter   [63:0]   VCD_OFF_TIME   = 0;

   // parameters for board delay simulation
   parameter   TPD_CLK_CTRLR_MEM       = 1900;               // total delay of clock from controller clock net to SDRAM
   parameter   TPD_CMD_CTRLR_MEM       = 1900;               // total delay of address/command signals from controller clock net to SDRAM
   parameter   TPD_DATA_CTRLR_MEM      = 1900;               // total delay of dq/dqs from Controller to SDRAM devices

   parameter   TPD_DATA_MEM_CTRLR      = TPD_DATA_CTRLR_MEM; // total delay of dq/dqs from SDRAM devices to Controller
   parameter   TPD_RD_EN_LOOPBACK      = TPD_DATA_CTRLR_MEM + TPD_DATA_MEM_CTRLR;

   parameter   RESET_INACTIVE_TIME       = 1;
   parameter   RESET_ACTIVE_TIME       = 1000000;

   parameter   SIM_EL_IDLE_TYPE        = 2'b10; // Electrical Idle Emulation: 11 == 1'b1 : Common Mode 1
                                                //                            10 == 1'b0 : Common Mode 0
                                                //                            01 == 1'bx : Undefined
                                                //                            00 == 1'bz : Tristate

   parameter   DUT_LANE_REVERSE        = 0;    // Default to DUT not reversed; Non-zero to reverse DUT Lanes
   parameter   BFM_LANE_REVERSE        = 0;    // Default to BFM not reversed; Non-zero to reverse BFM Lanes
   parameter   BFM_EMULATE_WIDTH       = 0;
   parameter   DUT_TX_INVERT           = 0;
   parameter   BFM_TX_INVERT           = 0;

   // Per PCIe Spec, the max skew that can be received accross the lanes at receiver is 8nS @ 5G
   //   and 20 nS @ 2.5G; this includes differences in length of SKP Ordered sets; select skew to
   //   apply accross lanes; skew is evenly distributed with Lane 0 having no skew and highest lane
   //   having MAX_LANE_SKEW
   parameter   MAX_LANE_SKEW           = 4000;  // To DUT
   parameter   MAX_LANE_SKEW_TO_BFM    = 4000;  // To BFM (8-bit per lane BFM has max 31 nS of range)
   parameter   BFM_SKEW_EN             = 0;
   parameter   DUT_SKEW_EN             = 0;
   parameter   BFM_SKEW_TYPE           = 0;
   parameter   DUT_SKEW_TYPE           = 0;

   localparam  APB_ADDR_WIDTH          = 16;   // Width of apb_paddr in APB_DATA_WIDTH words; ex: (APB_ADDR_WIDTH ==  16) -> 2^16 APB_DATA_WIDTH-bit words
   localparam  APB_DATA_WIDTH          = 32;               // Data Width
   localparam  APB_STRB_WIDTH          = 4;                // Strobe Width
   localparam  APB_PSEL_WIDTH          = 2;

   parameter   DUT_LANE_SHIFT          = 0;

   localparam NUM_LANES_USED = NUM_LANES;

   localparam REFCLK_PERIOD = (TX_RX_F_A == 5) ? 10000 : 8000;

   // AXI DMA
   localparam IMAGE_PATTERN = 1'b0; // 1: image pattern. 0: incremental pattern.
   localparam PER_BYTE_INCR = 1'b1; // Used when IMAGE_PATTERN == 1'b0. 1: Incremented per byte. 0: Incremented per 32-byte.
   localparam IMAGE_PATTERN_ONCE = 1'b1; // 1: Used when IMAGE_PATTERN == 1. 1: Send image pattern once. 0: Send repeatedly.
   localparam [16:0] STREAM_SIZE = 17'b0_0100_0000_0000_0000; // 16 KB for a stream.

   // -------------------
   // -- Local Signals --
   // -------------------

   // Error Counter
   integer                             ERROR_COUNT = 0;

   reg                                 pcie_clk;
   wire                                pcie_clk_p;
   wire                                pcie_clk_n;
   wire                                clkreq;
   reg                                 clk100_reg;
   reg                                 c_rst_n;
   reg                                 rst_n;
   reg                                 c_bp1_rst_n;
   reg                                 bp1_rst_n;
   wire                                activity_observed_i;
   reg                                 activity_observed;
   tri1 [1:0]                          clkreq_n;

   // Lane Masking - NWL Use Only
   wire [MAX_NUM_LANES-1:0]            lane_fail;
   reg [MAX_NUM_LANES-1:0]             lane_mask;

   // Track active_lanes
   wire [MAX_NUM_LANES-1:0]            active_lanes_dut;
   reg [MAX_NUM_LANES-1:0]             active_lanes_swiz;
   wire [MAX_NUM_LANES-1:0]            active_lanes_mask;
   wire [MAX_NUM_LANES-1:0]            active_lanes_shft;
   wire [MAX_NUM_LANES-1:0]            active_lanes_rev;
   wire [MAX_NUM_LANES-1:0]            active_lanes_brev;
   wire [MAX_NUM_LANES-1:0]            active_lanes_bfm;

   // Lane Skew Control - NWL Use Only
   reg [MAX_NUM_LANES-1:0]             bfm_skew_mask = (BFM_SKEW_TYPE == 1) ? {MAX_NUM_LANES{1'b1}} : {MAX_NUM_LANES{1'b0}};
   reg [MAX_NUM_LANES-1:0]             dut_skew_mask = (DUT_SKEW_TYPE == 1) ? {MAX_NUM_LANES{1'b1}} : {MAX_NUM_LANES{1'b0}};
   reg                                 bfm_skew_en   = (BFM_SKEW_EN == 1) ? 1'b1 : 1'b0;
   reg                                 dut_skew_en   = (DUT_SKEW_EN == 1) ? 1'b1 : 1'b0;
   integer                             dut_skew [MAX_NUM_LANES-1:0];
   integer                             bfm_skew [MAX_NUM_LANES-1:0];

   // Lane p, n Inversion - NWL Use Only
   reg [MAX_NUM_LANES-1:0]             bfm_invert_tx = DUT_TX_INVERT[MAX_NUM_LANES-1:0];
   reg [MAX_NUM_LANES-1:0]             dut_invert_tx = BFM_TX_INVERT[MAX_NUM_LANES-1:0];

   // Lane reversal Control - NWL Use Only
   reg                                 dut_reverse;
   reg                                 bfm_reverse;
   reg [4:0]                           lane_shift;
   reg [4:0]                           bfm_em_width;
   reg [4:0]                           dut_lanes_used;

   wire                                el_idle;


   // Serial lines connected to DUT/Model
   wire [MAX_NUM_LANES-1:0]            dut_to_model_p;
   wire [MAX_NUM_LANES-1:0]            dut_to_model_n;

   wire [MAX_NUM_LANES-1:0]            temp_model_to_dut_p;
   wire [MAX_NUM_LANES-1:0]            temp_model_to_dut_n;

   wire [MAX_NUM_LANES-1:0]            model_to_dut_p_swiz;
   wire [MAX_NUM_LANES-1:0]            model_to_dut_n_swiz;
   reg [MAX_NUM_LANES-1:0]             dut_to_model_p_swiz;
   reg [MAX_NUM_LANES-1:0]             dut_to_model_n_swiz;

   wire [MAX_NUM_LANES-1:0]            model_to_dut_p_shft;
   wire [MAX_NUM_LANES-1:0]            model_to_dut_n_shft;
   wire [MAX_NUM_LANES-1:0]            dut_to_model_p_shft;
   wire [MAX_NUM_LANES-1:0]            dut_to_model_n_shft;

   // Intermediary serial lines after optional actions
   wire [MAX_NUM_LANES-1:0]            dut_to_model_p_drev;
   wire [MAX_NUM_LANES-1:0]            dut_to_model_n_drev;

   wire [MAX_NUM_LANES-1:0]            dut_to_model_p_mask;
   wire [MAX_NUM_LANES-1:0]            dut_to_model_n_mask;

   reg [MAX_NUM_LANES-1:0]             dut_to_model_p_mask_skew;
   reg [MAX_NUM_LANES-1:0]             dut_to_model_n_mask_skew;

   wire [MAX_NUM_LANES-1:0]            dut_to_model_p_mask_skew_swap;
   wire [MAX_NUM_LANES-1:0]            dut_to_model_n_mask_skew_swap;

   wire [MAX_NUM_LANES-1:0]            dut_to_model_p_brev;
   wire [MAX_NUM_LANES-1:0]            dut_to_model_n_brev;

   wire [MAX_NUM_LANES-1:0]            model_to_dut_p_brev;
   wire [MAX_NUM_LANES-1:0]            model_to_dut_n_brev;

   wire [MAX_NUM_LANES-1:0]            model_to_dut_p_mask;
   wire [MAX_NUM_LANES-1:0]            model_to_dut_n_mask;

   reg [MAX_NUM_LANES-1:0]             model_to_dut_p_mask_skew;
   reg [MAX_NUM_LANES-1:0]             model_to_dut_n_mask_skew;

   wire [MAX_NUM_LANES-1:0]            model_to_dut_p_mask_skew_swap;
   wire [MAX_NUM_LANES-1:0]            model_to_dut_n_mask_skew_swap;

   reg [MAX_NUM_LANES-1:0]             model_to_dut_p;
   reg [MAX_NUM_LANES-1:0]             model_to_dut_n;


   // PCIe Bus Functional Model
   wire                                core_rst_n;
   wire                                core_clk;
   wire [NUM_LINKS_TB-1:0]             pl_link_up;
   wire [NUM_LINKS_TB-1:0]             dl_link_up;
   wire [NUM_LINKS_TB-1:0]             test_done;



   wire                                i2c_reset_n;
   wire                                proc_wr_en;
   wire                                proc_rd_en;
   wire [15:0]                         proc_addr;
   wire [31:0]                         proc_wr_data;
   wire [31:0]                         proc_rd_data;
   wire                                proc_rd_data_valid;

   reg[31:0]                           n_msg_cnt;
   reg[31:0]                           w_msg_cnt;
   reg[31:0]                           e_msg_cnt;
   reg[31:0]                           d_msg_cnt;

   wire [NUM_LINKS_TB-1:0]             apb_rst_n_hold;

   wire                                apb_pclk;
   wire                                apb_preset_n;
   wire [APB_ADDR_WIDTH-1:0]           apb_paddr;
   wire [APB_PSEL_WIDTH-1:0]           apb_psel;
   wire                                apb_penable;
   wire                                apb_pwrite;
   wire [APB_DATA_WIDTH-1:0]           apb_pwdata;
   wire [APB_STRB_WIDTH-1:0]           apb_pstrb;
   wire [APB_DATA_WIDTH-1:0]           apb_prdata;
   wire                                apb_pready;
   wire                                apb_pslverr;

   wire [APB_ADDR_WIDTH-1:0]           apb_paddr_i;
   wire [APB_PSEL_WIDTH-1:0]           apb_psel_i;
   wire                                apb_penable_i;
   wire                                apb_pwrite_i;
   wire [APB_DATA_WIDTH-1:0]           apb_pwdata_i;
   wire [APB_STRB_WIDTH-1:0]           apb_pstrb_i;
   wire                                apb_pready_i;
   wire                                apb_pslverr_i;


   assign activity_observed_i = apb_penable | gen_pcie_bfm[0].pcie_bfm.model_tx_en | gen_pcie_bfm[0].pcie_bfm.rx_en;  // PCIe bus activity

   always @(posedge activity_observed_i or posedge clk100_reg)
     begin
        if (activity_observed_i == 1'b1)
          activity_observed <= 1'b1;
        else
          activity_observed <= 1'b0;
     end

   // ---------------
   // Clock and Reset

   // Generate rising edge aligned clocks;
   //   Note: Not all clocks used in all configurations

   assign clkreq = ~clkreq_n[0];
   assign clkreq_n[0] = 1'b0;

   // Generate PCI Express reference clock
   initial
     begin
        pcie_clk = 0;
        forever
          begin
             #(REFCLK_PERIOD/2);
             pcie_clk = ~pcie_clk;
          end
     end

    assign pcie_clk_p =  clkreq ?  pcie_clk : 1'b0;
    assign pcie_clk_n =  clkreq ? ~pcie_clk : 1'b1;

   // Generate 100 MHz clock
   initial
     begin
        clk100_reg = 0;
        forever
          begin
             #5000; // 10 ns Period
             clk100_reg = ~clk100_reg;
          end
     end

   // Generate reset
   initial
     begin
        c_rst_n = 1;
        #RESET_INACTIVE_TIME;
        c_rst_n = 0;
        #RESET_ACTIVE_TIME;
        c_rst_n = 1;
     end

   // Generate reset for second link
   initial
     begin
        c_bp1_rst_n = 1;
        #RESET_INACTIVE_TIME;
        c_bp1_rst_n = 0;
        #RESET_ACTIVE_TIME;
        #10000000; // Hold Second BFM off for 10us
        c_bp1_rst_n = 1;
     end


   // DUT Reset extension:
   //   Use to hold core in reset while testing core CSR values.
   //   Most CSR values must be static when core perst_n is released.

   always @* begin
      rst_n     = c_rst_n & (&apb_rst_n_hold);
      bp1_rst_n = c_bp1_rst_n & (&apb_rst_n_hold);
   end


   // ----------------------------
   // Lane Mask, Skew, & Inversion

   // Use requested electrical idle symbol
   assign el_idle =  (SIM_EL_IDLE_TYPE == 2'b11) ? 1'b1 :
                     ((SIM_EL_IDLE_TYPE == 2'b10) ? 1'b0 :
                      ((SIM_EL_IDLE_TYPE == 2'b01) ? 1'bx : 1'bz));

   // Set bits cause associated Lane to bad data so it will be dropped from the link during training
   assign lane_fail =  0
                       ;

   generate
      if (MAX_NUM_LANES == 1)
        begin
           assign active_lanes_dut = 1'b1;
           assign active_lanes_bfm = 1'b1 & ~BFM_PHY_LANE_MASK;
        end
      else if (MAX_NUM_LANES == 2)
        begin
           assign active_lanes_dut = (    NUM_LANES == 2) ? 2'h3 : 2'h1;
           assign active_lanes_bfm = ((BFM_NUM_LANES == 2) ? 2'h3 : 2'h1) & ~BFM_PHY_LANE_MASK;
        end
      else if (MAX_NUM_LANES == 4)
        begin
           assign active_lanes_dut = (    NUM_LANES == 4) ? 4'hf :
                                     (    NUM_LANES == 2) ? 4'h3 : 4'h1;
           assign active_lanes_bfm = ((BFM_NUM_LANES == 4) ? 4'hf :
                                      (BFM_NUM_LANES == 2) ? 4'h3 : 4'h1) & ~BFM_PHY_LANE_MASK;
        end
      else if (MAX_NUM_LANES == 8)
        begin
           assign active_lanes_dut = (    NUM_LANES == 8) ? 8'hff :
                                     (    NUM_LANES == 4) ? 8'h0f :
                                     (    NUM_LANES == 2) ? 8'h03 : 8'h01;
           assign active_lanes_bfm = ((BFM_NUM_LANES == 8) ? 8'hff :
                                      (BFM_NUM_LANES == 4) ? 8'h0f :
                                      (BFM_NUM_LANES == 2) ? 8'h03 : 8'h01) & ~BFM_PHY_LANE_MASK;
        end
      else if (MAX_NUM_LANES == 16)
        begin
           assign active_lanes_dut = (    NUM_LANES == 16) ? 16'hffff :
                                     (    NUM_LANES ==  8) ? 16'h00ff :
                                     (    NUM_LANES ==  4) ? 16'h000f :
                                     (    NUM_LANES ==  2) ? 16'h0003 : 16'h0001;
           assign active_lanes_bfm = ((BFM_NUM_LANES == 16) ? 16'hffff :
                                      (BFM_NUM_LANES ==  8) ? 16'h00ff :
                                      (BFM_NUM_LANES ==  4) ? 16'h000f :
                                      (BFM_NUM_LANES ==  2) ? 16'h0003 : 16'h0001) & ~BFM_PHY_LANE_MASK;
        end
   endgenerate
   
   // Commented by Susrith
   //Reason :- Due to this serial read data(link0_rxn_i,link0_rxp_i) got affected (ie; Getting multi driven value in simulation )
   //Especially , in case of Non DMA operations
   /*
   initial begin
   #300000000; //kcheah 
   end
   */
   
   initial begin
      @(posedge core_clk);
      lane_mask = ~lane_fail;
      dut_reverse = DUT_LANE_REVERSE;
      bfm_reverse = BFM_LANE_REVERSE;
      lane_shift  = DUT_LANE_SHIFT;
      bfm_em_width = (BFM_EMULATE_WIDTH == 0) ? BFM_NUM_LANES : BFM_EMULATE_WIDTH;
      dut_lanes_used = NUM_LANES_USED;
   end

   always @* model_to_dut_p = model_to_dut_p_swiz;
   always @* model_to_dut_n = model_to_dut_n_swiz;

   always @* dut_to_model_p_swiz = dut_to_model_p;
   always @* dut_to_model_n_swiz = dut_to_model_n;
   always @* active_lanes_swiz   = active_lanes_dut;

   // Apply optional operations to serial lines to enable testing
   //   of down-training, skew correction, and lane inversion
   //     NOTE: The following registers are forced to control these functions
   //       lane_mask    [MAX_NUM_LANES-1:0] : clear corresponding bits to force lanes to output constant diff data
   //       skew_mask    [MAX_NUM_LANES-1:0] : set/clear corresponding bits to select skew for lanes
   //       dut_invert_tx[MAX_NUM_LANES-1:0] : set   corresponding bits to force DUT TX to invert tx_p & tx_n
   //       bfm_invert_tx[MAX_NUM_LANES-1:0] : set   corresponding bits to force BFM TX to invert tx_p & tx_n
   genvar g;
   generate
      for (g = 0; g < MAX_NUM_LANES; g = g + 1)
        begin: gen_lane_mask
           // ------------
           // DUT to Model

           always@* dut_skew[g] = dut_skew_en ? (dut_skew_mask[g] ? (MAX_LANE_SKEW_TO_BFM/(MAX_NUM_LANES-1))*g : MAX_LANE_SKEW_TO_BFM - ((MAX_LANE_SKEW_TO_BFM/(MAX_NUM_LANES-1))*g) ) : 0;
           always@* bfm_skew[g] = bfm_skew_en ? (bfm_skew_mask[g] ? (       MAX_LANE_SKEW/(MAX_NUM_LANES-1))*g : MAX_LANE_SKEW        - ((       MAX_LANE_SKEW/(MAX_NUM_LANES-1))*g) ) : 0;

           // Mask selected lanes : Force down-training
           assign dut_to_model_p_mask[g] = lane_mask[g] ? dut_to_model_p_swiz[g] : 1'b0;
           assign dut_to_model_n_mask[g] = lane_mask[g] ? dut_to_model_n_swiz[g] : 1'b1;
           assign   active_lanes_mask[g] = lane_mask[g] &   active_lanes_swiz[g];

           // DUT Lane Shift
           assign dut_to_model_p_shft[g] = (g < dut_lanes_used) ? ((g+lane_shift < dut_lanes_used) ? dut_to_model_p_mask[(g+lane_shift)] : dut_to_model_p_mask[g+lane_shift-dut_lanes_used]) : 1'bz;
           assign dut_to_model_n_shft[g] = (g < dut_lanes_used) ? ((g+lane_shift < dut_lanes_used) ? dut_to_model_n_mask[(g+lane_shift)] : dut_to_model_n_mask[g+lane_shift-dut_lanes_used]) : 1'bz;
           assign active_lanes_shft[g]   = (g < dut_lanes_used) ? ((g+lane_shift < dut_lanes_used) ?   active_lanes_mask[(g+lane_shift)] :   active_lanes_mask[g+lane_shift-dut_lanes_used]) : 1'b0;

           // DUT Lane Reversal
           assign dut_to_model_p_drev[g] = (g < dut_lanes_used) ? ((dut_reverse != 0) ? dut_to_model_p_shft[(dut_lanes_used-1)-g] : dut_to_model_p_shft[g]) : 1'bz;
           assign dut_to_model_n_drev[g] = (g < dut_lanes_used) ? ((dut_reverse != 0) ? dut_to_model_n_shft[(dut_lanes_used-1)-g] : dut_to_model_n_shft[g]) : 1'bz;
           assign active_lanes_rev[g]    = (g < dut_lanes_used) ? ((dut_reverse != 0) ? active_lanes_shft[(dut_lanes_used-1)-g] : active_lanes_shft[g]) : 1'bz;

           //   Final skew selection
           always @* dut_to_model_p_mask_skew[g] <= #(dut_skew[g]) dut_to_model_p_drev[g];
           always @* dut_to_model_n_mask_skew[g] <= #(dut_skew[g]) dut_to_model_n_drev[g];

           // DUT Lane Inversion
           assign dut_to_model_p_mask_skew_swap[g] = dut_invert_tx[g] ? dut_to_model_n_mask_skew[g] : dut_to_model_p_mask_skew[g];
           assign dut_to_model_n_mask_skew_swap[g] = dut_invert_tx[g] ? dut_to_model_p_mask_skew[g] : dut_to_model_n_mask_skew[g];

           // Model Lane Reversal
           assign dut_to_model_p_brev[g] = (g < bfm_em_width) ? ((bfm_reverse != 0) ? dut_to_model_p_mask_skew_swap[(bfm_em_width-1)-g] : dut_to_model_p_mask_skew_swap[g]) : 1'bz;
           assign dut_to_model_n_brev[g] = (g < bfm_em_width) ? ((bfm_reverse != 0) ? dut_to_model_n_mask_skew_swap[(bfm_em_width-1)-g] : dut_to_model_n_mask_skew_swap[g]) : 1'bz;
           assign   active_lanes_brev[g] = (g < bfm_em_width) ? ((bfm_reverse != 0) ?              active_lanes_rev[(bfm_em_width-1)-g] :              active_lanes_rev[g]) : 1'b0;

           // ------------
           // Model to DUT

           // Model Lane Reversal
           assign model_to_dut_p_brev[g] = (g < bfm_em_width) ? ((bfm_reverse != 0) ? temp_model_to_dut_p[(bfm_em_width-1)-g] : temp_model_to_dut_p[g]) : 1'bz;
           assign model_to_dut_n_brev[g] = (g < bfm_em_width) ? ((bfm_reverse != 0) ? temp_model_to_dut_n[(bfm_em_width-1)-g] : temp_model_to_dut_n[g]) : 1'bz;

           //   Final skew selection
           always @* model_to_dut_p_mask_skew[g] <= #(bfm_skew[g]) model_to_dut_p_brev[g];
           always @* model_to_dut_n_mask_skew[g] <= #(bfm_skew[g]) model_to_dut_n_brev[g];

           // Model Lane Inversion
           assign model_to_dut_p_mask_skew_swap[g] = bfm_invert_tx[g] ? model_to_dut_n_mask_skew[g] : model_to_dut_p_mask_skew[g];
           assign model_to_dut_n_mask_skew_swap[g] = bfm_invert_tx[g] ? model_to_dut_p_mask_skew[g] : model_to_dut_n_mask_skew[g];

           // DUT Lane Reversal
           assign model_to_dut_p_shft[g] = (g < dut_lanes_used) ? ((dut_reverse != 0) ? model_to_dut_p_mask_skew_swap[(dut_lanes_used-1)-g] : model_to_dut_p_mask_skew_swap[g]) : 1'bz;
           assign model_to_dut_n_shft[g] = (g < dut_lanes_used) ? ((dut_reverse != 0) ? model_to_dut_n_mask_skew_swap[(dut_lanes_used-1)-g] : model_to_dut_n_mask_skew_swap[g]) : 1'bz;

           // DUT Lane Shift
           assign model_to_dut_p_mask[g] = (g < dut_lanes_used) ? ((g >= lane_shift) ? model_to_dut_p_shft[(g-lane_shift)] : model_to_dut_p_shft[dut_lanes_used+g-lane_shift]) : 1'bz;
           assign model_to_dut_n_mask[g] = (g < dut_lanes_used) ? ((g >= lane_shift) ? model_to_dut_n_shft[(g-lane_shift)] : model_to_dut_n_shft[dut_lanes_used+g-lane_shift]) : 1'bz;

           // Mask selected lanes : Force down-training
           assign model_to_dut_p_swiz[g] = lane_mask[g] ? model_to_dut_p_mask[g] : 1'b0;
           assign model_to_dut_n_swiz[g] = lane_mask[g] ? model_to_dut_n_mask[g] : 1'b1;

        end
   endgenerate

   // -----------------------------
   // Instantiate Device Under Test


   // Signals used to inject errors into serial pcie data
   wire [NUM_LANES-1:0] dut_to_model_noerr_p;
   wire [NUM_LANES-1:0] dut_to_model_noerr_n;
   reg [NUM_LANES-1:0]  dut_to_model_err_inject;   // Used by loopback_test.v
   wire [NUM_LANES-1:0] model_to_dut_err_p;
   wire [NUM_LANES-1:0] model_to_dut_err_n;
   reg [NUM_LANES-1:0]  model_to_dut_err_inject;   // Used by loopback_test.v

   initial begin
      dut_to_model_err_inject = 0;
      model_to_dut_err_inject = 0;
   end

//---------------------------------------------------------

   GSR GSR_INST (.GSR_N(rst_n), .CLK(core_clk));

    //Gen_type and lane_number
    
    wire [1:0] gen_no;
    wire [2:0] lane_no;
    wire [2:0] mgmt_lane_no;
    
    assign gen_no  = (GENERATION == 2)? 2'd2 : ((GENERATION == 1) ? 2'd1 : 2'd0);
    assign lane_no = (NO_LANES == 3'd4)  ? 3'd3 : ((NO_LANES == 3'd2)   ? 3'd2 : ((NO_LANES == 3'd1) ? 3'd1 : 3'd0));
    assign mgmt_lane_no = (NO_LANES == 3'd4)  ? 6'd4 : ((NO_LANES == 3'd2)   ? 6'd2 : ((NO_LANES == 3'd1) ? 6'd1 : 6'd0));
	
	wire clk_usr_i;
	wire clk_usr_o;
	
	wire dma_done_ref_des;		
	wire clk_usr_div2_i_ref_des;
	wire [64*NO_LANES-1:0]m0_r_hrdata_i_ref_des;
	wire [31:0]m0_r_haddr_o_ref_des;
	wire [1:0]m0_r_htrans_o_ref_des;
	
	wire [1:0] non_dma_write_data_check;
	wire [31:0] bar_0_address;
    wire [31:0] bar_1_address;

    wire [NUM_USR_INT-1:0] usr_int_req_i_n_wire;
    wire usr_vector_done_set;
    assign usr_vector_done_set = 1'b0; 
    assign usr_int_req_i_n_wire = {NUM_USR_INT{1'b1}};
/*
wire [DMA_AXI_ID_WIDTH-1:0] s0_aximm_awid_i;
wire [63:0] s0_aximm_awaddr_i;
wire [7:0] s0_aximm_awlen_i;
wire [2:0] s0_aximm_awsize_i;
wire [1:0] s0_aximm_awburst_i;
wire s0_aximm_awlock_i; // Not supported.
wire [3:0] s0_aximm_awcache_i; // Not supported.
wire [2:0] s0_aximm_awprot_i; // Not supported.
wire [3:0] s0_aximm_awregion_i; // Not supported.
wire s0_aximm_awvalid_i;
wire s0_aximm_awready_o;
// AXI Write Channel
wire [AXI_WIDTH-1:0] s0_aximm_wdata_i;
wire [(AXI_WIDTH/8)-1:0] s0_aximm_wstrb_i;
wire s0_aximm_wlast_i;
wire [7:0] s0_aximm_wuser_i; // Not supported.
wire s0_aximm_wvalid_i;
wire s0_aximm_wready_o;
// AXI Write Response Channel
wire [DMA_AXI_ID_WIDTH-1:0] s0_aximm_bid_o;
wire [1:0] s0_aximm_bresp_o;
wire s0_aximm_bvalid_o;
wire s0_aximm_bready_i;
// AXI Read Address Channel
wire [DMA_AXI_ID_WIDTH-1:0] s0_aximm_arid_i;
wire [63:0] s0_aximm_araddr_i;
wire [7:0] s0_aximm_arlen_i;
wire [2:0] s0_aximm_arsize_i;
wire [1:0] s0_aximm_arburst_i;
wire s0_aximm_arlock_i; // Not supported.
wire [3:0] s0_aximm_arcache_i; // Not supported.
wire [2:0] s0_aximm_arprot_i; // Not supported.
wire [3:0] s0_aximm_arregion_i; // Not supported.
wire s0_aximm_arvalid_i;
wire s0_aximm_arready_o;
// AXI Read Data Channel
wire [DMA_AXI_ID_WIDTH-1:0] s0_aximm_rid_o;
wire [AXI_WIDTH-1:0] s0_aximm_rdata_o;
wire [1:0] s0_aximm_rresp_o;
wire s0_aximm_rlast_o;
wire s0_aximm_rvalid_o;
wire s0_aximm_rready_i;
*/
generate
// Bridge Mode is under this too
if ( (((USR_DAT_IF_MODE == 1) | (USR_DAT_IF_MODE == 3)) & (USR_DAT_IF_TYPE == "AXI_MM")) | (USR_DAT_IF_MODE == 2) ) begin: PCIE_AXI_DMA
    
    reg tb_clk_125;
    reg tb_clk_250;

    initial
    begin
        tb_clk_125 = 0;
        forever
        begin
            #(4000);
            tb_clk_125 = ~tb_clk_125;
        end
    end

    initial
    begin
        tb_clk_250 = 0;
        forever
        begin
            #(2000);
            tb_clk_250 = ~tb_clk_250;
        end
    end

    wire refclkp_i; 
    wire refclkn_i;
    wire [NUM_LANES-1:0] link0_rxp_i;
    wire [NUM_LANES-1:0] link0_rxn_i;
    wire [NUM_LANES-1:0] link0_txp_o;
    wire [NUM_LANES-1:0] link0_txn_o;
    wire perst_n_i;
    wire usr_rst_n;
    wire [NUM_LANES-1:0] refret_i;
    wire [NUM_LANES-1:0] rext_i;
    wire clk_125;
    wire linkup_done;
    wire clock_flag;
    wire [6:0] segment_out;
    wire [2:0] segment_en;
    wire clk_sel;
    wire pcie_sel;
    wire pcie_sw1_pd;
    wire pcie_sw2_pd;

    // reference clock for PCIe
    assign refclkp_i      = (pcie_clk_p                         );
    assign refclkn_i      = (pcie_clk_n                         );

    //Serial Data to and from PCIe
    assign link0_rxp_i    = (model_to_dut_err_p  [NO_LANES - 1 : 0]);
    assign link0_rxn_i    = (model_to_dut_err_n  [NO_LANES - 1 : 0]);
    assign dut_to_model_noerr_p[NO_LANES - 1 : 0] = link0_txp_o;
    assign dut_to_model_noerr_n[NO_LANES - 1 : 0] = link0_txn_o;
    
    assign perst_n_i = rst_n;
    assign usr_rst_n = rst_n;
    assign refret_i =  4'b0;
    assign rext_i =  4'b0;

    assign clk_125 = tb_clk_125;

        // PCIe AXI-MM DMA example design instance
	if (DMA_BYPASS_7S_AND_LED_DEMO == 1) begin: DMA_BYP_7S_AND_LED_DEMO_TOP
	    aximm_dma_ed_top_7s_LED_demo #(
		.SIM(1)
	    ) ed_top_inst (
		.refclkp_i(refclkp_i),
		.refclkn_i(refclkn_i),
		.link0_rxp_i(link0_rxp_i),
		.link0_rxn_i(link0_rxn_i),
		.link0_txp_o(link0_txp_o),
		.link0_txn_o(link0_txn_o),
		.perst_n_i(perst_n_i),
		.usr_rst_n(usr_rst_n),
		.refret_i(refret_i),
		.rext_i(rext_i),
		.clk_125(clk_125),
		.linkup_done(),
		.clock_flag(),
		.segment_out(),
		.segment_en(),
		.clk_sel(),
		.pcie_sel(),
		.pcie_sw1_pd(),
		.pcie_sw2_pd(),
		.LED_1(),
		.LED_2(),
		.LED_3(),
		.LED_4(),
		.LED_5(),
		.usr_int_req_i_n_button(usr_int_req_i_n_wire)
	    );
	end else begin   

      if (FULL_BRIDGE_EN == 1) begin: AXI_BRIDGE_ONLY

        axi_bridge_ed_top #(
            .SIM(1),
            .NUM_LANES(NUM_LANES),
            .AXI_BRIDGE_DATA_WIDTH(DMA_AXI_WIDTH)
        ) ed_top_inst (
            .refclkp_i(refclkp_i),
            .refclkn_i(refclkn_i),
            .link0_rxp_i(link0_rxp_i),
            .link0_rxn_i(link0_rxn_i),
            .link0_txp_o(link0_txp_o),
            .link0_txn_o(link0_txn_o),
            .ed_perst_n_i(perst_n_i),
            .ed_usr_rst_n(usr_rst_n),
            .refret_i(refret_i),
            .rext_i(rext_i),
            .clk_user(clk_125),
            .linkup_done(),
            .clock_flag(),
            .segment_out(),
            .segment_en(),
            .clk_sel(),
            .pcie_sel(),
            .pcie_sw1_pd(),
            .pcie_sw2_pd()
        );

      end else begin

	    aximm_dma_ed_top #(
		.SIM(1),
		.NUM_LANES(NUM_LANES)
	    ) ed_top_inst (
		.refclkp_i(refclkp_i),
		.refclkn_i(refclkn_i),
		.link0_rxp_i(link0_rxp_i),
		.link0_rxn_i(link0_rxn_i),
		.link0_txp_o(link0_txp_o),
		.link0_txn_o(link0_txn_o),
		.ed_perst_n_i(perst_n_i),
		.ed_usr_rst_n(usr_rst_n),
		.refret_i(refret_i),
		.rext_i(rext_i),
		.clk_user(clk_125),
		.linkup_done(),
		.clock_flag(),
		.segment_out(),
		.segment_en(),
		.clk_sel(),
		.pcie_sel(),
		.pcie_sw1_pd(),
		.pcie_sw2_pd(),
		.usr_int_req_i_n_button(4'b1111)
	    );

      end

	end
end
endgenerate

generate
if ( ((USR_DAT_IF_MODE == 1) | (USR_DAT_IF_MODE == 3)) & (USR_DAT_IF_TYPE == "AXI_STREAM")) begin: PCIE_AXIST_DMA

    reg tb_clk_125;

    initial
    begin
        tb_clk_125 = 0;
        forever
        begin
            #(4000);
            tb_clk_125 = ~tb_clk_125;
        end
    end

    wire refclkp_i;
    wire refclkn_i;
    wire [NUM_LANES-1:0] link0_rxp_i;
    wire [NUM_LANES-1:0] link0_rxn_i;
    wire [NUM_LANES-1:0] link0_txp_o;
    wire [NUM_LANES-1:0] link0_txn_o;
    wire perst_n_i;
    wire usr_rst_n;
    wire linkup_done;
    wire clock_flag;
    wire [6:0] segment_out;
    wire [2:0] segment_en;
    wire clk_sel;
    wire pcie_sel;
    wire pcie_sw1_pd;
    wire pcie_sw2_pd;

    // reference clock for PCIe
    assign refclkp_i      = (pcie_clk_p                         );
    assign refclkn_i      = (pcie_clk_n                         );

    //Serial Data to and from PCIe
    assign link0_rxp_i    = (model_to_dut_err_p  [NO_LANES - 1 : 0]);
    assign link0_rxn_i    = (model_to_dut_err_n  [NO_LANES - 1 : 0]);
    assign dut_to_model_noerr_p[NO_LANES - 1 : 0] = link0_txp_o;
    assign dut_to_model_noerr_n[NO_LANES - 1 : 0] = link0_txn_o;

    assign perst_n_i = rst_n;
    assign usr_rst_n = rst_n;

    // PCIe AXI-ST DMA example design instance
    axist_dma_ed_top  #(
       .SIM(1),
       .IMAGE_PATTERN(IMAGE_PATTERN), // 1: image pattern. 0: incremental pattern.
       .PER_BYTE_INCR(PER_BYTE_INCR), // Used when IMAGE_PATTERN == 1'b0. 1: Incremented per byte. 0: Incremented per 32-byte.
       .IMAGE_PATTERN_ONCE(IMAGE_PATTERN_ONCE), // 1: Used when IMAGE_PATTERN == 1. 1: Send image pattern once. 0: Send repeatedly.
       .STREAM_SIZE(STREAM_SIZE) // 16 KB for a stream.
    ) ed_top_inst (
       .refclkp_i(refclkp_i),
       .refclkn_i(refclkn_i),
       .link0_rxp_i(link0_rxp_i),
       .link0_rxn_i(link0_rxn_i),
       .link0_txp_o(link0_txp_o),
       .link0_txn_o(link0_txn_o),
       .ed_perst_n_i(perst_n_i),
       .ed_usr_rst_n(usr_rst_n),
       .refret_i(4'b0000),
       .rext_i(4'b0000),
       .clk_user(tb_clk_125),
       .linkup_done(),
       .usr_vector_done_set(usr_vector_done_set),
       //.clock_flag(),
       //.segment_out(),
       //.segment_en(),
       .clk_sel(),
       .pcie_sel(),
       .pcie_sw1_pd(),
       .pcie_sw2_pd()
    );

end
endgenerate

generate 

if (EN_DMA_SUPPORT == "Enable") begin:DMA_ENABLE 
    wire sys_clk_i;
    wire clk_usr_div2_i;
    wire clk_ps_90_i;
    wire c_apb_pclk_i;
    wire c_apb_preset_n_i;
    wire c_apb_psel_i;
    wire c_apb_penable_i;
    wire c_apb_pwrite_i;
    wire m0_w_hready_i;
    wire m0_w_hresp_i;
    wire m0_r_hresp_i;
    wire m0_r_hready_i;
    wire c_apb_pready_o;
    wire m0_w_hwrite_o;
    wire m0_r_hwrite_o;
    wire c_apb_pslverr_o;
    wire [31:0]c_apb_paddr_i;
    wire [31:0]c_apb_pwdata_i;
    wire [31:0]c_apb_prdata_o;
    wire [64*NO_LANES - 1: 0]m0_w_hrdata_i;
    wire [64*NO_LANES - 1: 0]m0_r_hrdata_i;
    wire [64*NO_LANES - 1: 0]m0_w_hwdata_o;
    wire [64*NO_LANES - 1: 0]m0_r_hwdata_o;
    wire [31:0]m0_w_haddr_o;
    wire [31:0]m0_r_haddr_o;
    wire [2:0] m0_w_hburst_o;
    wire [2:0] m0_r_hburst_o;
    wire [2:0] m0_w_hsize_o;
    wire [2:0] m0_r_hsize_o;
    wire [1:0] m0_w_htrans_o;
    wire [1:0] m0_r_htrans_o;
    wire m0_w_hmastlock_o;
    wire m0_r_hmastlock_o;
    wire m0_w_hprot_o;
    wire m0_r_hprot_o;

    reg clk_125;
    wire dma_done;

    initial
    begin
        clk_125 = 0;
        forever
        begin
            #(4000);
            clk_125 = ~clk_125;
        end
    end


    // Design instantiation
    tb_dma_application_layer # (
        .SIM (1),
        .NO_LANES(NO_LANES),
        .PCIE_CSR_BASE_ADDR(PCIE_CSR_BASE_ADDR)
    ) 
    dut(
        .perst_n_i               (rst_n  ),
        .usr_rst_n               (rst_n  ),
        .clock_flag			 	(clock_flag),
        .clk_125                 (clk_125),
        .dma_done_o              (dma_done),
        .sys_clk	  			    (sys_clk_i),
        .clk_usr_div2			(clk_usr_div2_i),
        .clk_ps_90 				(clk_ps_90_i),
        .c_apb_pclk				(c_apb_pclk_i),
        .c_apb_preset_n			(c_apb_preset_n_i),
        .c_apb_psel				(c_apb_psel_i),
        .c_apb_penable 			(c_apb_penable_i),
        .c_apb_pwrite			(c_apb_pwrite_i),
        .m_w_hready				(m0_w_hready_i),
        .m_w_hresp				(m0_w_hresp_i),
        .m_r_hresp 				(m0_r_hresp_i),
        .m_r_hready				(m0_r_hready_i),
        .c_apb_pready			(c_apb_pready_o),
        .m_w_hwrite				(m0_w_hwrite_o),
        .m_r_hwrite				(m0_r_hwrite_o),
        .c_apb_pslverr			(c_apb_pslverr_o),
        .c_apb_paddr			    (c_apb_paddr_i),
        .c_apb_pwdata			(c_apb_pwdata_i),
        .c_apb_prdata			(c_apb_prdata_o),
        .m_w_hrdata				(m0_w_hrdata_i),
        .m_r_hrdata				(m0_r_hrdata_i),
        .m_w_hwdata				(m0_w_hwdata_o),
        .m_r_hwdata				(m0_r_hwdata_o),
        .m_w_haddr				(m0_w_haddr_o),
        .m_r_haddr				(m0_r_haddr_o),
        .m_w_hburst				(m0_w_hburst_o),
        .m_r_hburst				(m0_r_hburst_o),
        .m_w_hsize				(m0_w_hsize_o),
        .m_r_hsize				(m0_r_hsize_o),
        .m_w_htrans				(m0_w_htrans_o),
        .m_r_htrans				(m0_r_htrans_o),
        .clk_usr_o				(clk_usr_o),
        .gen_no 				    (gen_no),
        .lane_no				    (lane_no)
    );

    wire refclkp_i ;
    wire refclkn_i ;


    wire linkup_done;
    wire link0_pl_link_up_o;
    wire link0_dl_link_up_o;
    wire link0_tl_link_up_o;
    wire clk_usr_ps90_i;

    // serial interface for PCIe lanes
    wire [3: 0]refret_i;
    wire [3: 0]rext_i;
    wire [NO_LANES - 1: 0]link0_rxp_i;
    wire [NO_LANES - 1: 0]link0_rxn_i;
    wire [NO_LANES - 1: 0]link0_txp_o;
    wire [NO_LANES - 1: 0]link0_txn_o;
    wire link0_aux_clk_i;
    wire link0_perst_n_i;
    wire link0_rst_usr_n_i;
    wire link0_clk_usr_o;
    wire link0_int_normal_o;
    wire link0_int_critical_o;
    wire link0_user_aux_power_detected_i;
    wire link0_user_transactions_pending_i;
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

    assign link0_aux_clk_i = 1'b0;
    assign link0_user_aux_power_detected_i = 1'b0;
    assign link0_user_transactions_pending_i = 1'b0;
    assign link0_perst_n_i = rst_n;
    assign link0_rst_usr_n_i = rst_n;
    assign clk_usr_o = link0_clk_usr_o;

    // Indicates weather linkup is done
    assign linkup_done 	  = link0_pl_link_up_o & link0_dl_link_up_o & link0_tl_link_up_o;

    // reference clock for PCIe
    assign refclkp_i      = (pcie_clk_p                         );
    assign refclkn_i      = (pcie_clk_n                         );

    //Serial Data to and from PCIe
    assign link0_rxp_i    = (model_to_dut_err_p  [NO_LANES - 1 : 0]);
    assign link0_rxn_i    = (model_to_dut_err_n  [NO_LANES - 1 : 0]);

    assign rext_i 	      =  4'b0;
    assign refret_i       =  4'b0;

    assign dut_to_model_noerr_p[NO_LANES - 1 : 0] = link0_txp_o;
    assign dut_to_model_noerr_n[NO_LANES - 1 : 0] = link0_txn_o;

    // For gen : 3 clock is shifted 90 and for other gen(1,2) sys_clk is given //gen 3 & 2 given 90 clk
    assign clk_usr_ps90_i = (gen_no == 2'd2) ? clk_ps_90_i : sys_clk_i;

    assign dma_done_ref_des						= (dma_done);
    assign clk_usr_div2_i_ref_des				= (clk_usr_div2_i);
    assign m0_r_hrdata_i_ref_des				= (m0_r_hrdata_i); 
    assign m0_r_haddr_o_ref_des					= (m0_r_haddr_o);  
    assign m0_r_htrans_o_ref_des				= (m0_r_htrans_o);

    // PCIE IP Instantiation
    `include "../dut_inst.v"	
end

endgenerate

generate

if( USR_DAT_IF_MODE == 0 ) begin:DMA_NOT_ENABLE 

    // wire sys_clk;
    // wire clk_usr_div2;
    // wire clk_usr_ps;
    // wire vc_rx_ready_i;
    // wire vc_rx_valid_o;
    // wire [1:0]   vc_rx_sel_o;
    // wire [12:0]  vc_rx_cmd_data_o;
    // wire vc_rx_sop_o;
    // wire [DATA_WIDTH-1:0] vc_rx_data_o;          //DATA_WIDTH-1
    // wire [4*NO_LANES-1 :0] vc_rx_datap_o;        //DATA_WIDTH/8-1
    // wire vc_rx_eop_o;
    // wire vc_rx_err_ecrc_o;
    // wire [1:0]   vc_rx_f_o;
    // wire vc_tx_valid_i; 
    // wire vc_tx_eop_i;
    // wire vc_tx_eop_n_i;
    // wire vc_tx_sop_i;
    // wire [DATA_WIDTH-1:0] vc_tx_data_i;          //DATA_WIDTH-1
    // wire [4*NO_LANES-1 :0] vc_tx_datap_i;        //DATA_WIDTH/8-1
    // wire vc_tx_ready_o;

    // wire ucfg_valid;
    // wire ucfg_wr_rd;
    // wire [11:2]  ucfg_addr;
    // wire [31:0]  ucfg_wr_data;
    // wire [31:0]  ucfg_rd_data;
    // wire [1:0]   ucfg_rd_done;
    // wire ucfg_ready;

    // wire lmmi_clk;
    // wire lmmi_resetn;
    // wire [4:0]  lmmi_request;
    // wire lmmi_wr_rdn;
    // wire [31:0] lmmi_wdata;
    // wire [16:0] lmmi_offset;
    // wire [63:0] lmmi_rdata;
    // wire [4:0]  lmmi_rdata_valid;
    // wire [4:0]  lmmi_ready;
    // wire rst_with_pll_lock;

    // wire link0_pl_link_up;
    // wire link0_dl_link_up;
    // wire link0_tl_link_up;
    // wire linkup_done;
    // assign linkup_done    = link0_pl_link_up & link0_dl_link_up & link0_tl_link_up;

    //Primary clock for PLL and used for debounce logic also   
    reg tb_clk_125;

    initial
    begin
        tb_clk_125 = 0;
        forever
        begin
            #(4000);
            tb_clk_125 = ~tb_clk_125;
        end
    end
    
    wire clk_125;
    assign clk_125 = tb_clk_125;

    // wire  c_apb_pclk_i ; 
    // wire c_apb_preset_n_i ; 
    // wire [31:0] c_apb_paddr_i ; 
    // wire c_apb_psel_i ; 
    // wire c_apb_penable_i ; 
    // wire c_apb_pwrite_i ; 
    // wire [31:0] c_apb_pwdata_i ; 
    // wire  [31:0] c_apb_prdata_o ; 
    // wire  c_apb_pready_o ; 
    // wire  c_apb_pslverr_o ; 
    // wire [31:0]rd_data_counter;
    
    //Serial interface
    wire [NUM_LANES-1:0] link0_rxp_i;        
    wire [NUM_LANES-1:0] link0_rxn_i;       
    wire refclkp_i;          
    wire refclkn_i;          
    wire [NUM_LANES-1:0] link0_txp_o;        
    wire [NUM_LANES-1:0] link0_txn_o;        
    
    assign link0_rxp_i        = (model_to_dut_err_p  [NUM_LANES-1:0]);
    assign link0_rxn_i        = (model_to_dut_err_n  [NUM_LANES-1:0]);
    assign refclkp_i          = (pcie_clk_p);
    assign refclkn_i          = (pcie_clk_n);
    assign dut_to_model_noerr_p = link0_txp_o ;
    assign dut_to_model_noerr_n = link0_txn_o ;		 
    
    example_design_top #(
    .SIM(1),
    .WIDTH(NUM_LANES),
    .DATA_WIDTH(DATA_WIDTH) 
    ) ed_top_inst (
        .refclkp_i(refclkp_i),
        .refclkn_i(refclkn_i),
        .link0_rxp_i(link0_rxp_i),
        .link0_rxn_i(link0_rxn_i),
        .link0_txp_o(link0_txp_o),
        .link0_txn_o(link0_txn_o),
        .ed_perst_n_i(rst_n),
        .ed_usr_rst_n(rst_n),
        .clk_user(clk_125),
	.refret_i(4'b0),
	.rext_i(4'b0),
        .linkup_done()
    );

    // tb_non_dma_app #(
        // .SIM(1),
        // .DATA_WIDTH    (DATA_WIDTH), 
        // .NUM_OF_LANES  ( (NO_LANES == 3'd4)  ? 4 : ((NO_LANES == 3'd2) ? 2 : 1)),
        // .DATA_INTERFACE(DATA_INTERFACE),
        // .CSR_ADDRESS   (CSR_ADDRESS),
        // .SERIES_PATTERN(NON_DMA_SERIES_PATTERN),
        // .NUM_PACKETS   (NON_DMA_NUM_PACKETS)
    // )         
    // dut (
        // .usr_rst_n              (rst_n),
        // .perst_n_i              (rst_n),
        // .clk_125                (clk_125),                      
        // .sys_clk                (sys_clk),
        // .clk_usr_div2           (clk_usr_div2),
        // .clk_usr_ps             (clk_usr_ps),
        // .vc_rx_ready_i          (vc_rx_ready_i),
        // .vc_rx_valid_o          (vc_rx_valid_o),
        // .vc_rx_sel_o            (vc_rx_sel_o),
        // .vc_rx_cmd_data_o       (vc_rx_cmd_data_o),
        // .vc_rx_sop_o            (vc_rx_sop_o),
        // .vc_rx_data_o           (vc_rx_data_o),
        // .vc_rx_datap_o          (vc_rx_datap_o),
        // .vc_rx_eop_o            (vc_rx_eop_o),
        // .vc_rx_err_ecrc_o       (vc_rx_err_ecrc_o),
        // .vc_rx_f_o              (vc_rx_f_o),
        // .vc_tx_valid_i          (vc_tx_valid_i),
        // .vc_tx_eop_i            (vc_tx_eop_i),
        // .vc_tx_eop_n_i          (vc_tx_eop_n_i),
        // .vc_tx_sop_i            (vc_tx_sop_i),
        // .vc_tx_data_i           (vc_tx_data_i),
        // .vc_tx_datap_i          (vc_tx_datap_i),
        // .vc_tx_ready_o          (vc_tx_ready_o),

        // .ucfg_valid_i           (ucfg_valid),
        // .ucfg_wr_rd_n_i         (ucfg_wr_rd),
        // .ucfg_addr_i            (ucfg_addr),
        // .ucfg_wr_data_i         (ucfg_wr_data),
        // .ucfg_rd_data_o         (ucfg_rd_data),
        // .ucfg_rd_done_o         (ucfg_rd_done),
        // .ucfg_ready_o           (ucfg_ready),
        // .link0_tl_link_up       (link0_tl_link_up),

        // .c_apb_pclk_o           (c_apb_pclk_i),
        // .c_apb_preset_n_o       (c_apb_preset_n_i),
        // .c_apb_paddr_o          (c_apb_paddr_i),
        // .c_apb_psel_o           (c_apb_psel_i),
        // .c_apb_penable_o        (c_apb_penable_i),
        // .c_apb_pwrite_o         (c_apb_pwrite_i),
        // .c_apb_pwdata_o         (c_apb_pwdata_i),
        // .c_apb_prdata_i         (c_apb_prdata_o),
        // .c_apb_pready_i         (c_apb_pready_o),
        // .c_apb_pslverr_i        (c_apb_pslverr_o),

        // .usr_lmmi_clk_i         (lmmi_clk),
        // .usr_lmmi_resetn_i      (lmmi_resetn),
        // .lmmi_request           (lmmi_request),
        // .lmmi_wr_rdn            (lmmi_wr_rdn),
        // .lmmi_wdata             (lmmi_wdata),
        // .lmmi_offset            (lmmi_offset),
        // .lmmi_rdata             (lmmi_rdata),
        // .lmmi_rdata_valid       (lmmi_rdata_valid),
        // .lmmi_ready             (lmmi_ready),

        // .rst_usr_n_i            (rst_with_pll_lock),
        // .gen_no                 (gen_no),
        // .lane_no                (lane_no),
        // .write_data_check       (non_dma_write_data_check),
        // .rd_data_counter        (rd_data_counter),
        // .bar_0_address          (bar_0_address),
        // .bar_1_address          (bar_1_address)
    // );

    //PCIe IP signals


    // wire [3:0] refret_i;           
    // wire [3:0] rext_i;             
    // wire sys_clk_i;          
    // wire clk_usr_div2_i;     
    // wire clk_usr_ps90_i;     
    // wire link0_aux_clk_i;    
    // wire link0_perst_n_i;    
    // wire link0_rst_usr_n_i;  
    // wire link0_clk_usr_o;    
    // wire link0_pl_link_up_o;
    // wire link0_dl_link_up_o;
    // wire link0_tl_link_up_o;

    // wire link0_user_aux_power_detected_i;   
    // wire [0:0] link0_user_transactions_pending_i; 

    //rx and tx signals 
    // wire link0_rx_ready_i;   
    // wire link0_rx_valid_o;   
    // wire [1:0] link0_rx_sel_o;    
    // wire [12:0]link0_rx_cmd_data_o; 
    // wire link0_rx_sop_o;      
    // wire[DATA_WIDTH-1:0]link0_rx_data_o;     
    // wire[4*NO_LANES-1 :0]link0_rx_datap_o;    
    // wire link0_rx_eop_o;      
    // wire link0_rx_err_ecrc_o; 
    // wire [1:0]link0_rx_f_o;        
    // wire link0_tx_valid_i;    
    // wire link0_tx_eop_i;      
    // wire link0_tx_eop_n_i;    
    // wire link0_tx_sop_i;      
    // wire [DATA_WIDTH-1:0]link0_tx_data_i;     
    // wire [4*NO_LANES-1 :0]link0_tx_datap_i;    
    // wire link0_tx_ready_o; 

    // wire link0_rx_credit_init_i;   
    // wire [11:0]link0_rx_credit_nh_i;    
    // wire link0_rx_credit_nh_inf_i;
    // wire link0_rx_credit_return_i; 

    //UCFG interface 
    // wire ucfg_link_i;   
    // wire ucfg_valid_i;  
    // wire ucfg_wr_rd_n_i;
    // wire [11:2] ucfg_addr_i;   
    // wire [2:0]  ucfg_f_i;      
    // wire [3:0]  ucfg_wr_be_i;  
    // wire [31:0] ucfg_wr_data_i;
    // wire [31:0] ucfg_rd_data_o;
    // wire [1:0]  ucfg_rd_done_o;
    // wire ucfg_ready_o;

    //LMMI interface
    // wire usr_lmmi_clk_i;      
    // wire usr_lmmi_resetn_i;   
    // wire [4:0] usr_lmmi_request_i;  
    // wire usr_lmmi_wr_rdn_i;   
    // wire [31:0] usr_lmmi_wdata_i;    
    // wire [16:0] usr_lmmi_offset_i;   
    // wire [63:0] usr_lmmi_rdata_o;
    // wire [4:0] usr_lmmi_rdata_valid_o;
    // wire [4:0] usr_lmmi_ready_o;

    //For AHBL and AXI interfaces
    // wire m0_tready_i ; 
    // wire m0_tvalid_o ; 
    // wire m0_tlast_o ; 
    // wire [64*NO_LANES-1:0] m0_tdata_o ; 
    // wire [15:0] m0_tstrb_o ; 
    // wire [15:0] m0_tkeep_o ; 
    // wire [7:0] m0_tid_o ; 
    // wire [3:0] m0_tdest_o ; 
    // wire s0_tready_o ; 
    // wire s0_tvalid_i ; 
    // wire s0_tlast_i ; 
    // wire [64*NO_LANES-1:0] s0_tdata_i ; 
    // wire [DATA_WIDTH/8 - 1:0] s0_tstrb_i ; 
    // wire [DATA_WIDTH/8 - 1:0] s0_tkeep_i ; 
    // wire [7:0] s0_tid_i ; 
    // wire [3:0] s0_tdest_i ; 

    // wire m0_w_hready_i ; 
    // wire m0_w_hresp_i ; 
    // wire [64*NO_LANES-1:0] m0_w_hrdata_i ; 
    // wire  [31:0] m0_w_haddr_o ; 
    // wire  [2:0] m0_w_hburst_o ; 
    // wire  m0_w_hmastlock_o ; 
    // wire  [3:0] m0_w_hprot_o ; 
    // wire  [2:0] m0_w_hsize_o ; 
    // wire  [1:0] m0_w_htrans_o ; 
    // wire  m0_w_hwrite_o ; 
    // wire  [64*NO_LANES-1:0] m0_w_hwdata_o ; 
    // wire  s0_hready_o ; 
    // wire  s0_hresp_o ; 
    // wire  [64*NO_LANES-1:0] s0_hrdata_o ; 
    // wire [31:0] s0_haddr_i ; 
    // wire [2:0] s0_hburst_i ; 
    // wire s0_hmastlock_i ; 
    // wire [3:0] s0_hprot_i ; 
    // wire [2:0] s0_hsize_i ; 
    // wire [1:0] s0_htrans_i ; 
    // wire s0_hwrite_i ; 
    // wire s0_hreadyin_i ; 
    // wire s0_hsel_i ; 
    // wire [64*NO_LANES-1:0] s0_hwdata_i ; 

    // assign m0_w_hresp_i = 1'b0;
    // assign m0_w_hready_i = vc_rx_ready_i;
    // assign m0_tready_i = vc_rx_ready_i;


    // assign refret_i           = 4'b0;                                   
    // assign rext_i             = 4'b0;                                   
    // assign sys_clk_i          = sys_clk;                                        
    // assign clk_usr_div2_i     = clk_usr_div2;
    // assign clk_usr_ps90_i     = clk_usr_ps;
    // assign link0_aux_clk_i    = lmmi_clk;
    // assign link0_perst_n_i    = rst_with_pll_lock;                        
    // assign link0_rst_usr_n_i  = rst_with_pll_lock;
    //Outputs		  
    // assign clk_usr_o          = link0_clk_usr_o;    
    // assign link0_pl_link_up   = link0_pl_link_up_o; 
    // assign link0_dl_link_up   = link0_dl_link_up_o; 
    // assign link0_tl_link_up   = link0_tl_link_up_o;
 

    // assign link0_user_aux_power_detected_i   = 1'b0;
    // assign link0_user_transactions_pending_i = 1'b0;

    //rx and tx data 
    //Inputs
    //Outputs  
    // assign vc_tx_ready_o       =(DATA_INTERFACE == "TLP")?(link0_tx_ready_o):((DATA_INTERFACE == "AHB_LITE") ? (s0_hready_o):(s0_tready_o));
    // assign vc_rx_valid_o       = link0_rx_valid_o;    
    // assign vc_rx_sel_o         = link0_rx_sel_o;      
    // assign vc_rx_cmd_data_o    = link0_rx_cmd_data_o; 
    // assign vc_rx_sop_o         = link0_rx_sop_o;      
    // assign vc_rx_data_o        = link0_rx_data_o;     
    // assign vc_rx_datap_o       = link0_rx_datap_o;    
    // assign vc_rx_eop_o         = link0_rx_eop_o;      
    // assign vc_rx_err_ecrc_o    = link0_rx_err_ecrc_o; 
    // assign vc_rx_f_o           = link0_rx_f_o;        

    // assign link0_rx_credit_init_i   = 1'b1;
    // assign link0_rx_credit_nh_i     = 12'h0000;
    // assign link0_rx_credit_nh_inf_i = 1'b1;
    // assign link0_rx_credit_return_i = 1'b1;

    //UCFG interface
    //Inputs
    // assign ucfg_link_i         = 1'b0;
    // assign ucfg_valid_i        = ucfg_valid;
    // assign ucfg_wr_rd_n_i      = ucfg_wr_rd;
    // assign ucfg_addr_i         = ucfg_addr;
    // assign ucfg_f_i            = 1'b0;
    // assign ucfg_wr_be_i        = 1'b0;
    // assign ucfg_wr_data_i      = ucfg_wr_data;
    //Outputs  
    // assign ucfg_rd_data        = ucfg_rd_data_o;
    // assign ucfg_rd_done        = ucfg_rd_done_o;
    // assign ucfg_ready          = ucfg_ready_o;  

    //LMMI interface
    //Inputs
    // assign usr_lmmi_clk_i      = lmmi_clk;
    // assign usr_lmmi_resetn_i   = lmmi_resetn;
    // assign usr_lmmi_request_i  = lmmi_request;
    // assign usr_lmmi_wr_rdn_i   = lmmi_wr_rdn;
    // assign usr_lmmi_wdata_i    = lmmi_wdata;
    // assign usr_lmmi_offset_i   = lmmi_offset;
    //Outputs  
    // assign  lmmi_rdata         = usr_lmmi_rdata_o ;       
    // assign  lmmi_rdata_valid   = usr_lmmi_rdata_valid_o ; 
    // assign  lmmi_ready         = usr_lmmi_ready_o ; 

    // wire acjtag_mode_i;
    // wire use_refmux_i;
    // wire sd_pll_refclk_i;
    // wire diffioclksel_i;
    // wire [1:0]clksel_i;

    // assign acjtag_mode_i   =  1'b0;
    // assign use_refmux_i    =  1'b0;
    // assign sd_pll_refclk_i =  1'b0;
    // assign diffioclksel_i  =  1'b0;
    // assign clksel_i        =  2'b0;	

    // PCIE IP Instantiation
    //`include "../dut_inst.v"	

    // if(DATA_INTERFACE == "AXI4_STREAM")

    // begin : AXI4_STREAM

        // axi2tlp #(
            // .DATA_WIDTH(DATA_WIDTH)
        // )
        // axi_2_tlp(
            // .clk                   (clk_usr_div2),
            // .rst_n                 (rst_n),
            // .m0_tvalid_o           (m0_tvalid_o),
            // .m0_tdata_o            (m0_tdata_o),
            // .m0_tlast_o            (m0_tlast_o),
            // .m0_tready_i           (m0_tready_i),
            // .link0_rx_data_o       (link0_rx_data_o),
            // .link0_rx_valid_o      (link0_rx_valid_o),
            // .link0_rx_sop_o        (link0_rx_sop_o),
            // .link0_rx_eop_o        (link0_rx_eop_o)
        // );

        // tlp2axi #(
            // .DATA_WIDTH(DATA_WIDTH)
        // )
        // tlp_2_axi(
            // .clk                   (clk_usr_div2),
            // .rst_n                 (rst_n),
            // .vc_tx_valid_i         (vc_tx_valid_i),
            // .vc_tx_eop_i           (vc_tx_eop_i),
            // .vc_tx_data_i          (vc_tx_data_i),
            // .s0_tvalid_i           (s0_tvalid_i),
            // .s0_tlast_i            (s0_tlast_i),
            // .s0_tdata_i            (s0_tdata_i),
            // .s0_tstrb_i            (s0_tstrb_i),
            // .s0_tkeep_i            (s0_tkeep_i),
            // .s0_tid_i              (s0_tid_i),
            // .s0_tdest_i            (s0_tdest_i)
        // );
    // end

    // else if (DATA_INTERFACE == "AHB_LITE")

    // begin : AHB_LITE

        // ahbl2tlp #(
            // .DATA_WIDTH(DATA_WIDTH)
        // ) 
        // ahbl_2_tlp(
            // .clk                  (clk_usr_div2),
            // .rst_n                (rst_n),
            // .m0_w_htrans_o        (m0_w_htrans_o),
            // .m0_w_hwdata_o        (m0_w_hwdata_o),
            // .m0_w_hwrite_o        (m0_w_hwrite_o),
            // .m0_w_hready_i        (m0_w_hready_i),
            // .m0_w_haddr_o         (m0_w_haddr_o),
            // .link0_rx_data_o      (link0_rx_data_o),
            // .link0_rx_valid_o     (link0_rx_valid_o),
            // .link0_rx_sop_o       (link0_rx_sop_o),
            // .link0_rx_eop_o       (link0_rx_eop_o)
        // );

        // tlp2ahbl #(
            // .DATA_WIDTH(DATA_WIDTH),
            // .CSR_ADDRESS(CSR_ADDRESS)
        // )
        // tlp_2_ahbl(
            // .clk                  (clk_usr_div2),
            // .rst_n                (rst_n),
            // .s0_haddr_i           (s0_haddr_i),
            // .s0_hburst_i          (s0_hburst_i),
            // .s0_hmastlock_i       (s0_hmastlock_i),
            // .s0_hprot_i           (s0_hprot_i),
            // .s0_hsize_i           (s0_hsize_i),
            // .s0_htrans_i          (s0_htrans_i),
            // .s0_hwrite_i          (s0_hwrite_i),
            // .s0_hreadyin_i        (s0_hreadyin_i),
            // .s0_hsel_i            (s0_hsel_i),
            // .s0_hwdata_i          (s0_hwdata_i),
            // .vc_tx_valid_i        (vc_tx_valid_i),
            // .vc_tx_eop_i          (vc_tx_eop_i),
            // .vc_tx_sop_i          (vc_tx_sop_i),
            // .vc_tx_data_i         (vc_tx_data_i),
            // .rd_data_counter      (rd_data_counter)
        // );
    // end

end 

endgenerate


//------------------------------------------------------------------	
genvar l0;
generate for (l0=0; l0<NUM_LANES; l0=l0+1) begin : gen_err_inj

    assign dut_to_model_p[l0]     = (dut_to_model_noerr_p[l0] === 1'bz) ? 1'bz : dut_to_model_noerr_p[l0] ^ dut_to_model_err_inject[l0];
    assign model_to_dut_err_p[l0] = (model_to_dut_p[l0] === 1'bz)       ? 1'bz : model_to_dut_p[l0]       ^ model_to_dut_err_inject[l0];

    assign dut_to_model_n[l0]     = (dut_to_model_noerr_n[l0] === 1'bz) ? 1'bz : dut_to_model_noerr_n[l0] ^ dut_to_model_err_inject[l0];
    assign model_to_dut_err_n[l0] = (model_to_dut_n[l0] === 1'bz)       ? 1'bz : model_to_dut_n[l0]       ^ model_to_dut_err_inject[l0];

end
endgenerate



// -------------------------
// PCIe Bus Functional Model

// Emulates a Root Complex Device and includes tasks called by test_sequences

reg     bfm_rst_n = 1'b1;

always @(rst_n)
begin
    if (rst_n === 1'b0)
    begin
        bfm_rst_n = 1'b0;
    end
    else if (bfm_rst_n == 1'b0 & rst_n == 1'b1)
    begin
        bfm_rst_n = 1'b1;
    end
end

reg tb_clk_125;

initial
begin
    tb_clk_125 = 0;
    forever
    begin
        #(4000);
        tb_clk_125 = ~tb_clk_125;
    end
end
localparam  CMD_DATA_WIDTH  = 13;
// The value of BFM_DATA_WIDTH is based on how the BFMs are generated
localparam  BFM_DATA_WIDTH  = (BFM_NUM_LANES == 16) ? 128 :
(BFM_NUM_LANES ==  8) ?  64 : 32;

wire    [NUM_LINKS_TB-1:0]          vc0_tx_sop;
wire [NUM_LINKS_TB-1:0]             vc0_tx_eop;
wire [NUM_LINKS_TB-1:0]             vc0_tx_eop_n;
wire [NUM_LINKS_TB-1:0]             vc0_tx_en;
wire [BFM_DATA_WIDTH-1:0]           vc0_tx_data     [NUM_LINKS_TB-1:0];
reg [NUM_LINKS_TB-1:0]              vc0_tx_busy;
wire [NUM_LINKS_TB-1:0]             vc0_tx_valid;
wire [NUM_LINKS_TB-1:0]             vc0_tx_ready;

wire                                vc_tx_sop;
wire                                vc_tx_eop;
wire                                vc_tx_eop_n;
wire [BFM_DATA_WIDTH-1:0]           vc_tx_data;
wire [3:0]                          vc_tx_link;
wire                                vc_tx_valid;
wire                                vc_tx_ready;

wire [1:0]                          vc0_rx_sel;
wire [CMD_DATA_WIDTH-1:0]           vc0_rx_cmd_data;
wire                                vc0_rx_err_ecrc;
wire                                vc0_rx_sop;
wire                                vc0_rx_eop;
wire [NUM_LINKS_TB-1:0]             vc0_rx_en;
wire [BFM_DATA_WIDTH-1:0]           vc0_rx_data;
wire                                vc_rx_en;

wire [NUM_LINKS_TB-1:0]             msg_en;
wire [NUM_LINKS_TB*160-1:0]         msg_data;
wire [NUM_LINKS_TB-1:0]             mgmt_inta;
wire [NUM_LINKS_TB-1:0]             mgmt_intb;
wire [NUM_LINKS_TB-1:0]             mgmt_intc;
wire [NUM_LINKS_TB-1:0]             mgmt_intd;
wire [NUM_LINKS_TB-1:0]             is_rp;
wire [NUM_LINKS_TB-1:0]             msi_vec_mask_capable;
wire [NUM_LINKS_TB*32-1:0]          msi_mask;
wire [NUM_LINKS_TB*32-1:0]          msi_pending;
wire [NUM_LINKS_TB*3-1:0]           msi_mult_msg_en;
wire [NUM_LINKS_TB*64-1:0]          msi_addr;
wire [NUM_LINKS_TB*16-1:0]          msi_data;
wire [NUM_LINKS_TB-1:0]             msi_en;
wire [NUM_LINKS_TB-1:0]             msix_en;
wire [NUM_LINKS_TB-1:0]             mgmt_interrupt_o;
wire [NUM_LINKS_TB-1:0]             mgmt_interrupt_legacy;
wire [NUM_LINKS_TB*2-1:0]           mgmt_link_speed;
wire [NUM_LINKS_TB*6-1:0]           mgmt_neg_link_width;
wire [NUM_LINKS_TB*3-1:0]           mgmt_max_payload_size;
wire [NUM_LINKS_TB*16-1:0]          mgmt_cfg_id;

wire clk_usr_i_125MHz;
wire clk_125;
wire usr_rst_n;
wire lock_ip;

assign clk_125 = tb_clk_125;
assign usr_rst_n = rst_n;

generate
   if (LINK0_FTL_INITIAL_TARGET_LINK_SPEED == 1) begin: PLL_125
      pll_125 pll_125_inst (
         .clki_i(clk_125),
         .rstn_i(usr_rst_n),
         .clkop_o(clk_usr_i_125MHz),
         .lock_o(lock_ip)
      );
   end
   else begin: PLL_62P5
      pll_62p5 pll_62p5_inst (
         .clki_i(clk_125),
         .rstn_i(usr_rst_n),
         .clkop_o(clk_usr_i_125MHz),
         .lock_o(lock_ip)
      );
   end
endgenerate

/*     axi4_master_bfm #
    (
	.DMA_AXI_ID_WIDTH               (DMA_AXI_ID_WIDTH           ),
	.AXI_WIDTH                      (AXI_WIDTH                  )
    )
    bridge_axi4_master_bfm
    (
	.axi_awid_o		(s0_aximm_awid_i),
	.axi_awaddr_o		(s0_aximm_awaddr_i),
	.axi_awlen_o		(s0_aximm_awlen_i),
	.axi_awsize_o		(s0_aximm_awsize_i),
	.axi_awburst_o		(s0_aximm_awburst_i),
	.axi_awvalid_o		(s0_aximm_awvalid_i),
	.axi_awready_i		(s0_aximm_awready_o),
	.axi_wdata_o		(s0_aximm_wdata_i),
	.axi_wstrb_o		(s0_aximm_wstrb_i),
	.axi_wlast_o		(s0_aximm_wlast_i),
	.axi_wvalid_o		(s0_aximm_wvalid_i),
	.axi_wready_i		(s0_aximm_wready_o),
	.axi_bid_i		(s0_aximm_bid_o),
	.axi_bresp_i		(s0_aximm_bresp_o),
	.axi_bvalid_i		(s0_aximm_bvalid_o),
	.axi_bready_o		(s0_aximm_bready_i),
	.axi_arid_o		(s0_aximm_arid_i),
	.axi_araddr_o		(s0_aximm_araddr_i),
	.axi_arlen_o		(s0_aximm_arlen_i),
	.axi_arsize_o		(s0_aximm_arsize_i),
	.axi_arburst_o		(s0_aximm_arburst_i),
	.axi_arvalid_o		(s0_aximm_arvalid_i),
	.axi_arready_i		(s0_aximm_arready_o),
	.axi_rid_i		(s0_aximm_rid_o),
	.axi_rdata_i		(s0_aximm_rdata_o),
	.axi_rresp_i		(s0_aximm_rresp_o),
	.axi_rlast_i		(s0_aximm_rlast_o),
	.axi_rvalid_i		(s0_aximm_rvalid_o),
	.axi_rready_o		(s0_aximm_rready_i),
	.axi_aclk		(clk_usr_i_125MHz),
	.axi_aresetn		(usr_rst_n)

    );*/

genvar                              p;
generate for (p=0; p<NUM_LINKS_TB; p=p+1) begin : gen_pcie_bfm

    pcie_bfm #
    (
        .HALF_PERIOD_5G                 (HALF_PERIOD_5G             ),
        .HALF_PERIOD_2G5                (HALF_PERIOD_2G5            ),
        .RCB_BYTES                      (BFM_RCB_BYTES              ),
        .BFM_PHY_LANE_MASK              (BFM_PHY_LANE_MASK          ),
        .BFM_MEM_SIZE_BITS              (BFM_MEM_SIZE_BITS          )
//	.DMA_AXI_ID_WIDTH               (DMA_AXI_ID_WIDTH           ),
//	.AXI_WIDTH                      (AXI_WIDTH                  )
    )
    pcie_bfm
    (
        .rst_n                 (bfm_rst_n                              ),
        .core_rst_n             (core_rst_n                             ),
        .core_clk               (core_clk                               ),

        .mgmt_training_mode     (1'b1                                   ), // When DUT is not the RC, then set the BFM to be the RC

        .rx_p                   (dut_to_model_p_brev[BFM_NUM_LANES-1:0] ),
        .rx_n                   (dut_to_model_n_brev[BFM_NUM_LANES-1:0] ),

        .vc0_tx_sop             (vc0_tx_sop             [p]             ),
        .vc0_tx_eop             (vc0_tx_eop             [p]             ),
        .vc0_tx_eop_n           (vc0_tx_eop_n           [p]             ),
        .vc0_tx_en              (vc0_tx_en              [p]             ),
        .vc0_tx_data            (vc0_tx_data            [p]             ),
        .vc0_rx_sel             (vc0_rx_sel                             ),
        .vc0_rx_cmd_data        (vc0_rx_cmd_data                        ),
        .vc0_rx_err_ecrc        (vc0_rx_err_ecrc                        ),
        .vc0_rx_sop             (vc0_rx_sop                             ),
        .vc0_rx_eop             (vc0_rx_eop                             ),
        .vc0_rx_en              (vc0_rx_en              [p]             ),
        .vc0_rx_data            (vc0_rx_data                            ),
        .msg_en                 (msg_en                 [p]                     ),
        .msg_data               (msg_data               [(p*160)+159:(p*160)]   ),
        .inta                   (mgmt_inta              [p]                     ),
        .intb                   (mgmt_intb              [p]                     ),
        .intc                   (mgmt_intc              [p]                     ),
        .intd                   (mgmt_intd              [p]                     ),
        .is_rp                  (is_rp                  [p]                     ),
        .msi_vec_mask_capable   (msi_vec_mask_capable   [p]                     ),
        .msi_mask               (msi_mask               [(p*32)+31:(p*32)]      ),
        .msi_pending            (msi_pending            [(p*32)+31:(p*32)]      ),
        .msi_mult_msg_en        (msi_mult_msg_en        [(p*3)+2:(p*3)]         ),
        .msi_addr               (msi_addr               [(p*64)+63:(p*64)]      ),
        .msi_data               (msi_data               [(p*16)+15:(p*16)]      ),
        .msi_en                 (msi_en                 [p]                     ),
        .msix_en                (msix_en                [p]                     ),
        .mgmt_interrupt_o       (mgmt_interrupt_o       [p]                     ),
        .mgmt_interrupt_legacy  (mgmt_interrupt_legacy  [p]                     ),
        .link_speed             (mgmt_link_speed        [(p*2)+1:(p*2)]         ),
        .neg_link_width         (mgmt_neg_link_width    [(p*6)+5:(p*6)]         ),
        .mgmt_max_payload_size  (mgmt_max_payload_size  [(p*3)+2:(p*3)]         ),
        .mgmt_cfg_id            (mgmt_cfg_id            [(p*16)+15:(p*16)]      )
/*	.axi_awid_o		(s0_aximm_awid_i),
	.axi_awaddr_o		(s0_aximm_awaddr_i),
	.axi_awlen_o		(s0_aximm_awlen_i),
	.axi_awsize_o		(s0_aximm_awsize_i),
	.axi_awburst_o		(s0_aximm_awburst_i),
	.axi_awvalid_o		(s0_aximm_awvalid_i),
	.axi_awready_i		(s0_aximm_awready_o),
	.axi_wdata_o		(s0_aximm_wdata_i),
	.axi_wstrb_o		(s0_aximm_wstrb_i),
	.axi_wlast_o		(s0_aximm_wlast_i),
	.axi_wvalid_o		(s0_aximm_wvalid_i),
	.axi_wready_i		(s0_aximm_wready_o),
	.axi_bid_i		(s0_aximm_bid_o),
	.axi_bresp_i		(s0_aximm_bresp_o),
	.axi_bvalid_i		(s0_aximm_bvalid_o),
	.axi_bready_o		(s0_aximm_bready_i),
	.axi_arid_o		(s0_aximm_arid_i),
	.axi_araddr_o		(s0_aximm_araddr_i),
	.axi_arlen_o		(s0_aximm_arlen_i),
	.axi_arsize_o		(s0_aximm_arsize_i),
	.axi_arburst_o		(s0_aximm_arburst_i),
	.axi_arvalid_o		(s0_aximm_arvalid_i),
	.axi_arready_i		(s0_aximm_arready_o),
	.axi_rid_i		(s0_aximm_rid_o),
	.axi_rdata_i		(s0_aximm_rdata_o),
	.axi_rresp_i		(s0_aximm_rresp_o),
	.axi_rlast_i		(s0_aximm_rlast_o),
	.axi_rvalid_i		(s0_aximm_rvalid_o),
	.axi_rready_o		(s0_aximm_rready_i),
	.axi_aclk		(clk_usr_i_125MHz),
	.axi_aresetn		(usr_rst_n)
*/
    );

    always @(posedge core_clk or negedge core_rst_n)
    begin
        if (core_rst_n == 1'b0)
            vc0_tx_busy[p] <= 1'b0;
        else
        begin
            if (vc0_tx_sop[p] & ~vc0_tx_eop[p] & vc0_tx_en[p])
                vc0_tx_busy[p] <= 1'b1;
            else if (vc0_tx_eop[p] & vc0_tx_en[p])
                vc0_tx_busy[p] <= 1'b0;
        end
    end

    assign vc0_tx_valid[p] = vc0_tx_sop[p]   | vc0_tx_busy[p];
    assign vc0_tx_en[p]    = vc0_tx_valid[p] & vc0_tx_ready[p];
end
endgenerate

assign vc_tx_valid      = vc0_tx_valid  [0];
assign vc0_tx_ready[0]  = vc_tx_ready;
assign vc_tx_sop        = vc0_tx_sop    [0];
assign vc_tx_eop        = vc0_tx_eop    [0];
assign vc_tx_eop_n      = vc0_tx_eop_n  [0];
assign vc_tx_data       = vc0_tx_data   [0];
assign vc_tx_link       = 4'h0;

assign vc_rx_en         = vc0_rx_en     [0];


bfm_pcie_model #(

    .SIM_EL_IDLE_TYPE               (SIM_EL_IDLE_TYPE           ),
    .BFM_PHY_LANE_MASK              (BFM_PHY_LANE_MASK          ),
    .RX_IDLE_ACTIVE_8G_ONLY_EIE     (RX_IDLE_ACTIVE_8G_ONLY_EIE ),
    .RX_IDLE_ACTIVE_5G_ONLY_EIE     (RX_IDLE_ACTIVE_5G_ONLY_EIE )

) pcie_model (

    .rst_n                 (bfm_rst_n                              ),
    .core_rst_n             (core_rst_n                             ),
    .core_clk               (core_clk                               ),
    .clkreq_n               (clkreq_n[0]                            ),
    .tx_p                   (temp_model_to_dut_p[BFM_NUM_LANES-1:0] ),
    .tx_n                   (temp_model_to_dut_n[BFM_NUM_LANES-1:0] ),

    .rx_p                   (dut_to_model_p_brev[BFM_NUM_LANES-1:0] ),
    .rx_n                   (dut_to_model_n_brev[BFM_NUM_LANES-1:0] ),

    .pl_link_up             (pl_link_up                             ),
    .dl_link_up             (dl_link_up                             ),

    .vc0_tx_sop             (vc_tx_sop                              ),
    .vc0_tx_eop             (vc_tx_eop                              ),
    .vc0_tx_eop_n           (vc_tx_eop_n                            ),
    .vc0_tx_en              (vc_tx_ready                            ),
    .vc0_tx_data            (vc_tx_data                             ),
    .vc0_rx_sel             (vc0_rx_sel                             ),
    .vc0_rx_cmd_data        (vc0_rx_cmd_data                        ),
    .vc0_rx_err_ecrc        (vc0_rx_err_ecrc                        ),
    .vc0_rx_sop             (vc0_rx_sop                             ),
    .vc0_rx_eop             (vc0_rx_eop                             ),
    .vc0_rx_en              (vc_rx_en                               ),
    .vc0_rx_data            (vc0_rx_data                            ),
    .msg_en                 (msg_en                                 ),
    .msg_data               (msg_data                               ),
    .mgmt_inta              (mgmt_inta                              ),
    .mgmt_intb              (mgmt_intb                              ),
    .mgmt_intc              (mgmt_intc                              ),
    .mgmt_intd              (mgmt_intd                              ),
    .is_rp                  (is_rp                                  ),
    .msi_vec_mask_capable   (msi_vec_mask_capable                   ),
    .msi_mask               (msi_mask                               ),
    .msi_pending            (msi_pending                            ),
    .msi_mult_msg_en        (msi_mult_msg_en                        ),
    .msi_addr               (msi_addr                               ),
    .msi_data               (msi_data                               ),
    .msi_en                 (msi_en                                 ),
    .msix_en                (msix_en                                ),
    .mgmt_interrupt_o       (mgmt_interrupt_o                       ),
    .mgmt_interrupt_legacy  (mgmt_interrupt_legacy                  ),
    .mgmt_link_speed        (mgmt_link_speed                        ),
    .mgmt_neg_link_width    (mgmt_neg_link_width                    ),
    .mgmt_max_payload_size  (mgmt_max_payload_size                  ),
    .mgmt_cfg_id            (mgmt_cfg_id                            )
);



// Tie unused lanes inactive
genvar                              i;
generate
if (BFM_NUM_LANES < NUM_LANES) begin
    for (i=BFM_NUM_LANES; i<NUM_LANES; i=i+1) begin
        assign temp_model_to_dut_p[i] = 1'bz;
        assign temp_model_to_dut_n[i] = 1'bz;
    end
end
endgenerate

genvar j;
generate
if (NUM_LANES < BFM_NUM_LANES) begin
    for (j=NUM_LANES; j<BFM_NUM_LANES; j=j+1) begin
        assign dut_to_model_p[j] = 1'bz;
        assign dut_to_model_n[j] = 1'bz;
    end
end
endgenerate

//----------------------------------------------
//ref_design_ts module instantiation
//----------------------------------------------

ref_design_ts #(
    //DMA parameters
    .NO_LANES		    (NO_LANES),
    .DMA_TESTCASE_TYPE	    (DMA_TESTCASE_TYPE),
    .DMA_NUM_OF_DESCRIPTORS (DMA_NUM_OF_DESCRIPTORS),								
    .DMA_BYTES_IN_DESCRIPTOR(DMA_BYTES_IN_DESCRIPTOR),
    .DMA_PATTERN            (DMA_PATTERN),
    .NUM_WRITE_OP           (NUM_OP),
    .NUM_READ_OP	    (NUM_OP),
    .DMA_FIXED_DATA         (DMA_FIXED_DATA),
    //Non DMA parameters
    .NON_DMA_TESTCASE_TYPE  (NON_DMA_TESTCASE_TYPE  ),
    .NON_DMA_SINGLE_BAR_SEL (NON_DMA_SINGLE_BAR_SEL ),
    .NON_DMA_SERIES_PATTERN (NON_DMA_SERIES_PATTERN ),
    .NON_DMA_FIXED_DATA     (NON_DMA_FIXED_DATA     ),
    .NON_DMA_NUM_DWORD      (NON_DMA_MAX_SUPPORTED_SIZE),
    .NON_DMA_NUM_PACKETS    (NON_DMA_NUM_PACKETS    ),
    .NUM_WRITES             (NUM_WRITES             ),
    .NUM_READS              (NUM_READS              ),
    //Parameter to choose design
    .EN_DMA_SUPPORT         (EN_DMA_SUPPORT),
    .USR_DAT_IF_MODE        (USR_DAT_IF_MODE),
    //PCIe AXI DMA parameters
    .EN_AXI_DMA             (EN_AXI_DMA),
    .NUM_H2F_CHAN           (NUM_H2F_CHAN),
    .NUM_F2H_CHAN           (NUM_F2H_CHAN),
    .USR_DAT_IF_TYPE        (USR_DAT_IF_TYPE),
    .FULL_BRIDGE_EN         (FULL_BRIDGE_EN),
    .DMA_BYPASS_EN          (DMA_BYPASS_EN),
    .DMA_BYPASS_IF_TYPE     (DMA_BYPASS_IF_TYPE),
    .DMA_INTERRUPT          (DMA_INTERRUPT),
    .DMA_BYPASS_7S_AND_LED_DEMO(DMA_BYPASS_7S_AND_LED_DEMO),
    .IMAGE_PATTERN          (IMAGE_PATTERN),
    .PER_BYTE_INCR          (PER_BYTE_INCR),
    //Others
    .BFM_MEM_SIZE_BITS      (BFM_MEM_SIZE_BITS)
)ref_design_ts(
    .rst_n                      (rst_n                          ),
    .clk                        (core_clk                       ),                                   
    .apb_rst_n_hold             (apb_rst_n_hold                 ),
    .pl_link_up                 (pl_link_up                     ),
    .dl_link_up                 (dl_link_up                     ),                                  
    .test_done                  (test_done                      ),
    .dma_compl		        (dma_done_ref_des               ),
    .pcie_clk	 	        (clk_usr_div2_i_ref_des         ),
    .m_r_hrdata_i	        (m0_r_hrdata_i_ref_des          ),
    .m_r_haddr_o 	        (m0_r_haddr_o_ref_des           ),
    .m_r_htrans_o               (m0_r_htrans_o_ref_des          ),
    .non_dma_write_data_check   (non_dma_write_data_check       ),
    .bar_0_address              (bar_0_address                  ),
    .bar_1_address              (bar_1_address                  ),
    .mgmt_link_speed            (mgmt_link_speed                ),
    .mgmt_neg_link_width        (mgmt_neg_link_width            ),
    .gen_no			(gen_no                         ),
    .lane_no                    (mgmt_lane_no                   )
);

assign proc_wr_en   = 1'b0;
assign proc_rd_en   = 1'b0;
assign proc_addr    = 16'b0;
assign proc_wr_data = 32'b0;
assign i2c_reset_n  = 1'b0;

// ---------------------------------------------------
// APB BFM (Test Core APB CSR Register Implementation)

apb4_master_bfm #
(
    .APB_CLK_PERIOD(10000),
    .APB_ADDR_WIDTH  (APB_ADDR_WIDTH ),
    .APB_DATA_WIDTH  (APB_DATA_WIDTH ),
    .APB_STRB_WIDTH  (APB_STRB_WIDTH ),
    .APB_PSEL_WIDTH  (APB_PSEL_WIDTH ),
    .APB_PCLK_MASTER (1),
    .APB_PSEL_SELECT (0)
) apb4_master_bfm (
    .apb_pclk       (apb_pclk       ), // Positive edge clock
    .apb_preset_n   (apb_preset_n   ), // Active-low asynchronous assert, apb_pclk synchronous de-assert reset
    .apb_paddr      (apb_paddr_i    ), // APB DATA_WIDTH-bit word address
    .apb_psel       (apb_psel_i     ), // Device Select
    .apb_penable    (apb_penable_i  ), // Asserted during access phase; remains asserted until apb_pready is asserted
    .apb_pwrite     (apb_pwrite_i   ), // Write/Read indicator
    .apb_pwdata     (apb_pwdata_i   ), // Write Data
    .apb_pstrb      (apb_pstrb_i    ), // Write Byte Enables
    .apb_prdata     (apb_prdata     ), // Read Data
    .apb_pready     (apb_pready_i   ), // Slave ready
    .apb_pslverr    (apb_pslverr_i  )  // Slave error
);
assign apb_paddr     = apb_paddr_i;
assign apb_psel      = apb_psel_i;
assign apb_penable   = apb_penable_i;
assign apb_pwrite    = apb_pwrite_i;
assign apb_pwdata    = apb_pwdata_i;
assign apb_pstrb     = apb_pstrb_i;
assign apb_pready_i  = rst_n;
assign apb_pslverr_i = apb_pslverr;


// --------------------------------------------------------------
// Watchdog timer. Stop simulation if no activity for a long time

integer wdt;

always @(posedge clk100_reg)
     begin
        if (pl_link_up === 1'b0)
          wdt <= 0;
        else if (activity_observed === 1'b1)
          wdt <= 0;
        else
          wdt <= wdt + 1;
     end

   wire    all_test_done;
   assign all_test_done = &test_done;
   always @(all_test_done)
     begin
        if (all_test_done == 1'b1)
          begin
             if (FINISH_STOP_N) $finish; else $stop;
          end
     end

   always @(posedge clk100_reg)
     begin
        if (ACTIVITY_WDT_TIMEOUT != 0 && wdt === ACTIVITY_WDT_TIMEOUT)
          begin
             $display("%0t ERROR: %m: Activity Watchdog Timer expired. No activity noticed for %0d uS. Exiting", $time, (ACTIVITY_WDT_TIMEOUT/100));
             inc_errors;
             report_status;
             //if (STOP_ON_ERR) if (FINISH_STOP_N) $finish; else $stop;
             // This fatal error should always end the sim., even if STOP_ON_ERR==0 to log other failures.
             if (FINISH_STOP_N) $finish; else $stop;
          end
     end


   // Halt test if the simulation time reaches absolute limit
   always @(posedge clk100_reg)
     begin
        if (ABSOLUTE_WDT_TIMEOUT != 0 && $time > (ABSOLUTE_WDT_TIMEOUT * 1000000))
          begin
             $display("%0t ERROR: %m: Watchdog timer expired. Reached maximum %0d mS simulation time allowed.", $time, ABSOLUTE_WDT_TIMEOUT/1000);
             inc_errors;
             report_status;
             // This fatal error should always end the sim., even if STOP_ON_ERR==0 to log other failures.
             //if (STOP_ON_ERR)
             if (FINISH_STOP_N) $finish; else $stop;
          end
     end

   task inc_errors;
      begin
         ERROR_COUNT = ERROR_COUNT + 1;
         if (STOP_ON_ERR) begin
            report_status;
            if (FINISH_STOP_N)
              $finish;
            else
              $stop;
         end
      end
   endtask

   task report_status;
      begin
         if (ERROR_COUNT == 0)
           $display("%0t INFO: %m: SIMULATION STATUS: SIMULATION PASSED", $time);
         else
           $display("%0t INFO: %m: SIMULATION STATUS: ********* %d ERRORS DETECTED **********", $time, ERROR_COUNT);
      end
   endtask




endmodule
