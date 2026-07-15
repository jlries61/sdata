--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later

with Ada.Characters.Handling; use Ada.Characters.Handling;
with SData_Core.Config.Runtime;
with SData_Core.Values;
with SData_Core.Table;

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

   --  ---- Package-body-level helpers for BY-sorted merge algorithms ------
   --  These are shared by Combine_Match, Combine_Interleave, and
   --  Combine_Join. They are not exported from the package spec.

   --  Unconstrained cursor array type: one Natural slot per input table.
   --  Value 1..Row_Count means "current row"; value > Row_Count means
   --  "exhausted". Initialise to 1 on entry.
   type Cursor_Array is array (Positive range <>) of Natural;

   --  Compare the BY-key at (TI, RI) with (TJ, RJ).
   --  Returns -1, 0, or +1 (lexicographic across By_Vars).
   function Key_Compare
     (By_Vars : SData.Transient_Table.Name_Vectors.Vector;
      TI : Table_Access; RI : Positive;
      TJ : Table_Access; RJ : Positive) return Integer
   is
   begin
      for K of By_Vars loop
         declare
            Name : constant String := To_String (K);
            VI   : constant SData_Core.Values.Value :=
                      TI.Get_Value (RI, Name);
            VJ   : constant SData_Core.Values.Value :=
                      TJ.Get_Value (RJ, Name);
         begin
            if SData_Core.Values."<" (VI, VJ) then return -1;
            elsif SData_Core.Values."<" (VJ, VI) then return 1;
            end if;
         end;
      end loop;
      return 0;
   end Key_Compare;

   --  Among all non-exhausted cursors, find the one with the smallest
   --  BY key (leftmost wins on ties). Returns False when all exhausted.
   function Find_Min_Key
     (By_Vars : SData.Transient_Table.Name_Vectors.Vector;
      Inputs  : Table_Vectors.Vector;
      Cursors : Cursor_Array;
      Min_Idx : out Positive) return Boolean
   is
      Found : Boolean := False;
   begin
      Min_Idx := 1;
      for I in Cursors'Range loop
         if Cursors (I) <=
            SData.Transient_Table.Row_Count (Inputs (I).all)
         then
            if not Found then
               Min_Idx := I;
               Found := True;
            elsif Key_Compare
                    (By_Vars,
                     Inputs (I), Cursors (I),
                     Inputs (Min_Idx), Cursors (Min_Idx)) < 0
            then
               Min_Idx := I;
            end if;
         end if;
      end loop;
      return Found;
   end Find_Min_Key;

   --  For the BY-key at the current cursor of each input, collect all
   --  consecutive rows with the same key into [Group_Start, Group_Start+Group_Size).
   --  Cursors are advanced past each group. Group_Size = 0 for inputs whose
   --  cursor is exhausted or whose current key differs from Reference_Idx.
   procedure Consume_Group
     (Cursors       : in out Cursor_Array;
      Inputs        : Table_Vectors.Vector;
      By_Vars       : SData.Transient_Table.Name_Vectors.Vector;
      Reference_Idx : Positive;
      Group_Start   : out Cursor_Array;
      Group_Size    : out Cursor_Array)
   is
      Ref_Start_Row : constant Positive := Cursors (Reference_Idx);
   begin
      for I in Cursors'Range loop
         Group_Start (I) := 0;
         Group_Size  (I) := 0;
         if Cursors (I) <=
            SData.Transient_Table.Row_Count (Inputs (I).all)
            and then Key_Compare
                       (By_Vars,
                        Inputs (I), Cursors (I),
                        Inputs (Reference_Idx), Ref_Start_Row) = 0
         then
            Group_Start (I) := Cursors (I);
            while Cursors (I) <=
                     SData.Transient_Table.Row_Count (Inputs (I).all)
               and then Key_Compare
                          (By_Vars,
                           Inputs (I), Cursors (I),
                           Inputs (Reference_Idx), Ref_Start_Row) = 0
            loop
               Group_Size (I) := Group_Size (I) + 1;
               Cursors (I) := Cursors (I) + 1;
            end loop;
         end if;
      end loop;
   end Consume_Group;

   --  Return a human-readable string describing the BY-key values at (T, Row).
   function By_Group_Key_String
     (By_Vars : SData.Transient_Table.Name_Vectors.Vector;
      T       : Table_Access;
      Row     : Positive) return String
   is
      R     : Unbounded_String;
      First : Boolean := True;
   begin
      for K of By_Vars loop
         if not First then R := R & ", "; end if;
         R := R & To_String (K) & "=";
         declare
            Vv : constant SData_Core.Values.Value :=
                    T.Get_Value (Row, To_String (K));
         begin
            case Vv.Kind is
               when SData_Core.Values.Val_Numeric =>
                  --  Round-trip render (not 'Image) so a whole-number key shows
                  --  as e.g. "1" rather than "1.00000000000000E+00" now that
                  --  Num_Val is double precision (#54).
                  R := R & SData_Core.Values.Image_Round_Trip (Vv.Num_Val);
               when SData_Core.Values.Val_Integer =>
                  R := R & Vv.Int_Val'Image;
               when SData_Core.Values.Val_String =>
                  R := R & "'" & To_String (Vv.Str_Val) & "'";
               when SData_Core.Values.Val_Missing =>
                  R := R & ".";
            end case;
         end;
         First := False;
      end loop;
      return To_String (R);
   end By_Group_Key_String;

   --  Filter the Schema_Warnings produced by Build_Schema into the
   --  caller's Warnings vector, suppressing collision warnings for
   --  BY-variable columns (which are intentionally shared).
   procedure Forward_Schema_Warnings
     (By_Vars         : SData.Transient_Table.Name_Vectors.Vector;
      Schema_Warnings : Warning_Vectors.Vector;
      Warnings        : in out Warning_Vectors.Vector)
   is
      Pfx : constant String := "column name collision: ";
   begin
      for W of Schema_Warnings loop
         declare
            Is_By_Collision : Boolean := False;
            Msg             : constant String := To_String (W);
         begin
            --  Build_Schema formats collision warnings as
            --  "column name collision: <Name> (last dataset wins)".
            --  Suppress the warning if <Name> is a BY variable.
            for K of By_Vars loop
               declare
                  KUp : constant String :=
                           Ada.Characters.Handling.To_Upper (To_String (K));
               begin
                  if Msg'Length > Pfx'Length
                     and then Msg (Msg'First .. Msg'First + Pfx'Length - 1)
                                 = Pfx
                  then
                     declare
                        After_Pfx : constant String :=
                           Msg (Msg'First + Pfx'Length .. Msg'Last);
                        --  After_Pfx starts with the column name; find
                        --  the space that follows the name.
                        Space_Pos : Natural := 0;
                     begin
                        for J in After_Pfx'Range loop
                           if After_Pfx (J) = ' ' then
                              Space_Pos := J;
                              exit;
                           end if;
                        end loop;
                        if Space_Pos > After_Pfx'First then
                           declare
                              Col_Name_In_Msg : constant String :=
                                 Ada.Characters.Handling.To_Upper
                                    (After_Pfx
                                       (After_Pfx'First
                                        .. Space_Pos - 1));
                           begin
                              if Col_Name_In_Msg = KUp then
                                 Is_By_Collision := True;
                              end if;
                           end;
                        end if;
                     end;
                  end if;
               end;
            end loop;
            if not Is_By_Collision then
               Warnings.Append (W);
            end if;
         end;
      end loop;
   end Forward_Schema_Warnings;

   --  ---- Provenance helper -------------------------------------------
   --  Append one Row_Provenance entry to Provenance for an output row.
   --  Contributors(I) is True iff input I (1-based, length = N_Inputs)
   --  contributed a real value row (not padding/missing) to this output row.
   procedure Append_Provenance
     (Provenance   : in out Provenance_Vectors.Vector;
      N_Inputs     : Positive;
      Contributed  : Boolean_Vectors.Vector)
   is
      Prov : Row_Provenance;
   begin
      pragma Assert (Natural (Contributed.Length) = N_Inputs);
      Prov.Contributors := Contributed;
      Provenance.Append (Prov);
   end Append_Provenance;

   --  ---- Combine_Positional -----------------------------------------

   function Combine_Positional
     (Inputs     : Table_Vectors.Vector;
      Warnings   : in out Warning_Vectors.Vector;
      Provenance : in out Provenance_Vectors.Vector)
      return SData.Transient_Table.Table
   is
      Result   : SData.Transient_Table.Table;
      Sources  : Source_Vectors.Vector;
      N_Inputs : constant Positive := Positive (Inputs.Length);
      Max_Rows : Natural := 0;
   begin
      Build_Schema (Result, Sources, Inputs, Warnings);
      for I in 1 .. N_Inputs loop
         if SData.Transient_Table.Row_Count (Inputs (I).all) > Max_Rows then
            Max_Rows := SData.Transient_Table.Row_Count (Inputs (I).all);
         end if;
      end loop;
      for R in 1 .. Max_Rows loop
         Result.Add_Row;
         --  Build provenance for this row: input I contributed iff
         --  its row count covers row R.
         declare
            Contrib : Boolean_Vectors.Vector;
         begin
            for I in 1 .. N_Inputs loop
               Contrib.Append
                 (R <= SData.Transient_Table.Row_Count (Inputs (I).all));
            end loop;
            Append_Provenance (Provenance, N_Inputs, Contrib);
         end;
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

   --  ---- Combine_Match ----------------------------------------------

   function Combine_Match
     (Inputs     : Table_Vectors.Vector;
      By_Vars    : SData.Transient_Table.Name_Vectors.Vector;
      Warnings   : in out Warning_Vectors.Vector;
      Provenance : in out Provenance_Vectors.Vector)
      return SData.Transient_Table.Table
   is
      Result   : SData.Transient_Table.Table;
      Sources  : Source_Vectors.Vector;
      N_Inputs : constant Positive := Positive (Inputs.Length);
      Cursors  : Cursor_Array (1 .. N_Inputs) := (others => 1);

      --  Returns True when Name (case-insensitive) is one of the BY vars.
      function Is_By_Var (Name : String) return Boolean is
         Up : constant String := To_Upper (Name);
      begin
         for B of By_Vars loop
            if To_Upper (To_String (B)) = Up then
               return True;
            end if;
         end loop;
         return False;
      end Is_By_Var;

   begin
      --  Build schema via a temporary Warnings vector so we can filter out
      --  spurious collision warnings for BY-key columns (shared by all inputs
      --  by definition) before passing the real caller Warnings vector.
      declare
         Schema_Warnings : Warning_Vectors.Vector;
      begin
         Build_Schema (Result, Sources, Inputs, Schema_Warnings);
         Forward_Schema_Warnings (By_Vars, Schema_Warnings, Warnings);
      end;
      loop
         declare
            Min_Idx : Positive;
         begin
            exit when not Find_Min_Key (By_Vars, Inputs, Cursors, Min_Idx);
            declare
               Group_Start  : Cursor_Array (1 .. N_Inputs);
               Group_Size   : Cursor_Array (1 .. N_Inputs);
               Max_Size     : Natural := 0;
               Multi_Count  : Natural := 0;
               Group_Key_T  : constant Table_Access := Inputs (Min_Idx);
               Group_Key_R  : constant Positive := Cursors (Min_Idx);
            begin
               Consume_Group (Cursors, Inputs, By_Vars, Min_Idx,
                              Group_Start, Group_Size);
               for I in Group_Size'Range loop
                  if Group_Size (I) > Max_Size then
                     Max_Size := Group_Size (I);
                  end if;
                  if Group_Size (I) > 1 then
                     Multi_Count := Multi_Count + 1;
                  end if;
               end loop;
               if Multi_Count >= 2 then
                  Warnings.Append
                    (To_Unbounded_String
                       ("N:M overlap in match merge at BY group with key=("
                          & By_Group_Key_String (By_Vars, Group_Key_T,
                                                 Group_Key_R)
                          & ")"));
               end if;
               for R_Off in 0 .. Max_Size - 1 loop
                  Result.Add_Row;
                  declare
                     R_Out : constant Positive :=
                                SData.Transient_Table.Row_Count (Result);
                  begin
                     --  Provenance: input I contributed iff it has at least
                     --  one row in this BY group (Group_Size(I) > 0).
                     declare
                        Contrib : Boolean_Vectors.Vector;
                     begin
                        for I in 1 .. N_Inputs loop
                           Contrib.Append (Group_Size (I) > 0);
                        end loop;
                        Append_Provenance (Provenance, N_Inputs, Contrib);
                     end;
                     for C in 1 .. Natural (Sources.Length) loop
                        declare
                           Src  : constant Col_Source := Sources (C);
                           T    : constant Table_Access := Inputs (Src.Table_Idx);
                           GS   : constant Natural := Group_Size (Src.Table_Idx);
                           Vv   : SData_Core.Values.Value;
                           R_In : Natural;
                        begin
                           if GS = 0 then
                              --  Owning input has no rows for this BY key.
                              --  For BY-var columns the key value is still
                              --  present in whichever input drove the group;
                              --  preserve it rather than emitting missing.
                              if Is_By_Var (To_String (Src.Col_Name)) then
                                 declare
                                    By_Source : Natural := 0;
                                    By_T      : Table_Access;
                                 begin
                                    for I in Group_Size'Range loop
                                       if Group_Size (I) > 0 then
                                          By_Source := I;
                                          exit;
                                       end if;
                                    end loop;
                                    if By_Source /= 0 then
                                       By_T := Inputs (By_Source);
                                       Vv   := By_T.Get_Value
                                               (Group_Start (By_Source),
                                                To_String (Src.Col_Name));
                                    else
                                       Vv := (Kind =>
                                                SData_Core.Values.Val_Missing);
                                    end if;
                                 end;
                              else
                                 Vv := (Kind => SData_Core.Values.Val_Missing);
                              end if;
                           else
                              if R_Off < GS then
                                 R_In := Group_Start (Src.Table_Idx) + R_Off;
                              else
                                 R_In := Group_Start (Src.Table_Idx) + GS - 1;
                              end if;
                              Vv := T.Get_Value (R_In, To_String (Src.Col_Name));
                           end if;
                           Result.Set_Value
                             (R_Out,
                              SData.Transient_Table.Column_Name (Result, C),
                              Vv);
                        end;
                     end loop;
                  end;
               end loop;
            end;
         end;
      end loop;
      return Result;
   end Combine_Match;

   --  ---- Combine_Interleave -----------------------------------------
   --  Streaming sort-merge of BY-sorted inputs. At each step, emit ONE
   --  row from the input with the smallest current BY key (leftmost wins
   --  on ties). Result columns that exist in the contributing input use
   --  its value; columns from other inputs are set to missing.
   --  Row count = sum of all input row counts.

   function Combine_Interleave
     (Inputs     : Table_Vectors.Vector;
      By_Vars    : SData.Transient_Table.Name_Vectors.Vector;
      Warnings   : in out Warning_Vectors.Vector;
      Provenance : in out Provenance_Vectors.Vector)
      return SData.Transient_Table.Table
   is
      Result   : SData.Transient_Table.Table;
      Sources  : Source_Vectors.Vector;
      N_Inputs : constant Positive := Positive (Inputs.Length);
      Cursors  : Cursor_Array (1 .. N_Inputs) := (others => 1);
   begin
      --  Build schema, suppressing BY-var collision warnings.
      declare
         Schema_Warnings : Warning_Vectors.Vector;
      begin
         Build_Schema (Result, Sources, Inputs, Schema_Warnings);
         Forward_Schema_Warnings (By_Vars, Schema_Warnings, Warnings);
      end;

      loop
         declare
            Min_Idx : Positive;
         begin
            exit when not Find_Min_Key (By_Vars, Inputs, Cursors, Min_Idx);
            Result.Add_Row;
            declare
               R_Out : constant Positive :=
                          SData.Transient_Table.Row_Count (Result);
               T_Src : constant Table_Access := Inputs (Min_Idx);
               R_In  : constant Positive := Cursors (Min_Idx);
            begin
               --  Provenance: only Min_Idx contributed this row; all others
               --  are missing.
               declare
                  Contrib : Boolean_Vectors.Vector;
               begin
                  for I in 1 .. N_Inputs loop
                     Contrib.Append (I = Min_Idx);
                  end loop;
                  Append_Provenance (Provenance, N_Inputs, Contrib);
               end;
               for C in 1 .. Natural (Sources.Length) loop
                  declare
                     Col_Name : constant String :=
                        SData.Transient_Table.Column_Name (Result, C);
                     V : SData_Core.Values.Value;
                  begin
                     if SData.Transient_Table.Has_Column
                          (T_Src.all, Col_Name)
                     then
                        V := T_Src.Get_Value (R_In, Col_Name);
                     else
                        V := (Kind => SData_Core.Values.Val_Missing);
                     end if;
                     Result.Set_Value (R_Out, Col_Name, V);
                  end;
               end loop;
            end;
            Cursors (Min_Idx) := Cursors (Min_Idx) + 1;
         end;
      end loop;
      return Result;
   end Combine_Interleave;

   --  ---- Combine_Join -----------------------------------------------
   --  Cartesian inner join by BY-key.  For each BY-key present in every
   --  input (intersection), emit N1 × N2 × ... × Nk rows covering all
   --  combinations of the per-input groups.  BY-key groups absent from
   --  any single input are silently dropped (inner-join semantics).
   --  If the product exceeds OPTIONS JOIN_WARN_THRESHOLD (and threshold
   --  > 0) one warning is emitted per offending BY-group.

   function Combine_Join
     (Inputs     : Table_Vectors.Vector;
      By_Vars    : SData.Transient_Table.Name_Vectors.Vector;
      Warnings   : in out Warning_Vectors.Vector;
      Provenance : in out Provenance_Vectors.Vector)
      return SData.Transient_Table.Table
   is
      Result    : SData.Transient_Table.Table;
      Sources   : Source_Vectors.Vector;
      N_Inputs  : constant Positive := Positive (Inputs.Length);
      Cursors   : Cursor_Array (1 .. N_Inputs) := (others => 1);
      Threshold : constant Natural :=
                     SData_Core.Config.Runtime.Options_Join_Warn_Threshold;
   begin
      --  Build schema, suppressing BY-var collision warnings.
      declare
         Schema_Warnings : Warning_Vectors.Vector;
      begin
         Build_Schema (Result, Sources, Inputs, Schema_Warnings);
         Forward_Schema_Warnings (By_Vars, Schema_Warnings, Warnings);
      end;

      loop
         declare
            Min_Idx : Positive;
         begin
            exit when not Find_Min_Key (By_Vars, Inputs, Cursors, Min_Idx);
            declare
               Group_Start  : Cursor_Array (1 .. N_Inputs);
               Group_Size   : Cursor_Array (1 .. N_Inputs);
               All_Present  : Boolean := True;
               Product      : Long_Long_Integer := 1;
               Group_Key_T  : constant Table_Access := Inputs (Min_Idx);
               Group_Key_R  : constant Positive := Cursors (Min_Idx);
               Skip_Group   : Boolean := False;
            begin
               Consume_Group (Cursors, Inputs, By_Vars, Min_Idx,
                              Group_Start, Group_Size);
               for I in Group_Size'Range loop
                  if Group_Size (I) = 0 then
                     All_Present := False;
                  else
                     Product :=
                        Product * Long_Long_Integer (Group_Size (I));
                  end if;
               end loop;
               if not All_Present then
                  Skip_Group := True;
               end if;
               if not Skip_Group then
                  if Threshold > 0
                     and then Product > Long_Long_Integer (Threshold)
                  then
                     Warnings.Append
                       (To_Unbounded_String
                          ("/JOIN BY-group product ("
                             & Long_Long_Integer'Image (Product)
                             & " ) exceeds OPTIONS JOIN_WARN_THRESHOLD"
                             & " at BY-key=("
                             & By_Group_Key_String
                                 (By_Vars, Group_Key_T, Group_Key_R)
                             & ")"));
                  end if;

                  --  Cartesian product: multi-index counter, rightmost varies
                  --  fastest.  Idx(I) ranges 0 .. Group_Size(I)-1.
                  declare
                     Idx  : Cursor_Array (1 .. N_Inputs) := (others => 0);
                     Done : Boolean := False;
                  begin
                     while not Done loop
                        Result.Add_Row;
                        declare
                           R_Out : constant Positive :=
                              SData.Transient_Table.Row_Count (Result);
                        begin
                           --  Provenance: for /JOIN inner join, every input
                           --  contributed (only fully-matched groups reach here).
                           declare
                              Contrib : Boolean_Vectors.Vector;
                           begin
                              for I in 1 .. N_Inputs loop
                                 Contrib.Append (True);
                              end loop;
                              Append_Provenance (Provenance, N_Inputs, Contrib);
                           end;
                           for C in 1 .. Natural (Sources.Length) loop
                              declare
                                 Src   : constant Col_Source := Sources (C);
                                 T     : constant Table_Access :=
                                           Inputs (Src.Table_Idx);
                                 R_In  : constant Positive :=
                                           Group_Start (Src.Table_Idx)
                                           + Idx (Src.Table_Idx);
                                 V     : constant SData_Core.Values.Value :=
                                           T.Get_Value
                                             (R_In,
                                              To_String (Src.Col_Name));
                              begin
                                 Result.Set_Value
                                   (R_Out,
                                    SData.Transient_Table.Column_Name
                                      (Result, C),
                                    V);
                              end;
                           end loop;
                        end;
                        --  Increment multi-index counter
                        declare
                           Carry : Boolean := True;
                           I     : Natural := N_Inputs;
                        begin
                           while Carry and then I >= 1 loop
                              Idx (I) := Idx (I) + 1;
                              if Idx (I) >= Group_Size (I) then
                                 Idx (I) := 0;
                                 I := I - 1;
                              else
                                 Carry := False;
                              end if;
                           end loop;
                           Done := Carry;
                        end;
                     end loop;
                  end;
               end if;
            end;
         end;
      end loop;
      return Result;
   end Combine_Join;

   --  ---- Append (vertical concatenation) ----------------------------

   --  A character (Col_String) column is routed to a destination whose name
   --  ends in "$"; numeric-family columns keep their name. This is a pure
   --  function of (name, type), so the value-copy pass can recompute it
   --  instead of threading a routing table. It also makes the numeric/
   --  character split order-independent: numeric "X" -> "X", character "X"
   --  -> "X$", whichever input each came from.
   function Append_Dest_Name
     (Col_Name : String;
      Col_Type : SData_Core.Table.Column_Type) return String
   is
      use type SData_Core.Table.Column_Type;
   begin
      if Col_Type = SData_Core.Table.Col_String
         and then (Col_Name'Length = 0
                   or else Col_Name (Col_Name'Last) /= '$')
      then
         return Col_Name & "$";
      else
         return Col_Name;
      end if;
   end Append_Dest_Name;

   --  Reconcile the output type when two inputs contribute to the same
   --  destination column. Integer + Numeric promotes to Numeric; a mix of
   --  numeric-family and string (only reachable for columns that bypass the
   --  "$" naming convention) coerces to string.
   function Reconcile_Type
     (A, B : SData_Core.Table.Column_Type)
      return SData_Core.Table.Column_Type
   is
      use type SData_Core.Table.Column_Type;
   begin
      if A = B then
         return A;
      elsif A = SData_Core.Table.Col_String
         or else B = SData_Core.Table.Col_String
      then
         return SData_Core.Table.Col_String;
      else
         --  Both numeric-family, types differ -> Integer + Numeric.
         return SData_Core.Table.Col_Numeric;
      end if;
   end Reconcile_Type;

   function Combine_Append
     (Inputs     : Table_Vectors.Vector;
      Warnings   : in out Warning_Vectors.Vector;
      Provenance : in out Provenance_Vectors.Vector)
      return SData.Transient_Table.Table
   is
      pragma Unreferenced (Warnings);
      use type SData_Core.Table.Column_Type;
      use type SData_Core.Values.Value_Kind;

      type Dest_Entry is record
         Name : Unbounded_String;
         Typ  : SData_Core.Table.Column_Type;
      end record;
      package Dest_Vectors is new Ada.Containers.Vectors
        (Index_Type => Positive, Element_Type => Dest_Entry);

      Result : SData.Transient_Table.Table;
      Dests  : Dest_Vectors.Vector;

      function Find_Dest (Up : String) return Natural is
      begin
         for I in 1 .. Natural (Dests.Length) loop
            if To_Upper (To_String (Dests (I).Name)) = Up then
               return I;
            end if;
         end loop;
         return 0;
      end Find_Dest;
   begin
      --  Pass 1: build the reconciled destination schema.
      for T_Idx in 1 .. Natural (Inputs.Length) loop
         declare
            T : constant Table_Access := Inputs (T_Idx);
         begin
            for C in 1 .. SData.Transient_Table.Column_Count (T.all) loop
               declare
                  Name : constant String :=
                     SData.Transient_Table.Column_Name (T.all, C);
                  CT   : constant SData_Core.Table.Column_Type :=
                     SData.Transient_Table.Get_Column_Type (T.all, Name);
                  Dest : constant String := Append_Dest_Name (Name, CT);
                  Pos  : constant Natural := Find_Dest (To_Upper (Dest));
               begin
                  if Pos = 0 then
                     Dests.Append
                       ((Name => To_Unbounded_String (Dest), Typ => CT));
                  else
                     Dests (Pos).Typ := Reconcile_Type (Dests (Pos).Typ, CT);
                  end if;
               end;
            end loop;
         end;
      end loop;

      for D of Dests loop
         Result.Add_Column (To_String (D.Name), D.Typ);
      end loop;

      --  Pass 2: stack rows. Each output row comes from exactly one input.
      for T_Idx in 1 .. Natural (Inputs.Length) loop
         declare
            T  : constant Table_Access := Inputs (T_Idx);
            N  : constant Natural := SData.Transient_Table.Row_Count (T.all);
            NC : constant Natural := SData.Transient_Table.Column_Count (T.all);

            --  Per-source-column routing, computed once for this input rather
            --  than per cell: the destination name and whether an integer
            --  value must be promoted to numeric there are both constant
            --  across rows.
            type Route_Entry is record
               Src     : Unbounded_String;
               Dest    : Unbounded_String;
               Promote : Boolean;
            end record;
            Routes : array (1 .. NC) of Route_Entry;
         begin
            for SC in 1 .. NC loop
               declare
                  Name : constant String :=
                     SData.Transient_Table.Column_Name (T.all, SC);
                  CT   : constant SData_Core.Table.Column_Type :=
                     SData.Transient_Table.Get_Column_Type (T.all, Name);
                  Dest : constant String := Append_Dest_Name (Name, CT);
               begin
                  Routes (SC) :=
                    (Src     => To_Unbounded_String (Name),
                     Dest    => To_Unbounded_String (Dest),
                     Promote =>
                        SData.Transient_Table.Get_Column_Type (Result, Dest)
                          = SData_Core.Table.Col_Numeric);
               end;
            end loop;

            for R in 1 .. N loop
               Result.Add_Row;
               declare
                  R_Out : constant Positive :=
                     SData.Transient_Table.Row_Count (Result);
               begin
                  --  Default every cell to missing.
                  for OC in 1 .. SData.Transient_Table.Column_Count (Result)
                  loop
                     Result.Set_Value
                       (R_Out,
                        SData.Transient_Table.Column_Name (Result, OC),
                        (Kind => SData_Core.Values.Val_Missing));
                  end loop;

                  --  Route each source column of this input to its dest.
                  for SC in 1 .. NC loop
                     declare
                        Src  : constant String := To_String (Routes (SC).Src);
                        Dest : constant String := To_String (Routes (SC).Dest);
                        V    : SData_Core.Values.Value := T.Get_Value (R, Src);
                     begin
                        --  Integer -> Numeric where the dest was promoted.
                        if Routes (SC).Promote
                           and then V.Kind = SData_Core.Values.Val_Integer
                        then
                           V := (Kind    => SData_Core.Values.Val_Numeric,
                                 Num_Val => SData_Core.Values.Real (V.Int_Val));
                        end if;
                        Result.Set_Value (R_Out, Dest, V);
                     end;
                  end loop;

                  --  Provenance: exactly one bit set (this input).
                  declare
                     Mask : Row_Provenance;
                  begin
                     for J in 1 .. Natural (Inputs.Length) loop
                        Mask.Contributors.Append (J = T_Idx);
                     end loop;
                     Provenance.Append (Mask);
                  end;
               end;
            end loop;
         end;
      end loop;

      return Result;
   end Combine_Append;

end SData.Merge;
