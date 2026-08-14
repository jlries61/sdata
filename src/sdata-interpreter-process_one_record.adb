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
            --  Stmt_OUTPUT is deliberately NOT here: OUTPUT is an immediate
            --  console-redirect command (executed once by the batch walker /
            --  at REPL entry).  Re-executing it per record re-opens the target
            --  with Create, truncating everything written before the data step
            --  and leaving only the final "RUN complete" line (issue #40).
            --  Stmt_DIM (and Stmt_ARRAY, never listed here) are the same
            --  category as of the P11 fix: DIM is now dispatched once, immediately,
            --  by the batch walker / at REPL entry, exactly like ARRAY already was.
            --  Re-executing it per record would re-DIM (and reset) the array on
            --  every record of a REPEAT n data step instead of once.
            --  Stmt_HOLD/Stmt_UNHOLD (also never listed here as of the
            --  2026-08-13 re-audit's PA-2/PB-4 resolution) are the same
            --  category too: they are Declarative -- a one-time decision
            --  about which variables retain their value across records, not
            --  a per-record toggle. An initial safety check against only
            --  tests/hold_test.cmd wrongly concluded per-record replay was
            --  never load-bearing; tests/sort_by.cmd's BY-group running-total
            --  idiom (HOLD var / accumulate / UNHOLD var, all written inside
            --  the per-record body) DID regress when this whitelist entry was
            --  first removed, because Set_Permanent's Is_Held check at
            --  assignment time -- not Reset_PDV_Non_Held's check at record
            --  entry -- is what actually mirrors a held variable's value into
            --  Temp_Symbols, and that only fires if HOLD is still "active"
            --  at the moment the LET runs. Root-caused by tracing Set_Hold /
            --  Reset_PDV_Non_Held live: the walker already dispatches a
            --  script's HOLD/UNHOLD pair once, immediately, before the first
            --  record ever runs (Execute's own deferred-kind exclusion list
            --  never listed HOLD/UNHOLD either) -- so a script that declares
            --  HOLD once *before* the loop and defers the per-group reset to
            --  an explicit "IF FIRST.group = 1 THEN LET var = 0" needs no
            --  per-record replay at all and produces byte-identical output.
            --  tests/sort_by.cmd was rewritten to that idiom rather than
            --  keeping HOLD/UNHOLD in this whitelist.
            --  Stmt_HELP (2026-08-13 re-audit PB-8): design.md §7.1,
            --  sdata-help.adb, and CLAUDE.md all already say Immediate: only
            --  this whitelist disagreed, silently re-printing the same HELP
            --  text once per record when HELP was left inside an open
            --  data-step body. No test exercises that (all help_*.cmd tests
            --  call HELP standalone, never inside REPEAT/RUN), so dropping it
            --  here is a pure bug fix, not a behavior trade-off like
            --  HOLD/UNHOLD's.
            --  Stmt_NAMES (PB-7): same shape as PB-8 -- design.md §7.1,
            --  sdata-help.adb, and CLAUDE.md all already say Immediate; only
            --  this whitelist silently re-fired it once per record. NAMES's
            --  own output happens at the moment it dispatches (like HELP) --
            --  it doesn't set state a later *deferred* statement reads -- so
            --  the walker's single top-to-bottom pre-scan already shows the
            --  right column list at each distinct textual position (e.g.
            --  before/after an interleaved RENAME) with no per-record
            --  redispatch needed. Confirmed via all 12 previously-passing
            --  tests using NAMES inside a data-step body: every failure after
            --  removing it here was pure duplicate output (the same block
            --  repeated once per record), never a position-dependent content
            --  difference -- see tests/rename_test.cmd, tests/column_mgmt.cmd.
            --
            --  Stmt_DIGITS (PB-6) looks identical on paper but is NOT safe to
            --  remove: unlike NAMES, DIGITS sets a precision that a *later
            --  deferred* PRINT reads when PRINT itself finally dispatches
            --  during the per-record pass. tests/digits_test.cmd interleaves
            --  DIGITS 5 / PRINT / DIGITS 2 / PRINT / DIGITS 8 / PRINT in one
            --  record body, expecting each PRINT to render at the precision
            --  set immediately before it. Without per-record replay, the
            --  walker's pre-scan collapses all three DIGITS calls to their
            --  final value (8) before the record even runs, and every PRINT
            --  renders at full precision instead. Confirmed by direct
            --  regression (make check) before this comment was written --
            --  DIGITS stays in this whitelist.
            --
            --  Stmt_ECHO (PB-5) was initially removed alongside HELP/NAMES on
            --  the assumption it was the same "prints for itself, nothing
            --  reads its state later" shape -- wrong, by the same mechanism
            --  as DIGITS: ECHO sets a console-output flag that a *later
            --  deferred* PRINT reads when PRINT itself dispatches. A scratch
            --  script (ECHO OFF / PRINT "a" / ECHO ON / PRINT "b", one
            --  record) proved it directly: with ECHO out of this whitelist,
            --  both PRINTs render, because the walker's pre-scan already
            --  collapsed OFF-then-ON to ON before the record ran. ECHO stays
            --  in this whitelist for the same reason DIGITS does. (design.md
            --  §7.1's "Immediate" label for both is still correct -- it
            --  describes how they're documented/used, not whether the engine
            --  can skip per-record redispatch; "Immediate" here means "takes
            --  effect at its position in program order," which for a
            --  statement written inside a repeated body means every record.)
            when Stmt_LET | Stmt_SET | Stmt_PRINT | Stmt_IF
               | Stmt_WHILE | Stmt_FOR | Stmt_LOOP_DO | Stmt_SELECT
               | Stmt_DELETE | Stmt_BREAK | Stmt_WRITE
               | Stmt_BY | Stmt_DIGITS | Stmt_ECHO =>
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