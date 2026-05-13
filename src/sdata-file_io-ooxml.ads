package SData.File_IO.OOXML is

   procedure Parse_OOXML (File_Name  : String;
                          Sheet_Name : String  := "";
                          Skip_Rows  : Natural := 0;
                          Max_Rows   : Natural := 0);

   procedure Write_OOXML (File_Name  : String;
                          Sheet_Name : String := "Sheet1");

end SData.File_IO.OOXML;
