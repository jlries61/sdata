--  SData Main Entry Point.
--  This procedure handles command-line argument parsing, reads the source command file,
--  invokes the parser to build the AST, and finally runs the interpreter.

with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Streams.Stream_IO;
with Ada.Exceptions; use Ada.Exceptions;
with SData.Parser; use SData.Parser;
with SData.AST; use SData.AST;

with SData.Interpreter; use SData.Interpreter;
with SData.Config; use SData.Config;

procedure SData_Main is
   
   --  Helper to read the entire contents of a file into a single String buffer.
   function Read_File (Filename : String) return String is
      File : Ada.Streams.Stream_IO.File_Type;
      Stream : Ada.Streams.Stream_IO.Stream_Access;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Filename);
      Stream := Ada.Streams.Stream_IO.Stream (File);
      declare
         -- Create a string of the exact size needed.
         Result : String (1 .. Integer (Ada.Streams.Stream_IO.Size (File)));
      begin
         String'Read (Stream, Result);
         Ada.Streams.Stream_IO.Close (File);
         return Result;
      end;
   end Read_File;

   --  Displays available command-line options.
   procedure Print_Usage is
   begin
      Put_Line ("Usage: sdata_main [options] [filename]");
      Put_Line ("Options:");
      Put_Line ("  -h, --help    Show this help message");
      Put_Line ("  -v, --version Show version information");
      Put_Line ("  -m <size>     Set max in-memory table size");
      Put_Line ("  -t <count>    Set max temporary variables");
      Put_Line ("  --clen <len>  Set max character variable length");
      Put_Line ("  --noshell     Disable SHELL command and function");
      Put_Line ("  -u, --infmt   Input dataset and format");
      Put_Line ("  -s, --outfmt  Output dataset and format");
      Put_Line ("  -o <file>     Console output file");
      Put_Line ("  -q            Suppress console output (Quiet Mode)");
      Put_Line ("  -t            Max temporary variable memory (not yet implemented)");
      Put_Line ("  -p            Pager specification (not yet implemented)");
   end Print_Usage;

   --  Runs the Interactive REPL.
   procedure Run_REPL is
      Line : String (1 .. 16384);
      Last : Natural;
      Ctx  : Parser_Context;
      Prog : Statement_Access;
   begin
      Set_Interactive (True);
      Put_Line ("SData Statistical Interpreter version " & SData.Config.Version_Str);
      Put_Line ("Interactive Console. Type QUIT to exit.");
      REPL : loop
         Put ("sdata> ");
         Flush;
         begin
            Get_Line (Line, Last);
            if Last > 0 then
               Initialize (Ctx, Line (1 .. Last));
               Prog := Parse_Program (Ctx);

               while Prog /= null loop
                  declare
                     Is_Declarative : constant Boolean :=
                        Prog.Kind in Stmt_USE | Stmt_SAVE | Stmt_KEEP | Stmt_DROP |
                                     Stmt_RENAME | Stmt_NAMES | Stmt_RUN | Stmt_QUIT | Stmt_END |
                                     Stmt_HOLD | Stmt_UNHOLD | Stmt_ARRAY | Stmt_DIM | Stmt_REPEAT | Stmt_NEW |
                                     Stmt_DIGITS | Stmt_HELP | Stmt_OUTPUT;
                  begin
                     if Is_Declarative then
                        if Prog.Kind = Stmt_RUN then
                           Run_Active_Program;
                        elsif Prog.Kind = Stmt_QUIT or else Prog.Kind = Stmt_END then
                           exit REPL;
                        else
                           Execute (Prog);
                        end if;
                     else
                        -- Deferred statements are queued until RUN.
                        Add_To_Active_Program (Prog);
                     end if;
                  end;
                  Prog := Prog.Next;
               end loop;
            end if;
         exception
            when End_Error =>
               New_Line;
               exit REPL;
            when E : others =>
               Put_Line ("Error: " & Exception_Message (E));
         end;
         exit REPL when not Is_Open (Standard_Input);
      end loop REPL;
   end Run_REPL;

   Ctx      : Parser_Context;
   Prog     : Statement_Access;
   Filename : String (1 .. 1024);
   Filename_Len : Natural := 0;
   Idx      : Positive := 1;
begin
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
                  Output_File (1 .. Val'Length) := Val;
                  Output_File_Len := Val'Length;
               end;
            end if;
         elsif Arg = "-u" or Arg = "--infmt" then
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
         elsif Arg = "-s" or Arg = "--outfmt" then
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
         elsif Arg = "-m" then
            if Idx < Argument_Count then
               Idx := Idx + 1;
               Max_Table_Rows := Natural'Value (Argument (Idx));
            end if;
         elsif Arg = "-t" then
            if Idx < Argument_Count then
               Idx := Idx + 1;
               Max_Temp_Vars := Natural'Value (Argument (Idx));
            end if;
         elsif Arg = "--clen" then
            if Idx < Argument_Count then
               Idx := Idx + 1;
               Max_String_Len := Natural'Value (Argument (Idx));
            end if;
         elsif Arg = "--noshell" then
            Disable_Shell := True;
         elsif Arg(1) /= '-' then
            -- This is the main command file to execute.
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

   --  Verify that a command file was provided.
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
   end;

exception
   -- Catch all exceptions and provide detailed error reporting.
   when E : others =>
      Put_Line ("An error occurred: " & Exception_Name (E) & ": " & Exception_Message (E));
end SData_Main;
