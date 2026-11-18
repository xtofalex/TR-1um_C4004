// SEC wrapper for the reference core MCS4_CPU (ref/mcs4_cpu.v, unchanged).
// - Active-low SYNC_N / CM_ROM_N / CM_RAM_N are inverted to active-high.
// - RES_N is held low for HOLD extra clocks after rst drops so that the first
//   SYNC and first A1 line up with the C4004 (which spends 2 clocks in its reset
//   synchronizer and 32 clocks clearing its SRAM). All outputs are gated with
//   `go`: MCS4_CPU asserts SYNC while in its reset state (state==0).
module cpu_top (
    input  wire       clk,
    input  wire       rst,
    input  wire       test,
    input  wire [3:0] d_in,
    output wire       bus_oe,
    output wire [3:0] bus_d,
    output wire       sync,
    output wire       cm_rom,
    output wire [3:0] cm_ram
);
    localparam [5:0] HOLD = 6'd33;

    reg  [5:0] cnt;
    wire       go = (cnt == HOLD);
    always @(posedge clk) begin
        if (rst)      cnt <= 6'd0;
        else if (!go) cnt <= cnt + 6'd1;
    end
    wire res_n = go & ~rst;

    wire [3:0] d_core;
    wire       test_core;
    wire [2:0] env_ph;
    wire       env_ph_valid;
    wire       sync_n, cm_rom_n, data_oe;
    wire [3:0] cm_ram_n, data_o;
    wire       sync_raw = go & ~sync_n;

    env_filter u_env (
        .clk(clk), .rst(rst), .d_in(d_in), .test(test), .sync(sync_raw),
        .d_core(d_core), .test_core(test_core), .ph(env_ph), .ph_valid(env_ph_valid)
    );

    MCS4_CPU u_cpu (
        .CLK(clk), .RES_N(res_n),
        .SYNC_N(sync_n), .DATA_I(d_core), .DATA_O(data_o), .DATA_OE(data_oe),
        .CM_ROM_N(cm_rom_n), .CM_RAM_N(cm_ram_n), .TEST(test_core)
    );

    wire       oe_raw   = go & data_oe;
    wire [3:0] dout_raw = data_o;
    assign sync   = sync_raw;
    assign cm_rom = go & ~cm_rom_n;
    assign cm_ram = {4{go}} & ~cm_ram_n;
`include "observe.vh"
endmodule
