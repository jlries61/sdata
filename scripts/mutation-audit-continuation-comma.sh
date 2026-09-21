#!/bin/sh
# Mutation audit of Skip_Continuation_Comma's call sites in the parser: replace
# ONE call with `null;`, rebuild, run the comma/continuation/statement tests, and
# report whether any test failed. A site where no test fails is not covered.
#
# This is the check behind "all 11 call sites are covered" (ADR-080, milestone
# 2026-09-19 verify). It used to live in a scratch directory, so nobody else
# could reproduce that claim; it is here so anyone can.
#
# Usage: scripts/mutation-audit-continuation-comma.sh [SITE ...]
#   SITE is 1..N in source order (default: all). Exit status 1 if any audited
#   site had no failing test. Each site needs a full rebuild (~90 s). The parser
#   is restored on exit, including on Ctrl-C.
set -u
cd "$(dirname "$0")/.."

F=src/parser/sdata-parser.adb
KEEP=$(mktemp)
cp "$F" "$KEEP"
restore() { cp "$KEEP" "$F"; rm -f "$KEEP"; }
trap 'restore; exit 130' INT TERM
trap restore EXIT

sites=$(grep -n '^ *Skip_Continuation_Comma (Ctx);' "$F" | cut -d: -f1)
total=$(printf '%s\n' "$sites" | wc -l)
want="$*"
[ -z "$want" ] && want=$(seq 1 "$total")

failing_tests() {
  for t in tests/*comma*.cmd tests/*continuation*.cmd tests/*trailing*.cmd tests/statement_end_*.cmd; do
    [ -f "$t" ] || continue
    b=$(basename "$t" .cmd); exp=tests/expected/$b.out; wantrc=0
    [ -f "tests/$b.exitcode" ] && wantrc=$(cat "tests/$b.exitcode")
    out=$(mktemp)
    if [ -f "tests/$b.repl" ]; then
      timeout 10 ./bin/sdata < "$t" 2>&1 | tail -n +4 > "$out"; rc=$?
    else
      timeout 10 ./bin/sdata "$t" > "$out" 2>&1 < /dev/null; rc=$?
    fi
    if [ "$rc" -ne "$wantrc" ] || ! cmp -s "$out" "$exp"; then echo "$b"; fi
    rm -f "$out"
  done | sort -u
}

status=0
for n in $want; do
  line=$(printf '%s\n' "$sites" | sed -n "${n}p")
  [ -z "$line" ] && { echo "site $n: no such site (there are $total)"; status=1; continue; }
  sub=$(awk -v n="$line" 'NR<=n && /^   (procedure|function) [A-Za-z_0-9]+/{name=$2} END{print name}' "$KEEP")
  cp "$KEEP" "$F"
  sed -i "${line}s/Skip_Continuation_Comma (Ctx);/null;/" "$F"
  if ! alr build > /dev/null 2>&1; then echo "site $n (line $line, $sub): BUILD FAILED"; status=1; continue; fi
  fails=$(failing_tests)
  if [ -z "$fails" ]; then
    echo "site $n (line $line, $sub): ** NO TEST FAILED -- not covered **"; status=1
  else
    echo "site $n (line $line, $sub): covered by $(printf '%s\n' "$fails" | wc -l) test(s): $(printf '%s\n' "$fails" | head -3 | tr '\n' ' ')"
  fi
done
restore; trap - EXIT
alr build > /dev/null 2>&1
exit $status
