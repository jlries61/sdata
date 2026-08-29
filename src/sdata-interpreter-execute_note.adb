--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

--  NOTE (ADR-059) -- the Immediate-tier counterpart to PRINT.  Requires at
--  least one argument (no bare "print everything" form, unlike PRINT: there
--  is no "current record" for it to print permanent variables of).  Rejects
--  any argument whose expression tree references a permanent variable or
--  permanent array anywhere within it -- not just a bare top-level
--  reference -- before printing anything, since no such reference can
--  reduce to a well-defined single value outside AGGREGATE/STATS's own
--  group-scan machinery (see ADR-059's Context for the full rationale).
separate (SData.Interpreter)
procedure Execute_Note (Stmt : Statement_Access) is

   procedure Reject_Name (Upper_Name : String) is
   begin
      raise Script_Error with
         "NOTE: """ & Upper_Name &
         """ is a permanent variable (a per-row value); NOTE only accepts" &
         " temporary variables";
   end Reject_Name;

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
               if Has_Array (Upper) then
                  if not Is_Temporary_Array (Upper) then
                     Reject_Name (Upper);
                  end if;
               elsif PDV_Resolve (Upper) > 0 then
                  Reject_Name (Upper);
               end if;
            end;
         when Expr_Binary_Op =>
            Reject_If_Permanent (E.Left);
            Reject_If_Permanent (E.Right);
         when Expr_Unary_Op =>
            Reject_If_Permanent (E.Operand);
         when Expr_Array_Access =>
            declare
               Upper : constant String := To_Upper (E.Arr_Name (1 .. E.Arr_Len));
            begin
               if Has_Array (Upper) and then not Is_Temporary_Array (Upper) then
                  Reject_Name (Upper);
               end if;
            end;
            Reject_If_Permanent_List (E.Arr_Idx);
         when Expr_Function_Call =>
            --  Mirrors Print_Value_List's own "a name Has_Array is really
            --  array access parsed as a call" handling (DIM hasn't
            --  necessarily run yet when this parses, per Check_Expr's own
            --  comment on the identical ambiguity).
            declare
               Upper : constant String := To_Upper (E.Func_Name (1 .. E.Func_Len));
            begin
               if Has_Array (Upper) and then not Is_Temporary_Array (Upper) then
                  Reject_Name (Upper);
               end if;
            end;
            Reject_If_Permanent_List (E.Arguments);
         when Expr_Numeric_Literal | Expr_String_Literal | Expr_Missing =>
            null;
      end case;
   end Reject_If_Permanent;

begin
   if Stmt.Print_Args = null then
      raise Script_Error with "NOTE requires at least one argument";
   end if;

   declare
      Current_Arg : Expression_List := Stmt.Print_Args;
   begin
      while Current_Arg /= null loop
         Reject_If_Permanent (Current_Arg.Expr);
         Current_Arg := Current_Arg.Next;
      end loop;
   end;

   Print_Value_List (Stmt.Print_Args);
end Execute_Note;
