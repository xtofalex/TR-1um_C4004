#!/bin/sh
# Preprocess each SEC configuration into one flat Verilog file per design.
# Output: cfg/<cfg>_c4004.v and cfg/<cfg>_ref.v, with `timescale lines removed
# (slang rejects a mix of files with and without a timescale).
set -e
cd "$(dirname "$0")"
mkdir -p cfg
C4004_SRC="sec/wrap_c4004.v sec/env_filter.v sec/sram128_sec.v ../rtl/c4004_core.v"
REF_SRC="sec/wrap_ref.v sec/env_filter.v ref/mcs4_cpu.v"   # ref last: it sets `default_nettype none

gen() { # gen <cfg> [DEFINE...]
  cfg=$1; shift
  defs=""
  for d in "$@"; do defs="$defs -D$d"; done
  iverilog -E -Isec $defs -o /dev/stdout $C4004_SRC | sed '/^[[:space:]]*`timescale/d' > "cfg/${cfg}_c4004.v"
  iverilog -E -Isec $defs -o /dev/stdout $REF_SRC   | sed '/^[[:space:]]*`timescale/d' > "cfg/${cfg}_ref.v"
  echo "cfg/${cfg}: defines = ${*:-none}"
}

gen strict
gen x1    MASK_X1
gen x1_tc MASK_X1 TEST_CONST
gen full  MASK_X1 TEST_CONST STACK_ENV

# Experiment only: x1 without the input register (shows the mixed-edge issue).
gen x1_noreg MASK_X1 NO_INPUT_REG
