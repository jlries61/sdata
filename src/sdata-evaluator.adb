with SData.Interpreter;
with SData.Variables; use SData.Variables;
with SData.Config;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with SData.Statistics;
with SData.Table;
with Ada.Containers.Vectors;
with SData.IO;        use SData.IO;
with SData.System;
with Ada.Calendar;
with Ada.Numerics;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;

--  SData.Evaluator — expression evaluator and built-in function dispatcher.
--
--  Entry points:
--    Evaluate           evaluates an Expression node to a Value
--    Evaluate_Function  dispatches a named function call
--    Is_True            coerces a Value to a Boolean (non-zero / non-empty)
--
--  Design notes:
--    * Missing value propagation: most functions return Val_Missing when any
--      required argument is missing.  Has_Args(N) encapsulates this check.
--    * LAG, NEXT, OBS and their string variants receive their first argument
--      as a variable *name* (a string) rather than the variable's current
--      value.  Is_Identifier_Ref_Function gates this special treatment.
--    * RECNO, BOF, and EOF operate in logical (filtered-view) space when a
--      SELECT filter is active; they query Logical_Record_Index rather than
--      Current_Record_Index.
--    * LAG and NEXT likewise navigate by logical offset and then map each
--      logical position to a physical row via Logical_To_Physical, so that
--      filtered-out rows are invisible to both functions.

