#!/bin/sh
# run_sec.sh <cfg> <engine> <k> [tag] [swap]
#   Runs Kepler-Formal SEC on cfg/<cfg>_c4004.v vs cfg/<cfg>_ref.v.
#   Each run gets its own directory results/<cfg>_<engine>_k<k>[_<tag>]/ (Kepler
#   writes miter_log_*.txt and report files to the cwd); stdout+stderr go to
#   run.log there, and the exit code and wall time to status.txt.
#   swap=1 passes the reference as --design1 and the C4004 as --design2.
#   Extra environment (KEPLER_SEC_DIAG, KEPLER_SEC_PDR_*) is passed through.
set -e
here=$(cd "$(dirname "$0")" && pwd)
KF=${KF:-$here/tools/kepler-formal/build/src/bin/kepler-formal}
cfg=$1; engine=$2; k=$3; tag=${4:-}; swap=${5:-0}
name=${cfg}_${engine}_k${k}${tag:+_$tag}
out=$here/results/$name
mkdir -p "$out"
d1=$here/cfg/${cfg}_c4004.v; d2=$here/cfg/${cfg}_ref.v
[ "$swap" = 1 ] && { t=$d1; d1=$d2; d2=$t; }
cd "$out"
echo "cmd: $KF -sv -v sec --sec-engine $engine -k $k --sec-reset-cycles 3 --sec-reset-port rst=1 --report-skipped-pos --design1 $d1 --design2 $d2" > status.txt
env | grep '^KEPLER_' >> status.txt || true
start=$(date +%s)
set +e
/usr/bin/time -l "$KF" -sv -v sec --sec-engine "$engine" -k "$k" \
  --sec-reset-cycles 3 --sec-reset-port rst=1 --report-skipped-pos \
  --design1 "$d1" --design2 "$d2" > run.log 2>&1
rc=$?
set -e
end=$(date +%s)
echo "exit: $rc  wall: $((end-start)) s" >> status.txt
grep 'maximum resident set size' run.log >> status.txt || true
cat status.txt
