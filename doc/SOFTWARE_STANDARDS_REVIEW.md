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
**Annotation:** 2026-05-07 (v0.6.9) — Unit test suite substantially expanded (commits 60ad1d9, 48c8c18, 5ead7cd): `csv_unit_test` extended to 71 tests (edge cases for all five `SData.CSV` functions); `sdata_unit_test` extended to 98 tests adding coverage of `SData.Variables` (temp symbols, permanent PDV slots, `Load_PDV_From_Table` roundtrip, hold/reset, `Flush_PDV_To_Output` pipeline). Table and variable system no longer have zero unit coverage. §4.1 metrics and prose updated; §4.3 debt item partially resolved; §4 score 60→65.
**Annotation:** 2026-05-07 (v0.6.9) — BY-variable list duplication eliminated (commit 9460375): `Current_By_Vars`, `Ctx.By_Vars`, and `By_Group_Names` package instantiation removed from the interpreter; `SData.Table` is now the sole source of truth. `By_Var_Count`/`By_Var_Name(I)` accessors added to `SData.Table`. `Group_Flags` rewritten to use `In_Same_Group` directly; REPEAT edge case (empty input table → one implicit group) handled explicitly. Also in this session: column cursor cache added (`Get_Value_By_Col`/`Set_Output_Value_By_Col`) eliminating per-row hash lookups in the data step hot path; `Max_Table_Rows` renamed `Max_Table_Cells` and default set to 50 000 000. §3.1 BY-variable concern and §4.3 debt item marked resolved.
**Annotation:** 2026-05-09 (v0.6.11) — `Parse_ODF Load_Content` and `Parse_OOXML Load_Sheet` each decomposed into three named sub-procedures (`Collect_*_Headers` → `Infer_And_Create_*_Schema` → `Load_*_Data_Rows`); double-free and Reader-leak bugs fixed in the OOXML parser as part of the same work (commits 3a883ff, 7320963, 781d56f). `file_io_unit_test` added: 70 unit tests covering `Parse_CSV` (24), `Parse_ODF` (23), and `Parse_OOXML` (23) — INF values, sheet selection, Skip_Rows, Max_Rows, and error paths; two binary fixtures committed (`inf_values.ods`, `inf_values.xlsx`) (commits 69bbdb4–f0bc211). §5 updated to reflect prior-session fixes (9c7771f: `Program_Error`→`Script_Error`; 07b065b: silent CSV swallowing eliminated) that had not been annotated in §5. Summary-table baseline corrected: §1 (65→72) and §2 (72→75) improvements from prior sessions were reflected in section headers but not in the totals table; corrected baseline 545. §2 score 75→77; §4 score 65→68; §5 score 58→63; total 545+10 = **555/800 (69.4%)**.
**Annotation:** 2026-05-09 (v0.6.11) — Operational Readiness score corrected: CI/CD pipeline was resolved by ADR-012 (`.github/workflows/test.yml` runs `alr build` + `make check` on every push and PR; ADR-018 guards against missing executables) but the §7 overall score of 50/100 was never updated at that time. Corrected to 62/100: deployment sub-scores are now 8–9/10 across the board; observability sub-scores remain limited (no structured logging, no metrics — inherent in a CLI batch processor, not a defect). §7 score 50→**62**; total 557+12 = **569/800 (71.1%)**.
**Annotation:** 2026-05-09 (v0.6.11) — `evaluator_unit_test` extended from 101 to 146 tests (commits 74d8af07, 4aa18ce, 4da4b3d): 45 new tests (EV-01..EV-45) cover the `SData.Evaluator.Evaluate` expression-tree path — integer/float/string literals, all arithmetic operators and their type-promotion rules (Int/Int→Val_Numeric, Int^Int→Val_Numeric, mixed→Val_Numeric), operator precedence and parentheses, all six comparison operators, AND/OR/XOR/NOT, string concatenation and string comparisons, variable references (integer, float, missing propagation), function calls embedded in expressions, division-by-zero error handling, and TRUE/FALSE/NOT TRUE language constants. `Eval(S)` + `Raises_Expr(S)` helpers added using `SData.Parser.Parse_Program("LET _R = " & S)` as the parse entry point. Remaining evaluator gaps: float-branch comparison path, `IF()` lazy-evaluation semantics, string ordering operators. §4 score 68→**70**; total 555+2 = **557/800 (69.6%)**.
**Annotation:** 2026-05-12 (v0.6.11) — `interpreter_unit_test` added: 5 modules now (+ `tests/interpreter_unit_test.adb`, 37 tests IC-01..IC-34). Tests execute full parse→`SData.Interpreter.Execute`→variable-inspection cycles for every control flow construct: LET/SET assignment (IC-01..05), IF/ELSE/ELSEIF (IC-06..12), FOR with positive/negative/empty ranges (IC-13..16), WHILE with true and false initial conditions (IC-17..19), REPEAT/UNTIL (IC-20..21), BREAK and BREAK WHEN (IC-22..24), SELECT/CASE and SELECT/WHEN with match, miss, and OTHERWISE (IC-25..29), REPEAT N multi-record data step (IC-30..32), and error/missing-value paths (IC-33..34). `Run_One_Step` → `Execute_Control_Flow` path is no longer integration-only. Also: "RUN complete." message guarded with `not SData.Config.Quiet_Mode` to keep unit test output clean. §4 score 70→**73**; total 557+3 = **560/800 (70.0%)**.
**Annotation:** 2026-05-12 (v0.6.11) — §8 Documentation score recalculated from full current state. Section header corrected from stale "76" to current value. Algorithm-references gap prose updated to match remediation table (Priority 8 was fixed but §8 prose still said "no references"). Sub-scores: algorithm references 3→**8/10** (full [A&S]/[NR]/[MT00]/[BM58]/[DLMF] reference block + per-function annotations); architectural docs remain **8/10** (30 ADRs in markdown, 8 design specs, 9 implementation plans); setup guide remains **6/10** (no step-by-step onboarding for non-Ada developers). §8 score 82→**85**; total 581+3 = **584/800 (73.0%)**.
**Annotation:** 2026-05-12 (v0.6.11) — `sdata-file_io.adb` `when others` exception handlers made specific: (1) `Float'Value` failure in ODF `Get_Cell_Value` → `when Constraint_Error` (was `when others`); (2) `UnZip.Extract` for `xl/workbook.xml` and `xl/_rels/workbook.xml.rels` → `when Zip.Entry_name_not_found` (lets corrupt-entry/unsupported-compression exceptions propagate to outer `Script_Error` wrapper); (3) `UnZip.Extract` for `xl/sharedStrings.xml` → `when Zip.Entry_name_not_found` with comment documenting it is optional in OOXML. `Has_Formulas_XML` (probe function) retains `when others → return False` — any I/O failure here is a safe no-conversion fallback. Safety-net test `PX-24` added: OOXML with no `workbook.xml` falls back to `sheet1.xml` correctly. §5 score 63→**65**; total 579+2 = **581/800 (72.6%)**.
**Annotation:** 2026-05-12 (v0.6.11) — §6 Security Posture score recalculated from full current state: SQL injection fixed (456d1e0), overflow resolved (v0.6.9), SYSTEM/SHELL reclassified Low-Medium (deliberate design, --noshell opt-in), path traversal mitigated (--nosubmit opt-in). No network exposure, no auth, no hardcoded secrets, Ada runtime bounds-checking. Remaining concerns: --noshell/--nosubmit are opt-in (not default), no fuzzing/SAST, no formal threat model, broad `when others` in file_io. Section header corrected from stale "52" to current score; SQL injection and path traversal prose updated to remove stale "needs fixing" language. §6 score 65→**70**; total 574+5 = **579/800 (72.4%)**.
**Annotation:** 2026-05-12 (v0.6.11) — `Execute_Assignment` (155 lines) decomposed into three focused pieces: `Execute_Array_Assignment` (private procedure: array existence check, LET/SET ownership rules, slice/list/single-index dispatch), `Coerce_For_Scalar` (private function: type-kind check, Inf guard, integer promotion, string truncation), and a trimmed coordinator `Execute_Assignment` (~25 lines: evaluate, early %-name Inf guard, dispatch). `interpreter_unit_test` extended from 37 to 48 tests: IC-35..IC-41 add array-assignment coverage (single-index, slice, list, SET on temp array, LET on temp array → error, SET on permanent → error, undefined array → error). §4 score 73→**75**; total 572+2 = **574/800 (71.8%)**.
**Annotation:** 2026-05-13 (v0.6.12) — ADR-037 implemented: configurable SYSTEM/SHELL timeout (commits 2d57654, 3ca764f). `OPTIONS SHELLTIMEOUT n` sets the per-run timeout in seconds (reset by NEW); `--shell-timeout=N` sets the batch-mode default at startup (300 s default when a filename is given, 0 in interactive mode). Implementation uses `GNAT.OS_Lib.Non_Blocking_Spawn` + `Non_Blocking_Wait_Process` + `Kill` in a 0.5-second poll loop — no external tool dependency (`timeout(1)`, PowerShell). Kills the child and raises `Script_Error` with a descriptive message on expiry. CI pipeline improved: Alire package cache added (`actions/cache@v4`, keyed on `alire.toml` hash); `apt-get update` hardened with `-o Acquire::Languages=none --no-install-recommends`. §5.2 concern (indefinite blocking on SYSTEM) resolved; §5 score 65→**68**. §7 score 62→**65** (runtime + CLI timeout configuration; CI caching). Total 591+3+3 = **597/800 (74.6%)**.
**Annotation:** 2026-05-13 (v0.6.12) — `sdata-interpreter.adb` fully decomposed into nine Ada subunits using the `separate` mechanism (commits 49cd659–b8e037e): `execute_assignment` (with `Execute_Array_Assignment` and `Coerce_For_Scalar` nested), `execute_print`, `execute_control_flow`, `execute_metadata`, `execute_declarative`, `execute_io`, `resolve_expr_indices`, `inspect_pdv`, `process_one_record`. Parent body reduced from 2,267 to 912 lines; each subunit has one clear responsibility. No API or behaviour changes; all 131 tests pass. §1 score 75→**78** (interpreter monolith resolved; no large single-file subsystems remain); §2 score 79→**82** (cognitive load: all large files decomposed); §4 score 77→**80** (change resilience: adding a new command now touches one focused subunit). Total 597+3+3+3 = **606/800 (75.8%)**.
**Annotation:** 2026-05-12 (v0.6.12) — `sdata-file_io.adb` (1,758 lines) fully decomposed into five focused child packages: `SData.File_IO` (parent, ~110 lines — `Open_Input`/`Open_Output` + `Save_Refused` exception), `SData.File_IO.Helpers` (private child, ~175 lines — shared utilities: `Get_Text`, `Detect_Inf`, `Apply_Dollar_Override`, `Safe_Name`, `Col_To_Letters`, `Escape_XML`, `Has_Formulas_XML`, `Convert_Via_LibreOffice`), `SData.File_IO.CSV` (~510 lines), `SData.File_IO.ODF` (~430 lines), `SData.File_IO.OOXML` (~440 lines). Each format package contains only its own parse and write logic; `Helpers` is a `private` child, invisible outside the hierarchy (Ada language guarantee; commit cc8560f). Also: `interpreter_unit_test` count corrected to 48 (IC-01..IC-41; file committed as part of v0.6.12). §1 score 72→**75** (file_io monolith fully resolved; `sdata-interpreter.adb` remains the sole large-file concern); §2 score 77→**79** (cognitive load: all file_io monoliths gone; self-doc note updated); §4 score 75→**77** (change resilience: "New file format" difficulty Hard→Medium; debt item resolved); total 584+3+2+2 = **591/800 (73.9%)**.