package body SData.Evaluator is

   --  BOG_Flag / EOG_Flag: per-record beginning-of-group / end-of-group
   --  indicators.  Set by the interpreter's data step loop before each
   --  record's program body executes; read by BOG() and EOG() functions.
   BOG_Flag : Boolean := False;
   EOG_Flag : Boolean := False;

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

   -----------------------
   -- Convert_To_Float --
   -----------------------
   function Convert_To_Float (V : Value) return Float is
   begin
      case V.Kind is
         when Val_Numeric => return V.Num_Val;
         when Val_Integer => return Float (V.Int_Val);
         when others      => raise Constraint_Error with "Cannot convert " & V.Kind'Image & " to Float";
      end case;
   end Convert_To_Float;

   ----------------------
   -- Evaluate_Function --
   ----------------------
   function Evaluate_Function (Name : String; Args : Expression_List) return Value is
      
      package Value_Vectors is new Ada.Containers.Vectors (Positive, Value, SData.Values."=");
      use type Ada.Containers.Count_Type;
      
      All_Vals : Value_Vectors.Vector;
      Current  : Expression_List := Args;
      Arg_Index : Natural := 0;

      --  Has_Args(N): returns True iff at least N arguments were supplied and
      --  none of the first N is missing.  A missing argument is treated the
      --  same as an absent one so that missing propagation is automatic for
      --  all functions that guard on Has_Args rather than inspecting each
      --  argument individually.
      function Has_Args (N : Positive) return Boolean is
      begin
         if All_Vals.Length < Ada.Containers.Count_Type(N) then return False; end if;
         for I in 1 .. N loop
            if All_Vals.Element (I).Kind = Val_Missing then return False; end if;
         end loop;
         return True;
      end Has_Args;

      function Num_Result (V : Float) return Value is
      begin
         return (Kind => Val_Numeric, Num_Val => V);
      end Num_Result;

      --  Functions that treat their first argument as a variable name if it's an identifier.
      function Is_Identifier_Ref_Function (N : String) return Boolean is
         U : constant String := To_Upper (N);
      begin
         return U = "LAG" or else U = "LAGC$" or else U = "NEXT" or else U = "NEXTC$" 
                or else U = "OBS" or else U = "OBSC$";
      end Is_Identifier_Ref_Function;

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

      -- Flatten arguments, expanding arrays if necessary
      while Current /= null loop
         Arg_Index := Arg_Index + 1;
         if Is_Identifier_Ref_Function (Name) and then Arg_Index = 1 and then Current.Expr.Kind = Expr_Variable then
            -- For these functions, if the first argument is a variable reference,
            -- use the name of the variable instead of its current value.
            declare
               VName : constant String := To_Upper (Current.Expr.Var_Name (1 .. Current.Expr.Var_Len));
            begin
               All_Vals.Append ((Kind => Val_String, Str_Val => To_Unbounded_String (VName)));
            end;
         elsif Current.Expr.Kind = Expr_Variable then
            declare
               VName : constant String := To_Upper (Current.Expr.Var_Name (1 .. Current.Expr.Var_Len));
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
         elsif Current.Expr.Kind = Expr_Array_Access or else Current.Expr.Kind = Expr_Function_Call then
            declare
               AName : constant String := To_Upper ((if Current.Expr.Kind = Expr_Array_Access 
                                                     then Current.Expr.Arr_Name (1 .. Current.Expr.Arr_Len)
                                                     else Current.Expr.Func_Name (1 .. Current.Expr.Func_Len)));
               Sub_List : Expression_List := (if Current.Expr.Kind = Expr_Array_Access 
                                              then Current.Expr.Arr_Idx
                                              else Current.Expr.Arguments);
            begin
               -- If it's an array, expand subscripts
               if Has_Array (AName) then
                  while Sub_List /= null loop
                     declare
                        Idx_Val : constant Value := Evaluate (Sub_List.Expr);
                        Idx : Integer;
                     begin
                        if Idx_Val.Kind = Val_Integer then Idx := Idx_Val.Int_Val;
                        else Idx := Integer (Float'Floor (Convert_To_Float (Idx_Val))); end if;
                        All_Vals.Append (Get_Array_Element (AName, idx));
                     exception
                        when Constraint_Error => All_Vals.Append ((Kind => Val_Missing));
                     end;
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

      --  Math Functions
      if Name = "ABS" and then Has_Args (1) then
         if All_Vals.Element (1).Kind = Val_Integer then
            return (Kind => Val_Integer, Int_Val => abs All_Vals.Element (1).Int_Val);
         else
            return Num_Result (abs Convert_To_Float (All_Vals.Element (1)));
         end if;
      elsif Name = "LOG" and then Has_Args (1) then
         declare V : constant Float := Convert_To_Float (All_Vals.Element (1));
         begin
            if V <= 0.0 then
               return Handle_Domain_Error ("Argument to LOG must be positive.");
            end if;
            return Num_Result (Log (V));
         end;
      elsif Name = "LOG10" and then Has_Args (1) then
         declare V : constant Float := Convert_To_Float (All_Vals.Element (1));
         begin
            if V <= 0.0 then
               return Handle_Domain_Error ("Argument to LOG10 must be positive.");
            end if;
            return Num_Result (Log (V, 10.0));
         end;
      elsif (Name = "LN" or else Name = "LOGE") and then Has_Args (1) then
         declare V : constant Float := Convert_To_Float (All_Vals.Element (1));
         begin
            if V <= 0.0 then
               return Handle_Domain_Error ("Argument to " & Name & " must be positive.");
            end if;
            return Num_Result (Log (V));
         end;
      elsif Name = "LOG2" and then Has_Args (1) then
         declare V : constant Float := Convert_To_Float (All_Vals.Element (1));
         begin
            if V <= 0.0 then
               return Handle_Domain_Error ("Argument to LOG2 must be positive.");
            end if;
            return Num_Result (Log (V) / Log (2.0));
         end;
      elsif (Name = "CLG" or else Name = "LGT") and then Has_Args (1) then
         declare V : constant Float := Convert_To_Float (All_Vals.Element (1));
         begin
            if V <= 0.0 then
               return Handle_Domain_Error ("Argument to " & Name & " must be positive.");
            end if;
            return Num_Result (Log (V, 10.0));
         end;
      elsif Name = "EXP" and then Has_Args (1) then
         declare
            V : constant Float := Convert_To_Float (All_Vals.Element (1));
         begin
            if V > 88.0 then
               return Handle_Domain_Error ("Argument to EXP is too large (overflow).");
            end if;
            return Num_Result (Exp (V));
         end;
      elsif Name = "ROUND" and then Has_Args (1) then
         declare
            V : constant Float := Convert_To_Float (All_Vals.Element (1));
            Decimals : Float := 0.0;
            Factor : Float;
         begin
            if Integer(All_Vals.Length) >= 2 and then All_Vals.Element (2).Kind /= Val_Missing then
               Decimals := Convert_To_Float (All_Vals.Element (2));
            end if;
            Factor := 10.0 ** Decimals;
            return Num_Result (Float'Rounding (V * Factor) / Factor);
         end;
      elsif Name = "CEIL" and then Has_Args (1) then
         return Num_Result (Float'Ceiling (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "FLOOR" and then Has_Args (1) then
         return Num_Result (Float'Floor (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "INT" and then Has_Args (1) then
         return Num_Result (Float'Floor (Convert_To_Float (All_Vals.Element (1))));
      elsif (Name = "FIX" or else Name = "IP") and then Has_Args (1) then
         return Num_Result (Float'Truncation (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "FP" and then Has_Args (1) then
         declare V : constant Float := Convert_To_Float (All_Vals.Element (1));
         begin return Num_Result (V - Float'Truncation (V)); end;
      elsif Name = "MOD" and then Has_Args (2) then
         declare
            V1 : constant Float := Convert_To_Float (All_Vals.Element (1));
            V2 : constant Float := Convert_To_Float (All_Vals.Element (2));
         begin
            if V2 /= 0.0 then return Num_Result (V1 - Float'Floor(V1/V2) * V2);
            else return Handle_Domain_Error ("Division by zero in MOD."); end if;
         end;
      elsif Name = "RECNO" then
         return (Kind => Val_Integer,
                 Int_Val => (if SData.Table.Is_Filtered
                             then Integer (SData.Table.Get_Logical_Record_Index)
                             else Integer (SData.Table.Get_Current_Record_Index)));
      elsif Name = "BOG" then
         return (Kind => Val_Integer, Int_Val => (if BOG_Flag then 1 else 0));
      elsif Name = "EOG" then
         return (Kind => Val_Integer, Int_Val => (if EOG_Flag then 1 else 0));
      elsif Name = "MISSING" and then Integer(All_Vals.Length) >= 1 then
         return (Kind => Val_Integer, Int_Val => (if All_Vals.Element (1).Kind = Val_Missing then 1 else 0));
      elsif Name = "SQRT" and then Has_Args (1) then
         declare
            V : constant Float := Convert_To_Float (All_Vals.Element (1));
         begin
            if V >= 0.0 then return Num_Result (Sqrt (V));
            else return Handle_Domain_Error ("Argument to SQRT must be non-negative."); end if;
         end;

      --  Aggregate Functions (row-wise, operating on the argument list for
      --  the current record).  All eight functions share a single pass that
      --  accumulates count, sum, sum-of-squares, min, and max simultaneously;
      --  Long_Float is used to reduce cancellation error in VAR/STD.
      --  STD/VAR return missing when N < 2 (sample formula requires at least
      --  two non-missing values).
      elsif Name = "SUM" or Name = "MEAN" or Name = "STD" or Name = "VAR" or
            Name = "MIN" or Name = "MAX" or Name = "N" or Name = "NMISS" then
         declare
            Sum, Sum_Sq, Min_V, Max_V : Long_Float := 0.0;
            N_Count, NMISS_Count : Natural := 0;
            First_Val : Boolean := True;
         begin
            for V of All_Vals loop
               if V.Kind = Val_Missing then
                  NMISS_Count := NMISS_Count + 1;
               else
                  declare FV : constant Long_Float := Long_Float (Convert_To_Float (V));
                  begin
                     N_Count := N_Count + 1;
                     Sum := Sum + FV;
                     Sum_Sq := Sum_Sq + FV**2;
                     if First_Val then
                        Min_V := FV; Max_V := FV; First_Val := False;
                     else
                        if FV < Min_V then Min_V := FV; end if;
                        if FV > Max_V then Max_V := FV; end if;
                     end if;
                  end;
               end if;
            end loop;

            if Name = "N" then return (Kind => Val_Integer, Int_Val => N_Count);
            elsif Name = "NMISS" then return (Kind => Val_Integer, Int_Val => NMISS_Count);
            end if;

            if N_Count = 0 then return (Kind => Val_Missing); end if;

            declare
               NF : constant Long_Float := Long_Float (N_Count);
            begin
               if Name = "SUM" then return (Kind => Val_Numeric, Num_Val => Float (Sum));
               elsif Name = "MEAN" then return (Kind => Val_Numeric, Num_Val => Float (Sum / NF));
               elsif Name = "MIN" then return (Kind => Val_Numeric, Num_Val => Float (Min_V));
               elsif Name = "MAX" then return (Kind => Val_Numeric, Num_Val => Float (Max_V));
               elsif Name = "VAR" or Name = "STD" then
                  if N_Count > 1 then
                     declare Variance : constant Long_Float := (Sum_Sq - (Sum**2 / NF)) / (NF - 1.0);
                     begin
                        if Name = "VAR" then return (Kind => Val_Numeric, Num_Val => Float (Variance));
                        else return (Kind => Val_Numeric, Num_Val => Sqrt (Float (Variance))); end if;
                     end;
                  else
                     return (Kind => Val_Missing);
                  end if;
               end if;
            end;
         end;

      elsif Name = "GMEAN" then
         declare
            Log_Sum : Long_Float := 0.0;
            N_Count : Natural := 0;
         begin
            for V of All_Vals loop
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
         end;
      elsif Name = "HMEAN" then
         declare
            Recip_Sum : Long_Float := 0.0;
            N_Count   : Natural := 0;
         begin
            for V of All_Vals loop
               if V.Kind /= Val_Missing then
                  declare FV : constant Long_Float := Long_Float (Convert_To_Float (V));
                  begin
                     if FV = 0.0 then return (Kind => Val_Missing); end if;
                     Recip_Sum := Recip_Sum + 1.0 / FV;
                     N_Count := N_Count + 1;
                  end;
               end if;
            end loop;
            if N_Count = 0 then return (Kind => Val_Missing); end if;
            return Num_Result (Float (Long_Float (N_Count) / Recip_Sum));
         end;
      elsif Name = "FALSE" then
         return (Kind => Val_Integer, Int_Val => 0);
      elsif Name = "TRUE" then
         return (Kind => Val_Integer, Int_Val => 1);

      -- Statistical Distributions (PDF)
      elsif Name = "ZDF" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Normal_PDF (Convert_To_Float (All_Vals.Element (1)), 0.0, 1.0));
      elsif Name = "NDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Normal_PDF (Convert_To_Float (All_Vals.Element (1)), 
                                                         Convert_To_Float (All_Vals.Element (2)), 
                                                         Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "UDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Uniform_PDF (Convert_To_Float (All_Vals.Element (1)), 
                                                          Convert_To_Float (All_Vals.Element (2)), 
                                                          Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "EDF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Exponential_PDF (Convert_To_Float (All_Vals.Element (1)), 
                                                              Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "BDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Beta_PDF (Convert_To_Float (All_Vals.Element (1)), 
                                                       Convert_To_Float (All_Vals.Element (2)), 
                                                       Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "PDF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Poisson_PMF (Convert_To_Float (All_Vals.Element (1)), 
                                                          Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "GDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Gamma_PDF (Convert_To_Float (All_Vals.Element (1)), 
                                                        Convert_To_Float (All_Vals.Element (2)), 
                                                        Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "XDF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Chi_Square_PDF (Convert_To_Float (All_Vals.Element (1)), 
                                                             Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "TDF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Student_T_PDF (Convert_To_Float (All_Vals.Element (1)), 
                                                            Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "FDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.F_PDF (Convert_To_Float (All_Vals.Element (1)), 
                                                    Convert_To_Float (All_Vals.Element (2)), 
                                                    Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "MDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Binomial_PMF (Convert_To_Float (All_Vals.Element (1)), 
                                                           Convert_To_Float (All_Vals.Element (2)), 
                                                           Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "WDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Weibull_PDF (Convert_To_Float (All_Vals.Element (1)), 
                                                         Convert_To_Float (All_Vals.Element (2)), 
                                                         Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "LDF" and then Has_Args (1) then
         declare X : constant Float := Convert_To_Float (All_Vals.Element (1));
                 E : constant Float := Exp (-X);
                 S : constant Float := 1.0 + E;
         begin return Num_Result (E / (S * S)); end;

      -- Statistical Distributions (CDF)
      elsif Name = "ZCF" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Normal_CDF (Convert_To_Float (All_Vals.Element (1)), 0.0, 1.0));
      elsif Name = "NCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Normal_CDF (Convert_To_Float (All_Vals.Element (1)), 
                                                         Convert_To_Float (All_Vals.Element (2)), 
                                                         Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "UCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Uniform_CDF (Convert_To_Float (All_Vals.Element (1)), 
                                                          Convert_To_Float (All_Vals.Element (2)), 
                                                          Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "ECF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Exponential_CDF (Convert_To_Float (All_Vals.Element (1)), 
                                                              Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "BCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Beta_CDF (Convert_To_Float (All_Vals.Element (1)), 
                                                       Convert_To_Float (All_Vals.Element (2)), 
                                                       Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "PCF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Poisson_CDF (Convert_To_Float (All_Vals.Element (1)), 
                                                          Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "GCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Gamma_CDF (Convert_To_Float (All_Vals.Element (1)), 
                                                        Convert_To_Float (All_Vals.Element (2)), 
                                                        Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "XCF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Chi_Square_CDF (Convert_To_Float (All_Vals.Element (1)), 
                                                             Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "TCF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Student_T_CDF (Convert_To_Float (All_Vals.Element (1)), 
                                                            Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "FCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.F_CDF (Convert_To_Float (All_Vals.Element (1)), 
                                                    Convert_To_Float (All_Vals.Element (2)), 
                                                    Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "MCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Binomial_CDF (Convert_To_Float (All_Vals.Element (1)), 
                                                           Convert_To_Float (All_Vals.Element (2)), 
                                                           Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "WCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Weibull_CDF (Convert_To_Float (All_Vals.Element (1)), 
                                                         Convert_To_Float (All_Vals.Element (2)), 
                                                         Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "LCF" and then Has_Args (1) then
         return Num_Result (1.0 / (1.0 + Exp (-Convert_To_Float (All_Vals.Element (1)))));

      -- Statistical Distributions (IDF)
      elsif Name = "ZIF" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Normal_IDF (Convert_To_Float (All_Vals.Element (1)), 0.0, 1.0));
      elsif Name = "NIF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Normal_IDF (Convert_To_Float (All_Vals.Element (1)), 
                                                         Convert_To_Float (All_Vals.Element (2)), 
                                                         Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "UIF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Uniform_IDF (Convert_To_Float (All_Vals.Element (1)), 
                                                          Convert_To_Float (All_Vals.Element (2)), 
                                                          Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "EIF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Exponential_IDF (Convert_To_Float (All_Vals.Element (1)), 
                                                              Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "BIF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Beta_IDF (Convert_To_Float (All_Vals.Element (1)), 
                                                       Convert_To_Float (All_Vals.Element (2)), 
                                                       Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "LIF" and then Has_Args (1) then
         declare P : constant Float := Convert_To_Float (All_Vals.Element (1));
         begin
            if P <= 0.0 or else P >= 1.0 then
               return Handle_Domain_Error ("LIF argument must be in (0, 1).");
            end if;
            return Num_Result (Log (P / (1.0 - P)));
         end;
      elsif Name = "PIF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Poisson_IDF (Convert_To_Float (All_Vals.Element (1)), 
                                                          Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "GIF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Gamma_IDF (Convert_To_Float (All_Vals.Element (1)),
                                                        Convert_To_Float (All_Vals.Element (2)),
                                                        Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "XIF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Chi_Square_IDF (Convert_To_Float (All_Vals.Element (1)),
                                                             Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "TIF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Student_T_IDF (Convert_To_Float (All_Vals.Element (1)),
                                                            Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "FIF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.F_IDF (Convert_To_Float (All_Vals.Element (1)),
                                                    Convert_To_Float (All_Vals.Element (2)),
                                                    Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "WIF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Weibull_IDF (Convert_To_Float (All_Vals.Element (1)),
                                                          Convert_To_Float (All_Vals.Element (2)),
                                                          Convert_To_Float (All_Vals.Element (3))));

      -- Random Numbers (RN)
      elsif Name = "ZRN" then
         return Num_Result (SData.Statistics.Normal_RN (0.0, 1.0));
      elsif Name = "NRN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Normal_RN (Convert_To_Float (All_Vals.Element (1)), 
                                                        Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "URN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Uniform_RN (Convert_To_Float (All_Vals.Element (1)), 
                                                         Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "ERN" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Exponential_RN (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "PRN" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Poisson_RN (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "GRN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Gamma_RN (Convert_To_Float (All_Vals.Element (1)), 
                                                       Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "MRN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Binomial_RN (Convert_To_Float (All_Vals.Element (1)), 
                                                          Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "WRN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Weibull_RN (Convert_To_Float (All_Vals.Element (1)), 
                                                         Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "LRN" then
         declare U : constant Float := SData.Statistics.Uniform_RN (0.0, 1.0);
         begin return Num_Result (Log (U / (1.0 - U))); end;
      elsif Name = "XRN" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Chi_Square_RN (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "TRN" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Student_T_RN (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "FRN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.F_RN (Convert_To_Float (All_Vals.Element (1)),
                                                   Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "SHELL" and then Has_Args (1) then
         if SData.Config.Disable_Shell then
            Put_Line_Error ("Error: SHELL function is disabled.");
            return (Kind => Val_Missing);
         else
            declare
               Command : constant String := SData.Values.To_String (All_Vals.Element (1));
               Success : Boolean;
            begin
               SData.System.Shell_Execute (Command, Success);
               return (Kind => Val_Integer, Int_Val => (if Success then 0 else 1));
            end;
         end if;
      elsif Name = "NUM" and then Has_Args (1) then
         declare
            V : constant Value := All_Vals.Element (1);
         begin
            if V.Kind = Val_Numeric or V.Kind = Val_Integer then
               return V;
            elsif V.Kind = Val_String then
               begin
                  return (Kind => Val_Numeric, Num_Val => Float'Value (SData.Values.To_String (V)));
               exception
                  when Constraint_Error => return (Kind => Val_Missing);
               end;
            else
               return (Kind => Val_Missing);
            end if;
         end;
      elsif Name = "NUM$" and then Has_Args (1) then
         declare
            V : constant Value := All_Vals.Element (1);
            Result : Value (Val_String);
            Img : constant String := SData.Values.To_String_Formatted (V);
         begin
            Result.Str_Val := To_Unbounded_String (Img);
            return Result;
         end;

      -- Trigonometric Functions (radians)
      elsif Name = "SIN" and then Has_Args (1) then
         return Num_Result (Sin (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "COS" and then Has_Args (1) then
         return Num_Result (Cos (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "TAN" and then Has_Args (1) then
         return Num_Result (Tan (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "ATN" and then Has_Args (1) then
         return Num_Result (Arctan (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "ATAN2" and then Has_Args (2) then
         return Num_Result (Arctan (Convert_To_Float (All_Vals.Element (1)),
                                   Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "SINH" and then Has_Args (1) then
         return Num_Result (Sinh (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "COSH" and then Has_Args (1) then
         return Num_Result (Cosh (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "TANH" and then Has_Args (1) then
         return Num_Result (Tanh (Convert_To_Float (All_Vals.Element (1))));
      elsif (Name = "HCS" or else Name = "HSN" or else Name = "HTN") and then Has_Args (1) then
         declare V : constant Float := Convert_To_Float (All_Vals.Element (1));
         begin
            if Name = "HCS" then return Num_Result (1.0 / Cosh (V));
            elsif Name = "HSN" then return Num_Result (1.0 / Sinh (V));
            else return Num_Result (Cosh (V) / Sinh (V)); end if;
         end;
      elsif (Name = "ARCSIN" or else Name = "ARCCOS" or else Name = "ARCTAN") and then Has_Args (1) then
         declare V : constant Float := Convert_To_Float (All_Vals.Element (1));
         begin
            if Name = "ARCSIN" then
               if V < -1.0 or else V > 1.0 then
                  return Handle_Domain_Error ("ARCSIN argument must be in [-1, 1].");
               end if;
               return Num_Result (Arcsin (V));
            elsif Name = "ARCCOS" then
               if V < -1.0 or else V > 1.0 then
                  return Handle_Domain_Error ("ARCCOS argument must be in [-1, 1].");
               end if;
               return Num_Result (Arccos (V));
            else
               return Num_Result (Arctan (V));
            end if;
         end;
      elsif (Name = "COT" or else Name = "CSC" or else Name = "SEC") and then Has_Args (1) then
         declare V : constant Float := Convert_To_Float (All_Vals.Element (1));
         begin
            if Name = "COT" then return Num_Result (Cos (V) / Sin (V));
            elsif Name = "CSC" then return Num_Result (1.0 / Sin (V));
            else return Num_Result (1.0 / Cos (V)); end if;
         end;
      elsif (Name = "DEG" or else Name = "DEGREE") and then Has_Args (1) then
         return Num_Result (Convert_To_Float (All_Vals.Element (1)) * 180.0 / Ada.Numerics.Pi);

      -- Trigonometric Functions (degrees)
      elsif Name = "SIND" and then Has_Args (1) then
         return Num_Result (Sin (Convert_To_Float (All_Vals.Element (1)) * Ada.Numerics.Pi / 180.0));
      elsif Name = "COSD" and then Has_Args (1) then
         return Num_Result (Cos (Convert_To_Float (All_Vals.Element (1)) * Ada.Numerics.Pi / 180.0));
      elsif Name = "TAND" and then Has_Args (1) then
         return Num_Result (Tan (Convert_To_Float (All_Vals.Element (1)) * Ada.Numerics.Pi / 180.0));
      elsif Name = "ATND" and then Has_Args (1) then
         return Num_Result (Arctan (Convert_To_Float (All_Vals.Element (1))) * 180.0 / Ada.Numerics.Pi);
      elsif Name = "ATAN2D" and then Has_Args (2) then
         return Num_Result (Arctan (Convert_To_Float (All_Vals.Element (1)),
                                   Convert_To_Float (All_Vals.Element (2))) * 180.0 / Ada.Numerics.Pi);

      -- String Functions
      elsif Name = "LEN" and then Has_Args (1) then
         declare V : constant Value := All_Vals.Element (1); begin
            if V.Kind = Val_String then return (Kind => Val_Integer, Int_Val => Length (V.Str_Val));
            else return (Kind => Val_Missing); end if;
         end;
      elsif Name = "LEFT$" and then Has_Args (2) then
         declare
            V : constant Value := All_Vals.Element (1);
            N : constant Integer := Integer (Convert_To_Float (All_Vals.Element (2)));
            R : Value (Val_String);
         begin
            if V.Kind /= Val_String then return (Kind => Val_Missing); end if;
            if N <= 0 then R.Str_Val := Null_Unbounded_String;
            elsif N >= Length (V.Str_Val) then R.Str_Val := V.Str_Val;
            else R.Str_Val := To_Unbounded_String (Slice (V.Str_Val, 1, N));
            end if;
            return R;
         end;
      elsif Name = "RIGHT$" and then Has_Args (2) then
         declare
            V : constant Value := All_Vals.Element (1);
            N : constant Integer := Integer (Convert_To_Float (All_Vals.Element (2)));
            R : Value (Val_String);
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
      elsif Name = "MID$" and then (Has_Args (2) or else Has_Args (3)) then
         declare
            V     : constant Value   := All_Vals.Element (1);
            Start : constant Integer := Integer (Convert_To_Float (All_Vals.Element (2)));
            Len   : constant Integer :=
               (if Has_Args (3) then Integer (Convert_To_Float (All_Vals.Element (3)))
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
      elsif Name = "TRIM$" and then Has_Args (1) then
         declare
            V : constant Value := All_Vals.Element (1);
            R : Value (Val_String);
         begin
            if V.Kind /= Val_String then return (Kind => Val_Missing); end if;
            declare use Ada.Strings.Fixed;
            begin R.Str_Val := To_Unbounded_String (Trim (To_String (V.Str_Val), Ada.Strings.Both));
            end;
            return R;
         end;
      elsif Name = "LTRIM$" and then Has_Args (1) then
         declare
            V : constant Value := All_Vals.Element (1);
            R : Value (Val_String);
         begin
            if V.Kind /= Val_String then return (Kind => Val_Missing); end if;
            declare use Ada.Strings.Fixed;
            begin R.Str_Val := To_Unbounded_String (Trim (To_String (V.Str_Val), Ada.Strings.Left));
            end;
            return R;
         end;
      elsif Name = "RTRIM$" and then Has_Args (1) then
         declare
            V : constant Value := All_Vals.Element (1);
            R : Value (Val_String);
         begin
            if V.Kind /= Val_String then return (Kind => Val_Missing); end if;
            declare use Ada.Strings.Fixed;
            begin R.Str_Val := To_Unbounded_String (Trim (To_String (V.Str_Val), Ada.Strings.Right));
            end;
            return R;
         end;
      elsif Name = "ASCII" and then Has_Args (1) then
         declare V : constant Value := All_Vals.Element (1);
         begin
            if V.Kind /= Val_String or else Length (V.Str_Val) = 0 then
               return (Kind => Val_Missing);
            end if;
            return (Kind => Val_Integer,
                    Int_Val => Character'Pos (Element (V.Str_Val, 1)));
         end;
      elsif (Name = "UCASE$" or else Name = "UPPER$") and then Has_Args (1) then
         declare
            V : constant Value := All_Vals.Element (1);
            R : Value (Val_String);
         begin
            if V.Kind /= Val_String then return (Kind => Val_Missing); end if;
            R.Str_Val := To_Unbounded_String (To_Upper (SData.Values.To_String (V)));
            return R;
         end;
      elsif (Name = "LCASE$" or else Name = "LOWER$") and then Has_Args (1) then
         declare
            V : constant Value := All_Vals.Element (1);
            R : Value (Val_String);
         begin
            if V.Kind /= Val_String then return (Kind => Val_Missing); end if;
            R.Str_Val := To_Unbounded_String (To_Lower (SData.Values.To_String (V)));
            return R;
         end;
      elsif Name = "POS" and then Has_Args (2) then
         declare
            Needle   : constant Value := All_Vals.Element (1);
            Haystack : constant Value := All_Vals.Element (2);
         begin
            if Needle.Kind /= Val_String or else Haystack.Kind /= Val_String then
               return (Kind => Val_Missing);
            end if;
            if Length (Needle.Str_Val) = 0 then return (Kind => Val_Integer, Int_Val => 1); end if;
            return (Kind => Val_Integer, Int_Val => Index (Haystack.Str_Val, SData.Values.To_String (Needle)));
         end;
      elsif Name = "CHR$" and then Has_Args (1) then
         declare
            Code : constant Integer := Integer (Convert_To_Float (All_Vals.Element (1)));
            R    : Value (Val_String);
         begin
            R.Str_Val := To_Unbounded_String ("" & Character'Val (Code));
            return R;
         end;
      elsif Name = "STR$" and then Has_Args (1) then
         declare
            Img : constant String := SData.Values.To_String_Formatted (All_Vals.Element (1));
            R   : Value (Val_String);
         begin
            R.Str_Val := To_Unbounded_String (Img);
            return R;
         end;
      elsif Name = "VAL" and then Has_Args (1) then
         declare
            V : constant Value := All_Vals.Element (1);
         begin
            if V.Kind /= Val_String then return (Kind => Val_Missing); end if;
            begin
               return (Kind => Val_Numeric,
                       Num_Val => Float'Value (SData.Values.To_String (V)));
            exception
               when Constraint_Error => return (Kind => Val_Missing);
            end;
         end;

      -- Base Conversion Functions
      elsif Name = "HEX$" and then Has_Args (1) then
         declare
            N   : constant Integer := Integer (Convert_To_Float (All_Vals.Element (1)));
            Buf : String (1 .. 16);
            Len : Natural := 0;
            Val : Integer := abs N;
            Hex_Chars : constant String := "0123456789ABCDEF";
            R   : Value (Val_String);
         begin
            if Val = 0 then Buf (1) := '0'; Len := 1;
            else
               while Val > 0 loop
                  Len := Len + 1;
                  Buf (Len) := Hex_Chars (Val mod 16 + 1);
                  Val := Val / 16;
               end loop;
               -- Reverse
               for I in 1 .. Len / 2 loop
                  declare Tmp : constant Character := Buf (I);
                  begin Buf (I) := Buf (Len - I + 1); Buf (Len - I + 1) := Tmp; end;
               end loop;
            end if;
            R.Str_Val := To_Unbounded_String (Buf (1 .. Len));
            return R;
         end;
      elsif Name = "OCT$" and then Has_Args (1) then
         declare
            N   : constant Integer := Integer (Convert_To_Float (All_Vals.Element (1)));
            Buf : String (1 .. 16);
            Len : Natural := 0;
            Val : Integer := abs N;
            R   : Value (Val_String);
         begin
            if Val = 0 then Buf (1) := '0'; Len := 1;
            else
               while Val > 0 loop
                  Len := Len + 1;
                  Buf (Len) := Character'Val (Val mod 8 + Character'Pos ('0'));
                  Val := Val / 8;
               end loop;
               for I in 1 .. Len / 2 loop
                  declare Tmp : constant Character := Buf (I);
                  begin Buf (I) := Buf (Len - I + 1); Buf (Len - I + 1) := Tmp; end;
               end loop;
            end if;
            R.Str_Val := To_Unbounded_String (Buf (1 .. Len));
            return R;
         end;
      elsif Name = "BIN$" and then Has_Args (1) then
         declare
            N   : constant Integer := Integer (Convert_To_Float (All_Vals.Element (1)));
            Buf : String (1 .. 32);
            Len : Natural := 0;
            Val : Integer := abs N;
            R   : Value (Val_String);
         begin
            if Val = 0 then Buf (1) := '0'; Len := 1;
            else
               while Val > 0 loop
                  Len := Len + 1;
                  Buf (Len) := Character'Val (Val mod 2 + Character'Pos ('0'));
                  Val := Val / 2;
               end loop;
               for I in 1 .. Len / 2 loop
                  declare Tmp : constant Character := Buf (I);
                  begin Buf (I) := Buf (Len - I + 1); Buf (Len - I + 1) := Tmp; end;
               end loop;
            end if;
            R.Str_Val := To_Unbounded_String (Buf (1 .. Len));
            return R;
         end;

      --  ── Record Navigation Functions ──────────────────────────────────────
      --  All of the following operate in *logical* space when a SELECT filter
      --  is active.  "Logical" means the 1-based position within the filtered
      --  view; "physical" means the actual row index in the Data Table.
      --  When no filter is active, logical == physical.
      elsif Name = "BOF" then
         return (Kind => Val_Integer,
                 Int_Val => (if SData.Table.Is_Filtered
                             then (if SData.Table.Get_Logical_Record_Index <= 1 then 1 else 0)
                             else (if SData.Table.Get_Current_Record_Index <= 1 then 1 else 0)));
      elsif Name = "EOF" then
         return (Kind => Val_Integer,
                 Int_Val => (if SData.Table.Is_Filtered
                             then (if SData.Table.Get_Logical_Record_Index >= SData.Table.Logical_Row_Count then 1 else 0)
                             else (if SData.Table.Get_Current_Record_Index >= SData.Table.Row_Count then 1 else 0)));
      elsif (Name = "LAG" or else Name = "LAGC$") and then (Has_Args (1) or else Has_Args (2)) then
         declare
            Var    : constant Value   := All_Vals.Element (1);
            N_Val  : constant Value   := (if Has_Args (2) then All_Vals.Element (2) else (Kind => Val_Integer, Int_Val => 1));
            N      : Integer;
            --  In filtered mode, navigate in logical space; physical is derived via Logical_To_Physical.
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
               if not SData.Interpreter.In_Same_Group (Phys_Curr, Phys_Prev) then
                  return (Kind => Val_Missing);
               end if;
               return SData.Table.Get_Value_Upper (Phys_Prev, To_Upper (SData.Values.To_String (Var)));
            end;
         end;
      elsif (Name = "NEXT" or else Name = "NEXTC$") and then (Has_Args (1) or else Has_Args (2)) then
         declare
            Var    : constant Value   := All_Vals.Element (1);
            N_Val  : constant Value   := (if Has_Args (2) then All_Vals.Element (2) else (Kind => Val_Integer, Int_Val => 1));
            N      : Integer;
            Log_Idx : constant Natural :=
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
               if not SData.Interpreter.In_Same_Group (Phys_Curr, Phys_Next) then
                  return (Kind => Val_Missing);
               end if;
               return SData.Table.Get_Value_Upper (Phys_Next, To_Upper (SData.Values.To_String (Var)));
            end;
         end;
      elsif (Name = "OBS" or else Name = "OBSC$") and then Has_Args (2) then
         declare
            --  Argument order: OBS(varname$, row)
            Var     : constant Value := All_Vals.Element (1);
            Row_Val : constant Value := All_Vals.Element (2);
            Row     : Integer;
         begin
            if Var.Kind /= Val_String then return (Kind => Val_Missing); end if;
            Row := Integer (Convert_To_Float (Row_Val));
            if Row < 1 or else Row > SData.Table.Row_Count then
               return (Kind => Val_Missing);
            end if;
            return SData.Table.Get_Value_Upper (Row, To_Upper (SData.Values.To_String (Var)));
         end;

      -- Date and Time Functions
      elsif Name = "DATE$" then
         declare
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
               MS : constant String := (if Mo < 10 then "0" else "") & Trim(Mo'Image, Ada.Strings.Both);
               DS : constant String := (if D  < 10 then "0" else "") & Trim(D'Image, Ada.Strings.Both);
            begin
               Buf := YS (YS'Last - 3 .. YS'Last) & "-" & MS & "-" & DS;
            end;
            R.Str_Val := To_Unbounded_String (Buf);
            return R;
         end;
      elsif Name = "TIME$" then
         declare
            R   : Value (Val_String);
            Now : constant Ada.Calendar.Time := Ada.Calendar.Clock;
            Y   : Ada.Calendar.Year_Number;
            Mo  : Ada.Calendar.Month_Number;
            D   : Ada.Calendar.Day_Number;
            Sec : Ada.Calendar.Day_Duration;
            Total_Sec : Natural;
            H, Mi, S  : Natural;
            Buf : String (1 .. 8);
         begin
            Ada.Calendar.Split (Now, Y, Mo, D, Sec);
            Total_Sec := Natural (Float'Floor (Float (Sec)));
            H  := Total_Sec / 3600;
            Mi := (Total_Sec mod 3600) / 60;
            S  := Total_Sec mod 60;
            declare
               use Ada.Strings.Fixed;
               HS  : constant String := (if H  < 10 then "0" else "") & Trim(H'Image, Ada.Strings.Both);
               MiS : constant String := (if Mi < 10 then "0" else "") & Trim(Mi'Image, Ada.Strings.Both);
               SS  : constant String := (if S  < 10 then "0" else "") & Trim(S'Image, Ada.Strings.Both);
            begin
               Buf := HS & ":" & MiS & ":" & SS;
            end;
            R.Str_Val := To_Unbounded_String (Buf);
            return R;
         end;

      -- Aggregate: MEDIAN
      elsif Name = "MEDIAN" then
         declare
            package Float_Vecs is new Ada.Containers.Vectors (Positive, Float);
            package Float_Sort  is new Float_Vecs.Generic_Sorting;
            Vals : Float_Vecs.Vector;
            N    : Natural := 0;
         begin
            for I in 1 .. Integer (All_Vals.Length) loop
               declare V : constant Value := All_Vals.Element (I); begin
                  if V.Kind /= Val_Missing then
                     Vals.Append (Convert_To_Float (V));
                     N := N + 1;
                  end if;
               end;
            end loop;
            if N = 0 then return (Kind => Val_Missing); end if;
            Float_Sort.Sort (Vals);
            if N mod 2 = 1 then
               return Num_Result (Vals.Element ((N + 1) / 2));
            else
               return Num_Result ((Vals.Element (N / 2) + Vals.Element (N / 2 + 1)) / 2.0);
            end if;
         end;

      -- Seeded Random Number (uniform 0..1)
      elsif Name = "RAN" or else Name = "RANDOM" then
         return Num_Result (SData.Statistics.Uniform_Random);

      end if;

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
            --  Check if it looks like an integer.
            if Float'Floor (Expr.Value) = Expr.Value then
               return (Kind => Val_Integer, Int_Val => Integer (Expr.Value));
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
               VVal  : constant Value  := Get (VName);
            begin
               if VVal.Kind = Val_Missing then
                  --  Fall back to zero-arg functions (optional parentheses)
                  if VName = "BOF"   or else VName = "EOF"    or else
                     VName = "BOG"   or else VName = "EOG"    or else
                     VName = "RECNO" or else VName = "DATE$"  or else
                     VName = "TIME$" or else VName = "RAN"    or else
                     VName = "RANDOM" or else VName = "LRN"   or else
                     VName = "FALSE" or else VName = "TRUE"
                  then
                     return Evaluate_Function (VName, null);
                  end if;
               end if;
               return VVal;
            end;

         when Expr_Array_Access =>
            declare
               -- Handle first subscript
               Index_Val : constant Value := (if Expr.Arr_Idx /= null then Evaluate (Expr.Arr_Idx.Expr) else (Kind => Val_Missing));
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
                  --  NOT: 0 -> 1, non-zero -> 0, missing -> missing
                  if Operand_Val.Kind = Val_Missing then return (Kind => Val_Missing); end if;
                  declare V : constant Float := Convert_To_Float (Operand_Val); begin
                     return (Kind => Val_Integer, Int_Val => (if V = 0.0 then 1 else 0));
                  end;
               elsif Operand_Val.Kind = Val_Numeric then
                  case Expr.UOp is when Op_Neg => return (Kind => Val_Numeric, Num_Val => -Operand_Val.Num_Val);
                                   when others => return (Kind => Val_Missing); end case;
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
            declare L : constant Value := Evaluate (Expr.Left); R : constant Value := Evaluate (Expr.Right);
            begin
               if L.Kind = Val_Missing or R.Kind = Val_Missing then return (Kind => Val_Missing); end if;
               
               -- Mixed-mode arithmetic logic.
               if (L.Kind = Val_Numeric or L.Kind = Val_Integer) and (R.Kind = Val_Numeric or R.Kind = Val_Integer) then
                  -- If both are integers, result is integer (mostly).
                  if L.Kind = Val_Integer and R.Kind = Val_Integer then
                     declare
                        L64 : constant Long_Integer := Long_Integer (L.Int_Val);
                        R64 : constant Long_Integer := Long_Integer (R.Int_Val);
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
                              -- Return float for division to preserve precision.
                              return (Kind => Val_Numeric, Num_Val => Float (L.Int_Val) / Float (R.Int_Val));
                           when Op_Pow => return (Kind => Val_Numeric, Num_Val => Float (L.Int_Val) ** Float (R.Int_Val));
                           when Op_Eq  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val = R.Int_Val then 1 else 0));
                           when Op_Ne  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val /= R.Int_Val then 1 else 0));
                           when Op_Lt  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val < R.Int_Val then 1 else 0));
                           when Op_Le  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val <= R.Int_Val then 1 else 0));
                           when Op_Gt  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val > R.Int_Val then 1 else 0));
                           when Op_Ge  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val >= R.Int_Val then 1 else 0));
                           when Op_And => return (Kind => Val_Integer, Int_Val => (if L.Int_Val /= 0 and R.Int_Val /= 0 then 1 else 0));
                           when Op_Or  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val /= 0 or R.Int_Val /= 0 then 1 else 0));
                           when Op_Xor => return (Kind => Val_Integer, Int_Val => (if (L.Int_Val /= 0) /= (R.Int_Val /= 0) then 1 else 0));
                        end case;

                        if Expr.Op in Op_Add .. Op_Mul then
                           if Res64 < Long_Integer (Integer'First) or else Res64 > Long_Integer (Integer'Last) then
                              raise Constraint_Error with "Integer overflow in " & Expr.Op'Image;
                           end if;
                           return (Kind => Val_Integer, Int_Val => Integer (Res64));
                        end if;
                        return (Kind => Val_Missing);
                     end;
                  else
                     -- One or both are Float, promote to Float.
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
                           when Op_Eq  => return (Kind => Val_Integer, Int_Val => (if FL = FR then 1 else 0));
                           when Op_Ne  => return (Kind => Val_Integer, Int_Val => (if FL /= FR then 1 else 0));
                           when Op_Lt  => return (Kind => Val_Integer, Int_Val => (if FL < FR then 1 else 0));
                           when Op_Le  => return (Kind => Val_Integer, Int_Val => (if FL <= FR then 1 else 0));
                           when Op_Gt  => return (Kind => Val_Integer, Int_Val => (if FL > FR then 1 else 0));
                           when Op_Ge  => return (Kind => Val_Integer, Int_Val => (if FL >= FR then 1 else 0));
                           when Op_And => return (Kind => Val_Integer, Int_Val => (if FL /= 0.0 and FR /= 0.0 then 1 else 0));
                           when Op_Or  => return (Kind => Val_Integer, Int_Val => (if FL /= 0.0 or FR /= 0.0 then 1 else 0));
                           when Op_Xor => return (Kind => Val_Integer, Int_Val => (if (FL /= 0.0) /= (FR /= 0.0) then 1 else 0));
                        end case;
                     end;
                  end if;
               elsif L.Kind = Val_String and R.Kind = Val_String then
                  case Expr.Op is
                     when Op_Add =>
                        declare 
                           V : Value (Val_String);
                           Limit : Natural := 1024; -- Default limit
                        begin
                           if SData.Config.Max_String_Len > 0 then
                              Limit := SData.Config.Max_String_Len;
                           end if;

                           V.Str_Val := L.Str_Val & R.Str_Val;
                           if Length (V.Str_Val) > Limit then 
                              Put_Line_Error ("Warning: String truncated to " & Integer'Image(Limit) & " characters.");
                              V.Str_Val := To_Unbounded_String (Slice (V.Str_Val, 1, Limit));
                           end if;
                           return V;
                        end;
                     when Op_Eq => return (Kind => Val_Integer, Int_Val => (if L.Str_Val = R.Str_Val then 1 else 0));
                     when others => return (Kind => Val_Missing);
                  end case;
               else return (Kind => Val_Missing); end if;
            end;

         when Expr_Function_Call =>
            declare
               FName : constant String := To_Upper (Expr.Func_Name (1 .. Expr.Func_Len));
            begin
               if Has_Array (FName) then
                  declare
                     -- Simple array lookup from function-like syntax F(idx)
                     Index_Val : constant Value := (if Expr.Arguments /= null then Evaluate (Expr.Arguments.Expr) else (Kind => Val_Missing));
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

end SData.Evaluator;
