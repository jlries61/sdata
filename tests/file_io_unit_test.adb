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
   --  Parse_ODF tests  (PO-01 .. PO-23)  — added in Task 3
   ---------------------------------------------------------------------------

   ---------------------------------------------------------------------------
   --  Parse_OOXML tests  (PX-01 .. PX-23)  — added in Task 4
   ---------------------------------------------------------------------------

   ---------------------------------------------------------------------------
   --  Summary
   ---------------------------------------------------------------------------
   New_Line;
   Put_Line (Passed'Image & " passed," & Failed'Image & " failed.");
   if Failed > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;

end File_IO_Unit_Test;
