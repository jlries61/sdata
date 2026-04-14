# Codebase Review: `SData — Statistical Data Interpreter`

**Reviewed:** 2026-04-13
**Scope:** Full repository — all 29 Ada source files, test suite, CI configuration, build system, packaging
**Domain:** Systat BASIC-style statistical data language interpreter; reads/writes CSV, ODS, XLSX; processes tabular data through a PDV-based data step
**Stack:** Ada 2012, GPRBuild/Alire, GNU Make; dependencies: Zip-Ada, XML/Ada, MathPaqs
**Voices Activated:** Fowler, Uncle Bob, Beck, Feathers, Evans, Humble, Jobs, Wozniak

---

## Overall Posture

```
⚠  Drifting — coherent intent undermined by accumulating decisions
```

**In one sentence:** The architecture is genuinely sound and the domain model is faithful, but the evaluator has become a load-bearing monolith whose growth pattern — one more `elsif` per feature — will eventually make the system unsafe to extend.

---

## Fowler — Architecture & Evolutionary Design

> *Refactoring, software smells, distribution decisions, change-enabling structure*

### Findings

**⚠ Concern — The Blob Function at the center of everything**
`src/sdata-evaluator.adb`, `Evaluate_Function` (~1,100 lines, line 82 onward)

The function dispatcher is a single function containing roughly 60 branches of `if Name = "ABS" and then Has_Args(1) then ... elsif Name = "LOG" and then Has_Args(1) then ...` cascading to the end of the file. Every new built-in function added to SData requires editing this function. There is no dispatch table, no registry, no strategy — just accretion. The file is already 1,279 lines. At the current trajectory, adding the next tier of functions (say, date/time, or additional statistical families) will push it past 1,600 lines with no natural stopping point. This is a Switch Statement smell in its most expensive form: the cost of each new case is borne by the entire function's readability and test surface.

**⚠ Concern — `Config` as a flat global-state scratchpad**
`src/sdata-config.ads`

The `Config` package is a single-level bag of mutable package-level variables: input format, output format, file paths, quiet mode, debug mode, REPEAT state, FPATH directories, pending save state, max table rows, max string length, max temp vars, shell disable, continue-on-error, ignore-math-errors, DIGITS precision, and the version constants. Any package in the system can read or write any of these at any time. There is no encapsulation, no visibility control, no invariants. This is not inherently catastrophic at the current size, but it is the architectural equivalent of a global namespace: every new feature gets a new variable here, and the coupling surface grows invisibly.

### Fowler's Recommendation

Introduce a dispatch table for `Evaluate_Function` — a map from function name to a subprogram access type. Group the functions into families (Math, String, Statistical, Navigation, Aggregate) and register each family separately. This is the Extract Function + Replace Conditional with Polymorphism refactoring sequence applied at the module level. For Config: separate the static configuration (command-line flags, limits) from the runtime state (Repeat_Active, Save_File_Active, Select_Filter_Expr). The static configuration is set once at startup; the runtime state changes as programs execute. Keeping them in the same package makes it impossible to reason about what is safe to cache and what must be re-read on every access.

---

## Uncle Bob — Code Structure & SOLID

> *Clean code, dependency direction, modularity, naming, separation of concerns*

### Findings

**🔴 Problem — Version constants that have already diverged**
`src/sdata-config.ads`, lines 59–62

```ada
Version_Major : constant := 0;
Version_Minor : constant := 3;
Version_Patch : constant := 0;
Version_Str   : constant String := "0.4.0";
```

There are two representations of the version in the same file, and they currently disagree: the numeric constants say 0.3.0; the string says 0.4.0. The `bump-version.sh` script updates `Version_Str` in nine locations but does not update the numeric constants. If `Version_Major/Minor/Patch` are used anywhere for conditional logic or comparison, they will silently return wrong answers. If they are not used, they are dead code maintaining a false impression of precision. Either derive `Version_Str` from the numeric constants (`Version_Major'Image & "." & ...`) or delete the numeric constants. There must be one source of truth.

