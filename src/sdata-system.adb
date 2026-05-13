with Ada.Environment_Variables;
with Ada.Text_IO;
with GNAT.OS_Lib; use GNAT.OS_Lib;
with Interfaces.C; use type Interfaces.C.int;
with SData.Config.Runtime;

package body SData.System is

   Is_Windows    : constant Boolean := GNAT.OS_Lib.Directory_Separator = '\';
   Timeout_Warned : Boolean := False;

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
         --  Interactive shell: no timeout applied.
         declare
            Path : GNAT.OS_Lib.String_Access;
         begin
            Resolve_Interactive_Shell (Path);
            GNAT.OS_Lib.Spawn (Path.all, (1 .. 0 => null), Success);
            Free (Path);
         end;
      else
         declare
            Timeout_Val : constant Natural :=
               SData.Config.Runtime.Options_Shell_Timeout;
            Path      : GNAT.OS_Lib.String_Access;
            Posix     : Boolean;
            Exit_Code : Integer;
         begin
            Resolve_Shell (Path, Posix);
            declare
               Shell_Arg : constant String :=
                  (if Posix then "-c" else "/c");

               --  Escape a string for embedding in a PowerShell single-quoted
               --  string literal (replace each ' with '').
               function Escape_PS (S : String) return String is
                  Result : String (1 .. S'Length * 2);
                  Pos    : Natural := 0;
               begin
                  for Ch of S loop
                     if Ch = ''' then
                        Pos := Pos + 1; Result (Pos) := ''';
                        Pos := Pos + 1; Result (Pos) := ''';
                     else
                        Pos := Pos + 1; Result (Pos) := Ch;
                     end if;
                  end loop;
                  return Result (1 .. Pos);
               end Escape_PS;

            begin
               if Timeout_Val > 0 and then not Is_Windows then
                  declare
                     TO_Path : GNAT.OS_Lib.String_Access :=
                        GNAT.OS_Lib.Locate_Exec_On_Path ("timeout");
                  begin
                     if TO_Path /= null then
                        declare
                           T_Img : constant String := Timeout_Val'Image;
                           T_Str : constant String :=
                              T_Img (T_Img'First + 1 .. T_Img'Last);
                           Args : GNAT.OS_Lib.Argument_List :=
                              (new String'(T_Str),
                               new String'(Path.all),
                               new String'(Shell_Arg),
                               new String'(Command));
                        begin
                           Exit_Code :=
                              GNAT.OS_Lib.Spawn (TO_Path.all, Args);
                           for I in Args'Range loop
                              Free (Args (I));
                           end loop;
                        end;
                        Free (TO_Path);
                     else
                        if not Timeout_Warned then
                           Ada.Text_IO.Put_Line
                              (Ada.Text_IO.Standard_Error,
                               "Warning: 'timeout' not found on PATH; "
                               & "SHELLTIMEOUT has no effect.");
                           Timeout_Warned := True;
                        end if;
                        declare
                           Args : GNAT.OS_Lib.Argument_List :=
                              (new String'(Shell_Arg),
                               new String'(Command));
                        begin
                           Exit_Code :=
                              GNAT.OS_Lib.Spawn (Path.all, Args);
                           for I in Args'Range loop
                              Free (Args (I));
                           end loop;
                        end;
                     end if;
                  end;
               elsif Timeout_Val > 0 then
                  --  Windows: wrap via PowerShell so we can kill on expiry.
                  --  Try pwsh (PS 7+) first, then powershell (PS 5.x).
                  declare
                     PS_Path : GNAT.OS_Lib.String_Access :=
                        GNAT.OS_Lib.Locate_Exec_On_Path ("pwsh");
                  begin
                     if PS_Path = null then
                        PS_Path :=
                           GNAT.OS_Lib.Locate_Exec_On_Path ("powershell");
                     end if;
                     if PS_Path /= null then
                        declare
                           T_Ms_Img : constant String :=
                              Natural'Image (Timeout_Val * 1_000);
                           T_Ms_Str : constant String :=
                              T_Ms_Img (T_Ms_Img'First + 1 .. T_Ms_Img'Last);
                           PS_Script : constant String :=
                              "$p = Start-Process '"
                              & Escape_PS (Path.all)
                              & "' -ArgumentList '"
                              & Shell_Arg
                              & "', '"
                              & Escape_PS (Command)
                              & "' -PassThru -NoNewWindow;"
                              & " if (-not $p.WaitForExit("
                              & T_Ms_Str
                              & ")) { Stop-Process -Id $p.Id -Force; exit 124 }"
                              & " else { exit $p.ExitCode }";
                           PS_Args : GNAT.OS_Lib.Argument_List :=
                              (new String'("-NonInteractive"),
                               new String'("-Command"),
                               new String'(PS_Script));
                        begin
                           Exit_Code :=
                              GNAT.OS_Lib.Spawn (PS_Path.all, PS_Args);
                           for I in PS_Args'Range loop
                              Free (PS_Args (I));
                           end loop;
                        end;
                        Free (PS_Path);
                     else
                        if not Timeout_Warned then
                           Ada.Text_IO.Put_Line
                              (Ada.Text_IO.Standard_Error,
                               "Warning: 'powershell' not found on PATH; "
                               & "SHELLTIMEOUT has no effect.");
                           Timeout_Warned := True;
                        end if;
                        declare
                           Args : GNAT.OS_Lib.Argument_List :=
                              (new String'(Shell_Arg), new String'(Command));
                        begin
                           Exit_Code :=
                              GNAT.OS_Lib.Spawn (Path.all, Args);
                           for I in Args'Range loop
                              Free (Args (I));
                           end loop;
                        end;
                     end if;
                  end;
               else
                  declare
                     Args : GNAT.OS_Lib.Argument_List :=
                        (new String'(Shell_Arg), new String'(Command));
                  begin
                     Exit_Code := GNAT.OS_Lib.Spawn (Path.all, Args);
                     for I in Args'Range loop Free (Args (I)); end loop;
                  end;
               end if;
            end;
            Free (Path);
            if Exit_Code = 124 then
               declare
                  T_Img : constant String := Timeout_Val'Image;
                  T_Str : constant String :=
                     T_Img (T_Img'First + 1 .. T_Img'Last);
               begin
                  raise Script_Error with
                     "SYSTEM command timed out after " & T_Str & " seconds";
               end;
            end if;
            Success := (Exit_Code = 0);
         end;
      end if;
   end Shell_Execute;

end SData.System;
