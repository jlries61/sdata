# Inf / -Inf Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make IEEE 754 positive and negative infinity first-class `Val_Numeric` values in SData, with controlled NaN detection, an `INF()` predicate, `OPTIONS IEEE_DIVIDE`, and full CSV/ODF/OOXML round-trip support.

**Architecture:** `Is_Inf` lands in `SData.Values` (lowest-level, importable everywhere). `Numeric_Result_Checked` and `Is_NaN` land in the private section of `SData.Evaluator` (accessible to its private child packages). Each feature area is a self-contained task. All tests follow the snapshot pattern: write the `.cmd`, run the binary, save output to `tests/expected/`.

**Tech Stack:** Ada 2012, GNAT, `gprbuild`. Build: `gprbuild -P sdata.gpr`. Test: `make check`. Run one test: `./bin/sdata [flags] tests/foo.cmd > tests/foo.tmp 2>&1`.

**Design spec:** `doc/specs/2026-05-06-inf-neginf-design.md`

---

## File Map

| File | Change |
|---|---|
| `src/sdata-values.ads` | Add `Is_Inf` (public) |
| `src/sdata-values.adb` | Implement `Is_Inf`; fix `To_String`/`To_String_Formatted` for Inf |
| `src/sdata-evaluator.ads` | Add `Numeric_Result_Checked` to private section |
| `src/sdata-evaluator.adb` | Implement `Is_NaN`, `Numeric_Result_Checked`; fix binary float ops; fix float division |
| `src/sdata-evaluator-misc_fns.adb` | Add `Handle_Inf_Fn`, register `INF` |
| `src/sdata-evaluator-aggregate_fns.adb` | NaN detection after Sum/Mean/Var/Std |
| `src/sdata-config-runtime.ads` | Add `IEEE_Divide : Boolean := False` |
| `src/sdata-config-runtime.adb` | Reset `IEEE_Divide` in `Reset` |
| `src/sdata-interpreter.adb` | `OPTIONS IEEE_DIVIDE` handler; Inf→integer check in `Execute_Assignment` |
| `src/sdata-csv.adb` | `Try_Fast_Float`: recognise Inf spellings |
| `src/sdata-file_io.adb` | Write Inf as string in CSV/ODF/OOXML; parse Inf strings on ODF/OOXML read |
| `src/sdata-help.adb` | Add `INF` topic; document `IEEE_DIVIDE` in OPTIONS |
| `tests/expected/help_all.out` | Regenerate after help changes |

---

## Task 1: `Is_Inf` in `SData.Values`

The `Is_Inf` predicate is needed by the evaluator, the interpreter, the file I/O layer, and `To_String`. It lives in `SData.Values` because that package is already imported by all of those consumers.

**Files:**
- Modify: `src/sdata-values.ads`
- Modify: `src/sdata-values.adb`

- [ ] **Step 1: Write the failing test**

Create `tests/inf_display.cmd`:
```
-- Test Inf display, To_String/To_String_Formatted, and INF() function
DIGITS 5
REPEAT 1
  LET X = MAXNUM() * 2.0
  LET Y = -(MAXNUM() * 2.0)
  PRINT X
  PRINT Y
RUN
QUIT
```

- [ ] **Step 2: Confirm the test shows wrong output (no Inf display yet)**

```bash
gprbuild -P sdata.gpr -q
./bin/sdata tests/inf_display.cmd 2>&1
```

Expected (before fix): some GNAT-defined float image for Inf, not `"Inf"` / `"-Inf"`.

- [ ] **Step 3: Add `Is_Inf` to `src/sdata-values.ads`**

Add after line 28 (`function To_String`), before `function To_String_Formatted`:

```ada
   --  Returns True for IEEE 754 positive or negative infinity.
   --  Returns False for finite values, Missing, and NaN.
   function Is_Inf (F : Float) return Boolean;
```

- [ ] **Step 4: Implement `Is_Inf` and fix `To_String` / `To_String_Formatted` in `src/sdata-values.adb`**

Add the implementation after the package body opening (after `package body SData.Values is`):

```ada
   function Is_Inf (F : Float) return Boolean is
   begin
      return F > Float'Last or else F < Float'First;
   end Is_Inf;
```

In `To_String`, replace the `Val_Numeric` case:
```ada
         when Val_Numeric =>
            if Is_Inf (V.Num_Val) then
               return (if V.Num_Val > 0.0 then "Inf" else "-Inf");
            end if;
            declare
               Img : constant String := Float'Image (V.Num_Val);
            begin
               return Trim (Img, Ada.Strings.Both);
            end;
```

In `To_String_Formatted`, replace the `Val_Numeric` case (the entire `declare` block starting at `package Float_IO`):
```ada
         when Val_Numeric =>
            if Is_Inf (V.Num_Val) then
               return (if V.Num_Val > 0.0 then "Inf" else "-Inf");
            end if;
            declare
               package Float_IO is new Ada.Text_IO.Float_IO (Float);
               Img : String (1 .. 100);
               Aft_Count : constant Natural := SData.Config.Print_Digits;
            begin
               if V.Num_Val = 0.0 then
                  declare
                     Zero_Img : String (1 .. Aft_Count + 2);
                  begin
                     Zero_Img (1 .. 2) := "0.";
                     for I in 3 .. Zero_Img'Last loop
                        Zero_Img (I) := '0';
                     end loop;
                     return Zero_Img;
                  end;
               end if;
               Float_IO.Put (Img, V.Num_Val, Aft => Aft_Count, Exp => 0);
               return Trim (Img, Ada.Strings.Both);
            exception
               when others =>
                  return Trim (Float'Image (V.Num_Val), Ada.Strings.Both);
            end;
```