**⚠ Concern — `Config` violates SRP at the package level**
`src/sdata-config.ads`

The Config package has at least three distinct responsibilities: (1) static CLI configuration, (2) runtime interpreter state (REPEAT, Save pending, FPATH directories), and (3) version metadata. A package that cannot be described without "and" is doing more than one thing. The immediate consequence: there is no way to reset the interpreter state for a `NEW` command without also touching the static configuration, leading to careful cherry-picking in `Execute_Declarative` (`Stmt_NEW` case) of which fields to reset.

**⚠ Concern — The evaluator's argument pre-evaluation breaks the name contract**
`src/sdata-evaluator.adb`, `Evaluate_Function`, lines 118–179

All arguments are evaluated eagerly into `All_Vals` before dispatch. This means `IF(condition, true_branch, false_branch)` evaluates both `true_branch` and `false_branch` before selecting one. If either branch has a domain error (e.g., `LOG(negative_number)`), it will trigger regardless of which branch is taken. The function is named `IF` and behaves like a function — callers expect lazy evaluation, or at minimum no side-effects from the non-selected branch. The function name misleads about its contract.

### Uncle Bob's Recommendation

Fix the version constants immediately — it is a five-minute change and the current state is a latent correctness bug. For Config: split into `SData.Config.CLI` (set at startup, never changed) and `SData.Config.Runtime` (interpreter state, reset by NEW). This is a dependency inversion win: the interpreter depends on runtime state it controls, not on the same package that the CLI parser writes to. For IF: implement short-circuit evaluation by dispatching before evaluating all arguments — evaluate the condition, then evaluate only the selected branch.

---

## Beck — Tests & Feedback Loops

> *Test quality, TDD signals, YAGNI, incremental design, feedback cycle length*

### Findings

**🔴 Problem — A test with no expectation cannot fail**
`Makefile`, lines 64–77

```bash
if [ -f "$$exp" ]; then
    diff -u ...
else
    echo "PASSED (No expected output file found)";
fi
```

If no `.out` file exists for a test, the test auto-passes. This means a new test script added to `tests/` with no corresponding expected output is silently "green." The harness provides false confidence: the developer sees PASSED, but nothing was verified. A test that cannot fail is not a test — it is a rehearsal.

**⚠ Concern — Stop-on-first-failure loses diagnostic context**
`Makefile`, `check` target

The harness calls `exit 1` on the first failing test. In a suite of 68 tests, a single regression stops all subsequent tests. The developer learns "test X failed" but not whether tests X+1 through X+68 also failed. This slows triage: is this one broken test or a systemic regression? TAP or a simple accumulator pattern would give a full picture before exiting.

**⚠ Concern — Output comparison tests at the suite boundary, nothing below it**
`tests/`

All 68 tests exercise the full pipeline: parse → interpret → evaluate → render output → diff. There are no unit tests for `SData.Statistics` (are the distribution implementations correct?), `SData.Table` (does the filter index rebuild correctly after column modification?), or `SData.Evaluator` (does `ROUND(1.5)` and `ROUND(2.5)` round correctly?). The suite catches regressions in observed output but gives no signal when an internal invariant breaks silently. A bug that produces wrong numbers but the same number of lines will pass.

### Beck's Recommendation

Fix the no-expectation auto-pass immediately: make the harness emit a warning and continue (not pass) when no expected file exists, or better, fail. For stop-on-first-failure: collect failures and report all of them; reserve the early exit for the CI environment only. For test depth: add at least a handful of unit-level tests for `Statistics` (known CDF values against published tables) and `Table` (row/column invariants). These do not need to be elaborate — even five tests per module would reveal whether a refactor broke internal behavior.

---

## Feathers — Safety of Change

> *Testability, seams, characterization, legacy rescue, blast radius*

### Findings

**🔴 Problem — Hard source buffer limits with silent failure risk**
`src/lexer/sdata-lexer.ads`, lines 37–38, 58

