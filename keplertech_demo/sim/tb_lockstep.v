// Lockstep random simulation of the two SEC wrappers (cfg/<cfg>_{c4004,ref}.v,
// module names suffixed _A (C4004) and _B (reference) by sim/prep.sh).
// Plusargs: +seed=<n> +ncyc=<n> +edge=<pos|neg> +stop=<n first mismatches to print>
`timescale 1ns/1ps
module tb_lockstep;
    reg clk = 0, rst = 1, test = 0;
    reg [3:0] d_in = 0;
    always #5 clk = ~clk;

    wire       oeA, oeB, syA, syB, crA, crB;
    wire [3:0] dA, dB, cmA, cmB;
    cpu_top_A A (.clk(clk), .rst(rst), .test(test), .d_in(d_in),
                 .bus_oe(oeA), .bus_d(dA), .sync(syA), .cm_rom(crA), .cm_ram(cmA));
    cpu_top_B B (.clk(clk), .rst(rst), .test(test), .d_in(d_in),
                 .bus_oe(oeB), .bus_d(dB), .sync(syB), .cm_rom(crB), .cm_ram(cmB));

    integer seed, seed0, ncyc, stopn, cyc, mism, first_mism, firstA1, firstB1, firstSA, firstSB;
    reg     negedge_stim;
    reg [8*8-1:0] edge_s;
    integer n_jms, n_bbl, n_jcn, n_src, n_fin, n_jin, n_isz, n_io, maxsp;
    integer n_jms_blk, n_bbl_blk;

    wire [10:0] vA = {oeA, dA, syA, crA, cmA};
    wire [10:0] vB = {oeB, dB, syB, crB, cmB};

    // C4004 internals for diagnostics
    wire [2:0] phA  = A.u_core.phase;
    wire       idA  = A.u_core.init_done;
    wire [3:0] oprA = A.u_core.opr;
    wire [3:0] opaA = A.u_core.opa;
    wire [1:0] spA  = A.u_core.sp;
    wire       tcA  = A.u_core.two_cycle;

    initial begin
        if (!$value$plusargs("seed=%d", seed)) seed = 1;
        seed0 = seed;
        if (!$value$plusargs("ncyc=%d", ncyc)) ncyc = 100000;
        if (!$value$plusargs("stop=%d", stopn)) stopn = 3;
        if (!$value$plusargs("edge=%s", edge_s)) edge_s = "pos";
        negedge_stim = (edge_s == "neg");
        mism = 0; first_mism = -1; firstA1 = -1; firstB1 = -1; firstSA = -1; firstSB = -1;
        n_jms = 0; n_bbl = 0; n_jcn = 0; n_src = 0; n_fin = 0; n_jin = 0; n_isz = 0; n_io = 0;
        n_jms_blk = 0; n_bbl_blk = 0; maxsp = 0;

        // 3 reset cycles, then random stimulus. cyc = post-reset clock index:
        // cyc=k means the k-th rising edge after rst was released.
        repeat (3) @(posedge clk);
        #1 rst = 0;
        for (cyc = 1; cyc <= ncyc; cyc = cyc + 1) begin
            if (negedge_stim) begin @(negedge clk); #1; end
            else              begin #0; end
            d_in = $random(seed);
            test = $random(seed);
            @(posedge clk); #1;
            check;
        end
        $display("RESULT seed=%0d edge=%0s cycles=%0d mismatches=%0d first=%0d firstSync C4004=%0d REF=%0d firstA1 C4004=%0d REF=%0d",
                 seed0, edge_s, ncyc, mism, first_mism, firstSA, firstSB, firstA1, firstB1);
        $display("COVER JMS=%0d (nop'd %0d) BBL=%0d (nop'd %0d) maxSP=%0d JCN=%0d ISZ=%0d SRC=%0d FIN=%0d JIN=%0d IO=%0d",
                 n_jms, n_jms_blk, n_bbl, n_bbl_blk, maxsp, n_jcn, n_isz, n_src, n_fin, n_jin, n_io);
        $finish;
    end

    // Sample 1 ns after each rising edge. Stimulus changes either 1 ns after the
    // rising edge (+edge=pos) or 1 ns after the falling edge (+edge=neg).
    task check;
        begin
            if (syA && firstSA < 0) firstSA = cyc;
            if (syB && firstSB < 0) firstSB = cyc;
            if (idA && phA == 0 && firstA1 < 0) firstA1 = cyc;
            if (B.u_cpu.state == 8'h01 && firstB1 < 0) firstB1 = cyc;
            if (idA && phA == 7 && !tcA) begin
                case (oprA)
                    4'h1: n_jcn = n_jcn + 1;
                    4'h2: if (opaA[0]) n_src = n_src + 1;
                    4'h3: if (opaA[0]) n_jin = n_jin + 1; else n_fin = n_fin + 1;
                    4'h5: n_jms = n_jms + 1;
                    4'h7: n_isz = n_isz + 1;
                    4'hC: n_bbl = n_bbl + 1;
                    4'hE: n_io  = n_io + 1;
                endcase
            end
`ifdef HAS_STACK_ENV
            if (A.u_env.in_x3 && A.u_env.blocked && !A.u_env.second) begin
                if (A.u_env.depth == 3) n_jms_blk = n_jms_blk + 1; else n_bbl_blk = n_bbl_blk + 1;
            end
`endif
            if (spA > maxsp) maxsp = spA;
            if (vA !== vB) begin
                mism = mism + 1;
                if (first_mism < 0) first_mism = cyc;
                if (mism <= stopn)
                    $display("DIFF cyc=%0d phase=%0d opr=%h opa=%h sp=%0d two_cycle=%0d | C4004 oe=%b d=%h sync=%b cmrom=%b cmram=%b | REF oe=%b d=%h sync=%b cmrom=%b cmram=%b",
                             cyc, phA, oprA, opaA, spA, tcA, oeA, dA, syA, crA, cmA, oeB, dB, syB, crB, cmB);
            end
        end
    endtask
endmodule
