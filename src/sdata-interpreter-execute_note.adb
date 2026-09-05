--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

--  NOTE (ADR-059) -- the Immediate-tier counterpart to PRINT.  Requires at
--  least one argument (no bare "print everything" form, unlike PRINT: there
--  is no "current record" for it to print permanent variables of).  Rejects
--  any argument whose expression tree references a permanent variable or
--  permanent array element anywhere within it -- not just a bare top-level
--  reference -- before printing anything, since no such reference can
--  reduce to a well-defined single value outside AGGREGATE/STATS's own
--  group-scan machinery (see ADR-059's Context for the full rationale).
--
--  Array references are checked per resolved ELEMENT (ADR-063), not by the
--  array's own declared storage class: a virtual array can alias
--  constituents of mixed class (sdata-core ADR-0023), and the array-level
--  flag is always False for virtual arrays regardless of what any specific
--  element actually is. The per-element check happens INSIDE
--  Print_Value_List's own index evaluation (via its Check_Permanent
--  callback), not as a separate up-front pass here -- an index expression
--  is not guaranteed idempotent (e.g. one containing RANDOM()), so
--  evaluating it once to check and again to print could check one element
--  and print a different one. See ADR-063 for the full rationale, including
--  this exact hazard and why it ruled out the original two-pass design.
separate (SData.Interpreter)
procedure Execute_Note (Stmt : Statement_Access) is

   procedure Reject_Name (Upper_Name : String) is
   begin
      raise Script_Error with
         "NOTE: """ & Upper_Name &
         """ is a permanent variable (a per-row value); NOTE only accepts" &
         " temporary variables";
   end Reject_Name;

   --  Passed to Print_Value_List as its Check_Permanent callback: rejects if
   --  the resolved element Arr_Name(Idx) is not a genuine temporary, naming
   --  the specific element (not the array), since it's the element (not
   --  necessarily the array as a whole) that's permanent. Print_Value_List
   --  calls this immediately after resolving each index and before printing
   --  it, so the element checked here is always the exact element printed.
   procedure Reject_Element (Arr_Name : String; Idx : Integer) is
   begin
      if not SData_Core.Variables.Array_Element_Is_Temporary (Arr_Name, Idx) then
         Reject_Name (Arr_Name & "(" &
            Ada.Strings.Fixed.Trim (Integer'Image (Idx), Ada.Strings.Both) & ")");
      end if;
   end Reject_Element;

   procedure Reject_If_Permanent (E : Expression_Access);

   procedure Reject_If_Permanent_List (List : Expression_List) is
      Node : Expression_List := List;
   begin
      while Node /= null loop
         Reject_If_Permanent (Node.Expr);
         if Node.Is_Range then
            Reject_If_Permanent (Node.Expr_End);
         end if;
         Node := Node.Next;
      end loop;
   end Reject_If_Permanent_List;

   procedure Reject_If_Permanent (E : Expression_Access) is
   begin
      if E = null then return; end if;
      case E.Kind is
         when Expr_Variable =>
            declare
               Upper : constant String := To_Upper (E.Var_Name (1 .. E.Var_Len));
            begin
               --  A bare whole-array reference (NOTE V, no index) needs no
               --  check here -- Print_Value_List's Check_Permanent callback
               --  covers every element it resolves from Start_Idx..End_Idx.
               if not Has_Array (Upper) and then PDV_Resolve (Upper) > 0 then
                  Reject_Name (Upper);
               end if;
            end;
         when Expr_Binary_Op =>
            Reject_If_Permanent (E.Left);
            Reject_If_Permanent (E.Right);
         when Expr_Unary_Op =>
            Reject_If_Permanent (E.Operand);
         when Expr_Array_Access =>
            --  Only the index tree itself is checked here, statically, for
            --  an embedded permanent-variable reference -- the array
            --  element's own storage class is Print_Value_List's
            --  Check_Permanent callback's job (see this file's header).
            Reject_If_Permanent_List (E.Arr_Idx);
         when Expr_Function_Call =>
            --  Mirrors Print_Value_List's own "a name Has_Array is really
            --  array access parsed as a call" handling (DIM hasn't
            --  necessarily run yet when this parses, per Check_Expr's own
            --  comment on the identical ambiguity).
            Reject_If_Permanent_List (E.Arguments);
         when Expr_Numeric_Literal | Expr_String_Literal | Expr_Missing =>
            null;
      end case;
   end Reject_If_Permanent;

begin
   if Stmt.Print_Args = null then
      raise Script_Error with "NOTE requires at least one argument";
   end if;

   --  ADR-062/issue #76: unknown-function and arity checking, reusing the
   --  same static analysis PRINT already gets via Analyze_One/
   --  Analyze_Deferred. Check_Undefined => False: NOTE executes
   --  immediately and has no whole-block forward-reference model to
   --  resolve undefined variables against, so only the function-checking
   --  half fires (matches Analyze_One's own entry-time mode).
   Check_Statement (Stmt, Check_Undefined => False);

   declare
      Current_Arg : Expression_List := Stmt.Print_Args;
   begin
      while Current_Arg /= null loop
         Reject_If_Permanent (Current_Arg.Expr);
         Current_Arg := Current_Arg.Next;
      end loop;
   end;

   Print_Value_List (Stmt.Print_Args, Reject_Element'Access);
end Execute_Note;
