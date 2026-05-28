--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

with Ada.Characters.Handling; use Ada.Characters.Handling;

package body SData.Transient_Table is

   --  Internal helper: returns the 1-based index of the column whose
   --  upper-cased name equals Upper_Name, or 0 if not found.
   function Column_Index_Upper
     (T : Table; Upper_Name : String) return Natural
   is
   begin
      for I in 1 .. Natural (T.Cols.Length) loop
         if To_Upper (To_String (T.Cols (I).Name)) = Upper_Name then
            return I;
         end if;
      end loop;
      return 0;
   end Column_Index_Upper;

   ---------------------------------------------------------------------------
   --  Schema
   ---------------------------------------------------------------------------

   procedure Add_Column
     (T        : in out Table;
      Name     : String;
      Col_Type : SData_Core.Table.Column_Type)
   is
      Empty : Value_Vectors.Vector;
   begin
      if Column_Index_Upper (T, To_Upper (Name)) /= 0 then
         raise Constraint_Error
           with "Transient_Table.Add_Column: duplicate name " & Name;
      end if;
      T.Cols.Append ((Name => To_Unbounded_String (Name), Typ => Col_Type));
      --  Pre-fill the new column with missing values for existing rows.
      for R in 1 .. T.N_Rows loop
         Empty.Append ((Kind => SData_Core.Values.Val_Missing));
      end loop;
      T.Data.Append (Empty);
   end Add_Column;

   function Has_Column (T : Table; Name : String) return Boolean is
   begin
      return Column_Index_Upper (T, To_Upper (Name)) /= 0;
   end Has_Column;

   function Column_Count (T : Table) return Natural is
   begin
      return Natural (T.Cols.Length);
   end Column_Count;

   function Column_Name (T : Table; I : Positive) return String is
   begin
      return To_String (T.Cols (I).Name);
   end Column_Name;

   function Get_Column_Type
     (T : Table; Name : String) return SData_Core.Table.Column_Type
   is
      Idx : constant Natural := Column_Index_Upper (T, To_Upper (Name));
   begin
      if Idx = 0 then
         raise Constraint_Error
           with "Transient_Table.Get_Column_Type: unknown column " & Name;
      end if;
      return T.Cols (Idx).Typ;
   end Get_Column_Type;

   ---------------------------------------------------------------------------
   --  Rows
   ---------------------------------------------------------------------------

   procedure Add_Row (T : in out Table) is
   begin
      T.N_Rows := T.N_Rows + 1;
      --  Append a missing value to each column's data vector.
      for I in 1 .. Natural (T.Data.Length) loop
         declare
            CV : Value_Vectors.Vector := T.Data (I);
         begin
            CV.Append ((Kind => SData_Core.Values.Val_Missing));
            T.Data.Replace_Element (I, CV);
         end;
      end loop;
   end Add_Row;

   function Row_Count (T : Table) return Natural is
   begin
      return T.N_Rows;
   end Row_Count;

   ---------------------------------------------------------------------------
   --  Value access
   ---------------------------------------------------------------------------

   function Get_Value
     (T   : Table;
      Row : Positive;
      Col : String)
     return SData_Core.Values.Value
   is
      Idx : constant Natural := Column_Index_Upper (T, To_Upper (Col));
   begin
      if Idx = 0 then
         raise Constraint_Error
           with "Transient_Table.Get_Value: unknown column " & Col;
      end if;
      return T.Data (Idx).Element (Row);
   end Get_Value;

   procedure Set_Value
     (T   : in out Table;
      Row : Positive;
      Col : String;
      Val : SData_Core.Values.Value)
   is
      Idx : constant Natural := Column_Index_Upper (T, To_Upper (Col));
   begin
      if Idx = 0 then
         raise Constraint_Error
           with "Transient_Table.Set_Value: unknown column " & Col;
      end if;
      declare
         CV : Value_Vectors.Vector := T.Data (Idx);
      begin
         CV.Replace_Element (Row, Val);
         T.Data.Replace_Element (Idx, CV);
      end;
   end Set_Value;

   ---------------------------------------------------------------------------
   --  Snapshot bridges
   ---------------------------------------------------------------------------

   function Snapshot_From_Current return Table is
      Result : Table;
      N      : constant Natural := SData_Core.Table.Column_Count;
      Rows   : constant Natural := SData_Core.Table.Row_Count;
   begin
      for I in 1 .. N loop
         declare
            Name : constant String := SData_Core.Table.Column_Name (I);
         begin
            Result.Add_Column
              (Name, SData_Core.Table.Get_Column_Type (Name));
         end;
      end loop;
      for R in 1 .. Rows loop
         Result.Add_Row;
         for I in 1 .. N loop
            declare
               Name : constant String := SData_Core.Table.Column_Name (I);
            begin
               Result.Set_Value
                 (R, Name, SData_Core.Table.Get_Value (R, Name));
            end;
         end loop;
      end loop;
      return Result;
   end Snapshot_From_Current;

   procedure Install_To_Current (T : Table) is
   begin
      SData_Core.Table.Clear;
      for I in 1 .. Column_Count (T) loop
         SData_Core.Table.Add_Column
           (Column_Name (T, I), T.Cols (I).Typ);
      end loop;
      for R in 1 .. T.N_Rows loop
         SData_Core.Table.Add_Row;
         for I in 1 .. Column_Count (T) loop
            declare
               Name : constant String := Column_Name (T, I);
            begin
               SData_Core.Table.Set_Value
                 (R, Name, T.Data (I).Element (R));
            end;
         end loop;
      end loop;
   end Install_To_Current;

end SData.Transient_Table;
