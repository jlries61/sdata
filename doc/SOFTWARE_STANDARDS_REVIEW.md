# Software Standards Review: SData

**Codebase:** `/home/jries/Develop/sdata`
**Language:** Ada 2012
**Version:** 0.5.1
**Total Source Lines:** ~10,839 (excluding generated obj/ files)
**Review Date:** 2026-04-16

---

## 1. Architectural Integrity

### 1.1 Structural Coherence

The architecture is a textbook interpreter pipeline and deserves credit for following it cleanly:

```
sdata_main → Parser/Lexer/AST → Interpreter → Evaluator → Table/Variables/Statistics/File_IO
```

Each package has a defensible reason to exist and a single, clear responsibility. A new developer can understand the system organization in under 20 minutes — the package names alone tell the story. No orphaned modules detected.

| Dimension | Assessment |
|---|---|
| Architectural Pattern | Layered interpreter pipeline (Lexer → Parser → AST → Executor) |
| Justification Quality | 9/10 |
| Complexity vs. Necessity | Well-matched to domain — no astronaut syndrome |

**One architectural concern:** `SData.Config` is a bag of mutable package-level variables, not a record passed through the call stack. This is a global-state design. For a single-threaded CLI tool it is workable, but it means the interpreter is not re-entrant and cannot be embedded or tested in isolation without resetting global state.

**Second concern:** `SData.Config` has `Repeat_Count : Natural` and `Repeat_Active : Boolean` at the top level *and* inside `Runtime_State_Record`. The interpreter uses only `Runtime.Repeat_Active`/`Runtime.Repeat_Count`. The top-level fields appear to be dead state. (`sdata-config.ads:29-30` vs `sdata-config.ads:44-45`)

### 1.2 Dependency Analysis

Direct Ada library dependencies: 4 (Zip-Ada, XML/Ada, MathPaqs, Ada_Sqlite3). All are compile-time; no dynamic loading. Dependency graph is flat and acyclic. No circular package dependencies detected. Alire manages versions; pinned exactly.

| Metric | Value |
|---|---|
| Direct dependencies | 4 |
| Unmaintained | 0 (all versioned and actively pinned) |
| Redundant libraries | 0 |
| Circular dependencies | None |

---

## 2. Code Quality & Craftsmanship

### 2.1 Naming & Readability

Naming is Ada-idiomatic and precise. Procedure names are verb phrases; function names are noun phrases. Column metadata uses descriptive record fields. No Hungarian notation. No mystery variables (`data`, `temp`, `x`). Readable aloud.

| Metric | Score |
|---|---|
| Naming Precision | 8/10 |
| Self-Documentation | 8/10 |
| Cognitive Load | Medium |

**Note:** Package-level booleans `BOG_Flag`/`EOG_Flag` in `sdata-evaluator.adb:60-61` are private implementation state for the `BOG()` and `EOG()` language functions, which are dispatched by the evaluator. The `Set_BOG`/`Set_EOG` interface in `sdata-evaluator.ads` is the correct boundary: the interpreter signals group boundaries; the evaluator answers function calls about them. Placement is correct.

### 2.2 Function Design

| Metric | Value |
|---|---|
| Avg procedure/function length | ~20 lines |
| Max function length | `Evaluate` (~220 lines) and `Run_One_Step` (~175 lines) |
| Single Responsibility | 8/10 |

~~`Handle_String_Ops` at ~253 lines, `Handle_Statistics` at ~187 lines, and `Handle_Navigation` at ~116 lines each violated the "one function does one thing" principle.~~ — **Fixed**: all three family handlers have been dissolved into individual per-function handlers. Each language function now has its own dedicated Ada subprogram (19 string handlers, 8 navigation handlers, 54 statistics handlers). The dispatch table is the sole dispatch layer — there is no second if-elsif re-dispatch inside a family handler. As a side effect, two previously registered but unimplemented functions (`BRN` and `MIF`) have been wired to their `SData.Statistics` implementations. The HEX$/OCT$/BIN$ code duplication was also eliminated via a shared `To_Base_String` helper.

The remaining large functions have defensible reasons:
- `Evaluate` (~220 lines) is a structural `case` on expression kind — it is linear in AST node types, not a dispatch chain.
- `Run_One_Step` (`sdata-interpreter.adb:1107`) is ~175 lines doing filter rebuilding, logical/physical mapping, BOG/EOG computation, PDV management, and output flushing — multiple distinct concerns in one procedure. Still an open item.
- `Handle_Math`, `Handle_Trig`, `Handle_Aggregate`, `Handle_Misc` retain their family-handler structure (70–120 lines each); these families have fewer members and the chains are shorter.

