# Codebase Review: `SData — Statistical Data Interpreter`

**Reviewed:** 2026-04-17
**Scope:** Full repository — all 29 Ada source files, test suite, CI configuration, build system, packaging
**Domain:** Systat BASIC-style statistical data language interpreter; reads/writes CSV, ODS, XLSX; processes tabular data through a PDV-based data step
**Stack:** Ada 2012, GPRBuild/Alire, GNU Make; dependencies: Zip-Ada, XML/Ada, MathPaqs, SQLite (via GNATColl)
**Voices Activated:** Fowler, Uncle Bob, Beck, Feathers, Kleppmann, Jobs

---

## Overall Posture

```
⚠  Drifting — coherent intent undermined by accumulating decisions
```

**In one sentence:** The core execution model is sound and considerable cleanup has landed recently, but the evaluator has grown a structural dependency that inverts its place in the architecture, and the dispatch table refactoring is only half-complete.

---

## Fowler — Architecture & Evolutionary Design

> *Refactoring, software smells, distribution decisions, change-enabling structure*

### Findings

**🔴 Problem — The evaluator depends on the interpreter**
`src/sdata-evaluator.adb`, line 1

```ada
with SData.Interpreter;
```

The intended dependency direction is `Interpreter → Evaluator`: the interpreter drives the data step, calls the evaluator to compute expressions, and owns BY-group state. Instead, the evaluator reaches back into `SData.Interpreter` to call `In_Same_Group` (lines 801, 834) when computing `LAG` and `NEXT` across group boundaries. This is a cycle at the body level: the evaluator cannot be compiled, loaded, or tested without the interpreter, and the interpreter cannot be tested without the evaluator. Any future change to `In_Same_Group`'s contract requires understanding both packages simultaneously. This is the most structurally consequential problem in the codebase.

**⚠ Concern — The dispatch table refactoring is half-complete**
`src/sdata-evaluator.adb`, lines 39–43 (comment), `Handle_Math`, `Handle_Trig`

The comment documents the current state honestly: "Math, trig, aggregate, and misc families share a handler and use Name to discriminate among members." String, navigation, and statistics functions each have a dedicated Ada subprogram registered individually in the dispatch table. But `Handle_Math`, `Handle_Trig`, and the aggregate/misc handlers are shared functions with internal if-elsif chains. The per-function dispatch table pattern is already in the codebase — finishing the migration for the math and trig families is mechanical work, not design work.

**⚠ Concern — `Config` bundles three distinct responsibilities**
`src/sdata-config.ads`

The Config package holds: (1) static CLI configuration (Input_Format, Output_Format, file paths, constraint limits, mode flags), (2) runtime interpreter state in `Runtime_State_Record` (Save pending, REPEAT mode, FPATH directories), and (3) version metadata (Version_Major/Minor/Patch). The introduction of `Runtime_State_Record` is a real improvement — runtime state is now explicitly grouped and `Reset_Runtime_State` has a clear scope. But all three responsibilities still live in one package, so any package that needs only version info must `with` the same package that owns mutable runtime state.

### Fowler's Recommendation

Break the evaluator→interpreter cycle first. `In_Same_Group` compares BY-group membership for two physical row indices — this is a function of BY-variable state, not of the interpreter. Moving it to `SData.Table` (which already owns row/column structures) removes the back-dependency entirely and costs nothing in behavior. Complete the dispatch table migration for `Handle_Math` and `Handle_Trig`: each function in those families is already handled identically in structure to the string/navigation functions. Separate version constants into `SData.Version` (a pure constants package with no mutable state) as a first step toward splitting Config.

---

## Uncle Bob — Code Structure & SOLID

> *Clean code, dependency direction, modularity, naming, separation of concerns*

### Findings

**🔴 Problem — Circular dependency inverts the evaluator's intended role**
`src/sdata-evaluator.adb`, line 1; `src/sdata-interpreter.ads`, line 28

The evaluator exists to serve the interpreter. In no layered architecture should the evaluator depend on the interpreter. The current cycle means that `In_Same_Group` — a query about BY-group membership — is declared on the interpreter's public interface even though it is only called by the evaluator. This pollutes the interpreter's API surface with an obligation that belongs elsewhere, and it makes it impossible to satisfy the Dependency Inversion Principle: there is no abstraction the evaluator can depend on that the interpreter also satisfies without the cycle.

