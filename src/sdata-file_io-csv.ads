package SData.File_IO.CSV is

   procedure Parse_CSV (File_Name   : String;
                        Delimiter   : String  := ",";
                        Read_Header : Boolean := True;
                        Charset     : String  := "";
                        Skip_Rows   : Natural := 0;
                        Max_Rows    : Natural := 0;
                        Nscan_Rows  : Natural := 0);

   procedure Write_CSV (File_Name       : String;
                        Delimiter       : String  := ",";
                        Write_Header    : Boolean := True;
                        Allow_Overwrite : Boolean := True;
                        Charset         : String  := "");

end SData.File_IO.CSV;
