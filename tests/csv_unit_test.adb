with Ada.Text_IO;      use Ada.Text_IO;
with Ada.Command_Line;
with SData.CSV;        use SData.CSV;

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

   procedure Check_Nat (Name : String; Got, Expected : Natural) is
   begin
      if Got = Expected then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got=" & Got'Image & "  expected=" & Expected'Image);
         Failed := Failed + 1;
      end if;
   end Check_Nat;

   procedure Check_Str (Name : String; Got, Expected : String) is
   begin
      if Got = Expected then
         Put_Line ("PASS: " & Name);
         Passed := Passed + 1;
      else
         Put_Line ("FAIL: " & Name
            & "  got=[" & Got & "]  expected=[" & Expected & "]");
         Failed := Failed + 1;
      end if;
   end Check_Str;

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

   R  : Float;
   N  : Natural;
   FA : Field_Array;

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

   --  ── Is_Numeric_Field ──────────────────────────────────────────────────
   Check ("INF-1 numeric",  Is_Numeric_Field ("42"), True);
   Check ("INF-2 dot",      Is_Numeric_Field ("."),  False);
   Check ("INF-3 empty",    Is_Numeric_Field (""),   False);

   --  ── At_Delimiter ──────────────────────────────────────────────────────
   Check ("ATD-1 comma match",  At_Delimiter ("a,b", 2, ","),               True);
   Check ("ATD-2 no match",     At_Delimiter ("a,b", 1, ","),               False);
   Check ("ATD-3 tab match",
      At_Delimiter ("a" & ASCII.HT & "b", 2, "" & ASCII.HT),               True);

   --  ── CSV_Field_End ─────────────────────────────────────────────────────
   Check_Nat ("CFE-1 first field",  CSV_Field_End ("a,b,c",     1, ","), 2);
   Check_Nat ("CFE-2 last field",   CSV_Field_End ("a,b,c",     5, ","), 0);
   Check_Nat ("CFE-3 quoted field", CSV_Field_End ("""hi"",b",  1, ","), 5);

   --  ── CSV_Unquote ───────────────────────────────────────────────────────
   Check_Str ("CUQ-1 double-quoted",  CSV_Unquote ("""hello"""),       "hello");
   Check_Str ("CUQ-2 doubled-quote",  CSV_Unquote ("""he""""llo"""),   "he""llo");
   Check_Str ("CUQ-3 untrimmed",      CSV_Unquote ("  hello  "),       "hello");
   Check_Str ("CUQ-4 single-quoted",  CSV_Unquote ("'world'"),         "world");

   --  ── Split_Indices ─────────────────────────────────────────────────────
   FA := Split_Indices ("a,b,c", ",", N);
   Check_Nat ("SI-1 count",  N,        3);
   Check_Nat ("SI-1 f1.S",   FA(1).S,  1);
   Check_Nat ("SI-1 f1.E",   FA(1).E,  1);
   Check_Nat ("SI-1 f2.S",   FA(2).S,  3);
   Check_Nat ("SI-1 f2.E",   FA(2).E,  3);
   Check_Nat ("SI-1 f3.S",   FA(3).S,  5);
   Check_Nat ("SI-1 f3.E",   FA(3).E,  5);

   FA := Split_Indices ("", ",", N);
   Check_Nat ("SI-2 empty count", N, 0);

   --  Input """a,b"",c""" is the Ada literal for the string: "a,b",c
   --  Positions: 1=" 2=a 3=, 4=b 5=" 6=, 7=c
   --  Field 1 = positions 1..5 (the quoted span); field 2 = position 7
   FA := Split_Indices ("""a,b"",c", ",", N);
   Check_Nat ("SI-3 quoted count", N,       2);
   Check_Nat ("SI-3 f1.S",         FA(1).S, 1);
   Check_Nat ("SI-3 f1.E",         FA(1).E, 5);
   Check_Nat ("SI-3 f2.S",         FA(2).S, 7);
   Check_Nat ("SI-3 f2.E",         FA(2).E, 7);

   --  ── Summary ───────────────────────────────────────────────────────────
   New_Line;
   Put_Line (Passed'Image & " passed," & Failed'Image & " failed.");
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end CSV_Unit_Test;
