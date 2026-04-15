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


with Ada.Finalization;
with Ada_Sqlite3;
with Ada.Unchecked_Deallocation;

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
   function Get_Value_Upper (Row : Positive; Upper_Name : String) return Value;

   --  Updates the value at a specific row and column. 
   --  Raises Type_Mismatch_Error if the value kind doesn't match the column type.
   procedure Set_Value (Row : Positive; Column_Name : String; Val : Value);
   procedure Set_Value_Upper (Row : Positive; Upper_Name : String; Val : Value);

   --  Renames an existing column.
   procedure Rename_Column (Old_Name, New_Name : String);

   --  Removes a column from the table.
   procedure Drop_Column (Name : String);
   
   --  Removes a specific row from the table.
   procedure Drop_Row (Index : Positive);

   --  Sorting support
   type Sort_Direction is (Ascending, Descending);
   type Sort_Criteria is record
      Name : String (1 .. 32);
      Len  : Natural;
      Dir  : Sort_Direction;
   end record;
   type Sort_Criteria_Array is array (Positive range <>) of Sort_Criteria;

   -- Sorts the table based on the given criteria.
   procedure Sort (Criteria : Sort_Criteria_Array);
   
   --  Sets/Gets the pointer to the current record during data step iteration.
   procedure Set_Current_Record_Index (Index : Natural);
   function Get_Current_Record_Index return Natural;

   procedure Set_Logical_Record_Index (Index : Natural);
   function Get_Logical_Record_Index return Natural;

   --  Filtered view support (SELECT filter)
   type Index_Array is array (Positive range <>) of Positive;
   procedure Set_Index_Map (Map : Index_Array);
   procedure Clear_Index_Map;
   function Logical_To_Physical (Logical : Positive) return Positive;
   function Logical_Row_Count return Natural;
   function Is_Filtered return Boolean;
   

   --  Output Table Management
   procedure Initialize_Output_Table;
   procedure Add_Output_Column (Name : String; Col_Type : Column_Type);
   procedure Add_Output_Row;
   procedure Set_Output_Value (Row : Positive; Column_Name : String; Val : Value);
   procedure Set_Output_Value_Upper (Row : Positive; Upper_Name : String; Val : Value);
   procedure Commit_Output_Table;
   function Output_Row_Count return Natural;

   procedure Set_Record_Explicitly_Written (State : Boolean);
   function Get_Record_Explicitly_Written return Boolean;

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


   Output_Data_Table : Column_Maps.Map;
   Output_Column_Order : Name_Vectors.Vector;
   Output_Table_Row_Count : Natural := 0;
   Record_Explicitly_Written : Boolean := False;

   --  Maintains the insertion order of column names for range expansion.
   Column_Order : Name_Vectors.Vector;
   
   --  Explicit row count (to handle cases where columns haven't been added yet).
   Table_Row_Count : Natural := 0;

   --  Current record pointer for the interpreter.
   Current_Record : Natural := 0;
   
   -- Logical record number (respecting filters)
   Logical_Record : Natural := 0;

   -- Segment tracking for disk spillover
   Current_Segment_Start : Positive := 1;

   --  SQLite Backing Store
   type Database_Access is access all Ada_Sqlite3.Database;
   type Backing_Store is record
      DB          : Database_Access := null;
      Is_Active   : Boolean := False;
      Temp_Path   : Unbounded_String;
      Row_Limit   : Natural := 0; -- -m value
   end record;

   Store : Backing_Store;

   --  Storage Management Procedures
   procedure Initialize_Backing_Store;
   procedure Spill_To_Disk;
   function Fetch_From_Disk (Row : Positive; Col_Name : String) return Value;

end SData.Table;
