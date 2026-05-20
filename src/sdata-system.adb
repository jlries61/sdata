--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

--  Thin wrapper: all logic lives in SData_Core.System.
--  sdata_privilege.c (and its C import) are owned by the sdata_core library.

with SData_Core.System;

package body SData.System is

   procedure Shell_Execute (Command : String := ""; Success : out Boolean) is
   begin
      SData_Core.System.Shell_Execute (Command, Success);
   end Shell_Execute;

   function Running_As_System_Account return Boolean is
   begin
      return SData_Core.System.Running_As_System_Account;
   end Running_As_System_Account;

end SData.System;
