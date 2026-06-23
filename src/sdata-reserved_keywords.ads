--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

with SData_Core.Commands;

package SData.Reserved_Keywords is

   --  The set of sdata reserved keywords, upper-cased. Source of truth is the
   --  keyword chain in SData.Lexer (src/lexer/sdata-lexer.adb); keep in sync
   --  when adding/removing a keyword. Passed to
   --  SData_Core.Commands.Warn_Reserved_Columns at USE time so columns whose
   --  names collide with a keyword are flagged.
   function Set return SData_Core.Commands.Reserved_Keyword_Sets.Set;

end SData.Reserved_Keywords;
