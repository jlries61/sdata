# Software Standards Audit: `SData` Statistical Data Interpreter

**Date:** 2026-05-14 | **Version:** 0.6.14 | **Auditor:** /software-standards v2.0.0
**Repository:** `/home/jries/Develop/sdata`
**Stack:** Ada 2012, GNAT/GPRbuild, Alire, SQLite3, Zip-Ada, XML-Ada, MathPaqs
**Domain:** Single-process batch/interactive interpreter — tabular statistical data processing
**Scope:** All Ada source files, build system, test suite, packaging

*This is a clean rewrite of the standards review as of v0.6.14. The previous document
(v0.6.13 and earlier) with its incremental annotations is preserved in git history.*

---

## 1. Architectural Integrity — **78/100**

### 1.1 Execution Model

The three-tier execution model is well-defined and consistently enforced:

| Tier | Examples | Behaviour |
|---|---|---|
| Declarative | USE, BY, SELECT, SAVE, FPATH, RSEED, OPTIONS | Execute immediately; configure interpreter state |
| Immediate | RUN, SORT, NEW, NAMES, LIST, HELP, SYSTEM | Execute immediately; not part of the data step |
| Deferred | LET, SET, PRINT, IF, FOR, WHILE, WRITE, DELETE | Queued in statement list; execute once per record |

This boundary is never breached. Deferred statements cannot be confused with immediate ones because they are queued rather than executed during parse. The design is documented in ADR-003 and in a block comment at the top of `sdata-interpreter.adb`.

### 1.2 Data Representation

The Program Data Vector (PDV) mirrors the current table schema as a flat `Value` vector. `Load_PDV_From_Table` fills it from the active row; `Flush_PDV_To_Output` writes it back. Column access uses a pre-resolved cursor cache (`Get_Value_By_Col` / `Set_Output_Value_By_Col`) — O(1), no per-row hash lookups. `SData.Table` is the sole source of truth for BY variable names, accessed via `By_Var_Count` / `By_Var_Name(I)`.

The SELECT filter is stored persistently as an expression and rebuilt as a logical→physical index map (`Filter_Map`) at the start of each `Run_One_Step`. All navigation functions operate in logical space.

### 1.3 Module Decomposition

Source is cleanly decomposed into focused packages:

**Interpreter:** `sdata-interpreter.adb` (912 lines, command dispatch + data step loop) + 9 `separate` subunits (1,387 lines total):

| Subunit | Lines | Responsibility |
|---|---|---|
| `execute_declarative` | 299 | USE, SAVE, BY, SELECT, FPATH, OPTIONS, … |
| `execute_metadata` | 259 | HELP, NAMES, LIST, SORT, RUN, NEW, … |
| `execute_assignment` | 182 | LET/SET (scalar and array) |
| `inspect_pdv` | 134 | BREAK interactive prompt |
| `process_one_record` | 132 | Per-record header, step-mode gate |
| `resolve_expr_indices` | 101 | Array index pre-resolution pass |
| `execute_print` | 97 | PRINT/WRITE/PUTLOG |
| `execute_control_flow` | 92 | IF/ELSE/FOR/WHILE/REPEAT/LOOP |
| `execute_io` | 91 | SUBMIT |

**Evaluator:** `sdata-evaluator.adb` (565 lines) + 6 child packages (2,097 lines): `distrib_fns`, `numeric_fns`, `string_fns`, `misc_fns`, `aggregate_fns`, `nav_fns`.

**File I/O:** `sdata-file_io.adb` (136 lines, public API) + 4 child packages: `Helpers` (172, private), `CSV` (643), `ODF` (453), `OOXML` (589).

**Support:** `sdata-table.adb` (1,042), `sdata-variables.adb` (728), `sdata-statistics.adb` (772), `sdata-help.adb` (1,559), `sdata_main.adb` (535), `sdata-config.ads` (55).

### 1.4 Concerns

