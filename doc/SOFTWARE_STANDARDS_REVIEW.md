# Software Standards Audit: `SData` Statistical Data Interpreter

**Date:** 2026-05-05 | **Version:** 0.6.8 | **Auditor:** /software-standards v1.0.0
**Repository:** `/home/jries/Develop/sdata`
**Stack:** Ada 2012, GNAT/GPRbuild, Alire, SQLite3, Zip-Ada, XML-Ada, MathPaqs
**Domain:** Single-process batch/interactive interpreter — tabular statistical data processing
**Scope:** All Ada source files, build system, test suite, packaging

*Note: Template adapted for single-codebase deep-dive audit.*
**Annotation:** 2026-05-05 (v0.6.8) — `doc/adrs.ods` (30 decisions, ADR-001–030) confirmed present; pointer added to `doc/architecture.md`; Architectural docs 5→8/10; Documentation 76→82, total 507→513.
**Annotation:** 2026-05-06 (v0.6.8) — SYSTEM/SHELL risk reclassified Low-Medium; sandboxing, allowlist, and metacharacter-escaping are won't-fix (deliberate design, same trust model as R/SAS/Python; --noshell is the correct operator-level mitigation). Security 52→58, total 513→519.
**Annotation:** 2026-05-06 (v0.6.8) — SQL column-name injection fixed (commit 456d1e0): `Sql_Id` helper now escapes `]`→`]]` at all five SQL construction sites in `sdata-table.adb`. Security 58→63, total 519→524.
**Annotation:** 2026-05-06 (v0.6.8) — `--nosubmit` flag added (commit 6909f15): disables SUBMIT for pipeline operators who need containment beyond `--noshell`; path traversal via SUBMIT marked won't-fix (same trust-model reasoning as SYSTEM/SHELL; `--nosubmit` is the opt-in mitigation). Security 63→65, total 524→526.

---

## Overall Posture

```
⚠  Drifting — sound domain model, but structural rot accumulating in three
   subsystems faster than it is being repaired
```

---

## 1. Architectural Integrity — 65/100

### 1.1 Structural Coherence

**Does the architecture have a clear, defensible reason for existing in its current form?**
Yes. The three-tier model (Declarative → Immediate → Deferred) is coherent, documented at the top of `sdata-interpreter.adb`, and consistently applied. The evaluator, table, variables, and help subsystems have clear charters. The parser and lexer are separate packages with appropriate layering.

**Can a new developer understand the system's organization in under 30 minutes?**
Mostly. The package structure is logical; an Ada developer can navigate it. But `sdata-interpreter.adb` (2,213 lines) and `sdata-file_io.adb` (1,646 lines) are still intimidating single-file subsystems. The evaluator refactoring brought `sdata-evaluator.adb` from 2,589 lines to 517, which was a significant quality improvement — but the same treatment has not been applied to file I/O or the interpreter.

**Are there orphaned modules?**
No orphaned modules detected. Every package is actively used.

**Architecture astronaut syndrome?**
The SQLite backing store for large tables (`ada_sqlite3`) is a justified complexity — without it, multi-million-row datasets would exhaust memory. The Zip-Ada and XML-Ada dependencies for ODF/OOXML are similarly justified. No gratuitous abstractions.

### 1.2 Dependency Analysis

| Dependency | Purpose | Version Pinned | Last Activity |
|---|---|---|---|
| zipada | ODF archive extraction | ^61.0.0 | Active |
| xmlada | XML parsing (ODF/OOXML) | ^26.0.0 | Active (AdaCore) |
| mathpaqs | Statistical distributions | exact (20260205) | Active |
| ada_sqlite3 | Disk-backed table storage | ^0.1.1 | Active |

Four direct dependencies, all justified, all maintained, no version-pinning mismatches. Dependency hygiene is **exemplary** for a project of this size. No npm-style dependency explosion.

**Verdict:** The architectural foundations are sound. The two failing grades are (1) the global-state integration bus documented in `SKEPTIC_REVIEW.md` — still partially present despite the `Step_Context` refactoring — and (2) the monolithic parser procedures in `sdata-file_io.adb` that have never been decomposed.

---

## 2. Code Quality & Craftsmanship — 72/100

### 2.1 Naming & Readability

