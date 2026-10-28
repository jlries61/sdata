--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

--  SData Main Entry Point.
--  This procedure handles command-line argument parsing, reads the source command file,
--  invokes the parser to build the AST, and finally runs the interpreter.

with Ada.Text_IO;
with Ada.Text_IO.Unbounded_IO;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Strings.Fixed;
with Ada.Streams.Stream_IO;
with Ada.Unchecked_Deallocation;
with Ada.Exceptions; use Ada.Exceptions;
with SData.Parser; use SData.Parser;
with SData.AST; use SData.AST;
with SData.Version;

with SData.Interpreter; use SData.Interpreter;
with SData_Core.Commands;
with SData_Core.Config;         use SData_Core.Config;
with SData_Core.IO;          use SData_Core.IO;
with SData.System;
with SData_Core.Signals;
--  Withed so the top-level handlers can name the two coercion exceptions and
--  surface them as clean script errors rather than via `when others`.  These
--  paths are rare but NOT unreachable: e.g. a derived output column that is
--  missing on its first record then character later reaches Type_Mismatch_Error
--  through the PDV/output flush (sdata-core issue #24).  This guard turns such a
--  case into a clean script error; the underlying mismatch is separately fixed
--  in sdata-core (output-column type upgrade).  See SOFTWARE_STANDARDS_REVIEW §5.3.
with SData_Core.Table;
with SData_Core.Values;
pragma Unreferenced (SData_Core.Signals);

procedure SData_Main is

   --  Helper to read the entire contents of a file into a single String buffer.
   --  The buffer is heap-allocated to avoid placing large scripts on the stack.
   function Read_File (Filename : String) return String is separate;

   --  Displays available command-line options.
   procedure Print_Usage is separate;

   --  Runs the Interactive REPL.
   procedure Run_REPL is separate;

   --  Outcome of command-line argument parsing: whether SData_Main should
   --  continue into batch/REPL execution, or stop immediately. By the time
   --  Exit_Now comes back, Set_Exit_Status has already been called (if
   --  needed) inside Parse_Command_Line, at the same point the original
   --  inline loop's own `return;` would have fired -- Outcome only signals
   --  "stop," it doesn't duplicate "why."
   type Parse_Outcome is (Continue_Running, Exit_Now);

   --  The handful of values the argument-parsing loop used to set as
   --  SData_Main's own locals (as opposed to SData_Core.Config's global
   --  option state, which Parse_Command_Line still mutates directly, same
   --  as the loop it replaces).
   type Parsed_Args is record
      Outcome                : Parse_Outcome := Continue_Running;
      Filename               : String (1 .. SData.Max_Path_Len);
      Filename_Len           : Natural := 0;
      Pager_Cmd              : Unbounded_String := Null_Unbounded_String;
      Shell_Timeout_Explicit : Boolean := False;
   end record;

   function Parse_Command_Line return Parsed_Args is separate;

   Ctx  : Parser_Context;
   Prog : Statement_Access;
   Args : Parsed_Args;
