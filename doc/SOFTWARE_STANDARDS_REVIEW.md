# SData — Software Standards Report

**Version reviewed:** 0.6.5 | **Date:** 2026-04-30 | **Tests:** 96 passing
**Annotation:** 2026-05-01/02 (v0.6.6, 99 cmd + 33 unit tests) — debug system implemented; `Parse_CSV` monolith resolved; CI workflow validated; see annotated sections below.

---

## 1. Architectural Integrity

### 1.1 Structural Coherence

The architecture is a classic recursive-descent pipeline: Lexer → Parser → AST → Interpreter → Evaluator, with orthogonal satellites (Table, File_IO, Statistics, Variables, Help). Every package has a single stated mission and stays inside it. A new developer can read `doc/architecture.md` and orient themselves in under 20 minutes.

| Question | Verdict |
|---|---|
| Clear, defensible reason for current form? | ✅ Yes — pipeline mirrors SAS/BASIC two-pass execution model |
| New developer understands in 30 min? | ✅ Yes — architecture doc + package names tell the story |
| Orphaned modules? | ✅ None |
| Architecture astronaut syndrome? | ✅ None — no gratuitous abstractions |

**Justification Quality: 9/10.** The only note: `SData.Config` vs `SData.Config.Runtime` is a subtle split (static constants vs mutable run state) that is not explained inline and takes a moment to understand. **[v0.6.6]** `SData.CSV` added as a new pure satellite package containing the six CSV string helpers extracted from `Parse_CSV`; zero dependencies on any other SData package.

### 1.2 Dependency Graph

The dependency graph is **acyclic** and strictly layered. No circular dependencies detected. Direct library dependencies are:

| Library | Purpose | Maintained? |
|---|---|---|
| GNAT.OS_Lib / GNAT.Strings | Portable spawn, file ops, string access | ✅ (bundled with GNAT) |
| Ada_Sqlite3 | SQLite bindings for spillover store | ✅ |
| Zip-Ada | ZIP read/write for ODS/XLSX | ✅ |
| XMLAda (DOM.Core, DOM.Readers) | XML parsing for ODS/XLSX | ✅ |

**Dependency ratio is minimal and every dependency is load-bearing.** No redundant libraries, no unmaintained dead weight.

---

## 2. Code Quality & Craftsmanship

### 2.1 Naming & Readability

Ada's verbosity forces names to be complete. The codebase honours this. `Execute_Assignment`, `Parse_Expression_List`, `Coerce_Value`, `Logical_To_Physical`, `Clear_Fetch_Cache` — all read like sentences. No Hungarian notation. No lazy `Temp` or `Data` used as real variables (`Temp_Path` is a literal temp file path; `Dummy` appears only in `pragma Unreferenced`).

| Naming Precision | Self-Documentation | Cognitive Load |
|---|---|---|
| 9/10 | 8/10 | Medium |

One demerit: `S.Arr_Idx_List` / `Arr_Is_Slice` on the Statement record are abbreviated in a file where everything else is spelled out. Minor.

### 2.2 Function Design

**Top 5 by size:**

| Procedure | File:Line | Lines | Verdict |
|---|---|---|---|
| `Parse_CSV` | `sdata-file_io.adb:285` | ~~553~~ ~377 | ~~⚠️ Too large; nested helpers mitigate but don't excuse~~ **[Resolved v0.6.6]** 6 pure helpers extracted to `SData.CSV`; orchestrator only |
| `Parse_OOXML` | `sdata-file_io.adb:1264` | ~365 | ⚠️ Acceptable for DOM traversal but pushes the limit |
| `Parse_ODF` | `sdata-file_io.adb:995` | ~264 | ⚠️ Same |
| `Register_All_Functions` | `sdata-evaluator.adb:2392` | ~191 | ✅ Pure dispatch table; no branches; justified |
| `Execute_Statement` | `sdata-interpreter.adb:86` | ~117 | ✅ Each case is a single call; justified |