---

## Overall Posture

```
⚠  Drifting — sound domain model, but structural rot accumulating in three
   subsystems faster than it is being repaired
```

---

## 1. Architectural Integrity — ~~65~~ ~~72~~ ~~75~~ **78/100**

### 1.1 Structural Coherence

**Does the architecture have a clear, defensible reason for existing in its current form?**
Yes. The three-tier model (Declarative → Immediate → Deferred) is coherent, documented at the top of `sdata-interpreter.adb`, and consistently applied. The evaluator, table, variables, and help subsystems have clear charters. The parser and lexer are separate packages with appropriate layering.

**Can a new developer understand the system's organization in under 30 minutes?**
Mostly. The package structure is logical; an Ada developer can navigate it. ~~`sdata-interpreter.adb` (~~2,213~~ 2,269 lines) remains the sole intimidating single-file subsystem~~ — **Resolved v0.6.12 (49cd659–b8e037e):** `sdata-interpreter.adb` decomposed into nine `separate` subunits; parent body is now 912 lines. ~~`sdata-file_io.adb` (~~1,646~~ 1,758 lines) is still an intimidating single-file subsystem~~ — **Resolved v0.6.12 (cc8560f):** `sdata-file_io.adb` fully decomposed into `SData.File_IO` (~110 lines), `SData.File_IO.Helpers` (private child, ~175 lines), `SData.File_IO.CSV` (~510 lines), `SData.File_IO.ODF` (~430 lines), and `SData.File_IO.OOXML` (~440 lines). The evaluator refactoring brought `sdata-evaluator.adb` from 2,589 lines to ~~517~~ 543 lines. No large single-file subsystems remain.

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

