--  Package SData.Config.Runtime holds interpreter state that changes during
--  execution and is reset to defaults by the NEW command.  Separating it from
--  SData.Config makes the boundary between startup configuration (set once by
--  the CLI) and per-run state (written by the interpreter) explicit.
--
--  Format_Type is inherited from the parent package SData.Config without a
--  separate with-clause.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package SData.Config.Runtime is

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
   Last_Error_Code     : Natural            := 0;
   Last_Error_Line     : Natural            := 0;

   --  OPTIONS command runtime state
   Options_CSVDLM      : Character        := ',';
   Options_Header      : Boolean          := True;
   Options_SAVEOVERWRT : Boolean          := True;
   Options_TXTFMT      : String (1 .. 8)  := "AUTO    ";
   Options_TXTFMT_Len  : Natural          := 4;
   Options_CHARSET     : String (1 .. 64) := (others => ' ');
   Options_CHARSET_Len : Natural          := 0;

   --  Effective delimiter/header saved at SAVE-statement time for use at write time
   Save_DLM    : Character := ',';
   Save_Header : Boolean   := True;

   procedure Reset;

end SData.Config.Runtime;
