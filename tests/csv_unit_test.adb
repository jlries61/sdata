--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

with Ada.Text_IO;      use Ada.Text_IO;
with Ada.Command_Line;
with SData.CSV;        use SData.CSV;
with SData.Values;     use SData.Values;

procedure CSV_Unit_Test is
   Passed : Natural := 0;
   Failed : Natural := 0;

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

   procedure Check (Name : String; Got, Expected : Natural) is
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

   procedure Check_Float (Name    : String;
                           Got_Ok  : Boolean; Got_Val  : Float;
                           Exp_Ok  : Boolean; Exp_Val  : Float;
                           Tol     : Float := 0.001) is
   begin
      if Got_Ok = Exp_Ok
         and then (not Exp_Ok or else abs (Got_Val - Exp_Val) <= Tol)
      then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got_ok=" & Got_Ok'Image & "  exp_ok=" & Exp_Ok'Image);
         Failed := Failed + 1;
      end if;
   end Check_Float;

   procedure Check_Inf (Name : String; Got_Ok : Boolean; Got_Val : Float;
                        Expected_Inf : Float) is
   begin
      if Got_Ok and then Got_Val = Expected_Inf then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got_ok=" & Got_Ok'Image & "  got=" & Got_Val'Image);
         Failed := Failed + 1;
      end if;
   end Check_Inf;

   R  : Float;
   FV : Field_Vectors.Vector;

