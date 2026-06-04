# Multi-Dataset USE + Multi-Target SAVE Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the design in `doc/specs/2026-05-27-merge-multi-output-design.md` — extend `USE` to combine 2+ datasets via positional / match / interleave / Cartesian-join semantics, extend `SAVE` to register multiple output targets, and extend `WRITE` to route records per target. Add SAS-style per-dataset options (KEEP, DROP, RENAME, IN) on USE and per-target options (KEEP, DROP, RENAME, IF) on SAVE.

**Architecture:** All merge orchestration lives in sdata. A new sdata-only `SData.Transient_Table` package holds intermediate per-input tables (the existing `SData_Core.Table` is a singleton, so we snapshot it after each per-input load and restore it after merging). A new `SData.Merge` package implements the four combiner algorithms. Multi-target SAVE registration also lives in sdata interpreter state (not in `SData_Core.Config.Runtime`). sdata-core gets two additive changes: a `Get_Column_Type` accessor and a new `OPTIONS JOIN_WARN_THRESHOLD` setting — no breaking API changes, data-vandal is unaffected.

**Tech Stack:** Ada 2012, Alire, GNAT toolchain. Test suites: `bin/csv_unit_test`, `bin/sdata_unit_test`, 140 `tests/*.cmd` integration tests via `make check`.

**Iteration boundaries:**
- Phases 0–5 ship the merge feature (USE-only). Stop after Phase 5 and the merge feature is complete and shippable.
- Phase 6 ships the multi-output SAVE/WRITE feature.
- Phase 7 is integration tests for both.
- Phase 8 is documentation and final validation.

---

## Pre-flight checks

- [ ] **Step 0.1: Verify clean working tree**

  ```bash
  git -C /home/jries/Develop/sdata status
  git -C /home/jries/Develop/sdata-core status
  ```

  Expected: both clean (no staged or modified files); only the untracked files noted at session start present.

- [ ] **Step 0.2: Verify the baseline test suites pass**

  ```bash
  cd /home/jries/Develop/sdata && make check
  cd /home/jries/Develop/data-vandal && make check
  ```

  Expected: sdata reports 140 integration tests pass + unit tests pass; data-vandal reports 11 tests pass. Record exact counts to compare against after the work is done.

- [ ] **Step 0.3: Confirm sdata-core builds standalone**

  ```bash
  cd /home/jries/Develop/sdata-core && alr build
  ```

  Expected: build succeeds with no errors. If it fails, stop and investigate; do not proceed.

---

## Phase 0: sdata-core additive helpers

These are the only sdata-core changes. They are purely additive — no existing signature or runtime field changes. Both consumers continue to build unchanged.

### Task 1: Add `Get_Column_Type` accessor to sdata-core Table

The transient-table snapshot path needs to read the column type of each column of the current table. There's no public accessor today.

**Files:**
- Modify: `/home/jries/Develop/sdata-core/src/sdata_core-table.ads`
- Modify: `/home/jries/Develop/sdata-core/src/sdata_core-table.adb`

- [ ] **Step 1: Add the declaration**

  In `sdata_core-table.ads`, add immediately after `function Has_Column (Name : String) return Boolean;` (line 31):

  ```ada
     --  Returns the declared Column_Type for the named column. Raises
     --  Constraint_Error if the column does not exist (caller should test
     --  Has_Column first when uncertainty is possible).
     function Get_Column_Type (Name : String) return Column_Type;
  ```

- [ ] **Step 2: Add the implementation**

  In `sdata_core-table.adb`, add the body. Look up the existing `Get_Value` implementation in the same file for the canonical pattern for looking up a column by name in `Data_Table` (the private `Column_Maps.Map`). Implement `Get_Column_Type` as:

  ```ada
  function Get_Column_Type (Name : String) return Column_Type is
     Cursor : constant Column_Maps.Cursor := Data_Table.Find (Name);
  begin
     if not Column_Maps.Has_Element (Cursor) then
        raise Constraint_Error with
          "Get_Column_Type: column not found: " & Name;
     end if;
     return Column_Maps.Element (Cursor).Typ;
  end Get_Column_Type;
  ```

  Place this body alongside the existing `Has_Column` body for proximity.

- [ ] **Step 3: Build sdata-core**

  ```bash
  cd /home/jries/Develop/sdata-core && alr build
  ```

  Expected: build succeeds.

- [ ] **Step 4: Build sdata and verify the existing tests pass**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: all 140 integration tests + unit tests pass. Additive changes must not break anything.

- [ ] **Step 5: Build data-vandal and verify its tests pass**

  ```bash
  cd /home/jries/Develop/data-vandal && make check
  ```

  Expected: all 11 tests pass.

- [ ] **Step 6: Commit (sdata-core)**

  ```bash
  cd /home/jries/Develop/sdata-core
  git add src/sdata_core-table.ads src/sdata_core-table.adb
  git commit -m "$(cat <<'EOF'
  feat(table): add Get_Column_Type public accessor

  Needed by sdata's upcoming transient-table snapshot path, which must
  inspect the type of each column of the current table when copying it
  into a per-input transient. Additive — no existing API changes.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

### Task 2: Add `OPTIONS JOIN_WARN_THRESHOLD` setting

The `/JOIN` Cartesian merge mode warns when a per-BY-group product exceeds a threshold. The threshold needs a Runtime field and an OPTIONS handler.

**Files:**
- Modify: `/home/jries/Develop/sdata-core/src/sdata_core-config-runtime.ads`
- Modify: `/home/jries/Develop/sdata-core/src/sdata_core-config-runtime.adb`
- Modify: `/home/jries/Develop/sdata-core/src/sdata_core-commands.ads`
- Modify: `/home/jries/Develop/sdata-core/src/sdata_core-commands.adb`

- [ ] **Step 1: Add the Runtime field**

  In `sdata_core-config-runtime.ads`, add after the `Options_Shell_Timeout` line (currently line 57):

  ```ada
     Options_Join_Warn_Threshold : Natural := 1_000_000;
  ```

- [ ] **Step 2: Reset the field in `Reset`**

  In `sdata_core-config-runtime.adb`, find the `Reset` procedure body. After the existing assignments resetting other OPTIONS fields, add:

  ```ada
        Options_Join_Warn_Threshold := 1_000_000;
  ```

  Match the indentation of the surrounding reset statements.

- [ ] **Step 3: Add the Commands wrapper declaration**

  In `sdata_core-commands.ads`, look for the section of `Execute_OPTIONS_*` declarations (e.g., `Execute_OPTIONS_Shell_Timeout`). Add immediately after the last `Execute_OPTIONS_*` declaration:

  ```ada
     ----------------------------------------------------------------
     --  OPTIONS JOIN_WARN_THRESHOLD — set the per-BY-group product
     --  threshold above which /JOIN merges emit a warning.  Value 0
     --  disables the warning entirely.
     procedure Execute_OPTIONS_Join_Warn_Threshold (Value : Natural);
  ```

- [ ] **Step 4: Add the Commands wrapper body**

  In `sdata_core-commands.adb`, alongside the other `Execute_OPTIONS_*` bodies, add:

  ```ada
  procedure Execute_OPTIONS_Join_Warn_Threshold (Value : Natural) is
  begin
     SData_Core.Config.Runtime.Options_Join_Warn_Threshold := Value;
  end Execute_OPTIONS_Join_Warn_Threshold;
  ```

- [ ] **Step 5: Build sdata-core, sdata, and data-vandal**

  ```bash
  cd /home/jries/Develop/sdata-core && alr build && \
  cd /home/jries/Develop/sdata && make check && \
  cd /home/jries/Develop/data-vandal && make check
  ```

  Expected: all succeed; baseline test counts unchanged.

- [ ] **Step 6: Commit (sdata-core)**

  ```bash
  cd /home/jries/Develop/sdata-core
  git add src/sdata_core-config-runtime.ads src/sdata_core-config-runtime.adb \
          src/sdata_core-commands.ads src/sdata_core-commands.adb
  git commit -m "$(cat <<'EOF'
  feat(options): add JOIN_WARN_THRESHOLD runtime option

  Threshold (default 1,000,000) above which /JOIN merges in sdata emit
  a per-BY-group warning to flag runaway Cartesian products. Value 0
  disables the warning. Additive — no existing API impact.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Phase 1: SData.Transient_Table package

A new sdata-only package providing an in-memory table value type for the per-input intermediates used during merge. Independent of `SData_Core.Table` (which is a singleton).

### Task 3: Create `SData.Transient_Table` package — basic ops + snapshot/install

**Files:**
- Create: `/home/jries/Develop/sdata/src/sdata-transient_table.ads`
- Create: `/home/jries/Develop/sdata/src/sdata-transient_table.adb`
- Modify: `/home/jries/Develop/sdata/tests/sdata_unit_test.adb` (add new test cases)

- [ ] **Step 1: Write the failing unit tests**

  In `tests/sdata_unit_test.adb`, add a new test section near the end of the test list (before the run-tests-and-report block). Use the existing project unit-test framework conventions — look at any existing test in that file for the assertion macro / convention used. The tests should cover:

  ```ada
  --  --- SData.Transient_Table tests ---

  --  Test: empty table has zero columns and rows
  declare
     T : SData.Transient_Table.Table;
  begin
     Assert (T.Column_Count = 0, "Empty table column count");
     Assert (T.Row_Count = 0, "Empty table row count");
  end;

  --  Test: Add_Column creates a column with the named type
  declare
     T : SData.Transient_Table.Table;
  begin
     T.Add_Column ("X", SData_Core.Table.Col_Numeric);
     Assert (T.Column_Count = 1, "After Add_Column count = 1");
     Assert (T.Has_Column ("X"), "Has_Column finds added column");
     Assert (T.Has_Column ("x"), "Has_Column is case-insensitive");
     Assert (T.Get_Column_Type ("X") = SData_Core.Table.Col_Numeric,
             "Column type preserved");
  end;

  --  Test: Add_Row + Set_Value + Get_Value round-trip
  declare
     T : SData.Transient_Table.Table;
     V : SData_Core.Values.Value;
  begin
     T.Add_Column ("X", SData_Core.Table.Col_Integer);
     T.Add_Row;
     T.Set_Value (1, "X", SData_Core.Values.From_Integer (42));
     V := T.Get_Value (1, "X");
     Assert (V.Kind = SData_Core.Values.Kind_Integer
             and then SData_Core.Values.To_Integer (V) = 42,
             "Value round-trip");
  end;

  --  Test: Snapshot_From_Current copies the current SData_Core.Table
  declare
     T : SData.Transient_Table.Table;
  begin
     SData_Core.Table.Clear;
     SData_Core.Table.Add_Column ("Y", SData_Core.Table.Col_String);
     SData_Core.Table.Add_Row;
     SData_Core.Table.Set_Value (1, "Y",
        SData_Core.Values.From_String ("hello"));
     T := SData.Transient_Table.Snapshot_From_Current;
     Assert (T.Column_Count = 1 and T.Row_Count = 1,
             "Snapshot shape matches");
     Assert (SData_Core.Values.To_String (T.Get_Value (1, "Y")) = "hello",
             "Snapshot value matches");
  end;

  --  Test: Install_To_Current replaces the current table
  declare
     T : SData.Transient_Table.Table;
  begin
     T.Add_Column ("Z", SData_Core.Table.Col_Numeric);
     T.Add_Row;
     T.Set_Value (1, "Z", SData_Core.Values.From_Float (3.14));
     SData_Core.Table.Clear;
     SData.Transient_Table.Install_To_Current (T);
     Assert (SData_Core.Table.Column_Count = 1
             and SData_Core.Table.Row_Count = 1,
             "Install_To_Current shape");
     Assert (SData_Core.Values.To_Float
                (SData_Core.Table.Get_Value (1, "Z")) = 3.14,
             "Install_To_Current value");
  end;
  ```

  Use the actual Values constructor/accessor names you find by reading `sdata_core-values.ads`. The names above (`From_Integer`, `From_Float`, `From_String`, `To_Integer`, `To_Float`, `To_String`, `Kind_Integer`) are the expected pattern; substitute the real ones if they differ.

- [ ] **Step 2: Run the unit tests to verify they fail to compile**

  ```bash
  cd /home/jries/Develop/sdata && make build
  ```

  Expected: compilation fails because `SData.Transient_Table` does not yet exist.

- [ ] **Step 3: Write the package spec**

  Create `src/sdata-transient_table.ads`:

  ```ada
  --  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
  --  License: GNU General Public License v3 or later
  --  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

  --  SData.Transient_Table — an in-memory table value type used by sdata's
  --  merge orchestration to hold per-input intermediates. Independent of
  --  SData_Core.Table (which is a singleton). Operations on a transient
  --  table do not touch the global SData_Core.Table state.

  with Ada.Containers.Vectors;
  with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
  with SData_Core.Table;
  with SData_Core.Values;

  package SData.Transient_Table is

     type Table is tagged limited private;

     --  Schema --------------------------------------------------------

     procedure Add_Column
       (T : in out Table;
        Name : String;
        Col_Type : SData_Core.Table.Column_Type);

     function Has_Column (T : Table; Name : String) return Boolean;
     function Column_Count (T : Table) return Natural;
     function Column_Name (T : Table; I : Positive) return String;
     function Get_Column_Type
       (T : Table; Name : String) return SData_Core.Table.Column_Type;

     --  Rows ----------------------------------------------------------

     procedure Add_Row (T : in out Table);
     function Row_Count (T : Table) return Natural;

     function Get_Value
       (T : Table; Row : Positive; Col : String)
       return SData_Core.Values.Value;
     procedure Set_Value
       (T : in out Table;
        Row : Positive;
        Col : String;
        Val : SData_Core.Values.Value);

     --  Snapshot bridges to/from the singleton SData_Core.Table -------

     --  Capture the current state of the global SData_Core.Table into
     --  a new Transient_Table value. Does not modify the global state.
     function Snapshot_From_Current return Table;

     --  Replace the global SData_Core.Table state with the contents of
     --  the given Transient_Table. The global table is Clear-ed first.
     procedure Install_To_Current (T : Table);

  private
     type Col_Entry is record
        Name : Unbounded_String;
        Typ  : SData_Core.Table.Column_Type;
     end record;
     package Col_Vectors is new Ada.Containers.Vectors
       (Index_Type => Positive, Element_Type => Col_Entry);

     package Value_Vectors is new Ada.Containers.Vectors
       (Index_Type => Positive, Element_Type => SData_Core.Values.Value);
     package Column_Data_Vectors is new Ada.Containers.Vectors
       (Index_Type => Positive, Element_Type => Value_Vectors.Vector,
        "=" => Value_Vectors."=");

     type Table is tagged limited record
        Cols    : Col_Vectors.Vector;
        Data    : Column_Data_Vectors.Vector;   --  one inner vector per column
        N_Rows  : Natural := 0;
     end record;

  end SData.Transient_Table;
  ```

