# Suffix-Driven Type Change on USE/SAVE RENAME — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `USE`/`SAVE` `rename=()` option apply the suffix-determines-type rule: a rename that changes a name's type suffix within the numeric family (float ↔ integer) converts the column's values; a rename crossing the numeric ↔ character boundary is rejected, all-or-nothing.

**Architecture:** One new shared value-level conversion helper in `SData_Core.Values` (the single home for the truncate/promote rule), consumed both by the existing `SData_Core.Table.Coerce_Value` (refactored to delegate) and by `SData.Transient_Table.Apply_Rename` (the sole code path for `USE`/`SAVE` `rename=()`). The standalone `RENAME` statement (global table, spill-capable) is deliberately untouched — see the spec's *Out of Scope*.

**Tech Stack:** Ada 2012, Alire (`alr build`), GNAT. Two crates: `~/Develop/sdata-core` (shared library — `Values`) and `~/Develop/sdata` (interpreter — `Transient_Table`, tests).

**Spec:** `doc/specs/2026-06-05-rename-suffix-type-change-design.md`

---

## Background facts the implementer needs

- **Type suffix rule:** name ends `$` → string (`Col_String`), ends `%` → integer (`Col_Integer`), no suffix → float (`Col_Numeric`).
- **`Value` variant** (`sdata-core/src/sdata_core-values.ads:15-29`): `Value_Kind` is `(Val_Numeric, Val_Integer, Val_String, Val_Missing)`; `Val_Numeric` carries `Num_Val : Float`, `Val_Integer` carries `Int_Val : Integer`, `Val_String` carries `Str_Val : Unbounded_String`.
- **Existing truncation rule** (to be centralized): `Integer (Float'Truncation (F))` — truncates toward zero. Lives today in `sdata-core/src/sdata_core-table.adb:272` (`Coerce_Value`) and `sdata/src/sdata-interpreter-execute_assignment.adb:125`.
- **Transient table internals** (`sdata/src/sdata-transient_table.ads:97-118`): columns held in two parallel-indexed vectors — `T.Cols` (each `Col_Entry` = `{Name : Unbounded_String; Typ : Column_Type}`) and `T.Data` (each element a `Value_Vectors.Vector` of one column's values). Column `I` in `T.Cols` corresponds to data vector `T.Data (I)`.
- **`Apply_Rename`** (`sdata/src/sdata-transient_table.adb:235-302`) is the ONLY procedure to change. It already has a validation pre-pass (duplicate source, duplicate target, collision) at `:245-281`, then an apply loop at `:283-301` that currently sets only `Entry_Val.Name`.
- **Both `USE` and `SAVE` `rename=()` funnel through `Apply_Rename`:** `USE` at `sdata/src/sdata-interpreter-execute_declarative.adb:267`, `SAVE` at `sdata/src/sdata-interpreter.adb:1045`.
- **Downstream consumers stay consistent:** `Install_To_Current` copies each transient column's `Typ` (`transient_table.adb:173`) and values (`:182`); the SAVE writer reads the transient `Typ`/values directly. Converting BOTH `Typ` and stored values keeps the transient table self-consistent.
- **Build order:** `Values` is in sdata-core. Always `cd ~/Develop/sdata-core && alr build` after editing it, then `cd ~/Develop/sdata && make check`.
- **Integration test harness** (`Makefile:119-152`): for each `tests/<name>.cmd`, runs `./bin/sdata <name>.cmd` capturing stdout+stderr, compares with `diff -wu` to `tests/expected/<name>.out`; expected exit code is `0` unless `tests/<name>.exitcode` exists.
- **Unit test harness** (`tests/sdata_unit_test.adb`): linear sequence of `Check (Name, Got, Expected)` calls (overloads for `Boolean`, `Integer`, `String`) and `Check_Kind`; exception-expecting tests use a local `Raised : Boolean` set in a `when ... =>` handler (pattern at `:752-772`). Built by `make check` as `bin/sdata_unit_test`.

---

## File Structure

| File | Crate | Change |
|---|---|---|
| `sdata-core/src/sdata_core-values.ads` | sdata-core | Add `Convert_Value` decl + `Conversion_Error` exception |
| `sdata-core/src/sdata_core-values.adb` | sdata-core | Add `Convert_Value` body |
| `sdata-core/src/sdata_core-table.adb` | sdata-core | Refactor `Coerce_Value` to delegate its two numeric promotions to `Convert_Value` |
| `sdata/src/sdata-transient_table.adb` | sdata | Add `Type_From_Name`/`Kind_Of` helpers; add boundary validation + value conversion to `Apply_Rename` |
| `sdata/tests/sdata_unit_test.adb` | sdata | Add `Convert_Value` (CV-*) and `Apply_Rename` retype (TT-26/27) unit tests |
| `sdata/tests/rename_retype.cmd` + `tests/data/rename_retype.csv` + `tests/expected/rename_retype.out` | sdata | Integration: float→integer conversion via `USE rename=` |
| `sdata/tests/rename_retype_err.cmd` + `tests/expected/rename_retype_err.out` + `tests/rename_retype_err.exitcode` | sdata | Integration: numeric→character boundary error |
| `sdata/man/man1/sdata.1` | sdata | Note conversion behavior under `RENAME=` |
| `sdata/doc/adrs.md` | sdata | Append ADR-044 |

---

## Task 1: `Convert_Value` helper in sdata-core (+ centralize truncation)

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-values.ads`
- Modify: `~/Develop/sdata-core/src/sdata_core-values.adb`
- Modify: `~/Develop/sdata-core/src/sdata_core-table.adb:265-274`
- Test: `~/Develop/sdata/tests/sdata_unit_test.adb`

- [ ] **Step 1: Declare `Convert_Value` and `Conversion_Error`**

In `sdata_core-values.ads`, after the `To_String_Formatted` declaration (around line 45), add:

```ada
   --  Convert V to the requested numeric-family kind.
   --  Val_Numeric <-> Val_Integer convert (Numeric -> Integer truncates
   --  toward zero, matching LET coercion); Val_Missing passes through; a
   --  Value already of kind Target is returned unchanged.  Raises
   --  Conversion_Error if a string is involved on either side (string value
   --  with a numeric Target, or string Target with a numeric value), i.e.
   --  the numeric/character boundary, which this routine does not cross.
   function Convert_Value (V : Value; Target : Value_Kind) return Value;

   --  Raised by Convert_Value for an unsupported string <-> numeric crossing.
   Conversion_Error : exception;
```

- [ ] **Step 2: Implement `Convert_Value`**

In `sdata_core-values.adb`, add the body (e.g. after `Is_Inf`, before `To_String`):

```ada
   ------------------
   -- Convert_Value --
   ------------------
   function Convert_Value (V : Value; Target : Value_Kind) return Value is
   begin
      if V.Kind = Val_Missing or else V.Kind = Target then
         return V;
      end if;
      case Target is
         when Val_Numeric =>
            if V.Kind = Val_Integer then
               return (Kind => Val_Numeric, Num_Val => Float (V.Int_Val));
            end if;
            raise Conversion_Error
              with "cannot convert string value to numeric";
         when Val_Integer =>
            if V.Kind = Val_Numeric then
               return (Kind    => Val_Integer,
                       Int_Val => Integer (Float'Truncation (V.Num_Val)));
            end if;
            raise Conversion_Error
              with "cannot convert string value to integer";
         when Val_String =>
            raise Conversion_Error
              with "cannot convert numeric value to string";
         when Val_Missing =>
            return (Kind => Val_Missing);
      end case;
   end Convert_Value;
```

- [ ] **Step 3: Refactor `Coerce_Value` to delegate (DRY)**

In `sdata_core-table.adb`, replace the two promotion bodies at `:265-274`. Change:

```ada
      if Col_Typ = Col_Numeric and then Val.Kind /= Val_Numeric then
         if Val.Kind = Val_Integer then
            return (Kind => Val_Numeric, Num_Val => Float (Val.Int_Val));
         end if;
         raise Type_Mismatch_Error with "Expected Numeric for column " & Col_Name;
      elsif Col_Typ = Col_Integer and then Val.Kind /= Val_Integer then
         if Val.Kind = Val_Numeric then
            return (Kind => Val_Integer, Int_Val => Integer (Float'Truncation (Val.Num_Val)));
         end if;
         raise Type_Mismatch_Error with "Expected Integer for column " & Col_Name;
```

to:

```ada
      if Col_Typ = Col_Numeric and then Val.Kind /= Val_Numeric then
         if Val.Kind = Val_Integer then
            return Convert_Value (Val, Val_Numeric);
         end if;
         raise Type_Mismatch_Error with "Expected Numeric for column " & Col_Name;
      elsif Col_Typ = Col_Integer and then Val.Kind /= Val_Integer then
         if Val.Kind = Val_Numeric then
            return Convert_Value (Val, Val_Integer);
         end if;
         raise Type_Mismatch_Error with "Expected Integer for column " & Col_Name;
```

(`Convert_Value`, `Val_Numeric`, `Val_Integer` are already `use`-visible here — `sdata_core-table.adb` uses these names unqualified at the original `:267`.)

- [ ] **Step 4: Build sdata-core**

Run: `cd ~/Develop/sdata-core && alr build`
Expected: clean build, no errors. (Confirms the new public API compiles and the `Coerce_Value` refactor type-checks.)

- [ ] **Step 5: Write the failing unit test for `Convert_Value`**

In `~/Develop/sdata/tests/sdata_unit_test.adb`, immediately before the `── Summary ──` block near the end of the file, add:

```ada
   ---------------------------------------------------------------------------
   --  Convert_Value (numeric-family conversion helper)
   ---------------------------------------------------------------------------
   declare
      Iv     : constant Value := (Kind => Val_Integer, Int_Val => 3);
      Fv     : constant Value := (Kind => Val_Numeric, Num_Val => 3.7);
      Fn     : constant Value := (Kind => Val_Numeric, Num_Val => -3.7);
      Sv     : constant Value := (Kind    => Val_String,
                                  Str_Val => To_Unbounded_String ("hi"));
      Mv     : constant Value := (Kind => Val_Missing);
      Sink   : Value;
      Raised : Boolean := False;
   begin
      Check ("CV-01 numeric->integer truncates toward zero",
             Convert_Value (Fv, Val_Integer).Int_Val, 3);
      Check ("CV-02 negative numeric->integer truncates toward zero",
             Convert_Value (Fn, Val_Integer).Int_Val, -3);
      Check ("CV-03 integer->numeric promotes",
             Convert_Value (Iv, Val_Numeric).Num_Val = 3.0, True);
      Check ("CV-04 missing passes through",
             Convert_Value (Mv, Val_Integer).Kind = Val_Missing, True);
      Check ("CV-05 same-kind is a no-op",
             Convert_Value (Iv, Val_Integer).Int_Val, 3);
      begin
         Sink := Convert_Value (Sv, Val_Integer);
      exception
         when Conversion_Error => Raised := True;
      end;
      Check ("CV-06 string->integer raises Conversion_Error", Raised, True);
      if Sink.Kind = Val_Missing then null; end if;  --  reference Sink
   end;
```

(`Value`, `Val_*`, `Convert_Value`, `Conversion_Error`, `To_Unbounded_String` are all already use-visible in this file via its `with`/`use` clauses for `SData_Core.Values` and `Ada.Strings.Unbounded`.)

- [ ] **Step 6: Run unit tests — verify CV tests pass**

Run: `cd ~/Develop/sdata && make check 2>&1 | grep -E "CV-0|passed,"`
Expected: `CV-01`..`CV-06` all `PASS`, and the final `N passed, 0 failed.` line for the unit suite.

- [ ] **Step 7: Commit**

```bash
cd ~/Develop/sdata-core && git add src/sdata_core-values.ads src/sdata_core-values.adb src/sdata_core-table.adb
git commit -m "feat: add Values.Convert_Value; centralize numeric truncation in Coerce_Value"
```

Then commit the sdata-side test:

```bash
cd ~/Develop/sdata && git add tests/sdata_unit_test.adb
git commit -m "test: cover SData_Core.Values.Convert_Value"
```

---

## Task 2: Retype on `Apply_Rename` (USE/SAVE rename=)

**Files:**
- Modify: `~/Develop/sdata/src/sdata-transient_table.adb` (add helpers above `Apply_Rename`; edit `Apply_Rename` at `:235-302`)
- Test: `~/Develop/sdata/tests/sdata_unit_test.adb`

- [ ] **Step 1: Write the failing unit tests (retype + all-or-nothing)**

In `~/Develop/sdata/tests/sdata_unit_test.adb`, after the existing `TT-25` block (around `:790`), add:

```ada
   --  TT-26: Apply_Rename float->integer rename converts type and truncates
   declare
      TT    : SData.Transient_Table.Table;
      Pairs : SData.Transient_Table.Rename_Map_Vectors.Vector;
   begin
      TT.Add_Column ("X", SData_Core.Table.Col_Numeric);
      TT.Add_Row;
      TT.Set_Value (1, "X", (Kind => Val_Numeric, Num_Val => 10.7));
      Pairs.Append ((Old_Name => To_Unbounded_String ("X"),
                     New_Name => To_Unbounded_String ("Y%")));
      SData.Transient_Table.Apply_Rename (TT, Pairs);
      Check ("TT-26 renamed column Y% present", TT.Has_Column ("Y%"), True);
      Check ("TT-26b column type now Integer",
             TT.Get_Column_Type ("Y%") = SData_Core.Table.Col_Integer, True);
      declare
         V : constant Value := TT.Get_Value (1, "Y%");
      begin
         Check ("TT-26c value truncated to 10",
                V.Kind = Val_Integer and then V.Int_Val = 10, True);
      end;
   end;

   --  TT-27: Apply_Rename rejects numeric->character boundary, all-or-nothing
   declare
      TT     : SData.Transient_Table.Table;
      Pairs  : SData.Transient_Table.Rename_Map_Vectors.Vector;
      Raised : Boolean := False;
   begin
      TT.Add_Column ("X", SData_Core.Table.Col_Numeric);
      TT.Add_Column ("K", SData_Core.Table.Col_Numeric);
      --  A valid pair (K->KK) plus an invalid boundary pair (X->Y$).
      Pairs.Append ((Old_Name => To_Unbounded_String ("K"),
                     New_Name => To_Unbounded_String ("KK")));
      Pairs.Append ((Old_Name => To_Unbounded_String ("X"),
                     New_Name => To_Unbounded_String ("Y$")));
      begin
         SData.Transient_Table.Apply_Rename (TT, Pairs);
      exception
         when SData.Transient_Table.Rename_Error => Raised := True;
      end;
      Check ("TT-27 boundary rename raises Rename_Error", Raised, True);
      Check ("TT-27b all-or-nothing: K not renamed", TT.Has_Column ("K"), True);
      Check ("TT-27c all-or-nothing: KK absent", TT.Has_Column ("KK"), False);
   end;
```

- [ ] **Step 2: Run — verify TT-26b/26c/27* FAIL**

Run: `cd ~/Develop/sdata && make check 2>&1 | grep -E "TT-26|TT-27"`
Expected: `TT-26` (column present) PASSES (rename already works), but `TT-26b`, `TT-26c` FAIL (type/value not converted yet), and `TT-27`, `TT-27c` FAIL (boundary not enforced; `KK` gets applied). This confirms the tests exercise the new behavior.

- [ ] **Step 3: Add the suffix→type helpers**

In `~/Develop/sdata/src/sdata-transient_table.adb`, after `Column_Index_Upper` (ends `:23`) and before the `--  Schema` banner, add:

```ada
   --  Map a name's type suffix to a column type: '$' -> string,
   --  '%' -> integer, otherwise numeric (float).  Mirrors the evaluator's
   --  Get_Expected_Kind so RENAME honours the suffix-determines-type rule.
   function Type_From_Name
     (Name : String) return SData_Core.Table.Column_Type
   is
      use SData_Core.Table;
   begin
      if Name'Length = 0 then
         return Col_Numeric;
      elsif Name (Name'Last) = '$' then
         return Col_String;
      elsif Name (Name'Last) = '%' then
         return Col_Integer;
      else
         return Col_Numeric;
      end if;
   end Type_From_Name;

   --  Value_Kind corresponding to a column type.
   function Kind_Of
     (T : SData_Core.Table.Column_Type) return SData_Core.Values.Value_Kind
   is
      use SData_Core.Table;
      use SData_Core.Values;
   begin
      case T is
         when Col_Numeric => return Val_Numeric;
         when Col_Integer => return Val_Integer;
         when Col_String  => return Val_String;
      end case;
   end Kind_Of;
```

- [ ] **Step 4: Add the boundary-validation loop to `Apply_Rename`**

In `Apply_Rename`, immediately AFTER the collision-check loop that ends at `:281` (`end loop;` following the "target name collides" raise) and BEFORE the `--  Apply: simultaneous rename...` comment at `:283`, insert:

```ada
      --  Validate: a suffix change must stay within the numeric family
      --  (float <-> integer).  Crossing the numeric/character boundary is
      --  rejected here, before any mutation, so nothing is applied on error
      --  (all-or-nothing).  Runs after the duplicate/collision checks so
      --  those messages fire first.
      for I in 1 .. Natural (T.Cols.Length) loop
         declare
            Col_Up  : constant String :=
              To_Upper (To_String (T.Cols (I).Name));
            Cur_Typ : constant SData_Core.Table.Column_Type := T.Cols (I).Typ;
            use type SData_Core.Table.Column_Type;
         begin
            for P of Pairs loop
               if To_Upper (To_String (P.Old_Name)) = Col_Up then
                  declare
                     New_Typ : constant SData_Core.Table.Column_Type :=
                       Type_From_Name (To_String (P.New_Name));
                  begin
                     if (Cur_Typ = SData_Core.Table.Col_String)
                          /= (New_Typ = SData_Core.Table.Col_String)
                     then
                        raise Rename_Error with
                          "Apply_Rename: cannot retype column "
                          & To_String (P.Old_Name)
                          & " across the numeric/character boundary ("
                          & To_String (P.Old_Name) & " -> "
                          & To_String (P.New_Name) & ")";
                     end if;
                  end;
                  exit;
               end if;
            end loop;
         end;
      end loop;
```

- [ ] **Step 5: Convert values in the apply loop**

Replace the existing apply-loop body at `:289-299`. Change:

```ada
            for P of Pairs loop
               if To_Upper (To_String (P.Old_Name)) = Col_Up then
                  declare
                     Entry_Val : Col_Entry := T.Cols (I);
                  begin
                     Entry_Val.Name := P.New_Name;
                     T.Cols.Replace_Element (I, Entry_Val);
                  end;
                  exit;
               end if;
            end loop;
```

to:

```ada
            for P of Pairs loop
               if To_Upper (To_String (P.Old_Name)) = Col_Up then
                  declare
                     Entry_Val : Col_Entry := T.Cols (I);
                     New_Typ   : constant SData_Core.Table.Column_Type :=
                       Type_From_Name (To_String (P.New_Name));
                     use type SData_Core.Table.Column_Type;
                  begin
                     if New_Typ /= Entry_Val.Typ then
                        --  Convert every value in this column to the new kind.
                        declare
                           CV       : Value_Vectors.Vector := T.Data (I);
                           New_Kind : constant SData_Core.Values.Value_Kind :=
                             Kind_Of (New_Typ);
                        begin
                           for R in 1 .. Natural (CV.Length) loop
                              CV.Replace_Element
                                (R, SData_Core.Values.Convert_Value
                                      (CV.Element (R), New_Kind));
                           end loop;
                           T.Data.Replace_Element (I, CV);
                        end;
                        Entry_Val.Typ := New_Typ;
                     end if;
                     Entry_Val.Name := P.New_Name;
                     T.Cols.Replace_Element (I, Entry_Val);
                  end;
                  exit;
               end if;
            end loop;
```

- [ ] **Step 6: Build and run — verify TT-26/27 now pass**

Run: `cd ~/Develop/sdata && make check 2>&1 | grep -E "TT-26|TT-27|passed,"`
Expected: `TT-26`, `TT-26b`, `TT-26c`, `TT-27`, `TT-27b`, `TT-27c` all `PASS`; unit suite reports `0 failed.`

- [ ] **Step 7: Run the full check (catch regressions in existing rename tests)**

Run: `cd ~/Develop/sdata && make check`
Expected: all unit tests pass and all 140 integration tests pass (in particular `rename_test`, `column_mgmt`, `save_multi_per_target_keep_drop_rename`, `use_merge_err_rename_dup_src`, `use_merge_err_rename_dup_target` — the duplicate/collision error messages must still fire first).

- [ ] **Step 8: Commit**

```bash
cd ~/Develop/sdata && git add src/sdata-transient_table.adb tests/sdata_unit_test.adb
git commit -m "feat: USE/SAVE rename= converts float<->integer, rejects numeric<->character"
```

---

## Task 3: Integration tests (.cmd) — success and error

**Files:**
- Create: `~/Develop/sdata/tests/data/rename_retype.csv`
- Create: `~/Develop/sdata/tests/rename_retype.cmd`
- Create: `~/Develop/sdata/tests/expected/rename_retype.out` (generated, then verified)
- Create: `~/Develop/sdata/tests/rename_retype_err.cmd`
- Create: `~/Develop/sdata/tests/rename_retype_err.exitcode`
- Create: `~/Develop/sdata/tests/expected/rename_retype_err.out` (generated, then verified)

- [ ] **Step 1: Create the test data file**

Write `~/Develop/sdata/tests/data/rename_retype.csv` (X has no suffix → float column):

```
X
10.7
-3.9
20.2
```

- [ ] **Step 2: Create the success-case script**

Write `~/Develop/sdata/tests/rename_retype.cmd`:

```
-- USE rename= converts float column X to integer Y% (truncates toward zero).
USE "tests/data/rename_retype.csv" (RENAME=(X=Y%))
NAMES
PRINT Y%
RUN
END
```

- [ ] **Step 3: Generate and verify the success expected output**

Run: `cd ~/Develop/sdata && ./bin/sdata tests/rename_retype.cmd > tests/expected/rename_retype.out 2>&1; echo "exit=$?"`
Then Read `tests/expected/rename_retype.out` and VERIFY:
- exit is `0`;
- the column is listed as `Y%` (not `X`) in the `Permanent Variables` block;
- the printed `Y%` values are the truncated integers `10`, `-3`, `20` (NOT `10.7`, `-3.9`, `20.2`, and `-3.9` truncates toward zero to `-3`, not `-4`).

If the values are not the truncated integers, the implementation is wrong — stop and fix Task 2 rather than accepting the generated file.

- [ ] **Step 4: Create the error-case script and exitcode**

Write `~/Develop/sdata/tests/rename_retype_err.cmd`:

```
-- USE rename= rejects a numeric->character boundary crossing (all-or-nothing).
USE "tests/data/rename_retype.csv" (RENAME=(X=Y$))
NAMES
END
```

Write `~/Develop/sdata/tests/rename_retype_err.exitcode` (single line):

```
1
```

- [ ] **Step 5: Generate and verify the error expected output**

Run: `cd ~/Develop/sdata && ./bin/sdata tests/rename_retype_err.cmd > tests/expected/rename_retype_err.out 2>&1; echo "exit=$?"`
Then Read `tests/expected/rename_retype_err.out` and VERIFY:
- exit is `1` (matches the `.exitcode` file);
- it contains the line `Error: Apply_Rename: cannot retype column X across the numeric/character boundary (X -> Y$)`;
- the `NAMES` output does NOT appear (the error aborted before it) — confirming all-or-nothing at the script level.

- [ ] **Step 6: Run the harness against both new tests**

Run: `cd ~/Develop/sdata && make check 2>&1 | grep -E "rename_retype"`
Expected: `tests/rename_retype.cmd ... PASSED` and `tests/rename_retype_err.cmd ... PASSED`.

- [ ] **Step 7: Full check**

Run: `cd ~/Develop/sdata && make check`
Expected: all unit tests pass and all 142 integration tests pass (140 existing + 2 new).

- [ ] **Step 8: Commit**

```bash
cd ~/Develop/sdata && git add tests/data/rename_retype.csv tests/rename_retype.cmd tests/rename_retype_err.cmd tests/rename_retype_err.exitcode tests/expected/rename_retype.out tests/expected/rename_retype_err.out
git commit -m "test: integration coverage for USE rename= type conversion + boundary error"
```

---

## Task 4: Cross-crate regression + documentation

**Files:**
- Modify: `~/Develop/sdata/man/man1/sdata.1` (USE `RENAME=` at `:259`, SAVE `RENAME=` at `:340`)
- Modify: `~/Develop/sdata/doc/adrs.md` (append ADR-044)

- [ ] **Step 1: Confirm data-vandal still builds and passes (sdata-core changed)**

Per the repo convention (CLAUDE.md): a sdata-core change requires checking the sister app.
Run: `cd ~/Develop/data-vandal && make check`
Expected: clean build and all 11 data-vandal tests pass. (The `Coerce_Value` refactor is behavior-preserving and `Convert_Value` is purely additive, so no behavior change is expected.)

- [ ] **Step 2: Document the behavior in the man page**

In `~/Develop/sdata/man/man1/sdata.1`, locate the USE `RENAME=` option description (near `:259`). After its existing text, add this plain-prose paragraph (no inline font macros, to avoid groff pitfalls):

```
If the new name's type suffix differs from the column's current type, the column
is retyped: a change within the numeric family converts the values (float to
integer truncates toward zero). A rename crossing the numeric/character boundary
(a "$" suffix added to or removed from a numeric column, or removed from a
character column) is rejected and the entire RENAME is aborted.
```

Apply the equivalent paragraph to the SAVE `RENAME=` option near `:340` (the behavior is identical on both).

- [ ] **Step 3: Append ADR-044**

Read the tail of `~/Develop/sdata/doc/adrs.md` to match the exact heading/section style of ADR-043 (around `:551`). Append a new section:

```markdown
### ADR-044: USE/SAVE RENAME= applies the suffix-determines-type rule

**Status:** Accepted

**Context:** A variable's type is denoted by its name suffix (`$` string,
`%` integer, none float), enforced on CSV import and `LET`/`SET` assignment but
not by `RENAME`. `USE foo(rename=(x=x%))` previously produced a column named
`X%` whose stored type was still float — a name/type mismatch.

**Decision:** The `USE`/`SAVE` `rename=()` option now derives each target
column's type from the new name's suffix. A change within the numeric family
(float <-> integer) converts the column's values (float -> integer truncates
toward zero, matching `LET` coercion). A rename crossing the numeric/character
boundary is rejected, and the whole `RENAME` is aborted with nothing applied
(all-or-nothing). The numeric truncation rule is centralized in
`SData_Core.Values.Convert_Value`, which `Table.Coerce_Value` also uses.

**Scope / non-goals:** The standalone `RENAME` statement (operating on the
global `SData_Core.Table`) remains name-only: that table spills row-segments to
SQLite typed by `Col.Typ`, so retyping a materialized column would require
rewriting the on-disk store — deferred. String <-> numeric conversion on rename
(option #2) is deferred past SData 1.0.

**Consequences:** Renaming a character column to a name without `$` (or a
numeric column to a `$` name) is now an error; string columns must keep a `$`
suffix across a rename. The transient-table path is unchanged for renames that
preserve the suffix.
```

- [ ] **Step 4: Verify docs build cleanly (man page lint)**

Run: `cd ~/Develop/sdata && man --warnings -E UTF-8 -l man/man1/sdata.1 > /dev/null`
Expected: no groff warnings on the edited lines. (If `man --warnings` is unavailable, run `groff -man -Tutf8 man/man1/sdata.1 > /dev/null` and expect no errors.)

- [ ] **Step 5: Commit**

```bash
cd ~/Develop/sdata && git add man/man1/sdata.1 doc/adrs.md
git commit -m "docs: document USE/SAVE rename= type conversion; add ADR-044"
```

---

## Task 5 (maintainer's call): version bump

> Optional — bump only if releasing. The path-pin means tests pass regardless of version numbers.

**Files:** the 9 files updated by `scripts/bump-version.sh` (see CLAUDE.md "Versioning").

- [ ] **Step 1: Bump sdata version**

Run: `cd ~/Develop/sdata && scripts/bump-version.sh 0.9.6 "USE/SAVE RENAME= applies suffix-determines-type (float<->integer convert; numeric<->character rejected)"`
Expected: 9 files updated.

- [ ] **Step 2: (Consider) bump sdata-core**

`Convert_Value` is new public API in sdata-core. If sdata-core is being released, bump its `~/Develop/sdata-core/alire.toml` version (e.g. `0.1.5` -> `0.1.6`) and update the path-pin/dependency constraint in `~/Develop/sdata/alire.toml` if the maintainer wants to require it. Independent of the sdata bump per ADR-043. Skip if not releasing sdata-core now.

- [ ] **Step 3: Final full check**

Run: `cd ~/Develop/sdata-core && alr build && cd ~/Develop/sdata && make check`
Expected: clean build, all unit + 142 integration tests pass.

- [ ] **Step 4: Commit and tag**

```bash
cd ~/Develop/sdata && git add -A
git commit -m "Bump version to 0.9.6"
git tag -a v0.9.6 -m "Version 0.9.6"
```

---

## Self-Review (completed during planning)

- **Spec coverage:** Rule table → Task 2 Steps 3-5 + Task 1. Conversion semantics (truncate/promote/missing) → `Convert_Value` (Task 1) + CV-01..05. Error semantics + all-or-nothing + ordering → boundary loop placed after existing checks (Task 2 Step 4) + TT-27 + error integration test. Scope (USE/SAVE only) → Task 2 targets `Apply_Rename`; standalone `RENAME` untouched. Behavior note (string→suffixless = error) → error integration test + man page + ADR. Tests → Tasks 1-3. Docs (man + ADR) → Task 4. (design.odt is a binary doc owned by the maintainer; the man page + ADR carry the committed-text record — `design.txt` is generated from `.odt` and is not hand-edited.)
- **Placeholder scan:** none — every code step shows full code; generated `.out` files are verified against explicit value assertions (the repo's established golden-output workflow), not left as TODOs.
- **Type consistency:** `Convert_Value (V : Value; Target : Value_Kind) return Value` and `Conversion_Error` used identically in Tasks 1-2; `Type_From_Name`/`Kind_Of` signatures match their call sites; `Col_Entry.Typ`, `T.Data (I)`, `Value_Vectors.Vector` match `transient_table.ads:97-118`.
