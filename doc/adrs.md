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

**Decision:** Redefine the unit of MAXINTAB / `-m` as cells (rows × columns). Both spill checks — in `Add_Row` for the input table and in `Add_Output_Row` for the output table — now compare `rows_in_current_segment × column_count` against the threshold. `Fetch_From_Disk` derives the equivalent rows-per-segment for cache-page alignment as `threshold / column_count` (floored at 1), preserving consistent segment boundaries between write and read paths. The variable name `Max_Table_Rows` is retained in the source to minimize churn; the semantics are recorded here and in the help strings. Default remains 0 (unlimited, no automatic spill). A practical guideline: 1 000 000 cells ≈ 25–32 MB at typical cell sizes; 10 000 000 cells ≈ 250–320 MB.

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
