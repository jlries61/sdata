--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Analyze_One (Stmt : Statement_Access) is

   --  Entry-time fast feedback (Task C5).  Runs the subset of semantic checks
   --  that are sound at the moment a single deferred statement is entered at
   --  the REPL:
   --    • Unknown-function + arity (C2)
   --    • Type-mismatch for scalar LET/SET targets (C3)
   --
   --  The undefined-variable check (C4) is intentionally OMITTED.  At entry
   --  time a name introduced by a LATER, not-yet-entered statement would be a
   --  false positive — forward references are legal within a deferred block.
   --  Undefined-var detection is exclusively the responsibility of the whole-
   --  block pass in Analyze_Deferred (called at RUN).
   --
   --  Arrays are NOT tracked via an "Introduced" set here: DIM/ARRAY are
   --  immediate commands in the REPL, so any live array is already registered
   --  in SData_Core.Variables.Has_Array by the time a subsequent LET can
   --  reference it.

   function U (S : String) return String renames To_Upper;

   --  IF is dispatched specially by the evaluator (lazy evaluation) and is
   --  not registered in the Dispatch_Table, so Is_Known_Function returns False
   --  for it.  Whitelist it so it is neither flagged as unknown nor arity-
   --  checked.  (All other special forms — LAG, NEXT, OBS, etc. — ARE
   --  registered; they are handled by the normal path.)
   function Is_Special_Function (Name : String) return Boolean is
     (U (Name) = "IF");

   --  Count the arguments in an expression list.
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

   --  Forward declarations: Check_Statement and Check_Body are mutually
   --  recursive (compound statements carry nested statement bodies).
   procedure Check_Statement (S : Statement_Access);

   procedure Check_Body (B : Statement_Access) is
      S : Statement_Access := B;
   begin
      while S /= null loop
         Check_Statement (S);
         S := S.Next;
      end loop;
   end Check_Body;

   --  True if the expression tree contains a call to a special (polymorphic)
   --  function whose return type is NOT determined by its name's suffix.  IF
   --  can return any kind depending on its arguments, so
   --  Static_Result_Kind(IF(...)) wrongly returns Val_Numeric.  When such a
   --  call appears in the RHS, the type-mismatch check is deferred to runtime
   --  for soundness.
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

   --  Recursively validate an expression tree: reject calls to unknown
   --  functions and calls to known functions with an out-of-range argument
   --  count.  The Expr_Variable arm is intentionally a no-op (undefined-var
   --  check is deferred to the whole-block Analyze_Deferred pass at RUN).
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
               --  A name parsed as a function call but registered as a live
               --  array (Has_Array) is really array access — skip the unknown/
               --  arity checks.  (In the REPL, DIM is immediate so any
               --  declared array is already live in Has_Array.)  Whitelisted
               --  special-form names (IF) are also excluded.
               if not SData_Core.Variables.Has_Array (U (FN))
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
                     N : constant Natural    := Arg_Count (E.Arguments);
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
               --  Recurse into arguments regardless.  For MISSING(<varname>)
               --  a direct Expr_Variable argument is NOT subject to the
               --  undefined-variable check (already skipped in this pass
               --  anyway), but other expressions inside MISSING's args still
               --  need function/arity checking.
               declare
                  C          : Expression_List := E.Arguments;
                  Is_Missing : constant Boolean := U (FN) = "MISSING";
               begin
                  while C /= null loop
                     if not (Is_Missing
                             and then C.Expr /= null
                             and then C.Expr.Kind = Expr_Variable)
                     then
                        Check_Expr (C.Expr);
                     end if;
                     if C.Is_Range then
                        Check_Expr (C.Expr_End);
                     end if;
                     C := C.Next;
                  end loop;
               end;
            end;
         when Expr_Variable =>
            null;   --  C5: undefined-var check intentionally omitted at entry
         when others =>
            null;   --  literals, missing: nothing to check here
      end case;
   end Check_Expr;

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

   function Kind_Name (K : Value_Kind) return String is
     (case K is when Val_String  => "string",
                when Val_Integer => "integer",
                when others      => "numeric");

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

      --  Scalar assignment type-mismatch check (C3).
      --  Reject ONLY the string<->numeric boundary.  Within the numeric
      --  family (Val_Numeric/Val_Integer) the runtime Coerce_For_Scalar
      --  promotes or truncates freely, so those are NOT rejected here.
      --  Soundness guards — defer to runtime when:
      --    • RHS kind is indeterminate (Val_Missing).
      --    • The RHS expression contains an IF call (IF is polymorphic;
      --      Static_Result_Kind returns the wrong kind because IF has no
      --      $/%suffix; deferring is the only sound choice).
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

begin
   Check_Statement (Stmt);
end Analyze_One;