**⚠ Concern — Config SRP: three responsibilities, one package**
`src/sdata-config.ads`

The `Runtime_State_Record` grouping is a step in the right direction — runtime state can now be reset atomically via `Reset_Runtime_State`. But `SData.Config` is still both the package a CLI argument parser writes to and the package the interpreter reads runtime state from. A package that is simultaneously a startup-configuration store and a per-run mutable state store cannot have its invariants reasoned about independently.

### Uncle Bob's Recommendation

Move `In_Same_Group` to `SData.Table` and remove the `with SData.Interpreter` clause from `sdata-evaluator.adb` — this is the minimal change that breaks the cycle. For Config: extract `SData.Config.Runtime` as a child package (or a top-level `SData.Runtime` package) that holds `Runtime_State_Record` and `Reset_Runtime_State`. This gives the interpreter a clean target to `with` without pulling in CLI-level configuration concerns.

---

## Beck — Tests & Feedback Loops

> *Test quality, TDD signals, YAGNI, incremental design, feedback cycle length*

### Findings

**⚠ Concern — Output comparison tests at the suite boundary, nothing below it**
`tests/`

All 77 tests exercise the full pipeline: parse → interpret → evaluate → render output → diff. There are no unit tests for `SData.Statistics` (are the distribution implementations correct?), `SData.Table` (does the filter index rebuild correctly after column modification?), or `SData.Evaluator` (does `ROUND(1.5)` round correctly?). The regression suite catches regressions in observed output but gives no signal when an internal invariant breaks silently. A bug that produces wrong numbers but the same number of lines will pass.

### Beck's Recommendation

Break the evaluator→interpreter cycle first — that is what creates the seam needed to write evaluator unit tests. Once the seam exists, add at minimum: (a) evaluator tests for boundary cases in `ROUND`, `MOD`, `LOG(0)`, and `IF` with a failing branch; (b) statistics tests for known CDF values against published tables. These do not need to be elaborate — even five tests per module would reduce the blast radius of a future refactor to something diagnosable.

---

## Feathers — Safety of Change

> *Testability, seams, characterization, legacy rescue, blast radius*

### Findings

**⚠ Concern — No test seam for the evaluator**
`src/sdata-evaluator.adb`, line 1

The evaluator→interpreter circular dependency means the evaluator has no visible seam. Any change to expression evaluation — a domain error fix, a rounding edge case, a missing-value propagation rule — can only be characterized through the full pipeline. If something breaks silently, the regression suite will not catch it if the output format is unchanged. This is the specific form in which the circular dependency inflicts ongoing cost: not as a compile error, but as a permanently coarse feedback loop for the package doing the most computational work.

### Feathers's Recommendation

Sprout technique for the evaluator refactor: do not attempt to unit-test the existing `Evaluate_Function` before breaking the cycle — the cycle prevents it. Instead, break the cycle (move `In_Same_Group`), then write a minimal test harness that calls `SData.Evaluator.Evaluate_Function` directly. The regression suite provides adequate coverage for the cycle-breaking step itself, since that is a mechanical move of one 15-line function with no behavior change.

---

## Kleppmann — Data Integrity & Persistence

> *Durability, consistency, failure modes, data pipeline correctness*

### Findings

**⚠ Concern — Temp file cleanup is best-effort under abnormal termination**
`src/sdata-table.adb`, `Backing_Store.Finalize`

The `Backing_Store` type's `Finalize` method deletes the SQLite temp file on normal exit and on unhandled exception unwind. This correctly handles the common cases. It does not run when the process is terminated by `SIGKILL`, a segfault, or the OOM killer. A batch job processing a 500 MB dataset spills to a 500 MB SQLite temp file; if killed by the OOM killer mid-run, the temp file is never deleted. This is a known limitation of the controlled-type cleanup pattern in Ada, not a defect in the implementation. But for a tool that may process large datasets on resource-constrained machines, accumulating orphan temp files in `/tmp` is a realistic operational problem.

### Kleppmann's Recommendation

Register a POSIX signal handler at startup (via `Ada.Interrupts` or `GNAT.Signal_Stack`) that records the temp file path and deletes it on `SIGTERM`/`SIGINT`/`SIGSEGV`. `SIGKILL` cannot be caught — that is a kernel-level constraint — but the OOM killer sends `SIGTERM` before escalating, and a user pressing Ctrl+C sends `SIGINT`. Catching those two covers the majority of abnormal-termination cases that leave orphan files.

