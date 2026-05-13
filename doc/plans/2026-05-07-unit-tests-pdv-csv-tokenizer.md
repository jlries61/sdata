# Unit Tests: PDV/Variables and CSV Tokenizer Edge Cases

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the two existing unit test binaries with edge-case coverage for `SData.CSV` and functional coverage for `SData.Variables` (PDV operations, symbol table, hold/reset, flush-to-output), moving the §4.1 verdict from "Critically insufficient" to "adequate for the data step hot path."

**Architecture:** Two self-contained Ada programs (`tests/csv_unit_test.adb` and `tests/sdata_unit_test.adb`) are already compiled by `sdata.gpr` and run by `make check`. No project-file changes are needed — only the two test source files are modified.

**Tech Stack:** Ada 2012, GNAT, `alr build`, `make check`.

---

## File Structure

- Modify: `tests/csv_unit_test.adb` (add ~20 edge-case tests for `SData.CSV`)
- Modify: `tests/sdata_unit_test.adb` (add `with SData.Variables`, add ~25 PDV/symbol-table tests)

---

## Task 1: Extend `csv_unit_test.adb` with edge-case tests

**Files:**
- Modify: `tests/csv_unit_test.adb`

The existing 38 tests cover happy paths for all five `SData.CSV` functions. This task adds ~20 tests targeting boundary conditions that the file-parsing code actually exercises: sign-prefix floats, negative-exponent scientific notation, INF literals, empty quoted fields, multi-char delimiters, and empty fields within a line.

- [ ] **Step 1: Verify baseline**

```bash
alr exec -- make check 2>&1 | tail -5
```

Expected: all tests pass (count may vary; no failures).

- [ ] **Step 2: Add `with SData.Values` to the test**

In `tests/csv_unit_test.adb`, add after the existing `with SData.CSV`:

```ada
with SData.Values; use SData.Values;
```

This gives access to `Pos_Inf` and `Neg_Inf` for the INF-literal tests.

- [ ] **Step 3: Add a `Check_Inf` helper**

After the existing `Check_Float` helper, add:

```ada
   procedure Check_Inf (Name : String; Got_Ok : Boolean; Got_Val : Float;
                        Expected_Inf : Float) is
   begin
      if Got_Ok and then Got_Val = Expected_Inf then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got_ok=" & Got_Ok'Image & "  got=" & Got_Val'Image);
         Failed := Failed + 1;
      end if;
   end Check_Inf;
```

- [ ] **Step 4: Add `Try_Fast_Float` edge-case tests**

After the existing TFF-5 block, add:

```ada
   Check_Float ("TFF-6 positive sign",
      Try_Fast_Float ("+3.14", R), R, True, 3.14);
   Check_Float ("TFF-7 negative exponent",
      Try_Fast_Float ("1E-3",  R), R, True, 0.001, 0.0001);
   Check_Float ("TFF-8 negative zero",
      Try_Fast_Float ("-0",    R), R, True, 0.0);
   Check_Float ("TFF-9 leading-dot decimal",
      Try_Fast_Float (".5",    R), R, True, 0.5);
   Check_Float ("TFF-10 spaces trimmed",
      Try_Fast_Float ("  42  ", R), R, True, 42.0);
   Check_Inf ("TFF-11 INF literal",
      Try_Fast_Float ("INF",  R), R, Pos_Inf);
   Check_Inf ("TFF-12 -INF literal",
      Try_Fast_Float ("-INF", R), R, Neg_Inf);
   Check_Float ("TFF-13 incomplete exponent",
      Try_Fast_Float ("1e",   R), R, False, 0.0);
   Check_Float ("TFF-14 double dot",
      Try_Fast_Float ("1.2.3", R), R, False, 0.0);
   Check_Float ("TFF-15 sign only",
      Try_Fast_Float ("-",    R), R, False, 0.0);
   Check_Float ("TFF-16 plus sign only",
      Try_Fast_Float ("+",    R), R, False, 0.0);
```

- [ ] **Step 5: Add `Is_Numeric_Field` edge-case tests**

After the existing INF-3 block, add:

```ada
   Check ("INF-4 negative exponent numeric", Is_Numeric_Field ("1E-3"),  True);
   Check ("INF-5 positive sign numeric",     Is_Numeric_Field ("+3.14"), True);
   Check ("INF-6 sign-only not numeric",     Is_Numeric_Field ("-"),     False);
   Check ("INF-7 double-dot not numeric",    Is_Numeric_Field ("1.2.3"), False);
   Check ("INF-8 INF is numeric",            Is_Numeric_Field ("INF"),   True);
```

- [ ] **Step 6: Add `CSV_Field_End` edge-case tests**

After the existing CFE-3 block, add:

