--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Execute_Control_Flow (Stmt : Statement_Access; Ctx : in out Step_Context) is
begin
   case Stmt.Kind is
      when Stmt_IF =>
         declare
            Cond_Val : constant Boolean := Is_True (Evaluate (Stmt.Condition));
         begin
            if Cond_Val then
               Debug_Trace ("IF → TRUE", 2);
               Execute_List (Stmt.Then_Branch, Ctx);
            else
               if Stmt.Else_Branch /= null then
                  Debug_Trace ("IF → FALSE", 2);
                  Debug_Trace ("ELSE → taken", 2);
                  Execute_List (Stmt.Else_Branch, Ctx);
               else
                  Debug_Trace ("IF → FALSE (skipping)", 2);
               end if;
            end if;
         end;
      when Stmt_WHILE =>
         while Is_True (Evaluate (Stmt.While_Cond)) loop Execute_List (Stmt.While_Body, Ctx); end loop;
      when Stmt_FOR =>
         declare Start_Val : constant Value := Evaluate (Stmt.For_Start);
                 End_Val   : constant Value := Evaluate (Stmt.For_End);
                 Step_Val  : Value := (Kind => Val_Numeric, Num_Val => 1.0);
                 Current_I : Float;
         begin
            if Stmt.For_Step /= null then Step_Val := Evaluate (Stmt.For_Step); end if;
            declare
               S  : constant Float := Convert_To_Float (Start_Val);
               E  : constant Float := Convert_To_Float (End_Val);
               ST : constant Float := Convert_To_Float (Step_Val);
            begin
               Current_I := S;
               while (ST > 0.0 and then Current_I <= E) or else (ST < 0.0 and then Current_I >= E) loop
                  declare
                     Loop_Val : constant Value := (Kind => Val_Numeric, Num_Val => Current_I);
                     For_Var_Name : constant String := Stmt.For_Var (1 .. Stmt.For_Var_Len);
                  begin
                     Set_Permanent (For_Var_Name, Loop_Val);
                     Debug_Trace ("FOR " & For_Var_Name & " = " & Debug_Value (Loop_Val), 2);
                     Execute_List (Stmt.For_Body, Ctx);
                  end;
                  Current_I := Current_I + ST;
               end loop;
            end;
         end;
      when Stmt_LOOP_REPEAT =>
         loop
            Execute_List (Stmt.Repeat_Body, Ctx);
            exit when Is_True (Evaluate (Stmt.Until_Cond));
         end loop;
      when Stmt_SELECT =>
         declare
            Val     : constant Value := (if Stmt.Selector /= null then Evaluate (Stmt.Selector) else (Kind => Val_Missing));
            Branch  : Case_Branch := Stmt.Branches;
            Matched : Boolean := False;
         begin
            while Branch /= null loop
               if Stmt.Selector = null then
                  declare Cond : Expression_List := Branch.Conditions;
                  begin
                     while Cond /= null loop
                        if Is_True (Evaluate (Cond.Expr)) then
                           Execute_List (Branch.Branch_Body, Ctx); Matched := True; exit;
                        end if;
                        Cond := Cond.Next;
                     end loop;
                  end;
               else
                  declare Cond : Expression_List := Branch.Conditions;
                  begin
                     while Cond /= null loop
                        if Evaluate (Cond.Expr) = Val then
                           Execute_List (Branch.Branch_Body, Ctx); Matched := True; exit;
                        end if;
                        Cond := Cond.Next;
                     end loop;
                  end;
               end if;
               exit when Matched;
               Branch := Branch.Next;
            end loop;
            if not Matched and then Stmt.Otherwise_Part /= null then
               Execute_List (Stmt.Otherwise_Part, Ctx);
            end if;
         end;
      when others => null;
   end case;
end Execute_Control_Flow;