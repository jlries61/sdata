with Ada.Environment_Variables;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with GNAT.OS_Lib; use GNAT.OS_Lib;

package body SData.System is

   procedure Shell_Execute (Command : String := ""; Success : out Boolean) is
      Shell : constant String := (if Ada.Environment_Variables.Exists ("SHELL") then Ada.Environment_Variables.Value ("SHELL")
                                  elsif Ada.Environment_Variables.Exists ("COMSPEC") then Ada.Environment_Variables.Value ("COMSPEC")
                                  else "/bin/sh");
   begin
      if Command = "" then
         GNAT.OS_Lib.Spawn (Shell, (1 .. 0 => null), Success);
      else
         declare
            Is_Windows : constant Boolean := (Shell'Length >= 7 and then To_Upper(Shell(Shell'Last-6..Shell'Last)) = "CMD.EXE") 
                                             or else (Shell'Length >= 3 and then To_Upper(Shell(Shell'Last-2..Shell'Last)) = "CMD");
            Arg : constant String := (if Is_Windows then "/c" else "-c");
            Args : GNAT.OS_Lib.Argument_List := (new String'(Arg), new String'(Command));
         begin
            GNAT.OS_Lib.Spawn (Shell, Args, Success);
            for I in Args'Range loop Free (Args (I)); end loop;
         end;
      end if;
   end Shell_Execute;

end SData.System;