~~The file I/O parsers are the only genuine design smell. `Parse_CSV` contains a 1 MB heap-allocated line buffer, inline charset detection, column type inference, and multi-path field parsing — it does at least five distinct things. The inner helpers (defined as nested procedures) soften this but the procedure boundary is still too coarse.~~ **[Resolved v0.6.6]** `Parse_CSV` reduced from 553 to ~377 lines. The six pure string helpers (`Try_Fast_Float`, `Is_Numeric_Field`, `At_Delimiter`, `CSV_Field_End`, `CSV_Unquote`, `Split_Indices`) now live in `SData.CSV` and are covered by 33 compiled Ada unit tests. `Parse_CSV` is now a clean orchestrator; the helpers with legitimate closure dependencies on local state remain nested. `Parse_OOXML` and `Parse_ODF` remain large but have the DOM-traversal excuse.

| Avg Function Length | Max Function Length | Single Responsibility |
|---|---|---|
| ~35 lines | ~~553~~ ~365 lines (`Parse_OOXML`) | ~~7/10~~ **8/10** [v0.6.6] |

### 2.3 Comment Quality

**Comment sins found:**

| Sin Type | Location | Severity |
|---|---|---|
| Potentially stale "called by NEW" comment | `sdata-variables.adb` (corrected in v0.6.4 cycle) | Resolved |
| TODO without date/owner | `sdata-variables.adb:520` | Low |
| `--debug` flag defined but never consulted in interpreter | `sdata-config.ads:42` | ~~Medium — silently inert~~ **[Resolved v0.6.6]** |

**No commented-out code anywhere.** Comments in the codebase consistently explain *why* (e.g., the SQLite pragma block explains *why* `synchronous=OFF` is safe for a private temp file). This is correct discipline.

---

## 3. Efficiency & Performance

### 3.1 Algorithmic Choices

| Area | Algorithm Used | Assessment |
|---|---|---|
| Table sort | Merge sort (in-memory) / SQLite ORDER BY (spilled) | ✅ O(n log n) both paths |
| Symbol table lookup | `Ada.Containers.Indefinite_Maps` (hash) | ✅ O(1) average |
| Function dispatch | Hash map (100+ functions) | ✅ O(1) average |
| CSV field parsing | Single-pass character scan per line | ✅ O(line_length) |
| Column type inference | Buffered first 20 rows only | ✅ Bounded cost |

**No O(n²) patterns detected.** The data step loop is O(records × statements), which is the minimum necessary; statements are not data.

**One observation:** `Column_Order` in `sdata-table.adb` is a `Vector` and some operations scan it linearly to find a name by position (`Rename_Column`, `Drop_Column`). This is O(columns), which is negligible at typical widths — but if the design ever anticipates very wide tables (thousands of columns), this would be the first bottleneck.

### 3.2 Resource Management

| Area | Rating | Notes |
|---|---|---|
| Memory | 9/10 | Explicit `Unchecked_Deallocation`; heap-allocated buffers freed in exception handlers |
| SQLite temp file | 9/10 | Signal handler ensures cleanup even on SIGINT/SIGTERM |
| File handles | 9/10 | `Is_Open` guards in all exception handlers; no unclosed handle paths found |
| GNAT.OS_Lib args | 9/10 | String_Access args freed after Spawn |

Slight concern: the 1 MB `Line_Buf` in `Parse_CSV` is heap-allocated for every file opened. Inconsequential in practice but could be a static or pass-in buffer instead.

---

## 4. Maintainability & Evolvability

### 4.1 Test Coverage & Quality

| Metric | Value |
|---|---|
| Test count | ~~96~~ ~~99~~ 107 cmd + 33 compiled Ada unit tests **[v0.6.6]** |
| Test mechanism | File-based diff (`.cmd` → expected `.out`) + standalone `csv_unit_test` executable |
| Execution time | <30 seconds total (10s per-test ceiling, most <1s) |
| Flaky tests | None observed |

**[v0.6.6]** `make check` now runs `./bin/csv_unit_test` before the `.cmd` suite. The 33 unit tests cover all six `SData.CSV` functions (`Try_Fast_Float`, `Is_Numeric_Field`, `At_Delimiter`, `CSV_Field_End`, `CSV_Unquote`, `Split_Indices`) and are compiled Ada — they catch type errors and contract violations that file-diff tests cannot.

**Coverage gaps:**

