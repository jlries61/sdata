with SData.Table; use SData.Table;
with SData.Config; use SData.Config;

package SData.File_IO is

   -- Open a dataset for reading, populating the given Table.
   procedure Open_Input (File_Name : String; Fmt : Format_Type);

   -- Open a dataset for writing – creates/overwrites the file.
   procedure Open_Output (File_Name : String; Fmt : Format_Type);

   -- Minimal implementation supporting a single worksheet.
   procedure Parse_CSV   (File_Name : String);
   procedure Parse_ODF   (File_Name : String);
   procedure Parse_OOXML (File_Name : String);
   
   procedure Write_CSV   (File_Name : String);
   procedure Write_ODF   (File_Name : String);
   procedure Write_OOXML (File_Name : String);

end SData.File_IO;
