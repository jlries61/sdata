with Ada.Characters.Handling;
with Ada.Containers;
with SData.Config;
with SData.IO;

with GNAT.OS_Lib;
with Ada.Unchecked_Deallocation;
with GNAT.Strings;
with Ada_Sqlite3;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;

package body SData.Table is

   use type Ada.Containers.Count_Type;
   use type GNAT.Strings.String_List_Access;
   use type Ada_Sqlite3.Result_Code;

   procedure Spill_Output_To_Disk;
   procedure Spill_Table_To_Disk (T : in out Column_Maps.Map; Table_Name : String; Start_Idx : Positive);

   ---------------------------
   -- Backing Store Cleanup --
   ---------------------------
   procedure Cleanup_Backing_Store is
      procedure Free_DB is new Ada.Unchecked_Deallocation (Ada_Sqlite3.Database, Database_Access);
      Success : Boolean;
   begin
      if Store.Is_Active then
         if Store.DB /= null then
            Free_DB (Store.DB);
         end if;
         declare
            Path : constant String := Ada.Strings.Unbounded.To_String (Store.Temp_Path);
         begin
            GNAT.OS_Lib.Delete_File (Path, Success);
         end;
         Store.Is_Active := False;
      end if;
   end Cleanup_Backing_Store;

   -- Filtered View Mapping
   type Index_Array_Access is access Index_Array;
   Filter_Map : Index_Array_Access := null;

   -----------
   -- Clear --
   -----------
   procedure Clear is
   begin
      Cleanup_Backing_Store;
      Data_Table.Clear;
      Column_Order.Clear;
      Table_Row_Count := 0;
      Current_Record := 0;
      Logical_Record := 0;
      Clear_Index_Map;
      Current_Segment_Start := 1;
   end Clear;

   ----------------
   -- Add_Column --
   ----------------
   procedure Add_Column (Name : String; Col_Type : Column_Type) is
      Upper_Name : constant String := Ada.Characters.Handling.To_Upper (Name);
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
      Column_Order.Append (Ada.Strings.Unbounded.To_Unbounded_String (Upper_Name));
   end Add_Column;

   ----------------------
   -- Get_Column_Names --
   ----------------------
   function Get_Column_Names return GNAT.Strings.String_List_Access is
      Count : constant Natural := Natural (Column_Order.Length);
      List : constant GNAT.Strings.String_List_Access := new GNAT.Strings.String_List (1 .. Count);
   begin
      for I in 1 .. Count loop
         List (I) := new String'(Ada.Strings.Unbounded.To_String (Column_Order.Element (I)));
      end loop;
      return List;
   end Get_Column_Names;

   ----------------
   -- Has_Column --
   ----------------
   function Has_Column (Name : String) return Boolean is
   begin
      return Data_Table.Contains (Ada.Characters.Handling.To_Upper (Name));
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
   begin
      if SData.Config.Max_Table_Rows > 0 and then
         Table_Row_Count >= (Current_Segment_Start + SData.Config.Max_Table_Rows - 1)
      then
         Spill_To_Disk;
         Current_Segment_Start := Table_Row_Count + 1;
      end if;

      Table_Row_Count := Table_Row_Count + 1;
      for Pos in Data_Table.Iterate loop
         Data_Table.Reference (Pos).Element.all.Data.Append ((Kind => Val_Missing));
      end loop;
   end Add_Row;

   ---------------
   -- Get_Value --
   ---------------
   function Get_Value (Row : Positive; Column_Name : String) return Value is
   begin
      return Get_Value_Upper (Row, Ada.Characters.Handling.To_Upper (Column_Name));
   end Get_Value;

   function Get_Value_Upper (Row : Positive; Upper_Name : String) return Value is
   begin
      if not Data_Table.Contains (Upper_Name) then
         return (Kind => Val_Missing);
      end if;
      declare
         Ref : constant Column_Maps.Constant_Reference_Type :=
            Data_Table.Constant_Reference (Upper_Name);
         Len : constant Natural := Natural (Ref.Element.all.Data.Length);
      begin
         if Row >= Current_Segment_Start and then Row < Current_Segment_Start + Len then
            return Ref.Element.all.Data.Element (Row - Current_Segment_Start + 1);
         elsif Store.Is_Active then
            return Fetch_From_Disk (Row, Upper_Name);
         else
            return (Kind => Val_Missing);
         end if;
      end;
   end Get_Value_Upper;

   procedure Set_Value (Row : Positive; Column_Name : String; Val : Value) is
   begin
      Set_Value_Upper (Row, Ada.Characters.Handling.To_Upper (Column_Name), Val);
   end Set_Value;

   procedure Set_Value_Upper (Row : Positive; Upper_Name : String; Val : Value) is
   begin
      if not Data_Table.Contains (Upper_Name) then
         return;
      end if;
      declare
         Ref : constant Column_Maps.Reference_Type := Data_Table.Reference (Upper_Name);
         Col : Column renames Ref.Element.all;
      begin
         if Row > Table_Row_Count then
            for I in Positive (Col.Data.Length) + 1 .. Row loop
               Col.Data.Append ((Kind => Val_Missing));
            end loop;
         end if;
         if Val.Kind /= Val_Missing then
            if Col.Typ = Col_Numeric and Val.Kind /= Val_Numeric then
               if Val.Kind = Val_Integer then
                  Col.Data.Replace_Element (Row - Current_Segment_Start + 1, (Kind => Val_Numeric, Num_Val => Float (Val.Int_Val)));
                  return;
               end if;
               raise Type_Mismatch_Error with "Expected Numeric, got " & Val.Kind'Image;
            elsif Col.Typ = Col_Integer and Val.Kind /= Val_Integer then
               if Val.Kind = Val_Numeric then
                  Col.Data.Replace_Element (Row - Current_Segment_Start + 1, (Kind => Val_Integer, Int_Val => Integer (Float'Truncation (Val.Num_Val))));
                  return;
               end if;
               raise Type_Mismatch_Error with "Expected Integer, got " & Val.Kind'Image;
            elsif Col.Typ = Col_String and Val.Kind /= Val_String then
               raise Type_Mismatch_Error with "Expected String, got " & Val.Kind'Image;
            end if;
         end if;
         Col.Data.Replace_Element (Row - Current_Segment_Start + 1, Val);
      end;
   end Set_Value_Upper;

   -------------------
   -- Rename_Column --
   -------------------
   procedure Rename_Column (Old_Name, New_Name : String) is
      Upper_Old : constant String := Ada.Characters.Handling.To_Upper (Old_Name);
      Upper_New : constant String := Ada.Characters.Handling.To_Upper (New_Name);
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
               if Ada.Strings.Unbounded.To_String (Column_Order.Element (I)) = Upper_Old then
                  Column_Order.Replace_Element (I, Ada.Strings.Unbounded.To_Unbounded_String (Upper_New));
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
      Upper_Name : constant String := Ada.Characters.Handling.To_Upper (Name);
   begin
      if Data_Table.Contains (Upper_Name) then
         Data_Table.Delete (Upper_Name);
         -- Update Order Vector
         for I in 1 .. Natural (Column_Order.Length) loop
            if Ada.Strings.Unbounded.To_String (Column_Order.Element (I)) = Upper_Name then
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
      N : constant Natural := Table_Row_Count;
   begin
      if N <= 1 or else Criteria'Length = 0 then return; end if;

      if Store.Is_Active then
         Spill_To_Disk;
         declare
            Col_Names : constant GNAT.Strings.String_List_Access := Get_Column_Names;
            Cols_CSV  : Unbounded_String;
            Col_Def   : Unbounded_String;
            OrderBy   : Unbounded_String := To_Unbounded_String (" ORDER BY ");
         begin
            if Col_Names = null or else Col_Names'Length = 0 then return; end if;

            for I in Col_Names'Range loop
               declare
                  Upper : constant String := Ada.Characters.Handling.To_Upper (Col_Names (I).all);
                  Typ   : constant Column_Type := Data_Table.Element (Upper).Typ;
                  SQL_T : constant String := (if Typ = Col_Numeric then "REAL"
                                              elsif Typ = Col_Integer then "INTEGER"
                                              else "TEXT");
               begin
                  Append (Cols_CSV, "[" & Upper & "]");
                  Append (Col_Def, "[" & Upper & "] " & SQL_T);
                  if I < Col_Names'Last then
                     Append (Cols_CSV, ", ");
                     Append (Col_Def, ", ");
                  end if;
               end;
            end loop;

            for I in Criteria'Range loop
               Append (OrderBy, "[" & Ada.Characters.Handling.To_Upper (Criteria (I).Name (1 .. Criteria (I).Len)) & "]");
               if Criteria (I).Dir = Descending then Append (OrderBy, " DESC"); end if;
               if I < Criteria'Last then Append (OrderBy, ", "); end if;
            end loop;
            -- Ensure stability: use record_id as tie-breaker
            Append (OrderBy, ", record_id ASC");

            Store.DB.Execute ("CREATE TABLE data_new (record_id INTEGER PRIMARY KEY AUTOINCREMENT, " & To_String (Col_Def) & ")");
            Store.DB.Execute ("INSERT INTO data_new (" & To_String (Cols_CSV) & ") " &
                              "SELECT " & To_String (Cols_CSV) & " FROM data " & To_String (OrderBy));
            Store.DB.Execute ("DROP TABLE data");
            Store.DB.Execute ("ALTER TABLE data_new RENAME TO data");

            declare Old : GNAT.Strings.String_List_Access := Col_Names; begin GNAT.Strings.Free (Old); end;
         end;
         return;
      end if;

      declare
         type Value_Row     is array (Natural range <>) of Value;
         type Value_Row_Acc is access Value_Row;
         Key_Data : array (Criteria'Range) of Value_Row_Acc;

         type Index_Array_Sort is array (Positive range <>) of Natural;
         type Index_Array_Acc  is access Index_Array_Sort;
         Indices : Index_Array_Acc;
         Temp    : Index_Array_Acc;

         function Lt (L, R : Natural) return Boolean is
         begin
            for C in Criteria'Range loop
               declare
                  VL : Value renames Key_Data (C)(L);
                  VR : Value renames Key_Data (C)(R);
               begin
                  if VL /= VR then
                     if Criteria (C).Dir = Ascending then
                        return VL < VR;
                     else
                        return VR < VL;
                     end if;
                  end if;
               end;
            end loop;
            return L < R;
         end Lt;

         procedure Merge_Sort (Lo, Hi : Positive) is
            Mid : Positive;
            I, J, K : Positive;
         begin
            if Lo >= Hi then return; end if;
            Mid := Lo + (Hi - Lo) / 2;
            Merge_Sort (Lo, Mid);
            Merge_Sort (Mid + 1, Hi);
            for X in Lo .. Hi loop Temp (X) := Indices (X); end loop;
            I := Lo; J := Mid + 1; K := Lo;
            while I <= Mid and then J <= Hi loop
               if not Lt (Temp (J), Temp (I)) then
                  Indices (K) := Temp (I); I := I + 1;
               else
                  Indices (K) := Temp (J); J := J + 1;
               end if;
               K := K + 1;
            end loop;
            while I <= Mid loop Indices (K) := Temp (I); I := I + 1; K := K + 1; end loop;
         end Merge_Sort;

      begin
         for C in Criteria'Range loop
            declare
               Col_Name : constant String :=
                  Ada.Characters.Handling.To_Upper (Criteria (C).Name (1 .. Criteria (C).Len));
               Row_Vals : constant Value_Row_Acc := new Value_Row (0 .. N);
            begin
               Row_Vals (0) := (Kind => Val_Missing);
               if Data_Table.Contains (Col_Name) then
                  for R in 1 .. N loop
                     Row_Vals (R) := Get_Value_Upper (R, Col_Name);
                  end loop;
               else
                  for R in 1 .. N loop
                     Row_Vals (R) := (Kind => Val_Missing);
                  end loop;
               end if;
               Key_Data (C) := Row_Vals;
            end;
         end loop;

         Indices := new Index_Array_Sort (1 .. N);
         Temp    := new Index_Array_Sort (1 .. N);
         for I in 1 .. N loop Indices (I) := I; end loop;

         Merge_Sort (1, N);

         declare
            Pos : Column_Maps.Cursor := Data_Table.First;
         begin
            while Column_Maps.Has_Element (Pos) loop
               declare
                  -- Only get the key once
                  Current_Key : constant String := Column_Maps.Key (Pos);
                  Old_Data    : Value_Vectors.Vector renames Data_Table.Reference (Pos).Element.all.Data;
                  New_Data    : Value_Vectors.Vector;
               begin
                  New_Data.Reserve_Capacity (Ada.Containers.Count_Type (N));
                  for I in 1 .. N loop
                     New_Data.Append (Get_Value_Upper (Indices (I), Current_Key));
                  end loop;
                  Value_Vectors.Move (Source => New_Data, Target => Old_Data);
               end;
               Column_Maps.Next (Pos);
            end loop;
         end;
      end;
   end Sort;

   ------------------------------
   -- Get_Current_Record_Index --
   ------------------------------
   function Get_Current_Record_Index return Natural is
   begin
      return Current_Record;
   end Get_Current_Record_Index;

   procedure Set_Logical_Record_Index (Index : Natural) is
   begin
      Logical_Record := Index;
   end Set_Logical_Record_Index;

   function Get_Logical_Record_Index return Natural is
   begin
      return Logical_Record;
   end Get_Logical_Record_Index;

   -------------------
   -- Set_Index_Map --
   -------------------
   procedure Set_Index_Map (Map : Index_Array) is
   begin
      Clear_Index_Map;
      if Map'Length > 0 then
         Filter_Map := new Index_Array'(Map);
      end if;
   end Set_Index_Map;

   ---------------------
   -- Clear_Index_Map --
   ---------------------
   procedure Clear_Index_Map is
      procedure Free is new Ada.Unchecked_Deallocation (Index_Array, Index_Array_Access);
   begin
      if Filter_Map /= null then
         Free (Filter_Map);
      end if;
   end Clear_Index_Map;

   -------------------------
   -- Logical_To_Physical --
   -------------------------
   function Logical_To_Physical (Logical : Positive) return Positive is
   begin
      if Filter_Map = null then
         return Logical;
      elsif Logical <= Filter_Map'Length then
         return Filter_Map (Logical);
      else
         return Logical; -- Fallback
      end if;
   end Logical_To_Physical;

   ------------------------
   -- Logical_Row_Count --
   ------------------------
   function Logical_Row_Count return Natural is
   begin
      if Filter_Map = null then
         return Table_Row_Count;
      else
         return Filter_Map'Length;
      end if;
   end Logical_Row_Count;

   -----------------
   -- Is_Filtered --
   -----------------
   function Is_Filtered return Boolean is
   begin
      return Filter_Map /= null;
   end Is_Filtered;

   ------------------------
   -- Set_Filtered_Stats --
   ------------------------
   procedure Set_Filtered_Stats (Recno : Natural; Is_BOF, Is_EOF : Boolean) is
   begin
      null;
   end Set_Filtered_Stats;

   function Get_Filtered_Recno return Natural is
   begin
      return Logical_Record;
   end Get_Filtered_Recno;

   function Is_Filtered_BOF return Boolean is
   begin
      return Logical_Record = 1;
   end Is_Filtered_BOF;

   function Is_Filtered_EOF return Boolean is
   begin
      return Logical_Record > 0 and then Logical_Record = Logical_Row_Count;
   end Is_Filtered_EOF;

   -----------------------------
   -- Output Table Management --
   -----------------------------

   procedure Initialize_Output_Table is
   begin
      Output_Data_Table.Clear;
      Output_Column_Order.Clear;
      Output_Table_Row_Count := 0;
   end Initialize_Output_Table;

   procedure Add_Output_Column (Name : String; Col_Type : Column_Type) is
      Upper_Name : constant String := Ada.Characters.Handling.To_Upper (Name);
      New_Col : Column;
   begin
      if Output_Data_Table.Contains (Upper_Name) then return; end if;
      New_Col.Name := (others => ' ');
      New_Col.Name (1 .. Upper_Name'Length) := Upper_Name;
      New_Col.Typ := Col_Type;
      
      for I in 1 .. Output_Table_Row_Count loop
         New_Col.Data.Append ((Kind => Val_Missing));
      end loop;
      
      Output_Data_Table.Insert (Upper_Name, New_Col);
      Output_Column_Order.Append (Ada.Strings.Unbounded.To_Unbounded_String (Upper_Name));
   end Add_Output_Column;

   procedure Add_Output_Row is
   begin
      if SData.Config.Max_Table_Rows > 0 and then
         Output_Table_Row_Count >= (Output_Segment_Start + SData.Config.Max_Table_Rows - 1)
      then
         Spill_Output_To_Disk;
         Output_Segment_Start := Output_Table_Row_Count + 1;
      end if;

      Output_Table_Row_Count := Output_Table_Row_Count + 1;
      for Pos in Output_Data_Table.Iterate loop
         Output_Data_Table.Reference (Pos).Element.all.Data.Append ((Kind => Val_Missing));
      end loop;
   end Add_Output_Row;

   procedure Set_Output_Value_Upper (Row : Positive; Upper_Name : String; Val : Value) is
   begin
      if not Output_Data_Table.Contains (Upper_Name) then
         return;
      end if;
      declare
         Ref : constant Column_Maps.Reference_Type :=
            Output_Data_Table.Reference (Upper_Name);
         Col : Column renames Ref.Element.all;
      begin
         if Col.Typ = Col_Numeric and then Val.Kind /= Val_Numeric and then Val.Kind /= Val_Missing then
            if Val.Kind = Val_Integer then
               Col.Data.Replace_Element (Row - Output_Segment_Start + 1, (Kind => Val_Numeric, Num_Val => Float (Val.Int_Val)));
               return;
            end if;
            raise Type_Mismatch_Error with "Expected Numeric for column " & Upper_Name;
         elsif Col.Typ = Col_Integer and then Val.Kind /= Val_Integer and then Val.Kind /= Val_Missing then
            if Val.Kind = Val_Numeric then
               Col.Data.Replace_Element (Row - Output_Segment_Start + 1, (Kind => Val_Integer, Int_Val => Integer (Float'Truncation (Val.Num_Val))));
               return;
            end if;
            raise Type_Mismatch_Error with "Expected Integer for column " & Upper_Name;
         elsif Col.Typ = Col_String and then Val.Kind /= Val_String and then Val.Kind /= Val_Missing then
            raise Type_Mismatch_Error with "Expected String for column " & Upper_Name;
         end if;
         Col.Data.Replace_Element (Row - Output_Segment_Start + 1, Val);
      end;
   end Set_Output_Value_Upper;

   procedure Set_Output_Value (Row : Positive; Column_Name : String; Val : Value) is
   begin
      Set_Output_Value_Upper (Row, Ada.Characters.Handling.To_Upper (Column_Name), Val);
   end Set_Output_Value;

   procedure Commit_Output_Table is
      Output_Spilled : constant Boolean := Output_Segment_Start > 1;
   begin
      if Output_Table_Row_Count = 0 and then Output_Data_Table.Is_Empty
        and then not Data_Table.Is_Empty
      then
         for Pos in Data_Table.Iterate loop
            declare
               Col : Column := Column_Maps.Element (Pos);
            begin
               Col.Data.Clear;
               Data_Table.Replace_Element (Pos, Col);
            end;
         end loop;
         Table_Row_Count := 0;
         if Store.Is_Active then
            Store.DB.Execute ("DROP TABLE IF EXISTS data");
            Store.DB.Execute ("DROP TABLE IF EXISTS output_data");
         end if;
      else
         Data_Table := Output_Data_Table;
         Column_Order := Output_Column_Order;
         Table_Row_Count := Output_Table_Row_Count;
         
         if Store.Is_Active then
            Store.DB.Execute ("DROP TABLE IF EXISTS data");
            if Output_Spilled then
               -- Move output segments to main data
               Spill_Output_To_Disk; -- Flush any remaining buffer
               Store.DB.Execute ("ALTER TABLE output_data RENAME TO data");
            end if;
         end if;
      end if;
      Initialize_Output_Table;
      -- Reset segments
      Current_Segment_Start := 1;
      Output_Segment_Start := 1;
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

   ------------------------------
   -- Initialize_Backing_Store --
   ------------------------------
   procedure Initialize_Backing_Store is
      FD : GNAT.OS_Lib.File_Descriptor;
      Temp_Name : GNAT.Strings.String_Access;
   begin
      if Store.Is_Active then return; end if;
      GNAT.OS_Lib.Create_Temp_File (FD, Temp_Name);
      GNAT.OS_Lib.Close (FD);
      Store.Temp_Path := Ada.Strings.Unbounded.To_Unbounded_String (Temp_Name.all);
      Store.DB := new Ada_Sqlite3.Database'(Ada_Sqlite3.Open (Temp_Name.all));
      Store.Is_Active := True;
      
      --  Note: tables are created lazily via Spill_Table_To_Disk.
      GNAT.Strings.Free (Temp_Name);
   end Initialize_Backing_Store;

   ---------------------------
   -- Spill_Table_To_Disk --
   ---------------------------
   procedure Spill_Table_To_Disk (T : in out Column_Maps.Map; Table_Name : String; Start_Idx : Positive) is
      SQL : Unbounded_String;
      Memory_Rows : Natural := 0;
      package Name_Vecs is new Ada.Containers.Vectors (Positive, Unbounded_String);
      Col_Names : Name_Vecs.Vector;
   begin
      if T.Is_Empty then return; end if;
      
      -- Get column names and memory row count
      for Pos in T.Iterate loop
         Col_Names.Append (To_Unbounded_String (Column_Maps.Key (Pos)));
         if Memory_Rows = 0 then
            Memory_Rows := Natural (Column_Maps.Element (Pos).Data.Length);
         end if;
      end loop;
      
      if Memory_Rows = 0 then return; end if;
      
      Initialize_Backing_Store;
      
      -- Create table if it doesn't exist
      SQL := To_Unbounded_String ("CREATE TABLE IF NOT EXISTS [" & Table_Name & "] (record_id INTEGER PRIMARY KEY");
      for Name of Col_Names loop
         declare
            Typ : constant Column_Type := T.Element (To_String (Name)).Typ;
            SQL_T : constant String := (if Typ = Col_Numeric then "REAL"
                                        elsif Typ = Col_Integer then "INTEGER"
                                        else "TEXT");
         begin
            Append (SQL, ", [" & To_String (Name) & "] " & SQL_T);
         end;
      end loop;
      Append (SQL, ")");
      Store.DB.Execute (To_String (SQL));

      -- Build INSERT statement
      SQL := To_Unbounded_String ("INSERT INTO [" & Table_Name & "] (record_id");
      for Name of Col_Names loop Append (SQL, ", [" & To_String (Name) & "]"); end loop;
      Append (SQL, ") VALUES (?");
      for I in 1 .. Natural (Col_Names.Length) loop Append (SQL, ", ?"); end loop;
      Append (SQL, ")");

      declare
         Stmt : Ada_Sqlite3.Statement := Store.DB.Prepare (To_String (SQL));
      begin
         for R in 1 .. Memory_Rows loop
            Stmt.Reset;
            Stmt.Clear_Bindings;
            Stmt.Bind_Int (1, Start_Idx + R - 1);
            for C in 1 .. Natural (Col_Names.Length) loop
               declare
                  Val : constant Value := T.Element (To_String (Col_Names.Element (C))).Data.Element (R);
               begin
                  case Val.Kind is
                     when Val_Numeric => Stmt.Bind_Double (C + 1, Val.Num_Val);
                     when Val_Integer => Stmt.Bind_Int (C + 1, Val.Int_Val);
                     when Val_String  => Stmt.Bind_Text (C + 1, To_String (Val.Str_Val));
                     when Val_Missing => Stmt.Bind_Null (C + 1);
                  end case;
               end;
            end loop;
            Stmt.Step;
         end loop;
      end;

      -- Clear memory vectors
      for Pos in T.Iterate loop
         T.Reference (Pos).Element.all.Data.Clear;
      end loop;
   end Spill_Table_To_Disk;

   procedure Spill_To_Disk is
   begin
      Spill_Table_To_Disk (Data_Table, "data", Current_Segment_Start);
   end Spill_To_Disk;

   procedure Spill_Output_To_Disk is
   begin
      Spill_Table_To_Disk (Output_Data_Table, "output_data", Output_Segment_Start);
   end Spill_Output_To_Disk;

   -----------------------
   -- Fetch_From_Disk --
   -----------------------
   function Fetch_From_Disk (Row : Positive; Col_Name : String) return Value is
      SQL : constant String := "SELECT [" & Ada.Characters.Handling.To_Upper (Col_Name) & "] FROM data WHERE record_id = " & 
                                Ada.Strings.Fixed.Trim (Row'Img, Ada.Strings.Both);
      Stmt : Ada_Sqlite3.Statement := Store.DB.Prepare (SQL);
   begin
      if Stmt.Step = Ada_Sqlite3.ROW then
         declare
            Typ : constant Column_Type := Data_Table.Element (Ada.Characters.Handling.To_Upper (Col_Name)).Typ;
         begin
            if Stmt.Column_Is_Null (0) then
               return (Kind => Val_Missing);
            elsif Typ = Col_Numeric then
               return (Kind => Val_Numeric, Num_Val => Stmt.Column_Double (0));
            elsif Typ = Col_Integer then
               return (Kind => Val_Integer, Int_Val => Stmt.Column_Int (0));
            else
               return (Kind => Val_String, Str_Val => Ada.Strings.Unbounded.To_Unbounded_String (Stmt.Column_Text (0)));
            end if;
         end;
      else
         return (Kind => Val_Missing);
      end if;
   end Fetch_From_Disk;

end SData.Table;