Ada's verbosity forces long names, which here is a feature. `Flush_PDV_To_Output`, `Reset_PDV_Non_Held`, `Rebuild_Filter_Map`, `Is_Identifier_Ref_Function` — all describe exactly what they do. No single-letter variables outside loop counters; no ambiguous abbreviations.

| Dimension | Score | Notes |
|---|---|---|
| Naming Precision | 9/10 | Excellent; Ada verbosity works in the codebase's favour |
| Self-Documentation | 7/10 | Good in evaluator/table; weakens inside file_io monoliths |
| Cognitive Load | Medium | Low in most files; **High** inside Parse_CSV and Parse_OOXML |

### 2.2 Function Design

**The two problems:**

`Parse_CSV` (`sdata-file_io.adb:286–677`) is **392 lines**. It simultaneously handles field tokenization, quote handling, escape sequences, column-type inference, and row loading. That is four distinct responsibilities in one procedure. A bug in type inference requires a developer to navigate 300 lines of tokenizer logic to find it.

`Parse_OOXML` (`sdata-file_io.adb:1103–1471`) is **369 lines**, with `Parse_ODF` at **268 lines**. All three XML/CSV parsers share the same structural flaw: data extraction and type inference are interleaved rather than separated into passes.

`Execute_Assignment` (`sdata-interpreter.adb:659–793`) is **135 lines** and handles range expansion, array indexing, LET/SET semantics, type coercion, and PDV updates in a single procedure. It does not have one job.

| Procedure | Lines | SRP Score | Verdict |
|---|---|---|---|
| Parse_CSV | 392 | 3/10 | Structural failure |
| Parse_OOXML | 369 | 3/10 | Structural failure |
| Parse_ODF | 268 | 4/10 | Very long |
| Execute_Assignment | 135 | 5/10 | Too broad |
| Process_One_Record | 130 | 7/10 | Large but coherent |
| Evaluate_Function | 134 | 6/10 | Complexity is warranted (array expansion) |
| Help_CONCEPTS | 51 | 9/10 | Fine |

### 2.3 Comment Quality

**Positives:** The design comments at the top of `sdata-interpreter.adb` and `sdata-evaluator.adb` are genuinely useful — they explain the *why* of the three-tier model and dispatch table design. The `Set_Group_Boundary` spec comment is an exemplary contract declaration.

**Comment sins:**

| Sin | Location | Severity |
|---|---|---|
| Section headers masquerading as design rationale | `sdata-help.adb:532` (`-- Math functions`) | Minor |
| "NEW should clear all array definitions" is action-oriented, not rationale | `sdata-variables.adb:151` | Minor |
| XML-parsing navigation comments describe *what* the loop does, not *why* the XPath equivalent was rejected | `sdata-file_io.adb:880–920` | Moderate |
| `pragma Warnings (Off, SData.Evaluator.Numeric_Fns)` has a correct explanatory comment, but the elaboration-cycle constraint that forced it warrants a longer note | `sdata-evaluator.adb:9–14` | Minor |

No commented-out code detected. No anonymous TODOs. This is clean.

---

## 3. Efficiency & Performance — 74/100

### 3.1 Algorithmic Choices

The dispatch table in `SData.Evaluator` (hashed map, O(1) per lookup) is correct for ~150 registered functions. Linear scan in `Help_Table` (`sdata-help.adb:1449–1455`) is O(n) over ~170 entries — acceptable given that HELP is not a hot path.

The `Filter_Map` is an array of physical row indices, built once per RUN via `Rebuild_Filter_Map`. Logical-to-physical mapping is O(1) thereafter. This is the correct design.

**Algorithmic concern — column access:**
`Data_Table` is `Column_Maps.Map` keyed by column name (`Ada.Containers.Indefinite_Hashed_Maps`). Per-cell access is `Data_Table("COLNAME").Data(Row_Index)`. This means every cell read during a data step — which happens M × N times (M statements × N rows) — performs a hash lookup on the column name. For a dataset with 50 columns and 100,000 rows, this is 5 million unnecessary hash lookups per data step if PDV indices could be pre-resolved. The PDV index cache (`Expr.Var_Index`) partially mitigates this for parsed expressions, but direct column reads in `Get_PDV_Value`/`Load_PDV_From_Table` still go through the hash map on every record.