```ada
Text   : String (1 .. 1024); -- Raw text content of the token
Source : String (1 .. 10000); -- Buffer for the input source code
```

The lexer accepts a source string but stores it in a 10,000-character buffer. `Initialize` assigns `Ctx.Source (1 .. Source'Length) := Source` — if the caller passes a string longer than 10,000 characters, this raises `Constraint_Error`. The `sdata_main.adb` `Read_File` function reads the entire script into a `String` and passes it directly to `Initialize` with no length check. A script file of 10,001 bytes crashes the interpreter with an uncaught `Constraint_Error`. The CRITIQUE.md history shows the REPL buffer was fixed in v0.3.4 from a similar issue — but the lexer source buffer has the same structural problem and was not addressed. The token text buffer (1,024 chars) imposes the same limit on any single token, including long string literals.

**⚠ Concern — Documented memory leak left in production**
`src/sdata-interpreter.adb`, lines 213–220

```ada
procedure Clear_Pending_Mods is
begin
   while Pending_Mods /= null loop
      declare Tmp : constant Column_Mod_List := Pending_Mods;
      begin Pending_Mods := Pending_Mods.Next;
            -- Implicit free managed by GC or let it leak for now in Ada
      end;
   end loop;
end Clear_Pending_Mods;
```

This comment documents an intentional memory leak. Ada does not have a GC for access types without explicit deallocation. Every KEEP or DROP statement allocates a `Column_Mod_Node` that is never freed. In a batch script with thousands of column operations, this accumulates. The comment suggests the author knows and intends to fix it. The risk is not catastrophic for typical scripts but it is a known defect in the current release.

**⚠ Concern — Borrowed-pointer ownership requires ongoing discipline**
`src/sdata-interpreter.adb`, lines 139, 160–168

`Select_Filter_Expr` holds a pointer into the AST owned by the active program. `Clear_Active_Program` nullifies it before freeing the program to prevent a dangling reference. This is correctly implemented today, but it is a seam-free dependency: any future path that frees the program without going through `Clear_Active_Program` will leave `Select_Filter_Expr` pointing to freed memory. There is no type-level enforcement of the ownership contract.

### Feathers's Recommendation

Address the source buffer first. Replace `String (1 .. 10000)` in `Lexer_Context` with `Unbounded_String` — the same fix applied to the REPL line buffer in v0.3.4. Add a length check (and a meaningful error) in `sdata_main.adb` between `Read_File` and `Initialize`. For `Clear_Pending_Mods`: introduce an `Unchecked_Deallocation` instance for `Column_Mod_Node` and call it — this is a one-line fix per the Ada pattern. For the filter pointer: formalize the ownership via a comment contract at the package level at minimum; consider making the filter expression a self-owned object rather than a borrowed reference.

---

## Evans — Domain Model & Bounded Contexts

> *Ubiquitous language, model integrity, bounded contexts, aggregate design*

### Findings

**✅ Strength — The domain vocabulary is faithfully rendered**
`src/sdata-interpreter.adb`, `src/sdata-variables.adb`, `src/sdata-evaluator.adb`

The PDV (Program Data Vector), BOG/EOG (beginning/end of group), BY-group processing, HOLD variables, RECNO in logical space, and the data step execution model are all authentic Systat-lineage terminology, correctly modeled. `Val_Missing` properly represents the domain concept of "no data" (SQL NULL semantics), with propagation through most functions via `Has_Args`. This is a domain model that would be recognizable to a Systat practitioner. That is not an accident and it is worth naming.

**⚠ Concern — The Config package corrupts the ubiquitous language at the boundary**
`src/sdata-config.ads`

The domain has a coherent vocabulary. But the configuration layer uses generic programming terms that don't match: `Save_File_Active` (vs. "pending SAVE"), `Repeat_Active` (vs. "REPEAT mode"), `Format_Type` (vs. the domain's use of format names as first-class nouns). A domain expert asking "is a SAVE pending?" has to know to check `Config.Save_File_Active`. The translation cost is small but accumulates — each new developer must learn both the domain vocabulary and the configuration vocabulary.

