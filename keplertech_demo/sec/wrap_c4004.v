// SEC wrapper for the C4004 core (rtl/c4004_core.v, instantiated unchanged).
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
    wire [3:0] d_core;
    wire       test_core;
    wire [2:0] env_ph;
    wire       env_ph_valid;
    wire [3:0] d_out;
    wire       d_oe, d_hiz, sync_raw;

    env_filter u_env (
        .clk(clk), .rst(rst), .d_in(d_in), .test(test), .sync(sync_raw),
        .d_core(d_core), .test_core(test_core), .ph(env_ph), .ph_valid(env_ph_valid)
    );

    c4004_core u_core (
        .clk(clk), .rst(rst), .test(test_core), .d_in(d_core),
        .d_out(d_out), .d_oe(d_oe), .d_hiz(d_hiz),
        .sync(sync_raw), .cm_rom(cm_rom), .cm_ram(cm_ram)
    );

    wire       oe_raw   = d_oe;
    wire [3:0] dout_raw = d_out;
    assign sync = sync_raw;
`include "observe.vh"
endmodule
