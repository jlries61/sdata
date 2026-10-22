# SData 1.0 pre-release stress test — report

Date: 2026-10-19 · Tester: Claude (Sonnet 5.5), adversarial/"try to break it" brief
Target: **sdata 0.37.0** (`main` @ `70f41d7`) with **sdata-core** `main` @ `9ccad66` (path pin, v0.16.x)
Build used: a private copy built with `alr build` (the repo's own `bin/` was removed mid-session, see §7)

Companion files in this directory:

| path | what |
|---|---|
| `FINDINGS.md` | the full running log: one entry per finding with severity, minimal repro, observed vs expected, and root cause where I found it |
| `repro/` | one tiny `.cmd` (+ data) per headline finding; `repro/run_all.sh [sdata]` runs them all |
| `tools/` | the harnesses (differential CSV sweep, sort/aggregate/merge/round-trip diffs vs pandas, distribution checks vs scipy, function fuzzer, …) |
| `probes/` | the `####`-separated probe scripts fed to `tools/multi.py` |

## 1. Bottom line

**I broke it — not subtly.** 11 high-severity, 19 medium and 20 low findings (50 entries in `FINDINGS.md`, plus one I retracted).
The existing suite is green (`make check` on my copy: 727 integration tests + 71/384/225/148/101 unit checks, 0 failures) and none of the
high-severity defects is caught by it, so "all tests pass" is not evidence about any of the areas below.

I would **not** release 1.0 until at least the data-corruption group (A) and the crash group (B) are fixed or explicitly documented as known limitations.
Most of them are small, localized fixes (several are one-line); I give root causes where I found them.

### A. Silent wrong data (worst — nothing tells the user)

| id | what happens | where |
|---|---|---|
| F37 | **XLSX reader ignores cell references**: any row with a blank cell is shifted left. Hits sdata's own xlsx output *and* real Excel/openpyxl files (a number even lands in a character column). | `sdata_core-file_io-ooxml.adb` ~426 |
| F34 | **ODS reader stops at the first row repeated > 1000 times** and silently drops it and *every row after it* (LibreOffice writes runs of identical rows this way). | `sdata_core-file_io-odf.adb:361` |
| F42 | **`%` columns are parsed through a double**: `1234567890123456789` → `1234567890123457024`; values near the int64 limits become missing. | `sdata_core-file_io-csv.adb` ~330-355 |
| F14 | **VAR/STD use `Σx² − (Σx)²/n`**: variance of 1e9+U(0,1) data is reported as **−1049.6** on one sample and **+1968** on another (true ≈ 0.08); a constant column makes `STATS` die with an Ada `Sqrt` error (real corpus file EDEMOS.CSV). | `sdata_core-evaluator-aggregate_fns.adb:70,81` |
| F25 | **UCASE$/LCASE$/LEN/LEFT$… are byte-based**: `UCASE$("日本語")` → garbage, `LCASE$("ÀÉ")` → invalid UTF-8 written to the output file. | string_fns |
| F22 | **`NRN(n,p)` (binomial) returns a normal variate** `N(n, p)` (copy-paste of ZRN). `MRN`, its documented synonym, is right. | `sdata_core-evaluator-distrib_fns.adb` `Handle_NRN` |
| F24 | **CSV lines > 1 MiB are silently split**: a 100,000-column file (corpus RANDOMWIDE1X.CSV) loads as 100,001 *records*. | `sdata_core-file_io-csv.adb:183` |
| F01 | **CRLF files**: the `\r` stays in the last column (name *and* values), so the last numeric column becomes character (`RINGS\r$` in corpus abalone.csv). **Bare-CR** files (corpus customer_cln_c.csv, 323,960 rows) become one 48 MB line → 67,772 junk columns. | csv reader (`Get_Line`) |
| F02 | **Quoted fields with embedded newlines are split into records** — and sdata can't read back what its own `SAVE` writes. 3 of 11 cases in the public csv-spectrum suite fail (all of the newline ones). | csv reader |
| F38 | **A zero-row table runs the data step once**: header-only CSV, or an empty `/JOIN`, followed by `LET`/`RUN`/`SAVE` produces a phantom all-missing row. Same root as `REPEAT 0` → 1 record (F28). | interpreter |

### B. Crashes / hangs

| id | what happens |
|---|---|
| F50 | **`STATS` and `AGGREGATE` die with `s-intman.adb:136 explicit raise` (stack overflow) when a group or the whole table has ≳ 350,000 rows** — including `/STATS=N`. Real corpus case: 246-W2.CSV (455k rows). `ulimit -s unlimited` makes it pass → per-group data lives on the 8 MB stack. `DISPLAY /LAST` has a second, higher limit (fails on the 11M-row HUGE11M.CSV). |
| F03 | Nesting limits: ~820 nested parentheses, ~390 nested `IF`, ~555 `FOR`, ~620 nested function calls, a 17,400-term `1+1+…` all abort the session with the same message (spec §5.3: "limited only by available stack", error message). |
| F52 | Calls with invalid distribution parameters **hang** instead of raising a domain error: `TCF(1,-1)`, `TIF(0.5,-1)`, `BCF(0.5,-1,0)` and kin (no iteration cap). See `FINDINGS.md`. |
| F41/F47 | Large inputs: forcing the spill path (`OPTIONS MAXINTAB 100000`) on a 40 MB / 19.5 M-cell file did not finish in 24 min (in-memory: 30 s). A 432 MB / 175 M-cell file drove RSS to 5.1 GB and wrote an 825 MB `GNAT-TEMP-*.TMP` *into the current directory*; `STATS` had not finished after 7.5 min. |

### C. Documented behaviour that isn't what happens (medium)

`SELECT CASE x` (the spelling in design.md §7.1) silently swallows the whole block (F11) · `BREAK` in batch mode aborts the rest of the record instead of "continuing" (F12) ·
`REPEAT 0` → 1 record (F28) · colon ranges `X1:X3` silently use only `X1` in expressions, `STATS`, `TRANSPOSE`, `BY` — and `BY G1-G2` groups by `G1` only (F36) ·
`RENAME` silently ignores collisions/unknown names and can produce a numeric column named `X$` (F17) · `/FMT=` doesn't override the extension on `SAVE` (F31) ·
`OUTPUT /CHARSET= /FMT=` ignored (F51) · charset handling is mostly a no-op; invalid UTF-8 is never rejected (F46) ·
`WIF` has scale/shape reversed (F19) · E-notation literals like `1e10` are 64-bit *integers*, so `1e10*1e10` is an overflow error (F48) ·
`AND`/`OR` don't short-circuit, so `IF X<>0 AND 1/X>1` divides by zero (F45) · blank CSV lines become phantom records (F16) ·
column names > 64 chars are silently truncated and collide (F29) · control characters make the XLSX/ODS writers emit ill-formed XML (F10) ·
`ROUND(x,n)` and a dozen other functions leak `NaN` values at extreme arguments although the spec says NaN is never exposed (F05, F52).

## 2. What I did

* **Read** `CLAUDE.md`, `doc/design.md` (all of §1–7), HELP, relevant ADRs and the sdata-core CSV/OOXML/ODF/aggregate/distribution sources.
* **Built** a private copy (`alr build`, ~80 s) and ran the shipped suite as a baseline (green).
* **Differential testing against pandas/scipy** (the oracle is an independent implementation, not my own expectation):
  * 266 CSVs from `/home/datasets/datasets_csv` (< 20 MB) + 5 mid-size ones + 18 public seaborn datasets: `USE`+`STATS` (N, NMISS, MEAN, MIN, MAX, STD) per numeric column vs pandas → 251/266 identical; the rest are the findings above (F14, F16, F24, F01, header-less/delimited files).
  * `SORT` (stability + missing-first) on 7 files, `BY`+`AGGREGATE` (SUM/MEAN/N/NMISS/MIN/MAX/MEDIAN/STD/PCTL) on 8 files, 40 random trials each of `/JOIN`, match-merge, `/INTERLEAVE` against pandas `merge`/`concat`: **no differences** (apart from the empty-result phantom row, F38).
  * 186 distribution-function evaluations (normal, χ², t, F, gamma, beta, binomial, Poisson, Weibull, logistic, exponential, Lambert W incl. tails) vs scipy: agree to 1e-9 except WIF (F19), arity differences (F20), boundary cases (F21, F23); 200,000-draw moment checks of all 14 RNGs: all correct except NRN (F22). `TABLES … /CHISQ` agrees with scipy to 5 digits.
  * XLSX/ODS round-trip of ~25 corpus files and the public csv-spectrum suite.
* **Hostile-input probes**: ~60 numeric-edge cases (int64 limits, ±Inf, NaN, 0/0, overflow); 40 CSV shapes (BOM, UTF-16 LE/BE/no-BOM, Latin-1, bad UTF-8, NUL, ragged rows, duplicate/empty/huge headers, unbalanced quotes, 1 MB lines); crafted XLSX/ODS (sparse cells, 2e9 repeat counts, 1 MB cells); 100 malformed or edge command forms; 175-function argument fuzzer (21,785 calls over a 15-value extreme grid); CLI option fuzz; SYSTEM/SHELL; signals; the REPL under a pty (EOF, Ctrl-C, continuation).
* **Scale**: 100 K → 4 M-row synthetic tables for each immediate command; HUGE11M.CSV (11 M rows); 432 MB / 175 M-cell CL10S6LT.CSV; forced-spill runs.

## 3. What held up (negative results worth knowing)

* All three tiers of control flow, BY/FIRST/LAST/LAG/NEXT inside BY groups, HOLD, WRITE routing to multiple `SAVE … AS` targets, IN=/IF=/KEEP=/RENAME= per-dataset options, `/APPEND`, `/INTERLEAVE`, `/JOIN`, match-merge: correct against pandas on randomized data.
* `SORT`: stable, multi-key, missing-first, numeric and character keys; `TABLES` one- and two-way incl. χ², φ, Cramér's V; `TRANSPOSE` variants.
* Numeric core: integer overflow detected in `+ - * ` and unary minus; IEEE_DIVIDE semantics; 1e308/Inf handling; ~150 distribution values; shortest-round-trip number output; SAVE/USE CSV round trip of floats is bit-exact.
* Spreadsheets: sparse-cell/huge-repeat/zip-bomb-style inputs are handled without memory blow-up; XXE is covered by the existing tests; OOXML/ODS string escaping is correct apart from control characters.
* SIGINT/SIGTERM/SIGHUP stop a runaway loop promptly in batch mode; Ctrl-D exits the REPL; `SUBMIT` recursion is detected (direct and indirect); `USE "x; touch pwned"` and similar are treated as file names (no shell interpolation found); `--noshell` really disables SHELL/SYSTEM.
* Most syntax errors give a clear message with a line number.

## 4. Not covered / limits of this exercise

* Platforms other than this Linux box; the packaged builds (deb/rpm/pkg/msi); locale-dependent behaviour; non-ASCII file *names*.
* Time zones/dates beyond `DATE$`/`TIME$`; ODS formula evaluation (only spot-checked); password-protected or macro workbooks.
* Large-file *correctness* above 20 MB was only partly diffed (the STATS crash F50 blocks stats on most row-heavy files; I used SORT/DISPLAY/LET paths for those).
* Interactive-only features (`INSERT`, `REMOVE`, `LIST`, `BREAK` prompt) were exercised lightly.
* No fix was attempted — per the brief this is a find-and-report exercise; nothing in `src/`, `tests/`, or sdata-core was modified.

## 5. Suggested order of attack

1. **F37, F34, F42, F24, F01/F02** — data-in correctness (reader bugs; each has a small, local fix and an obvious regression test using the files in `repro/`).
2. **F14** — Welford (or two-pass) variance, clamp at 0; also fixes the `Sqrt` crash. **F50** — move per-group buffers to the heap (or allocate the stack explicitly), then re-test at 10 M rows.
3. **F22** (one line), **F19**, **F25** (at least: leave bytes ≥ 0x80 alone in UCASE$/LCASE$; ideally code-point aware LEN/LEFT$/…).
4. **F38/F28** — an empty table must not execute the data step.
5. Make the doc and behaviour agree on `SELECT CASE`, colon ranges, `BREAK`, `/FMT=`, `OUTPUT /CHARSET=`, `HEX$`/`GCF`/`ECF` arities — design.md is the stated source of truth, so for each of these decide which side moves.
6. Replace raw `'Value`/`Constraint_Error`/`a-ngelfu.adb:…` messages with domain errors (a single `when others` isn't enough: ~25 distinct leak sites are listed in F04/F18/F33/F52).
7. Add the repro files as regression tests, and a nightly differential job (pandas/scipy are cheap oracles — this exercise found the bugs the example-based suite can't).

## 6. Reproducing

```
cd doc/stress-test-2026-10-19/repro && ./run_all.sh ../../../bin/sdata       # headline findings, with expected-vs-actual in REM lines
python3 tools/multi.py probes/p4.txt                                          # any probe file ('####'-separated scripts)
python3 tools/diffcsv.py /home/datasets/datasets_csv/*.csv > out.jsonl        # pandas differential; summarize with tools/sumdiff.py
```
`tools/*.py` default to `/home/jries/Develop/sdata/bin/sdata`; they need pandas, numpy, scipy, openpyxl (`pip install`), and, for the public datasets, network access to raw.githubusercontent.com.

## 7. Incidents during the session (for transparency)

* Midway, `~/Develop/sdata/bin/` disappeared (a packaging/`make clean` run in another terminal, I assume); I rebuilt a private copy under the session scratchpad and re-pointed my harnesses at it. I did not touch the repo's `bin/`, `obj/` or sources. The only change to your tree is this new directory `doc/stress-test-2026-10-19/` (uncommitted).
* Two harness mistakes of mine: `pkill -f` matched my own shell twice (it killed the in-flight 24-minute spill test — the "not finished after ~24 min" figure stands), and I first recorded "recursive SUBMIT exits 0", which I then re-measured and **retracted** (F07).
* Memory pressure: the 432 MB spill test pushed the machine to ~1.2 GB available before I stopped it.