| Concern | Impact | Fix Difficulty |
|---|---|---|
| Column-name hash lookup per record in table operations | Medium (measurable on large datasets) | Medium |
| Linear help-table scan | None (cold path) | Easy |
| BY-variable list duplicated (interpreter + table) | Negligible performance, high maintenance cost | Medium |

### 3.2 Resource Management

Ada's deterministic stack allocation and GNAT's runtime make memory leaks in the conventional sense rare. Heap allocation is explicit (`new`) and appears disciplined. The SQLite spill path correctly uses a temp file that is removed on `Clear`.

The `Filter_Map` (`Index_Array_Access`) is heap-allocated and freed in `Set_Index_Map` when replaced — correct. Expression trees (`Expression_Access`) allocated by the parser are never freed because the program buffer persists for the session lifetime; this is an intentional trade-off, not a leak.

| Resource | Handling | Score |
|---|---|---|
| Memory (general) | Disciplined; no leaks detected | 8/10 |
| File handles | `Ada.Text_IO` and Zip file handles appear to be closed correctly | 8/10 |
| SQLite connection | Opened on spill, managed via `ada_sqlite3` | 7/10 |
| Expression tree arena | Never freed; bounded by session lifetime | 6/10 (acceptable) |

### 3.3 Startup & Runtime Costs

No dynamic library loading, no JIT, no network calls at startup. Binary starts in < 50ms. Memory footprint at idle: < 5 MB. Under load (100k-row dataset), memory is bounded by the spill threshold configured via `-m`. No unnecessary blocking at startup.

---

## 4. Maintainability & Evolvability — 60/100

### 4.1 Test Coverage & Quality

**This is the weakest dimension.**

| Metric | Value | Verdict |
|---|---|---|
| Unit test modules | 1 (csv_unit_test) | Critically insufficient |
| Integration tests | 118 .cmd files | Comprehensive for happy paths |
| Coverage estimate | ~35–45% branch coverage | Below minimum acceptable |
| Test execution time | < 30s total | Excellent |
| Flaky tests | None observed | Good |

The evaluator, interpreter, table module, variable system, and file I/O have zero unit test coverage. Integration tests cannot isolate regression sources when failures occur across subsystem boundaries. The `distrib_test` unit test added in a prior session covers statistical functions — that is the only other non-CSV unit test and it demonstrates the model works. Expanding it to cover evaluator expression trees, table operations, and BY-group detection would require no architectural change.

### 4.2 Change Resilience

Adding a new built-in function requires: (1) a handler in the appropriate child package, (2) a `Dispatch_Table.Insert` call in that package's `Register`, (3) a `Help_*` procedure and key/table entry in `sdata-help.adb`. Three files, well-defined seams. This is genuinely good design that pays dividends.

Adding a new command requires: parser (token + production), AST node, interpreter `Execute_Statement` case arm, and help entry — four files, all with clear extension points.

Adding a new file format requires modifying `sdata-file_io.adb` — one file, but that file is already 1,646 lines. Extension is technically contained but practically difficult because the existing format procedures are too long to serve as readable models.

| Change Type | Files Affected | Difficulty |
|---|---|---|
| New built-in function | 2 | Easy |
| New command | 4 | Medium |
| New file format | 1 (large) | Hard |
| New distribution family | 1 | Easy |
| Change column storage model | 5+ | Hard |

### 4.3 Technical Debt Inventory

| Item | Severity | Remediation Effort | Trajectory |
|---|---|---|---|
| `Parse_CSV` / `Parse_OOXML` / `Parse_ODF` monoliths | High | 3–4 days | Stable (not growing) |
| `Execute_Assignment` too broad | Medium | 1 day | Stable |
| Integration-only test coverage | High | 2–3 days per module | Stable |
| BY-variable list duplication (interpreter + table) | Medium | 4 hours | Stable |
| Column hash lookup per record | Low | 1 day | Stable |
| No CI/CD pipeline | Medium | 4 hours | Stable |
| Global interpreter state (remaining post-Step_Context) | Medium | 2–3 days | Shrinking |

**Total estimated remediation: ~12–15 days. Interest rate: Stable.** The codebase is not actively accruing debt; it is maintaining its current level.

