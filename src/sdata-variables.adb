with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Strings.Unbounded;

package body SData.Variables is

   -------------------
   -- Set_Temporary --
   -------------------
   procedure Set_Temporary (Name : String; Val : Value) is
      Upper_Name : constant String := To_Upper (Name);
   begin
      --  Rule: SET cannot overwrite a permanent variable (column).
      if Has_Column (Upper_Name) then
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
      --  Rule: If it doesn't exist in the table, create the column.
      if not Has_Column (Upper_Name) then
         declare
            Typ : Column_Type := Col_Numeric;
         begin
            if Name (Name'Last) = '$' then Typ := Col_String;
            elsif Name (Name'Last) = '%' then Typ := Col_Integer; end if;
            Add_Column (Upper_Name, Typ);
         end;
      end if;

      --  If we were tracking this as a temporary variable, remove it from that pool (Promotion).
      if Temp_Symbols.Contains (Upper_Name) then
         Temp_Symbols.Delete (Upper_Name);
      end if;

      --  Update the table cell for the current record.
      if Get_Current_Record_Index > 0 then
         Set_Value (Get_Current_Record_Index, Upper_Name, Val);
      else
         --  Note: If not in a data step, LET creates the column structure but has no cell to write to.
         null;
      end if;
   end Set_Permanent;

   ---------
   -- Get --
   ---------
   function Get (Name : String) return Value is
      Upper_Name : constant String := To_Upper (Name);
   begin
      --  1. Check Data Table (Permanent).
      if Get_Current_Record_Index > 0 then
         declare
            Val : constant Value := Get_Value (Get_Current_Record_Index, Upper_Name);
         begin
            if Val.Kind /= Val_Missing then
               return Val;
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
   end Clear_Temporary;

   ------------------
   -- Define_Array --
   ------------------
   procedure Define_Array (Name : String; Constituents : GNAT.Strings.String_List) is
      use Ada.Strings.Unbounded;
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
      use GNAT.Strings;
   begin
      if Constituents /= null then
         Define_Array (Name, Constituents.all);
      end if;
   end Define_Array_Access;

   -----------------------
   -- Get_Array_Element --
   -----------------------
   function Get_Array_Element (Name : String; Index : Positive) return Value is
      use Ada.Strings.Unbounded;
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
      use Ada.Strings.Unbounded;
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
            -- Promotion logic similar to LET
            if Has_Column (Var_Name) then
               -- We'd need to know the column type. Variables.ads doesn't see Table's internal types easily.
               -- Actually, Set_Permanent handles column creation.
               -- But it doesn't handle type matching.
               null;
            end if;
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

end SData.Variables;
