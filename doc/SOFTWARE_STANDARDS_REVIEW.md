# Software Standards Audit: `SData` Statistical Data Interpreter

**Date:** 2026-06-08 (§3 revised 2026-06-09) | **Version:** 0.9.6 (§3 reflects 0.9.7 fixes) | **Auditor:** /software-standards v1.1.1
**Repository:** `/home/jries/Develop/sdata` (+ path-pinned `~/Develop/sdata-core`)
**Stack:** Ada 2012, GNAT/GPRbuild, Alire, SQLite3, Zip-Ada, XML-Ada, MathPaqs
**Domain:** Single-process batch/interactive interpreter — tabular statistical data processing
**Scope:** All Ada source in both crates (`sdata`, `sdata-core`), build system, test suite, packaging, docs
**Mode:** Adversarial single

*First re-audit since the three-crate split (v0.8.0, ADRs 039–043). The previous
clean rewrite (v0.6.14, 2026-05-14) is preserved in git history. Where the split
materially changed a dimension, the delta and its driver are called out.*

---

## 1. Architectural Integrity — **76/100**

### 1.1 The Three-Crate Split (ADRs 039–043)

Since v0.8.0 the project is three siblings under `~/Develop`: **sdata** (lexer,
AST, parser, interpreter, sdata-only commands), **sdata-core** (table + SQLite
spill, Variables/PDV, evaluator, Values, file I/O, shared `Execute_*` commands,
config, signals, system — consumed via an Alire path pin), and **data-vandal**
(sister app reusing sdata-core). The boundary is **acyclic**: sdata imports ~11
sdata-core packages; sdata-core imports nothing from sdata. ADR-040 keeps lexer/
AST/parser out of sdata-core, so each app owns its own surface syntax.

The split is well-motivated and cleanly bounded, but it imposes real integrity
costs that a single-crate design did not have:

- **Façade indirection.** Every shared command now routes through a
  `SData_Core.Commands.Execute_*` procedure (e.g. `execute_declarative.adb:86` →
  `Execute_USE` → `File_IO`). Correct, but a layer the v0.6.14 code lacked.
- **Capacity-constant duplication.** `src/sdata.ads:13–18` and
  `~/Develop/sdata-core/src/sdata_core.ads` define the *same* `Max_Name_Len`,
  `Max_Path_Len`, etc. with no cross-reference — a DRY violation that can silently
  diverge.
- **SELECT round-trip.** Because the evaluator lives in sdata-core but the parser
  does not, `SELECT expr` is re-serialised to text and re-parsed via
  `Evaluator.Parse_Expression`. Negligible at typical script sizes, but a real
  indirection introduced by ADR-040.

### 1.2 Execution Model — intact

The three-tier model (declarative / immediate / deferred, `sdata-interpreter.adb`
dispatch) is unchanged and still strictly enforced; deferred statements are queued
at parse time and run once per record. No tier leakage.

### 1.3 Module Decomposition

| File | Lines | Note |
|---|---|---|
| `src/parser/sdata-parser.adb` | 2,554 | largest; recursive-descent, unchanged shape |
| `src/sdata-help.adb` | 1,594 | table of literals, not complexity |
| `src/sdata-interpreter.adb` | 1,205 | dispatch + data step |
| `sdata-core/.../sdata_core-table.adb` | 1,174 | column store + SQLite spill |
| `sdata-core/.../sdata_core-evaluator.adb` | 1,059 | expression eval (bounded recursion, exempted) |
| `src/sdata-interpreter-execute_declarative.adb` | 828 | grew from 299: now single+multi USE, multi-target SAVE, options |

`sdata_core-commands.adb` (711 lines) is a new, coherent home for the shared
`Execute_*` procedures. No file inverts its dependencies; nothing is orphaned.

### 1.4 Concerns

- Cross-crate change coordination (see §4.2) is the dominant integrity tax.
- `execute_declarative.adb` at 828 lines is approaching the point where its merge-mode arms should become named subprograms (see §2).