- [ ] **Step 5: Build and run the test**

```bash
gprbuild -P sdata.gpr -q
./bin/sdata tests/inf_display.cmd 2>&1
```

Expected output:
```
Inf
-Inf
RUN complete. 1 records and 2 variables processed.
```

- [ ] **Step 6: Save expected output and commit**

```bash
./bin/sdata tests/inf_display.cmd > tests/expected/inf_display.out 2>&1
git add src/sdata-values.ads src/sdata-values.adb tests/inf_display.cmd tests/expected/inf_display.out
git commit -m "Add Is_Inf to SData.Values; fix Inf display in To_String"
```

---

## Task 2: `Numeric_Result_Checked` and NaN detection in binary float arithmetic

NaN cannot be stored as a `Val_Numeric` value. Every float arithmetic result must be checked. The check lives in a private helper that all evaluator child packages share.

**Files:**
- Modify: `src/sdata-evaluator.ads`
- Modify: `src/sdata-evaluator.adb`

- [ ] **Step 1: Write the failing test**

Create `tests/inf_nan.cmd`:
```
-- Test NaN detection from Inf arithmetic (Inf - Inf = NaN = error)
DIGITS 5
REPEAT 1
  LET X = MAXNUM() * 2.0
  LET Y = -(MAXNUM() * 2.0)
  LET Z = X + Y
  PRINT Z
RUN
QUIT
```

Create `tests/inf_nan.flags`:
```
-k
```

- [ ] **Step 2: Confirm there is no NaN error yet**

```bash
./bin/sdata -k tests/inf_nan.cmd 2>&1
```

Before fix: GNAT with IEEE 754 may silently store NaN in Z and PRINT some undefined string (not an error). The test should currently NOT print an error.

- [ ] **Step 3: Add `Numeric_Result_Checked` to the private section of `src/sdata-evaluator.ads`**

In the `private` section, after the `Handle_Domain_Error` declaration (line 74):
```ada
   function Numeric_Result_Checked (V : Float) return Value;
```

- [ ] **Step 4: Implement `Is_NaN` and `Numeric_Result_Checked` in `src/sdata-evaluator.adb`**

Add after the existing `Handle_Domain_Error` implementation (after line 103):
```ada
   function Is_NaN (F : Float) return Boolean is
   begin
      return F /= F;
   end Is_NaN;

   function Numeric_Result_Checked (V : Float) return Value is
   begin
      if Is_NaN (V) then
         return Handle_Domain_Error ("Result is not a number (NaN).");
      end if;
      return (Kind => Val_Numeric, Num_Val => V);
   end Numeric_Result_Checked;
```

- [ ] **Step 5: Replace binary float arithmetic ops with `Numeric_Result_Checked`**

In the float-float binary operator block (around line 418–427, the `case Expr.Op is` inside the `else` clause for mixed/float operands), replace:
```ada
                        case Expr.Op is
                           when Op_Add => return (Kind => Val_Numeric, Num_Val => FL + FR);
                           when Op_Sub => return (Kind => Val_Numeric, Num_Val => FL - FR);
                           when Op_Mul => return (Kind => Val_Numeric, Num_Val => FL * FR);
                           when Op_Div =>
                              if FR = 0.0 then
                                 raise SData.Script_Error with "Division by zero.";
                              end if;
                              return (Kind => Val_Numeric, Num_Val => FL / FR);
                           when Op_Pow => return (Kind => Val_Numeric, Num_Val => FL ** FR);
```

With:
```ada
                        case Expr.Op is
                           when Op_Add => return Numeric_Result_Checked (FL + FR);
                           when Op_Sub => return Numeric_Result_Checked (FL - FR);
                           when Op_Mul => return Numeric_Result_Checked (FL * FR);
                           when Op_Div =>
                              if FR = 0.0 then
                                 raise SData.Script_Error with "Division by zero.";
                              end if;
                              return Numeric_Result_Checked (FL / FR);
                           when Op_Pow => return Numeric_Result_Checked (FL ** FR);
```

- [ ] **Step 6: Build and run the NaN test**

```bash
gprbuild -P sdata.gpr -q
./bin/sdata -k tests/inf_nan.cmd 2>&1
```

Expected output:
```
Error: Result is not a number (NaN).
.
RUN complete. 1 records and 3 variables processed.
```

- [ ] **Step 7: Save expected output and commit**

```bash
./bin/sdata -k tests/inf_nan.cmd > tests/expected/inf_nan.out 2>&1
git add src/sdata-evaluator.ads src/sdata-evaluator.adb tests/inf_nan.cmd tests/inf_nan.flags tests/expected/inf_nan.out
git commit -m "Add Numeric_Result_Checked; detect NaN in binary float arithmetic"
```

---

## Task 3: `IEEE_Divide` option and float division by zero

