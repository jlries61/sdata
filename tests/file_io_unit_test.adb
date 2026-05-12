--  Unit tests for SData.File_IO: Parse_CSV, Parse_ODF, Parse_OOXML.
--  Calls parsers directly with fixture files in tests/data/ and
--  inspects the resulting SData.Table state via the public API.
--  Must be run from the project root (paths are relative to it).

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with SData;
with SData.Config;
with SData.Table;           use SData.Table;
with SData.Values;          use SData.Values;
with SData.File_IO;         use SData.File_IO;

procedure File_IO_Unit_Test is
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

   V : Value;

begin
   SData.Config.Quiet_Mode := True;

   ---------------------------------------------------------------------------
   --  Parse_CSV tests  (PC-01 .. PC-24)
   ---------------------------------------------------------------------------

   --  PC-01..PC-09: basic load of tests/data/sample.csv
   --  Contents: CATEGORY,VAL1,VAL2,VAL3; 6 rows.
   --  CATEGORY column contains "A","B","C" → inferred Col_String → renamed CATEGORY$.
   Parse_CSV ("tests/data/sample.csv");
   Check ("PC-01 col count",           Column_Count,    4);
   Check ("PC-02 row count",           Row_Count,       6);
   Check ("PC-03 col 1 name",          Column_Name (1), "CATEGORY$");
   Check ("PC-04 col 2 name",          Column_Name (2), "VAL1");
   V := Get_Value (1, "CATEGORY$");
   Check      ("PC-05 row1 CATEGORY$ kind",  V.Kind = Val_String, True);
   Check      ("PC-06 row1 CATEGORY$ value", To_String (V.Str_Val), "A");
   V := Get_Value (1, "VAL1");
   Check      ("PC-07 row1 VAL1 kind",       V.Kind = Val_Numeric, True);
   Check_Float ("PC-08 row1 VAL1",            V.Num_Val, 1.0);
   V := Get_Value (6, "VAL3");
   Check_Float ("PC-09 row6 VAL3",            V.Num_Val, 18.0);

   --  PC-10..PC-13: INF values in tests/data/inf_values.csv
   --  Contents: X,Y,Z; row 1 = Inf,-Inf,1.5
   Parse_CSV ("tests/data/inf_values.csv");
   V := Get_Value (1, "X");
   Check ("PC-10 INF row1 X kind",    V.Kind = Val_Numeric, True);
   Check ("PC-11 INF row1 X Pos_Inf",
          Is_Inf (V.Num_Val) and then V.Num_Val > 0.0, True);
   V := Get_Value (1, "Y");
   Check ("PC-12 INF row1 Y Neg_Inf",
          Is_Inf (V.Num_Val) and then V.Num_Val < 0.0, True);
   V := Get_Value (1, "Z");
   Check_Float ("PC-13 INF row1 Z normal", V.Num_Val, 1.5);

   --  PC-14..PC-15: header-only file (no data rows)
   --  Contents: A,B,C  (one header line, nothing else)
   Parse_CSV ("tests/data/header_only.csv");
   Check ("PC-14 header-only col count", Column_Count, 3);
   Check ("PC-15 header-only row count", Row_Count,    0);

   --  PC-16..PC-17: missing value — first field is "." sentinel
   --  Contents: X,Y / .,10 / 20,30 / 40,50
   Parse_CSV ("tests/data/missing_first.csv");
   V := Get_Value (1, "X");
   Check ("PC-16 missing val kind", V.Kind = Val_Missing, True);
   V := Get_Value (1, "Y");
   Check_Float ("PC-17 non-missing beside missing", V.Num_Val, 10.0);

   --  PC-18..PC-20: pipe delimiter
   --  Contents: NAME$|SCORE / Alice|90 / Bob|85
   Parse_CSV ("tests/data/pipe_delim.csv", Delimiter => "|");
   Check ("PC-18 pipe col count",    Column_Count, 2);
   Check ("PC-19 pipe row count",    Row_Count,    2);
   V := Get_Value (1, "NAME$");
   Check ("PC-20 pipe row1 NAME$",  To_String (V.Str_Val), "Alice");

   --  PC-21..PC-22: Skip_Rows=2 skips the first two data rows (both "A" rows)
   --  sample.csv rows: A/1/2/3, A/4/5/6, B/7/8/9, B/10/11/12, B/13/14/15, C/16/17/18
   --  After skipping 2: 4 rows remain; row 1 is B/7/8/9
   Parse_CSV ("tests/data/sample.csv", Skip_Rows => 2);
   Check ("PC-21 skip_rows=2 row count",  Row_Count, 4);
   V := Get_Value (1, "CATEGORY$");
   Check ("PC-22 skip_rows=2 row1 cat",  To_String (V.Str_Val), "B");

   --  PC-23..PC-24: Max_Rows=2 limits the result to the first two data rows
   Parse_CSV ("tests/data/sample.csv", Max_Rows => 2);
   Check ("PC-23 max_rows=2 row count", Row_Count, 2);
   V := Get_Value (2, "VAL1");
   Check_Float ("PC-24 max_rows=2 row2 VAL1", V.Num_Val, 4.0);

   ---------------------------------------------------------------------------
   --  Parse_ODF tests  (PO-01 .. PO-23)
   ---------------------------------------------------------------------------

   --  PO-01..PO-09: basic load of tests/data/sample.ods
   --  Contents: ID (numeric), NAME$ (string), SALARY (numeric); 3 rows.
   --  Row 1: ID=1, NAME$="Alice", SALARY=50000
   --  Row 2: ID=2, NAME$="Bob",   SALARY=60000
   --  Row 3: ID=3, NAME$="Charlie", SALARY=70000
   Parse_ODF ("tests/data/sample.ods");
   Check ("PO-01 col count",           Column_Count,    3);
   Check ("PO-02 row count",           Row_Count,       3);
   Check ("PO-03 col 1 name",          Column_Name (1), "ID");
   Check ("PO-04 col 2 name",          Column_Name (2), "NAME$");
   Check ("PO-05 col 3 name",          Column_Name (3), "SALARY");
   V := Get_Value (1, "ID");
   Check_Float ("PO-06 row1 ID",          V.Num_Val, 1.0);
   V := Get_Value (2, "NAME$");
   Check      ("PO-07 row2 NAME$ kind",   V.Kind = Val_String, True);
   Check      ("PO-08 row2 NAME$ value",  To_String (V.Str_Val), "Bob");
   V := Get_Value (3, "SALARY");
   Check_Float ("PO-09 row3 SALARY",      V.Num_Val, 70000.0);

   --  PO-10..PO-13: INF values in tests/data/inf_values.ods
   --  Contents: X,Y,Z; row 1 = Pos_Inf, Neg_Inf, 1.5
   Parse_ODF ("tests/data/inf_values.ods");
   V := Get_Value (1, "X");
   Check ("PO-10 INF row1 X kind",    V.Kind = Val_Numeric, True);
   Check ("PO-11 INF row1 X Pos_Inf",
          Is_Inf (V.Num_Val) and then V.Num_Val > 0.0, True);
   V := Get_Value (1, "Y");
   Check ("PO-12 INF row1 Y Neg_Inf",
          Is_Inf (V.Num_Val) and then V.Num_Val < 0.0, True);
   V := Get_Value (2, "Z");
   Check_Float ("PO-13 INF row2 Z normal", V.Num_Val, 2.5);

   --  PO-14..PO-17: sheet selection — "Scores" sheet
   --  Contents: ID (numeric), NAME$ (string), SCORE (numeric); 2 rows.
   --  Row 1: ID=1, NAME$="Alice", SCORE=95
   Parse_ODF ("tests/data/multi_sheet.ods", Sheet_Name => "Scores");
   Check ("PO-14 Scores col count",      Column_Count, 3);
   Check ("PO-15 Scores row count",      Row_Count,    2);
   V := Get_Value (1, "NAME$");
   Check ("PO-16 Scores row1 NAME$",     To_String (V.Str_Val), "Alice");
   V := Get_Value (1, "SCORE");
   Check_Float ("PO-17 Scores row1 SCORE", V.Num_Val, 95.0);

   --  PO-18..PO-19: sheet selection — "Metadata" sheet
   --  Contents: KEY$ (string), VALUE$ (string); 2 rows.
   --  Row 1: KEY$="Version", VALUE$="1.0"
   Parse_ODF ("tests/data/multi_sheet.ods", Sheet_Name => "Metadata");
   Check ("PO-18 Metadata col count",       Column_Count, 2);
   V := Get_Value (1, "KEY$");
   Check ("PO-19 Metadata row1 KEY$",       To_String (V.Str_Val), "Version");

   --  PO-20..PO-21: Skip_Rows=1 skips Alice; row 1 becomes Bob
   Parse_ODF ("tests/data/sample.ods", Skip_Rows => 1);
   Check ("PO-20 skip_rows=1 row count",   Row_Count, 2);
   V := Get_Value (1, "NAME$");
   Check ("PO-21 skip_rows=1 row1 NAME$",  To_String (V.Str_Val), "Bob");

   --  PO-22: Max_Rows=2 limits result to first two data rows
   Parse_ODF ("tests/data/sample.ods", Max_Rows => 2);
   Check ("PO-22 max_rows=2 row count",    Row_Count, 2);

   --  PO-23: corrupt zip file raises SData.Script_Error
   declare
      Raised : Boolean := False;
   begin
      begin
         Parse_ODF ("tests/data/bad.ods");
      exception
         when SData.Script_Error =>
            Raised := True;
      end;
      Check ("PO-23 bad ODS raises Script_Error", Raised, True);
   end;

   ---------------------------------------------------------------------------
   --  Parse_OOXML tests  (PX-01 .. PX-23)
   ---------------------------------------------------------------------------

   --  PX-01..PX-09: basic load of tests/data/sample.xlsx
   --  Same schema as sample.ods: ID (numeric), NAME$ (string), SALARY (numeric); 3 rows.
   Parse_OOXML ("tests/data/sample.xlsx");
   Check ("PX-01 col count",           Column_Count,    3);
   Check ("PX-02 row count",           Row_Count,       3);
   Check ("PX-03 col 1 name",          Column_Name (1), "ID");
   Check ("PX-04 col 2 name",          Column_Name (2), "NAME$");
   Check ("PX-05 col 3 name",          Column_Name (3), "SALARY");
   V := Get_Value (1, "ID");
   Check_Float ("PX-06 row1 ID",          V.Num_Val, 1.0);
   V := Get_Value (2, "NAME$");
   Check      ("PX-07 row2 NAME$ kind",   V.Kind = Val_String, True);
   Check      ("PX-08 row2 NAME$ value",  To_String (V.Str_Val), "Bob");
   V := Get_Value (3, "SALARY");
   Check_Float ("PX-09 row3 SALARY",      V.Num_Val, 70000.0);

   --  PX-10..PX-13: INF values in tests/data/inf_values.xlsx
   Parse_OOXML ("tests/data/inf_values.xlsx");
   V := Get_Value (1, "X");
   Check ("PX-10 INF row1 X kind",    V.Kind = Val_Numeric, True);
   Check ("PX-11 INF row1 X Pos_Inf",
          Is_Inf (V.Num_Val) and then V.Num_Val > 0.0, True);
   V := Get_Value (1, "Y");
   Check ("PX-12 INF row1 Y Neg_Inf",
          Is_Inf (V.Num_Val) and then V.Num_Val < 0.0, True);
   V := Get_Value (2, "Z");
   Check_Float ("PX-13 INF row2 Z normal", V.Num_Val, 2.5);

   --  PX-14..PX-17: sheet selection — "Scores" sheet
   Parse_OOXML ("tests/data/multi_sheet.xlsx", Sheet_Name => "Scores");
   Check ("PX-14 Scores col count",      Column_Count, 3);
   Check ("PX-15 Scores row count",      Row_Count,    2);
   V := Get_Value (1, "NAME$");
   Check ("PX-16 Scores row1 NAME$",     To_String (V.Str_Val), "Alice");
   V := Get_Value (1, "SCORE");
   Check_Float ("PX-17 Scores row1 SCORE", V.Num_Val, 95.0);

   --  PX-18..PX-19: sheet selection — "Metadata" sheet
   Parse_OOXML ("tests/data/multi_sheet.xlsx", Sheet_Name => "Metadata");
   Check ("PX-18 Metadata col count",       Column_Count, 2);
   V := Get_Value (1, "KEY$");
   Check ("PX-19 Metadata row1 KEY$",       To_String (V.Str_Val), "Version");

   --  PX-20..PX-21: Skip_Rows=1 skips Alice; row 1 becomes Bob
   Parse_OOXML ("tests/data/sample.xlsx", Skip_Rows => 1);
   Check ("PX-20 skip_rows=1 row count",   Row_Count, 2);
   V := Get_Value (1, "NAME$");
   Check ("PX-21 skip_rows=1 row1 NAME$",  To_String (V.Str_Val), "Bob");

   --  PX-22: Max_Rows=2 limits result to first two data rows
   Parse_OOXML ("tests/data/sample.xlsx", Max_Rows => 2);
   Check ("PX-22 max_rows=2 row count",    Row_Count, 2);

   --  PX-23: corrupt zip file raises SData.Script_Error
   declare
      Raised : Boolean := False;
   begin
      begin
         Parse_OOXML ("tests/data/bad.xlsx");
      exception
         when SData.Script_Error =>
            Raised := True;
      end;
      Check ("PX-23 bad XLSX raises Script_Error", Raised, True);
   end;

   ---------------------------------------------------------------------------
   --  Summary
   ---------------------------------------------------------------------------
   New_Line;
   Put_Line (Passed'Image & " passed," & Failed'Image & " failed.");
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;

end File_IO_Unit_Test;