**Δ from v0.6.14 (78):** −2. The split is sound engineering, but façade
indirection, duplicated capacity constants, and the SELECT round-trip are net
integrity costs not offset within this dimension.

---

## 2. Code Quality & Craftsmanship — **80/100**

### 2.1 Language Use

Ada 2012 idiom is exploited correctly: discriminated records for `Value`
(`sdata_core-values.ads:18–29`) and the AST `Statement` (`sdata-ast.ads`),
exhaustive `case` analysis, named association at call sites
(`execute_declarative.adb:86–97`), `Ada.Containers` for the statement list and
symbol tables, and `Limited_Controlled` `Finalize` for the SQLite backing store.

### 2.2 DRY — improved in v0.9.6

The float→integer truncation rule, previously inlined in two places, is now
centralized in `SData_Core.Values.Convert_Value` (`sdata_core-values.adb:23–48`);
`Table.Coerce_Value` delegates to it (`sdata_core-table.adb:267,272`). This is a
concrete craftsmanship gain (ADR-044).

### 2.3 Naming, Comments, TODOs

Identifiers are self-documenting (`Flush_PDV_To_Output`, `Rebuild_Column_Cache`,
`Convert_Value`). **Zero** `TODO`/`FIXME`/`XXX` across both crates. The one dated
deferral (`sdata_core-table.adb:96`, a bounded SQLite-handle leak gated on an
`ada_sqlite3` bump) is explicit and conditional. No commented-out code.

### 2.4 Concerns

- **`execute_declarative.adb` Execute_Declarative** is an 828-line procedure with
  nested per-merge-mode case arms (MM_Single / Positional / Match / Interleave /
  Join / Append) plus SAVE/OPTIONS. It is the one place cognitive load is high;
  its arms should be extracted into named subprograms.
- **No enforced static analysis.** `gnatcheck.rules` exists (two rules) but is not
  run in CI (Ubuntu `asis-programs` only). CodePeer unused. Pragma-`Annotate`
  exemptions for the bounded evaluator recursion are justified.

**Δ from v0.6.14 (82):** −2. The DRY win and clean naming are offset by the
oversized declarative-dispatch procedure and still-absent enforced SAST.

---

## 3. Efficiency & Performance — **83/100**

> **Post-audit correction (v0.9.7, 2026-06-09).** This audit (v0.9.6) scored the
> data-step hot path as "O(1), no per-row hashing — a highlight." That was wrong:
> a real-world script later exposed **three latent O(n²) defects** in the data
> step, two of them in the supposedly-clean hot path. All three are now fixed
> (sdata PR #21 / commit `396048a`, sdata-core PR #29 / commit `99a7534`,
> v0.9.7 / sdata-core 0.1.7). The score is revised **up** because the hot path is
> now genuinely linear; the prose below is corrected to match.

### 3.1 Hot Path & Storage

The in-memory column store spills to SQLite at `Max_Table_Cells` via batched
transactions (`Spill_Table_To_Disk`), with a segment cache on read and
`journal_mode=OFF`/`synchronous=OFF` for throughput — a genuine highlight.

Column access via `Column_Cursor_Cache` is O(1). **However, the per-record output
flush was not.** `SData_Core.Variables.Flush_PDV_To_Output` called
`Get_Column_Type`, which did `Column_Maps.Element (Cursor).Typ` — returning the
whole `Column` *by value*, deep-copying its entire `Value_Vectors` data (every
row) just to read one enum. Called per-column-per-record, this made **every**
`RUN` O(rows²): a plain `use; run` over 32k rows took ~402s. **[RESOLVED v0.9.7,
commit `99a7534`]** — read `Typ` through `Constant_Reference` (O(1)); the same
case now runs ~1.3s.

### 3.2 Transient-table build — was O(rows²)

