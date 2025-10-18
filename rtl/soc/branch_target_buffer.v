// Branch target buffer and prefetch address generator
// 
// When the newpc signal goes high, use the current I$ address to
// look up a likely branch target.  This will be presented to the
// cache controller in place of adr_out.
// If the real CPU address doesn't match, the transaction will be
// delayed and the real CPU address used instead.

// To Do: Maybe make this a two-way cache?  Probably no need.

// Using M9Ks and storing 32 bit addresses:
// A single M9K can store 256 entries - should be enough.
// Use bits 8:1 as a lookup into the BTB.
// Need to use bits 26:9 as a tag.

// Tag format: bit 31 - valid:
// Bits 19:0 - map to address bit 26:9

// BTB format: just a verbatim copy of the target address.

module branch_target_buffer (
	input clk,
	input reset_n,
    input  wire [ addr_max_bits+addr_prefix_bits-1:0] cpu_adr,        // cpu address
	input [1:0] cpu_state,
	input cpu_newpc,
	input cpu_ack,
	output reg [26:0] adr_out,
	output adr_out_stb,
	output reg ready
);

parameter addr_max_bits=26;
parameter addr_prefix_bits=1;
parameter addr_prefix=0;
parameter enable=1;

reg [31:0] tag_storage[256]; 
reg [31:0] btb_storage[256];

// When newpc goes high use the current adr_out address as an index into the BTB.

localparam BTB_INIT=4'd0;
localparam BTB_CLEAR=4'b1;
localparam BTB_IDLE=4'd2;
localparam BTB_WAIT_IFETCH=4'd3;
localparam BTB_WAIT_IFETCH2=4'd4;
localparam BTB_STORE=4'd5;
localparam BTB_HIT=4'd6;
localparam BTB_MISS=4'd7;
localparam BTB_LOOKUP=4'd8;
localparam BTB_WAIT=4'd9;
localparam BTB_DIRECT=4'd10;

localparam TAG_BIT_VALID=31;

reg [3:0] btb_state=BTB_INIT;

reg newpc_d;

reg [31:0] tag;
reg [31:0] target;

reg [7:0] btb_rd_a;
reg [7:0] btb_wr_a;
reg [31:0] btb_dat_w;
reg [31:0] btb_tag_w;
reg btb_we;

wire tag_hit = tag[ addr_max_bits+addr_prefix_bits-1:9] == adr_out[ addr_max_bits+addr_prefix_bits-1:9] ? 1'b1 : 1'b0;

// Sequence of events
// cpu_newpc goes high (this can happen multiple cycles before the next fetch - data cycles and internal cycles can happen while it's high.)
// BTB looks up tag and branch target based on current value of adr_out.

// On hit:
//   Update adr_out with cache contents
//   Wait for the actual fetch cycle to begin
//   Compare addresses once safe to do so

//   If matched:
//     raise adr_out_stb

// On miss, or if hit but the target doesn't match
//    update adr_out with CPU address
//    update BTB
//     raise adr_out_stb after enough cycles for cache to react to new address

// when cpu_newpc is low, update adr_out any time cpu_ir is high and clkena is pulsed.


