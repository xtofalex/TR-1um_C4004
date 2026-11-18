// Replay a Kepler-Formal counterexample on both wrapped designs.
// 3 reset cycles (rst=1, test=+test_rst), then trace cycle N = inputs applied
// during frame N; frame N outputs are those after N post-reset rising edges.
// Plusargs: +memh=<file> +n=<cycles> +test_rst=<0|1> +from=<first frame to print>
//           +edge=neg : apply each frame's inputs just after the falling edge that
//           precedes its rising edge (default: just after the previous rising edge)
`timescale 1ns/1ps
module replay;
    reg clk = 0, rst = 1, test = 0;
    reg [3:0] d_in = 0;
    always #5 clk = ~clk;

    wire       oeA, oeB, syA, syB, crA, crB;
    wire [3:0] dA, dB, cmA, cmB;
    cpu_top_A A (.clk(clk), .rst(rst), .test(test), .d_in(d_in),
                 .bus_oe(oeA), .bus_d(dA), .sync(syA), .cm_rom(crA), .cm_ram(cmA));
    cpu_top_B B (.clk(clk), .rst(rst), .test(test), .d_in(d_in),
                 .bus_oe(oeB), .bus_d(dB), .sync(syB), .cm_rom(crB), .cm_ram(cmB));

    reg [7:0] tr [0:4095];
    reg [1023:0] memh;
    integer n, i, from, ndiff, first, test_rst;
    reg [8*8-1:0] edge_s;
    wire [10:0] vA = {oeA, dA, syA, crA, cmA};
    wire [10:0] vB = {oeB, dB, syB, crB, cmB};
    reg [8*2-1:0] ph_name [0:7];

    initial begin
        ph_name[0]="A1"; ph_name[1]="A2"; ph_name[2]="A3"; ph_name[3]="M1";
        ph_name[4]="M2"; ph_name[5]="X1"; ph_name[6]="X2"; ph_name[7]="X3";
        if (!$value$plusargs("memh=%s", memh)) begin $display("need +memh"); $finish; end
        if (!$value$plusargs("n=%d", n)) n = 0;
        if (!$value$plusargs("from=%d", from)) from = 0;
        if (!$value$plusargs("test_rst=%d", test_rst)) test_rst = 0;
        if (!$value$plusargs("edge=%s", edge_s)) edge_s = "pos";
        $readmemh(memh, tr);
        ndiff = 0; first = -1;
        test = test_rst[0];
        repeat (3) @(posedge clk);
        #1;
        for (i = 0; i < n; i = i + 1) begin
            if (edge_s == "neg") begin @(negedge clk); #1; end
            {rst, test, d_in} = tr[i][5:0];
            #1;
            if (vA !== vB) begin ndiff = ndiff + 1; if (first < 0) first = i; end
            if (i >= from)
                $display("cyc %3d in: rst=%b test=%b d=%h | C4004 %s%s opr=%h opa=%h sp=%0d tc=%b acc=%h cy=%b | C4004 oe=%b d=%h s=%b cr=%b cm=%b | REF oe=%b d=%h s=%b cr=%b cm=%b  REF sp=%0d %s",
                    i, rst, test, d_in,
                    A.u_core.init_done ? "" : "init:", A.u_core.init_done ? ph_name[A.u_core.phase] : "--",
                    A.u_core.opr, A.u_core.opa, A.u_core.sp, A.u_core.two_cycle, A.u_core.acc, A.u_core.cy,
                    oeA, dA, syA, crA, cmA, oeB, dB, syB, crB, cmB, B.u_cpu.sp,
                    (vA !== vB) ? "<== DIFF" : "");
            @(posedge clk); #1;
        end
        $display("REPLAY frames=%0d diff_frames=%0d first_diff=%0d", n, ndiff, first);
        $finish;
    end
endmodule
