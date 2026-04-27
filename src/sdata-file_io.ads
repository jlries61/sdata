--  Package SData.File_IO implements the File I/O Layer. It provides the capability 
--  to read from and write to various dataset formats: CSV, ODS, and XLSX.
--  It supports automatic format detection and utilizes external utilities (ssconvert)
--  or native logic for specific file types.

with SData.Config; use SData.Config;

package SData.File_IO is

   --  Raised by Write_CSV when Allow_Overwrite = False and the target exists.
   Save_Refused : exception;

   --  Loads a dataset into the global Data Table.
   --  The 'Fmt' parameter serves as a default if format cannot be detected from the extension.
   --  Sheet_Name selects a specific sheet by name in ODF/OOXML files; empty string = first sheet.
   --  Delimiter and Read_Header apply to CSV format only.
   procedure Open_Input (File_Name  : String;
                         Fmt        : Format_Type;
                         Sheet_Name : String    := "";
                         Delimiter  : Character := ',';
                         Read_Header : Boolean  := True);

   --  Writes the current Data Table to a file.
   --  Sheet_Name sets the output sheet name in ODF/OOXML files (default: "Sheet1").
   --  Delimiter, Write_Header, and Allow_Overwrite apply to CSV format only.
   procedure Open_Output (File_Name       : String;
                          Fmt             : Format_Type;
                          Sheet_Name      : String    := "";
                          Delimiter       : Character := ',';
                          Write_Header    : Boolean   := True;
                          Allow_Overwrite : Boolean   := True);

   --  Individual parsers and writers for supported formats.
   procedure Parse_CSV   (File_Name   : String;
                          Delimiter   : Character := ',';
                          Read_Header : Boolean   := True);
   procedure Parse_ODF   (File_Name : String; Sheet_Name : String := ""); -- Handles .ods files
   procedure Parse_OOXML (File_Name : String; Sheet_Name : String := ""); -- Handles .xlsx files

   procedure Write_CSV   (File_Name       : String;
                          Delimiter       : Character := ',';
                          Write_Header    : Boolean   := True;
                          Allow_Overwrite : Boolean   := True);
   procedure Write_ODF   (File_Name : String; Sheet_Name : String := "Sheet1");
   procedure Write_OOXML (File_Name : String; Sheet_Name : String := "Sheet1");

end SData.File_IO;
