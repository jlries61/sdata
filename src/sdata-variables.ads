--  Package SData.Variables implements the Symbol Table for the interpreter.
--  It distinguishes between Temporary (memory only) and Permanent (table-linked) variables.

with SData.Values; use SData.Values;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;

package SData.Variables is

   --  Creates or updates a temporary variable. Fails if name matches a table column.
   procedure Set_Temporary (Name : String; Val : Value);

   --  Ensures a variable is permanent. If it was temporary, it's moved to the table.
   procedure Set_Permanent (Name : String; Val : Value);

   --  Retrieves a value. Lookup order: 1. Data Table, 2. Temporary symbols.
   function Get (Name : String) return Value;

   --  Removes all temporary variables (called at the end of a RUN).
   procedure Clear_Temporary;

private
   package Symbol_Table_Pkg is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type   => Value,
      Hash           => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   -- Holds only temporary variables created with SET.
   Temp_Symbols : Symbol_Table_Pkg.Map;

end SData.Variables;