---

## Jobs — Product Judgment & Coherence

> *Simplicity, API design, feature coherence, configuration surface, user model*

### Findings

**⚠ Concern — The configuration surface conflates two distinct user models**
`src/sdata_main.adb`, CLI argument handling

The CLI has two usage modes: batch processor and interactive REPL. The flags `--infmt` and `--outfmt` override format detection — they address edge cases that normal users never encounter. A user who knows about `filename[sheet]` syntax for multi-sheet files does not need `--infmt`; a user who doesn't know about it won't understand what `--infmt` does. These flags add four lines to the help output and create a source of confusion: users who set `--infmt CSV` and then `USE file.xlsx` inside the script will get surprising results.

### Jobs's Recommendation

Audit whether `--infmt` and `--outfmt` are exercised by any test that couldn't be replaced by the `filename[sheet]` syntax or by extension-based detection. If not, deprecate them in the next minor release with a visible deprecation warning. The help output should describe what a first-time user needs, not every flag the parser can accept.

---

## Synthesis

### Dominant Failure Mode

**The evaluator→interpreter circular dependency** is the one structural problem that blocks everything else. It prevents evaluator unit testing (Beck), removes the seam needed for safe refactoring (Feathers), pollutes the interpreter's public API (Uncle Bob), and violates the intended dependency direction of the architecture (Fowler). It has been one call site for some time and has not grown — but the dispatch table refactoring, when it resumes, will require writing evaluator unit tests to be done safely. Those tests cannot be written until the cycle is broken.

The Config package situation is a lower-temperature version of the same problem: a package that is simultaneously a CLI-configuration store and a mutable runtime-state store will eventually make it impossible to reason about invariants. The `Runtime_State_Record` grouping is an honest improvement; the next step is extraction.

### Highest-Leverage Intervention

**Break the evaluator→interpreter circular dependency.** Move `In_Same_Group` from `SData.Interpreter` to `SData.Table`, adjust its implementation to use BY-variable state visible at that layer, and update the two call sites in `sdata-evaluator.adb` (lines 801, 834). Remove the `with SData.Interpreter` clause. This is a 15-line function move with no behavior change. The regression suite is adequate coverage for the mechanical step. Once done: write five evaluator unit tests; resume the dispatch table migration for `Handle_Math` and `Handle_Trig`.

### Prioritized Remediation Order

| Priority | Action | Voice(s) | Effort | Risk if Deferred |
|---|---|---|---|---|
| 1 | Break evaluator→interpreter cycle: move `In_Same_Group` to `SData.Table` | Fowler, Uncle Bob, Beck, Feathers | S | High — structural; blocks unit testing and safe dispatch-table refactor |
| 2 | Complete dispatch table: per-function handlers for `Handle_Math` and `Handle_Trig` | Fowler | M | Med — deferring makes it harder as math family grows |
| 3 | Extract `SData.Config.Runtime` (or `SData.Runtime`) from `SData.Config` | Uncle Bob, Fowler | M | Low now; Med as feature count grows |
| 4 | Add evaluator and statistics unit tests (enabled by item 1) | Beck | M | Med — silent internal breakage goes undetected |
| 5 | Register SIGTERM/SIGINT handler for temp file cleanup | Kleppmann | S | Low — operational nuisance; SIGKILL cannot be caught regardless |
| 6 | Audit and deprecate `--infmt`/`--outfmt` if redundant | Jobs | S | Low — cosmetic but reduces help-text confusion |

---

## Caveats & Scope Limitations

The deployment pipeline (packaging scripts for RPM, DEB, SlackBuild, macOS) was not exercised — findings are based on CI configuration and Makefile inspection only. The mathematical correctness of the statistical distributions in `SData.Statistics` was not independently verified against published tables; the implementation uses standard numerical methods but was not validated against reference values. The ODF/OOXML parsing paths in `SData.File_IO` were reviewed structurally but not traced through the XML/Ada library behavior under malformed input.

---

*Review conducted using the Codebase Skeptic framework. Findings represent the application of established software engineering authority to observed evidence, not personal preference.*
