--  Package SData.Config holds startup configuration set by the CLI and
--  constant across the lifetime of the process.  Per-run interpreter state
--  that changes during execution (SAVE path, REPEAT mode, FPATH directories)
--  lives in the child package SData.Config.Runtime.

package SData.Config is

   --  Supported file formats for data I/O.
   type Format_Type is (CSV, ODF, OOXML);

   --  The expected format of the input dataset (set via --infmt).
   Input_Format  : Format_Type := CSV;

   --  The desired format for the output dataset (set via --outfmt).
   Output_Format : Format_Type := CSV;

   --  Optional input file from command line (-u).
   Input_File_Path : String (1 .. Max_Path_Len) := (others => ' ');
   Input_File_Len  : Natural := 0;

   --  If True, suppresses informational messages (e.g., "Dataset opened").
   Quiet_Mode    : Boolean := False;

   --  Optional output dataset from command line (-s).
   Output_Dataset_Path : String (1 .. Max_Path_Len) := (others => ' ');
   Output_Dataset_Len  : Natural := 0;

   --  Optional file to redirect console output (set via -o).
   Output_File     : String (1 .. Max_Path_Len) := (others => ' ');
   Output_File_Len : Natural := 0;

   --  DIGITS state (controlling float precision in output).
   Print_Digits  : Natural := 5;

   --  Constraint limits
   Max_Table_Cells : Natural := 0;      -- 0 means no limit; unit is rows × columns
   Max_String_Len  : Natural := 0;      -- 0 means no limit
   Max_Temp_Vars   : Natural := 0;      -- 0 means no limit
   Disable_Shell      : Boolean := False;
   Disable_Submit     : Boolean := False;
   Continue_On_Error  : Boolean := False;
   Ignore_Math_Errors : Boolean := False; -- If True, domain errors return Val_Missing instead of halting.
   Debug_Mode         : Boolean := False; -- If True, trace each statement and record to stderr.

   --  Version information
   Version_Major : constant Natural := 0;
   Version_Minor : constant Natural := 6;
   Version_Patch : constant Natural := 9;
   Version_Str   : constant String :=
      Natural'Image (Version_Major)(2 .. Natural'Image (Version_Major)'Last) & "." &
      Natural'Image (Version_Minor)(2 .. Natural'Image (Version_Minor)'Last) & "." &
      Natural'Image (Version_Patch)(2 .. Natural'Image (Version_Patch)'Last);

end SData.Config;
