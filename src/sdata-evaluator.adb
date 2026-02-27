with SData.Variables; use SData.Variables;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with SData.Statistics;
with Ada.Text_IO; use Ada.Text_IO;
with Ada.Exceptions;

package body SData.Evaluator is

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
            if Arg_Vals (I).Kind /= Val_Numeric then return False; end if;
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
         return Num_Result (abs Arg_Vals (1).Num_Val);
      elsif Name = "SQRT" and then Has_Args (1) then
         if Arg_Vals (1).Num_Val >= 0.0 then return Num_Result (Sqrt (Arg_Vals (1).Num_Val)); end if;
      elsif Name = "MAX" and then Has_Args (2) then
         return (if Arg_Vals (1).Num_Val > Arg_Vals (2).Num_Val then Arg_Vals (1) else Arg_Vals (2));
      elsif Name = "MIN" and then Has_Args (2) then
         return (if Arg_Vals (1).Num_Val < Arg_Vals (2).Num_Val then Arg_Vals (1) else Arg_Vals (2));

      --  Standard Normal (Z)
      elsif Name = "ZDF" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Z_PDF (Arg_Vals (1).Num_Val));
      elsif Name = "ZCF" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Z_CDF (Arg_Vals (1).Num_Val));
      elsif Name = "ZIF" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Z_IDF (Arg_Vals (1).Num_Val));
      elsif Name = "ZRN" then
         return Num_Result (SData.Statistics.Normal_RN (0.0, 1.0));

      --  Normal
      elsif Name = "NDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Normal_PDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val, Arg_Vals (3).Num_Val));
      elsif Name = "NCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Normal_CDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val, Arg_Vals (3).Num_Val));
      elsif Name = "NIF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Normal_IDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val, Arg_Vals (3).Num_Val));
      elsif Name = "NRN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Normal_RN (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val));

      --  Uniform
      elsif Name = "UDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Uniform_PDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val, Arg_Vals (3).Num_Val));
      elsif Name = "UCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Uniform_CDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val, Arg_Vals (3).Num_Val));
      elsif Name = "UIF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Uniform_IDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val, Arg_Vals (3).Num_Val));
      elsif Name = "URN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Uniform_RN (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val));

      --  Exponential
      elsif Name = "EDF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Exponential_PDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val));
      elsif Name = "ECF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Exponential_CDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val));
      elsif Name = "EIF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Exponential_IDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val));
      elsif Name = "ERN" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Exponential_RN (Arg_Vals (1).Num_Val));

      --  Beta
      elsif Name = "BDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Beta_PDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val, Arg_Vals (3).Num_Val));
      elsif Name = "BCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Beta_CDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val, Arg_Vals (3).Num_Val));
      elsif Name = "BIF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Beta_IDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val, Arg_Vals (3).Num_Val));

      --  Poisson
      elsif Name = "PDF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Poisson_PMF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val));
      elsif Name = "PCF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Poisson_CDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val));
      elsif Name = "PRN" and then Has_Args (1) then
         return Num_Result (SData.Statistics.Poisson_RN (Arg_Vals (1).Num_Val));

      --  Gamma
      elsif Name = "GDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Gamma_PDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val, Arg_Vals (3).Num_Val));
      elsif Name = "GCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.Gamma_CDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val, Arg_Vals (3).Num_Val));
      elsif Name = "GRN" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Gamma_RN (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val));

      --  Chi-square
      elsif Name = "XDF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Chi_Square_PDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val));
      elsif Name = "XCF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Chi_Square_CDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val));

      --  Student's T
      elsif Name = "TDF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Student_T_PDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val));
      elsif Name = "TCF" and then Has_Args (2) then
         return Num_Result (SData.Statistics.Student_T_CDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val));

      --  Snedecor's F
      elsif Name = "FDF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.F_PDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val, Arg_Vals (3).Num_Val));
      elsif Name = "FCF" and then Has_Args (3) then
         return Num_Result (SData.Statistics.F_CDF (Arg_Vals (1).Num_Val, Arg_Vals (2).Num_Val, Arg_Vals (3).Num_Val));

      end if;

      return (Kind => Val_Missing);
   exception
      when E : others => 
         return (Kind => Val_Missing);
   end Evaluate_Function;

   --------------
   -- Evaluate --
   --------------
   function Evaluate (Expr : Expression_Access) return Value is
   begin
      if Expr = null then return (Kind => Val_Missing); end if;

      case Expr.Kind is
         when Expr_Numeric_Literal =>
            return (Kind => Val_Numeric, Num_Val => Expr.Value);

         when Expr_String_Literal =>
            declare V : Value (Val_String);
            begin
               V.Str_Len := Expr.Str_Length;
               V.Str_Val (1 .. V.Str_Len) := Expr.Str_Value (1 .. Expr.Str_Length);
               return V;
            end;

         when Expr_Variable => return Get (Expr.Var_Name (1 .. Expr.Var_Len));

         when Expr_Unary_Op =>
            declare Operand_Val : constant Value := Evaluate (Expr.Operand);
            begin
               if Operand_Val.Kind = Val_Numeric then
                  case Expr.UOp is when Op_Neg => return (Kind => Val_Numeric, Num_Val => -Operand_Val.Num_Val); end case;
               else return (Kind => Val_Missing); end if;
            end;

         when Expr_Binary_Op =>
            declare L : constant Value := Evaluate (Expr.Left); R : constant Value := Evaluate (Expr.Right);
            begin
               if L.Kind = Val_Missing or R.Kind = Val_Missing then return (Kind => Val_Missing); end if;
               if L.Kind = Val_Numeric and R.Kind = Val_Numeric then
                  case Expr.Op is
                     when Op_Add => return (Kind => Val_Numeric, Num_Val => L.Num_Val + R.Num_Val);
                     when Op_Sub => return (Kind => Val_Numeric, Num_Val => L.Num_Val - R.Num_Val);
                     when Op_Mul => return (Kind => Val_Numeric, Num_Val => L.Num_Val * R.Num_Val);
                     when Op_Div => if R.Num_Val = 0.0 then return (Kind => Val_Missing); end if; return (Kind => Val_Numeric, Num_Val => L.Num_Val / R.Num_Val);
                     when Op_Pow => return (Kind => Val_Numeric, Num_Val => L.Num_Val ** R.Num_Val);
                     when Op_Eq  => return (Kind => Val_Numeric, Num_Val => (if L.Num_Val = R.Num_Val then 1.0 else 0.0));
                     when Op_Ne  => return (Kind => Val_Numeric, Num_Val => (if L.Num_Val /= R.Num_Val then 1.0 else 0.0));
                     when Op_Lt  => return (Kind => Val_Numeric, Num_Val => (if L.Num_Val < R.Num_Val then 1.0 else 0.0));
                     when Op_Le  => return (Kind => Val_Numeric, Num_Val => (if L.Num_Val <= R.Num_Val then 1.0 else 0.0));
                     when Op_Gt  => return (Kind => Val_Numeric, Num_Val => (if L.Num_Val > R.Num_Val then 1.0 else 0.0));
                     when Op_Ge  => return (Kind => Val_Numeric, Num_Val => (if L.Num_Val >= R.Num_Val then 1.0 else 0.0));
                  end case;
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
                     when Op_Eq => return (Kind => Val_Numeric, Num_Val => (if L.Str_Val (1 .. L.Str_Len) = R.Str_Val (1 .. R.Str_Len) then 1.0 else 0.0));
                     when others => return (Kind => Val_Missing);
                  end case;
               else return (Kind => Val_Missing); end if;
            end;

         when Expr_Function_Call =>
            return Evaluate_Function (To_Upper (Expr.Func_Name (1 .. Expr.Func_Len)), Expr.Arguments);
      end case;
   end Evaluate;

end SData.Evaluator;
