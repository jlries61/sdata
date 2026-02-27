--  Package SData.Config holds global configuration settings and flags for the SData interpreter,
--  typically populated from command-line arguments.

package SData.Config is

   --  Supported file formats for data I/O.
   type Format_Type is (CSV, ODF, OOXML);

   --  The expected format of the input dataset (set via --infmt).
   Input_Format  : Format_Type := CSV;

   --  The desired format for the output dataset (set via --outfmt).
   Output_Format : Format_Type := CSV;
   
   --  If True, suppresses informational messages (e.g., "Dataset opened").
   Quiet_Mode    : Boolean := False;

   --  Optional file to redirect console output (set via -o).
   Output_File   : String (1 .. 1024) := (others => ' ');
   Output_File_Len : Natural := 0;

   --  Pending SAVE operation for the next RUN.
   Save_File_Path  : String (1 .. 1024) := (others => ' ');
   Save_File_Len   : Natural := 0;
   Save_File_Active : Boolean := False;
   Save_File_Fmt    : Format_Type := CSV;

end SData.Config;
