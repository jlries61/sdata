# SData Performance Assessment
**Version:** 0.37.0  
**Date:** 2026-09-28  
**Build:** `alr build` (default profile, `-O2` optimisation, debug info retained)  
**Platform:** x86-64 Linux, single vCPU (Intel Skylake, IBRS) — see Methodology for why this matters

---

## Methodology

Benchmarks were run against synthetic CSV files generated with uniform random
numeric data (values formatted to 4 decimal places) via `scripts/benchmark.sh`.
Each measurement is the `user` time reported by the shell `time` builtin (CPU
time consumed by the process). All runs used `sdata -q` (quiet mode) to
suppress console output. Each section was run twice back-to-back; the figures
below are consistent to within ~5% across both runs and either run's value
would tell the same story — no averaging or cherry-picking was needed.

**`scripts/benchmark.sh` was broken going into this pass** and had to be fixed
before it could produce a number at all: every generated `.cmd` script used
`DATA "<file>"` to load a CSV, which is not a recognized sdata command (`USE`
is — `DATA` predates a rename this script was never updated for). Running the
unfixed script did not error visibly; each `sdata` invocation printed
`Error: Unrecognized command "DATA"` to stderr, exited immediately, and the
`time` wrapper faithfully reported that near-zero-cost failure as a
result — e.g. "0.002s to load 100,000 rows," which is off by roughly three
orders of magnitude and would have been reported as a genuine 500×
improvement over the 0.6.1 baseline had it not been checked by hand against a
manual `USE` invocation first. This is exactly the audit's own "museum vs.
current" test applied to a tool rather than a document, and it's why this
pass verifies every number against a real, non-erroring run rather than
trusting the script's exit code alone. The script has been fixed (`DATA` →
`USE`, six call sites) and committed alongside this doc.

**Platform note:** this measurement environment is a single-vCPU virtualized
host (see header), which is very likely *not* the same machine the 2026-04-24
(v0.6.1) baseline was measured on — that document names no CPU, core count, or
virtualization status, only "x86-64 Linux." Comparisons to the old baseline
below are stated as observations, not as claims of regression or improvement;
absolute wall-clock/CPU-time figures are not portable across unknown hardware,
and this document did not previously record enough platform detail to rule
that out as the dominant factor. This is being recorded explicitly for the
next re-measurement.

**Real-dataset corpus**: not committed to the repo (correctly — these are
large, externally-sourced files), but present on the machine this assessment
was run on at `/home/datasets/datasets_csv`. Not found under `tests/data/`,
which is why an earlier draft of this document incorrectly reported the
corpus as unavailable and omitted §4 entirely. `scripts/benchmark.sh` now
takes a `REAL_DATA_DIR` environment variable (default `tests/data`, so the
committed script stays portable) — this pass ran
`REAL_DATA_DIR=/home/datasets/datasets_csv sh scripts/benchmark.sh`. Whether
these five files were ever committed, or were always supplied locally by
whoever ran the original 0.6.1 benchmark, is still not recorded anywhere in
the repository.

Startup overhead remains negligible at every size tested (no measurable
`load only` time at trivially small row counts).

---

## Results

### 1. CSV Load — Row Scaling (100,000 rows × 10 cols, pure numeric)

| Rows | User time | Throughput |
|------|-----------|------------|
| 100,000 | ~1.15 s | ~87,000 rows/sec |

### 2. CSV Load — Column Scaling (10,000 rows × 100 cols, pure numeric)

| Cells | User time | Throughput |
|-------|-----------|------------|
| 1,000,000 | ~1.15 s | ~867,000 cells/sec |

### 3. Expression Evaluation Overhead

Each row processed by `RUN` incurs interpreter overhead beyond the base load
cost. The following measures a single `LET Y = V1 + V2` statement:

| Rows | Load only (user) | Load + RUN (user) | Per-row overhead |
|------|-------------------|--------------------|-------------------|
| 10,000 | ~0.117 s | ~0.219 s | ~10.2 μs |
| 100,000 | ~1.219 s | ~2.181 s | ~9.6 μs |

### 4. Real Datasets

File dimensions below are measured directly against the corpus on this
machine (header-excluded data-row count via `wc -l`, columns via the header's
field count, byte size via `ls`) rather than carried forward from the 0.6.1
doc, which is why row counts differ from that document by one in a couple of
cases (almost certainly a trailing-newline counting difference, not a
different file).

| Dataset | Rows | Cols | File size | User time |
|---|---|---|---|---|
| arrhythmia.csv | 451 | 280 | 393 KB | 0.14 s |
| GoodBadx_10Kc.csv | 9,873 | 20 | 698 KB | 0.24 s |
| d1_6-train-0.csv | 16,516 | 326 | 33.6 MB | 7.73 s |
| P3discrete4.csv | 59,999 | 69 | 18.8 MB | 4.16 s |
| 3-13-08-ArrayDataTrans.csv | 10 | 54,614 | 9.9 MB | 0.69 s (fixed; was **did not complete**) |

The first four loaded without incident. The fifth — 54,614 columns in a
single-digit row count — originally **did not complete** when this section
was first written: still consuming CPU continuously after 6+ minutes, against
a 0.655s figure recorded for the same file in the 0.6.1-era document. That was
not attributable to the hardware/crate-split/feature-growth uncertainty
discussed elsewhere in this document — it was isolated to two specific,
reproducible algorithmic causes and confirmed with controlled synthetic tests
(single-row CSVs at increasing column counts, `bin/sdata -q`):

| Columns | User time (pre-fix) | Ratio vs. half the column count |
|---|---|---|
| 5,000 | 3.4 s | — |
| 10,000 | 12.5 s | 3.7× for 2× columns |
| 20,000 | 49.1 s | 3.9× for 2× columns |

Both ratios are close to the textbook 4×-per-doubling signature of an
**O(columns²)** algorithm, and this curve extrapolated almost exactly onto
the multi-minute hang observed on the real 54,614-column file.

