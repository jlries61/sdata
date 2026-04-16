--  Package SData.Variables implements the Symbol Table for the interpreter.
--  It distinguishes between Temporary (memory only) and Permanent (table-linked) variables.

with SData.Values; use SData.Values;
with SData.Table;  use SData.Table;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with GNAT.Strings;

package SData.Variables is

   --  Creates or updates a temporary variable. Fails if name matches a table column.
   procedure Set_Temporary (Name : String; Val : Value);

   --  Ensures a variable is permanent. If it was temporary, it's moved to the table.
   procedure Set_Permanent (Name : String; Val : Value);

   --  Retrieves a value. Lookup order: 1. Permanent PDV, 2. Temporary symbols.
   function Get (Name : String) return Value;

   --  Removes a session variable.
   procedure Unset (Name : String);

   --  Removes all temporary variables (called at the end of a RUN).
   procedure Clear_Temporary;

   -- PDV Management (PDV stands for Program Data Vector)
   procedure Initialize_PDV;
   --  Load all table columns for Row into the PDV.
   procedure Load_PDV_From_Table (Row : Positive);
   --  Load a single already-upper-cased column Col_Name for Row into the PDV.
   --  Used by the SELECT filter scan to load only the columns the filter references.
   procedure Load_PDV_One_Column (Row : Positive; Col_Name : String);
   procedure Reset_PDV_Non_Held;
   procedure Refresh_PDV_Names;
   
   package Symbol_Table_Pkg is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type   => Value,
      Hash           => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   -- Flushes the current PDV to the Output Table
   procedure Flush_PDV_To_Output;

   function Get_Type (Name : String) return Value_Kind;
   
   function Get_PDV_Names return GNAT.Strings.String_List_Access;

   function Get_Session_Names return GNAT.Strings.String_List_Access;

   -- Array Management
   -- Defines a virtual array (maps existing variables)
   procedure Define_Array (Name : String; Constituents : GNAT.Strings.String_List);
   procedure Define_Array (Name : String; Constituents : Name_Vectors.Vector); -- For internal use
   procedure Define_Array_Access (Name : String; Constituents : GNAT.Strings.String_List_Access);

   -- Creates or resizes a real array (generates numbered variables)
   procedure Dim_Array (Name : String; Start_Idx, End_Idx : Integer; Is_Temp : Boolean);

   function Get_Array_Element (Name : String; Index : Integer) return Value;
   procedure Set_Array_Element (Name : String; Index : Integer; Val : Value);
   function Has_Array (Name : String) return Boolean;
   
   -- Returns the bounds of an array if it exists.
   procedure Get_Array_Bounds (Name : String; Start_Idx, End_Idx : out Integer);

   -- Hold/Unhold Management
   procedure Set_Hold (Name : String; State : Boolean);
   function Is_Held (Name : String) return Boolean;

   -- Group Management
   procedure Set_Current_Group_Key (Key : String);
   function Get_Current_Group_Key return String;

private
   -- Defines an array, whether virtual or real
   type Array_Kind is (Virtual_Array, Real_Array);

   type Array_Definition_Type is record
      Kind        : Array_Kind;
      Is_Temporary : Boolean := False; -- For Real_Array: If defined with /TEMP
      Start_Index : Integer := 1;      -- For Real_Array: Custom or 1-based
      End_Index   : Integer := 0;      -- For Real_Array: Derived from dimension or custom
      Constituents : Name_Vectors.Vector; -- For Virtual_Array: names of members; For Real_Array: generated names
   end record;
   function "=" (Left, Right : Array_Definition_Type) return Boolean; -- Declare equality operator

   -- Holds only temporary variables created with SET.
   Temp_Symbols : Symbol_Table_Pkg.Map;

   -- Holds array definitions (virtual or real).
   package Array_Table_Pkg is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Array_Definition_Type,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=",
      "="             => "=");
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

end SData.Variables;
