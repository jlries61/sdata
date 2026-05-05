# Parse_CSV Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the six pure CSV string helpers from the `Parse_CSV` monolith into a new `SData.CSV` package and add a compiled unit-test executable that exercises them.

**Architecture:** New `src/sdata-csv.ads` / `src/sdata-csv.adb` owns the field-boundary types and six pure helpers; `sdata-file_io.adb` gains a `with SData.CSV; use SData.CSV;` clause and loses the six nested bodies and their local type declarations. A `tests/csv_unit_test.adb` standalone Ada executable tests all six functions. Build and Makefile are updated to compile and run the new test binary before the existing `.cmd` suite.

**Tech Stack:** Ada 2012, GNAT, Alire (`alr build` to compile), `make check` to run the full test suite.

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `src/sdata-csv.ads` | Create | Public spec: types + six function signatures |
| `src/sdata-csv.adb` | Create | Pure implementations (no Table/IO dependencies) |
| `tests/csv_unit_test.adb` | Create | Standalone Ada test executable (21+ assertions) |
| `sdata.gpr` | Modify | Add `"tests"` to Source_Dirs; add `csv_unit_test` to Main + Builder |
| `Makefile` | Modify | Run `./bin/csv_unit_test` before `.cmd` loop in `check` target |
| `src/sdata-file_io.adb` | Modify | Add `with SData.CSV; use SData.CSV;`; remove 6 nested helpers + local types; update 3 call sites |

---

## Task 1: Create SData.CSV stub, test harness, and update build config

**Files:**
- Create: `src/sdata-csv.ads`
- Create: `src/sdata-csv.adb` (stub bodies — return wrong values so tests fail)
- Create: `tests/csv_unit_test.adb`
- Modify: `sdata.gpr`
- Modify: `Makefile`

- [ ] **Step 1: Create `src/sdata-csv.ads`**

```ada
package SData.CSV is

   Max_Fields : constant := 65_536;
   type Field_Pair  is record S, E : Natural; end record;
   type Field_Array is array (1 .. Max_Fields) of Field_Pair;

   function Try_Fast_Float   (S         : String;
                               Result    : out Float) return Boolean;

   function Is_Numeric_Field (F : String) return Boolean;

   function At_Delimiter     (Line      : String;
                               Pos       : Positive;
                               Delimiter : String) return Boolean;

   function CSV_Field_End    (Line      : String;
                               From      : Positive;
                               Delimiter : String) return Natural;

   function CSV_Unquote      (Raw : String) return String;

   function Split_Indices    (Line      : String;
                               Delimiter : String;
                               N_Fields  : out Natural) return Field_Array;

end SData.CSV;
```

- [ ] **Step 2: Create `src/sdata-csv.adb` with stub bodies**

These stubs compile cleanly but return wrong values so the test harness fails.

```ada
package body SData.CSV is

   function Try_Fast_Float (S : String; Result : out Float) return Boolean is
      pragma Unreferenced (S);
   begin
      Result := 0.0;
      return False;
   end Try_Fast_Float;

   function Is_Numeric_Field (F : String) return Boolean is
      pragma Unreferenced (F);
   begin
      return False;
   end Is_Numeric_Field;

   function At_Delimiter (Line      : String;
                           Pos       : Positive;
                           Delimiter : String) return Boolean is
      pragma Unreferenced (Line, Pos, Delimiter);
   begin
      return False;
   end At_Delimiter;

   function CSV_Field_End (Line      : String;
                            From      : Positive;
                            Delimiter : String) return Natural is
      pragma Unreferenced (Line, From, Delimiter);
   begin
      return 0;
   end CSV_Field_End;

   function CSV_Unquote (Raw : String) return String is
   begin
      return Raw;
   end CSV_Unquote;

   function Split_Indices (Line      : String;
                            Delimiter : String;
                            N_Fields  : out Natural) return Field_Array is
      pragma Unreferenced (Line, Delimiter);
      Res : Field_Array;
   begin
      N_Fields := 0;
      return Res;
   end Split_Indices;

end SData.CSV;
```