**Files:**
- Modify: `src/sdata-config-runtime.ads`
- Modify: `src/sdata-config-runtime.adb`
- Modify: `src/sdata-interpreter.adb`
- Modify: `src/sdata-evaluator.adb`

- [ ] **Step 1: Write the failing test**

Create `tests/inf_divide.cmd`:
```
-- Test OPTIONS IEEE_DIVIDE: nonzero/0 -> Inf, 0/0 -> NaN error
DIGITS 5
OPTIONS IEEE_DIVIDE YES
REPEAT 1
  LET A = 1.0 / 0.0
  LET B = -1.0 / 0.0
  LET C = 0.0 / 0.0
  PRINT A
  PRINT B
  PRINT C
RUN
QUIT
```

Create `tests/inf_divide.flags`:
```
-k
```

- [ ] **Step 2: Confirm `OPTIONS IEEE_DIVIDE YES` is currently unrecognised**

```bash
./bin/sdata -k tests/inf_divide.cmd 2>&1
```

Expected (before fix): `Warning: Unknown OPTIONS key: IEEE_DIVIDE` and then `Error: Division by zero.` for all three.

- [ ] **Step 3: Add `IEEE_Divide` to `src/sdata-config-runtime.ads`**

After the `Options_CHARSET_Len` line (line 36):
```ada
   IEEE_Divide         : Boolean                          := False;
```

- [ ] **Step 4: Reset `IEEE_Divide` in `src/sdata-config-runtime.adb`**

Add after `Options_CHARSET_Len := 0;` (line 28):
```ada
      IEEE_Divide         := False;
```

- [ ] **Step 5: Handle `IEEE_DIVIDE` in the `Stmt_OPTIONS` dispatcher in `src/sdata-interpreter.adb`**

In the `elsif Key = "CHARSET" then` block (around line 1519), add a new branch before the final `else` (the "Unknown OPTIONS key" warning):
```ada
               elsif Key = "IEEE_DIVIDE" then
                  SData.Config.Runtime.IEEE_Divide := (Val_Upper = "YES");
```

- [ ] **Step 6: Branch float division on `IEEE_Divide` in `src/sdata-evaluator.adb`**

Replace the `Op_Div` case in the float-float block (which currently always raises on zero):
```ada
                           when Op_Div =>
                              if SData.Config.Runtime.IEEE_Divide then
                                 return Numeric_Result_Checked (FL / FR);
                              else
                                 if FR = 0.0 then
                                    raise SData.Script_Error with "Division by zero.";
                                 end if;
                                 return Numeric_Result_Checked (FL / FR);
                              end if;
```

Ensure `sdata-evaluator.adb` already has `with SData.Config.Runtime;` — it does (line 8).

- [ ] **Step 7: Build and run the divide test**

```bash
gprbuild -P sdata.gpr -q
./bin/sdata -k tests/inf_divide.cmd 2>&1
```

Expected output:
```
Inf
-Inf
Error: Result is not a number (NaN).
.
RUN complete. 1 records and 3 variables processed.
```

- [ ] **Step 8: Save expected output and commit**

```bash
./bin/sdata -k tests/inf_divide.cmd > tests/expected/inf_divide.out 2>&1
git add src/sdata-config-runtime.ads src/sdata-config-runtime.adb src/sdata-interpreter.adb src/sdata-evaluator.adb tests/inf_divide.cmd tests/inf_divide.flags tests/expected/inf_divide.out
git commit -m "Add OPTIONS IEEE_DIVIDE; IEEE 754 float division by zero support"
```

---

## Task 4: `INF()` function

**Files:**
- Modify: `src/sdata-evaluator-misc_fns.adb`

- [ ] **Step 1: Extend the display test to include `INF()`**

Append to `tests/inf_display.cmd` (replace its content entirely):
```
-- Test Inf display and INF() function
DIGITS 5
REPEAT 1
  LET X = MAXNUM() * 2.0
  LET Y = -(MAXNUM() * 2.0)
  PRINT X
  PRINT Y
  PRINT INF(X)
  PRINT INF(Y)
  PRINT INF(1.0)
  PRINT INF(.)
  PRINT (INF(X) AND X > 0)
  PRINT (INF(Y) AND Y < 0)
RUN
QUIT
```

- [ ] **Step 2: Confirm `INF` is currently unknown**

```bash
./bin/sdata tests/inf_display.cmd 2>&1
```

Expected (before fix): `Error: Unknown function: INF` or similar.

- [ ] **Step 3: Add `Handle_Inf_Fn` to `src/sdata-evaluator-misc_fns.adb`**

Add after `Handle_Missing` (after line 28):
```ada
   function Handle_Inf_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if Integer (Vals.Length) < 1 then return (Kind => Val_Integer, Int_Val => 0); end if;
      declare
         V : constant Value := Vals.Element (1);
      begin
         if V.Kind = Val_Numeric and then SData.Values.Is_Inf (V.Num_Val) then
            return (Kind => Val_Integer, Int_Val => 1);
         else
            return (Kind => Val_Integer, Int_Val => 0);
         end if;
      end;
   end Handle_Inf_Fn;
```

- [ ] **Step 4: Register `INF` in the dispatch table**

