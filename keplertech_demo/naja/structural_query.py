"""Structural facts about the taped-out C4004 netlist, from najaeda (read-only).

  1. For every SRAM128 input pin: which top-level inputs reach it through
     combinational logic only (no flip-flop in between), and through how many
     gates.
  2. For every top-level data input: which flip-flops capture it first.

usage: python structural_query.py <netlist.v> <cells.lib> <sram.lib> > report.txt
"""
import sys
from collections import deque

from najaeda import netlist

netlist_v, cells_lib, sram_lib = sys.argv[1:4]
netlist.load_liberty([cells_lib, sram_lib])
netlist.load_verilog([netlist_v])
top = netlist.get_top()


def leaf_inst_name(term):
    inst = term.get_instance()
    return inst.get_name(), inst.get_model_name(), inst


def fanin_inputs(start_term):
    """Backward combinational walk from an input pin of a leaf instance.
    Returns {top input bit: min #gates} and the set of flops met on the way."""
    reached, flops = {}, set()
    seen = set()
    queue = deque([(start_term, 0)])
    while queue:
        term, depth = queue.popleft()
        eq = term.get_equipotential()
        for t in eq.get_top_drivers():
            name = str(t)
            reached[name] = min(depth, reached.get(name, depth))
        for drv in eq.get_leaf_drivers():
            name, model, inst = leaf_inst_name(drv)
            key = (name, drv.get_name())
            if key in seen:
                continue
            seen.add(key)
            if inst.is_sequential() or drv.is_sequential():
                flops.add(f"{name} ({model})")
                continue
            for inp in drv.get_combinatorial_inputs():
                queue.append((inp, depth + 1))
    return reached, flops


def first_capture(top_term):
    """Forward combinational walk from a top input: flops/macros that sample it."""
    caught, seen = set(), set()
    queue = deque([top_term])
    while queue:
        term = queue.popleft()
        for rd in term.get_equipotential().get_leaf_readers():
            name, model, inst = leaf_inst_name(rd)
            key = (name, rd.get_name())
            if key in seen:
                continue
            seen.add(key)
            if inst.is_sequential() or rd.is_sequential() or model == "SRAM128":
                caught.add(f"{name}.{rd.get_name()} ({model})")
                continue
            for out in rd.get_combinatorial_outputs():
                queue.append(out)
    return caught


cells = {}
for inst in top.get_child_instances():
    cells[inst.get_model_name()] = cells.get(inst.get_model_name(), 0) + 1
nseq = sum(1 for i in top.get_child_instances() if i.is_sequential())
print(f"# najaeda structural query on {netlist_v}")
print(f"cells: {sum(cells.values())} instances, {nseq} sequential, "
      + ", ".join(f"{m}={n}" for m, n in sorted(cells.items(), key=lambda x: -x[1])[:8]) + ", ...")

sram = top.get_child_instance("u_sram")
print("\n## SRAM128 input pins: top-level inputs reached without crossing a flop")
for term in sram.get_input_bit_terms():
    reached, _ = fanin_inputs(term)
    data = {k: v for k, v in reached.items() if not k.startswith(("clk", "rst"))}
    ctrl = {k: v for k, v in reached.items() if k.startswith(("clk", "rst"))}
    txt = ", ".join(f"{k} ({v} gates)" for k, v in sorted(data.items())) or "-"
    extra = (" | clock/reset: " + ", ".join(sorted(ctrl))) if ctrl else ""
    print(f"  {str(term):10s} <- {txt}{extra}")

print("\n## Top-level inputs: first flops / macro pins that sample them")
for term in top.get_input_bit_terms():
    if str(term).startswith(("clk", "rst")):
        continue
    caught = sorted(first_capture(term))
    print(f"  {str(term):8s} -> {len(caught)} sampling points: " + "; ".join(caught))
