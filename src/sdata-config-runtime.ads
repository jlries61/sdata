--  Package SData.Config.Runtime holds interpreter state that changes during
--  execution and is reset to defaults by the NEW command.  Separating it from
--  SData.Config makes the boundary between startup configuration (set once by
--  the CLI) and per-run state (written by the interpreter) explicit.
--
--  Format_Type is inherited from the parent package SData.Config without a
--  separate with-clause.

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package SData.Config.Runtime is

   Save_File_Path      : String (1 .. Max_Path_Len)       := (others => ' ');
   Save_File_Len       : Natural                           := 0;
   Save_File_Active    : Boolean                           := False;
   Save_File_Fmt       : Format_Type                       := CSV;
   Save_Sheet_Name     : String (1 .. Max_Sheet_Name_Len)  := (others => ' ');
   Save_Sheet_Name_Len : Natural                           := 0;
   FPath_Use           : Unbounded_String                  := Null_Unbounded_String;
   FPath_Save          : Unbounded_String                  := Null_Unbounded_String;
   FPath_Submit        : Unbounded_String                  := Null_Unbounded_String;
   FPath_Output        : Unbounded_String                  := Null_Unbounded_String;
   Repeat_Count        : Natural                           := 0;
   Repeat_Active       : Boolean                           := False;
   Last_Error_Code     : Natural                           := 0;
   Last_Error_Line     : Natural                           := 0;

   --  OPTIONS command runtime state
   Options_CSVDLM      : String (1 .. Max_Delimiter_Len)  := (',' , others => ' ');
   Options_CSVDLM_Len  : Natural                          := 1;
   Options_Header      : Boolean                          := True;
   Options_SAVEOVERWRT : Boolean                          := True;
   Options_TXTFMT      : String (1 .. Max_Delimiter_Len)  := "AUTO    ";
   Options_TXTFMT_Len  : Natural                          := 4;
   Options_CHARSET     : String (1 .. Max_Charset_Len)    := (others => ' ');
   Options_CHARSET_Len : Natural                          := 0;
   IEEE_Divide         : Boolean                          := False;
   Options_Shell_Timeout : Natural                        := 0;

   --  Effective delimiter/header/charset saved at SAVE-statement time for use at write time
   Save_DLM         : String (1 .. Max_Delimiter_Len)  := (',' , others => ' ');
   Save_DLM_Len     : Natural                          := 1;
   Save_Header      : Boolean                          := True;
   Save_Charset     : String (1 .. Max_Charset_Len)    := (others => ' ');
   Save_Charset_Len : Natural                          := 0;

   procedure Reset;

end SData.Config.Runtime;
