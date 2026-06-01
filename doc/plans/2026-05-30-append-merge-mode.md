# APPEND Merge Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the design in `doc/specs/2026-05-30-append-merge-mode-design.md` — add `/APPEND` as a fifth `USE` merge mode that vertically concatenates input rows in spec order with column-union semantics.

**Architecture:** Reuse the existing merge infrastructure. One new lexer token (`Token_APPEND`), one new AST enum value (`MM_Append`), one new combiner (`SData.Merge.Combine_Append`), parser dispatch update, executor mode-switch arm. No sdata-core changes.

**Tech Stack:** Ada 2012, Alire, existing sdata test framework. Builds on the merge + multi-output feature in PR #10.

---

## Pre-flight

- [ ] **Step 0.1: Verify branch state**

  ```bash
  cd /home/jries/Develop/sdata && git status && git branch --show-current
  ```

  Expected: clean tree on the chosen feature branch (`feat/append-merge-mode` or whatever the implementer chooses).

- [ ] **Step 0.2: Run the baseline test suite**

  ```bash
  cd /home/jries/Develop/sdata && make check
  cd /home/jries/Develop/data-vandal && make check
  cd /home/jries/Develop/sdata-core && alr build
  ```

  Record baseline counts.

---

## Task 1: Lexer — add Token_APPEND

**Files:**
- Modify: `/home/jries/Develop/sdata/src/lexer/sdata-lexer.ads`
- Modify: `/home/jries/Develop/sdata/src/lexer/sdata-lexer.adb`

- [ ] **Step 1: Add token kind to enum**

  In `sdata-lexer.ads`, add `Token_APPEND` alongside the other merge-mode tokens (`Token_INTERLEAVE`, `Token_JOIN`):

  ```ada
        Token_APPEND,
  ```

- [ ] **Step 2: Add keyword recognition**

  In `sdata-lexer.adb`, find the keyword-recognition chain (Task 5 added `Token_AS / IN / INTERLEAVE / JOIN` here). Add:

  ```ada
        elsif Upper = "APPEND" then T.Kind := Token_APPEND;
  ```

  Place alphabetically alongside the others.

- [ ] **Step 3: Build and run baseline tests**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: all baseline tests pass. The new token is unused yet.

- [ ] **Step 4: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/lexer/sdata-lexer.ads src/lexer/sdata-lexer.adb
  git commit -m "$(cat <<'EOF'
  feat(lexer): add Token_APPEND for /APPEND merge mode

  Reserved keyword. Recognised unconditionally; the parser will treat
  it contextually as a /APPEND whole-statement slash-option on USE.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 2: AST — add MM_Append to Merge_Mode

**Files:**
- Modify: `/home/jries/Develop/sdata/src/ast/sdata-ast.ads`

- [ ] **Step 1: Extend the enum**

  Find the `Merge_Mode` type declaration. Add `MM_Append`:

  ```ada
     type Merge_Mode is (MM_Single, MM_Positional, MM_Match,
                         MM_Interleave, MM_Join, MM_Append);
  ```

- [ ] **Step 2: Build**

  ```bash
  cd /home/jries/Develop/sdata && make build
  ```

  Expected: build succeeds. Any `case Mode is` that doesn't yet handle `MM_Append` produces a coverage warning — that's expected; subsequent tasks add the arms.

- [ ] **Step 3: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/ast/sdata-ast.ads
  git commit -m "$(cat <<'EOF'
  feat(ast): add MM_Append to Merge_Mode enum

  Used by upcoming parser dispatch for the /APPEND slash-option on USE.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 3: Add Combine_Append to SData.Merge

**Files:**
- Modify: `/home/jries/Develop/sdata/src/sdata-merge.ads`
- Modify: `/home/jries/Develop/sdata/src/sdata-merge.adb`
- Modify: `/home/jries/Develop/sdata/tests/sdata_unit_test.adb`

- [ ] **Step 1: Add declaration to spec**

  In `sdata-merge.ads`, alongside the other Combine_* functions, add:

  ```ada
     --  Vertical concatenation: emit every row of input 1 in order,
     --  then every row of input 2, and so on. Column-set = union of
     --  input columns. Each row uses values from its originating
     --  input; columns from other inputs are missing. Provenance:
     --  exactly one bit set per row (the contributing input).
     function Combine_Append
       (Inputs    : Table_Vectors.Vector;
        Warnings  : in out Warning_Vectors.Vector;
        Provenance : in out Provenance_Vectors.Vector)
        return SData.Transient_Table.Table;
  ```

  Note: no `By_Vars` parameter — append doesn't use BY.

