# File I/O Parser Unit Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `file_io_unit_test` binary with ~70 tests covering `Parse_CSV`, `Parse_ODF`, and `Parse_OOXML` in `src/sdata-file_io.adb`, exercising normal loading, INF values, sheet selection, Skip_Rows, Max_Rows, and error paths.

**Architecture:** A single new test program (`tests/file_io_unit_test.adb`) calls the three public parser procedures from `SData.File_IO` directly with fixture files from `tests/data/`, then inspects the resulting `SData.Table` state via the public API. No mocking or stubs — real files, real parsers. Two new binary fixture files (`tests/data/inf_values.ods`, `tests/data/inf_values.xlsx`) are committed in Task 1; all other required fixtures already exist. The binary is added to `sdata.gpr` (Main list + Builder) and to the `make check` target in the Makefile.

**Tech Stack:** Ada 2012, GNAT/GPRbuild, Alire. Build: `alr build`. Test: `make check`.

---

## Background: fixture file inventory

These files in `tests/data/` are used by the tests — check they exist before starting:

| File | What it contains |
|------|-----------------|
| `tests/data/sample.csv` | CATEGORY,VAL1,VAL2,VAL3 — 6 rows; CATEGORY inferred string |
| `tests/data/inf_values.csv` | X,Y,Z — 3 rows of INF/-INF/normal values |
| `tests/data/header_only.csv` | A,B,C — header row only, 0 data rows |
| `tests/data/missing_first.csv` | X,Y — row 1 has X=. (missing), Y=10 |
| `tests/data/pipe_delim.csv` | NAME$\|SCORE — 2 rows, pipe-delimited |
| `tests/data/sample.ods` | ID,NAME$,SALARY — 3 rows: Alice/Bob/Charlie |
| `tests/data/sample.xlsx` | Same schema as sample.ods |
| `tests/data/multi_sheet.ods` | Sheet "Scores": ID,NAME$,SCORE; Sheet "Metadata": KEY$,VALUE$ |
| `tests/data/multi_sheet.xlsx` | Same as multi_sheet.ods |
| `tests/data/bad.ods` | Corrupt zip (triggers Script_Error) |
| `tests/data/bad.xlsx` | Corrupt zip (triggers Script_Error) |
| `tests/data/inf_values.ods` | **NEW** — created from inf_values.csv; committed in Task 1 |
| `tests/data/inf_values.xlsx` | **NEW** — created from inf_values.csv; committed in Task 1 |

**Known fixture values (for writing assertions):**

`sample.csv` after parsing: columns CATEGORY$, VAL1, VAL2, VAL3 (4 cols, 6 rows).
- Row 1: CATEGORY$="A", VAL1=1.0, VAL2=2.0, VAL3=3.0
- Row 6: CATEGORY$="C", VAL1=16.0, VAL2=17.0, VAL3=18.0

`inf_values.csv/ods/xlsx` after parsing: columns X, Y, Z (3 cols, 3 rows).
- Row 1: X=Pos_Inf, Y=Neg_Inf, Z=1.5
- Row 2: X=Pos_Inf, Y=Neg_Inf, Z=2.5
- Row 3: X=Pos_Inf, Y=Pos_Inf, Z=3.5

`sample.ods/xlsx` after parsing: columns ID, NAME$, SALARY (3 cols, 3 rows).
- Row 1: ID=1.0, NAME$="Alice", SALARY=50000.0
- Row 2: ID=2.0, NAME$="Bob", SALARY=60000.0
- Row 3: ID=3.0, NAME$="Charlie", SALARY=70000.0

`multi_sheet.ods/xlsx [Scores]`: columns ID, NAME$, SCORE (3 cols, 2 rows).
- Row 1: ID=1.0, NAME$="Alice", SCORE=95.0

`multi_sheet.ods/xlsx [Metadata]`: columns KEY$, VALUE$ (2 cols, 2 rows).
- Row 1: KEY$="Version", VALUE$="1.0"

`missing_first.csv` after parsing: columns X, Y (2 cols, 3 rows).
- Row 1: X=Val_Missing, Y=10.0