- [ ] **Step 3: Create `tests/csv_unit_test.adb`**

```ada
with Ada.Text_IO;      use Ada.Text_IO;
with Ada.Command_Line;
with SData.CSV;        use SData.CSV;

procedure CSV_Unit_Test is
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

   procedure Check_Nat (Name : String; Got, Expected : Natural) is
   begin
      if Got = Expected then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got=" & Got'Image & "  expected=" & Expected'Image);
         Failed := Failed + 1;
      end if;
   end Check_Nat;

   procedure Check_Str (Name : String; Got, Expected : String) is
   begin
      if Got = Expected then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got=[" & Got & "]  expected=[" & Expected & "]");
         Failed := Failed + 1;
      end if;
   end Check_Str;

   procedure Check_Float (Name    : String;
                           Got_Ok  : Boolean; Got_Val  : Float;
                           Exp_Ok  : Boolean; Exp_Val  : Float;
                           Tol     : Float := 0.001) is
   begin
      if Got_Ok = Exp_Ok
         and then (not Exp_Ok or else abs (Got_Val - Exp_Val) <= Tol)
      then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got_ok=" & Got_Ok'Image & "  exp_ok=" & Exp_Ok'Image);
         Failed := Failed + 1;
      end if;
   end Check_Float;

   R  : Float;
   N  : Natural;
   FA : Field_Array;

begin
   --  ── Try_Fast_Float ────────────────────────────────────────────────────
   Check_Float ("TFF-1 integer",
      Try_Fast_Float ("42", R),    R, True,  42.0);
   Check_Float ("TFF-2 negative decimal",
      Try_Fast_Float ("-3.14", R), R, True,  -3.14);
   Check_Float ("TFF-3 scientific",
      Try_Fast_Float ("1.5E3", R), R, True,  1500.0);
   Check_Float ("TFF-4 empty",
      Try_Fast_Float ("", R),      R, False, 0.0);
   Check_Float ("TFF-5 non-numeric",
      Try_Fast_Float ("abc", R),   R, False, 0.0);

   --  ── Is_Numeric_Field ──────────────────────────────────────────────────
   Check ("INF-1 numeric",  Is_Numeric_Field ("42"), True);
   Check ("INF-2 dot",      Is_Numeric_Field ("."),  False);
   Check ("INF-3 empty",    Is_Numeric_Field (""),   False);

   --  ── At_Delimiter ──────────────────────────────────────────────────────
   Check ("ATD-1 comma match",  At_Delimiter ("a,b", 2, ","),               True);
   Check ("ATD-2 no match",     At_Delimiter ("a,b", 1, ","),               False);
   Check ("ATD-3 tab match",
      At_Delimiter ("a" & ASCII.HT & "b", 2, "" & ASCII.HT),               True);

   --  ── CSV_Field_End ─────────────────────────────────────────────────────
   Check_Nat ("CFE-1 first field",  CSV_Field_End ("a,b,c",     1, ","), 2);
   Check_Nat ("CFE-2 last field",   CSV_Field_End ("a,b,c",     5, ","), 0);
   Check_Nat ("CFE-3 quoted field", CSV_Field_End ("""hi"",b",  1, ","), 5);

   --  ── CSV_Unquote ───────────────────────────────────────────────────────
   Check_Str ("CUQ-1 double-quoted",  CSV_Unquote ("""hello"""),       "hello");
   Check_Str ("CUQ-2 doubled-quote",  CSV_Unquote ("""he""""llo"""),   "he""llo");
   Check_Str ("CUQ-3 untrimmed",      CSV_Unquote ("  hello  "),       "hello");
   Check_Str ("CUQ-4 single-quoted",  CSV_Unquote ("'world'"),         "world");

   --  ── Split_Indices ─────────────────────────────────────────────────────
   FA := Split_Indices ("a,b,c", ",", N);
   Check_Nat ("SI-1 count",  N,        3);
   Check_Nat ("SI-1 f1.S",   FA(1).S,  1);
   Check_Nat ("SI-1 f1.E",   FA(1).E,  1);
   Check_Nat ("SI-1 f2.S",   FA(2).S,  3);
   Check_Nat ("SI-1 f2.E",   FA(2).E,  3);
   Check_Nat ("SI-1 f3.S",   FA(3).S,  5);
   Check_Nat ("SI-1 f3.E",   FA(3).E,  5);

   FA := Split_Indices ("", ",", N);
   Check_Nat ("SI-2 empty count", N, 0);

   --  Input """a,b"",c""" is the Ada literal for the string: "a,b",c
   --  Positions: 1=" 2=a 3=, 4=b 5=" 6=, 7=c
   --  Field 1 = positions 1..5 (the quoted span); field 2 = position 7
   FA := Split_Indices ("""a,b"",c", ",", N);
   Check_Nat ("SI-3 quoted count", N,       2);
   Check_Nat ("SI-3 f1.S",         FA(1).S, 1);
   Check_Nat ("SI-3 f1.E",         FA(1).E, 5);
   Check_Nat ("SI-3 f2.S",         FA(2).S, 7);
   Check_Nat ("SI-3 f2.E",         FA(2).E, 7);

   --  ── Summary ───────────────────────────────────────────────────────────
   New_Line;
   Put_Line (Passed'Image & " passed," & Failed'Image & " failed.");
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end CSV_Unit_Test;
```

