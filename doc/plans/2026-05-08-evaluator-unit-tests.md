# Evaluator Unit Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a unit test executable (`evaluator_unit_test`) covering the four evaluator child packages — `numeric_fns`, `distrib_fns`, `misc_fns`, and `aggregate_fns` — exercising core functions, domain error paths, and edge cases; fixing any bugs surfaced.

**Architecture:** A thin `Call_Function` shim is added to `SData.Evaluator`'s public API to call any registered handler by name with a `Value_Array` argument list, bypassing the parser. Tests are written in `tests/evaluator_unit_test.adb` following the pattern established in `tests/sdata_unit_test.adb`. The shim is the only production-code change; all other work is additive test code.

**Tech Stack:** Ada 2012, GNAT/GPRbuild, Alire. Build with `alr build`. Run full suite with `make check`.

---

## File Map

| File | Action | Purpose |
|---|---|---|
| `src/sdata-evaluator.ads` | Modify | Add `Value_Array` type + `Call_Function` declaration |
| `src/sdata-evaluator.adb` | Modify | Implement `Call_Function` |
| `tests/evaluator_unit_test.adb` | Create | All evaluator unit tests |
| `sdata.gpr` | Modify | Add `evaluator_unit_test.adb` to `Main` + `Builder` |
| `Makefile` | Modify | Add `evaluator_unit_test` to `check` target |

---

### Task 1: Add `Call_Function` shim and build infrastructure

Adds the `Call_Function` shim to the public evaluator API, creates the test harness skeleton with all helpers but no test cases yet, wires it into the build, and verifies compilation. No actual test cases are added in this task.

**Files:**
- Modify: `src/sdata-evaluator.ads`
- Modify: `src/sdata-evaluator.adb`
- Create: `tests/evaluator_unit_test.adb`
- Modify: `sdata.gpr`
- Modify: `Makefile`

- [ ] **Step 1: Add `Value_Array` and `Call_Function` to `src/sdata-evaluator.ads`**

Immediately before the `private` keyword, insert:

```ada
   --  Thin shim for unit tests: call a registered function by name with
   --  pre-evaluated arguments.  Raises SData.Script_Error if Name is not in
   --  the dispatch table.
   type Value_Array is array (Positive range <>) of Value;
   function Call_Function (Name : String; Args : Value_Array) return Value;
```

- [ ] **Step 2: Implement `Call_Function` in `src/sdata-evaluator.adb`**

Add immediately after `Set_Group_Boundary` (around line 105, before `Handle_Domain_Error`):

```ada
   function Call_Function (Name : String; Args : Value_Array) return Value is
      Vals   : Value_Vectors.Vector;
      Cursor : constant Fn_Maps.Cursor := Dispatch_Table.Find (Name);
   begin
      for A of Args loop
         Vals.Append (A);
      end loop;
      if not Fn_Maps.Has_Element (Cursor) then
         raise Script_Error with "Call_Function: unknown function '" & Name & "'";
      end if;
      return Fn_Maps.Element (Cursor).all (Name, Vals);
   end Call_Function;
```

- [ ] **Step 3: Create `tests/evaluator_unit_test.adb` with the harness and no test cases**

