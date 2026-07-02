# Entry-Time Semantic Checking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move type-mismatch, unknown-function, arity, and undefined-variable checks for deferred statements from per-record `RUN` time to statement-entry (interactive) / pre-`RUN` (batch), and make `USE`/`REPEAT` clear the deferred program so those checks are sound.

**Architecture:** Part 1 fixes a latent spec violation — `USE`/`REPEAT` must cancel queued deferred statements (per `doc/design.md:960`), which the code currently does only on `NEW`. Part 2 adds a static semantic analyzer: a name-suffix-driven `Static_Result_Kind` in `sdata-core`, a per-statement checker in sdata driven by a static "known-name" environment, invoked authoritatively as a pre-`RUN` pass (both modes) and additionally at statement entry (interactive, for immediate feedback). Checks are **sound, not complete**: they reject only provable violations and defer whenever a type/name cannot be statically determined.

**Tech Stack:** Ada 2012, Alire (`alr build`), GNAT. Two crates: `sdata` (this repo) and `sdata-core` (`../sdata-core`). Tests: `.cmd` integration scripts diffed against `tests/expected/*.out`, plus Ada unit-test drivers.

## Global Constraints

- **Cross-crate build order:** any `sdata-core` change → `cd ~/Develop/sdata-core && alr build` first, then `cd ~/Develop/sdata && make check`, then `cd ~/Develop/data-vandal && make check`. All three green before committing (CLAUDE.md).
- **All 299 integration tests + 5 unit-test binaries must pass** before any commit touching `src/`, `tests/`, `*.gpr`, `Makefile`, or `alire.toml`. Never `--no-verify`.
- **Type system is name-suffix-driven:** `$`→`Val_String`, `%`→`Val_Integer`, else `Val_Numeric`. This is exactly `SData_Core.Evaluator.Get_Expected_Kind (Name : String) return Value_Kind` (already public, `sdata_core-evaluator.ads:106`). Reuse it; do not reinvent.
- **`Value_Kind`** = `(Val_Numeric, Val_Integer, Val_String, Val_Missing)` (`sdata_core-values.ads:15`).
- **Soundness rule (non-negotiable):** when a static kind or name cannot be resolved, the analyzer DEFERS (no error). Only provable violations raise.
- **Error type:** raise `SData_Core.Script_Error` (or `SData.Script_Error`; both are caught at the REPL and batch top level and printed as `Error: <msg>`). Hard errors for all four checks.
- **sdata-core public API:** `Expression`/`Expression_Access`/`Expression_Kind` live in `SData_Core.Evaluator` (`sdata_core-evaluator.ads:29-90`). Adding new public functions there is allowed; regenerate `docs/api/reference.html` via `scripts/gen-reference.sh` and commit it (sdata-core CLAUDE.md).
- **User-facing surface:** any behavior change is documented in `doc/design.md`, `man/man1/sdata.1`, and (where a topic applies) `src/sdata-help.adb`; regenerate `tests/expected/help_all.out` if HELP output changes.

---

## Reference: key existing code