- [ ] **Step 4: Update `sdata.gpr`**

Replace the entire file with:

```ada
with "zipada";
with "xmlada_dom";
with "xmlada_input";
with "mathpaqs";
with "ada_sqlite3";

project SData is
   for Source_Dirs use ("src/**", "tests");
   for Object_Dir use "obj";
   for Exec_Dir use "bin";
   for Main use ("sdata_main.adb", "csv_unit_test.adb");

   package Compiler is
      for Default_Switches ("Ada") use ("-gnat2012", "-gnatwa", "-gnatwl", "-gnatwu", "-g", "-O2");
   end Compiler;

   package Builder is
      for Default_Switches ("Ada") use ("-g");
      for Executable ("sdata_main.adb")    use "sdata";
      for Executable ("csv_unit_test.adb") use "csv_unit_test";
   end Builder;
end SData;
```

- [ ] **Step 5: Update `Makefile` — add unit-test run to `check` target**

In the `check` target, insert after `@echo "Running tests..."` and before the `@failures=0` line:

```makefile
	@echo "Running unit tests..."
	@$(TIMEOUT) 30 ./bin/csv_unit_test; \
	 if [ $$? -ne 0 ]; then \
	   echo "Unit tests FAILED"; exit 1; \
	 fi
	@echo ""
```

The full `check` target becomes:

```makefile
check: build
	@echo "Running tests..."
	@echo "Running unit tests..."
	@$(TIMEOUT) 30 ./bin/csv_unit_test; \
	 if [ $$? -ne 0 ]; then \
	   echo "Unit tests FAILED"; exit 1; \
	 fi
	@echo ""
	@failures=0; failed_list=""; total=0; \
	for f in tests/*.cmd; do \
```

- [ ] **Step 6: Build and confirm the test harness compiles but fails**

```bash
alr build
```

Expected: `Success: Build finished successfully` — both `bin/sdata` and `bin/csv_unit_test` produced.

```bash
./bin/csv_unit_test; echo "Exit: $?"
```

Expected: multiple `FAIL:` lines (stubs return wrong values), `Exit: 1`.

- [ ] **Step 7: Commit the failing scaffold**

```bash
git add src/sdata-csv.ads src/sdata-csv.adb tests/csv_unit_test.adb sdata.gpr Makefile
git commit -m "Add SData.CSV stub, unit test harness, and build wiring (tests fail)"
```

---

## Task 2: Implement SData.CSV body

**Files:**
- Modify: `src/sdata-csv.adb`

The implementations are lifted verbatim from the nested functions in `src/sdata-file_io.adb:357–553`, with the `Delimiter` closure parameter replaced by an explicit `Delimiter : String` argument.

- [ ] **Step 1: Replace `src/sdata-csv.adb` with the full implementation**