```ada
--  Unit tests for SData.Evaluator handler families:
--  numeric_fns, distrib_fns, misc_fns, aggregate_fns.
--  Calls functions via Call_Function — no parser or interpreter involved.

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Numerics;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with SData.Values;          use SData.Values;
with SData.Evaluator;       use SData.Evaluator;
with SData.Statistics;

procedure Evaluator_Unit_Test is
   Passed : Natural := 0;
   Failed : Natural := 0;

   --  -----------------------------------------------------------------------
   --  Check helpers
   --  -----------------------------------------------------------------------

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

   procedure Check_Num (Name : String; V : Value; Expected : Float;
                        Tol : Float := 0.001) is
   begin
      if V.Kind /= Val_Numeric then
         Put_Line ("FAIL: " & Name & "  got kind=" & V.Kind'Image
                   & "  expected Val_Numeric");
         Failed := Failed + 1;
      elsif abs (V.Num_Val - Expected) <= Tol then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
                   & "  got=" & V.Num_Val'Image
                   & "  expected=" & Expected'Image);
         Failed := Failed + 1;
      end if;
   end Check_Num;

   procedure Check_Int (Name : String; V : Value; Expected : Integer) is
   begin
      if V.Kind /= Val_Integer then
         Put_Line ("FAIL: " & Name & "  got kind=" & V.Kind'Image
                   & "  expected Val_Integer");
         Failed := Failed + 1;
      elsif V.Int_Val = Expected then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
                   & "  got=" & V.Int_Val'Image
                   & "  expected=" & Expected'Image);
         Failed := Failed + 1;
      end if;
   end Check_Int;

   procedure Check_Missing (Name : String; V : Value) is
   begin
      if V.Kind = Val_Missing then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name & "  got kind=" & V.Kind'Image
                   & "  expected Val_Missing");
         Failed := Failed + 1;
      end if;
   end Check_Missing;

   procedure Check_Str (Name : String; V : Value; Expected : String) is
   begin
      if V.Kind /= Val_String then
         Put_Line ("FAIL: " & Name & "  got kind=" & V.Kind'Image
                   & "  expected Val_String");
         Failed := Failed + 1;
      elsif To_String (V.Str_Val) = Expected then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
                   & "  got=[" & To_String (V.Str_Val) & "]"
                   & "  expected=[" & Expected & "]");
         Failed := Failed + 1;
      end if;
   end Check_Str;

   --  Returns True if calling Name(Args) raises any exception or returns
   --  Val_Missing.  Handles both the default mode (Script_Error raised) and
   --  --ignore-math-errors mode (Val_Missing returned).
   function Raises (Name : String; Args : Value_Array) return Boolean is
      V : Value;
   begin
      V := Call_Function (Name, Args);
      return V.Kind = Val_Missing;
   exception
      when others => return True;
   end Raises;

   --  -----------------------------------------------------------------------
   --  Convenience wrappers
   --  -----------------------------------------------------------------------

   --  Zero-argument call
   function F0 (Name : String) return Value is
   begin
      return Call_Function (Name, (1 .. 0 => (Kind => Val_Missing)));
   end F0;

   --  One numeric argument
   function F1 (Name : String; A : Float) return Value is
   begin
      return Call_Function (Name,
         (1 => (Kind => Val_Numeric, Num_Val => A)));
   end F1;

   --  Two numeric arguments
   function F2 (Name : String; A, B : Float) return Value is
   begin
      return Call_Function (Name,
         (1 => (Kind => Val_Numeric, Num_Val => A),
          2 => (Kind => Val_Numeric, Num_Val => B)));
   end F2;

   --  Three numeric arguments
   function F3 (Name : String; A, B, C : Float) return Value is
   begin
      return Call_Function (Name,
         (1 => (Kind => Val_Numeric, Num_Val => A),
          2 => (Kind => Val_Numeric, Num_Val => B),
          3 => (Kind => Val_Numeric, Num_Val => C)));
   end F3;

   --  One string argument
   function FS1 (Name : String; A : String) return Value is
   begin
      return Call_Function (Name,
         (1 => (Kind => Val_String, Str_Val => To_Unbounded_String (A))));
   end FS1;

   --  Two string arguments
   function FS2 (Name : String; A, B : String) return Value is
   begin
      return Call_Function (Name,
         (1 => (Kind => Val_String, Str_Val => To_Unbounded_String (A)),
          2 => (Kind => Val_String, Str_Val => To_Unbounded_String (B))));
   end FS2;

   V : Value;

begin

   Put_Line ("=== Evaluator Unit Tests ===");
   Put_Line ("");

   -- (test sections added by Tasks 2-6)

   Put_Line ("");
   Put_Line (Passed'Image & " passed," & Failed'Image & " failed.");
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;

end Evaluator_Unit_Test;
```

- [ ] **Step 4: Add `evaluator_unit_test` to `sdata.gpr`**

In the `for Main` line, add the new executable:
```ada
   for Main use ("sdata_main.adb", "csv_unit_test.adb", "sdata_unit_test.adb",
                 "evaluator_unit_test.adb");
```

In the `Builder` package, add:
```ada
      for Executable ("evaluator_unit_test.adb") use "evaluator_unit_test";
```

- [ ] **Step 5: Add `evaluator_unit_test` to `Makefile` `check` target**

Immediately after the `sdata_unit_test` block in `check:`, insert:

```makefile
	@[ -x bin/evaluator_unit_test ] || $(GPRBUILD) -P $(GPR_FILE)
	@$(TIMEOUT) 30 ./bin/evaluator_unit_test; \
	 if [ $$? -ne 0 ]; then \
	   echo "Unit tests FAILED"; exit 1; \
	 fi
```

- [ ] **Step 6: Build and verify the empty harness compiles and runs**

```bash
alr build
```
Expected: build succeeds; `bin/evaluator_unit_test` exists.

```bash
./bin/evaluator_unit_test
```
Expected output:
```
=== Evaluator Unit Tests ===

 0 passed, 0 failed.
```
Exit code: 0.

- [ ] **Step 7: Commit**

```bash
git add src/sdata-evaluator.ads src/sdata-evaluator.adb \
        tests/evaluator_unit_test.adb sdata.gpr Makefile
git commit -m "Add Call_Function shim and evaluator_unit_test harness scaffold"
```

---

### Task 2: Numeric_Fns — math function tests (NF-01..NF-21)

Tests for ABS, LOG/LN, LOG10, LOG2, EXP, SQRT, ROUND, CEIL, FLOOR/INT, FIX, FP, MOD, SGN, and their domain error paths. All in one commit.

**Files:**
- Modify: `tests/evaluator_unit_test.adb`

- [ ] **Step 1: Add NF-01..NF-21 in the main body before the summary `Put_Line`**

Replace `-- (test sections added by Tasks 2-6)` with:

