with Ada.Characters.Handling; use Ada.Characters.Handling;
with SData.Table;           use SData.Table;

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

end SData.Variables;
