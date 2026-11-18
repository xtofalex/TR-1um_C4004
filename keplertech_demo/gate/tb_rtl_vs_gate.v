// Random lockstep: rtl/c4004_core.v vs openroad/c4004_core_syn.v (taped-out
// netlist), same random d_in/test, same SRAM128 model (rtl/sram128_model.v) on
// both sides. Compares all pins and the SRAM interface every cycle.
// Plusargs: +seed= +ncyc= +edge=pos|neg +stop=
`timescale 1ns/1ps
module tb_rtl_vs_gate;
    reg clk = 0, rst = 1, test = 0;
    reg [3:0] d_in = 0;
    always #25 clk = ~clk;
    wire [3:0] dR, dG, cmR, cmG;
    wire oeR, oeG, hzR, hzG, syR, syG, crR, crG;
    c4004_core      R (.clk(clk), .rst(rst), .test(test), .d_in(d_in), .d_out(dR), .d_oe(oeR), .d_hiz(hzR), .sync(syR), .cm_rom(crR), .cm_ram(cmR));
    c4004_core_gate G (.clk(clk), .rst(rst), .test(test), .d_in(d_in), .d_out(dG), .d_oe(oeG), .d_hiz(hzG), .sync(syG), .cm_rom(crG), .cm_ram(cmG));
    wire [14:0] pR = {oeR, hzR, dR, syR, crR, cmR, 1'b0};
    wire [14:0] pG = {oeG, hzG, dG, syG, crG, cmG, 1'b0};
    // SRAM interface (only meaningful while CE could be active)
    wire [10:0] sR = {R.u_sram.CE, R.u_sram.WR, R.u_sram.A4, R.u_sram.A3, R.u_sram.A2, R.u_sram.A1, R.u_sram.A0, R.u_sram.DIN};
    wire [10:0] sG = {G.u_sram.CE, G.u_sram.WR, G.u_sram.A4, G.u_sram.A3, G.u_sram.A2, G.u_sram.A1, G.u_sram.A0, G.u_sram.DIN};
    integer seed, seed0, ncyc, stopn, cyc, pm, sm, nprint;
    reg [8*8-1:0] edge_s;
    initial begin
        if (!$value$plusargs("seed=%d", seed)) seed = 1; seed0 = seed;
        if (!$value$plusargs("ncyc=%d", ncyc)) ncyc = 100000;
        if (!$value$plusargs("stop=%d", stopn)) stopn = 5;
        if (!$value$plusargs("edge=%s", edge_s)) edge_s = "pos";
        pm = 0; sm = 0; nprint = 0;
        repeat (3) @(posedge clk); #1 rst = 0;
        for (cyc = 1; cyc <= ncyc; cyc = cyc + 1) begin
            if (edge_s == "neg") begin @(negedge clk); #1; end
            d_in = $random(seed); test = $random(seed);
            // check SRAM interface in the low-clock half (CE may be high)
            if (edge_s == "pos") begin @(negedge clk); #1; end
            if (sR !== sG) begin sm = sm + 1; if (nprint < stopn) begin nprint = nprint + 1;
                $display("SRAM-DIFF cyc=%0d phase=%0d opr=%h | RTL ce/wr/a/din=%b | GATE=%b", cyc, R.phase, R.opr, sR, sG); end end
            @(posedge clk); #1;
            if (pR !== pG) begin pm = pm + 1; if (nprint < stopn) begin nprint = nprint + 1;
                $display("PIN-DIFF  cyc=%0d phase=%0d opr=%h opa=%h | RTL %b | GATE %b", cyc, R.phase, R.opr, R.opa, pR, pG); end end
        end
        $display("RESULT seed=%0d edge=%0s cycles=%0d pin_mismatch_cycles=%0d sram_if_mismatch_cycles=%0d", seed0, edge_s, ncyc, pm, sm);
        $finish;
    end
endmodule
