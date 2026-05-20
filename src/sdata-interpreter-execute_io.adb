--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Execute_IO (Stmt : Statement_Access) is
begin
   case Stmt.Kind is
      when Stmt_SUBMIT =>
         if SData_Core.Config.Disable_Submit then
            Put_Line_Error ("Error: SUBMIT command is disabled.");
         else
         declare
            Final : constant String := Full_Path (Stmt.File_Path (1 .. Stmt.File_Len), "SUBMIT");
         begin
            if Submit_Chain.Contains (Final) then
               raise Script_Error with "Recursive SUBMIT detected: " & Final;
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
                  Execute (Sub_Prog);
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