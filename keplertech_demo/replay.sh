#!/bin/sh
# replay.sh <cfg> <kepler run.log> [from_frame] [test_rst] [pos|neg]
#   Converts the counterexample in the log to sim/build/<name>.memh and replays
#   it on both designs (the same preprocessed cfg files that SEC compared),
#   printing frames >= from_frame with C4004 phase/opr/opa/sp and DIFF flags.
#   test_rst = TEST value during the 3 reset cycles (matters only with
#   TEST_CONST; the Kepler trace does not print the reset frames).
set -e
cd "$(dirname "$0")"
cfg=$1; log=$2; from=${3:-0}; test_rst=${4:-0}; edge=${5:-pos}
sim/prep.sh "$cfg"
name=$(basename "$(dirname "$log")")
read n bad <<EOF
$(python3 sim/cex2memh.py "$log" "sim/build/$name.memh")
EOF
echo "trace: $n frames, Kepler reports first bad frame at cycle $bad"
iverilog -g2012 -o "sim/build/replay_$cfg.vvp" sim/replay.v "sim/build/${cfg}_A.v" "sim/build/${cfg}_B.v"
vvp -n "sim/build/replay_$cfg.vvp" +memh="sim/build/$name.memh" +n="$n" +from="$from" +test_rst="$test_rst" +edge="$edge" | grep -v '\$finish'
