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

   -- (test sections added by Tasks 3-6)

   Put_Line ("");
   Put_Line (Passed'Image & " passed," & Failed'Image & " failed.");
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;

end Evaluator_Unit_Test;
