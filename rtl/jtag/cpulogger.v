module cpulogger (
	input clk,
	input reset_n,
	input clkena,
	input [1:0] cpustate,
	input [27:0] addr,
	input [15:0] readdata,
	input [15:0] writedata,
	input [3:0] cacr,
	output freeze
);

reg frozen=1'b1;

assign freeze=frozen;

localparam addr_log2 = 10;
reg [addr_log2:0] rdptr_j=0;
reg [addr_log2-1:0] wrptr=0;
reg [31:0] jtag_d;

reg [63:0] storage [2**addr_log2];


// Write side

reg capture=1'b0;

always @(posedge clk) begin
	if(clkena && capture && !frozen) begin
		storage[wrptr]<={2'b00,cpustate,writedata,readdata,addr};
		wrptr<=wrptr+1;
	end

	storage_q<=storage[rdptr_j[addr_log2:1]];

	if(frozen || jtag_reset)
		wrptr<=0;
end

// Maintain a count of clkenas since the last reset, so we can start capturing / matching after a specific delay

reg [31:0] clkenacounter;
always @(posedge clk) begin
	if(clkena)
		clkenacounter <= clkenacounter+1;
	if(!reset_n)
		clkenacounter<=0;
end


// Virtual JTAG remote interface:

reg [7:0] jtag_cmd;

reg [63:0] storage_q;

always @(posedge clk) begin
	case(jtag_cmd)
		8'h00: jtag_d <= {clkenacounter[31:8],3'b000,cacr,frozen};
		8'h02: jtag_d <= rdptr_j[0] ? storage_q[63:32] : storage_q[31:0];
		default: ;
	endcase
end


// Data received from the host computer

reg jtag_reset;
reg jtag_report;

reg jtag_req;
reg jtag_ack;
reg jtag_wr;
wire [31:0] jtag_q;

// Define commands as follows:
// 00: get status:
//     Bit 0: Buffer full
//     Bit 4-1: CACR
// 01: unfreeze and start logging, freeze again when buffer is full
// 02: reset read pointer
// 03: release freeze bit
// 04: set match condition
//     Bit 0: match cpustate
//     Bit 1: match addres
//     Bit 2: match ena counter
//     Bits 4:3: cpustate to match
//     Bits 23:8: lower 16-bits of address to match
// 05: Bits 15:0: upper 16 bits of address to match
// 06: bits 23:0: 32 bits of cycle counter to match

reg statematching;
reg addressmatching;
reg countermatching = 1'b0;

reg oneshot = 1'b1;
reg matchstate = 1'b0;
reg matchaddress = 1'b0;
reg matchcounter = 1'b1;

reg [1:0] targetstate;
reg [31:0] targetaddress;
reg [31:0] targetcounter;

wire cache_en = cacr[0];
reg cache_en_d;


always @(posedge clk) begin
	jtag_reset<=1'b0;

	jtag_report<=1'b0;

	cache_en_d <= cache_en;

	statematching <= ((targetstate==cpustate) || !matchstate) ? 1'b1 : 1'b0;
	addressmatching <= ((targetaddress[27:0]==addr) || !matchaddress) ? 1'b1 : 1'b0;

	if(targetcounter==clkenacounter || !matchcounter)
		countermatching <= 1'b1;
	
	if(countermatching && statematching && addressmatching)
		capture <= 1'b1;

	if(jtag_ack && !jtag_wr) begin
		jtag_cmd <= jtag_q[31:24];
		case(jtag_q[31:24]) // Interpret the highest 8 bits as a command byte

			8'h00: begin
				jtag_report<=1'b1;
			end

			8'h01: begin // Begin capturing
				oneshot <= 1'b1; // Freeze again when the buffer fills
				frozen  <= 1'b0;	// Unfreeze the CPU
			end

			8'h02: begin
				jtag_report<=1'b1;
			end

			8'h03: begin // Release and CPU
				oneshot <= 1'b0;
				frozen  <= 1'b0;
			end

			8'h04: begin
				matchstate <= jtag_q[0];
				matchaddress <= jtag_q[1];
				matchcounter <= jtag_q[2];
				countermatching<=1'b0;
				targetstate <= jtag_q[4:3];
				targetaddress[15:0] <= jtag_q[23:8];
				capture <= 1'b0;
			end
			
			8'h05: begin
				targetaddress[31:16] <= jtag_q[15:0];
				capture <= 1'b0;
			end
			
			8'h06: begin
				targetcounter <= jtag_q[23:0];
				capture <= 1'b0;
			end
			
			8'hff: jtag_reset<=1'b1; // Command 0xff: reset

			default: 
				;
		endcase
	end
	
	if(clkena && &wrptr)
		frozen <= oneshot;

	// Freeze CPU when cache is enabled for the first time.
	if(reset_n && clkena && cache_en && !cache_en_d)
		frozen <= 1'b1;

//	if(!reset_n) begin
//		freeze <= 1'b0;
//		capture <= 1'b0;
//	end
	
	if(jtag_reset) begin
		frozen <= 1'b1;
		capture <= 1'b0;
		countermatching <= 1'b0;
	end
end


// Plumbing

always @(posedge clk) begin
	jtag_req<=!jtag_ack;

	if(jtag_ack && jtag_wr) begin
		case(jtag_cmd)
			8'h00: begin
				jtag_wr <= 1'b0;
			end
			8'h01: begin
				jtag_wr <= 1'b0;
			end
			8'h02: begin
				rdptr_j<=rdptr_j+1;
				jtag_wr <= ~(&rdptr_j);
			end
			8'h03: jtag_wr <= 1'b0;
			default: ;
		endcase
	end

	if(jtag_report) begin
		rdptr_j<=0;
		jtag_wr<=1'b1;
	end

	if(!reset_n)
		rdptr_j<={addr_log2{1'b1}};
end


// This bridge is borrowed from the EightThirtyTwo debug interface

debug_bridge_jtag #(.id('hc106)) bridge (
	.clk(clk),
	.reset_n(reset_n),
	.d(jtag_d),
	.q(jtag_q),
	.req(jtag_req),
	.wr(jtag_wr),
	.ack(jtag_ack)
);

endmodule

