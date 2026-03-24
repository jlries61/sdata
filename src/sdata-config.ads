--  Package SData.Config holds global configuration settings and flags for the SData interpreter,
--  typically populated from command-line arguments.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package SData.Config is

   --  Supported file formats for data I/O.
   type Format_Type is (CSV, ODF, OOXML);

   --  The expected format of the input dataset (set via --infmt).
   Input_Format  : Format_Type := CSV;

   --  The desired format for the output dataset (set via --outfmt).
   Output_Format : Format_Type := CSV;

   --  Optional input file from command line (-u).
   Input_File_Path : String (1 .. 1024) := (others => ' ');
   Input_File_Len  : Natural := 0;
   
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

   --  FPATH settings
   FPath_Use    : Unbounded_String := Null_Unbounded_String;
   FPath_Save   : Unbounded_String := Null_Unbounded_String;
   FPath_Submit : Unbounded_String := Null_Unbounded_String;
   FPath_Output : Unbounded_String := Null_Unbounded_String;

   --  REPEAT state.
   Repeat_Count  : Natural := 0;
   Repeat_Active : Boolean := False;

   --  DIGITS state (controlling float precision in output).
   Print_Digits  : Natural := 5;

   --  Constraint limits
   Max_Table_Rows  : Natural := 0;      -- 0 means no limit
   Max_String_Len  : Natural := 0;      -- 0 means no limit
   Max_Temp_Vars   : Natural := 0;      -- 0 means no limit
   Disable_Shell      : Boolean := False;
   Continue_On_Error  : Boolean := False;
   Ignore_Math_Errors : Boolean := False; -- If True, domain errors return Val_Missing instead of halting.

   --  Version information
   Version_Major : constant := 0;
   Version_Minor : constant := 2;
   Version_Patch : constant := 0;
   Version_Str   : constant String := "0.2.0";

end SData.Config;
