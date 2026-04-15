module axist_generator #(
   parameter IMAGE_PATTERN = 1'b1, // 1: image pattern. 0: incremental pattern.
   parameter PER_BYTE_INCR = 1'b1, // Used when IMAGE_PATTERN == 1'b0. 1: Incremented per byte. 0: Incremented per 32-byte.
   parameter IMAGE_PATTERN_ONCE = 1'b1, // 1: Used when IMAGE_PATTERN == 1. 1: Send image pattern once. 0: Send repeatedly.
   parameter [16:0] STREAM_SIZE = 17'b0_0100_0000_0000_0000 // 16 KB for a stream.
)
(
   input logic clk_i,
   input logic rst_n_i,
   input logic tx_dma_axist_tready_i,
   output logic tx_dma_axist_tvalid_o,
   output logic tx_dma_axist_tlast_o,
   output logic [255:0] tx_dma_axist_tdata_o,
   output logic [0:0] usr_int_req_o,
   input logic [0:0] usr_int_ack_i,
   input logic reg_usr_int_first_tlast
);

   localparam CNT_MAX = (STREAM_SIZE / 32) - 1; // 32B per beat.
   localparam CNT_WIDTH = $clog2(CNT_MAX);
   localparam PATTERN_WIDTH = (PER_BYTE_INCR == 1'b1) ? 3 : 8; // Count to 7 or 255

   typedef enum logic [1:0] {IDLE = 2'd0,
                             REQ = 2'd1,
			     DONE = 2'd2
                         } fsm_state;

   fsm_state cs_sm, ns_sm;


   generate
   if (IMAGE_PATTERN) begin

   // 120kB image, count from 0 to 3749 (3750 x 32B = 120000B)
   logic [29999:0][31:0] intBuf;
   logic [11:0] image_counter, image_counter_nxt;
   logic image_done, image_done_nxt;

   always_ff @ (posedge clk_i or negedge rst_n_i) begin
      if (~rst_n_i) begin
         image_counter <= '0;
	 image_done <= 1'b0;
      end
      else begin
         image_counter <= image_counter_nxt;
	 image_done <= image_done_nxt;
      end
   end

   always_comb begin
      intBuf = '0;
      `include "image1.txt"
   end

   // Set once
   assign image_done_nxt = ((image_counter == 'd3749) & tx_dma_axist_tready_i) ? 1'b1 : image_done;

   assign image_counter_nxt = ((image_counter == 'd3749) & tx_dma_axist_tready_i) ? '0 :
	                      (tx_dma_axist_tready_i & (~image_done | ~IMAGE_PATTERN_ONCE)) ? (image_counter + 'd1) :
			      image_counter;

   assign tx_dma_axist_tdata_o = {
                                 intBuf[(8*image_counter)+7][31:0],
                                 intBuf[(8*image_counter)+6][31:0],
                                 intBuf[(8*image_counter)+5][31:0],
                                 intBuf[(8*image_counter)+4][31:0],
                                 intBuf[(8*image_counter)+3][31:0],
                                 intBuf[(8*image_counter)+2][31:0],
                                 intBuf[(8*image_counter)+1][31:0],
                                 intBuf[(8*image_counter)+0][31:0]
	                         };
   assign tx_dma_axist_tlast_o = (image_counter == 'd3749);
   assign tx_dma_axist_tvalid_o = 1'b1;

   assign usr_int_req_o[0] = 1'b0;

   end
   else begin

   logic [PATTERN_WIDTH-1:0] axist_pattern, axist_pattern_nxt;
   logic [CNT_WIDTH-1:0] stream_counter;
   logic [31:0][7:0] per_byte_pattern;

   for (genvar i = 0; i < 32; i++) begin
      assign per_byte_pattern[i][7:0] = (axist_pattern * 32) + i;
   end

   always_ff @ (posedge clk_i or negedge rst_n_i) begin
      if (~rst_n_i) begin
         axist_pattern <= '0;
	 stream_counter <= CNT_MAX;
      end
      else begin
         axist_pattern <= tx_dma_axist_tready_i ? (axist_pattern + 'b1) : axist_pattern;
	 stream_counter <= (tx_dma_axist_tready_i & (stream_counter == '0)) ? CNT_MAX :
		           tx_dma_axist_tready_i ? (stream_counter - 'b1) : stream_counter;
      end
   end

   assign tx_dma_axist_tlast_o = (stream_counter == '0);
   assign tx_dma_axist_tvalid_o = 1'b1;
   assign tx_dma_axist_tdata_o = (PER_BYTE_INCR == 1'b1) ? per_byte_pattern : {32{axist_pattern[7:0]}};

   // FSM Combi
   // This FSM is an example of trigger interrupt at the first TLAST of AXI-ST
   // interface.
   always_comb begin

      ns_sm = cs_sm;

      case (cs_sm)

         IDLE: begin
            if (reg_usr_int_first_tlast & tx_dma_axist_tvalid_o & tx_dma_axist_tready_i & tx_dma_axist_tlast_o) begin
               ns_sm = REQ;
	    end
	    else begin
	       ns_sm = IDLE;
	    end
	 end

	 REQ: begin
            if (usr_int_ack_i) begin
               ns_sm = DONE;
            end
            else begin
               ns_sm = REQ;
            end
         end

	 DONE: begin
            ns_sm = DONE;
	 end

         default: begin
            ns_sm = IDLE;
         end

      endcase

   end

   assign usr_int_req_o[0] = (cs_sm == REQ);

   // Flops
   always_ff @(posedge clk_i or negedge rst_n_i) begin
      if (~rst_n_i) begin
         cs_sm <= IDLE;
      end
      else begin
         cs_sm <= ns_sm;
      end
   end

   end
   endgenerate

endmodule
