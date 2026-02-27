with Ada.Characters.Handling; use Ada.Characters.Handling;
with SData.Table;           use SData.Table;

package body SData.Variables is

   ---------
   -- Set --
   ---------
   --  Saves a value to the global symbol table (names are case-insensitive).
   procedure Set (Name : String; Val : Value) is
      Upper_Name : constant String := To_Upper (Name);
   begin
      if Symbols.Contains (Upper_Name) then
         Symbols.Replace (Upper_Name, Val);
      else
         Symbols.Insert (Upper_Name, Val);
      end if;
   end Set;

   ---------
   -- Get --
   ---------
   --  Retrieves a value. Lookup order: 
   --  1. Current record in the Data Table (if iterating).
   --  2. Global symbol table.
   function Get (Name : String) return Value is
      Upper_Name : constant String := To_Upper (Name);
   begin
      --  First, check if we are in a Data Step and if the name matches a column.
      if Get_Current_Record_Index > 0 then
         declare
            Val : constant Value := Get_Value (Get_Current_Record_Index, Upper_Name);
         begin
            if Val.Kind /= Val_Missing then
               return Val;
            end if;
         end;
      end if;

      --  Otherwise, look for the variable in the global symbol table.
      if Symbols.Contains (Upper_Name) then
         return Symbols.Element (Upper_Name);
      else
         --  If not found, return an explicit Missing value.
         return (Kind => Val_Missing);
      end if;
   end Get;

end SData.Variables;
