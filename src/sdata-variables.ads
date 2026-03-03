--  Package SData.Variables implements the Symbol Table for the interpreter.
--  It distinguishes between Temporary (memory only) and Permanent (table-linked) variables.

with SData.Values; use SData.Values;
with SData.Table;  use SData.Table;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;
with GNAT.Strings;

package SData.Variables is

   --  Creates or updates a temporary variable. Fails if name matches a table column.
   procedure Set_Temporary (Name : String; Val : Value);

   --  Ensures a variable is permanent. If it was temporary, it's moved to the table.
   procedure Set_Permanent (Name : String; Val : Value);

   --  Retrieves a value. Lookup order: 1. Data Table, 2. Temporary symbols.
   function Get (Name : String) return Value;

   --  Removes all temporary variables (called at the end of a RUN).
   procedure Clear_Temporary;

   -- Array Management
   procedure Define_Array (Name : String; Constituents : GNAT.Strings.String_List);
   procedure Define_Array (Name : String; Constituents : Name_Vectors.Vector);
   procedure Define_Array_Access (Name : String; Constituents : GNAT.Strings.String_List_Access);
   function Get_Array_Element (Name : String; Index : Positive) return Value;
   procedure Set_Array_Element (Name : String; Index : Positive; Val : Value);
   function Has_Array (Name : String) return Boolean;

   -- Hold/Unhold Management
   procedure Set_Hold (Name : String; State : Boolean);
   function Is_Held (Name : String) return Boolean;

private
   package Symbol_Table_Pkg is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type   => Value,
      Hash           => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   -- Holds only temporary variables created with SET.
   Temp_Symbols : Symbol_Table_Pkg.Map;

   -- Holds array constituent names.
   package Array_Table_Pkg is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Name_Vectors.Vector,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=",
      "="             => Name_Vectors."=");
   Array_Symbols : Array_Table_Pkg.Map;

   -- Tracks held status.
   package Hold_Table_Pkg is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Boolean,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");
   Hold_Symbols : Hold_Table_Pkg.Map;

end SData.Variables;
