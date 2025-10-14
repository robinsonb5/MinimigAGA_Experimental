// cpu / cache / sdram testbench
// based on 2013, rok.krajnc@gmail.com

//// module ////
module tb(
  input  wire           clk_114,
  input [25:0] cpuaddr_in,
  input [1:0] cpustate_in,
// SDRAM
input wire [ 16-1:0] DRAM_DQ,
output wire [ 16-1:0] DRAM_DQ_O,
output wire [ 13-1:0] DRAM_ADDR,
output wire           DRAM_LDQM,
output wire           DRAM_UDQM,
output wire           DRAM_WE_N,
output wire           DRAM_CAS_N,
output wire           DRAM_RAS_N,
output wire           DRAM_CS_N,
output wire           DRAM_BA_0,
output wire           DRAM_BA_1
);

`define SOC_SIM
`define SOC_VERIFY

parameter addr_prefix_bits = 1;
parameter addr_max_bits = 26;
parameter addr_prefix = 1'b0;

//// fake cpu ///
reg [3:0] slower;
wire      ramsel = cpu_state != 2'b01;
wire      cpu_ncs = ~ramsel | slower[0];

reg cpu_req;
reg [25:0] cpu_adr;
reg [3:0] cpu_state;
wire clkena;
assign    clkena = !slower[0] && (cpu_state[1:0] == 2'b01 || (tg68_cpuena & cpu_state[2])) ? 1'b1 : 1'b0;

initial cpu_adr <= 0;

always @(posedge clk_114) begin
	if (clkena) begin
		slower <= 4'b0111;
		cpu_adr <= cpuaddr_in;
		cpu_state<={2'b01,cpustate_in};
	end else
		slower <= {1'b0, slower[3:1]};


	if(slower[0]==1'b0 && cpu_state[2]==1'b1 && cpustate_in[1:0]!=2'b01) begin
		cpu_state<={2'b00,cpustate_in};
	end

	if (!reset_out)
		slower<=4'b1111;
end

//// internal signals ////

wire           clk_7_en = 0;
// data reg
reg  [16-1:0] dat;

// SDRAM controller
wire          sdctl_rst;
wire [ 3-1:0] cctrl;
wire          cache_inhibit = 0;

wire [ 4-1:0] sdram_cs;
wire [ 2-1:0] sdram_ba;
wire [ 2-1:0] sdram_dqm;

wire [ 4-1:0] sdram2_cs;
wire [ 2-1:0] sdram2_ba;
wire [ 2-1:0] sdram2_dqm;

reg    [25:0] rtgAddr;
wire          rtgce = 0;
wire          rtgfill;
wire          rtgack;
wire          rtgpri=0;
wire   [15:0] rtgRd;

wire   [22:0] audAddr=0;
wire          audce = 0;
wire          audfill;
wire          audack;
wire   [15:0] audRd;

wire [26-1:0] bridge_adr;
wire          bridge_cs;
wire          bridge_we;
wire [32-1:0] bridge_dat_w;
wire [16-1:0] bridge_dat_r;
wire          bridge_ack;
wire          bridge_err;
wire  [4-1:0] bridge_bytesel;
wire [16-1:0] ram_data=0;
wire [16-1:0] ram_data2=0;
reg [22-1:1] ram_address=0;
wire          _ram_bhe=1'b1;
wire          _ram_ble=1'b1;
wire          _ram_we=1'b1;
reg           _ram_oe=1'b0;
wire [16-1:0] ramdata_in;

reg           tg68_clds=1;
reg           tg68_cuds=1;
wire [16-1:0] tg68_cout;
wire          tg68_ena28;
wire          tg68_ena7RD;
wire          tg68_ena7WR;
wire          tg68_cpuena;
wire          tg68_cpuena2;
reg           tg68_dtack=0;

reg  [32-1:0] tg68_adr=0;
wire  [16-1:0] tg68_dat_in;
reg  [16-1:0] tg68_dat_out=0;


//// toplevel logic ////
assign cctrl = 3'b111;

assign bridge_cs = 1'b1;
assign bridge_adr = 26'h680000;
assign bridge_we = 1'b0;
assign bridge_dat_w = 32'd0;
assign bridge_bytesel = 4'b1111;


initial rtgAddr[25:24]<=2'b11;
always @(posedge clk_114) begin
	if(rtgack)
		rtgAddr <= rtgAddr+16;
	rtgAddr[25:24]<=2'b11;
end


//// modules ////

wire reset_out;

assign DRAM_UDQM = sdram_dqm[1];
assign DRAM_LDQM = sdram_dqm[0];
assign DRAM_CS_N = sdram_cs[0];
assign DRAM_BA_1 = sdram_ba[1];
assign DRAM_BA_0 = sdram_ba[0];

wire sdram_oe;

reg reset=1'b0;

always @(posedge clk_114)
	reset <= 1'b1;

// SDRAM controller
sdram_ctrl_splitcache sdram_ctrl (
  // sys
  .sysclk       (clk_114          ),
  .clk7_en      (clk_7_en         ),
  .clk28_en     (tg68_ena28       ),
  .reset_in     (reset            ),
  .cache_rst    (1'b1             ),
  .reset_out    (reset_out        ),
  .cache_inhibit(cache_inhibit    ),
  .cacheline_clr(1'b0             ),
  .cpu_cache_ctrl(4'b0011         ),
  // sdram
  .sdaddr       (DRAM_ADDR        ),
  .sd_cs        (sdram_cs         ),
  .ba           (sdram_ba         ),
  .sd_we        (DRAM_WE_N        ),
  .sd_ras       (DRAM_RAS_N       ),
  .sd_cas       (DRAM_CAS_N       ),
  .dqm          (sdram_dqm        ),
  .sdata_i      (DRAM_DQ          ),
  .sdata_o      (DRAM_DQ_O        ),
  .sdata_oe     (sdram_oe         ),
  // host
  .hostWR       (bridge_dat_w     ),
  .hostAddr     (bridge_adr[25:2] ),
  .hostce       (bridge_cs        ),
  .hostwe       (bridge_we        ),
  .hostbytesel  (bridge_bytesel   ),
  .hostRD       (bridge_dat_r     ),
  .hostena      (bridge_ack       ),
  // chip
  .chipAddr     ({2'b00, ram_address[21:1]}),
  .chipL        (_ram_ble         ),
  .chipU        (_ram_bhe         ),
  .chipL2       (1'b1             ),
  .chipU2       (1'b1             ),
  .chipRW       (_ram_we          ),
  .chip_dma     (_ram_oe          ),
  .chipWR       (ram_data         ),
  .chipWR2      (ram_data2        ),
  .chipRD       (ramdata_in       ),
  .chip48       (                 ),
  // RTG
  .rtgAddr      (rtgAddr          ),
  .rtgce        (rtgce            ),
  .rtgfill      (rtgfill          ),
  .rtgRd        (rtgRd            ),
  .rtgack       (rtgack           ),
  .rtgpri       (rtgpri           ),
  // Audio
  .audAddr      (audAddr          ),
  .audce        (audce            ),
  .audfill      (audfill          ),
  .audRd        (audRd            ),
  .audack       (audack           ),
  // cpu
  .cpuAddr      (cpu_adr[25:1]),
  .cpustate     (cpu_state    ),
  .cpuL         (tg68_clds        ),
  .cpuU         (tg68_cuds        ),
  .cpuWR        (tg68_dat_out     ),
  .cpuRD        (tg68_dat_in      ),
  .enaWRreg     (tg68_ena28       ),
  .ena7RDreg    (tg68_ena7RD      ),
  .ena7WRreg    (tg68_ena7WR      ),
  .cpuena       (tg68_cpuena      )
);

endmodule