```ada
with Ada.Strings;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body SData.CSV is

   function Try_Fast_Float (S : String; Result : out Float) return Boolean is
      I         : Integer := S'First;
      Whole     : Float   := 0.0;
      Frac      : Float   := 0.0;
      Denom     : Float   := 1.0;
      Sign      : Float   := 1.0;
      After_Dot : Boolean := False;
      Has_Digit : Boolean := False;
   begin
      if I > S'Last then return False; end if;
      if    S (I) = '-' then Sign := -1.0; I := I + 1;
      elsif S (I) = '+' then               I := I + 1;
      end if;
      while I <= S'Last loop
         case S (I) is
            when '0' .. '9' =>
               Has_Digit := True;
               if After_Dot then
                  Denom := Denom * 10.0;
                  Frac  := Frac + Float (Character'Pos (S (I)) - 48) / Denom;
               else
                  Whole := Whole * 10.0 + Float (Character'Pos (S (I)) - 48);
               end if;
            when '.' =>
               if After_Dot then return False; end if;
               After_Dot := True;
            when 'E' | 'e' | 'D' | 'd' =>
               begin
                  Result := Float'Value (S);
                  return True;
               exception
                  when others => return False;
               end;
            when others => return False;
         end case;
         I := I + 1;
      end loop;
      if not Has_Digit then return False; end if;
      Result := Sign * (Whole + Frac);
      return True;
   end Try_Fast_Float;

   function Is_Numeric_Field (F : String) return Boolean is
      Dummy : Float;
   begin
      return Try_Fast_Float (F, Dummy);
   end Is_Numeric_Field;

   function At_Delimiter (Line      : String;
                           Pos       : Positive;
                           Delimiter : String) return Boolean is
      DLen : constant Positive :=
         (if Delimiter'Length > 0 then Delimiter'Length else 1);
   begin
      if Pos + DLen - 1 > Line'Last then return False; end if;
      if DLen = 1 then return Line (Pos) = Delimiter (Delimiter'First); end if;
      return Line (Pos .. Pos + DLen - 1) = Delimiter;
   end At_Delimiter;

   function CSV_Field_End (Line      : String;
                            From      : Positive;
                            Delimiter : String) return Natural is
      I : Positive := From;
      Q : Character;
   begin
      if I > Line'Last then return 0; end if;
      if Line (I) = '"' or else Line (I) = ''' then
         Q := Line (I);
         I := I + 1;
         while I <= Line'Last loop
            if Line (I) = Q then
               if I < Line'Last and then Line (I + 1) = Q then
                  I := I + 2;
               else
                  I := I + 1;
                  exit;
               end if;
            else
               I := I + 1;
            end if;
         end loop;
         if At_Delimiter (Line, I, Delimiter) then return I; end if;
         return 0;
      else
         for K in From .. Line'Last loop
            if At_Delimiter (Line, K, Delimiter) then return K; end if;
         end loop;
         return 0;
      end if;
   end CSV_Field_End;

   function CSV_Unquote (Raw : String) return String is
      T : constant String := Trim (Raw, Ada.Strings.Both);
      Q : Character;
      R : Unbounded_String;
      I : Positive;
   begin
      if T'Length >= 2
         and then (T (T'First) = '"' or else T (T'First) = ''')
         and then T (T'Last) = T (T'First)
      then
         Q := T (T'First);
         I := T'First + 1;
         while I <= T'Last - 1 loop
            if T (I) = Q and then I < T'Last - 1 and then T (I + 1) = Q then
               Append (R, Q);
               I := I + 2;
            else
               Append (R, T (I));
               I := I + 1;
            end if;
         end loop;
         return To_String (R);
      end if;
      return T;
   end CSV_Unquote;

   function Split_Indices (Line      : String;
                            Delimiter : String;
                            N_Fields  : out Natural) return Field_Array is
      Res   : Field_Array;
      Start : Integer := Line'First;
      Count : Natural := 0;
      DLen  : constant Positive :=
         (if Delimiter'Length > 0 then Delimiter'Length else 1);
   begin
      N_Fields := 0;
      if Line'Length = 0 then return Res; end if;
      loop
         declare
            Delim : constant Natural := CSV_Field_End (Line, Start, Delimiter);
         begin
            Count := Count + 1;
            if Count <= Max_Fields then
               Res (Count).S := Start;
               Res (Count).E := (if Delim > 0 then Delim - 1 else Line'Last);
            end if;
            exit when Delim = 0;
            Start := Delim + DLen;
         end;
      end loop;
      N_Fields := Count;
      return Res;
   end Split_Indices;

end SData.CSV;
```

