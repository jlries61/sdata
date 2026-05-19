--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Resolve_Expr_Indices (Start, Boundary : Statement_Access) is

   procedure Resolve_Expr (Expr : Expression_Access);

   procedure Resolve_Expr_List (List : Expression_List) is
      Node : Expression_List := List;
   begin
      while Node /= null loop
         Resolve_Expr (Node.Expr);
         if Node.Is_Range then
            Resolve_Expr (Node.Expr_End);
         end if;
         Node := Node.Next;
      end loop;
   end Resolve_Expr_List;

   procedure Resolve_Expr (Expr : Expression_Access) is
   begin
      if Expr = null then return; end if;
      case Expr.Kind is
         when Expr_Variable =>
            declare
               Upper : constant String :=
                  To_Upper (Expr.Var_Name (1 .. Expr.Var_Len));
            begin
               Expr.Var_Index := SData_Core.Variables.PDV_Resolve (Upper);
            end;
         when Expr_Binary_Op =>
            Resolve_Expr (Expr.Left);
            Resolve_Expr (Expr.Right);
         when Expr_Unary_Op =>
            Resolve_Expr (Expr.Operand);
         when Expr_Function_Call =>
            Resolve_Expr_List (Expr.Arguments);
         when Expr_Array_Access =>
            Resolve_Expr_List (Expr.Arr_Idx);
         when others => null;
      end case;
   end Resolve_Expr;

   procedure Resolve_Stmt_List (Stmt  : Statement_Access;
                                Bound : Statement_Access);

   procedure Resolve_Stmt (S : Statement_Access) is
   begin
      if S = null then return; end if;
      Resolve_Expr (S.Expr);
      Resolve_Expr (S.Arr_Idx);
      Resolve_Expr_List (S.Arr_Idx_List);
      case S.Kind is
         when Stmt_PRINT =>
            Resolve_Expr_List (S.Print_Args);
         when Stmt_IF =>
            Resolve_Expr (S.Condition);
            Resolve_Stmt_List (S.Then_Branch, null);
            Resolve_Stmt_List (S.Else_Branch, null);
         when Stmt_FOR =>
            Resolve_Expr (S.For_Start);
            Resolve_Expr (S.For_End);
            Resolve_Expr (S.For_Step);
            Resolve_Stmt_List (S.For_Body, null);
         when Stmt_WHILE =>
            Resolve_Expr (S.While_Cond);
            Resolve_Stmt_List (S.While_Body, null);
         when Stmt_LOOP_REPEAT =>
            Resolve_Stmt_List (S.Repeat_Body, null);
            Resolve_Expr (S.Until_Cond);
         when Stmt_SELECT =>
            Resolve_Expr (S.Selector);
            declare
               B : Case_Branch := S.Branches;
            begin
               while B /= null loop
                  Resolve_Expr_List (B.Conditions);
                  Resolve_Stmt_List (B.Branch_Body, null);
                  B := B.Next;
               end loop;
            end;
            Resolve_Stmt_List (S.Otherwise_Part, null);
         when Stmt_RSEED =>
            Resolve_Expr (S.Seed_Expr);
         when Stmt_BREAK =>
            Resolve_Expr (S.Expr);
         when others => null;
      end case;
   end Resolve_Stmt;

   procedure Resolve_Stmt_List (Stmt  : Statement_Access;
                                Bound : Statement_Access) is
      Cur : Statement_Access := Stmt;
   begin
      while Cur /= null and then Cur /= Bound loop
         Resolve_Stmt (Cur);
         Cur := Cur.Next;
      end loop;
   end Resolve_Stmt_List;

begin
   Resolve_Stmt_List (Start, Boundary);
end Resolve_Expr_Indices;