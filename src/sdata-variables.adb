with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with GNAT.Strings; use GNAT.Strings;

package body SData.Variables is

   -------------------
   -- Set_Temporary --
   -------------------
   procedure Set_Temporary (Name : String; Val : Value) is
      Upper_Name : constant String := To_Upper (Name);
   begin
      --  Rule: SET cannot overwrite a permanent variable (column).
      if SData.Table.Has_Column (Upper_Name) then
         raise Program_Error with "Cannot SET permanent variable " & Upper_Name & " as temporary.";
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
         Temp_Symbols.Delete (Upper_Name);
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
      Permanent_Symbols.Clear;
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
      use GNAT.Strings;
      Col_Names : String_List_Access := SData.Table.Get_Column_Names;
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
         declare Old : String_List_Access := Col_Names; begin GNAT.Strings.Free (Old); end;
      end if;
   end Load_PDV_From_Table;

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
      use SData.Table;
      package Ordered_Names is new Ada.Containers.Vectors (Positive, Ada.Strings.Unbounded.Unbounded_String);
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
      use GNAT.Strings;
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
      V : Name_Vectors.Vector;
   begin
      for I in Constituents'Range loop
         Name_Vectors.Append (V, To_Unbounded_String (To_Upper (Constituents (I).all)));
      end loop;
      if Array_Symbols.Contains (Upper_Name) then
         Array_Symbols.Replace (Upper_Name, V);
      else
         Array_Symbols.Insert (Upper_Name, V);
      end if;
   end Define_Array;

   ------------------
   -- Define_Array --
   ------------------
   procedure Define_Array (Name : String; Constituents : Name_Vectors.Vector) is
      Upper_Name : constant String := To_Upper (Name);
   begin
      if Array_Symbols.Contains (Upper_Name) then
         Array_Symbols.Replace (Upper_Name, Constituents);
      else
         Array_Symbols.Insert (Upper_Name, Constituents);
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

   -----------------------
   -- Get_Array_Element --
   -----------------------
   function Get_Array_Element (Name : String; Index : Positive) return Value is
      Upper_Name : constant String := To_Upper (Name);
   begin
      if not Array_Symbols.Contains (Upper_Name) then
         return (Kind => Val_Missing);
      end if;
      
      declare
         V : constant Name_Vectors.Vector := Array_Symbols.Element (Upper_Name);
      begin
         if Index > Natural (V.Length) then
            return (Kind => Val_Missing);
         end if;
         return Get (To_String (V.Element (Index)));
      end;
   end Get_Array_Element;

   -----------------------
   -- Set_Array_Element --
   -----------------------
   procedure Set_Array_Element (Name : String; Index : Positive; Val : Value) is
      Upper_Name : constant String := To_Upper (Name);
   begin
      if not Array_Symbols.Contains (Upper_Name) then
         return;
      end if;

      declare
         V : constant Name_Vectors.Vector := Array_Symbols.Element (Upper_Name);
         Actual_Val : constant Value := Val;
      begin
         if Index > Natural (V.Length) then
            return;
         end if;
         
         declare
            Var_Name : constant String := To_String (V.Element (Index));
         begin
            Set_Permanent (Var_Name, Actual_Val);
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

   ---------------------
   -- Store_Aggregate --
   ---------------------
   procedure Store_Aggregate (Func_Name, Var_Name, Group_Key : String; Val : Value) is
      Key : constant String := To_Upper (Func_Name) & ":" & To_Upper (Var_Name) & ":" & Group_Key;
   begin
      if Aggregate_Symbols.Contains (Key) then
         Aggregate_Symbols.Replace (Key, Val);
      else
         Aggregate_Symbols.Insert (Key, Val);
      end if;
   end Store_Aggregate;

   -------------------
   -- Get_Aggregate --
   -------------------
   function Get_Aggregate (Func_Name, Var_Name, Group_Key : String) return Value is
      Key : constant String := To_Upper (Func_Name) & ":" & To_Upper (Var_Name) & ":" & Group_Key;
   begin
      if Aggregate_Symbols.Contains (Key) then
         return Aggregate_Symbols.Element (Key);
      else
         return (Kind => Val_Missing);
      end if;
   end Get_Aggregate;

   ----------------------
   -- Clear_Aggregates --
   ----------------------
   procedure Clear_Aggregates is
   begin
      Aggregate_Symbols.Clear;
   end Clear_Aggregates;

end SData.Variables;
