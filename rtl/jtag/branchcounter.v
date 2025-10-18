// Module to monitor how much time is lost to branching and transitioning between cachelines.
// Measures the following:
//   Total number of cycles between start and stop
//   Number of cycles spent fetching data from l2 to l1 during linear execution
//   Number of cycles spent fetching data from l2 to l1 on branches
//   Number of cycles spent fetching data from SDRAM to l1 on branches

module branchcounter (
	input clk,
	input reset_n,
	input clkena,
	input [1:0] cpustate,
	input [31:0] addr,
	input newpc
);

reg active_d;
reg active;
reg [7:0] cyclecounter;
reg [31:0] totalcounter;
reg [31:0] linearcounter;
reg [31:0] linearramcounter;
reg [31:0] branchcounter;
reg [31:0] branchramcounter;
reg [31:0] faultcounter;

reg [31:0] addr_next;
reg newpc_d;
reg newpc_ce_d;
reg fault;

always @(posedge clk) begin
	fault <= 1'b0;
	active_d <= active;
	
	if(fault)
		faultcounter <= faultcounter+1;
	
	if((cpustate==2'b00) && clkena) begin
		addr_next <= addr+2;
		newpc_d <= newpc;
	end

	if(clkena && newpc)
		newpc_d <= 1'b1;
	
	if(active && (cpustate==2'b00) && clkena) begin

		addr_next <= addr+2;

		if((!newpc_d) && (addr_next != addr))
			fault <= 1'b1;

		totalcounter <= totalcounter+cyclecounter;
		if(newpc_d) begin
			if (cyclecounter==6)
				branchcounter <= branchcounter + 2;
			else
				branchramcounter <= branchramcounter + cyclecounter-4;
		end else begin
			if (cyclecounter==6)
				linearcounter <= linearcounter + 2;
			else
				linearramcounter <= linearramcounter + cyclecounter-4;
		end
	end

	if(clkena)
		newpc_ce_d <= newpc;

	if(clkena)
		cyclecounter<=1;
	else
		cyclecounter<=cyclecounter+1;

	if(active && !active_d) begin
		totalcounter<= 0;
		branchcounter<= 0;
		branchramcounter<= 0;
		linearcounter<= 0;
		linearramcounter<= 0;
		faultcounter <= 0;
	end
end


// Virtual JTAG remote interface:

reg [7:0] jtag_cmd;

reg [2:0] rdptr_j;
reg [31:0] jtag_d;

always @(posedge clk) begin
	case(rdptr_j)
		3'b001: jtag_d <= linearcounter;
		3'b010: jtag_d <= linearramcounter;
		3'b011: jtag_d <= branchcounter;
		3'b100: jtag_d <= branchramcounter;
		3'b101: jtag_d <= faultcounter;
		default: jtag_d <= totalcounter;
	endcase
end


// Data received from the host computer

reg jtag_reset;
reg jtag_report;

reg jtag_req;
reg jtag_ack;
reg jtag_wr;
wire [31:0] jtag_q;

always @(posedge clk) begin
	jtag_reset<=1'b0;

	jtag_report<=1'b0;

	if(jtag_ack && !jtag_wr) begin
		jtag_cmd <= jtag_q[31:24];
		case(jtag_q[31:24]) // Interpret the highest 8 bits as a command byte

			8'h00: active <= 1'b0;
			8'h01: active <= 1'b1;
			8'h02: begin
				active <= 1'b0;
				jtag_report<=1'b1;
			end
			8'h03: begin
				jtag_report<=1'b1;
			end

			8'hff: jtag_reset<=1'b1; // Command 0xff: reset

		endcase
	end
	
	if(!reset_n)
		active<=1'b0;
end


// Plumbing

always @(posedge clk) begin
	jtag_req<=!jtag_ack;

	if(jtag_ack && jtag_wr) begin
		case(jtag_cmd)
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
		rdptr_j<=3'b111;
end


// This bridge is borrowed from the EightThirtyTwo debug interface

debug_bridge_jtag #(.id('hbc68)) bridge (
	.clk(clk),
	.reset_n(reset_n),
	.d(jtag_d),
	.q(jtag_q),
	.req(jtag_req),
	.wr(jtag_wr),
	.ack(jtag_ack)
);

endmodule

