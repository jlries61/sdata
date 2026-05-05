# Codebase Review: `SData Statistical Data Interpreter`

**Reviewed:** 2026-05-04 | **Last updated:** 2026-05-05 (commit 9804705)
**Scope:** Full source repository — all Ada source files, Makefile, test suite, packaging scripts
**Domain:** Single-process batch/interactive interpreter for tabular statistical data processing, inspired by the Systat BASIC data step model
**Stack:** Ada 2012, GNAT/GPRbuild, Zip-Ada / XML-Ada / MathPaqs / ada_sqlite3, SQLite3 backing store for large tables
**Voices Activated:** Fowler, Uncle Bob, Beck, Feathers, Jobs, Wozniak

---

## Overall Posture

```
⚠  Drifting — coherent intent undermined by accumulating decisions
```

**In one sentence:** The three-tier execution model is sound and well-documented, but global mutable state has become load-bearing infrastructure, making every core subsystem untestable in isolation and each new feature a tightrope walk over invisible contracts.

---

## Fowler — Architecture & Evolutionary Design

> *Refactoring, software smells, distribution decisions, change-enabling structure*

### Findings

**⚠ Concern — Global package state as the integration bus**
`src/sdata-interpreter.adb:56–172, src/sdata-evaluator.adb:62–63, src/sdata-table.ads:135–154`

The interpreter, evaluator, and table communicate entirely through package-level mutable state rather than explicit parameter passing. `BOG_Flag`/`EOG_Flag` live in `sdata-evaluator.adb` and are set by the interpreter's data step loop before each record — a dependency the evaluator's package spec does not declare. The BY variable list is duplicated: `Current_By_Vars` in the interpreter (line 59) and `Table_By_Vars` in the table, populated together on every `BY` statement but owned cleanly by neither. `Select_Filter_Expr` persists as a package-level variable in the interpreter between RUNs. This pattern removes all explicit seams between the three major subsystems; any cross-subsystem interaction becomes an implicit contract maintained by convention rather than type.

**🔴 Problem — Dual program buffer: two representations of the same data kept in sync**
`src/sdata-interpreter.adb:56–171`

`Active_Program_Head/Tail` (a linked list) and `Active_Program_Vec` (an `Ada.Containers.Vectors` vector) are both maintained in parallel. The linked list is used for execution traversal; the vector for indexed access (LIST, DELETE n[-m]). `Add_To_Active_Program` appends to both (lines 159–171). This is two authoritative representations of one data structure. Any future code path that appends to only one produces silent corruption. A single indexed vector supports both O(1) index access and in-order iteration — the linked list is redundant.

**⚠ Concern — `Run_One_Step` conflates six distinct concerns**
`src/sdata-interpreter.adb:~1800+`

The data step's core loop combines filter rebuilding, logical row count determination, BOG/EOG computation, per-record body execution, output flushing, and table commit — all in one procedure acting entirely through global state. The three-tier model documented at the top of the file is correct; its implementation makes each tier invisible from the outside and impossible to test independently.

### Fowler's Recommendation

Introduce an explicit `Interpreter_Context` record carrying BOG/EOG flags, the BY variable list, the filter expression, and the per-record deletion flag. Pass it as an `in out` parameter through the data step chain rather than relying on package-level globals. This is the *Replace Global State with Context Object* refactoring. It does not require changing the execution model at all, but it creates explicit seams where tests can inject state and components can be understood — and changed — in isolation.

---

## Uncle Bob — Code Structure & SOLID

> *Clean code, dependency direction, modularity, naming, separation of concerns*

### Findings

**🔴 Problem — SRP violation: `sdata-evaluator.adb` is a God Object**
`src/sdata-evaluator.adb` (2,589 lines)