1. ~~`HELP` command — the entire help dispatcher is untested. Any regression there is invisible.~~ **[Resolved v0.6.6]** 8 tests cover all four `Print_Help` code paths: index, `/ALL`, specific topic, unknown topic, plus case-insensitive lookup and alias dispatch.
2. Interactive REPL — pager integration, multi-statement entry, signal handling: zero automated coverage.
3. ~~`--debug` flag — defined in config, accepted by CLI, but never consulted in the interpreter. The flag does nothing.~~ **[Resolved v0.6.6]** `--debug` now emits per-statement and per-record trace to stderr; `BREAK`/`BREAK WHEN` deferred statements and interactive inspection REPL implemented. Tests: `debug_trace.cmd`, `break_basic.cmd`, `break_when.cmd`.
4. BY group edge cases — empty groups, single-record groups, group key changes on first record.
5. Array resizing (`TODO` at `sdata-variables.adb:520`) — the optimization path isn't tested either way.

**Test quality is high** — tests are behavioral (input script → expected output), not unit tests of implementation details. They survive refactoring. The `make check` harness is clean and produces an unambiguous pass/fail count.

### 4.2 Change Resilience

| Scenario | Files Typically Affected | Notes |
|---|---|---|
| New built-in function | `sdata-evaluator.adb` (handler + register) | 1–2 files; localized |
| New statement type | `sdata-ast.ads`, `sdata-parser.adb`, `sdata-interpreter.adb` | 3 files; well-defined path |
| New I/O format | `sdata-file_io.adb`, `sdata-file_io.ads`, `Open_Input`/`Open_Output` dispatch | 2 files |
| New CLI flag | `sdata_main.adb`, `sdata-config.ads`/`sdata-config-runtime.ads`, man page | 3–4 files |

Change blast radius is small and predictable. The parsing and execution pipelines are genuinely independent — adding a statement does not require touching the evaluator, and vice versa.

### 4.3 Technical Debt Inventory

| Item | Location | Estimated Effort | Trajectory |
|---|---|---|---|
| ~~`Parse_CSV` monolith~~ | ~~`sdata-file_io.adb:285`~~ | ~~4–6 hours~~ | **Resolved v0.6.6** — extracted to `SData.CSV`; 33 unit tests |
| ~~`--debug` flag silently inert~~ | ~~`sdata-config.ads:42`~~ | ~~2 hours~~ | **Resolved v0.6.6** |
| ~~HELP dispatcher untested~~ | ~~`sdata-help.adb`~~ | ~~2 hours~~ | **Resolved v0.6.6** |
| `CONTRIBUTING.md` missing | (project root) | 1 hour | Stable |
| Array resize TODO | `sdata-variables.adb:520` | 4 hours | Stable |

**Total remediation estimate: ~5 hours** (debug, Parse_CSV, and HELP coverage resolved in v0.6.6). **Debt is acknowledged, bounded, and not compounding.**

---

## 5. Error Handling & Resilience

### 5.1 Error Philosophy

The codebase has a single, consistent error strategy: **`SData.Script_Error` for all user-visible failures; Ada's standard exceptions for internal/programming errors; `Val_Missing` for recoverable numeric domain failures.** This is the right three-level taxonomy for an interpreter.

| Area | Rating | Notes |
|---|---|---|
| Consistency | 9/10 | `Script_Error` used uniformly; no ad-hoc `Put_Line ("Error: ...")` |
| Informativeness | 9/10 | Variable names, file names, and type context included in messages |
| Recovery patterns | 8/10 | `--ignore-math-errors` flag converts domain errors to missing; appropriate |

The `Handle_Domain_Error` helper at `sdata-evaluator.adb:90` is a clean single point of control for the math error policy.

### 5.2 Failure Modes

This is a batch interpreter, not a network service — no circuit breakers or retry logic are warranted. Failure modes that do apply:

| Scenario | Handling |
|---|---|
| File not found | `Script_Error` with filename |
| Malformed CSV/ODS/XLSX | `Script_Error` or `Program_Error` with format context |
| Integer overflow | Caught by `Constraint_Error` handler; reported as Script_Error |
| SIGINT during batch run | Signal handler cleans up SQLite temp file; exits |
| LibreOffice unavailable for formula recalc | Warning to stderr; falls back to cached values gracefully |

The LibreOffice fallback (`sdata-file_io.adb:1058–1062`) is an excellent example of graceful degradation: the feature works better when LibreOffice is present but doesn't fail without it.

---

## 6. Security Posture

### 6.1 Input Validation

