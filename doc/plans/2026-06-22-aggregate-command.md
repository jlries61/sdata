# AGGREGATE Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an `AGGREGATE` immediate-execution command that collapses the current table into one row per active BY group, computing registered aggregate functions on scalar columns, registered arrays (element-wise), or array elements.

**Architecture:** Shared `Execute_AGGREGATE` lives in sdata-core's `SData_Core.Commands`; it group-scans the SELECT-filtered logical view, builds a fresh output table via the data-step output path (`Initialize_Output_Table → Add_Output_* → Commit_Output_Table`), re-registers subscripted arrays, flushes a pending SAVE, then clears SELECT + BY. Type-checking uses a dedicated aggregate-only metadata side-table (NOT a widening of the shared evaluator dispatch map). sdata owns the lexer keyword, AST node, parser, immediate dispatch, and HELP.

**Tech Stack:** Ada 2012, GNAT/GPRbuild, Alire. Two crates: `~/Develop/sdata-core` (shared lib, path-pinned) and `~/Develop/sdata` (this interpreter). Sibling consumer `~/Develop/data-vandal` must stay green (no change required).

**Source of truth:** `doc/specs/2026-06-01-aggregate-design.md` (intent) as reconciled by `.ssd/features/aggregate-command/01-architect.md` (corrections C1–C3 + drift D1–D4). Where the spec and the architect doc disagree, **the architect doc wins**.

## Global Constraints

- **sdata-core stays additive** → patch bump only, `0.1.16 → 0.1.17`. No exported signature is removed or changed. (architect D4)
- **Do NOT bump the consumer `sdata_core` floor.** `sdata/alire.toml` and `data-vandal/alire.toml` keep `sdata_core = "^0.1.16"`; `^0.1.16` already admits `0.1.17`. The `../sdata-core` path pin hides floor drift from `make check` — verify floors by reading `alire.toml`, not by trusting the build. (memory: floor-drift gotcha)
- **Cross-crate gate is mandatory before any commit that touches `src/`/tests/build files:** `cd ~/Develop/sdata-core && alr build` → `cd ~/Develop/sdata && make check` → `cd ~/Develop/data-vandal && make check`. All three green. Never `--no-verify`.
- **Error messages are verbatim** from spec §5.1 (see each task). ERR/ERL populated via `Execute_Record_Error`.
- **Validation order** inside `Execute_AGGREGATE`: `4 → 5 → 6 → 7 → 8`, with `10` checked in the interpreter *before* dispatch; parse-time errors `1,2,3,9` in `Parse_AGGREGATE`. Report only the first failing spec. No side effect on any error. (spec §5.3, §5)
- **AGGREGATE becomes a reserved keyword** — lexer enum + keyword chain + `sdata-reserved_keywords.adb` kept in sync (in-file comment requires it). (architect C3)
- **User-facing trio updated together:** built-in HELP (`src/sdata-help.adb`), man page (`man/man1/sdata.1`), design doc (`doc/design.md` — markdown, NOT `.odt`). Regenerate `tests/expected/help_all.out` + `help_index.out`. (CLAUDE.md)
- **TDD, frequent commits, DRY, YAGNI.** Each task ends green and committed.

## Spec inaccuracies discovered during implementation (fold into ADR-046)

Beyond C1–C3 and D1–D4, integration-test generation exposed three more spec
inaccuracies, all corrected in the implementation:

- **E1 — array resolution is deferred to execute time, not parse time.** The
  parser cannot decide scalar-vs-array via `Has_Array` (spec §2 implies it can):
  in batch mode the array registry is empty until `USE` runs. `Parse_AGGREGATE`
  records a bare name as `Invar_Scalar`; `Execute_AGGREGATE` resolves it to
  `Invar_Array_Name` against the live registry (a `Resolved` spec vector).
- **E2 — BY auto-sorts, so spec §3.2's "non-adjacent runs stay separate" never
  occurs.** `BY G` reorders the physical table by the BY key, so equal keys are
  always adjacent by the time AGGREGATE scans. Consecutive-run grouping (correct,
  via `In_Same_Group`) therefore yields one group per distinct key. The
  `aggregate_by_consecutive_runs` test documents this real behavior.
- **E3 — the #10 message must be honest about RUN.** See Task 6 watermark note.

## Layering note (read before starting)

AGGREGATE is a vertical slice across lexer → parser → interpreter → core. The end-to-end `.cmd` integration tests (Task 8) only pass once Tasks 1–7 are all in place. Earlier tasks are driven by the **independently testable units** the codebase already supports: sdata-core in-crate drivers (`~/Develop/sdata-core/tests/run-tests.sh`) for Tasks 1–2, and sdata parser-construction unit tests (`tests/sdata_unit_test.adb`) for Task 5. Build between every step; in Ada a "failing test" is most often a compile failure or a driver assertion.

## File Structure

**sdata-core (build first — consumer depends on it):**
- `src/sdata_core-evaluator-aggregate_fns.ads/.adb` — add `Aggregate_Metadata` record + public `Lookup`; promote from `private` child to public child. (Task 1)
- `src/sdata_core-commands.ads` — add public `Aggregate_Invar_Kind`, `Aggregate_Spec`, `Aggregate_Spec_Vectors`, `Execute_AGGREGATE`. (Task 2)
- `src/sdata_core-commands.adb` — implement `Execute_AGGREGATE`. (Task 2)
- `tests/` in-crate driver — exercise `Lookup` (Task 1) and `Execute_AGGREGATE` (Task 2).

