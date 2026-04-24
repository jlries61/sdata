# SData Performance Assessment
**Version:** 0.6.1  
**Date:** 2026-04-24  
**Build:** `-O2` optimisation, debug info retained (`-g`)  
**Platform:** x86-64 Linux

---

## Methodology

Benchmarks were run against synthetic CSV files generated with uniform random
numeric data (values formatted to 4 decimal places), plus a selection of real
datasets from the project's test corpus.  Each measurement is the `user` time
reported by the shell `time` builtin (CPU time consumed by the process),
with wall-clock (`real`) time noted where it diverges meaningfully.
All runs used `sdata -q` (quiet mode) to suppress console output.
Background processes were cleared before each timing run.

Startup overhead is approximately 3 ms and is negligible at all dataset sizes
tested.

---

## Results

### 1. CSV Load — Row Scaling (10 columns, pure numeric)

| Rows | File size | User time | Rows/sec |
|------|-----------|-----------|----------|
| 1,000 | 77 KB | 0.014 s | 71,000 |
| 10,000 | 771 KB | 0.147 s | 68,000 |
| 100,000 | 7.5 MB | 1.293 s | 77,000 |
| 1,000,000 | 75 MB | 12.829 s | 78,000 |

Load rate is consistently **~75,000 rows/second** for a 10-column numeric
file.  Scaling is clean linear across three decades of row count with no
sign of degradation at large sizes.

### 2. CSV Load — Column Scaling (10,000 rows, pure numeric)

| Columns | File size | User time | Cells/sec |
|---------|-----------|-----------|-----------|
| 10 | 771 KB | 0.147 s | 680,000 |
| 50 | 3.8 MB | 0.695 s | 719,000 |
| 100 | 7.5 MB | 1.356 s | 737,000 |
| 250 | 19 MB | 3.566 s | 699,000 |
| 500 | 38 MB | 7.361 s | 679,000 |

Column scaling is also linear, with throughput stable at **~700,000
cells/second** across all column counts tested.  The per-cell cost is
essentially constant regardless of whether the data is arranged as many
short rows or few wide rows.

### 3. Expression Evaluation Overhead

Each row processed by `RUN` incurs interpreter overhead beyond the base
load cost.  The following measures a single `LET Y = V1 + V2` statement:

**Before Priority 2 fix (0.6.0/0.6.1 baseline):**

| Rows | Load only (user) | Load + RUN (user) | Per-row overhead |
|------|-----------------|-------------------|-----------------|
| 10,000 | 0.147 s | 0.457 s | ~31 μs |
| 100,000 | 1.293 s | 4.267 s | ~30 μs |

**After Priority 2 fix (indexed PDV + pre-resolved AST variables):**

| Rows | Load only (user) | Load + RUN (user) | Per-row overhead |
|------|-----------------|-------------------|-----------------|
| 100,000 | 1.293 s | 1.942 s | ~6 μs |

Per-row overhead dropped from **~30 μs to ~6 μs** — a **5× reduction**.
The fix replaced `Permanent_Symbols` (a hash map) with a flat `PDV_Vec`
vector, and pre-resolves all `Expr_Variable` AST node indices once per RUN
so that the hot evaluation path performs zero hash lookups per variable access.

### 4. Real Datasets

| Dataset | Rows | Cols | File size | Load (user) |
|---------|------|------|-----------|-------------|
| arrhythmia.csv | 452 | 280 | 396 KB | 0.017 s |
| GoodBadx\_10Kc.csv | 9,874 | 20 | 700 KB | 0.459 s |
| d1\_6-train-0.csv | 16,517 | 326 | 34 MB | 7.565 s |
| P3discrete4.csv | 60,000 | 69 | 19 MB | 11.473 s |
| 3-13-08-ArrayDataTrans.csv | 11 | 54,614 | 10 MB | 1.311 s |

The 54,614-column file loaded without error in 1.3 seconds of CPU time.
There is no observed hard limit on column count.  Real datasets with mixed
numeric and string fields, missing values, and repeated-column markers load
within the same order-of-magnitude as the synthetic benchmarks.

### 5. Spillover vs. In-Memory (100,000 rows × 10 cols, `LET Y = V1 + V2`)

**Before fix (0.6.0):**

| Mode | Real time | User time | Slowdown vs. in-memory |
|------|-----------|-----------|------------------------|
| In-memory (no `-m`) | 6.1 s | 4.3 s | — |
| Spillover (`-m 10000`, 10 segments) | 614 s | 437 s | **~101×** |

**After Priority 1 fix (segment-level prefetch + reference-type spill):**

