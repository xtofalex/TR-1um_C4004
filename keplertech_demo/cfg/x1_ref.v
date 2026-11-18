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
// Observation layer, included by both wrappers.
// Expects: oe_raw, dout_raw[3:0] (active-high core bus outputs) and
//          env_ph / env_ph_valid (phase recovered from the design's own sync).
// `MASK_X1`: the data bus (bus_oe and bus_d) is not observed during X1.

wire obs_mask = env_ph_valid & (env_ph == 3'd5);



assign bus_oe = oe_raw & ~obs_mask;
assign bus_d  = bus_oe ? dout_raw : 4'd0;
endmodule
// Environment model shared by both SEC wrappers (instantiated identically in
// wrap_c4004.v and wrap_ref.v). It sits between the top-level d_in/test pins
// and the CPU core, and recovers the 4004 state phase from the design's OWN
// sync output (sync is high in X3, so the next clock is A1).
//
// Always on:
//   d_in and test are registered on the rising edge before reaching the core.
//   Kepler-Formal SEC evaluates negedge state with the same input vector as the
//   preceding posedge, while the C4004 routes d_in combinationally into its
//   negedge-clocked SRAM address (SRC pre-read in M2). Registering the inputs
//   removes that mixed-edge combinational input path; it is a pure 1-clock
//   delay applied identically to both designs.
//
// `STACK_ENV`: restrict programs to stack-legal ones. Tracks subroutine depth
//   (0..3). In M1/M2 of an instruction's FIRST word, a JMS at depth 3 or a BBL
//   at depth 0 is replaced by NOP (00). Two-word instructions: JCN(1), FIM(2,
//   OPA[0]=0), FIN(3, OPA[0]=0), JUN(4), JMS(5), ISZ(7).
//
// `TEST_CONST`: TEST is captured while rst is high and then held, so it is a
//   free but constant value per run.
module env_filter (
    input  wire       clk,
    input  wire       rst,
    input  wire [3:0] d_in,
    input  wire       test,
    input  wire       sync,      // this design's own SYNC (high in X3)
    output wire [3:0] d_core,
    output wire       test_core,
    output reg  [2:0] ph,        // recovered phase: 0=A1 ... 3=M1 4=M2 5=X1 ... 7=X3
    output reg        ph_valid   // 1 once the first SYNC has been seen
);
    // ---- input registers (always) ----
    reg [3:0] d_q;
    reg       t_q;
    always @(posedge clk) begin
        if (rst) begin
            d_q <= 4'd0;
            t_q <= test;
        end else begin
            d_q <= d_in;



            t_q <= test;

        end
    end





    assign test_core = t_q;


    // ---- phase recovery from the design's own sync ----
    always @(posedge clk) begin
        if (rst) begin
            ph       <= 3'd0;
            ph_valid <= 1'b0;
        end else if (sync) begin
            ph       <= 3'd0;
            ph_valid <= 1'b1;
        end else begin
            ph       <= ph + 3'd1;
        end
    end


















































    assign d_core = d_q;

endmodule
//===========================================================
// MCS-4 Project
//-----------------------------------------------------------
// File Name   : mcs4_cpu.v
// Description : MCS-4 CPU
//-----------------------------------------------------------
// History :
// Rev.01 2025.05.19 M.Maruyama First Release
//-----------------------------------------------------------
// Copyright (C) 2025 M.Maruyama
//===========================================================

`default_nettype none

//---------------
// State Number
//---------------









//======================================
// Module : CPU Core
//======================================
module MCS4_CPU
(
    input  wire       CLK,      // clock
    input  wire       RES_N,    // reset_n
    //
    output wire       SYNC_N,   // Sync Signal
    input  wire [3:0] DATA_I,   // Data Input
    output wire [3:0] DATA_O,   // Data Output
    output wire       DATA_OE,  // Data Output Enable
    output wire       CM_ROM_N, // Memory Control for ROM
    output wire [3:0] CM_RAM_N, // Memory Control for RAM
    input  wire       TEST      // Test Input
);

integer i;

//--------------------
// Main CPU Resource
//--------------------
wire [11:0] pc;      // Program Counter
wire [11:0] pc_next; // Next PC
reg  [ 3:0] acc;     // Accumulator
reg         cy;      // Carry Borrow Flag
reg  [ 3:0] r[0:15]; // Index Registers
wire [ 3:0] rn;      // Index Register specified by opropa0
wire [ 7:0] rp;      // Index Register Pair specified by opropa0
reg  [ 2:0] dcl;     // Designate Comand Line
reg  [ 7:0] src;     // Send Register Control

//---------------------------------
// State Count
//---------------------------------
reg  [7:0] state;
reg  [7:0] state_next;
reg        multi_cycle;
reg        multi_cycle_inc;
//
always @(posedge CLK, negedge RES_N)
begin
    if (~RES_N)
        state <= 8'b00000000;
    else
        state <= state_next;
end
//
always @*
begin
    casez(state)
        8'b00000000 : state_next = 8'b00000001;
        8'b10000000 : state_next = 8'b00000001;
        default     : state_next = {state[6:0], state[7]}; // rotate left
    endcase
end

//----------------------------------
// Control of 2-Cycle Instruction
//----------------------------------
always @(posedge CLK, negedge RES_N)
begin
    if (~RES_N)
        multi_cycle <= 1'b0;
    else if (multi_cycle_inc)
        multi_cycle <= ~multi_cycle;
end

//------------------------
// Generate Sync Signal
//------------------------
assign SYNC_N = ~state_next[0];

//----------------------------
// Program Counter and Stack
//----------------------------
reg  [11:0] stack[0:3];
reg  [ 1:0] sp;
wire [11:0] pc_plus_one;
reg         pc_inc;
reg         pc_set;
reg         pc_push;
reg         pc_pop;
//
assign pc = stack[sp];
//
always @(posedge CLK, negedge RES_N)
begin
    if (~RES_N)
    begin
        stack[0] <= 12'h000;
        stack[1] <= 12'h000;
        stack[2] <= 12'h000;
        stack[3] <= 12'h000;
    end
    else if (pc_inc | pc_set)
        stack[sp] <= pc_next; // PC
end
//
always @(posedge CLK, negedge RES_N)
begin
    if (~RES_N)
        sp <= 2'b00;
    else if (pc_push)
        sp <= sp + 2'b01;
    else if (pc_pop)
        sp <= sp + 2'b11; // minus one
end

//-------------------------
// Instruction Fetch
//-------------------------
reg  [7:0] opropa0;
reg  [7:0] opropa1;
wire [3:0] data_o_rom_addr;
reg        do_fin;
//
assign data_o_rom_addr = (state[0] & do_fin)? r[1] // Lower Bits
                       : (state[1] & do_fin)? r[0] // Middle Bits
                       : (state[2] & do_fin)? pc_plus_one[11:8]
                       : (state[0])? pc[ 3:0]
                       : (state[1])? pc[ 7:4]
                       : (state[2])? pc[11:8]
                       : 4'b0000;
//
always @(posedge CLK, negedge RES_N)
begin
    if (~RES_N)
    begin
        opropa0 <= 8'h00;
        opropa1 <= 8'h00;
    end
    else if ((state[3]) & ~multi_cycle & ~do_fin)
        opropa0[7:4] <= DATA_I; // OPR
    else if ((state[4]) & ~multi_cycle & ~do_fin)
        opropa0[3:0] <= DATA_I; // OPA
    else if ((state[3]) &  multi_cycle & ~do_fin)
        opropa1[7:4] <= DATA_I; // OPR
    else if ((state[4]) &  multi_cycle & ~do_fin)
        opropa1[3:0] <= DATA_I; // OPA
end

//--------------------
// Next PC
//--------------------
reg pc_target_jcn;
reg pc_target_jun;
reg pc_target_jin;
//
assign pc_plus_one = pc + 12'h001;
assign pc_next = (pc_inc       )?  pc_plus_one
               : (pc_target_jcn)? {pc_plus_one[11:8], opropa1[7:0]}
               : (pc_target_jun)? {opropa0[3:0]     , opropa1[7:0]}
               : (pc_target_jin)? {pc_plus_one[11:8], rp}
               : pc;

//---------------------------------
// ALU : Arithmetic Logical Unit
//---------------------------------
reg  [3:0] alu_a;
reg        alu_a_acc;
reg        alu_a_rn;
reg        alu_a_opropa;
//
reg  [3:0] alu_b;
reg        alu_b_acc;
reg        alu_b_rn;
reg        alu_b_data_i;
//
reg        alu_c;
reg        alu_c_cy;
reg        alu_c_set;
//
reg  [4:0] alu;
reg        alu_thru_a;
reg        alu_thru_b;
reg        alu_add;
reg        alu_sub;
reg        alu_ral;
reg        alu_rar;
reg        alu_daa;
//
always @*
begin
    casez({alu_a_acc, alu_a_rn, alu_a_opropa})
        3'b1??  : alu_a = acc;
        3'b?1?  : alu_a = rn;
        3'b??1  : alu_a = opropa0[3:0];
        default : alu_a = 4'b0000;
    endcase
end
//
always @*
begin
    casez({alu_b_acc, alu_b_rn, alu_b_data_i})
        3'b1??  : alu_b = acc;
        3'b?1?  : alu_b = rn;
        3'b??1  : alu_b = DATA_I;
        default : alu_b = 4'b0000;
    endcase
end
//
always @*
begin
    casez({alu_c_cy, alu_c_set})
        2'b1?   : alu_c = cy;
        2'b?1   : alu_c = 1'b1;
        default : alu_c = 1'b0;
    endcase
end
//
always @*
begin
    casez({alu_thru_a, alu_thru_b, alu_add, alu_sub, alu_ral, alu_rar, alu_daa})
        7'b1?????? : alu = {1'b0, alu_a};
        7'b?1????? : alu = {1'b0, alu_b};
        7'b??1???? : alu = {1'b0, alu_a} + {1'b0,  alu_b} + {4'b0000,  alu_c};
        7'b???1??? : alu = {1'b0, alu_a} + {1'b0, ~alu_b} + {4'b0000, ~alu_c};
        7'b????1?? : alu = {alu_a[3], alu_a[2:0], cy};
        7'b?????1? : alu = {alu_a[0], cy, alu_a[3:1]};
        7'b??????1 : alu = {1'b0, alu_a} + 5'b00110;
        default    : alu = 5'b0_0000;
    endcase
end

//---------------
// KBP Table
//---------------
reg [3:0] kbp;
//
always @*
begin
    casez (acc)
         4'b0000 : kbp = 4'b0000;
         4'b0001 : kbp = 4'b0001;
         4'b0010 : kbp = 4'b0010;
         4'b0100 : kbp = 4'b0011;
         4'b1000 : kbp = 4'b0100;
         default : kbp = 4'b1111;
    endcase
end

//-------------------------------
// ACC : Accumulator
//-------------------------------
reg acc_alu;
reg acc_kbp;
//
always @(posedge CLK, negedge RES_N)
begin
    if (~RES_N)
        acc <= 4'b0000;
    else if (acc_alu)
        acc <= alu[3:0];
    else if (acc_kbp)
        acc <= kbp;
end

//-------------------
// Carry Flag CY
//-------------------
wire cy_next;
reg  cy_set;
reg  cy_inv;
reg  cy_wrt;
//
assign cy_next = alu[4];
//
always @(posedge CLK, negedge RES_N)
begin
    if (~RES_N)
        cy <= 1'b0;
    else if (cy_set)
        cy <= 1'b1;
    else if (cy_inv)
        cy <= ~cy;
    else if (cy_wrt)
        cy <= cy_next;
end

//-------------------------------
// Rn : Index Registers
//-------------------------------
wire [3:0] rp0;
wire [3:0] rp1;
reg        rp_fim;
reg        rn_alu;
reg        rn_acc;
wire       rn_zero;
wire [3:0] rn_index;
wire [3:0] rn_index0;
wire [3:0] rn_index1;
//
assign rn_index  = opropa0[3:0];
assign rn_index0 = opropa0[3:0] & 4'b1110;
assign rn_index1 = opropa0[3:0] | 4'b0001;
//
always @(posedge CLK, negedge RES_N)
begin
    if (~RES_N)
        for (i = 0; i < 16; i = i + 1) r[i] = 4'b0000;
    else if (rp_fim)
    begin
        r[rn_index0] <= opropa1[7:4];
        r[rn_index1] <= opropa1[3:0];
    end
    else if (do_fin & state[3])
        r[rn_index0] <= DATA_I;
    else if (do_fin & state[4])
        r[rn_index1] <= DATA_I;
    else if (rn_alu)
        r[rn_index] <= alu[3:0];
    else if (rn_acc)
        r[rn_index] <= acc;
end
//
assign rn  = r[rn_index];
assign rp0 = r[rn_index0];
assign rp1 = r[rn_index1];
assign rp  = {rp0, rp1};
assign rn_zero = (rn == 4'b0000);

//-------------------------------
// DCL : Designate Command Line
//-------------------------------
reg        dcl_set;
wire [3:0] dcl_convert;
//
always @(posedge CLK, negedge RES_N)
begin
    if (~RES_N)
        dcl <= 3'b000;
    else if (dcl_set)
        dcl <= acc[2:0];
end
//
assign dcl_convert[0] = (dcl == 3'b000);
assign dcl_convert[1] = dcl[0];
assign dcl_convert[2] = dcl[1];
assign dcl_convert[3] = dcl[2];

//-------------------------------
// SRC : Send Register Control
//-------------------------------
reg       src_set;
//
always @(posedge CLK, negedge RES_N)
begin
    if (~RES_N)
        src <= 8'h00;
    else if (src_set)
        src <= rp;
end

//-------------------
// CM_ROM Output
//-------------------
wire cm_rom_at_a3; // Assert at A3 always
wire cm_rom_at_m2; // Assert at M2 of I/O and RAM Access Instruction
reg  cm_rom_at_x2; // Assert at X2 of SRC Instruction
//
assign cm_rom_at_a3 = state[2];
assign cm_rom_at_m2 = state[4] & (opropa0[7:4] == 4'b1110);
//
assign CM_ROM_N = ~cm_rom_at_a3  // NOR
                & ~cm_rom_at_m2
                & ~cm_rom_at_x2;

//-------------------
// CM_RAM Output
//-------------------
wire [3:0] cm_ram_at_a3; // Assert at A3 always
wire       cm_ram_at_m2; // Assert at M2 of I/O and RAM Access Instruction
reg        cm_ram_at_x2; // Assert at X2 of SRC Instruction
//
assign cm_ram_at_a3 = {4{state[2]}} & dcl_convert;
assign cm_ram_at_m2 = state[4] & (opropa0[7:4] == 4'b1110);
//
assign CM_RAM_N = ~cm_ram_at_a3 // NOR
                & ~({4{cm_ram_at_m2}} & dcl_convert)
                & ~({4{cm_ram_at_x2}} & dcl_convert);

//----------------------
// Data Bus Output
//----------------------
wire [3:0] data_o_src;
reg        data_o_src_at_x2;
reg        data_o_src_at_x3;
wire [3:0] data_o_acc;
reg        data_o_acc_at_x2;
//
assign data_o_src = (data_o_src_at_x2)? src[7:4]
                  : (data_o_src_at_x3)? src[3:0]
                  : 4'b0000;
assign data_o_acc = (data_o_acc_at_x2)? acc : 4'b0000;
//
assign DATA_O = data_o_rom_addr
              | data_o_src
              | data_o_acc;
//
assign DATA_OE = state[0] | state[1] | state[2]
               | data_o_src_at_x2 | data_o_src_at_x3
               | data_o_acc_at_x2;
                
//-----------------
// TEST Input
//-----------------
reg test_sync;
//
always @(posedge CLK, negedge RES_N)
begin
    if (~RES_N)
        test_sync <= 1'b0;
    else
        test_sync <= TEST;
end

//-------------------
// Condition  for JCN
//-------------------
wire c1, c2, c3, c4;
wire jcn;
//
assign c1 = opropa0[3]; // C1: Invert Jump Condition
assign c2 = opropa0[2]; // C2: Jump if ACC==0
assign c3 = opropa0[1]; // C3: Jump if CY==1
assign c4 = opropa0[0]; // C4: Jump if TEST==0
//
assign jcn = c1 ^ (c2 & (acc == 4'b0000) | c3 & cy | c4 & ~test_sync);

//-------------------
// Condition for DAA
//-------------------
// Input   |Output
// ACC  CY |ACC  CY
// --------+---------
// 0-9  0  |0-9  0 (No Carry, CY unchanged)
// 0-9  1  |6-F  1 (No Carry, CY unchanged)
// A-F  0  |0-5  1 (Carry, CY changed)
// A-F  1  |0-5  1 (Carry, CY changed)
wire daa;
//
assign daa = cy | (acc > 4'b1001);

//-------------------------
// Instruction Control
//-------------------------
always @*
begin
    // Default Control Signal Level
    pc_inc  = 1'b0;
    pc_set  = 1'b0;
    pc_push = 1'b0;
    pc_pop  = 1'b0;
    multi_cycle_inc = 1'b0;
    //
    dcl_set = 1'b0;
    src_set = 1'b0;
    //
    rp_fim  = 1'b0;
    rn_alu  = 1'b0;
    rn_acc  = 1'b0;
    //
    acc_alu = 1'b0;
    acc_kbp = 1'b0;
    //
    alu_a_acc    = 1'b0;
    alu_a_rn     = 1'b0;
    alu_a_opropa = 1'b0;
    alu_b_acc    = 1'b0;
    alu_b_rn     = 1'b0;
    alu_b_data_i = 1'b0;
    alu_c_cy     = 1'b0;
    alu_c_set    = 1'b0;
    alu_thru_a   = 1'b0;
    alu_thru_b   = 1'b0;
    alu_add      = 1'b0;
    alu_sub      = 1'b0;
    alu_ral      = 1'b0;
    alu_rar      = 1'b0;
    alu_daa      = 1'b0;
    //
    cy_set = 1'b0;
    cy_inv = 1'b0;
    cy_wrt = 1'b0;
    //
    cm_rom_at_x2 = 1'b0;
    cm_ram_at_x2 = 1'b0;
    data_o_src_at_x2 = 1'b0;
    data_o_src_at_x3 = 1'b0;
    data_o_acc_at_x2 = 1'b0;
    //
    pc_target_jcn = 1'b0;
    pc_target_jun = 1'b0;
    pc_target_jin = 1'b0;
    //
    do_fin = 1'b0;
    
    // Set Contol Signals for each Instruction Sequence
    casez(opropa0)
        //--------------------------------------
        // NOP : No Operation
        8'b0000_0000 :
        begin
            pc_inc  = state[7];
        end
        //--------------------------------------
        // JCN : Jump Conditional
        8'b0001_???? :
        begin
            if (~multi_cycle | ~jcn)
            begin
                pc_inc = state[7];
            end
            else //  if (multi_cycle & jcn)
            begin
                pc_target_jcn = state[7];
                pc_set        = state[7];   
            end
            //
            multi_cycle_inc = state[7];
        end
        //--------------------------------------
        // FIM : Fetch Immediate from ROM
        8'b0010_???0 :
        begin
            if (~multi_cycle)
            begin
               // do nothing
            end
            else
            begin
                rp_fim = state[7];
            end
            //
            multi_cycle_inc = state[7];
            pc_inc  = state[7];
        end
        //--------------------------------------
        // SRC : Send Register Control
        8'b0010_???1 :
        begin
            src_set          = state[5];
            cm_rom_at_x2     = state[6];
            cm_ram_at_x2     = state[6];
            data_o_src_at_x2 = state[6];
            data_o_src_at_x3 = state[7];
            pc_inc           = state[7];
        end
        //--------------------------------------
        // FIN : Fetch Indirect from ROM
        8'b0011_???0 :
        begin
            if (~multi_cycle)
            begin
               // do nothing
            end
            else
            begin
                do_fin = 1'b1;
            end
            //
            multi_cycle_inc = state[7];
            pc_inc  = state[7] & multi_cycle;
        end
        //--------------------------------------
        // JIN : Jump Indirect
        8'b0011_???1 :
        begin
            pc_target_jin = state[7];
            pc_set        = state[7];
        end
        //--------------------------------------
        // JUN : Jump Unconditional
        8'b0100_???? :
        begin
            if (~multi_cycle)
            begin
                pc_inc = state[7];
            end
            else // if (multi_cycle)
            begin
                pc_target_jun = state[7];
                pc_set        = state[7];
            end
            //
            multi_cycle_inc = state[7];
        end
        //--------------------------------------
        // JMS : Jump to Subroutine
        8'b0101_???? :
        begin
            if (~multi_cycle)
            begin
                pc_inc = state[7];
            end
            else // if (multi_cycle)
            begin
                pc_inc        = state[6];
                pc_push       = state[6];
                //
                pc_target_jun = state[7];
                pc_set        = state[7];   
            end
            //
            multi_cycle_inc = state[7];
        end
        //--------------------------------------
        // INC : Increment Index Register
        8'b0110_???? :
        begin
            alu_a_rn  = state[7];
            alu_c_set = state[7];
            alu_add   = state[7];
            rn_alu    = state[7];
            pc_inc    = state[7];
        end
        //--------------------------------------
        // ISZ : Increment Index Register, Skip if Zero
        8'b0111_???? :
        begin
            if (~multi_cycle)
            begin
                alu_a_rn  = state[7];
                alu_c_set = state[7];
                alu_add   = state[7];
                rn_alu    = state[7];
                pc_inc    = state[7];
            end
            else
            begin
                pc_target_jcn = (~rn_zero)? state[7] : 1'b0;
                pc_set        = (~rn_zero)? state[7] : 1'b0;
                //
                pc_inc        = ( rn_zero)? state[7] : 1'b0;
            end        
            //
            multi_cycle_inc = state[7];
        end
        //--------------------------------------
        // ADD : Add Index Register to ACC
        8'b1000_???? :
        begin
            alu_a_acc = state[7];
            alu_b_rn  = state[7];
            alu_c_cy  = state[7];
            alu_add   = state[7];
            acc_alu   = state[7];
            cy_wrt    = state[7];
            pc_inc    = state[7];
        end
        //--------------------------------------
        // SUB : Subtract Index Register from ACC
        8'b1001_???? :
        begin
            alu_a_acc = state[7];
            alu_b_rn  = state[7];
            alu_c_cy  = state[7];
            alu_sub   = state[7];
            acc_alu   = state[7];
            cy_wrt    = state[7];
            pc_inc    = state[7];
        end
        //--------------------------------------
        // LD : Load Index Register to ACC
        8'b1010_???? :
        begin
            alu_a_rn   = state[7];
            alu_thru_a = state[7];
            acc_alu    = state[7];
            pc_inc     = state[7];
        end
        //--------------------------------------
        // XCH : Exchange Load Index Register and ACC
        8'b1011_???? :
        begin
            rn_acc     = state[7];
            alu_a_rn   = state[7];
            alu_thru_a = state[7];
            acc_alu    = state[7];
            pc_inc     = state[7];
        end
        //--------------------------------------
        // BBL : Branch Back and Load to ACC
        8'b1100_???? :
        begin
            pc_pop       = state[6];
            alu_a_opropa = state[7];
            alu_thru_a   = state[7];
            acc_alu      = state[7];
            pc_set       = state[7];   
        end
        //--------------------------------------
        // LDM : Load Imm4 to ACC
        8'b1101_???? :
        begin
            alu_a_opropa = state[7];
            alu_thru_a   = state[7];
            acc_alu      = state[7];
            pc_inc       = state[7];
        end
        //--------------------------------------
        // WRM : Write RAM_CH from ACC             8'b1110_0000
        // WMP : Write RAM Output Port from ACC    8'b1110_0001
        // WRR : Write ROM Output Port from ACC    8'b1110_0010
        // WPM : Write R/W Program Memory from ACC 8'b1110_0011
        // WR0 : Write RAM Status 0 from ACC       8'b1110_0100
        // WR1 : Write RAM Status 1 from ACC       8'b1110_0101
        // WR2 : Write RAM Status 2 from ACC       8'b1110_0110
        // WR3 : Write RAM Status 3 from ACC       8'b1110_0111
        8'b1110_0??? :
        begin
            data_o_acc_at_x2 = state[6];
            pc_inc           = state[7];
        end
        //--------------------------------------
        // RDM : Read RAM_CH to ACC         8'b1110_1001
        // RDR : Read ROM Input Port to ACC 8'b1110_1010
        // RD0 : Read RAM Status 0 into ACC 8'b1110_1100
        // RD1 : Read RAM Status 1 into ACC 8'b1110_1101
        // RD2 : Read RAM Status 2 into ACC 8'b1110_1110
        // RD3 : Read RAM Status 3 into ACC 8'b1110_1111
        8'b1110_1001,
        8'b1110_1010,
        8'b1110_11?? :
        begin
            alu_b_data_i = 1'b1;
            alu_thru_b   = 1'b1;
            acc_alu      = state[6];
            pc_inc       = state[7];
        end
        //--------------------------------------
        // SBM : Subtract RAM_CH from ACC
        8'b1110_1000 :
        begin
            alu_a_acc    = state[6];
            alu_b_data_i = state[6];
            alu_c_cy     = state[6];
            alu_sub      = state[6];
            acc_alu      = state[6];
            cy_wrt       = state[6];
            pc_inc       = state[7];
        end
        //--------------------------------------
        // ADM : Add RAM_CH to ACC
        8'b1110_1011 :
        begin
            alu_a_acc    = state[6];
            alu_b_data_i = state[6];
            alu_c_cy     = state[6];
            alu_add      = state[6];
            acc_alu      = state[6];
            cy_wrt       = state[6];
            pc_inc       = state[7];
        end
        //--------------------------------------
        // CLB : Clear Both ACC and CY
        8'b1111_0000 :
        begin
            acc_alu = state[7];
            cy_wrt  = state[7];
            pc_inc  = state[7];
        end
        //--------------------------------------
        // CLC : Clear CY
        8'b1111_0001 :
        begin
            cy_wrt = state[7];
            pc_inc = state[7];
        end
        //--------------------------------------
        // IAC : Increment ACC
        8'b1111_0010 :
        begin
            alu_a_acc = state[7];
            alu_c_set = state[7];
            alu_add   = state[7];
            acc_alu   = state[7];
            cy_wrt    = state[7];
            pc_inc    = state[7];
        end
        //--------------------------------------
        // CMC : Complement CY
        8'b1111_0011 :
        begin
            cy_inv = state[7];
            pc_inc = state[7];
        end
        //--------------------------------------
        // CMA : Complement ACC
        8'b1111_0100 :
        begin
            alu_b_acc = state[7];
            alu_c_set = state[7];
            alu_sub   = state[7];
            acc_alu   = state[7];
            pc_inc    = state[7];
        end
        //--------------------------------------
        // RAL : Rotate Left ACC and CY
        8'b1111_0101 :
        begin
            alu_a_acc = state[7];
            alu_ral   = state[7];
            acc_alu   = state[7];
            cy_wrt    = state[7];
            pc_inc    = state[7];
        end
        //--------------------------------------
        // RAR : Rotate Right ACC and CY
        8'b1111_0110 :
        begin
            alu_a_acc = state[7];
            alu_rar   = state[7];
            acc_alu   = state[7];
            cy_wrt    = state[7];
            pc_inc    = state[7];
        end
        //--------------------------------------
        // TCC : Transmit CY to ACC and Clear CY
        8'b1111_0111 :
        begin
            alu_c_cy = state[7];
            alu_add  = state[7]; // add only CY
            acc_alu  = state[7]; 
            cy_wrt   = state[7];
            pc_inc   = state[7];
        end
        //--------------------------------------
        // DAC : Decrement ACC
        8'b1111_1000 :
        begin
            alu_a_acc = state[7];
            alu_c_set = state[7];
            alu_sub   = state[7];
            acc_alu   = state[7];
            cy_wrt    = state[7];
            pc_inc    = state[7];
        end
        //--------------------------------------
        // TCS : Transfer CY Subtract and Clear CY
        8'b1111_1001 :
        begin
            alu_a_opropa = state[7];
            alu_c_cy     = state[7];
            alu_add      = state[7];
            acc_alu      = state[7];
            cy_wrt       = state[7];
            pc_inc       = state[7];
        end
        //--------------------------------------
        // STC : Set CY
        8'b1111_1010 :
        begin
            cy_set = state[7];
            pc_inc = state[7];
        end
        //--------------------------------------
        // DAA : Decimal Adjust ACC
        8'b1111_1011 :
        begin
            alu_a_acc = state[7];
            alu_daa   = state[7];
            acc_alu   = state[7] & daa;
            cy_wrt    = state[7] & cy_next; // if non carry, do not affect
            pc_inc    = state[7];
        end
        //--------------------------------------
        // KBP : Keyboard Process
        8'b1111_1100 :
        begin
            acc_kbp = state[7];
            pc_inc  = state[7];
        end
        //--------------------------------------
        // DCL : Designate Control Line
        8'b1111_1101 :
        begin
            dcl_set = state[7];
            pc_inc  = state[7];
        end
        //--------------------------------------
        // Others : Same as NOP
        default :
        begin
            pc_inc = state[7];
        end
        //--------------------------------------
    endcase
end

endmodule
//===========================================================
// End of File
//===========================================================