`pipe_delim.csv` with Delimiter="|": columns NAME$, SCORE (2 cols, 2 rows).
- Row 1: NAME$="Alice", SCORE=90.0

---

## File Map

| File | Action | What changes |
|------|--------|-------------|
| `tests/data/inf_values.ods` | Commit (already exists on disk) | New fixture |
| `tests/data/inf_values.xlsx` | Commit (already exists on disk) | New fixture |
| `tests/file_io_unit_test.adb` | Create | New test program |
| `sdata.gpr` | Modify | Add to Main list + Builder |
| `Makefile` | Modify | Add to `make check` |

---

### Task 1: Commit fixture files and create test scaffold

Commits the two pre-created fixture files, creates the test program skeleton (harness only, no test cases yet), wires it into the build system, and verifies a clean build.

**Files:**
- Commit: `tests/data/inf_values.ods`, `tests/data/inf_values.xlsx`
- Create: `tests/file_io_unit_test.adb`
- Modify: `sdata.gpr`
- Modify: `Makefile`

- [ ] **Step 1: Verify fixture files exist**

```bash
ls -la tests/data/inf_values.ods tests/data/inf_values.xlsx
```
Expected: both files exist with non-zero size (849 bytes and 1643 bytes respectively). If missing, re-create them:
```bash
printf 'USE "tests/data/inf_values.csv"\nSAVE "tests/data/inf_values.ods" /overwrite\nSAVE "tests/data/inf_values.xlsx" /overwrite\nRUN\nQUIT\n' | ./bin/sdata --batch
```

- [ ] **Step 2: Create `tests/file_io_unit_test.adb`**

```ada
--  Unit tests for SData.File_IO: Parse_CSV, Parse_ODF, Parse_OOXML.
--  Calls parsers directly with fixture files in tests/data/ and
--  inspects the resulting SData.Table state via the public API.
--  Must be run from the project root (paths are relative to it).

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with SData;
with SData.Config;
with SData.Table;           use SData.Table;
with SData.Values;          use SData.Values;
with SData.File_IO;         use SData.File_IO;

procedure File_IO_Unit_Test is
   Passed : Natural := 0;
   Failed : Natural := 0;

   procedure Check (Name : String; Got, Expected : Boolean) is
   begin
      if Got = Expected then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got=" & Got'Image & "  expected=" & Expected'Image);
         Failed := Failed + 1;
      end if;
   end Check;

   procedure Check (Name : String; Got, Expected : Integer) is
   begin
      if Got = Expected then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got=" & Got'Image & "  expected=" & Expected'Image);
         Failed := Failed + 1;
      end if;
   end Check;

   procedure Check (Name : String; Got, Expected : String) is
   begin
      if Got = Expected then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got=[" & Got & "]  expected=[" & Expected & "]");
         Failed := Failed + 1;
      end if;
   end Check;

   procedure Check_Float (Name : String; Got, Expected : Float;
                          Tol : Float := 0.001) is
   begin
      if abs (Got - Expected) <= Tol then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got=" & Got'Image & "  expected=" & Expected'Image);
         Failed := Failed + 1;
      end if;
   end Check_Float;

   V : Value;
   pragma Unreferenced (V);

begin
   SData.Config.Quiet_Mode := True;

   ---------------------------------------------------------------------------
   --  Parse_CSV tests  (PC-01 .. PC-24)  — added in Task 2
   ---------------------------------------------------------------------------

   ---------------------------------------------------------------------------
   --  Parse_ODF tests  (PO-01 .. PO-23)  — added in Task 3
   ---------------------------------------------------------------------------

   ---------------------------------------------------------------------------
   --  Parse_OOXML tests  (PX-01 .. PX-23)  — added in Task 4
   ---------------------------------------------------------------------------

   ---------------------------------------------------------------------------
   --  Summary
   ---------------------------------------------------------------------------
   New_Line;
   Put_Line (Passed'Image & " passed," & Failed'Image & " failed.");
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;

end File_IO_Unit_Test;
```

- [ ] **Step 3: Add to `sdata.gpr`**

Current `sdata.gpr` Main list (line 12):
```
   for Main use ("sdata_main.adb", "csv_unit_test.adb", "sdata_unit_test.adb", "evaluator_unit_test.adb");
```

