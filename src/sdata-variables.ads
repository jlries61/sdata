--  Package SData.Variables implements the Symbol Table for the interpreter.
--  It manages a global set of variables (independent of the Data Table)
--  using a hashed map for efficient lookup and storage of 'Value' records.

with SData.Values; use SData.Values;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;

package SData.Variables is

   --  Creates or updates a variable with the given name and value.
   procedure Set (Name : String; Val : Value);

   --  Retrieves the value of a variable. Returns Val_Missing if the variable is undefined.
   function Get (Name : String) return Value;

private
   --  The underlying map structure for the symbol table.
   package Symbol_Table_Pkg is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type   => Value,
      Hash           => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   --  The global symbol table state.
   Symbols : Symbol_Table_Pkg.Map;

end SData.Variables;