The evaluator implements expression tree traversal, ~100 built-in functions (mathematical, string, statistical, date/time, table navigation), and the dispatch table that routes function calls. The dispatch table pattern (`Dispatch_Table : Fn_Maps.Map`) is the right call for extensibility — but all handler bodies are co-located in the same 2,589-line compilation unit. Statistical distribution functions (Normal CDF, Student's t, F-distribution) and string manipulation functions (SUBSTR, TRIM, PAD) have no architectural reason to share a file with the expression tree evaluator. When a function has a bug, diagnosing it means navigating ~2,000 lines of unrelated context.

**⚠ Concern — Reversed dependency direction: interpreter drives evaluator's internal state**
`src/sdata-evaluator.adb:62–63, src/sdata-evaluator.ads`

`BOG_Flag` and `EOG_Flag` are private to `sdata-evaluator.adb`, set by the interpreter calling `Set_BOG`/`Set_EOG`. The evaluator's package spec advertises `Evaluate` and function dispatch; the caller side-effects the evaluator's private state before calling `Evaluate`. A reader of the evaluator package spec sees no indication that it has externally-driven state. This dependency runs backwards and is invisible from both call sites and the callee's interface.

**⚠ Concern — Magic constant 32 for name lengths scattered across types** ✅ *Resolved fae2d2d*
`src/sdata-table.ads:122, src/sdata-table.ads:66, src/sdata-interpreter.adb:133`

`String(1..32)` appeared in `Column.Name`, `Sort_Criteria.Name`, and `Column_Mod_Node.Name` — three separate struct definitions with no named constant tying them together. The limit of 32 characters for column names was also incorrect per the design specification (64 is the documented maximum). Additional enforcement points existed in the parser, interpreter, file I/O, and table body. *Fix: six capacity constants introduced in `SData` root package (`Max_Name_Len`, `Max_Path_Len`, `Max_Sheet_Name_Len`, `Max_Delimiter_Len`, `Max_Charset_Len`, `Max_Options_Val_Len`); `Max_Name_Len` corrected to 64; all 13 affected source files updated.*

### Uncle Bob's Recommendation

Extract function families into child packages: `SData.Evaluator.Math`, `SData.Evaluator.Strings`, `SData.Evaluator.Statistics`, `SData.Evaluator.Table_Navigation`. The dispatch table registration remains in the parent; handler bodies move to their natural home. For the BOG/EOG coupling, declare `Set_BOG`/`Set_EOG` explicitly in `evaluator.ads` with a comment stating the caller's obligation — the coupling stays but becomes a visible contract rather than a hidden side effect. The magic-constant finding is resolved.

---

## Beck — Tests & Feedback Loops

> *Test quality, TDD signals, YAGNI, incremental design, feedback cycle length*

### Findings

**🔴 Problem — Integration-only coverage: critical paths have no unit test harness**
`tests/*.cmd, src/csv_unit_test.adb`

There are 114 integration tests. There is one unit test binary (`csv_unit_test`) covering CSV parsing. There are zero unit tests for expression evaluation, parser correctness, table operations, BY-group detection, filter index map logic, or interpreter state management. The `Set_Index_Map` zero-match bug (fixed 2026-05-04) was latent because the only way to exercise "SELECT that matches nothing" was to write an integration test for it explicitly. Integration tests find bugs that produce wrong output. They do not find bugs in code paths that produce *no output* — deleted records, zero-match filters, empty groups — except by deliberately crafting coverage for each silent path.

**⚠ Concern — Statistical functions have no numerical regression tests**
`src/sdata-evaluator.adb` (statistical function handlers)

The distribution functions (`NORMINV`, `TINV`, `FINV`, `CHIINV`, and their CDF counterparts) implement non-trivial numerical algorithms. They are tested only insofar as integration tests happen to call them. Known-value tests (`NORMINV(0.975) ≈ 1.96`, `TINV(0.025, 30) ≈ −2.042`) do not exist. A ported or modified algorithm with a small coefficient error would pass the current test suite as long as the output rounds to the same number of displayed decimal places.

### Beck's Recommendation

Add a `statistics_unit_test` binary that calls the evaluator's function handlers with reference values from published statistical tables. This is a two-hour task for the highest-risk unprotected code in the project. The evaluator's package interface is already the right abstraction — `Evaluate` takes an expression tree and returns a `Value`; a test can construct literal-value trees without running the interpreter at all. Start here, because this test requires no architectural change and directly protects the most failure-prone subsystem.

---

## Feathers — Safety of Change

> *Testability, seams, characterization, legacy rescue, blast radius*

### Findings

**💀 Structural Risk — No seam to test any interpreter behavior in isolation** *(partially addressed a975a63)*
`src/sdata-interpreter.adb` (entire package body)

Every piece of interpreter state — the active program list, BY variables, filter expression, record deletion flag, submit chain, column modification queue — lives as package-level variables in the interpreter body. To test any single behavior (e.g., "does BY-group detection return True for the first record of a new group?"), you must initialize the entire interpreter stack, feed it a data step, and observe console output. This is the definition of a codebase where the blast radius of any change in the interpreter is bounded only by the integration test suite — which has structural gaps around silent code paths. *Partial fix: `Group_Flags` function sprouted (see Feathers finding below); the broader seam problem remains.*

**⚠ Concern — `NEW` command partial-reset invariant is untested**
`src/sdata-interpreter.adb: Clear_Active_Program`

`Clear_Active_Program` resets the program buffer, SELECT filter, BY vars, and index map. The `NEW` command also resets `Config.Runtime`. But state such as `Input_File_Columns`, `Submit_Chain`, and `Pending_Mods` appears in the interpreter body; their reset status under `NEW` is not obvious from reading. No test verifies that the sequence `USE "file1.csv" / LET X = 1 / RUN / NEW / USE "file2.csv" / RUN` leaves the interpreter in a clean state. The correctness of multi-step interactive sessions depends on which variables `NEW` resets — a contract that exists only in the implementation, not in any test.

### Feathers's Recommendation ✅ *Implemented a975a63*

`Is_First_In_Group` and `Is_Last_In_Group` (both reading `Current_By_Vars` global state) were replaced with:

```ada
function Group_Flags (Logical_I     : Positive;
                      Logical_Count : Natural;
                      By_Vars       : By_Group_Names.Vector)
                      return Group_Flags_Result;
```

`Group_Flags_Result` is a record `(BOG, EOG : Boolean)`. The function reads no global interpreter state; its result is fully determined by its arguments and the current table contents. `Process_One_Record` now calls it once and uses `Flags.BOG`/`Flags.EOG` throughout, eliminating the if/else dispatch between the BY-active and no-BY code paths. The seam for BY-group logic is now explicit and well-bounded. Next step when ready: expose `Group_Flags` in the interpreter's public spec and add a dedicated unit test.

---

## Jobs — Product Judgment & Coherence

> *Simplicity, API design, feature coherence, configuration surface, user model*

### Findings

**⚠ Concern — LET vs. SET asymmetry is load-bearing but underexplained**
`man/man1/sdata.1`

The language has both `LET` and `SET`. `LET` assigns to a data step variable (reset by `NEW`); `SET` assigns to a permanent variable (persists across `NEW`). This is a meaningful and intentional distinction. But arriving at the right choice requires understanding the PDV, the permanent/temporary variable distinction, and the data step execution model — none of which are explained before the command reference. A first-time user will use `LET` everywhere and be surprised when an accumulator resets between data steps, or will use `SET` everywhere and be surprised when a column disappears after the step. The asymmetry is correct; the path to understanding it is not visible from the interface.

**⚠ Concern — CLI flag surface lacks grouping and visual structure**
`src/sdata_main.adb` (option parsing), `--help` output

The flags fall into three natural groups: sizing (`-m`, `-t`, `--clen`), behavior (`--noshell`, `--ignore-math-errors`, `-k`), and I/O (`-p`, `-o`, `-q`). The `-h` output lists them flat. `--noshell` silently disables `-p` — a non-obvious interaction buried in the `-p` description. The man page is well-organized; the inline help is not. For a developer-facing tool this is minor, but coherence between `-h` output and the man page structure costs one afternoon.

### Jobs's Recommendation

Add a `CONCEPTS` or `INTRO` help topic accessible from the interpreter (`HELP CONCEPTS`) that explains the PDV, the LET vs. SET contract, and the BY-group model in two pages before the user reads any command reference. The interface is correct; the explanation is missing. For the CLI flags, group them in `-h` output with headers (Sizing, Behavior, Output) to match the man page structure.

---

## Wozniak — Engineering Economy & Elegance

> *Unnecessary complexity, algorithmic waste, abstraction tax, genuine ingenuity*

### Findings

**🔴 Problem — Linked list + vector: the simplest data structure pays a maintenance tax**
`src/sdata-interpreter.adb:56–171`

`Active_Program_Head/Tail` (linked list) and `Active_Program_Vec` (vector) maintain the same ordered sequence of program statements. Ada's `Ada.Containers.Vectors` supports O(1) indexed access (`Vec(I)`) and forward iteration — it subsumes the linked list entirely. The linked list fields (`Head`, `Tail`, `Stmt.Next`) add state to every statement node; `Add_To_Active_Program` spends six lines keeping them in sync. The entire linked list exists as a historical artifact. Its removal is a safe mechanical refactoring with a directly verifiable outcome.

**⚠ Concern — BY variable list duplicated between interpreter and table**
`src/sdata-interpreter.adb:59, src/sdata-table.adb:513–544`

`Current_By_Vars` in the interpreter and `Table_By_Vars` in the table are both ordered vectors of active BY variable names. When a `BY` statement executes, both are populated. `Is_First_In_Group`/`Is_Last_In_Group` in the interpreter use `Current_By_Vars`; `In_Same_Group` in the table uses `Table_By_Vars`. Both implement "are these two records in the same BY group?" with different interfaces and independently maintained state. There is one concept in two places kept in sync by a caller. The canonical copy should live in one location; the other should query it.

**⚠ Concern — Magic constant 32 is a hidden system limit with no compile-time alarm** ✅ *Resolved fae2d2d*
`src/sdata-table.ads:122, :66, src/sdata-interpreter.adb:133`

Three struct definitions independently hard-coded `String(1..32)` for name storage, with additional enforcement points scattered across the parser, interpreter body, table body, and file I/O. *Fix: all bare literals replaced with named constants from the `SData` root package; `Max_Name_Len` corrected to 64 per the design specification.*

### Wozniak's Recommendation ✅ *Implemented 9804705*

Remove the linked list entirely — replace `Active_Program_Head/Tail` and `Stmt.Next` traversal with direct vector iteration. This reduces the statement node type, simplifies `Add_To_Active_Program` to a single `Append`, and eliminates the sync hazard. *The named-constant finding is resolved; the linked list is now also resolved. `Active_Program_Head/Tail` removed; `Add_To_Active_Program` reduced to a single `Vec.Append`; `Run_Active_Program` chains vector entries transiently at call time and unlinks afterward. `Stmt.Next` is retained in the AST node — it is still required for nested control-flow sub-lists (IF branches, FOR bodies) — but the permanent top-level linked list is gone.*

---

## Synthesis

### Dominant Failure Mode

**Global mutable state as the integration bus.** Every major subsystem communicates through package-level variables set externally and read implicitly. This is not a stylistic preference. It means every function that reads `BOG_Flag`, `Filter_Map`, or `Current_By_Vars` has an invisible pre-condition that another package set that state correctly before the call. The `Set_Index_Map` zero-match bug is a direct consequence: the contract "null = no filter / non-null = filter active" was implicit, the zero-length case was not enumerated, and no test could isolate the sentinel logic without running a full data step. As new features land — particularly any that extend BY-group processing, selective execution, or multi-step data operations — this pattern will produce more subtle bugs of exactly the same character.

### Highest-Leverage Intervention

**Introduce `Interpreter_Context` and thread it through `Run_One_Step`.** The type carries BOG/EOG flags, the BY variable list, the filter expression, and the per-record deletion flag. The data step loop creates a context, populates it, and passes it down to `Process_One_Record`, `Is_First_In_Group`, and transitively to `Evaluate`. Package-level globals become initialization values for this context, not the canonical store during execution. This one change surfaces the invisible contracts that the current code enforces by convention, enables unit tests for `Is_First_In_Group` and BOG/EOG logic, eliminates the BY-variable duplication, removes the reversed evaluator dependency, and eliminates the partial-reset hazard — all at once, without rewriting the execution model.

### Where the Voices Disagree

Beck and Feathers both say "add tests first," but disagree on feasibility. Beck can add statistical unit tests today with no architectural change — those functions have deterministic inputs and outputs and do not touch global state. Start there. For the interpreter's core logic, Feathers is right that no unit test seam exists without the context-object refactoring first. The resolution is Beck's two-hour statistics test first (immediate value, no risk), then Feathers's Sprout Function for `Is_First_In_Group` (small safe seam), then the broader context-object refactoring when confidence in the seam pattern is established.

### Prioritized Remediation Order

| Priority | Action | Voice(s) | Effort | Risk if Deferred |
|---|---|---|---|---|
| ~~2~~ | ~~Introduce `Max_Name_Len` constant; reference from all three struct definitions~~ | Wozniak | — | ✅ *Done fae2d2d — six constants, 13 files, name limit corrected to 64* |
| ~~4~~ | ~~Sprout `Group_Flags` pure function from `Is_First_In_Group`/`Is_Last_In_Group`~~ | Feathers | — | ✅ *Done a975a63 — `Group_Flags(I, Count, By_Vars)` replaces both; Process_One_Record simplified* |
| ~~2~~ | ~~Replace linked list with vector in program buffer; remove `Stmt.Next`~~ | Wozniak | — | ✅ *Done 9804705 — `Active_Program_Head/Tail` removed; `Run_Active_Program` chains vector entries transiently; `Stmt.Next` retained for nested sub-lists* |
| 1 | Add `statistics_unit_test` with reference values for distribution functions | Beck | S | Med — numerical regressions catch silently |
| 3 | Declare `Set_BOG`/`Set_EOG` explicitly in `evaluator.ads` with caller contract | Uncle Bob | S | Low — invisible coupling accretes silently |
| 4 | Introduce `Interpreter_Context`; thread through data step chain | Fowler, Feathers | L | High — each new stateful feature deepens the global state problem |
| 5 | Extract evaluator function families into child packages | Uncle Bob | M | Med — file grows with each new function; navigation cost compounds |
| 6 | Add `CONCEPTS` help topic explaining PDV, LET/SET, BY-group model | Jobs | S | Low — but user confusion accumulates without a conceptual entry point |

---

## Caveats & Scope Limitations

The lexer, parser, and AST subsystems (`src/lexer/`, `src/parser/`, `src/ast/`) were not reviewed in depth — findings reflect the interpreter and evaluator only. The file I/O subsystem (`sdata-file_io.adb`, 1,646 lines) was not examined for ODF/OOXML parsing paths; the global state findings apply there but were not specifically evidenced. Packaging scripts (RPM spec, Debian control, SlackBuild) were not evaluated for correctness.

---

*Review conducted using the Codebase Skeptic framework. Findings represent the application of established software engineering authority to observed evidence, not personal preference.*
