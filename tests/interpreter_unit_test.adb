--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

--  Unit tests for SData.Interpreter: control flow (IF/ELSE/ELSEIF, FOR, WHILE,
--  REPEAT/UNTIL, BREAK, SELECT/CASE) and array assignment (single-index, slice,
--  list, LET/SET ownership rules).
--  Parses and executes script fragments, then inspects SData_Core.Variables and
--  SData_Core.Table state via their public APIs.

with Ada.Exceptions;
with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with SData_Core.Commands;
with SData_Core.Config;
with SData_Core.Table;
with SData_Core.Values;          use SData_Core.Values;
with SData_Core.Variables;
with SData.AST;             use SData.AST;
with SData.Lexer;           use SData.Lexer;
with SData.Parser;
with SData.Interpreter;

procedure Interpreter_Unit_Test is
   Passed : Natural := 0;
   Failed : Natural := 0;

   --  Single LF used to join script lines.
   L : constant String := (1 => ASCII.LF);

   procedure Check (Name : String; Got, Expected : Boolean) is
   begin
      if Got = Expected then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got=" & Got'Image & "  expected=" & Expected'Image);
         Failed := Failed + 1;
      end if;
   end Check;

   procedure Check (Name : String; Got, Expected : Integer) is
   begin
      if Got = Expected then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got=" & Got'Image & "  expected=" & Expected'Image);
         Failed := Failed + 1;
      end if;
   end Check;

   procedure Check (Name : String; Got, Expected : String) is
   begin
      if Got = Expected then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got=[" & Got & "]  expected=[" & Expected & "]");
         Failed := Failed + 1;
      end if;
   end Check;

   procedure Check_Float (Name : String; Got, Expected : Float;
                          Tol : Float := 0.001) is
   begin
      if abs (Got - Expected) <= Tol then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got=" & Got'Image & "  expected=" & Expected'Image);
         Failed := Failed + 1;
      end if;
   end Check_Float;

   --  Reset all interpreter state between tests.
   procedure Reset is
   begin
      SData_Core.Table.Clear;
      SData_Core.Variables.Clear_Temporary;
      SData_Core.Variables.Initialize_PDV;
      SData_Core.Commands.Execute_NEW;
   end Reset;

   --  Parse and execute Script from a clean state.  Propagates any exception.
   procedure Run (Script : String) is
      Ctx  : SData.Parser.Parser_Context;
      Prog : Statement_Access := null;
   begin
      Reset;
      SData.Parser.Initialize (Ctx, Script);
      Prog := SData.Parser.Parse_Program (Ctx);
      SData.Interpreter.Execute (Prog);
      SData.AST.Free_Program (Prog);
   exception
      when others =>
         SData.AST.Free_Program (Prog);
         raise;
   end Run;

   --  Returns True if executing Script raises any exception.
   function Raises (Script : String) return Boolean is
   begin
      Run (Script);
      return False;
   exception
      when others => return True;
   end Raises;

   --  Read a variable as integer from the PDV (handles Numeric → Integer).
   function GI (Name : String) return Integer is
      V : constant Value := SData_Core.Variables.Get (Name);
   begin
      case V.Kind is
         when Val_Integer => return V.Int_Val;
         when Val_Numeric => return Integer (V.Num_Val);
         when others      => return -99_999;
      end case;
   end GI;

   --  Read a variable as float from the PDV.
   function GF (Name : String) return Float is
      V : constant Value := SData_Core.Variables.Get (Name);
   begin
      case V.Kind is
         when Val_Numeric => return V.Num_Val;
         when Val_Integer => return Float (V.Int_Val);
         when others      => return -99_999.0;
      end case;
   end GF;

   --  Read a variable as string from the PDV.
   function GS (Name : String) return String is
      V : constant Value := SData_Core.Variables.Get (Name);
   begin
      if V.Kind = Val_String then return To_String (V.Str_Val);
      else return "<not-a-string>";
      end if;
   end GS;

   --  Read a committed table cell as integer.
   function TGI (Row : Positive; Name : String) return Integer is
      V : constant Value := SData_Core.Table.Get_Value (Row, Name);
   begin
      case V.Kind is
         when Val_Integer => return V.Int_Val;
         when Val_Numeric => return Integer (V.Num_Val);
         when others      => return -99_999;
      end case;
   end TGI;

   --  Read an array element as integer.
   function GI_Arr (Name : String; Idx : Integer) return Integer is
      V : constant Value := SData_Core.Variables.Get_Array_Element (Name, Idx);
   begin
      case V.Kind is
         when Val_Integer => return V.Int_Val;
         when Val_Numeric => return Integer (V.Num_Val);
         when others      => return -99_999;
      end case;
   end GI_Arr;

