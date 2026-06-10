# Software Standards Audit: `SData` Statistical Data Interpreter

**Date:** 2026-06-08 (§3 revised 2026-06-09; §1/§2/§5/§6/§8 revised 2026-06-10) | **Version:** 0.9.6 (§3 reflects 0.9.7 fixes) | **Auditor:** /software-standards v1.1.1
**Repository:** `/home/jries/Develop/sdata` (+ path-pinned `~/Develop/sdata-core`)
**Stack:** Ada 2012, GNAT/GPRbuild, Alire, SQLite3, Zip-Ada, XML-Ada, MathPaqs
**Domain:** Single-process batch/interactive interpreter — tabular statistical data processing
**Scope:** All Ada source in both crates (`sdata`, `sdata-core`), build system, test suite, packaging, docs
**Mode:** Adversarial single

*First re-audit since the three-crate split (v0.8.0, ADRs 039–043). The previous
clean rewrite (v0.6.14, 2026-05-14) is preserved in git history. Where the split
materially changed a dimension, the delta and its driver are called out.*

---

## 1. Architectural Integrity — **77/100** (2026-06-10)

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
- ~~**Capacity-constant duplication.**~~ — **RESOLVED 2026-06-10 (remediation #5).**
  `src/sdata.ads` no longer redefines the six capacity constants as literals; it
  `with`s `SData_Core` and re-exports them (`Max_Name_Len : constant :=
  SData_Core.Max_Name_Len;` …). There is now exactly one literal per limit (in
  `sdata_core.ads`), so the two cannot diverge; every existing `SData.*`/bare
  reference keeps working and the values remain static named numbers (sdata-only
  change, no version bump).
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
| `src/sdata-interpreter-execute_declarative.adb` | 864 | USE arm decomposed into `Execute_USE_Single`/`Execute_USE_Multi` (remediation #6); multi-target SAVE, options |

`sdata_core-commands.adb` (711 lines) is a new, coherent home for the shared
`Execute_*` procedures. No file inverts its dependencies; nothing is orphaned.

### 1.4 Concerns

- Cross-crate change coordination (see §4.2) is the dominant integrity tax.
- `execute_declarative.adb` at 828 lines is approaching the point where its merge-mode arms should become named subprograms (see §2).

**Δ from v0.6.14 (78):** −1 → **77** (2026-06-10). The split is sound engineering;
the capacity-constant duplication is now resolved (remediation #5), leaving façade
indirection and the SELECT round-trip as the residual split-introduced integrity
costs not offset within this dimension.

---

## 2. Code Quality & Craftsmanship — **81/100** (2026-06-10)

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

- ~~**`execute_declarative.adb` Execute_Declarative** is an 828-line procedure with
  nested per-merge-mode case arms…~~ — **RESOLVED 2026-06-10 (remediation #6).** The
  USE arm's two merge-mode paths are extracted into named nested subprograms
  `Execute_USE_Single` (~120 lines) and `Execute_USE_Multi` (~340 lines); the arm is
  now a 7-line dispatch (`if Stmt.Mode = MM_Single then Execute_USE_Single; else
  Execute_USE_Multi; …`). The bodies were moved **byte-identically** (verified by
  diff against the pre-refactor file), so behaviour is provably unchanged (build clean
  + 197/197 integration). The SAVE/OPTIONS arms already used named helpers
  (`Legacy_Execute_SAVE`, `Dlm_Display`).
- **No enforced static analysis (toolchain-blocked).** `gnatcheck.rules` exists (two
  rules) but is not run in CI: FSF GNAT 15.2 (the Alire toolchain) ships no
  `gnatcheck`, and Ubuntu's ASIS `gnatcheck` is version-incompatible with it (see §6.2
  for the full rationale). CodePeer unused. Pragma-`Annotate` exemptions for the
  bounded evaluator recursion are justified.

**Δ from v0.6.14 (82):** −1 → **81** (2026-06-10). The DRY win and clean naming now
include the decomposed declarative dispatch (remediation #6); the residual debit is the
still-absent enforced SAST (remediation #7).

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

## 4. Maintainability & Evolvability — **82/100**

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

**Gap — RESOLVED 2026-06-09 (remediation #3, sdata-core PR #31).**
`sdata_core-statistics.adb` (775 lines, ~54 distribution/IDF/RNG functions) had
no dedicated unit tests. Now covered by `tests/statistics_tests.adb`, an
88-assertion property-based in-crate driver: canonical reference values, CDF
boundaries + monotonicity, IDF∘CDF round-trips (incl. Weibull's reversed
`Scale`/`Shape` order), symmetry, PDF non-negativity, and seeded-RNG support.

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

**Δ from v0.6.14 (84):** −2 → **82** (2026-06-09). The untested-statistics gap is
now closed (remediation #3); the remaining debit is the two-crate change burden
for shared commands — real but well-managed by the path pin and CI sibling
checkout.

---

## 5. Error Handling & Resilience — **74/100** (2026-06-10)

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

- ~~**`Conversion_Error` / `Type_Mismatch_Error` are uncaught.**~~ — **RESOLVED
  2026-06-10 (remediation #4).** Re-examination upgraded the original "effectively
  unreachable" suspicion to a **verified-unreachable** conclusion: every script path
  that could raise either exception is already guarded — assignment
  (`Coerce_For_Scalar`) and rename (`Apply_Rename`) pre-validate the
  numeric/character boundary; merge **coerces** type-incompatible values to missing
  rather than raising (confirmed across match/interleave/join/append/positional); and
  the PDV flush only ever writes already-validated values. `Convert_Value`'s
  string-crossing branch has no reachable caller (its two callers are numeric↔integer
  only). Because the gap is theoretical, the fix is **defense-in-depth**, not a bug
  fix: sdata's two top-level handlers (`sdata_main.adb`) now catch
  `Type_Mismatch_Error` / `Conversion_Error` alongside `Script_Error`, so *if* a
  future path ever raises one it surfaces as a clean `Error: …` with a failure exit
  status instead of an "Internal error" via `when others`. No sdata-core change; no
  version bump.
- **No SUBMIT nesting-depth limit** (loop detection exists; depth does not).
- **No per-expression timeout** (a non-terminating `WHILE` runs forever).

**Δ from v0.6.14 (73):** +1 → **74** (2026-06-10). The coercion-exception surfacing
gap is closed as documented defense-in-depth (remediation #4), and the
unreachability is now verified rather than assumed; SQLite/CSV/signal handling remain
strong. The SUBMIT-depth and expression-timeout gaps are the remaining debits.

---

## 6. Security Posture — **77/100** (2026-06-10)

### 6.1 Trust Model & Controls — intact

The OS account is the boundary (as `awk`/`make`/`R system()`). Controls:
`--noshell`, `--nosubmit`, root/SYSTEM auto-enforcement
(`sdata_core-system.adb`), per-command shell timeout, and `Sql_Id`
bracket-escaping of column names at every DDL site in `sdata_core-table.adb`. No
hardcoded secrets.

### 6.2 Gaps

- **Threat model — REFRESHED 2026-06-09 (remediation #1, done).**
  `doc/threat_model.md` was stamped v0.6.13 / 2026-05-14 / "Current" and predated
  the three-crate split, merge/transient machinery, multi-target SAVE, and RENAME
  type conversion. It is now updated to v0.9.7: new attack-surface rows
  (merge/transient, per-dataset/target options), T1 extended to RENAME-derived
  names (covered by `Sql_Id`), a new **D4** (merge `/JOIN` amplification +
  unbounded transient memory, since transient tables don't spill), corrected file
  references, and refreshed gaps/deployment guidance.
- ~~**Fuzz corpus did not grow with the code.**~~ — **RESOLVED 2026-06-10
  (remediation #7, fuzz half).** `tests/merge_fuzz_driver.adb` exercises the merge
  path end-to-end: it derives 2–4 transient tables (typed columns, byte-derived rows)
  with a RENAME map from stdin bytes, then runs `Apply_Rename` / `Sort_By` and every
  `SData.Merge.Combine_*` combiner (Positional / Match / Interleave / Join / Append),
  catching expected `Rename_Error` / `Script_Error` and letting real crashes propagate.
  Seven seeds under `tests/fuzz_corpus/merge/` plus four merge/RENAME **syntax** seeds
  under `…/script/` (RENAME command, per-dataset `(RENAME=/KEEP/DROP)`, all merge
  modes, multi-target SAVE) extend the parser driver's coverage. Wired into
  `make fuzz-corpus` (which CI runs). Validated: 0 crashes across the seeds + 2000
  random inputs.
- **No SAST in CI — still open (toolchain-blocked).** `gnatcheck.rules` (two rules)
  is not run in CI. The Alire toolchain is **FSF GNAT 15.2**, which does *not* bundle
  `gnatcheck`; Ubuntu's `asis-programs` `gnatcheck` is ASIS-based and version-locked to
  Ubuntu's system GNAT, so it cannot process GNAT-15.2-built sources; the
  libadalang-based `gnatcheck` (Alire `libadalang_tools`) would mean building
  libadalang from source in CI — too heavy/fragile to justify for two rules. Revisit
  when an Alire `gnatcheck` binary crate is available; meanwhile `make gnatcheck` runs
  on a dev machine with a matching toolchain. CodePeer unused.

**Δ from v0.6.14 (77):** 0 → **77** (2026-06-10). The threat-model staleness and the
merge/RENAME fuzz gap — the two debits that drove the prior −1 — are both resolved;
the residual point is the toolchain-blocked SAST-in-CI.

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

## 8. Documentation — **86/100** (2026-06-10)

### 8.1 Current & strong

- **Man page** (`man/man1/sdata.1`, 1,098 lines, stamped v0.9.6 / 2026-06-06):
  covers merge modes, multi-target SAVE with `IF=`, and RENAME type-suffix
  conversion.
- **ADRs** (44), **specs** (22), **plans** (28) — a thorough, current design trail
  including ADR-044 and the rename spec/plan dated this cycle.
- **`doc/architecture.md`** updated for the three-crate package map.
- README/CONTRIBUTING cover the path-pin model and multi-platform packaging.

### 8.2 Gaps

- ~~**Stale test counts.**~~ — **RESOLVED 2026-06-09** (remediation #2): `CLAUDE.md`
  and `CONTRIBUTING.md` now state 197 integration tests / ~733 unit checks / 44
  data-vandal tests, with `make check` named as the source of truth. (One stale
  pair remains in the *sdata-core* `CLAUDE.md` — separate repo, PR pending.)
- ~~**Threat model stamp stale** (§6)~~ — **resolved 2026-06-09** (refreshed to v0.9.7).
- ~~**`doc/design.odt` remains binary-only.**~~ — **RESOLVED 2026-06-10
  (remediation #8, design half).** The design doc is converted to committed Markdown
  (`doc/design.md`, via pandoc) and is now the authoritative spec; the binary
  `design.odt` is removed. The spec is now diffable and grep-able in git (the command
  / function references are HTML tables, faithful to the original and GitHub-rendered).
- Statistics module has citations but no prose on implementation-choice rationale.

**Δ from v0.6.14 (87):** −1 → **86** (2026-06-10). The two documentation-currency
failures (stale threat-model stamp, stale test counts) are fixed, and the design doc
is now committed Markdown rather than binary ODF (remediation #8); the lone residual
debit is the statistics module's missing implementation-choice prose.

---

## Overall Scores

Scores are as of v0.9.6 except seven revised post-audit. From 2026-06-09:
**Efficiency** (→83, three O(n²) fixes in v0.9.7, §3), **Documentation** (→85,
threat-model + test-count syncs, §8), and **Maintainability** (→82, statistics
unit tests added, §4). From 2026-06-10: **Error Handling** (→74,
coercion-exception defense-in-depth guard + verified unreachability, §5),
**Architectural Integrity** (→77, capacity-constant de-duplication, §1),
**Code Quality** (→81, declarative-dispatch decomposition, §2), **Security**
(→77, threat-model refresh + merge/RENAME fuzz driver, §6), and **Documentation**
(→86, design doc converted to committed Markdown, §8). The total now exceeds
the v0.6.14 mark, with a different composition:
Efficiency and Operational Readiness up most; the split-coordination dimensions
remain the principal debits.

| Category | v0.6.14 | current | Δ |
|---|---|---|---|
| Architectural Integrity | 78 | **77** (2026-06-10) | −1 |
| Code Quality & Craftsmanship | 82 | **81** (2026-06-10) | −1 |
| Efficiency & Performance | 78 | **83** (v0.9.7) | +5 |
| Maintainability & Evolvability | 84 | **82** (2026-06-09) | −2 |
| Error Handling & Resilience | 73 | **74** (2026-06-10) | +1 |
| Security Posture | 77 | **77** (2026-06-10) | 0 |
| Operational Readiness | 66 | **72** | +6 |
| Documentation | 87 | **86** (2026-06-10) | −1 |
| **TOTAL** | **625/800 (78.1%)** | **632/800 (79.0%)** | **+7** |

---

## Prioritized Remediation

| Priority | Item | Section | Effort | Gain |
|---|---|---|---|---|
| ~~1~~ | ~~Refresh `doc/threat_model.md`~~ — **RESOLVED 2026-06-09**: updated to v0.9.7 with merge/transient + per-target-option attack surface, T1 extended to RENAME names, new D4 (merge/transient memory), corrected file refs | §6, §8 | — | done |
| ~~2~~ | ~~Sync stale test counts~~ — **RESOLVED 2026-06-09**: `CLAUDE.md` + `CONTRIBUTING.md` now state 197 integration / ~733 unit / 44 data-vandal, with `make check` named as the source of truth | §8 | — | done |
| ~~3~~ | ~~Add `statistics_unit_test`~~ — **RESOLVED 2026-06-09** (sdata-core PR #31): `tests/statistics_tests.adb`, 88 property-based assertions across all 14 distributions | §4 | — | done |
| ~~4~~ | ~~Wrap `Conversion_Error` / `Type_Mismatch_Error` into `Script_Error`~~ — **RESOLVED 2026-06-10**: verified unreachable by construction (assignment/rename pre-validate; merge coerces-to-missing; flush writes validated values), so closed as **defense-in-depth** — sdata's two top-level handlers now catch both alongside `Script_Error`. No sdata-core change | §5 | — | done |
| ~~5~~ | ~~De-duplicate capacity constants (`sdata.ads` vs `sdata_core.ads`)~~ — **RESOLVED 2026-06-10**: `sdata.ads` now `with`s `SData_Core` and re-exports the six constants from it; one literal per limit, cannot diverge. sdata-only, no version bump | §1 | — | done |
| ~~6~~ | ~~Extract `Execute_Declarative` merge-mode arms into named subprograms~~ — **RESOLVED 2026-06-10**: USE arm's single/multi paths extracted into `Execute_USE_Single` / `Execute_USE_Multi` (byte-identical move, verified by diff; 197/197 green); arm reduced to a 7-line dispatch | §2 | — | done |
| ~~7~~ | **PARTIAL 2026-06-10** — fuzz driver for merge + RENAME **done** (`tests/merge_fuzz_driver.adb` + seeds, wired into `make fuzz-corpus`; closes the §6 fuzz debit, +1). `gnatcheck`/SAST-in-CI **deferred (toolchain-blocked)**: FSF GNAT 15.2 ships no gnatcheck; ASIS gnatcheck is version-incompatible; libadalang build too heavy for CI (§2.4, §6.2) | §2, §6 | Medium | §6 +1 |
| 8 | ~~Commit a plain-text `design.txt`~~ → **committed `doc/design.md` (Markdown, RESOLVED 2026-06-10, §8 +1)**; add `--progress` and a SUBMIT depth limit | §8, §7, §5 | Low | §8 +1 |
| ~~9~~ | ~~In-place projection for single-`USE` options~~ — **RESOLVED v0.9.7**: transient `Add_Row`/`Set_Value` made in-place, so snapshot/install is now O(rows) | §3 | — | done |
| ~~10~~ | ~~Add a performance regression test~~ — **RESOLVED**: `tests/perf_regression.cmd` exercises all three paths on 20k/40k rows; relies on the harness 10s per-test timeout so an O(n²) reintroduction fails the suite | §3 | — | done |

---

## The Hard Truth

The code is not what slipped — the *discipline around it* is. SData v0.9.6 is a
well-built interpreter with an enviable test count, a clean acyclic crate split,
and a man page that actually matches the binary. Yet the headline number went
**down**, and that is the honest signal: the three-crate split bought reuse at the
price of coordination friction nobody has paid down, the statistics module was
775 lines of numerical approximation with **zero** unit tests guarding it, and the
threat model was a document describing a program that no longer existed — stamped
"Current" while two releases of new attack surface (merge, transient tables,
RENAME type coercion) went unanalysed. (Both of those are since fixed —
remediation #1 and #3 — see below.) And this audit's own §3 illustrates
the trap: it read the data-step hot path, pronounced it "O(1) — a highlight," and
**missed three latent O(n²) defects** that made a routine 49k-row script take
thirteen minutes. They were caught not by inspection but by a profiler on a real
workload — proof that "looks linear" is not the same as "is linear," and that
this codebase needs a standing performance test on a non-trivial dataset, not just
correctness tests. (All three are now fixed in v0.9.7, and a
standing perf-regression test — `tests/perf_regression.cmd`, which fails the
suite if any path goes quadratic again — now guards them; §3 is revised up
accordingly.) None of the remaining items are emergencies, and the highest-risk
ones — the stale threat model and the untested statistics module — are now
cleared. What remains is the kind of debt that stays invisible right up until
SData 1.0 puts a stability promise on top of it. The merge/RENAME fuzz gap (#7)
is now closed (`tests/merge_fuzz_driver.adb`); what is left is the
toolchain-blocked SAST-in-CI and the two-crate change friction. Close those
before the promise, not after.

---

## Appendix: Evidence Log

| Finding | File:Line / Source | Evidence |
|---|---|---|
| Three-crate split, acyclic boundary | ADRs 039–043; `sdata.ads`, `sdata_core.ads` | sdata→sdata-core only |
| Capacity-constant duplication **[RESOLVED 2026-06-10, remediation #5]** | `src/sdata.ads` re-exports from `sdata_core.ads` | `Max_* : constant := SData_Core.Max_*`; one literal per limit |
| DRY truncation centralization | `sdata_core-values.adb:23–48`; `sdata_core-table.adb:267,272` | Coerce_Value delegates to Convert_Value |
| Oversized declarative dispatch **[RESOLVED 2026-06-10, remediation #6]** | `src/sdata-interpreter-execute_declarative.adb` | USE arm extracted to `Execute_USE_Single`/`Execute_USE_Multi` (byte-identical move; 197/197 green) |
| O(n²) #1 `Get_Column_Type` whole-column copy **[RESOLVED v0.9.7, `99a7534`]** | `sdata_core-table.adb` (`Element(Cursor).Typ`) | per-record flush copied every row to read one enum; `use;run` 32k: 402s→1.3s (callgrind) |
| O(n²) #2 transient copy-per-cell **[RESOLVED v0.9.7, `396048a`]** | `src/sdata-transient_table.adb` (`Add_Row`/`Set_Value`) | whole-column copy per call; `/append` 49k: 791s→9s |
| O(n²) #3 BY re-sort per record **[RESOLVED v0.9.7, `396048a`]** | `src/sdata-interpreter-execute_declarative.adb` (Stmt_BY) | sorted whole table every record; pass-2 2k: 19s→0.17s |
| Perf headline | full adult train/test script | >13 min → ~11s after the three fixes; output identical |
| Statistics tested **[RESOLVED 2026-06-09, sdata-core PR #31]** | `sdata-core/tests/statistics_tests.adb` | 88 property-based assertions; all 14 distributions |
| Test counts | `make check`; `ls tests/*.cmd` | 196 integration; 733 unit (71/355/170/89/48) |
| `when others` inventory | grep both `src/` trees | 44 total (20 sdata, 24 core); ~10 silent-null, justified |
| Uncaught new exceptions | `sdata_core-values.adb:33,40,43`; `sdata_core-table.adb:269,274,276` | no handler; reach top-level only |
| Threat model stale | `doc/threat_model.md:3` | v0.6.13 / 2026-05-14 / "Current" |
| Stale doc test counts | `CLAUDE.md:38,40,73` | claims 140; actual 196 |
| design doc binary-only **[RESOLVED 2026-06-10, remediation #8]** | `doc/design.md` (pandoc-converted) | ODF removed; Markdown spec now authoritative + committed |
| Man page current | `man/man1/sdata.1:1` | v0.9.6 / 2026-06-06; 1,098 lines |
| Packaging version derived | `Makefile`, `debian/rules`, `slackware/sdata.SlackBuild` | sdata-core version globbed/injected, not hardcoded |
| ADR / spec / plan counts | `doc/adrs.md`, `doc/specs/`, `doc/plans/` | 44 / 22 / 28 |