- [ ] **Step 4: Write the package body**

  Create `src/sdata-transient_table.adb`:

  ```ada
  --  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
  --  License: GNU General Public License v3 or later

  with Ada.Characters.Handling; use Ada.Characters.Handling;

  package body SData.Transient_Table is

     function Column_Index_Upper
       (T : Table; Upper_Name : String) return Natural
     is
     begin
        for I in 1 .. Natural (T.Cols.Length) loop
           if To_Upper (To_String (T.Cols (I).Name)) = Upper_Name then
              return I;
           end if;
        end loop;
        return 0;
     end Column_Index_Upper;

     procedure Add_Column
       (T : in out Table;
        Name : String;
        Col_Type : SData_Core.Table.Column_Type)
     is
        Empty : Value_Vectors.Vector;
     begin
        if Column_Index_Upper (T, To_Upper (Name)) /= 0 then
           raise Constraint_Error
              with "Transient_Table.Add_Column: duplicate name " & Name;
        end if;
        T.Cols.Append ((Name => To_Unbounded_String (Name), Typ => Col_Type));
        --  Pre-fill with missing values up to current row count
        for R in 1 .. T.N_Rows loop
           Empty.Append (SData_Core.Values.Missing_Value);
        end loop;
        T.Data.Append (Empty);
     end Add_Column;

     function Has_Column (T : Table; Name : String) return Boolean is
     begin
        return Column_Index_Upper (T, To_Upper (Name)) /= 0;
     end Has_Column;

     function Column_Count (T : Table) return Natural is
     begin
        return Natural (T.Cols.Length);
     end Column_Count;

     function Column_Name (T : Table; I : Positive) return String is
     begin
        return To_String (T.Cols (I).Name);
     end Column_Name;

     function Get_Column_Type
       (T : Table; Name : String) return SData_Core.Table.Column_Type
     is
        Idx : constant Natural := Column_Index_Upper (T, To_Upper (Name));
     begin
        if Idx = 0 then
           raise Constraint_Error
              with "Transient_Table.Get_Column_Type: not found " & Name;
        end if;
        return T.Cols (Idx).Typ;
     end Get_Column_Type;

     procedure Add_Row (T : in out Table) is
     begin
        T.N_Rows := T.N_Rows + 1;
        for I in 1 .. Natural (T.Data.Length) loop
           T.Data (I).Append (SData_Core.Values.Missing_Value);
        end loop;
     end Add_Row;

     function Row_Count (T : Table) return Natural is
     begin
        return T.N_Rows;
     end Row_Count;

     function Get_Value
       (T : Table; Row : Positive; Col : String)
       return SData_Core.Values.Value
     is
        Idx : constant Natural := Column_Index_Upper (T, To_Upper (Col));
     begin
        if Idx = 0 then
           raise Constraint_Error
              with "Transient_Table.Get_Value: column not found: " & Col;
        end if;
        return T.Data (Idx).Element (Row);
     end Get_Value;

     procedure Set_Value
       (T : in out Table;
        Row : Positive;
        Col : String;
        Val : SData_Core.Values.Value)
     is
        Idx : constant Natural := Column_Index_Upper (T, To_Upper (Col));
     begin
        if Idx = 0 then
           raise Constraint_Error
              with "Transient_Table.Set_Value: column not found: " & Col;
        end if;
        T.Data (Idx).Replace_Element (Row, Val);
     end Set_Value;

     function Snapshot_From_Current return Table is
        Result : Table;
        N      : constant Natural := SData_Core.Table.Column_Count;
        Rows   : constant Natural := SData_Core.Table.Row_Count;
     begin
        for I in 1 .. N loop
           declare
              Name : constant String := SData_Core.Table.Column_Name (I);
           begin
              Result.Add_Column
                (Name, SData_Core.Table.Get_Column_Type (Name));
           end;
        end loop;
        for R in 1 .. Rows loop
           Result.Add_Row;
           for I in 1 .. N loop
              declare
                 Name : constant String := SData_Core.Table.Column_Name (I);
              begin
                 Result.Set_Value
                   (R, Name, SData_Core.Table.Get_Value (R, Name));
              end;
           end loop;
        end loop;
        return Result;
     end Snapshot_From_Current;

     procedure Install_To_Current (T : Table) is
     begin
        SData_Core.Table.Clear;
        for I in 1 .. Column_Count (T) loop
           SData_Core.Table.Add_Column
             (Column_Name (T, I), T.Cols (I).Typ);
        end loop;
        for R in 1 .. T.N_Rows loop
           SData_Core.Table.Add_Row;
           for I in 1 .. Column_Count (T) loop
              declare
                 Name : constant String := Column_Name (T, I);
              begin
                 SData_Core.Table.Set_Value
                   (R, Name, T.Data (I).Element (R));
              end;
           end loop;
        end loop;
     end Install_To_Current;

  end SData.Transient_Table;
  ```

  Notes on the body:
  - Uses `SData_Core.Values.Missing_Value` as the missing constant. If the actual constant has a different name (e.g., `Val_Missing` or a function `Missing`), substitute when implementing. Check `sdata_core-values.ads`.
  - All column lookups are case-insensitive (upper-cased internally) to match `SData_Core.Table` semantics.

- [ ] **Step 5: Build and verify the unit tests pass**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: build succeeds; new unit tests pass; existing 140 integration tests continue to pass; existing unit tests continue to pass.

- [ ] **Step 6: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/sdata-transient_table.ads src/sdata-transient_table.adb \
          tests/sdata_unit_test.adb
  git commit -m "$(cat <<'EOF'
  feat(merge): add SData.Transient_Table package

  In-memory table value type used by the upcoming multi-dataset USE merge
  orchestration to hold per-input intermediates. Includes snapshot bridges
  to/from the singleton SData_Core.Table. Unit tests in sdata_unit_test.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

### Task 4: Add column-projection helpers to `SData.Transient_Table`

Apply_Keep / Apply_Drop / Apply_Rename / Sort_By, mirroring the standalone-command semantics but operating on a transient table value.

**Files:**
- Modify: `/home/jries/Develop/sdata/src/sdata-transient_table.ads`
- Modify: `/home/jries/Develop/sdata/src/sdata-transient_table.adb`
- Modify: `/home/jries/Develop/sdata/tests/sdata_unit_test.adb` (add test cases)

- [ ] **Step 1: Write failing tests**

  Add to `tests/sdata_unit_test.adb` (in the SData.Transient_Table section):

  ```ada
  --  Test: Apply_Keep drops non-listed columns
  declare
     T : SData.Transient_Table.Table;
     V : SData.Transient_Table.Name_Vectors.Vector;
  begin
     T.Add_Column ("A", SData_Core.Table.Col_Integer);
     T.Add_Column ("B", SData_Core.Table.Col_String);
     T.Add_Column ("C", SData_Core.Table.Col_Numeric);
     T.Add_Row;
     V.Append (To_Unbounded_String ("A"));
     V.Append (To_Unbounded_String ("C"));
     T.Apply_Keep (V);
     Assert (T.Column_Count = 2 and T.Has_Column ("A") and T.Has_Column ("C")
             and not T.Has_Column ("B"), "Apply_Keep");
  end;

  --  Test: Apply_Drop removes listed columns
  declare
     T : SData.Transient_Table.Table;
     V : SData.Transient_Table.Name_Vectors.Vector;
  begin
     T.Add_Column ("A", SData_Core.Table.Col_Integer);
     T.Add_Column ("B", SData_Core.Table.Col_String);
     V.Append (To_Unbounded_String ("A"));
     T.Apply_Drop (V);
     Assert (T.Column_Count = 1 and T.Has_Column ("B")
             and not T.Has_Column ("A"), "Apply_Drop");
  end;

  --  Test: Apply_Rename performs simultaneous rename (a=b, b=c chain)
  declare
     T : SData.Transient_Table.Table;
     R : SData.Transient_Table.Rename_Map_Vectors.Vector;
  begin
     T.Add_Column ("A", SData_Core.Table.Col_Integer);
     T.Add_Column ("B", SData_Core.Table.Col_String);
     R.Append ((Old_Name => To_Unbounded_String ("A"),
                New_Name => To_Unbounded_String ("B")));
     R.Append ((Old_Name => To_Unbounded_String ("B"),
                New_Name => To_Unbounded_String ("C")));
     T.Apply_Rename (R);
     Assert (T.Column_Count = 2 and T.Has_Column ("B") and T.Has_Column ("C")
             and not T.Has_Column ("A"), "Apply_Rename chain");
  end;

  --  Test: Apply_Rename detects duplicate source error
  declare
     T : SData.Transient_Table.Table;
     R : SData.Transient_Table.Rename_Map_Vectors.Vector;
  begin
     T.Add_Column ("A", SData_Core.Table.Col_Integer);
     R.Append ((To_Unbounded_String ("A"), To_Unbounded_String ("B")));
     R.Append ((To_Unbounded_String ("A"), To_Unbounded_String ("C")));
     begin
        T.Apply_Rename (R);
        Assert (False, "Apply_Rename duplicate source should have raised");
     exception
        when SData.Transient_Table.Rename_Error => null;
     end;
  end;

  --  Test: Sort_By orders rows by named column ascending
  declare
     T : SData.Transient_Table.Table;
     V : SData.Transient_Table.Name_Vectors.Vector;
  begin
     T.Add_Column ("K", SData_Core.Table.Col_Integer);
     for I in 1 .. 3 loop
        T.Add_Row;
     end loop;
     T.Set_Value (1, "K", SData_Core.Values.From_Integer (3));
     T.Set_Value (2, "K", SData_Core.Values.From_Integer (1));
     T.Set_Value (3, "K", SData_Core.Values.From_Integer (2));
     V.Append (To_Unbounded_String ("K"));
     T.Sort_By (V);
     Assert (SData_Core.Values.To_Integer (T.Get_Value (1, "K")) = 1
             and SData_Core.Values.To_Integer (T.Get_Value (2, "K")) = 2
             and SData_Core.Values.To_Integer (T.Get_Value (3, "K")) = 3,
             "Sort_By ascending");
  end;
  ```

- [ ] **Step 2: Extend the package spec**

  Append to `src/sdata-transient_table.ads` (before `private`):

  ```ada
     --  Column projection / mutation ----------------------------------

     package Name_Vectors is new Ada.Containers.Vectors
       (Index_Type => Positive, Element_Type => Unbounded_String);

     type Rename_Pair is record
        Old_Name : Unbounded_String;
        New_Name : Unbounded_String;
     end record;
     package Rename_Map_Vectors is new Ada.Containers.Vectors
       (Index_Type => Positive, Element_Type => Rename_Pair);

     --  Keep only the listed columns (case-insensitive match). Names not
     --  present in the table are silently ignored (matches the standalone
     --  KEEP command semantics).
     procedure Apply_Keep
       (T : in out Table; Names : Name_Vectors.Vector);

     --  Drop the listed columns. Names not present are silently ignored.
     procedure Apply_Drop
       (T : in out Table; Names : Name_Vectors.Vector);

     --  Apply a set of rename pairs simultaneously (all renames are
     --  evaluated against the original names). Raises Rename_Error if
     --  any pair has a duplicate source name, any pair has a duplicate
     --  target name, or a target name collides with an existing
     --  non-renamed column.
     procedure Apply_Rename
       (T : in out Table; Pairs : Rename_Map_Vectors.Vector);

     --  Sort rows ascending by the named columns (lexicographic on the
     --  composite key). Names that do not exist in the table are
     --  silently treated as constant — sorting proceeds on remaining
     --  keys (consistent with the existing SData_Core.Table.Sort
     --  behavior for missing keys; verify against that code when
     --  implementing if unsure).
     procedure Sort_By
       (T : in out Table; Keys : Name_Vectors.Vector);

     Rename_Error : exception;
  ```

  Add `with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;` to the spec's context clause if not already present (it is, from Task 3).

- [ ] **Step 3: Extend the package body**

  Append to `src/sdata-transient_table.adb`:

  ```ada
     procedure Apply_Keep
       (T : in out Table; Names : Name_Vectors.Vector)
     is
        package U is new Ada.Containers.Indefinite_Hashed_Sets
          (Element_Type => String,
           Hash => Ada.Strings.Hash,
           Equivalent_Elements => "=");
        Keep_Set : U.Set;
     begin
        for N of Names loop
           Keep_Set.Include (To_Upper (To_String (N)));
        end loop;
        --  Iterate column list right-to-left, drop those NOT in keep set
        for I in reverse 1 .. Natural (T.Cols.Length) loop
           if not Keep_Set.Contains
                    (To_Upper (To_String (T.Cols (I).Name)))
           then
              T.Cols.Delete (I);
              T.Data.Delete (I);
           end if;
        end loop;
     end Apply_Keep;

     procedure Apply_Drop
       (T : in out Table; Names : Name_Vectors.Vector)
     is
     begin
        for N of Names loop
           declare
              Idx : constant Natural :=
                 Column_Index_Upper (T, To_Upper (To_String (N)));
           begin
              if Idx /= 0 then
                 T.Cols.Delete (Idx);
                 T.Data.Delete (Idx);
              end if;
           end;
        end loop;
     end Apply_Drop;

     procedure Apply_Rename
       (T : in out Table; Pairs : Rename_Map_Vectors.Vector)
     is
        package U is new Ada.Containers.Indefinite_Hashed_Sets
          (Element_Type => String,
           Hash => Ada.Strings.Hash,
           Equivalent_Elements => "=");
        Seen_Old : U.Set;
        Seen_New : U.Set;
     begin
        --  Validate: no duplicate sources, no duplicate targets, no target
        --  collision with an existing non-renamed column.
        for P of Pairs loop
           if Seen_Old.Contains (To_Upper (To_String (P.Old_Name))) then
              raise Rename_Error
                 with "duplicate RENAME source: " & To_String (P.Old_Name);
           end if;
           Seen_Old.Include (To_Upper (To_String (P.Old_Name)));
           if Seen_New.Contains (To_Upper (To_String (P.New_Name))) then
              raise Rename_Error
                 with "duplicate RENAME target: " & To_String (P.New_Name);
           end if;
           Seen_New.Include (To_Upper (To_String (P.New_Name)));
        end loop;
        for I in 1 .. Natural (T.Cols.Length) loop
           declare
              Cur_Up : constant String :=
                 To_Upper (To_String (T.Cols (I).Name));
           begin
              if Seen_New.Contains (Cur_Up)
                 and then not Seen_Old.Contains (Cur_Up)
              then
                 raise Rename_Error
                    with "RENAME target collides with existing column: "
                       & To_String (T.Cols (I).Name);
              end if;
           end;
        end loop;
        --  Apply: replace column names whose original matches a pair's source.
        for I in 1 .. Natural (T.Cols.Length) loop
           declare
              Cur_Up : constant String :=
                 To_Upper (To_String (T.Cols (I).Name));
           begin
              for P of Pairs loop
                 if To_Upper (To_String (P.Old_Name)) = Cur_Up then
                    T.Cols (I).Name := P.New_Name;
                    exit;
                 end if;
              end loop;
           end;
        end loop;
     end Apply_Rename;

     procedure Sort_By
       (T : in out Table; Keys : Name_Vectors.Vector)
     is
        --  Build an index permutation by stable-sorting row indices.
        type Idx_Array is array (Positive range <>) of Positive;
        Perm : Idx_Array (1 .. T.N_Rows);

        function Less (A, B : Positive) return Boolean is
        begin
           for K of Keys loop
              declare
                 Idx : constant Natural :=
                    Column_Index_Upper (T, To_Upper (To_String (K)));
                 VA, VB : SData_Core.Values.Value;
              begin
                 if Idx = 0 then
                    --  Skip non-existent key
                    null;
                 else
                    VA := T.Data (Idx).Element (A);
                    VB := T.Data (Idx).Element (B);
                    if SData_Core.Values.Compare (VA, VB) < 0 then
                       return True;
                    elsif SData_Core.Values.Compare (VA, VB) > 0 then
                       return False;
                    end if;
                 end if;
              end;
           end loop;
           return A < B;  --  stable fallback on original order
        end Less;

        procedure Swap (I, J : Positive) is
           Tmp : constant Positive := Perm (I);
        begin
           Perm (I) := Perm (J);
           Perm (J) := Tmp;
        end Swap;

        procedure Insertion_Sort is
           --  Use a simple insertion sort; row counts in transient tables
           --  are bounded by the input dataset size and a single
           --  Algorithms_Sort would require comparator instantiation. For
           --  larger tables, replace with Generic_Sort or similar.
        begin
           for I in 2 .. T.N_Rows loop
              declare
                 J : Positive := I;
              begin
                 while J > 1 and then Less (Perm (J), Perm (J - 1)) loop
                    Swap (J - 1, J);
                    J := J - 1;
                 end loop;
              end;
           end loop;
        end Insertion_Sort;

     begin
        if T.N_Rows < 2 then
           return;
        end if;
        for I in Perm'Range loop
           Perm (I) := I;
        end loop;
        Insertion_Sort;
        --  Materialize the permutation: build new Data vectors in the
        --  permuted order, replace.
        declare
           New_Data : Column_Data_Vectors.Vector;
        begin
           for C in 1 .. Natural (T.Data.Length) loop
              declare
                 V : Value_Vectors.Vector;
              begin
                 for I in 1 .. T.N_Rows loop
                    V.Append (T.Data (C).Element (Perm (I)));
                 end loop;
                 New_Data.Append (V);
              end;
           end loop;
           T.Data := New_Data;
        end;
     end Sort_By;
  ```

  Notes:
  - Add `with Ada.Containers.Indefinite_Hashed_Sets;`, `with Ada.Strings.Hash;` to the body's context clause if not already present.
  - `SData_Core.Values.Compare` is assumed to return `-1 | 0 | +1`. Check `sdata_core-values.ads`; if the API differs (e.g., a `<` operator instead), use that and adapt.
  - The insertion sort is intentionally simple; sort time on transient tables in the merge path is dominated by the larger I/O cost. If profiling later shows sort to be a bottleneck, replace with `Ada.Containers.Generic_Array_Sort` over `Perm`.

- [ ] **Step 4: Build and verify tests pass**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: all unit tests including the new ones pass; all 140 integration tests pass.

- [ ] **Step 5: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/sdata-transient_table.ads src/sdata-transient_table.adb \
          tests/sdata_unit_test.adb
  git commit -m "$(cat <<'EOF'
  feat(merge): add Apply_Keep / Apply_Drop / Apply_Rename / Sort_By

  Column projection and sort helpers on the transient table, mirroring
  the standalone KEEP / DROP / RENAME / SORT command semantics. Apply_Rename
  is simultaneous (all pairs evaluated against original names) and rejects
  duplicate sources, duplicate targets, and target-collides-with-existing.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Phase 2: Lexer + AST extensions

