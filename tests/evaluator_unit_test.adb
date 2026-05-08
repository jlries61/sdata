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
pragma Warnings (Off, SData.Statistics);

procedure Evaluator_Unit_Test is
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

   function Raises (Name : String; Args : Value_Array) return Boolean is
      V : Value;
   begin
      V := Call_Function (Name, Args);
      return V.Kind = Val_Missing;
   exception
      when others => return True;
   end Raises;

   function F0 (Name : String) return Value is
   begin
      return Call_Function (Name, (1 .. 0 => (Kind => Val_Missing)));
   end F0;

   function F1 (Name : String; A : Float) return Value is
   begin
      return Call_Function (Name,
         (1 => (Kind => Val_Numeric, Num_Val => A)));
   end F1;

   function F2 (Name : String; A, B : Float) return Value is
   begin
      return Call_Function (Name,
         (1 => (Kind => Val_Numeric, Num_Val => A),
          2 => (Kind => Val_Numeric, Num_Val => B)));
   end F2;

   function F3 (Name : String; A, B, C : Float) return Value is
   begin
      return Call_Function (Name,
         (1 => (Kind => Val_Numeric, Num_Val => A),
          2 => (Kind => Val_Numeric, Num_Val => B),
          3 => (Kind => Val_Numeric, Num_Val => C)));
   end F3;

   function FS1 (Name : String; A : String) return Value is
   begin
      return Call_Function (Name,
         (1 => (Kind => Val_String, Str_Val => To_Unbounded_String (A))));
   end FS1;

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

   --  NF-22: SGN(-5.0) = -1 as integer
   Check_Int ("NF-22: SGN(-5.0) = -1", F1 ("SGN", -5.0), -1);

   --  NF-23: SGN(0.0) = 0 as integer
   Check_Int ("NF-23: SGN(0.0) = 0", F1 ("SGN", 0.0), 0);

   --  NF-24: SGN(3.0) = 1 as integer
   Check_Int ("NF-24: SGN(3.0) = 1", F1 ("SGN", 3.0), 1);

   Put_Line ("");

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

   Put_Line ("--- DF: Distribution Functions ---");

   --  DF-01: ZDF(0.0) = 1/sqrt(2π) ≈ 0.39894
   Check_Num ("DF-01: ZDF(0.0) = 0.39894", F1 ("ZDF", 0.0), 0.39894, 0.0001);

   --  DF-02: ZCF(0.0) = 0.5 (symmetry of standard normal)
   Check_Num ("DF-02: ZCF(0.0) = 0.5", F1 ("ZCF", 0.0), 0.5, 0.0001);

   --  DF-03: ZIF(0.5) = 0.0 (inverse of ZCF)
   Check_Num ("DF-03: ZIF(0.5) = 0.0", F1 ("ZIF", 0.5), 0.0, 0.001);

   --  DF-04: ZIF(0.975) ≈ 1.96 (standard 95% two-tailed critical value)
   Check_Num ("DF-04: ZIF(0.975) = 1.96", F1 ("ZIF", 0.975), 1.96, 0.01);

   --  DF-05: ZDF with 3 args (shifted normal): ZDF(10.0, 10.0, 2.0) = 0.19947
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
   --  Exact value with seed 42:
   Check_Num ("DF-13b: NRN(10,2) seed-42 value", V, 11.39017, 0.0001);

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

   -- (test sections added by Task 6)

   Put_Line ("");
   Put_Line (Passed'Image & " passed," & Failed'Image & " failed.");
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;

end Evaluator_Unit_Test;