**⚠ Concern — `Evaluate_Function` is the domain model for built-in functions, and it is a string dispatch table**
`src/sdata-evaluator.adb`

The domain has well-defined categories of operations: mathematical, statistical, string, navigation, aggregate. The evaluator model has one category: "things named in a long if-elsif chain." A domain expert navigating the codebase cannot find "all statistical functions" without reading the entire function. The conceptual structure of the domain is not reflected in the code structure.

### Evans's Recommendation

Rename Config fields to match the domain language: `Pending_Save` instead of `Save_File_Active`, `Repeat_Mode` instead of `Repeat_Active`. These are cosmetic but they eliminate a mental translation step. For the evaluator: organize the dispatch by the domain categories that the HELP system already uses — the HELP entries are already grouped by function family. Let the code reflect that grouping.

---

## Humble — Delivery Pipeline & Deployment

> *Pipeline completeness, manual steps, rollback, environment parity, deploy safety*

### Findings

**⚠ Concern — CI has no timeout protection**
`.github/workflows/test.yml`, `Makefile` check target

The CI pipeline runs `make check`, which runs 68 tests serially with no per-test timeout. An infinite loop in any test script (e.g., a WHILE with a non-terminating condition) will hang the CI job until GitHub's default 6-hour job timeout kills it. The CRITIQUE.md acknowledges this as a deferred low-priority item. For a language interpreter that explicitly supports WHILE and REPEAT loops, this is not a hypothetical: it is the exact class of bug a user is most likely to introduce. The Makefile is one `timeout 5` wrapper per test from solving this.

**⚠ Concern — A visible, documented, non-functional flag ships in the release**
`src/sdata_main.adb`, line 68

```ada
Put_Line ("  -p                       Pager specification (not yet implemented)");
```

The `-p` flag is listed in the help output with the annotation "not yet implemented." It is not wired to anything. Users who pass `-p` will see it silently ignored. This is fine during active development but should not ship in a point release — it trains users to expect a feature that does not exist and creates questions about what happens when they pass it.

**⚠ Concern — `make run` hardcodes a test fixture as the default execution target**
`Makefile`, line 43

```makefile
run: build
    ./bin/sdata tests/test1.cmd
```

This target runs `tests/test1.cmd` — a specific test fixture, not a user script. Any contributor running `make run` executes someone else's test, not their own work. This is a development convenience that leaked into the shipped Makefile. It is harmless but misleading.

### Humble's Recommendation

Add `timeout 10` (or an appropriate duration) to the per-test invocation in the Makefile check loop — this is a 30-minute change that eliminates a whole class of CI hangs. Remove the `-p` flag entry from the help output until the feature is implemented, or wire it to a no-op with a warning. Replace `make run` with a target that requires a `FILE=` argument: `./bin/sdata $(FILE)` with a guard that prints an error if FILE is unset.

---

## Jobs — Product Judgment & Coherence

> *Simplicity, API design, feature coherence, configuration surface, user model*

### Findings

**🔴 Problem — The binary calls itself the wrong name**
`src/sdata_main.adb`, line 54

```ada
Put_Line ("Usage: sdata_main [options] [filename]");
```

The installed binary is `sdata`. The usage line says `sdata_main` — the internal Ada procedure name. This is the first thing a user sees when they run `sdata --help`. It's wrong. It signals that the help text was written once and never tested from the user's perspective. A user filing a bug report who copies the usage line will report the wrong program name.

**⚠ Concern — The configuration surface conflates two distinct user models**
`src/sdata_main.adb`, CLI argument handling