```ada
   --  Leading empty field: delimiter is the very first character.
   Check ("CFE-4 leading empty field",
      CSV_Field_End (",a,b", 1, ","), 1);
   --  From index past end of line: treated as last field.
   Check ("CFE-5 From past end",
      CSV_Field_End ("a", 2, ","), 0);
   --  Two-character delimiter.
   Check ("CFE-6 two-char delimiter first field",
      CSV_Field_End ("a::b::c", 1, "::"), 2);
```

- [ ] **Step 7: Add `CSV_Unquote` edge-case tests**

After the existing CUQ-4 block, add:

```ada
   Check ("CUQ-5 empty double-quoted",
      CSV_Unquote (""""""), "");
   Check ("CUQ-6 spaces inside quotes preserved",
      CSV_Unquote ("""  hello  """), "  hello  ");
   Check ("CUQ-7 single-char no quotes trimmed",
      CSV_Unquote ("  x  "), "x");
```

Note on CUQ-5: the Ada literal `""""""` represents the string `""` (two double-quote characters), which `CSV_Unquote` should return as the empty string.

- [ ] **Step 8: Add `Split_Indices` edge-case tests**

After the existing SI-3 block, add:

```ada
   --  Single field, no delimiter in line.
   Split_Indices ("abc", ",", FV);
   Check ("SI-4 single field count", Natural (FV.Length), 1);
   Check ("SI-4 f1.S", FV(1).S, 1);
   Check ("SI-4 f1.E", FV(1).E, 3);

   --  Tab-delimited.
   Split_Indices ("a" & ASCII.HT & "b" & ASCII.HT & "c",
                  "" & ASCII.HT, FV);
   Check ("SI-5 tab count", Natural (FV.Length), 3);
   Check ("SI-5 f2.S", FV(2).S, 3);
   Check ("SI-5 f2.E", FV(2).E, 3);

   --  Empty middle field: a,,c → three fields, field 2 is empty (E < S).
   Split_Indices ("a,,c", ",", FV);
   Check ("SI-6 empty middle count",  Natural (FV.Length), 3);
   Check ("SI-6 f2 empty (E<S)",      FV(2).E < FV(2).S, True);
   Check ("SI-6 f3.S", FV(3).S, 4);

   --  Trailing delimiter: a,b, → three fields, last is empty.
   Split_Indices ("a,b,", ",", FV);
   Check ("SI-7 trailing delimiter count",  Natural (FV.Length), 3);
   Check ("SI-7 last field empty (E<S)",    FV(3).E < FV(3).S, True);

   --  Two-character delimiter.
   Split_Indices ("a::b::c", "::", FV);
   Check ("SI-8 two-char delim count", Natural (FV.Length), 3);
   Check ("SI-8 f1.S", FV(1).S, 1);
   Check ("SI-8 f1.E", FV(1).E, 1);
   Check ("SI-8 f3.S", FV(3).S, 7);
   Check ("SI-8 f3.E", FV(3).E, 7);
```

- [ ] **Step 9: Build**

```bash
alr build 2>&1 | tail -5
```

Expected: `Build finished successfully`

- [ ] **Step 10: Run tests and confirm all pass**

```bash
alr exec -- bin/csv_unit_test
```

Expected: all PASS lines, 0 failed. Fix any failures before committing.

- [ ] **Step 11: Commit**

```bash
git add tests/csv_unit_test.adb
git commit -m "Test: extend CSV unit tests with edge-case coverage (~20 new tests)"
```

---

## Task 2: Extend `sdata_unit_test.adb` with PDV/Variables tests

**Files:**
- Modify: `tests/sdata_unit_test.adb`

The existing 65 tests cover `SData.Table` and a few `SData.Evaluator` helpers. `SData.Variables` has zero unit test coverage. This task adds a new section at the end of the test body covering: temporary variables, permanent variables (PDV slots), PDV load-from-table roundtrip, hold/reset, and flush-to-output pipeline.

**Context on the Variables subsystem:**
- `Initialize_PDV` mirrors the current table schema into the PDV (one slot per column, all `Val_Missing`).
- `Load_PDV_From_Table(Row)` fills PDV slots from a table row using the cursor cache.
- `Set_Permanent(Name, Val)` adds or updates a PDV slot (no table column needed).
- `Set_Temporary(Name, Val)` writes to the session symbol table. If a column with that name exists, it is **dropped from the table** (side effect — avoid passing column names here).
- `PDV_Resolve(Name)` returns the 1-based slot index; requires upper-case `Name`.
- `Get_PDV_Value(Idx)` returns the value in a slot.
- `Get(Name)` looks up PDV first, then temp symbols; performs `To_Upper` internally.
- `Reset_PDV_Non_Held` resets non-held PDV slots to `Val_Missing`; copies held slot values into `Temp_Symbols`.
- `Flush_PDV_To_Output` adds output columns matching PDV names, appends an output row, and fills it. Must call `SData.Table.Initialize_Output_Table` first. After `SData.Table.Commit_Output_Table` the main table holds the output row.

