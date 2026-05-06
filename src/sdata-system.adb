with Ada.Environment_Variables;
with GNAT.OS_Lib; use GNAT.OS_Lib;
with Interfaces.C; use type Interfaces.C.int;

package body SData.System is

   Is_Windows : constant Boolean := GNAT.OS_Lib.Directory_Separator = '\';

   function C_Is_System_Account return Interfaces.C.int;
   pragma Import (C, C_Is_System_Account, "sdata_is_system_account");

   function Running_As_System_Account return Boolean is
   begin
      return C_Is_System_Account /= 0;
   end Running_As_System_Account;

   --  Resolve the shell to use for SYSTEM/SHELL invocations.
   --  Posix is True when the resolved shell takes "-c" (POSIX shells),
   --  False when it takes "/c" (cmd.exe). Path must be Free'd by caller.
   --
   --  On Windows we look up bash and sh on PATH first so that MSYS/MinGW
   --  installations get POSIX quoting semantics; we only fall back to
   --  COMSPEC/cmd.exe when no POSIX shell is available. SHELL is not
   --  consulted because under MSYS it may carry a Unix-style path
   --  ("/usr/bin/bash") that the native Windows process loader cannot
   --  resolve.
   --
   --  On non-Windows we use /bin/sh for "-c" execution to avoid sourcing
   --  the user's login profile, matching the previous behaviour.
   procedure Resolve_Shell (Path  : out GNAT.OS_Lib.String_Access;
                            Posix : out Boolean) is
   begin
      if Is_Windows then
         Path := GNAT.OS_Lib.Locate_Exec_On_Path ("bash");
         if Path = null then
            Path := GNAT.OS_Lib.Locate_Exec_On_Path ("sh");
         end if;
         if Path /= null then
            Posix := True;
            return;
         end if;
         declare
            Comspec : constant String :=
               (if Ada.Environment_Variables.Exists ("COMSPEC")
                then Ada.Environment_Variables.Value ("COMSPEC")
                else "cmd.exe");
         begin
            Path  := new String'(Comspec);
            Posix := False;
         end;
      else
         Path  := new String'("/bin/sh");
         Posix := True;
      end if;
   end Resolve_Shell;

   --  Resolve an interactive shell (no command). Honours SHELL on
   --  non-Windows; on Windows prefers bash, then sh, then COMSPEC.
   --  Path must be Free'd by caller.
   procedure Resolve_Interactive_Shell (Path : out GNAT.OS_Lib.String_Access) is
      Posix_Unused : Boolean;
   begin
      if Is_Windows then
         Resolve_Shell (Path, Posix_Unused);
      else
         declare
            Shell : constant String :=
               (if Ada.Environment_Variables.Exists ("SHELL")
                then Ada.Environment_Variables.Value ("SHELL")
                else "/bin/sh");
         begin
            Path := new String'(Shell);
         end;
      end if;
   end Resolve_Interactive_Shell;

   procedure Shell_Execute (Command : String := ""; Success : out Boolean) is
   begin
      if Command = "" then
         declare
            Path : GNAT.OS_Lib.String_Access;
         begin
            Resolve_Interactive_Shell (Path);
            GNAT.OS_Lib.Spawn (Path.all, (1 .. 0 => null), Success);
            Free (Path);
         end;
      else
         declare
            Path  : GNAT.OS_Lib.String_Access;
            Posix : Boolean;
         begin
            Resolve_Shell (Path, Posix);
            declare
               Arg  : constant String := (if Posix then "-c" else "/c");
               Args : GNAT.OS_Lib.Argument_List :=
                  (new String'(Arg), new String'(Command));
            begin
               GNAT.OS_Lib.Spawn (Path.all, Args, Success);
               for I in Args'Range loop Free (Args (I)); end loop;
            end;
            Free (Path);
         end;
      end if;
   end Shell_Execute;

end SData.System;
