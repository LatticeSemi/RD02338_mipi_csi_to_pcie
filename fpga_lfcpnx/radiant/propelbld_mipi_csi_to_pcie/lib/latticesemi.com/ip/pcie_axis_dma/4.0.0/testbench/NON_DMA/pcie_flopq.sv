module pcie_flopq #(
  parameter WIDTH = 8,                      
  parameter DEPTH = 4,
  parameter FULLLIMIT = DEPTH
) (
  input  logic clk,
  input  logic rst_n,

  input  logic ivalid,
  output logic iready,
  input  logic [WIDTH-1:0] idata,

  output logic ovalid,
  input  logic oready,
  output logic [WIDTH-1:0] odata
);

  localparam bit ENABLE_ALMOST_FULL_FLAG = (FULLLIMIT < DEPTH)? 1'b1 : 1'b0;
  localparam CONST_1 = 1;

  logic full;
  logic almost_full;
	
  // pointer
  logic [$clog2(DEPTH):0] lptr, lptr_nxt, flip_wrapbit_lptr;
  logic [$clog2(DEPTH):0] uptr, uptr_nxt;
  logic [$clog2(DEPTH):0] level;
  logic nc_lptr_wrap_bit, nc_uptr_wrap_bit;
  logic get, put;

  //------------------------------------------------
  // TODO: add option to use MEM block or fully flops
  //------------------------------------------------
  logic [DEPTH-1:0][WIDTH-1:0] mem_data;

  //---------
  // status
  //---------
  // the following equation consist of 
  // 1) wrap bit.    ~lptr[$clog2(DEPTH)],    uptr[$clog2(N*DEPTH)] 
  // 2) act ptr bit. lptr[$clog2(DEPTH)-1:0], uptr[$clog2(N*DEPTH)-1:$clog2(N)]. this will be obmitted if DEPTH=1
  assign full = ( flip_wrapbit_lptr[$clog2(DEPTH):0] == uptr[$clog2(DEPTH):0] );

  assign flip_wrapbit_lptr[$clog2(DEPTH)]     = ~lptr[$clog2(DEPTH)]; // flip the wrap bit for not-equal compare later
  assign flip_wrapbit_lptr[$clog2(DEPTH)-1:0] = lptr[$clog2(DEPTH)-1:0];

  assign nc_lptr_wrap_bit = lptr[$clog2(DEPTH)]; // msb
  assign nc_uptr_wrap_bit = uptr[$clog2(DEPTH)]; // msb

  assign almost_full = (level[$clog2(DEPTH):0] >= FULLLIMIT[$clog2(DEPTH):0]);
  assign level[$clog2(DEPTH):0] = lptr[$clog2(DEPTH):0] - uptr[$clog2(DEPTH):0];

  assign ovalid = (lptr[$clog2(DEPTH):0] != uptr[$clog2(DEPTH):0]);

  //---------
  // inlet
  //---------
  assign iready = ENABLE_ALMOST_FULL_FLAG? ~almost_full : ~full;

  // load pointer
  assign put = ENABLE_ALMOST_FULL_FLAG? (ivalid & ~full) : (ivalid & iready);
  assign lptr_nxt [$clog2(DEPTH):0] = put? (lptr [$clog2(DEPTH):0] + CONST_1 [$clog2(DEPTH):0]) : lptr [$clog2(DEPTH):0]; // including wrap bit and good for 2^n rolloever

  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      lptr <= '0;
    end
    else begin
      lptr <= lptr_nxt;
    end
  end

  // non resetable
  always_ff @(posedge clk) begin
    if (put) begin 
      mem_data [ lptr[$clog2(DEPTH)-1:0] ] <= idata[WIDTH-1:0];
    end
  end

  //---------
  // outlet
  //---------
  // unload pointer
  assign get = ovalid & oready;
  assign uptr_nxt [$clog2(DEPTH):0] = get? (uptr [$clog2(DEPTH):0] + CONST_1 [$clog2(DEPTH):0]) : uptr[$clog2(DEPTH):0]; // including wrap bit and good for 2^n rolloever

  always_ff @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
      uptr <= '0;
    end  
    else begin
      uptr <= uptr_nxt;
    end  
  end

  assign odata = mem_data [ uptr[$clog2(DEPTH)-1:0] ];

endmodule