begin
   --  ── Try_Fast_Float ────────────────────────────────────────────────────
   Check_Float ("TFF-1 integer",
      Try_Fast_Float ("42", R),    R, True,  42.0);
   Check_Float ("TFF-2 negative decimal",
      Try_Fast_Float ("-3.14", R), R, True,  -3.14);
   Check_Float ("TFF-3 scientific",
      Try_Fast_Float ("1.5E3", R), R, True,  1500.0);
   Check_Float ("TFF-4 empty",
      Try_Fast_Float ("", R),      R, False, 0.0);
   Check_Float ("TFF-5 non-numeric",
      Try_Fast_Float ("abc", R),   R, False, 0.0);
   Check_Float ("TFF-6 positive sign",
      Try_Fast_Float ("+3.14", R), R, True, 3.14);
   Check_Float ("TFF-7 negative exponent",
      Try_Fast_Float ("1E-3",  R), R, True, 0.001, 0.0001);
   Check_Float ("TFF-8 negative zero",
      Try_Fast_Float ("-0",    R), R, True, 0.0);
   Check_Float ("TFF-9 leading-dot decimal",
      Try_Fast_Float (".5",    R), R, True, 0.5);
   Check_Float ("TFF-10 spaces trimmed",
      Try_Fast_Float ("  42  ", R), R, True, 42.0);
   Check_Inf ("TFF-11 INF literal",
      Try_Fast_Float ("INF",  R), R, Pos_Inf);
   Check_Inf ("TFF-12 -INF literal",
      Try_Fast_Float ("-INF", R), R, Neg_Inf);
   Check_Float ("TFF-13 incomplete exponent",
      Try_Fast_Float ("1e",   R), R, False, 0.0);
   Check_Float ("TFF-14 double dot",
      Try_Fast_Float ("1.2.3", R), R, False, 0.0);
   Check_Float ("TFF-15 sign only minus",
      Try_Fast_Float ("-",    R), R, False, 0.0);
   Check_Float ("TFF-16 sign only plus",
      Try_Fast_Float ("+",    R), R, False, 0.0);

   --  ── Is_Numeric_Field ──────────────────────────────────────────────────
   Check ("INF-1 numeric",  Is_Numeric_Field ("42"), True);
   Check ("INF-2 dot",      Is_Numeric_Field ("."),  False);
   Check ("INF-3 empty",    Is_Numeric_Field (""),   False);
   Check ("INF-4 negative exponent numeric", Is_Numeric_Field ("1E-3"),  True);
   Check ("INF-5 positive sign numeric",     Is_Numeric_Field ("+3.14"), True);
   Check ("INF-6 sign-only not numeric",     Is_Numeric_Field ("-"),     False);
   Check ("INF-7 double-dot not numeric",    Is_Numeric_Field ("1.2.3"), False);
   Check ("INF-8 INF is numeric",            Is_Numeric_Field ("INF"),   True);

   --  ── At_Delimiter ──────────────────────────────────────────────────────
   Check ("ATD-1 comma match",  At_Delimiter ("a,b", 2, ","),               True);
   Check ("ATD-2 no match",     At_Delimiter ("a,b", 1, ","),               False);
   Check ("ATD-3 tab match",
      At_Delimiter ("a" & ASCII.HT & "b", 2, "" & ASCII.HT),               True);
   Check ("ATD-4 two-char match",    At_Delimiter ("a::b", 2, "::"), True);
   Check ("ATD-5 two-char no-match", At_Delimiter ("a::b", 1, "::"), False);

   --  ── CSV_Field_End ─────────────────────────────────────────────────────
   Check ("CFE-1 first field",  CSV_Field_End ("a,b,c",     1, ","), 2);
   Check ("CFE-2 last field",   CSV_Field_End ("a,b,c",     5, ","), 0);
   Check ("CFE-3 quoted field", CSV_Field_End ("""hi"",b",  1, ","), 5);
   --  Leading empty field: delimiter is the very first character.
   Check ("CFE-4 leading empty field",
      CSV_Field_End (",a,b", 1, ","), 1);
   --  From index past end of line: treated as last field.
   Check ("CFE-5 From past end",
      CSV_Field_End ("a", 2, ","), 0);
   --  Two-character delimiter.
   Check ("CFE-6 two-char delimiter first field",
      CSV_Field_End ("a::b::c", 1, "::"), 2);

   --  ── CSV_Unquote ───────────────────────────────────────────────────────
   Check ("CUQ-1 double-quoted",  CSV_Unquote ("""hello"""),       "hello");
   Check ("CUQ-2 doubled-quote",  CSV_Unquote ("""he""""llo"""),   "he""llo");
   Check ("CUQ-3 untrimmed",      CSV_Unquote ("  hello  "),       "hello");
   Check ("CUQ-4 single-quoted",  CSV_Unquote ("'world'"),         "world");
   --  "" in Ada source is the two-character string consisting of two double-quotes.
   --  CSV_Unquote sees a quoted empty string and returns "".
   Check ("CUQ-5 empty double-quoted",
      CSV_Unquote (""""""), "");
   Check ("CUQ-6 spaces inside quotes preserved",
      CSV_Unquote ("""  hello  """), "  hello  ");
   Check ("CUQ-7 single-char no quotes trimmed",
      CSV_Unquote ("  x  "), "x");

   --  ── Split_Indices ─────────────────────────────────────────────────────
   Split_Indices ("a,b,c", ",", FV);
   Check ("SI-1-count",  Natural (FV.Length), 3);
   Check ("SI-1-f1.S",   FV(1).S,  1);
   Check ("SI-1-f1.E",   FV(1).E,  1);
   Check ("SI-1-f2.S",   FV(2).S,  3);
   Check ("SI-1-f2.E",   FV(2).E,  3);
   Check ("SI-1-f3.S",   FV(3).S,  5);
   Check ("SI-1-f3.E",   FV(3).E,  5);

   Split_Indices ("", ",", FV);
   Check ("SI-2 empty count", Natural (FV.Length), 0);

   --  Input """a,b"",c""" is the Ada literal for the string: "a,b",c
   --  Positions: 1=" 2=a 3=, 4=b 5=" 6=, 7=c
   --  Field 1 = positions 1..5 (the quoted span); field 2 = position 7
   Split_Indices ("""a,b"",c", ",", FV);
   Check ("SI-3 quoted count", Natural (FV.Length), 2);
   Check ("SI-3 f1.S",         FV(1).S, 1);
   Check ("SI-3 f1.E",         FV(1).E, 5);
   Check ("SI-3 f2.S",         FV(2).S, 7);
   Check ("SI-3 f2.E",         FV(2).E, 7);

   --  Single field, no delimiter in line.
   Split_Indices ("abc", ",", FV);
   Check ("SI-4 single field count", Natural (FV.Length), 1);
   Check ("SI-4 f1.S", FV(1).S, 1);
   Check ("SI-4 f1.E", FV(1).E, 3);

   --  Tab-delimited.
   Split_Indices ("a" & ASCII.HT & "b" & ASCII.HT & "c",
                  "" & ASCII.HT, FV);
   Check ("SI-5 tab count", Natural (FV.Length), 3);
   Check ("SI-5 f2.S", FV(2).S, 3);
   Check ("SI-5 f2.E", FV(2).E, 3);

   --  Empty middle field: a,,c → three fields, field 2 is empty (E < S).
   Split_Indices ("a,,c", ",", FV);
   Check ("SI-6 empty middle count",  Natural (FV.Length), 3);
   Check ("SI-6 f2 empty (E<S)",      FV(2).E < FV(2).S, True);
   Check ("SI-6 f3.S", FV(3).S, 4);

   --  Trailing delimiter: a,b, → three fields, last is empty.
   Split_Indices ("a,b,", ",", FV);
   Check ("SI-7 trailing delim count",    Natural (FV.Length), 3);
   Check ("SI-7 last field empty (E<S)",  FV(3).E < FV(3).S, True);

   --  Two-character delimiter.
   Split_Indices ("a::b::c", "::", FV);
   Check ("SI-8 two-char delim count", Natural (FV.Length), 3);
   Check ("SI-8 f1.S", FV(1).S, 1);
   Check ("SI-8 f1.E", FV(1).E, 1);
   Check ("SI-8 f3.S", FV(3).S, 7);
   Check ("SI-8 f3.E", FV(3).E, 7);

   --  ── Summary ───────────────────────────────────────────────────────────
   New_Line;
   Put_Line (Passed'Image & " passed," & Failed'Image & " failed.");
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end CSV_Unit_Test;