In the `Register` procedure body (around line 331 where `MISSING` is registered), add:
```ada
      Dispatch_Table.Insert ("INF",     Handle_Inf_Fn'Access);
```

- [ ] **Step 5: Build and run the display test**

```bash
gprbuild -P sdata.gpr -q
./bin/sdata tests/inf_display.cmd 2>&1
```

Expected output:
```
Inf
-Inf
1
1
0
0
1
1
RUN complete. 1 records and 2 variables processed.
```

- [ ] **Step 6: Save expected output and commit**

```bash
./bin/sdata tests/inf_display.cmd > tests/expected/inf_display.out 2>&1
git add src/sdata-evaluator-misc_fns.adb tests/inf_display.cmd tests/expected/inf_display.out
git commit -m "Add INF() built-in function"
```

---

## Task 5: Inf → integer assignment check

When `LET n% = expr` evaluates to Inf, the assignment must go through `Handle_Domain_Error` rather than letting Ada raise `Constraint_Error` with a generic message.

**Files:**
- Modify: `src/sdata-interpreter.adb`

- [ ] **Step 1: Write the failing test**

Create `tests/inf_int_assign.cmd`:
```
-- Assigning Inf to integer variable should use Handle_Domain_Error
DIGITS 5
REPEAT 1
  LET X = MAXNUM() * 2.0
  LET N% = X
  PRINT N%
RUN
QUIT
```

Create `tests/inf_int_assign.flags`:
```
-k
```

- [ ] **Step 2: Check current error message**

```bash
./bin/sdata -k tests/inf_int_assign.cmd 2>&1
```

Before fix: `Error: Assignment failed for variable N%: ...` (generic, comes from `Constraint_Error` during integer conversion). After fix: `Error: Cannot convert Inf to integer.`

- [ ] **Step 3: Add Inf check in `Execute_Assignment` in `src/sdata-interpreter.adb`**

In `Execute_Assignment`, after `Result : Value` is computed by `Evaluate(Stmt.Expr)` and before the variable is set, add an Inf→integer guard. Locate the section where the variable name is checked for `%` suffix (or where the assignment proceeds). The relevant code starts around line 662. Add this block immediately after `Result` is evaluated:

```ada
         --  Guard: assigning Inf to an integer variable is a domain error.
         if Result.Kind = Val_Numeric
            and then SData.Values.Is_Inf (Result.Num_Val)
            and then Var_Name_Str'Length > 0
            and then Var_Name_Str (Var_Name_Str'Last) = '%'
         then
            Result := SData.Evaluator.Handle_Domain_Error
               ("Cannot convert Inf to integer.");
         end if;
```

Note: `SData.Evaluator.Handle_Domain_Error` is declared public in `sdata-evaluator.ads` — wait, actually it is in the **private** section. Check: `sdata-interpreter.adb` is NOT a child package of `SData.Evaluator`, so it cannot see the private section. 

Alternative: call `Handle_Domain_Error` indirectly by raising `Script_Error` directly:

```ada
         if Result.Kind = Val_Numeric
            and then SData.Values.Is_Inf (Result.Num_Val)
            and then Var_Name_Str'Length > 0
            and then Var_Name_Str (Var_Name_Str'Last) = '%'
         then
            if SData.Config.Ignore_Math_Errors then
               Put_Line_Error ("Warning: Cannot convert Inf to integer.");
               Result := (Kind => Val_Missing);
            else
               raise SData.Script_Error with "Cannot convert Inf to integer.";
            end if;
         end if;
```

This replicates `Handle_Domain_Error` logic without needing access to the private evaluator helper. Place it after the `Evaluate` call that sets `Result` and before the variable write.

- [ ] **Step 4: Build and run the test**

```bash
gprbuild -P sdata.gpr -q
./bin/sdata -k tests/inf_int_assign.cmd 2>&1
```

Expected output:
```
Error: Cannot convert Inf to integer.
.
RUN complete. 1 records and 2 variables processed.
```

- [ ] **Step 5: Verify `--ignore-math-errors` gives Missing instead of error**

```bash
./bin/sdata --ignore-math-errors tests/inf_int_assign.cmd 2>&1
```

Expected:
```
Warning: Cannot convert Inf to integer.
.
RUN complete. 1 records and 2 variables processed.
```

- [ ] **Step 6: Save expected output and commit**

```bash
./bin/sdata -k tests/inf_int_assign.cmd > tests/expected/inf_int_assign.out 2>&1
git add src/sdata-interpreter.adb tests/inf_int_assign.cmd tests/inf_int_assign.flags tests/expected/inf_int_assign.out
git commit -m "Inf to integer assignment routes through Handle_Domain_Error logic"
```

---

## Task 6: Aggregate NaN detection

`SUM`, `MEAN`, `VAR`, `STD` can produce NaN when Inf and -Inf are mixed. Each must check the result before returning.

**Files:**
- Modify: `src/sdata-evaluator-aggregate_fns.adb`

- [ ] **Step 1: Write the failing test**

Create `tests/inf_aggregates.cmd`:
```
-- SUM of Inf values propagates Inf; mixed Inf/-Inf produces NaN error
DIGITS 5
REPEAT 1
  LET A = MAXNUM() * 2.0
  LET B = -(MAXNUM() * 2.0)
  LET S = SUM(A)
  LET M = MEAN(A, B)
  PRINT S
  PRINT M
RUN
QUIT
```

