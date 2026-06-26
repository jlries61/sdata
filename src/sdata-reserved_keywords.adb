--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

package body SData.Reserved_Keywords is

   function Set return SData_Core.Commands.Reserved_Keyword_Sets.Set is
      use SData_Core.Commands.Reserved_Keyword_Sets;
      S : SData_Core.Commands.Reserved_Keyword_Sets.Set := Empty_Set;
   begin
      --  Mirror SData.Lexer's keyword chain (bare forms, lines 246-314 of
      --  src/lexer/sdata-lexer.adb). Alphabetical for review.
      --  Slash-only forms ("/USE", "/MOCK", etc.) are excluded: a CSV column
      --  name cannot start with '/', so they pose no collision risk. Their bare
      --  equivalents (USE, MOCK, SAVE, SUBMIT, SYSTEM, OUTPUT, ALL) ARE included.
      S.Insert ("AGGREGATE");
      S.Insert ("ALL");
      S.Insert ("AND");
      S.Insert ("APPEND");
      S.Insert ("ARRAY");
      S.Insert ("AS");
      S.Insert ("BREAK");
      S.Insert ("BY");
      S.Insert ("CASE");
      S.Insert ("DELETE");
      S.Insert ("DIM");
      S.Insert ("DIGITS");
      S.Insert ("DISPLAY");
      S.Insert ("DROP");
      S.Insert ("ECHO");
      S.Insert ("ELSE");
      S.Insert ("ELSEIF");
      S.Insert ("END");
      S.Insert ("FOR");
      S.Insert ("FPATH");
      S.Insert ("HEADER");
      S.Insert ("HELP");
      S.Insert ("HOLD");
      S.Insert ("IF");
      S.Insert ("IN");
      S.Insert ("INTERLEAVE");
      S.Insert ("INTO");
      S.Insert ("JOIN");
      S.Insert ("KEEP");
      S.Insert ("LET");
      S.Insert ("LIST");
      S.Insert ("MOCK");
      S.Insert ("NAMES");
      S.Insert ("NEW");
      S.Insert ("NEXT");
      S.Insert ("NOT");
      S.Insert ("OPTIONS");
      S.Insert ("OR");
      S.Insert ("OTHERWISE");
      S.Insert ("OUTPUT");
      S.Insert ("PRINT");
      S.Insert ("QUIT");
      S.Insert ("REM");
      S.Insert ("RENAME");
      S.Insert ("REPEAT");
      S.Insert ("RSEED");
      S.Insert ("RUN");
      S.Insert ("SAVE");
      S.Insert ("SELECT");
      S.Insert ("SET");
      S.Insert ("SORT");
      S.Insert ("STEP");
      S.Insert ("SUBMIT");
      S.Insert ("SYSTEM");
      S.Insert ("THEN");
      S.Insert ("TO");
      S.Insert ("TRANSPOSE");
      S.Insert ("UNHOLD");
      S.Insert ("UNSET");
      S.Insert ("UNTIL");
      S.Insert ("USE");
      S.Insert ("WEND");
      S.Insert ("WHEN");
      S.Insert ("WHILE");
      S.Insert ("WRITE");
      S.Insert ("XOR");
      return S;
   end Set;

end SData.Reserved_Keywords;
