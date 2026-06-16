#!/bin/sh
# Cyclomatic-complexity gate for sdata src/.
# Fails (exit 1) if any unit's McCabe cyclomatic complexity exceeds
# MAX_CYCLOMATIC. Threshold derived from the measured maximum on 2026-06-16:
# the worst unit was SData_Main at 81; ceiling set to 85 (next multiple of 5
# above the measured max, and >= max+3 headroom). Raise it only deliberately,
# with justification — growth past the ceiling signals a subprogram that
# should be decomposed. See doc/specs/2026-06-15-gnatmetric-ci-gate-design.md.
set -eu

MAX_CYCLOMATIC=${MAX_CYCLOMATIC:-85}
GNATMETRIC=${GNATMETRIC:-gnatmetric}

cd "$(dirname "$0")/.."                      # repo root

rm -f metrix.xml
"$GNATMETRIC" --generate-xml-output --no-text-output --complexity-cyclomatic \
  --xml-file-name=metrix.xml src/*.ads src/*.adb >/dev/null 2>&1 || true

if [ ! -f metrix.xml ]; then
  echo "check-complexity: gnatmetric produced no metrix.xml" >&2
  exit 2
fi

result=$(awk '
  /<unit name="/ { if (match($0, /name="[^"]+"/)) cur = substr($0, RSTART+6, RLENGTH-7) }
  /<metric name="cyclomatic_complexity">/ {
    if (match($0, />[0-9]+</)) {
      v = substr($0, RSTART+1, RLENGTH-2) + 0
      if (v > max) { max = v; worst = cur }
    }
  }
  END { printf "%d %s", max+0, worst }
' metrix.xml)
rm -f metrix.xml

max=${result%% *}
worst=${result#* }

if [ "$max" -gt "$MAX_CYCLOMATIC" ]; then
  echo "check-complexity: FAIL — '$worst' has cyclomatic complexity $max (ceiling $MAX_CYCLOMATIC)" >&2
  exit 1
fi

echo "check-complexity: OK — max cyclomatic complexity $max in '$worst' (ceiling $MAX_CYCLOMATIC)"
