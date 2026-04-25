#!/bin/sh
# Reproduce the key measurements from doc/performance_assessment.md.
# Run from the repository root: sh scripts/benchmark.sh
# Requires: sdata on PATH (or pass SDATA=/path/to/sdata), awk, time builtin.
# Synthetic CSV files are generated in /tmp and cleaned up on exit.

SDATA=${SDATA:-./bin/sdata}
TMPDIR=${TMPDIR:-/tmp}
WORKDIR="$TMPDIR/sdata_bench_$$"
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
    printf "V1"
    i=2; while [ "$i" -le "$cols" ]; do printf ",V%d" "$i"; i=$((i+1)); done
    printf "\n"
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

# Run sdata quietly, report user time.
# Usage: time_run <label> <extra_flags> <script_file>
time_run() {
    local label="$1" flags="$2" script="$3"
    printf "  %-55s " "$label"
    { time "$SDATA" -q $flags "$script" ; } 2>&1 \
        | awk '/^user/{print $2}'
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
    printf "DATA \"%s\"\nQUIT\n" "$csv" > "$scr"
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
    printf "DATA \"%s\"\nQUIT\n" "$csv" > "$scr"
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
        printf "DATA \"%s\"\nQUIT\n" "$csv" > "$scr_load"

        local scr_run="$WORKDIR/run_let_${rows}.cmd"
        printf "DATA \"%s\"\nLET Y = V1 + V2\nRUN\nQUIT\n" "$csv" > "$scr_run"

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
    printf "DATA \"%s\"\nLET Y = V1 + V2\nRUN\nQUIT\n" "$csv" > "$scr"

    time_run "in-memory (no -m)       (user)" "" "$scr"
    time_run "spillover  -m 10000     (user)" "-m 10000" "$scr"
}

# ---------------------------------------------------------------------------
# Section 4: Real Datasets
# Paths are resolved relative to the repository root; skip missing files.
# ---------------------------------------------------------------------------
section4() {
    echo ""
    echo "=== 4. Real Datasets ==="

    # List: "label:path"  (paths relative to repo root or absolute)
    REAL_DATASETS="
arrhythmia.csv:tests/data/arrhythmia.csv
GoodBadx_10Kc.csv:tests/data/GoodBadx_10Kc.csv
d1_6-train-0.csv:tests/data/d1_6-train-0.csv
P3discrete4.csv:tests/data/P3discrete4.csv
3-13-08-ArrayDataTrans.csv:tests/data/3-13-08-ArrayDataTrans.csv
"
    local found=0
    for entry in $REAL_DATASETS; do
        local label="${entry%%:*}"
        local path="${entry#*:}"
        if [ ! -f "$path" ]; then
            printf "  %-45s  [SKIP — file not found: %s]\n" "$label" "$path"
            continue
        fi
        found=$((found+1))
        local scr="$WORKDIR/real_load.cmd"
        printf "DATA \"%s\"\nQUIT\n" "$path" > "$scr"
        time_run "$label (user)" "" "$scr"
    done
    [ "$found" -eq 0 ] && echo "  No real-dataset files found under tests/data/."
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
section5
section4

echo ""
echo "Done."
