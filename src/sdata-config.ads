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

   --  REPEAT state.
   Repeat_Count  : Natural := 0;
   Repeat_Active : Boolean := False;

   --  Runtime state (reset by NEW)
   type Runtime_State_Record is record
      Save_File_Path      : String (1 .. 1024) := (others => ' ');
      Save_File_Len       : Natural            := 0;
      Save_File_Active    : Boolean            := False;
      Save_File_Fmt       : Format_Type        := CSV;
      Save_Sheet_Name     : String (1 .. 64)   := (others => ' ');
      Save_Sheet_Name_Len : Natural            := 0;
      FPath_Use           : Unbounded_String   := Null_Unbounded_String;
      FPath_Save          : Unbounded_String   := Null_Unbounded_String;
      FPath_Submit        : Unbounded_String   := Null_Unbounded_String;
      FPath_Output        : Unbounded_String   := Null_Unbounded_String;
      Repeat_Count        : Natural            := 0;
      Repeat_Active       : Boolean            := False;
   end record;

   Runtime : Runtime_State_Record;

   procedure Reset_Runtime_State;

   --  DIGITS state (controlling float precision in output).

   --  DIGITS state (controlling float precision in output).
   Print_Digits  : Natural := 5;

   --  Constraint limits
   Max_Table_Rows  : Natural := 0;      -- 0 means no limit
   Max_String_Len  : Natural := 0;      -- 0 means no limit
   Max_Temp_Vars   : Natural := 0;      -- 0 means no limit
   Disable_Shell      : Boolean := False;
   Continue_On_Error  : Boolean := False;
   Ignore_Math_Errors : Boolean := False; -- If True, domain errors return Val_Missing instead of halting.
   Debug_Mode         : Boolean := False; -- If True, trace each statement and record to stderr.

   --  Version information
   Version_Major : constant Natural := 0;
   Version_Minor : constant Natural := 5;
   Version_Patch : constant Natural := 1;
   Version_Str   : constant String :=
      Natural'Image (Version_Major)(2 .. Natural'Image (Version_Major)'Last) & "." &
      Natural'Image (Version_Minor)(2 .. Natural'Image (Version_Minor)'Last) & "." &
      Natural'Image (Version_Patch)(2 .. Natural'Image (Version_Patch)'Last);

end SData.Config;
