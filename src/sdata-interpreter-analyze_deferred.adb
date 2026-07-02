--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Analyze_Deferred (Start, Boundary : Statement_Access) is

   --  Set of names introduced (LET/SET/FOR/DIM/ARRAY) within the deferred block.
   --  Whole-block scope: collected in Pass 1 so forward references are legal.
   Introduced : Name_Sets.Set;

   function U (S : String) return String renames To_Upper;

   --  A name is "defined" if it is a table column, a session variable, an
   --  array, or introduced anywhere in this deferred block (forward references
   --  are legal because we collect the full environment before any check runs).
   function Is_Defined (Name : String) return Boolean is
      Up : constant String := U (Name);
   begin
      return SData_Core.Table.Has_Column (Up)
        or else SData_Core.Variables.Has_Array (Up)
        or else SData_Core.Variables.Get_Type (Up) /= Val_Missing
        or else Introduced.Contains (Up);
   end Is_Defined;

   --  Forward declaration: Note_Introduced and Walk_Body are mutually recursive.
   procedure Note_Introduced (Stmt : Statement_Access);

   --  Walk the statement chain starting at Body_Start, recording each statement's
   --  introduced names.  Used to recurse into compound-statement bodies.
   procedure Walk_Body (Body_Start : Statement_Access) is
      S : Statement_Access := Body_Start;
   begin
      while S /= null loop
         Note_Introduced (S);
         S := S.Next;
      end loop;
   end Walk_Body;

   --  Record the name(s) introduced by Stmt and recurse into any sub-bodies so
   --  that names created by nested LET/SET/DIM/ARRAY/FOR are also collected.
   --  Mirrors the case structure of Free_Program (sdata-ast.adb).
   procedure Note_Introduced (Stmt : Statement_Access) is
   begin
      case Stmt.Kind is
         when Stmt_LET | Stmt_SET =>
            Introduced.Include (U (Stmt.Var_Name (1 .. Stmt.Var_Len)));
         when Stmt_FOR =>
            Introduced.Include (U (Stmt.For_Var (1 .. Stmt.For_Var_Len)));
            Walk_Body (Stmt.For_Body);
         when Stmt_DIM | Stmt_ARRAY =>
            if Stmt.Arr_Name_Len > 0 then
               Introduced.Include (U (Stmt.Arr_Name (1 .. Stmt.Arr_Name_Len)));
            end if;
         when Stmt_IF =>
            Walk_Body (Stmt.Then_Branch);
            Walk_Body (Stmt.Else_Branch);
         when Stmt_WHILE =>
            Walk_Body (Stmt.While_Body);
         when Stmt_LOOP_REPEAT =>
            Walk_Body (Stmt.Repeat_Body);
         when Stmt_SELECT =>
            declare
               Br : Case_Branch := Stmt.Branches;
            begin
               while Br /= null loop
                  Walk_Body (Br.Branch_Body);
                  Br := Br.Next;
               end loop;
            end;
            Walk_Body (Stmt.Otherwise_Part);
         when others => null;
      end case;
   end Note_Introduced;

   pragma Unreferenced (Is_Defined);
   --  Is_Defined is used by semantic checks added in Tasks C2-C5; suppress the
   --  unreferenced warning until the first check references it.

   --  Functions the parser turns into Expr_Function_Call nodes but that the
   --  evaluator dispatches SPECIALLY, outside Dispatch_Table -- so
   --  Is_Known_Function returns False for them even though they are valid.
   --  Confirmed by auditing SData_Core.Evaluator.Evaluate_Function: only IF
   --  is intercepted before the Dispatch_Table lookup (for lazy evaluation).
   --  Every other special-form name (LAG/NEXT/OBS and their $-variants,
   --  the identifier-ref functions) IS registered in Dispatch_Table with an
   --  arity, so it is handled by the normal path.  A whitelisted name is
   --  neither flagged as unknown nor arity-checked (its arity is not
   --  registered).
   function Is_Special_Function (Name : String) return Boolean is
     (U (Name) = "IF");

   --  Count the arguments in an expression list (each range counts as one).
   function Arg_Count (L : Expression_List) return Natural is
      N : Natural := 0;
      C : Expression_List := L;
   begin
      while C /= null loop
         N := N + 1;
         C := C.Next;
      end loop;
      return N;
   end Arg_Count;

   --  Recursively validate an expression tree: reject calls to unknown
   --  functions and calls to known functions with an out-of-range argument
   --  count.  Recurses into every sub-expression.
   procedure Check_Expr (E : Expression_Access) is
   begin
      if E = null then
         return;
      end if;
      case E.Kind is
         when Expr_Binary_Op =>
            Check_Expr (E.Left);
            Check_Expr (E.Right);
         when Expr_Unary_Op =>
            Check_Expr (E.Operand);
         when Expr_Array_Access =>
            declare
               C : Expression_List := E.Arr_Idx;
            begin
               while C /= null loop
                  Check_Expr (C.Expr);
                  if C.Is_Range then
                     Check_Expr (C.Expr_End);
                  end if;
                  C := C.Next;
               end loop;
            end;
         when Expr_Function_Call =>
            declare
               FN : constant String := E.Func_Name (1 .. E.Func_Len);
            begin
               --  A name parsed as a function call but registered as an array
               --  (or introduced as one in this block) is really array access
               --  -- batch parses X(1) as a call because DIM has not run yet.
               --  A whitelisted special-form name (IF) is valid but not in
               --  Dispatch_Table.  Skip the unknown/arity checks for both.
               if not SData_Core.Variables.Has_Array (U (FN))
                 and then not Introduced.Contains (U (FN))
                 and then not Is_Special_Function (FN)
               then
                  if not Is_Known_Function (FN) then
                     raise SData_Core.Script_Error with
                       "unknown function '" & FN & "'";
                  end if;
                  --  Function_Arity raises on an unregistered name, so it is
                  --  gated behind the Is_Known_Function check above.
                  declare
                     A : constant Arity_Spec := Function_Arity (FN);
                     N : constant Natural := Arg_Count (E.Arguments);
                  begin
                     if N < A.Min_Args or else N > A.Max_Args then
                        raise SData_Core.Script_Error with
                          "function '" & FN & "' expects "
                          & (if A.Min_Args = A.Max_Args
                             then A.Min_Args'Image & " argument(s)"
                             else "between" & A.Min_Args'Image & " and"
                                  & A.Max_Args'Image & " arguments")
                          & ", got" & N'Image;
                     end if;
                  end;
               end if;
               --  Recurse into arguments regardless.  For identifier-ref
               --  functions (LAG/NEXT/OBS) the first argument is a bare
               --  Expr_Variable naming a column; Check_Expr does nothing for
               --  Expr_Variable, so no spurious error results.
               declare
                  C : Expression_List := E.Arguments;
               begin
                  while C /= null loop
                     Check_Expr (C.Expr);
                     if C.Is_Range then
                        Check_Expr (C.Expr_End);
                     end if;
                     C := C.Next;
                  end loop;
               end;
            end;
         when others =>
            null;   --  literals, variables, missing: nothing to check here
      end case;
   end Check_Expr;

   --  Validate every expression in a list.
   procedure Check_Expr_List (L : Expression_List) is
      C : Expression_List := L;
   begin
      while C /= null loop
         Check_Expr (C.Expr);
         if C.Is_Range then
            Check_Expr (C.Expr_End);
         end if;
         C := C.Next;
      end loop;
   end Check_Expr_List;

   --  Map a Value_Kind to the human-readable type name used in error messages.
   function Kind_Name (K : Value_Kind) return String is
     (case K is when Val_String  => "string",
                when Val_Integer => "integer",
                when others      => "numeric");

   --  True if the expression tree contains any call to a special (polymorphic)
   --  function whose return type is NOT determined by its name's suffix — e.g.,
   --  IF can return any kind depending on its arguments, so
   --  Static_Result_Kind(IF(...)) wrongly returns Val_Numeric (the default for
   --  unsuffixed names).  When such a call appears in the RHS, defer the
   --  type-mismatch check to runtime for soundness.
   function Expr_Contains_Special_Call
     (E : Expression_Access) return Boolean
   is
      C : Expression_List;
   begin
      if E = null then
         return False;
      end if;
      case E.Kind is
         when Expr_Function_Call =>
            if Is_Special_Function (E.Func_Name (1 .. E.Func_Len)) then
               return True;
            end if;
            C := E.Arguments;
            while C /= null loop
               if Expr_Contains_Special_Call (C.Expr) then
                  return True;
               end if;
               if C.Is_Range
                  and then Expr_Contains_Special_Call (C.Expr_End)
               then
                  return True;
               end if;
               C := C.Next;
            end loop;
            return False;
         when Expr_Binary_Op =>
            return Expr_Contains_Special_Call (E.Left)
              or else Expr_Contains_Special_Call (E.Right);
         when Expr_Unary_Op =>
            return Expr_Contains_Special_Call (E.Operand);
         when Expr_Array_Access =>
            C := E.Arr_Idx;
            while C /= null loop
               if Expr_Contains_Special_Call (C.Expr) then
                  return True;
               end if;
               if C.Is_Range
                  and then Expr_Contains_Special_Call (C.Expr_End)
               then
                  return True;
               end if;
               C := C.Next;
            end loop;
            return False;
         when others =>
            return False;
      end case;
   end Expr_Contains_Special_Call;

   --  Forward declaration: Check_Statement and Check_Body are mutually
   --  recursive (compound statements carry nested statement bodies).
   procedure Check_Statement (S : Statement_Access);

   --  Validate every statement in a body chain.
   procedure Check_Body (B : Statement_Access) is
      S : Statement_Access := B;
   begin
      while S /= null loop
         Check_Statement (S);
         S := S.Next;
      end loop;
   end Check_Body;

   --  Validate every expression field of one statement, then recurse into any
   --  nested statement bodies.  Mirrors the field layout in sdata-ast.ads.
   procedure Check_Statement (S : Statement_Access) is
   begin
      --  Fields present on every statement (non-variant part).
      Check_Expr (S.Expr);
      Check_Expr (S.Arr_Idx);
      Check_Expr_List (S.Arr_Idx_List);

      case S.Kind is
         when Stmt_PRINT =>
            Check_Expr_List (S.Print_Args);
         when Stmt_IF =>
            Check_Expr (S.Condition);
            Check_Body (S.Then_Branch);
            Check_Body (S.Else_Branch);
         when Stmt_FOR =>
            Check_Expr (S.For_Start);
            Check_Expr (S.For_End);
            Check_Expr (S.For_Step);
            Check_Body (S.For_Body);
         when Stmt_WHILE =>
            Check_Expr (S.While_Cond);
            Check_Body (S.While_Body);
         when Stmt_LOOP_REPEAT =>
            Check_Body (S.Repeat_Body);
            Check_Expr (S.Until_Cond);
         when Stmt_RSEED =>
            Check_Expr (S.Seed_Expr);
         when Stmt_SELECT =>
            Check_Expr (S.Selector);
            declare
               Br : Case_Branch := S.Branches;
            begin
               while Br /= null loop
                  Check_Expr_List (Br.Conditions);
                  Check_Body (Br.Branch_Body);
                  Br := Br.Next;
               end loop;
            end;
            Check_Body (S.Otherwise_Part);
         when Stmt_KEEP | Stmt_DROP | Stmt_HOLD | Stmt_UNHOLD | Stmt_UNSET
            | Stmt_ARRAY | Stmt_DIM | Stmt_DISPLAY =>
            Check_Expr (S.Arr_Start_Expr);
            Check_Expr (S.Arr_End_Expr);
         when others =>
            null;
      end case;

      --  Scalar assignment type-mismatch check (Task C3).
      --  Reject ONLY the string<->numeric boundary; within the numeric family
      --  (Val_Numeric/Val_Integer) the runtime Coerce_For_Scalar promotes or
      --  truncates freely, so those are NOT rejected here.
      --  Soundness guards — defer to runtime when:
      --    • RHS kind is indeterminate (Val_Missing).
      --    • The RHS expression contains an IF call (IF is polymorphic —
      --      Static_Result_Kind returns the wrong kind for it because IF has no
      --      $/%suffix; deferring is the only sound choice).
      --  The check fires for ALL scalar LET/SET targets, including existing
      --  table columns — catching a mismatch before any record is processed.
      if (S.Kind = Stmt_LET or else S.Kind = Stmt_SET)
         and then not S.Is_Array and then S.Expr /= null
      then
         declare
            Target   : constant String := S.Var_Name (1 .. S.Var_Len);
            Expected : constant Value_Kind := Get_Expected_Kind (Target);
            RHS      : constant Value_Kind := Static_Result_Kind (S.Expr);
         begin
            if RHS /= Val_Missing
               and then not Expr_Contains_Special_Call (S.Expr)
               and then (Expected = Val_String) /= (RHS = Val_String)
            then
               raise SData_Core.Script_Error with
                 "Type mismatch for variable """ & Target
                 & """: cannot assign " & Kind_Name (RHS)
                 & " to " & Kind_Name (Expected) & " variable";
            end if;
         end;
      end if;
   end Check_Statement;

   Cur : Statement_Access;

begin
   if Start = null or else Start = Boundary then
      return;
   end if;

   --  Pass 1: collect introduced names (whole-block scope).
   Cur := Start;
   while Cur /= null and then Cur /= Boundary loop
      Note_Introduced (Cur);
      Cur := Cur.Next;
   end loop;

   --  Pass 2: run semantic checks.  Task C2 adds the unknown-function and
   --  arity checks (via Check_Statement -> Check_Expr).  A violation raises
   --  SData_Core.Script_Error, which propagates out of Execute before any
   --  record is processed.
   Cur := Start;
   while Cur /= null and then Cur /= Boundary loop
      Check_Statement (Cur);
      Cur := Cur.Next;
   end loop;
end Analyze_Deferred;