reg [2:0] fetch_stable_ctr;
always @(posedge clk)
  fetch_stable_ctr <= {fetch_stable_ctr[1:0],cpu_state==2'b00 && !cpu_ack ? 1'b1 : 1'b0};
wire fetch_adr_stable = &fetch_stable_ctr[1:0];

reg newpc_l;
reg newpc_startup;

`ifdef VERILATOR
reg newpc_neg;
reg cpu_ifetch;
// negedge working around a problem with verilator
always @(negedge clk) begin
	newpc_neg <= cpu_newpc;
	cpu_ifetch <= cpu_state == 2'b00 ? 1'b1 : 1'b0;
end

always @(posedge clk) begin
	newpc_d <= newpc_neg | newpc_startup;

	if (!reset_n)
		newpc_l <= 1'b1;
	else if (cpu_ack && cpu_ifetch)
		newpc_l <= newpc_neg;

	if (!reset_n)
		newpc_startup <= 1'b1;
	else if (cpu_state==2'b00)
		newpc_startup <= 1'b0;
end

`else
wire cpu_ifetch = cpu_state==2'b00 ? 1'b1 : 1'b0;
// newpc may well rise on a non-fetch cycle. We need to latch it high until a fetch cycle has completed.
always @(posedge clk) begin
	newpc_d <= cpu_newpc | newpc_startup; // Add a synthetic newpc at startup since we don't get one from the CPU for the first instruction fetch

	if (!reset_n)
		newpc_l <= 1'b1;
	else if (cpu_ack && (cpu_state==2'b00))
		newpc_l <= cpu_newpc;

	if (!reset_n)
		newpc_startup <= 1'b1;
	else if (cpu_state==2'b00)
		newpc_startup <= 1'b0;
end
`endif

reg [3:0] adriok;
assign adr_out_stb = adriok[3];


always @(posedge clk) begin

	adriok <= {adriok[2:0],adriok[0]};

	if(enable) begin
		tag <= tag_storage[btb_rd_a];
		target <= btb_storage[btb_rd_a];
	end

 	btb_we <= 1'b0;

	if(cpu_ack && (cpu_state==2'b00)) begin
		adriok <= 4'b0011;
		if(!newpc_d)
			adr_out <= adr_out + 2;
	end
		

	case(btb_state)
		BTB_INIT : begin
			ready <=1'b0;
			adr_out<=0;
			btb_state <= BTB_CLEAR;		
		end

		BTB_CLEAR : begin
			btb_wr_a <= adr_out[8:1];
			btb_tag_w <= 0;
			btb_we <= 1'b1;

			adr_out <= adr_out+2;
			if(!enable || adr_out[9]) begin
				btb_state <= BTB_IDLE;
				ready <= 1'b1;
			end
		end

		BTB_IDLE : begin
			btb_rd_a <= adr_out[8:1];
			if(newpc_d) begin
				btb_state <= BTB_LOOKUP;
				btb_wr_a <= adr_out[8:1];
				btb_tag_w[ addr_max_bits+addr_prefix_bits-1:0] <= adr_out;
				btb_tag_w[TAG_BIT_VALID]<=1'b1;
			end
			
		end
		
		BTB_LOOKUP : begin
			if(newpc_l || cpu_ack) begin
				adr_out <= target[addr_max_bits+addr_prefix_bits-1:0]; // Might be too soon...
				btb_state <= BTB_WAIT_IFETCH;
			end
		end
		
		BTB_WAIT_IFETCH : begin
			adriok<=4'b0001;
			if(cpu_ifetch)
				btb_state <= BTB_WAIT_IFETCH2;
		end
		
		BTB_WAIT_IFETCH2 : begin
			if(cpu_ifetch) begin
				if(enable && tag[TAG_BIT_VALID] && tag_hit)
					btb_state <= BTB_HIT;
				else
					btb_state <= BTB_MISS;
			end
		end

		// Check that the CPU did indeed branch to the expected address.
		BTB_HIT : begin // FIXME - might need one cycle delay here
			if(fetch_adr_stable) begin
				if(cpu_adr != adr_out[addr_max_bits+addr_prefix_bits-1:0]) begin
					adriok<=4'b0001;
					adr_out <= cpu_adr;
					btb_dat_w[ addr_max_bits+addr_prefix_bits-1:0] <= cpu_adr;
					btb_we <= 1'b1;
					btb_state <= BTB_WAIT;
				end else begin
					adriok<=4'b1111;
					btb_state <= BTB_IDLE;
				end
			end
		end
		
		BTB_MISS : begin // FIXME - might need one cycle delay here
			adr_out <= cpu_adr;
			adriok<=4'b0001;
			btb_dat_w[ addr_max_bits+addr_prefix_bits-1:0] <= cpu_adr;
			btb_we <= 1'b1;
			btb_state <= BTB_WAIT;
		end

		BTB_WAIT : begin
			if(cpu_ack)
				btb_state <= BTB_IDLE;
		end

		default : 
			btb_state <= BTB_IDLE;
	
	endcase

	if(!reset_n) begin
		btb_state<=BTB_INIT;
		ready <= 1'b0;
	end
		
	if(enable && btb_we) begin
		tag_storage[btb_wr_a] <= btb_tag_w;
		btb_storage[btb_wr_a] <= btb_dat_w;
	end
end

// Debugging: match counter

reg [3:0] match_counter /* synthesis noprune */;
reg mismatch /* synthesis noprune */;

always @(posedge clk) begin
	if(adr_out == cpu_adr)
		match_counter <= match_counter + 1;
	if(cpu_ack && cpu_state==2'b00)
		match_counter <= 0;
end

always @(posedge clk) begin
	mismatch <= 1'b0;
	if(cpu_ack && cpu_state==2'b00 && adr_out!=cpu_adr)
		mismatch <= 1'b1;
end

endmodule

