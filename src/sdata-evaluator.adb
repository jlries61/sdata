with SData.Variables; use SData.Variables;
with SData.Config;
with SData.Config.Runtime;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with SData.Statistics;
with SData.Table;
with Ada.Containers.Vectors;
with Ada.Containers.Indefinite_Hashed_Maps;
with SData.IO;        use SData.IO;
with SData.System;
with Ada.Calendar;
with Ada.Numerics;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;

--  SData.Evaluator — expression evaluator and built-in function dispatcher.
--
--  Entry points:
--    Evaluate           evaluates an Expression node to a Value
--    Evaluate_Function  dispatches a named function call
--    Is_True            coerces a Value to a Boolean (non-zero / non-empty)
--
--  Design notes:
--    * Missing value propagation: most functions return Val_Missing when any
--      required argument is missing.  Has_Args(Vals, N) encapsulates this check.
--    * LAG, NEXT, OBS and their string variants receive their first argument
--      as a variable *name* (a string) rather than the variable's current
--      value.  Is_Identifier_Ref_Function gates this special treatment.
--    * RECNO, BOF, and EOF operate in logical (filtered-view) space when a
--      SELECT filter is active; they query Logical_Record_Index rather than
--      Current_Record_Index.
--    * LAG and NEXT likewise navigate by logical offset and then map each
--      logical position to a physical row via Logical_To_Physical, so that
--      filtered-out rows are invisible to both functions.
--    * IF(cond, true_expr, false_expr) is intercepted before argument
--      flattening so that only the selected branch is evaluated (lazy eval).
--    * All other built-in functions are dispatched through Dispatch_Table,
--      a hashed map from function name to handler subprogram.  Every function
--      has its own dedicated Ada subprogram; the dispatch table is the sole
--      dispatch layer.  Synonym pairs (LOG/LN/LOGE, FLOOR/INT, FIX/IP,
--      DEG/DEGREE, etc.) share one subprogram registered under multiple keys.