### Task 5: Add new tokens to the lexer

**Files:**
- Modify: `/home/jries/Develop/sdata/src/lexer/sdata-lexer.ads`
- Modify: `/home/jries/Develop/sdata/src/lexer/sdata-lexer.adb`

- [ ] **Step 1: Add token kinds**

  In `sdata-lexer.ads`, find the `Token_Kind` enum (around lines 14-39). Add immediately before the closing parenthesis (so they keep enum-order conventions):

  ```ada
        Token_INTERLEAVE,
        Token_JOIN,
        Token_IN,
        Token_AS,
  ```

  Place these alongside related dataset/merge tokens (e.g., near `Token_BY`).

- [ ] **Step 2: Add keyword recognition**

  In `sdata-lexer.adb`, find the case-insensitive `Upper = "KEYWORD"` chain that maps an uppercased identifier to a Token_Kind (around lines 245-280, near `Token_USE`, `Token_BY`, `Token_RENAME`). Add four new clauses, placing them in alphabetical order relative to the existing entries:

  ```ada
        elsif Upper = "AS" then
           return Token_AS;
        elsif Upper = "IN" then
           return Token_IN;
        elsif Upper = "INTERLEAVE" then
           return Token_INTERLEAVE;
        elsif Upper = "JOIN" then
           return Token_JOIN;
  ```

  Note: These are *unconditional* keyword matches at the lexer level. The parser is responsible for tolerating these as identifiers outside dataset-spec contexts (this matches existing practice for `USE`, `BY`, etc., which are also unconditional keywords but treated contextually).

- [ ] **Step 3: Build to verify the lexer changes compile**

  ```bash
  cd /home/jries/Develop/sdata && make build
  ```

  Expected: build succeeds (possibly with parser warnings about unhandled tokens, which is fine for now — the parser does not yet need to do anything with them).

- [ ] **Step 4: Run existing tests**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: all 140 integration tests + unit tests pass. New tokens do not yet appear in any input so they do not affect behavior. Any existing test that incidentally uses a variable named `AS`, `IN`, `INTERLEAVE`, or `JOIN` will break and must be either renamed in the test (preferred — these are now keywords) or worked around. Inspect any failure carefully before changing tests.

- [ ] **Step 5: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/lexer/sdata-lexer.ads src/lexer/sdata-lexer.adb
  git commit -m "$(cat <<'EOF'
  feat(lexer): add INTERLEAVE / JOIN / IN / AS tokens

  New keywords used by the upcoming multi-dataset USE and multi-target SAVE
  grammar. Recognised unconditionally at the lexer level; the parser will
  treat them contextually within USE/SAVE statements.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

### Task 6: Extend the AST with Dataset_Spec, Save_Spec, and multi-spec statement variants

**Files:**
- Modify: `/home/jries/Develop/sdata/src/ast/sdata-ast.ads`
- Modify: `/home/jries/Develop/sdata/src/ast/sdata-ast.adb`

The current `Stmt_USE | Stmt_SAVE | ...` variant carries fields for a single file. We need to add new structures for the multi-dataset / multi-target case while keeping the existing fields for backward compatibility with the single-spec path.

- [ ] **Step 1: Add the Dataset_Spec / Save_Spec record types**

  In `sdata-ast.ads`, near the top of the package (before `Statement_Kind`), add:

  ```ada
     --  Shared by Dataset_Spec and Save_Spec: per-element option payload.
     --  Empty Vars list means "not specified". RENAME pairs use the
     --  existing Rename_List type.
     type Spec_Options is record
        Format_Specified : Boolean := False;
        Fmt_Override     : SData_Core.Config.Format_Type :=
                              SData_Core.Config.CSV;
        Header_Specified : Boolean := False;
        Header_Val       : Boolean := True;
        Charset_Val      : String (1 .. Max_Charset_Len) := (others => ' ');
        Charset_Len      : Natural := 0;
        DLM_Val          : String (1 .. Max_Delimiter_Len) := (others => ' ');
        DLM_Len          : Natural := 0;
        NSCAN_Val        : Natural := 0;   --  USE only
        Skip_Val         : Natural := 0;   --  USE only
        Maxrows_Val      : Natural := 0;   --  USE only
        Sheet_Name       : String (1 .. Max_Sheet_Name_Len) :=
                              (others => ' ');
        Sheet_Name_Len   : Natural := 0;
        Keep_Vars        : Variable_List;        --  null = not specified
        Drop_Vars        : Variable_List;
        Rename_Pairs     : Rename_List;
        IN_Name          : String (1 .. Max_Name_Len) := (others => ' ');
        IN_Name_Len      : Natural := 0;          --  USE only; 0 = not set
        IF_Expr          : Expression_Access;     --  SAVE only; null = not set
     end record;

     type Dataset_Spec is record
        File_Path     : String (1 .. Max_Path_Len) := (others => ' ');
        File_Len      : Natural := 0;
        Is_Mock       : Boolean := False;
        Alias         : String (1 .. Max_Name_Len) := (others => ' ');
        Alias_Len     : Natural := 0;             --  0 = no alias
        Opts          : Spec_Options;
     end record;
     type Dataset_Spec_Access is access all Dataset_Spec;

     package Dataset_Spec_Vectors is new Ada.Containers.Vectors
       (Index_Type => Positive, Element_Type => Dataset_Spec_Access);

     type Save_Spec is record
        File_Path     : String (1 .. Max_Path_Len) := (others => ' ');
        File_Len      : Natural := 0;
        Alias         : String (1 .. Max_Name_Len) := (others => ' ');
        Alias_Len     : Natural := 0;             --  0 = no alias
        Opts          : Spec_Options;
     end record;
     type Save_Spec_Access is access all Save_Spec;

     package Save_Spec_Vectors is new Ada.Containers.Vectors
       (Index_Type => Positive, Element_Type => Save_Spec_Access);

     type Merge_Mode is (MM_Single, MM_Positional, MM_Match,
                         MM_Interleave, MM_Join);
  ```

  Add `with Ada.Containers.Vectors;` to the spec's context clause if not already present.

- [ ] **Step 2: Extend the USE/SAVE statement variant**

  In `sdata-ast.ads`, find the `Stmt_USE | Stmt_SAVE | ...` variant arm (line 118). Add three new fields after the existing ones, before the `when Stmt_REPEAT =>` arm:

  ```ada
           --  --- Multi-dataset extensions (USE) and multi-target (SAVE) ---
           --  When Dataset_List is non-empty, the parser used the new
           --  multi-dataset USE grammar; Execute_USE should iterate it.
           --  When empty, fall back to the legacy single-file fields above.
           Dataset_List   : Dataset_Spec_Vectors.Vector;
           --  Whole-statement options for multi-dataset USE.
           By_Vars        : Variable_List;
           Mode           : Merge_Mode := MM_Single;
           --  When Save_List is non-empty, the parser used the new
           --  multi-target SAVE grammar; Execute_SAVE iterates it.
           --  When empty, fall back to the legacy single-file fields.
           Save_List      : Save_Spec_Vectors.Vector;
  ```

- [ ] **Step 3: Extend the WRITE statement variant**

  In `sdata-ast.ads`, locate the `case Kind is` block. Add a new variant arm just before `when others =>`:

  ```ada
        when Stmt_WRITE =>
           --  Empty Write_Targets = legacy bare WRITE (write to all
           --  registered SAVE targets). Non-empty = route only to these.
           Write_Targets : Variable_List;
  ```

- [ ] **Step 4: Extend `Free_Program` to release new heap-allocated members**

  In `sdata-ast.adb`, find `Free_Program` (and any helper it uses to free a single `Statement`). Add cleanup for:
  - Each `Dataset_Spec_Access` in `Dataset_List` (free the spec; free its `Opts.Keep_Vars`, `Opts.Drop_Vars`, `Opts.Rename_Pairs`, `Opts.IF_Expr` if non-null — though IF_Expr is SAVE-side, harmless to check).
  - Each `Save_Spec_Access` in `Save_List` (same cleanup).
  - The `By_Vars` and `Write_Targets` lists if non-null.

  Follow the pattern already in `Free_Program` for `Vars`, `Rename_Pairs`, etc.

- [ ] **Step 5: Build to verify**

  ```bash
  cd /home/jries/Develop/sdata && make build
  ```

  Expected: build succeeds. New fields default to empty/null so existing parser/executor code that doesn't reference them is unaffected.

- [ ] **Step 6: Run tests**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: all 140 + unit tests still pass. Behavior is unchanged because new fields are never populated yet.

- [ ] **Step 7: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/ast/sdata-ast.ads src/ast/sdata-ast.adb
  git commit -m "$(cat <<'EOF'
  feat(ast): add Dataset_Spec / Save_Spec / Merge_Mode for multi-spec USE/SAVE

  AST extensions for the upcoming multi-dataset USE and multi-target SAVE
  grammar. Legacy single-spec fields are preserved; new Dataset_List /
  Save_List / By_Vars / Mode / Write_Targets fields are added in parallel.
  When the lists are empty, executors fall through to the existing
  single-spec code path (back-compat).

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Phase 3: Parser

### Task 7: Add Parse_Per_Dataset_Options helper

A new parser helper that consumes a parenthesised option block of the form `(KEY=value KEY=value, ...)`. Used by both `Parse_Dataset_Spec` (Task 8) and `Parse_Save_Spec` (Task 9).

**Files:**
- Modify: `/home/jries/Develop/sdata/src/parser/sdata-parser.adb`

- [ ] **Step 1: Add the helper at the appropriate place in the parser body**

  In `sdata-parser.adb`, near the existing helpers (e.g., after `Parse_Variable_List` around line 650), add:

  ```ada
     --  Parse a parenthesised per-spec option block:
     --
     --    "(" option {, option} ")"
     --
     --  where option is one of:
     --     KEEP   = name_list
     --     DROP   = name_list
     --     RENAME = ( old=new {, old=new} )
     --     IN     = name        (USE only — ignored if Allow_IN is False)
     --     IF     = expr        (SAVE only — ignored if Allow_IF is False)
     --     FMT     = name
     --     HEADER  = YES|NO
     --     CHARSET = string
     --     DLM     = string
     --     NSCAN   = integer    (USE only — error if Allow_USE_Only is False)
     --     SKIP    = integer    (USE only — error if Allow_USE_Only is False)
     --     MAXROWS = integer    (USE only — error if Allow_USE_Only is False)
     --     SHEET   = string
     --
     --  On entry: peeked token is Token_LParen. On exit: Token_RParen has
     --  been consumed.
     procedure Parse_Spec_Options
       (Ctx           : in out Parse_Context;
        Opts          : in out Spec_Options;
        Allow_IN      : Boolean;
        Allow_IF      : Boolean;
        Allow_USE_Only : Boolean)
     is
        Tok : Token_Type;
     begin
        Expect (Ctx, Token_LParen);  --  consumes the (
        loop
           Tok := Next_Token (Ctx);
           case Tok.Kind is
              when Token_RParen =>
                 exit;
              when Token_KEEP =>
                 Expect (Ctx, Token_Equals);
                 Opts.Keep_Vars := Parse_Variable_List (Ctx);
              when Token_DROP =>
                 Expect (Ctx, Token_Equals);
                 Opts.Drop_Vars := Parse_Variable_List (Ctx);
              when Token_RENAME =>
                 Expect (Ctx, Token_Equals);
                 Opts.Rename_Pairs := Parse_Rename_Pairs (Ctx);
                 --  Parse_Rename_Pairs must accept an optional surrounding
                 --  paren block "(old=new, old=new)" — adapt or add this
                 --  variant if Parse_Rename_Pairs currently expects no parens.
              when Token_IN =>
                 if not Allow_IN then
                    Parse_Error (Ctx, "IN= not allowed here");
                 end if;
                 Expect (Ctx, Token_Equals);
                 declare
                    Id : constant Token_Type := Expect (Ctx, Token_Ident);
                 begin
                    Opts.IN_Name_Len := Id.Text_Len;
                    Opts.IN_Name (1 .. Id.Text_Len) :=
                       Id.Text (1 .. Id.Text_Len);
                 end;
              when Token_IF =>
                 if not Allow_IF then
                    Parse_Error (Ctx, "IF= not allowed here");
                 end if;
                 Expect (Ctx, Token_Equals);
                 Opts.IF_Expr := Parse_Expression (Ctx);
              when Token_Ident =>
                 --  Generic KEY=VALUE forms: FMT, HEADER, CHARSET, DLM,
                 --  NSCAN, SKIP, MAXROWS, SHEET.
                 declare
                    Key_Up : constant String :=
                       To_Upper (Tok.Text (1 .. Tok.Text_Len));
                 begin
                    Expect (Ctx, Token_Equals);
                    if Key_Up = "FMT" then
                       Opts.Format_Specified := True;
                       Opts.Fmt_Override := Parse_Format_Value (Ctx);
                    elsif Key_Up = "HEADER" then
                       Opts.Header_Specified := True;
                       Opts.Header_Val := Parse_Yes_No (Ctx);
                    elsif Key_Up = "CHARSET" then
                       Parse_Charset_Into
                         (Ctx, Opts.Charset_Val, Opts.Charset_Len);
                    elsif Key_Up = "DLM" then
                       Parse_String_Into
                         (Ctx, Opts.DLM_Val, Opts.DLM_Len);
                    elsif Key_Up = "SHEET" then
                       Parse_String_Into
                         (Ctx, Opts.Sheet_Name, Opts.Sheet_Name_Len);
                    elsif Key_Up = "NSCAN"
                       or else Key_Up = "SKIP"
                       or else Key_Up = "MAXROWS"
                    then
                       if not Allow_USE_Only then
                          Parse_Error
                            (Ctx, Key_Up & "= not allowed in SAVE options");
                       end if;
                       declare
                          N : constant Natural :=
                             Natural'Value (Parse_Quoted_Or_Number (Ctx));
                       begin
                          if Key_Up = "NSCAN" then
                             Opts.NSCAN_Val := N;
                          elsif Key_Up = "SKIP" then
                             Opts.Skip_Val := N;
                          else
                             Opts.Maxrows_Val := N;
                          end if;
                       end;
                    else
                       Parse_Error (Ctx, "unknown spec option: " & Key_Up);
                    end if;
                 end;
              when Token_Comma =>
                 null;  --  separator between options
              when others =>
                 Parse_Error
                   (Ctx, "unexpected token in spec option list: "
                       & Token_Kind'Image (Tok.Kind));
           end case;
        end loop;
     end Parse_Spec_Options;
  ```

  Notes:
  - `Expect`, `Next_Token`, `Parse_Error`, `Parse_Variable_List`,
    `Parse_Rename_Pairs`, `Parse_Format_Value`, `Parse_Yes_No`,
    `Parse_String_Into`, `Parse_Charset_Into`, `Parse_Quoted_Or_Number`,
    `Parse_Expression` are existing parser helpers — verify their exact
    names by inspecting the surrounding parser code and rename
    references in the snippet above to match.
  - `Parse_Rename_Pairs` currently parses the form `old=new, old=new`
    used by the standalone RENAME statement. Within the spec-options
    block we need the parenthesised form. Either: extend
    `Parse_Rename_Pairs` to accept an optional leading `(` (consume the
    `)` to match), or add a thin wrapper `Parse_Paren_Rename_Pairs`
    that asserts `Token_LParen`, calls the existing helper, asserts
    `Token_RParen`. Prefer the wrapper to avoid changing existing
    callers' behavior.
  - The "Token_Ident with Key_Up = ..." fallback is required because
    HEADER, FMT, CHARSET, etc. are not currently lexed as dedicated
    tokens — they appear as `Token_Ident`. If any of these *are*
    dedicated tokens in the lexer, extend the `case` to match them
    directly instead of falling into the `Token_Ident` branch.

- [ ] **Step 2: Compile to verify the helper parses**

  ```bash
  cd /home/jries/Develop/sdata && make build
  ```

  Expected: build succeeds; no callers of `Parse_Spec_Options` yet, so it's dead code (warning OK).

- [ ] **Step 3: Run existing tests**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: all tests still pass — the helper is unused.

- [ ] **Step 4: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/parser/sdata-parser.adb
  git commit -m "$(cat <<'EOF'
  feat(parser): add Parse_Spec_Options helper for per-spec option blocks

  Parses (KEY=value, ...) blocks used by USE dataset specs and SAVE target
  specs. Supports KEEP, DROP, RENAME, IN/IF, FMT, HEADER, CHARSET, DLM,
  NSCAN/SKIP/MAXROWS (USE), SHEET. Unused so far; wired up in subsequent
  Parse_USE / Parse_SAVE tasks.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