Replace with:
```
   for Main use ("sdata_main.adb", "csv_unit_test.adb", "sdata_unit_test.adb", "evaluator_unit_test.adb", "file_io_unit_test.adb");
```

Current Builder section ends at:
```
      for Executable ("evaluator_unit_test.adb") use "evaluator_unit_test";
```

Add after it (before `end Builder;`):
```
      for Executable ("file_io_unit_test.adb")   use "file_io_unit_test";
```

- [ ] **Step 4: Add to `Makefile`**

In the `check` target, find the evaluator_unit_test block:
```makefile
	@[ -x bin/evaluator_unit_test ] || $(GPRBUILD) -P $(GPR_FILE)
	@$(TIMEOUT) 30 ./bin/evaluator_unit_test; \
	 if [ $$? -ne 0 ]; then \
	   echo "Unit tests FAILED"; exit 1; \
	 fi
```

Add immediately after it:
```makefile
	@[ -x bin/file_io_unit_test ] || $(GPRBUILD) -P $(GPR_FILE)
	@$(TIMEOUT) 30 ./bin/file_io_unit_test; \
	 if [ $$? -ne 0 ]; then \
	   echo "Unit tests FAILED"; exit 1; \
	 fi
```

- [ ] **Step 5: Build**

```bash
cd /home/jries/Develop/sdata && alr build 2>&1 | grep -E "error:" | head -10
```
Expected: no errors. (The `pragma Unreferenced (V)` suppresses the unused-variable warning until tests are added in Tasks 2–4.)

- [ ] **Step 6: Verify scaffold runs**

```bash
./bin/file_io_unit_test
```
Expected output:
```
 0 passed, 0 failed.
```
Exit status 0 (no failures because there are no tests yet).

- [ ] **Step 7: Run make check to confirm existing tests still pass**

```bash
make check 2>&1 | tail -5
```
Expected: `All 128 tests passed.`

- [ ] **Step 8: Commit**

```bash
git add tests/data/inf_values.ods tests/data/inf_values.xlsx \
        tests/file_io_unit_test.adb sdata.gpr Makefile
git commit -m "Test: add file_io_unit_test scaffold and INF fixtures"
```

---

### Task 2: Parse_CSV tests (PC-01 .. PC-24)

Adds 24 tests covering basic loading, column names, INF values, missing values, pipe delimiter, Skip_Rows, and Max_Rows.

**Files:**
- Modify: `tests/file_io_unit_test.adb`

- [ ] **Step 1: Replace the Parse_CSV placeholder comment**

Find this block in `file_io_unit_test.adb`:
```ada
   ---------------------------------------------------------------------------
   --  Parse_CSV tests  (PC-01 .. PC-24)  — added in Task 2
   ---------------------------------------------------------------------------
```