| Vector | Risk | Mitigation |
|---|---|---|
| Script files (user input) | Low — intentionally trusted | `--noshell` disables SYSTEM |
| CSV data | Low — values become `Val_String`/`Val_Numeric`; no eval | Type coercion in `Coerce_Value` |
| File paths | Low — permissive by design (interpreter, not web server) | N/A |
| Shell commands via SYSTEM | Medium — user can pass arbitrary shell strings | `--noshell` flag; Spawn (not `system()`) |

**SYSTEM uses `GNAT.OS_Lib.Spawn` passing the command as a single argument to `/bin/sh -c`** — not string concatenation into a shell call. This is the correct implementation. A user script that calls `SYSTEM "rm -rf /"` is the *user's* problem; the tool doesn't amplify it.

### 6.2 Secrets Management

No hardcoded credentials, tokens, or passwords anywhere in the source. The only "sensitive" path is the SQLite temp file path, which is generated by the OS and stored in a package-level variable for signal-handler cleanup — appropriate.

---

## 7. Operational Readiness

### 7.1 Observability

| Capability | Status |
|---|---|
| Structured logging | ❌ None — `Ada.Text_IO.Put_Line` only |
| Log levels | ❌ None — `--quiet` suppresses informational only |
| `--debug` flag | ✅ **[Resolved v0.6.6]** Emits `[debug]`-prefixed trace to stderr: statement kind + record number per deferred statement, record-load events, BREAK entry/exit. `BREAK`/`BREAK WHEN` pause execution and enter an interactive inspection REPL (PDV dump, variable query, step/continue/quit). Step mode (`s`) advances one record at a time when running interactively. |
| Error output on stderr | ✅ `Put_Line_Error` routes to stderr consistently |
| Quiet mode | ✅ `--quiet` suppresses dataset-open messages |

~~The `--debug` flag is a minor embarrassment — it's documented in the man page and accepted at the CLI but does absolutely nothing. A new user who enables it expecting trace output will be confused.~~ **[Resolved v0.6.6]** The flag now produces meaningful trace output; see the Observability table above.

### 7.2 Deployment & Build

| Capability | Status |
|---|---|
| Build | ✅ `make` / `alr build` |
| Test | ✅ `make check` (~~96~~ 99 cmd + 33 unit tests, <30s) **[v0.6.6]** |
| Install | ✅ `make install` (binary + man page) |
| Package (RPM) | ✅ `make srpm` |
| Package (Debian) | ✅ `make dsc` |
| Package (Slackware) | ✅ `make slackware` |
| Package (macOS) | ✅ `make pkg` |
| Version bump | ✅ `scripts/bump-version.sh` (atomic 9-file update) |
| Rollback | ✅ Git history |
| CI/CD | ✅ `.github/workflows/test.yml` — push + PR on `main`; `alr build` + binary existence guard + `make check` (33 unit + 99 cmd); ubuntu-latest **[v0.6.6]** |

The `bump-version.sh` script is genuinely excellent — it validates format, detects old version strings, updates all locations atomically, and optionally builds, tests, commits, and tags. Most projects of this size don't have this.

---

## 8. Documentation

| Artifact | Rating | Notes |
|---|---|---|
| `README.md` | 9/10 | Build, test, install, usage, dependencies — all present and accurate |
| `man/man1/sdata.1` | 9/10 | Comprehensive command and function reference; accurately reflects 0.6.4 |
| `doc/architecture.md` | 8/10 | Package map, execution tiers, data step flow — solid contributor doc |
| `doc/CRITIQUE.md` | 9/10 | Self-aware, dated, tracks fix status — rare and valuable |
| `CONTRIBUTING.md` | ❌ Missing | Noted in CRITIQUE; deferred |
| ADRs (Architecture Decision Records) | ❌ None | Design rationale lives in `design.odt` and commit messages only |

---

## Overall Scores

