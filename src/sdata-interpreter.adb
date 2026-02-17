with Ada.Text_IO; use Ada.Text_IO;
with SData.Evaluator; use SData.Evaluator;
with SData.Values; use SData.Values;
with SData.Variables; use SData.Variables;

package body SData.Interpreter is

   procedure Execute (Prog : Statement_Access) is
      Current : Statement_Access := Prog;
   begin
      while Current /= null loop
         case Current.Kind is
            when Stmt_LET =>
               Set (Current.Var_Name (1 .. Current.Var_Len), Evaluate (Current.Expr));
            
            when Stmt_PRINT =>
               declare
                  Val : constant Value := Evaluate (Current.Print_Expr);
               begin
                  Put_Line (To_String (Val));
               end;

            when Stmt_END | Stmt_QUIT =>
               return;

            when others =>
               null; -- Other statements not implemented for execution yet
         end case;
         Current := Current.Next;
      end loop;
   end Execute;

end SData.Interpreter;
