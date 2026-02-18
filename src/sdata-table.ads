with Ada.Strings.Hash;
with GNAT.Strings;
with Ada.Containers.Indefinite_Hashed_Maps;
with Ada.Containers.Vectors;
with SData.Values; use SData.Values;


package SData.Table is

   procedure Clear;
   procedure Add_Column (Name : String);
   function Get_Column_Names return GNAT.Strings.String_List_Access;
   function Has_Column (Name : String) return Boolean;
   function Column_Count return Natural;
   function Row_Count return Natural;

   procedure Add_Row;
   function Get_Value (Row : Positive; Column_Name : String) return Value;
   procedure Set_Value (Row : Positive; Column_Name : String; Val : Value);
   
   -- To be replaced by a proper iterator later
   procedure Set_Current_Record_Index (Index : Natural);
   function Get_Current_Record_Index return Natural;

private
   package Value_Vectors is new Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Value);

   type Column is record
      Name : String (1 .. 32);
      Data : Value_Vectors.Vector;
   end record;
   
   package Column_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type => String,
      Element_Type => Column,
      Hash => Ada.Strings.Hash,
      Equivalent_Keys => "=");
      
   Data_Table : Column_Maps.Map;
   Current_Record : Natural := 0;

end SData.Table;
