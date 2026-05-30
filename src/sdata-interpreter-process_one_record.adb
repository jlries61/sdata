--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Process_One_Record (Logical_I        : Positive;
                               Logical_Count    : Natural;
                               Start            : Statement_Access;
                               Boundary         : Statement_Access;
                               Global_Has_Write : Boolean;
                               Ctx              : in out Step_Context;
                               Pause_After      : Boolean := False;
                               Action           : out Step_Action) is
   Phys_I : constant Positive := SData_Core.Table.Logical_To_Physical (Logical_I);
   Iter   : Statement_Access;
begin
   Set_Current_Record_Index (Phys_I);
   SData_Core.Table.Set_Logical_Record_Index (Logical_I);

   Reset_PDV_Non_Held;
   Load_PDV_From_Table (Phys_I);

   declare
      Flags  : constant Group_Flags_Result :=
         Group_Flags (Logical_I, Logical_Count);
      By_N   : constant Natural := SData_Core.Table.By_Var_Count;
   begin
      Ctx.BOG := Flags.BOG;
      Ctx.EOG := Flags.EOG;
      Set_Group_Boundary (BOG => Ctx.BOG, EOG => Ctx.EOG);
      for I in 1 .. By_N loop
         declare Name : constant String := SData_Core.Table.By_Var_Name (I); begin
            Set_Temporary ("FIRST." & Name, (Kind => Val_Integer, Int_Val => (if Flags.BOG then 1 else 0)));
            Set_Temporary ("LAST."  & Name, (Kind => Val_Integer, Int_Val => (if Flags.EOG then 1 else 0)));
         end;
      end loop;

      --  Emit record header with optional BY group annotation
      if SData_Core.Config.Debug_Level >= 2 then
         declare
            Header : Ada.Strings.Unbounded.Unbounded_String :=
               Ada.Strings.Unbounded.To_Unbounded_String
                  ("-- record" & Logical_I'Image & " (physical" & Phys_I'Image & ")");
         begin
            if By_N > 0 and then Flags.BOG then
               declare
                  Label : constant String :=
                     (if Logical_I = 1 then "BY GROUP START" else "BY GROUP CHANGE");
               begin
                  Ada.Strings.Unbounded.Append (Header, "  [" & Label & ":");
                  for I in 1 .. By_N loop
                     declare
                        Name    : constant String :=
                           SData_Core.Table.By_Var_Name (I);
                        New_Val : constant Value :=
                           SData_Core.Variables.Get (Name);
                     begin
                        if Logical_I > 1 then
                           --  CHANGE: show old → new
                           declare
                              Prev_Phys : constant Positive :=
                                 SData_Core.Table.Logical_To_Physical (Logical_I - 1);
                              Old_Val : constant Value :=
                                 SData_Core.Table.Get_Value (Prev_Phys, Name);
                           begin
                              Ada.Strings.Unbounded.Append
                                 (Header, " " & Name & " " & Debug_Value (Old_Val)
                                  & " → " & Debug_Value (New_Val));
                           end;
                        else
                           --  START: show just the current value
                           Ada.Strings.Unbounded.Append
                              (Header, " " & Name & "=" & Debug_Value (New_Val));
                        end if;
                     end;
                  end loop;
                  Ada.Strings.Unbounded.Append (Header, "]");
               end;
            end if;
            Debug_Trace (Ada.Strings.Unbounded.To_String (Header), 2);
         end;
      end if;
   end;

   Iter := Start;
   Ctx.Deleted := False;
   SData_Core.Table.Set_Record_Explicitly_Written (False);

   declare
      Break_Fired : Boolean := False;
      Act         : Step_Action := Action_Continue;
   begin
      while Iter /= null and then Iter /= Boundary loop
         case Iter.Kind is
            when Stmt_LET | Stmt_SET | Stmt_PRINT | Stmt_NAMES | Stmt_IF
               | Stmt_WHILE | Stmt_FOR | Stmt_LOOP_REPEAT | Stmt_SELECT
               | Stmt_DELETE | Stmt_BREAK | Stmt_WRITE | Stmt_OUTPUT | Stmt_ECHO
               | Stmt_HOLD | Stmt_UNHOLD | Stmt_DIM
               | Stmt_BY | Stmt_DIGITS | Stmt_HELP =>
               begin
                  Execute_Statement (Iter, Ctx);
               exception
                  when Break_Triggered =>
                     Inspect_PDV (Logical_I, Logical_Count, Act);
                     Break_Fired := True;
                  when E : Script_Error | SData_Core.Script_Error =>
                     if SData_Core.Config.Continue_On_Error then
                        Put_Line_Error ("Error: " & Ada.Exceptions.Exception_Message (E));
                        SData_Core.Commands.Execute_Record_Error
                           (1, SData_Core.Table.Get_Current_Record_Index);
                     else raise; end if;
                  when E : others =>
                     if SData_Core.Config.Continue_On_Error then
                        Put_Line_Error ("Error: " & Ada.Exceptions.Exception_Message (E));
                        SData_Core.Commands.Execute_Record_Error
                           (1, SData_Core.Table.Get_Current_Record_Index);
                     else raise Script_Error with Ada.Exceptions.Exception_Message (E); end if;
               end;
            when others => null;
         end case;
         exit when Ctx.Deleted or else Break_Fired;
         Iter := Iter.Next;
      end loop;

      if not Break_Fired and then Pause_After then
         Inspect_PDV (Logical_I, Logical_Count, Act);
      end if;
      Action := Act;
   end;

   --  Automatic flush: if the step contains no explicit WRITE and the
   --  record was not deleted, write the final PDV state to the output table.
   if not Ctx.Deleted and then not Global_Has_Write then
      SData_Core.Variables.Flush_PDV_To_Output;
   end if;

   --  Per-record multi-target routing (Follow-on C).
   --  After the data step body executes, route the current PDV into the
   --  appropriate per-target buffers.
   if not Ctx.Deleted and then Natural (Registered_Saves.Length) > 0 then
      if Write_Fired_This_Iter then
         --  Drain WRITE-queued targets into their buffers.
         --  A target may appear multiple times (e.g. WRITE a; WRITE a),
         --  producing one buffer row per WRITE statement that fired for it.
         for T_Ref of Pending_Writes_This_Iter loop
            for B of Target_Buffers loop
               if B.Target = T_Ref then
                  Append_Pdv_To_Buffer (B);
                  exit;
               end if;
            end loop;
         end loop;
      else
         --  Auto-flush: no explicit WRITE fired this iteration.
         --  Append to every target whose IF= filter passes.
         for B of Target_Buffers loop
            if Should_Write (B.Target) then
               Append_Pdv_To_Buffer (B);
            end if;
         end loop;
      end if;
   end if;

   --  Reset per-record WRITE routing state so each record starts clean.
   Write_Fired_This_Iter    := False;
   Pending_Writes_This_Iter.Clear;
end Process_One_Record;