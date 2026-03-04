--  Package SData.Variables implements the Symbol Table for the interpreter.
--  It distinguishes between Temporary (memory only) and Permanent (table-linked) variables.

with SData.Values; use SData.Values;
with SData.Table;  use SData.Table;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Vectors;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
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

   -- PDV Management (PDV stands for Program Data Vector)
   procedure Initialize_PDV;
   procedure Load_PDV_From_Table (Row : Positive);
   procedure Reset_PDV_Non_Held;
   
   package Symbol_Table_Pkg is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type   => Value,
      Hash           => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   function Take_PDV_Snapshot return Symbol_Table_Pkg.Map;

   package Snapshot_Collector is new Ada.Containers.Vectors (Positive, Symbol_Table_Pkg.Map, "=" => Symbol_Table_Pkg."=");

   -- Reconstruct table from snapshots
   procedure Commit_Snapshots_To_Table (Snapshots : Snapshot_Collector.Vector);

   function Get_Type (Name : String) return Value_Kind;
   
   function Get_PDV_Names return GNAT.Strings.String_List_Access;

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

   -- Group Management
   procedure Set_Current_Group_Key (Key : String);
   function Get_Current_Group_Key return String;

   -- Aggregate Management
   -- Stores a pre-calculated aggregate value for a specific variable.
   -- If Group_Key is empty, it's a global aggregate.
   procedure Store_Aggregate (Func_Name, Var_Name, Group_Key : String; Val : Value);
   function Get_Aggregate (Func_Name, Var_Name, Group_Key : String) return Value;
   procedure Clear_Aggregates;

private
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

   Current_Group_ID : Unbounded_String := Null_Unbounded_String;

   -- Holds permanent variables for the current record (PDV).
   Permanent_Symbols : Symbol_Table_Pkg.Map;

   -- Holds pre-calculated aggregate values.
   -- Key format: "FUNC:VAR:GROUP"
   package Aggregate_Table_Pkg is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Value,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");
   Aggregate_Symbols : Aggregate_Table_Pkg.Map;

end SData.Variables;