---

## 5. Error Handling & Resilience — 58/100

### 5.1 Error Philosophy

`Script_Error` is the single user-facing exception type, raised with descriptive messages throughout the interpreter and evaluator. The `-k` flag's `Continue_On_Error` path correctly catches it, logs to `ERR`/`ERL`, and continues. This is a coherent primary strategy.

**Where it breaks down:**

`sdata-file_io.adb` uses `Program_Error` in one location (`Parse_ODF:1093`) and `Script_Error` everywhere else — an inconsistency that will silently fall through `-k` handling. `Program_Error` in Ada is a language-defined exception for programming errors, not user-visible data errors; raising it for "merged cells in ODS file" is architecturally wrong.

`sdata-csv.adb` contains:
```ada
when others => return False;
```
twice (lines 42–45). Both swallow every exception type silently, including potential constraint errors that would mask format misdetection bugs.

`sdata-file_io.adb` has five additional broad `when others` handlers. Some re-raise; some suppress. There is no consistent policy about which exceptions from file I/O should surface to the user vs. be handled internally.

| Module | Error Consistency | Error Informativeness | Recovery |
|---|---|---|---|
| Evaluator | 9/10 | 9/10 | 9/10 |
| Interpreter | 8/10 | 8/10 | 8/10 |
| Table | 7/10 | 7/10 | 7/10 |
| File I/O | 4/10 | 5/10 | 5/10 |
| CSV | 3/10 | 3/10 | 3/10 |

### 5.2 Failure Modes

External services are limited to: shell commands (SYSTEM/SHELL), file system, SQLite. Shell failures are reported via return code. File-not-found raises `Script_Error` with filename. SQLite failure modes are partially handled but not uniformly.

No timeout logic for shell commands launched via SYSTEM — a long-running shell command blocks the interpreter indefinitely with no escape mechanism.

---

## 6. Security Posture — 52/100

### 6.1 Input Validation

**SYSTEM / SHELL — deliberate design, appropriate default:** The SYSTEM and SHELL commands pass their string argument to `/bin/sh -c`. This is the intended behaviour: SYSTEM is a first-class, documented feature serving the same role as `SYSTEM` in SAS or `system()` in R. Script authors are trusted by definition; the threat model is identical to R, Python, or any other scripting language used for data preparation. The `--noshell` flag gives pipeline operators an opt-in restriction for untrusted-script contexts — placing the responsibility on the operator is correct and consistent with how comparable tools handle this.

Sandboxing, allowlisting, and metacharacter escaping are all **won't-fix**: sandboxing adds platform-specific complexity without a realistic threat to defend against at this deployment scope; an allowlist cannot be defined generically without breaking legitimate use; escaping metacharacters would silently neuter the feature (pipes and redirects are intentional). **[Reclassified Low-Medium 2026-05-06.]**

**SQL column name injection:** `sdata-table.adb` constructs SQLite DDL/DML from column names. Column names originate from CSV headers (user-controlled input). If a column name contains SQL metacharacters (`"`, `'`, `--`), the generated SQL may be malformed or exploitable. This needs verification and quoting.

**Path traversal:** `Full_Path` in the interpreter resolves file paths using `FPath_*` base directories but does not explicitly reject `../` sequences. A SUBMIT statement could potentially traverse outside the intended working directory.

| Vector | Risk Level | Mitigated? |
|---|---|---|
| SYSTEM / SHELL | ~~High~~ **Low-Medium** | `--noshell` flag; deliberate design — won't-fix |
| SQL column name injection | Medium | ~~Not confirmed; no quoting found~~ **Fixed 456d1e0 — `Sql_Id` escapes `]`→`]]`** |
| Path traversal via SUBMIT | Low-Medium | `--nosubmit` flag (opt-in); won't-fix by default |
| ~~Expression evaluation overflow~~ | ~~Low~~ | ~~Ada Constraint_Error handled~~ **Resolved v0.6.9: Inf is now a first-class `Val_Numeric` value. Float overflow produces ±Inf; NaN from Inf arithmetic raises Script_Error (or `Val_Missing` with `--ignore-math-errors`). See `doc/specs/2026-05-06-inf-neginf-design.md`.** |

### 6.2 Secrets Management