- `sdata-help.adb` at 1,559 lines is the single largest source file. It is a large table of string literals with no logic; its size is not a complexity concern but it falls outside the decomposition pattern of every other module.
- The AST discriminated record (`Statement`) carries fields for all statement kinds in a single type. This is the standard Ada approach for sum types and is correct, but the type grows with every new statement kind.

---

## 2. Code Quality & Craftsmanship — **82/100**

### 2.1 Language Use

Ada 2012 provides strong static guarantees that raise the floor: bounds checking, discriminant constraints, no implicit type coercions, and `Ada.Finalization` controlled types for resource management. The codebase exploits these correctly:

- Discriminated records for the `Value` type and AST nodes — exhaustive `case` analysis where the discriminant is known
- Named association for calls with multiple parameters
- `Ada.Containers` instantiations for the statement list and symbol tables
- `pragma Annotate (GNATcheck, Exempt_On/Off, …)` for the two intentional `gnatcheck.rules` violations: mutual recursion in the evaluator tree traversal and `Open_Input`'s 9-parameter API

### 2.2 Exception Handling

Exception handling is mostly specific and informative. `Script_Error` is the standard user-visible exception; it carries an explanatory message and is never swallowed silently. `SQLite_Error` exceptions are fully wrapped with operation context at five sites in `sdata-table.adb`.

**Remaining `when others` handlers (23):** Most fall into three legitimate categories:
1. *Safety-net wraps* in `sdata_main.adb` (top-level catch-all → `Exception_Message`)
2. *Intentional null handlers* where a failed optional operation should not abort (e.g., `resolve_expr_indices` for non-fatal index resolution failures)
3. *Format-agnostic re-raise* in file I/O where the correct response to any unexpected error is `Script_Error`

A handful of `when others => null` handlers in the interpreter body (`sdata-interpreter.adb:447`, `:613`) are silent and warrant future tightening.

### 2.3 Naming and Style

Identifier names are self-documenting (`Flush_PDV_To_Output`, `Filter_Map`, `Column_Cursor_Cache`). The Ada convention of underscore-separated capitalized words is applied consistently. No abbreviations that require domain knowledge to decode.

### 2.4 Static Analysis

`gnatcheck.rules` enforces two rules: `Recursive_Subprograms` and `Too_Many_Parameters:8`. Both are not run in CI (GNATcheck requires the Ubuntu `asis-programs` package, not present on Debian/openSUSE). CodePeer has not been run.

---

## 3. Efficiency & Performance — **78/100**

### 3.1 Data Step Hot Path

The data step inner loop (`Run_One_Step`) has no per-row hash lookups. The `Column_Cursor_Cache` maps column names to integer indices once per schema load; `Get_Value_By_Col(Row, I)` and `Set_Output_Value_By_Col(I, V)` are direct index operations. The evaluator resolves array variable indices ahead of the data step loop via `Resolve_Expr_Indices`.

### 3.2 Table Storage

In-memory column-store with SQLite spillover. When `Add_Row` reaches `Max_Table_Cells` (default 50,000,000 cells ≈ 1.5 GB at 32 bytes/cell), rows are batched into SQLite via `Spill_Table_To_Disk` with a single `BEGIN`/`COMMIT` transaction per spill. `Fetch_From_Disk` reads segments on demand with a segment cache; reads are not per-row I/O. `PRAGMA journal_mode=OFF` and `PRAGMA synchronous=OFF` are applied for write performance.

### 3.3 Parser and Evaluator

The recursive-descent parser allocates AST nodes on the heap. No arena allocation. For typical script sizes (< 1,000 statements) this is not a bottleneck.

The evaluator uses standard algorithms for statistical distributions with citations ([A&S], [NR], [MT00], [BM58], [DLMF]).

### 3.4 Gaps

- No profiling infrastructure. `time` at the shell level works but there is no per-statement timing.
- No memory usage reporting (heap or PDV).
- No lazy evaluation beyond the `IF()` built-in (full argument evaluation before function dispatch).
- For very wide tables (10,000+ columns), the PDV fill/flush loop is O(columns) per record. No column projection is possible.

---

