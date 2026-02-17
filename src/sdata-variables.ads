with SData.Values; use SData.Values;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;

package SData.Variables is

   procedure Set (Name : String; Val : Value);
   function Get (Name : String) return Value;

private
   package Symbol_Table_Pkg is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type   => Value,
      Hash           => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   Symbols : Symbol_Table_Pkg.Map;

end SData.Variables;
