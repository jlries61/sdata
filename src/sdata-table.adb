with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Containers;         use Ada.Containers;

package body SData.Table is

   procedure Clear is
   begin
      Data_Table.Clear;
      Current_Record := 0;
   end Clear;

   procedure Add_Column (Name : String) is
      Upper_Name : constant String := To_Upper (Name);
      New_Col : Column;
      Num_Rows : constant Natural := Row_Count;
   begin
      if Data_Table.Contains (Upper_Name) then
         return; -- Or raise an error
      end if;
      
      New_Col.Name := (others => ' ');
      New_Col.Name (1 .. Upper_Name'Length) := Upper_Name;
      for I in 1 .. Num_Rows loop
         New_Col.Data.Append ( (Kind => Val_Missing) );
      end loop;
      
      Data_Table.Insert (Upper_Name, New_Col);
   end Add_Column;

   function Get_Column_Names return GNAT.Strings.String_List_Access is
      Count : constant Natural := Column_Count;
      List : constant GNAT.Strings.String_List_Access := new GNAT.Strings.String_List (1 .. Count);
      Index : Positive := 1;
      procedure Add_To_List (Position : Column_Maps.Cursor) is
      begin
         List (Index) := new String'(Column_Maps.Key (Position));
         Index := Index + 1;
      end Add_To_List;
   begin
      Data_Table.Iterate (Add_To_List'Access);
      return List;
   end Get_Column_Names;

   function Has_Column (Name : String) return Boolean is
   begin
      return Data_Table.Contains (To_Upper (Name));
   end Has_Column;

   function Column_Count return Natural is
   begin
      return Natural (Data_Table.Length);
   end Column_Count;

   function Row_Count return Natural is
   begin
      if Data_Table.Is_Empty then
         return 0;
      end if;
      
      -- All columns must have the same length
      return Natural (Column_Maps.Element (Data_Table.First).Data.Length);
   end Row_Count;

   procedure Add_Row is
      Position : Column_Maps.Cursor := Data_Table.First;
   begin
      while Column_Maps.Has_Element (Position) loop
         declare
            Col : Column := Column_Maps.Element (Position);
         begin
            Col.Data.Append ( (Kind => Val_Missing) );
            Data_Table.Replace_Element (Position, Col);
         end;
         Column_Maps.Next (Position);
      end loop;
   end Add_Row;

   function Get_Value (Row : Positive; Column_Name : String) return Value is
      Upper_Name : constant String := To_Upper (Column_Name);
   begin
      if not Data_Table.Contains (Upper_Name) then
         return (Kind => Val_Missing);
      end if;
      
      declare
         Col : constant Column := Data_Table.Element (Upper_Name);
      begin
         if Count_Type (Row) > Col.Data.Length then
            return (Kind => Val_Missing);
         end if;
         return Col.Data.Element (Row);
      end;
   end Get_Value;

   procedure Set_Value (Row : Positive; Column_Name : String; Val : Value) is
      Upper_Name : constant String := To_Upper (Column_Name);
   begin
      if not Data_Table.Contains (Upper_Name) then
         return; -- Or raise error
      end if;
      
      declare
         Position : constant Column_Maps.Cursor := Data_Table.Find (Upper_Name);
         Col : Column := Column_Maps.Element (Position);
      begin
         if Count_Type (Row) > Col.Data.Length then
            return; -- Or raise
         end if;
         Col.Data.Replace_Element (Row, Val);
         Data_Table.Replace_Element (Position, Col);
      end;
   end Set_Value;
   
   procedure Set_Current_Record_Index (Index : Natural) is
   begin
      Current_Record := Index;
   end Set_Current_Record_Index;
   
   function Get_Current_Record_Index return Natural is
   begin
      return Current_Record;
   end Get_Current_Record_Index;

end SData.Table;
