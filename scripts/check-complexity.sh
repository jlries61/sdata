#!/bin/sh
# Cyclomatic-complexity gate for sdata src/ (excluding the recursive-descent
# parser and the tokenizer — see the exemption note at the file list below).
# Fails (exit 1) if any covered unit's McCabe cyclomatic complexity exceeds
# MAX_CYCLOMATIC.
#
# Ceiling history: originally set to 85 when SData_Main measured 81 (next
# multiple of 5 above the then-measured max). That gave only 4 points of
# headroom after several releases' worth of growth (STATS, TABLES, PCTL, new
# option surfaces) — flagged by the 2026-09-26/27 standards audit as thin
# margin for a gate whose whole point is catching growth before it compounds.
# Re-measured 2026-10-19 after this cycle's extract-subunit refactors
# (SData_Main's CLI arg-parsing loop, Execute_Tables' three largest nested
# procedures, Parse_Expression, Execute_AGGREGATE/Execute_TRANSPOSE in
# sdata-core): current worst covered unit is Parse_Command_Line at 66,
# restoring 19 points of headroom (vs. 85) as a side effect of that
# decomposition work, not a ceiling change. Left at 85 rather than re-tightened
# to a new next-multiple-of-5 — ratcheting the ceiling down to track every dip
# in the measured max would recreate the same thin-margin problem the audit
# flagged, just at a smaller number. Raise (or deliberately re-baseline) only
# with justification — growth past the ceiling signals a subprogram that
# should be decomposed. See doc/specs/2026-06-15-gnatmetric-ci-gate-design.md.
set -eu

MAX_CYCLOMATIC=${MAX_CYCLOMATIC:-85}
GNATMETRIC=${GNATMETRIC:-gnatmetric}

cd "$(dirname "$0")/.."                      # repo root

# Analyse the whole src/ tree EXCEPT the recursive-descent parser and the
# tokenizer (src/parser, src/lexer). Their McCabe cyclomatic complexity is
# inherently high (large token/grammar dispatch case statements — e.g.
# Parse_Statement ~170, Get_Next_Token_Internal ~156) and intentional, exempted
# the same way gnatcheck.rules exempts the bounded evaluator recursion. All
# other src/ subprograms (incl. src/ast) are gated at MAX_CYCLOMATIC.
files=$(find src -type f \( -name '*.ads' -o -name '*.adb' \) \
        ! -path 'src/parser/*' ! -path 'src/lexer/*')

rm -f metrix.xml
gm_err=$(mktemp)
gm_status=0
# $files is an intentionally unquoted list of simple (space-free) source paths.
"$GNATMETRIC" --generate-xml-output --no-text-output --complexity-cyclomatic \
  --xml-file-name=metrix.xml $files >/dev/null 2>"$gm_err" || gm_status=$?

if [ ! -f metrix.xml ]; then
  # Fail closed, and surface WHY (gnatmetric's stderr is otherwise lost).
  echo "check-complexity: gnatmetric produced no metrix.xml (exit $gm_status). Failing closed." >&2
  echo "  gnatmetric : $GNATMETRIC" >&2
  echo "  cwd        : $(pwd)" >&2
  echo "  shared libs:" >&2; ldd "$GNATMETRIC" 2>&1 | sed 's/^/    /' >&2
  echo "  gnatmetric stderr (tail):" >&2; tail -20 "$gm_err" | sed 's/^/    /' >&2
  rm -f "$gm_err"
  exit 2
fi
rm -f "$gm_err"

# A single subprogram's McCabe complexity is always a whole number, so per-unit
# values render as bare integers (e.g. >81<). gnatmetric's file/global AVERAGE
# rollups render with decimals (e.g. >23.00<) inside a <global> block. Matching
# integer-only values therefore selects exactly the per-unit metrics and excludes
# the averages. If that ever stops holding (format drift), parsing yields max=0
# and the guard below fails CLOSED rather than passing silently.
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

case "$max" in
  ''|*[!0-9]*)
    echo "check-complexity: malfunction — non-numeric max '$max' (gnatmetric XML format changed?). Failing closed." >&2
    exit 2 ;;
esac

if [ "$max" -le 0 ] || [ -z "$worst" ]; then
  echo "check-complexity: malfunction — no per-unit complexity parsed (max=$max). Failing closed." >&2
  exit 2
fi

if [ "$max" -gt "$MAX_CYCLOMATIC" ]; then
  echo "check-complexity: FAIL — '$worst' has cyclomatic complexity $max (ceiling $MAX_CYCLOMATIC)" >&2
  exit 1
fi

echo "check-complexity: OK — max cyclomatic complexity $max in '$worst' (ceiling $MAX_CYCLOMATIC)"
