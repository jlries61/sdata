--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

--  SData parser fuzz driver.
--
--  Reads an arbitrary SData script from stdin, passes it through the lexer
--  and recursive-descent parser, and exits cleanly.  The interpreter is
--  intentionally NOT invoked, so shell commands, file writes, and other
--  side-effecting statements are never executed.
--
--  Expected exceptions (Incomplete_Statement for truncated multi-line
--  constructs, Script_Error for invalid syntax) are caught and silenced.
--  Unexpected exceptions (Constraint_Error, Program_Error, Storage_Error)
--  propagate uncaught so that AFL++ or a crash-regression harness detects them.
--
--  AFL++ usage:
--    afl-fuzz -i tests/fuzz_corpus/script -o fuzz_out/script \
--             -- ./bin/parser_fuzz_driver
--
--  Corpus regression (no AFL++ required):
--    make fuzz-corpus

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with SData.Parser;
with SData.AST;

procedure Parser_Fuzz_Driver is

   function Read_Stdin return String is
      Buf  : Unbounded_String;
      Line : String (1 .. 65_536);
      Last : Natural;
   begin
      loop
         Get_Line (Line, Last);
         Append (Buf, Line (1 .. Last));
         Append (Buf, ASCII.LF);
      end loop;
   exception
      when End_Error => return To_String (Buf);
   end Read_Stdin;

   Input : constant String := Read_Stdin;

begin
   if Input'Length = 0 then return; end if;

   declare
      Ctx  : SData.Parser.Parser_Context;
      Prog : SData.AST.Statement_Access;
      pragma Unreferenced (Prog);
   begin
      SData.Parser.Initialize (Ctx, Input);
      Prog := SData.Parser.Parse_Program (Ctx);
   exception
      when SData.Parser.Incomplete_Statement => null;
      when SData.Script_Error                => null;
   end;
end Parser_Fuzz_Driver;