Replace it with:
```ada
   ---------------------------------------------------------------------------
   --  Parse_CSV tests  (PC-01 .. PC-24)
   ---------------------------------------------------------------------------

   --  PC-01..PC-09: basic load of tests/data/sample.csv
   --  Contents: CATEGORY,VAL1,VAL2,VAL3; 6 rows.
   --  CATEGORY column contains "A","B","C" → inferred Col_String → renamed CATEGORY$.
   Parse_CSV ("tests/data/sample.csv");
   Check ("PC-01 col count",           Column_Count,    4);
   Check ("PC-02 row count",           Row_Count,       6);
   Check ("PC-03 col 1 name",          Column_Name (1), "CATEGORY$");
   Check ("PC-04 col 2 name",          Column_Name (2), "VAL1");
   V := Get_Value (1, "CATEGORY$");
   Check      ("PC-05 row1 CATEGORY$ kind",  V.Kind = Val_String, True);
   Check      ("PC-06 row1 CATEGORY$ value", To_String (V.Str_Val), "A");
   V := Get_Value (1, "VAL1");
   Check      ("PC-07 row1 VAL1 kind",       V.Kind = Val_Numeric, True);
   Check_Float ("PC-08 row1 VAL1",            V.Num_Val, 1.0);
   V := Get_Value (6, "VAL3");
   Check_Float ("PC-09 row6 VAL3",            V.Num_Val, 18.0);

   --  PC-10..PC-13: INF values in tests/data/inf_values.csv
   --  Contents: X,Y,Z; row 1 = Inf,-Inf,1.5
   Parse_CSV ("tests/data/inf_values.csv");
   V := Get_Value (1, "X");
   Check ("PC-10 INF row1 X kind",    V.Kind = Val_Numeric, True);
   Check ("PC-11 INF row1 X Pos_Inf",
          Is_Inf (V.Num_Val) and then V.Num_Val > 0.0, True);
   V := Get_Value (1, "Y");
   Check ("PC-12 INF row1 Y Neg_Inf",
          Is_Inf (V.Num_Val) and then V.Num_Val < 0.0, True);
   V := Get_Value (1, "Z");
   Check_Float ("PC-13 INF row1 Z normal", V.Num_Val, 1.5);

   --  PC-14..PC-15: header-only file (no data rows)
   --  Contents: A,B,C  (one header line, nothing else)
   Parse_CSV ("tests/data/header_only.csv");
   Check ("PC-14 header-only col count", Column_Count, 3);
   Check ("PC-15 header-only row count", Row_Count,    0);

   --  PC-16..PC-17: missing value — first field is "." sentinel
   --  Contents: X,Y / .,10 / 20,30 / 40,50
   Parse_CSV ("tests/data/missing_first.csv");
   V := Get_Value (1, "X");
   Check ("PC-16 missing val kind", V.Kind = Val_Missing, True);
   V := Get_Value (1, "Y");
   Check_Float ("PC-17 non-missing beside missing", V.Num_Val, 10.0);

   --  PC-18..PC-20: pipe delimiter
   --  Contents: NAME$|SCORE / Alice|90 / Bob|85
   Parse_CSV ("tests/data/pipe_delim.csv", Delimiter => "|");
   Check ("PC-18 pipe col count",    Column_Count, 2);
   Check ("PC-19 pipe row count",    Row_Count,    2);
   V := Get_Value (1, "NAME$");
   Check ("PC-20 pipe row1 NAME$",  To_String (V.Str_Val), "Alice");

   --  PC-21..PC-22: Skip_Rows=2 skips the first two data rows (both "A" rows)
   --  sample.csv rows: A/1/2/3, A/4/5/6, B/7/8/9, B/10/11/12, B/13/14/15, C/16/17/18
   --  After skipping 2: 4 rows remain; row 1 is B/7/8/9
   Parse_CSV ("tests/data/sample.csv", Skip_Rows => 2);
   Check ("PC-21 skip_rows=2 row count",  Row_Count, 4);
   V := Get_Value (1, "CATEGORY$");
   Check ("PC-22 skip_rows=2 row1 cat",  To_String (V.Str_Val), "B");

   --  PC-23..PC-24: Max_Rows=2 limits the result to the first two data rows
   Parse_CSV ("tests/data/sample.csv", Max_Rows => 2);
   Check ("PC-23 max_rows=2 row count", Row_Count, 2);
   V := Get_Value (2, "VAL1");
   Check_Float ("PC-24 max_rows=2 row2 VAL1", V.Num_Val, 4.0);
```

Also remove the `pragma Unreferenced (V);` line — `V` is now used. (Search for it and delete it.)

- [ ] **Step 2: Build and run**

```bash
alr build 2>&1 | grep "error:" | head -10
```
Expected: no errors.

```bash
./bin/file_io_unit_test 2>&1 | grep -E "FAIL|passed"
```
Expected: all 24 tests pass; last line: ` 24 passed, 0 failed.`

- [ ] **Step 3: Full check**

```bash
make check 2>&1 | tail -5
```
Expected: `All 128 tests passed.`

- [ ] **Step 4: Commit**

```bash
git add tests/file_io_unit_test.adb
git commit -m "Test: add Parse_CSV unit tests (PC-01..PC-24)"
```

---

### Task 3: Parse_ODF tests (PO-01 .. PO-23)

Adds 23 tests for `Parse_ODF`: basic loading, dollar-column name preservation, INF values, sheet selection, Skip_Rows, Max_Rows, and bad-file error.

