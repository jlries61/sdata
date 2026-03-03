--  Package SData.Table implements the Data Table Manager, providing an in-memory 
--  2D table structure for storing and manipulating records and columns.
--  Columns are typed (Numeric or String) and the table maintains consistency 
--  between rows.

with Ada.Strings.Hash;
with GNAT.Strings;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Vectors;
with SData.Values; use SData.Values;


package SData.Table is

   --  Resets the table state (removes all columns and rows).
   procedure Clear;

   --  Kinds of data allowed in a column.
   type Column_Type is (Col_Numeric, Col_Integer, Col_String);

   --  Defines a new column. If the table already has rows, they are padded with missing values.
   procedure Add_Column (Name : String; Col_Type : Column_Type);

   --  Returns a list of all current column names. 
   --  Note: The caller is responsible for freeing the GNAT.Strings.String_List_Access.
   function Get_Column_Names return GNAT.Strings.String_List_Access;

   --  Checks if a column with the given name (case-insensitive) exists.
   function Has_Column (Name : String) return Boolean;

   --  Returns the number of columns in the table.
   function Column_Count return Natural;

   --  Returns the number of rows (records) in the table.
   function Row_Count return Natural;

   --  Appends a new empty row to the table (all values initialized to Val_Missing).
   procedure Add_Row;

   --  Retrieves the value for a specific row and column.
   function Get_Value (Row : Positive; Column_Name : String) return Value;

   --  Updates the value at a specific row and column. 
   --  Raises Type_Mismatch_Error if the value kind doesn't match the column type.
   procedure Set_Value (Row : Positive; Column_Name : String; Val : Value);

   --  Renames an existing column.
   procedure Rename_Column (Old_Name, New_Name : String);

   --  Removes a column from the table.
   procedure Drop_Column (Name : String);
   
   --  Removes a specific row from the table.
   procedure Drop_Row (Index : Positive);
   
   --  Sets/Gets the pointer to the current record during data step iteration.
   procedure Set_Current_Record_Index (Index : Natural);
   function Get_Current_Record_Index return Natural;
   
   --  Package to store lists of column names.
   package Name_Vectors is new Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Unbounded_String);

   Type_Mismatch_Error : exception;

private
   --  Vector of values for a single column.
   package Value_Vectors is new Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Value);

   --  The internal representation of a column.
   type Column is record
      Name : String (1 .. 32); -- Padded name
      Typ  : Column_Type;      -- Enforced type
      Data : Value_Vectors.Vector; -- List of values (one per row)
   end record;
   
   --  Map from column name (String) to Column record.
   package Column_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type => String,
      Element_Type => Column,
      Hash => Ada.Strings.Hash,
      Equivalent_Keys => "=");
      
   --  The global data table state.
   Data_Table : Column_Maps.Map;

   --  Maintains the insertion order of column names for range expansion.
   Column_Order : Name_Vectors.Vector;
   
   --  Explicit row count (to handle cases where columns haven't been added yet).
   Table_Row_Count : Natural := 0;

   --  Current record pointer for the interpreter.
   Current_Record : Natural := 0;

end SData.Table;
