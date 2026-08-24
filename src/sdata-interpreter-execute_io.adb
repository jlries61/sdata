--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Execute_IO (Stmt : Statement_Access; Loop_Depth : Natural := 0) is
begin
   case Stmt.Kind is
      when Stmt_SUBMIT =>
         if SData_Core.Config.Disable_Submit then
            Put_Line_Error ("Error: SUBMIT command is disabled.");
         else
         declare
            Final : constant String := Full_Path (Stmt.File_Path (1 .. Stmt.File_Len), "SUBMIT");
            --  ADR-058: only the first loop-nested SUBMIT of a given file
            --  passes its real Loop_Depth through, so the submitted
            --  program's own declarative statements get ADR-056's warning
            --  once per file per session -- not once per invocation, which
            --  a re-parsed-every-call file would otherwise produce on every
            --  loop iteration.
            Effective_Loop_Depth : constant Natural :=
               (if Loop_Depth > 0 and then not Warned_Submit_Paths.Contains (Final)
                then Loop_Depth else 0);
            --  ADR-058: whether an error inside the submitted program was
            --  swallowed by Continue_On_Error (-k / REPL). Such an error
            --  never raises out of the Execute call below -- Execute's own
            --  per-statement dispatch loop catches it internally, at
            --  whatever nesting level it occurred -- so "Execute returned
            --  without raising" alone is not proof the submission actually
            --  ran cleanly. Detected via the ERR/ERL backing store
            --  (Execute_Record_Error) that both Continue_On_Error catch
            --  sites already write to on every swallowed error.
            Had_Internal_Error : Boolean := False;
         begin
            if Submit_Chain.Contains (Final) then
               raise Script_Error with "Recursive SUBMIT detected: " & Final;
            end if;
            if Natural (Submit_Chain.Length) >= Max_Submit_Depth then
               raise Script_Error with
                 "SUBMIT nesting too deep (depth limit"
                 & Max_Submit_Depth'Image & " exceeded): " & Final;
            end if;
            Submit_Chain.Insert (Final);
            declare
               type String_Access is access String;
               procedure Free_Buf is new Ada.Unchecked_Deallocation (String, String_Access);
               File     : Ada.Streams.Stream_IO.File_Type;
               Stream   : Ada.Streams.Stream_IO.Stream_Access;
               Contents : String_Access;  --  heap-allocated; avoids stack pressure
            begin
               Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Final);
               Contents := new String (1 .. Integer (Ada.Streams.Stream_IO.Size (File)));
               Stream := Ada.Streams.Stream_IO.Stream (File);
               String'Read (Stream, Contents.all);
               Ada.Streams.Stream_IO.Close (File);
               declare
                  Sub_Ctx  : Parser_Context;
                  Sub_Prog : Statement_Access;
               begin
                  Initialize (Sub_Ctx, Contents.all);
                  Sub_Prog := Parse_Program (Sub_Ctx);
                  Debug_Trace ("SUBMIT: entering "
                               & Stmt.File_Path (1 .. Stmt.File_Len), 1);
                  --  A SUBMIT sub-program is a self-contained statement stream:
                  --  its pending-deferred state must not perturb the caller's
                  --  (otherwise a sub-script's trailing RUN would clear, or its
                  --  un-run tail would inflate, the outer count that AGGREGATE's
                  --  #10 guard observes).  Snapshot and restore around it.
                  declare
                     Saved_Pending : constant Natural := Pending_Deferred;
                     Pre_Err_Code  : constant Natural :=
                        SData_Core.Config.Runtime.Last_Error_Code;
                     Pre_Err_Line  : constant Natural :=
                        SData_Core.Config.Runtime.Last_Error_Line;
                  begin
                     Execute (Sub_Prog, Effective_Loop_Depth);
                     Pending_Deferred := Saved_Pending;
                     Had_Internal_Error :=
                        SData_Core.Config.Runtime.Last_Error_Code /= Pre_Err_Code
                        or else SData_Core.Config.Runtime.Last_Error_Line /= Pre_Err_Line;
                  end;
                  SData.AST.Free_Program (Sub_Prog);
               end;
               Free_Buf (Contents);
            exception
               when Ada.Streams.Stream_IO.Name_Error =>
                  Free_Buf (Contents);
                  Submit_Chain.Delete (Final);
                  raise Script_Error with "SUBMIT: file not found: " & Final;
               when others =>
                  Free_Buf (Contents);
                  Submit_Chain.Delete (Final);
                  raise;
            end;
            --  ADR-058: only mark this path "warned" once the submission has
            --  actually completed without raising AND without an internal
            --  error swallowed by Continue_On_Error -- an earlier failed
            --  attempt (recursive SUBMIT, nesting-too-deep, file not found,
            --  a -k-swallowed error anywhere inside the submitted program,
            --  or any other error propagating out of Execute above) must
            --  not poison a later, legitimate first successful submission
            --  of the same path into being silently skipped.
            if Effective_Loop_Depth > 0 and then not Had_Internal_Error then
               Warned_Submit_Paths.Insert (Final);
            end if;
            Submit_Chain.Delete (Final);
         end;
         end if;
      when Stmt_SYSTEM =>
         if SData_Core.Config.Disable_Shell then
            Put_Line_Error ("Error: SYSTEM command is disabled.");
         else
            declare Success : Boolean;
            begin
               SData.System.Shell_Execute (Stmt.File_Path (1 .. Stmt.File_Len), Success);
            end;
         end if;
      when Stmt_OUTPUT =>
         SData_Core.Commands.Execute_OUTPUT
           (File_Name => (if Stmt.File_Len > 0
                          then Stmt.File_Path (1 .. Stmt.File_Len)
                          else ""),
            TXTFMT    => (if Stmt.Output_FMT_Len > 0
                          then Stmt.Output_FMT_Val (1 .. Stmt.Output_FMT_Len)
                          else ""),
            Charset   => (if Stmt.Output_CHARSET_Len > 0
                          then Stmt.Output_CHARSET_Val (1 .. Stmt.Output_CHARSET_Len)
                          else ""));
      when Stmt_FPATH =>
         SData_Core.Commands.Execute_FPATH
           (Path        => (if Stmt.File_Len > 0
                            then Stmt.File_Path (1 .. Stmt.File_Len)
                            else ""),
            Use_Flag    => Stmt.Use_Flag,
            Save_Flag   => Stmt.Save_Flag,
            Submit_Flag => Stmt.Submit_Flag,
            Output_Flag => Stmt.Output_Flag);
      when others => null;
   end case;
end Execute_IO;