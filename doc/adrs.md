# Architecture Decision Records

Each entry records a significant design choice: the context that forced a decision,
the decision itself, and its consequences. Consult before proposing structural changes
that might relitigate a settled question.

---

## Summary

| # | Title | Date | Status |
|---|---|---|---|
| ADR-001 | Choose Ada 2012 as implementation language | 2026-02-16 | Accepted |
| ADR-002 | Use a hand-written recursive-descent parser | 2026-02-16 | Accepted |
| ADR-003 | Use a three-tier execution model (Declarative / Immediate / Deferred) | 2026-02-27 | Accepted |
| ADR-004 | Use SQLite as the spillover backing store for large tables | 2026-02-27 | Accepted |
| ADR-005 | Apply SQLite performance pragmas and batch INSERT transactions for spillover | 2026-04-17 | Accepted |
| ADR-006 | Maintain an explicit Output_Column_Order vector for NAMES / SAVE ordering | 2026-02-17 | Accepted |
| ADR-007 | Use file-based diff as the primary test harness | 2026-02-20 | Accepted |
| ADR-008 | Use Alire for Ada dependency management | 2026-03-05 | Accepted |
| ADR-009 | Parse ODS and OOXML natively using XML/Ada rather than calling ssconvert or LibreOffice for reading | 2026-03-02 | Accepted |
| ADR-010 | Use GNAT.OS_Lib.Spawn for SYSTEM command execution | 2026-03-17 | Accepted |
| ADR-011 | Use LET for permanent variables and SET for temporary variables with strict cross-assignment enforcement | 2026-02-27 | Accepted |
| ADR-012 | Add GitHub Actions CI workflow with Alire integration | 2026-04-10 | Accepted |
| ADR-013 | Split SData.Config into static constants and SData.Config.Runtime for mutable run state | 2026-04-17 | Accepted |
| ADR-014 | Pre-resolve variable names to column indices before the data step loop | 2026-04-17 | Accepted |
| ADR-015 | Implement a segment-prefetch cache for SQLite spillover reads | 2026-04-17 | Accepted |
| ADR-016 | Rename LIST to DISPLAY for table viewing; LIST becomes program-buffer only | 2026-04-18 | Accepted |
| ADR-017 | Extract SData.CSV as a pure satellite package for CSV string helpers | 2026-05-01 | Accepted |
| ADR-018 | Add a CI Verify binaries step to guard against missing executables | 2026-05-02 | Accepted |
| ADR-019 | Drop orphaned columns immediately on DIM resize rather than deferred garbage collection | 2026-05-02 | Accepted |
| ADR-020 | Raise Incomplete_Statement on SELECT at EOF to fix interactive REPL SELECT CASE parsing | 2026-05-01 | Accepted |
| ADR-021 | Use Interfaces.Integer_64 rather than Long_Integer for overflow detection | 2026-05-01 | Accepted |
| ADR-022 | Prefer bash/sh over cmd.exe for SYSTEM and SHELL on Windows | 2026-05-01 | Accepted |
| ADR-023 | Use NAMES after RUN for array resize test verification rather than SAVE-based file comparison | 2026-05-02 | Accepted |
| ADR-024 | Implement a data-driven HELP dispatcher rather than a large if-elsif chain | 2026-03-04 | Accepted |
| ADR-025 | Install signal handlers for SIGTERM/SIGINT to clean up SQLite temp files | 2026-04-17 | Accepted |
| ADR-026 | Call LibreOffice subprocess for formula evaluation; fall back to cached values | 2026-03-02 | Accepted |
| ADR-027 | Adopt RPM-first packaging with a bump-version script covering all tracked locations | 2026-03-05 | Accepted |
| ADR-028 | Use SELECT /ALL and bare BY for state cancellation rather than new keywords | 2026-04-10 | Accepted |
| ADR-029 | Implement BREAK / BREAK WHEN as deferred debug statements with a mini-REPL | 2026-04-30 | Accepted |
| ADR-030 | Use relative paths in options_test for cross-platform portability | 2026-05-01 | Accepted |
| ADR-031 | Keep SYSTEM/SHELL enabled by default; mark sandboxing/allowlist/escaping as won't-fix | 2026-05-06 | Accepted |
| ADR-032 | Add --nosubmit flag to disable SUBMIT command | 2026-05-06 | Accepted |
| ADR-033 | Use a C stub for privilege detection rather than florist_blady | 2026-05-06 | Accepted |
| ADR-034 | Measure MAXINTAB / -m in cells (rows × columns), not rows | 2026-05-07 | Accepted |
| ADR-035 | Adopt IEEE 754 infinity as a first-class evaluator value | 2026-05-07 | Accepted |
| ADR-036 | Set MAXINTAB default to 50 000 000 cells with a static value rather than runtime memory detection | 2026-05-07 | Accepted |
| ADR-037 | Add configurable SYSTEM/SHELL timeout defaulting to 300 s in batch mode, unlimited in interactive | 2026-05-13 | Accepted |
| ADR-038 | Add VANDALIZE command for generating noisy variable copies | 2026-05-15 | Superseded |
| ADR-039 | Extract sdata-core as a shared Alire library | 2026-05-21 | Accepted |
| ADR-040 | sdata-core contains no lexer, AST, or parser | 2026-05-21 | Accepted |
| ADR-041 | Auto-detect subscripted columns as arrays at USE time; narrow DIM | 2026-05-21 | Accepted |
| ADR-042 | Add Execute_OUTPUT_Table as a parallel sdata-core entry point | 2026-05-21 | Accepted |
| ADR-043 | Per-application version constants | 2026-05-21 | Accepted |
| ADR-044 | USE/SAVE RENAME= applies the suffix-determines-type rule | 2026-06-06 | Accepted |
| ADR-045 | Promote the reserved-keyword USE warning to sdata-core; keep keyword lists per-consumer | 2026-06-20 | Accepted |
| ADR-046 | AGGREGATE command — active-BY grouping, build-and-swap, and an aggregate metadata side-table | 2026-06-23 | Accepted |
| ADR-047 | TRANSPOSE command — type-uniformity, union-of-IDs, max-K padding, and output-collision rules | 2026-06-25 | Accepted |
| ADR-048 | STATS command — transposed-AGGREGATE layout, always-replace + print/NOPRINT, shared group-scan helper | 2026-06-30 | Accepted |
| ADR-049 | TABLES command — print-only frequency/crosstabulation reporting | 2026-07-03 | Accepted |
| ADR-050 | SAVE /DECIMALS and round-trip float output | 2026-07-09 | Accepted |
| ADR-051 | Reject SORT/AGGREGATE/TRANSPOSE/STATS inside an active REPEAT block | 2026-07-30 | Superseded by ADR-055 |
| ADR-052 | Validate SORT/BY variable names unconditionally, not gated on Column_Count > 0 | 2026-07-30 | Accepted |
| ADR-053 | REPL test coverage via a Makefile `.repl` marker convention, not a Run_REPL refactor | 2026-08-03 | Accepted |
| ADR-054 | Resolve REPEAT/DELETE keyword overloading: rename the low-usage side (REPEAT/UNTIL loop -> DO/UNTIL; DELETE n[-m] line editor -> REMOVE n[-m]) | 2026-08-03 | Accepted |
| ADR-055 | Implicit RUN instead of rejecting SORT/AGGREGATE/TRANSPOSE/STATS with a pending program (supersedes ADR-051's reject mechanism) | 2026-08-03 | Accepted |
| ADR-056 | Declarative statement inside FOR/WHILE/DO-UNTIL: warn once per occurrence, don't reject | 2026-08-05 | Accepted |
| ADR-057 | `.i`/`-.i`/`.n` typed literals construct Infinity/NaN directly; NaN's existing "never survives arithmetic" policy is preserved, not relaxed | 2026-08-08 | Accepted |
| ADR-058 | SUBMIT inside a loop gets the same ADR-056 declarative-in-loop warning as inline use, deduplicated by submitted file path since SUBMIT re-parses fresh each call | 2026-08-24 | Accepted |
| ADR-059 | NOTE — an Immediate-tier counterpart to PRINT that unconditionally rejects permanent variables | 2026-08-29 | Accepted |
| ADR-060 | Parser errors raise Script_Error instead of printing and silently continuing | 2026-08-29 | Accepted |
| ADR-061 | `Run_REPL` echoes each input line unconditionally, closing design.md's "Statement Echo" gap | 2026-08-31 | Accepted |
| ADR-062 | Declarative/Immediate-tier expressions get the same unknown-function/arity checking as Deferred, by reusing `Check_Statement` — not by duplicating it | 2026-09-03 | Accepted |
| ADR-063 | NOTE's permanent-variable rejection checks the resolved array *element*, not the array's declared class | 2026-09-05 | Accepted |
| ADR-064 | Lexer `Token_Bad` sites raise Script_Error instead of printing and silently continuing | 2026-09-05 | Accepted |
| ADR-065 | Status/bookkeeping messages reach the OUTPUT-file transcript unconditionally, matching design.md sec6.1 | 2026-09-05 | Accepted |

---

## Decisions

### ADR-001: Choose Ada 2012 as implementation language
**Date:** 2026-02-16 | **Status:** Accepted

**Context:** The project is a statistical data language interpreter inspired by SAS/Systat BASIC. A compiled, strongly typed language was needed that could handle performance-sensitive data processing, rich type checking at compile time, and production-quality error handling without relying on a garbage collector.

**Decision:** Implement sdata in Ada 2012 using the GNAT toolchain. Ada's contract-based programming, tagged types, and built-in numeric overflow semantics map cleanly onto interpreter requirements.

**Consequences:** The codebase benefits from strong compile-time guarantees and GNAT's rich runtime checking, but the Ada ecosystem has limited mature libraries (especially for spreadsheets and statistics), requiring several components to be implemented from scratch.

---

### ADR-002: Use a hand-written recursive-descent parser
**Date:** 2026-02-16 | **Status:** Accepted

**Context:** The sdata scripting language is a BASIC dialect with case-insensitive keywords, line continuation, operator-precedence expressions, and multiple distinct statement forms. Parser generators for Ada are rare and their maturity was uncertain.

**Decision:** Implement a hand-written recursive-descent parser (with Pratt-style operator-precedence climbing for expressions) in SData.Parser / SData.Lexer.

**Consequences:** Complete control over grammar evolution, error messages, and special-case handling (e.g. SELECT disambiguation). The trade-off is more manual maintenance as the grammar grows, but the codebase is self-contained and the parser boundaries are well understood.

---

### ADR-003: Use a three-tier execution model (Declarative / Immediate / Deferred)
**Date:** 2026-02-27 | **Status:** Accepted

**Context:** SData's design requires a data step model where some commands configure upcoming execution (USE, BY, SELECT), some execute immediately (RUN, SORT, NAMES), and some execute once per record when RUN is reached (LET, PRINT, IF). A simple two-tier model would conflate the configuring and non-configuring immediate commands, making the RUN boundary ambiguous.

**Decision:** Implement three tiers explicitly: Declarative (configure state at parse time), Immediate (execute at once, non-configuring), and Deferred (queue until RUN triggers iteration over records). The Is_Immediate predicate in SData.Interpreter encodes tier membership.

**Consequences:** The data step boundary (RUN) is unambiguous and the execution model mirrors the SAS/BASIC inspiration. Adding a new statement requires consciously placing it in a tier, which acts as a design review gate.

---

### ADR-004: Use SQLite as the spillover backing store for large tables
**Date:** 2026-02-27 | **Status:** Accepted

**Context:** In-memory data tables are bounded by available RAM. Datasets larger than Max_Table_Rows need to spill to disk. Ada has no standard in-process persistent store; implementing a custom binary format would be substantial effort.

**Decision:** Use SQLite (via Ada_Sqlite3 bindings) as a process-private temporary backing store. When the table exceeds Max_Table_Rows, rows are flushed to a SQLite temp file. SORT delegates to SQLite ORDER BY; reads are batched at segment granularity.

**Consequences:** SQLite provides a correct, well-tested implementation of on-disk storage and ORDER BY for free. The trade-off is a ~1.5x overhead vs. in-memory (after the segment-prefetch optimization) and an external C library dependency. An early implementation had 101x overhead before the segment-prefetch and transaction-batch fixes.

---

### ADR-005: Apply SQLite performance pragmas and batch INSERT transactions for spillover
**Date:** 2026-04-17 | **Status:** Accepted

**Context:** The initial SQLite backing store treated each row INSERT as its own transaction and used default durability settings (journal + fsync). This produced 101x slowdown vs. in-memory for a 100K-row workload because the SQLite temp file is process-private and discarded on exit — durability guarantees were both unnecessary and expensive.

**Decision:** Set PRAGMA synchronous=OFF, PRAGMA journal_mode=OFF, and PRAGMA temp_store=MEMORY on the temp database at open time, and wrap each segment spill in a single BEGIN/COMMIT transaction rather than one transaction per row.

**Consequences:** Spillover overhead dropped from 101x to approximately 1.5x. The pragmas are safe because the file is never shared and is deleted on process exit or clean shutdown, so loss of durability has no correctness consequence.

---

### ADR-006: Maintain an explicit Output_Column_Order vector for NAMES / SAVE ordering
**Date:** 2026-02-17 | **Status:** Accepted

**Context:** SData.Table stores columns in an Ada.Containers.Indefinite_Maps hash map, which has non-deterministic iteration order. NAMES output and SAVE output must reflect the order in which columns were explicitly set (not hash order), and that order must survive RENAME operations.

**Decision:** Maintain a separate Column_Order vector (for input/current table) and Output_Column_Order vector (for the step's output table) alongside the hash map. All column operations keep both structures in sync. At step commit, Output_Column_Order replaces Column_Order.

**Consequences:** NAMES and SAVE output is deterministic and user-visible ordering is preserved. Linear scans of the order vector for RENAME and DROP are O(columns), which is negligible at typical widths but would be a bottleneck for very wide tables.

---

### ADR-007: Use file-based diff as the primary test harness
**Date:** 2026-02-20 | **Status:** Accepted

**Context:** An interpreter needs behavioral tests that verify end-to-end output for given script inputs. Ada unit-test frameworks existed but would require wiring the interpreter through an Ada API; scripted diff-based tests validate the full pipeline including the CLI and output formatting.

**Decision:** Implement a make check harness that runs each tests/*.cmd script through ./bin/sdata, captures stdout, and diffs it against tests/expected/<name>.out. Any difference is a test failure.

**Consequences:** Tests are easy to add (two files) and resilient to refactoring (they test behavior, not internals). Interactive features and pure unit-level logic are not directly testable this way; a separate csv_unit_test executable was later added for pure-function Ada unit tests.

---

### ADR-008: Use Alire for Ada dependency management
**Date:** 2026-03-05 | **Status:** Accepted

**Context:** The project depends on Zip-Ada, XML/Ada, MathPaqs, and Ada_Sqlite3. These libraries are not part of the GNAT standard distribution. A reproducible build mechanism was needed that could locate these libraries without hardcoding paths.

**Decision:** Use Alire (the Ada package manager) and declare all dependencies in alire.toml. alr build fetches and compiles all dependencies before calling gprbuild. CI uses setup-alire@v3 pinned to version 2.1.0 (which uses the stable-1.4.0 index where all required libraries are present).

**Consequences:** Reproducible builds across machines. The version pin (2.1.0) was necessary because 2.0.1 used an older community index lacking Zip-Ada. Alire adds ~60s to cold CI builds for dependency fetch.

---

### ADR-009: Parse ODS and OOXML natively using XML/Ada rather than calling ssconvert or LibreOffice for reading
**Date:** 2026-03-02 | **Status:** Accepted

**Context:** The initial design considered three options for spreadsheet I/O: LibreOffice UNO API bindings (complex), calling external tools like ssconvert/LibreOffice headless (external dependency, subprocess overhead), or direct XML parsing of the ODS/OOXML ZIP containers.

**Decision:** Implement native ODS and OOXML readers using Zip-Ada (to unzip the container) and XML/Ada (to parse the inner XML). For formula evaluation only, fall back to calling soffice --headless as a subprocess. Cached cell values are read directly without any external tool when LibreOffice is absent.

**Consequences:** Reading spreadsheets has no external tool dependency. Formula evaluation requires LibreOffice, but the fallback to cached values works correctly for files saved by any spreadsheet application after a full recalculation. ssconvert was considered as a lighter fallback but not implemented.

---

### ADR-010: Use GNAT.OS_Lib.Spawn for SYSTEM command execution
**Date:** 2026-03-17 | **Status:** Accepted

**Context:** The SYSTEM command allows scripts to invoke shell commands. Using system() from C or Ada's equivalent passes the command string to a shell, which introduces quoting and injection risks. GNAT provides Spawn which takes argv directly.

**Decision:** Implement SYSTEM via GNAT.OS_Lib.Spawn, passing the command as a single argument to /bin/sh -c (or bash/sh on Windows). The --noshell flag disables both SYSTEM and the SHELL() function entirely.

**Consequences:** The attack surface is limited to the user's own script — the tool does not amplify injection. On Windows, the POSIX shell detection was later refined to prefer bash/sh on PATH over cmd.exe because SHELL environment variable paths are Unix-style and unresolvable by the Windows loader.

---

### ADR-011: Use LET for permanent variables and SET for temporary variables with strict cross-assignment enforcement
**Date:** 2026-02-27 | **Status:** Accepted

**Context:** The design spec distinguishes between permanent variables (table columns, persisted across records) and temporary variables (reset to missing at each record unless HOLDed). The original implementation did not enforce which keyword could assign which type. The Stage 2 audit found this gap.

**Decision:** Enforce strict rules: LET may not modify individual elements of a temporary array; SET may not modify elements of a permanent or virtual array. A guard using Has_Array is checked before the modification rules to avoid misleading errors for undefined arrays.

**Consequences:** Scripts that incorrectly mix LET/SET semantics are caught at runtime with a clear error message. The enforcement required adding the Has_Array check after an early implementation produced misleading errors for undefined arrays.

---

### ADR-012: Add GitHub Actions CI workflow with Alire integration
**Date:** 2026-04-10 | **Status:** Accepted

**Context:** The project had no automated build and test verification. Regressions could only be caught by local make check runs. The project uses Alire, which means CI must set up the Alire environment before building.

**Decision:** Add .github/workflows/test.yml that uses setup-alire@v3 (pinned to version 2.1.0) to install Alire, runs alr build to compile, then alr exec -- make check to run the full test suite. A Verify binaries step was later added to guard against a missing csv_unit_test binary.

**Consequences:** Every push to main and every pull request is automatically built and tested on ubuntu-latest. Multi-platform CI (macOS, Windows) was deferred; the project targets Linux as primary platform.

---

### ADR-013: Split SData.Config into static constants and SData.Config.Runtime for mutable run state
**Date:** 2026-04-17 | **Status:** Accepted

**Context:** The initial SData.Config package mixed compile-time constants (default values, limits) with mutable run-state (current DIGITS setting, active flags). The codebase review identified this as a global-state substrate that made the interpreter non-re-entrant.

**Decision:** Extract mutable interpreter state into a child package SData.Config.Runtime. Static constants remain in SData.Config. This is explicitly scoped as a single-threaded CLI concern — full re-entrancy is not a goal for the current tool.

**Consequences:** The split clarifies which values are invariant and which change during execution. Non-re-entrancy remains but is now consciously documented. The remedy for embedding the interpreter in a multi-threaded context in the future is well-understood.

---

### ADR-014: Pre-resolve variable names to column indices before the data step loop
**Date:** 2026-04-17 | **Status:** Accepted

**Context:** The initial evaluator performed a hash-map lookup for every variable reference on every record during RUN. With a 100K-row dataset and a LET statement, this was ~30 us/row — the dominant cost. Column indices are stable within a single data step.

**Decision:** Before the data step loop begins, resolve all variable references in the deferred statement list to their column indices. Per-row evaluation uses the cached indices directly rather than re-hashing each name on every record.

**Consequences:** Per-row overhead dropped from ~30 us to ~6 us (5x reduction). In-memory 100K-row workload improved from 3.0s to 1.9s user time. Spillover performance maintained at ~1.5x in-memory.

---

### ADR-015: Implement a segment-prefetch cache for SQLite spillover reads
**Date:** 2026-04-17 | **Status:** Accepted

**Context:** The original spillover read path used a one-row cached-row cache: each miss triggered an individual SELECT WHERE record_id = N query. At 100K rows with ~10K spilled, this was ~10,000 round-trips to SQLite — responsible for 101x slowdown vs. in-memory.

**Decision:** Replace the one-row cache with a segment-level prefetch: when a row is not in the in-memory window, fetch the entire segment (size = Max_Table_Rows) in one SQL query. Row-level access within the segment is then in-memory.

**Consequences:** Spillover penalty dropped from 101x to ~1.5x. The remaining gap is expected overhead from the segment loads and output spills for the benchmark workload.

---

### ADR-016: Rename LIST to DISPLAY for table viewing; LIST becomes program-buffer only
**Date:** 2026-04-18 | **Status:** Accepted

**Context:** The LIST command was being used for two purposes: showing the queued program buffer (BW BASIC convention) and showing the data table contents. When Phase 5 added program-buffer LIST, the dual use became ambiguous.

**Decision:** Introduce DISPLAY [varlist] as the dedicated command for viewing table data. LIST is reserved exclusively for showing the numbered program buffer entries (or an empty buffer notice). Alternatives considered: SHOW (vaguer), DUMP (sounds destructive), VIEW (implies read-only browsing).

**Consequences:** All existing tests using LIST X were updated to DISPLAY X. The semantics are now unambiguous and consistent with the BW BASIC convention for LIST.

---

### ADR-017: Extract SData.CSV as a pure satellite package for CSV string helpers
**Date:** 2026-05-01 | **Status:** Accepted

**Context:** Parse_CSV in sdata-file_io.adb grew to 553 lines, containing six algorithmic string helpers (Try_Fast_Float, Is_Numeric_Field, At_Delimiter, CSV_Field_End, CSV_Unquote, Split_Indices) alongside orchestration logic. These pure helpers had no dependencies on table or file state but were impossible to unit test in isolation while nested inside Parse_CSV.

**Decision:** Extract the six pure helpers into a new SData.CSV package with no dependencies on any other SData package. Add a standalone csv_unit_test executable with 33 Ada unit tests covering all six functions. Helpers with legitimate closure dependencies on Parse_CSV local state remain nested.

**Consequences:** Parse_CSV was reduced from 553 to ~377 lines and became a clean orchestrator. The 33 compiled Ada unit tests catch type errors and contract violations invisible to the file-diff harness. SData.CSV added as a zero-dependency satellite in the acyclic package graph.

---

### ADR-018: Add a CI Verify binaries step to guard against missing executables
**Date:** 2026-05-02 | **Status:** Accepted

**Context:** After csv_unit_test was added as a second binary (v0.6.6), a future change to sdata.gpr could accidentally remove it from the for Main use clause. The test harness would then fail with a cryptic binary-not-found error rather than a named CI step failure.

**Decision:** Add a test -x bin/sdata && test -x bin/csv_unit_test check as a named Verify binaries step in the CI workflow, placed between Build and Run test suite.

**Consequences:** Binary-absence failures are surfaced at build time with a clear step name rather than buried in test harness output. No structural changes to the workflow.

---

### ADR-019: Drop orphaned columns immediately on DIM resize rather than deferred garbage collection
**Date:** 2026-05-02 | **Status:** Accepted

**Context:** When a permanent array is re-DIM'd to a smaller range (e.g. DIM A(1:5) followed by DIM A(1:3)), table columns for out-of-range indices (A(4) and A(5)) were left in the table with a null stub and a comment suggesting a separate garbage collection step. The orphaned columns appeared in NAMES and SAVE output.

**Decision:** Call Drop_Column immediately for each out-of-range index in the Dim_Array resize loop, guarded by (I < Start_Idx or else I > End_Idx). No deferred GC mechanism is needed. Overlapping columns retain their data.

**Consequences:** The behavior is correct and immediate: NAMES after a shrinking DIM shows only the new range. The Drop_Column API already existed (used by the interpreter's DROP statement), so no new API was required. Tests for all three resize scenarios (shrink, expand, shift) were added.

---

### ADR-020: Raise Incomplete_Statement on SELECT at EOF to fix interactive REPL SELECT CASE parsing
**Date:** 2026-05-01 | **Status:** Accepted

**Context:** The parser uses SELECT <expr> for two forms: a row filter (declarative) and the SELECT CASE block (deferred control flow). In the interactive REPL, when SELECT <expr> arrived with no following CASE before EOF, the parser committed to the filter form and subsequent CASE lines then failed. In batch mode this worked because the full file was in the buffer.

**Decision:** When SELECT <expr> is followed only by newline+EOF in the input buffer, raise Incomplete_Statement so the REPL buffers the input and waits for more. When CASE lines are typed on subsequent lines, the full block is re-parsed correctly. Batch mode is unaffected.

**Consequences:** SELECT CASE blocks work correctly in the interactive REPL. An explicit error message was also added for Incomplete_Statement in batch mode (which indicates a genuinely truncated file).

---

### ADR-021: Use Interfaces.Integer_64 rather than Long_Integer for overflow detection
**Date:** 2026-05-01 | **Status:** Accepted

**Context:** The evaluator's overflow check for integer arithmetic widened operands to Long_Integer before range-checking. On 64-bit Linux GNAT, Long_Integer is 64 bits, making the check correct. On Windows MinGW GNAT, Long_Integer is 32 bits (LLP64 model), so the widened operands overflowed before the manual check ran, producing an internal constraint-error instead of the user-friendly overflow message.

**Decision:** Replace Long_Integer with Interfaces.Integer_64, which is guaranteed 64 bits on every platform. Use 'use type Interfaces.Integer_64' (not 'use Interfaces') to expose only the relational operators for that type without polluting the namespace.

**Consequences:** Integer overflow detection is correct and portable across Linux and Windows GNAT. The namespace narrowing (use type) is cleaner than the full use Interfaces that was added initially and then corrected.

---

### ADR-022: Prefer bash/sh over cmd.exe for SYSTEM and SHELL on Windows
**Date:** 2026-05-01 | **Status:** Accepted

**Context:** On Windows, the SHELL environment variable is either absent or carries a Unix-style path (e.g. /usr/bin/bash) that the Windows loader cannot resolve. The previous detection trusted SHELL then COMSPEC then suffix-matched against CMD.EXE, causing commands to be dispatched through cmd.exe. Single quotes survived because cmd.exe does not process them, breaking the system_test golden output.

**Decision:** Detect Windows via GNAT.OS_Lib.Directory_Separator. On Windows, look up bash then sh on PATH (covering MSYS/MinGW installations). Only fall back to COMSPEC/cmd.exe when no POSIX shell is found on PATH.

**Consequences:** MSYS/MinGW Windows builds get POSIX semantics for SYSTEM and SHELL, making test output consistent with Linux. Users without a POSIX shell on PATH still get cmd.exe as fallback.

---

### ADR-023: Use NAMES after RUN for array resize test verification rather than SAVE-based file comparison
**Date:** 2026-05-02 | **Status:** Accepted

**Context:** When writing tests for DIM array resize behavior, two verification approaches were available: (1) SAVE the table to a file and inspect the file contents, or (2) call NAMES after the resize and diff the column list in the terminal output. The SAVE approach would require a file comparison and clean-up step; the NAMES approach works entirely through the existing file-diff harness.

**Decision:** Use NAMES as the verification mechanism in array resize tests. For expand and shift scenarios where NAMES reflects Output_Column_Order (only explicitly SET columns), all elements of the new range are explicitly SET to make the full column set visible in the NAMES output.

**Consequences:** Tests are simple two-file additions (.cmd + .out) with no auxiliary cleanup or file I/O. The requirement to SET all elements to make them visible in NAMES is documented as a test design note in the commit message. Note: NAMES-based tests do not directly verify Drop_Column was called; a SAVE-based test would close that gap if needed.

---

### ADR-024: Implement a data-driven HELP dispatcher rather than a large if-elsif chain
**Date:** 2026-03-04 | **Status:** Accepted

**Context:** The HELP command covers 100+ topics (commands and functions). Implementing lookup as a linear if-elsif chain would be 300+ lines, brittle to add to, and untestable by path. A table-driven approach allows the dispatch to be data rather than code.

**Decision:** Implement Print_Help in SData.Help as a hash-map lookup over a Help_Table array of (Key, Handler, In_Cmd, In_Func) records. Four code paths: bare HELP (index), HELP /ALL (full reference), known topic (call handler), unknown topic (error). Aliases share a handler. Case normalization via To_Upper before lookup.

**Consequences:** Adding a new HELP topic requires only a new record in Help_Table and a handler procedure — no control flow changes. The 8 HELP dispatcher tests cover all four code paths including case-insensitive lookup and alias dispatch.

---

### ADR-025: Install signal handlers for SIGTERM/SIGINT to clean up SQLite temp files
**Date:** 2026-04-17 | **Status:** Accepted

**Context:** The SQLite backing store writes a temp file in /tmp for spilled tables. On normal exit, Finalize is called and the file is deleted. But if the process receives SIGTERM or Ctrl-C (SIGINT) during a spillover run, the temp file is orphaned.

**Decision:** Implement SData.Signals with two handlers: SIGTERM via pragma Attach_Handler on a protected procedure (Ada interrupts mechanism), and SIGINT via GNAT.Ctrl_C.Install_Handler at package elaboration. SData.Table calls Register_Cleanup_Path when the backing store activates and Clear_Cleanup_Path in Finalize.

**Consequences:** Temp files are cleaned up on SIGTERM and Ctrl-C, not just on normal exit. The Ada_Sqlite3.Database finalization remains deferred (a known upstream library issue prevents calling Free in Finalize without a double-finalization crash), but the file handle is closed by the OS and the path is unlinked by the signal handler.

---

### ADR-026: Call LibreOffice subprocess for formula evaluation; fall back to cached values
**Date:** 2026-03-02 | **Status:** Accepted

**Context:** SData reads ODS and OOXML files natively. Cells with formulas store both the formula expression and the last cached result. Evaluating formulas in Ada would require implementing a two-pass loader, an OpenFormula parser, a cell-dependency resolver, and an expression evaluator for two different formula dialects — estimated at multiple focused development sessions.

**Decision:** For formula cells, call soffice --headless --convert-to as a subprocess to produce a fresh conversion with recalculated values, then read the converted file. When LibreOffice is absent, fall back to the cached result values stored in the file by the saving application.

**Consequences:** The common case (files saved after a full recalculation) works correctly without LibreOffice. Volatile formulas (=TODAY(), =RAND()) may produce stale values when LibreOffice is absent. The architecture is documented so a native evaluator can be added later without structural changes.

---

### ADR-027: Adopt RPM-first packaging with a bump-version script covering all tracked locations
**Date:** 2026-03-05 | **Status:** Accepted

**Context:** sdata targets Linux as its primary platform. A packaged binary distribution is needed for installation without requiring users to build from source. Version strings appear in nine files across the repo and were frequently desynchronized (wrong day-of-week in changelog, incorrect version in secondary files).

**Decision:** Implement a sdata.spec file for RPM builds (primary), with debian/changelog and sdata.SlackBuild for Debian and Slackware. A scripts/bump-version.sh script updates all version strings atomically across the nine tracked locations.

**Consequences:** Three packaging formats are maintained in parallel. The version bump script prevents the frequent desynchronization errors seen before it was added. Tags were not added for v0.6.1-v0.6.6 and were retroactively applied in v0.6.7.

---

### ADR-028: Use SELECT /ALL and bare BY for state cancellation rather than new keywords
**Date:** 2026-04-10 | **Status:** Accepted

**Context:** The SELECT declarative command (row filter) and BY grouping state both needed cancellation forms. Options for each included new keywords (SELECT OFF, CLEAR SELECT, CLEAR BY) or reusing existing syntax.

**Decision:** Use SELECT /ALL to cancel the active row filter (already parsed as a distinct branch), and bare BY (no arguments) to cancel BY grouping. NEW was also verified to clear both Select_Filter_Expr and Current_By_Vars.

**Consequences:** The command set is minimal and internally consistent. SELECT /ALL and bare BY are self-documenting without adding new reserved words. The symmetry with SELECT <expr> / BY var1 var2 makes the intent clear.

---

### ADR-029: Implement BREAK / BREAK WHEN as deferred debug statements with a mini-REPL
**Date:** 2026-04-30 | **Status:** Accepted

**Context:** The --debug flag was defined in SData.Config but consulted nowhere in the interpreter — it was silently inert. Users had no way to inspect the PDV mid-step or pause execution at a specific record condition without adding PRINT statements.

**Decision:** Implement a two-part debug system: (1) passive trace via --debug emits [debug] lines to stderr for LET/SET, IF, SELECT, DELETE, BY group changes, USE, and RUN events; (2) interactive inspection via BREAK and BREAK WHEN <expr> deferred statements that pause execution and enter a mini-REPL. In non-interactive (piped/batch) context, BREAK continues automatically.

**Consequences:** The --debug flag is now genuinely useful. Inspect_PDV is ~150 additional lines all confined to sdata-interpreter.adb. Three new tests cover the passive trace and non-interactive BREAK behavior; interactive REPL navigation is covered by manual testing only.

---

### ADR-030: Use relative paths in options_test for cross-platform portability
**Date:** 2026-05-01 | **Status:** Accepted

**Context:** The options_test script hardcoded /tmp/ paths for output files. On native Windows GNAT builds, /tmp resolves to C:\\tmp, which typically does not exist, breaking the test. The stray output files were also landing in the project root and not being cleaned up.

**Decision:** Use plain relative filenames in options_test (no path prefix) so the files land in the working directory (make check runs from the project root). Add the two filenames to the clean target in the Makefile.

**Consequences:** The test passes identically on Linux and Windows. The clean target now removes all test artifacts.

---

### ADR-031: Keep SYSTEM/SHELL enabled by default; mark sandboxing/allowlist/escaping as won't-fix
**Date:** 2026-05-06 | **Status:** Accepted

**Context:** A security audit flagged SYSTEM and SHELL as "High" risk and recommended sandboxing, allowlisting, and metacharacter escaping. SData is a CLI analysis tool where script authors are trusted by definition — the threat model is identical to R, SAS, or Python used for data preparation. The --noshell flag already provides an opt-in restriction for pipeline operators running untrusted scripts.

**Decision:** Classify SYSTEM/SHELL risk as Low-Medium. Mark sandboxing, allowlisting, and metacharacter escaping as won't-fix. Sandboxing adds platform-specific complexity without a realistic threat to defend against at this deployment scope; an allowlist cannot be defined generically without breaking legitimate use; escaping metacharacters would silently neuter the feature (pipes and redirects are intentional). The --noshell flag remains the documented mitigation for untrusted-script contexts.

**Consequences:** The security posture is "trust the script author," consistent with every comparable scripting tool. Pipeline operators who need containment must explicitly pass --noshell. This decision places responsibility on the operator, not the tool.

---

### ADR-033: Use a C stub for privilege detection rather than florist_blady
**Date:** 2026-05-06 | **Status:** Accepted

**Context:** Enforcing --noshell and --nosubmit when running as root or Windows SYSTEM required calling `getuid()` on POSIX and `GetUserNameA()` on Windows. The Alire crate `florist_blady` provides Ada POSIX bindings including `POSIX.Process_Identification.Get_Real_User_ID`, which would cover `getuid()` in pure Ada. However, `florist_blady` is explicitly `Available when: Windows => False`, meaning it cannot be declared as an unconditional dependency. A conditional Alire dependency would still require a separate Ada path for Windows, and the crate requires its own `configure` + `make gen` post-fetch build steps.

**Decision:** Implement privilege detection as an 18-line C stub (`src/sdata_privilege.c`) using `#ifdef _WIN32` to branch between `GetUserNameA` (Windows) and `getuid()` (POSIX). The stub is wrapped by a single Ada function `SData.System.Running_As_System_Account` via `pragma Import`. The GPR project gains `for Languages use ("Ada", "C")` to compile the stub.

**Consequences:** The project gains a minimal, intentional C dependency for one specific purpose. This is acceptable given that the project already links a C library (Ada_Sqlite3 via its SQLite3 amalgamation) and the stub is self-contained with no further C code planned. `florist_blady` was explicitly evaluated and rejected: its Windows exclusion makes it less portable than the C stub it would replace.

---

### ADR-034: Measure MAXINTAB / -m in cells (rows × columns), not rows
**Date:** 2026-05-07 | **Status:** Accepted

**Context:** The `-m` CLI flag and `OPTIONS MAXINTAB` both set `Max_Table_Rows`, which was compared against the in-memory row count to decide when to spill a segment to SQLite. The help text said "max in-memory table size," but the implementation was a pure row limit. For a 100-column table the memory consumed per threshold unit is 100× that of a 1-column table, so the parameter had no stable meaning as a size limit across different datasets.

**Decision:** Redefine the unit of MAXINTAB / `-m` as cells (rows × columns). Both spill checks — in `Add_Row` for the input table and in `Add_Output_Row` for the output table — now compare `rows_in_current_segment × column_count` against the threshold. `Fetch_From_Disk` derives the equivalent rows-per-segment for cache-page alignment as `threshold / column_count` (floored at 1), preserving consistent segment boundaries between write and read paths. The config variable was subsequently renamed from `Max_Table_Rows` to `Max_Table_Cells` to match the semantics. A practical guideline: 1 000 000 cells ≈ 25–32 MB at typical cell sizes; 10 000 000 cells ≈ 250–320 MB.

**Consequences:** The threshold is now proportional to actual memory consumption regardless of dataset width. The default of 0 preserves existing behavior for all users who have not set the option. The one-to-one correspondence between write-segment size and read-segment size is maintained because both derive rows-per-segment from the same formula. Column count is stable during the row-adding phase for both the input and output tables (columns are finalized before rows are appended in all parsers and in `Flush_PDV_To_Output`), so the divisor does not change within a single spill calculation.

---

### ADR-035: Adopt IEEE 754 infinity as a first-class evaluator value
**Date:** 2026-05-07 | **Status:** Accepted

**Context:** The evaluator treated divide-by-zero and arithmetic overflow as fatal runtime errors. Scripts that divided by a denominator that could be zero in some records had to guard every such expression with an IF check, making data-cleaning code verbose. SAS — the primary design reference — propagates IEEE 754 infinity rather than halting, and provides a missing-value propagation model that does not require defensive guards at every arithmetic site.

**Decision:** Treat IEEE 754 positive and negative infinity as first-class values in the SData runtime:

- `Pos_Inf` and `Neg_Inf` constants are initialized via a local `Big : Float := Float'Last` followed by `Big * 2.0` at package elaboration of `SData.Values`. Initializing directly as a constant causes GNAT to evaluate the expression at compile time and raise `Constraint_Error`; deferring to a local non-constant variable produces the IEEE overflow at runtime, yielding the correct bit-pattern. A targeted `pragma Warnings (Off/On, "could be declared constant")` suppresses the resulting GNAT `-gnatwk` warning.
- An `INF()` built-in function returns `Pos_Inf`; negation (`-INF()`) gives `Neg_Inf`.
- `OPTIONS IEEE_DIVIDE ON` (the default) routes division by zero to `Pos_Inf` or `Neg_Inf` based on the sign of the numerator; `OPTIONS IEEE_DIVIDE OFF` restores the original fatal-error behavior.
- Infinity propagates through arithmetic and transcendental functions (e.g. `FLOOR(Inf) = Inf`, `SQRT(Inf) = Inf`).
- Integer assignment is a firewall: assigning an infinite value to an integer column raises a runtime error. Real (floating-point) columns accept and store infinity without restriction.

**Consequences:** Scripts can perform division and exponential operations without defensive IF guards when propagation is acceptable. The initialize-via-runtime-overflow technique is GNAT-specific but is the only way to generate IEEE infinity in Ada without compiler-generated Constraint_Error; it is isolated to a two-line block in `SData.Values`. The INTEGER firewall prevents silent data corruption in downstream integer arithmetic while leaving the propagation path open for real-valued computations.

---

### ADR-032: Add --nosubmit flag to disable SUBMIT command
**Date:** 2026-05-06 | **Status:** Accepted

**Context:** SUBMIT reads and executes external script files. Without SYSTEM/SHELL (i.e. with --noshell active), a malicious submitted script has a limited blast radius (SData operations only: USE, SAVE, PRINT), but path traversal via SUBMIT could still reach files outside the intended working directory. Pipeline operators who need complete containment had no way to disable SUBMIT independently of other flags.

**Decision:** Add --nosubmit flag mirroring --noshell. When active, any SUBMIT statement emits a user-visible error message and does not execute. Path traversal is marked won't-fix by default; --nosubmit is the opt-in mitigation. The flags are independent and can be combined.

**Consequences:** Pipeline operators have a complete containment toolkit: --noshell prevents OS command execution, --nosubmit prevents external script loading. Both flags together give a maximally restricted execution environment. The implementation is 4 lines: one config flag, one CLI argument branch, one guard in the SUBMIT handler, and one help text update.

---

### ADR-036: Set MAXINTAB default to 50 000 000 cells with a static value rather than runtime memory detection
**Date:** 2026-05-07 | **Status:** Accepted

**Context:** Once MAXINTAB was redefined in cells (ADR-034), the previous default of 0 (unlimited) risked OOM on large datasets because the spill threshold was never reached. A non-zero default was needed. Two approaches were considered: a static constant, or a runtime calculation based on available physical memory (e.g. querying `/proc/meminfo` on Linux or `sysctl` on BSD/macOS).

**Decision:** Use a static default of 50 000 000 cells, encoded as `Max_Table_Cells : Natural := 50_000_000` in `SData.Config`. Runtime memory detection was rejected for three reasons: (1) "available memory" is a moving target — other processes compete for RAM throughout the run, so a startup snapshot provides false precision; the right question is a *policy* about how much RAM sdata is allowed to claim, and a static value makes that policy explicit and auditable; (2) querying free physical RAM portably requires platform-specific paths (`/proc/meminfo`, `sysctl`, `GlobalMemoryStatusEx`) that add complexity for dubious benefit; (3) the correct response to varying machine sizes is the existing `-m` / `OPTIONS MAXINTAB` override, not automatic detection.

The value 50 000 000 was derived from targeting ~1.5 GB on an 8 GB machine (the low end of "average" in 2026). Each `Value` cell is a variant record sized to its largest variant (`Unbounded_String` in GNAT ≈ 16–20 bytes plus discriminant and alignment), giving an estimated 24–32 bytes per cell. At 32 bytes/cell: 50 000 000 × 32 = 1.6 GB. This covers 500 000 rows × 100 columns or 5 000 000 rows × 10 columns before spilling to SQLite, which is adequate for most statistical workloads. Users who need more set `OPTIONS MAXINTAB N` or `-m N`; users who want the old unlimited behaviour set `OPTIONS MAXINTAB 0` or `-m 0`.

**Consequences:** Large datasets no longer silently exhaust RAM by default. The threshold is conservative for numeric-heavy data (actual cell size ≈ 16 bytes → ~800 MB at 50M cells) and reasonable for mixed data. The static value is easy to explain, easy to override, and requires no OS-specific code.

---

### ADR-037: Add configurable SYSTEM/SHELL timeout defaulting to 300 s in batch mode, unlimited in interactive
**Date:** 2026-05-13 | **Status:** Accepted

**Context:** `GNAT.OS_Lib.Spawn` (used for SYSTEM and SHELL execution, per ADR-010) is a blocking call with no timeout parameter. A hung shell command — waiting on a network mount, a stalled subprocess, or a deadlocked pipeline — blocks the sdata process indefinitely with no escape. This is a §5 gap in the software standards audit. However, imposing a blanket timeout is wrong for interactive use: a user running `SYSTEM "bash"` or `SYSTEM "python3"` at the REPL may legitimately keep an interactive shell open for any length of time. The timeout is only meaningful as a guard against accidental hangs in unattended batch runs.

**Decision:** Add a `Shell_Timeout` configuration variable (seconds; 0 = unlimited) to `SData.Config.Runtime`, controlled by two surfaces:

1. **CLI flag `--shell-timeout=N`** — sets the initial value at startup. Default: 300 in batch mode (stdin is not a terminal), 0 in interactive mode (stdin is a terminal). The mode check uses `GNAT.OS_Lib.Is_Stdin_A_TTY` (or equivalent `isatty(0)` via a small pragma-Import stub if not available directly).
2. **`OPTIONS SHELLTIMEOUT N`** — runtime override, allowing scripts to raise the limit for known-slow operations (`OPTIONS SHELLTIMEOUT 600`) or lower it for rapid sanity checks.

Implementation uses the POSIX `timeout` utility as a command prefix: the shell invocation becomes `timeout N /bin/sh -c "user_command"`. Exit code 124 from `timeout` is distinguished from a genuine non-zero exit and reported to the user as a distinct timeout error (`Script_Error` with message "SYSTEM command timed out after N seconds"). On platforms where `timeout` is absent the feature degrades gracefully: if `timeout` is not found on `PATH`, the command runs without a time limit and a one-time warning is emitted.

300 seconds was chosen as the batch default: it is long enough to cover typical data-pipeline shell calls (sorting large files, calling `ssconvert` on a large spreadsheet, running an ETL subprocess), but short enough to limit damage from an accidental hang in an overnight batch run. Users with known slow operations can raise the limit explicitly; users who want the old unlimited behaviour set `OPTIONS SHELLTIMEOUT 0` or `--shell-timeout=0`.

**Consequences:** Batch runs are now protected from indefinite hangs by default. Interactive use is unaffected. The implementation avoids POSIX signal handling in Ada (which requires `pragma Import` of `sigaction` and careful interaction with the Ada runtime's own signal use) by delegating to the well-tested `timeout` utility. The platform-availability caveat is limited: `timeout` ships in GNU coreutils and is present on all major Linux distributions, macOS (via Homebrew `coreutils`), and WSL; the graceful degradation path covers edge cases without making the feature a hard dependency. Exit-code 124 is a stable, documented convention of GNU `timeout` and the POSIX `timeout` command.

---

### ADR-038: Add VANDALIZE command for generating noisy variable copies
**Date:** 2026-05-15 | **Status:** Superseded — VANDALIZE moved to the standalone `data-vandal` application.
See design spec at `doc/specs/2026-05-19-data-vandal-design.md`.

**Context:** Statistical workflows frequently require synthetic data generation, anonymisation of sensitive variables, and sensitivity testing. SData had no built-in facility for introducing controlled noise into table variables. Users had to write verbose multi-statement workarounds (FOR loops, conditional LETs, manual RSEED management) that did not compose cleanly with BY-group stratification. Full design rationale: `doc/specs/2026-05-15-vandalize-design.md`.

**Decision:** Add `VANDALIZE <source> INTO <dest> [/PERTURB[=prob[,sd-frac]]] [/SHUFFLE[=prob]] [/MISS[=prob]] [/BY=var[,var...]]` as an **immediate** command (same execution tier as SORT). Key design choices and their rationale:

- **Mutually exclusive per-cell probability model.** A single Uniform(0,1) draw per row selects at most one operation via cumulative thresholds (MISS → SHUFFLE → PERTURB). The residual probability yields an unchanged copy. This gives the user direct control over the mixing proportion and avoids double-counting.
- **Immediate tier; no implicit RUN.** VANDALIZE operates on the table in its current state, consistent with SORT. Pending deferred statements (LET, PRINT, etc.) are unaffected and execute on the next explicit RUN.
- **BY-group stratification is local.** `/BY=` in VANDALIZE saves, temporarily replaces, and then restores the global BY state, so it has no side-effect on subsequent BY-group processing.
- **Fisher-Yates shuffle per group.** SHUFFLE builds a per-group permutation index using Fisher-Yates and maps each output row to a shuffled source row, ensuring a uniform permutation without replacement.
- **Population SD for PERTURB; graceful degradation for small groups.** The noise scale uses population standard deviation (divide by N, not N−1). If a group has fewer than two non-missing values, SD is treated as 0.0 (no perturbation noise) rather than raising Script_Error. This is more robust for sparse BY-groups encountered in real anonymisation workflows.
- **`Expr_Missing` expression kind.** Adding `Token_Dot` to the lexer (required for the `/PERTURB=.,sd-frac` placeholder syntax) broke existing code that passed `.` as a function argument (e.g. `INF(.)`), because `.` previously fell through to `when others` in the punctuation case and was silently ignored. The fix was to introduce `Expr_Missing` as a proper AST expression kind evaluating to `Val_Missing`, making `.` a first-class expression throughout the language.
- **DIM array support via `SData.Variables` API.** When source is a DIM array base name, VANDALIZE iterates over elements using `SData.Variables.Has_Array` / `Get_Array_Bounds`, building element column names in parenthesis notation (`X(1)`, `X(2)`, …) consistent with the existing DIM naming convention.

**Consequences:** Users can generate noisy copies of any permanent variable with a single statement, with control over operation type, probability, and BY-group stratification. The `Expr_Missing` AST kind is a permanent addition that correctly represents the `.` missing-value literal; it resolves a pre-existing latent issue in `INF(.)` parsing. Nine integration tests cover errors, MISS, SHUFFLE, PERTURB, BY groups, in-place replacement, combined operations, and DIM arrays.

---

### ADR-039: Extract sdata-core as a shared Alire library
**Date:** 2026-05-21 | **Status:** Accepted

**Context:** A standalone `data-vandal` application was needed (see ADR-038 supersession and the data-vandal design spec at `doc/specs/2026-05-19-data-vandal-design.md`). VANDALIZE itself is a thin layer over the table, evaluator, and command-execution machinery that already existed in sdata; rebuilding any of that in data-vandal would have meant maintaining two copies of the data layer, two evaluators, two CSV/ODF/OOXML parsers, etc. The alternative — leaving everything in sdata and adding a second binary target — would have bound data-vandal's release cadence to sdata's and pulled the entire sdata command set into data-vandal's executable.

**Decision:** Factor sdata's data layer, evaluator, and the execution bodies of the commands shared between sdata and data-vandal into a separate Alire library crate named `sdata_core`. Both sdata and data-vandal depend on it. During development, both consumers use a path pin (`[[pins]] sdata_core = { path = "../sdata-core" }`) plus a normal version constraint (`sdata_core = "^0.1.0"`); the pin overrides version resolution for local builds while the constraint defines what a future Alire-index-published consumer would require.

The packages moved into sdata-core: `Table`, `Values`, `Variables`, `Statistics`, `CSV`, `IO`, `File_IO` (and its `CSV`/`ODF`/`OOXML`/`Helpers` children), `Config`, `Config.Runtime`, `Signals`, `Evaluator` (and its `Aggregate_Fns`/`Distrib_Fns`/`Misc_Fns`/`Nav_Fns`/`Numeric_Fns`/`String_Fns` children), `System`, plus the `sdata_privilege.c` privilege-detection stub. A new package `SData_Core.Commands` exposes one `Execute_*` procedure per command shared between consumers (USE, SAVE, FPATH, OUTPUT, SELECT, KEEP, DROP, ARRAY, DIM, RUN, plus the post-Task-16 `Execute_OUTPUT_Table` and `Execute_Rebuild_Filter`).

**Consequences:** sdata shed roughly 11 000 lines of source (now in sdata-core) and gained one dependency line. data-vandal's main package is ~2 200 lines plus its share of sdata-core. The two binaries can be released on independent schedules: sdata-core 0.1.0 + sdata 0.8.0 + data-vandal 0.1.0 ship as the first set of tagged versions. The path-pin convention can be lifted by publishing sdata-core to the Alire community index when it stabilises; this requires a one-line change in each consumer's `alire.toml`. sdata's 140 integration tests pass unchanged; data-vandal's 11 native VANDALIZE tests verify the executor was ported faithfully.

---

### ADR-040: sdata-core contains no lexer, AST, or parser
**Date:** 2026-05-21 | **Status:** Accepted

**Context:** A natural first instinct when factoring sdata-core out (ADR-039) was to put the lexer, AST, and parser in the shared library too — those are mechanical components and both consumers need them. Ada enumeration types are closed: `Token_Kind`, `Statement_Kind`, and `Expression_Kind` cannot be extended after definition. If sdata-core owned them, every token sdata uses (LET, IF, FOR, WHILE, SORT, BREAK, …) would also be in data-vandal's binary, and every new sdata command would be a breaking change for data-vandal — or vice versa. The alternative of representing tokens as `Unbounded_String` and statements as a tagged hierarchy would have worked but at significant runtime cost and away from idiomatic Ada.

**Decision:** Each application owns its complete lexer, AST, and parser. sdata-core owns the data layer, the evaluator, and the command execution procedures. `SData_Core.Commands.Execute_*` procedures accept plain Ada values (paths, name vectors, expression accesses) — never AST node types. The expression parser is shared via a string-based entry point: `SData_Core.Evaluator.Parse_Expression (Text : String) return Expression_Access`. Each consumer's parser reconstructs the SELECT-filter expression text from its own token stream and hands the string off to `Parse_Expression`; the returned expression tree then flows back through `Execute_SELECT`.

**Consequences:** sdata's lexer/AST/parser are unchanged in concept (just renamed `SData.*`); data-vandal owns its own small lexer (16 keywords + the operators needed for SELECT expressions), AST (11 statement kinds), and parser (~700 lines). The two applications can add or rename commands independently. The shared `Parse_Expression` keeps both consumers honest about expression-language compatibility: a SELECT filter that parses in sdata parses identically in data-vandal because the same evaluator parses both. The cost is the small overhead of reconstructing tokens into a string and re-tokenising inside `Parse_Expression`, which is negligible compared to the cost of evaluating the filter against table rows.

---

### ADR-041: Auto-detect subscripted columns as arrays at USE time; narrow DIM
**Date:** 2026-05-21 | **Status:** Accepted

**Context:** SData's `DIM` command pre-declares subscripted-variable groups: `DIM X 1 5` reserves columns `X(1) .. X(5)` so that later expressions like `X(I)` can index into them. When a dataset is loaded that already contains columns named `X(1)`, `X(2)`, `X(3)`, however, the user previously had to also issue `DIM X 1 3` to make `X(I)` work — even though the information was already in the column names. data-vandal exposes the same expression language but has no `DIM` command, so without auto-detection there would be no way to vandalise array columns at all.

**Decision:** Add `SData_Core.Variables.Register_Subscripted_Columns`, called automatically from `SData_Core.Commands.Execute_USE` after every successful file load. It scans column names for the `name(n)` pattern (n a positive integer), groups by base name, and registers each group as a DIM array spanning `min(n) .. max(n)`. Gaps in the subscript sequence are permitted. Both sdata and data-vandal receive this automatically; no user command is required.

SData retains `DIM` but its scope narrows to creating subscripted variables that do not yet exist in the loaded data (e.g., to extend an existing group, or to pre-declare a group that an upcoming LET statement will populate). data-vandal has no `DIM` and never needs one — it consumes existing arrays only.

**Consequences:** Existing sdata scripts are unaffected: `DIM X 1 5` before `USE` pre-declares; `DIM X 1 5` after `USE` extends (or no-ops if the array already covers that range). New sdata scripts can drop the redundant `DIM` after a `USE` that loads subscripted columns. data-vandal can vandalise array sources (`VANDALIZE X /MISS=1.0` where X(1..3) are loaded columns) with no setup. Auto-detection is conservative: only column names matching the strict `<base>(<positive-int>)` pattern register as arrays, so names like `f(x)`, `cos(theta)`, or `count_2024` are left alone.

---

### ADR-042: Add Execute_OUTPUT_Table as a parallel sdata-core entry point
**Date:** 2026-05-21 | **Status:** Accepted

**Context:** The data-vandal design spec (§4.1) requires that `RUN` write the table to the OUTPUT path when no explicit SAVE is pending. sdata's existing `OUTPUT` command, however, does something different: it redirects PRINT-style console output to a file. The two semantics are incompatible — overloading the same `Execute_OUTPUT` procedure to mean both would break sdata's existing behaviour and confuse the code path that flushes the table on RUN.

**Decision:** Add a second sdata-core entry point, `SData_Core.Commands.Execute_OUTPUT_Table (File_Name, TXTFMT)`, that captures a table-output destination in new runtime fields (`Output_Table_Path`, `Output_Table_Len`, `Output_Table_Active`, `Output_Table_Fmt`). A new helper, `Flush_Pending_Output_Table`, is wired into `Execute_RUN` after `Flush_Pending_Save`; if an explicit SAVE is pending it wins, otherwise the table is written to the OUTPUT_Table destination. sdata's existing `Execute_OUTPUT` (text redirection) is unchanged. data-vandal's `Stmt_OUTPUT` dispatches to `Execute_OUTPUT_Table`; sdata's continues to dispatch to `Execute_OUTPUT`.

**Consequences:** Both applications get the semantics their respective specs and user bases expect, with no conditional behaviour in sdata-core. The two destination states (`Save_File_*` for one-shot SAVE; `Output_Table_*` for persistent OUTPUT) coexist cleanly. The `Output_Table_Active` flag intentionally stays set after a flush so that repeated `RUN`s keep writing to the same destination — OUTPUT is a setting, not a one-shot. The cost is a small duplication in the two `Flush_*` helpers (path resolution, format selection, header writing); a future cleanup could factor a common writer if it grows further.

---

### ADR-043: Per-application version constants
**Date:** 2026-05-21 | **Status:** Accepted

**Context:** When `SData.Config` moved into sdata-core (as part of ADR-039), the `Version_Major/Minor/Patch/Str` and `Copyright_*` constants moved with it. That left sdata's user-facing version banner ("SData version 0.7.1") sourced from a package shared with data-vandal, even though data-vandal had its own version (0.1.0) and sdata-core had a third one (0.1.0 in its `alire.toml`). The `bump-version.sh` script broke when it could no longer find `src/sdata-config.ads` in sdata, and a single set of constants could no longer correctly identify any of the three crates.

**Decision:** Each consumer of sdata-core owns its own version constants in its own package. sdata's live in `SData.Version` (`src/sdata-version.ads` in the sdata crate); data-vandal has its own (currently a hard-coded string in main, sufficient until it grows complexity). sdata-core's own version lives only in its `alire.toml` — no Ada constants, because no code in sdata-core currently needs to display "sdata-core version X.Y.Z". Each crate's `alire.toml` carries its own `version =` field; `[[depends-on]]` constraints in consumers pin the required sdata-core range (currently `^0.1.0`). The `bump-version.sh` script targets `src/sdata-version.ads` instead of the removed `src/sdata-config.ads`.

**Consequences:** sdata, sdata-core, and data-vandal can release on independent schedules without their version numbers drifting in confusing lockstep. The Alire path-pin (used during development) overrides version resolution for local builds; the version constraint takes effect for consumers fetching from the index. Each release tag stands on a coherent set of versions: `sdata-core v0.1.0` + `sdata v0.8.0` + `data-vandal v0.1.0` is the first such set. Future sdata-core releases will require touching consumer `alire.toml`s to bump the constraint floor (`^0.1.0` → `^0.2.0` if breaking), which is the explicit acknowledgement those bumps deserve.

---

### ADR-044: USE/SAVE RENAME= applies the suffix-determines-type rule
**Date:** 2026-06-06 | **Status:** Accepted

**Context:** A variable's type is denoted by its name suffix (`$` string, `%` integer, none float), enforced on CSV import and `LET`/`SET` assignment but not by `RENAME`. `USE foo(rename=(x=x%))` previously produced a column named `X%` whose stored type was still float — a name/type mismatch. Separately, implementation revealed that per-dataset/per-target paren options (`rename=`/`keep=`/`drop=`) were applied only in the multi-dataset `USE` and multi-target `SAVE` code paths; a single-dataset `USE` (`MM_Single`) and a single-target `SAVE` (legacy pending-save flush) silently ignored them, so the headline single-dataset case never reached the rename logic at all.

**Decision:** The `USE`/`SAVE` `rename=()` option derives each target column's type from the new name's suffix. A change within the numeric family (float ↔ integer) converts the column's values (float → integer truncates toward zero, matching `LET` coercion) inside `SData.Transient_Table.Apply_Rename`; a rename crossing the numeric/character boundary is rejected, aborting the whole `RENAME` with nothing applied (all-or-nothing, validated before mutation). The numeric truncation rule is centralized in `SData_Core.Values.Convert_Value`, which `Table.Coerce_Value` also delegates to. To make the rule reach single-dataset/single-target forms, the `MM_Single` USE path now snapshots the loaded table and applies rename → keep → drop before caching `Input_File_Columns`, and a single-target SAVE carrying paren options is routed through the existing multi-target registration/projection flush (per-record auto-flush fills its buffer) instead of the legacy pending-save path; an optionless single SAVE is unchanged.

**Scope / non-goals:** The standalone `RENAME` statement (operating on the global `SData_Core.Table`) remains name-only: that table spills row-segments to SQLite typed by `Col.Typ`, so retyping a materialized column would require rewriting the on-disk store — deferred. String ↔ numeric conversion on rename (option #2) is deferred past SData 1.0.

**Consequences:** Renaming a character column to a name without `$` (or a numeric column to a `$` name) is now an error; string columns must keep a `$` suffix across a rename. Single-dataset `USE` and single-target `SAVE` now honour their `rename=`/`keep=`/`drop=` options uniformly with the multi forms (a latent gap fixed in passing). Renames that preserve the suffix are unaffected.

---

### ADR-045: Promote the reserved-keyword USE warning to sdata-core; keep keyword lists per-consumer
**Date:** 2026-06-20 | **Status:** Accepted

**Context:** The quoted-identifiers feature (design spec `doc/specs/2026-05-30-quoted-identifiers-design.md`) added a USE-time advisory warning when a loaded column's name collides with a reserved keyword (e.g. a CSV column literally named `AS` or `USE`). The original 2026-05-30 design kept the warning **sdata-only**, reasoning that "data-vandal doesn't need it." When the feature was scoped to cover both consumers, that rationale collapsed — data-vandal loads the same files and hits the same silent-collision trap. Three placements were possible: (a) keep it sdata-only and re-implement independently in data-vandal; (b) duplicate a private helper in each consumer; (c) promote one shared helper into sdata-core. The warning logic only walks the package-global `SData_Core.Table` against a set of upcased strings — it touches nothing grammar-specific — so it is genuinely shareable. But the reserved-keyword *list itself* mirrors each consumer's lexer keyword chain (sdata reserves 64 keywords; data-vandal 27), and per [ADR-040](adrs.md) grammars are deliberately not shared.

**Decision:** Promote only the warning *mechanism* to sdata-core; keep the *list* per-consumer. `SData_Core.Commands.Warn_Reserved_Columns (Keywords : Reserved_Keyword_Sets.Set)` walks the global table and emits one advisory per colliding column; each consumer passes its own set (`SData.Reserved_Keywords`, `Data_Vandal.Reserved_Keywords`). The exported set type `Reserved_Keyword_Sets` is an `Indefinite_Ordered_Sets (String)`. The helper takes **no `Table` parameter** — the table is a package-global singleton, so it reads `SData_Core.Table.Column_Count` / `Column_Name (I)` directly. Suppression gating lives **inside** the helper (single authority), keyed on a new shared runtime toggle `SData_Core.Config.Runtime.Options_Warn_Reserved : Boolean := True` (getter + `Internal` setter), flipped by a shared `SData_Core.Commands.Execute_OPTIONS_WarnReserved (Value : Boolean)` that `OPTIONS WARNRESERVED YES|NO` (default YES) dispatches to in each consumer. The addition is **purely additive** to sdata-core's public surface — no existing symbol changed — so it is pin-safe for `consumer-tests.yml` (which builds a release-pinned sdata against sdata-core). It first ships in sdata-core **0.1.16**.

**Consequences:** Both consumers get identical warning and suppression semantics from one implementation; the message text or gating logic is changed once. The feature splits cleanly along the ADR-040 seam — shared data-level mechanism in sdata-core, grammar-specific lexer token / parser routing / keyword list implemented twice (once per consumer). Because both consumers now call 0.1.16-only API, both must constrain `sdata_core ^0.1.16`. That floor bump was initially **missed**: the `[[pins]] sdata_core = { path = "../sdata-core" }` pin overrides the version constraint for local builds, so `make check` cannot catch floor drift — a consumer can call new sdata-core API while still constraining an older floor and every local test still passes. It was corrected in follow-up (sdata `147ff39`, data-vandal PR #22), and the hazard is now a standing note for any future sdata-core API consumption. data-vandal, which had no `OPTIONS` command, gained a minimal one (`Token_OPTIONS` → `Stmt_OPTIONS` → `Parse_OPTIONS` → dispatch, with a no-arg display and a non-fatal warning on unknown keys) solely to host `WARNRESERVED`.

### ADR-046: AGGREGATE command — active-BY grouping, build-and-swap, and an aggregate metadata side-table
**Date:** 2026-06-23 | **Status:** Accepted

**Context:** The AGGREGATE command (design spec `doc/specs/2026-06-01-aggregate-design.md`) collapses the current table into one row per active BY group, computing registered aggregate functions over scalar columns, whole arrays (element-wise), or array elements. Implementing it raised several non-obvious decisions; the approved spec also turned out to be inaccurate in three places once grounded against the current source, and integration testing exposed three more. This ADR records the decisions and the corrections so the spec is not mistaken for the as-built contract.

**Decision:**
1. **Grouping from the active BY only — no `/BY=` clause.** AGGREGATE reads `SData_Core.Table.By_Var_Name`/`By_Var_Count`, consistent with the rest of the language; there is no per-command grouping override.
2. **Aggregate metadata as a dedicated public side-table, NOT a widening of the shared evaluator dispatch map.** The function dispatch table (`SData_Core.Evaluator.Dispatch_Table`) is a single global map shared by six handler families and lives in the package's private part; widening its value type would touch every family and both call sites, and the `Aggregate_Fns` child is private. Instead a separate `Aggregate_Meta_Table` (name → `{Accepts_Numeric, Accepts_Character}`) is populated alongside the existing aggregate registrations and exposed via public `Is_Aggregate` / `Lookup` on `SData_Core.Evaluator`. The record carries **no handler** — AGGREGATE computes each group's result through the already-public `Call_Function`, so no private dispatch type leaks. `Accepts_Character` is true only for `N`/`NMISS` (the only handlers that actually tolerate string input today).
3. **Build-and-swap, not the `Execute_OUTPUT_Table`/VANDALIZE pattern the spec named.** `Execute_OUTPUT_Table` only registers a SAVE target; VANDALIZE mutates the table in place. AGGREGATE instead builds a fresh output table (`Initialize_Output_Table` → `Add_Output_*` → `Commit_Output_Table`), re-registers subscripted arrays (ADR-041), flushes a pending SAVE, then clears the stale SELECT filter and the active BY. The forward group-scan models data-vandal's `Compute_Groups`.
4. **Write-and-clear pending SAVE; clear SELECT and BY after running.** A pending SAVE is flushed (failures surface as error #11) and the active SELECT and BY are cleared, since the grouping is "consumed" and the filter may reference columns that no longer exist. The stale logical→physical index map is cleared before the flush so the full aggregated table is written.
5. **Array scalar-vs-array resolution is deferred to execute time.** The spec implied the parser resolves a bare name via `Has_Array`, but in batch mode the parser runs before `USE`, so the registry is empty then. `Parse_AGGREGATE` records a bare name as `Invar_Scalar`; `Execute_AGGREGATE` resolves it against the live registry.
6. **Error #10 ("pending program statements") uses a unified `Pending_Deferred` counter, not a buffer-length test.** The deferred program buffer persists across RUN, and batch mode does not use that buffer at all (it walks the parsed linked list). A single `Pending_Deferred` counter — incremented when a deferred statement is queued (REPL) or skipped pending a RUN (batch), reset on RUN, cleared on NEW — makes #10 fire consistently in both modes and makes the "issue RUN or NEW first" guidance accurate (RUN genuinely resolves it).

**A further spec correction (not a decision):** the spec's §3.2 "no auto-sort; non-adjacent runs of the same key produce separate rows" does not occur in practice, because `BY` auto-sorts the physical table by the BY key. By the time AGGREGATE scans, equal keys are always adjacent, so one group is produced per distinct key. AGGREGATE's grouping (consecutive runs via `In_Same_Group`) is correct; the precondition the spec assumed simply never holds.

**Consequences:** AGGREGATE is purely additive to sdata-core's public surface (`Aggregate_Metadata`/`Is_Aggregate`/`Lookup` on `Evaluator`; `Aggregate_Invar_Kind`/`Aggregate_Spec`/`Aggregate_Spec_Vectors`/`Execute_AGGREGATE` on `Commands`) — a patch bump (sdata-core 0.1.16 → 0.1.17), and the existing `^0.1.16` consumer floor still admits it, so no consumer-constraint change is needed. data-vandal does not use `Execute_AGGREGATE` but builds and tests clean against the additive API. AGGREGATE becomes a reserved keyword in sdata's lexer. The `Pending_Deferred` counter is now load-bearing for any future table-replacing immediate command that must reject mid-data-step invocation.

---

### ADR-047: TRANSPOSE command — type-uniformity, union-of-IDs, max-K padding, and output-collision rules
**Date:** 2026-06-25 | **Status:** Accepted

**Context:** The TRANSPOSE command (design spec `doc/specs/2026-06-01-transpose-design.md`, architect reconciliation `.ssd/features/transpose/01-architect.md`) reshapes the in-memory table: each transposed column becomes one output row, with either an `/ARRAY` of per-row values or `/ID`-named per-row columns. It mirrors AGGREGATE in its build-and-swap mechanism, `Pending_Deferred` guard, and BY/SELECT/SAVE post-execution side effects. Several non-obvious behavioral decisions arose during design; the approved spec mechanism (§3.5, §3.8) was also inaccurate in three places, superseded by structural corrections C1–C3 in the architect doc. This ADR records the behavioral decisions. The mechanism corrections are AGGREGATE-derived and are documented in the architect doc rather than re-stated here.

**Decision:**
1. **Type-uniformity of the transposed set (error #8).** All columns in the transposed set must share a single type — all numeric or all character. A mixed set is rejected at pre-execution time before any table mutation. The requirement exists because each transposed-value column in the output must have a single declared type (`Col_Numeric` or `Col_String`), and the `/ARRAY` name's `$`-suffix rule (decision 5) cannot be satisfied for a mixed set.
2. **Union-of-IDs across BY blocks in first-encounter order; sparse cells → missing.** In the `/ID` case, the pre-scan walk accumulates the union of all `/ID` values across all blocks in first-encounter order (not sorted, not block-local). Every output block receives one column per union member; cells whose block does not contain a given ID value are left at their `Add_Output_Row`-initialised `Val_Missing`. Duplicate `/ID` values within a single block are error #6; the duplicate check is block-local, not cross-block (the same value legitimately appears in different blocks).
3. **Max-K array bound across all blocks; short blocks padded with missing.** In the `/ARRAY` case, K = `max(rows_in_block_i)` over the full pre-scan. All blocks produce `K` output columns even if they have fewer rows; short-block positions beyond the block's row count remain `Val_Missing`. This ensures the output schema is uniform across blocks.
4. **/ID column auto-exclusion from the transposed set.** When `/ID=var` is used, `var` is removed from the transposed-set candidates (KEEP∖DROP∖{ID}∖{BY}) regardless of whether it appears in `/KEEP` or `/DROP`. Its values become output column names rather than transposed data. This is silent (no warning) and is consistent with the AGGREGATE pattern of BY variables being excluded from aggregate targets.
5. **Error-on-output-collision (#10) and `$`-suffix matching rules (#7, #11).** Output-column collisions — where the `/NAME` column's name equals a BY variable name, the `/ARRAY` name equals a BY variable name, or an `/ID` union value equals a BY variable name or the `/NAME` column — are rejected at pre-execution time with a descriptive message. The `$`-suffix rules are: for `/ARRAY`, the array name must have a trailing `$` iff the transposed set is character (mismatch = error #11); for `/ID` values, if the transposed set is character the output column name is the ID value with `$` appended if not already present; if the transposed set is numeric, an ID value ending in `$` is rejected as error #7.
6. **Build mechanism follows AGGREGATE exactly (structural correction C3).** The spec (§3.5) prescribed `Dim_Array` for /ARRAY construction. `Dim_Array` writes the *live* data table and cannot participate in the `Initialize_Output_Table` → `Commit_Output_Table` build sequence. The correct approach (verified against landed `Execute_AGGREGATE`, commands.adb:845-848, 981-984, 1013) is: add individually-named `_X_(1)..(K)` columns via `Add_Output_Column`, then call `Register_Subscripted_Columns` after `Commit_Output_Table`. This auto-detects the `name(n)` pattern and registers the DIM array. For the `/ID` case the value columns are standalone (not `name(n)`), so `Register_Subscripted_Columns` is a harmless no-op — called unconditionally (same as AGGREGATE). A lexer keyword `Token_TRANSPOSE` is required (structural correction C2); the spec said "no lexer change" but `Parse_Statement` dispatches on `Tok.Kind`.

**Consequences:** TRANSPOSE is purely additive to sdata-core's public surface (`Transpose_Options` record type and `Execute_TRANSPOSE` procedure on `Commands`) — a patch bump (sdata-core 0.1.17 → 0.1.18), and the existing `^0.1.16` consumer floor still admits it, so no consumer-constraint change is needed. data-vandal does not use `Execute_TRANSPOSE` but builds and tests clean against the additive API. TRANSPOSE becomes a reserved keyword in sdata's lexer. The `Pending_Deferred` counter established by ADR-046 guards TRANSPOSE too (error #12).

---

### ADR-048: STATS command — transposed-AGGREGATE layout, always-replace + print/NOPRINT, shared group-scan helper
**Date:** 2026-06-30 | **Status:** Accepted

**Context:** STATS (design spec `doc/specs/2026-06-30-stats-command-design.md`) is SData's PROC MEANS analogue: per-variable summary statistics over the current table, grouped by the active BY. It is functionally a "transposed AGGREGATE" and reuses the same aggregate-function dispatch and build-and-swap machinery.

**Decision:**
1. **Result layout is row-per-(BY group × variable), columns = statistics.** Schema: BY vars + `_NAME_$` (the analysis-variable name, reusing TRANSPOSE's name-column convention) + one column per requested statistic. This is the transpose of AGGREGATE's row-per-group/column-per-clause layout and matches the PROC MEANS report orientation. `N`/`NMISS` columns are `Col_Integer`; the rest `Col_Numeric`.
2. **Always replace the in-memory table; print by default, suppress with `/NOPRINT`.** STATS uses the same build-and-swap path as AGGREGATE/TRANSPOSE (always replaces the table, flushes a pending SAVE, clears SELECT/BY). Printing is layered on top in the interpreter via the existing DISPLAY renderer; `/NOPRINT` suppresses only the printout, so the replacement always happens and `/NOPRINT` is never a no-op.
3. **Shared `Collect_Groups`/`Group_Values` helper (approach A).** The BY-group scan was factored out of `Execute_AGGREGATE` into private helpers in `sdata_core-commands.adb` and is now called by both AGGREGATE and STATS, eliminating scan duplication. AGGREGATE behavior is unchanged (verified by its integration tests).
4. **Statistics = the registered aggregate allow-list; default `N MIN MEAN MAX STD`.** `/STATS` names are validated with `Evaluator.Is_Aggregate`; the character-input rule reuses `Aggregate_Metadata.Accepts_Character` (only `N`/`NMISS`). No stat-column renaming and no `/NAME=` override in v1 (YAGNI).
5. **Pending-deferred guard reuses the `Pending_Deferred` counter** established by ADR-046; STATS adds the next error in that lineage ("STATS: pending program statements exist; issue RUN or NEW first").
6. **Empty or fully-filtered input yields zero output rows**, consistent with AGGREGATE (the transposed-AGGREGATE layout inherits AGGREGATE's group-scan semantics: no groups → no rows). The original spec's aspirational wording about an "N=0 row" was superseded by the as-built behaviour, which the spec's own fallback clause ("match AGGREGATE") blesses.

**Consequences:** STATS is purely additive to sdata-core's public surface (`Stats_Options` + `Execute_STATS` on `Commands`) — a patch bump (sdata-core 0.1.18 → 0.1.19); the `^0.1.16` consumer floor still admits it, so no consumer-constraint change. data-vandal does not use `Execute_STATS` but builds and tests clean against the additive API. STATS becomes a reserved keyword in sdata's lexer. sdata gets a minor bump (0.11.1 → 0.12.0) for the new command.

---

### ADR-049: TABLES command — print-only frequency/crosstabulation reporting
**Date:** 2026-07-03 | **Status:** Accepted

**Context:** TABLES (design spec `doc/specs/2026-07-03-tables-command-design.md`) is SData's PROC FREQ analogue: one-way, two-way, and multiway frequency tables with optional chi-square statistics. Unlike STATS, AGGREGATE, and TRANSPOSE — which all build-and-swap the in-memory table — TABLES produces a printed report and leaves all interpreter state unchanged.

**Decision:**
1. **Print-only reporting model.** TABLES renders a frequency/crosstabulation report and never mutates the table, PDV, pending SAVE, SELECT, or BY. This diverges deliberately from the build-and-swap model of STATS/AGGREGATE/TRANSPOSE: a crosstab is inherently two-dimensional and has no downstream consumer that would benefit from a table replacement. Leaving SELECT and BY intact also means TABLES can be re-run with different requests without re-issuing USE, BY, or SELECT.
2. **Multiway (3+ variables) always renders in list form.** A request of three or more crossing variables is always presented as one row per observed combination (the same list form as `/LIST` for two-way), never as stacked two-way grids. This avoids unreadable nested tables. `/LIST` extends list form to two-way tables on demand; for one-way tables it is a no-op; for three-or-more-way it is redundant-but-harmless (already list). List form changes presentation only and never affects whether statistics are computed.
3. **Statistics scope is Tier 2.5: the chi-square family plus Cramér's V.** Included: Pearson chi-square, Likelihood-Ratio (G²), Continuity-Adjusted (2×2 only, Yates), and Mantel-Haenszel chi-squares; Phi coefficient, Contingency Coefficient, and Cramér's V. All p-values use the existing `Chi_Square_CDF` function in `SData_Core.Statistics`. Deferred to a later feature: Fisher's exact test, ordinal/nominal measures of association with asymptotic standard errors (Gamma, Kendall's tau-b, etc.), and odds ratio/relative risk. The tier boundary is drawn at the chi-square family because it feeds already-existing statistical primitives at low incremental cost; the deferred items require separate multi-week effort.
4. **One-way `/CHISQ` = equal-proportions goodness-of-fit.** For a one-way table, `/CHISQ` tests whether observed frequencies are consistent with a uniform distribution across the k observed levels: statistic Σ(obs−exp)²/exp with exp = N/k, DF = k−1.
5. **Three-or-more-way `/CHISQ` is skipped with a warning.** When `/CHISQ` accompanies a 3+-variable request, a warning is emitted and no statistics are produced. Per-stratum chi-squares across multiway tables are deferred.
6. **SAS-faithful partial-missing exclusion (a decision refined during implementation).** For crossings, an observation is excluded from all counts if *any* crossing variable is missing, and the excluded count is reported as a `Frequency Missing = N` line beneath the table. Marginals and level sets are derived from jointly-present rows only (not from all rows unconditionally). This matches SAS PROC FREQ behavior. `/MISSING` promotes missing to an ordinary category, appearing as its own level in all counts; no separate `Frequency Missing` line is printed in that mode.
7. **Placement: pure contingency-table kernels additive in `SData_Core.Statistics`; counting and rendering sdata-only.** The `Chi_Square_Tests` and `Goodness_Of_Fit` functions are pure (no I/O, no table access) and belong with the other statistical routines in sdata-core where they can be unit-tested in the core harness against known references. TABLES counting, level enumeration, and report rendering are implemented in the sdata-only `Execute_Tables` subunit, since TABLES shares nothing with data-vandal.
8. **Pending-deferred guard.** TABLES raises before doing any work if deferred program statements are queued (the same `Pending_Deferred > 0` check used by STATS/AGGREGATE/TRANSPOSE), consistent with those commands' requirement that the report reflects fully-processed data.

**Consequences:** TABLES becomes a new reserved word in sdata's lexer. sdata-core 0.1.22 (additive — `Chi_Square_Tests` and `Goodness_Of_Fit` added to `SData_Core.Statistics`); the sdata floor is bumped from `^0.1.20` to `^0.1.22`. data-vandal does not use any TABLES API and builds clean against the additive sdata-core surface. The print-only model means TABLES can be invoked repeatedly within a session without disturbing SELECT, BY, or the table — a different usage pattern from STATS/AGGREGATE/TRANSPOSE, which consume and transform the table on each call.

---

### ADR-050: SAVE /DECIMALS and round-trip float output
**Date:** 2026-07-09 | **Status:** Accepted

**Context:** Design spec `doc/specs/2026-07-09-save-decimals-design.md` addresses two coupled
problems in how `SAVE` writes floating-point cells. First, a latent precision bug: all three
writers (CSV, ODF, OOXML) rendered finite floats with plain `Float'Image`, which GNAT limits
to 6 significant digits — already lossy for a 32-bit `Float`, which needs 9 significant digits
to round-trip (e.g. `123456.789` was silently stored as `123457`, even in spreadsheets, where
no space pressure justifies the loss). Second, there was no way to control saved precision at
`SAVE` time; `OPTIONS DIGITS` only affects console/PRINT output and is consulted by no writer.
The spec fixes both together: every writer always renders at round-trip precision by default,
and a new `/DECIMALS=N` option lets a user additionally request a specific decimal count, with
mechanics that deliberately differ between CSV and the two spreadsheet formats.

**Decision:**
1. **Per-format `/DECIMALS=N` semantics are deliberately asymmetric, not a shared code path.**
   `N` is a non-negative-integer count of decimal places (parse error otherwise: `/DECIMALS=
   requires a non-negative integer`). **CSV** rounds the stored text value to `N` places and
   strips trailing zeros (and a bare trailing `.`) — a genuine, variable-width data reduction,
   because the CSV cell text *is* the data and trailing zeros are pure redundancy. **ODF/OOXML**
   instead keep the full round-trip-precise value in the cell (`office:value` / `<v>`) and
   attach a *fixed* `N`-decimal display number-format (`<number:number-style>` /
   `styles.xml` `numFmt` + `cellXfs`, referenced via `s=` on each numeric cell), so cells
   always *show* exactly `N` decimals with no information at stake — the format's only job is
   aligned, consistent presentation. Only finite `Val_Numeric` cells are affected in any
   format; integer, character, missing, and `Inf`/`-Inf` cells are untouched. HELP, the man
   page, and design.md all state this asymmetry explicitly so a future change does not "fix"
   it into false symmetry.
2. **Round-trip-precision default is a bugfix that changes existing output bytes.** With no
   `/DECIMALS=`, all three writers now render finite floats at round-trip precision for the
   current numeric type (9 significant digits for 32-bit `Float`), trailing zeros trimmed,
   superseding the previous 6-digit `Float'Image` rendering. This is unconditional — it is not
   gated behind any option — so every existing `.csv`/`.ods`/`.xlsx` fixture containing a saved
   float shifted and had to be regenerated and manually reviewed (not blindly accepted) as part
   of implementation.
3. **Shared renderers, digit count fixed for the current 32-bit `Float`.** `Image_Round_Trip`
   and `Image_Fixed_Decimals` (`SData_Core.Values`) replace three independent `Float'Image`
   call sites with one implementation each writer calls. The round-trip search loop (`Aft` 1
   .. 17) and the exponential fallback (`Aft => 8, Exp => 2`, i.e. 9 significant digits) are
   fixed literal constants sized for 32-bit `Float`, which is what round-trips binary32; both
   renderers are also typed to `Float` throughout. Nothing here auto-derives from
   `Float'Digits`/`Float'Model_Mantissa` — see decision 5.
4. **Additive, defaulted-parameter plumbing for contract safety.** `Execute_SAVE` and
   `Open_Output` are public sdata-core API shared with data-vandal. `Decimals` is added as a
   single new **defaulted** trailing parameter (`Integer := -1`, meaning "no `/DECIMALS=`
   given"), stashed via a new `SData_Core.Config.Runtime` setter/getter alongside the existing
   `Save_DLM`/`Header`/`Charset` state. This keeps data-vandal source-compatible without any
   code change on its part, and keeps the older sdata tag pinned by sdata-core's
   `consumer-tests.yml` building against the new sdata-core unmodified — the same additive
   pattern established for AGGREGATE/TRANSPOSE/STATS/TABLES in prior ADRs.
5. **Platform-native (double) precision widening is out of scope, deferred to the planned
   design-vs-code audit.** design.md's Floating Point Numeric section prescribes
   architecture-dependent precision (64-bit → IEEE 754 double), but the implementation uses a
   plain 32-bit `Float` throughout. This feature targets round-trip fidelity of the *current*
   `Float` only; it does not attempt to close that pre-existing design/code conformance gap.
   Per decision 3, the renderers' digit counts are fixed constants and both renderers are typed
   to `Float`, not derived from the numeric type — so the deferred widening audit **must**
   revisit `Image_Round_Trip`/`Image_Fixed_Decimals` (both the significant-digit constants and
   the `Float` parameter type) when it widens the underlying numeric type to `Long_Float`;
   neither ODF nor OOXML constrains the stored value to 32-bit precision, so only the renderers
   (not the file formats) stand in the way.

**Consequences:** sdata-core gains an additive API surface (`Execute_SAVE`/`Open_Output`
`Decimals` parameter, `Runtime.Set_Save_Decimals`/`Save_Decimals`, `Image_Round_Trip`/
`Image_Fixed_Decimals` on `SData_Core.Values`) — patch bump 0.1.26 → 0.1.27. sdata gains the
`DECIMALS=` parser/AST plumbing (`sdata-parser.adb`, `Spec_Options`/`Stmt_SAVE` on
`sdata-ast.ads`) and the interpreter call-site wiring at both the single-target and
multi-target `SAVE` paths; the corresponding sdata minor bump (0.13.3 → 0.14.0) and
`sdata_core = "^0.1.27"` floor raise land with the release task that follows this docs change,
per the standard cross-crate release sequence (sdata-core first, then sdata, then data-vandal).
data-vandal's code is unaffected by the additive API, but because the round-trip-precision
default changes saved-float bytes unconditionally, its own expected-output fixtures containing
saved floats must be regenerated once it advances its `sdata-core` floor, and its `make check`
re-run before push, per the standing two-consumer local gate.

---

### ADR-051: Reject SORT/AGGREGATE/TRANSPOSE/STATS inside an active REPEAT block
**Date:** 2026-07-30 | **Status:** Superseded by [ADR-055](#adr-055-implicit-run-instead-of-rejecting-sortaggregatetransposestats-with-a-pending-program)

**Superseded 2026-08-03:** issue #70 reconsidered the reject *mechanism* below — it is
replaced by an implicit `RUN` (see ADR-055). The root-cause finding this ADR established
(these four commands could silently execute against a table their own pending body hadn't
populated yet) remains correct and is still cited by ADR-055; only the remedy changes.

**Context:** Issue #66 (split from sdata-core PR #101's review, the EAV disk-spill schema). `SORT`
placed between `REPEAT n` and its matching `RUN` executed immediately against `Data_Table`, but
the `REPEAT` body had not yet populated it — the sort silently no-op'd. `tests/sort_by.cmd` masked
this for years: its sample data (`VAL = RECNO()`) was already monotonic in generation order, so
"no sort happened" was indistinguishable from "sorted." `AGGREGATE`/`TRANSPOSE`/`STATS` have the
same latent gap, incidentally masked in the common case by their existing `Pending_Deferred > 0`
guard (which happens to be nonzero once at least one `LET`/`SET` is queued ahead of them in the
body) but not when the Immediate command is the very first statement after `REPEAT n`.

**Decision:**
1. **Reuse the existing `Repeat_Active` flag** (`SData_Core.Config.Runtime`) as the guard
   condition, rather than introducing new interpreter state. Verified against the source: it is
   set `True` by `Execute_REPEAT (Count)` when `Count > 0`
   (`sdata_core-config-runtime-internal.adb`), and cleared `False` only by `Commit_Step`
   (`sdata-interpreter.adb`), which runs after the matching `RUN` executes the deferred body and
   commits the table — i.e. it is exactly coextensive with "between `REPEAT n` and its matching
   `RUN`."
2. **Guard once, at the shared `Execute_Statement` dispatch point**, not by duplicating a check at
   each of the batch `Execute` and REPL `Run_REPL` call sites. Tracing both confirmed they already
   funnel every non-deferred, non-`RUN` statement through the same `Execute_Statement` procedure —
   one guard there covers batch and interactive mode identically by construction, with no second
   code path to keep in sync (the class of drift risk CLAUDE.md already flags for HELP/man/design.md).
3. **Gate exactly `Stmt_SORT | Stmt_AGGREGATE | Stmt_TRANSPOSE | Stmt_STATS`** — the Immediate-tier
   commands that read or replace `Data_Table` row content. Every other Immediate-tier command
   (`OPTIONS`, `HELP`, `DIGITS`, `ECHO`, `RSEED`, `SYSTEM`, `NAMES`, `LIST`, `DISPLAY`, `FPATH`,
   `KEEP`/`DROP`/`RENAME`, `ARRAY`/`DIM`, `HOLD`/`UNHOLD`, `SUBMIT`, `OUTPUT`) is unaffected and
   remains legal mid-body. `Stmt_TABLES` is dispatched the same way but was found, during this
   design pass, to be missing from `Is_Immediate` entirely — a separate, REPL-only dispatch-routing
   bug (queued via `Add_To_Active_Program` instead of executed immediately, then silently dropped by
   `process_one_record.adb`'s per-record whitelist) unrelated to `Repeat_Active`. Deliberately left
   out of this fix and filed separately (issue #68) rather than folded in, matching how #66/#67 split
   from #64's review.
4. **The new check runs *before* each command's existing `Pending_Deferred` guard**, not after.
   `Repeat_Active` is the more specific condition and, in practice, the more common one (a real
   `REPEAT` body almost always has a `LET`/`SET` queued ahead of the Immediate command, so without
   this ordering the misleading "pending program statements exist" message — which reads as "you
   have stray queued statements," not "you are structurally inside an unrun data-generation step" —
   would be what most users actually see). Placing the guard directly in `Execute_Statement`, ahead
   of the call into `Execute_Aggregate`/`Execute_Transpose`/`Execute_Stats`, gets this ordering for
   free rather than requiring it to be threaded through each handler.
5. **Message names the actual cause** rather than reusing the `Pending_Deferred` text verbatim:
   `"<CMD>: cannot run before RUN inside a REPEAT n data-generation step; issue RUN or NEW first"`.
   "REPEAT n data-generation step," not bare "REPEAT block," to avoid confusion with the unrelated
   `REPEAT`/`UNTIL` control-flow loop this same language already has an on-record ambiguity finding
   about (issue #57; design.md §5.5's note on the same distinction).
6. **`tests/sort_by.cmd` is rewritten, not merely re-asserted.** Its pre-fix expected output already
   reflected the no-op behavior (unsorted, generation-order data) the issue proved wrong. The rewrite
   moves `SORT`/`BY` to after the generating `RUN` (mirroring `tests/spill_sort_test.cmd`'s working
   pattern), and required two further adjustments discovered only by actually running the interpreter
   rather than hand-deriving the new expected output: block 1's `VAL` formula was changed from
   `RECNO()` to `7 - RECNO()` so the sort's effect is empirically visible (the original formula was
   already monotonic — the same coincidence that hid the bug for years); block 2's `SET VAL` became
   `LET VAL`, since a `SET` temporary variable does not survive past the `RUN` it was computed in,
   and the rewritten structure now needs `VAL` to persist into a second, later `RUN`. A side effect of
   moving `BY G` out from before `RUN`: `Group_Flags` (`sdata-interpreter.adb`) special-cases
   `Row_Count = 0` (true throughout a from-scratch `REPEAT` body) as "all generated records form one
   implicit group," so the pre-fix test's cumulative-sum column never actually reset between BY
   groups (10, 15, 21 continuing across the G=0/G=1 boundary); with `BY G` now evaluated after the
   table is committed, groups reset correctly (1, 3, 6 then 4, 9, 15) — the more obviously correct
   behavior, and a second latent symptom of the same root design gap this ADR fixes, not a separate
   bug. New tests (`tests/repeat_sort_reject.cmd`, `tests/repeat_aggregate_reject.cmd`) specifically
   exercise the zero-pending-statements case (the actual net-new coverage — with statements already
   pending, `Pending_Deferred` alone already caught it), plus `tests/repeat_zero_sort_ok.cmd`
   confirming `REPEAT 0` (the documented cancel form) does not trip the new guard.

**Consequences:** Purely additive to the error surface — no existing test relied on any of these
four commands succeeding inside an active `REPEAT` body (`make check`: 352 → 355, all green). No
sdata-core API change: `Repeat_Active` and `Execute_REPEAT` are shared plumbing, but `data-vandal`
has no `REPEAT` statement or `Is_Immediate`-equivalent dispatcher of its own (confirmed: zero
matches in its source), so this fix is sdata-only, no version floor change, no cross-crate
coordination. Companion issue #67 (tighten `SORT`'s `Column_Count > 0` undefined-variable bypass)
can now proceed, since that bypass has no remaining legitimate case to protect once this lands.
Issue #68 (the `Stmt_TABLES`/`Is_Immediate` REPL dispatch gap found during design) is filed as a
separate follow-up, out of scope here.

---

### ADR-052: Validate SORT/BY variable names unconditionally, not gated on Column_Count > 0
**Date:** 2026-07-30 | **Status:** Accepted

**Context:** Issue #67, split from the same sdata-core PR #101 review as #66 and explicitly
sequenced after it. `SORT`/`BY`'s undefined-variable guard (added for issue #50) only validated
named variables against `Has_Column` when `SData_Core.Table.Column_Count > 0`; when
`Column_Count = 0` (reachable independently of `Row_Count`), validation was skipped and a name
that was never a column silently succeeded as a no-op instead of erroring. The bypass's original
rationale was to allow a "legitimate forward reference" — naming a variable a later `LET` in the
same `REPEAT` body would create.

**Decision:**
1. **Remove the `Column_Count > 0` condition entirely for both `SORT` and `BY`**
   (`src/sdata-interpreter-execute_declarative.adb`); the `Has_Column` validation loop runs
   unconditionally whenever named variables are given.
2. **The "forward reference" rationale was never actually reachable, confirmed by reading
   `Stmt_REPEAT`'s handler, not just tested.** `REPEAT n` (any `n`, including the `REPEAT 0`
   cancel form) unconditionally calls `SData_Core.Table.Clear` before its body is parsed —
   `Column_Count = 0` is guaranteed inside a from-scratch `REPEAT` body, not merely common.
   Combined with `LET`/`SET` being deferred (they only execute at the body's `RUN`, regardless
   of textual position) and `BY` being declarative (dispatches immediately as the body is
   parsed), no ordering of `BY` relative to a same-body `LET` can ever make the named column
   exist at `BY`'s own execution time — confirmed empirically: `REPEAT 6 / LET G=... / BY G`
   (LET textually *before* BY) still raises `undefined variable "G"`, identically to a genuine
   typo, once the fix is applied. For `SORT` specifically, #66 (ADR-051) independently closes
   the same window from the other direction: `SORT` can no longer execute at all while
   `Repeat_Active`, so by the time its guard runs there is no pending body to forward-reference
   into. The bypass protected nothing observable in either command, in any configuration.
3. **No sdata-core change.** This is sdata's own pre-validation catching an undefined name
   before it reaches sdata-core's `Sorting.Sort` at all — the same architectural pattern as #66.
   `tests/spill_sort_undef_var_test.cmd` (added alongside sdata-core PR #101, the EAV disk-spill
   schema) exercised a third, independent trigger for `Column_Count = 0` — `DROP`-ing every
   column of a table with real spilled rows, not `REPEAT` — reaching sdata-core's disk-spill
   `Sorting.Sort` rebuild tolerating an unresolvable sort key (`Backing_Store.Col_Id` returning
   0). That sdata-core tolerance mechanism is untouched and remains defensive; it is simply no
   longer *reached* via this specific trigger, since sdata's guard now catches the undefined
   name first. The test is rewritten to assert the corrected error instead of the old
   tolerance, with its header comment updated to explain the new reachability.
4. **Design.md and the man page and HELP text previously documented the exemption as
   intentional** ("When the table has columns, each named variable must be..."), not merely as
   an implementation artifact — found while auditing the user-facing surface for this change,
   per this project's three-reference sync convention. All three corrected to state the
   requirement unconditionally, matching #50's original design intent
   (`doc/design.md`'s SORT/BY reference rows never actually meant to carve out this exemption;
   it was an implementation-only detail that had leaked into the docs).

**Consequences:** Purely additive to the error surface. No sdata-core change, no version floor
change, no cross-crate coordination. `tests/repeat_zero_sort_ok.cmd` (an ADR-051 test) is renamed
to `tests/repeat_zero_aggregate_ok.cmd` and its command changed from `SORT X` to `AGGREGATE
N=N()`: `REPEAT` (any count) always clears the table, so no name `SORT` could reference after
`REPEAT 0` would still exist once this fix landed, making `SORT` unable to isolate ADR-051's
`Repeat_Active` boundary from this ADR's now-unconditional undefined-variable guard;
`AGGREGATE N=N()` takes no input-column argument and cleanly tests only the ADR-051 boundary.
New tests: `tests/by_repeat_body_undefined.cmd` (BY inside a REPEAT body on a same-body,
not-yet-run `LET` target, confirming the "backward reference" case errors identically to a
typo). `make check`: 355 → 356.

### ADR-053: REPL test coverage via a Makefile `.repl` marker convention, not a Run_REPL refactor
**Date:** 2026-08-03 | **Status:** Accepted

**Context:** Issue #69, found during #68's design pass. All `tests/*.cmd` integration tests run via
`./bin/sdata tests/<name>.cmd` (a filename argument), which selects **batch mode**
(`SData.Interpreter.Execute`) exclusively. `Run_REPL` (`src/sdata_main.adb`) — reached only when
**no** filename is given, reading from stdin instead — was never exercised by `make check` at any
level. This is exactly why #68 (`Stmt_TABLES` missing from `Is_Immediate`) went unnoticed: nothing
in the automated suite could have caught it, since nothing in the suite ever called `Run_REPL`.
#69 raised three options without evaluating them in depth: (1) extend the test harness to pipe
stdin and strip `Run_REPL`'s version-string-bearing startup banner before diffing; (2) refactor
`Run_REPL`'s dispatch loop into a small, separately-testable public procedure callable by both
`Run_REPL` and a unit test; (3) accept the gap and rely on targeted unit tests per regression, as
#68 did for `Is_Immediate`.

**Decision:** Option 1. A `tests/<name>.repl` marker file, placed alongside a `tests/<name>.cmd`
script, tells `make check`'s existing test loop to invoke `./bin/sdata $EXTRA_FLAGS < tests/<name>.cmd`
(piped stdin, no filename argument) instead of `./bin/sdata $EXTRA_FLAGS tests/<name>.cmd` — this
alone is sufficient to select `Run_REPL` instead of batch mode; no source change to `Run_REPL`
itself is required. The fixed 3-line startup banner (which embeds `SData.Version.Version_Str`, not
suppressed by any existing flag including `-q`, confirmed empirically) is stripped from actual
output (`tail -n +4`) before the existing `diff -wu` comparison against `tests/expected/<name>.out`
runs, so expected files stay version-string-free and never need hand-editing on a version bump —
directly avoiding the maintenance trap #69 itself warned a naive REPL test would create.

Option 2 was rejected: extracting `Run_REPL`'s dispatch loop into a public, separately-testable
procedure is a real behavioral-preservation refactor (the loop's state — `Buffer`,
`Ended_With_Continuation`'s interaction with `Parser_Context`, the pager-flush points inside each
exception handler — is intertwined with the surrounding `Get_Line`/prompt loop) with its own risk of
introducing a regression in the exact code path being protected, for no coverage benefit over Option
1's zero-source-change approach. Option 3 was rejected as strictly weaker: it only re-guards
regressions after they ship (as #68's `IMM-01`/`IMM-02` unit tests now do for `Stmt_TABLES`
specifically), never testing the REPL's dispatch loop, buffering, or error-recovery behavior as a
whole; the actual `.cmd` scripts below prove Option 1 test the literal `Run_REPL` code path, not a
substitute.

**New tests** (all exercise genuinely REPL-only code paths, not just a REPL-mode restatement of an
existing batch test): `repl_dispatch_basic.cmd` (normal immediate/deferred/RUN dispatch through the
REPL loop); `repl_tables_immediate.cmd` (direct regression guard reproducing #68's exact shape — a
bare `TABLES` statement must produce output immediately, with no `RUN` in between; verified to
independently fail when `Stmt_TABLES` is removed from `Is_Immediate` again, confirming this closes
the actual gap #69 reports, not just adds inert test files); `repl_continuation.cmd` (the
trailing-comma line-continuation buffer, which only exists in `Run_REPL`'s incremental
`Get_Line`/`Parse_Program` loop — batch mode parses the whole file at once and never distinguishes a
mid-file trailing comma from any other character); `repl_error_recovery.cmd` (a script error from an
Immediate-tier command mid-session resets the buffer and the REPL keeps accepting input afterward,
proving `Run_REPL`'s own exception handlers, not batch's `Execute`, recovered cleanly);
`repl_eof_no_quit.cmd` (reaching end-of-input without an explicit `QUIT`/`END` exercises the
`Ada.Text_IO.End_Error` handler, a distinct exit path from the `Stmt_QUIT`/`Stmt_END` dispatch
branch `repl_dispatch_basic.cmd` already covers).

**Consequences:** sdata-only, no sdata-core change (`Run_REPL` and the Makefile are both sdata-only
surfaces). No source change to `src/sdata_main.adb` at all — this ADR is a test-infrastructure
decision, not a behavioral one. `make check`: 357 → 362. The `.repl` marker convention generalizes:
any future REPL-specific behavior (e.g. a fix to `Insert_Point`/`Append_Mode` program-buffer editing,
issue #32) gets the same treatment — write the `.cmd` script normally, add an empty `tests/<name>.repl`
marker, and generate the expected output by running the actual binary once and stripping the banner.

### ADR-054: Resolve REPEAT/DELETE keyword overloading by renaming the low-usage side
**Date:** 2026-08-03 | **Status:** Accepted

**Context:** Issue #63, split from #57 item 2. `REPEAT` names two unrelated constructs: the
`REPEAT`/`UNTIL` post-test loop (design.md §5.3, inherited from the Bywater BASIC heritage this
project's spec defers to) and `REPEAT n`, sdata's own data-step record-count command (§5.5, §5.7).
`DELETE` names two unrelated constructs: the classic-BASIC line-editor command `DELETE n[-m]`
(removes program-buffer entries, REPL-only) and the SAS-DATA-step-style bare `DELETE` (marks the
current record for deletion, the meaning this project's own data-step model is built around). The
parser already disambiguated both pairs correctly by lookahead (a following newline/EOF/colon vs.
a numeric literal), and #57's docs pass had already added explicit "Note:" disambiguation to
design.md — nothing was actually broken. The issue's own framing declined to decide unilaterally:
"needs a deliberate decision on whether to rename one construct in each pair — a breaking
change — rather than deciding it incidentally."

**Decision:** Rename the *lower-usage* member of each pair, not the historically-inherited one, and
confirmed this choice with the user (rather than picking unilaterally) given usage data that cuts
against intuition:

- `REPEAT`/`UNTIL` loop → **`DO`/`UNTIL`** (mirrors this language's existing `WHILE`/`WEND`
  start/condition-bearing-end pairing style; `DO` was an unclaimed keyword).
- `DELETE n[-m]` (line editor) → **`REMOVE n[-m]`** (pairs naturally with the existing `INSERT`
  line-editor command; `REMOVE` was unclaimed).

**Usage data that drove the decision, not just intuition:** `REPEAT n` (data-step) appeared in 74
of 362 test scripts at decision time — the single most central idiom in the whole suite — versus
`REPEAT`/`UNTIL` (the loop) in exactly 1. Bare `DELETE` (record) appeared in 2 tests; `DELETE n[-m]`
(line editor) in 0 committed tests (REPL-only, untestable before ADR-053/issue #69 built the
`.repl` marker convention). The historically "standard" BASIC-heritage meaning is the *low-usage*
side in both pairs; sdata's own domain-specific invention is the dominant, load-bearing one.
Renaming the dominant side to satisfy a near-unused legacy construct would have touched ~20% of the
test suite and every user script using the core data-generation idiom, for comparatively little
benefit — renaming the low-usage side costs one test each.

Both `Token_REPEAT` and `Token_DELETE` retain their original grammar-disambiguation *shape* even
though the ambiguity is gone: `Token_REPEAT` now unconditionally parses a following numeric
literal (`REPEAT n`); `Token_DELETE` now unconditionally takes no argument (bare record-delete).
A bare `REPEAT` (no count) or a `DELETE n` (numeric argument) — both pre-#63 spellings — now raise
a clean, migration-specific `Script_Error` (`"REPEAT requires a record count...; for a
REPEAT/UNTIL-style loop, use DO/UNTIL instead"` / `"DELETE takes no argument...; to remove
program-buffer line(s), use REMOVE n[-m] instead"`) rather than an unguarded `Natural'Value`
`CONSTRAINT_ERROR` crash — this migration hint matters more here than at most other numeric-argument
parse sites in this file, since it is exactly the mistake a pre-#63 script is most likely to make.

Internal identifiers renamed alongside the keywords, for consistency (not just user-facing
syntax): `Stmt_LOOP_REPEAT` → `Stmt_LOOP_DO`, `Stmt_PROGRAM_DELETE` → `Stmt_PROGRAM_REMOVE`, the
AST record fields `Repeat_Body` → `Do_Body` and `Delete_From`/`Delete_To` →
`Remove_From`/`Remove_To`, and `Execute_Program_Delete` → `Execute_Program_Remove`. Leaving these
named after the old keyword would recreate a diluted form of the exact reader-confusion this ADR
resolves.

**Consequences:** sdata-only (this whole feature family — lexer, AST, parser, REPL line editor —
lives in this crate, confirmed no sdata-core or data-vandal involvement). Breaking change,
acknowledged: `tests/repeat_until_test.cmd` renamed to `tests/do_until_test.cmd` and rewritten to
`DO`/`UNTIL`; `tests/interpreter_unit_test.adb`'s IC-20/IC-21 (loop) and IN-12/13/14/19
(line-editor) rewritten to the new spellings. New tests: `tests/repl_remove_lines.cmd` (a `.repl`
marker test, ADR-053's convention — the first genuine end-to-end REPL integration test for the
INSERT/LIST/REMOVE program-buffer-editor family, previously only unit-tested via direct procedure
calls); `tests/repeat_bare_rejected.cmd` and `tests/delete_numeric_rejected.cmd` (confirm the old
spellings now fail cleanly, exit 1, with the migration-hint message). HELP (`sdata-help.adb`:
`Help_REPEAT`/new `Help_DO`, `Help_DELETE`/new `Help_REMOVE`, the command index and execution-tier
summary lines), man page, and design.md (§5.3, §5.4, §5.5, §5.7, §5.8, the command-reference table)
all updated per the three-reference sync rule; `tests/expected/help_all.out` and
`tests/expected/help_index.out` regenerated. `make check`: 362 → 365. Closes jlries61/sdata#63.

### ADR-055: Implicit RUN instead of rejecting SORT/AGGREGATE/TRANSPOSE/STATS with a pending program
**Date:** 2026-08-03 | **Status:** Accepted (supersedes [ADR-051](#adr-051-reject-sortaggregatetransposestats-inside-an-active-repeat-block)'s reject mechanism)

**Context:** Issue #70. ADR-051 rejects `SORT`/`AGGREGATE`/`TRANSPOSE`/`STATS` outright when a
deferred program is pending — either un-run statements queued since the last `RUN`
(`Pending_Deferred > 0`) or an open `REPEAT n` body (`Repeat_Active`) — because they would
otherwise silently read a table that program hasn't populated yet. User's own framing: *"This
strikes me as more intuitive than simply making those commands fail."* Confirmed decisions from
prior exploration (2026-07-30, embedded in the issue): the implicit `RUN` always announces itself
with the identical `"RUN complete. N records and M variables processed."` message an explicit
`RUN` prints; no `OPTIONS` toggle (replaces the reject outright — zero external users of that
behavior existed); applies uniformly to all four commands; both trigger conditions consolidate
into one shared check.

**Decision — one injection point, not two.** The issue's own prior exploration assumed batch mode
and REPL needed separate injection points (REPL supposedly having "zero visibility" into
interpreter internals). Re-reading the current source found this premise wrong:
`SData.Interpreter.Execute (Prog : Statement_Access)` is a single public procedure that *both*
modes call through — REPL's `Run_REPL` (`sdata_main.adb`) dispatches every Immediate-tier statement
that isn't `RUN`/`QUIT`/`END` through this exact same `Execute`, just with a singleton `Prog`. A new
local procedure `Ensure_Pending_Flushed`, declared inside `Execute` (so it has access to that
call's own `Step_Start`/`Current`), is invoked from one new `elsif` branch checking
`Current.Kind in Stmt_SORT | Stmt_AGGREGATE | Stmt_TRANSPOSE | Stmt_STATS and then
(Pending_Deferred > 0 or else Repeat_Active)`, placed ahead of `Execute_Statement`'s normal
dispatch for these four kinds. `Reject_If_Repeat_Active` and the three individual
`Pending_Deferred > 0` guards inside `Execute_Aggregate`/`Execute_Transpose`/`Execute_Stats` are
deleted entirely (`SORT` never had one of its own).

`Ensure_Pending_Flushed` still needs two flush mechanisms, since batch and REPL represent "the
pending program" via genuinely different structures: `Active_Program_Vec` (REPL's queue,
populated only by `Add_To_Active_Program`, which only `Run_REPL` ever calls — batch never touches
it) vs. the `Step_Start..Current` slice of *this specific call's own* list walk (correct for batch's
whole-file walk, but for REPL's singleton-statement calls this range is always empty, since any
real pending statement lives in `Active_Program_Vec`, invisible to it). A batch-style flush when
`Active_Program_Vec` is non-empty would silently skip the real pending statement — reproducing the
exact bug this feature fixes — so the mechanism is chosen by `Active_Program_Vec.Is_Empty`: non-empty
→ call the already-public `Run_Active_Program` (no new query needed, contrary to the prior
exploration's assumption); empty → replicate the existing `Stmt_RUN` branch's
`Analyze_Deferred`/`Run_One_Step` call using `Current` as the boundary (not `Current.Next`, since
`Current` itself still needs its own `Execute_Statement` dispatch afterward). Verified
mechanically: `Process_One_Record`'s walk (`while Iter /= null and then Iter /= Boundary loop`) and
`Analyze_Deferred`'s guard (`if Start = null or else Start = Boundary then`) both treat
`Start = Boundary` as empty regardless of whether the shared value is null or a real node, so
`Run_One_Step (Current, Current)` — the empty-`REPEAT`-body case — behaves identically to
`Run_One_Step (null, null)`: it runs `Repeat_Count` records through zero deferred statements,
matching a from-scratch empty body. **Verified concretely, not just reasoned through**: reverted the
`Active_Program_Vec.Is_Empty` check to `if False then` and confirmed a REPL scenario (`LET Z=99`
typed, then `SORT Z`) broke exactly as predicted (`Z` silently never created, `SORT Z` then raised
"undefined variable"), then restored it and confirmed the same scenario works correctly.

**A second, related bug found and fixed in the same change: SAVE association.** A registered `SAVE`
is one-shot — sdata-core's `Flush_Pending_Save` calls `Clear_Pending_Save` immediately after
writing, so it is consumed by whichever commit point reaches it first (matches
`tests/aggregate_save_flush.cmd`'s own pre-existing comment, "a pending SAVE is written and then
cleared" — previously misread during investigation as evidence of a *persistent*, re-written-every-commit
model, which is not what the code does). Without a fix, an implicit `RUN` becomes a *new* commit
point that didn't exist under ADR-051 (these four commands previously either ran with `SAVE`
already flushed by a prior explicit `RUN`, or were rejected before reaching one) and silently
steals the one-shot write — confirmed empirically: `REPEAT 4 / LET X=RECNO / SAVE "f.csv" /
AGGREGATE TOTAL=SUM(X)` (no explicit `RUN`) wrote the *pre-aggregate* per-record data to `f.csv`,
not the aggregated `TOTAL`, and the identical pattern reproduced for `SORT` (writes the pre-sort
order). Fixed with a small additive **sdata-core** change: `SData_Core.Commands.Execute_Commit_Step`
gained an optional `Flush_Save : Boolean := True` parameter (default preserves existing behavior for
every other call site) so the flush can be skipped for exactly one commit. sdata's own
`Ensure_Pending_Flushed` sets a new package-body flag, `Suppress_Next_Save_Flush`, immediately
before performing its flush (covers both the direct `Run_One_Step` path and the path inside
`Run_Active_Program`'s own nested `Execute` call, since the flag is package-level and shared across
nesting depth); `Commit_Step` consumes-and-resets it, passing `Flush_Save => False` through for that
one commit only. This lets the *triggering command's own* existing save-flush step — `SORT`'s direct
`Execute_Commit_Step` call, or `AGGREGATE`/`TRANSPOSE`/`STATS`'s `Commit_Reshaped_Table` (a separate,
inline check-and-flush that does not go through `Execute_Commit_Step` at all) — be the one that
actually consumes the one-shot `SAVE`, with the correct post-command result. No sdata-core signature
change was needed beyond the one additive parameter; no new public `Flush_Pending_Save` exposure was
needed either, since all four commands already had their own flush step once traced fully (an
earlier, incomplete trace of `SORT`'s code had missed its `Execute_Commit_Step` call in
`sdata-interpreter-execute_declarative.adb`, which is in sdata, not sdata-core — that led to a
wrong initial assumption that `SORT` needed a new flush step added; it did not).

**Rejected alternative**: unifying batch's `Step_Start` tracking onto `Active_Program_Vec`-style
accumulation, so there is only one representation of "the pending program." Rejected as a real
rearchitecture of how batch mode walks a script file, out of scope for this feature (the original
exploration already recorded and rejected this; re-confirmed here).

**Test plan.** Existing tests asserting the old reject behavior rewritten to assert success instead:
`tests/repeat_sort_reject.cmd` → `tests/repeat_sort_implicit_run_undefined.cmd` (implicit RUN then
ADR-052's undefined-variable error, since the REPEAT body is empty); `tests/repeat_aggregate_reject.cmd`
→ `tests/repeat_aggregate_implicit_run.cmd` (implicit RUN then success, since `N()` needs no input
column — the two together show the trigger is orthogonal to whether the triggering command then
succeeds); `tests/aggregate_buffer_nonempty.cmd` → `tests/aggregate_pending_implicit_run.cmd`,
`tests/stats_pending_error.cmd` → `tests/stats_pending_implicit_run.cmd`,
`tests/transpose_buffer_nonempty.cmd` → `tests/transpose_pending_implicit_run.cmd` (the original,
pre-#66 `Pending_Deferred`-only guards, predating `REPEAT` involvement entirely); `tests/aggregate_submit_pending.cmd`
kept (still valid: `SUBMIT`'s save/restore of `Pending_Deferred` around its nested `Execute` call
means the outer `LET` is still pending after the sub-script's own `RUN` returns, now triggering a
second, correct implicit RUN before `AGGREGATE`, rather than an error). `tests/repeat_zero_aggregate_ok.cmd`
and `tests/by_repeat_body_undefined.cmd` needed no changes (the former's assertion — no active
`REPEAT` after `REPEAT 0`, so neither trigger fires — is still exactly correct; the latter never
invokes any of the four commands at all). `tests/sort_by.cmd` needed no changes either (both blocks
already place `SORT`/`BY` after an explicit `RUN`, so neither trigger condition holds). New tests:
`tests/pending_sort_implicit_run.cmd` (the one `Pending_Deferred`-alone case not already covered —
`SORT` never had its own individual guard before this ADR); `tests/repeat_transpose_implicit_run_empty.cmd`
/ `tests/repeat_stats_implicit_run_empty.cmd` (`Repeat_Active`-alone for the two commands not
covered by the renamed reject tests); `tests/repl_implicit_run_sort.cmd` (a `.repl` marker test per
ADR-053 — the one test that actually discriminates a correct implementation from a naive one, per
the verification described above); `tests/repeat_save_implicit_run.cmd` and
`tests/repl_implicit_run_save.cmd` (`.repl`, covering the `Run_Active_Program` flush path
specifically) for the SAVE-association fix, both re-loading the saved file via `USE`+`DISPLAY` so
`make check`'s stdout-diff can verify content (this project's test harness does not diff produced
CSV files directly).

**Consequences:** Cross-crate — this is the first sdata-only feature in the #66/#67/#68/#70 lineage
to also require an sdata-core change, once the SAVE-association bug was found. sdata-core:
`Execute_Commit_Step` gains the additive `Flush_Save` parameter (`docs/api/reference.html`
regenerated per sdata-core's own convention for public `.ads` changes); no version-floor bump
needed in either consumer (additive, matches the STATS/TRANSPOSE precedent). sdata:
`Reject_If_Repeat_Active` deleted; `Suppress_Next_Save_Flush` added; `design.md` §5.7 fully rewritten
(implicit-RUN semantics plus the SAVE-association note); HELP (`Help_SORT`/`Help_AGGREGATE`/
`Help_TRANSPOSE`/`Help_STATS`) and the man page updated to match, per the three-reference sync rule.
`make check`: 365 → 371 (6 net new: `pending_sort_implicit_run`, `repeat_transpose_implicit_run_empty`,
`repeat_stats_implicit_run_empty`, `repl_implicit_run_sort`, `repeat_save_implicit_run`,
`repl_implicit_run_save`; the renamed reject/pending tests are not net-new). Closes jlries61/sdata#70.

### ADR-056: Declarative statement inside FOR/WHILE/DO-UNTIL: warn once per occurrence, don't reject
**Date:** 2026-08-05 | **Status:** Accepted

**Context:** Design-vs-implementation audit finding P15
(`.ssd/audits/2026-08-03-design-vs-implementation/report.md`). §5.4 stated flatly that Declarative
statements "May not appear in FOR, WHILE, or DO/UNTIL blocks," listing `USE, SAVE, KEEP, DROP, BY,
DIM, ARRAY, DIGITS, OPTIONS` as examples. Testing three genuinely Declarative-tier commands (`KEEP`,
`SAVE`, `BY`, verified via their own `HELP` text) inside a `FOR` loop inside a `REPEAT` body found no
rejection at all — the statement just ran in place, same as any Deferred statement. No enforcement
code for this restriction was ever found in the source (confirmed by grep across the interpreter);
whether it was stale documentation or a missing check was left for a decision, same posture as P8
before its own won't-fix resolution.

**Decision (user's framing, verbatim in spirit):** *"I'm not sure how good an idea it is to put
declarative statements inside of a loop, but at least in theory, it is not a syntax error. At most,
it is confusing and thus warrants a warning."* — permit it, don't reject it, but surface a warning so
the behavior (the statement takes effect once, not per iteration) isn't silently confusing.

**Which statements trigger the warning.** Cross-checking design.md's own §5.4 prose list, its §7.1
Commands reference table's `Type` column, and `sdata-help.adb`'s per-command `"Execution: ..."` lines
found the three sources mutually disagree on several rows (`OPTIONS`, `RSEED`, `USE`, `ECHO`,
`RENAME`, `HOLD`/`UNHOLD` are classified differently by at least two of the three). Rather than
resolve that whole matrix here — a separate, larger audit-scale task, flagged as a residual — the
warning set uses exactly the sources the audit's own P15 finding already established as the tested
ground truth: each command's individual `HELP` `"Execution: Declarative"` line. That set is `ARRAY,
BY, DIM, DROP, FPATH, KEEP, REPEAT, SAVE, SELECT` (the row-filter form, not `SELECT CASE`) — nine
commands. Notably this *excludes* `USE` (its own `Help_USE` says `"Execution: Immediate"`, disagreeing
with the old §5.4 list) and *includes* `ARRAY`/`DIM` (confirmed Declarative by the same audit's
sibling finding P11's fix, sdata commit 9ad1858; `sdata-help.adb`'s general `Help_EXECUTION` overview topic still listed both under
"Deferred," an uncaught leftover from before that fix — corrected in the same change as a directly
adjacent, actively-contradictory piece of the same documentation surface, not scope creep).

**Mechanism — warn once per source occurrence, not once per iteration.** A `Step_Context.Loop_Depth`
counter (new field, `SData.Interpreter`) brackets `Stmt_WHILE`/`Stmt_FOR`/`Stmt_LOOP_DO` body
execution in `Execute_Control_Flow`, exception-safe (a `BREAK` mid-loop still decrements correctly).
`Execute_Statement` checks `Ctx.Loop_Depth > 0` for the nine-statement set and, if so, warns via
`Put_Line_Error` — but only once: a new `Warned_In_Loop : Boolean := False` field on the AST
`Statement` record itself (common to all statement kinds, before the `case Kind is` variant part) is
set the first time, so a `FOR I = 1 TO 1000` loop containing a `SAVE` warns exactly once, not a
thousand times. Verified: a 5-iteration loop produces exactly one warning line; the statement's own
effect (e.g. `KEEP`'s filtering) still applies normally each time it's reached, matching pre-existing
Declarative-tier semantics — nothing about *execution* changes, only that a warning is now surfaced.

**Documentation, three-reference sync plus the newly-found HELP self-contradiction:**
`design.md` §5.4 rewritten (permitted-with-warning, corrected Examples list to the nine above);
`sdata-help.adb`'s `Help_EXECUTION` topic corrected (`ARRAY`/`DIM` moved from its stale "Deferred"
list to "Declarative"; `USE` moved to "Immediate" to match `Help_USE`'s own line) and a note on the
new warning added; man page's "Declarative commands" section header gained a one-sentence note.
`tests/expected/help_all.out` regenerated and diffed before overwriting — confirmed only the intended
`HELP EXECUTION` block changed. The man page's full per-command section placement (e.g. whether `USE`'s
lengthy entry should move out of "Declarative commands") and design.md's §7.1 Commands table `Type`
mismatches (`OPTIONS`, `RSEED`, `ECHO`, `RENAME`, `HOLD`/`UNHOLD`) are **not** touched by this ADR —
flagged as a residual finding for a future pass, not fixed here.

**Consequences:** sdata-only (`sdata-ast.ads`, `sdata-interpreter.adb`,
`sdata-interpreter-execute_control_flow.adb`, `sdata-help.adb`, `design.md`, man page); no sdata-core
change, no cross-crate gate needed. New test `tests/declarative_in_loop_warn.cmd` (a 3-iteration `FOR`
loop containing `KEEP`, asserting exactly one warning line and correct final data). `make check`:
376 → 377, all green. Verified via revert: reverting the interpreter changes reproduces the exact
pre-fix silent behavior against the new test, then re-applying restores it.

### ADR-057: `.i`/`-.i`/`.n` typed literals construct Infinity/NaN directly; NaN's existing
"never survives arithmetic" policy is preserved, not relaxed

**Date:** 2026-08-08 | **Status:** Accepted

**Context:** Issue #71. design.md §2.4/§8.5 already documented IEEE 754 ±Infinity and NaN as
present in the value model — Infinity freely reachable via arithmetic overflow, NaN reachable
internally from `0/0` but deliberately never exposed as a stored value ("converted to an error
message... or a warning and a missing value"). §8.5 listed the missing piece as a noted-but-
unimplemented gap: a script could not *write* `.i`/`-.i`/`.n` as a literal to construct these
values directly, only encounter them as arithmetic side effects. That NaN policy is not just
prose — `SData_Core.Evaluator.Numeric_Result_Checked`, which every float `Add`/`Sub`/`Mul`/`Div`/
`Pow` result (and `SUM`/`MEAN`/`VAR`/`STD`) is routed through, raises a domain error the instant a
NaN would otherwise be returned. The open design question a `.n` literal raises: does adding a way
to *construct* NaN also mean *relaxing* that guard so NaN can flow through arithmetic?

**Decision:** No. `.i` and `.n` are new literal forms recognized by the lexer immediately after a
`.` and before falling back to the existing bare-`.` (missing value) or leading-dot-decimal (`.5`)
handling — disambiguated by requiring the `i`/`n` (either case) to be followed by a word boundary,
so `.info` still lexes exactly as before (`[Missing]["info" identifier]`, already a two-token parse
error in every context that matters, unchanged by this feature). `.i` constructs `SData_Core.
Values.Pos_Inf` (the existing public elaboration-time sentinel `Real'Last * 2.0`, already used
wherever Infinity must be produced at runtime); `-.i` needs no special construction — it falls out
for free from the existing generic unary-minus operator (`Op_Neg`, a raw sign-bit flip, not routed
through `Numeric_Result_Checked`) applied to `.i`. `.n` constructs a new public sentinel `NaN_Val`
(`Pos_Inf - Pos_Inf`, the canonical IEEE-754 NaN-producing operation, computed at runtime alongside
`Pos_Inf`/`Neg_Inf` for the same static-expression reason those two are). Both bypass
`Numeric_Result_Checked` entirely at construction (a literal is not an arithmetic *result*), but
`Numeric_Result_Checked` itself is **unchanged**: the moment a `.n` value is used in `+`, `-`, `*`,
`/`, or `**`, it raises the same friendly domain error `0/0` already does. `.n` therefore becomes a
usable *sentinel/placeholder* value — assignable, storable, printable (as `NaN`), and comparable
(`.n = .n` is `False`, correctly per IEEE 754) — without reopening whether NaN should silently
propagate through computation, which design.md deliberately decided against.

**Finding during design (systems-designer review), fixed in the same change, not deferred:**
`SData_Core.Evaluator.Aggregate_Fns.Handle_Min_Fn`/`Handle_Max_Fn` did not route through
`Numeric_Result_Checked` — they returned `Compute_Stats_Pass`'s raw running `Min_V`/`Max_V`
directly. `Compute_Stats_Pass` seeds that running value from the *first* non-missing value in a BY
group and updates it only via a plain `<`/`>` comparison; under IEEE 754 every comparison against
NaN is `False`, so a NaN as the first value in a group used to freeze `Min_V`/`Max_V` at NaN for
the rest of the group with no later value ever able to replace it, and `MIN()`/`MAX()` would then
silently return that NaN with **no error** — exactly the failure shape design.md says NaN must
never take. This was unreachable before this feature (NaN couldn't survive to be stored at all);
`.n` makes the precondition reachable for the first time. Fixed by wrapping both functions' return
in `Numeric_Result_Checked`, identical to the pattern `Handle_Sum`/`Handle_Mean` already use — a
no-op for every NaN-free group, and the same domain error for a NaN-poisoned one.

**Finding during implementation, fixed in the same change:** `sdata-parser.adb`'s `REMOVE n[-m]`
line-editor command unconditionally called `Real'Value` on the token following `REMOVE` (and, for
the range form, following `-`), assuming it was always `Token_Numeric_Literal`. `.i`/`.n` are new,
distinct token kinds that carry no text (constructed via arithmetic, not string parsing — see
below for why), so `REMOVE .i` or `REMOVE 1-.n` used to reach `Real'Value` on an empty string and
raise an uncaught `Constraint_Error` — an "Internal error"-shaped crash, not the clean, descriptive,
corrective-action error design.md §8 requires for every error condition. Fixed with an explicit
`Token_Kind` check ahead of both `Real'Value` calls, raising a clean `Script_Error` naming the
problem instead. A systematic grep of every `Real'Value` call site in `sdata-parser.adb` confirmed
these were the only two unguarded sites; sibling numeric-argument commands (`INSERT`, `FOR`/`STEP`)
either already type-check before consuming the token or compose through the general expression
parser (where `Op_Neg` already handles `-.i` safely), so no other site needed a change.

**Token representation:** two new `Token_Kind` members per lexer (`Token_Infinity`/`Token_NaN` in
sdata's own lexer; `TK_Infinity`/`TK_NaN` in sdata-core's private `Parse_Expression` mini-lexer,
additive, not exported) rather than reusing `Token_Numeric_Literal` with sentinel text consumed via
`Real'Value("Inf")`/`Real'Value("NaN")` — GNAT-specific special-value string parsing is unverified
in this codebase and compiler/version-dependent, whereas the arithmetic-construction pattern above
is already proven safe by this project's own `Pos_Inf`/`Neg_Inf` elaboration code.

**Three-repo parity, same shape as the `^`/`**` operator-parity fix (ADR — see the archived
`caret-power-operator-fix` workstream, issue #65):** sdata's own lexer/parser (LET/IF/etc.);
sdata-core's shared `Parse_Expression` mini-lexer (SELECT filter expressions in both sdata and
data-vandal go through this); and data-vandal's own independent lexer, which needed the identical
`.i`/`.n` recognition **and** a `Token_To_String` entry rendering them back as `".i"`/`".n"` — data-
vandal's `Collect_Select_Filter_Text` reconstructs a SELECT filter's text from its own lexer's
tokens (space-joined) before handing it to sdata-core's `Parse_Expression`; without an explicit
`Token_To_String` arm these two token kinds (which carry no raw text) would round-trip as an empty
string, silently dropping the literal from the reconstructed filter — the same corruption class the
`^`/`**` fix found and fixed for data-vandal's dropped `^` character. Caught and fixed in this
change via `tests/select_infinity_nan.cmd` (data-vandal), not discovered as a follow-up "bonus
finding" the way the `^`/`**` fix's data-vandal bug was.

**Rendering:** `SData_Core.Values.To_String`/`To_String_Formatted`/`Image_Round_Trip` already
special-cased `Is_Inf` (`"Inf"`/`"-Inf"`) but had no `Is_NaN` branch — a stored NaN fell through to
raw `Real'Image`, GNAT-implementation-defined text, inconsistent with the `Inf`/`-Inf` convention.
New public `SData_Core.Values.Is_NaN` (mirrors `Is_Inf`) and an explicit `"NaN"` branch added to
all three functions (and `Image_Fixed_Decimals`), checked ahead of the sign-based `Is_Inf` branch
since NaN's sign bit is not meaningful. CSV output delegates to `To_String`, so this covers CSV
round-tripping too; no separate `file_io` change needed (confirmed no independent float-formatting
path there).

**Consequences:** Easier — the literal is additive and small; `Numeric_Result_Checked` and every
arithmetic operator body are untouched. Harder — a `.n` value used inside AGGREGATE/STATS/SORT or
any expression that sums, compares-for-ordering, or otherwise computes over it surfaces a domain
error at that point, not at the literal's construction site; this is correct and matches `0/0`'s
existing behavior, verified by `tests/aggregate_min_max_nan_first.cmd` and `tests/
infinity_nan_arithmetic_error.cmd`. Give up — no "NaN propagates silently through computation"
mode in this iteration; a future issue wanting that is a deliberate, separately-ADR'd policy
reversal, not a side effect of this literal-syntax addition. SORT's comparison stability with a
stored NaN present is a known IEEE limitation (not a new fix requirement) and is not addressed
here.

**Alternatives rejected:** relaxing `Numeric_Result_Checked` to let user-constructed NaN propagate
— rejected, `Value` doesn't (and shouldn't) carry a "how did I get this NaN" provenance tag to
distinguish deliberate construction from an accidental arithmetic NaN, and it's out of proportion
to what #71 asked for. Parsing `.i`/`.n` via `Real'Value` on GNAT special-value strings — rejected
as unverified and unnecessary given the proven-safe arithmetic-construction alternative. Reusing
`Token_Numeric_Literal` with sentinel text — rejected, the parser's existing conversion site
unconditionally calls `Real'Value(S)` on that token kind's text, so reusing it means either
special-casing that call site anyway or accepting the `Real'Value` risk above.

**Versions/tests:** sdata-core (`Is_NaN`/`NaN_Val` on `SData_Core.Values`; `TK_Infinity`/`TK_NaN` +
construction in `Parse_Expression`; `Handle_Min_Fn`/`Handle_Max_Fn` fix), sdata (`Token_Infinity`/
`Token_NaN` in the lexer/parser; `REMOVE` guard fix), data-vandal (lexer + `Token_To_String`
parity) all additive; consumer floors unchanged if no other breaking change accompanies the
release. sdata-core in-crate tests: `parse_expression_tests.adb` (construction, disambiguation,
arithmetic-guard-still-raises), `values_tests.adb` (`Is_NaN`/`NaN_Val`/rendering),
`aggregate_exec_test.adb` (MIN/MAX NaN-first-row regression). sdata integration tests:
`infinity_nan_literals.cmd`, `infinity_nan_disambiguation.cmd`, `infinity_nan_arithmetic_error.cmd`,
`aggregate_min_max_nan_first.cmd`, `repl_remove_infinity_nan_rejected.cmd` (`.repl`-marker, per the
`repl-test-coverage` convention). data-vandal: `select_infinity_nan.cmd`. Full three-way gate green:
sdata-core in-crate suite, sdata `make check`, data-vandal `make check`, all pre- and post-change.

### ADR-058: SUBMIT inside a loop gets the same ADR-056 declarative-in-loop warning as inline use, deduplicated by submitted file path

**Date:** 2026-08-24 | **Status:** Accepted

**Context:** Design-vs-implementation re-audit finding PD-2
(`.ssd/audits/2026-08-13-design-vs-implementation/report.md`). §5.8 states *"If SUBMIT appears
inside IF, FOR, WHILE, or DO/UNTIL block, submitted file may not contain declarative statements"* —
but nothing enforces this, and unlike the direct (non-SUBMIT) case, not even ADR-056's own warning
fires. Traced to three broken links in the same chain: `Execute_Statement` has `Ctx.Loop_Depth` in
scope when it dispatches `Stmt_SUBMIT` to `Execute_IO`, but doesn't pass it; `Execute_IO`'s
`Stmt_SUBMIT` handler calls the top-level `Execute (Sub_Prog)` recursively, which has no way to
receive an ambient loop depth either; `Execute`'s own `Outer_Ctx : Step_Context`, declared fresh
per top-level statement it walks, always starts at the record default `Loop_Depth => 0`. Almost
certainly a stale leftover from before ADR-056 — the restriction was presumably real when direct
declarative-in-loop use was a hard rejection; ADR-056 changed the *direct* case from reject→warn
but never touched (or re-derived) SUBMIT's own, separately-worded restriction.

**Decision — symmetric warning, not stricter rejection.** SUBMIT gets exactly the same treatment
ADR-056 already gives an inline loop body: permitted, warned once, not rejected. The underlying
concern is identical in both cases (a Declarative statement takes effect once, not per iteration,
which is confusing but not wrong) — SUBMIT's separately-worded, stricter §5.8 text is judged to be
an artifact of predating ADR-056's unification of this concern, not a deliberately different policy
for the SUBMIT case. §5.8 (and the `SUBMIT` command-row repeat) reworded to match ADR-056's
permitted-with-warning posture.

**Mechanism — threading `Loop_Depth` through the SUBMIT boundary.** `Execute` gains an optional
`Base_Loop_Depth : Natural := 0` parameter; its `Outer_Ctx` now starts from that value instead of
the implicit `0`. All 6 of `Execute`'s pre-existing call sites (top-level batch/REPL entry points)
are unaffected by the default. `Execute_IO` gains a `Loop_Depth : Natural := 0` parameter, threaded
from `Execute_Statement`'s existing `Ctx.Loop_Depth` at its one dispatch site. `Execute_IO`'s
`Stmt_SUBMIT` handler passes it into the recursive `Execute (Sub_Prog, Loop_Depth)` call.

**Mechanism — deduplication by file path, not by AST node (new machinery, not a reuse of ADR-056's
own mechanism).** ADR-056's `Warned_In_Loop` flag lives on the AST `Statement` record itself and
works because an inline loop body is parsed once and the same node objects re-execute every
iteration. `SUBMIT` calls `Parse_Program` fresh, inside its own handler, on *every* invocation —
a brand-new AST, with `Warned_In_Loop` reset to its default `False` every time. Naively threading
`Loop_Depth` through with no other change would make a `SUBMIT` inside an *N*-iteration loop
produce *N* separate warnings — one fresh reset per invocation — pure noise for the common case of
a loop repeatedly submitting the same, unchanging file, and a real regression against ADR-056's own
"warn once, not per iteration" intent (not caught by the original audit, whose repro used a
single-iteration loop and couldn't distinguish "warn once" from "warn once per invocation").

Fixed by keying deduplication on the submitted file's own resolved path (`Final`, the same
normalized-absolute-path value already used by the pre-existing `Submit_Chain` recursion-detection
set — a proven, stable key for exactly this purpose) rather than by AST node identity. A new
`Warned_Submit_Paths : Name_Sets.Set` (same `Name_Sets` package `Submit_Chain` already uses) records
which submitted files have already produced at least one ADR-056 warning while loop-nested. On each
`Stmt_SUBMIT` dispatch:

```ada
Effective_Loop_Depth : constant Natural :=
   (if Loop_Depth > 0 and then not Warned_Submit_Paths.Contains (Final)
    then Loop_Depth else 0);
if Effective_Loop_Depth > 0 then
   Warned_Submit_Paths.Insert (Final);
end if;
...
Execute (Sub_Prog, Effective_Loop_Depth);
```

The *first* loop-nested submission of a given file passes its real `Loop_Depth` through, so every
distinct Declarative statement in that file warns once each (matching ADR-056's own per-statement
granularity *within* that one invocation — a file with two different Declarative lines gets two
warnings, not one, on its first submission). Every *subsequent* loop-nested submission of the same
file passes `Effective_Loop_Depth = 0`, so none of that invocation's statements can trigger the
warning at all — `Execute_Statement`'s existing `Ctx.Loop_Depth > 0` gate handles this without any
further change. This is a deliberate coarsening relative to ADR-056's exact per-AST-node semantics
(there, "once" means "once for the life of that specific node"; here, "once" means "once per
distinct file path per session") — accepted because AST-node identity is exactly the thing SUBMIT's
re-parsing makes meaningless as a dedup key, and file path is the closest stable analog available.
Reset at `NEW` (`Stmt_NEW`'s existing block of `Clear_*` calls in `execute_declarative.adb` gains a
matching `Clear_Warned_Submit_Paths`), matching how `Warned_In_Loop`'s own effective scope ends
when `NEW` discards the active program and any loop body it belonged to.

**Documentation:** `design.md` §5.8 and the `SUBMIT` command-row repeat reworded from "may not
contain declarative statements" to describe the permitted-with-warning behavior, referencing this
ADR.

**Consequences:** sdata-only (`sdata-interpreter.ads`, `sdata-interpreter.adb`,
`sdata-interpreter-execute_io.adb`, `sdata-interpreter-execute_declarative.adb`, `design.md`); no
sdata-core change, no cross-crate gate needed. New tests: the audit's own single-iteration repro
(now producing the ADR-056 warning instead of silence), and a multi-iteration repro proving the
per-file-path dedup fires exactly once across N loop-nested submissions of the same file, not N
times.

**Alternatives rejected:** implementing the stricter, originally-documented rejection instead of a
warning — rejected in favor of ADR-056 precedent-consistency (see Decision above), though this
brief's own investigation flagged it as a legitimate alternative reading, not a clear-cut wrong
answer. Per-statement (rather than per-file-path) deduplication, tracking `(file path, in-file
statement position)` pairs to exactly match ADR-056's per-node granularity even across re-parses —
rejected as more machinery than the problem warrants; a script author who has been warned once
about a given submitted file's loop-nesting behavior does not need every distinct Declarative line
in that same file re-flagged on every subsequent iteration once they've been told the file itself
is affected.

### ADR-059: NOTE — an Immediate-tier counterpart to PRINT that unconditionally rejects permanent variables

**Date:** 2026-08-29 | **Status:** Accepted

**Context:** User request for a new command, `NOTE`, syntactically identical to `PRINT` (`NOTE
<value> [<value>...]`) but Immediate-tier — it fires once, at its position in program order, like
`SYSTEM`/`HELP`/`NAMES`/`ECHO`/`DIGITS`, rather than being queued and executed once per record via
`RUN` the way `PRINT` is. The motivating use case is a lightweight, no-`RUN`-required way to
inspect a temporary (`SET`) variable's value immediately, without the ceremony of queuing a data
step.

**Decision — permanent variables are rejected unconditionally, anywhere in an argument's
expression tree, not just as a bare reference.** A permanent (table-column) variable is a per-row
vector; it has a well-defined single value only during a per-record execution pass, which an
Immediate-tier statement — by construction, firing once, independent of any specific record —
never has. The natural-seeming compromise ("allow a permanent variable when it's been reduced to
one value, e.g. inside an aggregate call like `SUM(X)`") was investigated and found not to exist as
a real capability: `SUM(v1, [v2, ...])` used as an ordinary expression-level function (outside
`AGGREGATE`/`STATS`'s own dedicated syntax) is a **row-wise** function — it sums several columns
*within the current record*, not across rows — confirmed empirically (`PRINT SUM(SCORE)` against a
two-row fixture printed each row's own `SCORE` value once per record, not a table-wide total).
There is no mechanism anywhere in this codebase that reduces a permanent variable to a single value
outside `AGGREGATE`/`STATS`'s own group-scan machinery, and that machinery is reachable only
through their dedicated command syntax, not from an arbitrary expression. Since nothing can
legitimately produce a well-defined single value from a permanent variable in a `NOTE` argument,
allowing it anywhere — bare, or buried inside arithmetic, a non-aggregate function call, or an
array-index expression — would only ever produce an arbitrary, unpredictable value (whatever
happens to be sitting in the PDV at `NOTE`'s one-shot dispatch point: unpopulated if no data has
been loaded yet, or a stale leftover from the last row a prior `RUN` processed). `NOTE` therefore
walks each argument's full expression tree and rejects on the first permanent-variable or
permanent-array reference found anywhere within it, before printing anything.

**Decision — NOTE fires exactly once inside a loop body, never replayed per record, matching
HELP/NAMES rather than ECHO/DIGITS.** This project's 2026-08-13 audit (findings PB-5 through PB-8)
established that `process_one_record.adb`'s per-record replay whitelist exists specifically for
Immediate-tier statements whose effect is read by, or itself reads, another statement's state
within the *same* per-record pass (`ECHO`'s console-suppression flag is read by a later deferred
`PRINT`; `DIGITS`'s precision is read the same way) — `HELP`/`NAMES` were deliberately removed from
that whitelist because their output depends on nothing that changes per iteration. `NOTE` is
architecturally closer to `HELP`/`NAMES`: even though its temporary-variable arguments *could* be
updated by a preceding deferred `LET`/`SET` in the same loop body, `NOTE` fires before any deferred
statement in that body has ever executed (deferred statements only run once `RUN` is reached), so
replaying it per record would not show meaningfully different values without also fundamentally
changing `NOTE`'s own one-shot Immediate semantics — a much larger design change the user
explicitly declined. `NOTE` is therefore deliberately absent from the per-record whitelist; a
script like `SET total=0 / REPEAT 5 / LET total=total+X / NOTE total / RUN` prints `total`'s
pre-loop value exactly once, not a running total per iteration — a known, accepted consequence of
this decision, not a defect.

**Mechanism — shared AST field and parser arm, not duplicated.** `sdata-ast.ads`'s `Statement`
variant record already groups multiple `Statement_Kind` values under one shared field block
wherever their shape is identical (e.g. `Stmt_USE | Stmt_SAVE | Stmt_SUBMIT | ...`); `Stmt_NOTE`
joins `Stmt_PRINT`'s existing arm (`when Stmt_PRINT | Stmt_NOTE => Print_Args : Expression_List;`)
with zero new fields, since `NOTE`'s argument list is structurally identical to `PRINT`'s.
`sdata-parser.adb`'s `Token_PRINT` case arm widens to `Token_PRINT | Token_NOTE` the same way,
sharing one argument-parsing loop.

**Mechanism — dispatch is three independently-traced decision points, not a symmetric pair.**
REPL's `Is_Immediate` (`sdata-interpreter.adb`) is an *inclusion* list — `Stmt_NOTE` must be added
explicitly, or a bare `NOTE` typed interactively is silently queued as if Deferred, reproducing
issue #68/finding PB-11's exact bug class. Batch mode's own dispatch (`Execute`'s main loop) is
structurally different — an *exclusion* list of Deferred kinds — so `Stmt_NOTE`, not being one of
those, already dispatches as Immediate with **zero** code change there; it must not be added to
that list "for symmetry" with the REPL fix, which would wrongly defer it in batch mode instead.
`process_one_record.adb`'s per-record whitelist is a third, independent list `NOTE` deliberately
stays out of (see the fire-once decision above). All three are covered by dedicated regression
tests, including a `.repl`-marked test exercising the REPL dispatch path specifically — a batch-only
test would not have caught issue #68 either.

**Mechanism — `Print_Value_List` extracted from `Execute_Print`, not duplicated.**
`Execute_Print`'s existing non-bare-argument branch (bare-variable, whole-array, array-element,
function-call, and generic-expression printing, ~75 lines) is factored into a shared procedure
called by both `Execute_Print` (replacing its inline block, verified byte-identical output on every
existing `PRINT` test) and the new `Execute_Note` (called once every argument has passed the
permanent-variable check).

**Consequences:** sdata-only (`sdata-lexer.{ads,adb}`, `sdata-ast.ads`, `sdata-parser.adb`,
`sdata-interpreter.{ads,adb}`, `sdata-interpreter-execute_print.adb`, new
`sdata-interpreter-execute_note.adb`, `sdata-reserved_keywords.adb`, `sdata-help.adb`,
`man/man1/sdata.1`, `design.md`); no sdata-core or data-vandal change, no cross-crate gate needed
(matching `PRINT`'s own sdata-only status per ADR-040). New reserved keyword `NOTE` — a table
column literally named `NOTE` now triggers the existing reserved-keyword-collision warning, the
same as any other reserved name.

**Alternatives rejected:** permitting a permanent variable inside an aggregate-function call
(`NOTE SUM(X)`) — rejected because no such capability exists today; building one would be a
separate, cross-cutting "aggregate functions as ordinary expression-level functions" feature
affecting `LET`/`IF`/`PRINT` too, not something to fold into adding one new command. Replaying
`NOTE` once per record inside a loop body, matching `ECHO`/`DIGITS` — rejected by explicit user
decision; considered because `NOTE`'s temporary-variable arguments can meaningfully change across
loop iterations the way `ECHO`'s/`DIGITS`'s own state does, but the user judged `NOTE`'s simpler,
`HELP`/`NAMES`-like one-shot semantics preferable. A bare `NOTE` printing all temporary variables
(mirroring `PRINT`'s own bare-argument behavior for permanent variables) — rejected by explicit
user decision in favor of requiring at least one argument.

### ADR-060: Parser errors raise Script_Error instead of printing and silently continuing

**Date:** 2026-08-29 | **Status:** Accepted

**Context:** Design-vs-implementation re-audit finding PE-8
(`.ssd/audits/2026-08-13-design-vs-implementation/part-e-io-operators-implementation-notes.md`)
sampled one parser error site (`sdata-parser.adb:562`, "Expected expression after operator") and
found that after printing the error, the script silently continues and exits 0. Investigating that
one site found the root cause is architectural, not local: `Parse_Program`'s loop (`exit when
New_Stmt = null`) cannot distinguish `Parse_Statement` returning `null` because parsing legitimately
reached the end of the program from returning `null` because a parse error occurred somewhere and
was already printed via `Put_Line_Error`. Either way, `Parse_Program` stops and hands back whatever
was successfully parsed *before* the problem, and the caller executes that truncated program as if
it were complete. `grep -c Put_Line_Error src/parser/sdata-parser.adb` found **~60** call sites
sharing this exact shape, every one printing a message beginning `"Error: ..."` (confirmed none are
legitimate non-fatal warnings) — confirmed empirically to be systemic, not confined to the one
audited line, via a second, unrelated repro (`USE MOCK` / `BOGUSCOMMAND` / `RUN` prints "Unrecognized
command" yet still runs `USE MOCK` and exits 0). A handful of sites don't even return `null` on
error — they print the message and then return a partially-built, wrong node as if parsing
succeeded (e.g. `Parse_Primary`'s two unclosed-delimiter cases). A partial, never-fully-wired
mitigation already existed in `Parse_USE_Stmt`/`Parse_SAVE_Stmt`: a local `Had_Error` flag, set at 9
of their own error sites, but it only short-circuits that function's own later logic (forcing
`Stmt.Mode := MM_Single`) — it never reached `Parse_Program`, so a malformed `USE`/`SAVE` spec still
silently "succeeded" with a degraded statement.

**Decision.** Every one of the ~60 parser error sites now `raise Script_Error with "<message>"`
(the exact existing message text, plus location info — see Mechanism below) instead of printing via
`Put_Line_Error` and falling through / returning `null` / returning a wrong node. This is not a new
mechanism: it makes the parser use the *same* propagation path every other error class in this
codebase already relies on — `sdata_main.adb`'s batch driver and `Run_REPL` both already catch
`SData.Script_Error | SData_Core.Script_Error | ...` at the top level and print `Error: <message>`
with a non-zero exit (batch) or a clean input-buffer reset (REPL). Zero changes were needed to
either handler.

**Decision — remove the `Had_Error` flag mechanism and other now-dead "keep parsing anyway"
recovery code, don't leave it in place.** Once every one of `Had_Error`'s 9 assignment sites raises
immediately instead, a downstream `if Had_Error then` check can never observe `True` — the raise has
already unwound past it — so the variable and both of its later conditional blocks in
`Parse_USE_Stmt`/`Parse_SAVE_Stmt` are provably dead and were deleted, not left as inert
bookkeeping. Likewise the `/DECIMALS=` negative-integer case's explicit two-token skip
(`sdata-parser.adb:936-943` pre-fix), which existed only to let the option-list loop keep going
after a bad value, was deleted along with the recovery it served.

**Decision — add location info to every converted site.** The audit's own finding named the missing
`Tok.Line` at the one sampled site as part of the same complaint as the silent-continue behavior.
Every one of the ~60 sites already had a `constant Token` in scope whose `.Line` is the correct one
to cite (no new plumbing needed anywhere), so all of them gained an `" at line" & <token>.Line'Image`
suffix, matching the existing "Unrecognized command ... at line N" message's own phrasing exactly.

**Decision — accept a bounded, session-scoped memory leak in REPL mode; do not attempt a broader AST
ownership refactor.** This codebase's AST nodes are plain Ada `access` types (freed explicitly via
`Free_Program`/`Free_Expression`), not controlled types — Ada does not automatically deallocate them
when an exception unwinds past a partially-built expression tree. In batch mode this is
inconsequential (the process exits immediately after the top-level catch prints the error). In REPL
mode, a malformed statement's already-allocated sub-expressions leak, bounded by how many malformed
statements a user types before restarting the session — small in practice, and strictly *smaller*
in consequence than the bug being fixed (which silently executes wrong or truncated programs, not
merely leaks memory). A broader RAII-style ownership refactor of the AST to eliminate this leak
entirely was considered and rejected as substantially larger, riskier, separate work with no
concrete need behind it yet.

**Consequences:** sdata-only (`src/parser/sdata-parser.adb`; lexer/AST/parser are sdata-only per
ADR-040) — no sdata-core or data-vandal change. 9 existing tests required expected-output rework,
identified by direct inspection before the change (not discovered via test failures after the
fact): `decimals_negative.cmd` and 8 of the 16 `use_merge_err_*.cmd` tests previously encoded the
*buggy* behavior directly — a parser error message immediately followed by a confusing, unrelated
second error (`"Error: .CSV: No such file or directory"`) from `Parse_USE_Stmt`'s `Had_Error`-
triggered `MM_Single` fallback attempting to open a garbled filename built from a partially-parsed
spec. Under this fix, each of those scripts now fails cleanly at the true point of error, with a
single, correct message — a strict readability improvement for anyone who hits one of these errors
for real, not just a bug fix. `use_merge_err_in_col_collision.cmd` and `use_merge_err_by_missing.cmd`
were confirmed to be genuine *runtime* errors (the dataset is actually opened first), unrelated to
this change, and were left untouched.

**Alternatives rejected:** a shared `Parser_Error` helper procedure wrapping the raise — rejected in
favor of individual `raise Script_Error with "..."` at each site, matching this codebase's own
established idiom for single-site errors elsewhere (`TABLES /ORDER=`, `REPEAT`'s bare-count check,
this session's own `ECHO` fix) and keeping the diff maximally reviewable site-by-site without a new
layer of indirection. Fixing only the one originally-audited site (`sdata-parser.adb:562`) — an
explicit choice offered to and rejected by the project owner in favor of closing the whole ~60-site
bug class at once, once the shared root cause was found. A broader AST-ownership refactor to
eliminate the REPL-mode leak entirely — rejected as separate, larger, unjustified-by-need work (see
Decision above).

### ADR-061: `Run_REPL` echoes each input line unconditionally, closing design.md's "Statement Echo" gap

**Date:** 2026-08-31 | **Status:** Accepted

**Context:** Design-vs-implementation re-audit finding PE-7
(`.ssd/audits/2026-08-13-design-vs-implementation/part-e-io-operators-implementation-notes.md`):
design.md §6.3 states "Statements shall be echoed to screen, even if console output is disabled."
No code implemented this. In a real terminal, typed characters appear on screen via the terminal
driver's own canonical-mode echo — OS behavior sdata never provided — which does not survive
non-tty invocation (piped stdin), even though `Run_REPL` explicitly supports it
(`Set_Interactive (True)` is set unconditionally whenever no script filename is given). Confirmed
empirically: `printf 'USE MOCK\nLET Z = 5\nPRINT Z\nRUN\nQUIT\n' | ./bin/sdata` showed none of the
five typed statements in its output, only their side effects, identically with or without `-q`.

**Decision.** `Run_REPL` (`src/sdata_main.adb`) now writes each input line back out via
`Ada.Text_IO.Unbounded_IO.Put_Line (Line)` immediately after `Ada.Text_IO.Unbounded_IO.Get_Line
(Line)` reads it — one call site, one line added. The write is unconditional: not gated by
`Quiet_Mode` or `Local_Echo`, matching design.md's explicit "even if console output is disabled"
wording and the existing precedent that the prompt itself (`"sdata> "` / `"..> "`) and the startup
banner already print ungated, bypassing the pager buffer, for the identical reason (must always
appear immediately).

**Decision — echo the raw per-line input, not the assembled statement.** `Get_Line` already runs
exactly once per loop iteration, including once per continuation line (a trailing-comma statement
re-prompts and re-reads before the full buffer is re-parsed), so placing the echo immediately after
`Get_Line` produces one echo per physical input line — including continuation lines — with zero
additional bookkeeping, and mirrors what real terminal echo would show in real time rather than
withholding output until a (possibly multi-line) statement finishes parsing.

**Decision — place the echo before `Append`/`Parse_Program`, not after a successful parse.** The
line is echoed regardless of whether it later turns out to be part of a statement that fails to
parse. design.md's "even if console output is disabled" wording carries no carve-out for that case
— the statement was typed and should be shown, independent of what happens to it afterward.

**Non-decision — `Local_Echo`/`ECHO` is untouched.** The existing `Local_Echo` flag
(`sdata_core-io.adb`, toggled by the `ECHO` command) gates whether **command *output*** is printed
(e.g. `USE`'s "Generating mock data..." message) — a different, pre-existing concept from
**statement echo**, which this ADR adds as new, independent behavior. Conflating the two would have
been a mistake: it is the root of a separate, already-deferred finding (PE-4, `-q`'s doc claiming
`ECHO ON` can countermand it — false, since neither `Local_Echo` nor `Quiet_Mode` has ever gated
input text).

**Decision — the identical fix also applies to `BREAK`'s debug sub-prompt.** Code review (round 1)
found a second `Get_Line` call site, `Inspect_PDV` (`src/sdata-interpreter-inspect_pdv.adb`, the
`BREAK` statement's record-by-record debug prompt), sharing the exact same defect: its own guard
(`if not SData_Core.IO.Is_Interactive then ... return;`) looks like tty protection but
`Is_Interactive` reads the same `Interactive_Mode` flag `Run_REPL` sets unconditionally at entry —
so the debug prompt runs and reads real commands (`CONTINUE`/`STEP`/`RUN`/`PRINT <expr>`/
`RECORD N`) unechoed under a piped `Run_REPL` session exactly as much as a real tty one, verified
live. Fixed identically (echo immediately after `Get_Line`), with one adaptation: this prompt
writes to `Standard_Error`, not `Standard_Output` like `Run_REPL`'s, so its echo does too — the
echo always matches the stream of the prompt it completes, not a fixed stream.

**Consequences:** sdata-only (`src/sdata_main.adb`, `src/sdata-interpreter-inspect_pdv.adb`; both
sdata-only per ADR-040) — no sdata-core or data-vandal change. Every existing `.repl`-marked
integration test (17, found via `find tests -name '*.repl'`, not assumed from any prior
workstream's list) required expected-output regeneration, since echoed input is new output
appearing in all of them; each was regenerated from the freshly built binary and diffed to confirm
the *only* delta in every case is the newly-echoed line text, never a change to any command's own
output. Batch execution of a script file is unaffected by either site — design.md §6.3 is scoped
to "Interactive Mode," `Interactive_Mode` is never set in batch mode, and both existing
batch-mode `BREAK` tests (`break_basic.cmd`, `break_when.cmd`) are confirmed unchanged.

**Alternatives rejected:** narrowing design.md's claim to describe tty-only reliance instead of
implementing the echo — rejected because sdata's REPL explicitly and deliberately supports
non-tty piped invocation (the `repl-test-coverage` workstream's entire `.repl` test family exists
because of this), so a piped session's transcript being unreadable is a real usability gap, not
just a doc inaccuracy to soften. Buffering and echoing the fully-assembled statement instead of
each physical line — rejected as not matching real terminal echo (which shows each line as typed)
and as needlessly diverging from the already-correct per-line prompt pairing.

### ADR-062: Declarative/Immediate-tier expressions get the same unknown-function/arity checking as Deferred, by reusing `Check_Statement` — not by duplicating it

**Date:** 2026-09-03 | **Status:** Accepted

**Context:** [jlries61/sdata#76](https://github.com/jlries61/sdata/issues/76), filed during the
`note-command` workstream's own code review. `PRINT` (Deferred-tier) gets a clean
`Error: unknown function 'X'` / arity-mismatch error from `Check_Statement`/`Check_Expr`
(`sdata-interpreter.adb`) — a static pass that runs once, before `Evaluate` ever executes,
via `Analyze_One` (entry-time, on every statement queued through `Add_To_Active_Program`) and
`Analyze_Deferred` (whole-block, immediately before `RUN`). `RSEED`, `NOTE`, and `DIM` evaluate a
user-supplied expression exactly the same way (`Evaluate`/`Eval_Raw` → `Evaluate_Function`), but
**never reach `Check_Statement` at all**, because none of them are ever queued through
`Add_To_Active_Program` — RSEED and DIM are Declarative-tier, NOTE is Immediate-tier, and both
tiers dispatch straight to execution, bypassing the only two call sites `Check_Statement` has.
`Evaluate_Function`'s own final dispatch (`sdata_core-evaluator.adb`) silently returns
`Val_Missing` on an unrecognized name instead of raising, so the gap is invisible rather than
merely unhelpful: `NOTE BOGUSFUNC(X)` prints `.` (missing), and `RSEED BOGUSFUNC(1)` raises a
confusing secondary error (`Cannot convert VAL_MISSING to Real`) from trying to use the
silently-substituted missing value as a seed, never "unknown function."

**Investigation, not assumption, before deciding:**

- Searched every call site of `Evaluate_Function` across all three repos (`sdata-core`, `sdata`,
  `data-vandal`) — exactly two, both inside `sdata_core-evaluator.adb` itself: the
  `Expr_Function_Call` AST arm (the direct "user typed `FOO(...)`" path) and the
  `Expr_Variable`/zero-arg-fallback path, which is pre-gated by `Is_Zero_Arg_Fallback`'s own
  fixed, always-registered name list. **Neither call site depends on the silent-`Missing`
  fallback for a legitimate "probe an unknown name" purpose** — the brief's stated risk for
  Direction (a) does not materialize.
- Enumerated every Declarative/Immediate-tier statement that evaluates an arbitrary user
  expression the same unchecked way: **RSEED**'s `Seed_Expr`, **NOTE**'s `Print_Args` (via the
  `Print_Value_List` helper it shares with `PRINT` — same evaluation code, different upstream
  checking depending on which statement reached it), and **DIM**'s `Arr_Start_Expr`/`Arr_End_Expr`
  array-bound expressions. `DISPLAY` (named as a candidate in the issue) takes a `Variable_List`,
  not an expression — not affected. `SYSTEM` takes a raw file-path string, not an expression — not
  affected. A fourth site, **`SAVE`'s per-target `IF=` option** (`Should_Write`,
  `sdata-interpreter.adb`), has the identical unchecked-evaluation shape but is architecturally
  different — evaluated once *per record* during `WRITE`'s flush, not once per statement —
  addressed by validating it once, at SAVE-target registration time, not on every record.
- Read `Check_Statement`'s existing `case S.Kind` dispatch (`sdata-interpreter.adb`): it **already
  has an `Stmt_RSEED` arm** checking `Seed_Expr`, and its `Stmt_KEEP | Stmt_DROP | ... | Stmt_DIM
  | ...` arm **already checks** `Arr_Start_Expr`/`Arr_End_Expr`. Both are dead code today — fully
  written, fully correct, simply never invoked for these statement kinds. `Stmt_NOTE` is the one
  gap even within `Check_Statement` itself: it shares `Print_Args` with `Stmt_PRINT` at the AST
  level (ADR-059) but was never added to `Check_Statement`'s `Stmt_PRINT` arm, so even a future
  caller of `Check_Statement` on a `NOTE` statement wouldn't check its arguments without one more
  one-line fix.

**Decision — reuse `Check_Statement`, don't duplicate its logic (primary fix, sdata-only).** Add
`Stmt_NOTE` to `Check_Statement`'s existing `Stmt_PRINT` arm (one line: `when Stmt_PRINT |
Stmt_NOTE =>`), then call `Check_Statement (Stmt, Check_Undefined => False)` at the top of each of
`Execute_RSEED`, `Execute_Note`, and `Execute_DIM`'s own dispatch, before any evaluation happens —
matching exactly the `Check_Undefined => False` mode `Analyze_One` already uses for entry-time
checking of a freshly-typed Deferred statement (undefined-variable checking stays off, since these
Declarative/Immediate statements execute immediately and don't have Deferred's whole-block forward-
reference model — only the already-battle-tested `Is_Known_Function`/`Function_Arity` half fires).
For `SAVE`'s `IF=` option: call `Check_Expr` once, when the target is registered
(`Execute_SAVE`/target-parsing, not `Should_Write`'s own per-record call), so a bad expression is
caught once at declaration time rather than re-validated on every row. This is the smallest,
lowest-risk fix that gets both unknown-function **and** arity checking, for free, by wiring in
logic that already exists, is already covered by `PRINT`'s own regression tests, and needs zero
new checking logic written — only new call sites.

**Decision — also raise in `Evaluate_Function`'s own fallback, as a defense-in-depth backstop
(secondary fix, sdata-core).** `Evaluate_Function`'s final dispatch now raises
`SData_Core.Script_Error with "unknown function '" & Name & "'"` instead of returning
`(Kind => Val_Missing)`, matching the sibling `Call_Function`'s existing behavior. Confirmed safe
by the call-site investigation above — nothing depends on the silent return. This does not by
itself add arity checking (that stays `Check_Statement`'s job, since `Evaluate_Function` has no
natural place to know an arity mismatch from a legitimately-variable-arity function without
duplicating `Function_Arity`'s table) and is not the primary fix for *this* issue — every path
`Check_Statement` now covers will already raise its own clearer, arity-aware error first. Its
purpose is closing the systemic pattern, not just today's four instances: any *future*
Declarative/Immediate-tier command that evaluates a user expression and forgets to call
`Check_Statement`/`Check_Expr` first now fails loudly instead of silently, the same insurance
`Call_Function`'s callers already had.

**Consequences:** primary fix is sdata-only (`sdata-interpreter.adb`'s `Check_Statement`,
`sdata-interpreter-execute_declarative.adb`'s `Execute_RSEED`, `sdata-interpreter-execute_note.adb`'s
`Execute_Note`, `sdata-interpreter-execute_metadata.adb`'s `Execute_DIM`/SAVE-target registration).
Secondary fix is sdata-core-only (`sdata_core-evaluator.adb`'s `Evaluate_Function`), requiring the
standard cross-crate gate (`alr build` → sdata `make check` → data-vandal `make check`) since
`data-vandal` also calls the shared evaluator. No data model change. No feature flag — this is a
strictly-additive error-surfacing fix (a case that previously silently mis-evaluated now raises;
no previously-successful script becomes an error, since a script calling a genuinely unknown
function was never producing a meaningful result in the first place).

**Alternatives rejected:** Direction (a) alone from the issue (global raise in
`Evaluate_Function`'s fallback, no `Check_Statement` wiring) — would fix the silent-missing-value
symptom but not arity checking, and would give `NOTE`/`RSEED`/`DIM` a different, less specific
error message than `PRINT` gets for the identical mistake, an inconsistency the issue's own
framing (comparing `NOTE`'s and `PRINT`'s behavior side by side) argues against. Direction (b) as
literally specified (new, duplicated per-command checks mirroring `Reject_If_Permanent`'s
structure) — rejected once the investigation found `Check_Statement` already implements the
needed logic correctly and only lacks call sites; writing a second, parallel implementation of
"is this function known, is the arity right" would itself become exactly the kind of duplicated,
independently-drifting logic this project's own 2026-08-13 audit (and this milestone's own
`codebase-skeptic` pass) already flagged as a recurring failure shape elsewhere in this codebase.

### ADR-063: NOTE's permanent-variable rejection checks the resolved array *element*, not the array's declared class

**Date:** 2026-09-05 | **Status:** Accepted

**Context:** [jlries61/sdata#83](https://github.com/jlries61/sdata/issues/83). `NOTE`'s
`Reject_If_Permanent` (ADR-059) rejects any argument referencing a permanent (per-row) variable,
walking the full expression tree so a reference buried inside an array index or function argument
is caught, not just a bare top-level one. For a virtual array (`ARRAY V A B`, aliasing possibly
mixed-class constituents — see sdata-core ADR-0023), the check tested `Is_Temporary_Array(V)`, the
*array's* declared storage class. `SData_Core.Variables.Define_Array` hardcodes this `False` for
every virtual array unconditionally (ADR-0023's own finding), so the check always concluded "V is
permanent" and rejected — even when the specific constituent a given reference actually names is a
genuine temporary with a perfectly well-defined value. `NOTE V(2)` failed even when `V(2)` aliases
a `SET` variable; a bare `NOTE V` (whole-array form, matching `PRINT`'s own bare-array semantics)
failed the same way regardless of any individual constituent's real class.

Confirmed the same defect reaches `NOTE` through **three** AST shapes, not one: `Expr_Variable`
(bare `V`, which `Print_Value_List` — the shared evaluation/printing routine ADR-059 factored out —
resolves to *every* element from `Get_Array_Bounds`'s `Start_Idx..End_Idx`), `Expr_Array_Access`
(`V(2)`, `V(1,3,5)`, and range form `V(1:3)` — `Arr_Idx` is an `Expression_List` supporting all
three shapes per `SData_Core.Evaluator`'s own field comment), and `Expr_Function_Call` (the
parser's pre-`DIM`-time array-vs-call ambiguity `Print_Value_List` and `Reject_If_Permanent` both
already special-case identically). All three currently gate on the same array-level flag and
needed the identical fix.

**Decision — check the resolved element's actual class via `Array_Element_Is_Temporary`, not the
array's declared class, for all three shapes.** `SData_Core.Variables.Array_Element_Is_Temporary
(Name, Index)` (added by sdata-core ADR-0023 for the identical write-side defect) already resolves
a virtual array's constituent to its real storage class (genuinely `SET`-created and not currently
`HOLD`-ed) and returns the array-wide flag unchanged for a real (`DIM`'d) array, where it's already
uniformly correct.

**Decision — the per-element check runs *inside* `Print_Value_List`'s own index evaluation, as a
callback, not as a separate pass in `Reject_If_Permanent` beforehand.** The first implementation of
this ADR had `Reject_If_Permanent` evaluate each index itself (justified by the argument that
`Reject_If_Permanent_List` already independently guarantees the index tree contains no permanent-
variable reference, so evaluating it can't itself violate ADR-059's "no ill-defined value" Context
requirement) and then call `Print_Value_List`, which evaluates the *same* index expression again to
actually print. Testing that implementation directly (constructing a mixed-class virtual array and
indexing it with `V(1 + INT(RANDOM()*2))`) surfaced a real defect the safety argument didn't cover:
an index expression's *evaluation* need not be idempotent even when it's permanent-reference-free —
`RANDOM()` draws a fresh value on every call — so the check's evaluation and the print's evaluation
could resolve to *different* elements. Observed in practice: the check-time draw would sometimes
land on the temporary element (pass) while the separate print-time draw landed on the permanent one
moments later, silently printing the very permanent value `NOTE` exists to reject, defeating
ADR-059 outright. The fix is to evaluate each index exactly **once**, at the point it's actually
used to print, and check the element there: `Print_Value_List` gained an optional
`Check_Permanent : access procedure (Arr_Name : String; Idx : Integer)` parameter, called
immediately after it resolves an index (or range bound) to a concrete `Idx` and before the
corresponding `Put` — for every shape it already resolves indices in (bare `Expr_Variable`'s
`Start_Idx..End_Idx` loop, `Expr_Array_Access`/`Expr_Function_Call`'s single/comma-list/`Is_Range`
walk). `Execute_Print` passes no callback (`null`, the default) — `PRINT` is unaffected. `Execute_Note`
passes `Reject_Element'Access`, a small nested procedure wrapping `Array_Element_Is_Temporary`; since
it's an anonymous access-to-subprogram parameter, passing a nested subprogram's `'Access` directly as
a same-call argument is accessibility-safe with no extra machinery. `Reject_If_Permanent` itself goes
back to being purely static for arrays (ADR-059's original mechanism, unchanged): it still walks
`Reject_If_Permanent_List(E.Arr_Idx)` / `(E.Arguments)` to catch a permanent variable referenced
*inside* an index expression (`NOTE V(SCORE)`, still statically rejected, no evaluation involved),
but no longer resolves or checks the array element itself — that moved entirely into
`Print_Value_List`'s single evaluation pass.

**Consequences:**

*Positive* — Closes #83: `NOTE` on a virtual array's temporary element or whole array now
correctly reflects each constituent's real storage class, matching what bare-name `NOTE B` already
allows for that same constituent. Error messages name the specific element (`V(3)`), not just the
array, matching sdata-core ADR-0023/0024's own established convention of naming what the user
would need to reference. No sdata-core change — `Array_Element_Is_Temporary` already existed;
this is sdata-only (`sdata-interpreter.adb`/`-execute_note.adb`/`-print_value_list.adb`). The index
expression is evaluated exactly once per element, same as before this ADR, so no new evaluation
cost and no idempotency hazard for any index expression, deterministic or not.

*Negative* — `Print_Value_List` (shared with `PRINT`) now carries a `NOTE`-only parameter, a small
layering smell, though it's `null` by default and `PRINT`'s call site is untouched. If element 1 of
a bare/list/range `NOTE` is temporary and a later element is permanent, that first element's value
is already `Put` to the output stream before the later check raises — a partial line precedes the
`Error:` line — whereas the (superseded) first implementation checked every element before printing
any of them. Accepted: existing "some output, then an error" sequences already occur elsewhere in
this interpreter when a later argument fails after an earlier one succeeded, and no regression test
in the current suite depends on the erased check-before-any-print ordering (the one bare-array
regression test, `note_reject_permanent_array.cmd`, has its permanent element first).

**Alternatives rejected:** the original two-pass design described above (evaluate-to-check, then
evaluate-again-to-print) — superseded by direct testing during this same ADR's implementation,
which found the double-evaluation defect described above; restricting the fix to literal-integer
indices only (no evaluation anywhere) — would fix `NOTE V(2)` but not `NOTE V(I)` (variable index)
or the bare whole-array form, leaving the bulk of real-world usage still broken, and the
single-evaluation redesign fixes the general case with no idempotency hazard, so there was no
remaining reason to accept that narrower scope. Leaving the array-level check as a fallback for
non-literal indices — same rejection: the general case is now handled soundly, so a fallback would
just reintroduce the bug for exactly the cases most likely to be hit in practice.

### ADR-064: Lexer `Token_Bad` sites raise Script_Error instead of printing and silently continuing

**Date:** 2026-09-05 | **Status:** Accepted

**Context:** [sdata#77](https://github.com/jlries61/sdata/issues/77), filed as a deliberate
out-of-scope follow-up from the ADR-060/PE-8 parser-error-propagation workstream (that workstream's
own brief explicitly flagged the lexer's `Token_Bad` path as "a candidate follow-up finding if
confirmed, don't fold into this workstream's scope without a separate decision"). `SData.Lexer`'s
backtick-quoted-identifier handling (`src/lexer/sdata-lexer.adb`) has exactly two error sites — the
unterminated-quote and empty-quote cases — both printing `"Error: ..."` via `Put_Line_Error` and
returning a `Token_Bad`-kind token instead of a real error. The one consuming site,
`Parse_Statement`'s top-level dispatch (`sdata-parser.adb`, `when Token_Bad => return null;`), is
indistinguishable from `Parse_Program`'s own clean-EOF signal — the exact same `null`-means-two-
things ambiguity ADR-060 fixed for the parser's own ~60 sites, reintroduced one layer down. Confirmed
empirically: `printf 'USE MOCK\n\`bad\nRUN\n' | sdata; echo $?` prints the error, then still runs
`USE MOCK` and exits 0 — matching the issue's own repro exactly.

**Scope is broader than the issue's literal repro.** The bug is not confined to `Token_Bad` as a
statement's leading token: a backtick error nested inside an expression silently drops the whole
containing statement while the rest of the script still succeeds — `printf 'USE MOCK\nLET Y =
\`bad + 1\nPRINT Y\nRUN\n' | sdata` prints the lex error, then prints `Y` as missing (`.`) for
every record and reports `RUN complete`, exit 0. The issue's own suggested fix (converting only the
one `Parse_Statement` dispatch arm) would not have closed this case, since that arm only ever fires
when `Token_Bad` is the first token of a statement.

**Decision.** Both `Token_Bad`-producing sites now `raise Script_Error with "<message>"` (the exact
existing message text, minus the `"Error: "` prefix the top-level handlers already supply) instead
of printing via `Put_Line_Error` and returning a sentinel token — the same mechanism ADR-060
established for the parser one layer up, reusing the identical, already-verified top-level catch in
both batch and REPL mode with zero changes to either handler. Unlike ADR-060's ~60 sites, this
required no case-by-case survey of downstream consumers: `SData.Lexer`'s tokenizing entry points are
called from nowhere in `src/` except `src/parser/sdata-parser.ad[bs]`, and that file has exactly
three local exception handlers, all narrowly `when Constraint_Error =>` around numeric-literal
overflow — none catch `Script_Error` or `others` — so a lexer-raised exception unwinds unimpeded
through every parser call site, top-level statement dispatch or nested expression parsing alike, to
the same handlers ADR-060 already confirmed correct at all four `Parse_Program` call sites (batch
driver, REPL, SUBMIT, BREAK-debug-prompt).

**Decision — remove `Token_Bad` outright, don't leave it as an inert sentinel.** With both
producing sites converted, `Token_Bad` has no remaining producer, so the parser's now-unreachable
consumption arm, the enum literal itself, and its `.ads` doc comment were all deleted in the same
change — confirmed safe: no `Token_Kind'Pos`/`'Val`-driven table exists anywhere in `src/`, so
removing the literal cannot shift any positional encoding another site depends on, and Ada's
case-statement exhaustiveness check would itself fail the build if any live arm had been missed.

**Consequences:** sdata-only (`src/lexer/sdata-lexer.adb`, `src/lexer/sdata-lexer.ads`,
`src/parser/sdata-parser.adb`; lexer/AST/parser are sdata-only per ADR-040) — no sdata-core or
data-vandal change. One existing test, `tests/quoted_id_bad.cmd`, previously encoded the buggy
exit-0 behavior directly (no `.exitcode` file present); it now requires `tests/quoted_id_bad.exitcode`
asserting exit 1, with its expected message text unchanged. Four new regression tests were added:
the empty-quoted-identifier variant (previously uncovered), the nested-in-expression case (the one
that most directly demonstrates why a parser-only fix would have been insufficient), and a
`.repl`-marked REPL-mode test modeled on ADR-060's own REPL-recovery proof, confirming a lex error
cleanly resets the session and it keeps working afterward. Inherits the same accepted trade-off
ADR-060 documented and does not re-litigate: a partially-built AST sub-expression from the
nested-expression case is not freed when the raise unwinds mid-parse (Ada access types have no
automatic cleanup) — inconsequential in batch mode (process exits immediately) and a small,
bounded, session-scoped leak in REPL mode, strictly smaller in consequence than the bug being
fixed.

**Alternatives rejected:** raising at the parser's consumption site instead of the lexer's origin
sites — rejected because it would leave `Token_Bad` alive as a sentinel nothing but a
soon-to-be-dead arm produces meaning for, whereas raising at the true origin lets the whole sentinel
be deleted outright; no lexer-level recovery mode or future consumer wanting to inspect a bad token
rather than abort was found during design. A broader audit of every lexer error path beyond
`Token_Bad` — deliberately out of scope: `grep -n Put_Line_Error src/lexer/sdata-lexer.adb` found
exactly these two sites and no other lexer error class currently exists; any future discovery gets
its own follow-up decision, matching this ADR's own origin as a scoped-out follow-up from ADR-060
rather than silent scope creep.

### ADR-065: Status/bookkeeping messages reach the OUTPUT-file transcript unconditionally, matching design.md §6.1

**Date:** 2026-09-05 | **Status:** Accepted

**Context:** [sdata#81](https://github.com/jlries61/sdata/issues/81), filed as a deliberate
follow-up from the PE-4/sdata-core ADR-0022 (`Quiet_Mode`→`Local_Echo` unification) code review.
design.md §6.1 states the `OUTPUT`-file copy of console output is written **unconditionally**,
even under `-q` ("only the stdout copy is suppressed"). `SData_Core.IO.Put_Line`
(`sdata-core/src/sdata_core-io.adb:219-235`) already implements this correctly on its own:

```ada
procedure Put_Line (Item : String) is
begin
   if Redirected then
      Ada.Text_IO.Put_Line (Redirect_File, Item);   -- unconditional
      Ada.Text_IO.Flush (Redirect_File);
   end if;
   if Local_Echo then
      ... stdout / pager write ...                   -- correctly gated
   end if;
end Put_Line;
```

`Is_Local_Echo` (`sdata_core-io.adb:92`) is simply the public accessor for the same `Local_Echo`
flag `Put_Line` already checks internally. The bug: 6 status/bookkeeping call sites additionally
wrapped their entire `Put_Line` call in `if Is_Local_Echo then ... end if;` — fully redundant with
`Put_Line`'s own internal stdout gating, but incorrectly *also* skipping the unconditional
`Redirected`-file write, since the call never happened at all under `-q`. Confirmed empirically:
`printf 'OUTPUT "/tmp/out.txt"\nUSE MOCK\nQUIT\n' | sdata -q; cat /tmp/out.txt` was empty.

**Scope corrected from 5 to 6 sites.** The issue named 5; a `grep -rn Is_Local_Echo` sweep across
`sdata` and `sdata-core` this session found a 6th, structurally identical site the issue's own
enumeration missed — `sdata/src/sdata-interpreter.adb`'s `Commit_Step` (multi-target `SAVE ... AS
X, ... AS Y`'s own `"Dataset saved: ..."`, a different call site than single-target `SAVE`'s
sdata-core-side message). Final site list:

| # | File | Message |
|---|---|---|
| 1 | `sdata-core/src/sdata_core-file_io.adb` (`Open_Input`) | `"Generating mock data..."` |
| 2 | `sdata-core/src/sdata_core-file_io.adb` (`Open_Input`) | `"Dataset opened: ..."` |
| 3 | `sdata-core/src/sdata_core-commands.adb` (`Flush_Pending_Output_Table`) | `"Dataset saved: ..."` |
| 4 | `sdata-core/src/sdata_core-commands.adb` (`Flush_Pending_Save`) | `"Dataset saved: ..."` |
| 5 | `sdata/src/sdata-interpreter.adb` (`Print_Run_Complete`) | `"RUN complete. ..."` |
| 6 | `sdata/src/sdata-interpreter.adb` (`Commit_Step`, multi-target SAVE) | `"Dataset saved: ..."` |

**Decision.** Each of the 6 sites now calls `Put_Line` directly instead of wrapping it in
`if Is_Local_Echo then ... end if;` — a pure deletion at every site, since `Put_Line` already does
the right thing internally. No restructuring, no new helper: every site's fix is "delete the guard,
call `Put_Line` at one less indentation level." Confirmed via direct re-read of all 6 sites that
none contain any logic beyond the single `Put_Line` call, so no site needed different treatment.

**Decision — user chose to fix the code, not soften the doc.** Presented two options: make the
`OUTPUT`-file transcript truly unconditional for these messages (align code with design.md §6.1 as
literally written), or narrow §6.1's wording to document this as a stated exception. **User chose:
fix the code.**

**Site 3 (`Flush_Pending_Output_Table`) is fixed but untestable via any current test
infrastructure — a pre-existing condition, not introduced by this fix.** `Execute_OUTPUT_Table`
(the procedure that populates `Config.Runtime.Output_Table_Path`/`Output_Table_Active`, which
`Flush_Pending_Output_Table` reads) was added per ADR-042 as "a parallel sdata-core entry point"
but has **zero callers** anywhere across sdata, sdata-core, or data-vandal today — confirmed via
`grep -rn Execute_OUTPUT_Table` across all three repos' `src/`. sdata's own `OUTPUT` command
(`Stmt_OUTPUT`) calls the unrelated `Execute_OUTPUT` (console-redirect only); data-vandal's
`OUTPUT` statement does the same ("Matches sdata's OUTPUT semantic" per its own source comment).
sdata-core's own in-crate test driver explicitly excludes file-writing `Execute_*` paths from its
scope (`tests/README.md`: "the `Execute_*` paths that load or write data ... are not [covered],
since they require a populated table and the filesystem"). The fix is correct and forward-looking
(a future consumer wiring up `Execute_OUTPUT_Table` inherits the fix automatically) but cannot be
exercised by any test today — documented here rather than manufacturing an artificial test path
for currently-dead code.

**Consequences:** Cross-repo change — 4 sites in `sdata-core` (`Commands`/`File_IO`, shared with
data-vandal), 2 in `sdata` (`sdata-interpreter.adb`, sdata-only per ADR-040). sdata-core's fix
landed via its own PR-based workflow (server-enforced) and the mandatory three-way local gate
(`alr build` sdata-core, `make check` sdata, `make check` data-vandal) before either half was
pushed, per sdata's CLAUDE.md § "Cross-crate coordination." 2 new regression tests added, both
combining multiple sites in one `-q` + `OUTPUT`-redirected script, each asserting the `OUTPUT` file
now contains the messages while stdout remains exactly as suppressed as before (verified against 2
existing tests — `pe4_quiet_alone_still_suppresses.cmd` and `pe4_echo_on_undoes_quiet.cmd` — whose
stdout-suppression assertions are structurally immune to this fix, since `Put_Line`'s `Redirected`
and `Local_Echo` gates are independent). Zero existing tests required rework: cross-referencing
every `-q`-flagged test against every `OUTPUT`-using test found no prior overlap, confirming the
gap this fix closes was previously completely untested. data-vandal's identical-shape 7th site
(`execute_vandalize.adb:1230`, `"VANDALIZE complete. ..."`) is explicitly out of scope per the
issue's own framing — data-vandal's own decision, not addressed here.

**Alternatives rejected:** narrowing design.md §6.1's wording instead of fixing the code — rejected
by explicit user decision (see above). Extending the fix to data-vandal's identical-shape 7th site
in the same change — rejected as scope creep across a repo boundary the issue itself declared out
of scope; left as a candidate for data-vandal's own decision, not silently folded in.
