#!/bin/bash
# Usage: ./run_all.sh [path/to/sdata]   (default: ../../../bin/sdata)
# Runs every FNN.cmd in this directory and prints its output; the expected-vs-actual is in each file's REM lines.
S=${1:-../../../bin/sdata}
python3 F24_gen.py 2>/dev/null; python3 F50_gen.py 2>/dev/null
for f in F*.cmd; do
  echo "=================== $f"; grep '^REM' "$f" | sed 's/^/   | /'
  timeout 20 "$S" "$f" 2>&1 | head -25
done
