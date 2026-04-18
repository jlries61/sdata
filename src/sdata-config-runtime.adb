package body SData.Config.Runtime is

   procedure Reset is
   begin
      Save_File_Path      := (others => ' ');
      Save_File_Len       := 0;
      Save_File_Active    := False;
      Save_File_Fmt       := CSV;
      Save_Sheet_Name     := (others => ' ');
      Save_Sheet_Name_Len := 0;
      FPath_Use           := Null_Unbounded_String;
      FPath_Save          := Null_Unbounded_String;
      FPath_Submit        := Null_Unbounded_String;
      FPath_Output        := Null_Unbounded_String;
      Repeat_Count        := 0;
      Repeat_Active       := False;
   end Reset;

end SData.Config.Runtime;