| Mode | Real time | User time | Slowdown vs. in-memory |
|------|-----------|-----------|------------------------|
| In-memory (no `-m`) | 4.2 s | 3.0 s | — |
| Spillover (`-m 10000`, 10 segments) | 6.1 s | 4.5 s | **~1.5×** |

The 101× penalty has been eliminated.  Two bugs were responsible:
1. **Cell-by-cell SQL reads**: `Fetch_From_Disk` issued one `SELECT` per cell;
   replaced with one `SELECT` per segment (10,000× reduction in query count).
2. **Deep-copy in `Spill_Table_To_Disk`**: `T.Element(Key)` inside the inner
   loop copied the entire column `Vector` (O(N) values) for every cell, producing
   O(N²) allocations per spill call.  Fixed by using `Constant_Reference` via
   pre-computed cursors.

---

## Bottleneck Analysis

Three root causes account for essentially all observed slowness.

### A. CSV Parser (~700,000 cells/sec ceiling)

The current `Parse_CSV` implementation has three contributing inefficiencies:

1. **`Ada.Text_IO.Get_Line`** reads character by character through the Ada
   runtime.  For large files this is substantially slower than bulk stream
   reads.

2. **Double allocation in `Split`**: each field is converted to an
   `Unbounded_String` inside `Split`, then immediately converted back to a
   plain `String` in `Process_Row`.  This allocates and frees a heap object
   per field per row.

3. **`Float'Value` for numeric parsing**: Ada's `Float'Value` attribute
   invokes the runtime's general-purpose string-to-float conversion.  A
   hand-rolled fast path (e.g. inline digit accumulation) would be
   meaningfully faster for the common case of short decimal strings.

### B. Per-Row Variable Lookup (~30 μs/row overhead)

During `RUN`, every variable reference in every statement resolves at
runtime by name through `Ada.Containers.Indefinite_Hashed_Maps`.  A
`LET Y = V1 + V2` statement performs approximately four such lookups per
row: two reads (`V1`, `V2`), one write (`Y`), and one column-type check.
At 10,000 rows this is 40,000 hash-map string lookups for a single
statement.

The fix is to pre-resolve variable names to column indices once (at
program-buffer commit time or at the first `RUN`) and replace hash-map
lookups during iteration with direct indexed vector access.  This is a
structural change to the interpreter but not an architectural one.

### C. Spillover Read Access (~101× penalty)

The SQLite backing store is accessed cell-by-cell during `RUN`: each
`Get_Value` call for a row that has been evicted to disk issues a separate
SQL `SELECT` statement.  With `-m 10000` and 100,000 rows, processing
the first statement in the program buffer triggers approximately 100,000
individual SQL queries just to read `V1`.

The correct approach is to prefetch an entire in-memory segment's worth of
rows from SQLite before beginning iteration over that segment, storing
results in a flat per-column array.  Each segment then requires one SQL
query per column rather than one per cell per column, reducing query count
by a factor of `segment_size`.

---

## Recommendations

The following improvements are listed in priority order based on impact.

### Priority 1 — Fix spillover read access (blocker) ✓ DONE

The 101× slowdown has been eliminated (now ~1.5×) by two fixes:
segment-level prefetch in `Fetch_From_Disk` and switching
`Spill_Table_To_Disk` from `T.Element` (deep copy per cell) to
`Constant_Reference` via pre-computed cursors.

### Priority 2 — Pre-resolve variable names (high value) ✓ DONE

Per-row overhead reduced from ~30 μs to ~6 μs (5×) by:
replacing `Permanent_Symbols` hash map with a flat `PDV_Vec` vector,
adding `Var_Index` to `Expr_Variable` AST nodes, and pre-resolving all
variable indices once per RUN so the hot evaluation path does no hash lookups.

### Priority 3 — Faster CSV tokenisation (moderate value)

Replacing `Ada.Text_IO.Get_Line` with stream-based bulk reads, removing
the double `Unbounded_String` allocation in `Split`, and inlining a fast
float parser would improve the ~700,000 cells/sec load ceiling.  This is
the most mechanical of the three changes but also the one with the narrowest
impact — it only helps during `USE`, and the current rate is acceptable for
datasets up to a few hundred thousand rows.

---

## Summary

In-memory performance is predictably linear in both row and column count,
with no pathological cases at large sizes.  Both high-priority bottlenecks have been eliminated.  The spillover penalty
is down from 101× to ~1.5×, and per-row evaluation overhead is down from
~30 μs to ~6 μs.  The one remaining actionable item is Priority 3, the
CSV parser ceiling (~700,000 cells/sec), which does not require architectural
changes.
