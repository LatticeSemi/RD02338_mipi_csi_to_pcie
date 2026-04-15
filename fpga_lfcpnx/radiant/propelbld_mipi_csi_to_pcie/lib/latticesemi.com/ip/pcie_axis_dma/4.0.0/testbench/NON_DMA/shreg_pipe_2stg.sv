module shreg_pipe_2stg #(
   parameter WIDTH = 128
)
(
   input logic clk_i, 
   input logic rst_n_i,
   input logic [WIDTH-1:0] data_i,
   input logic valid_i,
   output logic ready_o,
   output logic [WIDTH-1:0] data_o,
   output logic valid_o,
   input logic ready_i
);

   logic lptr_incr;
   logic [1:0] lptr, lptr_nxt; /* synthesis syn_preserve=1 */
   logic uptr_incr;
   logic [1:0] uptr, uptr_nxt; /* synthesis syn_preserve=1 */
   logic [1:0] lptr_wrap, lptr_wrap_add, lptr_wrap_nxt;
   logic [1:0] uptr_wrap, uptr_wrap_add, uptr_wrap_nxt;
   logic [1:0][WIDTH-1:0] storage, storage_nxt;
   logic [1:0] storage_capture;
   //logic [1:0] lptr_plus1, uptr_plus1;
   //logic [1:0] diff, diff_norm, diff_wr, diff_rd;
   //logic almost_full, almost_full_nxt;
   //logic not_almost_full_nxt;
   logic ready_nxt;

   // Load Pointer

   assign lptr_incr = valid_i & ready_o;

   generate
      for (genvar i = 0; i < 2; i++) begin
         assign lptr_nxt[i] = lptr_incr ? ~lptr[i] : lptr[i];
      end
   endgenerate
   assign lptr_wrap_add = (lptr_wrap + 'b1);
   assign lptr_wrap_nxt = lptr_incr ? lptr_wrap_add : lptr_wrap;

   // Unload Pointer

   assign uptr_incr = valid_o & ready_i;

   generate
      for (genvar i = 0; i < 2; i++) begin
         assign uptr_nxt[i] = uptr_incr ? ~uptr[i] : uptr[i];
      end
   endgenerate
   assign uptr_wrap_add = (uptr_wrap + 'b1);
   assign uptr_wrap_nxt = uptr_incr ? uptr_wrap_add : uptr_wrap;

   // Storage
   assign storage_capture[0] = lptr_incr & ~lptr[0];
   assign storage_capture[1] = lptr_incr & lptr[1];

   assign storage_nxt[0] = storage_capture[0] ? data_i : storage[0];
   assign storage_nxt[1] = storage_capture[1] ? data_i : storage[1];

   // ready
   assign ready_nxt = ~((lptr_wrap_nxt[1] != uptr_wrap_nxt[1]) & (lptr_wrap_nxt[0] == uptr_wrap_nxt[0]));

   // Outlet
   assign valid_o = uptr_wrap != lptr_wrap;

   always_comb begin
      case (uptr[0])
         1'b0: data_o[(WIDTH/2)-1:0] = storage[0][(WIDTH/2)-1:0];
         1'b1: data_o[(WIDTH/2)-1:0] = storage[1][(WIDTH/2)-1:0];
      endcase
   end

   always_comb begin
      case (uptr[1])
         1'b0: data_o[WIDTH-1:(WIDTH/2)] = storage[0][WIDTH-1:(WIDTH/2)];
         1'b1: data_o[WIDTH-1:(WIDTH/2)] = storage[1][WIDTH-1:(WIDTH/2)];
      endcase
   end

   // Flops

   generate
      for (genvar i=0; i<2; i++) begin
         always_ff @(posedge clk_i) begin
            storage[i] <= storage_nxt[i];
         end
      end
   endgenerate

   always_ff @(posedge clk_i or negedge rst_n_i) begin
      if (~rst_n_i) begin
         lptr[1:0] <= '0;
	 uptr[1:0] <= '0;
	 lptr_wrap <= '0;
	 uptr_wrap <= '0;
	 ready_o <= 1'b0;
      end
      else begin
         lptr[1:0] <= lptr_nxt[1:0];
         uptr[1:0] <= uptr_nxt[1:0];
	 lptr_wrap <= lptr_wrap_nxt;
         uptr_wrap <= uptr_wrap_nxt;
	 ready_o <= ready_nxt;
      end
   end

endmodule
