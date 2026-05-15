--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

with Ada.Unchecked_Deallocation;

package body SData.AST is

   procedure Free_Expr      is new Ada.Unchecked_Deallocation (Expression,          Expression_Access);
   procedure Free_Expr_Node is new Ada.Unchecked_Deallocation (Expression_List_Node, Expression_List);
   procedure Free_Var_Node  is new Ada.Unchecked_Deallocation (Variable_List_Node,   Variable_List);
   procedure Free_Ren_Node  is new Ada.Unchecked_Deallocation (Rename_Pair_Node,     Rename_List);
   procedure Free_Br_Node   is new Ada.Unchecked_Deallocation (Case_Branch_Node,     Case_Branch);
   procedure Free_Stmt_Node is new Ada.Unchecked_Deallocation (Statement,            Statement_Access);

   --  Forward declarations to resolve mutual recursion:
   --    Free(Expression_Access) <-> Free(Expression_List)
   --    Free(Statement_Access)  <-> Free_Program
   procedure Free (Expr     : in out Expression_Access);
   procedure Free (List     : in out Expression_List);
   procedure Free (List     : in out Variable_List);
   procedure Free (List     : in out Rename_List);
   procedure Free (Branches : in out Case_Branch);
   procedure Free (Stmt     : in out Statement_Access);

   procedure Free (List : in out Expression_List) is
      Next : Expression_List;
   begin
      while List /= null loop
         Next := List.Next;
         Free (List.Expr);
         if List.Is_Range then
            Free (List.Expr_End);
         end if;
         Free_Expr_Node (List);
         List := Next;
      end loop;
   end Free;

   procedure Free (Expr : in out Expression_Access) is
   begin
      if Expr = null then return; end if;
      case Expr.Kind is
         when Expr_Binary_Op    => Free (Expr.Left);    Free (Expr.Right);
         when Expr_Unary_Op     => Free (Expr.Operand);
         when Expr_Function_Call => Free (Expr.Arguments);
         when Expr_Array_Access  => Free (Expr.Arr_Idx);
         when others             => null;
      end case;
      Free_Expr (Expr);
   end Free;

   procedure Free (List : in out Variable_List) is
      Next : Variable_List;
   begin
      while List /= null loop
         Next := List.Next;
         Free_Var_Node (List);
         List := Next;
      end loop;
   end Free;

   procedure Free (List : in out Rename_List) is
      Next : Rename_List;
   begin
      while List /= null loop
         Next := List.Next;
         Free_Ren_Node (List);
         List := Next;
      end loop;
   end Free;

   procedure Free (Branches : in out Case_Branch) is
      Next : Case_Branch;
   begin
      while Branches /= null loop
         Next := Branches.Next;
         Free (Branches.Conditions);
         Free_Program (Branches.Branch_Body);
         Free_Br_Node (Branches);
         Branches := Next;
      end loop;
   end Free;

   procedure Free (Stmt : in out Statement_Access) is
   begin
      if Stmt = null then return; end if;
      --  Free common expression fields present on every statement kind.
      Free (Stmt.Arr_Idx);
      Free (Stmt.Arr_Idx_List);
      Free (Stmt.Expr);
      --  Free discriminant-specific children.
      case Stmt.Kind is
         when Stmt_PRINT =>
            Free (Stmt.Print_Args);
         when Stmt_KEEP | Stmt_DROP | Stmt_HOLD | Stmt_UNHOLD
            | Stmt_UNSET | Stmt_ARRAY | Stmt_DIM =>
            Free (Stmt.Vars);
            Free (Stmt.Arr_Vars);
            Free (Stmt.Arr_Start_Expr);
            Free (Stmt.Arr_End_Expr);
         when Stmt_RENAME =>
            Free (Stmt.Rename_Pairs);
         when Stmt_IF =>
            Free (Stmt.Condition);
            Free_Program (Stmt.Then_Branch);
            Free_Program (Stmt.Else_Branch);
         when Stmt_FOR =>
            Free (Stmt.For_Start);
            Free (Stmt.For_End);
            Free (Stmt.For_Step);
            Free_Program (Stmt.For_Body);
         when Stmt_WHILE =>
            Free (Stmt.While_Cond);
            Free_Program (Stmt.While_Body);
         when Stmt_LOOP_REPEAT =>
            Free_Program (Stmt.Repeat_Body);
            Free (Stmt.Until_Cond);
         when Stmt_RSEED =>
            Free (Stmt.Seed_Expr);
         when Stmt_SELECT =>
            Free (Stmt.Selector);
            Free (Stmt.Branches);
            Free_Program (Stmt.Otherwise_Part);
         when Stmt_SORT | Stmt_BY =>
            Free (Stmt.Sort_Vars);
         when others =>
            null;
      end case;
      Free_Stmt_Node (Stmt);
   end Free;

   procedure Free_Program (Prog : in out Statement_Access) is
      Next : Statement_Access;
   begin
      while Prog /= null loop
         Next := Prog.Next;
         Prog.Next := null;  --  Disconnect before freeing to prevent double-free.
         Free (Prog);
         Prog := Next;
      end loop;
   end Free_Program;

   function Copy_Expression_List (List : Expression_List) return Expression_List is
   begin
      if List = null then return null; end if;
      return new Expression_List_Node'(Expr     => Copy_Expression (List.Expr),
                                       Is_Range => List.Is_Range,
                                       Expr_End => (if List.Is_Range then Copy_Expression (List.Expr_End) else null),
                                       Next     => Copy_Expression_List (List.Next));
   end Copy_Expression_List;

   function Copy_Expression (Expr : Expression_Access) return Expression_Access is
      Res : Expression_Access;
   begin
      if Expr = null then return null; end if;
      Res := new Expression (Expr.Kind);
      case Expr.Kind is
         when Expr_Numeric_Literal =>
            Res.Value      := Expr.Value;
            Res.Is_Integer := Expr.Is_Integer;
            Res.Int_Value  := Expr.Int_Value;
         when Expr_String_Literal  => Res.Str_Value := Expr.Str_Value;
         when Expr_Variable =>
            Res.Var_Name := Expr.Var_Name;
            Res.Var_Len  := Expr.Var_Len;
         when Expr_Binary_Op =>
            Res.Op    := Expr.Op;
            Res.Left  := Copy_Expression (Expr.Left);
            Res.Right := Copy_Expression (Expr.Right);
         when Expr_Unary_Op =>
            Res.UOp     := Expr.UOp;
            Res.Operand := Copy_Expression (Expr.Operand);
         when Expr_Function_Call =>
            Res.Func_Name := Expr.Func_Name;
            Res.Func_Len  := Expr.Func_Len;
            Res.Arguments := Copy_Expression_List (Expr.Arguments);
         when Expr_Array_Access =>
            Res.Arr_Name := Expr.Arr_Name;
            Res.Arr_Len  := Expr.Arr_Len;
            Res.Arr_Idx  := Copy_Expression_List (Expr.Arr_Idx);
      end case;
      return Res;
   end Copy_Expression;

   procedure Free_Expression (Expr : in out Expression_Access) is
   begin
      Free (Expr);
   end Free_Expression;

end SData.AST;