module depth2_fifo_new #(
   parameter WIDTH = 128,
   parameter PIPESTG_EN = 1'b1
)
(
   input logic clk_i, 
   input logic rst_n_i,
   input logic [WIDTH-1:0] data_i,
   input logic  empty_i,
   output logic rd_en_o,
   output logic [WIDTH-1:0] data_o,
   output logic valid_o,
   input logic ready_i
);

   logic avail;
   logic ready_int;

   dma_rd_en_manager
   rd_en_mmgr (
      .clk_i(clk_i),
      .rst_n_i(rst_n_i),
      .fifo_empty_i(empty_i),
      .source_rd_en_i(ready_int),
      .avail_o(avail),
      .rd_en_o(rd_en_o)
   );

   generate
      if (PIPESTG_EN == 1'b1) begin: PIPESTG
         shreg_pipe_2stg #(
            .WIDTH(WIDTH)
         )
         pipestg_inst
         (
            .clk_i(clk_i),
            .rst_n_i(rst_n_i),
            .data_i(data_i),
            .valid_i(avail),
            .ready_o(ready_int),
            .data_o(data_o),
            .valid_o(valid_o),
            .ready_i(ready_i)
         );
      end
      else begin
         assign data_o = data_i;
         assign valid_o = avail;
         assign ready_int = ready_i;
      end
   endgenerate

endmodule