- [ ] **Step 1: Add `with SData.Variables` to the test**

In `tests/sdata_unit_test.adb`, add after the existing `with SData.Evaluator`:

```ada
with SData.Variables; use SData.Variables;
```

- [ ] **Step 2: Add temporary-variable tests**

Before the final `New_Line; Put_Line (...)` summary block, add:

```ada
   ---------------------------------------------------------------------------
   --  ── SData.Variables: temporary (session) variables ───────────────────
   ---------------------------------------------------------------------------

   --  Start from a known state: empty table, empty temp symbols.
   SData.Table.Clear;
   Clear_Temporary;

   Set_Temporary ("myvar", (Kind => Val_Numeric, Num_Val => 5.5));
   Check ("V-01 Defined after Set_Temporary",   Defined ("myvar"), True);
   Check ("V-02 Defined case-insensitive",       Defined ("MYVAR"), True);
   V := Get ("myvar");
   Check       ("V-03 Get temp kind",    V.Kind = Val_Numeric, True);
   Check_Float ("V-04 Get temp value",   V.Num_Val, 5.5);

   Set_Temporary ("myvar", (Kind => Val_Numeric, Num_Val => 9.9));
   V := Get ("myvar");
   Check_Float ("V-05 Update temp value", V.Num_Val, 9.9);

   Unset ("myvar");
   Check ("V-06 Defined after Unset", Defined ("myvar"), False);
   V := Get ("myvar");
   Check ("V-07 Get after Unset returns Missing", V.Kind = Val_Missing, True);

   Set_Temporary ("alpha", (Kind => Val_Numeric, Num_Val => 1.0));
   Set_Temporary ("beta",  (Kind => Val_Numeric, Num_Val => 2.0));
   Clear_Temporary;
   Check ("V-08 Defined after Clear_Temporary alpha", Defined ("alpha"), False);
   Check ("V-09 Defined after Clear_Temporary beta",  Defined ("beta"),  False);
```

- [ ] **Step 3: Add permanent-variable (PDV slot) tests**

```ada
   ---------------------------------------------------------------------------
   --  ── SData.Variables: permanent variables (PDV slots) ──────────────────
   ---------------------------------------------------------------------------

   --  Empty table → empty PDV after Initialize_PDV.
   SData.Table.Clear;
   Initialize_PDV;

   Set_Permanent ("SCORE", (Kind => Val_Numeric, Num_Val => 99.0));
   Check ("V-10 Defined after Set_Permanent",     Defined ("SCORE"), True);
   V := Get ("SCORE");
   Check       ("V-11 Get permanent kind",   V.Kind = Val_Numeric, True);
   Check_Float ("V-12 Get permanent value",  V.Num_Val, 99.0);

   Check ("V-13 PDV_Resolve finds slot", PDV_Resolve ("SCORE") > 0, True);
   declare
      Slot : constant Positive := PDV_Resolve ("SCORE");
   begin
      V := Get_PDV_Value (Slot);
      Check_Float ("V-14 Get_PDV_Value matches Get", V.Num_Val, 99.0);
   end;

   Set_Permanent ("SCORE", (Kind => Val_Numeric, Num_Val => 42.0));
   V := Get ("SCORE");
   Check_Float ("V-15 Update permanent value", V.Num_Val, 42.0);

   Check ("V-16 PDV_Resolve unknown returns 0", PDV_Resolve ("NOSUCHVAR"), 0);
```

- [ ] **Step 4: Add PDV load-from-table roundtrip tests**

```ada
   ---------------------------------------------------------------------------
   --  ── SData.Variables: Load_PDV_From_Table roundtrip ────────────────────
   ---------------------------------------------------------------------------

   SData.Table.Clear;
   SData.Table.Add_Column ("A",  SData.Table.Col_Numeric);
   SData.Table.Add_Column ("B%", SData.Table.Col_Integer);
   SData.Table.Add_Row;
   SData.Table.Set_Value (1, "A",  (Kind => Val_Numeric, Num_Val => 3.14));
   SData.Table.Set_Value (1, "B%", (Kind => Val_Integer, Int_Val => 7));

   Initialize_PDV;
   --  Before load: all slots are Val_Missing.
   V := Get ("A");
   Check ("V-17 PDV before load is Missing", V.Kind = Val_Missing, True);

   Load_PDV_From_Table (1);
   V := Get ("A");
   Check       ("V-18 Get A after load kind",  V.Kind = Val_Numeric, True);
   Check_Float ("V-19 Get A after load value", V.Num_Val, 3.14);
   V := Get ("B%");
   Check ("V-20 Get B% after load kind",  V.Kind = Val_Integer, True);
   Check ("V-21 Get B% after load value", V.Int_Val, 7);

   --  PDV_Resolve requires upper-case name (matches how names are stored).
   declare
      Slot_A : constant Positive := PDV_Resolve ("A");
   begin
      V := Get_PDV_Value (Slot_A);
      Check_Float ("V-22 Get_PDV_Value(A) = 3.14", V.Num_Val, 3.14);
   end;
```

