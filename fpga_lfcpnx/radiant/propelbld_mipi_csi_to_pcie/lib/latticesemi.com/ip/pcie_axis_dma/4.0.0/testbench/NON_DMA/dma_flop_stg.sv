module dma_flop_stg #(
   parameter RESETTABLE = 1'b1,
   parameter WIDTH = 1
)
(
   input logic clk_i,
   input logic rst_n_i,
   input logic [WIDTH-1:0] data_i,
   output logic [WIDTH-1:0] data_o
);

   generate
      if (RESETTABLE) begin : RST_ASYNC
         always_ff @(posedge clk_i or negedge rst_n_i) begin
            if (~rst_n_i) begin
               data_o <= '0;
            end
            else begin
               data_o <= data_i;
            end
         end
      end
      else begin : NO_RST
         always_ff @(posedge clk_i) begin
            data_o <= data_i;
         end
      end
   endgenerate

endmodule