- [ ] **Step 2: Implement in body**

  In `sdata-merge.adb`, alongside the other Combine_* bodies:

  ```ada
  function Combine_Append
    (Inputs    : Table_Vectors.Vector;
     Warnings  : in out Warning_Vectors.Vector;
     Provenance : in out Provenance_Vectors.Vector)
     return SData.Transient_Table.Table
  is
     Result   : SData.Transient_Table.Table;
     Sources  : Source_Vectors.Vector;
     N_Inputs : constant Natural := Natural (Inputs.Length);
  begin
     Build_Schema (Result, Sources, Inputs, Warnings);
     for I in 1 .. N_Inputs loop
        declare
           T : constant Table_Access := Inputs (I);
           N : constant Natural :=
                  SData.Transient_Table.Row_Count (T.all);
        begin
           for R in 1 .. N loop
              Result.Add_Row;
              declare
                 R_Out : constant Positive :=
                    SData.Transient_Table.Row_Count (Result);
              begin
                 for C in 1 .. Natural (Sources.Length) loop
                    declare
                       Col_Out : constant String :=
                          SData.Transient_Table.Column_Name (Result, C);
                       V : SData_Core.Values.Value;
                    begin
                       if SData.Transient_Table.Has_Column
                            (T.all, Col_Out)
                       then
                          V := T.Get_Value (R, Col_Out);
                       else
                          V := (Kind => SData_Core.Values.Val_Missing);
                       end if;
                       Result.Set_Value (R_Out, Col_Out, V);
                    end;
                 end loop;
              end;
              --  Provenance: exactly one bit set (input I)
              declare
                 Mask : Row_Provenance;
              begin
                 for J in 1 .. N_Inputs loop
                    Mask.Contributors.Append (J = I);
                 end loop;
                 Provenance.Append (Mask);
              end;
           end loop;
        end;
     end loop;
     return Result;
  end Combine_Append;
  ```