```ada
   Put_Line ("--- NF: Numeric Math Functions ---");

   --  NF-01: ABS of negative float
   Check_Num ("NF-01: ABS(-3.5) = 3.5", F1 ("ABS", -3.5), 3.5);

   --  NF-02: ABS of negative integer preserves integer kind
   V := Call_Function ("ABS", (1 => (Kind => Val_Integer, Int_Val => -7)));
   Check_Int ("NF-02: ABS(-7) = 7 as integer", V, 7);

   --  NF-03: ABS(0.0) = 0.0
   Check_Num ("NF-03: ABS(0.0) = 0.0", F1 ("ABS", 0.0), 0.0);

   --  NF-04: LOG(1.0) = 0.0
   Check_Num ("NF-04: LOG(1.0) = 0.0", F1 ("LOG", 1.0), 0.0);

   --  NF-05: LN(e) = 1.0 (alias check)
   Check_Num ("NF-05: LN(e) = 1.0", F1 ("LN", Ada.Numerics.e), 1.0);

   --  NF-06: LOG of negative raises domain error
   Check ("NF-06: LOG(-1.0) raises domain error",
          Raises ("LOG", (1 => (Kind => Val_Numeric, Num_Val => -1.0))), True);

   --  NF-07: LOG10(100.0) = 2.0
   Check_Num ("NF-07: LOG10(100.0) = 2.0", F1 ("LOG10", 100.0), 2.0);

   --  NF-08: LOG2(8.0) = 3.0
   Check_Num ("NF-08: LOG2(8.0) = 3.0", F1 ("LOG2", 8.0), 3.0);

   --  NF-09: EXP(0.0) = 1.0
   Check_Num ("NF-09: EXP(0.0) = 1.0", F1 ("EXP", 0.0), 1.0);

   --  NF-10: EXP(1.0) = e
   Check_Num ("NF-10: EXP(1.0) = e", F1 ("EXP", 1.0), Ada.Numerics.e, 0.0001);

   --  NF-11: SQRT(9.0) = 3.0
   Check_Num ("NF-11: SQRT(9.0) = 3.0", F1 ("SQRT", 9.0), 3.0);

   --  NF-12: SQRT of negative raises domain error
   Check ("NF-12: SQRT(-1.0) raises domain error",
          Raises ("SQRT", (1 => (Kind => Val_Numeric, Num_Val => -1.0))), True);

   --  NF-13: ROUND(3.567, 2) = 3.57
   Check_Num ("NF-13: ROUND(3.567, 2) = 3.57", F2 ("ROUND", 3.567, 2.0), 3.57);

   --  NF-14: ROUND(3.5) with default 0 decimals = 4.0
   Check_Num ("NF-14: ROUND(3.5) = 4.0", F1 ("ROUND", 3.5), 4.0);

   --  NF-15: CEIL(3.1) = 4.0
   Check_Num ("NF-15: CEIL(3.1) = 4.0", F1 ("CEIL", 3.1), 4.0);

   --  NF-16: FLOOR(3.9) = 3.0
   Check_Num ("NF-16: FLOOR(3.9) = 3.0", F1 ("FLOOR", 3.9), 3.0);

   --  NF-17: INT is an alias for FLOOR
   Check_Num ("NF-17: INT(3.9) = 3.0", F1 ("INT", 3.9), 3.0);

   --  NF-18: FIX truncates toward zero (differs from FLOOR for negatives)
   Check_Num ("NF-18: FIX(-2.7) = -2.0", F1 ("FIX", -2.7), -2.0);

   --  NF-19: FP returns fractional part
   Check_Num ("NF-19: FP(3.7) = 0.7", F1 ("FP", 3.7), 0.7);

   --  NF-20: MOD(7.0, 3.0) = 1.0
   Check_Num ("NF-20: MOD(7.0, 3.0) = 1.0", F2 ("MOD", 7.0, 3.0), 1.0);

   --  NF-21: MOD with zero divisor raises domain error
   Check ("NF-21: MOD(x, 0.0) raises domain error",
          Raises ("MOD", (1 => (Kind => Val_Numeric, Num_Val => 5.0),
                          2 => (Kind => Val_Numeric, Num_Val => 0.0))), True);
```

- [ ] **Step 2: Add NF-22..NF-28 (SGN tests) in the same section**

```ada
   --  NF-22: SGN(-5.0) = -1 as integer
   Check_Int ("NF-22: SGN(-5.0) = -1", F1 ("SGN", -5.0), -1);

   --  NF-23: SGN(0.0) = 0 as integer
   Check_Int ("NF-23: SGN(0.0) = 0", F1 ("SGN", 0.0), 0);

   --  NF-24: SGN(3.0) = 1 as integer
   Check_Int ("NF-24: SGN(3.0) = 1", F1 ("SGN", 3.0), 1);

   Put_Line ("");
```

- [ ] **Step 3: Build and run**

```bash
alr build && ./bin/evaluator_unit_test
```
Expected: all NF tests pass.  If any fail, the output shows the actual vs expected value — fix the implementation and re-run before proceeding.

- [ ] **Step 4: Commit**

```bash
git add tests/evaluator_unit_test.adb
git commit -m "Test: numeric math functions NF-01..NF-24"
```

---

### Task 3: Numeric_Fns — trigonometric function tests (NF-25..NF-38)

Tests for SIN, COS, TAN, ATN/ARCTAN, ATAN2, ARCSIN, ARCCOS, DEG, RAD, plus domain error paths for ARCSIN/ARCCOS.

**Files:**
- Modify: `tests/evaluator_unit_test.adb`

- [ ] **Step 1: Add the trig section after the NF-22..NF-24 block**