**sdata (consumer):**
- `src/lexer/sdata-lexer.ads/.adb` + `src/sdata-reserved_keywords.adb` — `Token_AGGREGATE`. (Task 3)
- `src/ast/sdata-ast.ads/.adb` — `Stmt_AGGREGATE`, `Aggregate_Spec`/`_Access`/`_Vectors`, `Free` arm. (Task 4)
- `src/parser/sdata-parser.adb` — `Parse_AGGREGATE` + dispatch arm; convert AST spec → core spec. (Task 5)
- `src/sdata-interpreter.adb` — `Is_Immediate`, `Execute_Statement` arm, error #10 guard, three-tier comment. (Task 6)
- `src/sdata-help.adb` — `Help_AGGREGATE`, key, table row, index line. (Task 7)
- `tests/aggregate_*.cmd` + `tests/expected/aggregate_*.out` (+ `.exitcode`) — 18 integration tests. (Task 8)
- `tests/sdata_unit_test.adb` — parser-construction unit cases. (Task 5)

**Docs / release:**
- `doc/design.md`, `man/man1/sdata.1`, `doc/adrs.md` (ADR-046), `doc/architecture.md`, `CLAUDE.md`, `README.md`, `doc/threat_model.md` (glance). (Task 9)
- version bumps + tags. (Task 10)

---

### Task 1: Aggregate metadata side-table + public `Lookup` (sdata-core)