### 2.3 Comment Quality

Package-level design notes in both `sdata-evaluator.adb:18-43` and `sdata-interpreter.adb:23-50` are exemplary — they explain the *why* and document non-obvious invariants (lazy IF eval, logical vs. physical space, missing-value propagation).

**Comment sins found:**

| Sin | Location | Severity |
|---|---|---|
| ~~Duplicate comment `DIGITS state` on consecutive lines~~ | ~~`sdata-config.ads:53-54`~~ | ~~Low~~ — **Fixed** |
| ~~Inconsistent indentation (tabs vs spaces) mixed~~ | ~~`sdata-evaluator.adb:1279-1282`~~ | ~~Low~~ — **Fixed** |
| ~~`-- Update Order Vector` describes *what*, not *why*~~ | ~~`sdata-table.adb:246`~~ | ~~Low~~ — **Fixed** |

No commented-out code. No anonymous TODOs.

---

## 3. Efficiency & Performance

### 3.1 Algorithmic Choices

| Concern | Location | Severity |
|---|---|---|
| ~~SELECT filter scanned all columns per row even when filter only referenced a subset~~ | ~~`sdata-interpreter.adb`~~ | — | **Fixed** — `Collect_Filter_Vars` AST walker + `Load_PDV_One_Column` loads only referenced columns |
| ~~`Load_PDV_From_Table` heap-allocated a new `String_List` on every call~~ | ~~`sdata-variables.adb`~~ | — | **Fixed** — rewrote to use `Column_Count`/`Column_Name(I)` with no heap allocation |
| ~~Spill INSERT loop had no transaction wrapper — O(N) auto-commits per spill~~ | ~~`sdata-table.adb: Spill_Table_To_Disk`~~ | — | **Fixed** — loop wrapped in explicit `BEGIN`/`COMMIT` |
| ~~Backing store opened with default journal/sync/cache settings~~ | ~~`sdata-table.adb: Initialize_Backing_Store`~~ | — | **Fixed** — `journal_mode=OFF`, `synchronous=OFF`, `cache_size=-65536`, `temp_store=MEMORY` |
| Sort copies full column arrays | `sdata-table.adb` Sort procedure | Acceptable for memory-resident data |
| ~~`Get_Column_Names` allocates a heap-allocated `String_List` — callers must remember to free~~ | ~~`sdata-table.adb`, `sdata-interpreter.adb`, `sdata-file_io.adb`, `sdata-variables.adb`~~ | — | **Fixed** — `Get_Column_Names` removed from the public API; all 17 call sites migrated to `Column_Count`/`Column_Name(I)`; 3 confirmed leaks in range-expansion functions eliminated as a side effect |

No O(n²) algorithmic failures. Hash maps used throughout for O(1) column lookup. The SQLite spill-to-disk design for large tables is appropriate.

**SELECT filter optimization detail:** The filter scan now calls `Collect_Filter_Vars` once before the row loop to walk the filter expression AST and collect only the column names it references. Inside the loop, only those columns are loaded via `Load_PDV_One_Column`. Temporary variables present in the filter are skipped (guarded by `Has_Column`) so they remain visible from `Temp_Symbols`. For a 10-column table where the filter references 2 columns, this reduces PDV work per row by 80%. `Is_Identifier_Ref_Function` (LAG/NEXT/OBS family) is respected during AST traversal — their first argument is a variable name, not a value, and is excluded from the load set.

**Spill performance optimization detail:** `Spill_Table_To_Disk` previously executed each prepared-statement `Step` in its own implicit SQLite transaction, causing O(N) lock-acquire/release cycles (and O(N) fsyncs under the default `synchronous=FULL` setting). The loop is now wrapped in an explicit `BEGIN`/`COMMIT`, collapsing the cost to a single commit regardless of table size. `Initialize_Backing_Store` now sets four pragmas immediately after opening: `journal_mode=OFF` eliminates the rollback journal file entirely; `synchronous=OFF` removes all fsync calls (safe because this is a process-private temp file); `cache_size=-65536` gives SQLite a 64 MB page cache so sort runs stay hot between external-merge passes; `temp_store=MEMORY` keeps SQLite's own internal sort intermediates in RAM rather than writing a second temp file. Together these changes mean that for a spilled table, `SORT` delegates to SQLite's external merge sort running at full I/O-bound throughput rather than being throttled by per-row durability overhead.