```ada
   Put_Line ("--- NF: Trigonometric Functions ---");

   --  NF-25: SIN(0.0) = 0.0
   Check_Num ("NF-25: SIN(0.0) = 0.0", F1 ("SIN", 0.0), 0.0);

   --  NF-26: COS(0.0) = 1.0
   Check_Num ("NF-26: COS(0.0) = 1.0", F1 ("COS", 0.0), 1.0);

   --  NF-27: TAN(0.0) = 0.0
   Check_Num ("NF-27: TAN(0.0) = 0.0", F1 ("TAN", 0.0), 0.0);

   --  NF-28: ATN(1.0) = π/4
   Check_Num ("NF-28: ATN(1.0) = pi/4",
              F1 ("ATN", 1.0), Float (Ada.Numerics.Pi) / 4.0);

   --  NF-29: ARCTAN is an alias for ATN
   Check_Num ("NF-29: ARCTAN(1.0) = pi/4",
              F1 ("ARCTAN", 1.0), Float (Ada.Numerics.Pi) / 4.0);

   --  NF-30: ATAN2(1.0, 1.0) = π/4
   Check_Num ("NF-30: ATAN2(1.0, 1.0) = pi/4",
              F2 ("ATAN2", 1.0, 1.0), Float (Ada.Numerics.Pi) / 4.0);

   --  NF-31: ARCSIN(1.0) = π/2
   Check_Num ("NF-31: ARCSIN(1.0) = pi/2",
              F1 ("ARCSIN", 1.0), Float (Ada.Numerics.Pi) / 2.0);

   --  NF-32: ARCSIN domain error (|x| > 1)
   Check ("NF-32: ARCSIN(2.0) raises domain error",
          Raises ("ARCSIN", (1 => (Kind => Val_Numeric, Num_Val => 2.0))), True);

   --  NF-33: ARCCOS(0.0) = π/2
   Check_Num ("NF-33: ARCCOS(0.0) = pi/2",
              F1 ("ARCCOS", 0.0), Float (Ada.Numerics.Pi) / 2.0);

   --  NF-34: ARCCOS domain error (|x| > 1)
   Check ("NF-34: ARCCOS(2.0) raises domain error",
          Raises ("ARCCOS", (1 => (Kind => Val_Numeric, Num_Val => 2.0))), True);

   --  NF-35: DEG(π) = 180.0
   Check_Num ("NF-35: DEG(pi) = 180.0",
              F1 ("DEG", Float (Ada.Numerics.Pi)), 180.0, 0.001);

   --  NF-36: RAD(180.0) = π
   Check_Num ("NF-36: RAD(180.0) = pi",
              F1 ("RAD", 180.0), Float (Ada.Numerics.Pi), 0.0001);

   --  NF-37: SIND(90.0) = 1.0
   Check_Num ("NF-37: SIND(90.0) = 1.0", F1 ("SIND", 90.0), 1.0);

   --  NF-38: COSD(0.0) = 1.0
   Check_Num ("NF-38: COSD(0.0) = 1.0", F1 ("COSD", 0.0), 1.0);

   Put_Line ("");
```

- [ ] **Step 2: Build and run**

```bash
alr build && ./bin/evaluator_unit_test
```
Expected: all NF-25..NF-38 tests pass. Fix any failures before continuing.

- [ ] **Step 3: Commit**

```bash
git add tests/evaluator_unit_test.adb
git commit -m "Test: trigonometric functions NF-25..NF-38"
```

---

### Task 4: Distrib_Fns tests (DF-01..DF-16)

Tests for the normal PDF/CDF/IDF family, logistic CDF/IDF, argument-count error handling, and random number generators (NRN regression test included).

**Files:**
- Modify: `tests/evaluator_unit_test.adb`

- [ ] **Step 1: Determine the expected NRN seed-42 value**

Run this one-line sdata script to find the deterministic value produced by NRN with seed 42:

```bash
echo "rseed 42; let x = nrn(10, 2); print x" | ./bin/sdata
```

Record the output (e.g., `11.39017`). You will use it in NF-13 below.

- [ ] **Step 2: Add the DF section after the trig block**

Replace `<NRN_SEED42_VALUE>` with the actual value from Step 1.

