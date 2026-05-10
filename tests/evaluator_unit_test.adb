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
with SData.AST;       use SData.AST;
with SData.Parser;
with SData.Variables; use SData.Variables;

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

   function Eval (S : String) return Value is
      Ctx  : SData.Parser.Parser_Context;
      Prog : Statement_Access;
      V    : Value;
   begin
      SData.Parser.Initialize (Ctx, "LET _R = " & S);
      Prog := SData.Parser.Parse_Program (Ctx);
      V := Evaluate (Prog.Expr);
      Free_Program (Prog);
      return V;
   exception
      when others =>
         Free_Program (Prog);
         raise;
   end Eval;

   function Raises_Expr (S : String) return Boolean is
      V : Value;
   begin
      V := Eval (S);
      return V.Kind = Val_Missing;
   exception
      when others => return True;
   end Raises_Expr;

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

   --  AF-06: VAR(1,2,3,4,5) = 2.5 (sample variance)
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

   --  AF-08: STD(1,2,3,4,5) ≈ 1.5811 (sample stddev = sqrt(2.5))
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

   --  AF-11: N(1, missing, 3) = 2 (count non-missing)
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

   --  AF-13: MEDIAN(1,2,3,4,5) = 3.0 (odd count: middle element)
   Check_Num ("AF-13: MEDIAN(1,2,3,4,5) = 3.0",
              Call_Function ("MEDIAN",
                 (1 => (Kind => Val_Numeric, Num_Val => 1.0),
                  2 => (Kind => Val_Numeric, Num_Val => 2.0),
                  3 => (Kind => Val_Numeric, Num_Val => 3.0),
                  4 => (Kind => Val_Numeric, Num_Val => 4.0),
                  5 => (Kind => Val_Numeric, Num_Val => 5.0))), 3.0);

   --  AF-14: MEDIAN(1,2,3,4) = 2.5 (even count: avg of two middle values)
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

   --  AF-16: GMEAN(1, 4, 16) = 4.0 (exp(mean(ln(1),ln(4),ln(16))))
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

   --  AF-18: HMEAN(1, 2, 4) = 12/7 ≈ 1.7143 (N / Σ(1/x))
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

   ---------------------------------------------------------------------------
   --  Expression evaluator tests (EV-01 .. EV-16): Literals and arithmetic
   ---------------------------------------------------------------------------

   Put_Line ("--- EV: Expression Evaluator Tests ---");

   --  EV-01: Integer literal
   Check_Int ("EV-01: integer literal 1", Eval ("1"), 1);

   --  EV-02: Float literal
   Check_Num ("EV-02: float literal 1.5", Eval ("1.5"), 1.5);

   --  EV-03: String literal
   Check_Str ("EV-03: string literal ""hello""", Eval ("""hello"""), "hello");

   --  EV-04: Integer addition -> Val_Integer
   Check_Int ("EV-04: 2 + 3 = 5 (Val_Integer)", Eval ("2 + 3"), 5);

   --  EV-05: Integer subtraction -> Val_Integer
   Check_Int ("EV-05: 7 - 2 = 5 (Val_Integer)", Eval ("7 - 2"), 5);

   --  EV-06: Integer multiplication -> Val_Integer
   Check_Int ("EV-06: 3 * 4 = 12 (Val_Integer)", Eval ("3 * 4"), 12);

   --  EV-07: Integer / integer always yields Val_Numeric (not integer division)
   Check_Num ("EV-07: 7 / 2 = 3.5 (Val_Numeric)", Eval ("7 / 2"), 3.5);

   --  EV-08: Integer ^ integer always yields Val_Numeric
   Check_Num ("EV-08: 2 ^ 3 = 8.0 (Val_Numeric)", Eval ("2 ^ 3"), 8.0);

   --  EV-09: Float operand promotes result to Val_Numeric
   Check_Num ("EV-09: 1.5 + 0.5 = 2.0 (Val_Numeric)", Eval ("1.5 + 0.5"), 2.0);

   --  EV-10: Operator precedence: * binds tighter than +
   Check_Int ("EV-10: 2 + 3 * 4 = 14", Eval ("2 + 3 * 4"), 14);

   --  EV-11: Parentheses override precedence
   Check_Int ("EV-11: (2 + 3) * 4 = 20", Eval ("(2 + 3) * 4"), 20);

   --  EV-12: Unary minus on integer -> Val_Integer
   Check_Int ("EV-12: -5 (Val_Integer)", Eval ("-5"), -5);

   --  EV-13: Unary minus on float -> Val_Numeric
   Check_Num ("EV-13: -1.5 (Val_Numeric)", Eval ("-1.5"), -1.5);

   --  EV-14: Left-associative subtraction: 10 - 3 - 2 = 5 (not 10 - (3-2) = 9)
   Check_Int ("EV-14: 10 - 3 - 2 = 5", Eval ("10 - 3 - 2"), 5);

   --  EV-15: Mixed integer + float -> Val_Numeric
   Check_Num ("EV-15: 2 + 3.0 = 5.0 (Val_Numeric)", Eval ("2 + 3.0"), 5.0);

   --  EV-16: 6 / 2 is still Val_Numeric (integer operands, division always float)
   Check_Num ("EV-16: 6 / 2 = 3.0 (Val_Numeric)", Eval ("6 / 2"), 3.0);

   ---------------------------------------------------------------------------
   --  EV-17 .. EV-32: Comparison and boolean operators
   ---------------------------------------------------------------------------

   --  EV-17: Equal — true
   Check_Int ("EV-17: 3 = 3 -> 1", Eval ("3 = 3"), 1);

   --  EV-18: Equal — false
   Check_Int ("EV-18: 3 = 4 -> 0", Eval ("3 = 4"), 0);

   --  EV-19: Not-equal — true
   Check_Int ("EV-19: 3 <> 4 -> 1", Eval ("3 <> 4"), 1);

   --  EV-20: Less-than — true
   Check_Int ("EV-20: 3 < 4 -> 1", Eval ("3 < 4"), 1);

   --  EV-21: Less-than-or-equal — equal case
   Check_Int ("EV-21: 3 <= 3 -> 1", Eval ("3 <= 3"), 1);

   --  EV-22: Greater-than — true
   Check_Int ("EV-22: 4 > 3 -> 1", Eval ("4 > 3"), 1);

   --  EV-23: Greater-than-or-equal — false
   Check_Int ("EV-23: 3 >= 4 -> 0", Eval ("3 >= 4"), 0);

   --  EV-24: AND — both true -> 1
   Check_Int ("EV-24: 1 AND 1 -> 1", Eval ("1 AND 1"), 1);

   --  EV-25: AND — one false -> 0
   Check_Int ("EV-25: 1 AND 0 -> 0", Eval ("1 AND 0"), 0);

   --  EV-26: OR — one true -> 1
   Check_Int ("EV-26: 0 OR 1 -> 1", Eval ("0 OR 1"), 1);

   --  EV-27: OR — both false -> 0
   Check_Int ("EV-27: 0 OR 0 -> 0", Eval ("0 OR 0"), 0);

   --  EV-28: XOR — both same -> 0
   Check_Int ("EV-28: 1 XOR 1 -> 0", Eval ("1 XOR 1"), 0);

   --  EV-29: XOR — different -> 1
   Check_Int ("EV-29: 1 XOR 0 -> 1", Eval ("1 XOR 0"), 1);

   --  EV-30: NOT on non-zero -> 0
   Check_Int ("EV-30: NOT 1 -> 0", Eval ("NOT 1"), 0);

   --  EV-31: NOT on zero -> 1
   Check_Int ("EV-31: NOT 0 -> 1", Eval ("NOT 0"), 1);

   --  EV-32: Compound boolean: (3 < 2) OR (5 > 4) -> 1
   Check_Int ("EV-32: (3 < 2) OR (5 > 4) -> 1", Eval ("(3 < 2) OR (5 > 4)"), 1);

   Put_Line ("");
   Put_Line (Passed'Image & " passed," & Failed'Image & " failed.");
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;

end Evaluator_Unit_Test;
