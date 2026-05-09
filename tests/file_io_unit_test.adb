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
   pragma Unreferenced (V);

begin
   SData.Config.Quiet_Mode := True;

   ---------------------------------------------------------------------------
   --  Parse_CSV tests  (PC-01 .. PC-24)  — added in Task 2
   ---------------------------------------------------------------------------

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