```ada
   Put_Line ("--- DF: Distribution Functions ---");

   --  DF-01: ZDF(0.0) = 1/sqrt(2π) ≈ 0.39894
   Check_Num ("DF-01: ZDF(0.0) = 0.39894", F1 ("ZDF", 0.0), 0.39894, 0.0001);

   --  DF-02: ZCF(0.0) = 0.5 (symmetry of standard normal)
   Check_Num ("DF-02: ZCF(0.0) = 0.5", F1 ("ZCF", 0.0), 0.5, 0.0001);

   --  DF-03: ZIF(0.5) = 0.0 (inverse of ZCF)
   Check_Num ("DF-03: ZIF(0.5) = 0.0", F1 ("ZIF", 0.5), 0.0, 0.001);

   --  DF-04: ZIF(0.975) ≈ 1.96 (standard 95% two-tailed critical value)
   Check_Num ("DF-04: ZIF(0.975) = 1.96", F1 ("ZIF", 0.975), 1.96, 0.01);

   --  DF-05: ZDF with 3 args (shifted normal): ZDF(10.0, 10.0, 2.0) = ZDF(0.0)/2
   --  Normal PDF with μ=10, σ=2 at x=10 = (1/(2*sqrt(2π))) ≈ 0.19947
   Check_Num ("DF-05: ZDF(10.0, 10.0, 2.0) = 0.19947",
              F3 ("ZDF", 10.0, 10.0, 2.0), 0.19947, 0.0001);

   --  DF-06: ZDF with exactly 2 args raises an error (not a valid call)
   Check ("DF-06: ZDF(x, mu) with 2 args raises error",
          Raises ("ZDF",
                  (1 => (Kind => Val_Numeric, Num_Val => 0.0),
                   2 => (Kind => Val_Numeric, Num_Val => 0.0))), True);

   --  DF-07: ZCF with 3 args: ZCF(10.0, 10.0, 2.0) = 0.5
   Check_Num ("DF-07: ZCF(10.0, 10.0, 2.0) = 0.5",
              F3 ("ZCF", 10.0, 10.0, 2.0), 0.5, 0.0001);

   --  DF-08: ZCF with exactly 2 args raises an error
   Check ("DF-08: ZCF(x, mu) with 2 args raises error",
          Raises ("ZCF",
                  (1 => (Kind => Val_Numeric, Num_Val => 0.0),
                   2 => (Kind => Val_Numeric, Num_Val => 0.0))), True);

   --  DF-09: LCF(0.0) = 0.5 (logistic CDF = sigmoid; sigmoid(0) = 0.5)
   Check_Num ("DF-09: LCF(0.0) = 0.5", F1 ("LCF", 0.0), 0.5, 0.0001);

   --  DF-10: LIF(0.5) = 0.0 (logit(0.5) = ln(0.5/0.5) = ln(1) = 0)
   Check_Num ("DF-10: LIF(0.5) = 0.0", F1 ("LIF", 0.5), 0.0, 0.001);

   --  DF-11: LIF domain error — p must be strictly in (0, 1)
   Check ("DF-11: LIF(0.0) raises domain error",
          Raises ("LIF", (1 => (Kind => Val_Numeric, Num_Val => 0.0))), True);
   Check ("DF-12: LIF(1.0) raises domain error",
          Raises ("LIF", (1 => (Kind => Val_Numeric, Num_Val => 1.0))), True);

   --  DF-13: NRN(10.0, 2.0) returns Val_Numeric (regression: was calling BRN)
   SData.Statistics.Set_Seed (42);
   V := F2 ("NRN", 10.0, 2.0);
   Check ("DF-13: NRN(10,2) returns Val_Numeric", V.Kind = Val_Numeric, True);
   --  Exact value with seed 42 — replace <NRN_SEED42_VALUE> with Step 1 output:
   Check_Num ("DF-13b: NRN(10,2) seed-42 value", V, <NRN_SEED42_VALUE>, 0.0001);

   --  DF-14: URN(0, 1) returns a value in [0.0, 1.0)
   SData.Statistics.Set_Seed (42);
   V := F2 ("URN", 0.0, 1.0);
   Check ("DF-14: URN(0,1) returns Val_Numeric", V.Kind = Val_Numeric, True);
   Check ("DF-14b: URN(0,1) in [0,1)", V.Num_Val >= 0.0 and V.Num_Val < 1.0, True);

   --  DF-15: ZRN() with no args returns Val_Numeric
   SData.Statistics.Set_Seed (42);
   V := F0 ("ZRN");
   Check ("DF-15: ZRN() returns Val_Numeric", V.Kind = Val_Numeric, True);

   --  DF-16: RAN() returns value in [0.0, 1.0)
   SData.Statistics.Set_Seed (42);
   V := F0 ("RAN");
   Check ("DF-16: RAN() in [0,1)", V.Num_Val >= 0.0 and V.Num_Val < 1.0, True);

   Put_Line ("");
```

- [ ] **Step 3: Build and run**

```bash
alr build && ./bin/evaluator_unit_test
```
Expected: all DF tests pass.

- [ ] **Step 4: Commit**

```bash
git add tests/evaluator_unit_test.adb
git commit -m "Test: distribution functions DF-01..DF-16"
```

---

### Task 5: Misc_Fns tests (MF-01..MF-26)

Tests for MISSING, INF, TRUE, FALSE, PI, NUM, TRUNCATE, INDEX, MATCH, LTW (Lambert W), MAXINT, MINNUM, LBOUND/UBOUND, ERR, ERL.

**Files:**
- Modify: `tests/evaluator_unit_test.adb`

- [ ] **Step 1: Add the MF section after the DF block**