- [ ] **Step 2: Build**

```bash
alr build
```

Expected: `Success: Build finished successfully`

- [ ] **Step 3: Run unit tests**

```bash
./bin/csv_unit_test
```

Expected output (all 27 assertions):

```
PASS: TFF-1 integer
PASS: TFF-2 negative decimal
PASS: TFF-3 scientific
PASS: TFF-4 empty
PASS: TFF-5 non-numeric
PASS: INF-1 numeric
PASS: INF-2 dot
PASS: INF-3 empty
PASS: ATD-1 comma match
PASS: ATD-2 no match
PASS: ATD-3 tab match
PASS: CFE-1 first field
PASS: CFE-2 last field
PASS: CFE-3 quoted field
PASS: CUQ-1 double-quoted
PASS: CUQ-2 doubled-quote
PASS: CUQ-3 untrimmed
PASS: CUQ-4 single-quoted
PASS: SI-1 count
PASS: SI-1 f1.S
PASS: SI-1 f1.E
PASS: SI-1 f2.S
PASS: SI-1 f2.E
PASS: SI-1 f3.S
PASS: SI-1 f3.E
PASS: SI-2 empty count
PASS: SI-3 quoted count
PASS: SI-3 f1.S
PASS: SI-3 f1.E
PASS: SI-3 f2.S
PASS: SI-3 f2.E

 31 passed,  0 failed.
```

Exit code: 0

- [ ] **Step 4: Commit**

```bash
git add src/sdata-csv.adb
git commit -m "Implement SData.CSV: extract pure CSV helpers from Parse_CSV"
```

---

## Task 3: Update sdata-file_io.adb

**Files:**
- Modify: `src/sdata-file_io.adb`

Remove the six nested helpers and their local types from `Parse_CSV`; add `with SData.CSV; use SData.CSV;`; update three call sites to pass `Delimiter` explicitly.

- [ ] **Step 1: Add `with SData.CSV; use SData.CSV;` to the file header**

Insert after line 17 (`with GNAT.Strings; use GNAT.Strings;`):

```ada
with SData.CSV;       use SData.CSV;
```

- [ ] **Step 2: Remove the six nested helper bodies and their local type declarations**

Inside `Parse_CSV` (starting at `sdata-file_io.adb:285`), delete the following blocks in their entirety:

1. **`Try_Fast_Float`** — the `function Try_Fast_Float … end Try_Fast_Float;` block (currently lines 357–398).

2. **`DLen` constant** (line 406–407) — delete:
   ```ada
   DLen : constant Positive :=
      (if Delimiter'Length > 0 then Delimiter'Length else 1);
   ```
   **Note:** `DLen` is still used by `Process_Line_Direct` at the line `Start := Delim_Pos + DLen;`. Keep a local `DLen` constant inside `Process_Line_Direct` instead (see Step 3).

3. **`At_Delimiter`** — the `function At_Delimiter … end At_Delimiter;` block.

4. **`CSV_Field_End`** — the `function CSV_Field_End … end CSV_Field_End;` block.

5. **`CSV_Unquote`** — the `function CSV_Unquote … end CSV_Unquote;` block.

6. **`Is_Numeric_Field`** — the `function Is_Numeric_Field … end Is_Numeric_Field;` block.

7. **`Max_Fields`, `Field_Pair`, `Field_Array`** — the three local type/constant declarations:
   ```ada
   Max_Fields : constant := 65536;
   type Field_Pair is record S, E : Natural; end record;
   type Field_Array is array (1 .. Max_Fields) of Field_Pair;
   ```