`Transient_Table.Add_Row` / `Set_Value` copied the whole column vector on every
call (copy-modify-copy-back), so any transient build — `/append` and merge
(`sdata-merge.adb`), `Snapshot_From_Current` / `Install_To_Current`, and the
single-`USE`/`SAVE` option projection — was O(rows²). A 49k-row `/append` took
~791s. **[RESOLVED v0.9.7, commit `396048a`]** — mutate in place via `Reference`;
the merge now runs ~9s. This also makes the single-`USE`-with-options
snapshot/install O(rows) rather than O(rows²), retiring the prior cycle's "honest
debit" for that feature.

### 3.3 BY re-sort per record — was O(rows²·log rows)

A `BY` statement inside a data-step body is dispatched once per record, and each
dispatch re-sorted the entire table. **[RESOLVED v0.9.7, commit `396048a`]** — an
idempotent guard skips the re-sort when the requested BY keys already match the
established ones (the input table is immutable during the step and the sort is
stable); bare `BY` still cancels grouping.

### 3.4 Remaining

- `Transient_Table.Get_Value`/`Set_Value` still do a per-cell linear column-index
  scan + `To_Upper` (O(cols) per cell); minor at typical widths, a candidate for a
  cached position map.
- Parser heap-allocates AST nodes; no arena. Fine below ~1,000 statements.
- No per-statement profiling or memory-usage reporting infrastructure.

**Δ from v0.6.14 (78):** +5. The three O(n²) defects that were latent at audit
time are fixed; the hot path, transient build, and BY step are now linear, with
the strong spill design intact. The audit's failure to catch these on inspection
is itself a finding (see Hard Truth).

---

## 4. Maintainability & Evolvability — **80/100**

### 4.1 Test Coverage

| Suite | Count |
|---|---|
| Integration `.cmd` | **196** |
| `csv_unit_test` | 71 |
| `sdata_unit_test` (Table/Variables/PDV/transient/merge) | 355 |
| `evaluator_unit_test` | 170 |
| `file_io_unit_test` | 89 |
| `interpreter_unit_test` | 48 |
| **Unit total** | **733** |

CI runs all unit suites + 196 integration tests + a fuzz-corpus regression on push
and PR. data-vandal carries its own 44 integration tests (run manually / its own CI).

**Gap (carried from v0.6.14):** `sdata_core-statistics.adb` (775 lines, ~54
distribution/IDF/RNG functions) still has **no dedicated unit tests** — exercised
only indirectly via integration scripts. Boundary conditions, monotonicity, and
IDF∘CDF round-trips are unverified at the unit level.

### 4.2 Change Resilience

Adding a *deferred statement* is still a clean single-crate change (AST + lexer +
parser + one interpreter subunit). Adding/altering a *shared command*, however, is
now a **two-crate** change: edit `SData_Core.Commands`, rebuild sdata-core, bump
its version + the consumer constraint, rebuild sdata. ADR-044 is a real example
(touched both crates + `alire.toml`s). The path pin and CI sibling-checkout make
this manageable, but the friction is real and worth acknowledging in process docs.

### 4.3 Decision Records — excellent

44 ADRs (ADR-001…044), 22 design specs, 28 implementation plans. ADRs 039–043
document the split rationale/boundary/consequences in depth; ADR-044 covers the
RENAME suffix-type rule. `scripts/bump-version.sh` updates 9 files atomically.

**Δ from v0.6.14 (84):** −4. Strong docs and growing tests, but the untested
statistics module and the two-crate change burden are genuine evolvability costs.

---

## 5. Error Handling & Resilience — **73/100**

### 5.1 Strategy

`Script_Error` carries descriptive context and is caught at the top level in
`sdata_main.adb`; `--continue-on-error` resumes per-statement with `ERR()`/`ERL()`.
`--ignore-math-errors` maps FP domain errors to `Val_Missing`. SQLite failures are
wrapped with operation context at five sites in `sdata_core-table.adb`
(e.g. `:505–512`). CSV emits actionable, non-fatal warnings (filename/row/column)
rather than silently coercing. `Limited_Controlled` `Finalize` + SIGINT/SIGTERM
handlers (`sdata_core-signals.adb`) remove the SQLite temp file on every catchable
exit path.