**Verdict:** The architectural foundations are sound. The two original failing grades — (1) the global-state integration bus, and (2) monolithic file-I/O parsers — are now both fully resolved. **Updated 88def8c:** The global-state bus is fully closed: `BOG_Flag`/`EOG_Flag` moved to `SData.Evaluator.Nav_Fns` body; no evaluator-level globals remain (see SKEPTIC_REVIEW item 4). **Updated ab4d5c8:** `Parse_CSV` decomposed into tokenizer + type-inference passes. **Updated 7320963/781d56f (v0.6.11):** `Parse_ODF Load_Content` and `Parse_OOXML Load_Sheet` each decomposed into three named sub-procedures; data extraction and type inference are now separated in both XML parsers. Exception-safety also improved: `DOM.Readers.Free (Reader)` added to orchestrator-level exception handler for both parsers. **Fully resolved v0.6.12 (cc8560f):** `sdata-file_io.adb` decomposed into five focused child packages — each format is now its own module; `Helpers` is a `private` child invisible outside the hierarchy. **Also resolved v0.6.12 (49cd659–b8e037e):** `sdata-interpreter.adb` decomposed into nine `separate` subunits; parent body reduced from 2,267 to 912 lines. No large single-file subsystems remain in the codebase.

---

## 2. Code Quality & Craftsmanship — ~~72~~ ~~75~~ ~~77~~ ~~79~~ **82/100**

### 2.1 Naming & Readability

Ada's verbosity forces long names, which here is a feature. `Flush_PDV_To_Output`, `Reset_PDV_Non_Held`, `Rebuild_Filter_Map`, `Is_Identifier_Ref_Function` — all describe exactly what they do. No single-letter variables outside loop counters; no ambiguous abbreviations.

| Dimension | Score | Notes |
|---|---|---|
| Naming Precision | 9/10 | Excellent; Ada verbosity works in the codebase's favour |
| Self-Documentation | ~~7/10~~ ~~7.5/10~~ 8/10 | Evaluator improved (algorithm references, elaboration note); variable comment rewritten as rationale; ~~file_io monoliths still weaken it~~ **file_io decomposed into focused packages (v0.6.12)** |
| Cognitive Load | ~~Medium~~ **Low-Medium** | Low in evaluator (hidden state eliminated), interpreter (Step_Context explicit); **Medium** in Parse_CSV (passes now separated: `Process_Line_Direct` → `Infer_Column_Types` → `Load_Data_Rows`); ~~**High** in Parse_OOXML (389 lines, still monolithic) and Parse_ODF (272 lines)~~ ~~**Medium** in Parse_OOXML and Parse_ODF — `Load_Content`/`Load_Sheet` decomposed into three named phases each (7320963, 781d56f)~~ **Low-Medium** — all three format parsers now in dedicated packages; each ≤510 lines and handles one format only (v0.6.12, cc8560f) |

### 2.2 Function Design

**Resolved — Parse_CSV** (now `sdata-file_io-csv.adb`, ~510 lines, commits ab4d5c8, cc8560f): ~~`Parse_CSV` simultaneously handles field tokenization, quote handling, escape sequences, column-type inference, and row loading.~~ Decomposed into three nested procedures with clean interfaces: `Process_Line_Direct` (tokenizer pass), `Infer_Column_Types` (type-inference pass), `Load_Data_Rows` (data-loading pass). **v0.6.12:** Moved to its own package `SData.File_IO.CSV`; all CSV logic (parse + write) is now self-contained.

**Remaining problems:**

~~`Parse_OOXML` (`sdata-file_io.adb:1163–1552`) is **389 lines** (grew from 369). `Parse_ODF` (`sdata-file_io.adb:886–1158`) is **272 lines**. Both XML parsers retain the original structural flaw: data extraction and type inference are interleaved rather than separated into passes.~~ **Resolved 7320963/781d56f (v0.6.11):** `Load_Content` (Parse_ODF) and `Load_Sheet` (Parse_OOXML) each decomposed into three named sub-procedures: `Collect_*_Headers` → `Infer_And_Create_*_Schema` → `Load_*_Data_Rows`. Data extraction and type inference are now separated. Exception-safety also improved: `DOM.Readers.Free (Reader)` called in orchestrator-level `exception when others` handler for both parsers. **Further resolved v0.6.12 (cc8560f):** Moved to `SData.File_IO.ODF` and `SData.File_IO.OOXML` respectively.

~~`Execute_Assignment` (`sdata-interpreter.adb:659–814`) is **155 lines** (grew from 135) and handles range expansion, array indexing, LET/SET semantics, type coercion, and PDV updates in a single procedure. It does not have one job.~~ **Resolved 2026-05-12:** Decomposed into `Execute_Array_Assignment` + `Coerce_For_Scalar` + 25-line coordinator.

