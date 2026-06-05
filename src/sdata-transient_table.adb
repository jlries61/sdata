--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

with Ada.Characters.Handling;    use Ada.Characters.Handling;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Strings.Hash;

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

   --  Map a name's type suffix to a column type: '$' -> string,
   --  '%' -> integer, otherwise numeric (float).  Mirrors the evaluator's
   --  Get_Expected_Kind so RENAME honours the suffix-determines-type rule.
   function Type_From_Name
     (Name : String) return SData_Core.Table.Column_Type
   is
      use SData_Core.Table;
   begin
      if Name'Length = 0 then
         return Col_Numeric;
      elsif Name (Name'Last) = '$' then
         return Col_String;
      elsif Name (Name'Last) = '%' then
         return Col_Integer;
      else
         return Col_Numeric;
      end if;
   end Type_From_Name;

   --  Value_Kind corresponding to a column type.
   function Kind_Of
     (T : SData_Core.Table.Column_Type) return SData_Core.Values.Value_Kind
   is
      use SData_Core.Table;
      use SData_Core.Values;
   begin
      case T is
         when Col_Numeric => return Val_Numeric;
         when Col_Integer => return Val_Integer;
         when Col_String  => return Val_String;
      end case;
   end Kind_Of;

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

   ---------------------------------------------------------------------------
   --  Column projection / mutation
   ---------------------------------------------------------------------------

   procedure Apply_Keep
     (T : in out Table; Names : Name_Vectors.Vector)
   is
      package U is new Ada.Containers.Indefinite_Hashed_Sets
        (Element_Type        => String,
         Hash                => Ada.Strings.Hash,
         Equivalent_Elements => "=");
      Keep_Set : U.Set;
   begin
      for N of Names loop
         Keep_Set.Include (To_Upper (To_String (N)));
      end loop;
      for I in reverse 1 .. Natural (T.Cols.Length) loop
         if not Keep_Set.Contains
                  (To_Upper (To_String (T.Cols (I).Name)))
         then
            T.Cols.Delete (I);
            T.Data.Delete (I);
         end if;
      end loop;
   end Apply_Keep;

   ---------------------------------------------------------------------------

   procedure Apply_Drop
     (T : in out Table; Names : Name_Vectors.Vector)
   is
   begin
      for N of Names loop
         declare
            Idx : constant Natural :=
              Column_Index_Upper (T, To_Upper (To_String (N)));
         begin
            if Idx /= 0 then
               T.Cols.Delete (Idx);
               T.Data.Delete (Idx);
            end if;
         end;
      end loop;
   end Apply_Drop;

   ---------------------------------------------------------------------------

   procedure Apply_Rename
     (T : in out Table; Pairs : Rename_Map_Vectors.Vector)
   is
      package U is new Ada.Containers.Indefinite_Hashed_Sets
        (Element_Type        => String,
         Hash                => Ada.Strings.Hash,
         Equivalent_Elements => "=");
      Seen_Old : U.Set;
      Seen_New : U.Set;
   begin
      --  Validate: no duplicate source names, no duplicate target names.
      for P of Pairs loop
         declare
            Old_Up : constant String := To_Upper (To_String (P.Old_Name));
            New_Up : constant String := To_Upper (To_String (P.New_Name));
         begin
            if Seen_Old.Contains (Old_Up) then
               raise Rename_Error
                 with "Apply_Rename: duplicate source name "
                      & To_String (P.Old_Name);
            end if;
            Seen_Old.Include (Old_Up);

            if Seen_New.Contains (New_Up) then
               raise Rename_Error
                 with "Apply_Rename: duplicate target name "
                      & To_String (P.New_Name);
            end if;
            Seen_New.Include (New_Up);
         end;
      end loop;

      --  Validate: no target name collides with a non-renamed existing column.
      for I in 1 .. Natural (T.Cols.Length) loop
         declare
            Col_Up : constant String :=
              To_Upper (To_String (T.Cols (I).Name));
         begin
            if Seen_New.Contains (Col_Up)
              and then not Seen_Old.Contains (Col_Up)
            then
               raise Rename_Error
                 with "Apply_Rename: target name collides with existing column "
                      & To_String (T.Cols (I).Name);
            end if;
         end;
      end loop;

      --  Validate: a suffix change must stay within the numeric family
      --  (float <-> integer).  Crossing the numeric/character boundary is
      --  rejected here, before any mutation, so nothing is applied on error
      --  (all-or-nothing).  Runs after the duplicate/collision checks so
      --  those messages fire first.
      for I in 1 .. Natural (T.Cols.Length) loop
         declare
            Col_Up  : constant String :=
              To_Upper (To_String (T.Cols (I).Name));
            Cur_Typ : constant SData_Core.Table.Column_Type := T.Cols (I).Typ;
            use type SData_Core.Table.Column_Type;
         begin
            for P of Pairs loop
               if To_Upper (To_String (P.Old_Name)) = Col_Up then
                  declare
                     New_Typ : constant SData_Core.Table.Column_Type :=
                       Type_From_Name (To_String (P.New_Name));
                  begin
                     if (Cur_Typ = SData_Core.Table.Col_String)
                          /= (New_Typ = SData_Core.Table.Col_String)
                     then
                        raise Rename_Error with
                          "Apply_Rename: cannot retype column "
                          & To_String (P.Old_Name)
                          & " across the numeric/character boundary ("
                          & To_String (P.Old_Name) & " -> "
                          & To_String (P.New_Name) & ")";
                     end if;
                  end;
                  exit;
               end if;
            end loop;
         end;
      end loop;

      --  Apply: simultaneous rename evaluated against original names.
      for I in 1 .. Natural (T.Cols.Length) loop
         declare
            Col_Up : constant String :=
              To_Upper (To_String (T.Cols (I).Name));
         begin
            for P of Pairs loop
               if To_Upper (To_String (P.Old_Name)) = Col_Up then
                  declare
                     Entry_Val : Col_Entry := T.Cols (I);
                     New_Typ   : constant SData_Core.Table.Column_Type :=
                       Type_From_Name (To_String (P.New_Name));
                     use type SData_Core.Table.Column_Type;
                  begin
                     if New_Typ /= Entry_Val.Typ then
                        --  Convert every value in this column to the new kind.
                        declare
                           CV       : Value_Vectors.Vector := T.Data (I);
                           New_Kind : constant SData_Core.Values.Value_Kind :=
                             Kind_Of (New_Typ);
                        begin
                           for R in 1 .. Natural (CV.Length) loop
                              CV.Replace_Element
                                (R, SData_Core.Values.Convert_Value
                                      (CV.Element (R), New_Kind));
                           end loop;
                           T.Data.Replace_Element (I, CV);
                        end;
                        Entry_Val.Typ := New_Typ;
                     end if;
                     Entry_Val.Name := P.New_Name;
                     T.Cols.Replace_Element (I, Entry_Val);
                  end;
                  exit;
               end if;
            end loop;
         end;
      end loop;
   end Apply_Rename;

   ---------------------------------------------------------------------------

   procedure Sort_By
     (T : in out Table; Keys : Name_Vectors.Vector)
   is
      N_Rows : constant Natural := T.N_Rows;
   begin
      if N_Rows < 2 then
         return;
      end if;

      --  Build list of resolved key column indices (silently skip unknowns).
      declare
         type Index_Array is array (Positive range <>) of Natural;
         Max_Keys  : constant Positive := Positive (Keys.Length) + 1;
         Key_Idxs  : Index_Array (1 .. Max_Keys) := (others => 0);
         N_Keys    : Natural := 0;

         --  Permutation array: Perm(i) = physical row to place at position i.
         type Perm_Array is array (Positive range <>) of Positive;
         Perm : Perm_Array (1 .. N_Rows);

         function Less (A, B : Positive) return Boolean is
         --  Returns True when the row at physical index A sorts before B.
         begin
            for K in 1 .. N_Keys loop
               declare
                  Idx : constant Natural := Key_Idxs (K);
                  VA  : constant SData_Core.Values.Value :=
                    T.Data (Idx).Element (A);
                  VB  : constant SData_Core.Values.Value :=
                    T.Data (Idx).Element (B);
               begin
                  if SData_Core.Values."<" (VA, VB) then
                     return True;
                  elsif SData_Core.Values."<" (VB, VA) then
                     return False;
                  end if;
                  --  Equal on this key; continue to next.
               end;
            end loop;
            return False;
         end Less;

      begin
         --  Resolve key column indices.
         for K of Keys loop
            declare
               Idx : constant Natural :=
                 Column_Index_Upper (T, To_Upper (To_String (K)));
            begin
               if Idx /= 0 then
                  N_Keys := N_Keys + 1;
                  Key_Idxs (N_Keys) := Idx;
               end if;
            end;
         end loop;

         if N_Keys = 0 then
            return;
         end if;

         --  Initialize permutation to identity.
         for I in 1 .. N_Rows loop
            Perm (I) := I;
         end loop;

         --  Insertion sort on the permutation array.
         for I in 2 .. N_Rows loop
            declare
               Key_Val : constant Positive := Perm (I);
               J       : Natural := I - 1;
            begin
               while J >= 1 and then Less (Key_Val, Perm (J)) loop
                  Perm (J + 1) := Perm (J);
                  J := J - 1;
               end loop;
               Perm (J + 1) := Key_Val;
            end;
         end loop;

         --  Materialize the permutation: build new data column by column.
         for C in 1 .. Natural (T.Data.Length) loop
            declare
               Old_Col : constant Value_Vectors.Vector := T.Data (C);
               New_Col : Value_Vectors.Vector;
            begin
               for I in 1 .. N_Rows loop
                  New_Col.Append (Old_Col.Element (Perm (I)));
               end loop;
               T.Data.Replace_Element (C, New_Col);
            end;
         end loop;
      end;
   end Sort_By;

end SData.Transient_Table;
