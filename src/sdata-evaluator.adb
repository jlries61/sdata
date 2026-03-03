with SData.Variables; use SData.Variables;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with SData.Statistics;
with SData.Table;

package body SData.Evaluator is

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
      
      Arg_Vals : array (1 .. 4) of Value := (others => (Kind => Val_Missing));
      Count    : Natural := 0;
      Current  : Expression_List := Args;

      function Has_Args (N : Positive) return Boolean is
      begin
         if Count < N then return False; end if;
         for I in 1 .. N loop
            if Arg_Vals (I).Kind = Val_Missing then return False; end if;
         end loop;
         return True;
      end Has_Args;

      function Num_Result (V : Float) return Value is
      begin
         return (Kind => Val_Numeric, Num_Val => V);
      end Num_Result;

   begin
      while Current /= null and Count < 4 loop
         Count := Count + 1;
         Arg_Vals (Count) := Evaluate (Current.Expr);
         Current := Current.Next;
      end loop;

      --  Math Functions
      if Name = "ABS" and then Has_Args (1) then
         if Arg_Vals (1).Kind = Val_Integer then
            return (Kind => Val_Integer, Int_Val => abs Arg_Vals (1).Int_Val);
         else
            return Num_Result (abs Convert_To_Float (Arg_Vals (1)));
         end if;
      elsif Name = "LOG" and then Has_Args (1) then
         declare V : constant Float := Convert_To_Float (Arg_Vals (1));
         begin return (if V > 0.0 then Num_Result (Log (V)) else (Kind => Val_Missing)); end;
      elsif Name = "LOG10" and then Has_Args (1) then
         declare V : constant Float := Convert_To_Float (Arg_Vals (1));
         begin return (if V > 0.0 then Num_Result (Log (V, 10.0)) else (Kind => Val_Missing)); end;
      elsif Name = "EXP" and then Has_Args (1) then
         return Num_Result (Exp (Convert_To_Float (Arg_Vals (1))));
      elsif Name = "ROUND" and then Has_Args (1) then
         declare
            V : constant Float := Convert_To_Float (Arg_Vals (1));
            Decimals : Float := 0.0;
            Factor : Float;
         begin
            if Count >= 2 and then Arg_Vals (2).Kind /= Val_Missing then
               Decimals := Convert_To_Float (Arg_Vals (2));
            end if;
            Factor := 10.0 ** Decimals;
            return Num_Result (Float'Rounding (V * Factor) / Factor);
         end;
      elsif Name = "CEIL" and then Has_Args (1) then
         return Num_Result (Float'Ceiling (Convert_To_Float (Arg_Vals (1))));
      elsif Name = "FLOOR" and then Has_Args (1) then
         return Num_Result (Float'Floor (Convert_To_Float (Arg_Vals (1))));
      elsif Name = "INT" and then Has_Args (1) then
         return Num_Result (Float'Truncation (Convert_To_Float (Arg_Vals (1))));
      elsif Name = "MOD" and then Has_Args (2) then
         declare
            V1 : constant Float := Convert_To_Float (Arg_Vals (1));
            V2 : constant Float := Convert_To_Float (Arg_Vals (2));
         begin
            if V2 /= 0.0 then return Num_Result (V1 - Float'Floor(V1/V2) * V2);
            else return (Kind => Val_Missing); end if;
         end;
      elsif Name = "RECNO" then
         return (Kind => Val_Integer, Int_Val => Integer (SData.Table.Get_Current_Record_Index));
      elsif Name = "MISSING" and then Count >= 1 then
         return (Kind => Val_Integer, Int_Val => (if Arg_Vals (1).Kind = Val_Missing then 1 else 0));
      elsif Name = "SQRT" and then Has_Args (1) then
         declare
            V : constant Float := Convert_To_Float (Arg_Vals (1));
         begin
            if V >= 0.0 then return Num_Result (Sqrt (V)); end if;
         end;
      elsif Name = "MAX" and then Has_Args (2) then
         if Arg_Vals (1).Kind = Val_Integer and Arg_Vals (2).Kind = Val_Integer then
            return (if Arg_Vals (1).Int_Val > Arg_Vals (2).Int_Val then Arg_Vals (1) else Arg_Vals (2));
         else
            return (if Convert_To_Float (Arg_Vals (1)) > Convert_To_Float (Arg_Vals (2)) then Arg_Vals (1) else Arg_Vals (2));
         end if;
      elsif Name = "MIN" and then Has_Args (2) then
         if Arg_Vals (1).Kind = Val_Integer and Arg_Vals (2).Kind = Val_Integer then
            return (if Arg_Vals (1).Int_Val < Arg_Vals (2).Int_Val then Arg_Vals (1) else Arg_Vals (2));
         else
            return (if Convert_To_Float (Arg_Vals (1)) < Convert_To_Float (Arg_Vals (2)) then Arg_Vals (1) else Arg_Vals (2));
         end if;

      --  Standard Normal (Z)
      elsif Name = "ZDF" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Z_PDF (Convert_To_Float (Arg_Vals (1))));
      elsif Name = "ZCF" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Z_CDF (Convert_To_Float (Arg_Vals (1))));
      elsif Name = "ZIF" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Z_IDF (Convert_To_Float (Arg_Vals (1))));
      elsif Name = "ZRN" then
         return Num_Result (SData.Statistics.Normal_RN (0.0, 1.0));

      --  Normal
      elsif Name = "NDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Normal_PDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));
      elsif Name = "NCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Normal_CDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));
      elsif Name = "NIF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Normal_IDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));
      elsif Name = "NRN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Normal_RN (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2))));

      --  Uniform
      elsif Name = "UDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Uniform_PDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));
      elsif Name = "UCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Uniform_CDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));
      elsif Name = "UIF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Uniform_IDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));
      elsif Name = "URN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Uniform_RN (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2))));

      --  Exponential
      elsif Name = "EDF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Exponential_PDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2))));
      elsif Name = "ECF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Exponential_CDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2))));
      elsif Name = "EIF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Exponential_IDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2))));
      elsif Name = "ERN" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Exponential_RN (Convert_To_Float (Arg_Vals (1))));

      --  Beta
      elsif Name = "BDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Beta_PDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));
      elsif Name = "BCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Beta_CDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));
      elsif Name = "BIF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Beta_IDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));

      --  Poisson
      elsif Name = "PDF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Poisson_PMF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2))));
      elsif Name = "PCF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Poisson_CDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2))));
      elsif Name = "PRN" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Poisson_RN (Convert_To_Float (Arg_Vals (1))));

      --  Gamma
      elsif Name = "GDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Gamma_PDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));
      elsif Name = "GCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Gamma_CDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));
      elsif Name = "GRN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Gamma_RN (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2))));

      --  Chi-square
      elsif Name = "XDF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Chi_Square_PDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2))));
      elsif Name = "XCF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Chi_Square_CDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2))));

      --  Student's T
      elsif Name = "TDF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Student_T_PDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2))));
      elsif Name = "TCF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Student_T_CDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2))));

      --  Snedecor's F
      elsif Name = "FDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.F_PDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));
      elsif Name = "FCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.F_CDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));

      --  Binomial
      elsif Name = "MDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Binomial_PMF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));
      elsif Name = "MCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Binomial_CDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));
      elsif Name = "MRN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Binomial_RN (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2))));

      --  Weibull
      elsif Name = "WDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Weibull_PDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));
      elsif Name = "WCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Weibull_CDF (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2)), Convert_To_Float (Arg_Vals (3))));
      elsif Name = "WRN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Weibull_RN (Convert_To_Float (Arg_Vals (1)), Convert_To_Float (Arg_Vals (2))));

      end if;

      return (Kind => Val_Missing);
   exception
      when others => return (Kind => Val_Missing);
   end Evaluate_Function;

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
               Index_Val : constant Value := Evaluate (Expr.Arr_Idx);
               Idx : Natural;
            begin
               if Index_Val.Kind = Val_Integer then
                  Idx := Index_Val.Int_Val;
               elsif Index_Val.Kind = Val_Numeric then
                  Idx := Natural (Float'Floor (Index_Val.Num_Val));
               else
                  return (Kind => Val_Missing);
               end if;
               
               if Idx > 0 then
                  return Get_Array_Element (Expr.Arr_Name (1 .. Expr.Arr_Len), Idx);
               else
                  return (Kind => Val_Missing);
               end if;
            end;

         when Expr_Unary_Op =>
            declare Operand_Val : constant Value := Evaluate (Expr.Operand);
            begin
               if Operand_Val.Kind = Val_Numeric then
                  case Expr.UOp is when Op_Neg => return (Kind => Val_Numeric, Num_Val => -Operand_Val.Num_Val); end case;
               elsif Operand_Val.Kind = Val_Integer then
                  case Expr.UOp is when Op_Neg => return (Kind => Val_Integer, Int_Val => -Operand_Val.Int_Val); end case;
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
                     case Expr.Op is
                        when Op_Add => return (Kind => Val_Integer, Int_Val => L.Int_Val + R.Int_Val);
                        when Op_Sub => return (Kind => Val_Integer, Int_Val => L.Int_Val - R.Int_Val);
                        when Op_Mul => return (Kind => Val_Integer, Int_Val => L.Int_Val * R.Int_Val);
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
                        declare V : Value (Val_String);
                        begin
                           V.Str_Len := L.Str_Len + R.Str_Len;
                           if V.Str_Len > 1024 then V.Str_Len := 1024; end if;
                           V.Str_Val (1 .. L.Str_Len) := L.Str_Val (1 .. L.Str_Len);
                           V.Str_Val (L.Str_Len + 1 .. V.Str_Len) := R.Str_Val (1 .. V.Str_Len - L.Str_Len);
                           return V;
                        end;
                     when Op_Eq => return (Kind => Val_Integer, Int_Val => (if L.Str_Val (1 .. L.Str_Len) = R.Str_Val (1 .. R.Str_Len) then 1 else 0));
                     when others => return (Kind => Val_Missing);
                  end case;
               else return (Kind => Val_Missing); end if;
            end;

         when Expr_Function_Call =>
            return Evaluate_Function (To_Upper (Expr.Func_Name (1 .. Expr.Func_Len)), Expr.Arguments);
      end case;
   end Evaluate;

end SData.Evaluator;
