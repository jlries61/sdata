package SData.System is
   procedure Shell_Execute (Command : String := ""; Success : out Boolean);
   function Running_As_System_Account return Boolean;
end SData.System;