## 4. Maintainability & Evolvability — **84/100**

### 4.1 Test Coverage

| Suite | Count | Scope |
|---|---|---|
| Integration tests | 135 | End-to-end `.cmd` scripts; every language feature has at least one test |
| CSV unit tests | 71 | All five `SData.CSV` public functions; edge cases |
| Variable/Table unit tests | 122 | PDV, temp/permanent symbols, hold, sort, drop, column cache |
| Evaluator unit tests | 166 | All operators, type promotion, comparison, string ops, IF() laziness |
| File I/O unit tests | 89 | CSV (with diagnostic warnings), ODF, OOXML; INF values, sheet selection |
| Interpreter unit tests | 48 | Control flow, assignment, SELECT, REPEAT; full parse→execute→inspect cycle |
| **Total** | **631** | |

CI runs all unit tests plus all 135 integration tests on every push to main and every PR. Fuzz corpus regression (26 seeds across 4 drivers) also runs in CI.

### 4.2 Change Resilience

Adding a new deferred statement requires touching one subunit (`execute_assignment.adb`, `execute_control_flow.adb`, etc.) plus the AST discriminated record and the parser. The interpreter parent body (`sdata-interpreter.adb`) only needs a new dispatch arm in `Run_One_Step`. Adding a new CSV/ODF/OOXML format feature is isolated to the relevant `sdata-file_io-*.adb` child package.

### 4.3 Decision Records

37 ADRs in `doc/adrs.md` cover language choice, execution model, table design, CLI conventions, security restrictions, test strategy, and per-session architectural calls. 10 design specs and 19 implementation plans in `doc/specs/` and `doc/plans/`.

### 4.4 Versioning and Release

`scripts/bump-version.sh` updates 9 files atomically (source, alire.toml, Makefile, RPM spec, Slackware, man page, README, Debian changelog). Git tags on version bump commits.

### 4.5 Gaps

- No mutation testing or coverage measurement beyond the test count.
- `gnatcheck` is not in CI (platform availability issue).
- The statistics module (`sdata-statistics.adb`, 772 lines) has no dedicated unit tests — covered only via integration tests that exercise the distribution functions.

---

## 5. Error Handling & Resilience — **73/100**

### 5.1 User-Visible Errors

`Script_Error` is raised with a descriptive message at every error site and caught at the top level in `sdata_main.adb`, which prints it and exits with a non-zero status. `--continue-on-error` catches `Script_Error` per-statement and resumes; `ERR()` / `ERL()` expose the last error to the script.

`--ignore-math-errors` converts floating-point domain errors to `Val_Missing` instead of halting. This is correct for statistical workflows where a single bad value should not abort a 10,000-record run.

### 5.2 CSV Diagnostic Warnings

`sdata-file_io-csv.adb` emits actionable warnings for four malformed-input categories: unclosed quoted fields, type mismatches in typed columns, extra fields beyond header count, and short rows. All messages include filename, data-row number, and column index. Values are stored as `Val_Missing` rather than silently coercing.

### 5.3 SQLite Error Handling

Five `SQLite_Error` handlers in `sdata-table.adb` wrap all backing-store operations with operation-specific messages ("could not write dataset to disk (disk full?): …"). Previously, `SQLite_Error` propagated unhandled and was laundered by the interpreter's generic `when others`.

### 5.4 Resource Cleanup

- `Ada.Finalization.Limited_Controlled` `Finalize` on `Backing_Store` deletes the SQLite temp file on normal exit, including unhandled exception paths.
- SIGTERM and SIGINT handlers in `sdata-signals.adb` delete the temp file before exit.
- SIGKILL and power loss cannot be caught (residual risk; noted in threat model).

### 5.5 Shell Timeout

`OPTIONS SHELLTIMEOUT n` and `--shell-timeout=N` set a per-command wall-clock timeout (default 300 s in batch mode, 0 in interactive mode). Implementation uses `GNAT.OS_Lib.Non_Blocking_Spawn` + 0.5 s poll loop + `Kill` + `Wait_Process` — no external dependency on `timeout(1)`.

