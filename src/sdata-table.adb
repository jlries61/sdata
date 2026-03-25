with Ada.Text_IO;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Containers;         use Ada.Containers;
with SData.Config;

package body SData.Table is

   -----------
   -- Clear --
   -----------
   procedure Clear is
   begin
      Data_Table.Clear;
      Column_Order.Clear;
      Table_Row_Count := 0;
      Current_Record := 0;
   end Clear;

   ----------------
   -- Add_Column --
   ----------------
   procedure Add_Column (Name : String; Col_Type : Column_Type) is
      Upper_Name : constant String := To_Upper (Name);
      New_Col : Column;
   begin
      if Data_Table.Contains (Upper_Name) then
         return; 
      end if;
      
      New_Col.Name := (others => ' ');
      New_Col.Name (1 .. Upper_Name'Length) := Upper_Name;
      New_Col.Typ := Col_Type;
      
      --  Rule: New columns must match the existing table height.
      for I in 1 .. Table_Row_Count loop
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
      return Table_Row_Count;
   end Row_Count;

   -------------
   -- Add_Row --
   -------------
   procedure Add_Row is
      Position : Column_Maps.Cursor := Data_Table.First;
   begin
      if SData.Config.Max_Table_Rows > 0 and then Table_Row_Count >= SData.Config.Max_Table_Rows then
         raise Program_Error with "Table row limit (" & Integer'Image(SData.Config.Max_Table_Rows) & ") exceeded.";
      end if;

      Table_Row_Count := Table_Row_Count + 1;
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
         --  Safety check: Ensure the row actually exists in this column's data vector.
         if Count_Type (Row) > Col.Data.Length then
            --  Auto-extend if necessary (though Add_Row should handle this).
            for I in Positive (Col.Data.Length) + 1 .. Row loop
               Col.Data.Append ((Kind => Val_Missing));
            end loop;
         end if;

         if Val.Kind /= Val_Missing then
            if Col.Typ = Col_Numeric and Val.Kind /= Val_Numeric then
               if Val.Kind = Val_Integer then
                  Col.Data.Replace_Element (Row, (Kind => Val_Numeric, Num_Val => Float (Val.Int_Val)));
                  Data_Table.Replace_Element (Position, Col);
                  return;
               end if;
               raise Type_Mismatch_Error with "Expected Numeric, got " & Val.Kind'Image;
            elsif Col.Typ = Col_Integer and Val.Kind /= Val_Integer then
               if Val.Kind = Val_Numeric then
                  Col.Data.Replace_Element (Row, (Kind => Val_Integer, Int_Val => Integer (Float'Truncation (Val.Num_Val))));
                  Data_Table.Replace_Element (Position, Col);
                  return;
               end if;
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

   --------------
   -- Drop_Row --
   --------------
   procedure Drop_Row (Index : Positive) is
      Position : Column_Maps.Cursor := Data_Table.First;
   begin
      if Index > Table_Row_Count then return; end if;
      Table_Row_Count := Table_Row_Count - 1;
      while Column_Maps.Has_Element (Position) loop
         declare
            Col : Column := Column_Maps.Element (Position);
         begin
            if Index <= Positive (Col.Data.Length) then
               Col.Data.Delete (Index);
               Data_Table.Replace_Element (Position, Col);
            end if;
         end;
         Column_Maps.Next (Position);
      end loop;
   end Drop_Row;

   ------------------------------
   -- Set_Current_Record_Index --
   ------------------------------
   procedure Set_Current_Record_Index (Index : Natural) is
   begin
      Current_Record := Index;
   end Set_Current_Record_Index;
   
   ----------
   -- Sort --
   ----------
   procedure Sort (Criteria : Sort_Criteria_Array) is
      -- To sort a table, we sort an array of record indices (1..Table_Row_Count)
      -- based on the values in the table, then reconstruct the data vectors.
      
      package Index_Vectors is new Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Positive);
      
      function Compare_Rows (L, R : Positive) return Boolean is
      begin
         for I in Criteria'Range loop
            declare
               Col_Name : constant String := To_Upper (Criteria (I).Name (1 .. Criteria (I).Len));
               VL : constant Value := Get_Value (L, Col_Name);
               VR : constant Value := Get_Value (R, Col_Name);
            begin
               if VL /= VR then
                  if Criteria (I).Dir = Ascending then
                     return VL < VR;
                  else
                     return VR < VL;
                  end if;
               end if;
            end;
         end loop;
         return False; -- Equal
      end Compare_Rows;
      
      -- package Index_Sort is new Index_Vectors.Generic_Sorting;
      -- Manual sorting to avoid ambiguous compiler versions of Generic_Sorting
      procedure Manual_Sort (V : in out Index_Vectors.Vector) is
         Changed : Boolean;
      begin
         loop
            Changed := False;
            for I in 1 .. Integer(V.Length) - 1 loop
               if Compare_Rows (V.Element (I + 1), V.Element (I)) then
                  declare
                     T : constant Positive := V.Element (I);
                  begin
                     V.Replace_Element (I, V.Element (I + 1));
                     V.Replace_Element (I + 1, T);
                     Changed := True;
                  end;
               end if;
            end loop;
            exit when not Changed;
         end loop;
      end Manual_Sort;
      
      Indices : Index_Vectors.Vector;
      
   begin
      if Table_Row_Count <= 1 or Criteria'Length = 0 then return; end if;
      
      for I in 1 .. Table_Row_Count loop Indices.Append (I); end loop;
      
      Manual_Sort (Indices);
      
      -- Reorder all columns
      declare
         Position : Column_Maps.Cursor := Data_Table.First;
      begin
         while Column_Maps.Has_Element (Position) loop
            declare
               Col : Column := Column_Maps.Element (Position);
               New_Data : Value_Vectors.Vector;
            begin
               for I in 1 .. Table_Row_Count loop
                  New_Data.Append (Col.Data.Element (Indices.Element (I)));
               end loop;
               Col.Data := New_Data;
               Data_Table.Replace_Element (Position, Col);
            end;
            Column_Maps.Next (Position);
         end loop;
      end;
   end Sort;

   ------------------------------
   -- Get_Current_Record_Index --
   ------------------------------
   function Get_Current_Record_Index return Natural is
   begin
      return Current_Record;
   end Get_Current_Record_Index;


   -----------------------------
   -- Output Table Management --
   -----------------------------

   procedure Initialize_Output_Table is
   begin
      Output_Data_Table.Clear;
      Output_Column_Order.Clear;
      Output_Table_Row_Count := 0;
      --  Seed the output table with the current column structure (no data)
      --  so that column names are preserved even if all records are deleted.
      for Name of Column_Order loop
         declare
            Upper_Name : constant String := To_String (Name);
            Src_Col    : constant Column := Data_Table.Element (Upper_Name);
            New_Col    : Column;
         begin
            New_Col.Name := Src_Col.Name;
            New_Col.Typ  := Src_Col.Typ;
            Output_Data_Table.Insert (Upper_Name, New_Col);
            Output_Column_Order.Append (Name);
         end;
      end loop;
   end Initialize_Output_Table;

   procedure Add_Output_Column (Name : String; Col_Type : Column_Type) is
      Upper_Name : constant String := To_Upper (Name);
      New_Col : Column;
   begin
      if Output_Data_Table.Contains (Upper_Name) then return; end if;
      New_Col.Name := (others => ' ');
      New_Col.Name (1 .. Upper_Name'Length) := Upper_Name;
      New_Col.Typ := Col_Type;
      
      -- If the output table already has rows, pad with missing values
      for I in 1 .. Output_Table_Row_Count loop
         New_Col.Data.Append ((Kind => Val_Missing));
      end loop;
      
      Output_Data_Table.Insert (Upper_Name, New_Col);
      Output_Column_Order.Append (To_Unbounded_String (Upper_Name));
   end Add_Output_Column;

   procedure Add_Output_Row is
   begin
      if SData.Config.Max_Table_Rows > 0 and then Output_Table_Row_Count >= SData.Config.Max_Table_Rows then
         Ada.Text_IO.Put_Line ("Warning: Table row limit (" & Integer'Image(SData.Config.Max_Table_Rows) & ") exceeded. Memory cache full.");
         -- In Phase 5, this will spill to disk. For now, we continue but warn.
      end if;
      Output_Table_Row_Count := Output_Table_Row_Count + 1;
      
      for Pos in Output_Data_Table.Iterate loop
         declare
            Col : Column := Column_Maps.Element (Pos);
         begin
            Col.Data.Append ((Kind => Val_Missing));
            Output_Data_Table.Replace_Element (Pos, Col);
         end;
      end loop;
   end Add_Output_Row;

   procedure Set_Output_Value (Row : Positive; Column_Name : String; Val : Value) is
      Upper_Name : constant String := To_Upper (Column_Name);
      Col : Column;
   begin
      if not Output_Data_Table.Contains (Upper_Name) then
         return; -- Or throw an error
      end if;
      
      Col := Output_Data_Table.Element (Upper_Name);
      
      if Col.Typ = Col_Numeric and then Val.Kind /= Val_Numeric and then Val.Kind /= Val_Missing then
         raise Type_Mismatch_Error with "Expected Numeric for column " & Upper_Name;
      elsif Col.Typ = Col_Integer and then Val.Kind /= Val_Integer and then Val.Kind /= Val_Missing then
         raise Type_Mismatch_Error with "Expected Integer for column " & Upper_Name;
      elsif Col.Typ = Col_String and then Val.Kind /= Val_String and then Val.Kind /= Val_Missing then
         raise Type_Mismatch_Error with "Expected String for column " & Upper_Name;
      end if;
      
      Col.Data.Replace_Element (Row, Val);
      Output_Data_Table.Replace (Upper_Name, Col);
   end Set_Output_Value;

   procedure Commit_Output_Table is
   begin
      Data_Table := Output_Data_Table;
      Column_Order := Output_Column_Order;
      Table_Row_Count := Output_Table_Row_Count;
      Initialize_Output_Table;
   end Commit_Output_Table;

   function Output_Row_Count return Natural is
   begin
      return Output_Table_Row_Count;
   end Output_Row_Count;

   procedure Set_Record_Explicitly_Written (State : Boolean) is
   begin
      Record_Explicitly_Written := State;
   end Set_Record_Explicitly_Written;

   function Get_Record_Explicitly_Written return Boolean is
   begin
      return Record_Explicitly_Written;
   end Get_Record_Explicitly_Written;

end SData.Table;