- **Batch walker** `Execute (Prog)` — `src/sdata-interpreter.adb:1468-1532`. Walks the linked list; `Step_Start` marks the current deferred block; on `Stmt_RUN` it calls `Run_One_Step (Step_Start, Current)` (line 1480) then `Step_Start := Current.Next` (line 1498). Deferred kinds are skipped and counted in `Pending_Deferred` (lines 1499-1528).
- **Interactive queue** `Add_To_Active_Program` — `src/sdata-interpreter.adb:362-377`; increments `Pending_Deferred`. `Run_Active_Program` (425-471) chains `Active_Program_Vec` entries + a synthetic `Stmt_RUN` cap and calls `Execute`, so interactive RUNs flow through the same walker.
- **Full reset** `Clear_Active_Program` — `src/sdata-interpreter.adb:379-391`: frees `Active_Program_Vec`, zeros `Pending_Deferred`, resets `Append_Mode`/`Insert_Point`, AND clears SELECT filter, index map, BY-vars. Called only from the `Stmt_NEW` handler (`sdata-interpreter-execute_declarative.adb:793`).
- **USE handler** — `sdata-interpreter-execute_declarative.adb:59` (`Execute_USE_Single`), `:194` (`Execute_USE_Multi`), dispatched from the `Stmt_USE` arm.
- **REPEAT handler** — `sdata-interpreter-execute_declarative.adb:767` (`when Stmt_REPEAT =>`).
- **Runtime type check** `Coerce_For_Scalar` — `src/sdata-interpreter-execute_assignment.adb:96-147`; raises `SData_Core.Table.Type_Mismatch_Error` per record.
- **Existing entry-time literal check (issue #31)** — `src/parser/sdata-parser.adb:2148-2187`. Keep as-is; the new checks generalize it.
- **Parser function/array classification** — `src/parser/sdata-parser.adb:426-462`: `name(args)` → `Expr_Array_Access` iff `Has_Array` true *now*, else `Expr_Function_Call`. In batch, `DIM` has not run at parse time, so array elements parse as function calls — the analyzer must re-disambiguate via `Has_Array`.
- **Accessors:** `SData_Core.Table.Has_Column (Name) return Boolean` (`sdata_core-table.ads:39`), `Column_Count` (`:47`), `Column_Name (I)` (`:51`); `SData_Core.Variables.Get_Type (Name)` (`:62`), `Has_Array (Name)` (`:85`), `Get_Session_Names return GNAT.Strings.String_List_Access` (`:66`).
- **AST:** `Statement` common fields `Var_Name`/`Var_Len`/`Is_Array`/`Expr` and full `Statement_Kind` in `src/ast/sdata-ast.ads:142-316`. `Expression` variant in `sdata_core-evaluator.ads:60-90`.

---

## PHASE A — Part 1: `USE`/`REPEAT` clear the deferred program

### Task A1: Narrow `Clear_Deferred_Program` + interactive USE/REPEAT clearing

**Files:**
- Modify: `src/sdata-interpreter.ads` (add declaration)
- Modify: `src/sdata-interpreter.adb` (add body near `Clear_Active_Program:379`)
- Modify: `src/sdata-interpreter-execute_declarative.adb` (call it in USE + REPEAT arms)
- Test: `tests/use_clears_deferred.cmd` + `tests/expected/use_clears_deferred.out`

**Interfaces:**
- Produces: `procedure SData.Interpreter.Clear_Deferred_Program;` — frees the deferred program buffer and resets `Pending_Deferred`, `Append_Mode`, `Insert_Point`; does NOT touch the SELECT filter, index map, or BY-vars (unlike `Clear_Active_Program`).

- [ ] **Step 1: Write the failing integration test**

Create `tests/use_clears_deferred.cmd`:
```
-- A LET queued before USE must be cancelled by USE (design.md:960).
-- MARKER must NOT appear as a column after RUN.
LET MARKER = 1
USE MOCK
NAMES
RUN
```
Create `tests/expected/use_clears_deferred.out` capturing the intended behavior: `NAMES` lists only MOCK's columns (`ID NAME$ SALARY`) with no `MARKER`, and `RUN` reports the MOCK column count (3), not 4. (Fill the exact expected text after Step 3 by running the binary once and confirming MARKER is absent; the test asserts MARKER absence.)

- [ ] **Step 2: Run it to verify current (buggy) behavior**

Run: `make build && ./bin/sdata tests/use_clears_deferred.cmd`
Expected BEFORE fix: `MARKER` IS present (LET survives USE) — demonstrates the bug.

- [ ] **Step 3: Add `Clear_Deferred_Program`**

In `src/sdata-interpreter.ads`, after line 25 (`procedure Clear_Active_Program;`):
```ada
   --  Clears ONLY the deferred program buffer and its pending counter /
   --  insertion cursor.  Unlike Clear_Active_Program it leaves the SELECT
   --  filter, index map, and BY-vars intact.  Called by USE and REPEAT so a
   --  new input source cancels queued LET/SET/etc. (design.md:960) without
   --  disturbing unrelated session state.
   procedure Clear_Deferred_Program;
```

In `src/sdata-interpreter.adb`, immediately before `Clear_Active_Program` (line 379):
```ada
   procedure Clear_Deferred_Program is
   begin
      for E of Active_Program_Vec loop
         SData.AST.Free_Program (E.Stmt);
      end loop;
      Active_Program_Vec.Clear;
      Pending_Deferred := 0;
      Append_Mode  := True;
      Insert_Point := 0;
   end Clear_Deferred_Program;
```

- [ ] **Step 4: Call it from the USE and REPEAT handlers**

In `src/sdata-interpreter-execute_declarative.adb`, in the `Stmt_REPEAT` arm (line 767), add as the FIRST statement of the arm:
```ada
      when Stmt_REPEAT =>
         Clear_Deferred_Program;
         SData_Core.Table.Clear;
         SData_Core.Commands.Execute_REPEAT (Stmt.Count);
         Input_File_Columns.Clear;
```
In the `Stmt_USE` arm, after the dataset has been loaded (i.e. after the `Execute_USE_Single` / `Execute_USE_Multi` dispatch completes, so the clear cannot interfere with reading the file), add `Clear_Deferred_Program;`. Locate the end of the USE arm (after line 545's `Execute_USE_Multi;` dispatch block) and insert the call there.

> Note: `Clear_Deferred_Program` must be visible inside the separate body `execute_declarative.adb`. It is a private sibling of `Execute_Declarative`; since both are children/subunits of `SData.Interpreter`, reference it as `SData.Interpreter.Clear_Deferred_Program` or via the parent's visibility. Confirm it compiles; if the subunit cannot see it, promote the declaration into the package spec (already done in Step 3) — spec-visible is sufficient.

- [ ] **Step 5: Rebuild, finalize expected output, verify test passes**

Run: `make build && ./bin/sdata tests/use_clears_deferred.cmd`
Confirm `MARKER` is ABSENT and RUN reports 3 variables. Write that exact output into `tests/expected/use_clears_deferred.out`.
Run: `make check` (interactive-path clearing is now covered).
Expected: PASS, no regressions.

- [ ] **Step 6: Commit**

```bash
git add src/sdata-interpreter.ads src/sdata-interpreter.adb \
        src/sdata-interpreter-execute_declarative.adb \
        tests/use_clears_deferred.cmd tests/expected/use_clears_deferred.out
git commit -m "fix: USE and REPEAT clear the deferred program buffer (design.md:960)"
```

### Task A2: Batch walker cancels the deferred block on USE/REPEAT

**Files:**
- Modify: `src/sdata-interpreter.adb:1499-1529` (the immediate-execution branch of `Execute`)
- Test: `tests/use_clears_deferred_batch.cmd` + `tests/expected/use_clears_deferred_batch.out`

**Interfaces:**
- Consumes: `Step_Start`, `Pending_Deferred` locals/state in `Execute`.
- Produces: batch semantics where deferred statements textually BEFORE a `USE`/`REPEAT` do not run at a later `RUN`.

- [ ] **Step 1: Write the failing test**

Create `tests/use_clears_deferred_batch.cmd`:
```
-- LET before USE must not run against the dataset loaded by USE.
LET MARKER = 1
USE MOCK
RUN
NAMES
```
Create `tests/expected/use_clears_deferred_batch.out`: RUN reports 3 variables; NAMES shows no MARKER. (Finalize text in Step 4.)

- [ ] **Step 2: Verify current behavior is wrong**

Run: `make build && ./bin/sdata tests/use_clears_deferred_batch.cmd`
Expected BEFORE fix: MARKER present (pre-USE LET runs). Note: Task A1's `Clear_Deferred_Program` does NOT fix batch, because batch keeps deferred statements in the parsed linked list, not `Active_Program_Vec`.

- [ ] **Step 3: Reset the deferred block in the walker**

In `src/sdata-interpreter.adb`, the immediate-execution branch runs `Execute_Statement (Current, Outer_Ctx)` (line 1509). Immediately AFTER that call returns normally (inside the same `declare` block, after line 1509, before the exception handlers), add:
```ada
               --  A new input source cancels any deferred statements queued
               --  before it (design.md:960): advance the deferred-block start
               --  past this statement and drop the pending count so the next
               --  RUN's data step excludes them.
               if Current.Kind = Stmt_USE or else Current.Kind = Stmt_REPEAT then
                  Step_Start := Current.Next;
                  Pending_Deferred := 0;
               end if;
```

- [ ] **Step 4: Rebuild, finalize expected output, verify**

Run: `make build && ./bin/sdata tests/use_clears_deferred_batch.cmd`
Confirm MARKER absent, RUN reports 3 variables; write exact output into the `.out` file.
Run: `make check`
Expected: PASS, no regressions.

- [ ] **Step 5: Fix the stale comments**

In `src/sdata-interpreter.adb:99` change "reset to append only by NEW" to name `USE`, `REPEAT`, and `NEW`. The comment at line 453 already says "only NEW/USE/REPEAT replaces it" — now accurate; leave it.

- [ ] **Step 6: Commit**

```bash
git add src/sdata-interpreter.adb tests/use_clears_deferred_batch.cmd \
        tests/expected/use_clears_deferred_batch.out
git commit -m "fix: batch walker cancels deferred block on USE/REPEAT"
```

---

## PHASE B — sdata-core: static type inference + function metadata

### Task B1: `Static_Result_Kind` (name-suffix-driven expression kind inference)

**Files:**
- Modify: `../sdata-core/src/sdata_core-evaluator.ads` (declare public function + the `Static_Kind` type)
- Modify: `../sdata-core/src/sdata_core-evaluator.adb` (body)
- Test: `tests/evaluator_unit_test.adb` (add cases)

**Interfaces:**
- Produces:
  ```ada
  --  Statically infer the result kind of an expression WITHOUT evaluating it,
  --  using only name suffixes, literal kinds, and operator propagation.
  --  Returns Val_Missing to mean "cannot determine statically -- defer".
  function Static_Result_Kind (Expr : Expression_Access) return Value_Kind;
  ```
  (Reuses the convention that `Val_Missing` == "unknown/defer".)

- [ ] **Step 1: Write failing unit tests**

In `tests/evaluator_unit_test.adb`, add a helper and cases (uses `Parse_Expression`, already `with`n via `SData_Core.Evaluator`):
```ada
   procedure Check_Kind (Name, Text : String; Expected : Value_Kind) is
      E : Expression_Access := Parse_Expression (Text);
      K : constant Value_Kind := Static_Result_Kind (E);
   begin
      Free_Expression (E);
      if K = Expected then
         Put_Line ("PASS: " & Name); Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name & "  got=" & K'Image
                   & "  expected=" & Expected'Image);
         Failed := Failed + 1;
      end if;
   end Check_Kind;
```
Add invocations (in the test body):
```ada
   Check_Kind ("srk_str_var",   "NAME$",        Val_String);
   Check_Kind ("srk_int_var",   "COUNT%",       Val_Integer);
   Check_Kind ("srk_num_var",   "SALARY",       Val_Numeric);
   Check_Kind ("srk_str_lit",   """hello""",    Val_String);
   Check_Kind ("srk_num_lit",   "3.14",         Val_Numeric);
   Check_Kind ("srk_int_lit",   "42",           Val_Integer);
   Check_Kind ("srk_num_add",   "X + Y",        Val_Numeric);
   Check_Kind ("srk_str_concat","A$ + B$",      Val_String);
   Check_Kind ("srk_cmp",       "X > 3",        Val_Numeric);
   Check_Kind ("srk_str_fn",    "UPPER$(A$)",   Val_String);
   Check_Kind ("srk_num_fn",    "SQRT(X)",      Val_Numeric);
   Check_Kind ("srk_missing",   ".",            Val_Missing);   -- unknown/defer
   Check_Kind ("srk_mixed_add", "X + A$",       Val_Missing);   -- can't resolve -> defer
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ~/Develop/sdata-core && alr build && cd ~/Develop/sdata && make build && ./bin/evaluator_unit_test`
Expected: compile error (function not defined) — this is the failing state.

- [ ] **Step 3: Declare in the spec**

In `../sdata-core/src/sdata_core-evaluator.ads`, after `Get_Expected_Kind` (line 106):
```ada
   --  Statically infer the result kind of an expression WITHOUT evaluating it.
   --  Uses name suffixes (via Get_Expected_Kind), literal kinds, and operator
   --  propagation only.  Returns Val_Missing when the kind cannot be determined
   --  statically (mixed-kind operands, '.' literal, dynamic constructs) -- the
   --  caller must treat Val_Missing as "defer, do not reject".
   function Static_Result_Kind (Expr : Expression_Access) return Value_Kind;
```

- [ ] **Step 4: Implement the body**

In `../sdata-core/src/sdata_core-evaluator.adb`, add:
```ada
   function Static_Result_Kind (Expr : Expression_Access) return Value_Kind is
   begin
      if Expr = null then
         return Val_Missing;
      end if;
      case Expr.Kind is
         when Expr_String_Literal =>
            return Val_String;
         when Expr_Numeric_Literal =>
            return (if Expr.Is_Integer then Val_Integer else Val_Numeric);
         when Expr_Missing =>
            return Val_Missing;
         when Expr_Variable =>
            return Get_Expected_Kind (Expr.Var_Name (1 .. Expr.Var_Len));
         when Expr_Array_Access =>
            return Get_Expected_Kind (Expr.Arr_Name (1 .. Expr.Arr_Len));
         when Expr_Function_Call =>
            --  String-returning functions end in '$' by convention; suffix
            --  drives the kind exactly as it does for variables.
            return Get_Expected_Kind (Expr.Func_Name (1 .. Expr.Func_Len));
         when Expr_Unary_Op =>
            --  Neg and Not both yield numeric.
            return Val_Numeric;
         when Expr_Binary_Op =>
            declare
               L : constant Value_Kind := Static_Result_Kind (Expr.Left);
               R : constant Value_Kind := Static_Result_Kind (Expr.Right);
            begin
               case Expr.Op is
                  when Op_Eq | Op_Ne | Op_Lt | Op_Le | Op_Gt | Op_Ge
                     | Op_And | Op_Or | Op_Xor =>
                     return Val_Numeric;              -- boolean result (0/1)
                  when Op_Sub | Op_Mul | Op_Div | Op_Pow =>
                     return Val_Numeric;              -- numeric-only operators
                  when Op_Add =>
                     --  '+' concatenates two strings, else numeric.  Any
                     --  Val_Missing operand or a string/numeric mix is
                     --  indeterminate -> defer.
                     if L = Val_String and then R = Val_String then
                        return Val_String;
                     elsif (L in Val_Numeric | Val_Integer)
                        and then (R in Val_Numeric | Val_Integer)
                     then
                        return Val_Numeric;
                     else
                        return Val_Missing;
                     end if;
               end case;
            end;
      end case;
   end Static_Result_Kind;
```
> Verify against `doc/design.md` whether `+` actually concatenates strings; if sdata uses a different concat operator or none, simplify `Op_Add` to return `Val_Numeric` when both operands are numeric and `Val_Missing` otherwise. Do not guess — check the operator table before finalizing.

- [ ] **Step 5: Rebuild and verify tests pass**

Run: `cd ~/Develop/sdata-core && alr build && cd ~/Develop/sdata && make build && ./bin/evaluator_unit_test`
Expected: all `srk_*` cases PASS.

- [ ] **Step 6: Regenerate the API reference and commit (sdata-core)**

```bash
cd ~/Develop/sdata-core
scripts/gen-reference.sh
git add src/sdata_core-evaluator.ads src/sdata_core-evaluator.adb docs/api/reference.html
git commit -m "feat: add Static_Result_Kind for static expression-kind inference"
```
(The sdata-side test change is committed with Task C where it is exercised end-to-end, or separately: `git -C ~/Develop/sdata add tests/evaluator_unit_test.adb && git -C ~/Develop/sdata commit -m "test: Static_Result_Kind kind-inference cases"`.)

### Task B2: `Is_Known_Function` accessor

**Files:**
- Modify: `../sdata-core/src/sdata_core-evaluator.ads`
- Modify: `../sdata-core/src/sdata_core-evaluator.adb`
- Test: `tests/evaluator_unit_test.adb`

**Interfaces:**
- Produces: `function Is_Known_Function (Name : String) return Boolean;` — True iff `Name` (case-insensitive) is in the evaluator dispatch table.

- [ ] **Step 1: Write failing unit tests**

In `tests/evaluator_unit_test.adb`:
```ada
   Check ("ikf_known",   Is_Known_Function ("SQRT"),     True);
   Check ("ikf_str_fn",  Is_Known_Function ("UPPER$"),   True);
   Check ("ikf_unknown", Is_Known_Function ("FOOBAR"),   False);
   Check ("ikf_case",    Is_Known_Function ("sqrt"),     True);
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ~/Develop/sdata-core && alr build`
Expected: compile error (undefined) — failing state.

- [ ] **Step 3: Declare + implement**

Spec (`sdata_core-evaluator.ads`, near `Is_Aggregate:147`):
```ada
   --  True iff Name (case-insensitive) is a registered evaluator function.
   --  Used by consumers' static analyzers to reject unknown function calls.
   function Is_Known_Function (Name : String) return Boolean;
```
Body (`sdata_core-evaluator.adb`): the dispatch table is keyed by upper-cased names.
```ada
   function Is_Known_Function (Name : String) return Boolean is
   begin
      return Dispatch_Table.Contains (To_Upper (Name));
   end Is_Known_Function;
```
> Confirm the case convention used at registration (grep the family `Register` procedures for how keys are inserted; match it — if keys are stored upper-cased, upper-case the argument as shown; `To_Upper` is already used throughout the crate).

- [ ] **Step 4: Verify tests pass**

Run: `cd ~/Develop/sdata-core && alr build && cd ~/Develop/sdata && make build && ./bin/evaluator_unit_test`
Expected: `ikf_*` PASS.

- [ ] **Step 5: Commit (sdata-core)**

```bash
cd ~/Develop/sdata-core && scripts/gen-reference.sh
git add src/sdata_core-evaluator.ads src/sdata_core-evaluator.adb docs/api/reference.html
git commit -m "feat: add Is_Known_Function dispatch-table accessor"
```

### Task B3: Function arity metadata + `Function_Arity` accessor

**Files:**
- Modify: `../sdata-core/src/sdata_core-evaluator.ads` (arity record type + accessor + a `Register_Arity` used by families)
- Modify: `../sdata-core/src/sdata_core-evaluator.adb` (private `Arity_Table` + accessor body)
- Modify: each handler family that registers functions — `../sdata-core/src/sdata_core-evaluator-numeric_fns.adb`, `-string_fns.adb`, `-distrib_fns.adb`, `-misc_fns.adb`, `-nav_fns.adb`, `-aggregate_fns.adb` (register arity alongside each function)
- Test: `tests/evaluator_unit_test.adb`

**Interfaces:**
- Produces:
  ```ada
  type Arity_Spec is record
     Min_Args : Natural;
     Max_Args : Natural;   -- Natural'Last means "no upper bound" (variadic)
  end record;
  --  Returns the arity of a known function; raises SData_Core.Script_Error if
  --  Name is not a known function (call Is_Known_Function first).
  function Function_Arity (Name : String) return Arity_Spec;
  ```
- Consumes: `Is_Known_Function` (B2).

- [ ] **Step 1: Write failing unit tests**

```ada
   declare
      A : Arity_Spec;
   begin
      A := Function_Arity ("SQRT");
      Check ("arity_sqrt_min", A.Min_Args = 1, True);
      Check ("arity_sqrt_max", A.Max_Args = 1, True);
      A := Function_Arity ("SUBSTR$");   -- 2 or 3 args (verify against design)
      Check ("arity_substr_min", A.Min_Args = 2, True);
   end;
```

- [ ] **Step 2: Run to verify failure**

Run: `cd ~/Develop/sdata-core && alr build`
Expected: compile error — failing state.

- [ ] **Step 3: Add the type, table, registration, and accessor**

Spec (`sdata_core-evaluator.ads`):
```ada
   type Arity_Spec is record
      Min_Args : Natural := 0;
      Max_Args : Natural := Natural'Last;
   end record;

   function Function_Arity (Name : String) return Arity_Spec;

   --  Register a function's arity.  Called by each handler family's private
   --  Register procedure alongside the Dispatch_Table insert.
   procedure Register_Arity (Name : String; Min_Args, Max_Args : Natural);
```
Body/private (`sdata_core-evaluator.adb`/`.ads` private part) — mirror `Aggregate_Meta_Maps` (`sdata_core-evaluator.ads:188-193`):
```ada
   package Arity_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type => String, Element_Type => Arity_Spec,
      Hash => Ada.Strings.Hash, Equivalent_Keys => "=");
   Arity_Table : Arity_Maps.Map;
```
```ada
   procedure Register_Arity (Name : String; Min_Args, Max_Args : Natural) is
   begin
      Arity_Table.Include (To_Upper (Name), (Min_Args, Max_Args));
   end Register_Arity;

   function Function_Arity (Name : String) return Arity_Spec is
      C : constant Arity_Maps.Cursor := Arity_Table.Find (To_Upper (Name));
   begin
      if Arity_Maps.Has_Element (C) then
         return Arity_Maps.Element (C);
      else
         raise SData_Core.Script_Error
           with "no arity registered for function '" & Name & "'";
      end if;
   end Function_Arity;
```

- [ ] **Step 4: Register arity in every handler family**

In each `*_fns.adb` family's `Register` procedure, next to each `Dispatch_Table.Include (Name, Handler)` add a `Register_Arity (Name, Min, Max)`. Determine each function's arity from its handler's `Has_Args` checks and from `doc/design.md` / `man/man1/sdata.1` FUNCTIONS section (line 379). For genuinely variadic functions use `Max => Natural'Last`. For identifier-ref functions (LAG/NEXT/OBS, `Is_Identifier_Ref_Function`) register their true arity.
> This is the largest mechanical step. Do one family per commit if helpful. Cross-check counts against the FUNCTIONS table in the man page so none are missed.

- [ ] **Step 5: Verify tests pass**

Run: `cd ~/Develop/sdata-core && alr build && cd ~/Develop/sdata && make build && ./bin/evaluator_unit_test`
Expected: `arity_*` PASS. Then `make check` (no behavior change yet, so all green).

- [ ] **Step 6: Commit (sdata-core)**

```bash
cd ~/Develop/sdata-core && scripts/gen-reference.sh
git add src/sdata_core-evaluator.ads src/sdata_core-evaluator.adb src/sdata_core-evaluator-*_fns.adb docs/api/reference.html
git commit -m "feat: register per-function arity metadata + Function_Arity accessor"
```

---

## PHASE C — sdata: the semantic analyzer

### Task C1: Analyzer skeleton + static environment

**Files:**
- Create: `src/sdata-interpreter-analyze_deferred.adb` (a subunit of `SData.Interpreter`)
- Modify: `src/sdata-interpreter.adb` (declare the subunit: `procedure Analyze_Deferred (Start, Boundary : Statement_Access); ... is separate;`)
- Test: driven via `.cmd` tests in later steps (analyzer is exercised end-to-end).

**Interfaces:**
- Produces: `procedure Analyze_Deferred (Start, Boundary : Statement_Access);` — walks the statement chain `[Start, Boundary)`, builds a set of names introduced by those statements, then re-walks and runs the four checks on each statement's expressions/targets. Raises `SData_Core.Script_Error` on the first provable violation. No-op when `Start = Boundary` or `Start = null`.
- Consumes: `SData_Core.Evaluator.Static_Result_Kind` / `Is_Known_Function` / `Function_Arity` / `Get_Expected_Kind`; `SData_Core.Table.Has_Column`/`Column_Count`/`Column_Name`; `SData_Core.Variables.Get_Type`/`Has_Array`/`Get_Session_Names`.

- [ ] **Step 1: Declare the subunit**

In `src/sdata-interpreter.adb` near the other subunit declarations (around line 130-152):
```ada
   procedure Analyze_Deferred (Start, Boundary : Statement_Access);
```
and near the other `is separate;` lines (around 759-894):
```ada
   procedure Analyze_Deferred (Start, Boundary : Statement_Access) is separate;
```

- [ ] **Step 2: Implement the environment + traversal skeleton (no checks yet)**

Create `src/sdata-interpreter-analyze_deferred.adb`:
```ada
separate (SData.Interpreter)
procedure Analyze_Deferred (Start, Boundary : Statement_Access) is

   package Name_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type => String, Hash => Ada.Strings.Hash, Equivalent_Elements => "=");
   Introduced : Name_Sets.Set;   -- names created by LET/SET/DIM/ARRAY/FOR in this block

   function U (S : String) return String renames To_Upper;

   --  A name is "defined" if it is a table column, a session variable, an
   --  array, or introduced anywhere in this deferred block (whole-block scope,
   --  so forward references are legal).
   function Is_Defined (Name : String) return Boolean is
      Up : constant String := U (Name);
   begin
      return SData_Core.Table.Has_Column (Up)
        or else SData_Core.Variables.Has_Array (Up)
        or else SData_Core.Variables.Get_Type (Up) /= Val_Missing
        or else Introduced.Contains (Up);
   end Is_Defined;

   procedure Note_Introduced (Stmt : Statement_Access) is
   begin
      case Stmt.Kind is
         when Stmt_LET | Stmt_SET =>
            Introduced.Include (U (Stmt.Var_Name (1 .. Stmt.Var_Len)));
         when Stmt_FOR =>
            Introduced.Include (U (Stmt.For_Var (1 .. Stmt.For_Var_Len)));
         when Stmt_DIM | Stmt_ARRAY =>
            if Stmt.Arr_Name_Len > 0 then
               Introduced.Include (U (Stmt.Arr_Name (1 .. Stmt.Arr_Name_Len)));
            end if;
         when others => null;
      end case;
   end Note_Introduced;

   Cur : Statement_Access;
begin
   if Start = null or else Start = Boundary then
      return;
   end if;

   --  Pass 1: collect introduced names (whole-block scope).
   Cur := Start;
   while Cur /= null and then Cur /= Boundary loop
      Note_Introduced (Cur);
      Cur := Cur.Next;
   end loop;

   --  Pass 2: run checks (added in Tasks C2-C5).
   Cur := Start;
   while Cur /= null and then Cur /= Boundary loop
      --  Check hooks inserted here by later tasks.
      Cur := Cur.Next;
   end loop;
end Analyze_Deferred;
```
Add the needed `with`/`use`: `Ada.Containers.Indefinite_Hashed_Sets`, `Ada.Strings.Hash`, `SData_Core.Table`, `SData_Core.Variables`, `SData_Core.Evaluator`, `SData_Core.Values`. `To_Upper` is already available in the interpreter closure (used pervasively); if not visible in the subunit, add the same `with`/`use` the parent uses.
> `Note_Introduced` must also recurse into compound statements (IF/FOR/WHILE/SELECT bodies) to collect names introduced by nested LET/SET. Add recursion over `Then_Branch`/`Else_Branch`/`For_Body`/`While_Body`/`Repeat_Body`/`Branches`/`Otherwise_Part` (all `Statement_Access` chains) — mirror the traversal in `Free_Program`. Keep it in this task so the environment is complete before any check runs.

- [ ] **Step 3: Build and verify no behavior change**

Run: `make build && make check`
Expected: PASS (skeleton is a no-op; not yet wired into `Execute`).

- [ ] **Step 4: Commit**

```bash
git add src/sdata-interpreter.adb src/sdata-interpreter-analyze_deferred.adb
git commit -m "feat: deferred-statement analyzer skeleton + static name environment"
```

### Task C2: Expression walk + unknown-function and arity checks

**Files:**
- Modify: `src/sdata-interpreter-analyze_deferred.adb`
- Test: `tests/check_unknown_fn.cmd` + `.out`, `tests/check_arity.cmd` + `.out`

**Interfaces:**
- Produces: an internal `procedure Check_Expr (E : Expression_Access)` that recursively validates an expression tree, and per-statement dispatch that calls it on every expression field.

- [ ] **Step 1: Write failing integration tests**

`tests/check_unknown_fn.cmd`:
```
USE MOCK
LET X = FOOBAR(SALARY)
RUN
```
`tests/expected/check_unknown_fn.out`: an `Error:` line naming `FOOBAR` as an unknown function, and NO "RUN complete" line (rejected before the data step). Add `tests/check_unknown_fn.exitcode` containing `1` if the harness checks exit codes (see `Makefile:136-137`).

`tests/check_arity.cmd`:
```
USE MOCK
LET X = SQRT(SALARY, 2)
RUN
```
`tests/expected/check_arity.out`: an `Error:` line about wrong argument count for `SQRT`.

- [ ] **Step 2: Verify current behavior**

Run: `make build && ./bin/sdata tests/check_unknown_fn.cmd`
Expected BEFORE: `FOOBAR` silently yields missing; RUN completes (no error). Demonstrates the gap.

- [ ] **Step 3: Implement `Check_Expr` with unknown-fn + arity**

In `analyze_deferred.adb`, add before the `begin` of `Analyze_Deferred`:
```ada
   function Arg_Count (L : Expression_List) return Natural is
      N : Natural := 0; C : Expression_List := L;
   begin
      while C /= null loop N := N + 1; C := C.Next; end loop;
      return N;
   end Arg_Count;

   procedure Check_Expr (E : Expression_Access) is
   begin
      if E = null then return; end if;
      case E.Kind is
         when Expr_Binary_Op =>
            Check_Expr (E.Left); Check_Expr (E.Right);
         when Expr_Unary_Op =>
            Check_Expr (E.Operand);
         when Expr_Array_Access =>
            declare C : Expression_List := E.Arr_Idx; begin
               while C /= null loop Check_Expr (C.Expr);
                  if C.Is_Range then Check_Expr (C.Expr_End); end if;
                  C := C.Next; end loop;
            end;
         when Expr_Function_Call =>
            declare
               FN : constant String := E.Func_Name (1 .. E.Func_Len);
            begin
               --  A name parsed as a function call but registered as an array
               --  is really array access (batch parses X(1) as a call because
               --  DIM has not run yet).  Not an unknown function.
               if not SData_Core.Variables.Has_Array (U (FN))
                 and then not Introduced.Contains (U (FN))
               then
                  if not Is_Known_Function (FN) then
                     raise SData_Core.Script_Error with
                       "unknown function '" & FN & "'";
                  end if;
                  declare
                     A : constant Arity_Spec := Function_Arity (FN);
                     N : constant Natural := Arg_Count (E.Arguments);
                  begin
                     if N < A.Min_Args or else N > A.Max_Args then
                        raise SData_Core.Script_Error with
                          "function '" & FN & "' expects "
                          & (if A.Min_Args = A.Max_Args
                             then A.Min_Args'Image & " argument(s)"
                             else "between" & A.Min_Args'Image & " and"
                                  & A.Max_Args'Image & " arguments")
                          & ", got" & N'Image;
                     end if;
                  end;
               end if;
               --  Recurse into arguments regardless.
               declare C : Expression_List := E.Arguments; begin
                  while C /= null loop Check_Expr (C.Expr);
                     if C.Is_Range then Check_Expr (C.Expr_End); end if;
                     C := C.Next; end loop;
               end;
            end;
         when others => null;   -- literals, variables, missing: nothing here
      end case;
   end Check_Expr;
```
Add a per-statement dispatch used in Pass 2 (call `Check_Expr` on every expression field of the statement — `Expr`, `Condition`, `Print_Args`, `For_Start/End/Step`, `While_Cond`, `Selector`/branch conditions, `Seed_Expr`, `Until_Cond`, and array-subscript expressions), and recurse into nested bodies. Factor this into `procedure Check_Statement (S : Statement_Access)` and call it from Pass 2:
```ada
   Cur := Start;
   while Cur /= null and then Cur /= Boundary loop
      Check_Statement (Cur);
      Cur := Cur.Next;
   end loop;
```
> `Check_Statement` must mirror the field structure in `sdata-ast.ads:200-315`. Handle every kind that carries an `Expression_Access`/`Expression_List`. For compound kinds, recurse into their `Statement_Access` bodies.

- [ ] **Step 4: Wire the analyzer into `Execute` (pre-RUN, both modes)**

In `src/sdata-interpreter.adb`, in `Execute`, immediately before `Run_One_Step (Step_Start, Current);` (line 1480):
```ada
            Analyze_Deferred (Step_Start, Current);
```
This runs for interactive (via `Run_Active_Program`'s synthetic cap) and batch alike. A raised `Script_Error` propagates to the REPL handler (`sdata_main.adb:190`) or batch top level (`:565`) and prints `Error: ...` before any record is processed.

- [ ] **Step 5: Rebuild, finalize expected outputs, verify**

Run: `make build`, then run each new `.cmd` and confirm the error fires before RUN; write exact `Error:` text into the `.out` files.
Run: `make check`
Expected: new tests PASS; investigate any pre-existing test that now errors — if a test legitimately used an unknown "function" that is actually an array/typo, fix the test or confirm the array path. Document any intentional test change in the commit message.

- [ ] **Step 6: Commit**

```bash
git add src/sdata-interpreter.adb src/sdata-interpreter-analyze_deferred.adb \
        tests/check_unknown_fn.cmd tests/expected/check_unknown_fn.out \
        tests/check_arity.cmd tests/expected/check_arity.out
git commit -m "feat: analyzer rejects unknown functions and arity errors pre-RUN"
```

### Task C3: Assignment type-mismatch check

**Files:**
- Modify: `src/sdata-interpreter-analyze_deferred.adb`
- Test: `tests/check_type_mismatch.cmd` + `.out`, `tests/check_type_defer.cmd` + `.out`

**Interfaces:**
- Consumes: `Static_Result_Kind`, `Get_Expected_Kind`.

- [ ] **Step 1: Write failing + defer tests**

`tests/check_type_mismatch.cmd` (the motivating example):
```
USE MOCK
LET FOO = NAME$
RUN
```
`tests/expected/check_type_mismatch.out`: `Error:` naming a type mismatch assigning a string to numeric `FOO`, no RUN completion.

`tests/check_type_defer.cmd` (must NOT error — RHS kind indeterminate):
```
USE MOCK
LET FOO = SALARY + .
RUN
```
`tests/expected/check_type_defer.out`: RUN completes normally (the `.` makes the RHS kind `Val_Missing` → defer). This guards against false positives.

- [ ] **Step 2: Verify current behavior**

Run: `make build && ./bin/sdata tests/check_type_mismatch.cmd`
Expected BEFORE: error only appears per-record after RUN starts (current deferred behavior).

- [ ] **Step 3: Implement the check in `Check_Statement`**

In the `Stmt_LET | Stmt_SET` handling of `Check_Statement`, after the `Check_Expr (S.Expr)` recursion, add (scalar assignment only — array-element type rules differ and stay at runtime):
```ada
      if (S.Kind = Stmt_LET or else S.Kind = Stmt_SET)
         and then not S.Is_Array and then S.Expr /= null
      then
         declare
            Target   : constant String := S.Var_Name (1 .. S.Var_Len);
            Expected : constant Value_Kind := Get_Expected_Kind (Target);
            RHS      : constant Value_Kind := Static_Result_Kind (S.Expr);
         begin
            --  Defer whenever the RHS kind is indeterminate (soundness rule).
            --  Integer is assignable to a numeric target (matches Coerce).
            if RHS /= Val_Missing
               and then Expected /= RHS
               and then not (Expected = Val_Numeric and then RHS = Val_Integer)
            then
               raise SData_Core.Script_Error with
                 "Type mismatch for variable """ & Target
                 & """: cannot assign " & Kind_Name (RHS)
                 & " to " & Kind_Name (Expected) & " variable";
            end if;
         end;
      end if;
```
Add the local `Kind_Name` helper (reuse the wording from `parser.adb:2169-2173`):
```ada
   function Kind_Name (K : Value_Kind) return String is
     (case K is when Val_String => "string", when Val_Integer => "integer",
                when others => "numeric");
```

- [ ] **Step 4: Rebuild, finalize outputs, verify both tests**

Run: `make build`; run both `.cmd` files. Confirm mismatch errors pre-RUN and the defer case completes RUN. Write exact outputs.
Run: `make check`
Expected: PASS. If any existing test intentionally assigned across kinds relying on deferral, reconcile it.

- [ ] **Step 5: Commit**

```bash
git add src/sdata-interpreter-analyze_deferred.adb \
        tests/check_type_mismatch.cmd tests/expected/check_type_mismatch.out \
        tests/check_type_defer.cmd tests/expected/check_type_defer.out
git commit -m "feat: analyzer rejects provable assignment type mismatches pre-RUN"
```

### Task C4: Undefined-variable check

**Files:**
- Modify: `src/sdata-interpreter-analyze_deferred.adb`
- Test: `tests/check_undefined_var.cmd` + `.out`, `tests/check_forward_ref.cmd` + `.out`

**Interfaces:**
- Consumes: `Is_Defined` (Task C1).

- [ ] **Step 1: Write failing + forward-reference tests**

`tests/check_undefined_var.cmd`:
```
USE MOCK
LET X = NOSUCHVAR + 1
RUN
```
`tests/expected/check_undefined_var.out`: `Error:` naming `NOSUCHVAR` as undefined, no RUN completion.

`tests/check_forward_ref.cmd` (must NOT error — `B` defined later in the block):
```
USE MOCK
LET A = B + 1
LET B = 2
RUN
```
`tests/expected/check_forward_ref.out`: RUN completes (whole-block scope: `B` is introduced in the block).

- [ ] **Step 2: Verify current behavior**

Run: `make build && ./bin/sdata tests/check_undefined_var.cmd`
Expected BEFORE: `NOSUCHVAR` silently missing; RUN completes.

- [ ] **Step 3: Add the undefined-var check to `Check_Expr`**

In `Check_Expr`, extend the `Expr_Variable` arm (currently `others => null`; split it out):
```ada
         when Expr_Variable =>
            if not Is_Defined (E.Var_Name (1 .. E.Var_Len)) then
               raise SData_Core.Script_Error with
                 "undefined variable """ & E.Var_Name (1 .. E.Var_Len) & """";
            end if;
```
> Reserved pseudo-identifiers: if any bare identifier (no parentheses) is a legitimate special name — e.g. navigation/state names usable without `()` — it would parse as `Expr_Variable` and be wrongly flagged. Before finalizing, grep the evaluator/design for any bare special identifiers (RECNO/BOF/EOF/ERR/ERL/N and the nav family are normally *functions* called with `()`, hence `Expr_Function_Call`, and are unaffected). If any bare specials exist, add them to `Is_Defined` as an allow-list. Add a test for each you find.

- [ ] **Step 4: Rebuild, finalize outputs, verify both tests**

Run: `make build`; run both `.cmd` files; confirm the undefined case errors pre-RUN and the forward-reference case completes RUN. Write exact outputs.
Run: `make check`
Expected: PASS. This is the highest false-positive-risk check — scrutinize every failing pre-existing test; a legitimate failure means a missing entry in `Is_Defined`, not a bad test.

- [ ] **Step 5: Commit**

```bash
git add src/sdata-interpreter-analyze_deferred.adb \
        tests/check_undefined_var.cmd tests/expected/check_undefined_var.out \
        tests/check_forward_ref.cmd tests/expected/check_forward_ref.out
git commit -m "feat: analyzer rejects undefined variable references pre-RUN"
```

### Task C5: Interactive entry-time fast feedback

**Files:**
- Modify: `src/sdata-interpreter.adb` (`Add_To_Active_Program:362`)
- Modify: `src/sdata-interpreter-analyze_deferred.adb` (expose a single-statement entry check)
- Test: `tests/check_entry_interactive.cmd` + `.out` (a script that relies on the error firing at entry, before RUN)

**Interfaces:**
- Produces: `procedure Analyze_One (Stmt : Statement_Access);` — runs the subset of checks that are sound at entry time (type-mismatch, unknown-function, arity) on a single statement against the CURRENT schema; does NOT run the undefined-variable check (forward references are only resolvable at the pre-RUN whole-block pass). Raises `SData_Core.Script_Error` on violation.

- [ ] **Step 1: Write the test**

Because the harness runs scripts (not a live REPL), assert entry-time rejection by ordering: put a `PRINT` immediate after the bad `LET` and confirm the error precedes any RUN. `tests/check_entry_interactive.cmd`:
```
USE MOCK
LET FOO = NAME$
NAMES
RUN
```
Expected: the type-mismatch error appears and `NAMES`/`RUN` still run in batch (batch catches at pre-RUN, not entry — so this test mainly confirms no double-error and consistent messaging). For genuine entry-behavior, add a note that interactive REPL rejects the `LET` line immediately; this is validated manually (see Step 4).
> Entry-time behavior is REPL-specific and not directly expressible in the batch `.cmd` harness. Keep the automated test focused on "no regression / single clear error," and validate the true entry-time rejection manually in an interactive session.

- [ ] **Step 2: Implement `Analyze_One`**

Refactor `analyze_deferred.adb` so the per-statement checks are reusable. Add a public-to-parent entry:
```ada
separate (SData.Interpreter)
procedure Analyze_One (Stmt : Statement_Access) is
begin
   --  Entry-time subset: no undefined-var (forward refs), so use an empty
   --  Introduced set and skip Is_Defined-based rejection.  Reuse Check_Expr
   --  with undefined-var disabled and the type-mismatch + fn checks enabled.
   ...
end Analyze_One;
```
Simplest structure: parameterize the shared checker with a boolean `Check_Undefined : Boolean` and have `Analyze_Deferred` pass `True`, `Analyze_One` pass `False`. Declare both subunits in `sdata-interpreter.adb`.

- [ ] **Step 3: Call `Analyze_One` at entry**

In `Add_To_Active_Program` (`sdata-interpreter.adb:362`), before appending the statement:
```ada
   Analyze_One (Stmt);   -- entry-time fast feedback (interactive)
```
A raised error propagates to the REPL handler and the statement is never queued — matching the motivating example.

- [ ] **Step 4: Verify**

Run: `make build && make check` (batch tests unaffected / consistent).
Manual: `./bin/sdata` then type `USE MOCK` / `LET FOO = NAME$` and confirm the error appears immediately at the `LET` line, before any `RUN`. Confirm `LET FOO = NOSUCHVAR` is NOT rejected at entry (deferred to RUN) — proving forward-ref safety.

- [ ] **Step 5: Commit**

```bash
git add src/sdata-interpreter.adb src/sdata-interpreter-analyze_deferred.adb \
        tests/check_entry_interactive.cmd tests/expected/check_entry_interactive.out
git commit -m "feat: interactive entry-time checking of deferred statements"
```

---

## PHASE D — Documentation & user surface

### Task D1: Update design doc, man page, HELP

**Files:**
- Modify: `doc/design.md` (USE clause + REPEAT symmetry + new entry-time-checking subsection)
- Modify: `man/man1/sdata.1`
- Modify: `src/sdata-help.adb` (note on entry-time checking under a relevant topic)
- Modify: `tests/expected/help_all.out` (regen if HELP text changed)

- [ ] **Step 1: design.md**

In the `USE` command reference row (line 960) confirm the existing "Any DROP, KEEP, LET, or REPEAT statements are canceled when a new dataset is read in" clause; add matching wording to the `REPEAT` row. Add a new subsection (near the LET/SET or execution-model section) specifying: deferred statements are validated at entry (interactive) / before the data step (batch) for (1) assignment type mismatches, (2) unknown functions, (3) function arity, (4) undefined variables; all are hard errors; checks are sound-but-incomplete (indeterminate cases defer to runtime).

- [ ] **Step 2: man page**

In `man/man1/sdata.1`, document the four checks and when they fire (LANGUAGE OVERVIEW around line 138 and/or the RUN/LET descriptions).

- [ ] **Step 3: HELP + snapshot**

Add a one-line note to the most relevant HELP topic(s) in `src/sdata-help.adb` (e.g. under `LET`/`RUN`) about entry-time validation. Rebuild and regenerate the snapshot:
```bash
make build
./bin/sdata tests/help_all.cmd > tests/expected/help_all.out   # confirm this matches the harness's invocation first
```
Verify by diffing that only the intended lines changed. Re-run `make check`.

- [ ] **Step 4: Commit**

```bash
git add doc/design.md man/man1/sdata.1 src/sdata-help.adb tests/expected/help_all.out
git commit -m "docs: document entry-time semantic checking (design, man, HELP)"
```

---

## PHASE E — Full cross-crate validation gate

### Task E1: Green all three crates

- [ ] **Step 1: sdata-core builds**

Run: `cd ~/Develop/sdata-core && alr build`
Expected: clean build.

- [ ] **Step 2: sdata full suite**

Run: `cd ~/Develop/sdata && make check`
Expected: all unit binaries + all integration tests (now ≥299 + the new tests) PASS.

- [ ] **Step 3: data-vandal suite (sdata-core changed)**

Run: `cd ~/Develop/data-vandal && make check`
Expected: PASS (data-vandal does not use sdata's deferred statements, but it links sdata-core; confirm `Static_Result_Kind`/`Is_Known_Function`/`Function_Arity`/`Register_Arity` additions did not break its build or tests).

- [ ] **Step 4: Version bumps (if releasing)**

If cutting releases: bump `sdata-core` in `../sdata-core/alire.toml` (additive → minor), update the `sdata_core = "^X.Y.Z"` floor in `sdata/alire.toml` and `data-vandal/alire.toml` only if a new symbol floor is needed, and run `scripts/bump-version.sh` for sdata. Tag both per their conventions. (Coordinate per CLAUDE.md; do not bump sdata and sdata-core versions in lockstep.)

---

## Self-Review

**Spec coverage:**
- Part 1 (USE/REPEAT clear queue) → Tasks A1 (interactive + narrow clear) + A2 (batch walker) + comment fix.
- Static type environment → Task C1.
- Check 1 type mismatch → C3 (+ B1 `Static_Result_Kind`).
- Check 2 unknown function → C2 (+ B2 `Is_Known_Function`); array-vs-function disambiguation handled in `Check_Expr`.
- Check 3 arity → C2 (+ B3 arity table).
- Check 4 undefined variable → C4; whole-block/forward-ref scope in C1.
- Interactive entry vs batch pre-RUN split → C5 (entry) + C2 Step 4 (pre-RUN hook covers both modes).
- Sound-not-complete deferral → enforced in B1 (`Val_Missing` return) and consumed in C3.
- Docs (design/man/HELP) → D1. Cross-crate gate → E1.

**Placeholder scan:** No "TBD"/"handle edge cases" left as work items. Three explicit *verify-before-finalizing* notes remain (B1 `+`-concat operator semantics, B3 per-function arities, C4 bare special identifiers) — these are correctness confirmations against the language spec, each with a concrete method and a test, not deferred design.

**Type consistency:** `Static_Result_Kind`/`Is_Known_Function`/`Function_Arity`/`Arity_Spec`/`Register_Arity` (sdata-core) and `Analyze_Deferred`/`Analyze_One`/`Clear_Deferred_Program` (sdata) are used with identical signatures across tasks. `Val_Missing`-as-"defer" is consistent between B1 and C3.

**Known risk carried into implementation:** Tasks C2/C4 may surface pre-existing tests that relied on silent-missing for unknown functions/names. Each such failure is triaged in the task's verify step: fix the test if it was a latent typo, or extend `Is_Defined`/the array path if it was legitimate. Document any test change in the commit.