Create `tests/inf_aggregates.flags`:
```
-k
```

- [ ] **Step 2: Confirm no NaN error currently**

```bash
./bin/sdata -k tests/inf_aggregates.cmd 2>&1
```

Before fix: NaN is silently stored (or produces garbage output). After fix: NaN triggers Script_Error.

- [ ] **Step 3: Add NaN checks to aggregate functions in `src/sdata-evaluator-aggregate_fns.adb`**

Add `with SData.Values; use SData.Values;` if not already present at the top (it is already there).

Replace `Handle_Sum` body:
```ada
   function Handle_Sum (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R : constant Stats_Pass_Result := Compute_Stats_Pass (Vals);
   begin
      if R.N_Count = 0 then return (Kind => Val_Missing); end if;
      return Numeric_Result_Checked (Float (R.Sum));
   end Handle_Sum;
```

Replace `Handle_Mean` body:
```ada
   function Handle_Mean (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R : constant Stats_Pass_Result := Compute_Stats_Pass (Vals);
   begin
      if R.N_Count = 0 then return (Kind => Val_Missing); end if;
      return Numeric_Result_Checked (Float (R.Sum / Long_Float (R.N_Count)));
   end Handle_Mean;
```

Replace `Handle_Var_Fn` body:
```ada
   function Handle_Var_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R  : constant Stats_Pass_Result := Compute_Stats_Pass (Vals);
      NF : Long_Float;
   begin
      if R.N_Count < 2 then return (Kind => Val_Missing); end if;
      NF := Long_Float (R.N_Count);
      return Numeric_Result_Checked
         (Float ((R.Sum_Sq - (R.Sum ** 2 / NF)) / (NF - 1.0)));
   end Handle_Var_Fn;
```

Replace `Handle_Std_Fn` body:
```ada
   function Handle_Std_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R  : constant Stats_Pass_Result := Compute_Stats_Pass (Vals);
      NF : Long_Float;
   begin
      if R.N_Count < 2 then return (Kind => Val_Missing); end if;
      NF := Long_Float (R.N_Count);
      return Numeric_Result_Checked
         (Sqrt (Float ((R.Sum_Sq - (R.Sum ** 2 / NF)) / (NF - 1.0))));
   end Handle_Std_Fn;
```

(`Numeric_Result_Checked` is visible here because `SData.Evaluator.Aggregate_Fns` is a private child of `SData.Evaluator`.)

- [ ] **Step 4: Build and run the test**

```bash
gprbuild -P sdata.gpr -q
./bin/sdata -k tests/inf_aggregates.cmd 2>&1
```

Expected output:
```
Inf
Error: Result is not a number (NaN).
.
RUN complete. 1 records and 4 variables processed.
```

- [ ] **Step 5: Save expected output and commit**

```bash
./bin/sdata -k tests/inf_aggregates.cmd > tests/expected/inf_aggregates.out 2>&1
git add src/sdata-evaluator-aggregate_fns.adb tests/inf_aggregates.cmd tests/inf_aggregates.flags tests/expected/inf_aggregates.out
git commit -m "Detect NaN in aggregate functions (SUM/MEAN/VAR/STD)"
```

---

## Task 7: CSV Inf parsing

**Files:**
- Modify: `src/sdata-csv.adb`

- [ ] **Step 1: Write the failing test**

Create `tests/data/inf_values.csv`:
```
X,Y,Z
Inf,-Inf,1.5
infinity,-INFINITY,2.5
+Inf,+Infinity,3.5
```

Create `tests/inf_io.cmd`:
```
-- Test CSV round-trip: read Inf spellings, write as Inf/-Inf, read back
DIGITS 5
USE "tests/data/inf_values.csv"
PRINT X
PRINT Y
PRINT Z
PRINT INF(X)
PRINT INF(Y)
RUN
QUIT
```

- [ ] **Step 2: Confirm Inf strings are read as Val_String currently**

```bash
./bin/sdata tests/inf_io.cmd 2>&1
```

Before fix: X and Y columns are Val_String (not Val_Numeric), `INF(X)` = 0 (string is not Inf).

- [ ] **Step 3: Add Inf recognition to `Try_Fast_Float` in `src/sdata-csv.adb`**

At the very top of `Try_Fast_Float`, before the sign-handling logic, add a case-insensitive Inf check. Add `with Ada.Characters.Handling; use Ada.Characters.Handling;` at the top of the file if not already present, then add to `Try_Fast_Float`:

```ada
   function Try_Fast_Float (S : String; Result : out Float) return Boolean is
      T  : constant String := Ada.Strings.Fixed.Trim (S, Ada.Strings.Both);
      TU : String (T'Range);
   begin
      --  Normalise to upper case for Inf recognition.
      for I in T'Range loop TU (I) := Ada.Characters.Handling.To_Upper (T (I)); end loop;
      if TU = "INF" or else TU = "+INF" or else TU = "INFINITY" or else TU = "+INFINITY" then
         Result := Float'Last * 2.0;
         return True;
      elsif TU = "-INF" or else TU = "-INFINITY" then
         Result := -(Float'Last * 2.0);
         return True;
      end if;
      --  Existing fast decimal parser below.
      declare
         I         : Integer := T'First;
```