begin
   --  Enforce --noshell and --nosubmit when running as root / SYSTEM.
   --  Done first so the restriction applies regardless of how sdata is invoked.
   if SData.System.Running_As_System_Account then
      if not Disable_Shell or else not Disable_Submit then
         Put_Line_Error ("Warning: Running as root/SYSTEM; "
                         & "--noshell and --nosubmit enforced.");
      end if;
      Disable_Shell  := True;
      Disable_Submit := True;
   end if;

   --  Initial argument check.
   if Argument_Count = 0 then
      Run_REPL;
      return;
   end if;

   Args := Parse_Command_Line;
   if Args.Outcome = Exit_Now then
      return;
   end if;

   --  Set shell-timeout default: 300 s for batch, 0 for interactive.
   --  Only applies when --shell-timeout=N was not given explicitly.
   if not Args.Shell_Timeout_Explicit and then Args.Filename_Len > 0 then
      SData_Core.Config.Shell_Timeout_Default := 300;
   end if;
   SData_Core.Commands.Execute_OPTIONS_Shell_Timeout
      (SData_Core.Config.Shell_Timeout_Default);

   --  Validate -p / --noshell interaction.
   if Length (Args.Pager_Cmd) > 0 and then Disable_Shell then
      Put_Line_Error ("Error: --noshell disables external process execution; "
                      & "-p cannot be used with --noshell");
      Set_Exit_Status (Failure);
      return;
   end if;

   --  Activate external pager (interactive mode only; ignored for batch scripts).
   if Length (Args.Pager_Cmd) > 0 and then Args.Filename_Len = 0 then
      begin
         SData_Core.IO.Set_Pager (To_String (Args.Pager_Cmd));
      exception
         when E : SData_Core.IO.Pager_Not_Found =>
            Put_Line_Error ("Error: " & Exception_Message (E));
            Set_Exit_Status (Failure);
            return;
      end;
   end if;

   --  Handle output redirection if specified on command line.
   if Output_File_Len > 0 then
      SData_Core.IO.Open_Output (Output_File (1 .. Output_File_Len));
   end if;

   --  Verify that a command file was provided.
   if Input_File_Len > 0 then
      declare
         Stmt : Statement_Access := new Statement (Stmt_USE);
      begin
         Stmt.File_Path (1 .. Input_File_Len) := Input_File_Path (1 .. Input_File_Len);
         Stmt.File_Len := Input_File_Len;
         SData.Interpreter.Execute (Stmt);
         SData.AST.Free_Program (Stmt);
      end;
   end if;

   --  Verify if an output dataset was provided via -s.
   if Output_Dataset_Len > 0 then
      declare
         Stmt : Statement_Access := new Statement (Stmt_SAVE);
      begin
         Stmt.File_Path (1 .. Output_Dataset_Len) := Output_Dataset_Path (1 .. Output_Dataset_Len);
         Stmt.File_Len := Output_Dataset_Len;
         SData.Interpreter.Execute (Stmt);
         SData.AST.Free_Program (Stmt);
      end;
   end if;

   if Args.Filename_Len = 0 then
      Run_REPL;
      return;
   end if;

   --  MAIN EXECUTION FLOW.
   declare
      -- 1. Read the command file into memory.
      Source : constant String := Read_File (Args.Filename (1 .. Args.Filename_Len));
   begin
      -- 2. Initialize the parser.
      Initialize (Ctx, Source);

      -- 3. Parse the source into an AST program (linked list of statements).
      Prog := Parse_Program (Ctx);
      
      -- 4. Execute the program using the interpreter.
      Execute (Prog);

      -- 5. Free the AST now that execution is complete.
      SData.AST.Free_Program (Prog);
   end;

   if SData_Core.IO.Is_Redirected then
      SData_Core.IO.Close_Output;
   end if;

exception
   when SData.Parser.Incomplete_Statement =>
      Put_Line_Error ("Error: incomplete block at end of script"
                      & " (missing END SELECT, END IF, NEXT, or WEND?)");
      Set_Exit_Status (Failure);
   when E : SData.Script_Error | SData_Core.Script_Error
          | SData_Core.Table.Type_Mismatch_Error
          | SData_Core.Values.Conversion_Error =>
      Put_Line_Error ("Error: " & Exception_Message (E));
      Set_Exit_Status (Failure);
   when E : Constraint_Error =>
      --  A runtime check failure from a number that does not fit; the Ada
      --  file:line text means nothing to the user (F18, F33).
      Put_Line_Error ("Error: " & SData.Interpreter.Friendly_Message (E));
      Set_Exit_Status (Failure);
   when E : others =>
      Put_Line_Error ("An error occurred: " & Exception_Name (E) & ": " & Exception_Message (E));
      Set_Exit_Status (Failure);
end SData_Main;