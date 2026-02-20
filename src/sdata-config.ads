package SData.Config is
   type Format_Type is (CSV, ODF, OOXML);

   Input_Format  : Format_Type := CSV;
   Output_Format : Format_Type := CSV;
   
   Quiet_Mode    : Boolean := False;
   Output_File   : String (1 .. 1024) := (others => ' ');
   Output_File_Len : Natural := 0;

end SData.Config;