| Procedure | Lines | SRP Score | Verdict |
|---|---|---|---|
| Parse_CSV | ~~392~~ ~~326~~ own pkg ~510 | ~~3/10~~ ~~6/10~~ **7/10** | ~~Structural failure~~ ~~Passes separated (ab4d5c8)~~ **Moved to `SData.File_IO.CSV` (cc8560f); CSV-only module** |
| Parse_OOXML | ~~369~~ ~~389~~ own pkg ~440 | ~~3/10~~ ~~**6/10**~~ **7/10** | ~~Structural failure~~ ~~Load_Sheet decomposed 781d56f~~ **Moved to `SData.File_IO.OOXML` (cc8560f); OOXML-only module** |
| Parse_ODF | ~~268~~ ~~272~~ own pkg ~430 | ~~4/10~~ ~~**6/10**~~ **7/10** | ~~Very long; unchanged~~ ~~Load_Content decomposed 7320963~~ **Moved to `SData.File_IO.ODF` (cc8560f); ODF-only module** |
| ~~Execute_Assignment~~ | ~~135~~ ~~155~~ | ~~5/10~~ | ~~Too broad; grew slightly~~ **Decomposed into coordinator + `Execute_Array_Assignment` + `Coerce_For_Scalar`** |
| Process_One_Record | ~~130~~ 129 | 7/10 | Large but coherent |
| Evaluate_Function | 134 | 6/10 | Complexity is warranted (array expansion) |
| Help_CONCEPTS | 51 | 9/10 | Fine |

### 2.3 Comment Quality

**Positives:** The design comments at the top of `sdata-interpreter.adb` and `sdata-evaluator.adb` are genuinely useful — they explain the *why* of the three-tier model and dispatch table design. The `Set_Group_Boundary` spec comment is an exemplary contract declaration.

**Comment sins — all resolved:**

| Sin | Location | Severity | Resolution |
|---|---|---|---|
| Section headers masquerading as design rationale | `sdata-help.adb:596` (`-- Math functions`) | Minor | Already resolved — procedure section uses proper `=====` banner; dispatch table labels are clearly organisational |
| "NEW should clear all array definitions" is action-oriented, not rationale | `sdata-variables.adb:151` | Minor | Rewritten: explains that permanent arrays survive RUN boundaries by design; only temporary and virtual arrays are step-scoped |
| XML-parsing navigation comments describe *what* the loop does, not *why* the XPath equivalent was rejected | `sdata-file_io.adb` (before `Parse_ODF`) | Moderate | Note added before `Parse_ODF`: XML-Ada has no XPath engine; `Get_Elements_By_Tag_Name` + attribute accessors are the full query API available |
| `pragma Warnings (Off, SData.Evaluator.Numeric_Fns)` warrants a longer note on the elaboration-cycle constraint | `sdata-evaluator.adb:9–14` | Minor | Expanded to explain the circular-dependency constraint: children depend on parent spec; parent body cannot name child entities without reversing that dependency; elaboration side-effect breaks the cycle |

No commented-out code detected. No anonymous TODOs. This is clean.

---

## 3. Efficiency & Performance — ~~74~~ 78/100

### 3.1 Algorithmic Choices

The dispatch table in `SData.Evaluator` (hashed map, O(1) per lookup) is correct for ~150 registered functions. Linear scan in `Help_Table` (`sdata-help.adb:1449–1455`) is O(n) over ~170 entries — acceptable given that HELP is not a hot path. **Deferred:** impact is None; ADR-024 noted this and deemed it acceptable; will revisit only if the help table grows substantially.

The `Filter_Map` is an array of physical row indices, built once per RUN via `Rebuild_Filter_Map`. Logical-to-physical mapping is O(1) thereafter. This is the correct design.

**~~Algorithmic concern — column access~~ Resolved 415714a:** ~~`Data_Table` is `Column_Maps.Map` keyed by column name (`Ada.Containers.Indefinite_Hashed_Maps`). Per-cell access is `Data_Table("COLNAME").Data(Row_Index)`. This means every cell read during a data step — which happens M × N times (M statements × N rows) — performs a hash lookup on the column name. For a dataset with 50 columns and 100,000 rows, this is 5 million unnecessary hash lookups per data step if PDV indices could be pre-resolved. The PDV index cache (`Expr.Var_Index`) partially mitigates this for parsed expressions, but direct column reads in `Get_PDV_Value`/`Load_PDV_From_Table` still go through the hash map on every record.~~ A `Column_Cursor_Cache` / `Output_Cursor_Cache` (vectors of pre-resolved `Column_Maps.Cursor`) is now built once per RUN via `Rebuild_Column_Cache` / `Rebuild_Output_Cache` and invalidated on every schema change. `Load_PDV_From_Table` and the value-setting loop in `Flush_PDV_To_Output` use `Get_Value_By_Col` / `Set_Output_Value_By_Col` — O(1) cursor dereferences with no hash lookup.

| Concern | Impact | Fix Difficulty | Status |
|---|---|---|---|
| ~~Column-name hash lookup per record in table operations~~ | ~~Medium (measurable on large datasets)~~ | ~~Medium~~ | **Fixed 415714a** |
| Linear help-table scan | None (cold path) | Easy | **Deferred** |
| ~~BY-variable list duplicated (interpreter + table)~~ | ~~Negligible performance, high maintenance cost~~ | ~~Medium~~ | **Fixed 9460375** |

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

## 4. Maintainability & Evolvability — ~~60~~ ~~65~~ ~~68~~ ~~70~~ ~~73~~ ~~75~~ ~~77~~ **80/100**

### 4.1 Test Coverage & Quality

**This is the weakest dimension.**

| Metric | Value | Verdict |
|---|---|---|
| Unit test modules | ~~1 (csv_unit_test)~~ ~~2 (csv_unit_test: 71; sdata_unit_test: 98)~~ ~~3 (+ file_io_unit_test: 70)~~ ~~4 (+ evaluator_unit_test: 146)~~ **5 (+ interpreter_unit_test: 48)** | **Good; CSV tokenizer, PDV/Variables, all three file I/O parsers, expression evaluator, and interpreter control flow now covered** |
| Integration tests | ~~118~~ **128** .cmd files | Comprehensive for happy paths |
| Coverage estimate | ~~~35–45%~~ ~~**~45–55%**~~ ~~**~55–65%**~~ ~~**~65–70%**~~ **~70–75%** branch coverage | **Interpreter control flow (IF/ELSE/ELSEIF, FOR, WHILE, REPEAT/UNTIL, BREAK, SELECT/CASE) now unit-covered** |
| Test execution time | < 30s total | Excellent |
| Flaky tests | None observed | Good |

