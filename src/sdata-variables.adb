with Ada.Characters.Handling; use Ada.Characters.Handling;
with SData.Table;           use SData.Table;

package body SData.Variables is

   procedure Set (Name : String; Val : Value) is
      Upper_Name : constant String := To_Upper (Name);
   begin
      if Symbols.Contains (Upper_Name) then
         Symbols.Replace (Upper_Name, Val);
      else
         Symbols.Insert (Upper_Name, Val);
      end if;
   end Set;

   function Get (Name : String) return Value is
      Upper_Name : constant String := To_Upper (Name);
   begin
      if Get_Current_Record_Index > 0 then
         declare
            Val : constant Value := Get_Value (Get_Current_Record_Index, Upper_Name);
         begin
            if Val.Kind /= Val_Missing then
               return Val;
            end if;
         end;
      end if;

      if Symbols.Contains (Upper_Name) then
         return Symbols.Element (Upper_Name);
      else
         return (Kind => Val_Missing);
      end if;
   end Get;

end SData.Variables;
