with SData.Variables; use SData.Variables;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
with Ada.Characters.Handling; use Ada.Characters.Handling;

package body SData.Evaluator is

   --------------
   -- Evaluate --
   --------------
   --  The main entry point for expression evaluation.
   function Evaluate (Expr : Expression_Access) return Value is
   begin
      --  Safety check for null pointers in the AST.
      if Expr = null then
         return (Kind => Val_Missing);
      end if;

      case Expr.Kind is
         --  Handle simple numeric literals.
         when Expr_Numeric_Literal =>
            return (Kind => Val_Numeric, Num_Val => Expr.Value);

         --  Handle string literals (copying them into the Value buffer).
         when Expr_String_Literal =>
            declare
               V : Value (Val_String);
            begin
               V.Str_Len := Expr.Str_Length;
               V.Str_Val (1 .. V.Str_Len) := Expr.Str_Value (1 .. Expr.Str_Length);
               return V;
            end;

         --  Handle variable lookups (managed by SData.Variables).
         when Expr_Variable =>
            return Get (Expr.Var_Name (1 .. Expr.Var_Len));

         --  Handle unary operations (like -X).
         when Expr_Unary_Op =>
            declare
               Operand_Val : constant Value := Evaluate (Expr.Operand);
            begin
               if Operand_Val.Kind = Val_Numeric then
                  case Expr.UOp is
                     when Op_Neg => return (Kind => Val_Numeric, Num_Val => -Operand_Val.Num_Val);
                  end case;
               else
                  --  Unary minus on strings or missing values results in missing.
                  return (Kind => Val_Missing);
               end if;
            end;

         --  Handle binary operations (arithmetic, comparisons, string joining).
         when Expr_Binary_Op =>
            declare
               L : constant Value := Evaluate (Expr.Left);
               R : constant Value := Evaluate (Expr.Right);
            begin
               --  MISSING VALUE PROPAGATION: If either side is missing, result is missing.
               if L.Kind = Val_Missing or R.Kind = Val_Missing then
                  return (Kind => Val_Missing);
               end if;

               --  Numeric operations.
               if L.Kind = Val_Numeric and R.Kind = Val_Numeric then
                  case Expr.Op is
                     when Op_Add => return (Kind => Val_Numeric, Num_Val => L.Num_Val + R.Num_Val);
                     when Op_Sub => return (Kind => Val_Numeric, Num_Val => L.Num_Val - R.Num_Val);
                     when Op_Mul => return (Kind => Val_Numeric, Num_Val => L.Num_Val * R.Num_Val);
                     when Op_Div => 
                        if R.Num_Val = 0.0 then return (Kind => Val_Missing); end if;
                        return (Kind => Val_Numeric, Num_Val => L.Num_Val / R.Num_Val);
                     when Op_Pow => return (Kind => Val_Numeric, Num_Val => L.Num_Val ** R.Num_Val);
                     when Op_Eq  => return (Kind => Val_Numeric, Num_Val => (if L.Num_Val = R.Num_Val then 1.0 else 0.0));
                     when Op_Ne  => return (Kind => Val_Numeric, Num_Val => (if L.Num_Val /= R.Num_Val then 1.0 else 0.0));
                     when Op_Lt  => return (Kind => Val_Numeric, Num_Val => (if L.Num_Val < R.Num_Val then 1.0 else 0.0));
                     when Op_Le  => return (Kind => Val_Numeric, Num_Val => (if L.Num_Val <= R.Num_Val then 1.0 else 0.0));
                     when Op_Gt  => return (Kind => Val_Numeric, Num_Val => (if L.Num_Val > R.Num_Val then 1.0 else 0.0));
                     when Op_Ge  => return (Kind => Val_Numeric, Num_Val => (if L.Num_Val >= R.Num_Val then 1.0 else 0.0));
                  end case;

               --  String operations.
               elsif L.Kind = Val_String and R.Kind = Val_String then
                  case Expr.Op is
                     when Op_Add => -- String concatenation
                        declare
                           V : Value (Val_String);
                        begin
                           V.Str_Len := L.Str_Len + R.Str_Len;
                           if V.Str_Len > 1024 then V.Str_Len := 1024; end if; -- Enforce buffer limit
                           V.Str_Val (1 .. L.Str_Len) := L.Str_Val (1 .. L.Str_Len);
                           V.Str_Val (L.Str_Len + 1 .. V.Str_Len) := R.Str_Val (1 .. V.Str_Len - L.Str_Len);
                           return V;
                        end;
                     when Op_Eq => return (Kind => Val_Numeric, Num_Val => (if L.Str_Val (1 .. L.Str_Len) = R.Str_Val (1 .. R.Str_Len) then 1.0 else 0.0));
                     when others => return (Kind => Val_Missing); -- Incompatible string operations
                  end case;
               else
                  --  Type mismatch between L and R.
                  return (Kind => Val_Missing);
               end if;
            end;

         --  Handle built-in function calls.
         when Expr_Function_Call =>
            declare
               Name : constant String := To_Upper (Expr.Func_Name (1 .. Expr.Func_Len));
            begin
               if Expr.Arguments = null then
                  return (Kind => Val_Missing);
               end if;

               declare
                  --  Evaluate the first argument.
                  Arg1 : constant Value := Evaluate (Expr.Arguments.Expr);
               begin
                  if Name = "ABS" then
                     if Arg1.Kind = Val_Numeric then
                        return (Kind => Val_Numeric, Num_Val => abs (Arg1.Num_Val));
                     end if;
                  elsif Name = "SQRT" then
                     if Arg1.Kind = Val_Numeric and then Arg1.Num_Val >= 0.0 then
                        return (Kind => Val_Numeric, Num_Val => Sqrt (Arg1.Num_Val));
                     end if;
                  elsif Name = "MAX" or else Name = "MIN" then
                     --  Handle two-argument functions.
                     if Expr.Arguments.Next /= null then
                        declare
                           Arg2 : constant Value := Evaluate (Expr.Arguments.Next.Expr);
                        begin
                           if Arg1.Kind = Val_Numeric and Arg2.Kind = Val_Numeric then
                              if Name = "MAX" then
                                 if Arg1.Num_Val > Arg2.Num_Val then return Arg1; else return Arg2; end if;
                              else
                                 if Arg1.Num_Val < Arg2.Num_Val then return Arg1; else return Arg2; end if;
                              end if;
                           end if;
                        end;
                     end if;
                  end if;
               end;
               --  Function unknown or invalid arguments.
               return (Kind => Val_Missing);
            end;
      end case;
   end Evaluate;

end SData.Evaluator;