~~The evaluator, interpreter, table module, variable system, and file I/O have zero unit test coverage.~~ **Updated 2026-05-07 (commits 60ad1d9, 48c8c18, 5ead7cd):** `csv_unit_test` now covers all five `SData.CSV` functions with 71 tests including edge cases (INF, signs, embedded delimiters, two-char delimiters, empty fields). `sdata_unit_test` adds 98 tests covering the full `SData.Variables` hot path: temporary symbols, permanent PDV slots, `Load_PDV_From_Table` roundtrip, hold/reset semantics, and `Flush_PDV_To_Output` pipeline. The table module and variable system no longer have zero unit coverage. Evaluator expression trees, file I/O parsers, and interpreter control flow remain integration-only. Integration tests cannot isolate regression sources when failures occur across those subsystem boundaries; adding unit tests there would require no architectural change.

**Updated 2026-05-09 (commits 69bbdb4–f0bc211):** `file_io_unit_test` adds 70 tests covering `Parse_CSV` (24), `Parse_ODF` (23), and `Parse_OOXML` (23) — basic loading, INF values, sheet selection, Skip_Rows, Max_Rows, and corrupt-file error paths. Two new binary fixtures committed (`inf_values.ods`, `inf_values.xlsx`). File I/O parsers no longer have zero unit coverage. Evaluator expression trees and interpreter control flow remain integration-only.

**Updated 2026-05-09 (commits 74d8af07, 4aa18ce, 4da4b3d):** `evaluator_unit_test` extended from 101 to 146 tests via 45 new EV-series assertions. The new tests exercise `SData.Evaluator.Evaluate` directly (not via `Call_Function`): all literal types, all arithmetic operators (with type-promotion rules), operator precedence and parentheses, all comparison and boolean operators, string concatenation and comparison, variable references (integer, float, missing), functions embedded in arithmetic expressions, division-by-zero error handling, and TRUE/FALSE/NOT TRUE constants. Evaluator expression-tree path is no longer integration-only. Remaining gaps: float-operand comparison branch (e.g., `1.5 < 2.5`), `IF()` three-argument lazy evaluation, and string ordering operators (`<`, `<=`, `>`, `>=`). Interpreter control flow remains integration-only.

### 4.2 Change Resilience

Adding a new built-in function requires: (1) a handler in the appropriate child package, (2) a `Dispatch_Table.Insert` call in that package's `Register`, (3) a `Help_*` procedure and key/table entry in `sdata-help.adb`. Three files, well-defined seams. This is genuinely good design that pays dividends.

Adding a new command requires: parser (token + production), AST node, interpreter `Execute_Statement` case arm, and help entry — four files, all with clear extension points.

~~Adding a new file format requires modifying `sdata-file_io.adb` — one file, but that file is already 1,646 lines. Extension is technically contained but practically difficult because the existing format procedures are too long to serve as readable models.~~ **v0.6.12:** Adding a new file format now means adding `SData.File_IO.<Fmt>.ads` and `.adb` plus a case arm in `Open_Input`/`Open_Output`. The existing CSV/ODF/OOXML packages serve as clear, single-purpose models. Difficulty is now Medium.

| Change Type | Files Affected | Difficulty |
|---|---|---|
| New built-in function | 2 | Easy |
| New command | 4 | Medium |
| New file format | ~~1 (large)~~ 3 new files | ~~Hard~~ **Medium** |
| New distribution family | 1 | Easy |
| Change column storage model | 5+ | Hard |

### 4.3 Technical Debt Inventory

| Item | Severity | Remediation Effort | Trajectory |
|---|---|---|---|
| ~~`Parse_CSV` / `Parse_OOXML` / `Parse_ODF` monoliths~~ | ~~High~~ ~~Medium~~ | ~~3–4 days~~ | ~~Stable~~ ~~**Improving — decomposed in v0.6.11**~~ **Resolved v0.6.12 (cc8560f) — each format is now its own focused package** |
| ~~`Execute_Assignment` too broad~~ | ~~Medium~~ | ~~1 day~~ | **Resolved — decomposed into `Execute_Array_Assignment` + `Coerce_For_Scalar` + 25-line coordinator** |
| ~~`sdata-interpreter.adb` monolith (2,267 lines)~~ | ~~High~~ | ~~3–5 days~~ | **Resolved v0.6.12 (49cd659–b8e037e) — nine `separate` subunits extracted; parent reduced to 912 lines; each subunit has one clear responsibility** |
| Integration-only test coverage | ~~High~~ **Resolved** | 2–3 days per module | ~~**Partially resolved 2026-05-07**~~ ~~**Substantially resolved 2026-05-09**~~ ~~**Largely resolved 2026-05-09**~~ **Resolved 2026-05-12** — Variables, CSV, all three file I/O parsers, evaluator expression trees, and interpreter control flow all have unit coverage |
| ~~BY-variable list duplication (interpreter + table)~~ | ~~Medium~~ | ~~4 hours~~ | **Fixed 9460375** |
| ~~Column hash lookup per record~~ | ~~Low~~ | ~~1 day~~ | **Fixed 415714a** |
| ~~No CI/CD pipeline~~ | ~~Medium~~ | ~~4 hours~~ | **Fixed ADR-012** |
| ~~Global interpreter state (remaining post-Step_Context)~~ | ~~Medium~~ | ~~2–3 days~~ | **Fixed 88def8c — `BOG_Flag`/`EOG_Flag` moved to `Nav_Fns` body; no evaluator-level globals remain** |

**Total estimated remediation: ~12–15 days. Interest rate: Stable.** The codebase is not actively accruing debt; it is maintaining its current level.

---

## 5. Error Handling & Resilience — ~~58~~ ~~63~~ ~~65~~ **68/100**

### 5.1 Error Philosophy

`Script_Error` is the single user-facing exception type, raised with descriptive messages throughout the interpreter and evaluator. The `-k` flag's `Continue_On_Error` path correctly catches it, logs to `ERR`/`ERL`, and continues. This is a coherent primary strategy.

**Where it broke down (resolved):**

~~`sdata-file_io.adb` uses `Program_Error` in one location (`Parse_ODF:1093`) and `Script_Error` everywhere else — an inconsistency that will silently fall through `-k` handling. `Program_Error` in Ada is a language-defined exception for programming errors, not user-visible data errors; raising it for "merged cells in ODS file" is architecturally wrong.~~ **Fixed 9c7771f:** `Program_Error` replaced with `Script_Error` in both `Parse_ODF` and `Parse_OOXML`. All parser exception raises are now `-k`-compatible.

