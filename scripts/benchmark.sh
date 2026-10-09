#!/bin/sh
# Reproduce the key measurements from doc/performance_assessment.md.
# Run from the repository root: sh scripts/benchmark.sh
# Requires: sdata on PATH (or pass SDATA=/path/to/sdata), awk, time builtin.
# Synthetic CSV files are generated in /tmp and cleaned up on exit.

SDATA=${SDATA:-./bin/sdata}
_BENCH_TMP=${TMPDIR:-/tmp}
WORKDIR="$_BENCH_TMP/sdata_bench_$$"
mkdir -p "$WORKDIR"

cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT INT TERM

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Generate a pure-numeric CSV with R rows and C columns.
gen_csv() {
    local file="$1" rows="$2" cols="$3"
    # Header
    printf "V1" > "$file"
    i=2; while [ "$i" -le "$cols" ]; do printf ",V%d" "$i"; i=$((i+1)); done >> "$file"
    printf "\n" >> "$file"
    # Data rows: awk fills with pseudo-random 4-decimal floats
    awk -v rows="$rows" -v cols="$cols" 'BEGIN {
        srand(42)
        for (r=1; r<=rows; r++) {
            for (c=1; c<=cols; c++) {
                printf "%.4f", rand()*1000
                if (c<cols) printf ","
            }
            printf "\n"
        }
    }' >> "$file"
}

# Tracks whether any time_run invocation hit an sdata-reported error, so the
# script can exit non-zero at the end -- without this, a broken command (the
# stale "DATA" vs "USE" bug that went unnoticed for ~30 releases, see
# doc/performance_assessment.md) produces a near-zero "time" for a run that
# actually failed, and nothing downstream (a human skimming the output, or a
# future CI job) has any signal that anything went wrong.
BENCH_FAILED=0

# Run sdata quietly, report user time. FAILS LOUDLY (prints the error,
# flags the run, keeps going) if sdata itself reported an error -- a broken
# command must never silently report a fast time for a run that did nothing.
# Usage: time_run <label> <extra_flags> <script_file>
time_run() {
    local label="$1" flags="$2" script="$3" out
    printf "  %-55s " "$label"
    out=$( { time "$SDATA" -q $flags "$script" ; } 2>&1 )
    if printf '%s\n' "$out" | grep -q '^Error:'; then
        echo "FAILED"
        printf '%s\n' "$out" | grep '^Error:' | sed 's/^/    /' >&2
        BENCH_FAILED=1
        return
    fi
    # The shell `time` keyword's output format is NOT portable across
    # shells, and /bin/sh resolves to a genuinely different shell depending
    # on platform (dash on Debian/Ubuntu, incl. GitHub Actions runners --
    # bash in some other environments), so this cannot assume one format:
    #   bash/ksh: a "real/user/sys" block, e.g. a line "user  0m1.234s"
    #   dash:     one line "1.23user 0.01system 0:01.30elapsed ...", no
    #             separate "real" label and a bare "Xuser" token instead
    # of a labelled "0mX.XXXs" one. Handle both explicitly rather than
    # silently printing nothing when the pattern doesn't match (which is
    # exactly how this script's own CI blind spot went unnoticed before --
    # see the comment on BENCH_FAILED above).
    printf '%s\n' "$out" | awk '
        /^user[ \t]/ { print $2; found=1; exit }
        /[0-9.]+user([ \t]|$)/ {
            for (i = 1; i <= NF; i++) {
                if ($i ~ /user$/) { print $i; found=1; exit }
            }
        }
        END { if (!found) print "(unparsed time output)" }
    '
}

# ---------------------------------------------------------------------------
# Section 1: CSV Load — Row Scaling (10 columns, 100 K rows)
# ---------------------------------------------------------------------------
section1() {
    echo ""
    echo "=== 1. CSV Load — Row Scaling (100,000 rows × 10 cols) ==="
    local csv="$WORKDIR/rows100k.csv"
    gen_csv "$csv" 100000 10
    local scr="$WORKDIR/load_only.cmd"
    printf "USE \"%s\"\nQUIT\n" "$csv" > "$scr"
    time_run "load 100K rows (user)" "" "$scr"
}