### 5.2 `when others` inventory

44 total (sdata 20, sdata-core 24); ~10 are silent `=> null`. Spot-checked, the
silent ones are legitimate (AST-walk "other kinds" branches, exhaustive-case
catch-alls with `pragma Warnings`, non-fatal index-resolution). The two the prior
audit flagged in the interpreter body remain the weakest pattern but are bounded.

### 5.3 Gaps

- **`Conversion_Error` / `Type_Mismatch_Error` are uncaught.** In current paths
  they are effectively unreachable — `Apply_Rename`'s pre-validation rejects the
  numeric↔character crossing before `Convert_Value` runs, and `Coerce_Value` only
  invokes `Convert_Value` for numeric↔integer — so they would only ever surface via
  the top-level `when others`. Defensive, but they should be wrapped into
  `Script_Error` at the sdata-core boundary for clean messaging.
- **No SUBMIT nesting-depth limit** (loop detection exists; depth does not).
- **No per-expression timeout** (a non-terminating `WHILE` runs forever).

**Δ from v0.6.14 (73):** 0. Net flat — SQLite/CSV/signal handling remain strong;
the new exceptions add a minor surfacing gap offset by thorough RENAME validation.

---

## 6. Security Posture — **74/100**

### 6.1 Trust Model & Controls — intact

The OS account is the boundary (as `awk`/`make`/`R system()`). Controls:
`--noshell`, `--nosubmit`, root/SYSTEM auto-enforcement
(`sdata_core-system.adb`), per-command shell timeout, and `Sql_Id`
bracket-escaping of column names at every DDL site in `sdata_core-table.adb`. No
hardcoded secrets.

### 6.2 Gaps

- **Threat model is stale.** `doc/threat_model.md` is stamped **v0.6.13 /
  2026-05-14 / "Current"** and predates the three-crate split, the merge/transient
  machinery, multi-target SAVE projections, and RENAME type conversion. New input
  surfaces (merge BY-group warning volume, RENAME-derived column names reaching the
  spill layer) are unanalysed. This is the single biggest security debit.
- **Fuzz corpus did not grow with the code.** Drivers still cover CSV/parser/ODS/
  XLSX; the ~886-line merge path and RENAME syntax have no fuzz driver. The CI job
  is seed-corpus regression, not coverage-guided fuzzing.
- No SAST in CI (gnatcheck Ubuntu-only; CodePeer unused).

**Δ from v0.6.14 (77):** −3. Controls unchanged, but the threat model not keeping
pace with two releases of new attack surface is a real posture regression.

---

## 7. Operational Readiness — **72/100**

### 7.1 Improvements

- **Packaging version derivation is robust.** The bundled sdata-core version is
  *derived*, never hardcoded: the Makefile injects it from `../sdata-core/alire.toml`
  for the SRPM; `debian/rules` and `slackware/sdata.SlackBuild` glob the bundled
  `sdata-core-*` tree. This closes a whole class of drift.
- **CI breadth.** `.github/workflows/test.yml` checks out sdata-core as a sibling
  (path-pin aware), builds, runs `make check` + fuzz-corpus. sdata-core additionally
  has a consumer-tests workflow that runs sdata against it.
- **Observability.** `--debug[=N]` three levels, runtime `OPTIONS DEBUG N`,
  `ERR()`/`ERL()`, and the BREAK/WHEN inspector.

### 7.2 Gaps

- **No progress reporting** (`--progress`/record-count) for long USE/SORT/aggregate
  runs — silence until completion.
- **No unified ecosystem CI:** data-vandal is not exercised in sdata's pipeline
  (manual `cd ~/Develop/data-vandal && make check` per CLAUDE.md). The sdata-core
  consumer-test pin also lags the current sdata release.
- Stale in-repo test counts (see §8) cause onboarding confusion.

**Δ from v0.6.14 (66):** +6. Derived-version packaging, expanded CI, and richer
debug/test infrastructure are concrete operational gains — the one dimension that
improved.

---

## 8. Documentation — **83/100**