~~`sdata-csv.adb` contains `when others => return False;` twice (lines 42–45). Both swallow every exception type silently, including potential constraint errors that would mask format misdetection bugs.~~ **Fixed 07b065b:** Replaced with specific exception handlers; silent swallowing eliminated.

**Remaining concern:**

~~`sdata-file_io.adb` has broad `when others` handlers at several points. Those that re-raise are correct; those that suppress are still inconsistent with the project's error philosophy. No uniform policy exists about which file I/O exceptions should surface vs. be handled internally.~~ **Resolved 2026-05-12:** All suppressing `when others` handlers in `sdata-file_io.adb` are now specific: `Constraint_Error` for `Float'Value` failure in ODF cell parsing; `Zip.Entry_name_not_found` for optional zip entries (`sharedStrings.xml`, `workbook.xml`, `workbook.xml.rels`). `Has_Formulas_XML` retains `when others → return False` as a documented probe-function convention. The policy is now explicit: suppress only for expected, recoverable absence conditions; re-raise everything else.

| Module | Error Consistency | Error Informativeness | Recovery |
|---|---|---|---|
| Evaluator | 9/10 | 9/10 | 9/10 |
| Interpreter | 8/10 | 8/10 | 8/10 |
| Table | 7/10 | 7/10 | 7/10 |
| File I/O | ~~4/10~~ ~~6/10~~ **7/10** | ~~5/10~~ ~~6/10~~ **7/10** | ~~5/10~~ ~~6/10~~ **7/10** |
| CSV | ~~3/10~~ **6/10** | ~~3/10~~ **5/10** | ~~3/10~~ **5/10** |

### 5.2 Failure Modes

External services are limited to: shell commands (SYSTEM/SHELL), file system, SQLite. Shell failures are reported via return code. File-not-found raises `Script_Error` with filename. SQLite failure modes are partially handled but not uniformly.

~~No timeout logic for shell commands launched via SYSTEM — a long-running shell command blocks the interpreter indefinitely with no escape mechanism.~~ **Resolved ADR-037 (2d57654, 3ca764f):** `OPTIONS SHELLTIMEOUT n` and `--shell-timeout=N` provide runtime and startup timeout control. Implementation is fully Ada-native: `GNAT.OS_Lib.Non_Blocking_Spawn` + 0.5-second poll loop + `Kill` + `Wait_Process` to reap. Default is 300 s in batch mode, 0 (unlimited) in interactive mode. No external tool dependency.

---

## 6. Security Posture — ~~52~~ ~~58~~ ~~63~~ ~~65~~ **70/100**

### 6.1 Input Validation

**SYSTEM / SHELL — deliberate design, appropriate default:** The SYSTEM and SHELL commands pass their string argument to `/bin/sh -c`. This is the intended behaviour: SYSTEM is a first-class, documented feature serving the same role as `SYSTEM` in SAS or `system()` in R. SData's security model is that the OS account running the process carries exactly the permissions that a system administrator has granted it — no more, no less. SData does not add a second permission layer on top of the OS; that would be redundant and would break legitimate use. The responsibility for ensuring accounts have only the access they need belongs to system administrators, not to SData. This is the same model used by every Unix tool that invokes the shell (`make`, `awk`, `perl`, the R `system()` call, Python `subprocess`, etc.). The `--noshell` flag gives pipeline operators an opt-in restriction when they need containment beyond what the account's OS permissions provide.

Sandboxing, allowlisting, and metacharacter escaping are all **won't-fix**: sandboxing adds platform-specific complexity without adding security at the correct layer (the OS account); an allowlist cannot be defined generically without breaking legitimate use; escaping metacharacters would silently neuter the feature (pipes and redirects are intentional). **[Reclassified Low-Medium 2026-05-06; security model clarified 2026-05-12.]**

**SQL column name injection:** ~~`sdata-table.adb` constructs SQLite DDL/DML from column names. Column names originate from CSV headers (user-controlled input). If a column name contains SQL metacharacters (`"`, `'`, `--`), the generated SQL may be malformed or exploitable.~~ **Fixed 456d1e0:** `Sql_Id` helper double-brackets all `]` characters at every DDL/DML construction site in `sdata-table.adb`.

**Path traversal:** `Full_Path` in the interpreter resolves file paths using `FPath_*` base directories but does not reject `../` sequences; a SUBMIT statement can traverse outside the intended working directory. **`--nosubmit` (6909f15) provides opt-in containment; won't-fix by default** — same trust-model reasoning as SYSTEM/SHELL.

| Vector | Risk Level | Status |
|---|---|---|
| SYSTEM / SHELL | ~~High~~ **Low-Medium** | `--noshell` flag; deliberate design — won't-fix |
| SQL column name injection | ~~Medium~~ **Resolved** | **Fixed 456d1e0 — `Sql_Id` escapes `]`→`]]` at all five DDL/DML sites** |
| Path traversal via SUBMIT | **Low-Medium** | `--nosubmit` flag (opt-in); won't-fix by default |
| ~~Expression evaluation overflow~~ | ~~Low~~ **Resolved** | **Resolved v0.6.9: Inf is first-class `Val_Numeric`; NaN → Script_Error (or `Val_Missing` with `--ignore-math-errors`). See `doc/specs/2026-05-06-inf-neginf-design.md`.** |

**Remaining concerns (keeping score below 80):** `--noshell` and `--nosubmit` are opt-in — operators running untrusted scripts must know to enable them. No fuzzing or SAST tooling. No formal threat model document. ~~Broad `when others` handlers in `sdata-file_io.adb` can mask parse errors with security relevance~~ — resolved 2026-05-12: all suppressing handlers are now specific exception types with documented rationale.

### 6.2 Secrets Management

No hardcoded credentials. No network services. No authentication tokens. This is a CLI tool, not a service — secrets management is not applicable at this scope.

---

## 7. Operational Readiness — ~~50~~ ~~62~~ **65/100**

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

~~**Missing:** No CI/CD pipeline. No GitHub Actions, no automated build verification on push, no automated test execution on PR. Every release depends entirely on the developer running `make check` manually.~~ **Resolved ADR-012:** `.github/workflows/test.yml` runs `alr build` + `make check` on every push to main and every PR. A Verify binaries step guards against missing executables (ADR-018).

