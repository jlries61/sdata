with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Containers;         use Ada.Containers;

package body SData.Table is

   -----------
   -- Clear --
   -----------
   procedure Clear is
   begin
      Data_Table.Clear;
      Current_Record := 0;
   end Clear;

   ----------------
   -- Add_Column --
   ----------------
   --  Defines a new column structure. Maintains existing row count by padding with missing values.
   procedure Add_Column (Name : String; Col_Type : Column_Type) is
      Upper_Name : constant String := To_Upper (Name);
      New_Col : Column;
      Num_Rows : Natural := 0;
   begin
      -- Determine how many rows are already in the table using the first existing column.
      if not Data_Table.Is_Empty then
         Num_Rows := Natural (Column_Maps.Element (Data_Table.First).Data.Length);
      end if;

      -- Columns are unique (case-insensitive).
      if Data_Table.Contains (Upper_Name) then
         return; 
      end if;
      
      -- Initialize column metadata.
      New_Col.Name := (others => ' ');
      New_Col.Name (1 .. Upper_Name'Length) := Upper_Name;
      New_Col.Typ := Col_Type;
      
      -- Pre-fill new column with missing values to match existing table height.
      for I in 1 .. Num_Rows loop
         New_Col.Data.Append ((Kind => Val_Missing));
      end loop;
      
      Data_Table.Insert (Upper_Name, New_Col);
   end Add_Column;

   ----------------------
   -- Get_Column_Names --
   ----------------------
   function Get_Column_Names return GNAT.Strings.String_List_Access is
      Count : constant Natural := Column_Count;
      List : constant GNAT.Strings.String_List_Access := new GNAT.Strings.String_List (1 .. Count);
      Index : Positive := 1;
      
      -- Iterator procedure for hashed map.
      procedure Add_To_List (Position : Column_Maps.Cursor) is
      begin
         List (Index) := new String'(Column_Maps.Key (Position));
         Index := Index + 1;
      end Add_To_List;
   begin
      Data_Table.Iterate (Add_To_List'Access);
      return List;
   end Get_Column_Names;

   ----------------
   -- Has_Column --
   ----------------
   function Has_Column (Name : String) return Boolean is
   begin
      return Data_Table.Contains (To_Upper (Name));
   end Has_Column;

   ------------------
   -- Column_Count --
   ------------------
   function Column_Count return Natural is
   begin
      return Natural (Data_Table.Length);
   end Column_Count;

   ---------------
   -- Row_Count --
   ---------------
   function Row_Count return Natural is
   begin
      if Data_Table.Is_Empty then
         return 0;
      end if;
      
      -- Return the row count of the first column found.
      return Natural (Column_Maps.Element (Data_Table.First).Data.Length);
   end Row_Count;

   -------------
   -- Add_Row --
   -------------
   --  Increases the height of the table by appending a missing value to every column.
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

   ---------------
   -- Get_Value --
   ---------------
   function Get_Value (Row : Positive; Column_Name : String) return Value is
      Upper_Name : constant String := To_Upper (Column_Name);
   begin
      if not Data_Table.Contains (Upper_Name) then
         return (Kind => Val_Missing);
      end if;
      
      declare
         Col : constant Column := Data_Table.Element (Upper_Name);
      begin
         -- Return missing if row index is out of bounds.
         if Count_Type (Row) > Col.Data.Length then
            return (Kind => Val_Missing);
         end if;
         return Col.Data.Element (Row);
      end;
   end Get_Value;

   ---------------
   -- Set_Value --
   ---------------
   procedure Set_Value (Row : Positive; Column_Name : String; Val : Value) is
      Upper_Name : constant String := To_Upper (Column_Name);
   begin
      if not Data_Table.Contains (Upper_Name) then
         return;
      end if;

      declare
         Position : constant Column_Maps.Cursor := Data_Table.Find (Upper_Name);
         Col : Column := Column_Maps.Element (Position);
      begin
         if Count_Type (Row) > Col.Data.Length then
            return;
         end if;

         --  Perform type checking against column definition.
         if Val.Kind /= Val_Missing then
            if Col.Typ = Col_Numeric and Val.Kind /= Val_Numeric then
               raise Type_Mismatch_Error with "Expected Numeric, got " & Val.Kind'Image;
            elsif Col.Typ = Col_Integer and Val.Kind /= Val_Integer then
               raise Type_Mismatch_Error with "Expected Integer, got " & Val.Kind'Image;
            elsif Col.Typ = Col_String and Val.Kind /= Val_String then
               raise Type_Mismatch_Error with "Expected String, got " & Val.Kind'Image;
            end if;
         end if;

         Col.Data.Replace_Element (Row, Val);
         Data_Table.Replace_Element (Position, Col);
      end;
   end Set_Value;
   
   ------------------------------
   -- Set_Current_Record_Index --
   ------------------------------
   procedure Set_Current_Record_Index (Index : Natural) is
   begin
      Current_Record := Index;
   end Set_Current_Record_Index;
   
   ------------------------------
   -- Get_Current_Record_Index --
   ------------------------------
   function Get_Current_Record_Index return Natural is
   begin
      return Current_Record;
   end Get_Current_Record_Index;

end SData.Table;