begin
   SData_Core.Config.Quiet_Mode := True;

   Put_Line ("=== Interpreter Control Flow Unit Tests ===");
   Put_Line ("");

   -----------------------------------------------------------------------
   --  A.  Assignment (LET / SET)
   -----------------------------------------------------------------------
   Put_Line ("--- A: Assignment ---");

   --  IC-01: LET creates an integer permanent variable.
   Run ("LET X = 42" & L & "RUN");
   Check ("IC-01: LET integer", GI ("X"), 42);

   --  IC-02: LET creates a float permanent variable.
   Run ("LET X = 3.14" & L & "RUN");
   Check_Float ("IC-02: LET float", GF ("X"), 3.14);

   --  IC-03: LET creates a string permanent variable.
   Run ("LET S$ = ""hello""" & L & "RUN");
   Check ("IC-03: LET string", GS ("S$"), "hello");

   --  IC-04: SET creates a temporary variable.
   Run ("SET T = 99" & L & "RUN");
   Check ("IC-04: SET integer", GI ("T"), 99);

   --  IC-05: LET evaluates an arithmetic expression referencing other vars.
   Run ("LET A = 3" & L & "LET B = 4" & L & "LET C = A + B" & L & "RUN");
   Check ("IC-05: LET A + B = 7", GI ("C"), 7);

   -----------------------------------------------------------------------
   --  B.  IF / ELSE / ELSEIF
   -----------------------------------------------------------------------
   Put_Line ("");
   Put_Line ("--- B: IF / ELSE / ELSEIF ---");

   --  IC-06: IF true branch executes.
   Run ("LET X = 0" & L &
        "IF 1 = 1 THEN" & L &
        "  LET X = 1" & L &
        "END" & L & "RUN");
   Check ("IC-06: IF true branch executes", GI ("X"), 1);

   --  IC-07: IF false with no ELSE skips body.
   Run ("LET X = 0" & L &
        "IF 1 = 0 THEN" & L &
        "  LET X = 1" & L &
        "END" & L & "RUN");
   Check ("IC-07: IF false (no ELSE) skips body", GI ("X"), 0);

   --  IC-08: IF false with ELSE takes the ELSE branch.
   Run ("LET X = 0" & L &
        "IF 1 = 0 THEN" & L &
        "  LET X = 1" & L &
        "ELSE" & L &
        "  LET X = 2" & L &
        "END" & L & "RUN");
   Check ("IC-08: IF false takes ELSE branch", GI ("X"), 2);

   --  IC-09: ELSEIF chain — second condition matches.
   Run ("LET X = 0" & L &
        "IF 1 = 2 THEN" & L &
        "  LET X = 1" & L &
        "ELSEIF 1 = 1 THEN" & L &
        "  LET X = 2" & L &
        "ELSE" & L &
        "  LET X = 3" & L &
        "END" & L & "RUN");
   Check ("IC-09: ELSEIF second condition matches", GI ("X"), 2);

   --  IC-10: ELSEIF chain — all miss, ELSE taken.
   Run ("LET X = 0" & L &
        "IF 1 = 2 THEN" & L &
        "  LET X = 1" & L &
        "ELSEIF 1 = 3 THEN" & L &
        "  LET X = 2" & L &
        "ELSE" & L &
        "  LET X = 3" & L &
        "END" & L & "RUN");
   Check ("IC-10: ELSEIF all miss takes ELSE", GI ("X"), 3);

   --  IC-11: ELSEIF with no trailing ELSE falls through silently.
   Run ("LET X = 0" & L &
        "IF 1 = 2 THEN" & L &
        "  LET X = 1" & L &
        "ELSEIF 1 = 3 THEN" & L &
        "  LET X = 2" & L &
        "END IF" & L & "RUN");
   Check ("IC-11: ELSEIF no-ELSE falls through silently", GI ("X"), 0);

   --  IC-12: Nested IF.
   Run ("LET X = 0" & L &
        "IF 1 = 1 THEN" & L &
        "  IF 2 = 2 THEN" & L &
        "    LET X = 42" & L &
        "  END" & L &
        "END" & L & "RUN");
   Check ("IC-12: nested IF true/true", GI ("X"), 42);

   -----------------------------------------------------------------------
   --  C.  FOR loops
   -----------------------------------------------------------------------
   Put_Line ("");
   Put_Line ("--- C: FOR ---");

   --  IC-13: Basic FOR accumulates sum 1+2+3+4+5 = 15.
   Run ("LET SUM = 0" & L &
        "FOR I = 1 TO 5" & L &
        "  LET SUM = SUM + I" & L &
        "NEXT" & L & "RUN");
   Check ("IC-13: FOR sum 1..5 = 15", GI ("SUM"), 15);

   --  IC-14: FOR with step 2 counts 5 odd values (1,3,5,7,9).
   Run ("LET N = 0" & L &
        "FOR I = 1 TO 9 STEP 2" & L &
        "  LET N = N + 1" & L &
        "NEXT" & L & "RUN");
   Check ("IC-14: FOR step 2 iterates 5 times", GI ("N"), 5);

   --  IC-15: FOR with positive step and end < start does not iterate.
   Run ("LET X = 0" & L &
        "FOR I = 5 TO 1" & L &
        "  LET X = X + 1" & L &
        "NEXT" & L & "RUN");
   Check ("IC-15: FOR empty (end < start, step > 0)", GI ("X"), 0);

   --  IC-16: FOR with negative step (countdown 5..1, sum = 15).
   Run ("LET SUM = 0" & L &
        "FOR I = 5 TO 1 STEP -1" & L &
        "  LET SUM = SUM + I" & L &
        "NEXT" & L & "RUN");
   Check ("IC-16: FOR negative step sum 5..1 = 15", GI ("SUM"), 15);

   -----------------------------------------------------------------------
   --  D.  WHILE loops
   -----------------------------------------------------------------------
   Put_Line ("");
   Put_Line ("--- D: WHILE ---");

   --  IC-17: WHILE increments counter until limit.
   Run ("LET X = 0" & L &
        "LET N = 1" & L &
        "WHILE N <= 5" & L &
        "  LET X = X + 1" & L &
        "  LET N = N + 1" & L &
        "WEND" & L & "RUN");
   Check ("IC-17: WHILE loop executes 5 times", GI ("X"), 5);

   --  IC-18: WHILE with initially false condition never executes.
   Run ("LET X = 99" & L &
        "WHILE 1 = 0" & L &
        "  LET X = 0" & L &
        "WEND" & L & "RUN");
   Check ("IC-18: WHILE false condition skips body", GI ("X"), 99);

   --  IC-19: WHILE doubles N until it exceeds 100.
   Run ("LET N = 1" & L &
        "WHILE N < 100" & L &
        "  LET N = N * 2" & L &
        "WEND" & L & "RUN");
   Check ("IC-19: WHILE doubles 1→128", GI ("N"), 128);

   -----------------------------------------------------------------------
   --  E.  REPEAT / UNTIL loop
   -----------------------------------------------------------------------
   Put_Line ("");
   Put_Line ("--- E: REPEAT/UNTIL ---");

   --  IC-20: Body executes at least once even when condition is true initially.
   Run ("LET J = 10" & L &
        "LET C = 0" & L &
        "REPEAT" & L &
        "  LET C = C + 1" & L &
        "  LET J = J + 1" & L &
        "UNTIL J > 5" & L & "RUN");
   Check ("IC-20: REPEAT/UNTIL executes once (condition initially true)", GI ("C"), 1);

   --  IC-21: REPEAT/UNTIL iterates until condition becomes true.
   Run ("LET I = 1" & L &
        "LET C = 0" & L &
        "REPEAT" & L &
        "  LET C = C + 1" & L &
        "  LET I = I + 1" & L &
        "UNTIL I > 3" & L & "RUN");
   Check ("IC-21: REPEAT/UNTIL runs 3 iterations", GI ("C"), 3);

   -----------------------------------------------------------------------
   --  F.  BREAK
   -----------------------------------------------------------------------
   Put_Line ("");
   Put_Line ("--- F: BREAK ---");

   --  IC-22: BREAK skips remaining statements for the current record.
   Run ("REPEAT 1" & L &
        "LET X = 1" & L &
        "BREAK" & L &
        "LET X = 999" & L &
        "RUN");
   Check ("IC-22: BREAK skips subsequent LET", TGI (1, "X"), 1);

   --  IC-23: BREAK WHEN true skips remaining statements.
   Run ("REPEAT 1" & L &
        "LET X = 1" & L &
        "BREAK WHEN 1 = 1" & L &
        "LET X = 999" & L &
        "RUN");
   Check ("IC-23: BREAK WHEN true skips subsequent LET", TGI (1, "X"), 1);

   --  IC-24: BREAK WHEN false does not trigger; subsequent statement executes.
   Run ("REPEAT 1" & L &
        "LET X = 1" & L &
        "BREAK WHEN 1 = 0" & L &
        "LET X = 999" & L &
        "RUN");
   Check ("IC-24: BREAK WHEN false does not skip", TGI (1, "X"), 999);

   -----------------------------------------------------------------------
   --  G.  SELECT / CASE and SELECT / WHEN
   -----------------------------------------------------------------------
   Put_Line ("");
   Put_Line ("--- G: SELECT ---");

   --  IC-25: SELECT with selector matches first CASE.
   Run ("LET G = 90" & L &
        "SELECT (G)" & L &
        "  CASE (90) LET R$ = ""A""" & L &
        "  CASE (85) LET R$ = ""B""" & L &
        "  OTHERWISE LET R$ = ""C""" & L &
        "END" & L & "RUN");
   Check ("IC-25: SELECT matches first CASE", GS ("R$"), "A");

   --  IC-26: SELECT with selector matches second CASE.
   Run ("LET G = 85" & L &
        "SELECT (G)" & L &
        "  CASE (90) LET R$ = ""A""" & L &
        "  CASE (85) LET R$ = ""B""" & L &
        "  OTHERWISE LET R$ = ""C""" & L &
        "END" & L & "RUN");
   Check ("IC-26: SELECT matches second CASE", GS ("R$"), "B");

   --  IC-27: SELECT with selector, no CASE match → OTHERWISE.
   Run ("LET G = 70" & L &
        "SELECT (G)" & L &
        "  CASE (90) LET R$ = ""A""" & L &
        "  CASE (85) LET R$ = ""B""" & L &
        "  OTHERWISE LET R$ = ""C""" & L &
        "END" & L & "RUN");
   Check ("IC-27: SELECT no CASE match takes OTHERWISE", GS ("R$"), "C");

   --  IC-28: SELECT-WHEN (no selector) matches second WHEN.
   Run ("LET X = 0" & L &
        "SELECT" & L &
        "  WHEN (1 = 0) LET X = 1" & L &
        "  WHEN (1 = 1) LET X = 2" & L &
        "  OTHERWISE LET X = 3" & L &
        "END" & L & "RUN");
   Check ("IC-28: SELECT WHEN (no selector) second condition", GI ("X"), 2);

   --  IC-29: SELECT with no match and no OTHERWISE leaves variable unchanged.
   Run ("LET X = 0" & L &
        "SELECT (99)" & L &
        "  CASE (1) LET X = 1" & L &
        "END" & L & "RUN");
   Check ("IC-29: SELECT no match, no OTHERWISE is no-op", GI ("X"), 0);

   -----------------------------------------------------------------------
   --  H.  REPEAT N declarative mode (multi-record data step)
   -----------------------------------------------------------------------
   Put_Line ("");
   Put_Line ("--- H: REPEAT N (multi-record step) ---");

   --  IC-30: REPEAT 3 generates exactly 3 committed rows.
   Run ("REPEAT 3" & L &
        "LET X = RECNO()" & L &
        "RUN");
   Check ("IC-30: REPEAT 3 creates 3 rows", SData_Core.Table.Row_Count, 3);

   --  IC-31: Each record carries the correct RECNO value.
   Check ("IC-31: record 1 X = 1", TGI (1, "X"), 1);
   Check ("IC-31: record 2 X = 2", TGI (2, "X"), 2);
   Check ("IC-31: record 3 X = 3", TGI (3, "X"), 3);

   --  IC-32: REPEAT 1 is minimal; exactly one row committed.
   Run ("REPEAT 1" & L &
        "LET X = 42" & L &
        "RUN");
   Check ("IC-32: REPEAT 1 creates 1 row", SData_Core.Table.Row_Count, 1);
   Check ("IC-32: REPEAT 1 row value", TGI (1, "X"), 42);

   -----------------------------------------------------------------------
   --  I.  Error handling
   -----------------------------------------------------------------------
   Put_Line ("");
   Put_Line ("--- I: Error handling ---");

   --  IC-33: Division by zero raises Script_Error.
   Check ("IC-33: division by zero raises error",
          Raises ("LET X = 1 / 0" & L & "RUN"), True);

   --  IC-34: Calling an unknown function returns Val_Missing (no error).
   --  Evaluate_Function returns Val_Missing for names not in the dispatch table.
   Run ("LET X = XXXXXXXX()" & L & "RUN");
   Check ("IC-34: unknown function returns Val_Missing",
          SData_Core.Variables.Get ("X").Kind = Val_Missing, True);

   -----------------------------------------------------------------------
   --  J.  Array Assignment (safety net for Execute_Assignment refactor)
   -----------------------------------------------------------------------
   Put_Line ("");
   Put_Line ("--- J: Array Assignment ---");

   --  IC-35: Single-index LET assigns to the named element.
   Run ("DIM A35(3)" & L & "LET A35(2) = 42" & L & "RUN");
   Check ("IC-35: single-index LET A35(2) = 42", GI_Arr ("A35", 2), 42);

   --  IC-36: Slice LET A36(2:4) = 99 sets every element in the range.
   Run ("DIM A36(5)" & L & "LET A36(2:4) = 99" & L & "RUN");
   Check ("IC-36: slice element 2", GI_Arr ("A36", 2), 99);
   Check ("IC-36: slice element 3", GI_Arr ("A36", 3), 99);
   Check ("IC-36: slice element 4", GI_Arr ("A36", 4), 99);

   --  IC-37: List LET A37(1,3,5) = 77 sets exactly the named elements.
   Run ("DIM A37(5)" & L & "LET A37(1,3,5) = 77" & L & "RUN");
   Check ("IC-37: list element 1", GI_Arr ("A37", 1), 77);
   Check ("IC-37: list element 3", GI_Arr ("A37", 3), 77);
   Check ("IC-37: list element 5", GI_Arr ("A37", 5), 77);

   --  IC-38: SET assigns to a temporary array element.
   Run ("DIM T38(3) /TEMP" & L & "SET T38(1) = 5" & L & "RUN");
   Check ("IC-38: SET on temp array T38(1) = 5", GI_Arr ("T38", 1), 5);

   --  IC-39: LET on a temporary array element raises Script_Error.
   Check ("IC-39: LET on temp array element raises error",
          Raises ("DIM T39(3) /TEMP" & L & "LET T39(1) = 1" & L & "RUN"), True);

   --  IC-40: SET on a permanent array element raises Script_Error.
   Check ("IC-40: SET on permanent array element raises error",
          Raises ("DIM P40(3)" & L & "SET P40(1) = 1" & L & "RUN"), True);

   --  IC-41: Assignment to an undefined array raises Script_Error.
   Check ("IC-41: assignment to undefined array raises error",
          Raises ("LET UNDEF41(1) = 1" & L & "RUN"), True);

   -----------------------------------------------------------------------
   --  K.  Lexer: Backtick-Quoted Identifiers (Task 3)
   -----------------------------------------------------------------------
   Put_Line ("");
   Put_Line ("--- K: Lexer backtick-quoted identifiers ---");

   --  Helper: lex a single-token source and return the token.
   declare
      function Lex1 (Source : String) return Token is
         Ctx : Lexer_Context;
      begin
         Initialize (Ctx, Source);
         return Get_Next_Token (Ctx);
      end Lex1;

      T : Token;
   begin
      --  LC-01: `AS` produces Token_Quoted_Identifier with text "AS".
      T := Lex1 ("`AS`");
      Check ("LC-01: `AS` kind = Token_Quoted_Identifier",
             T.Kind = Token_Quoted_Identifier, True);
      Check ("LC-01: `AS` text = ""AS""",
             T.Text (1 .. T.Length), "AS");

      --  LC-02: `as` preserves lowercase (case preserved at token level).
      T := Lex1 ("`as`");
      Check ("LC-02: `as` text = ""as""",
             T.Text (1 .. T.Length), "as");
      Check ("LC-02: `as` kind = Token_Quoted_Identifier",
             T.Kind = Token_Quoted_Identifier, True);

      --  LC-03: `a.b c` passes dots and spaces through verbatim.
      T := Lex1 ("`a.b c`");
      Check ("LC-03: `a.b c` text = ""a.b c""",
             T.Text (1 .. T.Length), "a.b c");
      Check ("LC-03: `a.b c` kind = Token_Quoted_Identifier",
             T.Kind = Token_Quoted_Identifier, True);

      --  LC-04: `` (empty backticks) produces Token_Bad.
      T := Lex1 ("``");
      Check ("LC-04: empty backticks kind = Token_Bad",
             T.Kind = Token_Bad, True);

      --  LC-05: `AS (no closing backtick) produces Token_Bad.
      T := Lex1 ("`AS");
      Check ("LC-05: unterminated backtick kind = Token_Bad",
             T.Kind = Token_Bad, True);
   end;

   -----------------------------------------------------------------------
   --  L.  Active-program buffer recovery after a failed RUN (issue #31)
   --      Mimics the interactive REPL: deferred statements are queued one at
   --      a time via Add_To_Active_Program, RUN raises mid-step, and a
   --      subsequent NEW (Clear_Active_Program) must not double-free the
   --      still-chained statement list.
   -----------------------------------------------------------------------
   Put_Line ("");
   Put_Line ("--- L: Active-program recovery after failed RUN (issue #31) ---");

   declare
      --  Parse a single statement in isolation (Next = null), exactly as the
      --  REPL does when each command arrives on its own line.
      function Parse_One (Src : String) return Statement_Access is
         Ctx : SData.Parser.Parser_Context;
      begin
         SData.Parser.Initialize (Ctx, Src & L);
         return SData.Parser.Parse_Program (Ctx);
      end Parse_One;

      Run_Raised : Boolean := False;
   begin
      Reset;
      SData.Interpreter.Clear_Active_Program;

      --  Queue two deferred statements that parse cleanly but fail during the
      --  data step: the second assigns the string variable S$ to the numeric
      --  variable N (a NON-literal right-hand side, so the parse-time literal
      --  check does not pre-empt it), which raises a type mismatch at RUN.
      --  Two statements are required to trigger the double-free: a single
      --  queued statement leaves no second vector entry to re-free.
      SData.Interpreter.Add_To_Active_Program (Parse_One ("SET S$ = ""hi"""));
      SData.Interpreter.Add_To_Active_Program (Parse_One ("SET N = S$"));

      begin
         SData.Interpreter.Run_Active_Program;
      exception
         when others => Run_Raised := True;
      end;
      Check ("IC-42: failed RUN propagates the type-mismatch error",
             Run_Raised, True);

      --  Pre-fix this double-frees the still-chained list and crashes the
      --  process; post-fix Run_Active_Program has unchained on the way out,
      --  so Clear_Active_Program completes cleanly.
      SData.Interpreter.Clear_Active_Program;
      Check ("IC-43: NEW after a failed RUN does not double-free (issue #31)",
             SData.Interpreter.Program_Buffer_Length, 0);
   end;

   -----------------------------------------------------------------------
   --  M.  TRANSPOSE: parser / dispatch unit tests
   -----------------------------------------------------------------------
   Put_Line ("");
   Put_Line ("--- M: TRANSPOSE parser / dispatch ---");

   --  TT-01: /ID and /ARRAY are mutually exclusive (parse-time error).
   declare
      Did_Raise : Boolean := False;
   begin
      begin
         Run ("transpose /id=id$ /array=y");
      exception
         when E : others =>
            Did_Raise := True;
            Check ("TT-01: /ID + /ARRAY error message",
                   Ada.Exceptions.Exception_Message (E),
                   "TRANSPOSE: /ID and /ARRAY are mutually exclusive");
      end;
      Check ("TT-01: /ID + /ARRAY raises error", Did_Raise, True);
   end;

   --  TT-02: /KEEP= with empty list (parse-time error).
   declare
      Did_Raise : Boolean := False;
   begin
      begin
         Run ("transpose /keep=");
      exception
         when E : others =>
            Did_Raise := True;
            Check ("TT-02: /KEEP= empty error message",
                   Ada.Exceptions.Exception_Message (E),
                   "TRANSPOSE: /KEEP= requires at least one variable");
      end;
      Check ("TT-02: /KEEP= empty raises error", Did_Raise, True);
   end;

   --  TT-03: /NAME value without trailing $ (parse-time error).
   declare
      Did_Raise : Boolean := False;
   begin
      begin
         Run ("transpose /name=foo");
      exception
         when E : others =>
            Did_Raise := True;
            Check ("TT-03: /NAME no-$ error message",
                   Ada.Exceptions.Exception_Message (E),
                   "TRANSPOSE: /NAME column 'foo' must end in $" &
                   " (character column required)");
      end;
      Check ("TT-03: /NAME no-$ raises error", Did_Raise, True);
   end;

   --  TT-04: Valid TRANSPOSE /DROP=id$ produces reshaped schema.
   --  transpose_simple.csv: id$ score height (3 rows A/B/C) → 2 rows, 4 cols.
   Run ("use ""tests/data/transpose_simple.csv""" & L &
        "transpose /drop=id$");
   Check ("TT-04: row count = 2 (SCORE, HEIGHT)",
          SData_Core.Table.Row_Count, 2);
   Check ("TT-04: _NAME_$ column present",
          SData_Core.Table.Has_Column ("_NAME_$"), True);
   Check ("TT-04: _X_(1) column present",
          SData_Core.Table.Has_Column ("_X_(1)"), True);

   --  TT-05: TRANSPOSE /ID=id$ names output columns from ID values.
   --  id$ values A/B/C → columns A, B, C plus _NAME_$.
   Run ("use ""tests/data/transpose_simple.csv""" & L &
        "transpose /id=id$");
   Check ("TT-05: row count = 2 (SCORE, HEIGHT)",
          SData_Core.Table.Row_Count, 2);
   Check ("TT-05: column A present (from id$ value ""A"")",
          SData_Core.Table.Has_Column ("A"), True);

   --  TT-06: Bare TRANSPOSE on all-numeric fixture uses default _X_ array.
   --  transpose_numeric.csv: score height weight (2 rows) → 3 rows, 3 cols.
   Run ("use ""tests/data/transpose_numeric.csv""" & L &
        "transpose");
   Check ("TT-06: row count = 3 (SCORE, HEIGHT, WEIGHT)",
          SData_Core.Table.Row_Count, 3);
   Check ("TT-06: _X_(1) column present (default _X_ array)",
          SData_Core.Table.Has_Column ("_X_(1)"), True);

   -----------------------------------------------------------------------
   --  Summary
   -----------------------------------------------------------------------
   Put_Line ("");
   Put_Line ("Passed:" & Passed'Image & "  Failed:" & Failed'Image);
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;

end Interpreter_Unit_Test;