The CLI has two usage modes: (1) a batch processor (`sdata script.cmd`) and (2) an interactive REPL (`sdata` with no file). The flags `-u` (input dataset) and `-s` (output dataset) are relevant to both. But `--infmt` and `--outfmt` are flags for overriding format detection — they apply to edge cases that normal users never need. A user who knows about `filename[sheet]` syntax for multi-sheet files does not need `--infmt`; a user who doesn't know about it won't know what `--infmt` does. The configuration surface could be simplified by letting `USE file.xlsx[Sheet2]` handle all format/sheet selection, eliminating the need for CLI format override flags entirely. That would reduce the help text by a quarter and eliminate a source of confusion.

### Jobs's Recommendation

Fix the usage line — it is a one-line change. Audit whether `--infmt` and `--outfmt` are exercised by any test that couldn't be replaced by the `filename[sheet]` syntax; if not, deprecate them. The pager flag should be removed from help output until it does something. The rule is: if a user reads your help output and tries something, it must work.

---

## Wozniak — Engineering Economy & Elegance

> *Unnecessary complexity, algorithmic waste, abstraction tax, genuine ingenuity*

### Findings

**🔴 Problem — `IF()` performs eager evaluation of all branches**
`src/sdata-evaluator.adb`, lines 118–182

The argument flattening loop evaluates every argument into `All_Vals` before the function name is dispatched. `IF(condition, LOG(x), 0.0)` evaluates `LOG(x)` unconditionally — if `x` is negative, this raises a domain error regardless of whether the condition is true. This is not how any user expects `IF` to behave. It is also how `LAG`, `NEXT`, and `OBS` avoid the issue: they are carved out before evaluation with `Is_Identifier_Ref_Function`. `IF` needs the same treatment. The fix is to detect `IF` before the flattening loop and evaluate lazily.

**⚠ Concern — `Add_Pending_Mod` walks the list to find the tail every time**
`src/sdata-interpreter.adb`, lines 199–211

The `Pending_Mods` linked list is appended to by walking from head to tail on every insertion. This is O(n) per append. For a KEEP statement naming 20 columns, this is 20 O(n) walks. The fix is trivially a tail pointer — the same pattern already used correctly in `Active_Program_Head`/`Active_Program_Tail` for the REPL program list.

**⚠ Concern — String concatenation allocates then truncates**
`src/sdata-evaluator.adb`, lines 1232–1246

String concatenation via `Op_Add` builds the full concatenated string into `V.Str_Val`, then checks if it exceeds the limit, then truncates. The full allocation happens even when the result will be truncated. For a `Max_String_Len` of 256 concatenating two 10,000-character strings, 20,000 characters are allocated to produce 256. Check the limit before concatenating, or concatenate only up to the limit.

**✅ Elegance worth naming — The `Has_Args` guard pattern**
`src/sdata-evaluator.adb`, lines 96–103

The `Has_Args(N)` local function simultaneously checks argument count and missing-value propagation. Every function that calls `Has_Args(N)` gets correct missing-value semantics for free. This is genuinely elegant: a single guard eliminates two failure modes (insufficient arguments, missing propagation) with one readable call. It is the kind of small thing that makes a codebase pleasant to extend.

### Wozniak's Recommendation

Fix the `IF` eager evaluation — it is a correctness bug, not a style issue, and the mechanism to fix it is already present (`Is_Identifier_Ref_Function` shows the pattern). Add a tail pointer to the pending mods list. For string concatenation: check `Length(L.Str_Val) + Length(R.Str_Val) > Limit` before concatenating, and use only as much of the right-hand string as remains under the limit — avoid the over-allocation.

---

## Synthesis

### Dominant Failure Mode

There is no single catastrophic failure mode. The codebase is well-structured and the core execution model is sound. The dominant pattern is **deferred technical debt acknowledged but not scheduled**: the memory leak in `Clear_Pending_Mods` is documented in a comment; the lexer buffer limit is the same class of bug fixed in the REPL but not addressed in the lexer; the test auto-pass-on-no-expectation is a known hole. These are not ignorance failures — the CRITIQUE.md demonstrates self-awareness. They are prioritization failures: each issue was deferred for a reason, but they are accumulating without a clear trigger for resolution.