```ada
   Put_Line ("--- MF: Miscellaneous Functions ---");

   --  MF-01: MISSING of Val_Missing → 1
   Check_Int ("MF-01: MISSING(missing) = 1",
              Call_Function ("MISSING",
                 (1 => (Kind => Val_Missing))), 1);

   --  MF-02: MISSING of a numeric → 0
   Check_Int ("MF-02: MISSING(3.0) = 0",
              Call_Function ("MISSING",
                 (1 => (Kind => Val_Numeric, Num_Val => 3.0))), 0);

   --  MF-03: MISSING of empty string → 1
   Check_Int ("MF-03: MISSING('') = 1",
              Call_Function ("MISSING",
                 (1 => (Kind => Val_String,
                         Str_Val => To_Unbounded_String ("")))), 1);

   --  MF-04: INF(+Inf) = 1
   Check_Int ("MF-04: INF(+Inf) = 1",
              Call_Function ("INF",
                 (1 => (Kind => Val_Numeric, Num_Val => Pos_Inf))), 1);

   --  MF-05: INF(-Inf) = 1
   Check_Int ("MF-05: INF(-Inf) = 1",
              Call_Function ("INF",
                 (1 => (Kind => Val_Numeric, Num_Val => Neg_Inf))), 1);

   --  MF-06: INF(1.0) = 0
   Check_Int ("MF-06: INF(1.0) = 0",
              Call_Function ("INF",
                 (1 => (Kind => Val_Numeric, Num_Val => 1.0))), 0);

   --  MF-07: TRUE() = 1
   Check_Int ("MF-07: TRUE() = 1", F0 ("TRUE"), 1);

   --  MF-08: FALSE() = 0
   Check_Int ("MF-08: FALSE() = 0", F0 ("FALSE"), 0);

   --  MF-09: PI() = Ada.Numerics.Pi (exact)
   Check_Num ("MF-09: PI() = pi",
              F0 ("PI"), Float (Ada.Numerics.Pi), 0.000001);

   --  MF-10: NUM("3.14") → 3.14
   Check_Num ("MF-10: NUM('3.14') = 3.14",
              FS1 ("NUM", "3.14"), 3.14, 0.001);

   --  MF-11: NUM("abc") → Val_Missing (parse error)
   Check_Missing ("MF-11: NUM('abc') = missing", FS1 ("NUM", "abc"));

   --  MF-12: TRUNCATE(3.567, 2) = 3.56 (truncate, not round)
   Check_Num ("MF-12: TRUNCATE(3.567, 2) = 3.56", F2 ("TRUNCATE", 3.567, 2.0), 3.56);

   --  MF-13: TRUNCATE(3.567, -1) → Val_Missing (negative places)
   Check_Missing ("MF-13: TRUNCATE(3.567, -1) = missing",
                  F2 ("TRUNCATE", 3.567, -1.0));

   --  MF-14: INDEX("hello world", "world") = 7
   Check_Int ("MF-14: INDEX('hello world', 'world') = 7",
              FS2 ("INDEX", "hello world", "world"), 7);

   --  MF-15: INDEX("hello", "xyz") = 0 (not found)
   Check_Int ("MF-15: INDEX('hello', 'xyz') = 0",
              FS2 ("INDEX", "hello", "xyz"), 0);

   --  MF-16: INDEX("hello", "") = 1 (empty needle)
   Check_Int ("MF-16: INDEX('hello', '') = 1",
              FS2 ("INDEX", "hello", ""), 1);

   --  MF-17: MATCH("hello world", "world", 1) = 7
   V := Call_Function ("MATCH",
           (1 => (Kind => Val_String, Str_Val => To_Unbounded_String ("hello world")),
            2 => (Kind => Val_String, Str_Val => To_Unbounded_String ("world")),
            3 => (Kind => Val_Numeric, Num_Val => 1.0)));
   Check_Int ("MF-17: MATCH('hello world','world',1) = 7", V, 7);

   --  MF-18: MATCH starting past the match returns 0
   V := Call_Function ("MATCH",
           (1 => (Kind => Val_String, Str_Val => To_Unbounded_String ("hello world")),
            2 => (Kind => Val_String, Str_Val => To_Unbounded_String ("hello")),
            3 => (Kind => Val_Numeric, Num_Val => 3.0)));
   Check_Int ("MF-18: MATCH('hello world','hello',3) = 0", V, 0);

   --  MF-19: LTW(0.0) = 0.0 (W(0) = 0 by definition)
   Check_Num ("MF-19: LTW(0.0) = 0.0", F1 ("LTW", 0.0), 0.0, 0.000001);

   --  MF-20: LTW(e) ≈ 1.0 (W(e) = 1 because 1*e^1 = e)
   Check_Num ("MF-20: LTW(e) = 1.0", F1 ("LTW", Ada.Numerics.e), 1.0, 0.0001);

   --  MF-21: LTW domain error (x < -1/e ≈ -0.3679)
   Check ("MF-21: LTW(-1.0) raises domain error",
          Raises ("LTW", (1 => (Kind => Val_Numeric, Num_Val => -1.0))), True);

   --  MF-22: MAXINT() = Integer'Last
   Check_Int ("MF-22: MAXINT() = Integer'Last", F0 ("MAXINT"), Integer'Last);

   --  MF-23: MININT() = Integer'First
   Check_Int ("MF-23: MININT() = Integer'First", F0 ("MININT"), Integer'First);

   --  MF-24: MINNUM() > 0.0 (smallest positive float)
   V := F0 ("MINNUM");
   Check ("MF-24: MINNUM() > 0.0", V.Kind = Val_Numeric and V.Num_Val > 0.0, True);

   --  MF-25: LBOUND for unknown array → Val_Missing
   Check_Missing ("MF-25: LBOUND('NONEXISTENT') = missing",
                  FS1 ("LBOUND", "NONEXISTENT"));

   --  MF-26: ERR() returns Val_Integer (value depends on runtime state)
   V := F0 ("ERR");
   Check ("MF-26: ERR() returns Val_Integer", V.Kind = Val_Integer, True);

   Put_Line ("");
```

- [ ] **Step 2: Build and run**

```bash
alr build && ./bin/evaluator_unit_test
```
Expected: all MF tests pass. Fix any failures before proceeding.

- [ ] **Step 3: Commit**

```bash
git add tests/evaluator_unit_test.adb
git commit -m "Test: miscellaneous functions MF-01..MF-26"
```

---

### Task 6: Aggregate_Fns tests (AF-01..AF-19)

Tests for SUM, MEAN, VAR, STD, MIN, MAX, N, NMISS, MEDIAN, GMEAN, HMEAN, including missing-value propagation, edge cases (N < 2 for variance), and both odd- and even-count median.

