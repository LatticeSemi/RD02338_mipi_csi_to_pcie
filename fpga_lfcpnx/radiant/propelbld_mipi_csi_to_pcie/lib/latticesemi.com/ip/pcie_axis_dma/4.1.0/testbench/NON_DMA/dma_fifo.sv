module dma_fifo #(
   parameter FIFO_WIDTH = 128,
   parameter FIFO_DEPTH = 256,
   parameter PIPESTG_EN = 1'b1,
   parameter FIFO_REGMODE = "noreg", // "reg", "noreg"
   parameter FIFO_IMPL = "EBR", // "LUT", "EBR", "HARD_IP"
   parameter AFULL_FLAG = 2,
   parameter AEMPTY_FLAG = 4,
   parameter DEVICE_FAMILY = "LFCPNX"
)
(
   // Clock and reset
   input logic clk_i,
   input logic rst_n_i,
   // Inlet
   input logic wr_en_i,
   input logic [FIFO_WIDTH-1:0] data_i,
   output logic almost_full_o,
   output logic full_o,
   // Outlet
   output logic [FIFO_WIDTH-1:0] data_o,
   output logic valid_o,
   input logic ready_i
);

   logic rd_en;
   logic empty;
   logic [FIFO_WIDTH-1:0] data_tmp;

   // /home/rel/$RADIANT_VERSION/rtf/ip/pmi/pmi_fifo.v
   // Parameter Definition
   //Name                        Value                             Default
   /*
   ------------------------------------------------------------------------------
   pmi_data_width              <integer>                                 8
   pmi_data_depth              <integer>                               256
   pmi_full_flag               <integer>                               256
   pmi_empty_flag              <integer>                                 0
   pmi_almost_full_flag        <integer>                               252
   pmi_almost_empty_flag       <integer>                                 4
   pmi_regmode               "reg"|"noreg"                           "reg"
   pmi_family            "iCE40UP" | "LIFCL"                      "common"
   module_type                 <string>                         "pmi_fifo"
   pmi_implementation    "LUT" | "EBR" | "HARD_IP"               "HARD_IP"
   ----------------------------------------------------------------------------*/
   pmi_fifo #(
      .pmi_family             (DEVICE_FAMILY),
      .pmi_data_width         (FIFO_WIDTH),
      .pmi_data_depth         (FIFO_DEPTH),
      .pmi_full_flag          (FIFO_DEPTH),
      .pmi_empty_flag         (0),
      .pmi_almost_full_flag   (AFULL_FLAG),
      .pmi_almost_empty_flag  (AEMPTY_FLAG),
      .pmi_regmode            (FIFO_REGMODE),
      .pmi_implementation     (FIFO_IMPL),
      .module_type            ("pmi_fifo")
   ) pmi_fifo_inst (
      .Reset                  (~rst_n_i),
      .Clock                  (clk_i),
      .WrEn                   (wr_en_i),
      .RdEn                   (rd_en),
      .Data                   (data_i),
      .Q                      (data_tmp),
      .Empty                  (empty),
      .Full                   (full_o),
      .AlmostFull             (almost_full_o),
      .AlmostEmpty            ()
   );

   depth2_fifo_new #(
      .WIDTH(FIFO_WIDTH),
      .PIPESTG_EN(PIPESTG_EN)
   )
   fifo_rd_en_manager
   (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .data_i(data_tmp),
      .empty_i(empty),
      .rd_en_o(rd_en),
      .data_o(data_o),
      .valid_o(valid_o),
      .ready_i(ready_i)
   );

endmodule