### Task 8: Rewrite Parse_USE for multi-dataset grammar (with back-compat)

**Files:**
- Modify: `/home/jries/Develop/sdata/src/parser/sdata-parser.adb`
- Add: `/home/jries/Develop/sdata/tests/use_merge_parse.cmd` (and `.exp`)

- [ ] **Step 1: Write a failing integration test**

  Create `tests/use_merge_parse.cmd`:

  ```
  USE tests/data/a.csv, tests/data/b.csv /BY=ID
  NAMES
  ```

  Create `tests/use_merge_parse.exp` (replace with the expected NAMES output once you know the column shapes of `a.csv` and `b.csv` — use existing data files in `tests/data/` if present, or create small ones).

  If `tests/data/a.csv` / `b.csv` don't exist, create them too — e.g.:
  - `tests/data/a.csv`:
    ```
    ID,X
    1,10
    2,20
    ```
  - `tests/data/b.csv`:
    ```
    ID,Y
    1,100
    2,200
    ```

  Then `use_merge_parse.exp` should list `ID X Y` (or whatever the NAMES command formats them as — check an existing `.exp` file alongside a `NAMES` test for the format).

- [ ] **Step 2: Run the test to verify it fails**

  ```bash
  cd /home/jries/Develop/sdata && make check 2>&1 | grep use_merge_parse
  ```

  Expected: the test fails with a parse error on the comma after `tests/data/a.csv`.