The secondary pattern is **the evaluator's unsustainable growth**: a 1,100-line cascading if-elsif dispatcher that gains one branch per new function. At current velocity this is a 6-month problem, not a 6-week problem. But it becomes structurally unsafe before it becomes unreadable.

### Highest-Leverage Intervention

**Fix `IF()` eager evaluation.** It is the only finding that is simultaneously a correctness bug (not a style issue), affects every user who calls `IF()` with a branch that could produce a domain error, and has a clear and well-bounded fix. The `Is_Identifier_Ref_Function` pattern already solves an analogous problem for `LAG`/`NEXT`/`OBS`. Apply the same treatment to `IF` before the flattening loop in `Evaluate_Function`. This is a half-day change with high confidence.

Second priority: fix the lexer source buffer. It is the same class of bug that was fixed in the REPL — a hard-limit `String` buffer that raises `Constraint_Error` on overflow. It has the same fix. It affects every batch user with a script longer than 10,000 characters.

### Where the Voices Disagree

Beck and Feathers create a mild tension on the evaluator refactor. Beck says: before you refactor the 1,100-line `Evaluate_Function`, you need unit tests that will catch a refactoring error. Feathers says: there is no seam to write unit tests against the evaluator without also invoking the parser and interpreter. The resolution is Feathers's sprout technique: do not refactor the existing function; instead, implement the next new built-in function using the new dispatch-table mechanism alongside the existing if-elsif chain, prove it works, then migrate existing functions one family at a time — each migration covered by the regression test suite. The regression tests, while coarse-grained, will catch observable behavior changes.

### Prioritized Remediation Order

| Priority | Action | Voice(s) | Effort | Risk if Deferred |
|---|---|---|---|---|
| 1 | Fix `IF()` eager argument evaluation | Wozniak, Uncle Bob | S | High — correctness bug affecting all IF users |
| 2 | Fix lexer 10,000-char source buffer (use Unbounded_String) | Feathers, Wozniak | S | Med — crashes on scripts > 10KB |
| 3 | Fix version constant divergence (`Version_Major/Minor/Patch` vs `Version_Str`) | Uncle Bob | S | Med — silent wrong answers if constants are ever used |
| 4 | Fix `Clear_Pending_Mods` memory leak (add Unchecked_Deallocation) | Feathers | S | Med — accumulates across column-heavy workloads |
| 5 | Fix test harness: make missing-expectation a warning/failure, not a pass | Beck | S | Med — false green CI coverage |
| 6 | Fix usage line: `sdata_main` → `sdata` | Jobs | S | Low — user-facing but cosmetic |
| 7 | Add per-test timeout to `make check` | Humble | S | Med — first infinite loop hangs CI |
| 8 | Remove non-functional `-p` flag from help output | Jobs, Humble | S | Low — misleading but harmless |
| 9 | Fix `Add_Pending_Mod` O(n) tail-walk (add tail pointer) | Wozniak | S | Low — performance, not correctness |
| 10 | Fix string concatenation over-allocation | Wozniak | S | Low — wastes memory on truncated strings |
| 11 | Begin evaluator refactor: dispatch table for one function family | Fowler, Uncle Bob | M | Med — deferring makes it geometrically harder |
| 12 | Separate `Config.CLI` from `Config.Runtime` | Fowler, Uncle Bob, Evans | M | Low now, Med as feature count grows |

---

## Caveats & Scope Limitations

The deployment pipeline (packaging scripts for RPM, DEB, SlackBuild, macOS) was not exercised — Humble's findings are based on CI configuration and Makefile inspection only. The mathematical correctness of the statistical distributions in `SData.Statistics` was not independently verified against published tables; the implementation appears to use standard numerical methods (Lentz continued fraction, series expansion for incomplete gamma) but was not validated against reference values. The ODF/OOXML parsing paths in `SData.File_IO` were reviewed structurally but not traced through the XML/Ada library behavior under malformed input.

---

*Review conducted using the Codebase Skeptic framework. Findings represent the application of established software engineering authority to observed evidence, not personal preference.*