**Files:**
- Modify: `tests/file_io_unit_test.adb`

- [ ] **Step 1: Replace the Parse_ODF placeholder comment**

Find:
```ada
   ---------------------------------------------------------------------------
   --  Parse_ODF tests  (PO-01 .. PO-23)  — added in Task 3
   ---------------------------------------------------------------------------
```

Replace with:
```ada
   ---------------------------------------------------------------------------
   --  Parse_ODF tests  (PO-01 .. PO-23)
   ---------------------------------------------------------------------------

   --  PO-01..PO-09: basic load of tests/data/sample.ods
   --  Contents: ID (numeric), NAME$ (string), SALARY (numeric); 3 rows.
   --  Row 1: ID=1, NAME$="Alice", SALARY=50000
   --  Row 2: ID=2, NAME$="Bob",   SALARY=60000
   --  Row 3: ID=3, NAME$="Charlie", SALARY=70000
   Parse_ODF ("tests/data/sample.ods");
   Check ("PO-01 col count",           Column_Count,    3);
   Check ("PO-02 row count",           Row_Count,       3);
   Check ("PO-03 col 1 name",          Column_Name (1), "ID");
   Check ("PO-04 col 2 name",          Column_Name (2), "NAME$");
   Check ("PO-05 col 3 name",          Column_Name (3), "SALARY");
   V := Get_Value (1, "ID");
   Check_Float ("PO-06 row1 ID",          V.Num_Val, 1.0);
   V := Get_Value (2, "NAME$");
   Check      ("PO-07 row2 NAME$ kind",   V.Kind = Val_String, True);
   Check      ("PO-08 row2 NAME$ value",  To_String (V.Str_Val), "Bob");
   V := Get_Value (3, "SALARY");
   Check_Float ("PO-09 row3 SALARY",      V.Num_Val, 70000.0);

   --  PO-10..PO-13: INF values in tests/data/inf_values.ods
   --  Contents: X,Y,Z; row 1 = Pos_Inf, Neg_Inf, 1.5
   Parse_ODF ("tests/data/inf_values.ods");
   V := Get_Value (1, "X");
   Check ("PO-10 INF row1 X kind",    V.Kind = Val_Numeric, True);
   Check ("PO-11 INF row1 X Pos_Inf",
          Is_Inf (V.Num_Val) and then V.Num_Val > 0.0, True);
   V := Get_Value (1, "Y");
   Check ("PO-12 INF row1 Y Neg_Inf",
          Is_Inf (V.Num_Val) and then V.Num_Val < 0.0, True);
   V := Get_Value (2, "Z");
   Check_Float ("PO-13 INF row2 Z normal", V.Num_Val, 2.5);

   --  PO-14..PO-17: sheet selection — "Scores" sheet
   --  Contents: ID (numeric), NAME$ (string), SCORE (numeric); 2 rows.
   --  Row 1: ID=1, NAME$="Alice", SCORE=95
   Parse_ODF ("tests/data/multi_sheet.ods", Sheet_Name => "Scores");
   Check ("PO-14 Scores col count",      Column_Count, 3);
   Check ("PO-15 Scores row count",      Row_Count,    2);
   V := Get_Value (1, "NAME$");
   Check ("PO-16 Scores row1 NAME$",     To_String (V.Str_Val), "Alice");
   V := Get_Value (1, "SCORE");
   Check_Float ("PO-17 Scores row1 SCORE", V.Num_Val, 95.0);

   --  PO-18..PO-19: sheet selection — "Metadata" sheet
   --  Contents: KEY$ (string), VALUE$ (string); 2 rows.
   --  Row 1: KEY$="Version", VALUE$="1.0"
   Parse_ODF ("tests/data/multi_sheet.ods", Sheet_Name => "Metadata");
   Check ("PO-18 Metadata col count",       Column_Count, 2);
   V := Get_Value (1, "KEY$");
   Check ("PO-19 Metadata row1 KEY$",       To_String (V.Str_Val), "Version");

   --  PO-20..PO-21: Skip_Rows=1 skips Alice; row 1 becomes Bob
   Parse_ODF ("tests/data/sample.ods", Skip_Rows => 1);
   Check ("PO-20 skip_rows=1 row count",   Row_Count, 2);
   V := Get_Value (1, "NAME$");
   Check ("PO-21 skip_rows=1 row1 NAME$",  To_String (V.Str_Val), "Bob");

   --  PO-22: Max_Rows=2 limits result to first two data rows
   Parse_ODF ("tests/data/sample.ods", Max_Rows => 2);
   Check ("PO-22 max_rows=2 row count",    Row_Count, 2);

   --  PO-23: corrupt zip file raises SData.Script_Error
   declare
      Raised : Boolean := False;
   begin
      Parse_ODF ("tests/data/bad.ods");
   exception
      when SData.Script_Error => Raised := True;
   end;
   Check ("PO-23 bad ODS raises Script_Error", Raised, True);
```