package body SData.Evaluator is

   --  BOG_Flag / EOG_Flag: per-record beginning-of-group / end-of-group
   --  indicators.  Set by the interpreter's data step loop before each
   --  record's program body executes; read by BOG() and EOG() functions.
   function Is_True (V : Value) return Boolean is
   begin
      case V.Kind is
         when Val_Integer => return V.Int_Val /= 0;
         when Val_Numeric => return V.Num_Val /= 0.0;
         when Val_String  => return Length (V.Str_Val) > 0;
         when Val_Missing => return False;
      end case;
   end Is_True;

   BOG_Flag : Boolean := False;
   EOG_Flag : Boolean := False;

   ---------------------------------------------------------------------------
   --  Package-level type infrastructure for the dispatch table
   ---------------------------------------------------------------------------

   package Value_Vectors is new Ada.Containers.Vectors (Positive, Value, SData.Values."=");
   use type Ada.Containers.Count_Type;

   --  Handler signature: every family handler receives the upper-cased
   --  function name and the pre-evaluated, pre-flattened argument vector.
   type Fn_Handler is access function
      (Name : String; Vals : Value_Vectors.Vector) return Value;

   package Fn_Maps is new Ada.Containers.Indefinite_Hashed_Maps
      (Key_Type        => String,
       Element_Type    => Fn_Handler,
       Hash            => Ada.Strings.Hash,
       Equivalent_Keys => "=");

   Dispatch_Table : Fn_Maps.Map;

   ---------------------------------------------------------------------------
   --  Package-level helpers shared by Evaluate_Function and all handlers
   ---------------------------------------------------------------------------

   function Is_BOG return Boolean is (BOG_Flag);
   function Is_EOG return Boolean is (EOG_Flag);

   function Handle_Domain_Error (Msg : String) return Value is
   begin
      if SData.Config.Ignore_Math_Errors then
         Put_Line_Error ("Warning: " & Msg);
         return (Kind => Val_Missing);
      else
         raise SData.Script_Error with Msg;
      end if;
   end Handle_Domain_Error;

   procedure Set_BOG (Val : Boolean) is
   begin
      BOG_Flag := Val;
   end Set_BOG;

   procedure Set_EOG (Val : Boolean) is
   begin
      EOG_Flag := Val;
   end Set_EOG;

   function Convert_To_Float (V : Value) return Float is
   begin
      case V.Kind is
         when Val_Numeric => return V.Num_Val;
         when Val_Integer => return Float (V.Int_Val);
         when others      => raise Constraint_Error with "Cannot convert " & V.Kind'Image & " to Float";
      end case;
   end Convert_To_Float;

   --  Has_Args(Vals, N): returns True iff at least N arguments were supplied
   --  and none of the first N is missing.  Missing propagation is automatic
   --  for all functions that guard on Has_Args rather than inspecting each
   --  argument individually.
   function Has_Args (Vals : Value_Vectors.Vector; N : Positive) return Boolean is
   begin
      if Vals.Length < Ada.Containers.Count_Type (N) then return False; end if;
      for I in 1 .. N loop
         if Vals.Element (I).Kind = Val_Missing then return False; end if;
      end loop;
      return True;
   end Has_Args;

   function Num_Result (V : Float) return Value is
   begin
      return (Kind => Val_Numeric, Num_Val => V);
   end Num_Result;

   --  Functions that treat their first argument as a variable name.
   function Is_Identifier_Ref_Function (N : String) return Boolean is
      U : constant String := To_Upper (N);
   begin
      return U in "LAG" | "LAGC$" | "NEXT" | "NEXTC$" | "OBS" | "OBSC$"
                | "LBOUND" | "UBOUND";
   end Is_Identifier_Ref_Function;


   ---------------------------------------------------------------------------
   --  Math handlers — one subprogram per language function
   ---------------------------------------------------------------------------

   function Handle_Abs (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      if Vals.Element (1).Kind = Val_Integer then
         return (Kind => Val_Integer, Int_Val => abs Vals.Element (1).Int_Val);
      else
         return Num_Result (abs Convert_To_Float (Vals.Element (1)));
      end if;
   end Handle_Abs;

   --  LOG / LN / LOGE — natural logarithm
   function Handle_Log_Nat (Name : String; Vals : Value_Vectors.Vector) return Value is
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare V : constant Float := Convert_To_Float (Vals.Element (1));
      begin
         if V <= 0.0 then
            return Handle_Domain_Error ("Argument to " & Name & " must be positive.");
         end if;
         return Num_Result (Log (V));
      end;
   end Handle_Log_Nat;

   --  LOG10 / CLG / LGT — base-10 logarithm
   function Handle_Log10_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare V : constant Float := Convert_To_Float (Vals.Element (1));
      begin
         if V <= 0.0 then
            return Handle_Domain_Error ("Argument to " & Name & " must be positive.");
         end if;
         return Num_Result (Log (V, 10.0));
      end;
   end Handle_Log10_Fn;

   function Handle_Log2_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare V : constant Float := Convert_To_Float (Vals.Element (1));
      begin
         if V <= 0.0 then
            return Handle_Domain_Error ("Argument to " & Name & " must be positive.");
         end if;
         return Num_Result (Log (V) / Log (2.0));
      end;
   end Handle_Log2_Fn;

   function Handle_Exp_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare V : constant Float := Convert_To_Float (Vals.Element (1));
      begin
         if V > 88.0 then
            return Handle_Domain_Error ("Argument to " & Name & " is too large (overflow).");
         end if;
         return Num_Result (Exp (V));
      end;
   end Handle_Exp_Fn;

   function Handle_Round_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare
         V        : constant Float := Convert_To_Float (Vals.Element (1));
         Decimals : Float := 0.0;
         Factor   : Float;
      begin
         if Integer (Vals.Length) >= 2 and then Vals.Element (2).Kind /= Val_Missing then
            Decimals := Convert_To_Float (Vals.Element (2));
         end if;
         Factor := 10.0 ** Decimals;
         return Num_Result (Float'Rounding (V * Factor) / Factor);
      end;
   end Handle_Round_Fn;

   function Handle_Ceil_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Float'Ceiling (Convert_To_Float (Vals.Element (1))));
   end Handle_Ceil_Fn;

   --  FLOOR / INT — round toward -infinity
   function Handle_Floor_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Float'Floor (Convert_To_Float (Vals.Element (1))));
   end Handle_Floor_Fn;

   --  FIX / IP — truncate toward zero
   function Handle_Fix_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Float'Truncation (Convert_To_Float (Vals.Element (1))));
   end Handle_Fix_Fn;

   function Handle_Fp_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare V : constant Float := Convert_To_Float (Vals.Element (1));
      begin return Num_Result (V - Float'Truncation (V)); end;
   end Handle_Fp_Fn;

   function Handle_Mod_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      declare
         V1 : constant Float := Convert_To_Float (Vals.Element (1));
         V2 : constant Float := Convert_To_Float (Vals.Element (2));
      begin
         if V2 /= 0.0 then return Num_Result (V1 - Float'Floor (V1 / V2) * V2);
         else return Handle_Domain_Error ("Division by zero in MOD."); end if;
      end;
   end Handle_Mod_Fn;

   function Handle_Sqrt_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare V : constant Float := Convert_To_Float (Vals.Element (1));
      begin
         if V >= 0.0 then return Num_Result (Sqrt (V));
         else return Handle_Domain_Error ("Argument to SQRT must be non-negative."); end if;
      end;
   end Handle_Sqrt_Fn;

   function Handle_Sgn_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare V : constant Float := Convert_To_Float (Vals.Element (1));
      begin
         if V > 0.0 then return (Kind => Val_Integer, Int_Val => 1);
         elsif V < 0.0 then return (Kind => Val_Integer, Int_Val => -1);
         else return (Kind => Val_Integer, Int_Val => 0);
         end if;
      end;
   end Handle_Sgn_Fn;

   ---------------------------------------------------------------------------
   --  Trig handlers — one subprogram per language function
   ---------------------------------------------------------------------------

   function Handle_Sin_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Sin (Convert_To_Float (Vals.Element (1))));
   end Handle_Sin_Fn;

   function Handle_Cos_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Cos (Convert_To_Float (Vals.Element (1))));
   end Handle_Cos_Fn;

   function Handle_Tan_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Tan (Convert_To_Float (Vals.Element (1))));
   end Handle_Tan_Fn;

   function Handle_Atn_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Arctan (Convert_To_Float (Vals.Element (1))));
   end Handle_Atn_Fn;

   function Handle_Atan2_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (Arctan (Convert_To_Float (Vals.Element (1)),
                                 Convert_To_Float (Vals.Element (2))));
   end Handle_Atan2_Fn;

   function Handle_Sinh_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Sinh (Convert_To_Float (Vals.Element (1))));
   end Handle_Sinh_Fn;

   function Handle_Cosh_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Cosh (Convert_To_Float (Vals.Element (1))));
   end Handle_Cosh_Fn;

   function Handle_Tanh_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Tanh (Convert_To_Float (Vals.Element (1))));
   end Handle_Tanh_Fn;

   function Handle_Hcs_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (1.0 / Cosh (Convert_To_Float (Vals.Element (1))));
   end Handle_Hcs_Fn;

   function Handle_Hsn_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (1.0 / Sinh (Convert_To_Float (Vals.Element (1))));
   end Handle_Hsn_Fn;

   function Handle_Htn_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare V : constant Float := Convert_To_Float (Vals.Element (1));
      begin return Num_Result (Cosh (V) / Sinh (V)); end;
   end Handle_Htn_Fn;

   function Handle_Arcsin_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare V : constant Float := Convert_To_Float (Vals.Element (1));
      begin
         if V < -1.0 or else V > 1.0 then
            return Handle_Domain_Error ("ARCSIN argument must be in [-1, 1].");
         end if;
         return Num_Result (Arcsin (V));
      end;
   end Handle_Arcsin_Fn;

   function Handle_Arccos_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare V : constant Float := Convert_To_Float (Vals.Element (1));
      begin
         if V < -1.0 or else V > 1.0 then
            return Handle_Domain_Error ("ARCCOS argument must be in [-1, 1].");
         end if;
         return Num_Result (Arccos (V));
      end;
   end Handle_Arccos_Fn;

   function Handle_Arctan_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Arctan (Convert_To_Float (Vals.Element (1))));
   end Handle_Arctan_Fn;

   function Handle_Cot_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare V : constant Float := Convert_To_Float (Vals.Element (1));
      begin return Num_Result (Cos (V) / Sin (V)); end;
   end Handle_Cot_Fn;

   function Handle_Csc_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (1.0 / Sin (Convert_To_Float (Vals.Element (1))));
   end Handle_Csc_Fn;

   function Handle_Sec_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (1.0 / Cos (Convert_To_Float (Vals.Element (1))));
   end Handle_Sec_Fn;

   --  DEG / DEGREE — convert radians to degrees
   function Handle_Deg_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Convert_To_Float (Vals.Element (1)) * 180.0 / Ada.Numerics.Pi);
   end Handle_Deg_Fn;

   function Handle_Sind_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Sin (Convert_To_Float (Vals.Element (1)) * Ada.Numerics.Pi / 180.0));
   end Handle_Sind_Fn;

   function Handle_Cosd_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Cos (Convert_To_Float (Vals.Element (1)) * Ada.Numerics.Pi / 180.0));
   end Handle_Cosd_Fn;

   function Handle_Tand_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Tan (Convert_To_Float (Vals.Element (1)) * Ada.Numerics.Pi / 180.0));
   end Handle_Tand_Fn;

   function Handle_Atnd_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Arctan (Convert_To_Float (Vals.Element (1))) * 180.0 / Ada.Numerics.Pi);
   end Handle_Atnd_Fn;

   function Handle_Atan2d_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (Arctan (Convert_To_Float (Vals.Element (1)),
                                 Convert_To_Float (Vals.Element (2))) * 180.0 / Ada.Numerics.Pi);
   end Handle_Atan2d_Fn;

   ---------------------------------------------------------------------------
   --  Aggregate helpers and handlers
   ---------------------------------------------------------------------------

   type Stats_Pass_Result is record
      N_Count     : Natural    := 0;
      NMISS_Count : Natural    := 0;
      Sum         : Long_Float := 0.0;
      Sum_Sq      : Long_Float := 0.0;
      Min_V       : Long_Float := 0.0;
      Max_V       : Long_Float := 0.0;
      Has_Values  : Boolean    := False;
   end record;

   function Compute_Stats_Pass (Vals : Value_Vectors.Vector) return Stats_Pass_Result is
      R : Stats_Pass_Result;
   begin
      for V of Vals loop
         if V.Kind = Val_Missing then
            R.NMISS_Count := R.NMISS_Count + 1;
         else
            declare FV : constant Long_Float := Long_Float (Convert_To_Float (V));
            begin
               R.N_Count := R.N_Count + 1;
               R.Sum     := R.Sum + FV;
               R.Sum_Sq  := R.Sum_Sq + FV ** 2;
               if not R.Has_Values then
                  R.Min_V := FV; R.Max_V := FV; R.Has_Values := True;
               else
                  if FV < R.Min_V then R.Min_V := FV; end if;
                  if FV > R.Max_V then R.Max_V := FV; end if;
               end if;
            end;
         end if;
      end loop;
      return R;
   end Compute_Stats_Pass;

   function Handle_Sum (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R : constant Stats_Pass_Result := Compute_Stats_Pass (Vals);
   begin
      if R.N_Count = 0 then return (Kind => Val_Missing); end if;
      return (Kind => Val_Numeric, Num_Val => Float (R.Sum));
   end Handle_Sum;

   function Handle_Mean (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R : constant Stats_Pass_Result := Compute_Stats_Pass (Vals);
   begin
      if R.N_Count = 0 then return (Kind => Val_Missing); end if;
      return (Kind => Val_Numeric, Num_Val => Float (R.Sum / Long_Float (R.N_Count)));
   end Handle_Mean;

   function Handle_Var_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R  : constant Stats_Pass_Result := Compute_Stats_Pass (Vals);
      NF : Long_Float;
   begin
      if R.N_Count < 2 then return (Kind => Val_Missing); end if;
      NF := Long_Float (R.N_Count);
      return (Kind => Val_Numeric, Num_Val => Float ((R.Sum_Sq - (R.Sum ** 2 / NF)) / (NF - 1.0)));
   end Handle_Var_Fn;

   function Handle_Std_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R  : constant Stats_Pass_Result := Compute_Stats_Pass (Vals);
      NF : Long_Float;
   begin
      if R.N_Count < 2 then return (Kind => Val_Missing); end if;
      NF := Long_Float (R.N_Count);
      return (Kind => Val_Numeric,
              Num_Val => Sqrt (Float ((R.Sum_Sq - (R.Sum ** 2 / NF)) / (NF - 1.0))));
   end Handle_Std_Fn;

   function Handle_Min_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R : constant Stats_Pass_Result := Compute_Stats_Pass (Vals);
   begin
      if R.N_Count = 0 then return (Kind => Val_Missing); end if;
      return (Kind => Val_Numeric, Num_Val => Float (R.Min_V));
   end Handle_Min_Fn;

   function Handle_Max_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R : constant Stats_Pass_Result := Compute_Stats_Pass (Vals);
   begin
      if R.N_Count = 0 then return (Kind => Val_Missing); end if;
      return (Kind => Val_Numeric, Num_Val => Float (R.Max_V));
   end Handle_Max_Fn;

   function Handle_N_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R : constant Stats_Pass_Result := Compute_Stats_Pass (Vals);
   begin
      return (Kind => Val_Integer, Int_Val => R.N_Count);
   end Handle_N_Fn;

   function Handle_Nmiss_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      Count : Integer := 0;
   begin
      for V of Vals loop
         if V.Kind = Val_Missing or else (V.Kind = Val_String and then Length (V.Str_Val) = 0) then
            Count := Count + 1;
         end if;
      end loop;
      return (Kind => Val_Integer, Int_Val => Count);
   end Handle_Nmiss_Fn;

   function Handle_Gmean (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      Log_Sum : Long_Float := 0.0;
      N_Count : Natural   := 0;
   begin
      for V of Vals loop
         if V.Kind /= Val_Missing then
            declare FV : constant Float := Convert_To_Float (V);
            begin
               if FV <= 0.0 then return (Kind => Val_Missing); end if;
               Log_Sum := Log_Sum + Long_Float (Log (FV));
               N_Count := N_Count + 1;
            end;
         end if;
      end loop;
      if N_Count = 0 then return (Kind => Val_Missing); end if;
      return Num_Result (Exp (Float (Log_Sum / Long_Float (N_Count))));
   end Handle_Gmean;

   function Handle_Hmean (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      Recip_Sum : Long_Float := 0.0;
      N_Count   : Natural   := 0;
   begin
      for V of Vals loop
         if V.Kind /= Val_Missing then
            declare FV : constant Long_Float := Long_Float (Convert_To_Float (V));
            begin
               if FV = 0.0 then return (Kind => Val_Missing); end if;
               Recip_Sum := Recip_Sum + 1.0 / FV;
               N_Count   := N_Count + 1;
            end;
         end if;
      end loop;
      if N_Count = 0 then return (Kind => Val_Missing); end if;
      return Num_Result (Float (Long_Float (N_Count) / Recip_Sum));
   end Handle_Hmean;

   function Handle_Median (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      package Float_Vecs is new Ada.Containers.Vectors (Positive, Float);
      package Float_Sort  is new Float_Vecs.Generic_Sorting;
      FVals   : Float_Vecs.Vector;
      N_Count : Natural := 0;
   begin
      for I in 1 .. Integer (Vals.Length) loop
         declare V : constant Value := Vals.Element (I);
         begin
            if V.Kind /= Val_Missing then
               FVals.Append (Convert_To_Float (V));
               N_Count := N_Count + 1;
            end if;
         end;
      end loop;
      if N_Count = 0 then return (Kind => Val_Missing); end if;
      Float_Sort.Sort (FVals);
      if N_Count mod 2 = 1 then
         return Num_Result (FVals.Element ((N_Count + 1) / 2));
      else
         return Num_Result ((FVals.Element (N_Count / 2) + FVals.Element (N_Count / 2 + 1)) / 2.0);
      end if;
   end Handle_Median;

   ---------------------------------------------------------------------------
   --  To_Base_String — private helper for HEX$, OCT$, BIN$
   ---------------------------------------------------------------------------
   function To_Base_String (N : Integer; Radix : Positive) return String is
      Digits_Map : constant String := "0123456789ABCDEF";
      Buf        : String (1 .. 32);
      Len        : Natural := 0;
      Val        : Integer := abs N;
   begin
      if Val = 0 then return "0"; end if;
      while Val > 0 loop
         Len := Len + 1;
         Buf (Len) := Digits_Map (Val mod Radix + 1);
         Val := Val / Radix;
      end loop;
      for I in 1 .. Len / 2 loop
         declare Tmp : constant Character := Buf (I);
         begin Buf (I) := Buf (Len - I + 1); Buf (Len - I + 1) := Tmp; end;
      end loop;
      return Buf (1 .. Len);
   end To_Base_String;

   ---------------------------------------------------------------------------
   --  String-operation handlers — one subprogram per language function
   ---------------------------------------------------------------------------

   function Handle_Len (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare V : constant Value := Vals.Element (1);
      begin
         if V.Kind = Val_String then
            return (Kind => Val_Integer, Int_Val => Length (V.Str_Val));
         else
            return (Kind => Val_Missing);
         end if;
      end;
   end Handle_Len;

   function Handle_Left (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      declare
         V : constant Value   := Vals.Element (1);
         N : constant Integer := Integer (Convert_To_Float (Vals.Element (2)));
         R : Value (Val_String);
      begin
         if V.Kind /= Val_String then return (Kind => Val_Missing); end if;
         if N <= 0 then R.Str_Val := Null_Unbounded_String;
         elsif N >= Length (V.Str_Val) then R.Str_Val := V.Str_Val;
         else R.Str_Val := To_Unbounded_String (Slice (V.Str_Val, 1, N));
         end if;
         return R;
      end;
   end Handle_Left;

   function Handle_Right (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      declare
         V     : constant Value   := Vals.Element (1);
         N     : constant Integer := Integer (Convert_To_Float (Vals.Element (2)));
         R     : Value (Val_String);
         Start : Integer;
      begin
         if V.Kind /= Val_String then return (Kind => Val_Missing); end if;
         if N <= 0 then R.Str_Val := Null_Unbounded_String;
         elsif N >= Length (V.Str_Val) then R.Str_Val := V.Str_Val;
         else
            Start := Length (V.Str_Val) - N + 1;
            R.Str_Val := To_Unbounded_String (Slice (V.Str_Val, Start, Length (V.Str_Val)));
         end if;
         return R;
      end;
   end Handle_Right;

   function Handle_Mid (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      declare
         V     : constant Value   := Vals.Element (1);
         Start : constant Integer := Integer (Convert_To_Float (Vals.Element (2)));
         Len   : constant Integer :=
            (if Has_Args (Vals, 3) then Integer (Convert_To_Float (Vals.Element (3)))
             else Length (V.Str_Val));
         R     : Value (Val_String);
         S, E  : Integer;
      begin
         if V.Kind /= Val_String or else Start < 1 then return (Kind => Val_Missing); end if;
         S := Start;
         E := Integer'Min (S + Len - 1, Length (V.Str_Val));
         if S > Length (V.Str_Val) then R.Str_Val := Null_Unbounded_String;
         else R.Str_Val := To_Unbounded_String (Slice (V.Str_Val, S, E));
         end if;
         return R;
      end;
   end Handle_Mid;

   function Handle_Seg (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      declare
         V     : constant Value   := Vals.Element (1);
         Start : Integer          := Integer (Convert_To_Float (Vals.Element (2)));
         Len   : constant Integer := Integer (Convert_To_Float (Vals.Element (3)));
         R     : Value (Val_String);
         S, E  : Integer;
      begin
         if V.Kind /= Val_String or else Len <= 0 then return (Kind => Val_Missing); end if;
         if Start <= 0 then Start := 1; end if;
         S := Start;
         E := Integer'Min (S + Len - 1, Length (V.Str_Val));
         if S > Length (V.Str_Val) then R.Str_Val := Null_Unbounded_String;
         else R.Str_Val := To_Unbounded_String (Slice (V.Str_Val, S, E));
         end if;
         return R;
      end;
   end Handle_Seg;

   function Handle_Trim (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      V : Value;
      R : Value (Val_String);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      V := Vals.Element (1);
      if V.Kind /= Val_String then return (Kind => Val_Missing); end if;
      declare use Ada.Strings.Fixed;
      begin R.Str_Val := To_Unbounded_String (Trim (To_String (V.Str_Val), Ada.Strings.Both)); end;
      return R;
   end Handle_Trim;

   function Handle_Ltrim (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      V : Value;
      R : Value (Val_String);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      V := Vals.Element (1);
      if V.Kind /= Val_String then return (Kind => Val_Missing); end if;
      declare use Ada.Strings.Fixed;
      begin R.Str_Val := To_Unbounded_String (Trim (To_String (V.Str_Val), Ada.Strings.Left)); end;
      return R;
   end Handle_Ltrim;

   function Handle_Rtrim (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      V : Value;
      R : Value (Val_String);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      V := Vals.Element (1);
      if V.Kind /= Val_String then return (Kind => Val_Missing); end if;
      declare use Ada.Strings.Fixed;
      begin R.Str_Val := To_Unbounded_String (Trim (To_String (V.Str_Val), Ada.Strings.Right)); end;
      return R;
   end Handle_Rtrim;

   function Handle_ASCII (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare V : constant Value := Vals.Element (1);
      begin
         if V.Kind /= Val_String or else Length (V.Str_Val) = 0 then
            return (Kind => Val_Missing);
         end if;
         return (Kind => Val_Integer, Int_Val => Character'Pos (Element (V.Str_Val, 1)));
      end;
   end Handle_ASCII;

   --  UCASE$/UPPER$ share this handler; both uppercase-convert their argument.
   function Handle_Upper (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      V : Value;
      R : Value (Val_String);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      V := Vals.Element (1);
      if V.Kind /= Val_String then return (Kind => Val_Missing); end if;
      R.Str_Val := To_Unbounded_String (To_Upper (SData.Values.To_String (V)));
      return R;
   end Handle_Upper;

   --  LCASE$/LOWER$ share this handler; both lowercase-convert their argument.
   function Handle_Lower (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      V : Value;
      R : Value (Val_String);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      V := Vals.Element (1);
      if V.Kind /= Val_String then return (Kind => Val_Missing); end if;
      R.Str_Val := To_Unbounded_String (To_Lower (SData.Values.To_String (V)));
      return R;
   end Handle_Lower;

   function Handle_Pos (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      declare
         Needle   : constant Value := Vals.Element (1);
         Haystack : constant Value := Vals.Element (2);
      begin
         if Needle.Kind /= Val_String or else Haystack.Kind /= Val_String then
            return (Kind => Val_Missing);
         end if;
         if Length (Needle.Str_Val) = 0 then return (Kind => Val_Integer, Int_Val => 1); end if;
         return (Kind    => Val_Integer,
                 Int_Val => Index (Haystack.Str_Val, SData.Values.To_String (Needle)));
      end;
   end Handle_Pos;

   --  INSTR(haystack, needle) — BW BASIC argument order (reversed from POS)
   function Handle_Instr (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      declare
         Haystack : constant Value := Vals.Element (1);
         Needle   : constant Value := Vals.Element (2);
      begin
         if Needle.Kind /= Val_String or else Haystack.Kind /= Val_String then
            return (Kind => Val_Missing);
         end if;
         if Length (Needle.Str_Val) = 0 then return (Kind => Val_Integer, Int_Val => 1); end if;
         return (Kind    => Val_Integer,
                 Int_Val => Index (Haystack.Str_Val, SData.Values.To_String (Needle)));
      end;
   end Handle_Instr;

   function Handle_Chr (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R : Value (Val_String);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare Code : constant Integer := Integer (Convert_To_Float (Vals.Element (1)));
      begin
         R.Str_Val := To_Unbounded_String ("" & Character'Val (Code));
         return R;
      end;
   end Handle_Chr;

   function Handle_Str (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R : Value (Val_String);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      R.Str_Val := To_Unbounded_String (SData.Values.To_String_Formatted (Vals.Element (1)));
      return R;
   end Handle_Str;

   function Handle_Val (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare V : constant Value := Vals.Element (1);
      begin
         if V.Kind /= Val_String then return (Kind => Val_Missing); end if;
         begin
            return (Kind    => Val_Numeric,
                    Num_Val => Float'Value (SData.Values.To_String (V)));
         exception
            when Constraint_Error => return (Kind => Val_Missing);
         end;
      end;
   end Handle_Val;

   function Handle_Num_Str (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      Result : Value (Val_String);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      Result.Str_Val :=
         To_Unbounded_String (SData.Values.To_String_Formatted (Vals.Element (1)));
      return Result;
   end Handle_Num_Str;

   function Handle_Hex (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R : Value (Val_String);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      R.Str_Val := To_Unbounded_String
         (To_Base_String (Integer (Convert_To_Float (Vals.Element (1))), 16));
      return R;
   end Handle_Hex;

   function Handle_Hex_From_Str (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare
         V : constant Value := Vals.Element (1);
         S : constant String := (if V.Kind = Val_String then To_String (V.Str_Val)
                                 else Integer'Image (Integer (Convert_To_Float (V))));
      begin
         return (Kind => Val_Integer, Int_Val => Integer'Value ("16#" & S & "#"));
      exception
         when Constraint_Error => return (Kind => Val_Missing);
      end;
   end Handle_Hex_From_Str;

   function Handle_Oct (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R : Value (Val_String);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      R.Str_Val := To_Unbounded_String
         (To_Base_String (Integer (Convert_To_Float (Vals.Element (1))), 8));
      return R;
   end Handle_Oct;

   function Handle_Bin (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      R : Value (Val_String);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      R.Str_Val := To_Unbounded_String
         (To_Base_String (Integer (Convert_To_Float (Vals.Element (1))), 2));
      return R;
   end Handle_Bin;

   ---------------------------------------------------------------------------
   --  Record-navigation handlers — one subprogram per language function
   ---------------------------------------------------------------------------

   function Handle_Recno (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind    => Val_Integer,
              Int_Val => (if SData.Table.Is_Filtered
                          then Integer (SData.Table.Get_Logical_Record_Index)
                          else Integer (SData.Table.Get_Current_Record_Index)));
   end Handle_Recno;

   --  ORD(s) returns the ASCII code of the first character of s.
   --  ORD with no argument is a synonym for RECNO (logical record position).
   function Handle_Ord (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if Has_Args (Vals, 1) then
         declare V : constant Value := Vals.Element (1);
         begin
            if V.Kind /= Val_String or else Length (V.Str_Val) = 0 then
               return (Kind => Val_Missing);
            end if;
            return (Kind    => Val_Integer,
                    Int_Val => Character'Pos (Element (V.Str_Val, 1)));
         end;
      end if;
      return (Kind    => Val_Integer,
              Int_Val => (if SData.Table.Is_Filtered
                          then Integer (SData.Table.Get_Logical_Record_Index)
                          else Integer (SData.Table.Get_Current_Record_Index)));
   end Handle_Ord;

   function Handle_BOF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind    => Val_Integer,
              Int_Val => (if SData.Table.Is_Filtered
                          then (if SData.Table.Get_Logical_Record_Index <= 1 then 1 else 0)
                          else (if SData.Table.Get_Current_Record_Index <= 1 then 1 else 0)));
   end Handle_BOF;

   function Handle_EOF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind    => Val_Integer,
              Int_Val => (if SData.Table.Is_Filtered
                          then (if SData.Table.Get_Logical_Record_Index >= SData.Table.Logical_Row_Count then 1 else 0)
                          else (if SData.Table.Get_Current_Record_Index >= SData.Table.Row_Count then 1 else 0)));
   end Handle_EOF;

   function Handle_BOG (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind => Val_Integer, Int_Val => (if BOG_Flag then 1 else 0));
   end Handle_BOG;

   function Handle_EOG (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind => Val_Integer, Int_Val => (if EOG_Flag then 1 else 0));
   end Handle_EOG;

   --  LAG/LAGC$ share this handler; both look up the nth prior record value.
   function Handle_Lag (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare
         Var     : constant Value := Vals.Element (1);
         N_Val   : constant Value :=
            (if Has_Args (Vals, 2) then Vals.Element (2)
             else (Kind => Val_Integer, Int_Val => 1));
         N       : Integer;
         Log_Idx : constant Natural :=
            (if SData.Table.Is_Filtered then SData.Table.Get_Logical_Record_Index
             else SData.Table.Get_Current_Record_Index);
      begin
         if Var.Kind /= Val_String then return (Kind => Val_Missing); end if;
         N := Integer (Convert_To_Float (N_Val));
         if N <= 0 or else Log_Idx <= N then return (Kind => Val_Missing); end if;
         declare
            Phys_Curr : constant Positive := SData.Table.Logical_To_Physical (Log_Idx);
            Phys_Prev : constant Positive := SData.Table.Logical_To_Physical (Log_Idx - N);
         begin
            if not SData.Table.In_Same_Group (Phys_Curr, Phys_Prev) then
               return (Kind => Val_Missing);
            end if;
            return SData.Table.Get_Value_Upper (Phys_Prev, To_Upper (SData.Values.To_String (Var)));
         end;
      end;
   end Handle_Lag;

   --  NEXT/NEXTC$ share this handler; both look up the nth succeeding record value.
   function Handle_Next_Val (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare
         Var       : constant Value := Vals.Element (1);
         N_Val     : constant Value :=
            (if Has_Args (Vals, 2) then Vals.Element (2)
             else (Kind => Val_Integer, Int_Val => 1));
         N         : Integer;
         Log_Idx   : constant Natural :=
            (if SData.Table.Is_Filtered then SData.Table.Get_Logical_Record_Index
             else SData.Table.Get_Current_Record_Index);
         Log_Count : constant Natural :=
            (if SData.Table.Is_Filtered then SData.Table.Logical_Row_Count
             else SData.Table.Row_Count);
      begin
         if Var.Kind /= Val_String then return (Kind => Val_Missing); end if;
         N := Integer (Convert_To_Float (N_Val));
         if N <= 0 or else (Log_Idx + N) > Log_Count then return (Kind => Val_Missing); end if;
         declare
            Phys_Curr : constant Positive := SData.Table.Logical_To_Physical (Log_Idx);
            Phys_Next : constant Positive := SData.Table.Logical_To_Physical (Log_Idx + N);
         begin
            if not SData.Table.In_Same_Group (Phys_Curr, Phys_Next) then
               return (Kind => Val_Missing);
            end if;
            return SData.Table.Get_Value_Upper (Phys_Next, To_Upper (SData.Values.To_String (Var)));
         end;
      end;
   end Handle_Next_Val;

   --  OBS/OBSC$ share this handler; both look up a variable value at an absolute row.
   function Handle_Obs (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      declare
         Var     : constant Value := Vals.Element (1);
         Row_Val : constant Value := Vals.Element (2);
         Row     : Integer;
      begin
         if Var.Kind /= Val_String then return (Kind => Val_Missing); end if;
         Row := Integer (Convert_To_Float (Row_Val));
         if Row < 1 or else Row > SData.Table.Row_Count then
            return (Kind => Val_Missing);
         end if;
         return SData.Table.Get_Value_Upper (Row, To_Upper (SData.Values.To_String (Var)));
      end;
   end Handle_Obs;

   ---------------------------------------------------------------------------
   --  Statistics handlers — one subprogram per language function.
   --  L-prefix functions implement the Logistic distribution inline.
   --  MIF and BRN were previously registered but unimplemented; they are now
   --  wired to their respective SData.Statistics functions.
   ---------------------------------------------------------------------------

   --  --- PDF family ---

   function Handle_ZDF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      N : constant Natural := Natural (Vals.Length);
   begin
      if N = 2 then raise SData.Script_Error with "ZDF requires 1 or 3 arguments, not 2."; end if;
      if N >= 3 then
         if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
         return Num_Result (SData.Statistics.Normal_PDF (Convert_To_Float (Vals.Element (1)),
                                                         Convert_To_Float (Vals.Element (2)),
                                                         Convert_To_Float (Vals.Element (3))));
      else
         if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
         return Num_Result (SData.Statistics.Normal_PDF (Convert_To_Float (Vals.Element (1)), 0.0, 1.0));
      end if;
   end Handle_ZDF;

   function Handle_NDF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Normal_PDF (Convert_To_Float (Vals.Element (1)),
                                                      Convert_To_Float (Vals.Element (2)),
                                                      Convert_To_Float (Vals.Element (3))));
   end Handle_NDF;

   function Handle_UDF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Uniform_PDF (Convert_To_Float (Vals.Element (1)),
                                                       Convert_To_Float (Vals.Element (2)),
                                                       Convert_To_Float (Vals.Element (3))));
   end Handle_UDF;

   function Handle_EDF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Exponential_PDF (Convert_To_Float (Vals.Element (1)),
                                                           Convert_To_Float (Vals.Element (2))));
   end Handle_EDF;

   function Handle_BDF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Beta_PDF (Convert_To_Float (Vals.Element (1)),
                                                    Convert_To_Float (Vals.Element (2)),
                                                    Convert_To_Float (Vals.Element (3))));
   end Handle_BDF;

   function Handle_PDF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Poisson_PMF (Convert_To_Float (Vals.Element (1)),
                                                       Convert_To_Float (Vals.Element (2))));
   end Handle_PDF;

   function Handle_GDF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Gamma_PDF (Convert_To_Float (Vals.Element (1)),
                                                     Convert_To_Float (Vals.Element (2)),
                                                     Convert_To_Float (Vals.Element (3))));
   end Handle_GDF;

   function Handle_XDF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Chi_Square_PDF (Convert_To_Float (Vals.Element (1)),
                                                          Convert_To_Float (Vals.Element (2))));
   end Handle_XDF;

   function Handle_TDF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Student_T_PDF (Convert_To_Float (Vals.Element (1)),
                                                         Convert_To_Float (Vals.Element (2))));
   end Handle_TDF;

   function Handle_FDF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.F_PDF (Convert_To_Float (Vals.Element (1)),
                                                 Convert_To_Float (Vals.Element (2)),
                                                 Convert_To_Float (Vals.Element (3))));
   end Handle_FDF;

   function Handle_MDF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Binomial_PMF (Convert_To_Float (Vals.Element (1)),
                                                        Convert_To_Float (Vals.Element (2)),
                                                        Convert_To_Float (Vals.Element (3))));
   end Handle_MDF;

   function Handle_WDF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Weibull_PDF (Convert_To_Float (Vals.Element (1)),
                                                       Convert_To_Float (Vals.Element (2)),
                                                       Convert_To_Float (Vals.Element (3))));
   end Handle_WDF;

   --  Logistic PDF: f(x) = e^-x / (1 + e^-x)^2
   function Handle_LDF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare
         X : constant Float := Convert_To_Float (Vals.Element (1));
         E : constant Float := Exp (-X);
         S : constant Float := 1.0 + E;
      begin
         return Num_Result (E / (S * S));
      end;
   end Handle_LDF;

   --  --- CDF family ---

   function Handle_ZCF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      N : constant Natural := Natural (Vals.Length);
   begin
      if N = 2 then raise SData.Script_Error with "ZCF requires 1 or 3 arguments, not 2."; end if;
      if N >= 3 then
         if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
         return Num_Result (SData.Statistics.Normal_CDF (Convert_To_Float (Vals.Element (1)),
                                                         Convert_To_Float (Vals.Element (2)),
                                                         Convert_To_Float (Vals.Element (3))));
      else
         if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
         return Num_Result (SData.Statistics.Normal_CDF (Convert_To_Float (Vals.Element (1)), 0.0, 1.0));
      end if;
   end Handle_ZCF;

   function Handle_NCF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Normal_CDF (Convert_To_Float (Vals.Element (1)),
                                                      Convert_To_Float (Vals.Element (2)),
                                                      Convert_To_Float (Vals.Element (3))));
   end Handle_NCF;

   function Handle_UCF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Uniform_CDF (Convert_To_Float (Vals.Element (1)),
                                                       Convert_To_Float (Vals.Element (2)),
                                                       Convert_To_Float (Vals.Element (3))));
   end Handle_UCF;

   function Handle_ECF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Exponential_CDF (Convert_To_Float (Vals.Element (1)),
                                                           Convert_To_Float (Vals.Element (2))));
   end Handle_ECF;

   function Handle_BCF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Beta_CDF (Convert_To_Float (Vals.Element (1)),
                                                    Convert_To_Float (Vals.Element (2)),
                                                    Convert_To_Float (Vals.Element (3))));
   end Handle_BCF;

   function Handle_PCF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Poisson_CDF (Convert_To_Float (Vals.Element (1)),
                                                       Convert_To_Float (Vals.Element (2))));
   end Handle_PCF;

   function Handle_GCF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Gamma_CDF (Convert_To_Float (Vals.Element (1)),
                                                     Convert_To_Float (Vals.Element (2)),
                                                     Convert_To_Float (Vals.Element (3))));
   end Handle_GCF;

   function Handle_XCF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Chi_Square_CDF (Convert_To_Float (Vals.Element (1)),
                                                          Convert_To_Float (Vals.Element (2))));
   end Handle_XCF;

   function Handle_TCF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Student_T_CDF (Convert_To_Float (Vals.Element (1)),
                                                         Convert_To_Float (Vals.Element (2))));
   end Handle_TCF;

   function Handle_FCF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.F_CDF (Convert_To_Float (Vals.Element (1)),
                                                 Convert_To_Float (Vals.Element (2)),
                                                 Convert_To_Float (Vals.Element (3))));
   end Handle_FCF;

   function Handle_MCF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Binomial_CDF (Convert_To_Float (Vals.Element (1)),
                                                        Convert_To_Float (Vals.Element (2)),
                                                        Convert_To_Float (Vals.Element (3))));
   end Handle_MCF;

   function Handle_WCF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Weibull_CDF (Convert_To_Float (Vals.Element (1)),
                                                       Convert_To_Float (Vals.Element (2)),
                                                       Convert_To_Float (Vals.Element (3))));
   end Handle_WCF;

   --  Logistic CDF: F(x) = 1 / (1 + e^-x)  (sigmoid)
   function Handle_LCF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (1.0 / (1.0 + Exp (-Convert_To_Float (Vals.Element (1)))));
   end Handle_LCF;

   --  --- IDF family ---

   function Handle_ZIF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      N : constant Natural := Natural (Vals.Length);
   begin
      if N = 2 then raise SData.Script_Error with "ZIF requires 1 or 3 arguments, not 2."; end if;
      if N >= 3 then
         if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
         return Num_Result (SData.Statistics.Normal_IDF (Convert_To_Float (Vals.Element (1)),
                                                         Convert_To_Float (Vals.Element (2)),
                                                         Convert_To_Float (Vals.Element (3))));
      else
         if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
         return Num_Result (SData.Statistics.Normal_IDF (Convert_To_Float (Vals.Element (1)), 0.0, 1.0));
      end if;
   end Handle_ZIF;

   function Handle_NIF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Normal_IDF (Convert_To_Float (Vals.Element (1)),
                                                      Convert_To_Float (Vals.Element (2)),
                                                      Convert_To_Float (Vals.Element (3))));
   end Handle_NIF;

   function Handle_UIF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Uniform_IDF (Convert_To_Float (Vals.Element (1)),
                                                       Convert_To_Float (Vals.Element (2)),
                                                       Convert_To_Float (Vals.Element (3))));
   end Handle_UIF;

   function Handle_EIF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Exponential_IDF (Convert_To_Float (Vals.Element (1)),
                                                           Convert_To_Float (Vals.Element (2))));
   end Handle_EIF;

   function Handle_BIF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Beta_IDF (Convert_To_Float (Vals.Element (1)),
                                                    Convert_To_Float (Vals.Element (2)),
                                                    Convert_To_Float (Vals.Element (3))));
   end Handle_BIF;

   --  Logistic IDF: Q(p) = ln(p / (1-p))  (logit function); p must be in (0, 1).
   function Handle_LIF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare P : constant Float := Convert_To_Float (Vals.Element (1));
      begin
         if P <= 0.0 or else P >= 1.0 then
            return Handle_Domain_Error ("LIF argument must be in (0, 1).");
         end if;
         return Num_Result (Log (P / (1.0 - P)));
      end;
   end Handle_LIF;

   function Handle_PIF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Poisson_IDF (Convert_To_Float (Vals.Element (1)),
                                                       Convert_To_Float (Vals.Element (2))));
   end Handle_PIF;

   function Handle_GIF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Gamma_IDF (Convert_To_Float (Vals.Element (1)),
                                                     Convert_To_Float (Vals.Element (2)),
                                                     Convert_To_Float (Vals.Element (3))));
   end Handle_GIF;

   function Handle_XIF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Chi_Square_IDF (Convert_To_Float (Vals.Element (1)),
                                                          Convert_To_Float (Vals.Element (2))));
   end Handle_XIF;

   function Handle_TIF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Student_T_IDF (Convert_To_Float (Vals.Element (1)),
                                                         Convert_To_Float (Vals.Element (2))));
   end Handle_TIF;

   function Handle_FIF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.F_IDF (Convert_To_Float (Vals.Element (1)),
                                                 Convert_To_Float (Vals.Element (2)),
                                                 Convert_To_Float (Vals.Element (3))));
   end Handle_FIF;

   function Handle_WIF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Weibull_IDF (Convert_To_Float (Vals.Element (1)),
                                                       Convert_To_Float (Vals.Element (2)),
                                                       Convert_To_Float (Vals.Element (3))));
   end Handle_WIF;

   function Handle_MIF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Binomial_IDF (Convert_To_Float (Vals.Element (1)),
                                                        Convert_To_Float (Vals.Element (2)),
                                                        Convert_To_Float (Vals.Element (3))));
   end Handle_MIF;

   --  --- RN (random number) family ---

   function Handle_ZRN (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      N : constant Natural := Natural (Vals.Length);
   begin
      if N = 0 then
         return Num_Result (SData.Statistics.Normal_RN (0.0, 1.0));
      elsif N = 1 then
         if Vals.Element (1).Kind = Val_Missing then return (Kind => Val_Missing); end if;
         raise SData.Script_Error with "ZRN requires 0 or 2 arguments, not 1.";
      else
         if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
         return Num_Result (SData.Statistics.Normal_RN (Convert_To_Float (Vals.Element (1)),
                                                        Convert_To_Float (Vals.Element (2))));
      end if;
   end Handle_ZRN;

   function Handle_NRN (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Normal_RN (Convert_To_Float (Vals.Element (1)),
                                                     Convert_To_Float (Vals.Element (2))));
   end Handle_NRN;

   function Handle_URN (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      N : constant Natural := Natural (Vals.Length);
   begin
      if N = 0 then
         return Num_Result (SData.Statistics.Uniform_RN (0.0, 1.0));
      elsif N = 1 then
         if Vals.Element (1).Kind = Val_Missing then return (Kind => Val_Missing); end if;
         raise SData.Script_Error with "URN requires 0 or 2 arguments, not 1.";
      else
         if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
         return Num_Result (SData.Statistics.Uniform_RN (Convert_To_Float (Vals.Element (1)),
                                                         Convert_To_Float (Vals.Element (2))));
      end if;
   end Handle_URN;

   function Handle_ERN (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Exponential_RN (Convert_To_Float (Vals.Element (1))));
   end Handle_ERN;

   function Handle_PRN (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Poisson_RN (Convert_To_Float (Vals.Element (1))));
   end Handle_PRN;

   function Handle_GRN (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Gamma_RN (Convert_To_Float (Vals.Element (1)),
                                                    Convert_To_Float (Vals.Element (2))));
   end Handle_GRN;

   function Handle_MRN (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Binomial_RN (Convert_To_Float (Vals.Element (1)),
                                                       Convert_To_Float (Vals.Element (2))));
   end Handle_MRN;

   function Handle_WRN (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Weibull_RN (Convert_To_Float (Vals.Element (1)),
                                                      Convert_To_Float (Vals.Element (2))));
   end Handle_WRN;

   function Handle_BRN (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Beta_RN (Convert_To_Float (Vals.Element (1)),
                                                   Convert_To_Float (Vals.Element (2))));
   end Handle_BRN;

   --  Logistic RN: sample via inversion — U(0,1) → logit(U)
   function Handle_LRN (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
      U : constant Float := SData.Statistics.Uniform_RN (0.0, 1.0);
   begin
      return Num_Result (Log (U / (1.0 - U)));
   end Handle_LRN;

   function Handle_XRN (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Chi_Square_RN (Convert_To_Float (Vals.Element (1))));
   end Handle_XRN;

   function Handle_TRN (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.Student_T_RN (Convert_To_Float (Vals.Element (1))));
   end Handle_TRN;

   function Handle_FRN (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      return Num_Result (SData.Statistics.F_RN (Convert_To_Float (Vals.Element (1)),
                                                Convert_To_Float (Vals.Element (2))));
   end Handle_FRN;

   --  RAN/RANDOM share this handler; both return a Uniform(0,1) deviate.
   function Handle_Ran (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return Num_Result (SData.Statistics.Uniform_Random);
   end Handle_Ran;

   ---------------------------------------------------------------------------
   ---------------------------------------------------------------------------
   --  Misc handlers — one subprogram per language function
   ---------------------------------------------------------------------------

   function Handle_Missing (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if Integer (Vals.Length) < 1 then return (Kind => Val_Missing); end if;
      declare
         V : constant Value := Vals.Element (1);
      begin
         if V.Kind = Val_Missing or else (V.Kind = Val_String and then Length (V.Str_Val) = 0) then
            return (Kind => Val_Integer, Int_Val => 1);
         else
            return (Kind => Val_Integer, Int_Val => 0);
         end if;
      end;
   end Handle_Missing;

   function Handle_False (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind => Val_Integer, Int_Val => 0);
   end Handle_False;

   function Handle_True (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind => Val_Integer, Int_Val => 1);
   end Handle_True;

   function Handle_Err_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind => Val_Integer, Int_Val => SData.Config.Runtime.Last_Error_Code);
   end Handle_Err_Fn;

   function Handle_Erl_Fn (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind => Val_Integer, Int_Val => SData.Config.Runtime.Last_Error_Line);
   end Handle_Erl_Fn;

   function Handle_Date (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
      R   : Value (Val_String);
      Now : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Y   : Ada.Calendar.Year_Number;
      Mo  : Ada.Calendar.Month_Number;
      D   : Ada.Calendar.Day_Number;
      Sec : Ada.Calendar.Day_Duration;
      Buf : String (1 .. 10);
   begin
      Ada.Calendar.Split (Now, Y, Mo, D, Sec);
      declare
         use Ada.Strings.Fixed;
         YS : constant String := Y'Image;
         MS : constant String := (if Mo < 10 then "0" else "") & Trim (Mo'Image, Ada.Strings.Both);
         DS : constant String := (if D  < 10 then "0" else "") & Trim (D'Image,  Ada.Strings.Both);
      begin
         Buf := YS (YS'Last - 3 .. YS'Last) & "-" & MS & "-" & DS;
      end;
      R.Str_Val := To_Unbounded_String (Buf);
      return R;
   end Handle_Date;

   function Handle_Time (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
      R         : Value (Val_String);
      Now       : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      Y         : Ada.Calendar.Year_Number;
      Mo        : Ada.Calendar.Month_Number;
      D         : Ada.Calendar.Day_Number;
      Sec       : Ada.Calendar.Day_Duration;
      Total_Sec : Natural;
      H, Mi, S  : Natural;
      Buf       : String (1 .. 8);
   begin
      Ada.Calendar.Split (Now, Y, Mo, D, Sec);
      Total_Sec := Natural (Float'Floor (Float (Sec)));
      H  := Total_Sec / 3600;
      Mi := (Total_Sec mod 3600) / 60;
      S  := Total_Sec mod 60;
      declare
         use Ada.Strings.Fixed;
         HS  : constant String := (if H  < 10 then "0" else "") & Trim (H'Image,  Ada.Strings.Both);
         MiS : constant String := (if Mi < 10 then "0" else "") & Trim (Mi'Image, Ada.Strings.Both);
         SS  : constant String := (if S  < 10 then "0" else "") & Trim (S'Image,  Ada.Strings.Both);
      begin
         Buf := HS & ":" & MiS & ":" & SS;
      end;
      R.Str_Val := To_Unbounded_String (Buf);
      return R;
   end Handle_Time;

   function Handle_Shell (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      if SData.Config.Disable_Shell then
         Put_Line_Error ("Error: SHELL function is disabled.");
         return (Kind => Val_Missing);
      end if;
      declare
         Command : constant String := SData.Values.To_String (Vals.Element (1));
         Success : Boolean;
      begin
         SData.System.Shell_Execute (Command, Success);
         return (Kind => Val_Integer, Int_Val => (if Success then 0 else 1));
      end;
   end Handle_Shell;

   function Handle_Num (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare V : constant Value := Vals.Element (1);
      begin
         if V.Kind = Val_Numeric or else V.Kind = Val_Integer then
            return V;
         elsif V.Kind = Val_String then
            begin
               return (Kind    => Val_Numeric,
                       Num_Val => Float'Value (SData.Values.To_String (V)));
            exception
               when Constraint_Error => return (Kind => Val_Missing);
            end;
         else
            return (Kind => Val_Missing);
         end if;
      end;
   end Handle_Num;

   ---------------------------------------------------------------------------
   --  Handlers added in v0.6.2
   ---------------------------------------------------------------------------

   --  PI — value of pi (no arguments)
   function Handle_Pi (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return Num_Result (Ada.Numerics.Pi);
   end Handle_Pi;

   --  TIMER — seconds elapsed since midnight (wall-clock)
   function Handle_Timer (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return Num_Result (Float (Ada.Calendar.Seconds (Ada.Calendar.Clock)));
   end Handle_Timer;

   --  TRUNCATE(X, Y%) — truncate X to Y% decimal places (toward zero, no rounding)
   function Handle_Truncate (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      declare
         X      : constant Float   := Convert_To_Float (Vals.Element (1));
         Places : constant Integer := Integer (Convert_To_Float (Vals.Element (2)));
         Factor : constant Float   := 10.0 ** Float (Places);
      begin
         if Places < 0 then return (Kind => Val_Missing); end if;
         return Num_Result (Float'Truncation (X * Factor) / Factor);
      end;
   end Handle_Truncate;

   --  LBOUND(arrayname) — lower bound of a DIM array
   function Handle_Lbound (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if Integer (Vals.Length) < 1 or else Vals.Element (1).Kind /= Val_String then
         return (Kind => Val_Missing);
      end if;
      declare
         AName             : constant String := SData.Values.To_String (Vals.Element (1));
         Start_Idx, End_Idx : Integer;
      begin
         Get_Array_Bounds (AName, Start_Idx, End_Idx);
         if End_Idx < Start_Idx then return (Kind => Val_Missing); end if;
         return (Kind => Val_Integer, Int_Val => Start_Idx);
      end;
   end Handle_Lbound;

   --  UBOUND(arrayname) — upper bound of a DIM array
   function Handle_Ubound (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if Integer (Vals.Length) < 1 or else Vals.Element (1).Kind /= Val_String then
         return (Kind => Val_Missing);
      end if;
      declare
         AName             : constant String := SData.Values.To_String (Vals.Element (1));
         Start_Idx, End_Idx : Integer;
      begin
         Get_Array_Bounds (AName, Start_Idx, End_Idx);
         if End_Idx < Start_Idx then return (Kind => Val_Missing); end if;
         return (Kind => Val_Integer, Int_Val => End_Idx);
      end;
   end Handle_Ubound;

   --  INDEX(A$, B$) — 1-based position of B$ in A$, or 0 if not found
   function Handle_Index_Str (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      declare
         Haystack : constant Value := Vals.Element (1);
         Needle   : constant Value := Vals.Element (2);
      begin
         if Haystack.Kind /= Val_String or else Needle.Kind /= Val_String then
            return (Kind => Val_Missing);
         end if;
         if Length (Needle.Str_Val) = 0 then return (Kind => Val_Integer, Int_Val => 1); end if;
         return (Kind    => Val_Integer,
                 Int_Val => Index (Haystack.Str_Val, SData.Values.To_String (Needle)));
      end;
   end Handle_Index_Str;

   --  MATCH(A$, B$, X%) — 1-based position of B$ in A$ starting from position X%
   function Handle_Match (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 3) then return (Kind => Val_Missing); end if;
      declare
         Haystack : constant Value   := Vals.Element (1);
         Needle   : constant Value   := Vals.Element (2);
         Start    : constant Integer := Integer (Convert_To_Float (Vals.Element (3)));
         H_Str    : constant String  := SData.Values.To_String (Haystack);
         N_Str    : constant String  := SData.Values.To_String (Needle);
         From     : constant Positive := Positive'Max (Start, 1);
      begin
         if Haystack.Kind /= Val_String or else Needle.Kind /= Val_String then
            return (Kind => Val_Missing);
         end if;
         if From > H_Str'Length or else N_Str'Length = 0 then
            return (Kind => Val_Integer, Int_Val => (if N_Str'Length = 0 then From else 0));
         end if;
         return (Kind    => Val_Integer,
                 Int_Val => Ada.Strings.Fixed.Index (H_Str, N_Str, From));
      end;
   end Handle_Match;

   --  MAXLEN(A$) — maximum string length capacity (global --clen setting)
   function Handle_Maxlen (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind => Val_Integer, Int_Val => SData.Config.Max_String_Len);
   end Handle_Maxlen;

   --  MAXLVL — maximum supported FOR-loop nesting level (implementation constant)
   function Handle_Maxlvl (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind => Val_Integer, Int_Val => 1_000);
   end Handle_Maxlvl;

   --  MAXINT — largest representable 32-bit signed integer
   function Handle_Maxint (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind => Val_Integer, Int_Val => Integer'Last);
   end Handle_Maxint;

   --  MAXNUM — largest representable floating-point value
   function Handle_Maxnum (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return Num_Result (Float'Last);
   end Handle_Maxnum;

   --  MININT — smallest (most negative) representable 32-bit signed integer
   function Handle_Minint (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind => Val_Integer, Int_Val => Integer'First);
   end Handle_Minint;

   --  MINNUM — smallest positive representable floating-point value
   function Handle_Minnum (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return Num_Result (Float'Model_Small);
   end Handle_Minnum;

   --  RAD / RADIAN — convert degrees to radians
   function Handle_Rad (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      return Num_Result (Convert_To_Float (Vals.Element (1)) * Ada.Numerics.Pi / 180.0);
   end Handle_Rad;

   --  LTW(X) — Lambert W function W₀(x), principal branch (x ≥ -1/e)
   --  Uses Halley's method; typically converges in 5-10 iterations.
   function Handle_Ltw (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
      E_Inv : constant Float := 1.0 / Ada.Numerics.E;
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare
         X : constant Float := Convert_To_Float (Vals.Element (1));
         W : Float;
         EW, WEW, F, Fp, Fpp : Float;
      begin
         if X < -E_Inv then
            return Handle_Domain_Error ("LTW: argument must be >= -1/e (~-0.3679).");
         end if;
         if X = 0.0 then return Num_Result (0.0); end if;
         --  Initial guess
         if X >= 0.0 then
            W := Log (1.0 + X);
         else
            W := -1.0 + Sqrt (2.0 * (1.0 + Ada.Numerics.E * X));
         end if;
         --  Halley iterations
         for I in 1 .. 100 loop
            EW  := Exp (W);
            WEW := W * EW;
            F   := WEW - X;
            Fp  := EW * (W + 1.0);
            Fpp := EW * (W + 2.0);
            declare
               Denom : constant Float := Fp - F * Fpp / (2.0 * Fp);
            begin
               exit when abs Denom < Float'Model_Small;
               declare Step : constant Float := F / Denom;
               begin
                  W := W - Step;
                  exit when abs Step < Float'Epsilon * abs W + Float'Model_Small;
               end;
            end;
         end loop;
         return Num_Result (W);
      end;
   end Handle_Ltw;

   ---------------------------------------------------------------------------
   --  Evaluate_Function — public entry point
   --
   --  1. IF is intercepted early for lazy evaluation.
   --  2. All other arguments are flattened (with array expansion) into Vals.
   --  3. Dispatch_Table maps the function name to a handler subprogram.
   ---------------------------------------------------------------------------
   function Evaluate_Function (Name : String; Args : Expression_List) return Value is
      All_Vals  : Value_Vectors.Vector;
      Current   : Expression_List := Args;
      Arg_Index : Natural         := 0;
   begin
      --  IF(cond, true_expr, false_expr) requires lazy evaluation: only the
      --  selected branch is evaluated so that domain errors in the non-taken
      --  branch are never raised.  Handle it here, before the argument-
      --  flattening loop, and return immediately.
      if Name = "IF" then
         declare
            Cond_Node  : constant Expression_List := Args;
            True_Node  : constant Expression_List :=
               (if Cond_Node /= null then Cond_Node.Next else null);
            False_Node : constant Expression_List :=
               (if True_Node /= null then True_Node.Next else null);
            Cond_Val   : Value;
         begin
            if Cond_Node = null or else True_Node = null or else False_Node = null then
               return (Kind => Val_Missing);
            end if;
            Cond_Val := Evaluate (Cond_Node.Expr);
            if Cond_Val.Kind = Val_Missing then
               return (Kind => Val_Missing);
            end if;
            if Is_True (Cond_Val) then
               return Evaluate (True_Node.Expr);
            else
               return Evaluate (False_Node.Expr);
            end if;
         end;
      end if;

      --  Flatten arguments, expanding arrays where needed.
      while Current /= null loop
         Arg_Index := Arg_Index + 1;
         if Is_Identifier_Ref_Function (Name) and then Arg_Index = 1
            and then Current.Expr.Kind = Expr_Variable
         then
            --  For LAG/NEXT/OBS the first argument is the variable name, not
            --  its value.
            declare
               VName : constant String :=
                  To_Upper (Current.Expr.Var_Name (1 .. Current.Expr.Var_Len));
            begin
               All_Vals.Append ((Kind => Val_String, Str_Val => To_Unbounded_String (VName)));
            end;
         elsif Current.Expr.Kind = Expr_Variable then
            declare
               VName : constant String :=
                  To_Upper (Current.Expr.Var_Name (1 .. Current.Expr.Var_Len));
            begin
               if Has_Array (VName) then
                  declare
                     Start_Idx, End_Idx : Integer;
                  begin
                     Get_Array_Bounds (VName, Start_Idx, End_Idx);
                     for I in Start_Idx .. End_Idx loop
                        All_Vals.Append (Get_Array_Element (VName, I));
                     end loop;
                  end;
               else
                  All_Vals.Append (Evaluate (Current.Expr));
               end if;
            end;
         elsif Current.Expr.Kind = Expr_Array_Access
            or else Current.Expr.Kind = Expr_Function_Call
         then
            declare
               AName    : constant String :=
                  To_Upper ((if Current.Expr.Kind = Expr_Array_Access
                             then Current.Expr.Arr_Name (1 .. Current.Expr.Arr_Len)
                             else Current.Expr.Func_Name (1 .. Current.Expr.Func_Len)));
               Sub_List : Expression_List :=
                  (if Current.Expr.Kind = Expr_Array_Access
                   then Current.Expr.Arr_Idx
                   else Current.Expr.Arguments);
            begin
               if Has_Array (AName) then
                  while Sub_List /= null loop
                     if Sub_List.Is_Range then
                        declare
                           Lo_Val : constant Value := Evaluate (Sub_List.Expr);
                           Hi_Val : constant Value := Evaluate (Sub_List.Expr_End);
                           Lo, Hi : Integer;
                        begin
                           if Lo_Val.Kind = Val_Integer then Lo := Lo_Val.Int_Val;
                           elsif Lo_Val.Kind = Val_Numeric then Lo := Integer (Float'Floor (Lo_Val.Num_Val));
                           else raise Script_Error with "Array range lower bound must be numeric";
                           end if;

                           if Hi_Val.Kind = Val_Integer then Hi := Hi_Val.Int_Val;
                           elsif Hi_Val.Kind = Val_Numeric then Hi := Integer (Float'Floor (Hi_Val.Num_Val));
                           else raise Script_Error with "Array range upper bound must be numeric";
                           end if;

                           for I in Lo .. Hi loop
                              All_Vals.Append (Get_Array_Element (AName, I));
                           end loop;
                        exception
                           when Constraint_Error => All_Vals.Append ((Kind => Val_Missing));
                        end;
                     else
                        declare
                           Idx_Val : constant Value := Evaluate (Sub_List.Expr);
                           Idx     : Integer;
                        begin
                           if Idx_Val.Kind = Val_Integer then Idx := Idx_Val.Int_Val;
                           else Idx := Integer (Float'Floor (Convert_To_Float (Idx_Val))); end if;
                           All_Vals.Append (Get_Array_Element (AName, Idx));
                        exception
                           when Constraint_Error => All_Vals.Append ((Kind => Val_Missing));
                        end;
                     end if;
                     Sub_List := Sub_List.Next;
                  end loop;
               else
                  All_Vals.Append (Evaluate (Current.Expr));
               end if;
            end;
         else
            All_Vals.Append (Evaluate (Current.Expr));
         end if;
         Current := Current.Next;
      end loop;

      --  Dispatch via table.
      declare
         Cursor : constant Fn_Maps.Cursor := Dispatch_Table.Find (Name);
      begin
         if Fn_Maps.Has_Element (Cursor) then
            return Fn_Maps.Element (Cursor).all (Name, All_Vals);
         end if;
      end;

      return (Kind => Val_Missing);
   end Evaluate_Function;

   --------------------
   -- Get_Expected_Kind --
   --------------------
   function Get_Expected_Kind (Name : String) return Value_Kind is
   begin
      if Name'Length = 0 then return Val_Numeric; end if;
      if Name (Name'Last) = '$' then return Val_String;
      elsif Name (Name'Last) = '%' then return Val_Integer;
      else return Val_Numeric; end if;
   end Get_Expected_Kind;

   --------------
   -- Evaluate --
   --------------
   function Evaluate (Expr : Expression_Access) return Value is
   begin
      if Expr = null then return (Kind => Val_Missing); end if;

      case Expr.Kind is
         when Expr_Numeric_Literal =>
            if Expr.Is_Integer then
               return (Kind => Val_Integer, Int_Val => Expr.Int_Value);
            else
               return (Kind => Val_Numeric, Num_Val => Expr.Value);
            end if;

         when Expr_String_Literal =>
            declare V : Value (Val_String);
            begin
               V.Str_Val := Expr.Str_Value;
               return V;
            end;

         when Expr_Variable =>
            declare
               VName : constant String := To_Upper (Expr.Var_Name (1 .. Expr.Var_Len));
               VVal  : constant Value  :=
                  (if Expr.Var_Index > 0
                   then Get_PDV_Value (Expr.Var_Index)
                   else Get (VName));
            begin
               if VVal.Kind = Val_Missing then
                  --  Fall back to zero-arg functions (optional parentheses)
                  if VName in "BOF" | "EOF" | "BOG" | "EOG" | "RECNO" | "ORD" |
                              "DATE$" | "TIME$" | "RAN" | "RANDOM" | "RND" | "LRN" |
                              "ZRN" | "URN" | "PI" | "TIMER" |
                              "ERR" | "ERL" |
                              "MAXLEN" | "MAXLVL" | "MAXINT" | "MAXNUM" |
                              "MININT" | "MINNUM" |
                              "FALSE" | "TRUE" then
                     return Evaluate_Function (VName, null);
                  end if;
               end if;
               return VVal;
            end;

         when Expr_Array_Access =>
            declare
               Index_Val : constant Value :=
                  (if Expr.Arr_Idx /= null
                   then Evaluate (Expr.Arr_Idx.Expr)
                   else (Kind => Val_Missing));
               Idx : Integer;
            begin
               if Index_Val.Kind = Val_Integer then
                  Idx := Index_Val.Int_Val;
               elsif Index_Val.Kind = Val_Numeric then
                  Idx := Integer (Float'Floor (Index_Val.Num_Val));
               else
                  return (Kind => Val_Missing);
               end if;
               return Get_Array_Element (Expr.Arr_Name (1 .. Expr.Arr_Len), Idx);
            end;

         when Expr_Unary_Op =>
            declare Operand_Val : constant Value := Evaluate (Expr.Operand);
            begin
               if Expr.UOp = Op_Not then
                  if Operand_Val.Kind = Val_Missing then return (Kind => Val_Missing); end if;
                  declare V : constant Float := Convert_To_Float (Operand_Val);
                  begin
                     return (Kind => Val_Integer, Int_Val => (if V = 0.0 then 1 else 0));
                  end;
               elsif Operand_Val.Kind = Val_Numeric then
                  case Expr.UOp is
                     when Op_Neg => return (Kind => Val_Numeric, Num_Val => -Operand_Val.Num_Val);
                     when others => return (Kind => Val_Missing);
                  end case;
               elsif Operand_Val.Kind = Val_Integer then
                  case Expr.UOp is
                     when Op_Neg =>
                        if Operand_Val.Int_Val = Integer'First then
                           raise Constraint_Error with "Integer overflow in unary negation";
                        end if;
                        return (Kind => Val_Integer, Int_Val => -Operand_Val.Int_Val);
                     when others => return (Kind => Val_Missing);
                  end case;
               else return (Kind => Val_Missing); end if;
            end;

         when Expr_Binary_Op =>
            declare
               L : constant Value := Evaluate (Expr.Left);
               R : constant Value := Evaluate (Expr.Right);
            begin
               if L.Kind = Val_Missing or R.Kind = Val_Missing then
                  return (Kind => Val_Missing);
               end if;

               if (L.Kind = Val_Numeric or L.Kind = Val_Integer) and
                  (R.Kind = Val_Numeric or R.Kind = Val_Integer)
               then
                  if L.Kind = Val_Integer and R.Kind = Val_Integer then
                     declare
                        L64   : constant Long_Integer := Long_Integer (L.Int_Val);
                        R64   : constant Long_Integer := Long_Integer (R.Int_Val);
                        Res64 : Long_Integer;
                     begin
                        case Expr.Op is
                           when Op_Add => Res64 := L64 + R64;
                           when Op_Sub => Res64 := L64 - R64;
                           when Op_Mul => Res64 := L64 * R64;
                           when Op_Div =>
                              if R.Int_Val = 0 then
                                 raise SData.Script_Error with "Division by zero.";
                              end if;
                              return (Kind    => Val_Numeric,
                                      Num_Val => Float (L.Int_Val) / Float (R.Int_Val));
                           when Op_Pow =>
                              return (Kind    => Val_Numeric,
                                      Num_Val => Float (L.Int_Val) ** Float (R.Int_Val));
                           when Op_Eq  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val = R.Int_Val  then 1 else 0));
                           when Op_Ne  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val /= R.Int_Val then 1 else 0));
                           when Op_Lt  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val < R.Int_Val  then 1 else 0));
                           when Op_Le  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val <= R.Int_Val then 1 else 0));
                           when Op_Gt  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val > R.Int_Val  then 1 else 0));
                           when Op_Ge  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val >= R.Int_Val then 1 else 0));
                           when Op_And => return (Kind => Val_Integer, Int_Val => (if L.Int_Val /= 0 and R.Int_Val /= 0 then 1 else 0));
                           when Op_Or  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val /= 0 or  R.Int_Val /= 0 then 1 else 0));
                           when Op_Xor => return (Kind => Val_Integer, Int_Val => (if (L.Int_Val /= 0) /= (R.Int_Val /= 0) then 1 else 0));
                        end case;
                        if Expr.Op in Op_Add .. Op_Mul then
                           if Res64 < Long_Integer (Integer'First)
                              or else Res64 > Long_Integer (Integer'Last)
                           then
                              raise Constraint_Error with "Integer overflow in " & Expr.Op'Image;
                           end if;
                           return (Kind => Val_Integer, Int_Val => Integer (Res64));
                        end if;
                        return (Kind => Val_Missing);
                     end;
                  else
                     declare
                        FL : constant Float := Convert_To_Float (L);
                        FR : constant Float := Convert_To_Float (R);
                     begin
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
                           when Op_Eq  => return (Kind => Val_Integer, Int_Val => (if FL = FR  then 1 else 0));
                           when Op_Ne  => return (Kind => Val_Integer, Int_Val => (if FL /= FR then 1 else 0));
                           when Op_Lt  => return (Kind => Val_Integer, Int_Val => (if FL < FR  then 1 else 0));
                           when Op_Le  => return (Kind => Val_Integer, Int_Val => (if FL <= FR then 1 else 0));
                           when Op_Gt  => return (Kind => Val_Integer, Int_Val => (if FL > FR  then 1 else 0));
                           when Op_Ge  => return (Kind => Val_Integer, Int_Val => (if FL >= FR then 1 else 0));
                           when Op_And => return (Kind => Val_Integer, Int_Val => (if FL /= 0.0 and FR /= 0.0 then 1 else 0));
                           when Op_Or  => return (Kind => Val_Integer, Int_Val => (if FL /= 0.0 or  FR /= 0.0 then 1 else 0));
                           when Op_Xor => return (Kind => Val_Integer, Int_Val => (if (FL /= 0.0) /= (FR /= 0.0) then 1 else 0));
                        end case;
                     end;
                  end if;

               elsif L.Kind = Val_String and R.Kind = Val_String then
                  case Expr.Op is
                     when Op_Add =>
                        declare
                           V     : Value (Val_String);
                           Limit : Natural := 1024;
                        begin
                           if SData.Config.Max_String_Len > 0 then
                              Limit := SData.Config.Max_String_Len;
                           end if;
                           declare
                              LL : constant Natural := Length (L.Str_Val);
                              RL : constant Natural := Length (R.Str_Val);
                           begin
                              if LL + RL > Limit then
                                 Put_Line_Error ("Warning: String truncated to " &
                                                Integer'Image (Limit) & " characters.");
                                 if LL >= Limit then
                                    V.Str_Val := To_Unbounded_String (Slice (L.Str_Val, 1, Limit));
                                 else
                                    V.Str_Val := L.Str_Val & Slice (R.Str_Val, 1, Limit - LL);
                                 end if;
                              else
                                 V.Str_Val := L.Str_Val & R.Str_Val;
                              end if;
                           end;
                           return V;
                        end;
                     when Op_Eq  => return (Kind => Val_Integer, Int_Val => (if L.Str_Val = R.Str_Val then 1 else 0));
                     when Op_Ne  => return (Kind => Val_Integer, Int_Val => (if L.Str_Val /= R.Str_Val then 1 else 0));
                     when Op_Lt  => return (Kind => Val_Integer, Int_Val => (if L.Str_Val < R.Str_Val then 1 else 0));
                     when Op_Le  => return (Kind => Val_Integer, Int_Val => (if L.Str_Val <= R.Str_Val then 1 else 0));
                     when Op_Gt  => return (Kind => Val_Integer, Int_Val => (if L.Str_Val > R.Str_Val then 1 else 0));
                     when Op_Ge  => return (Kind => Val_Integer, Int_Val => (if L.Str_Val >= R.Str_Val then 1 else 0));
                     when others => raise SData.Script_Error with "Operator not supported for character values.";
                  end case;
               else
                  raise SData.Script_Error with "Type mismatch in expression (e.g., combining numeric and character values).";
               end if;
            end;

         when Expr_Function_Call =>
            declare
               FName : constant String :=
                  To_Upper (Expr.Func_Name (1 .. Expr.Func_Len));
            begin
               if Has_Array (FName) then
                  declare
                     Index_Val : constant Value :=
                        (if Expr.Arguments /= null
                         then Evaluate (Expr.Arguments.Expr)
                         else (Kind => Val_Missing));
                     Idx : Integer;
                  begin
                     if Index_Val.Kind = Val_Integer then
                        Idx := Index_Val.Int_Val;
                     elsif Index_Val.Kind = Val_Numeric then
                        Idx := Integer (Float'Floor (Index_Val.Num_Val));
                     else
                        return (Kind => Val_Missing);
                     end if;
                     return Get_Array_Element (FName, Idx);
                  end;
               else
                  return Evaluate_Function (FName, Expr.Arguments);
               end if;
            end;
      end case;
   end Evaluate;


   ---------------------------------------------------------------------------
   --  Package initialization — populate the dispatch table.
   --  Each function name is registered exactly once; every name maps to the
   --  handler subprogram for its family.
   ---------------------------------------------------------------------------
   procedure Register_All_Functions is
   begin
      --  Math
      Dispatch_Table.Insert ("ABS",    Handle_Abs'Access);
      Dispatch_Table.Insert ("LOG",    Handle_Log_Nat'Access);
      Dispatch_Table.Insert ("LN",     Handle_Log_Nat'Access);
      Dispatch_Table.Insert ("LOGE",   Handle_Log_Nat'Access);
      Dispatch_Table.Insert ("LOG10",  Handle_Log10_Fn'Access);
      Dispatch_Table.Insert ("CLG",    Handle_Log10_Fn'Access);
      Dispatch_Table.Insert ("LGT",    Handle_Log10_Fn'Access);
      Dispatch_Table.Insert ("LOG2",   Handle_Log2_Fn'Access);
      Dispatch_Table.Insert ("EXP",    Handle_Exp_Fn'Access);
      Dispatch_Table.Insert ("ROUND",  Handle_Round_Fn'Access);
      Dispatch_Table.Insert ("CEIL",   Handle_Ceil_Fn'Access);
      Dispatch_Table.Insert ("FLOOR",  Handle_Floor_Fn'Access);
      Dispatch_Table.Insert ("INT",    Handle_Floor_Fn'Access);
      Dispatch_Table.Insert ("FIX",    Handle_Fix_Fn'Access);
      Dispatch_Table.Insert ("IP",     Handle_Fix_Fn'Access);
      Dispatch_Table.Insert ("FP",     Handle_Fp_Fn'Access);
      Dispatch_Table.Insert ("FRAC",   Handle_Fp_Fn'Access);
      Dispatch_Table.Insert ("MOD",    Handle_Mod_Fn'Access);
      Dispatch_Table.Insert ("SQRT",   Handle_Sqrt_Fn'Access);
      Dispatch_Table.Insert ("SQR",    Handle_Sqrt_Fn'Access);
      Dispatch_Table.Insert ("SGN",    Handle_Sgn_Fn'Access);

      --  Trigonometry
      Dispatch_Table.Insert ("SIN",    Handle_Sin_Fn'Access);
      Dispatch_Table.Insert ("COS",    Handle_Cos_Fn'Access);
      Dispatch_Table.Insert ("TAN",    Handle_Tan_Fn'Access);
      Dispatch_Table.Insert ("ATN",    Handle_Atn_Fn'Access);
      Dispatch_Table.Insert ("ATAN2",  Handle_Atan2_Fn'Access);
      Dispatch_Table.Insert ("SINH",   Handle_Sinh_Fn'Access);
      Dispatch_Table.Insert ("COSH",   Handle_Cosh_Fn'Access);
      Dispatch_Table.Insert ("TANH",   Handle_Tanh_Fn'Access);
      Dispatch_Table.Insert ("HCS",    Handle_Hcs_Fn'Access);
      Dispatch_Table.Insert ("HSN",    Handle_Hsn_Fn'Access);
      Dispatch_Table.Insert ("HTN",    Handle_Htn_Fn'Access);
      Dispatch_Table.Insert ("ARCSIN", Handle_Arcsin_Fn'Access);
      Dispatch_Table.Insert ("ARCCOS", Handle_Arccos_Fn'Access);
      Dispatch_Table.Insert ("ARCTAN", Handle_Arctan_Fn'Access);
      Dispatch_Table.Insert ("COT",    Handle_Cot_Fn'Access);
      Dispatch_Table.Insert ("CSC",    Handle_Csc_Fn'Access);
      Dispatch_Table.Insert ("SEC",    Handle_Sec_Fn'Access);
      Dispatch_Table.Insert ("DEG",    Handle_Deg_Fn'Access);
      Dispatch_Table.Insert ("DEGREE", Handle_Deg_Fn'Access);
      Dispatch_Table.Insert ("SIND",   Handle_Sind_Fn'Access);
      Dispatch_Table.Insert ("COSD",   Handle_Cosd_Fn'Access);
      Dispatch_Table.Insert ("TAND",   Handle_Tand_Fn'Access);
      Dispatch_Table.Insert ("ATND",   Handle_Atnd_Fn'Access);
      Dispatch_Table.Insert ("ATAN2D", Handle_Atan2d_Fn'Access);

      --  Aggregate
      Dispatch_Table.Insert ("SUM",    Handle_Sum'Access);
      Dispatch_Table.Insert ("MEAN",   Handle_Mean'Access);
      Dispatch_Table.Insert ("STD",    Handle_Std_Fn'Access);
      Dispatch_Table.Insert ("VAR",    Handle_Var_Fn'Access);
      Dispatch_Table.Insert ("MIN",    Handle_Min_Fn'Access);
      Dispatch_Table.Insert ("MAX",    Handle_Max_Fn'Access);
      Dispatch_Table.Insert ("N",      Handle_N_Fn'Access);
      Dispatch_Table.Insert ("NMISS",  Handle_Nmiss_Fn'Access);
      Dispatch_Table.Insert ("GMEAN",  Handle_Gmean'Access);
      Dispatch_Table.Insert ("HMEAN",  Handle_Hmean'Access);
      Dispatch_Table.Insert ("MEDIAN", Handle_Median'Access);

      --  String operations
      Dispatch_Table.Insert ("LEN",    Handle_Len'Access);
      Dispatch_Table.Insert ("LEFT$",  Handle_Left'Access);
      Dispatch_Table.Insert ("RIGHT$", Handle_Right'Access);
      Dispatch_Table.Insert ("MID$",   Handle_Mid'Access);
      Dispatch_Table.Insert ("SEG$",   Handle_Seg'Access);
      Dispatch_Table.Insert ("TRIM$",  Handle_Trim'Access);
      Dispatch_Table.Insert ("LTRIM$", Handle_Ltrim'Access);
      Dispatch_Table.Insert ("RTRIM$", Handle_Rtrim'Access);
      Dispatch_Table.Insert ("ASCII",  Handle_ASCII'Access);
      Dispatch_Table.Insert ("ASC",    Handle_ASCII'Access);
      Dispatch_Table.Insert ("UCASE$", Handle_Upper'Access);
      Dispatch_Table.Insert ("UPPER$", Handle_Upper'Access);
      Dispatch_Table.Insert ("LCASE$", Handle_Lower'Access);
      Dispatch_Table.Insert ("LOWER$", Handle_Lower'Access);
      Dispatch_Table.Insert ("POS",    Handle_Pos'Access);
      Dispatch_Table.Insert ("INSTR",  Handle_Instr'Access);
      Dispatch_Table.Insert ("CHR$",   Handle_Chr'Access);
      Dispatch_Table.Insert ("STR$",   Handle_Str'Access);
      Dispatch_Table.Insert ("VAL",    Handle_Val'Access);
      Dispatch_Table.Insert ("HEX$",   Handle_Hex'Access);
      Dispatch_Table.Insert ("HEX",    Handle_Hex_From_Str'Access);
      Dispatch_Table.Insert ("OCT$",   Handle_Oct'Access);
      Dispatch_Table.Insert ("BIN$",   Handle_Bin'Access);
      Dispatch_Table.Insert ("NUM$",   Handle_Num_Str'Access);

      --  Record navigation
      Dispatch_Table.Insert ("RECNO",  Handle_Recno'Access);
      Dispatch_Table.Insert ("BOF",    Handle_BOF'Access);
      Dispatch_Table.Insert ("EOF",    Handle_EOF'Access);
      Dispatch_Table.Insert ("BOG",    Handle_BOG'Access);
      Dispatch_Table.Insert ("EOG",    Handle_EOG'Access);
      Dispatch_Table.Insert ("ORD",    Handle_Ord'Access);
      Dispatch_Table.Insert ("LAG",    Handle_Lag'Access);
      Dispatch_Table.Insert ("LAGC$",  Handle_Lag'Access);
      Dispatch_Table.Insert ("NEXT",   Handle_Next_Val'Access);
      Dispatch_Table.Insert ("NEXTC$", Handle_Next_Val'Access);
      Dispatch_Table.Insert ("OBS",    Handle_Obs'Access);
      Dispatch_Table.Insert ("OBSC$",  Handle_Obs'Access);

      --  Statistical distributions — PDF family
      Dispatch_Table.Insert ("ZDF",    Handle_ZDF'Access);
      Dispatch_Table.Insert ("NDF",    Handle_NDF'Access);
      Dispatch_Table.Insert ("UDF",    Handle_UDF'Access);
      Dispatch_Table.Insert ("EDF",    Handle_EDF'Access);
      Dispatch_Table.Insert ("BDF",    Handle_BDF'Access);
      Dispatch_Table.Insert ("PDF",    Handle_PDF'Access);
      Dispatch_Table.Insert ("GDF",    Handle_GDF'Access);
      Dispatch_Table.Insert ("XDF",    Handle_XDF'Access);
      Dispatch_Table.Insert ("TDF",    Handle_TDF'Access);
      Dispatch_Table.Insert ("FDF",    Handle_FDF'Access);
      Dispatch_Table.Insert ("MDF",    Handle_MDF'Access);
      Dispatch_Table.Insert ("WDF",    Handle_WDF'Access);
      Dispatch_Table.Insert ("LDF",    Handle_LDF'Access);
      --  CDF family
      Dispatch_Table.Insert ("ZCF",    Handle_ZCF'Access);
      Dispatch_Table.Insert ("NCF",    Handle_NCF'Access);
      Dispatch_Table.Insert ("UCF",    Handle_UCF'Access);
      Dispatch_Table.Insert ("ECF",    Handle_ECF'Access);
      Dispatch_Table.Insert ("BCF",    Handle_BCF'Access);
      Dispatch_Table.Insert ("PCF",    Handle_PCF'Access);
      Dispatch_Table.Insert ("GCF",    Handle_GCF'Access);
      Dispatch_Table.Insert ("XCF",    Handle_XCF'Access);
      Dispatch_Table.Insert ("TCF",    Handle_TCF'Access);
      Dispatch_Table.Insert ("FCF",    Handle_FCF'Access);
      Dispatch_Table.Insert ("MCF",    Handle_MCF'Access);
      Dispatch_Table.Insert ("WCF",    Handle_WCF'Access);
      Dispatch_Table.Insert ("LCF",    Handle_LCF'Access);
      --  IDF family
      Dispatch_Table.Insert ("ZIF",    Handle_ZIF'Access);
      Dispatch_Table.Insert ("NIF",    Handle_NIF'Access);
      Dispatch_Table.Insert ("UIF",    Handle_UIF'Access);
      Dispatch_Table.Insert ("EIF",    Handle_EIF'Access);
      Dispatch_Table.Insert ("BIF",    Handle_BIF'Access);
      Dispatch_Table.Insert ("LIF",    Handle_LIF'Access);
      Dispatch_Table.Insert ("PIF",    Handle_PIF'Access);
      Dispatch_Table.Insert ("MIF",    Handle_MIF'Access);
      Dispatch_Table.Insert ("GIF",    Handle_GIF'Access);
      Dispatch_Table.Insert ("XIF",    Handle_XIF'Access);
      Dispatch_Table.Insert ("TIF",    Handle_TIF'Access);
      Dispatch_Table.Insert ("FIF",    Handle_FIF'Access);
      Dispatch_Table.Insert ("WIF",    Handle_WIF'Access);
      --  RN family
      Dispatch_Table.Insert ("ZRN",    Handle_ZRN'Access);
      Dispatch_Table.Insert ("NRN",    Handle_NRN'Access);
      Dispatch_Table.Insert ("URN",    Handle_URN'Access);
      Dispatch_Table.Insert ("ERN",    Handle_ERN'Access);
      Dispatch_Table.Insert ("PRN",    Handle_PRN'Access);
      Dispatch_Table.Insert ("GRN",    Handle_GRN'Access);
      Dispatch_Table.Insert ("MRN",    Handle_MRN'Access);
      Dispatch_Table.Insert ("WRN",    Handle_WRN'Access);
      Dispatch_Table.Insert ("BRN",    Handle_BRN'Access);
      Dispatch_Table.Insert ("LRN",    Handle_LRN'Access);
      Dispatch_Table.Insert ("XRN",    Handle_XRN'Access);
      Dispatch_Table.Insert ("TRN",    Handle_TRN'Access);
      Dispatch_Table.Insert ("FRN",    Handle_FRN'Access);
      Dispatch_Table.Insert ("RAN",    Handle_Ran'Access);
      Dispatch_Table.Insert ("RANDOM", Handle_Ran'Access);
      Dispatch_Table.Insert ("RND",    Handle_Ran'Access);

      --  Miscellaneous
      Dispatch_Table.Insert ("MISSING", Handle_Missing'Access);
      Dispatch_Table.Insert ("FALSE",   Handle_False'Access);
      Dispatch_Table.Insert ("TRUE",    Handle_True'Access);
      Dispatch_Table.Insert ("DATE$",   Handle_Date'Access);
      Dispatch_Table.Insert ("TIME$",   Handle_Time'Access);
      Dispatch_Table.Insert ("SHELL",   Handle_Shell'Access);
      Dispatch_Table.Insert ("NUM",     Handle_Num'Access);
      Dispatch_Table.Insert ("ERR",     Handle_Err_Fn'Access);
      Dispatch_Table.Insert ("ERL",     Handle_Erl_Fn'Access);

      Dispatch_Table.Insert ("PI",      Handle_Pi'Access);
      Dispatch_Table.Insert ("TIMER",   Handle_Timer'Access);
      Dispatch_Table.Insert ("TRUNCATE", Handle_Truncate'Access);
      Dispatch_Table.Insert ("LBOUND",  Handle_Lbound'Access);
      Dispatch_Table.Insert ("UBOUND",  Handle_Ubound'Access);
      Dispatch_Table.Insert ("INDEX",   Handle_Index_Str'Access);
      Dispatch_Table.Insert ("MATCH",   Handle_Match'Access);
      Dispatch_Table.Insert ("MAXLEN",  Handle_Maxlen'Access);
      Dispatch_Table.Insert ("MAXLVL",  Handle_Maxlvl'Access);
      Dispatch_Table.Insert ("MAXINT",  Handle_Maxint'Access);
      Dispatch_Table.Insert ("MAXNUM",  Handle_Maxnum'Access);
      Dispatch_Table.Insert ("MININT",  Handle_Minint'Access);
      Dispatch_Table.Insert ("MINNUM",  Handle_Minnum'Access);
      Dispatch_Table.Insert ("RAD",     Handle_Rad'Access);
      Dispatch_Table.Insert ("RADIAN",  Handle_Rad'Access);
      Dispatch_Table.Insert ("LTW",     Handle_Ltw'Access);
   end Register_All_Functions;

begin
   Register_All_Functions;
end SData.Evaluator;