No hardcoded credentials. No network services. No authentication tokens. This is a CLI tool, not a service — secrets management is not applicable at this scope.

---

## 7. Operational Readiness — 50/100

### 7.1 Observability

`--debug` mode emits structured trace lines to stderr (`[debug] record N`, `[debug] LET X = ...`). This is adequate for interactive debugging but is not a logging framework. There are no log levels, no structured JSON output, no log rotation, and no way to enable partial tracing (e.g., "trace only LET assignments").

`ERR`/`ERL` functions expose last-error state to scripts — this is runtime introspection, not observability infrastructure. No metrics, no histogram of record processing times, no memory usage reporting.

| Capability | Present | Quality |
|---|---|---|
| Debug tracing | Yes (`--debug`) | 6/10 — useful but not configurable |
| Error state introspection | Yes (`ERR()`/`ERL()`) | 7/10 |
| Performance profiling | No | — |
| Structured logging | No | — |
| Metrics | No | — |

### 7.2 Deployment & Configuration

Configuration is externalized correctly — CLI flags control all runtime behaviour, no hardcoded paths, no config files required. The `OPTIONS` command provides runtime reconfiguration. Multi-platform packaging (RPM, DEB, Slackware, macOS, Windows MSI) is mature and version-coordinated via `scripts/bump-version.sh` — the tooling here is better than most projects four times this size.

**Missing:** No CI/CD pipeline. No GitHub Actions, no automated build verification on push, no automated test execution on PR. Every release depends entirely on the developer running `make check` manually.

| Capability | Score |
|---|---|
| Config externalization | 9/10 |
| Packaging breadth | 9/10 |
| Deployment automation | 3/10 (manual only) |
| CI/CD | 0/10 |
| Rollback | 8/10 (git tags, versioned packages) |

---

## 8. Documentation — 76/100

`README.md` is substantive: build requirements, feature overview, example usage. The man page (`man/man1/sdata.1`, 795 lines) is comprehensive and current — it covers every command and option. `HELP /ALL` from the interpreter produces a complete command and function reference that matches the man page. `doc/SKEPTIC_REVIEW.md` is a rare and valuable asset: a living architectural audit document where findings are marked resolved with commit hashes as they are addressed.

**Gaps:**

- ~~No architecture decision records (ADRs). The three-tier execution model, the PDV reset semantics, the SQLite spill threshold, and the LAG/NEXT group-boundary semantics are documented in code comments and the SKEPTIC_REVIEW but not in a durable design document.~~ **[Resolved 2026-05-05]** `doc/adrs.ods` contains 30 decisions (ADR-001–030) covering language choice, execution model, table design, CLI conventions, test strategy, and per-session architectural calls. A navigation pointer was added to `doc/architecture.md`.
- No algorithm documentation for statistical distributions. The Halley's-method Lambert W implementation in `Handle_Ltw`, the normal CDF algorithm in `SData.Statistics`, and the iterative IDF implementations have no references to the numerical methods literature they implement.
- Setup time from docs: ~15 minutes for an Ada/Alire developer; much longer for anyone unfamiliar with the toolchain, as the Alire workflow is not clearly documented for first-timers.

| Dimension | Score |
|---|---|
| README quality | 8/10 |
| Man page | 9/10 |
| In-system help | 9/10 |
| Architectural docs | ~~5/10~~ **8/10** |
| Algorithm references | 3/10 |
| Setup guide clarity | 6/10 |

---

## Overall Scores

| Category | Score |
|---|---|
| Architectural Integrity | 65/100 |
| Code Quality & Craftsmanship | 72/100 |
| Efficiency & Performance | 74/100 |
| Maintainability & Evolvability | 60/100 |
| Error Handling & Resilience | 58/100 |
| Security Posture | ~~52/100~~ ~~58/100~~ ~~63/100~~ **65/100** |
| Operational Readiness | 50/100 |
| Documentation | ~~76/100~~ **82/100** |
| **TOTAL** | ~~507/800 (63.4%)~~ ~~513/800 (64.1%)~~ ~~519/800 (64.9%)~~ ~~524/800 (65.5%)~~ **526/800 (65.8%)** |

---

## Prioritized Remediation