- [ ] **Step 2: Build and run**

```bash
alr build 2>&1 | grep "error:" | head -10
```
Expected: no errors.

```bash
./bin/file_io_unit_test 2>&1 | grep -E "FAIL|passed"
```
Expected: last line ` 47 passed, 0 failed.` (24 CSV + 23 ODF).

- [ ] **Step 3: Full check**

```bash
make check 2>&1 | tail -5
```
Expected: `All 128 tests passed.`

- [ ] **Step 4: Commit**

```bash
git add tests/file_io_unit_test.adb
git commit -m "Test: add Parse_ODF unit tests (PO-01..PO-23)"
```

---

### Task 4: Parse_OOXML tests (PX-01 .. PX-23)

Adds 23 tests for `Parse_OOXML`, mirroring the ODF suite exactly but using `.xlsx` fixtures.

**Files:**
- Modify: `tests/file_io_unit_test.adb`

- [ ] **Step 1: Replace the Parse_OOXML placeholder comment**

Find:
```ada
   ---------------------------------------------------------------------------
   --  Parse_OOXML tests  (PX-01 .. PX-23)  — added in Task 4
   ---------------------------------------------------------------------------
```

Replace with:
```ada
   ---------------------------------------------------------------------------
   --  Parse_OOXML tests  (PX-01 .. PX-23)
   ---------------------------------------------------------------------------

   --  PX-01..PX-09: basic load of tests/data/sample.xlsx
   --  Same schema as sample.ods: ID (numeric), NAME$ (string), SALARY (numeric); 3 rows.
   Parse_OOXML ("tests/data/sample.xlsx");
   Check ("PX-01 col count",           Column_Count,    3);
   Check ("PX-02 row count",           Row_Count,       3);
   Check ("PX-03 col 1 name",          Column_Name (1), "ID");
   Check ("PX-04 col 2 name",          Column_Name (2), "NAME$");
   Check ("PX-05 col 3 name",          Column_Name (3), "SALARY");
   V := Get_Value (1, "ID");
   Check_Float ("PX-06 row1 ID",          V.Num_Val, 1.0);
   V := Get_Value (2, "NAME$");
   Check      ("PX-07 row2 NAME$ kind",   V.Kind = Val_String, True);
   Check      ("PX-08 row2 NAME$ value",  To_String (V.Str_Val), "Bob");
   V := Get_Value (3, "SALARY");
   Check_Float ("PX-09 row3 SALARY",      V.Num_Val, 70000.0);

   --  PX-10..PX-13: INF values in tests/data/inf_values.xlsx
   Parse_OOXML ("tests/data/inf_values.xlsx");
   V := Get_Value (1, "X");
   Check ("PX-10 INF row1 X kind",    V.Kind = Val_Numeric, True);
   Check ("PX-11 INF row1 X Pos_Inf",
          Is_Inf (V.Num_Val) and then V.Num_Val > 0.0, True);
   V := Get_Value (1, "Y");
   Check ("PX-12 INF row1 Y Neg_Inf",
          Is_Inf (V.Num_Val) and then V.Num_Val < 0.0, True);
   V := Get_Value (2, "Z");
   Check_Float ("PX-13 INF row2 Z normal", V.Num_Val, 2.5);

   --  PX-14..PX-17: sheet selection — "Scores" sheet
   Parse_OOXML ("tests/data/multi_sheet.xlsx", Sheet_Name => "Scores");
   Check ("PX-14 Scores col count",      Column_Count, 3);
   Check ("PX-15 Scores row count",      Row_Count,    2);
   V := Get_Value (1, "NAME$");
   Check ("PX-16 Scores row1 NAME$",     To_String (V.Str_Val), "Alice");
   V := Get_Value (1, "SCORE");
   Check_Float ("PX-17 Scores row1 SCORE", V.Num_Val, 95.0);

   --  PX-18..PX-19: sheet selection — "Metadata" sheet
   Parse_OOXML ("tests/data/multi_sheet.xlsx", Sheet_Name => "Metadata");
   Check ("PX-18 Metadata col count",       Column_Count, 2);
   V := Get_Value (1, "KEY$");
   Check ("PX-19 Metadata row1 KEY$",       To_String (V.Str_Val), "Version");

   --  PX-20..PX-21: Skip_Rows=1 skips Alice; row 1 becomes Bob
   Parse_OOXML ("tests/data/sample.xlsx", Skip_Rows => 1);
   Check ("PX-20 skip_rows=1 row count",   Row_Count, 2);
   V := Get_Value (1, "NAME$");
   Check ("PX-21 skip_rows=1 row1 NAME$",  To_String (V.Str_Val), "Bob");

   --  PX-22: Max_Rows=2 limits result to first two data rows
   Parse_OOXML ("tests/data/sample.xlsx", Max_Rows => 2);
   Check ("PX-22 max_rows=2 row count",    Row_Count, 2);

   --  PX-23: corrupt zip file raises SData.Script_Error
   declare
      Raised : Boolean := False;
   begin
      Parse_OOXML ("tests/data/bad.xlsx");
   exception
      when SData.Script_Error => Raised := True;
   end;
   Check ("PX-23 bad XLSX raises Script_Error", Raised, True);
```