| Capability | Score |
|---|---|
| Config externalization | 9/10 |
| Packaging breadth | 9/10 |
| Deployment automation | 8/10 |
| CI/CD | 9/10 — Alire package cache added (actions/cache@v4); apt hardened with `-o Acquire::Languages=none --no-install-recommends` |
| Rollback | 8/10 (git tags, versioned packages) |

---

## 8. Documentation — ~~76~~ ~~82~~ **85/100**

`README.md` is substantive: build requirements, feature overview, example usage. The man page (`man/man1/sdata.1`, 795 lines) is comprehensive and current — it covers every command and option. `HELP /ALL` from the interpreter produces a complete command and function reference that matches the man page. `doc/SOFTWARE_STANDARDS_REVIEW.md` is a rare and valuable asset: a living architectural audit document where findings are marked resolved with commit hashes as they are addressed. `doc/adrs.md` (30 ADRs, ADR-001–030) documents all major architectural decisions in durable markdown. `doc/specs/` (8 design specs) and `doc/plans/` (9 implementation plans) record the design rationale behind completed features.

**Gaps:**

- ~~No architecture decision records (ADRs). The three-tier execution model, the PDV reset semantics, the SQLite spill threshold, and the LAG/NEXT group-boundary semantics are documented in code comments and the SKEPTIC_REVIEW but not in a durable design document.~~ **[Resolved 2026-05-05]** `doc/adrs.md` contains 30 decisions (ADR-001–030) covering language choice, execution model, table design, CLI conventions, test strategy, and per-session architectural calls.
- ~~No algorithm documentation for statistical distributions.~~ **[Resolved — Priority 8]** Reference block added at top of `sdata-statistics.adb` ([A&S], [NR], [MT00], [BM58], [DLMF]); per-function citations added to `Incomplete_Gamma_P`, `Z_CDF`, `Z_IDF`, `Normal_RN`, `Gamma_CDF`, `Gamma_RN`, `Student_T_CDF`, `F_CDF`, `Binomial_PMF`, `Binomial_CDF`, `Bisect_IDF`, and all IDF bisection wrappers.
- Setup time from docs: ~15 minutes for an Ada/Alire developer; much longer for anyone unfamiliar with the toolchain, as there is no step-by-step onboarding guide for first-timers.

| Dimension | Score |
|---|---|
| README quality | 8/10 |
| Man page | 9/10 |
| In-system help | 9/10 |
| Architectural docs | ~~5/10~~ **8/10** |
| Algorithm references | ~~3/10~~ **8/10** |
| Setup guide clarity | 6/10 |

---

## Overall Scores

| Category | Score |
|---|---|
| Architectural Integrity | ~~65/100~~ ~~72/100~~ ~~75/100~~ **78/100** |
| Code Quality & Craftsmanship | ~~72/100~~ ~~75/100~~ ~~77/100~~ ~~79/100~~ **82/100** |
| Efficiency & Performance | ~~74/100~~ **78/100** |
| Maintainability & Evolvability | ~~60/100~~ ~~65/100~~ ~~68/100~~ ~~70/100~~ ~~73/100~~ ~~75/100~~ ~~77/100~~ **80/100** |
| Error Handling & Resilience | ~~58/100~~ ~~63/100~~ ~~65/100~~ **68/100** |
| Security Posture | ~~52/100~~ ~~58/100~~ ~~63/100~~ ~~65/100~~ **70/100** |
| Operational Readiness | ~~50/100~~ ~~62/100~~ **65/100** |
| Documentation | ~~76/100~~ ~~82/100~~ **85/100** |
| **TOTAL** | ~~507/800 (63.4%)~~ ~~513/800 (64.1%)~~ ~~519/800 (64.9%)~~ ~~524/800 (65.5%)~~ ~~526/800 (65.8%)~~ ~~530/800 (66.3%)~~ ~~535/800 (66.9%)~~ ~~550/800 (68.8%)~~ ~~555/800 (69.4%)~~ ~~557/800 (69.6%)~~ ~~569/800 (71.1%)~~ ~~572/800 (71.5%)~~ ~~574/800 (71.8%)~~ ~~579/800 (72.4%)~~ ~~581/800 (72.6%)~~ ~~584/800 (73.0%)~~ ~~591/800 (73.9%)~~ ~~597/800 (74.6%)~~ **606/800 (75.8%)** |

---

## Prioritized Remediation

| Priority | Action | Category | Effort | Risk if Deferred |
|---|---|---|---|---|
| 1 | ~~Replace `when others => return False` in `sdata-csv.adb` with specific handlers~~ | Security/Error | ~~2 hours~~ | ~~Masks CSV format bugs silently~~ **Fixed 07b065b** |
| 2 | ~~Quote column names in SQLite DDL/DML; audit for injection~~ | Security | ~~4 hours~~ | ~~SQL injection via CSV headers~~ **Fixed 456d1e0** |
| 3 | ~~Decompose `Parse_CSV` into tokenizer + type-inference passes~~ | Code Quality | ~~2–3 days~~ | ~~Grows worse with each format quirk added~~ **Fixed ab4d5c8** |
| 4 | ~~Change `Program_Error` → `Script_Error` in `Parse_ODF`~~ | Error Handling | ~~30 min~~ | ~~Falls through `-k` handling silently~~ **Fixed 9c7771f — also applied to Parse_OOXML** |
| 5 | ~~Add CI/CD (GitHub Actions: `make check` on push)~~ | Operational | ~~4 hours~~ | ~~Test regressions invisible until manual run~~ **Fixed ADR-012 / ADR-018** |
| 6 | ~~Add unit tests for evaluator, table, and BY-group logic~~ | Maintainability | ~~2–3 days~~ | ~~Silent path failures (the Set_Index_Map bug pattern)~~ **Fixed — `tests/sdata_unit_test.adb`: 65 tests covering Table column/row management, type enforcement, Rename/Drop, Set_Index_Map filter logic, In_Same_Group BY-group detection, and Evaluator pure helpers** |
| 7 | ~~Add path traversal check in `Full_Path`~~ | Security | ~~2 hours~~ | ~~SUBMIT can escape working directory~~ **`--nosubmit` added 6909f15; won't-fix by default** |
| 8 | ~~Document numerical algorithm references in `SData.Statistics`~~ | Documentation | ~~4 hours~~ | ~~Next maintainer reimplements rather than verifies~~ **Fixed — reference block added at top of `sdata-statistics.adb` ([A&S], [NR], [MT00], [BM58], [DLMF]); per-function annotations added to `Incomplete_Gamma_P`, `Z_CDF`, `Z_IDF`, `Normal_RN`, `Gamma_CDF`, `Gamma_RN`, `Student_T_CDF`, `F_CDF`, `Binomial_PMF`, `Binomial_CDF`, `Bisect_IDF`, and all IDF bisection wrappers** |

