--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData_Main)
function Parse_Command_Line return Parsed_Args is
   Result : Parsed_Args;
   Idx    : Positive := 1;
begin
   --  Manual command-line argument parsing loop.
   while Idx <= Argument_Count loop
      declare
         Arg : constant String := Argument (Idx);
      begin
         if Arg = "-h" or Arg = "--help" then
            Print_Usage;
            Result.Outcome := Exit_Now;
            return Result;
         elsif Arg = "-v" or Arg = "--version" then
            Put_Line ("SData version " & SData.Version.Version_Str);
            Result.Outcome := Exit_Now;
            return Result;
         elsif Arg = "--copyright" then
            Ada.Text_IO.Put_Line (SData.Version.Copyright_Notice);
            Result.Outcome := Exit_Now;
            return Result;
         elsif Arg = "-q" then
            Set_Local_Echo (False);
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
                     Result.Outcome := Exit_Now;
                     return Result;
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
                     Result.Outcome := Exit_Now;
                     return Result;
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
                     Result.Outcome := Exit_Now;
                     return Result;
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
                     Result.Outcome := Exit_Now;
                     return Result;
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
                     Result.Outcome := Exit_Now;
                     return Result;
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
                     Result.Outcome := Exit_Now;
                     return Result;
               end;
            end if;
         elsif Arg'Length > 7 and then Arg (1 .. 7) = "--clen=" then
            begin
               Max_String_Len := Natural'Value (Arg (8 .. Arg'Last));
            exception
               when Constraint_Error =>
                  Put_Line_Error ("Error: argument to --clen must be a non-negative integer");
                  Set_Exit_Status (Failure);
                  Result.Outcome := Exit_Now;
                  return Result;
            end;
         elsif Arg'Length > 16 and then Arg (1 .. 16) = "--shell-timeout=" then
            begin
               SData_Core.Config.Shell_Timeout_Default :=
                  Natural'Value (Arg (17 .. Arg'Last));
               Result.Shell_Timeout_Explicit := True;
            exception
               when Constraint_Error =>
                  Put_Line_Error ("Error: argument to --shell-timeout must be a non-negative integer");
                  Set_Exit_Status (Failure);
                  Result.Outcome := Exit_Now;
                  return Result;
            end;
         elsif Arg = "-p" then
            if Idx < Argument_Count then
               Idx := Idx + 1;
               Result.Pager_Cmd := To_Unbounded_String (Argument (Idx));
            else
               Put_Line_Error ("Error: -p requires a pager command argument");
               Set_Exit_Status (Failure);
               Result.Outcome := Exit_Now;
               return Result;
            end if;
         elsif Arg = "--noshell" then
            Disable_Shell := True;
         elsif Arg = "--nosubmit" then
            Disable_Submit := True;
         elsif Arg = "--ignore-math-errors" then
            Ignore_Math_Errors := True;
         elsif Arg = "--progress" then
            Progress := True;
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
                  Result.Outcome := Exit_Now;
                  return Result;
            end;
         elsif Arg = "-k" or else Arg = "--continue-on-error" then
            Continue_On_Error := True;
         elsif Arg'Length > 0 and then Arg (1) /= '-' then
            -- This is the main command file to execute.
            if Arg'Length > Result.Filename'Length then
               Put_Line_Error ("Error: filename is too long (max"
                               & Result.Filename'Length'Image & " characters)");
               Set_Exit_Status (Failure);
               Result.Outcome := Exit_Now;
               return Result;
            end if;
            Result.Filename (1 .. Arg'Length) := Arg;
            Result.Filename_Len := Arg'Length;
            
            --  AUTO-DETECT FORMAT based on the extension of the command file itself.
            declare
               Ext_Idx : Natural := 0;
            begin
               for J in reverse 1 .. Result.Filename_Len loop
                  if Result.Filename (J) = '.' then
                     Ext_Idx := J;
                     exit;
                  end if;
               end loop;
               if Ext_Idx > 0 then
                  declare
                     Ext : constant String := Result.Filename (Ext_Idx + 1 .. Result.Filename_Len);
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

   return Result;
end Parse_Command_Line;
