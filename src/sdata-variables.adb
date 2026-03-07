with Ada.Characters.Handling; use Ada.Characters.Handling;
with GNAT.Strings; use GNAT.Strings;
with Ada.Containers; use Ada.Containers; -- For Count_Type
with Ada.Strings.Fixed;

package body SData.Variables is

   ---------------------------
   -- Array_Definition_Type --
   ---------------------------
   function "=" (Left, Right : Array_Definition_Type) return Boolean is
   begin
      if Left.Kind /= Right.Kind then return False; end if;
      if Left.Is_Temporary /= Right.Is_Temporary then return False; end if;
      if Left.Start_Index /= Right.Start_Index then return False; end if;
      if Left.End_Index /= Right.End_Index then return False; end if;
      -- Only compare constituents if it's a virtual array
      if Left.Kind = Virtual_Array then
         return SData.Table.Name_Vectors."=" (Left.Constituents, Right.Constituents);
      else -- Real_Array
         -- Real arrays are defined by their bounds and temporary status, not explicit constituents list
         return True; 
      end if;
   end "=";

   -------------------------
   -- Get_Real_Var_Name --
   -------------------------
   function Get_Real_Var_Name (Array_Name : String; Index : Integer) return String is
   begin
      --  Converts "MYARRAY" and 5 to "MYARRAY(5)"
      return Array_Name & "(" & Ada.Strings.Fixed.Trim(Integer'Image(Index), Ada.Strings.Both) & ")";
   end Get_Real_Var_Name;

   -------------------
   -- Set_Temporary --
   -------------------
   procedure Set_Temporary (Name : String; Val : Value) is
      Upper_Name : constant String := To_Upper (Name);
   begin
      --  Rule: SET cannot overwrite a permanent variable (column).
      if SData.Table.Has_Column (Upper_Name) then
         raise Program_Error with "Cannot SET permanent variable '" & Upper_Name & "' as temporary.";
      end if;

      if Temp_Symbols.Contains (Upper_Name) then
         Temp_Symbols.Replace (Upper_Name, Val);
      else
         Temp_Symbols.Insert (Upper_Name, Val);
      end if;
   end Set_Temporary;

   -------------------
   -- Set_Permanent --
   -------------------
   procedure Set_Permanent (Name : String; Val : Value) is
      Upper_Name : constant String := To_Upper (Name);
   begin
      --  If we were tracking this as a temporary variable, remove it from that pool (Promotion).
      --  EXCEPT if it is HELD.
      if Temp_Symbols.Contains (Upper_Name) and then not Is_Held (Upper_Name) then
         Symbol_Table_Pkg.Delete (Temp_Symbols, Upper_Name);
      end if;

      --  Update the Permanent symbols PDV.
      if Permanent_Symbols.Contains (Upper_Name) then
         Permanent_Symbols.Replace (Upper_Name, Val);
      else
         Permanent_Symbols.Insert (Upper_Name, Val);
      end if;
      
      -- If HELD, we must ensure it persists in the Temp_Symbols map for the next record
      if Is_Held (Upper_Name) then
         if Temp_Symbols.Contains (Upper_Name) then
            Temp_Symbols.Replace (Upper_Name, Val);
         else
            Temp_Symbols.Insert (Upper_Name, Val);
         end if;
      end if;
   end Set_Permanent;

   ---------
   -- Get --
   ---------
   function Get (Name : String) return Value is
      Upper_Name : constant String := To_Upper (Name);
   begin
      --  1. Check Permanent PDV first.
      if Permanent_Symbols.Contains (Upper_Name) then
         declare
            V : constant Value := Permanent_Symbols.Element (Upper_Name);
         begin
            if V.Kind /= Val_Missing then
               return V;
            end if;
         end;
      end if;

      --  2. Check Temporary symbols.
      if Temp_Symbols.Contains (Upper_Name) then
         return Temp_Symbols.Element (Upper_Name);
      else
         return (Kind => Val_Missing);
      end if;
   end Get;

   ---------------------
   -- Clear_Temporary --
   ---------------------
   procedure Clear_Temporary is
   begin
      Temp_Symbols.Clear;
      -- Permanent_Symbols are NOT cleared here. They are managed by the Data Step loop.
      -- (i.e., Reset_PDV_Non_Held and Load_PDV_From_Table)
      declare
         Cursor : Array_Table_Pkg.Cursor := Array_Symbols.First;
      begin
         while Array_Table_Pkg.Has_Element (Cursor) loop
            declare
               Arr_Def : constant Array_Definition_Type := Array_Table_Pkg.Element (Cursor);
            begin
               if Arr_Def.Kind = Real_Array and then Arr_Def.Is_Temporary then
                  for I in Arr_Def.Start_Index .. Arr_Def.End_Index loop
                     declare
                        Var_Name : constant String := Get_Real_Var_Name (To_String (Arr_Def.Constituents.First_Element), I);
                     begin
                        if Temp_Symbols.Contains (Var_Name) then
                           Symbol_Table_Pkg.Delete (Temp_Symbols, Var_Name);
                        end if;
                     end;
                  end loop;
                  Array_Table_Pkg.Delete (Array_Symbols, Cursor);
                  -- Note: Restart scan as map might have reordered due to deletion.
                  Cursor := Array_Symbols.First;
               else
                  Array_Table_Pkg.Next (Cursor);
               end if;
            end;
         end loop;
      end;
   end Clear_Temporary;

   --------------------
   -- Initialize_PDV --
   --------------------
   procedure Initialize_PDV is
   begin
      Permanent_Symbols.Clear;
   end Initialize_PDV;

   -------------------------
   -- Load_PDV_From_Table --
   -------------------------
   procedure Load_PDV_From_Table (Row : Positive) is
      Col_Names : constant GNAT.Strings.String_List_Access := SData.Table.Get_Column_Names;
   begin
      if Col_Names /= null then
         for I in Col_Names'Range loop
            declare
               Name : constant String := To_Upper (Col_Names (I).all);
               Val  : constant Value := SData.Table.Get_Value (Row, Name);
            begin
               if Permanent_Symbols.Contains (Name) then
                  Permanent_Symbols.Replace (Name, Val);
               else
                  Permanent_Symbols.Insert (Name, Val);
               end if;
            end;
         end loop;
         declare Old : GNAT.Strings.String_List_Access := Col_Names; begin GNAT.Strings.Free (Old); end;
      end if;
   end Load_PDV_From_Table;

   -----------------------
   -- Refresh_PDV_Names --
   -----------------------
   procedure Refresh_PDV_Names is
      Col_Names : constant GNAT.Strings.String_List_Access := SData.Table.Get_Column_Names;
   begin
      if Col_Names /= null then
         for I in Col_Names'Range loop
            declare
               Name : constant String := To_Upper (Col_Names (I).all);
            begin
               if not Permanent_Symbols.Contains (Name) then
                  Permanent_Symbols.Insert (Name, (Kind => Val_Missing));
               end if;
            end;
         end loop;
         declare Old : GNAT.Strings.String_List_Access := Col_Names; begin GNAT.Strings.Free (Old); end;
      end if;
   end Refresh_PDV_Names;

   ------------------------
   -- Reset_PDV_Non_Held --
   ------------------------
   procedure Reset_PDV_Non_Held is
      Pos : Symbol_Table_Pkg.Cursor := Permanent_Symbols.First;
   begin
      while Symbol_Table_Pkg.Has_Element (Pos) loop
         declare
            Name : constant String := Symbol_Table_Pkg.Key (Pos);
         begin
            if not Is_Held (Name) then
               Permanent_Symbols.Replace_Element (Pos, (Kind => Val_Missing));
            else
               -- If HELD, make sure the value is also in Temp_Symbols so Get finds it
               if not Temp_Symbols.Contains (Name) then
                  Temp_Symbols.Insert (Name, Symbol_Table_Pkg.Element (Pos));
               else
                  Temp_Symbols.Replace (Name, Symbol_Table_Pkg.Element (Pos));
               end if;
            end if;
         end;
         Symbol_Table_Pkg.Next (Pos);
      end loop;
   end Reset_PDV_Non_Held;

   -----------------------
   -- Take_PDV_Snapshot --
   -----------------------
   function Take_PDV_Snapshot return Symbol_Table_Pkg.Map is
   begin
      return Permanent_Symbols;
   end Take_PDV_Snapshot;

   -------------------------------
   -- Commit_Snapshots_To_Table --
   -------------------------------
   procedure Commit_Snapshots_To_Table (Snapshots : Snapshot_Collector.Vector) is
      package Ordered_Names is new Ada.Containers.Vectors (Positive, Unbounded_String);
      Order : Ordered_Names.Vector;
   begin
      SData.Table.Clear;
      if Snapshots.Is_Empty then return; end if;
      
      -- 1. Identify all columns from all snapshots and preserve order
      for S of Snapshots loop
         declare
            Pos : Symbol_Table_Pkg.Cursor := S.First;
         begin
            while Symbol_Table_Pkg.Has_Element (Pos) loop
               declare
                  Name : constant String := Symbol_Table_Pkg.Key (Pos);
                  V    : constant Value := Symbol_Table_Pkg.Element (Pos);
                  Typ  : Column_Type := Col_Numeric;
                  Found : Boolean := False;
               begin
                  for ON of Order loop
                     if To_String (ON) = Name then Found := True; exit; end if;
                  end loop;

                  if not Found then
                     Order.Append (To_Unbounded_String (Name));
                     -- Determine type by suffix or first observed value
                     if Name'Length > 0 then
                        if Name (Name'Last) = '$' then Typ := Col_String;
                        elsif Name (Name'Last) = '%' then Typ := Col_Integer; end if;
                     end if;
                     
                     if V.Kind = Val_Integer then Typ := Col_Integer;
                     elsif V.Kind = Val_String then Typ := Col_String;
                     end if;

                     Add_Column (Name, Typ);
                  end if;
               end;
               Symbol_Table_Pkg.Next (Pos);
            end loop;
         end;
      end loop;
      
      -- 2. Add rows
      for S of Snapshots loop
         Add_Row;
         declare
            Pos : Symbol_Table_Pkg.Cursor := S.First;
         begin
            while Symbol_Table_Pkg.Has_Element (Pos) loop
               Set_Value (Row_Count, Symbol_Table_Pkg.Key (Pos), Symbol_Table_Pkg.Element (Pos));
               Symbol_Table_Pkg.Next (Pos);
            end loop;
         end;
      end loop;
   end Commit_Snapshots_To_Table;

   function Get_Type (Name : String) return Value_Kind is
      Upper : constant String := To_Upper (Name);
   begin
      if Permanent_Symbols.Contains (Upper) then
         return Permanent_Symbols.Element (Upper).Kind;
      end if;
      return Val_Missing;
   end Get_Type;

   -------------------
   -- Get_PDV_Names --
   -------------------
   function Get_PDV_Names return String_List_Access is
      Count : constant Natural := Natural (Permanent_Symbols.Length);
      List : constant String_List_Access := new String_List (1 .. Count);
      Pos  : Symbol_Table_Pkg.Cursor := Permanent_Symbols.First;
      Idx  : Positive := 1;
   begin
      while Symbol_Table_Pkg.Has_Element (Pos) loop
         List (Idx) := new String'(Symbol_Table_Pkg.Key (Pos));
         Idx := Idx + 1;
         Symbol_Table_Pkg.Next (Pos);
      end loop;
      return List;
   end Get_PDV_Names;

   ------------------
   -- Define_Array --
   ------------------
   procedure Define_Array (Name : String; Constituents : GNAT.Strings.String_List) is
      Upper_Name : constant String := To_Upper (Name);
      Arr_Def : Array_Definition_Type;
   begin
      Arr_Def.Kind := Virtual_Array;
      Arr_Def.Is_Temporary := False; -- Virtual arrays are always permanent aliases
      Arr_Def.Start_Index := 1;      -- Virtual arrays are always 1-based
      Arr_Def.End_Index := Integer(Constituents'Length);
      for I in Constituents'Range loop
         Arr_Def.Constituents.Append (To_Unbounded_String (To_Upper (Constituents (I).all)));
      end loop;
      if Array_Symbols.Contains (Upper_Name) then
         Array_Symbols.Replace (Upper_Name, Arr_Def);
      else
         Array_Symbols.Insert (Upper_Name, Arr_Def);
      end if;
   end Define_Array;

   ------------------
   -- Define_Array --
   ------------------
   procedure Define_Array (Name : String; Constituents : Name_Vectors.Vector) is
      Upper_Name : constant String := To_Upper (Name);
      Arr_Def : Array_Definition_Type;
   begin
      Arr_Def.Kind := Virtual_Array;
      Arr_Def.Is_Temporary := False;
      Arr_Def.Start_Index := 1;
      Arr_Def.End_Index := Integer(Constituents.Length);
      Arr_Def.Constituents := Constituents; -- Copy the vector
      if Array_Symbols.Contains (Upper_Name) then
         Array_Symbols.Replace (Upper_Name, Arr_Def);
      else
         Array_Symbols.Insert (Upper_Name, Arr_Def);
      end if;
   end Define_Array;

   -------------------------
   -- Define_Array_Access --
   -------------------------
   procedure Define_Array_Access (Name : String; Constituents : GNAT.Strings.String_List_Access) is
   begin
      if Constituents /= null then
         Define_Array (Name, Constituents.all);
      end if;
   end Define_Array_Access;
   
   -------------------------
   -- Create_Real_Elements --
   -------------------------
   procedure Create_Real_Elements (Arr_Def : in out Array_Definition_Type) is
      -- This procedure constructs the actual variable names and, if permanent, adds them as columns.
      -- Assumes Arr_Def.Constituents only contains the base array name (e.g., "X")
      Name_Prefix : constant String := To_String (Arr_Def.Constituents.First_Element); -- Base name like "X"
      Old_Constituents : constant Name_Vectors.Vector := Arr_Def.Constituents; -- Temporarily hold base name
   begin
      Arr_Def.Constituents.Clear;
      -- Put base name back in Constituent[0] for easy access by Get_Real_Var_Name
      Arr_Def.Constituents.Append (Old_Constituents.First_Element);

      for I in Arr_Def.Start_Index .. Arr_Def.End_Index loop
         declare
            Var_Name : constant String := Get_Real_Var_Name (Name_Prefix, I);
         begin
            Arr_Def.Constituents.Append (To_Unbounded_String(Var_Name));
            
            -- If not temporary, create as permanent column if it doesn't exist
            if not Arr_Def.Is_Temporary and then not SData.Table.Has_Column (Var_Name) then
               -- Type based on suffix of Name_Prefix if available, else numeric
               declare
                  Typ : SData.Table.Column_Type := SData.Table.Col_Numeric;
               begin
                  if Name_Prefix'Length > 0 then
                     if Name_Prefix (Name_Prefix'Last) = '$' then Typ := SData.Table.Col_String;
                     elsif Name_Prefix (Name_Prefix'Last) = '%' then Typ := SData.Table.Col_Integer; end if;
                  end if;
                  SData.Table.Add_Column (Var_Name, Typ);
               end;
            end if;
         end;
      end loop;
   end Create_Real_Elements;

   ------------------
   -- Dim_Array --
   ------------------
   procedure Dim_Array (Name : String; Start_Idx, End_Idx : Integer; Is_Temp : Boolean) is
      Upper_Name : constant String := To_Upper (Name);
      Arr_Def : Array_Definition_Type;
   begin
      -- Validate indices
      if Start_Idx > End_Idx then
         raise Program_Error with "DIM array lower bound " & Integer'Image(Start_Idx) & " cannot be greater than upper bound " & Integer'Image(End_Idx);
      end if;

      Arr_Def.Kind := Real_Array;
      Arr_Def.Is_Temporary := Is_Temp;
      Arr_Def.Start_Index := Start_Idx;
      Arr_Def.End_Index := End_Idx;
      Arr_Def.Constituents.Append (To_Unbounded_String(Upper_Name)); -- Base name at Constituents[0]

      -- Handle Redefinition/Resizing
      if Array_Symbols.Contains (Upper_Name) then
         declare
            Existing_Def : constant Array_Definition_Type := Array_Symbols.Element (Upper_Name);
         begin
            if Existing_Def.Kind = Virtual_Array then
               raise Program_Error with "Cannot redefine virtual array '" & Upper_Name & "' as real array with DIM.";
            elsif Existing_Def.Kind = Real_Array then
               -- Check for temporary status change
               if Existing_Def.Is_Temporary /= Is_Temp then
                  raise Program_Error with "Cannot change temporary status of existing real array '" & Upper_Name & "'.";
               end if;
               
               -- Resizing - For now, clear all old elements, then recreate new.
               -- TODO: Optimize for expansion/contraction to preserve values
               for I in Existing_Def.Start_Index .. Existing_Def.End_Index loop
                  -- Delete variable from system if it was part of this real array
                  declare
                     Var_Name : constant String := Get_Real_Var_Name (To_String(Existing_Def.Constituents.First_Element), I);
                  begin
                     if not Existing_Def.Is_Temporary and then SData.Table.Has_Column (Var_Name) then
                        -- For permanent real array elements, we should remove column if it's outside new bounds
                        -- but not if it's within the new bounds (to avoid data loss)
                        -- For simplicity, let's just leave old columns for now if permanent.
                        -- A separate garbage collection might be needed.
                        null;
                     end if;
                     -- For temporary elements, clear from Temp_Symbols
                     if Existing_Def.Is_Temporary and then Temp_Symbols.Contains (Var_Name) then
                        Symbol_Table_Pkg.Delete (Temp_Symbols, Var_Name);
                     end if;
                  end;
               end loop;
            end if;
         end;
      end if;

      -- Create new elements / Add elements for expansion
      Create_Real_Elements (Arr_Def);

      if Array_Symbols.Contains (Upper_Name) then
         Array_Symbols.Replace (Upper_Name, Arr_Def);
      else
         Array_Symbols.Insert (Upper_Name, Arr_Def);
      end if;
   end Dim_Array;

   -----------------------
   -- Get_Array_Element --
   -----------------------
   function Get_Array_Element (Name : String; Index : Integer) return Value is
      Upper_Name : constant String := To_Upper (Name);
   begin
      if not Array_Symbols.Contains (Upper_Name) then
         return (Kind => Val_Missing);
      end if;
      
      declare
         Arr_Def : constant Array_Definition_Type := Array_Symbols.Element (Upper_Name);
      begin
         if Index < Arr_Def.Start_Index or else Index > Arr_Def.End_Index then
            return (Kind => Val_Missing); -- Index out of bounds
         end if;

         if Arr_Def.Kind = Virtual_Array then
            -- Lookup from constituents list
            declare
               Offset : constant Positive := Index - Arr_Def.Start_Index + 1; -- Virtual arrays are 1-based internally
            begin
               if Offset > Integer(Arr_Def.Constituents.Length) then
                  return (Kind => Val_Missing); -- Should not happen if array correctly defined
               end if;
               return Get (To_String (Arr_Def.Constituents.Element (Offset)));
            end;
         else -- Real_Array
            -- Construct name like ARRAY_NAME(INDEX)
            return Get (Get_Real_Var_Name (To_String(Arr_Def.Constituents.First_Element), Index));
         end if;
      end;
   end Get_Array_Element;

   -----------------------
   -- Set_Array_Element --
   -----------------------
   procedure Set_Array_Element (Name : String; Index : Integer; Val : Value) is
      Upper_Name : constant String := To_Upper (Name);
   begin
      if not Array_Symbols.Contains (Upper_Name) then
         -- Implicit creation if array does not exist and it's a permanent Real_Array
         -- For now, error if not defined. DIM must define it explicitly.
         raise Program_Error with "Array '" & Upper_Name & "' not defined.";
      end if;

      declare
         Arr_Def : constant Array_Definition_Type := Array_Symbols.Element (Upper_Name);
      begin
         if Index < Arr_Def.Start_Index or else Index > Arr_Def.End_Index then
            raise Program_Error with "Array index " & Index'Image & " out of bounds for '" & Upper_Name & "'.";
         end if;

         declare
            Var_Name_Str : Unbounded_String;
         begin
            if Arr_Def.Kind = Virtual_Array then
               -- Lookup from constituents list
               declare
                  Offset : constant Positive := Index - Arr_Def.Start_Index + 1;
               begin
                  if Offset > Integer(Arr_Def.Constituents.Length) then
                     raise Program_Error with "Array index " & Index'Image & " out of bounds for virtual array '" & Upper_Name & "'.";
                  end if;
                  Var_Name_Str := To_Unbounded_String (To_String (Arr_Def.Constituents.Element (Offset)));
               end;
            else -- Real_Array
               -- Construct name like ARRAY_NAME(INDEX)
               Var_Name_Str := To_Unbounded_String (Get_Real_Var_Name (To_String(Arr_Def.Constituents.First_Element), Index));
            end if;

            -- Set the value using appropriate scope (temporary or permanent)
            if Arr_Def.Is_Temporary then
               Set_Temporary (To_String (Var_Name_Str), Val);
            else
               Set_Permanent (To_String (Var_Name_Str), Val);
            end if;
         end;
      end;
   end Set_Array_Element;

   ---------------
   -- Has_Array --
   ---------------
   function Has_Array (Name : String) return Boolean is
   begin
      return Array_Symbols.Contains (To_Upper (Name));
   end Has_Array;

   ----------------------
   -- Get_Array_Bounds --
   ----------------------
   procedure Get_Array_Bounds (Name : String; Start_Idx, End_Idx : out Integer) is
      Upper_Name : constant String := To_Upper (Name);
   begin
      if Array_Symbols.Contains (Upper_Name) then
         declare
            Arr_Def : constant Array_Definition_Type := Array_Symbols.Element (Upper_Name);
         begin
            Start_Idx := Arr_Def.Start_Index;
            End_Idx   := Arr_Def.End_Index;
         end;
      else
         Start_Idx := 0;
         End_Idx   := -1;
      end if;
   end Get_Array_Bounds;

   --------------
   -- Set_Hold --
   --------------
   procedure Set_Hold (Name : String; State : Boolean) is
      Upper_Name : constant String := To_Upper (Name);
   begin
      if Upper_Name = "" then return; end if;
      if Hold_Symbols.Contains (Upper_Name) then
         Hold_Symbols.Replace (Upper_Name, State);
      else
         Hold_Symbols.Insert (Upper_Name, State);
      end if;
   end Set_Hold;

   -------------
   -- Is_Held --
   -------------
   function Is_Held (Name : String) return Boolean is
      Upper_Name : constant String := To_Upper (Name);
   begin
      if Hold_Symbols.Contains (Upper_Name) then
         return Hold_Symbols.Element (Upper_Name);
      else
         return False;
      end if;
   end Is_Held;

   --------------------------
   -- Set_Current_Group_Key --
   --------------------------
   procedure Set_Current_Group_Key (Key : String) is
   begin
      Current_Group_ID := To_Unbounded_String (Key);
   end Set_Current_Group_Key;

   --------------------------
   -- Get_Current_Group_Key --
   --------------------------
   function Get_Current_Group_Key return String is
   begin
      return To_String (Current_Group_ID);
   end Get_Current_Group_Key;

end SData.Variables;