# ---------------------------------------------------------------------------
# Section 2: CSV Load — Column Scaling (10,000 rows, 100 columns)
# ---------------------------------------------------------------------------
section2() {
    echo ""
    echo "=== 2. CSV Load — Column Scaling (10,000 rows × 100 cols) ==="
    local csv="$WORKDIR/cols100.csv"
    gen_csv "$csv" 10000 100
    local scr="$WORKDIR/load_only2.cmd"
    printf "USE \"%s\"\nQUIT\n" "$csv" > "$scr"
    time_run "load 10K rows × 100 cols (user)" "" "$scr"
}

# ---------------------------------------------------------------------------
# Section 3: Expression Evaluation Overhead
# LET Y = V1 + V2 over 10 K and 100 K rows
# ---------------------------------------------------------------------------
section3() {
    echo ""
    echo "=== 3. Expression Evaluation Overhead (LET Y = V1 + V2) ==="

    for rows in 10000 100000; do
        local csv="$WORKDIR/eval_${rows}.csv"
        gen_csv "$csv" "$rows" 10

        local scr_load="$WORKDIR/load_only_${rows}.cmd"
        printf "USE \"%s\"\nQUIT\n" "$csv" > "$scr_load"

        local scr_run="$WORKDIR/run_let_${rows}.cmd"
        printf "USE \"%s\"\nLET Y = V1 + V2\nRUN\nQUIT\n" "$csv" > "$scr_run"

        time_run "load only   ${rows} rows (user)" "" "$scr_load"
        time_run "load + RUN  ${rows} rows (user)" "" "$scr_run"
    done
}

# ---------------------------------------------------------------------------
# Section 5: Spillover vs In-Memory (100 K rows × 10 cols, LET Y = V1 + V2)
# ---------------------------------------------------------------------------
section5() {
    echo ""
    echo "=== 5. Spillover vs. In-Memory (100K rows × 10 cols, LET Y = V1+V2) ==="
    local csv="$WORKDIR/spill100k.csv"
    gen_csv "$csv" 100000 10

    local scr="$WORKDIR/spill_run.cmd"
    printf "USE \"%s\"\nLET Y = V1 + V2\nRUN\nQUIT\n" "$csv" > "$scr"

    time_run "in-memory (no -m)       (user)" "" "$scr"
    time_run "spillover  -m 10000     (user)" "-m 10000" "$scr"
}

# ---------------------------------------------------------------------------
# Section 4: Real Datasets
# Looked up under $REAL_DATA_DIR (default: tests/data, relative to the repo
# root); not committed to the repo, so set REAL_DATA_DIR to wherever your
# copies live, e.g.: REAL_DATA_DIR=/path/to/corpus sh scripts/benchmark.sh
# ---------------------------------------------------------------------------
section4() {
    echo ""
    echo "=== 4. Real Datasets ==="
    local data_dir="${REAL_DATA_DIR:-tests/data}"
    echo "  (looking under: $data_dir)"

    # List: "label:filename"
    REAL_DATASETS="
arrhythmia.csv
GoodBadx_10Kc.csv
d1_6-train-0.csv
P3discrete4.csv
3-13-08-ArrayDataTrans.csv
"
    local found=0
    for name in $REAL_DATASETS; do
        local path="$data_dir/$name"
        if [ ! -f "$path" ]; then
            printf "  %-45s  [SKIP — file not found: %s]\n" "$name" "$path"
            continue
        fi
        found=$((found+1))
        local scr="$WORKDIR/real_load.cmd"
        printf "USE \"%s\"\nQUIT\n" "$path" > "$scr"
        time_run "$name (user)" "" "$scr"
    done
    [ "$found" -eq 0 ] && echo "  No real-dataset files found under $data_dir/."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "SData benchmark — $(date)"
echo "Binary: $SDATA"
"$SDATA" --version 2>&1 | head -1 || true

section1
section2
section3
section4
section5

echo ""
if [ "$BENCH_FAILED" -ne 0 ]; then
    echo "Done -- one or more runs FAILED (see above)."
else
    echo "Done."
fi
exit "$BENCH_FAILED"
