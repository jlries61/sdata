--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Inspect_PDV
  (Logical_I     :        Positive;
   Logical_Count :        Natural;
   Action        :    out Step_Action)
is
   Inspect_I  : Positive := Logical_I;
   Saved_Phys : constant Positive :=
      SData.Table.Logical_To_Physical (Logical_I);

   procedure Load_Inspect_Record (L : Positive) is
      P : constant Positive := SData.Table.Logical_To_Physical (L);
   begin
      SData.Table.Set_Current_Record_Index (P);
      SData.Variables.Load_PDV_From_Table (P);
      Put_Line_Error ("[debug] loaded record" & L'Image & " into PDV");
   end Load_Inspect_Record;

begin
   Action := Action_Continue;

   if not SData.IO.Is_Interactive then
      Put_Line_Error ("[debug] BREAK: record" & Logical_I'Image
                      & " paused (non-interactive — continuing)");
      return;
   end if;

   loop
      declare
         Prompt : constant String :=
            "[debug:record "
            & Ada.Strings.Fixed.Trim (Positive'Image (Inspect_I), Ada.Strings.Both)
            & "]> ";
         Line   : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Ada.Text_IO.Put (Ada.Text_IO.Standard_Error, Prompt);
         Ada.Text_IO.Unbounded_IO.Get_Line (Line);
         declare
            S     : constant String :=
               Ada.Strings.Fixed.Trim
                  (Ada.Strings.Unbounded.To_String (Line), Ada.Strings.Both);
            Upper : constant String := To_Upper (S);
         begin
            if Upper = "CONTINUE" or else Upper = "C" then
               SData.Table.Set_Current_Record_Index (Saved_Phys);
               SData.Variables.Load_PDV_From_Table (Saved_Phys);
               Action := Action_Continue;
               return;

            elsif Upper = "STEP" or else Upper = "S" then
               SData.Table.Set_Current_Record_Index (Saved_Phys);
               SData.Variables.Load_PDV_From_Table (Saved_Phys);
               Action := Action_Step;
               return;

            elsif Upper = "RUN" then
               SData.Table.Set_Current_Record_Index (Saved_Phys);
               SData.Variables.Load_PDV_From_Table (Saved_Phys);
               Action := Action_Run;
               return;

            elsif Upper'Length >= 6
               and then Upper (Upper'First .. Upper'First + 5) = "RECORD"
            then
               declare
                  Rest   : constant String :=
                     Ada.Strings.Fixed.Trim
                        (S (S'First + 6 .. S'Last), Ada.Strings.Both);
                  Target : Integer;
               begin
                  if Rest'Length = 0 then
                     Put_Line_Error ("Usage: RECORD N | RECORD +N | RECORD -N");
                  else
                     if Rest (Rest'First) = '+' then
                        Target := Inspect_I
                           + Integer'Value (Rest (Rest'First + 1 .. Rest'Last));
                     elsif Rest (Rest'First) = '-' then
                        Target := Inspect_I
                           - Integer'Value (Rest (Rest'First + 1 .. Rest'Last));
                     else
                        Target := Integer'Value (Rest);
                     end if;
                     if Target < 1 then Target := 1; end if;
                     if Target > Logical_Count then Target := Logical_Count; end if;
                     Inspect_I := Positive (Target);
                     Load_Inspect_Record (Inspect_I);
                  end if;
               exception
                  when Constraint_Error =>
                     Put_Line_Error ("Invalid record number: " & Rest);
               end;

            elsif S'Length >= 5
               and then To_Upper (S (S'First .. S'First + 4)) = "PRINT"
            then
               declare
                  Expr_Str : constant String :=
                     Ada.Strings.Fixed.Trim
                        (S (S'First + 5 .. S'Last), Ada.Strings.Both);
               begin
                  if Expr_Str'Length = 0 then
                     Put_Line_Error ("Usage: PRINT <expr>");
                  else
                     declare
                        Parse_Ctx : Parser_Context;
                        Prog      : Statement_Access;
                        Exec_Ctx  : Step_Context;
                     begin
                        Initialize (Parse_Ctx, "PRINT " & Expr_Str);
                        Prog := Parse_Program (Parse_Ctx);
                        if Prog /= null then
                           Execute_Statement (Prog, Exec_Ctx);
                           SData.AST.Free_Program (Prog);
                        end if;
                     exception
                        when E : others =>
                           Put_Line_Error
                              ("Error: " & Ada.Exceptions.Exception_Message (E));
                     end;
                  end if;
               end;

            elsif S'Length = 0 then
               null;

            else
               Put_Line_Error ("Unknown command: " & S);
               Put_Line_Error
                  ("Commands: PRINT <expr>  RECORD N/+N/-N  CONTINUE  STEP  RUN");
            end if;
         end;
      end;
   end loop;
end Inspect_PDV;