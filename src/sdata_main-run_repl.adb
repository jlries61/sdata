--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData_Main)
--  Runs the Interactive REPL.
procedure Run_REPL is
   Line   : Unbounded_String;
   Ctx    : Parser_Context;
   Prog   : Statement_Access;
   Buffer : Unbounded_String;
begin
   SData_Core.IO.Set_Interactive (True);
   --  Print the banner directly (bypasses pager buffer — it should
   --  always appear immediately, not be held until the first command).
   Ada.Text_IO.Put_Line ("SData Statistical Interpreter version "
                         & SData.Version.Version_Str);
   Ada.Text_IO.Put_Line (SData.Version.Copyright_Str
                         & ". License GPLv3+. Run 'sdata --copyright' for details.");
   Ada.Text_IO.Put_Line ("Interactive Console. Type QUIT to exit.");
   Buffer := Null_Unbounded_String;
   REPL : loop
      --  ADR-081: end an unfinished PRINT/NOTE line (one ending in a
      --  semicolon) so the prompt starts on a fresh line.
      SData.Interpreter.Finish_Print_Line;
      SData_Core.IO.Flush_Pager_Buffer;
      if Length (Buffer) = 0 then
         Ada.Text_IO.Put ("sdata> ");
      else
         Ada.Text_IO.Put ("..> ");
      end if;
      Ada.Text_IO.Flush;
      begin
         Ada.Text_IO.Unbounded_IO.Get_Line (Line);

         --  Statement Echo (design.md §6.3): echo the raw input line back
         --  unconditionally -- not gated by Local_Echo -- so a
         --  piped/non-tty session shows the same transcript a real
         --  terminal's own canonical-mode echo would produce.  Placed
         --  before Append/Parse_Program so it fires even if this line
         --  turns out to be part of a statement that never successfully
         --  parses; design.md's "even if console output is disabled"
         --  wording carries no carve-out for that case (see ADR-061).
         Ada.Text_IO.Unbounded_IO.Put_Line (Line);

         Append (Buffer, Line & ASCII.LF);

         Initialize (Ctx, To_String (Buffer));

         begin
            Prog := Parse_Program (Ctx);

            --  A statement ending with a comma continues on the next
            --  line (design spec).  If the buffer ended on such a
            --  dangling continuation, keep buffering and prompt for the
            --  rest rather than running a half-finished statement.
            if Ended_With_Continuation (Ctx) then
               --  Discard the half-parsed program; the full buffer is
               --  re-parsed once the continuation line arrives.
               SData.AST.Free_Program (Prog);
               raise SData.Parser.Incomplete_Statement;
            end if;

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
                           SData_Core.IO.Flush_Pager_Buffer;
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
            SData_Core.IO.Flush_Pager_Buffer;

         exception
            when SData.Parser.Incomplete_Statement =>
               --  Keep buffer as is; wait for more input — do not flush.
               null;
         end;

      exception
         when Ada.Text_IO.End_Error =>
            SData_Core.IO.Flush_Pager_Buffer;
            Ada.Text_IO.New_Line;
            exit REPL;
         when E : SData.Script_Error | SData_Core.Script_Error
                | SData_Core.Table.Type_Mismatch_Error
                | SData_Core.Values.Conversion_Error =>
            Put_Line_Error ("Error: " & Exception_Message (E));
            Buffer := Null_Unbounded_String;
            SData_Core.IO.Flush_Pager_Buffer;
         when E : others =>
            Put_Line_Error ("Internal error: " & Exception_Name (E) & ": " & Exception_Message (E));
            Buffer := Null_Unbounded_String;
            SData_Core.IO.Flush_Pager_Buffer;
      end;
      exit REPL when not Ada.Text_IO.Is_Open (Ada.Text_IO.Standard_Input);
   end loop REPL;
end Run_REPL;