8. **`Split_Indices`** — the `function Split_Indices … end Split_Indices;` block.

- [ ] **Step 3: Update `Process_Line_Direct` — add local `DLen` and pass `Delimiter` to `CSV_Field_End`**

The updated `Process_Line_Direct` body (replacing the current one):

```ada
procedure Process_Line_Direct (Line : String; Names : String_List) is
   DLen        : constant Positive :=
      (if Delimiter'Length > 0 then Delimiter'Length else 1);
   Start       : Integer := Line'First;
   Field_Count : Natural := 0;
begin
   if Max_Rows > 0 and then Rows_Written >= Max_Rows then return; end if;
   Rows_Written := Rows_Written + 1;
   Add_Row;
   loop
      declare
         Delim_Pos : constant Natural := CSV_Field_End (Line, Start, Delimiter);
         Val       : Value;
         Num       : Float;
      begin
         declare
            Raw : constant String :=
               (if Delim_Pos > 0 then Line (Start .. Delim_Pos - 1)
                else                  Line (Start .. Line'Last));
            F   : constant String := CSV_Unquote (Raw);
         begin
            Field_Count := Field_Count + 1;
            if Field_Count <= Names'Length then
               if F = "" or else F = "." then
                  Val := (Kind => Val_Missing);
               elsif Try_Fast_Float (F, Num) then
                  Val := (Kind => Val_Numeric, Num_Val => Num);
               else
                  Val := (Kind    => Val_String,
                          Str_Val => To_Unbounded_String (F));
               end if;
               Set_Value_Upper (Row_Count, Names (Field_Count).all, Val);
            end if;
         end;
         exit when Delim_Pos = 0;
         Start := Delim_Pos + DLen;
      end;
   end loop;
end Process_Line_Direct;
```

- [ ] **Step 4: Update `Load_Columns_And_Data` — pass `Delimiter` to `Split_Indices`**

Two call sites inside `Load_Columns_And_Data`:

Change:
```ada
H_Idx : constant Field_Array := Split_Indices (H_Str, N_Hdr);
```
To:
```ada
H_Idx : constant Field_Array := Split_Indices (H_Str, Delimiter, N_Hdr);
```

Change:
```ada
D_Idx : constant Field_Array := Split_Indices (D_Str, N_Fld);
```
To:
```ada
D_Idx : constant Field_Array := Split_Indices (D_Str, Delimiter, N_Fld);
```

- [ ] **Step 5: Build**

```bash
alr build
```

Expected: `Success: Build finished successfully` with zero warnings.

If there are `unreferenced` warnings on `Max_Fields` from SData.CSV being visible but unused in the file body context, they are false positives from `use SData.CSV` — silence with a targeted `pragma Warnings (Off, "referenced")` or narrow the `use` to a local context inside `Parse_CSV`. In practice GNAT does not warn on re-exported names from `use` clauses so this should not arise.

- [ ] **Step 6: Run the full test suite**

```bash
make check
```

Expected:
```
Running unit tests...
 31 passed,  0 failed.

Running tests...
Testing tests/array_test.cmd... PASSED
...
All 99 tests passed.
```

- [ ] **Step 7: Commit**

```bash
git add src/sdata-file_io.adb
git commit -m "Remove Parse_CSV nested helpers; delegate to SData.CSV package"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Covered by |
|---|---|
| Extract 6 helpers to SData.CSV | Tasks 1–2 |
| Types Field_Pair / Field_Array in SData.CSV | Task 1 Step 1 |
| Test harness csv_unit_test.adb | Task 1 Step 3 |
| sdata.gpr Source_Dirs + Main + Builder | Task 1 Step 4 |
| Makefile runs unit test before .cmd suite | Task 1 Step 5 |
| Remove 6 nested bodies from file_io | Task 3 Steps 2–4 |
| 3 call sites updated with Delimiter param | Task 3 Steps 3–4 |
| alr build zero warnings | Task 3 Step 5 |
| make check 99 tests pass | Task 3 Step 6 |