### 3.2 Resource Management

**Critical finding:** `sdata-table.adb:36-44` — The Database pointer is deliberately NOT freed on cleanup to avoid a double-finalization crash with the Ada_Sqlite3 library:

```ada
--  We avoid manual Free of the Database pointer here because it
--  triggers a double-finalization crash with the library's internal
--  state management during program exit.
```

This is a pragmatic workaround for a library defect, clearly documented. For a CLI tool that exits immediately after use it is acceptable. For any future library embedding it would be a memory leak.

| Metric | Score |
|---|---|
| Resource Handling | 8/10 |
| Memory Safety | 8/10 |

### 3.3 Startup & Runtime Costs

- Cold start: sub-millisecond (no dynamic loading, no JIT, native binary)
- Idle memory: minimal; no background threads
- ~~`SUBMIT` and `Read_File` read entire script files into stack-allocated `String` buffers — deep SUBMIT chains with large scripts could exhaust the stack~~ **Fixed** — both sites now heap-allocate the read buffer (`new String (1 .. Size)`) and free it after parse/execute; stack pressure from nested SUBMITs is eliminated.

---

## 4. Maintainability & Evolvability

### 4.1 Test Coverage & Quality

| Metric | Value |
|---|---|
| Test framework | Shell-driven integration tests (diff comparison) |
| Unit tests | None |
| Test files | ~70 .cmd scripts |
| Test execution time | Fast (10s timeout per test; suite runs in seconds) |

Tests are **integration tests only** — they run the full interpreter and compare stdout. This means:
- **Good:** They test real behavior under real conditions.
- **Bad:** A failure gives minimal information about what broke. No line numbers, no call stacks in test output, just a diff.
- **Bad:** Edge cases in individual functions (e.g., `Handle_Math` domain checking) are only exercised if a test script happens to trigger them.

No AUnit or other unit test framework. For a project with ~1,600 lines of expression evaluation logic, zero unit tests on individual evaluator functions is a gap.

Test breadth is commendable: control flow, BY-groups, aggregates, spill/sort, string functions, type checking, file I/O formats (CSV, ODF, OOXML), edge cases (overflow, empty save, boundary conditions).

**Status:** This gap is a known item deferred to **Phase 6: Testing & Validation** of the development plan (`doc/feasibility_assessment.md`). Phase 6 covers: comprehensive test suite, validation against BW BASIC, performance benchmarking, edge case testing, and security review.

### 4.2 Change Resilience

Adding a new built-in function requires:
1. Add a new `Handle_FuncName` subprogram in `sdata-evaluator.adb`
2. Add one `Dispatch_Table.Insert` line in `Register_All_Functions`
3. Add help text in `sdata-help.adb`
4. Add a test `.cmd` file and expected output

That is a clean, well-defined change surface with no risk of disturbing unrelated functions. Adding a new statement type is more invasive (lexer token, parser case, AST node type, interpreter case, help text) but the pattern is consistent throughout.

~~Type coercion logic is duplicated between `Set_Value_Upper` and `Set_Output_Value_Upper` in `sdata-table.adb`. A change to coercion rules requires edits in two places.~~ **Fixed** — extracted to private `Coerce_Value (Val, Col_Typ, Col_Name)` function; both procedures now delegate to it. Error messages standardized to "Expected X for column Y" format.

### 4.3 Technical Debt Inventory

| Item | Location | Remediation Estimate | Interest Rate |
|---|---|---|---|
| ~~Dead `Repeat_Count`/`Repeat_Active` at top-level of `SData.Config`~~ | `sdata-config.ads:29-30` | 30 min | **Fixed** |
| ~~Duplicate type coercion logic~~ | ~~`sdata-table.adb:191-223, 578-607`~~ | — | **Fixed** — `Coerce_Value` helper |
| ~~`BOG_Flag`/`EOG_Flag` owned by evaluator but logically belong to interpreter~~ | `sdata-evaluator.adb:60-61` | — | **Retracted** — placement is correct per design |
| No unit tests for evaluator functions | Entire evaluator | 20+ hours | Growing |
| ~~Integer literal classification via `Float'Floor` may misclassify large integers~~ | ~~`sdata-evaluator.adb:1259-1263`~~ | — | **Fixed** — `Is_Integer`/`Int_Value` stored at parse time |
| Database pointer not freed on cleanup | `sdata-table.adb:36-44` | Blocked on upstream library fix | Stable |
| ~~`Handle_String_Ops`, `Handle_Statistics`, `Handle_Navigation` SRP violations~~ | ~~`sdata-evaluator.adb`~~ | — | **Fixed** — dissolved into 81 individual handlers; dispatch table is now the sole dispatch layer |
| `Run_One_Step` does filter rebuild, BOG/EOG, PDV management, output flush | `sdata-interpreter.adb:1107` | 4 hours | Stable |