| Category | Score | Notes |
|---|---|---|
| Architectural Integrity | 88/100 | Clean pipeline; minor Config split confusion |
| Code Quality | ~~78/100~~ **83/100** | Good naming/comments; ~~`Parse_CSV` monolith is the outlier~~ Parse_CSV monolith resolved v0.6.6 |
| Efficiency | 87/100 | No algorithmic flaws; `Column_Order` linear scan is latent |
| Maintainability | ~~80/100~~ **86/100** | Strong tests + Ada unit tests + HELP coverage; REPL gap remains; debug resolved v0.6.6 |
| Error Handling | 87/100 | Consistent strategy; good messages; LibreOffice fallback is exemplary |
| Security | 84/100 | Safe shell invocation; appropriate permissiveness for tool type |
| Operational Readiness | ~~74/100~~ **80/100** | Build/package pipeline is excellent; CI live v0.6.6; observability is Text_IO only; debug resolved v0.6.6 |
| Documentation | 86/100 | Strong across the board; missing CONTRIBUTING and ADRs |
| **TOTAL** | ~~664~~ **681/800** | +17 from Code Quality, Maintainability, and Operational Readiness improvements in v0.6.6 |

---

## The Hard Truth

This is good software. Genuinely good — not "good for a one-person project," but good by any measure. The architecture is clean, the tests are behaviorally correct, the error handling is disciplined, and the version management script is better than what most ten-person teams ship.

~~**The thing that would embarrass you in front of a senior engineer is `Parse_CSV`.** It is 553 lines, it does five different jobs, and it is effectively untestable as a unit. You cannot write a test for "the charset detection path inside Parse_CSV" without firing the whole machine. This is the only part of the codebase where the seams are in the wrong places. The rest of the I/O parsers (OOXML, ODF) are long for the same structural reason — DOM traversal is verbose — but they have a better excuse. CSV has no such excuse.~~ **[Resolved v0.6.6]** `Parse_CSV` is now a clean orchestrator (~377 lines). The six pure helpers live in `SData.CSV` with 33 compiled Ada unit tests. The seams are in the right places.

~~**The `--debug` flag is a lie to the user.**~~ **[Resolved v0.6.6]** `--debug` now delivers genuine observability: per-statement trace, per-record events, and an interactive `BREAK`/`BREAK WHEN` inspection REPL with step mode. The lie has been made true.

~~**The codebase has no CI.**~~ **[Resolved v0.6.6]** `.github/workflows/test.yml` runs on every push and PR to `main`: `alr build` → binary existence guard → `make check` (33 unit + 99 cmd tests). The class of "broken commit lands on main undetected" risk is now closed.

At 3 AM with a broken pipe in production? I'd trust this codebase. The error handling is solid, the fallbacks are real, and the test suite would have caught most regressions before they shipped. But I'd sleep better if `Parse_CSV` had been split apart three months ago.

---

## Appendix: Evidence Log

| Finding | File:Line | Evidence |
|---|---|---|
| ~~`Parse_CSV` monolith~~ | `sdata-file_io.adb:285` | ~~553 lines; contains charset detection, type inference, quote parsing, field splitting, row emission~~ **[Resolved v0.6.6]** ~377 lines; 6 helpers extracted to `src/sdata-csv.ads`/`sdata-csv.adb`; 33 unit tests in `tests/csv_unit_test.adb` |
| ~~`--debug` flag inert~~ | `sdata-interpreter.adb:186,1878,2124` | **[Resolved v0.6.6]** `Debug_Mode` now consulted in `Debug_Trace`, step-mode gate, and `BREAK` execution path; 3 tests cover trace and break behaviour |
| HELP untested | `sdata-help.adb` | No `tests/help*.cmd` exists |
| `Column_Order` linear scan | `sdata-table.adb:263–269` | Loop over Vector to find column name in `Rename_Column` |
| LibreOffice graceful fallback | `sdata-file_io.adb:1058–1062` | Warning to stderr + `using cached values` on missing LibreOffice |
| `SYSTEM` uses Spawn correctly | `sdata-system.adb:23` | `GNAT.OS_Lib.Spawn (Exec, Args, Success)` — not `system()` string concat |
| Signal cleanup registered | `sdata-table.adb:733` | `SData.Signals.Register_Cleanup_Path` called on SQLite temp file creation |
| Merge sort used | `sdata-table.adb:403–421` | `Merge_Sort` nested procedure; O(n log n) |
| One TODO in codebase | `sdata-variables.adb:520` | `-- TODO: Optimize for expansion/contraction to preserve values` |
| `bump-version.sh` atomic update | `scripts/bump-version.sh` | Updates 9 files; validates format; optional build/test/commit/tag |