**Fixed** (sdata-core#156, ADR-0028/ADR-0029). The straightforward reading of
the issue — one O(n²) scan — turned out to be only half the story, confirmed
by direct instrumented timing rather than assumed from the curve above:

1. `Warn_If_Duplicate_Name` (`sdata_core-file_io-helpers.adb`) did an O(n)
   linear scan, re-`To_Upper`-ing every previously-seen column name on each
   new column. Replaced with a `Name_Sets` hashed set (upper-cased once at
   insertion) — ADR-0028.
2. Verifying fix 1 against a synthetic wide file with **zero duplicate
   names** still showed the same quadratic signature, which meant the first
   fix alone was necessary but not sufficient. Traced to
   `SData_Core.Table.Add_Column` (and, discovered mid-fix, its output-side
   twin `Add_Output_Column`, hit once per column on every `RUN` record flush
   via `Flush_PDV_To_Output`): both called an unconditional full
   `Rebuild_Column_Cache`/`Rebuild_Output_Cache` on *every* column insertion,
   itself O(n) per call and O(n²) total, independent of duplicate names.
   Fixed by comparing the underlying hashed map's `Capacity` before/after
   `Insert` and only paying the full rebuild when a real rehash occurred —
   ADR-0029.

Re-measured against the same real 54,614-column file after both fixes:
**0.69 s**, matching the pre-regression 0.655s 0.6.1-era figure. A synthetic
55,000-column file (zero duplicates) confirms the same figure independently.
Loading is now linear in column count up to at least 55,000 columns, with no
ceiling reintroduced by either fix (a hashed set and an amortized-growth
cursor cache both scale past any column count tested here).

### 5. Spillover vs. In-Memory (100,000 rows × 10 cols, `LET Y = V1 + V2`)

| Mode | User time | Slowdown vs. in-memory |
|------|-----------|-------------------------|
| In-memory (no `-m`) | ~2.20 s | — |
| Spillover (`-m 10000`, 10 segments) | ~5.16 s | **~2.3×** |

---

## Observations vs. the 2026-04-24 (v0.6.1) baseline

Stated as observations, not conclusions — see the Platform note above for why
a causal claim isn't supportable from this data alone:

- **Row/column load throughput** (~87K rows/sec, ~867K cells/sec here) is
  roughly half the old post-fix figures (~170K rows/sec, ~1.7M cells/sec).
- **Per-row expression-evaluation overhead** (~10 μs here) is roughly 60%
  higher than the old post-fix figure (~6 μs).
- **Spillover slowdown** (~2.3× here) is higher than the old post-fix figure
  (~1.5×), though both are far below the pre-fix ~101× this project
  eliminated — that fix (segment-level prefetch, `Constant_Reference` spill)
  is architectural and nothing in this pass suggests it regressed.

Two structural changes since 0.6.1 could plausibly move these numbers even on
identical hardware, independent of the single-vCPU caveat above:

- **The v0.8.0 three-crate split** moved the table/PDV/evaluator layer into
  `sdata-core`, consumed via a path-pinned Alire dependency. Every hot-path
  call this benchmark exercises (`USE`'s CSV load, `LET`'s evaluator dispatch,
  spillover's `Fetch_From_Disk`) now crosses a package boundary that didn't
  exist in 0.6.1's single-crate layout. `alr build`'s optimizer inlines across
  that boundary where it can, but this pass did not verify how completely.
- **Command/option surface growth since 0.6.1** — STATS, TABLES, PCTL,
  `/MISSING=`, `/TYPES=`, and everything else shipped across ~30 releases —
  adds branches to code this benchmark's hot paths pass through (e.g. `USE`'s
  per-field dispatch now has more declared-option cases to check), even
  though none of those options are exercised by this benchmark's plain
  numeric CSVs.

Neither explanation is verified here; distinguishing "different hardware" from
"real per-call overhead added since 0.6.1" would require re-running this exact
script on the original 0.6.1 measurement hardware, or profiling a 0.6.1
tag against v0.37.0 on identical hardware — out of scope for this pass. This
is recorded as a known gap for the next assessment rather than resolved by
guessing.

---

## Bottleneck Analysis (historical — 0.6.x, retained for context)

The three root causes identified in the 0.6.x assessment, and their fixes,
remain accurate as a historical record of completed work. They are not
re-derived here since this pass did not re-profile the codebase from
scratch — only re-measure its current throughput.

### A. CSV Parser (~700,000 cells/sec ceiling, pre-fix)

`Ada.Text_IO.Get_Line` character-by-character reads, double allocation in
`Split` (each field round-tripped through `Unbounded_String`), and
`Float'Value`'s general-purpose parser were the three contributors. Fixed via
a heap-allocated line buffer, in-place field parsing (`Process_Line_Direct`),
and `Try_Fast_Float` (inline decimal parser, `Float'Value` fallback only for
scientific notation). **Done — Priority 3, 0.6.1.**

### B. Per-Row Variable Lookup (~30 μs/row overhead, pre-fix)

Every variable reference resolved at runtime through
`Ada.Containers.Indefinite_Hashed_Maps` — four hash lookups per
`LET Y = V1 + V2` row. Fixed by replacing `Permanent_Symbols` with a flat
`PDV_Vec` vector and pre-resolving `Expr_Variable` AST node indices once per
`RUN`. **Done — Priority 2, 0.6.1.**

### C. Spillover Read Access (~101× penalty, pre-fix)

Cell-by-cell SQL reads (`Fetch_From_Disk` issuing one `SELECT` per cell) and
an `O(N²)` deep-copy in `Spill_Table_To_Disk` (`T.Element(Key)` copying the
full column vector per cell). Fixed via segment-level prefetch and
`Constant_Reference` with pre-computed cursors. **Done — Priority 1, 0.6.1.**
The ~2.3× figure measured in this pass (§5 above) confirms the fix is still
in effect — nowhere near the eliminated 101× — with the residual gap from the
old ~1.5× figure covered by the Observations section above rather than
re-analyzed as a new bottleneck.

### D. Duplicate-column-name check + per-column cursor-cache rebuild (O(columns²), fixed)

`Warn_If_Duplicate_Name` (`sdata-core/src/sdata_core-file_io-helpers.adb:500`)
scanned every previously-seen column name for each new column while building
the header, for CSV, ODF, and OOXML alike — invisible below a few hundred
columns; rendered a 54,614-column real file unusable (§4 above). Neither this
nor its sibling bottleneck below was one of the three the 0.6.x pass fixed —
both were added later (a duplicate-column-name warning feature, and the
column-cursor cache itself), so neither is a regression in code that
predates 0.6.1; both are genuine bottlenecks this document did not know about
until this pass's real-dataset run surfaced the first of them.

A second, independent O(n²) mechanism (`SData_Core.Table.Add_Column` /
`Add_Output_Column`, each rebuilding their entire cursor cache from scratch
on every single column insert) was found while verifying the first fix —
fixing `Warn_If_Duplicate_Name` alone left the same real file still taking
tens of seconds. See §4 above for the fix (ADR-0028/ADR-0029,
sdata-core#156, now closed) and the re-measured 0.69s figure.

---

## Recommendations

### Priority 1 — Fix the O(columns²) duplicate-name check and cursor-cache rebuild — **done**

Tracked in [sdata-core#156](https://github.com/jlries61/sdata-core/issues/156)
(§4/Bottleneck D above), closed. Fixed and re-measured: the real
54,614-column file that previously did not complete now loads in 0.69s,
matching the pre-regression 0.655s baseline.

### Priority 2 — Re-measure on known, stable hardware before the next comparison

This pass could not distinguish environment noise from real per-call overhead
growth (see Observations above). The next performance assessment should
either run on the same physical/virtual hardware as this one (recorded in the
header above for that reason) or explicitly re-baseline against a tagged
historical version on that same hardware, so any future comparison is
apples-to-apples in a way this document and its 0.6.1 predecessor both failed
to be.

---

## Summary

In-memory performance remains linear in both row and column count **at the
scale the synthetic benchmarks in §1–3 test (up to 100 columns)**, with no
pathological cases observed there. All three 0.6.x priority bottlenecks
remain fixed — the eliminated 101× spillover penalty has not come back
(currently ~2.3×). Current absolute throughput (~87K rows/sec, ~867K
cells/sec, ~10 μs/row evaluation overhead) is lower than the 0.6.1 post-fix
figures on a like-for-like reading of the numbers, but this document cannot
currently attribute that gap to hardware, the v0.8.0 crate split,
feature-surface growth, or some combination of the three — see Observations
above.

**A genuinely new bottleneck was found and fixed**: real-dataset testing (§4,
restored this pass after an earlier draft of this document incorrectly
reported the corpus as unavailable — it lives at
`/home/datasets/datasets_csv` on this machine, not in the repo) surfaced an
O(columns²) duplicate-column-name check that made any CSV/ODF/OOXML file
with tens of thousands of columns effectively unusable regardless of row
count, confirmed by controlled synthetic tests showing textbook quadratic
scaling. A second, independent O(n²) mechanism in the column-load cursor
cache was found while verifying the first fix. Both are fixed
(sdata-core#156, ADR-0028/ADR-0029); the real 54,614-column file now loads in
0.69s, matching the pre-regression baseline. `scripts/benchmark.sh` itself
was also silently broken (stale `DATA` command name) going into this pass
and has been fixed; it had not caught its own staleness in ~30 releases
because nothing exercises it in CI.