| Priority | Action | Category | Effort | Risk if Deferred |
|---|---|---|---|---|
| 1 | Replace `when others => return False` in `sdata-csv.adb` with specific handlers | Security/Error | 2 hours | Masks CSV format bugs silently |
| 2 | ~~Quote column names in SQLite DDL/DML; audit for injection~~ | Security | ~~4 hours~~ | ~~SQL injection via CSV headers~~ **Fixed 456d1e0** |
| 3 | Decompose `Parse_CSV` into tokenizer + type-inference passes | Code Quality | 2–3 days | Grows worse with each format quirk added |
| 4 | Change `Program_Error` → `Script_Error` in `Parse_ODF` | Error Handling | 30 min | Falls through `-k` handling silently |
| 5 | Add CI/CD (GitHub Actions: `make check` on push) | Operational | 4 hours | Test regressions invisible until manual run |
| 6 | Add unit tests for evaluator, table, and BY-group logic | Maintainability | 2–3 days | Silent path failures (the Set_Index_Map bug pattern) |
| 7 | ~~Add path traversal check in `Full_Path`~~ | Security | ~~2 hours~~ | ~~SUBMIT can escape working directory~~ **`--nosubmit` added 6909f15; won't-fix by default** |
| 8 | Document numerical algorithm references in `SData.Statistics` | Documentation | 4 hours | Next maintainer reimplements rather than verifies |

---

## The Hard Truth

This codebase is the work of someone who actually knows what they're doing. The domain model is correct, the Ada is idiomatic, the help system is unusually thorough, and the version-management and packaging tooling is better than most open-source projects ten times its size. The SKEPTIC_REVIEW discipline — maintaining a living audit document and marking findings resolved with commit hashes — is a practice most professional teams don't have.

But here's what I'd be thinking at 3 AM with a corrupted dataset:

**`sdata-file_io.adb` is a trap.** Three procedures totalling over 1,000 lines, each mixing tokenization, type inference, and data loading in a single call stack, each with broad `when others` handlers that silently absorb exceptions. When CSV parsing fails on a malformed file, the error that surfaces may bear no relationship to the actual failure point. `Parse_CSV` has been accumulating edge cases for years and it shows. This is the part of the codebase I would not touch without full test coverage written first — and that coverage does not exist.

**The security posture is "trust the user completely."** SYSTEM executes arbitrary shell commands. SUBMIT can reference arbitrary paths. Column names from CSV headers go into SQL strings unquoted. For a personal analysis tool on a trusted machine, this is fine. For anything in a shared pipeline or invoked on untrusted data, it is not. The `--noshell` flag helps, but it is opt-in and not the default, which means the safe mode requires explicit action.

The codebase scores **63%** — solidly competent, clearly improving (the SKEPTIC_REVIEW trajectory is positive), but not yet the kind of code you hand to a new contributor and say "go find the CSV parsing bug." The file I/O layer is the debt that earns the most interest.

---

## Appendix: Evidence Log

| Finding | File:Line | Evidence |
|---|---|---|
| Parse_CSV is 392 lines | `sdata-file_io.adb:286–677` | Single procedure, multiple concerns |
| Parse_OOXML is 369 lines | `sdata-file_io.adb:1103–1471` | Single procedure |
| Parse_ODF raises Program_Error | `sdata-file_io.adb:1093–1096` | Wrong exception type for user-visible error |
| Silent exception swallow | `sdata-csv.adb:42–45` | `when others => return False` twice |
| Column-name SQL construction | `sdata-table.adb` | ~~DDL built from user-controlled column names~~ **Fixed 456d1e0 — Sql_Id helper escapes `]`→`]]`** |
| SYSTEM shell injection surface | `sdata-system.adb:68–95` | ~~Unquoted string passed to `/bin/sh -c`~~ **Deliberate design; same trust model as R/SAS/Python; won't-fix** |
| No CI pipeline | `.github/` absent | No automated build/test on push |
| BY-variable list duplication | `sdata-interpreter.adb:59`, `sdata-table.adb:53` | Two independent copies of the same vector |
| 1 unit test module | `tests/csv_unit_test.adb` | No evaluator/table/interpreter unit tests |
| Execute_Assignment 135 lines | `sdata-interpreter.adb:659–793` | Multiple assignment concerns in one body |
