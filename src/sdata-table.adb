with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Containers;         use Ada.Containers;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;

package body SData.Table is

   -----------
   -- Clear --
   -----------
   procedure Clear is
   begin
      Data_Table.Clear;
      Column_Order.Clear;
      Current_Record := 0;
   end Clear;

   ----------------
   -- Add_Column --
   ----------------
   procedure Add_Column (Name : String; Col_Type : Column_Type) is
      Upper_Name : constant String := To_Upper (Name);
      New_Col : Column;
      Num_Rows : Natural := 0;
   begin
      if not Data_Table.Is_Empty then
         Num_Rows := Natural (Column_Maps.Element (Data_Table.First).Data.Length);
      end if;

      if Data_Table.Contains (Upper_Name) then
         return; 
      end if;
      
      New_Col.Name := (others => ' ');
      New_Col.Name (1 .. Upper_Name'Length) := Upper_Name;
      New_Col.Typ := Col_Type;
      
      for I in 1 .. Num_Rows loop
         New_Col.Data.Append ((Kind => Val_Missing));
      end loop;
      
      Data_Table.Insert (Upper_Name, New_Col);
      Column_Order.Append (To_Unbounded_String (Upper_Name));
   end Add_Column;

   ----------------------
   -- Get_Column_Names --
   ----------------------
   function Get_Column_Names return GNAT.Strings.String_List_Access is
      Count : constant Natural := Natural (Column_Order.Length);
      List : constant GNAT.Strings.String_List_Access := new GNAT.Strings.String_List (1 .. Count);
   begin
      for I in 1 .. Count loop
         List (I) := new String'(To_String (Column_Order.Element (I)));
      end loop;
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
      return Natural (Column_Maps.Element (Data_Table.First).Data.Length);
   end Row_Count;

   -------------
   -- Add_Row --
   -------------
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

   -------------------
   -- Rename_Column --
   -------------------
   procedure Rename_Column (Old_Name, New_Name : String) is
      Upper_Old : constant String := To_Upper (Old_Name);
      Upper_New : constant String := To_Upper (New_Name);
   begin
      if Data_Table.Contains (Upper_Old) and then not Data_Table.Contains (Upper_New) then
         declare
            Col : Column := Data_Table.Element (Upper_Old);
         begin
            Col.Name := (others => ' ');
            if Upper_New'Length > 32 then
               Col.Name := Upper_New (Upper_New'First .. Upper_New'First + 31);
            else
               Col.Name (1 .. Upper_New'Length) := Upper_New;
            end if;
            Data_Table.Delete (Upper_Old);
            Data_Table.Insert (Upper_New, Col);
            
            -- Update Order Vector
            for I in 1 .. Natural (Column_Order.Length) loop
               if To_String (Column_Order.Element (I)) = Upper_Old then
                  Column_Order.Replace_Element (I, To_Unbounded_String (Upper_New));
                  exit;
               end if;
            end loop;
         end;
      end if;
   end Rename_Column;

   -----------------
   -- Drop_Column --
   -----------------
   procedure Drop_Column (Name : String) is
      Upper_Name : constant String := To_Upper (Name);
   begin
      if Data_Table.Contains (Upper_Name) then
         Data_Table.Delete (Upper_Name);
         -- Update Order Vector
         for I in 1 .. Natural (Column_Order.Length) loop
            if To_String (Column_Order.Element (I)) = Upper_Name then
               Column_Order.Delete (I);
               exit;
            end if;
         end loop;
      end if;
   end Drop_Column;
   
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