**Files:**
- Modify: `tests/evaluator_unit_test.adb`

- [ ] **Step 1: Add the AF section after the MF block**

```ada
   Put_Line ("--- AF: Aggregate Functions ---");

   --  AF-01: SUM(1, 2, 3) = 6.0
   Check_Num ("AF-01: SUM(1,2,3) = 6.0",
              Call_Function ("SUM",
                 (1 => (Kind => Val_Numeric, Num_Val => 1.0),
                  2 => (Kind => Val_Numeric, Num_Val => 2.0),
                  3 => (Kind => Val_Numeric, Num_Val => 3.0))), 6.0);

   --  AF-02: SUM with no args → Val_Missing
   Check_Missing ("AF-02: SUM() = missing",
                  Call_Function ("SUM", (1 .. 0 => (Kind => Val_Missing))));

   --  AF-03: SUM skips missing values: SUM(1, missing, 3) = 4.0
   Check_Num ("AF-03: SUM(1,missing,3) = 4.0",
              Call_Function ("SUM",
                 (1 => (Kind => Val_Numeric, Num_Val => 1.0),
                  2 => (Kind => Val_Missing),
                  3 => (Kind => Val_Numeric, Num_Val => 3.0))), 4.0);

   --  AF-04: MEAN(2, 4, 6) = 4.0
   Check_Num ("AF-04: MEAN(2,4,6) = 4.0",
              Call_Function ("MEAN",
                 (1 => (Kind => Val_Numeric, Num_Val => 2.0),
                  2 => (Kind => Val_Numeric, Num_Val => 4.0),
                  3 => (Kind => Val_Numeric, Num_Val => 6.0))), 4.0);

   --  AF-05: MEAN with no args → Val_Missing
   Check_Missing ("AF-05: MEAN() = missing",
                  Call_Function ("MEAN", (1 .. 0 => (Kind => Val_Missing))));

   --  AF-06: VAR(1,2,3,4,5) = 2.5  (sample variance: (SSQ - SS^2/N)/(N-1))
   Check_Num ("AF-06: VAR(1,2,3,4,5) = 2.5",
              Call_Function ("VAR",
                 (1 => (Kind => Val_Numeric, Num_Val => 1.0),
                  2 => (Kind => Val_Numeric, Num_Val => 2.0),
                  3 => (Kind => Val_Numeric, Num_Val => 3.0),
                  4 => (Kind => Val_Numeric, Num_Val => 4.0),
                  5 => (Kind => Val_Numeric, Num_Val => 5.0))), 2.5, 0.0001);

   --  AF-07: VAR with a single value → Val_Missing (N < 2)
   Check_Missing ("AF-07: VAR(single) = missing",
                  Call_Function ("VAR",
                     (1 => (Kind => Val_Numeric, Num_Val => 5.0))));

   --  AF-08: STD(1,2,3,4,5) ≈ 1.5811  (sample stddev = sqrt(2.5))
   Check_Num ("AF-08: STD(1,2,3,4,5) = 1.5811",
              Call_Function ("STD",
                 (1 => (Kind => Val_Numeric, Num_Val => 1.0),
                  2 => (Kind => Val_Numeric, Num_Val => 2.0),
                  3 => (Kind => Val_Numeric, Num_Val => 3.0),
                  4 => (Kind => Val_Numeric, Num_Val => 4.0),
                  5 => (Kind => Val_Numeric, Num_Val => 5.0))), 1.5811, 0.0001);

   --  AF-09: MIN(3, 1, 4, 1, 5) = 1.0
   Check_Num ("AF-09: MIN(3,1,4,1,5) = 1.0",
              Call_Function ("MIN",
                 (1 => (Kind => Val_Numeric, Num_Val => 3.0),
                  2 => (Kind => Val_Numeric, Num_Val => 1.0),
                  3 => (Kind => Val_Numeric, Num_Val => 4.0),
                  4 => (Kind => Val_Numeric, Num_Val => 1.0),
                  5 => (Kind => Val_Numeric, Num_Val => 5.0))), 1.0);

   --  AF-10: MAX(3, 1, 4, 1, 5) = 5.0
   Check_Num ("AF-10: MAX(3,1,4,1,5) = 5.0",
              Call_Function ("MAX",
                 (1 => (Kind => Val_Numeric, Num_Val => 3.0),
                  2 => (Kind => Val_Numeric, Num_Val => 1.0),
                  3 => (Kind => Val_Numeric, Num_Val => 4.0),
                  4 => (Kind => Val_Numeric, Num_Val => 1.0),
                  5 => (Kind => Val_Numeric, Num_Val => 5.0))), 5.0);

   --  AF-11: N(1, missing, 3) = 2  (count non-missing)
   Check_Int ("AF-11: N(1,missing,3) = 2",
              Call_Function ("N",
                 (1 => (Kind => Val_Numeric, Num_Val => 1.0),
                  2 => (Kind => Val_Missing),
                  3 => (Kind => Val_Numeric, Num_Val => 3.0))), 2);

   --  AF-12: NMISS(1, missing, missing, 3) = 2
   Check_Int ("AF-12: NMISS(1,missing,missing,3) = 2",
              Call_Function ("NMISS",
                 (1 => (Kind => Val_Numeric, Num_Val => 1.0),
                  2 => (Kind => Val_Missing),
                  3 => (Kind => Val_Missing),
                  4 => (Kind => Val_Numeric, Num_Val => 3.0))), 2);

   --  AF-13: MEDIAN(1,2,3,4,5) = 3.0  (odd count: middle element)
   Check_Num ("AF-13: MEDIAN(1,2,3,4,5) = 3.0",
              Call_Function ("MEDIAN",
                 (1 => (Kind => Val_Numeric, Num_Val => 1.0),
                  2 => (Kind => Val_Numeric, Num_Val => 2.0),
                  3 => (Kind => Val_Numeric, Num_Val => 3.0),
                  4 => (Kind => Val_Numeric, Num_Val => 4.0),
                  5 => (Kind => Val_Numeric, Num_Val => 5.0))), 3.0);

   --  AF-14: MEDIAN(1,2,3,4) = 2.5  (even count: avg of two middle values)
   Check_Num ("AF-14: MEDIAN(1,2,3,4) = 2.5",
              Call_Function ("MEDIAN",
                 (1 => (Kind => Val_Numeric, Num_Val => 1.0),
                  2 => (Kind => Val_Numeric, Num_Val => 2.0),
                  3 => (Kind => Val_Numeric, Num_Val => 3.0),
                  4 => (Kind => Val_Numeric, Num_Val => 4.0))), 2.5);

   --  AF-15: MEDIAN unsorted input: MEDIAN(5,3,1,4,2) = 3.0
   Check_Num ("AF-15: MEDIAN(5,3,1,4,2) = 3.0",
              Call_Function ("MEDIAN",
                 (1 => (Kind => Val_Numeric, Num_Val => 5.0),
                  2 => (Kind => Val_Numeric, Num_Val => 3.0),
                  3 => (Kind => Val_Numeric, Num_Val => 1.0),
                  4 => (Kind => Val_Numeric, Num_Val => 4.0),
                  5 => (Kind => Val_Numeric, Num_Val => 2.0))), 3.0);

   --  AF-16: GMEAN(1, 4, 16) = 4.0  (exp(mean(ln(1),ln(4),ln(16))))
   Check_Num ("AF-16: GMEAN(1,4,16) = 4.0",
              Call_Function ("GMEAN",
                 (1 => (Kind => Val_Numeric, Num_Val => 1.0),
                  2 => (Kind => Val_Numeric, Num_Val => 4.0),
                  3 => (Kind => Val_Numeric, Num_Val => 16.0))), 4.0, 0.0001);

   --  AF-17: GMEAN with a zero value → Val_Missing (ln(0) undefined)
   Check_Missing ("AF-17: GMEAN(1,0,4) = missing",
                  Call_Function ("GMEAN",
                     (1 => (Kind => Val_Numeric, Num_Val => 1.0),
                      2 => (Kind => Val_Numeric, Num_Val => 0.0),
                      3 => (Kind => Val_Numeric, Num_Val => 4.0))));

   --  AF-18: HMEAN(1, 2, 4) = 12/7 ≈ 1.7143  (N / Σ(1/x))
   Check_Num ("AF-18: HMEAN(1,2,4) = 1.7143",
              Call_Function ("HMEAN",
                 (1 => (Kind => Val_Numeric, Num_Val => 1.0),
                  2 => (Kind => Val_Numeric, Num_Val => 2.0),
                  3 => (Kind => Val_Numeric, Num_Val => 4.0))),
              12.0 / 7.0, 0.0001);

   --  AF-19: HMEAN with a zero value → Val_Missing (1/0 undefined)
   Check_Missing ("AF-19: HMEAN(1,0,4) = missing",
                  Call_Function ("HMEAN",
                     (1 => (Kind => Val_Numeric, Num_Val => 1.0),
                      2 => (Kind => Val_Numeric, Num_Val => 0.0),
                      3 => (Kind => Val_Numeric, Num_Val => 4.0))));

   Put_Line ("");
```

