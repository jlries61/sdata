--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

--  Unit tests for SData_Core.File_IO: Parse_CSV, Parse_ODF, Parse_OOXML.
--  Calls parsers directly with fixture files in tests/data/ and
--  inspects the resulting SData_Core.Table state via the public API.
--  Must be run from the project root (paths are relative to it).

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with SData_Core.Config;
with SData_Core.Table;           use SData_Core.Table;
with SData_Core.Values;          use SData_Core.Values;
with SData_Core.File_IO;
with SData_Core.File_IO.CSV;     use SData_Core.File_IO.CSV;
with SData_Core.File_IO.ODF;     use SData_Core.File_IO.ODF;
with SData_Core.File_IO.OOXML;   use SData_Core.File_IO.OOXML;

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
   SData_Core.Config.Quiet_Mode := True;

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

   --  PC-25..PC-27: unclosed quote — parser recovers; corrupt field stored
   --  with the leading quote character still present in the value.
   --  File: NAME$,SCORE / "Alice,90 / Bob,85
   Parse_CSV ("tests/data/unclosed_quote.csv");
   Check ("PC-25 unclosed-quote col count",  Column_Count, 2);
   Check ("PC-26 unclosed-quote row count",  Row_Count,    2);
   V := Get_Value (2, "NAME$");
   Check ("PC-27 unclosed-quote row2 NAME$", To_String (V.Str_Val), "Bob");

   --  PC-28..PC-31: non-numeric value in numeric column stored as missing.
   --  File: ID,VALUE / 1,10.0 / 2,N/A / 3,30.0
   Parse_CSV ("tests/data/type_mismatch.csv");
   Check ("PC-28 type-mismatch col count",     Column_Count, 2);
   Check ("PC-29 type-mismatch row count",     Row_Count,    3);
   V := Get_Value (2, "VALUE");
   Check ("PC-30 type-mismatch row2 missing",  V.Kind = Val_Missing, True);
   V := Get_Value (3, "VALUE");
   Check_Float ("PC-31 type-mismatch row3 ok", V.Num_Val, 30.0);

   --  PC-32..PC-36: ragged rows — short and long rows.
   --  File: A,B,C / 1,2,3 / 4,5 / 6,7,8,9
   Parse_CSV ("tests/data/ragged_rows.csv");
   Check ("PC-32 ragged col count",        Column_Count, 3);
   Check ("PC-33 ragged row count",        Row_Count,    3);
   V := Get_Value (2, "C");
   Check ("PC-34 short-row missing C",     V.Kind = Val_Missing, True);
   V := Get_Value (3, "A");
   Check_Float ("PC-35 long-row A ok",     V.Num_Val, 6.0);
   V := Get_Value (3, "C");
   Check_Float ("PC-36 long-row C ok",     V.Num_Val, 8.0);

   ---------------------------------------------------------------------------
   --  PC-37..PC-40: SQLite spill path during Parse_CSV.
   --  sample.csv: 4 columns, 6 data rows.
   --  Max_Table_Cells=8 → Add_Row spills every 2 rows.
   --  After load: rows 1-2 and 3-4 in SQLite; rows 5-6 in memory.
   --  All 6 rows must be accessible via Fetch_From_Disk / in-memory.
   ---------------------------------------------------------------------------
   declare
      Saved_Cap : constant Natural := SData_Core.Config.Max_Table_Cells;
   begin
      SData_Core.Config.Max_Table_Cells := 8;
      Parse_CSV ("tests/data/sample.csv");
      SData_Core.Config.Max_Table_Cells := Saved_Cap;
   end;
   Check ("PC-37 spill row count",           Row_Count,    6);
   Check ("PC-38 spill col count",           Column_Count, 4);
   V := Get_Value (1, "VAL1");
   Check_Float ("PC-39 spill row1 from disk",   V.Num_Val, 1.0);
   V := Get_Value (3, "VAL1");
   Check_Float ("PC-40 spill row3 from disk",   V.Num_Val, 7.0);

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

   --  PO-23: corrupt zip file raises SData_Core.Script_Error
   declare
      Raised : Boolean := False;
   begin
      begin
         Parse_ODF ("tests/data/bad.ods");
      exception
         when SData_Core.Script_Error =>
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

   --  PX-23: corrupt zip file raises SData_Core.Script_Error
   declare
      Raised : Boolean := False;
   begin
      begin
         Parse_OOXML ("tests/data/bad.xlsx");
      exception
         when SData_Core.Script_Error =>
            Raised := True;
      end;
      Check ("PX-23 bad XLSX raises Script_Error", Raised, True);
   end;

   --  PX-24: OOXML file with no workbook.xml falls back to sheet1.xml.
   --  Exercises the Zip.Entry_name_not_found suppression path in
   --  Find_Sheet_XML_Path (lines 1269, 1314 of sdata-file_io.adb).
   SData_Core.Table.Clear;
   Parse_OOXML ("tests/data/no_workbook.xlsx");
   Check ("PX-24 no-workbook xlsx row count", Row_Count, 1);
   Check ("PX-24 no-workbook xlsx A1 = 77",
          Integer (SData_Core.Table.Get_Value (1, "A").Num_Val), 77);
   Check ("PX-24 no-workbook xlsx B1 = 88",
          Integer (SData_Core.Table.Get_Value (1, "B").Num_Val), 88);

   ---------------------------------------------------------------------------
   --  NSC-* : numeric-looking values in a '$' (Col_String) column must load
   --  as STRINGS across all three readers, not abort (CSV) or be dropped to
   --  missing (ODF/OOXML).  Regression for the adultdata1 'fnlwgt$' bug: a
   --  CSV header of "fnlwgt$" forces Col_String, but cells like 77516 were
   --  built as Val_Numeric and rejected by the table's type coercion.
   --  Fixtures: tests/data/numeric_string_col.{csv,ods,xlsx}, header LABEL$,N
   --  with LABEL$ holding 77516 / 83311.
   ---------------------------------------------------------------------------

   --  NSC-CSV: load must not raise, and LABEL$ must hold the text "77516".
   declare
      Loaded_OK : Boolean := True;
   begin
      SData_Core.Table.Clear;
      begin
         Parse_CSV ("tests/data/numeric_string_col.csv");
      exception
         when E : others =>
            Loaded_OK := False;
            Put_Line ("   (CSV raised: "
               & Ada.Exceptions.Exception_Message (E) & ")");
      end;
      Check ("NSC-CSV-01 loads without type error", Loaded_OK, True);
      if Loaded_OK then
         Check ("NSC-CSV-02 col 1 name", Column_Name (1), "LABEL$");
         V := Get_Value (1, "LABEL$");
         Check ("NSC-CSV-03 row1 LABEL$ kind", V.Kind = Val_String, True);
         Check ("NSC-CSV-04 row1 LABEL$ value", To_String (V), "77516");
         V := Get_Value (2, "LABEL$");
         Check ("NSC-CSV-05 row2 LABEL$ value", To_String (V), "83311");
      end if;
   end;

   --  NSC-ODF: same, via the ODS reader (cell is office:value-type="float").
   SData_Core.Table.Clear;
   Parse_ODF ("tests/data/numeric_string_col.ods");
   Check ("NSC-ODF-01 col 1 name", Column_Name (1), "LABEL$");
   V := Get_Value (1, "LABEL$");
   Check ("NSC-ODF-02 row1 LABEL$ kind", V.Kind = Val_String, True);
   Check ("NSC-ODF-03 row1 LABEL$ value", To_String (V), "77516");

   --  NSC-OOXML: same, via the XLSX reader (cell is t="n").
   SData_Core.Table.Clear;
   Parse_OOXML ("tests/data/numeric_string_col.xlsx");
   Check ("NSC-XLSX-01 col 1 name", Column_Name (1), "LABEL$");
   V := Get_Value (1, "LABEL$");
   Check ("NSC-XLSX-02 row1 LABEL$ kind", V.Kind = Val_String, True);
   Check ("NSC-XLSX-03 row1 LABEL$ value", To_String (V), "77516");

   ---------------------------------------------------------------------------
   --  RT-* : CSV writer round-trip precision (SAVE /DECIMALS design).
   ---------------------------------------------------------------------------

   --  Round-trip default: a value 6-digit Float'Image would corrupt survives.
   --  Observe the read-back Float value directly (the writer stored it at
   --  round-trip precision), not via To_String.
   Parse_CSV ("tests/data/precision_src.csv");
   SData_Core.File_IO.Open_Output ("tests/data/rt_out.csv", SData_Core.Config.CSV);
   Parse_CSV ("tests/data/rt_out.csv");
   V := Get_Value (1, "X");
   Check ("CSV round-trip preserves X", V.Num_Val = Float'(123456.789), True);

   --  /DECIMALS=2 rounds the stored CSV text; the read-back Float is 3.14.
   Parse_CSV ("tests/data/precision_src.csv");
   SData_Core.File_IO.Open_Output ("tests/data/dec_out.csv", SData_Core.Config.CSV,
                                   Decimals => 2);
   Parse_CSV ("tests/data/dec_out.csv");
   V := Get_Value (2, "X");   --  row 2 X = 3.14159 -> DECIMALS=2 -> 3.14
   Check ("CSV DECIMALS=2 rounds X to 3.14", V.Num_Val = Float'(3.14), True);

   --  ODF keeps full precision in office:value regardless of /DECIMALS.
   Parse_CSV ("tests/data/precision_src.csv");
   SData_Core.File_IO.Open_Output ("tests/data/dec_out.ods", SData_Core.Config.ODF,
                                   Decimals => 2);
   Parse_ODF ("tests/data/dec_out.ods");
   V := Get_Value (1, "X");
   Check ("ODF stored value stays full precision",
          V.Num_Val = Float'(123456.789), True);

   --  OOXML keeps full precision in <v> regardless of /DECIMALS.
   Parse_CSV ("tests/data/precision_src.csv");
   SData_Core.File_IO.Open_Output ("tests/data/dec_out.xlsx", SData_Core.Config.OOXML,
                                   Decimals => 2);
   Parse_OOXML ("tests/data/dec_out.xlsx");
   V := Get_Value (1, "X");
   Check ("OOXML stored value stays full precision",
          V.Num_Val = Float'(123456.789), True);

   ---------------------------------------------------------------------------
   --  Summary
   ---------------------------------------------------------------------------
   New_Line;
   Put_Line (Passed'Image & " passed," & Failed'Image & " failed.");
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;

end File_IO_Unit_Test;