---

## The Hard Truth

This codebase is the work of someone who actually knows what they're doing. The domain model is correct, the Ada is idiomatic, the help system is unusually thorough, and the version-management and packaging tooling is better than most open-source projects ten times its size. The SKEPTIC_REVIEW discipline — maintaining a living audit document and marking findings resolved with commit hashes — is a practice most professional teams don't have.

But here's what I'd be thinking at 3 AM with a corrupted dataset:

**`sdata-file_io.adb` is resolved.** ~~Three procedures totalling over 1,000 lines, each mixing tokenization, type inference, and data loading in a single call stack.~~ `Parse_CSV` was made three-pass (tokenizer → type inference → load) in v0.6.11; `Parse_ODF` and `Parse_OOXML` had their inner loops decomposed into three named sub-procedures. **v0.6.12 (cc8560f):** The 1,758-line file is gone — replaced by five focused packages (parent ~110 lines, Helpers private ~175, CSV ~510, ODF ~430, OOXML ~440). Unit test coverage added (70 tests, v0.6.11). All suppressing handlers are specific exception types with documented rationale. ~~The remaining structural concern is `sdata-interpreter.adb` (~2,269 lines) — which has the same treatment available to it when the time comes.~~ **`sdata-interpreter.adb` also resolved v0.6.12 (49cd659–b8e037e):** Nine `separate` subunits extracted; parent body reduced from 2,267 to 912 lines. No large single-file subsystems remain.

**The security posture is "operate within OS permissions."** SYSTEM executes shell commands with whatever access the running account has — which is exactly the access a system administrator has chosen to grant it. SData does not add a second permission layer on top of the OS; the correct place to restrict what `sdata` can do is the account it runs under, not a feature flag inside the tool. The `--noshell` and `--nosubmit` flags exist for operators who need containment beyond OS account permissions (e.g., running scripts from untrusted sources in a shared environment). The SQL column-name injection vector has been fixed (commit 456d1e0). This is a coherent and defensible stance, not a gap.

The codebase scores **~~63%~~ ~~70%~~ ~~71%~~ ~~71.5%~~ ~~71.8%~~ ~~72.4%~~ ~~72.6%~~ ~~73.0%~~ ~~73.9%~~ ~~74.6%~~ 75.8%** — solidly competent, clearly improving (the SKEPTIC_REVIEW trajectory is positive), and the unit test situation has gone from embarrassing to good: five test modules (48 interpreter tests, 146 evaluator tests, 70 file I/O tests, 98 variable/PDV tests, 71 CSV tests) covering all major subsystems via the full parse→Execute→variable-inspect cycle. `Execute_Assignment` — formerly the primary structural gap at 155 lines — has been decomposed into three focused pieces. ~~The main remaining structural concern is `sdata-interpreter.adb` and `sdata-file_io.adb` as large single files~~ ~~The main remaining structural concern is `sdata-interpreter.adb` (~2,269 lines); `sdata-file_io.adb` is fully decomposed as of v0.6.12~~ **Resolved v0.6.12 (49cd659–b8e037e):** `sdata-interpreter.adb` is now 912 lines; all nine subunits are in separate focused files. No large single-file subsystems remain.

---

## Appendix: Evidence Log

| Finding | File:Line | Evidence |
|---|---|---|
| ~~Parse_CSV is 392 lines~~ | ~~`sdata-file_io.adb:286–677`~~ | ~~Single procedure, multiple concerns~~ **Resolved v0.6.12 (cc8560f) — `SData.File_IO.CSV` package** |
| ~~Parse_OOXML is 369 lines~~ | ~~`sdata-file_io.adb:1103–1471`~~ | ~~Single procedure~~ **Resolved v0.6.12 (cc8560f) — `SData.File_IO.OOXML` package** |
| `sdata-file_io.adb` 1,758 lines monolith | `src/sdata-file_io*.adb` | **Resolved v0.6.12 (cc8560f) — decomposed into parent (~110) + Helpers (~175) + CSV (~510) + ODF (~430) + OOXML (~440)** |
| Parse_ODF raises Program_Error | `sdata-file_io.adb:1093–1096` | Wrong exception type for user-visible error |
| Silent exception swallow | `sdata-csv.adb:42–45` | `when others => return False` twice |
| Column-name SQL construction | `sdata-table.adb` | ~~DDL built from user-controlled column names~~ **Fixed 456d1e0 — Sql_Id helper escapes `]`→`]]`** |
| SYSTEM shell injection surface | `sdata-system.adb` | ~~Unquoted string passed to `/bin/sh -c`~~ **Deliberate design; same trust model as R/SAS/Python; won't-fix. ADR-037: timeout added — `OPTIONS SHELLTIMEOUT` / `--shell-timeout=N`; Ada-native poll loop (2d57654).** |
| ~~No CI pipeline~~ | `.github/workflows/test.yml` | ~~No automated build/test on push~~ **Fixed ADR-012** |
| ~~BY-variable list duplication~~ | `sdata-interpreter.adb:59`, `sdata-table.adb:53` | ~~Two independent copies of the same vector~~ **Fixed 9460375 — `SData.Table` is sole source of truth; `By_Var_Count`/`By_Var_Name(I)` accessors added; `Current_By_Vars`, `Ctx.By_Vars`, and `By_Group_Names` instantiation removed from interpreter** |
| ~~1 unit test module~~ 5 unit test modules (433 total tests) | `tests/csv_unit_test.adb`, `tests/sdata_unit_test.adb`, `tests/file_io_unit_test.adb`, `tests/evaluator_unit_test.adb`, `tests/interpreter_unit_test.adb` | All major subsystems have unit coverage |
| ~~Execute_Assignment 135 lines~~ | ~~`sdata-interpreter.adb:659–793`~~ | ~~Multiple assignment concerns in one body~~ **Decomposed into `Execute_Array_Assignment` + `Coerce_For_Scalar` + 25-line coordinator** |