Adjust the rest of the existing body to use `T` instead of `S` (since `T` is the trimmed string). The existing variable `I : Integer := S'First;` becomes `I : Integer := T'First;` and all references to `S` inside the loop become `T`. Replace the existing function body with:

```ada
   function Try_Fast_Float (S : String; Result : out Float) return Boolean is
      T         : constant String := Ada.Strings.Fixed.Trim (S, Ada.Strings.Both);
      I         : Integer := T'First;
      Whole     : Float   := 0.0;
      Frac      : Float   := 0.0;
      Denom     : Float   := 1.0;
      Sign      : Float   := 1.0;
      After_Dot : Boolean := False;
      Has_Digit : Boolean := False;
      TU        : String (T'Range);
   begin
      for K in T'Range loop TU (K) := Ada.Characters.Handling.To_Upper (T (K)); end loop;
      if TU = "INF" or else TU = "+INF" or else TU = "INFINITY" or else TU = "+INFINITY" then
         Result := Float'Last * 2.0;  --  +Inf via overflow
         return True;
      elsif TU = "-INF" or else TU = "-INFINITY" then
         Result := -(Float'Last * 2.0);  --  -Inf via overflow
         return True;
      end if;
      if I > T'Last then return False; end if;
      if    T (I) = '-' then Sign := -1.0; I := I + 1;
      elsif T (I) = '+' then               I := I + 1;
      end if;
      while I <= T'Last loop
         case T (I) is
            when '0' .. '9' =>
               Has_Digit := True;
               if After_Dot then
                  Denom := Denom * 10.0;
                  Frac  := Frac + Float (Character'Pos (T (I)) - 48) / Denom;
               else
                  Whole := Whole * 10.0 + Float (Character'Pos (T (I)) - 48);
               end if;
            when '.' =>
               if After_Dot then return False; end if;
               After_Dot := True;
            when 'E' | 'e' | 'D' | 'd' =>
               begin
                  Result := Float'Value (T);
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
```

Add `with Ada.Characters.Handling;` at the top of `src/sdata-csv.adb` (it is not yet present).

- [ ] **Step 4: Build and run the CSV parse test**

```bash
gprbuild -P sdata.gpr -q
./bin/sdata tests/inf_io.cmd 2>&1
```

Expected output:
```
Inf
-Inf
1.50000
1
1
Inf
-Inf
2.50000
1
1
Inf
-Inf
3.50000
1
1
RUN complete. 3 records and 3 variables processed.
```

- [ ] **Step 5: Save expected output and commit**

```bash
./bin/sdata tests/inf_io.cmd > tests/expected/inf_io.out 2>&1
git add src/sdata-csv.adb tests/data/inf_values.csv tests/inf_io.cmd tests/expected/inf_io.out
git commit -m "CSV parser recognises Inf/-Inf/Infinity spellings (case-insensitive)"
```

---

## Task 8: CSV / ODF / OOXML write and ODF / OOXML read

**Files:**
- Modify: `src/sdata-file_io.adb`

- [ ] **Step 1: Write the failing test**

Create `tests/inf_round_trip.cmd`:
```
-- Round-trip: write Inf to CSV and read it back
DIGITS 5
USE "tests/data/inf_values.csv"
SAVE "tests/data/inf_output.csv"
RUN

USE "tests/data/inf_output.csv"
PRINT X
PRINT INF(X)
RUN
QUIT
```

- [ ] **Step 2: Confirm Inf is written incorrectly before fix**

```bash
./bin/sdata tests/inf_round_trip.cmd 2>&1
```

Before fix: the `Val_Numeric` write path at line 808 calls `Val.Num_Val'Img` which produces GNAT's Inf image (e.g., `+Inf` or implementation-defined), but the file may not be round-trippable.

- [ ] **Step 3: Fix CSV Inf write in `src/sdata-file_io.adb`**

In `Write_CSV`, in the row-writing loop (around line 808), replace the `Val_Numeric` case:
```ada
                  if Val.Kind = Val_Numeric then
                     if SData.Values.Is_Inf (Val.Num_Val) then
                        Write_String
                           (if Val.Num_Val > 0.0 then "Inf" else "-Inf");
                     else
                        Write_String (Trim (Val.Num_Val'Img, Ada.Strings.Both));
                     end if;
```

- [ ] **Step 4: Fix ODF Inf write in `Write_ODF` in `src/sdata-file_io.adb`**

In the data-row loop of `Write_ODF` (around line 1622), replace the `Val_Numeric` case:
```ada
                     when Val_Numeric =>
                        if SData.Values.Is_Inf (V.Num_Val) then
                           declare
                              Img : constant String :=
                                 (if V.Num_Val > 0.0 then "Inf" else "-Inf");
                           begin
                              Append (S1, "<table:table-cell office:value-type=""string""><text:p>" &
                                          Img & "</text:p></table:table-cell>");
                           end;
                        else
                           Append (S1, "<table:table-cell office:value-type=""float"" office:value=""" &
                                   Trim (V.Num_Val'Img, Ada.Strings.Both) & """>" &
                                   "<text:p>" & Trim (V.Num_Val'Img, Ada.Strings.Both) &
                                   "</text:p></table:table-cell>");
                        end if;
```

