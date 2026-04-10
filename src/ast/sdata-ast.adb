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

end SData.AST;
