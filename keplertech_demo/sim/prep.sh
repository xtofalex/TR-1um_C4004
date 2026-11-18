#!/bin/sh
# prep.sh <cfg>: copy cfg/<cfg>_{c4004,ref}.v into sim/build/ with module names
# suffixed (_A = C4004 wrapper, _B = reference wrapper) so both fit one sim.
set -e
cd "$(dirname "$0")/.."
cfg=$1; mkdir -p sim/build
sed -E 's/[[:<:]](cpu_top|env_filter)[[:>:]]/\1_A/g' cfg/${cfg}_c4004.v > sim/build/${cfg}_A.v
sed -E 's/[[:<:]](cpu_top|env_filter)[[:>:]]/\1_B/g' cfg/${cfg}_ref.v   > sim/build/${cfg}_B.v