- [ ] **Step 5: Fix OOXML Inf write in `Write_OOXML` in `src/sdata-file_io.adb`**

In the data-row loop of `Write_OOXML` (around line 1548), replace the `Val_Numeric` case:
```ada
                     when Val_Numeric =>
                        if SData.Values.Is_Inf (V.Num_Val) then
                           declare
                              Img : constant String :=
                                 (if V.Num_Val > 0.0 then "Inf" else "-Inf");
                           begin
                              Append (S1, "<c r=""" & Ref &
                                 """ t=""inlineStr""><is><t>" & Img & "</t></is></c>");
                           end;
                        else
                           Append (S1, "<c r=""" & Ref & """><v>" &
                              Trim (V.Num_Val'Img, Ada.Strings.Both) & "</v></c>");
                        end if;
```

- [ ] **Step 6: Fix ODF Inf read in `Get_Cell_Value` inside `Parse_ODF`**

In `Get_Cell_Value` (around line 866), in the `elsif Length (P_List) > 0` branch (string cell), add Inf recognition before returning `Val_String`:
```ada
            elsif Length (P_List) > 0 then
               declare
                  S  : constant String := Get_Text (Item (P_List, 0));
                  SU : constant String := Ada.Characters.Handling.To_Upper (S);
               begin
                  Free (P_List);
                  if SU = "INF" or else SU = "+INF"
                     or else SU = "INFINITY" or else SU = "+INFINITY"
                  then
                     return (Kind => Val_Numeric, Num_Val => Float'Last * 2.0);
                  elsif SU = "-INF" or else SU = "-INFINITY" then
                     return (Kind => Val_Numeric, Num_Val => -(Float'Last * 2.0));
                  end if;
                  return (Kind    => Val_String,
                          Str_Val => To_Unbounded_String (S));
               end;
```

`with Ada.Characters.Handling; use Ada.Characters.Handling;` is already present at line 11 of `sdata-file_io.adb` — no change needed.

- [ ] **Step 7: Fix OOXML Inf read in `Get_Cell_Value` inside `Parse_OOXML`**

In `Get_Cell_Value` for OOXML (around line 1280), in the `IS_List` branch that produces `Val_String`:
```ada
            elsif Length (IS_List) > 0 then
               declare
                  T_Nodes : Node_List := Get_Elements_By_Tag_Name
                     (DOM.Core.Element (Item (IS_List, 0)), "t");
               begin
                  if Length (T_Nodes) > 0 then
                     declare
                        S  : constant String := Get_Text (Item (T_Nodes, 0));
                        SU : constant String := Ada.Characters.Handling.To_Upper (S);
                     begin
                        Free (T_Nodes); Free (V_List); Free (IS_List);
                        if SU = "INF" or else SU = "+INF"
                           or else SU = "INFINITY" or else SU = "+INFINITY"
                        then
                           return (Kind => Val_Numeric, Num_Val => Float'Last * 2.0);
                        elsif SU = "-INF" or else SU = "-INFINITY" then
                           return (Kind => Val_Numeric, Num_Val => -(Float'Last * 2.0));
                        end if;
                        return (Kind    => Val_String,
                                Str_Val => To_Unbounded_String (S));
                     end;
                  end if;
                  Free (T_Nodes);
               end;
```

Also add Inf recognition in the `t="str"` inline path (line 1275):
```ada
                  elsif T_Attr = "str" then
                     declare
                        SU : constant String :=
                           Ada.Characters.Handling.To_Upper (Val_Str);
                     begin
                        if SU = "INF" or else SU = "+INF"
                           or else SU = "INFINITY" or else SU = "+INFINITY"
                        then
                           Free (V_List); Free (IS_List);
                           return (Kind => Val_Numeric, Num_Val => Float'Last * 2.0);
                        elsif SU = "-INF" or else SU = "-INFINITY" then
                           Free (V_List); Free (IS_List);
                           return (Kind => Val_Numeric, Num_Val => -(Float'Last * 2.0));
                        end if;
                        Free (V_List); Free (IS_List);
                        return (Kind => Val_String,
                                Str_Val => To_Unbounded_String (Val_Str));
                     end;
```

- [ ] **Step 8: Build and run the round-trip test**

```bash
gprbuild -P sdata.gpr -q
./bin/sdata tests/inf_round_trip.cmd 2>&1
```

Expected output:
```
Dataset opened: tests/data/inf_values.csv
Dataset saved: tests/data/inf_output.csv
RUN complete. 3 records and 3 variables processed.
Dataset opened: tests/data/inf_output.csv
Inf
1
Inf
1
Inf
1
RUN complete. 3 records and 3 variables processed.
```

- [ ] **Step 9: Save expected output and commit**

```bash
./bin/sdata tests/inf_round_trip.cmd > tests/expected/inf_round_trip.out 2>&1
git add src/sdata-file_io.adb tests/inf_round_trip.cmd tests/expected/inf_round_trip.out
git commit -m "CSV/ODF/OOXML write Inf as string; ODF/OOXML read Inf from string cells"
```

---

## Task 9: Help text and snapshot regeneration

**Files:**
- Modify: `src/sdata-help.adb`
- Modify: `tests/expected/help_all.out`

