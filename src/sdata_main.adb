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

with SData.Interpreter; use SData.Interpreter;
with SData.Config;         use SData.Config;
with SData.Config.Runtime;
with SData.IO;          use SData.IO;
with SData.System;
with SData.Signals;
pragma Unreferenced (SData.Signals);

procedure SData_Main is
   
   --  Helper to read the entire contents of a file into a single String buffer.
   --  The buffer is heap-allocated to avoid placing large scripts on the stack.
   function Read_File (Filename : String) return String is
      type String_Access is access String;
      procedure Free_Buf is new Ada.Unchecked_Deallocation (String, String_Access);
      File   : Ada.Streams.Stream_IO.File_Type;
      Stream : Ada.Streams.Stream_IO.Stream_Access;
   begin
      begin
         Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Filename);
      exception
         when Ada.Streams.Stream_IO.Name_Error =>
            raise SData.Script_Error with "cannot open """ & Filename & """: file not found";
         when Ada.Streams.Stream_IO.Use_Error =>
            raise SData.Script_Error with "cannot open """ & Filename & """: permission denied";
      end;
      declare
         Size : constant Ada.Streams.Stream_IO.Count := Ada.Streams.Stream_IO.Size (File);
      begin
         if Integer (Size) = 0 then
            Ada.Streams.Stream_IO.Close (File);
            return "";
         end if;
         Stream := Ada.Streams.Stream_IO.Stream (File);
         declare
            Buf : String_Access := new String (1 .. Integer (Size));
         begin
            String'Read (Stream, Buf.all);
            Ada.Streams.Stream_IO.Close (File);
            declare
               Ret : constant String := Buf.all;  --  copy; Buf can now be freed
            begin
               Free_Buf (Buf);
               return Ret;
            end;
         end;
      end;
   end Read_File;

   --  Displays available command-line options.
   procedure Print_Usage is
   begin
      Put_Line ("Usage: sdata [options] [filename]");
      Put_Line ("Options:");
      Put_Line ("  -h, --help    Show this help message");
      Put_Line ("  -v, --version Show version information");
      Put_Line ("  -m <cells>    Set max in-memory table cells (rows*cols; 0 = unlimited)");
      Put_Line ("  -t <count>    Set max temporary variables");
      Put_Line ("  --clen <len>  Set max character variable length");
      Put_Line ("  --shell-timeout=N        SYSTEM/SHELL timeout in seconds (0=unlimited; default 300 in batch)");
      Put_Line ("  --noshell                Disable SHELL command and function");
      Put_Line ("  --nosubmit               Disable SUBMIT command");
      Put_Line ("  -k, --continue-on-error  Continue executing after a statement error");
      Put_Line ("  --ignore-math-errors     Math domain errors return MISSING instead of halting");
      Put_Line ("  -u, --infmt              Input dataset and format");
      Put_Line ("  -s, --outfmt             Output dataset and format");
      Put_Line ("  -o <file>                Console output file");
      Put_Line ("  -q                       Suppress console output (Quiet Mode)");
      Put_Line ("  -p <pager>               External pager command for interactive output");
      Put_Line ("                           (e.g. ""less -F"", ""more""); ignored in batch mode;");
      Put_Line ("                           incompatible with --noshell");
      Put_Line ("  --debug[=N]              Trace execution to stderr");
      Put_Line ("                           1=I/O only  2=+record/flow  3=+assignments (default 3)");
   end Print_Usage;

   --  Runs the Interactive REPL.
   procedure Run_REPL is
      Line   : Unbounded_String;
      Ctx    : Parser_Context;
      Prog   : Statement_Access;
      Buffer : Unbounded_String;
   begin
      SData.IO.Set_Interactive (True);
      --  Print the banner directly (bypasses pager buffer — it should
      --  always appear immediately, not be held until the first command).
      Ada.Text_IO.Put_Line ("SData Statistical Interpreter version "
                            & SData.Config.Version_Str);
      Ada.Text_IO.Put_Line (SData.Config.Copyright_Str
                            & ". License GPLv3+. Run 'sdata --copyright' for details.");
      Ada.Text_IO.Put_Line ("Interactive Console. Type QUIT to exit.");
      Buffer := Null_Unbounded_String;
      REPL : loop
         if Length (Buffer) = 0 then
            Ada.Text_IO.Put ("sdata> ");
         else
            Ada.Text_IO.Put ("..> ");
         end if;
         Ada.Text_IO.Flush;
         begin
            Ada.Text_IO.Unbounded_IO.Get_Line (Line);
            Append (Buffer, Line & ASCII.LF);

            Initialize (Ctx, To_String (Buffer));

            begin
               Prog := Parse_Program (Ctx);

               --  Save source for program buffer display before clearing.
               declare
                  Source_Text : constant String := Ada.Strings.Fixed.Trim
                    (To_String (Buffer), Ada.Strings.Right);
               begin
                  -- If parsing succeeded, we can clear the buffer.
                  Buffer := Null_Unbounded_String;

                  while Prog /= null loop
                     begin
                        if Is_Immediate (Prog.Kind) then
                           if Prog.Kind = Stmt_RUN then
                              Run_Active_Program;
                           elsif Prog.Kind = Stmt_QUIT or else Prog.Kind = Stmt_END then
                              SData.IO.Flush_Pager_Buffer;
                              exit REPL;
                           else
                              Execute (Prog);
                           end if;
                        else
                           --  Deferred statements are queued until RUN.
                           Add_To_Active_Program (Prog, Source_Text);
                        end if;
                     end;
                     Prog := Prog.Next;
                  end loop;
               end;
               SData.IO.Flush_Pager_Buffer;

            exception
               when SData.Parser.Incomplete_Statement =>
                  --  Keep buffer as is; wait for more input — do not flush.
                  null;
            end;

         exception
            when Ada.Text_IO.End_Error =>
               SData.IO.Flush_Pager_Buffer;
               Ada.Text_IO.New_Line;
               exit REPL;
            when E : SData.Script_Error =>
               Put_Line_Error ("Error: " & Exception_Message (E));
               Buffer := Null_Unbounded_String;
               SData.IO.Flush_Pager_Buffer;
            when E : others =>
               Put_Line_Error ("Internal error: " & Exception_Name (E) & ": " & Exception_Message (E));
               Buffer := Null_Unbounded_String;
               SData.IO.Flush_Pager_Buffer;
         end;
         exit REPL when not Ada.Text_IO.Is_Open (Ada.Text_IO.Standard_Input);
      end loop REPL;
   end Run_REPL;

   Ctx                    : Parser_Context;
   Prog                   : Statement_Access;
   Filename               : String (1 .. SData.Max_Path_Len);
   Filename_Len           : Natural := 0;
   Idx                    : Positive := 1;
   Pager_Cmd              : Unbounded_String := Null_Unbounded_String;
   Shell_Timeout_Explicit : Boolean := False;
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

   --  Manual command-line argument parsing loop.
   while Idx <= Argument_Count loop
      declare
         Arg : constant String := Argument (Idx);
      begin
         if Arg = "-h" or Arg = "--help" then
            Print_Usage;
            return;
         elsif Arg = "-v" or Arg = "--version" then
            Put_Line ("SData version " & Version_Str);
            return;
         elsif Arg = "-q" then
            Quiet_Mode := True;
         elsif Arg = "-o" then
            -- Handle output file redirection.
            if Idx < Argument_Count then
               Idx := Idx + 1;
               declare
                  Val : constant String := Argument (Idx);
               begin
                  if Val'Length > Output_File'Length then
                     Put_Line_Error ("Error: argument to -o is too long (max"
                                     & Output_File'Length'Image & " characters)");
                     Set_Exit_Status (Failure);
                     return;
                  end if;
                  Output_File (1 .. Val'Length) := Val;
                  Output_File_Len := Val'Length;
               end;
            end if;
         elsif Arg = "-u" then
            if Idx < Argument_Count then
               Idx := Idx + 1;
               declare
                  Val : constant String := Argument (Idx);
               begin
                  if Val'Length > Input_File_Path'Length then
                     Put_Line_Error ("Error: argument to -u is too long (max"
                                     & Input_File_Path'Length'Image & " characters)");
                     Set_Exit_Status (Failure);
                     return;
                  end if;
                  Input_File_Path (1 .. Val'Length) := Val;
                  Input_File_Len := Val'Length;
               end;
            end if;
         elsif Arg = "--infmt" then
            -- Set the global input format.
            if Idx < Argument_Count then
               Idx := Idx + 1;
               declare
                  Val : constant String := Argument (Idx);
               begin
                  if Val = "csv" then Input_Format := CSV;
                  elsif Val = "ods" or Val = "odf" then Input_Format := ODF;
                  elsif Val = "xlsx" or Val = "ooxml" then Input_Format := OOXML;
                  end if;
               end;
            end if;
         elsif Arg'Length > 8 and then Arg (1 .. 8) = "--infmt=" then
            declare
               Val : constant String := Arg (9 .. Arg'Last);
            begin
               if Val = "csv" then Input_Format := CSV;
               elsif Val = "ods" or Val = "odf" then Input_Format := ODF;
               elsif Val = "xlsx" or Val = "ooxml" then Input_Format := OOXML;
               end if;
            end;
         elsif Arg = "-s" then
            if Idx < Argument_Count then
               Idx := Idx + 1;
               declare
                  Val : constant String := Argument (Idx);
               begin
                  if Val'Length > Output_Dataset_Path'Length then
                     Put_Line_Error ("Error: argument to -s is too long (max"
                                     & Output_Dataset_Path'Length'Image & " characters)");
                     Set_Exit_Status (Failure);
                     return;
                  end if;
                  Output_Dataset_Path (1 .. Val'Length) := Val;
                  Output_Dataset_Len := Val'Length;
               end;
            end if;
         elsif Arg = "--outfmt" then
            -- Set the global output format.
            if Idx < Argument_Count then
               Idx := Idx + 1;
               declare
                  Val : constant String := Argument (Idx);
               begin
                  if Val = "csv" then Output_Format := CSV;
                  elsif Val = "ods" or Val = "odf" then Output_Format := ODF;
                  elsif Val = "xlsx" or Val = "ooxml" then Output_Format := OOXML;
                  end if;
               end;
            end if;
         elsif Arg'Length > 9 and then Arg (1 .. 9) = "--outfmt=" then
            declare
               Val : constant String := Arg (10 .. Arg'Last);
            begin
               if Val = "csv" then Output_Format := CSV;
               elsif Val = "ods" or Val = "odf" then Output_Format := ODF;
               elsif Val = "xlsx" or Val = "ooxml" then Output_Format := OOXML;
               end if;
            end;
         elsif Arg = "-m" then
            if Idx < Argument_Count then
               Idx := Idx + 1;
               begin
                  Max_Table_Cells := Natural'Value (Argument (Idx));
               exception
                  when Constraint_Error =>
                     Put_Line_Error ("Error: argument to -m must be a non-negative integer");
                     Set_Exit_Status (Failure);
                     return;
               end;
            end if;
         elsif Arg = "-t" then
            if Idx < Argument_Count then
               Idx := Idx + 1;
               begin
                  Max_Temp_Vars := Natural'Value (Argument (Idx));
               exception
                  when Constraint_Error =>
                     Put_Line_Error ("Error: argument to -t must be a non-negative integer");
                     Set_Exit_Status (Failure);
                     return;
               end;
            end if;
         elsif Arg = "--clen" then
            if Idx < Argument_Count then
               Idx := Idx + 1;
               begin
                  Max_String_Len := Natural'Value (Argument (Idx));
               exception
                  when Constraint_Error =>
                     Put_Line_Error ("Error: argument to --clen must be a non-negative integer");
                     Set_Exit_Status (Failure);
                     return;
               end;
            end if;
         elsif Arg'Length > 7 and then Arg (1 .. 7) = "--clen=" then
            begin
               Max_String_Len := Natural'Value (Arg (8 .. Arg'Last));
            exception
               when Constraint_Error =>
                  Put_Line_Error ("Error: argument to --clen must be a non-negative integer");
                  Set_Exit_Status (Failure);
                  return;
            end;
         elsif Arg'Length > 16 and then Arg (1 .. 16) = "--shell-timeout=" then
            begin
               SData.Config.Shell_Timeout_Default :=
                  Natural'Value (Arg (17 .. Arg'Last));
               Shell_Timeout_Explicit := True;
            exception
               when Constraint_Error =>
                  Put_Line_Error ("Error: argument to --shell-timeout must be a non-negative integer");
                  Set_Exit_Status (Failure);
                  return;
            end;
         elsif Arg = "-p" then
            if Idx < Argument_Count then
               Idx := Idx + 1;
               Pager_Cmd := To_Unbounded_String (Argument (Idx));
            else
               Put_Line_Error ("Error: -p requires a pager command argument");
               Set_Exit_Status (Failure);
               return;
            end if;
         elsif Arg = "--noshell" then
            Disable_Shell := True;
         elsif Arg = "--nosubmit" then
            Disable_Submit := True;
         elsif Arg = "--ignore-math-errors" then
            Ignore_Math_Errors := True;
         elsif Arg = "--debug" then
            Debug_Level := 3;
         elsif Arg'Length > 8
            and then Arg (Arg'First .. Arg'First + 7) = "--debug="
         then
            declare
               Level_Str : constant String :=
                  Arg (Arg'First + 8 .. Arg'Last);
               N         : Natural;
            begin
               N := Natural'Value (Level_Str);
               if N > 3 then
                  Put_Line_Error ("Warning: --debug level" & N'Image
                                  & " exceeds maximum (3); using 3");
                  Debug_Level := 3;
               else
                  Debug_Level := N;
               end if;
            exception
               when Constraint_Error =>
                  Put_Line_Error ("Error: argument to --debug must be"
                                  & " 0, 1, 2, or 3");
                  Set_Exit_Status (Failure);
                  return;
            end;
         elsif Arg = "-k" or else Arg = "--continue-on-error" then
            Continue_On_Error := True;
         elsif Arg'Length > 0 and then Arg (1) /= '-' then
            -- This is the main command file to execute.
            if Arg'Length > Filename'Length then
               Put_Line_Error ("Error: filename is too long (max"
                               & Filename'Length'Image & " characters)");
               Set_Exit_Status (Failure);
               return;
            end if;
            Filename (1 .. Arg'Length) := Arg;
            Filename_Len := Arg'Length;
            
            --  AUTO-DETECT FORMAT based on the extension of the command file itself.
            declare
               Ext_Idx : Natural := 0;
            begin
               for J in reverse 1 .. Filename_Len loop
                  if Filename (J) = '.' then
                     Ext_Idx := J;
                     exit;
                  end if;
               end loop;
               if Ext_Idx > 0 then
                  declare
                     Ext : constant String := Filename (Ext_Idx + 1 .. Filename_Len);
                  begin
                     if Ext = "csv" then Input_Format := CSV; Output_Format := CSV;
                     elsif Ext = "ods" or Ext = "odf" then Input_Format := ODF; Output_Format := ODF;
                     elsif Ext = "xlsx" or Ext = "ooxml" then Input_Format := OOXML; Output_Format := OOXML;
                     end if;
                  end;
               end if;
            end;
         end if;
      end;
      Idx := Idx + 1;
   end loop;

   --  Set shell-timeout default: 300 s for batch, 0 for interactive.
   --  Only applies when --shell-timeout=N was not given explicitly.
   if not Shell_Timeout_Explicit and then Filename_Len > 0 then
      SData.Config.Shell_Timeout_Default := 300;
   end if;
   SData.Config.Runtime.Options_Shell_Timeout :=
      SData.Config.Shell_Timeout_Default;

   --  Validate -p / --noshell interaction.
   if Length (Pager_Cmd) > 0 and then Disable_Shell then
      Put_Line_Error ("Error: --noshell disables external process execution; "
                      & "-p cannot be used with --noshell");
      Set_Exit_Status (Failure);
      return;
   end if;

   --  Activate external pager (interactive mode only; ignored for batch scripts).
   if Length (Pager_Cmd) > 0 and then Filename_Len = 0 then
      begin
         SData.IO.Set_Pager (To_String (Pager_Cmd));
      exception
         when E : SData.IO.Pager_Not_Found =>
            Put_Line_Error ("Error: " & Exception_Message (E));
            Set_Exit_Status (Failure);
            return;
      end;
   end if;

   --  Handle output redirection if specified on command line.
   if Output_File_Len > 0 then
      SData.IO.Open_Output (Output_File (1 .. Output_File_Len));
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

   if Filename_Len = 0 then
      Run_REPL;
      return;
   end if;

   --  MAIN EXECUTION FLOW.
   declare
      -- 1. Read the command file into memory.
      Source : constant String := Read_File (Filename (1 .. Filename_Len));
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

   if SData.IO.Is_Redirected then
      SData.IO.Close_Output;
   end if;

exception
   when SData.Parser.Incomplete_Statement =>
      Put_Line_Error ("Error: incomplete block at end of script"
                      & " (missing END SELECT, END IF, NEXT, or WEND?)");
      Set_Exit_Status (Failure);
   when E : SData.Script_Error =>
      Put_Line_Error ("Error: " & Exception_Message (E));
      Set_Exit_Status (Failure);
   when E : others =>
      Put_Line_Error ("An error occurred: " & Exception_Name (E) & ": " & Exception_Message (E));
      Set_Exit_Status (Failure);
end SData_Main;