### 5.6 Gaps

- 23 `when others` handlers; several (`sdata-interpreter.adb:447`, `:613`) are silent null handlers that could mask unexpected exceptions.
- No SUBMIT nesting depth limit. A script that calls SUBMIT on itself can exhaust stack (unlikely in practice; addressed by `--nosubmit`).
- No per-expression timeout. A `WHILE` loop that never terminates runs indefinitely.

---

## 6. Security Posture — **77/100**

### 6.1 Trust Model

The OS account is the security boundary. A script can do anything the account can do — this is intentional and matches the trust model of `awk`, `make`, R (`system()`), Python (`subprocess`). The correct operator mitigation is a restricted account, not a restricted tool. See `doc/threat_model.md`.

### 6.2 Implemented Controls

| Control | Mechanism | ADR |
|---|---|---|
| Disable SYSTEM/SHELL | `--noshell` | ADR-031 |
| Disable SUBMIT | `--nosubmit` | ADR-032 |
| Auto-enforce on root/SYSTEM | Checked at startup | ADR-033 |
| SQL injection (column names) | `Sql_Id` double-brackets `]` | — |
| SQLite temp file cleanup | Signal handlers + Finalize | ADR-025 |
| SYSTEM/SHELL timeout | `--shell-timeout=N`, `OPTIONS SHELLTIMEOUT` | ADR-037 |

### 6.3 Fuzz Coverage

Four fuzz drivers using AFL++ `@@` convention:
- `csv_fuzz_driver` — all six `SData.CSV` public functions
- `parser_fuzz_driver` — lexer and recursive-descent parser
- `ods_fuzz_driver` — `Parse_ODF` (Zip-Ada + XML-Ada path)
- `xlsx_fuzz_driver` — `Parse_OOXML` (Zip-Ada + XML-Ada path)

26-seed corpus regression runs in CI (`make fuzz-corpus`). Full coverage-guided fuzzing with AFL++ is not continuous.

### 6.4 Gaps

- `--noshell` and `--nosubmit` are opt-in, not default. Operators running untrusted scripts must remember to set them.
- No formal SAST in CI (`gnatcheck` is manual Ubuntu-only).
- CodePeer has not been run.
- No path-traversal restriction inside SUBMIT (by design; `--nosubmit` is the mitigation).

---

## 7. Operational Readiness — **66/100**

### 7.1 Observability

`--debug[=N]` emits structured trace lines to stderr at three configurable levels:

| Level | Name | Trace output |
|---|---|---|
| 1 | sparse | USE opened, SUBMIT entering, RUN complete |
| 2 | normal | Level 1 + per-record header + IF/FOR/SELECT/DELETE outcomes |
| 3 | verbose | Level 2 + every LET/SET assignment |

`OPTIONS DEBUG N` adjusts the level at runtime, allowing scripts to narrow tracing to a specific segment. `ERR()` / `ERL()` expose last-error state to scripts.

No structured logging, no metrics, no performance histograms. These are inherent limitations of a single-process CLI batch tool, not gaps that need fixing.

| Capability | Quality |
|---|---|
| Debug tracing | 8/10 — three configurable levels; runtime adjustable |
| Error introspection | 7/10 — ERR()/ERL() in script; no stack trace to user |
| Performance profiling | — (not present) |
| Structured logging | — (not applicable) |
| Metrics | — (not applicable) |

### 7.2 Deployment & Configuration

All runtime behaviour is controlled by CLI flags; no hardcoded paths, no required config files. `OPTIONS` provides runtime reconfiguration of MAXINTAB, MAXTEMPMEM, CSVDLM, HEADER, SAVEOVERWRT, TXTFMT, CHARSET, IEEE_DIVIDE, SHELLTIMEOUT, and DEBUG. Bare `OPTIONS` displays all current values.

Multi-platform packaging is mature:
- RPM (`sdata.spec`)
- Debian/Ubuntu (`debian/`)
- Slackware (`slackware/sdata.SlackBuild`)
- macOS and Windows builds documented in README and CONTRIBUTING.md