- [ ] **Step 2: Build and run**

```bash
alr build && ./bin/evaluator_unit_test
```
Expected: all AF tests pass. Fix any failures before continuing.

- [ ] **Step 3: Run the full test suite**

```bash
make check
```
Expected: all tests pass including the 128+ integration tests. Exit code 0.

- [ ] **Step 4: Commit**

```bash
git add tests/evaluator_unit_test.adb
git commit -m "Test: aggregate functions AF-01..AF-19"
```

---

## Self-Review Notes

**Spec coverage:** All four handler families have test cases. Random number generators beyond NRN/URN/ZRN/RAN are type-checked only (no exact values without seeding per-function); this is sufficient to catch signature bugs.

**Placeholder scan:** None — all steps contain actual Ada code.

**Type consistency:** `Value_Array`, `Check_Num`, `Check_Int`, `Check_Missing`, `Check_Str`, `F0`/`F1`/`F2`/`F3`/`FS1`/`FS2`, `Raises` — all defined once in Task 1 and used consistently in Tasks 2-6.

**Known gap:** `Check_Int` is called with the return value of a 0-arg `F0` call in MF-07/MF-08 — those handlers return `Val_Integer`, not a plain `Integer`. `Check_Int` takes a `Value`, so this is correct.

**DF-13b placeholder:** The literal `<NRN_SEED42_VALUE>` in Task 4 Step 2 must be replaced with the actual output from the `echo "rseed 42..." | ./bin/sdata` command in Task 4 Step 1 before the file will compile.
