#!/bin/sh
# random_sim.sh <cfg> [ncyc] [seeds...]: lockstep random sim of both designs,
# once with stimulus changing after the rising edge and once after the falling edge.
set -e
cd "$(dirname "$0")"
cfg=${1:-full}; ncyc=${2:-1000000}; shift 2 2>/dev/null || shift $#
seeds=${*:-"1 2 3 4 5"}
sim/prep.sh $cfg
defs=""; [ "$cfg" = full ] && defs="-DHAS_STACK_ENV"
iverilog -g2012 $defs -o sim/build/${cfg}.vvp sim/tb_lockstep.v sim/build/${cfg}_A.v sim/build/${cfg}_B.v
for s in $seeds; do
  for e in pos neg; do
    vvp -n sim/build/${cfg}.vvp +seed=$s +ncyc=$ncyc +edge=$e +stop=3 | grep -v '^VCD\|\$finish'
  done
done