- [ ] **Step 1: Add `INF` help topic to `src/sdata-help.adb`**

Locate the section where `MISSING` is defined (around line 1187 where `K_MISSING` is declared). Add alongside it:
```ada
   K_INF          : aliased constant String := "INF";
```

And add the help body text for `INF` following the pattern used by `MISSING`:
```ada
   T_INF : aliased constant String :=
      "INF(x)" & ASCII.LF &
      "  Returns 1 if x is positive or negative infinity, 0 otherwise." & ASCII.LF &
      "  Returns 0 for finite values, missing values, and strings." & ASCII.LF &
      ASCII.LF &
      "  To test for positive infinity:  INF(x) AND x > 0" & ASCII.LF &
      "  To test for negative infinity:  INF(x) AND x < 0" & ASCII.LF &
      "  NOT INF(x) serves the role of FINITE() for non-missing values." & ASCII.LF &
      ASCII.LF &
      "  See also: MISSING, OPTIONS IEEE_DIVIDE";
```

Add a `Help_INF` procedure near `Help_MISSING` (line 747):
```ada
   procedure Help_INF is begin
      Put_Line ("Function: INF(x)  ->  1 if x is +/-Inf, else 0");
      Put_Line ("  INF(x) AND x > 0  tests for positive infinity");
      Put_Line ("  INF(x) AND x < 0  tests for negative infinity");
      Put_Line ("  NOT INF(x) serves as FINITE() for non-missing values");
      Put_Line ("  See also: MISSING, OPTIONS IEEE_DIVIDE");
   end Help_INF;
```

Declare `K_INF` near `K_MISSING` (line 1187):
```ada
   K_INF          : aliased constant String := "INF";
```

Add the entry to the help topics array near the `K_MISSING` entry (line 1403):
```ada
      (K_INF'Access,      Help_INF'Access,      N, F),
```

- [ ] **Step 2: Add `IEEE_DIVIDE` to the OPTIONS help topic**

Locate the OPTIONS help text in `sdata-help.adb`. Add to the body of the OPTIONS description:
```
  IEEE_DIVIDE YES|NO
    When YES, float division by zero produces +/-Inf (IEEE 754) instead of
    an error. 0.0/0.0 always produces an error. Default: NO.
    Cleared by NEW.
```

- [ ] **Step 3: Build and regenerate `help_all.out`**

```bash
gprbuild -P sdata.gpr -q
./bin/sdata tests/help_all.cmd > tests/expected/help_all.out 2>&1
```

- [ ] **Step 4: Verify INF appears in the help index**

```bash
./bin/sdata tests/help_all.cmd 2>&1 | grep -i "INF\|IEEE"
```

Expected: lines showing `INF` function description and `IEEE_DIVIDE` option.

- [ ] **Step 5: Commit**

```bash
git add src/sdata-help.adb tests/expected/help_all.out
git commit -m "Add INF() and OPTIONS IEEE_DIVIDE to help system"
```

---

## Task 10: Full test suite and software standards annotation

- [ ] **Step 1: Verify SORT and BY groups with Inf require no code change**

The existing `"<"` operator in `SData.Values` (line 119–129) converts both operands to `Float` and calls `FL < FR`. IEEE 754 float comparison handles ±Inf correctly: `-Inf < any_finite < +Inf`. SORT and BY grouping already use this comparison, so no code change is needed. Verify by running:

```bash
./bin/sdata - <<'EOF'
REPEAT 3
  LET X = (if RECNO() = 1 then MAXNUM() * 2.0 else (if RECNO() = 2 then -(MAXNUM() * 2.0) else 1.5))
  WRITE
RUN
SORT BY X
PRINT X
RUN
QUIT
EOF
```

Expected: rows sorted as `-Inf`, `1.5`, `Inf`.

- [ ] **Step 2: Run the full test suite**

```bash
make check
```

Expected: all tests pass. If any test other than the new ones fails, investigate and fix before proceeding.

- [ ] **Step 2: Annotate `doc/SOFTWARE_STANDARDS_REVIEW.md`**

In section 6.1 (Expression Evaluation Overflow), add annotation:
```
~~**Expression evaluation overflow** (Float overflow silently produces Inf)~~
Resolved in v0.6.9: Inf is now a first-class Val_Numeric value. Float overflow
produces ±Inf; NaN from Inf arithmetic raises Script_Error (or Val_Missing with
--ignore-math-errors). See doc/specs/2026-05-06-inf-neginf-design.md.
```

Adjust the score for the Expression Evaluation Overflow item and update the running total.

- [ ] **Step 3: Commit**

```bash
git add doc/SOFTWARE_STANDARDS_REVIEW.md
git commit -m "Annotate standards review: expression overflow resolved by Inf support"
```

---

## Quick Reference: Build and Test Commands

```bash
# Build
gprbuild -P sdata.gpr -q

# Run one test manually
./bin/sdata tests/foo.cmd 2>&1
./bin/sdata -k tests/foo.cmd 2>&1              # continue on error
./bin/sdata --ignore-math-errors tests/foo.cmd 2>&1

# Regenerate a snapshot
./bin/sdata [flags] tests/foo.cmd > tests/expected/foo.out 2>&1

# Full suite
make check
```
