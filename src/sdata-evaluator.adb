with SData.Variables; use SData.Variables;
with SData.Config;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with SData.Statistics;
with SData.Table;
with Ada.Containers.Vectors;
with Ada.Text_IO; use Ada.Text_IO;
with SData.System;

package body SData.Evaluator is

   BOG_Flag : Boolean := False;
   EOG_Flag : Boolean := False;

   function Is_BOG return Boolean is (BOG_Flag);
   function Is_EOG return Boolean is (EOG_Flag);

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

   begin
      -- Flatten arguments, expanding arrays if necessary
      while Current /= null loop
         if Current.Expr.Kind = Expr_Variable then
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
                        when others => All_Vals.Append ((Kind => Val_Missing));
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
         begin return (if V > 0.0 then Num_Result (Log (V)) else (Kind => Val_Missing)); end;
      elsif Name = "LOG10" and then Has_Args (1) then
         declare V : constant Float := Convert_To_Float (All_Vals.Element (1));
         begin return (if V > 0.0 then Num_Result (Log (V, 10.0)) else (Kind => Val_Missing)); end;
      elsif Name = "EXP" and then Has_Args (1) then
         return Num_Result (Exp (Convert_To_Float (All_Vals.Element (1))));
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
         return Num_Result (Float'Truncation (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "MOD" and then Has_Args (2) then
         declare
            V1 : constant Float := Convert_To_Float (All_Vals.Element (1));
            V2 : constant Float := Convert_To_Float (All_Vals.Element (2));
         begin
            if V2 /= 0.0 then return Num_Result (V1 - Float'Floor(V1/V2) * V2);
            else return (Kind => Val_Missing); end if;
         end;
      elsif Name = "RECNO" then
         return (Kind => Val_Integer, Int_Val => Integer (SData.Table.Get_Current_Record_Index));
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
            else return (Kind => Val_Missing); end if;
         end;

      -- Aggregate Functions (Row-wise)
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
      elsif Name = "LDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Laplace_PDF (Convert_To_Float (All_Vals.Element (1)), 
                                                          Convert_To_Float (All_Vals.Element (2)), 
                                                          Convert_To_Float (All_Vals.Element (3))));

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
      elsif Name = "LCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Laplace_CDF (Convert_To_Float (All_Vals.Element (1)), 
                                                          Convert_To_Float (All_Vals.Element (2)), 
                                                          Convert_To_Float (All_Vals.Element (3))));

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
      elsif Name = "LIF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Laplace_IDF (Convert_To_Float (All_Vals.Element (1)), 
                                                          Convert_To_Float (All_Vals.Element (2)), 
                                                          Convert_To_Float (All_Vals.Element (3))));
      elsif Name = "PIF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Poisson_IDF (Convert_To_Float (All_Vals.Element (1)), 
                                                          Convert_To_Float (All_Vals.Element (2))));

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
      elsif Name = "LRN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Laplace_RN (Convert_To_Float (All_Vals.Element (1)), 
                                                         Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "XRN" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Chi_Square_RN (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "TRN" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Student_T_RN (Convert_To_Float (All_Vals.Element (1))));
      elsif Name = "FRN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.F_RN (Convert_To_Float (All_Vals.Element (1)),
                                                   Convert_To_Float (All_Vals.Element (2))));
      elsif Name = "SHELL" and then Has_Args (1) then
         if SData.Config.Disable_Shell then
            Put_Line ("Error: SHELL function is disabled.");
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
                  return (Kind => Val_Numeric, Num_Val => Float'Value (V.Str_Val (1 .. V.Str_Len)));
               exception
                  when others => return (Kind => Val_Missing);
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
            Result.Str_Len := Img'Length;
            if Result.Str_Len > 1024 then Result.Str_Len := 1024; end if;
            Result.Str_Val (1 .. Result.Str_Len) := Img (Img'First .. Img'First + Result.Str_Len - 1);
            return Result;
         end;

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
               V.Str_Len := Expr.Str_Length;
               V.Str_Val (1 .. V.Str_Len) := Expr.Str_Value (1 .. Expr.Str_Length);
               return V;
            end;

         when Expr_Variable => return Get (Expr.Var_Name (1 .. Expr.Var_Len));

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
               if Operand_Val.Kind = Val_Numeric then
                  case Expr.UOp is when Op_Neg => return (Kind => Val_Numeric, Num_Val => -Operand_Val.Num_Val); end case;
               elsif Operand_Val.Kind = Val_Integer then
                  case Expr.UOp is 
                     when Op_Neg => 
                        if Operand_Val.Int_Val = Integer'First then
                           raise Constraint_Error with "Integer overflow in unary negation";
                        end if;
                        return (Kind => Val_Integer, Int_Val => -Operand_Val.Int_Val); 
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
                              if R.Int_Val = 0 then return (Kind => Val_Missing); end if;
                              -- Return float for division to preserve precision.
                              return (Kind => Val_Numeric, Num_Val => Float (L.Int_Val) / Float (R.Int_Val));
                           when Op_Pow => return (Kind => Val_Numeric, Num_Val => Float (L.Int_Val) ** Float (R.Int_Val));
                           when Op_Eq  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val = R.Int_Val then 1 else 0));
                           when Op_Ne  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val /= R.Int_Val then 1 else 0));
                           when Op_Lt  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val < R.Int_Val then 1 else 0));
                           when Op_Le  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val <= R.Int_Val then 1 else 0));
                           when Op_Gt  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val > R.Int_Val then 1 else 0));
                           when Op_Ge  => return (Kind => Val_Integer, Int_Val => (if L.Int_Val >= R.Int_Val then 1 else 0));
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
                           when Op_Div => if FR = 0.0 then return (Kind => Val_Missing); end if; return (Kind => Val_Numeric, Num_Val => FL / FR);
                           when Op_Pow => return (Kind => Val_Numeric, Num_Val => FL ** FR);
                           when Op_Eq  => return (Kind => Val_Integer, Int_Val => (if FL = FR then 1 else 0));
                           when Op_Ne  => return (Kind => Val_Integer, Int_Val => (if FL /= FR then 1 else 0));
                           when Op_Lt  => return (Kind => Val_Integer, Int_Val => (if FL < FR then 1 else 0));
                           when Op_Le  => return (Kind => Val_Integer, Int_Val => (if FL <= FR then 1 else 0));
                           when Op_Gt  => return (Kind => Val_Integer, Int_Val => (if FL > FR then 1 else 0));
                           when Op_Ge  => return (Kind => Val_Integer, Int_Val => (if FL >= FR then 1 else 0));
                        end case;
                     end;
                  end if;
               elsif L.Kind = Val_String and R.Kind = Val_String then
                  case Expr.Op is
                     when Op_Add =>
                        declare 
                           V : Value (Val_String);
                           Limit : Natural := 1024;
                        begin
                           if SData.Config.Max_String_Len > 0 and then SData.Config.Max_String_Len < 1024 then
                              Limit := SData.Config.Max_String_Len;
                           end if;

                           V.Str_Len := L.Str_Len + R.Str_Len;
                           if V.Str_Len > Limit then 
                              Put_Line ("Warning: String truncated to " & Integer'Image(Limit) & " characters.");
                              V.Str_Len := Limit;
                           end if;
                           
                           V.Str_Val (1 .. L.Str_Len) := L.Str_Val (1 .. L.Str_Len);
                           if V.Str_Len > L.Str_Len then
                              V.Str_Val (L.Str_Len + 1 .. V.Str_Len) := R.Str_Val (1 .. V.Str_Len - L.Str_Len);
                           end if;
                           return V;
                        end;
                     when Op_Eq => return (Kind => Val_Integer, Int_Val => (if L.Str_Val (1 .. L.Str_Len) = R.Str_Val (1 .. R.Str_Len) then 1 else 0));
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