Implements architect **C1**, refined during implementation (**Option P**): put the
minimal public surface on `SData_Core.Evaluator` itself (which `Commands` already
depends on), with the metadata map in the parent's *private* part, populated by the
existing `Aggregate_Fns.Register`. **The metadata record carries only the two type
booleans — NO `Handler` field** — because `Execute_AGGREGATE` computes via the
already-public `Evaluator.Call_Function (Name, Args : Value_Array)` (evaluator.ads:130-131),
so no private `Fn_Handler`/`Value_Vectors` type is ever leaked. This avoids changing
the child's privacy AND avoids touching the parent's private dispatch types.

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-evaluator.ads` — add `Aggregate_Metadata` record + `Is_Aggregate` + `Lookup` to the **visible** part (near `Call_Function`, ~`:131`); add a `Aggregate_Meta_Maps` instance + `Aggregate_Meta_Table` map to the **private** part (near `Fn_Maps`/`Dispatch_Table`, ~`:153-161`).
- Modify: `~/Develop/sdata-core/src/sdata_core-evaluator.adb` — implement `Is_Aggregate`/`Lookup` bodies.
- Modify: `~/Develop/sdata-core/src/sdata_core-evaluator-aggregate_fns.adb` — in `Register`, populate `Aggregate_Meta_Table` alongside the existing `Dispatch_Table.Insert` calls (`:186-196`). The `.ads` (private child) stays unchanged — it is NOT promoted.
- Test: add `tests/aggregate_meta_test.adb` wired into `tests/sdata_core_tests.gpr` + `tests/run-tests.sh` driver list.

**Interfaces:**
- Consumes: existing public `Evaluator.Call_Function` + `Value_Array` (evaluator.ads:130-131); `SData_Core.Script_Error` (sdata_core.ads:19).
- Produces (all on `SData_Core.Evaluator`, public):
  ```ada
  type Aggregate_Metadata is record
     Accepts_Numeric   : Boolean;
     Accepts_Character : Boolean;
  end record;
  function Is_Aggregate (Name : String) return Boolean;       -- upper-cases internally
  function Lookup (Name : String) return Aggregate_Metadata;  -- raises Script_Error on miss: "AGGREGATE: '<name>' is not a registered aggregate function"
  ```

- [ ] **Step 1: Add the public surface to `evaluator.ads`.** In the visible part near `Call_Function`, add the `Aggregate_Metadata` record, `Is_Aggregate`, and `Lookup` declarations (with a doc comment noting `Lookup` raises `Script_Error` on miss and that the metadata is the aggregate allow-list used by AGGREGATE's parse-time/type checks). In the private part near `Dispatch_Table`, add:
  ```ada
  package Aggregate_Meta_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type => String, Element_Type => Aggregate_Metadata,
      Hash => Ada.Strings.Hash, Equivalent_Keys => "=");
  Aggregate_Meta_Table : Aggregate_Meta_Maps.Map;
  ```

- [ ] **Step 2: Implement `Is_Aggregate`/`Lookup` in `evaluator.adb`.** Upper-case the name with the same idiom used by `Call_Function`/`UC` (`evaluator.adb:121`). `Is_Aggregate` = `Aggregate_Meta_Table.Contains (UC(Name))`. `Lookup` = `if not Contains then raise SData_Core.Script_Error with "AGGREGATE: '" & Name & "' is not a registered aggregate function"; else return Aggregate_Meta_Table.Element (UC(Name));`.

- [ ] **Step 3: Populate the metadata map in `aggregate_fns.adb` `Register`.** After each existing `Dispatch_Table.Insert ("X", Handle_X'Access);` (`:186-196`), add `Aggregate_Meta_Table.Insert ("X", (Accepts_Numeric => True, Accepts_Character => <flag>));`. Flags: `N`,`NMISS` → `Accepts_Character => True`; all 9 others (`SUM,MEAN,STD,VAR,MIN,MAX,GMEAN,HMEAN,MEDIAN`) → `Accepts_Character => False`. (The child body sees `Aggregate_Meta_Table` because it is a child of `SData_Core.Evaluator` — the parent private part is visible in a child body.)

- [ ] **Step 4: Build to surface any visibility/elaboration error.**
  Run: `cd ~/Develop/sdata-core && alr build` — Expected: compiles clean.

- [ ] **Step 5: Write the unit driver `tests/aggregate_meta_test.adb`** (model on an existing driver, e.g. `tests/call_function_tests.adb`, for the assertion/exit-code convention). Assert: `Is_Aggregate("sum")` & `Is_Aggregate("MEDIAN")` True; `Is_Aggregate("sqrt")` False; `Lookup("N").Accepts_Character` True; `Lookup("SUM").Accepts_Character` False and `.Accepts_Numeric` True; `Lookup("nmiss").Accepts_Character` True; all 11 names resolve without raising. Register it in `tests/sdata_core_tests.gpr` (main list) and add `aggregate_meta_test` to the `for driver in …` loop in `tests/run-tests.sh`.

- [ ] **Step 6: Build + run drivers.**
  Run: `cd ~/Develop/sdata-core && alr build && bash tests/run-tests.sh`
  Expected: new driver passes; existing drivers still pass. (Sanity gate / Beck B1.)

- [ ] **Step 7: Confirm the shared dispatch + other 5 families untouched.**
  Run: `cd ~/Develop/sdata-core && grep -rn "Dispatch_Table" src/ | grep -v aggregate_fns`
  Expected: nav/numeric/string/distrib/misc registrations and `evaluator.adb:131,338` unchanged — confirming C1's zero-blast-radius claim.

- [ ] **Step 8: Commit.**
  ```bash
  cd ~/Develop/sdata-core
  git add src/sdata_core-evaluator.ads src/sdata_core-evaluator.adb src/sdata_core-evaluator-aggregate_fns.adb tests/aggregate_meta_test.adb tests/sdata_core_tests.gpr tests/run-tests.sh
  git commit -m "feat(aggregate): add aggregate metadata side-table + public Lookup/Is_Aggregate"
  ```

---

### Task 2: `Execute_AGGREGATE` + public spec types (sdata-core)

Implements architect **C2**. The heart of the feature.

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-commands.ads` (public surface; mirror `Use_Defaults` record style at `:68-74` and `Table.Name_Vectors` instantiation at `table.ads:167`)
- Modify: `~/Develop/sdata-core/src/sdata_core-commands.adb`
- Test: extend the in-crate driver to build a small table, set BY vars, call `Execute_AGGREGATE`, assert output schema + values.

**Interfaces:**
- Consumes (all verified): `Aggregate_Fns.Lookup`/`Is_Aggregate` (Task 1); `Table.Logical_Row_Count`, `Table.Logical_To_Physical`, `Table.In_Same_Group`, `Table.By_Var_Count`, `Table.By_Var_Name`, `Table.Clear_By_Vars`; `Table.Initialize_Output_Table`, `Add_Output_Column`, `Add_Output_Row`, `Set_Output_Value_By_Col`, `Commit_Output_Table`; `Variables.Refresh_PDV_Names`, `Variables.Register_Subscripted_Columns`; `Has_Array` + array-bounds accessor in `Variables`; `Config.Runtime.Save_File_Active`; `Execute_Commit_Step` (does `Rebuild_Filter_Map; Flush_Pending_Save; Flush_Pending_Output_Table`); `Execute_SELECT (null)`; `Execute_Record_Error`.
- Produces:
  ```ada
  type Aggregate_Invar_Kind is (Invar_Empty, Invar_Scalar, Invar_Array_Element, Invar_Array_Name);
  type Aggregate_Spec is record
     Outvar      : Ada.Strings.Unbounded.Unbounded_String;
     Fn_Name     : Ada.Strings.Unbounded.Unbounded_String;
     Invar_Kind  : Aggregate_Invar_Kind;
     Invar_Name  : Ada.Strings.Unbounded.Unbounded_String;
     Invar_Index : Natural;   -- used only when Invar_Kind = Invar_Array_Element
  end record;
  package Aggregate_Spec_Vectors is new Ada.Containers.Vectors (Positive, Aggregate_Spec);
  procedure Execute_AGGREGATE (Specs : Aggregate_Spec_Vectors.Vector);
  ```
  (Use `Unbounded_String` to match the spec §2 AST record; the bounded `Use_Defaults` style is the alternative if the package forbids `Unbounded_String` — check existing `with` clauses in `commands.ads`; it already uses `Unbounded_String` elsewhere, confirm.)

- [ ] **Step 1: Declare the public types + procedure in `commands.ads`.**
  Add the Interfaces block above to the package spec, near the other `Execute_*` declarations. Build to confirm the spec compiles (procedure body still missing → body-required error is expected at link, not compile of the spec).
  Run: `cd ~/Develop/sdata-core && alr build` — Expected: spec compiles; missing body reported.

- [ ] **Step 2: Implement pre-exec validation (errors 4→5→6→7→8) in `commands.adb`.**
  In `Execute_AGGREGATE`, before any table mutation, loop specs in order and raise `SData_Core.Script_Error` with the **verbatim** message on the first failure:
  - **#4 unknown invar** — resolve `Invar_Name`: scalar column (table has the column), registered array (`Has_Array`), or array element. If none: `"AGGREGATE: unknown variable '<name>'"`.
  - **#5 subscript out of range** — for `Invar_Array_Element`, if `Invar_Index` ∉ `1..k`: `"AGGREGATE: subscript <i> out of range for array '<name>' (1..<k>)"`.
  - **#6 type mismatch** — `m := Aggregate_Fns.Lookup (Fn_Name)`; determine input column type (numeric/character) via the table/PDV column type; if character and not `m.Accepts_Character`, or numeric and not `m.Accepts_Numeric`: `"AGGREGATE: function '<fn>' does not accept input of type <T>"` (`<T>` = `numeric`/`character`).
  - **#7 suffix mismatch** — function return type given input: `N`/`NMISS` → integer (outvar must not end `$`); all current others → numeric (no `$`). If `Outvar` ends in `$` disagreeing: `"AGGREGATE: outvar '<name>' suffix mismatch — function '<fn>' on input '<invar>' returns <type>"`.
  - **#8 BY collision** — if `Outvar` (normalized) equals any `By_Var_Name(I)`: `"AGGREGATE: outvar '<name>' collides with active BY variable"`.
  Emit warning **W1** (resize) to the normal output if an outvar pre-exists with different shape: `"AGGREGATE: resizing existing variable '<name>' (<old> → <new>)"`. (Pre-exec; same shape = silent.)

- [ ] **Step 3: Implement the group-scan + build (the C2 path).**
  Model the forward group pass on data-vandal's `Compute_Groups` (`data_vandal-execute_vandalize.adb:373-421`): iterate `for L in 1 .. Table.Logical_Row_Count`, map `P := Table.Logical_To_Physical (L)`, start a new group when `L = 1` or `not Table.In_Same_Group (P, Prev_P)`. Within a group, for each spec accumulate the group's values into a `Value_Vectors.Vector` per scalar (or k vectors per array). At group end:
  1. `Table.Add_Output_Row`.
  2. Write BY-var defining values for the group via `Set_Output_Value_By_Col`.
  3. For each spec, compute the result by calling the handler from Task 1: `Aggregate_Fns.Lookup (Fn).Handler.all (Fn, Group_Values)`; write to the spec's output column(s). For `N()` with `Invar_Kind = Invar_Empty`, the result is the integer group row count (do not call a handler — set the count directly).
  Before the loop, `Table.Initialize_Output_Table` and `Add_Output_Column` for: each BY var (preserving name + type), then each spec's column(s) in command order (scalar → 1 col named `Outvar`; array(k) → `Outvar(1)..Outvar(k)`). Missing-value handling is inherited from the handlers (they skip `Val_Missing`); empty input (`Logical_Row_Count = 0`) → zero output rows, correct schema, no warning (spec §3.5).

- [ ] **Step 4: Commit the new table + side effects (spec §3.6 order).**
  After the scan: `Table.Commit_Output_Table` (wholesale swap + `Rebuild_Column_Cache`); `Variables.Refresh_PDV_Names`; `Variables.Register_Subscripted_Columns` (ADR-041 array re-detect — mirror `Execute_USE` at `commands.adb:353-354`). Then honor a pending SAVE: if `Config.Runtime.Save_File_Active`, call `Execute_Commit_Step` (which runs `Flush_Pending_Save` — clears SAVE) wrapped so a flush failure raises `"AGGREGATE: SAVE flush failed: " & <inner message>` (#11, post-exec — in-memory swap is NOT rolled back, matches VANDALIZE). Finally clear SELECT via `Execute_SELECT (null)` (also clears the index map) and clear BY via `Table.Clear_By_Vars`.

- [ ] **Step 5: Write the failing core driver test.**
  Extend `~/Develop/sdata-core/tests/aggregate_meta_test.adb` (or a new `aggregate_exec_test.adb`): programmatically build a 2-column table (`g` group key with values 1,1,2 and `x` numeric 10,20,30), `Table.Add_By_Var ("G")`, build an `Aggregate_Spec_Vectors.Vector` with `total = SUM(x)` and `n = N()`, call `Execute_AGGREGATE`, then assert the post-state table has columns `G,total,n`, 2 rows, with `(1,30,2)` and `(2,30,1)`. Also assert BY is cleared (`By_Var_Count = 0`).

- [ ] **Step 6: Build + run the driver.**
  Run: `cd ~/Develop/sdata-core && alr build && bash tests/run-tests.sh`
  Expected: FAIL before Steps 2–4 land; PASS after. Iterate until green.

- [ ] **Step 7: Cross-crate smoke (sdata-core change must not break consumers via API).**
  Run: `cd ~/Develop/sdata && alr build` and `cd ~/Develop/data-vandal && alr build`
  Expected: both still build against the additive sdata-core. (Full `make check` deferred to Task 10; this is the early additive-API smoke.)

- [ ] **Step 8: Commit.**
  ```bash
  cd ~/Develop/sdata-core
  git add src/sdata_core-commands.ads src/sdata_core-commands.adb tests/
  git commit -m "feat(aggregate): implement Execute_AGGREGATE (group-scan, build-swap, SAVE flush, clear SELECT/BY)"
  ```

---

### Task 3: Lexer keyword `Token_AGGREGATE` (sdata)

Implements architect **C3**.

**Files:**
- Modify: `src/lexer/sdata-lexer.ads:23-32` (`Token_Kind` enum)
- Modify: `src/lexer/sdata-lexer.adb:~313` (keyword if/elsif chain; fallthrough `else Token_Identifier` at `:319`)
- Modify: `src/sdata-reserved_keywords.adb:~20` (alphabetical, between `AS` and `BREAK`)

**Interfaces:**
- Produces: `Token_AGGREGATE` token kind, recognised case-insensitively.

- [ ] **Step 1: Add `Token_AGGREGATE` to the `Token_Kind` enum** in `sdata-lexer.ads` (alongside `Token_SORT`, `Token_DISPLAY`, etc.).

- [ ] **Step 2: Add the keyword arm** in `sdata-lexer.adb`: `elsif Upper = "AGGREGATE" then T.Kind := Token_AGGREGATE;` (model on the `DISPLAY` arm at `:313`).

- [ ] **Step 3: Add to the reserved-keyword set** in `sdata-reserved_keywords.adb`: `S.Insert ("AGGREGATE");` in alphabetical position. (The in-file comment requires keeping this in sync with the lexer.)

- [ ] **Step 4: Build.**
  Run: `cd ~/Develop/sdata && alr build`
  Expected: compiles. (Parser `case Tok.Kind` will warn/error about an unhandled `Token_AGGREGATE` only if the case has no `others`; it has `when others =>` at `parser.adb:2548`, so it compiles and currently routes AGGREGATE to "Unrecognized command" until Task 5.)

- [ ] **Step 5: Commit.**
  ```bash
  cd ~/Develop/sdata
  git add src/lexer/sdata-lexer.ads src/lexer/sdata-lexer.adb src/sdata-reserved_keywords.adb
  git commit -m "feat(aggregate): add AGGREGATE lexer keyword + reserved-word entry"
  ```

---

### Task 4: AST node `Stmt_AGGREGATE` (sdata)

**Files:**
- Modify: `src/ast/sdata-ast.ads` — add `Aggregate_Spec`/`_Access`/`_Vectors` near `Dataset_Spec` (`:75-86`); add `Stmt_AGGREGATE` to `Statement_Kind` (`:158`); add variant arm after the `Stmt_WRITE` arm (`:261-264`).
- Modify: `src/ast/sdata-ast.adb` — add `Ada.Unchecked_Deallocation` instance (near `:9-14`) + a `when Stmt_AGGREGATE =>` arm in `Free` (`:106-182`).

**Interfaces:**
- Produces (sdata-side AST mirror of the core spec record):
  ```ada
  type Aggregate_Invar_Kind is (Invar_Empty, Invar_Scalar, Invar_Array_Element, Invar_Array_Name);
  type Aggregate_Spec is record
     Outvar      : Unbounded_String;
     Fn_Name     : Unbounded_String;
     Invar_Kind  : Aggregate_Invar_Kind;
     Invar_Name  : Unbounded_String;
     Invar_Index : Natural := 0;
  end record;
  type Aggregate_Spec_Access is access Aggregate_Spec;
  package Aggregate_Spec_Vectors is new Ada.Containers.Vectors (Positive, Aggregate_Spec_Access);
  ```
  And in the `Statement` variant: `when Stmt_AGGREGATE => Agg_List : Aggregate_Spec_Vectors.Vector;`

- [ ] **Step 1: Declare the spec types** near `Dataset_Spec` (`ast.ads:75-86`), mirroring `Dataset_Spec_Access` + `Dataset_Spec_Vectors`.

- [ ] **Step 2: Add `Stmt_AGGREGATE`** to the `Statement_Kind` enumeration (`ast.ads:158`).

- [ ] **Step 3: Add the variant arm** `when Stmt_AGGREGATE => Agg_List : Aggregate_Spec_Vectors.Vector;` after the `Stmt_WRITE` arm (`ast.ads:~264`).

- [ ] **Step 4: Add the deallocation instance + `Free` arm** in `ast.adb`: add `procedure Free_Aggregate_Spec is new Ada.Unchecked_Deallocation (Aggregate_Spec, Aggregate_Spec_Access);` near `:9-14`; add a `when Stmt_AGGREGATE =>` arm in `Free` that loops `Stmt.Agg_List.First_Index .. Last_Index`, calls `Free_Aggregate_Spec` on each element, then `Stmt.Agg_List.Clear;` (model on the `Stmt_USE | Stmt_SAVE` arm at `:117-144`). No `Expression_Access` fields → no expression frees needed.

- [ ] **Step 5: Build.**
  Run: `cd ~/Develop/sdata && alr build`
  Expected: compiles (the new `Stmt_AGGREGATE` will surface as unhandled in `Is_Immediate`/`Execute_Statement` only if those use exhaustive `case` without `others` — they use membership tests / have `others`; confirm at build, address in Task 6).

- [ ] **Step 6: Commit.**
  ```bash
  cd ~/Develop/sdata
  git add src/ast/sdata-ast.ads src/ast/sdata-ast.adb
  git commit -m "feat(aggregate): add Stmt_AGGREGATE AST node + Free arm"
  ```

---

### Task 5: Parser `Parse_AGGREGATE` + parse-time errors (sdata)

**Files:**
- Modify: `src/parser/sdata-parser.adb` — new `Parse_AGGREGATE` (model on `Parse_USE_Stmt` at `:1123`); dispatch arm `when Token_AGGREGATE =>` in `Parse_Statement` (`:1680` case, near the SORT/DISPLAY arms ~`:2233-2493`).
- Test: `tests/sdata_unit_test.adb` — parser-construction cases (spec §8.2).

**Interfaces:**
- Consumes: `Has_Array` (from `SData_Core.Variables`, already `with`/`use`d at `parser.adb:10`) for array-name resolution at parse time; `Aggregate_Fns.Is_Aggregate` (Task 1) for error #2; the AST types from Task 4.
- Produces: a `Stmt_AGGREGATE` statement with a populated `Agg_List`.

- [ ] **Step 1 (DEVIATION — recorded 2026-06-22): no standalone parser unit tests.**
  The spec §8.2 assumed parser-construction cases live in `tests/sdata_unit_test.adb`,
  but that binary tests `SData_Core.Variables`/PDV — **this codebase has no parser
  unit-test harness; the parser is exercised exclusively through `.cmd` integration
  tests.** Building a new harness is scope creep. Instead, `Parse_AGGREGATE`'s
  parse-time errors are covered by integration tests in Task 8: `aggregate_unknown_fn`
  (#2), `aggregate_nmiss_no_arg` (#3), plus added `aggregate_dup_outvar` (#9) and
  `aggregate_empty_spec` (#1). Happy-path kind resolution (scalar / array / element /
  empty) is covered by `aggregate_basic`, `aggregate_array_input`,
  `aggregate_array_element`, `aggregate_no_arg_n`.

- [ ] **Step 2: Implement `Parse_AGGREGATE (Ctx, Stmt)`.** Allocate `Stmt := new Statement (Stmt_AGGREGATE);`. Loop parsing whitespace-separated specs until end-of-statement: each spec is `<outvar> = <fn> ( <invar-or-empty> )`. For each:
  - parse `Outvar` identifier (may end `$`); split function name; require `(`.
  - **#1** empty spec list (no specs parsed) → raise `"AGGREGATE: at least one outvar spec required"`.
  - **#2** `if not Aggregate_Fns.Is_Aggregate (Fn) then raise … "is not a registered aggregate function"`. (Rejects non-aggregates like `SQRT`, `LEN$` at parse time.)
  - **#3** non-`N` function with empty `()` → `"AGGREGATE: function '<name>' requires an argument"`. `N()` empty is allowed (kind `Invar_Empty`).
  - Resolve invar kind: empty → `Invar_Empty`; identifier followed by `(int)` → `Invar_Array_Element` (capture index, must be positive integer literal); identifier where `Has_Array(UC(name))` → `Invar_Array_Name`; else `Invar_Scalar`. (Same `Has_Array` parse-time idiom as `Parse_Primary` at `parser.adb:432`.)
  - **#9** duplicate outvar within this command → `"AGGREGATE: duplicate outvar name '<name>'"`.
  - append a `new Aggregate_Spec'(...)` to `Stmt.Agg_List`.

- [ ] **Step 3: Add the dispatch arm** in `Parse_Statement`: `when Token_AGGREGATE => Stmt := new Statement (Stmt_AGGREGATE); Parse_AGGREGATE (Ctx, Stmt);` (placed near `:2454`).

- [ ] **Step 4: Build + run unit tests until green.**
  Run: `cd ~/Develop/sdata && make build && ./bin/sdata_unit_test`
  Expected: the new parser cases PASS; existing cases unaffected.

- [ ] **Step 5: Commit.**
  ```bash
  cd ~/Develop/sdata
  git add src/parser/sdata-parser.adb tests/sdata_unit_test.adb
  git commit -m "feat(aggregate): parse AGGREGATE specs with parse-time error checks"
  ```

---

### Task 6: Interpreter dispatch + error #10 guard (sdata)

**Files:**
- Modify: `src/sdata-interpreter.adb` — `Is_Immediate` (`:84-93`), `Execute_Statement` dispatch (`:749-864`, case at `:753`), three-tier comment (`:33-60`).

**Interfaces:**
- Consumes: `Program_Buffer_Length` (`interpreter.ads:22`) for error #10; the AST `Agg_List` (Task 4); `SData_Core.Commands.Execute_AGGREGATE` + `Aggregate_Spec_Vectors` (Task 2).
- Produces: end-to-end execution of AGGREGATE.

- [ ] **Step 1: Add `Stmt_AGGREGATE` to `Is_Immediate`** (`:86-92` membership list) so the REPL/Execute path treats it as immediate.

- [ ] **Step 2 (REFINED — #10 semantics): watermark, not bare non-empty.**
  The deferred buffer **persists across RUN** (`interpreter.adb:400` — only NEW/USE/
  REPEAT replace it), so a bare `Program_Buffer_Length > 0` guard would block the
  normal `REPEAT/LET/RUN → AGGREGATE` workflow AND make the error message's "issue
  RUN first" guidance false (RUN can't clear the buffer). Fix: track
  `Committed_Program_Len` = buffer length at the last RUN (set in
  `Run_Active_Program`, reset to 0 in `Clear_Active_Program`); fire #10 only when
  `Program_Buffer_Length > Committed_Program_Len` (i.e. statements appended **since**
  the last RUN). Now RUN genuinely resolves the condition. Validated: data-step
  workflow passes; a `LET` queued after RUN fires #10; a following RUN clears it.
  **Fold into ADR-046 as a sixth decision.** The `when Stmt_AGGREGATE =>` arm calls
  the `Execute_Aggregate` helper which performs this guard. Then convert the AST `Agg_List` (vector of `Aggregate_Spec_Access`) into a `SData_Core.Commands.Aggregate_Spec_Vectors.Vector` (copy each field; map the `Aggregate_Invar_Kind` enum 1:1), and call `SData_Core.Commands.Execute_AGGREGATE (Core_Specs);`. Wrap in the existing error handling so runtime errors route through `Execute_Record_Error` (ERR/ERL). Print a success line consistent with sibling immediate commands (e.g. SORT's "…N records and V variables processed.") — confirm exact wording against `Run_Active_Program`/SORT output and reuse the same helper.

- [ ] **Step 3: Update the three-tier comment block** (`:38-39`) to add `AGGREGATE` to the Immediate-tier examples list.

- [ ] **Step 4: Build + manual end-to-end smoke.**
  Run:
  ```bash
  cd ~/Develop/sdata && alr build
  printf 'NEW\nREPEAT 3\nLET g=1\nLET x=10*RECNO\nRUN\nAGGREGATE total=SUM(x) n=N()\nDISPLAY\nQUIT\n' | ./bin/sdata
  ```
  Expected: one row, columns `total=60, n=3` (adjust to the exact LET semantics; the point is AGGREGATE now executes end-to-end rather than "Unrecognized command").

- [ ] **Step 5: Commit.**
  ```bash
  cd ~/Develop/sdata
  git add src/sdata-interpreter.adb
  git commit -m "feat(aggregate): dispatch AGGREGATE as immediate command with pending-buffer guard"
  ```

---

### Task 7: HELP topic + snapshot regen (sdata)

**Files:**
- Modify: `src/sdata-help.adb` — `Help_AGGREGATE` proc (model `Help_SORT` at `:225-230`); `K_AGGREGATE` constant (~`:1185`); `Help_Table` row (~`:1398`); `Help_Index` category line (~`:21`).
- Regenerate: `tests/expected/help_all.out`, `tests/expected/help_index.out`.

- [ ] **Step 1: Add `Help_AGGREGATE`** emitting Command/description/Execution lines (syntax from spec §2; behavior one-paragraph; pointer to man page), `K_AGGREGATE : aliased constant String := "AGGREGATE";`, the `(K_AGGREGATE'Access, Help_AGGREGATE'Access, C, N),` table row, and an AGGREGATE entry on the appropriate `Help_Index` category line (e.g. "Data step:").

- [ ] **Step 2: Build, then regenerate the two snapshots from actual output.**
  Run:
  ```bash
  cd ~/Develop/sdata && alr build
  ./bin/sdata tests/help_all.cmd > tests/expected/help_all.out
  printf 'HELP\nQUIT\n' | ./bin/sdata > tests/expected/help_index.out   # confirm help_index.cmd's actual driver first
  ```
  Inspect both diffs to confirm ONLY the AGGREGATE additions changed (no accidental reflow).
  Run: `git diff tests/expected/help_all.out tests/expected/help_index.out`

- [ ] **Step 3: Confirm no reserved-keyword / options snapshot drift.**
  Run: `cd ~/Develop/sdata && grep -rl "AGGREGATE" tests/expected/ ; ls tests/expected/*options*`
  Expected: AGGREGATE appears only where intended; `*options*` snapshots unchanged (AGGREGATE doesn't touch OPTIONS). If a reserved-keyword snapshot lists keywords, regenerate it too.

- [ ] **Step 4: Commit.**
  ```bash
  cd ~/Develop/sdata
  git add src/sdata-help.adb tests/expected/help_all.out tests/expected/help_index.out
  git commit -m "docs(help): add HELP AGGREGATE topic + regenerate snapshots"
  ```

---

### Task 8: Integration tests (sdata) — the 18 `.cmd` cases

**Files:** Create paired `tests/aggregate_*.cmd` + `tests/expected/aggregate_*.out`; for error cases that exit non-zero, add `tests/aggregate_*.exitcode`. (Harness: `Makefile:126-170`; golden-file diff `-wu`.)

The 18 scenarios (spec §8.1, re-baselined): `aggregate_basic`, `aggregate_by_single`, `aggregate_by_multi`, `aggregate_by_consecutive_runs`, `aggregate_array_input`, `aggregate_array_element`, `aggregate_array_resize_warn`, `aggregate_no_arg_n`, `aggregate_select_active`, `aggregate_save_flush`, `aggregate_by_cleared`, `aggregate_character_min_max` (err), `aggregate_nmiss_no_arg` (err), `aggregate_by_collision` (err), `aggregate_buffer_nonempty` (err), `aggregate_empty_input`, `aggregate_unknown_fn` (err), `aggregate_unknown_invar` (err).

- [ ] **Step 1: Write the success-case `.cmd` scripts** (model on `tests/sort_test.cmd`). Each is a sequence of REPL commands building a small table, then AGGREGATE, then DISPLAY/PRINT to render the result. Keep inputs tiny and deterministic.

- [ ] **Step 2: Write the error-case `.cmd` scripts** and their `.exitcode` files (non-zero) reproducing each catalogued error; the error message lands in captured stdout/stderr.

- [ ] **Step 3: Generate expected outputs from actual runs, verifying each by inspection** (golden-file convention this harness uses — there is no way to pre-write exact rendering):
  ```bash
  cd ~/Develop/sdata && alr build
  for t in aggregate_basic aggregate_by_single aggregate_by_multi aggregate_by_consecutive_runs \
           aggregate_array_input aggregate_array_element aggregate_array_resize_warn \
           aggregate_no_arg_n aggregate_select_active aggregate_save_flush aggregate_by_cleared \
           aggregate_character_min_max aggregate_nmiss_no_arg aggregate_by_collision \
           aggregate_buffer_nonempty aggregate_empty_input aggregate_unknown_fn aggregate_unknown_invar; do
    ./bin/sdata tests/$t.cmd > tests/expected/$t.out 2>&1
    echo "=== $t ==="; cat tests/expected/$t.out
  done
  ```
  Read each output and confirm it matches the spec's intended semantics BEFORE accepting it as golden. For `aggregate_save_flush`, also confirm the SAVE file was written and assert the pending SAVE cleared (a following `SAVE`-less run). For `aggregate_select_active`/`aggregate_by_cleared`, add follow-up commands proving SELECT/BY were cleared.

- [ ] **Step 4: Run the full integration suite.**
  Run: `cd ~/Develop/sdata && make check`
  Expected: 202 prior + 18 new = **220** integration tests pass; all unit binaries pass.

- [ ] **Step 5: Commit.**
  ```bash
  cd ~/Develop/sdata
  git add tests/aggregate_*.cmd tests/expected/aggregate_*.out tests/aggregate_*.exitcode
  git commit -m "test(aggregate): add 18 integration tests (220 total)"
  ```

---

### Task 9: Documentation trio + ADR-046 + threat-model glance (sdata)

**Files:** `doc/design.md`, `man/man1/sdata.1`, `doc/adrs.md`, `doc/architecture.md`, `CLAUDE.md`, `README.md`, `doc/threat_model.md`.

- [ ] **Step 1: `doc/design.md`** — new AGGREGATE section under "Commands": syntax, semantics, BY/SELECT/SAVE interaction, function set, array behavior, error summary. Add the note that aggregate functions accept character input only if their dispatch metadata says so (current: `N`, `NMISS`). Match the existing HTML-table style for the command/function reference.

- [ ] **Step 2: `man/man1/sdata.1`** — new `.TP` / `.B AGGREGATE` block under "Immediate commands": one syntax line + one-paragraph semantics, cross-referencing BY, SAVE, SELECT.

- [ ] **Step 3: `doc/adrs.md` — add ADR-046** (next free number; ADR-044/045 are taken). Title e.g. "AGGREGATE: active-BY grouping, no auto-sort, write-and-clear SAVE, clear BY, and aggregate metadata side-table." Capture the **five** decisions (architect Decision Log): active BY only / no auto-sort / write-and-clear SAVE / clear BY post-AGGREGATE / metadata as a dedicated public side-table (C1). Status: Accepted.

- [ ] **Step 4: `doc/architecture.md`** — one line in the shared-commands list mentioning `Execute_AGGREGATE`.

- [ ] **Step 5: `CLAUDE.md`** — add AGGREGATE to the Immediate-command list (three-tier table) and the sdata-only command list in the repo-layout prose.

- [ ] **Step 6: `README.md`** — optional one bullet under feature highlights.

- [ ] **Step 7: `doc/threat_model.md`** — glance per systems-designer §3. AGGREGATE adds no new input surface (reads existing table, writes via existing SAVE path). Add a one-line note ONLY if the doc enumerates per-command surfaces; otherwise leave unchanged and record "no new surface" in the commit message.

- [ ] **Step 8: Commit (docs-only — no `make check` required per CLAUDE.md, but this commit also has no `src/` changes).**
  ```bash
  cd ~/Develop/sdata
  git add doc/design.md man/man1/sdata.1 doc/adrs.md doc/architecture.md CLAUDE.md README.md doc/threat_model.md
  git commit -m "docs(aggregate): document AGGREGATE; add ADR-046"
  ```

---

### Task 10: Cross-crate gate, version bumps, tags (release)

**Files:** `~/Develop/sdata-core/alire.toml`; sdata's 9 version files via `scripts/bump-version.sh`.

- [ ] **Step 1: Full three-way gate (mandatory).**
  ```bash
  cd ~/Develop/sdata-core && alr build
  cd ~/Develop/sdata && make check          # expect 220 integration + all unit
  cd ~/Develop/data-vandal && make check    # expect green, unchanged
  ```
  All three must pass. If data-vandal fails, STOP — the additive change regressed a consumer.

- [ ] **Step 2: Bump sdata-core patch 0.1.16 → 0.1.17.** Edit `~/Develop/sdata-core/alire.toml` `version = "0.1.17"`. Confirm **no** consumer floor change is needed: `grep sdata_core ~/Develop/sdata/alire.toml ~/Develop/data-vandal/alire.toml` → both `^0.1.16` (admits 0.1.17). Commit + tag:
  ```bash
  cd ~/Develop/sdata-core && git add alire.toml && git commit -m "chore: bump version to 0.1.17 (AGGREGATE Execute_AGGREGATE API)"
  git tag -a v0.1.17 -m "Version 0.1.17"
  ```

- [ ] **Step 3: Bump sdata version.**
  ```bash
  cd ~/Develop/sdata
  scripts/bump-version.sh 0.10.0 "AGGREGATE command"
  git add -A && git commit -m "chore: bump version to 0.10.0 (AGGREGATE command)"
  git tag -a v0.10.0 -m "Version 0.10.0"
  ```
  (`0.10.0` — confirmed by the user 2026-06-22 for this new command.)

- [ ] **Step 4: Final verification.**
  Run: `cd ~/Develop/sdata && make check` once more on the bumped tree. Expected: green.
  Confirm `sdata-core` consumer-tests pin note in CLAUDE.md is unaffected (this is an additive change; no pinned-consumer break).

---

## Self-Review

**Spec coverage:** §2 grammar → Tasks 4,5. §3 semantics (group ID, per-group agg, output schema, empty input, side effects) → Task 2. §4 type handling / metadata refactor → Tasks 1,2 (revised per C1). §5 error catalog (1–11) → Tasks 2 (#4–8,11), 5 (#1,2,3,9), 6 (#10) + W1 (Task 2). §6 examples → Task 8 tests. §7 footprint → reconciled across tasks (C1/C2/C3). §8 tests → Tasks 1,2,5,8. §9 docs → Task 9. §10 versioning → Task 10. §11 out-of-scope → not implemented (MODE, char MIN/MAX, windowed, expr args, /BY=). **No gaps.**

**Placeholder scan:** Large Ada bodies (`Execute_AGGREGATE` group-scan, `Parse_AGGREGATE`) are specified by exact API calls + verified line-cited patterns to mirror rather than fully literal 200-line bodies, because the surrounding bodies were not read in full and fabricating them would risk wrong signatures. This is a deliberate, flagged tradeoff: every API the implementer must call is named with its verified signature/location; expected `.out` files are golden-generated-then-inspected (the harness's actual convention), not fabricated. Error messages ARE verbatim. Test scripts ARE concrete in structure.

**Type consistency:** `Aggregate_Invar_Kind` literals: core uses `Invar_Empty/Invar_Scalar/Invar_Array_Element/Invar_Array_Name` (Task 2); sdata AST uses the same names (Task 4) for a 1:1 enum map (Task 6). `Aggregate_Spec` fields (`Outvar/Fn_Name/Invar_Kind/Invar_Name/Invar_Index`) identical in both crates. `Lookup`/`Is_Aggregate` names consistent across Tasks 1,2,5. `Execute_AGGREGATE (Specs : Aggregate_Spec_Vectors.Vector)` consistent Tasks 2,6.