- [ ] **Step 5: Add hold / Reset_PDV_Non_Held tests**

```ada
   ---------------------------------------------------------------------------
   --  ── SData.Variables: hold / Reset_PDV_Non_Held ─────────────────────────
   ---------------------------------------------------------------------------

   --  Build a PDV with two columns: HELD and FREE.
   SData.Table.Clear;
   SData.Table.Add_Column ("HELD", SData.Table.Col_Numeric);
   SData.Table.Add_Column ("FREE", SData.Table.Col_Numeric);
   SData.Table.Add_Row;
   SData.Table.Set_Value (1, "HELD", (Kind => Val_Numeric, Num_Val => 7.0));
   SData.Table.Set_Value (1, "FREE", (Kind => Val_Numeric, Num_Val => 3.0));
   Initialize_PDV;
   Load_PDV_From_Table (1);

   Set_Hold ("HELD", True);
   Check ("V-23 Is_Held true",  Is_Held ("HELD"), True);
   Check ("V-24 Is_Held false", Is_Held ("FREE"), False);

   Reset_PDV_Non_Held;

   --  HELD slot keeps its value (and is also copied to Temp_Symbols).
   V := Get ("HELD");
   Check       ("V-25 Held var survives Reset kind",  V.Kind = Val_Numeric, True);
   Check_Float ("V-26 Held var survives Reset value", V.Num_Val, 7.0);

   --  FREE slot is reset to Val_Missing.
   V := Get ("FREE");
   Check ("V-27 Non-held var is Missing after Reset", V.Kind = Val_Missing, True);

   --  Clean up hold state.
   Set_Hold ("HELD", False);
   Check ("V-28 Is_Held after clearing", Is_Held ("HELD"), False);
```

- [ ] **Step 6: Add Flush_PDV_To_Output / Commit_Output_Table roundtrip tests**

```ada
   ---------------------------------------------------------------------------
   --  ── SData.Variables: Flush_PDV_To_Output pipeline ──────────────────────
   ---------------------------------------------------------------------------

   --  Set up a 1-column table, load into PDV, flush to output, commit.
   SData.Table.Clear;
   SData.Table.Add_Column ("X", SData.Table.Col_Numeric);
   SData.Table.Add_Row;
   SData.Table.Set_Value (1, "X", (Kind => Val_Numeric, Num_Val => 42.0));

   Initialize_PDV;
   Load_PDV_From_Table (1);

   SData.Table.Initialize_Output_Table;
   Flush_PDV_To_Output;

   Check ("V-29 Output_Row_Count = 1 after flush", SData.Table.Output_Row_Count, 1);

   SData.Table.Commit_Output_Table;

   Check ("V-30 Row_Count = 1 after commit",    SData.Table.Row_Count, 1);
   Check ("V-31 Column X present after commit", SData.Table.Has_Column ("X"), True);
   V := SData.Table.Get_Value (1, "X");
   Check       ("V-32 Committed value kind",  V.Kind = Val_Numeric, True);
   Check_Float ("V-33 Committed value",       V.Num_Val, 42.0);
```

- [ ] **Step 7: Build**

```bash
alr build 2>&1 | tail -5
```

Expected: `Build finished successfully`. If GNAT reports ambiguous `Check` or `Check_Float` overloads, qualify the calls (e.g., `Check ("...", SData.Table.Output_Row_Count, 1)` uses the `Integer` overload, which is fine).

- [ ] **Step 8: Run tests and confirm all pass**

```bash
alr exec -- bin/sdata_unit_test
```

Expected: all PASS lines, 0 failed. The prior 65 tests must still pass. Fix any failures before committing.

- [ ] **Step 9: Run full test suite**

```bash
alr exec -- make check 2>&1 | tail -10
```

Expected: no regressions in the integration tests.

- [ ] **Step 10: Commit**

```bash
git add tests/sdata_unit_test.adb
git commit -m "Test: add PDV/Variables unit tests (~25 new tests)"
```

---

## Final Verification

- [ ] **Step 1: Confirm new test counts**

```bash
alr exec -- bin/csv_unit_test  2>&1 | tail -3
alr exec -- bin/sdata_unit_test 2>&1 | tail -3
```

Expected: csv_unit_test ≥ 55 passed, sdata_unit_test ≥ 90 passed, 0 failed in either.

- [ ] **Step 2: Full suite clean**

```bash
alr exec -- make check 2>&1 | tail -5
```

Expected: all tests passed, 0 failed.