### 8.1 Current & strong

- **Man page** (`man/man1/sdata.1`, 1,098 lines, stamped v0.9.6 / 2026-06-06):
  covers merge modes, multi-target SAVE with `IF=`, and RENAME type-suffix
  conversion.
- **ADRs** (44), **specs** (22), **plans** (28) — a thorough, current design trail
  including ADR-044 and the rename spec/plan dated this cycle.
- **`doc/architecture.md`** updated for the three-crate package map.
- README/CONTRIBUTING cover the path-pin model and multi-platform packaging.

### 8.2 Gaps

- **Stale test counts.** `CLAUDE.md` claims **140** integration tests in three
  places (`:38`, `:40`, `:73`); actual is **196**. `CONTRIBUTING.md` likewise lags.
- **Threat model stamp stale** (§6) — also a documentation-currency failure.
- **`doc/design.odt` remains binary-only.** A `design.txt` exists locally but is
  **untracked** (not committed), so the authoritative spec is still ODF-only in git.
- Statistics module has citations but no prose on implementation-choice rationale.

**Δ from v0.6.14 (87):** −4. Excellent breadth and a current man page, undercut by
stale test-count claims, the stale threat-model stamp, and the still-uncommitted
plain-text design doc.

---

## Overall Scores

Scores are as of v0.9.6 except **Efficiency**, revised to **83** after the three
O(n²) defects it had missed were fixed in v0.9.7 (see §3).

| Category | v0.6.14 | current | Δ |
|---|---|---|---|
| Architectural Integrity | 78 | **76** | −2 |
| Code Quality & Craftsmanship | 82 | **80** | −2 |
| Efficiency & Performance | 78 | **83** (v0.9.7) | +5 |
| Maintainability & Evolvability | 84 | **80** | −4 |
| Error Handling & Resilience | 73 | **73** | 0 |
| Security Posture | 77 | **74** | −3 |
| Operational Readiness | 66 | **72** | +6 |
| Documentation | 87 | **83** | −4 |
| **TOTAL** | **625/800 (78.1%)** | **621/800 (77.6%)** | **−4** |

---

## Prioritized Remediation

| Priority | Item | Section | Effort | Gain |
|---|---|---|---|---|
| 1 | Refresh `doc/threat_model.md` to v0.9.6 — cover merge/transient surface, RENAME-derived names, shared sdata-core surface | §6, §8 | Medium | §6 +2 |
| 2 | Sync stale test counts (`CLAUDE.md` 140→196, `CONTRIBUTING.md`); ideally derive from harness output | §8 | Low | §8 +2 |
| 3 | Add `statistics_unit_test` for `sdata_core-statistics.adb` (boundaries, monotonicity, IDF∘CDF) | §4 | Medium | §4 +2 |
| 4 | Wrap `Conversion_Error` / `Type_Mismatch_Error` into `Script_Error` at the sdata-core boundary | §5 | Low | §5 +1 |
| 5 | De-duplicate capacity constants (`sdata.ads` vs `sdata_core.ads`) | §1 | Low | §1 +1 |
| 6 | Extract `Execute_Declarative` merge-mode arms into named subprograms | §2 | Medium | §2 +1 |
| 7 | `gnatcheck`/SAST in CI; fuzz driver for merge + RENAME syntax | §2, §6 | Medium | §6 +1 |
| 8 | Commit a plain-text `design.txt`; add `--progress` and a SUBMIT depth limit | §8, §7, §5 | Low | §8 +1 |
| ~~9~~ | ~~In-place projection for single-`USE` options~~ — **RESOLVED v0.9.7**: transient `Add_Row`/`Set_Value` made in-place, so snapshot/install is now O(rows) | §3 | — | done |
| 10 | Add a **performance regression test** on a non-trivial dataset (e.g. a timed `use; run` + `/append` + `by` on ~50k rows) so an O(n²) reintroduction is caught in CI, not in production | §3 | Low | guards §3 |

---

## The Hard Truth

