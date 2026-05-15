--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

--  OOXML (Excel .xlsx) fuzz driver.
--
--  Passes an arbitrary file through Parse_OOXML.  The file path is given as
--  the first command-line argument so that AFL++ can use @@ substitution.
--
--  Expected exceptions (Script_Error for any parse failure — corrupt ZIP,
--  missing workbook, malformed XML) are caught and silenced.  Unexpected
--  exceptions (Constraint_Error, Program_Error, Storage_Error) propagate
--  uncaught so that AFL++ or a crash-regression harness can detect them.
--
--  AFL++ usage:
--    afl-fuzz -i tests/fuzz_corpus/xlsx -o fuzz_out/xlsx \
--             -- ./bin/xlsx_fuzz_driver @@
--
--  Corpus regression (no AFL++ required):
--    make fuzz-corpus

with Ada.Command_Line;
with SData.Config;
with SData.Table;
with SData.File_IO.OOXML;

procedure XLSX_Fuzz_Driver is
begin
   if Ada.Command_Line.Argument_Count /= 1 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   SData.Config.Quiet_Mode := True;
   SData.Table.Clear;

   begin
      SData.File_IO.OOXML.Parse_OOXML (Ada.Command_Line.Argument (1));
   exception
      when SData.Script_Error => null;
   end;
end XLSX_Fuzz_Driver;