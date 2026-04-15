module shreg_pipe_ultimate #(
   parameter WIDTH = 128,
   parameter IN_FLOP_EN = 1'b1, // Enable input flop. This flop is non-resettable and can allow EBR output to be flopped. Existing EBR output flop is resettable.
   parameter USE_VALID = 1'b0 // Decide whether wr_en will qual with valid=1 or not
)
(
   input logic clk_i, 
   input logic rst_n_i,
   input logic [WIDTH-1:0] data_i,
   input logic [5:0] valid_i,
   input logic [5:0] wr_en_i,
   output logic not_almost_full_o, /* synthesis syn_preserve=1 */
//   output logic not_almost_full_2_o, /* synthesis syn_preserve=1 */
//   output logic not_almost_full_3_o, /* synthesis syn_preserve=1 */
   output logic [WIDTH-1:0] data_o,
   output logic valid_o,
   input logic ready_i
);

   logic [5:0] lptr_incr;
   logic [4:0][1:0] lptr, lptr_add, lptr_nxt; /* synthesis syn_preserve=1 */
   logic uptr_incr;
   logic [4:0][1:0] uptr, uptr_nxt; /* synthesis syn_preserve=1 */
   logic [3:0][WIDTH-1:0] storage, storage_nxt;
   logic [3:0] storage_capture;
   logic [WIDTH-1:0] data_i_f, data_int;
   logic [5:0] valid_i_f, valid_int;
   logic [1:0] lptr_plus1, uptr_plus1;
   logic [1:0] diff, diff_norm, diff_wr, diff_rd;
   logic almost_full, almost_full_nxt;
   logic not_almost_full_nxt;
   logic [2:0] lptr_wrap, lptr_wrap_add, lptr_wrap_nxt;
   logic [2:0] uptr_wrap, uptr_wrap_add, uptr_wrap_nxt;

   assign data_int = IN_FLOP_EN ? data_i_f : data_i;
   assign valid_int = IN_FLOP_EN ? valid_i_f : valid_i;

   // Load Pointer

   assign lptr_incr = USE_VALID ? (wr_en_i & valid_int) : wr_en_i;

   generate
      for (genvar i = 0; i < 5; i++) begin
	 assign lptr_add[i] = (lptr[i] + 2'b01);
         assign lptr_nxt[i] = lptr_incr[i] ? lptr_add[i] : lptr[i];
      end
   endgenerate

   assign lptr_wrap_add = lptr_wrap + 'b1;
   assign lptr_wrap_nxt = lptr_incr[4] ? lptr_wrap_add : lptr_wrap;

   // Unload Pointer

   assign uptr_incr = valid_o & ready_i;
//   assign uptr_nxt[0] = uptr_incr ? (uptr[0] + 2'b01) : uptr[0];
//   assign uptr_nxt[1] = uptr_incr ? (uptr[0] + 2'b01) : uptr[0];
//   assign uptr_nxt[2] = uptr_incr ? (uptr[0] + 2'b01) : uptr[0];
//   assign uptr_nxt[3] = uptr_incr ? (uptr[0] + 2'b01) : uptr[0];
   assign uptr_nxt[0] = uptr_incr ? (uptr_plus1) : uptr[0];
   assign uptr_nxt[1] = uptr_incr ? (uptr_plus1) : uptr[0];
   assign uptr_nxt[2] = uptr_incr ? (uptr_plus1) : uptr[0];
   assign uptr_nxt[3] = uptr_incr ? (uptr_plus1) : uptr[0];
   assign uptr_nxt[4] = uptr_incr ? (uptr_plus1) : uptr[4];
   assign uptr_wrap_add = uptr_wrap + 'b1;
   assign uptr_wrap_nxt = uptr_incr ? uptr_wrap_add : uptr_wrap;

   // Storage
   assign storage_capture[0] = lptr_incr[0] & (lptr[0] == 2'b00);
   assign storage_capture[1] = lptr_incr[1] & (lptr[1] == 2'b01);
   assign storage_capture[2] = lptr_incr[2] & (lptr[2] == 2'b10);
   assign storage_capture[3] = lptr_incr[3] & (lptr[3] == 2'b11);

   assign storage_nxt[0] = storage_capture[0] ? data_int : storage[0];
   assign storage_nxt[1] = storage_capture[1] ? data_int : storage[1];
   assign storage_nxt[2] = storage_capture[2] ? data_int : storage[2];
   assign storage_nxt[3] = storage_capture[3] ? data_int : storage[3];

   // Almost Full
   assign diff_norm = lptr[4] - uptr[4];
   assign diff_wr  = lptr_plus1 - uptr[4];
   assign diff_rd = lptr[4] - uptr_plus1;
   // Ori: assign diff = (lptr_incr[5] == uptr_incr) ? diff_norm : (lptr_incr[5]) ? diff_wr : diff_rd;
   always_comb begin
      case ({lptr_incr[5], uptr_incr})
         2'b00: diff = diff_norm;
	 2'b01: diff = diff_rd;
         2'b10: diff = diff_wr; 
	 2'b11: diff = diff_norm;
      endcase
   end
   // Ori: assign almost_full_nxt = (diff >= 2) | (diff > 2) & almost_full;
   // New: Set when diff >= 2
   // Clear when almost_full=1 and diff <= 2
   // Ori: assign almost_full_nxt = ~(almost_full & (diff <= 2) & (diff != 0)) & ((diff >= 2) | almost_full);
   assign not_almost_full_nxt = ~(~(~not_almost_full_o & (diff <= 2) & (diff != 0)) & ((diff >= 2) | ~not_almost_full_o));

   // Outlet
   // Ori: assign valid_o = uptr[4] != lptr[4];
   assign valid_o = uptr_wrap != lptr_wrap;

   always_comb begin
      case (uptr[0])
         2'b00: data_o[(WIDTH/4)-1:0] = storage[0][(WIDTH/4)-1:0];
         2'b01: data_o[(WIDTH/4)-1:0] = storage[1][(WIDTH/4)-1:0];
	 2'b10: data_o[(WIDTH/4)-1:0] = storage[2][(WIDTH/4)-1:0];
	 2'b11: data_o[(WIDTH/4)-1:0] = storage[3][(WIDTH/4)-1:0];
      endcase
   end

   always_comb begin
      case (uptr[1])
         2'b00: data_o[(WIDTH/2)-1:(WIDTH/4)] = storage[0][(WIDTH/2)-1:(WIDTH/4)];
         2'b01: data_o[(WIDTH/2)-1:(WIDTH/4)] = storage[1][(WIDTH/2)-1:(WIDTH/4)];
         2'b10: data_o[(WIDTH/2)-1:(WIDTH/4)] = storage[2][(WIDTH/2)-1:(WIDTH/4)];
         2'b11: data_o[(WIDTH/2)-1:(WIDTH/4)] = storage[3][(WIDTH/2)-1:(WIDTH/4)];
      endcase
   end

   always_comb begin
      case (uptr[2])
         2'b00: data_o[(3*WIDTH/4)-1:(WIDTH/2)] = storage[0][(3*WIDTH/4)-1:(WIDTH/2)];
         2'b01: data_o[(3*WIDTH/4)-1:(WIDTH/2)] = storage[1][(3*WIDTH/4)-1:(WIDTH/2)];
         2'b10: data_o[(3*WIDTH/4)-1:(WIDTH/2)] = storage[2][(3*WIDTH/4)-1:(WIDTH/2)];
         2'b11: data_o[(3*WIDTH/4)-1:(WIDTH/2)] = storage[3][(3*WIDTH/4)-1:(WIDTH/2)];
      endcase
   end

   always_comb begin
      case (uptr[3])
         2'b00: data_o[WIDTH-1:(3*WIDTH/4)] = storage[0][WIDTH-1:(3*WIDTH/4)];
         2'b01: data_o[WIDTH-1:(3*WIDTH/4)] = storage[1][WIDTH-1:(3*WIDTH/4)];
         2'b10: data_o[WIDTH-1:(3*WIDTH/4)] = storage[2][WIDTH-1:(3*WIDTH/4)];
         2'b11: data_o[WIDTH-1:(3*WIDTH/4)] = storage[3][WIDTH-1:(3*WIDTH/4)];
      endcase
   end


   // Flops

   generate
      for (genvar i=0; i<4; i++) begin
         always_ff @(posedge clk_i) begin
            storage[i] <= storage_nxt[i];
         end
      end
   endgenerate

   always_ff @(posedge clk_i) begin
      data_i_f <= data_i;
      valid_i_f <= valid_i;
   end

   always_ff @(posedge clk_i or negedge rst_n_i) begin
      if (~rst_n_i) begin
         lptr[0] <= '0;
	 lptr[1] <= '0;
	 lptr[2] <= '0;
	 lptr[3] <= '0;
	 lptr[4] <= '0;
	 //lptr[5] <= '0;
	 uptr[0] <= '0;
         uptr[1] <= '0;
         uptr[2] <= '0;
         uptr[3] <= '0;
         uptr[4] <= '0;
         //uptr[5] <= '0;
	 lptr_plus1 <= '0;
	 uptr_plus1 <= '0;
	 //almost_full <= 1'b0;
	 not_almost_full_o <= 1'b1;
//	 not_almost_full_2_o <= 1'b1;
//	 not_almost_full_3_o <= 1'b1;
	 lptr_wrap <= '0;
	 uptr_wrap <= '0;
      end
      else begin
         lptr[0] <= lptr_nxt[0];
	 lptr[1] <= lptr_nxt[1];
	 lptr[2] <= lptr_nxt[2];
	 lptr[3] <= lptr_nxt[3];
	 lptr[4] <= lptr_nxt[4];
	 //lptr[5] <= lptr_nxt[5];
         uptr[0] <= uptr_nxt[0];
	 uptr[1] <= uptr_nxt[1];
	 uptr[2] <= uptr_nxt[2];
	 uptr[3] <= uptr_nxt[3];
	 uptr[4] <= uptr_nxt[4];
	 //uptr[5] <= uptr_nxt[5];
	 lptr_plus1 <= lptr_nxt[4] + 'b1;
         //uptr_plus1 <= uptr_nxt[5] + 'b1;
	 uptr_plus1 <= uptr_nxt[0] + 'b1;
	 //almost_full <= almost_full_nxt;
	 not_almost_full_o <= not_almost_full_nxt;
//	 not_almost_full_2_o <= not_almost_full_nxt;
//	 not_almost_full_3_o <= not_almost_full_nxt;
	 lptr_wrap <= lptr_wrap_nxt;
         uptr_wrap <= uptr_wrap_nxt;
      end
   end

endmodule