The code is not what slipped — the *discipline around it* is. SData v0.9.6 is a
well-built interpreter with an enviable test count, a clean acyclic crate split,
and a man page that actually matches the binary. Yet the headline number went
**down**, and that is the honest signal: the three-crate split bought reuse at the
price of coordination friction nobody has paid down, the statistics module is
still 775 lines of numerical approximation with **zero** unit tests guarding it,
and the threat model is a document describing a program that no longer exists —
stamped "Current" while two releases of new attack surface (merge, transient
tables, RENAME type coercion) went unanalysed. And this audit's own §3 illustrates
the trap: it read the data-step hot path, pronounced it "O(1) — a highlight," and
**missed three latent O(n²) defects** that made a routine 49k-row script take
thirteen minutes. They were caught not by inspection but by a profiler on a real
workload — proof that "looks linear" is not the same as "is linear," and that
this codebase needs a standing performance test on a non-trivial dataset, not just
correctness tests. (All three are now fixed in v0.9.7; §3 is revised up
accordingly.) None of the remaining items are emergencies. All of them are the
kind of debt that is invisible right up until SData 1.0 puts a stability promise on
top of it. Fix the threat model, the statistics tests, and add a perf regression
test before that promise, not after.

---

## Appendix: Evidence Log

| Finding | File:Line / Source | Evidence |
|---|---|---|
| Three-crate split, acyclic boundary | ADRs 039–043; `sdata.ads`, `sdata_core.ads` | sdata→sdata-core only |
| Capacity-constant duplication | `src/sdata.ads:13–18` vs `sdata_core.ads` | identical constants, no cross-ref |
| DRY truncation centralization | `sdata_core-values.adb:23–48`; `sdata_core-table.adb:267,272` | Coerce_Value delegates to Convert_Value |
| Oversized declarative dispatch | `src/sdata-interpreter-execute_declarative.adb` | 828 lines, nested merge-mode arms |
| O(n²) #1 `Get_Column_Type` whole-column copy **[RESOLVED v0.9.7, `99a7534`]** | `sdata_core-table.adb` (`Element(Cursor).Typ`) | per-record flush copied every row to read one enum; `use;run` 32k: 402s→1.3s (callgrind) |
| O(n²) #2 transient copy-per-cell **[RESOLVED v0.9.7, `396048a`]** | `src/sdata-transient_table.adb` (`Add_Row`/`Set_Value`) | whole-column copy per call; `/append` 49k: 791s→9s |
| O(n²) #3 BY re-sort per record **[RESOLVED v0.9.7, `396048a`]** | `src/sdata-interpreter-execute_declarative.adb` (Stmt_BY) | sorted whole table every record; pass-2 2k: 19s→0.17s |
| Perf headline | full adult train/test script | >13 min → ~11s after the three fixes; output identical |
| Statistics untested | `sdata_core-statistics.adb` (775 lines); `tests/` | no `statistics_unit_test` |
| Test counts | `make check`; `ls tests/*.cmd` | 196 integration; 733 unit (71/355/170/89/48) |
| `when others` inventory | grep both `src/` trees | 44 total (20 sdata, 24 core); ~10 silent-null, justified |
| Uncaught new exceptions | `sdata_core-values.adb:33,40,43`; `sdata_core-table.adb:269,274,276` | no handler; reach top-level only |
| Threat model stale | `doc/threat_model.md:3` | v0.6.13 / 2026-05-14 / "Current" |
| Stale doc test counts | `CLAUDE.md:38,40,73` | claims 140; actual 196 |
| design doc binary-only | `git ls-files doc/design.txt` | untracked; only `design.odt` committed |
| Man page current | `man/man1/sdata.1:1` | v0.9.6 / 2026-06-06; 1,098 lines |
| Packaging version derived | `Makefile`, `debian/rules`, `slackware/sdata.SlackBuild` | sdata-core version globbed/injected, not hardcoded |
| ADR / spec / plan counts | `doc/adrs.md`, `doc/specs/`, `doc/plans/` | 44 / 22 / 28 |
