module dma_rd_en_manager
(
   input logic clk_i,
   input logic rst_n_i,
   input logic fifo_empty_i,
   input logic source_rd_en_i,
   output logic avail_o,
   output logic rd_en_o
);

   typedef enum logic [1:0] {IDLE = 2'd0,
                             AVAIL = 2'd1,
                             WAIT = 2'd2
                         } fsm_state;

   fsm_state cs_sm, ns_sm;

   logic avail_nxt;

   // FSM Combi
   always_comb begin

      ns_sm = cs_sm;
      avail_nxt = avail_o;
      rd_en_o = 1'b0; // Pulse

      case (cs_sm)

         IDLE: begin
            if (~fifo_empty_i) begin
               ns_sm = AVAIL;
	       rd_en_o = 1'b1;
               avail_nxt = 1'b1;
            end
            else begin
               ns_sm = cs_sm;
            end
         end

         AVAIL: begin
            if (source_rd_en_i & ~fifo_empty_i) begin
               ns_sm = AVAIL;
	       rd_en_o = 1'b1;
	       avail_nxt = 1'b1;
	    end
	    else if (source_rd_en_i & fifo_empty_i) begin
               ns_sm = WAIT;
	       avail_nxt = 1'b0;
	    end
	    else begin
               ns_sm = cs_sm;
            end
         end

	 WAIT: begin
            if (~fifo_empty_i) begin
               ns_sm = AVAIL;
               rd_en_o = 1'b1;
               avail_nxt = 1'b1;
            end
	    else begin
               ns_sm = cs_sm;
            end
         end

	 default: begin
	    ns_sm = IDLE;
	 end

       endcase
   end

   // Flops
   always_ff @(posedge clk_i or negedge rst_n_i) begin
      if (~rst_n_i) begin
         cs_sm <= IDLE;
	 avail_o <= 1'b0;
      end
      else begin
	 cs_sm <= ns_sm;
	 avail_o <= avail_nxt;
      end
   end

endmodule