CI/CD: GitHub Actions runs `alr build` + `make check` + fuzz corpus regression on every push to main and every PR. Alire package cache keyed on `alire.toml` hash reduces cold-build time.

| Capability | Score |
|---|---|
| Config externalization | 9/10 |
| Packaging breadth | 9/10 |
| CI/CD | 9/10 |
| Deployment automation | 8/10 |
| Rollback | 8/10 (git tags, versioned packages) |

### 7.3 Gaps

- No monitoring or health-check mechanism for long-running batch jobs (no `--progress` flag or record-count reporting).
- No log file redirection; debug output goes to stderr only (addressable at shell level with `2>file`).

---

## 8. Documentation — **87/100**

### 8.1 End-User Documentation

- **Man page** (`man/man1/sdata.1`, 854 lines): comprehensive; covers every option, statement, expression, and built-in function. Kept current with implementation.
- **In-system help** (`HELP /ALL`): matches the man page; generated from `sdata-help.adb` at runtime.
- **README.md** (283 lines): build requirements, feature overview, example usage, platform notes.
- **CONTRIBUTING.md** (286 lines): seven-step Alire-based quickstart targeting ~15 min from zero to passing tests; code map, dev workflow, reference document index.

### 8.2 Design and Architecture Documentation

- **`doc/adrs.md`**: 37 ADRs (ADR-001–037) covering language choice, execution model, table design, CLI conventions, security restrictions, test strategy, and per-session decisions. Status field (Accepted / Superseded) maintained.
- **`doc/threat_model.md`**: full STRIDE analysis; nine threats with likelihood, impact, status, and mitigation. Trust model explained. Deployment recommendations for pipeline operators.
- **`doc/specs/`**: 10 design specs for completed features.
- **`doc/plans/`**: 19 implementation plans (retained as project record).
- **`doc/design.odt`**: authoritative language spec, data model, command reference, built-in functions, BY-group semantics. Not plain text; requires LibreOffice or `soffice --headless --convert-to txt`.
- **`doc/SOFTWARE_STANDARDS_REVIEW.md`**: this document (living audit).

### 8.3 Algorithm Documentation

`sdata-statistics.adb` has a reference block at the top ([A&S], [NR], [MT00], [BM58], [DLMF]) and per-function citations for all distribution and IDF implementations. Statistical algorithms are no longer undocumented.

### 8.4 Gaps

- `doc/design.odt` is the authoritative language spec but is binary (ODF). No plain-text equivalent is committed. Developers must convert it manually or use LibreOffice.
- The statistics module has algorithm citations but no prose explanation of implementation choices (e.g., why Beasley-Springer-Moro for normal IDF vs. rational approximation).

---

## Overall Scores

| Category | Score |
|---|---|
| Architectural Integrity | **78/100** |
| Code Quality & Craftsmanship | **82/100** |
| Efficiency & Performance | **78/100** |
| Maintainability & Evolvability | **84/100** |
| Error Handling & Resilience | **73/100** |
| Security Posture | **77/100** |
| Operational Readiness | **66/100** |
| Documentation | **87/100** |
| **TOTAL** | **625/800 (78.1%)** |

---

## Prioritized Remediation

Items where a focused effort would move the score most:

| Priority | Item | Affected section | Effort | Gain |
|---|---|---|---|---|
| 1 | Tighten silent `when others => null` handlers in interpreter body | §5 | Low | §5 +1 |
| 2 | `gnatcheck` in CI (Ubuntu runner or alternative SAST tool) | §6 | Medium | §6 +1 |
| 3 | Unit tests for `sdata-statistics.adb` | §4 | Medium | §4 +1 |
| 4 | Plain-text committed version of `doc/design.odt` | §8 | Low | §8 +1 |
| 5 | Progress reporting flag (`--progress N`) for long batch jobs | §7 | Medium | §7 +1 |
| 6 | SUBMIT nesting depth limit | §5 | Low | §5 +1 |
