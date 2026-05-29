--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later

with Ada.Characters.Handling; use Ada.Characters.Handling;
with SData_Core.Values;

package body SData.Merge is

   --  ---- Schema-building helper -------------------------------------
   --  Build the result schema: columns are taken in order from each
   --  input, skipping names already present from earlier inputs. On
   --  collision the source shifts to the rightmost input (last wins)
   --  and one warning is emitted per colliding name.

   type Col_Source is record
      Table_Idx : Positive;
      Col_Name  : Unbounded_String;
   end record;
   package Source_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Col_Source);

   procedure Build_Schema
     (Result   : in out SData.Transient_Table.Table;
      Sources  : in out Source_Vectors.Vector;
      Inputs   : Table_Vectors.Vector;
      Warnings : in out Warning_Vectors.Vector)
   is
      function Find_Result_Col (Up : String) return Natural is
      begin
         for I in 1 .. SData.Transient_Table.Column_Count (Result) loop
            if To_Upper
                 (SData.Transient_Table.Column_Name (Result, I)) = Up
            then
               return I;
            end if;
         end loop;
         return 0;
      end Find_Result_Col;
   begin
      for T_Idx in 1 .. Natural (Inputs.Length) loop
         declare
            T : constant Table_Access := Inputs (T_Idx);
            N : constant Natural :=
                  SData.Transient_Table.Column_Count (T.all);
         begin
            for C in 1 .. N loop
               declare
                  Name : constant String :=
                     SData.Transient_Table.Column_Name (T.all, C);
                  Up   : constant String := To_Upper (Name);
                  Pos  : constant Natural := Find_Result_Col (Up);
               begin
                  if Pos = 0 then
                     Result.Add_Column
                       (Name,
                        SData.Transient_Table.Get_Column_Type (T.all, Name));
                     Sources.Append
                       ((Table_Idx => T_Idx,
                         Col_Name  => To_Unbounded_String (Name)));
                  else
                     Warnings.Append
                       (To_Unbounded_String
                          ("column name collision: " & Name
                             & " (last dataset wins)"));
                     Sources (Pos).Table_Idx := T_Idx;
                     Sources (Pos).Col_Name :=
                        To_Unbounded_String (Name);
                  end if;
               end;
            end loop;
         end;
      end loop;
   end Build_Schema;

   --  ---- Combine_Positional -----------------------------------------

   function Combine_Positional
     (Inputs   : Table_Vectors.Vector;
      Warnings : in out Warning_Vectors.Vector)
      return SData.Transient_Table.Table
   is
      Result   : SData.Transient_Table.Table;
      Sources  : Source_Vectors.Vector;
      Max_Rows : Natural := 0;
   begin
      Build_Schema (Result, Sources, Inputs, Warnings);
      for I in 1 .. Natural (Inputs.Length) loop
         if SData.Transient_Table.Row_Count (Inputs (I).all) > Max_Rows then
            Max_Rows := SData.Transient_Table.Row_Count (Inputs (I).all);
         end if;
      end loop;
      for R in 1 .. Max_Rows loop
         Result.Add_Row;
         for C in 1 .. Natural (Sources.Length) loop
            declare
               Src : constant Col_Source := Sources (C);
               T   : constant Table_Access := Inputs (Src.Table_Idx);
               V   : SData_Core.Values.Value;
            begin
               if R <= SData.Transient_Table.Row_Count (T.all) then
                  V := T.Get_Value (R, To_String (Src.Col_Name));
               else
                  V := (Kind => SData_Core.Values.Val_Missing);
               end if;
               Result.Set_Value
                 (R, SData.Transient_Table.Column_Name (Result, C), V);
            end;
         end loop;
      end loop;
      return Result;
   end Combine_Positional;

   --  ---- Stubs for tasks 12-14 --------------------------------------

   function Combine_Match
     (Inputs   : Table_Vectors.Vector;
      By_Vars  : SData.Transient_Table.Name_Vectors.Vector;
      Warnings : in out Warning_Vectors.Vector)
      return SData.Transient_Table.Table
   is
      pragma Unreferenced (Inputs, By_Vars, Warnings);
      R : SData.Transient_Table.Table;
   begin
      raise Program_Error with "Combine_Match not yet implemented";
      return R;
   end Combine_Match;

   function Combine_Interleave
     (Inputs   : Table_Vectors.Vector;
      By_Vars  : SData.Transient_Table.Name_Vectors.Vector;
      Warnings : in out Warning_Vectors.Vector)
      return SData.Transient_Table.Table
   is
      pragma Unreferenced (Inputs, By_Vars, Warnings);
      R : SData.Transient_Table.Table;
   begin
      raise Program_Error with "Combine_Interleave not yet implemented";
      return R;
   end Combine_Interleave;

   function Combine_Join
     (Inputs   : Table_Vectors.Vector;
      By_Vars  : SData.Transient_Table.Name_Vectors.Vector;
      Warnings : in out Warning_Vectors.Vector)
      return SData.Transient_Table.Table
   is
      pragma Unreferenced (Inputs, By_Vars, Warnings);
      R : SData.Transient_Table.Table;
   begin
      raise Program_Error with "Combine_Join not yet implemented";
      return R;
   end Combine_Join;

end SData.Merge;