- [ ] **Step 3: Rewrite Parse_USE**

  In `sdata-parser.adb`, find `Parse_USE` (around lines 802–980 by the subagent's map; locate the exact `Stmt_USE` parsing branch). Replace its body with logic that:

  1. Parses one `Dataset_Spec`:
     - Filename token (may be a bare identifier converted to upper + .CSV, or a quoted string, or `MOCK` — current logic).
     - Optional `[sheet]` (existing bracket-sheet syntax).
     - Optional `AS alias`: if peek is `Token_AS`, consume; expect `Token_Ident`; store in `Spec.Alias`.
     - Optional `(per-dataset opts)`: if peek is `Token_LParen`, call `Parse_Spec_Options (Allow_IN => True, Allow_IF => False, Allow_USE_Only => True)`.
     - Append the spec to a local `Dataset_Spec_Vectors.Vector`.
  2. While peek is `Token_Comma`, consume it and parse the next spec.
  3. Then parse whole-statement slash-options: `BY`, `INTERLEAVE`, `JOIN` are new; the existing `FMT`, `HEADER`, `CHARSET`, `DLM`, `NSCAN`, `SKIP`, `MAXROWS` slash-options are still accepted but ONLY if exactly one dataset was parsed AND that dataset had no paren-block (back-compat path — apply them to that single dataset's `Opts`). If multiple datasets, slash-options other than `BY`/`INTERLEAVE`/`JOIN` are a parse error.
  4. Decide `Mode`:
     - 1 dataset → `MM_Single` (keep legacy single-file fields populated; leave `Dataset_List` empty)
     - >1 dataset, no `/BY` → `MM_Positional`
     - >1 dataset, `/BY` only → `MM_Match`
     - >1 dataset, `/BY` + `/INTERLEAVE` → `MM_Interleave`
     - >1 dataset, `/BY` + `/JOIN` → `MM_Join`
     - `/INTERLEAVE` + `/JOIN` together → parse error
     - `/INTERLEAVE` or `/JOIN` without `/BY` → parse error
     - 1 dataset with `/JOIN` or `/INTERLEAVE` → parse error
  5. For multi-dataset (Mode /= MM_Single): populate `Stmt.Dataset_List`, `Stmt.By_Vars`, `Stmt.Mode`; leave the legacy `File_Path` / `File_Len` / ... fields blank.
  6. For single dataset (Mode = MM_Single): populate the legacy `File_Path` / `File_Len` / option fields exactly as today, plus copy `Spec.Opts.Keep_Vars`/`Drop_Vars`/`Rename_Pairs`/`IN_Name` into the statement if any were present in a paren block (these need a place to live in MM_Single — add a tiny per-statement `Single_Spec_Opts : Spec_Options;` field to the variant in Task 6 if not already present, or fold them into the existing fields when the type matches). The simplest implementation: always populate `Stmt.Dataset_List` even for single-dataset, and have `Mode = MM_Single` mean "treat as legacy load but with a paren-block options carrier". The executor then uses the spec's Opts.

  Detailed implementation pattern (sketched; adapt to existing parser idioms):

  ```ada
  procedure Parse_USE (Ctx : in out Parse_Context; Stmt : Statement_Access) is
     Specs : Dataset_Spec_Vectors.Vector;
     Tok   : Token_Type;
     Saw_BY        : Boolean := False;
     Saw_JOIN      : Boolean := False;
     Saw_INTERLEAVE: Boolean := False;
  begin
     loop
        declare
           Spec : constant Dataset_Spec_Access := new Dataset_Spec;
        begin
           Parse_Dataset_Filename (Ctx, Spec.File_Path, Spec.File_Len,
                                   Spec.Is_Mock);
           --  Existing logic for [sheet] bracket syntax — keep it
           Parse_Optional_Sheet_Bracket (Ctx, Spec.Opts);
           --  AS alias?
           if Peek_Token (Ctx).Kind = Token_AS then
              Tok := Next_Token (Ctx);   --  consume AS
              Tok := Expect (Ctx, Token_Ident);
              Spec.Alias_Len := Tok.Text_Len;
              Spec.Alias (1 .. Tok.Text_Len) := Tok.Text (1 .. Tok.Text_Len);
           end if;
           --  Paren-block options?
           if Peek_Token (Ctx).Kind = Token_LParen then
              Parse_Spec_Options
                (Ctx, Spec.Opts,
                 Allow_IN => True, Allow_IF => False,
                 Allow_USE_Only => True);
           end if;
           Specs.Append (Spec);
        end;
        exit when Peek_Token (Ctx).Kind /= Token_Comma;
        Tok := Next_Token (Ctx);   --  consume comma
     end loop;

     --  Whole-statement slash-options loop
     while Peek_Token (Ctx).Kind = Token_Slash loop
        Tok := Next_Token (Ctx);   --  consume /
        Tok := Next_Token (Ctx);   --  the option key
        case Tok.Kind is
           when Token_BY =>
              Expect (Ctx, Token_Equals);
              Stmt.By_Vars := Parse_Variable_List (Ctx);
              Saw_BY := True;
           when Token_JOIN =>
              Saw_JOIN := True;
           when Token_INTERLEAVE =>
              Saw_INTERLEAVE := True;
           when others =>
              --  Legacy slash-options (FMT, HEADER, etc.): only allowed
              --  when there's exactly one dataset and it has no paren opts.
              if Natural (Specs.Length) /= 1
                 or else Has_Paren_Opts (Specs.First_Element.all)
              then
                 Parse_Error
                   (Ctx, "this slash-option requires a single dataset with "
                      & "no paren options block");
              end if;
              Apply_Legacy_Slash_Option
                (Ctx, Tok, Specs.First_Element.Opts);
        end case;
     end loop;

     --  Validate mode combination
     if Saw_INTERLEAVE and Saw_JOIN then
        Parse_Error (Ctx, "/INTERLEAVE and /JOIN cannot both be specified");
     end if;
     if (Saw_INTERLEAVE or Saw_JOIN) and not Saw_BY then
        Parse_Error
          (Ctx, "/INTERLEAVE and /JOIN require /BY=");
     end if;
     if Natural (Specs.Length) = 1
        and then (Saw_INTERLEAVE or Saw_JOIN)
     then
        Parse_Error
          (Ctx, "/INTERLEAVE and /JOIN require multiple datasets");
     end if;

     if Natural (Specs.Length) = 1 then
        Stmt.Mode := MM_Single;
        --  Populate legacy fields from the single spec for back-compat.
        --  Also populate Dataset_List so the executor can read the
        --  paren-block options uniformly.
        Stmt.File_Path := Specs.First_Element.File_Path;
        Stmt.File_Len  := Specs.First_Element.File_Len;
        Stmt.Is_Mock   := Specs.First_Element.Is_Mock;
        --  Copy the spec's Opts into the legacy override fields:
        Copy_Opts_To_Legacy_Use_Fields (Specs.First_Element.Opts, Stmt);
        Stmt.Dataset_List := Specs;
     else
        if Saw_INTERLEAVE then
           Stmt.Mode := MM_Interleave;
        elsif Saw_JOIN then
           Stmt.Mode := MM_Join;
        elsif Saw_BY then
           Stmt.Mode := MM_Match;
        else
           Stmt.Mode := MM_Positional;
        end if;
        Stmt.Dataset_List := Specs;
     end if;
  end Parse_USE;
  ```

  Implement `Has_Paren_Opts`, `Copy_Opts_To_Legacy_Use_Fields`,
  `Parse_Dataset_Filename`, `Parse_Optional_Sheet_Bracket`, and
  `Apply_Legacy_Slash_Option` as local helpers extracted from the
  existing `Parse_USE` body — most of their logic is already present;
  this task is reorganising not reinventing.

- [ ] **Step 4: Build and run**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: all existing 140 integration tests still pass; the new `use_merge_parse.cmd` test passes (parse succeeds and NAMES output matches `.exp`). It's OK if Execute_USE doesn't yet do the merge — at this stage we just need parsing not to error and the legacy single-dataset path to remain intact.

  If a test fails: the most common cause is that an existing test happens to use a column name `AS`, `IN`, `INTERLEAVE`, or `JOIN`. Inspect carefully — those are now keywords and the test needs renaming.

- [ ] **Step 5: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/parser/sdata-parser.adb tests/use_merge_parse.cmd tests/use_merge_parse.exp tests/data/a.csv tests/data/b.csv
  git commit -m "$(cat <<'EOF'
  feat(parser): accept multi-dataset USE syntax

  Parse USE with comma-separated dataset specs, optional per-dataset
  parenthesised options, and the whole-statement /BY= /INTERLEAVE /JOIN
  options. Single-dataset USE continues to parse unchanged via the
  legacy field path. Executor wiring lands in a later task; this commit
  is parse-only.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

### Task 9: Rewrite Parse_SAVE for multi-target grammar (with back-compat)

Same shape as Task 8, applied to SAVE.

**Files:**
- Modify: `/home/jries/Develop/sdata/src/parser/sdata-parser.adb`
- Add: `/home/jries/Develop/sdata/tests/save_multi_parse.cmd` (and `.exp`)

- [ ] **Step 1: Write a failing test**

  Create `tests/save_multi_parse.cmd`:

  ```
  REPEAT 3
  LET A = RECNO()
  SAVE tests/out/p.csv, tests/out/q.csv
  RUN
  ```

  Create `tests/save_multi_parse.exp` — record the expected stdout (likely empty, since no PRINT). After running the test will check both `tests/out/p.csv` and `tests/out/q.csv` exist with the expected contents; you'll need a small wrapper or you can use the post-run comparison conventions already in `tests/`. Look at any existing test that produces files to mirror its `.exp` style.

- [ ] **Step 2: Run to verify failure**

  Expected: parse error on the comma after the first filename.

- [ ] **Step 3: Rewrite Parse_SAVE**

  Mirror the Parse_USE structure. Each `Save_Spec` accepts:
  - Filename + optional `[sheet]` + optional `AS alias` + optional `(per-target opts)`
  - Per-target opts via `Parse_Spec_Options (Allow_IN => False, Allow_IF => True, Allow_USE_Only => False)`.

  Whole-statement slash-options for SAVE: only the legacy ones (FMT, HEADER, CHARSET, DLM, SHEET); error on `BY`, `JOIN`, `INTERLEAVE`. Same single-dataset back-compat rule (legacy slash-options OK only if exactly one target with no paren block).

  Populate `Stmt.Save_List` for multi-target; populate legacy `Stmt.File_Path` etc. for single-target.

- [ ] **Step 4: Build and verify**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: all existing tests pass; new `save_multi_parse.cmd` parses (executor wiring lands in Phase 6). If executor errors when it sees a multi-target SAVE because Execute_SAVE doesn't iterate the list yet, add a temporary check in the parser test: just run `NAMES` after `USE` without `RUN` so SAVE isn't actually executed. Adjust the test to verify the parse only, e.g.:

  ```
  USE tests/data/a.csv
  SAVE tests/out/p.csv, tests/out/q.csv
  NAMES
  ```

  The NAMES output shows the input table columns; the SAVE statement was accepted but not yet acted on. The `.exp` should just be the NAMES output.

- [ ] **Step 5: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/parser/sdata-parser.adb tests/save_multi_parse.cmd tests/save_multi_parse.exp
  git commit -m "$(cat <<'EOF'
  feat(parser): accept multi-target SAVE syntax

  Parse SAVE with comma-separated target specs, optional per-target
  parenthesised options. Single-target SAVE continues to parse unchanged
  via the legacy field path. Executor wiring lands in Phase 6.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

### Task 10: Extend Parse_WRITE for optional target list

**Files:**
- Modify: `/home/jries/Develop/sdata/src/parser/sdata-parser.adb`

- [ ] **Step 1: Locate the current Parse_WRITE**

  Around line 1275–1276 in `sdata-parser.adb` — currently a bare `Stmt := new Statement (Stmt_WRITE);` with no further parsing.

- [ ] **Step 2: Extend to optionally consume a target list**

  Replace the WRITE parse branch with:

  ```ada
  when Token_WRITE =>
     Stmt := new Statement (Stmt_WRITE);
     --  Optional target list: WRITE target [, target ...]
     if Peek_Token (Ctx).Kind = Token_Ident
        or else Peek_Token (Ctx).Kind = Token_String_Literal
     then
        Stmt.Write_Targets := Parse_Variable_List (Ctx);
     end if;
  ```

  Note: `Parse_Variable_List` handles comma-separated identifier lists; aliases and bare filenames both parse as identifiers (after the existing filename-to-uppercase convention). If quoted filenames need to be supported as targets, extend `Parse_Variable_List` or use a more tailored helper.

- [ ] **Step 3: Build and run existing tests**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: all 140 + unit tests pass. Existing `WRITE` (no-arg) tests continue to work because the new code only activates when there's a token after WRITE.

- [ ] **Step 4: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/parser/sdata-parser.adb
  git commit -m "$(cat <<'EOF'
  feat(parser): accept optional target list on WRITE statement

  WRITE [target [, target ...]] — empty target list (bare WRITE) keeps
  current semantics (write to default/all). Routing executor lands in
  Phase 6.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Phase 4: Merge combiners

### Task 11: Create SData.Merge package skeleton + Positional combiner

**Files:**
- Create: `/home/jries/Develop/sdata/src/sdata-merge.ads`
- Create: `/home/jries/Develop/sdata/src/sdata-merge.adb`
- Modify: `/home/jries/Develop/sdata/tests/sdata_unit_test.adb`

- [ ] **Step 1: Write failing unit tests for positional combine**

  Add to `tests/sdata_unit_test.adb`:

  ```ada
  --  --- SData.Merge.Combine_Positional tests ---

  --  Test: two tables, equal row counts, disjoint columns, no collisions
  declare
     use SData.Transient_Table;
     A, B, R : Table;
     V : SData_Core.Values.Value;
     Inputs : SData.Merge.Table_Vectors.Vector;
     Warnings : SData.Merge.Warning_Vectors.Vector;
  begin
     A.Add_Column ("X", SData_Core.Table.Col_Integer);
     A.Add_Row; A.Set_Value (1, "X", SData_Core.Values.From_Integer (1));
     A.Add_Row; A.Set_Value (2, "X", SData_Core.Values.From_Integer (2));
     B.Add_Column ("Y", SData_Core.Table.Col_String);
     B.Add_Row; B.Set_Value (1, "Y", SData_Core.Values.From_String ("a"));
     B.Add_Row; B.Set_Value (2, "Y", SData_Core.Values.From_String ("b"));
     Inputs.Append (A'Unchecked_Access);
     Inputs.Append (B'Unchecked_Access);
     R := SData.Merge.Combine_Positional (Inputs, Warnings);
     Assert (R.Column_Count = 2, "Positional column count");
     Assert (R.Row_Count = 2, "Positional row count");
     V := R.Get_Value (1, "X");
     Assert (SData_Core.Values.To_Integer (V) = 1, "Positional X[1]");
     V := R.Get_Value (2, "Y");
     Assert (SData_Core.Values.To_String (V) = "b", "Positional Y[2]");
     Assert (Natural (Warnings.Length) = 0, "Positional no warnings");
  end;

  --  Test: mismatched row counts — shorter side padded with missing
  declare
     use SData.Transient_Table;
     A, B, R : Table;
     Inputs : SData.Merge.Table_Vectors.Vector;
     Warnings : SData.Merge.Warning_Vectors.Vector;
  begin
     A.Add_Column ("X", SData_Core.Table.Col_Integer);
     A.Add_Row; A.Set_Value (1, "X", SData_Core.Values.From_Integer (10));
     A.Add_Row; A.Set_Value (2, "X", SData_Core.Values.From_Integer (20));
     A.Add_Row; A.Set_Value (3, "X", SData_Core.Values.From_Integer (30));
     B.Add_Column ("Y", SData_Core.Table.Col_Integer);
     B.Add_Row; B.Set_Value (1, "Y", SData_Core.Values.From_Integer (100));
     Inputs.Append (A'Unchecked_Access);
     Inputs.Append (B'Unchecked_Access);
     R := SData.Merge.Combine_Positional (Inputs, Warnings);
     Assert (R.Row_Count = 3, "Positional row count = max");
     Assert (SData_Core.Values.Is_Missing (R.Get_Value (2, "Y")),
             "Positional Y[2] padded missing");
     Assert (SData_Core.Values.Is_Missing (R.Get_Value (3, "Y")),
             "Positional Y[3] padded missing");
  end;

  --  Test: column-name collision — rightmost wins, one warning
  declare
     use SData.Transient_Table;
     A, B, R : Table;
     Inputs : SData.Merge.Table_Vectors.Vector;
     Warnings : SData.Merge.Warning_Vectors.Vector;
  begin
     A.Add_Column ("Z", SData_Core.Table.Col_Integer);
     A.Add_Row; A.Set_Value (1, "Z", SData_Core.Values.From_Integer (1));
     B.Add_Column ("Z", SData_Core.Table.Col_Integer);
     B.Add_Row; B.Set_Value (1, "Z", SData_Core.Values.From_Integer (99));
     Inputs.Append (A'Unchecked_Access);
     Inputs.Append (B'Unchecked_Access);
     R := SData.Merge.Combine_Positional (Inputs, Warnings);
     Assert (R.Column_Count = 1, "Positional collision: one column");
     Assert (SData_Core.Values.To_Integer (R.Get_Value (1, "Z")) = 99,
             "Positional collision: rightmost wins");
     Assert (Natural (Warnings.Length) = 1,
             "Positional collision: one warning");
  end;
  ```

  Note: `Table_Vectors` and `Warning_Vectors` instantiations are defined in the new package; `'Unchecked_Access` works because the tagged Table values are local and live to end of declare-block. If the type-checker rejects this for the limited tagged type, change the test to use `aliased Table` and `'Access`.

  `SData_Core.Values.Is_Missing` is assumed to exist; check `sdata_core-values.ads` and use the actual name.

- [ ] **Step 2: Verify compile failure**

  ```bash
  cd /home/jries/Develop/sdata && make build
  ```

  Expected: build fails — package SData.Merge does not exist.

- [ ] **Step 3: Create the package spec**

  Create `src/sdata-merge.ads`:

  ```ada
  --  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
  --  License: GNU General Public License v3 or later

  --  SData.Merge — pure combiner algorithms operating on transient tables.
  --  Each Combine_* function takes a vector of input transient tables and
  --  produces a single combined transient table. Warnings are emitted into
  --  the caller-supplied warning vector rather than to stderr directly, so
  --  the caller can decide on per-statement deduplication and formatting.

  with Ada.Containers.Vectors;
  with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
  with SData.Transient_Table;

  package SData.Merge is

     type Table_Access is access all SData.Transient_Table.Table;
     package Table_Vectors is new Ada.Containers.Vectors
       (Index_Type => Positive, Element_Type => Table_Access);

     package Warning_Vectors is new Ada.Containers.Vectors
       (Index_Type => Positive, Element_Type => Unbounded_String);

     --  Positional: combine by row index. Row count = max across inputs;
     --  shorter sides padded with missing. Column collisions: rightmost
     --  wins, one warning per collision.
     function Combine_Positional
       (Inputs   : Table_Vectors.Vector;
        Warnings : in out Warning_Vectors.Vector)
        return SData.Transient_Table.Table;

     --  Match merge (SAS-style full outer). Inputs MUST already be sorted
     --  by By_Vars. Row count per BY group = max across inputs; shorter
     --  sides recycle their last row. One warning per BY group where 2+
     --  inputs have >1 row for that key. Unmatched keys produce rows
     --  with missing values on absent sides.
     function Combine_Match
       (Inputs   : Table_Vectors.Vector;
        By_Vars  : SData.Transient_Table.Name_Vectors.Vector;
        Warnings : in out Warning_Vectors.Vector)
        return SData.Transient_Table.Table;

     --  Interleave: rows from inputs emitted in BY-sorted order
     --  (stream-merge of pre-sorted inputs). Row count per BY group =
     --  sum across inputs.
     function Combine_Interleave
       (Inputs   : Table_Vectors.Vector;
        By_Vars  : SData.Transient_Table.Name_Vectors.Vector;
        Warnings : in out Warning_Vectors.Vector)
        return SData.Transient_Table.Table;

     --  Cartesian inner join: row count per matched BY group =
     --  product across inputs. Unmatched keys (in any input) are
     --  dropped. One warning per group whose product exceeds
     --  SData_Core.Config.Runtime.Options_Join_Warn_Threshold (0
     --  disables).
     function Combine_Join
       (Inputs   : Table_Vectors.Vector;
        By_Vars  : SData.Transient_Table.Name_Vectors.Vector;
        Warnings : in out Warning_Vectors.Vector)
        return SData.Transient_Table.Table;

  end SData.Merge;
  ```

- [ ] **Step 4: Implement Combine_Positional**

  Create `src/sdata-merge.adb`:

  ```ada
  --  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
  --  License: GNU General Public License v3 or later

  with Ada.Characters.Handling; use Ada.Characters.Handling;
  with SData_Core.Values;

  package body SData.Merge is

     --  Build the result schema for a positional/match/join merge:
     --  columns are taken in order from each input, skipping names
     --  already present from earlier inputs. Returns the column-source
     --  map: Source(I).Table_Idx = which input contributes column I;
     --  Source(I).Col_Name = the name within that input.
     --
     --  Column collisions: when input N has a column with the same name
     --  as input M < N, the column stays at its first-occurrence
     --  position but the *source* shifts to input N (rightmost wins).
     --  A warning is emitted once per colliding name.

     type Col_Source is record
        Table_Idx : Positive;
        Col_Name  : Unbounded_String;
     end record;
     package Source_Vectors is new Ada.Containers.Vectors
       (Index_Type => Positive, Element_Type => Col_Source);

     procedure Build_Schema
       (Result    : in out SData.Transient_Table.Table;
        Sources   : in out Source_Vectors.Vector;
        Inputs    : Table_Vectors.Vector;
        Warnings  : in out Warning_Vectors.Vector)
     is
        --  Helper to find position by case-insensitive name in Result.
        function Find_Result_Col (Up : String) return Natural is
        begin
           for I in 1 .. SData.Transient_Table.Column_Count (Result) loop
              if To_Upper
                   (SData.Transient_Table.Column_Name (Result, I)) = Up
              then
                 return I;
              end if;
           end loop;
           return 0;
        end Find_Result_Col;
     begin
        for T_Idx in 1 .. Natural (Inputs.Length) loop
           declare
              T : constant Table_Access := Inputs (T_Idx);
              N : constant Natural := SData.Transient_Table.Column_Count (T.all);
           begin
              for C in 1 .. N loop
                 declare
                    Name : constant String :=
                       SData.Transient_Table.Column_Name (T.all, C);
                    Up   : constant String := To_Upper (Name);
                    Pos  : constant Natural := Find_Result_Col (Up);
                 begin
                    if Pos = 0 then
                       --  New column
                       Result.Add_Column
                         (Name,
                          SData.Transient_Table.Get_Column_Type (T.all, Name));
                       Sources.Append
                         ((Table_Idx => T_Idx,
                           Col_Name  => To_Unbounded_String (Name)));
                    else
                       --  Collision: rightmost wins; update source, warn once.
                       Warnings.Append
                         (To_Unbounded_String
                            ("column name collision: " & Name
                               & " (last dataset wins)"));
                       Sources (Pos).Table_Idx := T_Idx;
                       Sources (Pos).Col_Name :=
                          To_Unbounded_String (Name);
                    end if;
                 end;
              end loop;
           end;
        end loop;
     end Build_Schema;

     function Combine_Positional
       (Inputs   : Table_Vectors.Vector;
        Warnings : in out Warning_Vectors.Vector)
        return SData.Transient_Table.Table
     is
        Result    : SData.Transient_Table.Table;
        Sources   : Source_Vectors.Vector;
        Max_Rows  : Natural := 0;
     begin
        Build_Schema (Result, Sources, Inputs, Warnings);
        for I in 1 .. Natural (Inputs.Length) loop
           if SData.Transient_Table.Row_Count (Inputs (I).all) > Max_Rows then
              Max_Rows := SData.Transient_Table.Row_Count (Inputs (I).all);
           end if;
        end loop;
        for R in 1 .. Max_Rows loop
           Result.Add_Row;
           for C in 1 .. Natural (Sources.Length) loop
              declare
                 Src : constant Col_Source := Sources (C);
                 T   : constant Table_Access := Inputs (Src.Table_Idx);
                 V   : SData_Core.Values.Value;
              begin
                 if R <= SData.Transient_Table.Row_Count (T.all) then
                    V := T.Get_Value (R, To_String (Src.Col_Name));
                 else
                    V := SData_Core.Values.Missing_Value;
                 end if;
                 --  Use the result column's actual name (could differ
                 --  in case from Src.Col_Name; case-insensitive lookup
                 --  handles either).
                 Result.Set_Value
                   (R, SData.Transient_Table.Column_Name (Result, C), V);
              end;
           end loop;
        end loop;
        return Result;
     end Combine_Positional;

     --  Combine_Match, Combine_Interleave, Combine_Join: implemented
     --  in subsequent tasks. Stub bodies for now to allow compilation.

     function Combine_Match
       (Inputs   : Table_Vectors.Vector;
        By_Vars  : SData.Transient_Table.Name_Vectors.Vector;
        Warnings : in out Warning_Vectors.Vector)
        return SData.Transient_Table.Table
     is
        R : SData.Transient_Table.Table;
     begin
        raise Program_Error with "Combine_Match not yet implemented";
        return R;
     end Combine_Match;

     function Combine_Interleave
       (Inputs   : Table_Vectors.Vector;
        By_Vars  : SData.Transient_Table.Name_Vectors.Vector;
        Warnings : in out Warning_Vectors.Vector)
        return SData.Transient_Table.Table
     is
        R : SData.Transient_Table.Table;
     begin
        raise Program_Error with "Combine_Interleave not yet implemented";
        return R;
     end Combine_Interleave;

     function Combine_Join
       (Inputs   : Table_Vectors.Vector;
        By_Vars  : SData.Transient_Table.Name_Vectors.Vector;
        Warnings : in out Warning_Vectors.Vector)
        return SData.Transient_Table.Table
     is
        R : SData.Transient_Table.Table;
     begin
        raise Program_Error with "Combine_Join not yet implemented";
        return R;
     end Combine_Join;

  end SData.Merge;
  ```

- [ ] **Step 5: Build and run unit tests**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: positional combiner tests pass; existing 140 integration tests and other unit tests continue to pass.

- [ ] **Step 6: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/sdata-merge.ads src/sdata-merge.adb tests/sdata_unit_test.adb
  git commit -m "$(cat <<'EOF'
  feat(merge): SData.Merge skeleton + Combine_Positional

  New package providing the four merge combiners (positional, match,
  interleave, Cartesian join) over transient tables. This commit lands
  Combine_Positional with full collision detection (rightmost wins,
  one warning per collision) and missing-value padding for mismatched
  row counts. Match/Interleave/Join are stubbed (raise Program_Error)
  and implemented in subsequent tasks.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

### Task 12: Implement Combine_Match (SAS-style full outer)

**Files:**
- Modify: `/home/jries/Develop/sdata/src/sdata-merge.adb`
- Modify: `/home/jries/Develop/sdata/tests/sdata_unit_test.adb`

- [ ] **Step 1: Write failing unit tests**

  Add to `tests/sdata_unit_test.adb`:

  ```ada
  --  Test: 1:1 match merge — single key, two inputs, fully matched
  declare
     use SData.Transient_Table;
     A, B, R : Table;
     Inputs   : SData.Merge.Table_Vectors.Vector;
     By_Vars  : Name_Vectors.Vector;
     Warnings : SData.Merge.Warning_Vectors.Vector;
  begin
     A.Add_Column ("ID", SData_Core.Table.Col_Integer);
     A.Add_Column ("X",  SData_Core.Table.Col_Integer);
     A.Add_Row; A.Set_Value (1, "ID", SData_Core.Values.From_Integer (1));
                A.Set_Value (1, "X",  SData_Core.Values.From_Integer (10));
     A.Add_Row; A.Set_Value (2, "ID", SData_Core.Values.From_Integer (2));
                A.Set_Value (2, "X",  SData_Core.Values.From_Integer (20));
     B.Add_Column ("ID", SData_Core.Table.Col_Integer);
     B.Add_Column ("Y",  SData_Core.Table.Col_Integer);
     B.Add_Row; B.Set_Value (1, "ID", SData_Core.Values.From_Integer (1));
                B.Set_Value (1, "Y",  SData_Core.Values.From_Integer (100));
     B.Add_Row; B.Set_Value (2, "ID", SData_Core.Values.From_Integer (2));
                B.Set_Value (2, "Y",  SData_Core.Values.From_Integer (200));
     Inputs.Append (A'Unchecked_Access);
     Inputs.Append (B'Unchecked_Access);
     By_Vars.Append (To_Unbounded_String ("ID"));
     R := SData.Merge.Combine_Match (Inputs, By_Vars, Warnings);
     Assert (R.Row_Count = 2, "Match 1:1 row count");
     Assert (SData_Core.Values.To_Integer (R.Get_Value (1, "X")) = 10,
             "Match X[1]");
     Assert (SData_Core.Values.To_Integer (R.Get_Value (1, "Y")) = 100,
             "Match Y[1]");
     Assert (Natural (Warnings.Length) = 0, "Match 1:1 no warnings");
  end;

  --  Test: 1:M match merge — short side recycles, no warning
  --  Test: N:M match merge — warning emitted; recycling
  --  Test: unmatched key on A — row appears with missing Y
  --  Test: unmatched key on B — row appears with missing X
  --  (Implement each as a separate declare block following the pattern above.)
  ```

  Each test should follow the same structural pattern; expand from the example.

- [ ] **Step 2: Implement Combine_Match**

  Replace the stub in `sdata-merge.adb`:

  ```ada
  function Combine_Match
    (Inputs   : Table_Vectors.Vector;
     By_Vars  : SData.Transient_Table.Name_Vectors.Vector;
     Warnings : in out Warning_Vectors.Vector)
     return SData.Transient_Table.Table
  is
     Result  : SData.Transient_Table.Table;
     Sources : Source_Vectors.Vector;

     --  Cursor pointing at the next unconsumed row of each input.
     Cursors : array (1 .. Natural (Inputs.Length)) of Natural := (others => 1);

     --  Compare BY-key values between input I@row and input J@row.
     --  Returns -1/0/+1 based on lex order across By_Vars.
     function Key_Compare
       (TI : Table_Access; RI : Positive;
        TJ : Table_Access; RJ : Positive) return Integer is
     begin
        for K of By_Vars loop
           declare
              Name : constant String := To_String (K);
              VI : constant SData_Core.Values.Value := TI.Get_Value (RI, Name);
              VJ : constant SData_Core.Values.Value := TJ.Get_Value (RJ, Name);
              C  : constant Integer := SData_Core.Values.Compare (VI, VJ);
           begin
              if C /= 0 then
                 return C;
              end if;
           end;
        end loop;
        return 0;
     end Key_Compare;

     --  Return the smallest key currently visible across all input
     --  cursors. Sets Min_Idx to one input that has that key. Returns
     --  False if all inputs are exhausted.
     function Find_Min_Key
       (Min_Idx : out Natural) return Boolean is
        Found : Boolean := False;
     begin
        Min_Idx := 0;
        for I in Cursors'Range loop
           if Cursors (I) <= SData.Transient_Table.Row_Count (Inputs (I).all) then
              if not Found then
                 Min_Idx := I;
                 Found := True;
              else
                 if Key_Compare
                      (Inputs (I),       Cursors (I),
                       Inputs (Min_Idx), Cursors (Min_Idx)) < 0
                 then
                    Min_Idx := I;
                 end if;
              end if;
           end if;
        end loop;
        return Found;
     end Find_Min_Key;

     --  Advance each input's cursor past all rows with the current key,
     --  capturing the group size per input.
     procedure Consume_Group
       (Reference_Idx : Positive;
        Group_Start : out array (1 .. Natural (Inputs.Length)) of Natural;
        Group_Size  : out array (1 .. Natural (Inputs.Length)) of Natural) is
     begin
        for I in Cursors'Range loop
           Group_Start (I) := 0;
           Group_Size (I)  := 0;
           if Cursors (I) <= SData.Transient_Table.Row_Count (Inputs (I).all)
              and then Key_Compare
                          (Inputs (I),             Cursors (I),
                           Inputs (Reference_Idx), Cursors (Reference_Idx))
                          = 0
           then
              Group_Start (I) := Cursors (I);
              while Cursors (I)
                       <= SData.Transient_Table.Row_Count (Inputs (I).all)
                 and then Key_Compare
                             (Inputs (I), Cursors (I),
                              Inputs (Reference_Idx), Group_Start (Reference_Idx))
                             = 0
              loop
                 Group_Size (I) := Group_Size (I) + 1;
                 Cursors (I) := Cursors (I) + 1;
              end loop;
           end if;
        end loop;
     end Consume_Group;

  begin
     Build_Schema (Result, Sources, Inputs, Warnings);

     loop
        declare
           Min_Idx : Natural;
        begin
           exit when not Find_Min_Key (Min_Idx);
           declare
              Group_Start : array (1 .. Natural (Inputs.Length)) of Natural;
              Group_Size  : array (1 .. Natural (Inputs.Length)) of Natural;
              Max_Size    : Natural := 0;
              Multi_Count : Natural := 0;
              Warn_Key    : Unbounded_String;
           begin
              Consume_Group (Min_Idx, Group_Start, Group_Size);
              for I in Group_Size'Range loop
                 if Group_Size (I) > Max_Size then
                    Max_Size := Group_Size (I);
                 end if;
                 if Group_Size (I) > 1 then
                    Multi_Count := Multi_Count + 1;
                 end if;
              end loop;
              if Multi_Count >= 2 then
                 --  N:M overlap — one warning per BY group
                 Warn_Key := To_Unbounded_String
                   ("N:M overlap in match merge at BY group with key=("
                      & By_Group_Key_String
                          (Inputs (Min_Idx).all, Group_Start (Min_Idx), By_Vars)
                      & ")");
                 Warnings.Append (Warn_Key);
              end if;
              --  Emit Max_Size output rows; shorter sides recycle their
              --  last row (SAS semantics). For inputs that didn't have
              --  this key at all (Group_Size=0), emit missing values.
              for R_Off in 0 .. Max_Size - 1 loop
                 Result.Add_Row;
                 declare
                    R_Out : constant Positive := Result.Row_Count;
                 begin
                    for C in 1 .. Natural (Sources.Length) loop
                       declare
                          Src     : constant Col_Source := Sources (C);
                          T       : constant Table_Access :=
                                      Inputs (Src.Table_Idx);
                          GS      : constant Natural := Group_Size (Src.Table_Idx);
                          R_In    : Natural;
                          V       : SData_Core.Values.Value;
                          Col_Out : constant String :=
                                      SData.Transient_Table.Column_Name (Result, C);
                       begin
                          if GS = 0 then
                             V := SData_Core.Values.Missing_Value;
                          else
                             --  Recycle: use last row if R_Off >= GS
                             if R_Off < GS then
                                R_In := Group_Start (Src.Table_Idx) + R_Off;
                             else
                                R_In := Group_Start (Src.Table_Idx) + GS - 1;
                             end if;
                             V := T.Get_Value (R_In, To_String (Src.Col_Name));
                          end if;
                          Result.Set_Value (R_Out, Col_Out, V);
                       end;
                    end loop;
                 end;
              end loop;
           end;
        end;
     end loop;
     return Result;
  end Combine_Match;

  --  Helper: format the BY-key tuple as a string for warning messages.
  function By_Group_Key_String
    (T       : SData.Transient_Table.Table;
     Row     : Positive;
     By_Vars : SData.Transient_Table.Name_Vectors.Vector) return String
  is
     R : Unbounded_String;
     First : Boolean := True;
  begin
     for K of By_Vars loop
        if not First then
           R := R & ", ";
        end if;
        R := R & SData_Core.Values.To_Display_String
                   (T.Get_Value (Row, To_String (K)));
        First := False;
     end loop;
     return To_String (R);
  end By_Group_Key_String;
  ```

  Notes:
  - `SData_Core.Values.To_Display_String` is assumed to exist for warning formatting. If the actual API is different (e.g., `Image` or per-kind formatters), adapt.
  - Move `By_Group_Key_String` above `Combine_Match` since it's referenced from there.
  - The Consume_Group procedure uses Ada's nested-array parameter — if the dialect doesn't accept unconstrained arrays as out parameters this way, refactor to use `Natural'Array` types or use a record-of-vectors instead.

- [ ] **Step 3: Build and verify tests pass**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add src/sdata-merge.adb tests/sdata_unit_test.adb
  git commit -m "feat(merge): implement Combine_Match (SAS-style full outer)

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 13: Implement Combine_Interleave

**Files:**
- Modify: `/home/jries/Develop/sdata/src/sdata-merge.adb`
- Modify: `/home/jries/Develop/sdata/tests/sdata_unit_test.adb`

- [ ] **Step 1: Write failing unit tests**

  Add tests covering:
  - Two inputs, disjoint BY keys → rows emitted in BY-sorted order; sum row count.
  - Two inputs, overlapping BY keys → rows from both interleaved by key.
  - For each output row, columns absent from the contributing input get missing values.

- [ ] **Step 2: Implement Combine_Interleave**

  Replace the stub. Algorithm: build schema as in Match. Maintain cursors. At each step:
  1. Find the input with the smallest current BY key (Find_Min_Key from Match).
  2. Emit one row using only that input's column values; other inputs' columns get missing.
  3. Advance that input's cursor by one.
  4. Repeat until all cursors are exhausted.

  ```ada
  function Combine_Interleave
    (Inputs   : Table_Vectors.Vector;
     By_Vars  : SData.Transient_Table.Name_Vectors.Vector;
     Warnings : in out Warning_Vectors.Vector)
     return SData.Transient_Table.Table
  is
     Result  : SData.Transient_Table.Table;
     Sources : Source_Vectors.Vector;
     Cursors : array (1 .. Natural (Inputs.Length)) of Natural := (others => 1);

     --  (Reuse Key_Compare and Find_Min_Key as in Combine_Match; if they're
     --  declared local to Combine_Match, hoist them to package body level
     --  or duplicate. Cleanest is to hoist them; refactor Combine_Match
     --  to use the hoisted versions.)

  begin
     Build_Schema (Result, Sources, Inputs, Warnings);
     loop
        declare
           Min_Idx : Natural;
        begin
           exit when not Find_Min_Key (Cursors, Inputs, By_Vars, Min_Idx);
           Result.Add_Row;
           declare
              R_Out : constant Positive := Result.Row_Count;
              R_In  : constant Positive := Cursors (Min_Idx);
              T     : constant Table_Access := Inputs (Min_Idx);
           begin
              for C in 1 .. Natural (Sources.Length) loop
                 declare
                    Col_Out : constant String :=
                       SData.Transient_Table.Column_Name (Result, C);
                    Src     : constant Col_Source := Sources (C);
                    V       : SData_Core.Values.Value;
                 begin
                    --  In interleave, the contributing input is Min_Idx
                    --  regardless of Src.Table_Idx — emit value if the
                    --  current input has the column, missing otherwise.
                    if T.Has_Column (Col_Out) then
                       V := T.Get_Value (R_In, Col_Out);
                    else
                       V := SData_Core.Values.Missing_Value;
                    end if;
                    Result.Set_Value (R_Out, Col_Out, V);
                 end;
              end loop;
              Cursors (Min_Idx) := Cursors (Min_Idx) + 1;
           end;
        end;
     end loop;
     return Result;
  end Combine_Interleave;
  ```

  Note: hoist `Key_Compare` and `Find_Min_Key` to package-body level (taking `Cursors`, `Inputs`, `By_Vars` as parameters) so both Combine_Match and Combine_Interleave (and Combine_Join) can share them.

- [ ] **Step 3: Build and verify tests pass**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add src/sdata-merge.adb tests/sdata_unit_test.adb
  git commit -m "feat(merge): implement Combine_Interleave (BY-sorted streaming merge)

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 14: Implement Combine_Join (Cartesian inner)

**Files:**
- Modify: `/home/jries/Develop/sdata/src/sdata-merge.adb`
- Modify: `/home/jries/Develop/sdata/tests/sdata_unit_test.adb`

- [ ] **Step 1: Write failing unit tests**

  Add tests covering:
  - 1:1 join: same as match for fully matched keys.
  - N:M join: produces N*M rows per matched BY group.
  - Unmatched keys: groups present in some inputs but not all are dropped (no output rows).
  - JOIN_WARN_THRESHOLD: set the threshold low, verify a warning fires.

- [ ] **Step 2: Implement Combine_Join**

  Algorithm: similar to Combine_Match, but:
  - For each BY group, only emit rows if EVERY input has at least one row for that key (inner join). Otherwise skip the group.
  - Output row count per group = product of group sizes.
  - For each combination (r₁, r₂, ..., rₖ) where rᵢ ∈ [0, Group_Size(i)-1]: emit one row with column values from each source's group_start(i) + rᵢ.
  - If product > `Options_Join_Warn_Threshold` and threshold > 0: emit one warning per such group.

  ```ada
  function Combine_Join
    (Inputs   : Table_Vectors.Vector;
     By_Vars  : SData.Transient_Table.Name_Vectors.Vector;
     Warnings : in out Warning_Vectors.Vector)
     return SData.Transient_Table.Table
  is
     Result  : SData.Transient_Table.Table;
     Sources : Source_Vectors.Vector;
     Cursors : array (1 .. Natural (Inputs.Length)) of Natural := (others => 1);
     Threshold : constant Natural :=
                   SData_Core.Config.Runtime.Options_Join_Warn_Threshold;
  begin
     Build_Schema (Result, Sources, Inputs, Warnings);
     loop
        declare
           Min_Idx : Natural;
        begin
           exit when not Find_Min_Key (Cursors, Inputs, By_Vars, Min_Idx);
           declare
              Group_Start : array (1 .. Natural (Inputs.Length)) of Natural;
              Group_Size  : array (1 .. Natural (Inputs.Length)) of Natural;
              All_Present : Boolean := True;
              Product     : Long_Long_Integer := 1;
           begin
              Consume_Group (Cursors, Inputs, By_Vars, Min_Idx,
                             Group_Start, Group_Size);
              for I in Group_Size'Range loop
                 if Group_Size (I) = 0 then
                    All_Present := False;
                 else
                    Product := Product * Long_Long_Integer (Group_Size (I));
                 end if;
              end loop;
              if not All_Present then
                 goto Continue;
              end if;
              if Threshold > 0 and then Product > Long_Long_Integer (Threshold)
              then
                 Warnings.Append
                   (To_Unbounded_String
                      ("/JOIN BY-group product ("
                         & Long_Long_Integer'Image (Product)
                         & ") exceeds OPTIONS JOIN_WARN_THRESHOLD"));
              end if;
              --  Emit the Cartesian product. Iterate as a multi-index
              --  counter Idx (1..k) where Idx(i) ∈ [0, Group_Size(i)-1].
              declare
                 Idx : array (1 .. Natural (Inputs.Length)) of Natural :=
                          (others => 0);
                 Done : Boolean := False;
              begin
                 while not Done loop
                    Result.Add_Row;
                    declare
                       R_Out : constant Positive := Result.Row_Count;
                    begin
                       for C in 1 .. Natural (Sources.Length) loop
                          declare
                             Src   : constant Col_Source := Sources (C);
                             T     : constant Table_Access :=
                                       Inputs (Src.Table_Idx);
                             R_In  : constant Positive :=
                                       Group_Start (Src.Table_Idx)
                                       + Idx (Src.Table_Idx);
                             V     : constant SData_Core.Values.Value :=
                                       T.Get_Value
                                         (R_In, To_String (Src.Col_Name));
                          begin
                             Result.Set_Value
                               (R_Out,
                                SData.Transient_Table.Column_Name (Result, C),
                                V);
                          end;
                       end loop;
                    end;
                    --  Increment the multi-index counter.
                    declare
                       Carry : Boolean := True;
                       I     : Natural := Idx'Last;
                    begin
                       while Carry and then I >= 1 loop
                          Idx (I) := Idx (I) + 1;
                          if Idx (I) >= Group_Size (I) then
                             Idx (I) := 0;
                             I := I - 1;
                          else
                             Carry := False;
                          end if;
                       end loop;
                       Done := Carry;  --  carried out the top — finished
                    end;
                 end loop;
              end;
              <<Continue>> null;
           end;
        end;
     end loop;
     return Result;
  end Combine_Join;
  ```

  Verify the multi-index counter logic by tracing through a 2×3 case manually; off-by-one is easy here.

- [ ] **Step 3: Build and verify tests pass**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add src/sdata-merge.adb tests/sdata_unit_test.adb
  git commit -m "feat(merge): implement Combine_Join (Cartesian inner)

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
  ```

---

## Phase 5: USE handler — wire merge into Execute_USE

### Task 15: Rewrite Execute_USE to orchestrate multi-load + merge

**Files:**
- Modify: `/home/jries/Develop/sdata/src/sdata-interpreter-execute_declarative.adb`
- Modify: any package the interpreter uses to emit warnings (likely `SData_Core.IO.Put_Line_Error`)

- [ ] **Step 1: Locate the existing Execute_USE handler**

  In `sdata-interpreter-execute_declarative.adb`, around lines 23–63 (per the map). It currently extracts AST fields and calls `SData_Core.Commands.Execute_USE`.

- [ ] **Step 2: Rewrite the body**

  ```ada
  procedure Execute_USE (Stmt : Statement_Access) is
  begin
     if Stmt.Mode = MM_Single
        and then Natural (Stmt.Dataset_List.Length) <= 1
     then
        --  Legacy path: existing behavior. If Dataset_List has one
        --  entry, copy its per-spec options into the legacy parameters
        --  too (Parse_USE already did this; we just call the existing
        --  Commands.Execute_USE with the legacy fields).
        Legacy_Execute_USE (Stmt);
        return;
     end if;

     --  Multi-dataset path.
     declare
        Snapshots : SData.Merge.Table_Vectors.Vector;
        Warnings  : SData.Merge.Warning_Vectors.Vector;
        Combined  : SData.Transient_Table.Table;
     begin
        for Spec_Idx in 1 .. Natural (Stmt.Dataset_List.Length) loop
           declare
              Spec : constant Dataset_Spec_Access :=
                        Stmt.Dataset_List (Spec_Idx);
              Snap : aliased SData.Transient_Table.Table;
           begin
              --  Load this input into the global table via legacy Execute_USE.
              SData_Core.Commands.Execute_USE
                (File_Name   => Spec.File_Path (1 .. Spec.File_Len),
                 Fmt         => (if Spec.Opts.Format_Specified
                                 then Spec.Opts.Fmt_Override
                                 else SData_Core.Config.CSV),
                 Sheet_Name  => Spec.Opts.Sheet_Name (1 .. Spec.Opts.Sheet_Name_Len),
                 Delimiter   => Spec.Opts.DLM_Val (1 .. Spec.Opts.DLM_Len),
                 Read_Header => (if Spec.Opts.Header_Specified
                                 then Spec.Opts.Header_Val
                                 else SData_Core.Config.Runtime.Options_Header),
                 Charset     => Spec.Opts.Charset_Val (1 .. Spec.Opts.Charset_Len),
                 Skip_Rows   => Spec.Opts.Skip_Val,
                 Max_Rows    => Spec.Opts.Maxrows_Val,
                 Nscan_Rows  => Spec.Opts.NSCAN_Val,
                 Is_Mock     => Spec.Is_Mock);

              --  Snapshot the global table into a transient.
              Snap := SData.Transient_Table.Snapshot_From_Current;

              --  Apply per-dataset RENAME → KEEP → DROP.
              if Spec.Opts.Rename_Pairs /= null then
                 declare
                    R : SData.Transient_Table.Rename_Map_Vectors.Vector;
                 begin
                    --  Convert Rename_List → Rename_Map_Vectors.Vector.
                    Convert_Rename_List (Spec.Opts.Rename_Pairs, R);
                    Snap.Apply_Rename (R);
                 end;
              end if;
              if Spec.Opts.Keep_Vars /= null
                 and Spec.Opts.Drop_Vars /= null
              then
                 raise SData_Core.Script_Error
                    with "KEEP and DROP cannot both be specified for the "
                       & "same dataset in USE";
              end if;
              if Spec.Opts.Keep_Vars /= null then
                 declare
                    V : SData.Transient_Table.Name_Vectors.Vector;
                 begin
                    Convert_Variable_List (Spec.Opts.Keep_Vars, V);
                    Snap.Apply_Keep (V);
                 end;
              end if;
              if Spec.Opts.Drop_Vars /= null then
                 declare
                    V : SData.Transient_Table.Name_Vectors.Vector;
                 begin
                    Convert_Variable_List (Spec.Opts.Drop_Vars, V);
                    Snap.Apply_Drop (V);
                 end;
              end if;

              --  Auto-sort by BY-vars if /BY= was specified.
              if Stmt.Mode = MM_Match
                 or Stmt.Mode = MM_Interleave
                 or Stmt.Mode = MM_Join
              then
                 declare
                    By_Names : SData.Transient_Table.Name_Vectors.Vector;
                 begin
                    Convert_Variable_List (Stmt.By_Vars, By_Names);
                    --  Verify every BY var exists in this snapshot.
                    for N of By_Names loop
                       if not Snap.Has_Column (To_String (N)) then
                          raise SData_Core.Script_Error
                             with "/BY=" & To_String (N)
                                & " is not present in dataset "
                                & Spec.File_Path (1 .. Spec.File_Len);
                       end if;
                    end loop;
                    Snap.Sort_By (By_Names);
                 end;
              end if;

              Snapshots.Append (Snap'Unchecked_Access);
              --  Note: Snap is local to this iteration; we need a heap-
              --  allocated copy. Replace 'Unchecked_Access with an
              --  explicit `new SData.Transient_Table.Table'(Snap)` once
              --  Transient_Table is non-limited, OR change Snapshots to
              --  hold values rather than accesses. The simplest
              --  refactor: make SData.Merge.Table_Vectors hold values
              --  via `Element_Type => SData.Transient_Table.Table` and
              --  drop the access type — Ada will copy. Adjust Task 11's
              --  Table_Vectors definition accordingly.
           end;
        end loop;

        --  Combine according to Mode.
        case Stmt.Mode is
           when MM_Positional =>
              Combined := SData.Merge.Combine_Positional
                            (Snapshots, Warnings);
           when MM_Match =>
              Combined := SData.Merge.Combine_Match
                            (Snapshots,
                             Convert_To_Name_Vector (Stmt.By_Vars),
                             Warnings);
           when MM_Interleave =>
              Combined := SData.Merge.Combine_Interleave
                            (Snapshots,
                             Convert_To_Name_Vector (Stmt.By_Vars),
                             Warnings);
           when MM_Join =>
              Combined := SData.Merge.Combine_Join
                            (Snapshots,
                             Convert_To_Name_Vector (Stmt.By_Vars),
                             Warnings);
           when MM_Single =>
              null;  --  unreachable here
        end case;

        --  Install combined result.
        SData.Transient_Table.Install_To_Current (Combined);

        --  Register IN= variables as temp scalars in the PDV.
        --  (Implementation: for each Spec with IN_Name_Len > 0, create
        --  a temp Integer variable; the value 1 or 0 will be set per
        --  record during the data step based on which inputs
        --  contributed. For MVP, treat IN= as always-1 since the
        --  merge result doesn't track per-row provenance; a follow-on
        --  task can add provenance columns. See Open Issues at end of
        --  this plan.)

        --  Emit warnings.
        for W of Warnings loop
           SData_Core.IO.Put_Line_Error
             ("warning: " & To_String (W));
        end loop;
     end;

     --  Clear REPEAT (matches legacy Execute_USE side effect).
     SData_Core.Config.Runtime.Repeat_Active := False;
     SData_Core.Config.Runtime.Repeat_Count := 0;
  end Execute_USE;
  ```

  Implement helpers `Convert_Rename_List`, `Convert_Variable_List`,
  `Convert_To_Name_Vector`, `Legacy_Execute_USE` as local procedures.
  `Legacy_Execute_USE` is the current Execute_USE body, renamed.

  **Important refactor needed:** the snippet uses `'Unchecked_Access` on
  a local `Snap`. Limited types can't be copied; the cleanest fix is to
  redefine `Table_Vectors` (in `sdata-merge.ads`) to hold heap-allocated
  `Table_Access` values and explicitly `new` each one in this loop:

  ```ada
  declare
     Snap_Ptr : constant SData.Merge.Table_Access :=
                  new SData.Transient_Table.Table;
  begin
     Snap_Ptr.all := SData.Transient_Table.Snapshot_From_Current;
     --  apply RENAME/KEEP/DROP/Sort_By on Snap_Ptr.all
     Snapshots.Append (Snap_Ptr);
  end;
  ```

  If `SData.Transient_Table.Table` is `tagged limited private`
  (Task 3), `Snap_Ptr.all := ...` will fail. Either:
  - Make the type non-limited (just `tagged private`) so it's copyable; or
  - Add an explicit `Copy` procedure to `SData.Transient_Table` and use
    that.

  Pick the non-limited option (simpler) and update Task 3's spec to
  remove the `limited` keyword. Memory ownership: the access values in
  `Snapshots` are freed at end of Execute_USE — add an explicit cleanup
  loop that deallocates each one before returning. Use
  `Ada.Unchecked_Deallocation`.

- [ ] **Step 3: Add integration test for positional merge**

  Create `tests/use_merge_positional.cmd`:

  ```
  USE tests/data/a.csv, tests/data/b.csv
  PRINT ID, X, Y
  RUN
  ```

  Create `tests/use_merge_positional.exp` with the expected printed output (one PRINT line per row). Use the small a.csv / b.csv files created in Task 8.

- [ ] **Step 4: Build and run**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: existing tests pass; `use_merge_positional` test passes; the parse-only `use_merge_parse` test from Task 8 now exercises the executor and may need its `.exp` updated to match the actual NAMES output after merge.

- [ ] **Step 5: Commit**

  ```bash
  git add src/sdata-interpreter-execute_declarative.adb \
          src/sdata-transient_table.ads src/sdata-transient_table.adb \
          src/sdata-merge.ads \
          tests/use_merge_positional.cmd tests/use_merge_positional.exp \
          tests/use_merge_parse.exp
  git commit -m "$(cat <<'EOF'
  feat(use): wire multi-dataset merge into Execute_USE

  Multi-dataset USE statements now load each input into a transient,
  apply per-dataset RENAME/KEEP/DROP, auto-sort by BY vars when
  /BY= is present, and combine into the global table via the SData.Merge
  combiners. Single-dataset USE continues to use the legacy code path
  unchanged. IN= variables are accepted but currently always 1 for any
  row (a follow-on task can add per-row provenance — see plan open issues).

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Phase 6: Multi-target SAVE/WRITE

### Task 16: Add Registered_Saves state to sdata interpreter

**Files:**
- Modify: `/home/jries/Develop/sdata/src/sdata-interpreter.adb` (private state section, lines ~59–150)
- Maybe modify: `/home/jries/Develop/sdata/src/sdata-interpreter.ads` if a public accessor is needed (probably not)

- [ ] **Step 1: Declare the registration list and per-iteration flag**

  In the `sdata-interpreter.adb` private state section (alongside `Step_Context`, `Active_Program_Vec`, etc.), add:

  ```ada
  --  Multi-target SAVE registration. When non-empty, supersedes the
  --  single-target Save_File_* fields in SData_Core.Config.Runtime
  --  for the duration of the next RUN. Cleared by RUN flush, by an
  --  empty SAVE statement, or by NEW.
  type Save_Target is record
     File_Path : Unbounded_String;
     Alias     : Unbounded_String;        --  empty = no alias
     Opts      : SData.AST.Spec_Options;
  end record;
  type Save_Target_Access is access all Save_Target;
  package Save_Target_Vectors is new Ada.Containers.Vectors
    (Index_Type => Positive, Element_Type => Save_Target_Access);
  Registered_Saves : Save_Target_Vectors.Vector;

  --  Reset per record; set True by any WRITE that fires during the
  --  iteration; consulted at end-of-record to decide whether to
  --  auto-flush.
  Write_Fired_This_Iter : Boolean := False;
  ```

- [ ] **Step 2: Add a helper to clear Registered_Saves**

  ```ada
  procedure Clear_Registered_Saves is
  begin
     for T of Registered_Saves loop
        --  free Opts.Keep_Vars / Drop_Vars / Rename_Pairs / IF_Expr
        --  using the same helpers Free_Program uses
        Free_Spec_Options (T.Opts);
        --  free T itself
        declare
           procedure Free is new Ada.Unchecked_Deallocation
             (Save_Target, Save_Target_Access);
           Tmp : Save_Target_Access := T;
        begin
           Free (Tmp);
        end;
     end loop;
     Registered_Saves.Clear;
  end Clear_Registered_Saves;
  ```

  Add a call to `Clear_Registered_Saves` from the NEW handler (find the existing NEW-command body and add the call alongside other resets).

- [ ] **Step 3: Build to verify**

  ```bash
  cd /home/jries/Develop/sdata && make build
  ```

  Expected: build succeeds. State is unused so far — no behavior change.

- [ ] **Step 4: Commit**

  ```bash
  git add src/sdata-interpreter.adb
  git commit -m "feat(save): add Registered_Saves interpreter state

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 17: Rewrite Execute_SAVE to populate Registered_Saves

**Files:**
- Modify: `/home/jries/Develop/sdata/src/sdata-interpreter-execute_declarative.adb`

- [ ] **Step 1: Locate Execute_SAVE (around lines 71–100)**

- [ ] **Step 2: Rewrite the body**

  ```ada
  procedure Execute_SAVE (Stmt : Statement_Access) is
  begin
     --  Empty SAVE clears all registrations (legacy + new).
     if Stmt.File_Len = 0
        and then Natural (Stmt.Save_List.Length) = 0
     then
        Clear_Registered_Saves;
        SData_Core.Config.Runtime.Save_File_Active := False;
        return;
     end if;

     --  Single-target back-compat path: when Save_List is empty,
     --  delegate to legacy.
     if Natural (Stmt.Save_List.Length) = 0 then
        Legacy_Execute_SAVE (Stmt);
        return;
     end if;

     --  Multi-target: clear any prior registrations and re-register.
     Clear_Registered_Saves;

     --  Validate alias uniqueness within this statement.
     declare
        package U is new Ada.Containers.Indefinite_Hashed_Sets
          (Element_Type => String,
           Hash => Ada.Strings.Hash,
           Equivalent_Elements => "=");
        Seen_Alias : U.Set;
        Seen_File  : U.Set;
     begin
        for Spec of Stmt.Save_List loop
           if Spec.Alias_Len > 0 then
              declare
                 A : constant String :=
                    To_Upper (Spec.Alias (1 .. Spec.Alias_Len));
              begin
                 if Seen_Alias.Contains (A) then
                    raise SData_Core.Script_Error
                       with "duplicate SAVE alias: "
                          & Spec.Alias (1 .. Spec.Alias_Len);
                 end if;
                 Seen_Alias.Include (A);
              end;
           end if;
           declare
              F : constant String :=
                 To_Upper (Spec.File_Path (1 .. Spec.File_Len));
           begin
              if Seen_File.Contains (F) then
                 raise SData_Core.Script_Error
                    with "duplicate SAVE file: "
                       & Spec.File_Path (1 .. Spec.File_Len);
              end if;
              Seen_File.Include (F);
           end;
           if Spec.Opts.Keep_Vars /= null
              and Spec.Opts.Drop_Vars /= null
           then
              raise SData_Core.Script_Error
                 with "KEEP and DROP cannot both be specified for the "
                    & "same SAVE target";
           end if;
        end loop;
     end;

     --  Register each target.
     for Spec of Stmt.Save_List loop
        declare
           T : constant Save_Target_Access := new Save_Target;
        begin
           T.File_Path :=
              To_Unbounded_String (Spec.File_Path (1 .. Spec.File_Len));
           if Spec.Alias_Len > 0 then
              T.Alias :=
                 To_Unbounded_String (Spec.Alias (1 .. Spec.Alias_Len));
           end if;
           T.Opts := Spec.Opts;  --  field-by-field copy (Spec_Options
                                 --  is a value record; access fields
                                 --  share ownership — see note below)
           Registered_Saves.Append (T);
        end;
     end loop;
  end Execute_SAVE;
  ```

  Ownership note: `Spec.Opts.Keep_Vars`, `Drop_Vars`, `Rename_Pairs`,
  `IF_Expr` are heap-allocated and owned by the AST. If `Execute_SAVE`
  is called multiple times for the same statement, the registration
  list takes a shared reference (the AST outlives the registration).
  When `Clear_Registered_Saves` runs, do NOT free these access fields —
  the AST owns them and `Free_Program` will free them at end of
  program / NEW. Adjust `Free_Spec_Options` in Task 16 to only nullify
  the references in the target, not free the underlying nodes.

- [ ] **Step 3: Build and verify**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: existing tests pass; the Task 9 parser test (`save_multi_parse.cmd`) now passes through Execute_SAVE without error (though the actual write still goes through the legacy single-pending-SAVE path at RUN time — wired up in Task 19).

- [ ] **Step 4: Commit**

  ```bash
  git add src/sdata-interpreter-execute_declarative.adb
  git commit -m "feat(save): multi-target Execute_SAVE registers all targets

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 18: Rewrite Execute_WRITE to route to named targets

**Files:**
- Modify: `/home/jries/Develop/sdata/src/sdata-interpreter.adb` (around line 571)
- Possibly modify a sdata-core helper to write a single record to a named file

- [ ] **Step 1: Refactor: extract Write_Record_To_Target helper**

  Add to `sdata-interpreter.adb` body:

  ```ada
  procedure Write_Record_To_Target (T : Save_Target_Access) is
  begin
     --  Evaluate IF filter, if any.
     if T.Opts.IF_Expr /= null then
        declare
           V : constant SData_Core.Values.Value :=
                  SData_Core.Evaluator.Evaluate (T.Opts.IF_Expr);
        begin
           if not SData_Core.Values.To_Boolean (V) then
              return;
           end if;
        end;
     end if;
     --  Project PDV through per-target KEEP / DROP / RENAME — most
     --  efficient: pass the projection metadata to a sdata-core write
     --  helper that writes a single row. If that helper doesn't exist,
     --  the simplest implementation is:
     --    1. Snapshot current global table → transient.
     --    2. Apply RENAME / KEEP / DROP / select only current row.
     --    3. Install_To_Current.
     --    4. Call existing single-record-write path for the target.
     --    5. Restore the original snapshot.
     --  This is slow but correct. Profile after correctness.
     --  ...
     --  For the first MVP, ignore per-target KEEP/DROP/RENAME (treat
     --  them as future work — see plan open issues) and just write
     --  the PDV as-is to the file given by T.File_Path. Use the
     --  existing flush path:
     SData_Core.File_IO.Append_Current_Record
       (File_Name => To_String (T.File_Path),
        Header_Was_Written => Header_Already_Sent (T));
  end Write_Record_To_Target;
  ```

  `SData_Core.File_IO.Append_Current_Record` may not exist yet — check
  `sdata_core-file_io.ads`. If it doesn't, this task either (a) adds
  it as an additive sdata-core helper, or (b) reuses the existing
  whole-table SAVE path on the full PDV. Option (b) is cleaner if the
  existing write path can be invoked per record cheaply. If neither is
  feasible without significant sdata-core work, defer per-target
  KEEP/DROP/RENAME to a follow-on task and ship multi-target with
  shared schema first. **Decision point — record the chosen approach
  in the commit message.**

- [ ] **Step 2: Rewrite Execute_WRITE**

  Replace the WRITE handler:

  ```ada
  procedure Execute_WRITE (Stmt : Statement_Access) is
  begin
     if Natural (Registered_Saves.Length) = 0 then
        raise SData_Core.Script_Error
           with "WRITE: no SAVE target registered";
     end if;
     if Stmt.Write_Targets = null then
        --  Write to every registered target.
        for T of Registered_Saves loop
           Write_Record_To_Target (T);
        end loop;
     else
        --  Write only to named targets.
        for V of Iterate_Variable_List (Stmt.Write_Targets) loop
           declare
              Target_Up : constant String := To_Upper (V);
              Found     : Boolean := False;
           begin
              for T of Registered_Saves loop
                 if (Length (T.Alias) > 0
                     and then To_Upper (To_String (T.Alias)) = Target_Up)
                    or else
                    To_Upper (To_String (T.File_Path)) = Target_Up
                 then
                    Write_Record_To_Target (T);
                    Found := True;
                    exit;
                 end if;
              end loop;
              if not Found then
                 raise SData_Core.Script_Error
                    with "WRITE target not registered: " & V;
              end if;
           end;
        end loop;
     end if;
     Write_Fired_This_Iter := True;
     SData_Core.Table.Set_Record_Explicitly_Written (True);
  end Execute_WRITE;
  ```

- [ ] **Step 3: Build and verify**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: existing tests pass.

- [ ] **Step 4: Commit**

  ```bash
  git add src/sdata-interpreter.adb
  git commit -m "feat(write): route to named SAVE targets; suppress auto-flush

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 19: Update process_one_record and RUN flush for multi-target

**Files:**
- Modify: `/home/jries/Develop/sdata/src/sdata-interpreter-process_one_record.adb`
- Modify: `/home/jries/Develop/sdata/src/sdata-interpreter.adb` (RUN handler)

- [ ] **Step 1: Reset Write_Fired_This_Iter at start of each record**

  In `process_one_record.adb`, at line ~87 where `Set_Record_Explicitly_Written (False)` is called, add immediately after:

  ```ada
  Write_Fired_This_Iter := False;
  ```

- [ ] **Step 2: Add multi-target auto-flush at end of each record**

  Locate the end-of-record auto-flush in `process_one_record.adb` (or wherever it currently lives — search for `Flush_PDV_To_Output` or similar). After the existing single-target auto-flush, add:

  ```ada
  if not Write_Fired_This_Iter
     and Natural (Registered_Saves.Length) > 0
  then
     for T of Registered_Saves loop
        Write_Record_To_Target (T);
     end loop;
  end if;
  ```

- [ ] **Step 3: Close/finalize targets at RUN end**

  In `sdata-interpreter.adb`, find the RUN handler. After the existing single-pending-SAVE flush, add a loop that closes / finalizes each registered target (call any sdata-core "close output writer" helper if one exists; otherwise the per-record append path already writes to disk and there's nothing to close). Then clear:

  ```ada
  Clear_Registered_Saves;
  ```

- [ ] **Step 4: Build and verify**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

- [ ] **Step 5: Commit**

  ```bash
  git add src/sdata-interpreter.adb src/sdata-interpreter-process_one_record.adb
  git commit -m "feat(save): multi-target auto-flush and RUN-time finalization

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
  ```

---

## Phase 7: Integration tests

### Task 20: Merge integration tests

**Files:**
- Add: `/home/jries/Develop/sdata/tests/use_merge_positional_eq.cmd` (+ `.exp`)
- Add: `/home/jries/Develop/sdata/tests/use_merge_positional_pad.cmd` (+ `.exp`)
- Add: `/home/jries/Develop/sdata/tests/use_merge_match_1to1.cmd` (+ `.exp`)
- Add: `/home/jries/Develop/sdata/tests/use_merge_match_1toM.cmd` (+ `.exp`)
- Add: `/home/jries/Develop/sdata/tests/use_merge_match_NtoM_warn.cmd` (+ `.exp`)
- Add: `/home/jries/Develop/sdata/tests/use_merge_match_unmatched.cmd` (+ `.exp`)
- Add: `/home/jries/Develop/sdata/tests/use_merge_interleave_sorted.cmd` (+ `.exp`)
- Add: `/home/jries/Develop/sdata/tests/use_merge_interleave_unsorted.cmd` (+ `.exp`)
- Add: `/home/jries/Develop/sdata/tests/use_merge_join_NxM.cmd` (+ `.exp`)
- Add: `/home/jries/Develop/sdata/tests/use_merge_join_unmatched_dropped.cmd` (+ `.exp`)
- Add: `/home/jries/Develop/sdata/tests/use_merge_per_ds_keep_drop_rename.cmd` (+ `.exp`)
- Add: `/home/jries/Develop/sdata/tests/use_merge_collision_warn.cmd` (+ `.exp`)
- Add corresponding `tests/data/*.csv` input files as needed.

- [ ] **Step 1: For each test case, create the `.cmd` script and `.exp` reference output**

  Follow the pattern of existing `tests/*.cmd` files. Each test should be small and focused.

  Example — `use_merge_match_1to1.cmd`:
  ```
  USE tests/data/m_left.csv, tests/data/m_right.csv /BY=ID
  PRINT ID, LX, RY
  RUN
  ```

  With `tests/data/m_left.csv`:
  ```
  ID,LX
  1,a
  2,b
  3,c
  ```

  And `tests/data/m_right.csv`:
  ```
  ID,RY
  1,10
  2,20
  3,30
  ```

  And `use_merge_match_1to1.exp`: the literal PRINT output expected.

- [ ] **Step 2: Run `make check` after each test is added**

  Add tests one at a time and run after each to verify it passes (or to surface a bug that needs fixing before continuing).

- [ ] **Step 3: Commit all merge integration tests together**

  ```bash
  git add tests/use_merge_*.cmd tests/use_merge_*.exp tests/data/m_*.csv
  git commit -m "test(merge): integration tests for all four merge modes

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 21: Multi-output integration tests

**Files:**
- Add: `tests/save_multi_no_write.cmd`
- Add: `tests/save_multi_with_if.cmd`
- Add: `tests/save_multi_write_named.cmd`
- Add: `tests/save_multi_write_alias.cmd`
- Add: `tests/save_multi_double_write.cmd`
- Add: `tests/save_multi_write_unknown_err.cmd`
- All with `.exp` reference outputs.

- [ ] **Step 1: Create each test**

  Follow the pattern in `tests/`. Tests that produce files need to verify file contents after the run — examine an existing file-producing test to see the convention (likely `.exp` lists expected stdout, and a sidecar check compares output files to expected fixtures).

- [ ] **Step 2: Add tests one-by-one, run `make check` after each**

- [ ] **Step 3: Commit**

  ```bash
  git add tests/save_multi_*.cmd tests/save_multi_*.exp
  git commit -m "test(save): integration tests for multi-target SAVE + WRITE routing

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 22: Error-condition integration tests

**Files:** one `.cmd` + `.exp` per error condition listed in spec §5. Examples:

- `tests/use_merge_err_by_missing.cmd` — `/BY=` references a variable not in one input.
- `tests/use_merge_err_keep_drop_both.cmd` — KEEP and DROP both on same dataset.
- `tests/use_merge_err_rename_dup_src.cmd` — `RENAME=(a=b, a=c)`.
- `tests/use_merge_err_in_collision_col.cmd` — IN= name matches a real column.
- `tests/use_merge_err_in_collision_in.cmd` — two datasets with same IN= name.
- `tests/use_merge_err_alias_dup.cmd` — two `AS` aliases identical.
- `tests/use_merge_err_join_no_by.cmd` — `/JOIN` without `/BY=`.
- `tests/use_merge_err_interleave_no_by.cmd` — `/INTERLEAVE` without `/BY=`.
- `tests/use_merge_err_join_and_interleave.cmd` — both specified.
- `tests/use_merge_err_join_single_ds.cmd` — `/JOIN` with one dataset.
- `tests/save_multi_err_alias_dup.cmd` — duplicate alias.
- `tests/save_multi_err_file_dup.cmd` — duplicate filename.
- `tests/save_multi_err_keep_drop_both.cmd` — KEEP and DROP both.
- `tests/save_multi_err_if_unknown_var.cmd` — IF= references unknown variable.

- [ ] **Step 1: Add each test**

  Each `.exp` should include the expected error message text and the test framework should assert non-zero exit. Mirror the convention of any existing error-checking test in `tests/`.

- [ ] **Step 2: Run `make check` after each**

- [ ] **Step 3: Commit**

  ```bash
  git add tests/use_merge_err_*.cmd tests/use_merge_err_*.exp \
          tests/save_multi_err_*.cmd tests/save_multi_err_*.exp
  git commit -m "test: error-condition integration tests for merge / multi-output

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
  ```

---

## Phase 8: Documentation and final validation

### Task 23: Update the man page

**Files:**
- Modify: `/home/jries/Develop/sdata/man/man1/sdata.1`

- [ ] **Step 1: Update the USE description**

  Find the existing USE entry (around line 181 per the earlier map). Replace the single-file synopsis with:

  ```
  .B USE \fIspec\fR[\fB,\fR \fIspec\fR ...] [\fB/BY=\fIvar\fR ...] [\fB/INTERLEAVE\fR|\fB/JOIN\fR]
  
  where \fIspec\fR is:
  
  .B \fIfile\fR[\fB[\fIsheet\fB]\fR] [\fBAS \fIalias\fR] [\fB(\fIopts\fB)\fR]
  ```

  Add detailed prose describing the four merge modes (positional, match, interleave, join), per-dataset options (KEEP, DROP, RENAME, IN, FMT, HEADER, CHARSET, DLM, NSCAN, SKIP, MAXROWS, SHEET), and behavior on collisions and unmatched keys. Use the spec document as authoritative source.

- [ ] **Step 2: Update the SAVE description**

  Same shape. Document multi-target SAVE, per-target options including IF=, alias use with WRITE.

- [ ] **Step 3: Update the WRITE description**

  Document `WRITE [target [, target ...]]`.

- [ ] **Step 4: Add a new OPTIONS entry for JOIN_WARN_THRESHOLD**

  Add to the OPTIONS section.

- [ ] **Step 5: Verify man page renders**

  ```bash
  groff -man -Tutf8 /home/jries/Develop/sdata/man/man1/sdata.1 | head -100
  ```

  Expected: no groff errors; sections render correctly.

- [ ] **Step 6: Commit**

  ```bash
  git add man/man1/sdata.1
  git commit -m "docs(man): document multi-dataset USE, multi-target SAVE, WRITE routing

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
  ```

---

### Task 24: Final validation

- [ ] **Step 1: Run the full sdata test suite**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: 140 + new merge tests + new multi-output tests + new error tests all pass; all unit tests pass. Record the new totals.

- [ ] **Step 2: Run the data-vandal test suite**

  ```bash
  cd /home/jries/Develop/data-vandal && make check
  ```

  Expected: 11 tests pass. Critical — verifies the additive sdata-core changes (Get_Column_Type, JOIN_WARN_THRESHOLD) did not break data-vandal.

- [ ] **Step 3: Verify sdata-core builds standalone**

  ```bash
  cd /home/jries/Develop/sdata-core && alr build
  ```

  Expected: succeeds.

- [ ] **Step 4: Inspect git log for the work**

  ```bash
  cd /home/jries/Develop/sdata && git log --oneline main..HEAD | head -40
  cd /home/jries/Develop/sdata-core && git log --oneline main..HEAD | head -10
  ```

  Verify commit history is clean, each commit message describes its scope, no fixup commits left behind.

- [ ] **Step 5: Optional — bump sdata version**

  If shipping as a release, run the versioning script:

  ```bash
  scripts/bump-version.sh 0.9.0 "Multi-dataset USE merge and multi-target SAVE/WRITE"
  ```

  Then commit and tag per CLAUDE.md conventions. Skip this step if you're not releasing yet.

---

## Required follow-on tasks (not yet expanded above)

The plan's main task list above ships a working merge + multi-output framing but defers two spec-required behaviors. These tasks MUST be added before declaring the spec complete; they are tracked here as items for the implementing engineer to expand into full TDD tasks during execution (or for the plan author to expand in a revision before execution begins).

### Required follow-on A: IN= variable per-row provenance

**Spec requirement (§2):** "IN= variables become temporary integer scalars (0 or 1) per logical record, named per the per-dataset option."

**Why deferred in main plan:** combiners would need to emit a parallel contributor-mask vector and Execute_USE would need to materialize Integer PDV temps from it — substantial extra plumbing across Tasks 11–15. Decided cleaner to ship in a dedicated follow-on rather than thread it through every combiner task.

**Approach to expand into TDD tasks:**

1. Add an output parameter `Provenance : out Provenance_Vectors.Vector` to each `Combine_*` function (one bitmask per emitted row; bit *i* set means input *i* contributed).
2. For Positional: bit *i* set when `R <= Row_Count(Inputs(i))`; otherwise unset.
3. For Match: bit *i* set when `Group_Size(i) > 0` for the current group; constant across the group's emitted rows.
4. For Interleave: only the bit for `Min_Idx` is set per emitted row.
5. For Join: all bits are set (Cartesian only emits when every input has the key).
6. In Execute_USE, after install: walk the spec list collecting requested IN= names. For each, register a temp Integer column in the PDV (use `SData_Core.Variables.Register_Subscripted_Columns` pattern per ADR-041 or the closest equivalent) initialized from the corresponding bit per row.
7. Add integration tests: `tests/use_merge_in_match.cmd`, `tests/use_merge_in_interleave.cmd`, `tests/use_merge_in_positional.cmd` — each asserts IN= column values across rows.

### Required follow-on B: per-target KEEP/DROP/RENAME on SAVE

**Spec requirement (§3):** "KEEP / DROP / RENAME: applied to the output projection at write time. The in-memory PDV is not mutated."

**Why deferred in main plan:** the existing single-target SAVE path writes the whole live table; per-record per-target projection requires either a new sdata-core append-projected-record helper or a snapshot/project/restore cycle per write. The choice and implementation are non-trivial.

**Approach to expand into TDD tasks:**

1. Decide between option (a) add `SData_Core.File_IO.Append_Projected_Record (File, Projection_Spec)` as an additive sdata-core helper, or (b) implement entirely in sdata via a transient-snapshot wrapper around the existing append path.
2. Prefer option (a) — it's the architectural fit for sdata-core's File_IO responsibility, and it benefits future use cases.
3. Implement `Append_Projected_Record` in sdata-core: takes a list of (source_col_name, output_col_name, included_yes_no) entries; writes one row of the current PDV applying the projection.
4. Update `Write_Record_To_Target` (Task 18) to build the Projection_Spec from `T.Opts.Keep_Vars`/`Drop_Vars`/`Rename_Pairs` and pass it to the new helper.
5. Add integration tests: `tests/save_multi_keep.cmd`, `tests/save_multi_drop.cmd`, `tests/save_multi_rename.cmd` — each asserts the output file column set differs from the live PDV.
6. Validate live PDV is unchanged after the write (the same `NAMES` output before and after).

## Lesser open issues (acceptable to defer post-shipping)

1. **Type-mismatch on column collision.** If two inputs have a column with the same name but different types (e.g., `X` is Integer in one, String in the other), the spec says "rightmost wins, warn once" without specifying behavior on type conflict. The current `Build_Schema` silently adopts the rightmost input's type. If stricter behavior is wanted (error on type conflict), add a check in `Build_Schema` — this would be additive.

2. **Memory ownership of `Snapshots` access values.** Task 15 notes the need for explicit `Unchecked_Deallocation` cleanup of the snapshot vector before Execute_USE returns. Verify no leaks via Valgrind or similar after the feature is shipped.

3. **Sort_By performance.** The insertion-sort fallback in `Transient_Table.Sort_By` is O(n²) and will be slow for large inputs. Replace with `Ada.Containers.Generic_Array_Sort` over the permutation once profiling shows it matters.

4. **OPTIONS JOIN_WARN_THRESHOLD parser wiring.** Task 2 adds the runtime field and sdata-core wrapper, but the sdata-side OPTIONS dispatch (in `execute_declarative.adb` around lines 192–260 per the map) must be extended with an `elsif Key = "JOIN_WARN_THRESHOLD"` branch that parses the value and calls `SData_Core.Commands.Execute_OPTIONS_Join_Warn_Threshold`. Add this in Task 14 (when first needed by the Combine_Join warning test) — or as a separate Task 2b if the engineer prefers to land it earlier.

---

## Self-Review Summary

- **Spec coverage:** §1 grammar → Tasks 5, 6, 7, 8, 9, 10. §2 merge semantics → Tasks 11–14 (combiners) + 15 (orchestration). §3 multi-output → Tasks 16, 17, 18, 19. §4 architecture → reflected in package structure. §5 error handling → Task 22. §6 testing strategy → Tasks 20, 21, 22.
- **Two spec requirements deferred to Required Follow-ons:** IN= per-row provenance (§2) and per-target KEEP/DROP/RENAME on SAVE (§3). Both are tracked as Required Follow-on A and B above and must be expanded into TDD tasks before declaring the spec complete. These cannot be skipped — they are documented spec behaviors.
- **Placeholder scan:** No TBDs/TODOs in the task code blocks; deferrals are explicitly named with full re-expansion guidance.
- **Type consistency:** Names used across tasks (`Dataset_Spec_Access`, `Spec_Options`, `Save_Target_Access`, `Combine_*`, `Apply_Keep`/`Apply_Drop`/`Apply_Rename`, `Write_Fired_This_Iter`, `Registered_Saves`) are consistent.
- **Plan scope:** Large by necessity — the feature is large. The phase boundaries allow stopping after Phase 5 (merge only, shippable) or after Phase 7 (full spec MVP, modulo Required Follow-ons A and B).
