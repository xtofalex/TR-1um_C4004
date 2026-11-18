# C4004 — formal verification report

Thank you for publishing the C4004 in full, from RTL to the taped-out netlist.
A complete open design like this is rare, and it made the study below possible.

We examined the design with three open-source tools from keplertech, without
modifying it:

* [**Kepler-Formal**](https://github.com/keplertech/kepler-formal): sequential
  equivalence, pin by pin and cycle by cycle, for every possible program.
* [**najaeda**](https://github.com/keplertech/naja): structural queries on the
  taped-out netlist.
* [**naja-schematic**](https://github.com/keplertech/naja-schematic):
  schematics drawn directly from the netlist.

We asked two questions:

1. Does the C4004 behave like an independently written 4004? For the
   comparison we used `MCS4_CPU` by Mr. Maruyama
   ([ttsky25a_MCS4_CPU](https://github.com/munetomo-maruyama/ttsky25a_MCS4_CPU)).
2. Is the taped-out netlist the same machine as the RTL?

Every difference reported below was also reproduced in simulation.

## Results

| Check | Result | Time |
|---|---|---|
| C4004 vs MCS4_CPU | first difference at cycle 39 (X1) | 1 s |
| … X1 not observed | difference at cycle 50 (JCN on TEST) | 15 s |
| … TEST held constant | difference at cycle 74 (stack) | 47 min |
| … stack kept within 3 levels | **`d_oe` (outside X1), `sync`, `cm_rom` proved equal**. `d_out`, `cm_ram`: no difference through cycle 73 | 5–26 min |
| RTL vs `openroad/c4004_core_syn.v` | **16 of 23 signals proved equal**, including the SRAM address, CE and WR, for any SRAM contents | 13.5 min |

"Proved" means proved for every reachable state, not sampled. For the signals
that did not finish within the solver budget, the bounded result holds, and
lockstep simulation found 0 mismatches over 5 × 10⁶ cycles.

## Observations

**1. X1: the C4004 follows Intel.** The C4004 copies the M2 nibble onto the bus
at X1, exactly as Intel documents ("the 4004 simply copies the data which it
received at M2"). MCS4_CPU leaves the bus floating there.
*Counterexample: `29`.*

**2. Subroutine stack.** In Intel's 4004 the PC is one of the four stack
registers, which gives three nesting levels. The C4004 keeps the PC in
flip-flops, so after an overflow or underflow it returns to a different
address. *Counterexample: `0F C8 CA C2 C0` → 0x000 in the C4004, 0x001 in
MCS4_CPU.* Programs that respect the nesting limit are not affected.

**3. When JCN samples TEST.** In the netlist, TEST is sampled by exactly one
flip-flop, `cond_lat` (found with najaeda), at the end of X2 of the first
cycle. MCS4_CPU samples it in the second cycle. *Counterexample: `19 21`.*
We could not find the answer in Intel's manuals. We would be glad to hear
your view, since TEST polling loops are common in 4004 programs.

**4. SRC reads the bus at mid-M2.** najaeda shows that `D[3:1]` reaches the
SRAM address through two gates, with no flip-flop in between. It is the only
data input that does. `SRAM128.lib` asks for the address to be held while CE is
high, so the ROM must present OPA by the middle of M2.
*Counterexample: `68 29` (INC R8; SRC P4): with a late OPA, R2 is sent instead
of R8.* Kepler-Formal raised this because it also considers a bus that changes
at the falling edge. It may be worth confirming against the timing of the
test-board ROM.

![D[3:1] → BUFTH → MUX2 → SRAM A[3:1], selected by sram_src_m2_q](img/sram_addr_from_bus.png)

*Drawn by naja-schematic `render` from the netlist and Liberty files.*

## The netlist

Kepler-Formal compared the netlist produced by Yosys and
`insert_high_fo_buffers.py` with the RTL, treating the SRAM as a black box.
* Proved equal: `d_out[0,2,3]`, `d_oe`, `d_hiz`, `sync`, `cm_rom`,
  `cm_ram[2]`, SRAM `A[4:0]`, `CE`, `WR`, `DIN[3]`.
* The remaining signals are bounded, with 0 mismatches in 5 × 10⁶ simulated
  cycles.
* **No synthesis or buffering error was found.**

## Reproduce

```sh
./gen_cfg.sh && ./run_sec.sh x1 k_induction 80          # one SEC run
./replay.sh x1 results/x1_k_induction_k80/run.log 34     # replay its counterexample
python naja/structural_query.py ../openroad/c4004_core_syn.v \
  ../module/STDCELL/tr1um_typ_5v0_25c.lib ../module/SRAM128/SRAM128.lib   # najaeda
```

Method, every run and the exact commands are in [DETAILS.md](DETAILS.md).
We would be grateful for any comments or corrections.