- [ ] **Step 3: Add unit tests**

  In `tests/sdata_unit_test.adb`, add a Combine_Append section (label tests CA-01..CA-05) following the pattern of CP/CM/CI/CJ:

  - CA-01: two inputs, disjoint columns (A: ID,X; B: ID,Y), 2+2=4 output rows, missing values in non-contributing columns
  - CA-02: two inputs with overlapping column name, last-wins + collision warning
  - CA-03: three inputs, 2+2+2=6 output rows
  - CA-04: mismatched row counts (A: 3 rows; B: 1 row), 4 output rows total
  - CA-05: provenance — for each row, exactly one bit set, matching the originating input index

  Mirror the structure of CI-01 (Combine_Interleave's first test) — the setup is similar.

- [ ] **Step 4: Build and test**

  ```bash
  cd /home/jries/Develop/sdata && make check
  cd /home/jries/Develop/data-vandal && make check
  ```

  Expected: all baseline tests pass + 5 new CA-* unit tests.

- [ ] **Step 5: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/sdata-merge.ads src/sdata-merge.adb tests/sdata_unit_test.adb
  git commit -m "$(cat <<'EOF'
  feat(merge): implement Combine_Append (vertical concatenation)

  Stack rows from each input in spec order. Column-set = union of input
  columns; each row carries values from its originating input only,
  other inputs' columns are missing. Provenance: exactly one bit set
  per row. No BY parameter; append preserves input order.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 4: Parser — accept /APPEND and validate mutex

**Files:**
- Modify: `/home/jries/Develop/sdata/src/parser/sdata-parser.adb`

- [ ] **Step 1: Add Saw_APPEND tracking and slash-option case**

  In `Parse_USE_Stmt`, find the slash-option loop (alongside `Saw_BY`, `Saw_INTERLEAVE`, `Saw_JOIN`). Add:

  ```ada
     Saw_APPEND : Boolean := False;
  ```

  In the slash-option case-of-token branch, add:

  ```ada
        when Token_APPEND =>
           Saw_APPEND := True;
  ```

- [ ] **Step 2: Add mutex validation**

  In the post-loop validation block (where `/INTERLEAVE + /JOIN`, `/INTERLEAVE without /BY` etc. are checked), add:

  ```ada
     if Saw_APPEND
        and then (Saw_BY or Saw_INTERLEAVE or Saw_JOIN)
     then
        Put_Line_Error
          ("Error: /APPEND cannot be combined with /BY, "
             & "/INTERLEAVE, or /JOIN");
        Had_Error := True;
     end if;
     if Saw_APPEND and Natural (Specs.Length) = 1 then
        Put_Line_Error
          ("Error: /APPEND requires multiple datasets");
        Had_Error := True;
     end if;
  ```

- [ ] **Step 3: Add MM_Append to mode determination**

  In the post-validation mode-assignment block:

  ```ada
     if Saw_APPEND then
        Stmt.Mode := MM_Append;
     elsif Saw_INTERLEAVE then
        Stmt.Mode := MM_Interleave;
     ...
  ```

  Place `Saw_APPEND` check first so it takes precedence over the default-to-Positional branch.

- [ ] **Step 4: Build and run**

  ```bash
  cd /home/jries/Develop/sdata && make build && make check
  ```

  Expected: all existing tests pass. `/APPEND` parses but the executor doesn't yet handle MM_Append — Task 5 wires it. Any USE with `/APPEND` currently produces an error from Execute_USE's case-of-mode statement, which we accept temporarily; integration tests for `/APPEND` land in Task 6 after the executor is wired.

- [ ] **Step 5: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/parser/sdata-parser.adb
  git commit -m "$(cat <<'EOF'
  feat(parser): accept /APPEND slash-option on multi-dataset USE

  Parse_USE_Stmt now recognises /APPEND, tracks it via Saw_APPEND,
  validates mutex (cannot combine with /BY, /INTERLEAVE, /JOIN; not
  permitted with a single dataset), and sets Stmt.Mode := MM_Append.
  Executor dispatch lands in the next commit.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 5: Executor — dispatch MM_Append to Combine_Append

**Files:**
- Modify: `/home/jries/Develop/sdata/src/sdata-interpreter-execute_declarative.adb`

- [ ] **Step 1: Locate the per-spec sort gate**

  In the multi-dataset path of Execute_USE, find the block that auto-sorts each snapshot by BY-vars. It currently fires for `Match | Interleave | Join`. Update to exclude `MM_Append`:

  ```ada
     if Stmt.Mode = MM_Match
        or Stmt.Mode = MM_Interleave
        or Stmt.Mode = MM_Join
     then
        --  auto-sort by By_Vars
        ...
     end if;
  ```

  No change needed — `MM_Append` is not in the list, so sort is correctly skipped. Verify the existing code reads exactly this way and doesn't fall through to sort for new modes.

- [ ] **Step 2: Convert By_Vars only when needed**

  The existing code converts `Stmt.By_Vars` to `By_Names` for the match/interleave/join modes. APPEND doesn't use BY. The conversion is gated on the same mode condition above and is correct as-is.

- [ ] **Step 3: Add MM_Append to combine dispatch**

  Find the `case Stmt.Mode is` arm that selects which Combine_* to call. Add:

  ```ada
        when MM_Append =>
           Combined := SData.Merge.Combine_Append
                         (Snapshots, Warnings, Provenance);
  ```

  Note the absence of `By_Names` — Combine_Append takes only Inputs / Warnings / Provenance.

- [ ] **Step 4: Build and run**

  ```bash
  cd /home/jries/Develop/sdata && make check
  cd /home/jries/Develop/data-vandal && make check
  ```

  Expected: all baseline tests pass. The executor now dispatches MM_Append correctly.

- [ ] **Step 5: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/sdata-interpreter-execute_declarative.adb
  git commit -m "$(cat <<'EOF'
  feat(use): dispatch MM_Append to Combine_Append

  Execute_USE's combine-mode case now handles MM_Append by calling
  SData.Merge.Combine_Append (no By_Names parameter). The auto-sort
  step is correctly skipped because APPEND preserves input order.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 6: Integration tests for /APPEND

**Files:**
- Add: 4 functional `.cmd` files + matching `tests/expected/*.out`
- Add: 3 error `.cmd` files + matching `.exitcode` + `.out`
- Add: `tests/data/append_a.csv`, `tests/data/append_b.csv`, `tests/data/append_c.csv` if not already present (or reuse merge_a.csv / merge_b.csv from earlier work)

- [ ] **Step 1: Create or reuse fixtures**

  Check whether `tests/data/merge_a.csv` and `merge_b.csv` can be reused. If they suffice, skip new fixture creation. Otherwise:

  - `tests/data/append_a.csv`:
    ```
    ID,X
    1,10
    2,20
    ```
  - `tests/data/append_b.csv`:
    ```
    ID,Y
    3,300
    4,400
    ```
  - `tests/data/append_c.csv`:
    ```
    ID,Z
    5,5000
    ```

- [ ] **Step 2: Functional tests**

  `tests/use_merge_append_two.cmd`:
  ```
  USE "tests/data/append_a.csv", "tests/data/append_b.csv" /APPEND
  PRINT ID, X, Y
  RUN
  NEW
  END
  ```

  Expected output: 4 rows. First two: ID=1,2 with X=10,20 and Y=. Last two: ID=3,4 with X=. and Y=300,400.

  `tests/use_merge_append_three.cmd`: same shape with three inputs.

  `tests/use_merge_append_with_in.cmd`:
  ```
  USE "tests/data/append_a.csv" (IN=fromA),
      "tests/data/append_b.csv" (IN=fromB)
      /APPEND
  PRINT ID, fromA, fromB
  RUN
  NEW
  END
  ```

  Expected: 4 rows. First two have fromA=1, fromB=0. Last two have fromA=0, fromB=1.

  `tests/use_merge_append_per_ds_keep.cmd`: exercise per-dataset KEEP=.

  Run each, capture actual output, save as `tests/expected/<name>.out`.

- [ ] **Step 3: Error tests**

  `tests/use_merge_err_append_with_by.cmd`:
  ```
  USE "tests/data/append_a.csv", "tests/data/append_b.csv" /BY=ID /APPEND
  NEW
  END
  ```

  Expected exit 1 with "Error: /APPEND cannot be combined with /BY, /INTERLEAVE, or /JOIN" in stderr.

  `tests/use_merge_err_append_with_join.cmd`: /JOIN /APPEND, same expected error.

  `tests/use_merge_err_append_single.cmd`: single-dataset `/APPEND`, expected error "/APPEND requires multiple datasets".

  Each test gets a `.cmd`, a `.exitcode` (`1`), and a `tests/expected/*.out`.

- [ ] **Step 4: Build and run**

  ```bash
  cd /home/jries/Develop/sdata && make check
  cd /home/jries/Develop/data-vandal && make check
  ```

  Expected: baseline + 4 functional + 3 error = 7 new tests, all pass.

- [ ] **Step 5: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add tests/use_merge_append_*.cmd tests/expected/use_merge_append_*.out \
          tests/use_merge_err_append_*.cmd tests/expected/use_merge_err_append_*.out \
          tests/use_merge_err_append_*.exitcode \
          tests/data/append_*.csv
  git commit -m "$(cat <<'EOF'
  test(merge): integration tests for /APPEND merge mode

  Four functional tests (two-input, three-input, IN= provenance,
  per-dataset KEEP=) and three error tests (mutex with /BY, mutex
  with /JOIN, single-dataset rejection).

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 7: Update the man page

**Files:**
- Modify: `/home/jries/Develop/sdata/man/man1/sdata.1`

- [ ] **Step 1: Add APPEND to the merge-mode table**

  Find the merge-mode table in the USE section (added in Task 23 of the merge-multi-output work; near line 200 of the man page). Add a row for APPEND:

  ```
  /APPEND          Vertical concatenation         No BY required; rows
                   in spec order with             from each input emitted in
                   column-union semantics         input order
  ```

  Match the existing rows' formatting.

- [ ] **Step 2: Add prose paragraph below the table**

  Add (after the existing mutual-exclusivity paragraph):

  ```
  .PP
  .B /APPEND
  produces a vertical concatenation of the input datasets in spec
  order: all rows of the first dataset, then all rows of the second,
  and so on.
  Output columns are the union of input columns (collision warnings
  fire as elsewhere).
  Each output row carries values only from its originating input;
  columns introduced by other inputs are missing.
  .B /APPEND
  may not be combined with
  .BR /BY ,
  .BR /INTERLEAVE ,
  or
  .BR /JOIN ,
  and requires at least two datasets.
  ```

- [ ] **Step 3: Verify groff render**

  ```bash
  groff -man -Tutf8 /home/jries/Develop/sdata/man/man1/sdata.1 > /dev/null 2>&1 && echo OK
  ```

- [ ] **Step 4: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add man/man1/sdata.1
  git commit -m "$(cat <<'EOF'
  docs(man): document /APPEND merge mode

  New row in the merge-mode table plus a descriptive paragraph
  covering vertical-concatenation semantics, column union, and mutex
  rules.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 8: Final validation

- [ ] **Step 1: Full test suites**

  ```bash
  cd /home/jries/Develop/sdata && make check
  cd /home/jries/Develop/data-vandal && make check
  cd /home/jries/Develop/sdata-core && alr build
  ```

  Expected: baseline + 5 unit tests (CA-*) + 7 integration tests = 12 new passes.

- [ ] **Step 2: Inspect history**

  ```bash
  cd /home/jries/Develop/sdata && git log --oneline | head -10
  ```

  Verify commits are focused, conventional, and read as a coherent story.

---

## Self-Review Summary

- **Spec coverage:** semantics → Tasks 3, 5; lexer → Task 1; AST → Task 2; parser → Task 4; executor → Task 5; documentation → Task 7; tests → Tasks 3, 6.
- **Placeholder scan:** no TBDs; every step has exact code or commands.
- **Type consistency:** `Combine_Append` signature matches the spec exactly (Inputs / Warnings / Provenance; no By_Vars).
- **Estimated effort:** under a day of subagent execution. Smaller than the quoted-identifier plan; substantially smaller than any single Follow-on from the merge feature.