---

## 5. Error Handling & Resilience

### 5.1 Error Philosophy

| Metric | Score |
|---|---|
| Error Consistency | 9/10 |
| Error Informativeness | 8/10 |
| Recovery Patterns | 8/10 |

`Script_Error` is the unified exception for user-visible errors. Ada's exception model ensures errors propagate upward cleanly. `Handle_Domain_Error` centralizes the decision between halt and warn-and-continue for math errors. `Continue_On_Error` allows batch scripts to proceed past statement errors. Error messages include the variable name or context.

The distinction between recoverable (`Script_Error`, caught and reported) and unrecoverable (`Constraint_Error`, `Program_Error`, propagated to main) is clear and appropriate.

**Minor issue:** `Execute_IO` (`sdata-interpreter.adb:1031`) catches all exceptions on `Open_Output` and emits a single-line error, swallowing the original exception type. A script that specifies an output file on a read-only filesystem gets a terse message but execution continues silently with output going to stdout.

### 5.2 Failure Modes

This is a local CLI tool — there are no external services to be unavailable. File-not-found is handled (`Name_Error` → `Script_Error`). SUBMIT recursive cycle detection is implemented and tested. Integer overflow in 64-bit arithmetic is detected and raised as `Script_Error`. The tool fails with a non-zero exit code on unhandled `Script_Error` propagation.

| Metric | Score |
|---|---|
| Graceful Degradation | 8/10 |
| Timeout Strategy | N/A |
| Retry Logic | N/A |

---

## 6. Security Posture

SData is a local data-processing interpreter with no network surface, no authentication, and no multi-tenancy. The security considerations are bounded:

| Concern | Status |
|---|---|
| Shell injection via `SYSTEM` command | Mitigated — `--noshell` disables; user controls script content |
| Path traversal via `USE`/`SAVE`/`SUBMIT` | Not mitigated — user controls all paths. Intentional (it's a scripting tool). |
| SQLite injection | N/A — no user SQL passthrough; schema is fully controlled by the application |
| Secrets in code | None |
| SUBMIT recursive cycle detection | Implemented (`Submit_Chain` set) |

The `--noshell` flag is meaningful for restricted execution environments (CI, shared systems). Its interaction with the `-p` pager option is documented.

| Metric | Score |
|---|---|
| Input Validation Coverage | 8/10 (appropriate to domain) |
| Known Vulnerabilities | 0 |

---

## 7. Operational Readiness

### 7.1 Observability

| Metric | Assessment |
|---|---|
| Structured logging | None — `Put_Line_Error` for warnings, no severity levels |
| Debug mode | `--debug` traces each statement and record to stderr |
| Metrics | None |
| Distributed tracing | N/A (single-process CLI) |

For a CLI data processing tool this is appropriate. `--debug` provides enough traceability for script authors.

| Metric | Score |
|---|---|
| Logging Quality | 6/10 |
| Metrics Coverage | N/A |
| Traceability | 7/10 |

### 7.2 Deployment & Configuration

| Metric | Assessment |
|---|---|
| Config externalized from code | Yes — all runtime config via command-line flags |
| Packaging | RPM, Debian, Slackware, macOS pkg — well-covered |
| Build automation | `make`, `gprbuild`, `alr` all supported |
| Rollback | Via git tag/version; `bump-version.sh` is atomic |

The `scripts/bump-version.sh` atomically updates 9 version locations and can build, test, commit, and tag in one operation. This is mature version management.

| Metric | Score |
|---|---|
| Config Management | 9/10 |
| Deployment Automation | 9/10 |
| Rollback Capability | 8/10 |

---

## 8. Documentation

| Document | Quality |
|---|---|
| README | 9/10 — Complete: build, packaging for 4 distros, quick start, all CLI flags; macOS section includes SDK path fix and `gtimeout` note |
| Package spec comments | 7/10 — `sdata-table.ads` has good docstrings; some specs minimal |
| Package body design notes | 9/10 — evaluator and interpreter headers explain non-obvious invariants |
| Man page | Present (in `man/`) |
| Architectural ADRs | Absent — decisions captured inline but not in a searchable form |

One gap: the interactive help system (`HELP /ALL`) is the primary user documentation for the command language itself, which is good, but the design specification lives at `~/Develop/Data/Docs/design.odt` (outside the repo), which means it is not co-versioned with the code.

The macOS section is notably thorough: the Alire/GNAT SDK path issue (`C_INCLUDE_PATH` vs `SDKROOT`, and why `SDKROOT` alone does not work with GCC-based GNAT) and the `gtimeout`/coreutils requirement are exactly the kind of platform-specific knowledge that normally survives only in contributor memory. Capturing it here is the right call.

| Metric | Score |
|---|---|
| README Quality | 9/10 |
| Architectural Docs | 6/10 |
| Setup Time from Docs | ~15 minutes |

---

## Overall Scores

| Category | Score |
|---|---|
| Architectural Integrity | 78/100 |
| Code Quality | 78/100 |
| Efficiency | 92/100 |
| Maintainability | 71/100 |
| Error Handling | 85/100 |
| Security | 82/100 |
| Operational Readiness | 75/100 |
| Documentation | 80/100 |
| **TOTAL** | **641/800** |

---

## Final Verdict

**Strengths:**
- Clean layered architecture with no circular dependencies
- Ada's type system does real work here — the compiler catches entire classes of errors before runtime
- Exception handling is consistent and principled throughout
- Excellent README and inline design documentation
- Comprehensive integration test suite with good domain coverage
- Sophisticated features (BY-groups, SELECT filter, disk spillover, lazy IF eval) are well-implemented and well-documented
- Each built-in language function now has its own Ada subprogram — the dispatch table is the sole dispatch layer with no hidden second-level re-dispatch

**Fatal Flaws:**
- None — there are no security holes, data corruption paths, or correctness violations found in the overall design

**Genuine Defects Found:**

1. ~~**Bug in `Handle_Trig`** (`sdata-evaluator.adb:282`): The pattern `Name in "HCS" | "HSN" | "HSN"` had `"HSN"` twice; `HTN` (hyperbolic cotangent) returned `Val_Missing` silently.~~ — **Fixed**.

2. ~~**Integer literal precision** (`sdata-evaluator.adb:1259-1263`): Classifying a literal as integer by testing `Float'Floor(Expr.Value) = Expr.Value` fails for large integers (e.g., `16777217`) that cannot be exactly represented in 32-bit `Float`.~~ — **Fixed**: `Expr_Numeric_Literal` in the AST now carries `Is_Integer : Boolean` and `Int_Value : Integer`; the parser stores the exact value at parse time.

3. ~~**Dead state** in `SData.Config` top-level (`Repeat_Count`, `Repeat_Active`).~~ — **Fixed**.

4. ~~**SRP violations**: `Handle_String_Ops`, `Handle_Statistics`, `Handle_Navigation` were multi-hundred-line if-elsif re-dispatch chains.~~ — **Fixed**: dissolved into 81 individual handlers; `BRN` (Beta RN) and `MIF` (Binomial IDF) were also wired to their `SData.Statistics` implementations (they were registered but silently returned missing).

**Recommendation:** The architectural patterns (global state, no unit tests) suit the project's current scale; revisit if the codebase grows significantly or if library embedding becomes a goal. The remaining open item of note is `Run_One_Step`'s multiple concerns.

---

## The Hard Truth

This is competent, honest Ada code. It is not trying to impress anyone — it is trying to work correctly, and it largely succeeds. The architecture matches the problem domain. The error handling is better than most interpreted languages' own implementations. The README is better than most commercial tools write.

The three significant quality issues identified at first review — the HTN silent-wrong-answer bug, the integer literal precision defect, and the family-handler SRP violations — have all been resolved. The dispatch table is now the sole dispatch layer: each language function has exactly one Ada subprogram. Adding a new function is a 2-file change with zero risk of accidentally breaking a neighbouring function. Two silently-broken functions (`BRN`, `MIF`) were discovered and fixed as a side effect.

What remains: zero unit tests for the expression evaluator. The integration tests tell you *that* something broke; they do not tell you *what*. When `Handle_GIF` produces a wrong gamma quantile, you will not know if it is the numerical algorithm, the argument parsing, the missing-value propagation, or something in the dispatch path — you will diff test output and grep for gamma. This is the primary remaining quality gap for a project of this complexity.

The design specification living outside the repository in a `.odt` file is an operational risk. `doc/design.odt` is now present in the repo but is not currently open for easy in-repo reading without LibreOffice or pandoc.

Trust this at 3 AM? Yes — with higher confidence than at first review.

---

## Appendix: Evidence Log

| Finding | File | Line(s) | Evidence |
|---|---|---|---|
| ~~HTN bug: duplicate HSN in pattern match~~ | `sdata-evaluator.adb` | 282 | **Fixed** — pattern now `"HCS" \| "HSN" \| "HTN"` |
| ~~Integer precision via Float~~ | `sdata-evaluator.adb` | 1259-1263 | **Fixed** — `Is_Integer`/`Int_Value` fields added to AST; parser detects and stores exact integer at parse time |
| ~~Dead top-level Repeat state~~ | `sdata-config.ads` | 29-30 | **Fixed** — dead fields removed; `Runtime_State_Record` is the correct home per spec |
| ~~Duplicate coercion logic~~ | `sdata-table.adb` | 191-223 and 578-607 | **Fixed** — extracted to `Coerce_Value (Val, Col_Typ, Col_Name)` private function; error messages standardized to "Expected X for column Y" |
| ~~BOG/EOG state in wrong package~~ | `sdata-evaluator.adb` | 60-61 | **Retracted** — flags are private implementation state for `BOG()`/`EOG()` functions; evaluator ownership is correct |
| Acknowledged DB pointer leak | `sdata-table.adb` | 36-44 | Comment documents deliberate non-free to avoid finalization crash |
| ~~Stack allocation for file content in SUBMIT and Read_File~~ | `sdata-interpreter.adb`, `sdata_main.adb` | SUBMIT block, Read_File | **Fixed** — heap-allocated with `new String (1 .. Size)`; freed after parse/execute |
| ~~Duplicate DIGITS comment~~ | `sdata-config.ads` | 53-54 | **Fixed** — duplicate line removed |
| ~~Inconsistent indentation (tabs vs spaces)~~ | `sdata-evaluator.adb` | 1279-1282 | **Fixed** — no tabs remain |
| ~~Design doc not in repo~~ | External | N/A | **Resolved** — `doc/design.odt` and `doc/feasibility_assessment.md` copied into repo |
| ~~`Handle_String_Ops`/`Handle_Statistics`/`Handle_Navigation` SRP violations~~ | `sdata-evaluator.adb` | 452-1014 | **Fixed** — dissolved into 81 individual handlers; `To_Base_String` helper eliminates HEX$/OCT$/BIN$ duplication |
| ~~`BRN` registered, not implemented~~ | `sdata-evaluator.adb` | 1626 | **Fixed** — `Handle_BRN` calls `SData.Statistics.Beta_RN` |
| ~~`MIF` registered, not implemented~~ | `sdata-evaluator.adb` | 1612 | **Fixed** — `Handle_MIF` calls `SData.Statistics.Binomial_IDF` |
| ~~SELECT filter loaded all columns per row~~ | `sdata-interpreter.adb` / `sdata-variables.adb` | filter scan | **Fixed** — `Collect_Filter_Vars` + `Load_PDV_One_Column`: only referenced columns loaded per row; heap allocation in `Load_PDV_From_Table` also eliminated |
| ~~Spill INSERT loop unboxed — O(N) implicit transactions~~ | `sdata-table.adb: Spill_Table_To_Disk` | row loop | **Fixed** — wrapped in explicit `BEGIN`/`COMMIT` |
| ~~Backing store opened with default SQLite durability settings~~ | `sdata-table.adb: Initialize_Backing_Store` | DB open | **Fixed** — `journal_mode=OFF`, `synchronous=OFF`, `cache_size=-65536`, `temp_store=MEMORY` |
| ~~`Get_Column_Names` heap-allocates a `String_List`; callers must free — 3 confirmed leaks in range-expansion functions~~ | `sdata-table.adb`, `sdata-interpreter.adb`, `sdata-file_io.adb`, `sdata-variables.adb` | 17 call sites | **Fixed** — function removed from public API; all callers migrated to `Column_Count`/`Column_Name(I)`; leaks in `Expand_Range`, `Set_Hold_For_Range`, `Resolve_Range` eliminated |