- [ ] **Step 2: Build and run**

```bash
alr build 2>&1 | grep "error:" | head -10
```
Expected: no errors.

```bash
./bin/file_io_unit_test 2>&1 | grep -E "FAIL|passed"
```
Expected: last line ` 70 passed, 0 failed.` (24 CSV + 23 ODF + 23 OOXML).

- [ ] **Step 3: Full check**

```bash
make check 2>&1 | tail -5
```
Expected: `All 128 tests passed.`

- [ ] **Step 4: Commit**

```bash
git add tests/file_io_unit_test.adb
git commit -m "Test: add Parse_OOXML unit tests (PX-01..PX-23)"
```

---

## Self-Review Notes

**Spec coverage:**
- Parse_CSV: basic load ✓, column names ✓, INF values ✓, missing values ✓, pipe delimiter ✓, Skip_Rows ✓, Max_Rows ✓
- Parse_ODF: basic load ✓, dollar-column name preserved ✓, INF values ✓, sheet selection ✓, Skip_Rows ✓, Max_Rows ✓, bad-file error ✓
- Parse_OOXML: same coverage as ODF ✓
- Dollar-suffix override (Apply_Dollar_Override): covered implicitly — NAME$ in sample.ods/xlsx is a string column whose name ends in `$`; PO-04/PO-07/PX-04/PX-07 verify it parses as Val_String. A fixture with numeric-looking values in a `$`-column was considered but deferred because Process_Line_Direct does not currently coerce numerics to strings for $-suffix CSV columns (pre-existing limitation); ODF/OOXML dollar override requires the cell to be stored as a text cell to survive the data-loading phase.

**Placeholder scan:** No TBD, no incomplete steps. All code blocks complete.

**Type consistency:**
- `Check (name, bool, bool)` overload used for all boolean assertions
- `Check (name, int, int)` overload used for `Column_Count` and `Row_Count`
- `Check (name, str, str)` overload used for column names and string values
- `Check_Float` used for all float assertions
- `V : Value` declared once at top; reused across all test sections
- `SData.Script_Error` referenced as qualified name (needs `with SData;`)
- `Is_Inf (V.Num_Val)` from `SData.Values` — correct public function
- `To_String (V.Str_Val)` — uses `Ada.Strings.Unbounded.To_String`, in scope via `use Ada.Strings.Unbounded`
