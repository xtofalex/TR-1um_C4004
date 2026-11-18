# Details

Method, runs and commands behind [README.md](README.md).

## Setup

| item | value |
|---|---|
| Kepler-Formal | [keplertech/kepler-formal](https://github.com/keplertech/kepler-formal) `56c9e1d`, Release build in `tools/` (not committed) |
| najaeda / naja-schematic | 0.7.35 / 0.3.0 (PyPI), in `tools/naja-venv` |
| Reference core | `ref/mcs4_cpu.v`, `MCS4_CPU` from ttsky25a_MCS4_CPU @ `107eb92`, unmodified, Apache-2.0 (`ref/LICENSE`) |
| C4004 | `../rtl/c4004_core.v` and `../openroad/c4004_core_syn.v`, unmodified |
| Simulator | Icarus Verilog 13.0 |

## 1. C4004 vs MCS4_CPU

Both cores run one clock per 4004 state (A1 … X3). They are compared at the
pins only; no internal name is assumed to match.

**Wrappers (`sec/`)** give both designs the same top:
`cpu_top(clk, rst, test, d_in[3:0] → bus_oe, bus_d[3:0], sync, cm_rom, cm_ram[3:0])`.
* `wrap_ref.v` inverts MCS4_CPU's active-low outputs. It holds `RES_N` low for
  33 extra clocks so that the first SYNC (clock 33) and first A1 (clock 34)
  line up with the C4004, which clears its SRAM after reset.
* `sram128_sec.v` is the SRAM model without initial zeroing.
* `env_filter.v` is shared by both sides. It registers `d_in`/`test` and
  recovers the state phase from each design's own SYNC. It has three optional
  switches:

| switch | effect |
|---|---|
| `MASK_X1` | bus not observed in X1 (finding 1) |
| `TEST_CONST` | TEST constant during a run (finding 3) |
| `STACK_ENV` | JMS at depth 3 / BBL at depth 0 replaced by NOP (finding 2) |

**Configurations (`gen_cfg.sh` → `cfg/`)**: `strict` (none), `x1`, `x1_tc`,
`full` (all three switches). Simulation uses these same files.

| cfg | Kepler-Formal | result | time |
|---|---|---|---|
| strict | k-induction | counterexample, cycle 39 | 1 s |
| x1 | k-induction | counterexample, cycle 50 | 15 s |
| x1_tc | k-induction | counterexample, cycle 74 (shortest possible) | 47 min |
| full | PDR | `bus_oe`, `sync`, `cm_rom` proved | 26 min |
| full | k-induction | no difference through cycle 73 | – |

Lockstep random simulation (`sim/tb_lockstep.v`) found 0 mismatches in `full`
over 5 seeds × 10⁶ cycles, with stimulus changing at either clock edge. Each
counterexample was replayed on both designs (`replay.sh`, outputs in
`results/*/replay*.txt`).

## 2. Findings

**1. X1 (cycle 39, `29` = SRC P4).** The C4004 drives OPA at X1, and MCS4_CPU
floats the bus. The MCS-40 User's Manual (1974) says the 4004 "simply copies the
data which it received at M2", so the C4004 matches Intel.

**2. JCN / TEST (cycle 50, `19 21`).** The C4004 latches the condition at the
end of X2 of cycle 1, with TEST = 0, and does not jump. MCS4_CPU evaluates it in
X3 of cycle 2, from TEST during X2 of cycle 2 (TEST = 1), and jumps. The Intel
manuals reviewed do not state when TEST is sampled.

**3. Stack (cycle 74, `0F C8 CA C2 C0`).** Four BBLs at depth 0 wrap both stack
pointers back to 0. In MCS4_CPU, as in Intel's 4004 ("4 registers, one of them
is used as the program counter"), entry 0 still holds the PC 0x001. In the
C4004 it is a cleared SRAM return slot, so it returns to 0x000. For the same
reason the C4004 nests 4 levels instead of 3.

**4. SRC bus timing (`68 29`).** During M2 of SRC, the SRAM address is
`{0, D[3:1], 0}`, taken directly from the bus while CE is high. `SRAM128.lib`
requires the address to be stable from CE↑ to CE↓, so OPA must be valid by
mid-M2. Kepler-Formal checks inputs that change at the falling edge, and found
this in the `x1_noreg` configuration (`env_filter` without its input register):
SRC P4 sends R2 instead of R8 at cycle 48. The replay reproduces this with
inputs changing at the falling edge (`replay_neg.txt`); with inputs changing at
the rising edge the result is correct (`replay_pos.txt`).

## 3. RTL vs taped-out netlist (`gate/`)

`openroad/c4004_core_syn.v` (Yosys + `insert_high_fo_buffers.py`, 637 cells +
`SRAM128`) is compared with the RTL. The SRAM is cut out as a black box
(`--set-as-boundary u_sram u_sram`, `gate/sram128_bbox.v` on the RTL side). The
SRAM's input pins therefore become checked outputs, and its read data is
arbitrary.

* PDR proves 16 of 23 signals equal: `d_out[0,2,3]`, `d_oe`, `d_hiz`, `sync`,
  `cm_rom`, `cm_ram[2]`, SRAM `A[4:0]`, `CE`, `WR`, `DIN[3]`.
* k-induction finds no difference through cycle 59.
* Random lockstep simulation (`gate/tb_rtl_vs_gate.v`, cell models from
  `openroad/primitives.v`) checks the 11 pins and the 11 SRAM pins every cycle,
  with 0 mismatches over 5 × 10⁶ cycles.

## 4. najaeda and naja-schematic

* `naja/structural_query.py` (najaeda, read-only) lists, for each SRAM input
  pin, the top-level inputs that reach it without crossing a flip-flop. For each
  data input, it lists the flip-flops that sample it first. Output:
  `results/najaeda_structural_query.txt`. Two facts stand out:
  * `d_in[1..3]` → `u_sram/A1..A3` through 2 gates;
  * `test` → only `_1098_` (`cond_lat`).
* `img/sram_addr_from_bus.png`: naja-schematic `render`, run from the
  repository root:
  ```sh
  naja-schematic render --verilog openroad/c4004_core_syn.v \
    --liberty module/STDCELL/tr1um_typ_5v0_25c.lib module/SRAM128/SRAM128.lib \
    --trace u_sram:A1 --trace u_sram:A2 --trace u_sram:A3 \
    --style keplertech_demo/naja/style_sram.json --instance-label both --hide-ui-glyphs \
    --svg keplertech_demo/img/sram_addr_from_bus.svg \
    --png keplertech_demo/img/sram_addr_from_bus.png --scale 2
  ```

## 5. Reproduce

```sh
git clone --recurse-submodules https://github.com/keplertech/kepler-formal tools/kepler-formal
cmake -S tools/kepler-formal -B tools/kepler-formal/build -DCMAKE_BUILD_TYPE=Release
make -C tools/kepler-formal/build -j8 kepler-formal
python3 -m venv tools/naja-venv && tools/naja-venv/bin/pip install najaeda naja-schematic

./gen_cfg.sh
./run_sec.sh strict k_induction 80
./run_sec.sh x1     k_induction 80
./run_sec.sh x1_tc  k_induction 140
KEPLER_SEC_PDR_DUAL_RAIL_SINGLETON_CONFLICT_BUDGET=50000000 \
KEPLER_SEC_PDR_DUAL_RAIL_SINGLETON_DECISION_BUDGET=2000000000 \
KEPLER_SEC_PDR_DUAL_RAIL_SINGLETON_TICK_BUDGET=25000000000 \
  ./run_sec.sh full pdr 400
./run_sec.sh x1_noreg k_induction 80
./replay.sh x1 results/x1_k_induction_k80/run.log 34
./random_sim.sh full 1000000
```

`run_sec.sh <cfg> <engine> <k>` writes the log and a status file to
`results/<cfg>_<engine>_k<k>/`.
