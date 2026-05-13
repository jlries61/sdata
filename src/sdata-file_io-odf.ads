package SData.File_IO.ODF is

   procedure Parse_ODF (File_Name  : String;
                        Sheet_Name : String  := "";
                        Skip_Rows  : Natural := 0;
                        Max_Rows   : Natural := 0);

   procedure Write_ODF (File_Name  : String;
                        Sheet_Name : String := "Sheet1");

end SData.File_IO.ODF;
