--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Execute_USE (Stmt : Statement_Access) is

   --  Helper: convert an AST Variable_List linked list to a
   --  Transient_Table Name_Vectors.Vector of unbounded strings.
   procedure Convert_Variable_List
     (V    : Variable_List;
      Outv : in out SData.Transient_Table.Name_Vectors.Vector)
   is
      Cur : Variable_List := V;
   begin
      while Cur /= null loop
         Outv.Append
           (To_Unbounded_String
              (Cur.Var.Start_Name (1 .. Cur.Var.Start_Len)));
         Cur := Cur.Next;
      end loop;
   end Convert_Variable_List;

   --  Helper: convert an AST Rename_List linked list to a
   --  Transient_Table Rename_Map_Vectors.Vector.
   procedure Convert_Rename_List
     (R    : Rename_List;
      Outv : in out SData.Transient_Table.Rename_Map_Vectors.Vector)
   is
      Cur : Rename_List := R;
   begin
      while Cur /= null loop
         Outv.Append
           ((Old_Name => To_Unbounded_String
                           (Cur.Old_Name (1 .. Cur.Old_Len)),
             New_Name => To_Unbounded_String
                           (Cur.New_Name (1 .. Cur.New_Len))));
         Cur := Cur.Next;
      end loop;
   end Convert_Rename_List;

   --  Build a per-physical-row inclusion vector for a dataset
   --  spec's IF= filter (ADR-074/sdata#92). Must be called with
   --  the just-loaded raw singleton table still in place
   --  (original column names, before RENAME=/KEEP=/DROP=) --
   --  i.e. right after SData_Core.Commands.Execute_USE loads this
   --  spec's file and before Snapshot_From_Current copies it out.
   --  Check_Undefined => True: unlike SAVE's IF= (which uses
   --  False -- see ADR-062), USE's IF= has no later-statement
   --  completion window, so a variable that isn't a real column
   --  of this specific input is unconditionally an error here.
   function Build_IF_Include
     (Expr : Expression_Access)
     return SData.Transient_Table.Boolean_Vectors.Vector
   is
      Result : SData.Transient_Table.Boolean_Vectors.Vector;
   begin
      --  Rebuild the PDV from scratch against THIS spec's raw
      --  schema BEFORE checking or scanning. Execute_USE's own
      --  internal Refresh_PDV_Names is additive-only (by design,
      --  for the normal USE-then-RUN flow, where Run_One_Step's
      --  own Initialize_PDV call is what actually resets the PDV
      --  before any expression is evaluated) -- it never removes
      --  a PRIOR spec's stale names, so a later spec's own column
      --  names would otherwise be appended at new PDV slots while
      --  Load_PDV_From_Table (which walks slots 1..Column_Count)
      --  keeps writing into the earlier spec's stale slots,
      --  silently resolving this spec's column references to
      --  Missing. This must run BEFORE Check_Expr too, not just
      --  before the scan: Is_Defined/SData_Core.Variables.Defined
      --  consult the live PDV_Index, so a stale entry surviving
      --  from a prior spec (e.g. this spec's merge_c has no "X",
      --  but a prior spec's "X" is still in PDV_Index) would make
      --  Check_Undefined => True silently pass on a name that
      --  isn't actually a column of THIS input. Harmless to reset
      --  here: Initialize_PDV touches only the PDV_Names/
      --  PDV_Index/PDV_Vec mapping (not Temp_Symbols), and the
      --  next RUN calls Initialize_PDV itself regardless, so
      --  nothing downstream depends on the mapping this scan
      --  leaves behind.
      SData_Core.Variables.Initialize_PDV;
      Check_Expr (Expr, Check_Undefined => True);
      for R in 1 .. SData_Core.Table.Row_Count loop
         Load_PDV_From_Table (R);
         Result.Append (Is_True (Evaluate (Expr)));
      end loop;
      return Result;
   end Build_IF_Include;

   procedure Execute_USE_Single is
   begin
      --  -------------------------------------------------------
      --  Legacy single-dataset path — no behavioral change.
      --  -------------------------------------------------------
      declare
         File_Name : constant String :=
            (if Stmt.Is_Mock then "MOCK"
             else Stmt.File_Path (1 .. Stmt.File_Len));
         --  Resolve delimiter / header / charset against OPTIONS
         --  state in core (single authority — see ADR / Evans
         --  E1).  Format still resolves consumer-side (it falls
         --  back to Input_Format, not an OPTIONS field).
         Eff : constant SData_Core.Commands.Use_Defaults :=
            SData_Core.Commands.Resolve_Use_Defaults
              (Delimiter           =>
                  Dlm_To_Str (Stmt.DLM_Path (1 .. Stmt.DLM_Len)),
               Delimiter_Specified => Stmt.DLM_Len > 0,
               Read_Header         => Stmt.Header_Val,
               Header_Specified    => Stmt.Header_Specified,
               Charset             =>
                  Stmt.Output_CHARSET_Val
                    (1 .. Stmt.Output_CHARSET_Len),
               Charset_Specified   => Stmt.Output_CHARSET_Len > 0);
         Eff_Fmt : constant SData_Core.Config.Format_Type :=
            (if Stmt.Format_Specified then Stmt.Fmt_Override
             else SData_Core.Config.Input_Format);
      begin
         SData_Core.Commands.Execute_USE
           (File_Name   => File_Name,
            Fmt         => Eff_Fmt,
            Sheet_Name  => Stmt.Sheet_Name (1 .. Stmt.Sheet_Name_Len),
            Delimiter   => Eff.Delimiter (1 .. Eff.Delimiter_Len),
            Read_Header => Eff.Read_Header,
            Charset     => Eff.Charset (1 .. Eff.Charset_Len),
            Skip_Rows   => Stmt.Skip_Val,
            Max_Rows    => Stmt.Maxrows_Val,
            Nscan_Rows  => Stmt.NSCAN_Val,
            Missing_Tokens => Stmt.Missing_Val (1 .. Stmt.Missing_Len),
            Declared_Types => Stmt.Types_Val (1 .. Stmt.Types_Len),
            Is_Mock     => Stmt.Is_Mock);
      end;

      --  Apply per-dataset RENAME / KEEP / DROP for single-dataset
      --  USE.  The MM_Single path historically ignored these paren
      --  options; apply them here (via a snapshot of the freshly
      --  loaded table) so single-dataset USE matches the
      --  multi-dataset behavior.  Done BEFORE caching
      --  Input_File_Columns so the cache reflects the post-projection
      --  schema.
      if not Stmt.Dataset_List.Is_Empty then
         declare
            Spec : constant Dataset_Spec_Access :=
                     Stmt.Dataset_List.First_Element;
         begin
            if Spec.Opts.Keep_Vars /= null
               and then Spec.Opts.Drop_Vars /= null
            then
               raise SData_Core.Script_Error
                 with "KEEP and DROP cannot both be specified"
                      & " on the same USE dataset spec";
            end if;
            if Spec.Opts.Rename_Pairs /= null
               or else Spec.Opts.Keep_Vars /= null
               or else Spec.Opts.Drop_Vars /= null
               or else Spec.Opts.IF_Expr /= null
            then
               declare
                  Snap : SData.Transient_Table.Table :=
                           (if Spec.Opts.IF_Expr /= null
                            then SData.Transient_Table
                                   .Snapshot_From_Current
                                     (Include =>
                                        Build_IF_Include
                                          (Spec.Opts.IF_Expr))
                            else SData.Transient_Table
                                   .Snapshot_From_Current);
               begin
                  if Spec.Opts.Rename_Pairs /= null then
                     declare
                        Pairs : SData.Transient_Table
                                   .Rename_Map_Vectors.Vector;
                     begin
                        Convert_Rename_List
                          (Spec.Opts.Rename_Pairs, Pairs);
                        Snap.Apply_Rename (Pairs);
                     end;
                  end if;
                  if Spec.Opts.Keep_Vars /= null then
                     declare
                        Names : SData.Transient_Table
                                   .Name_Vectors.Vector;
                     begin
                        Convert_Variable_List
                          (Spec.Opts.Keep_Vars, Names);
                        Snap.Apply_Keep (Names);
                     end;
                  end if;
                  if Spec.Opts.Drop_Vars /= null then
                     declare
                        Names : SData.Transient_Table
                                   .Name_Vectors.Vector;
                     begin
                        Convert_Variable_List
                          (Spec.Opts.Drop_Vars, Names);
                        Snap.Apply_Drop (Names);
                     end;
                  end if;
                  SData.Transient_Table.Install_To_Current (Snap);
               end;
            end if;
         end;
      end if;

      --  Single-dataset USE: clear any IN= read-only names (and
      --  their auto-drop registration) from a prior multi-dataset
      --  USE.  No IN= columns are created here.
      Clear_Readonly_IN_Names;
      Clear_Auto_Drop_IN_Names;
      --  Cache column names from the file so future bookkeeping can
      --  tell the difference between original and derived columns.
      Input_File_Columns.Clear;
      for I in 1 .. Column_Count loop
         Input_File_Columns.Include (Column_Name (I));
      end loop;
      --  Warn for any column whose name collides with a reserved keyword.
      SData_Core.Commands.Warn_Reserved_Columns
        (SData.Reserved_Keywords.Set);
      Debug_Trace ("USE: opened "
                   & Stmt.File_Path (1 .. Stmt.File_Len)
                   & " ("
                   & Ada.Strings.Fixed.Trim
                        (Natural'Image (SData_Core.Table.Row_Count),
                         Ada.Strings.Both)
                   & " records, "
                   & Ada.Strings.Fixed.Trim
                        (Natural'Image (SData_Core.Table.Column_Count),
                         Ada.Strings.Both)
                   & " variables)", 1);
   end Execute_USE_Single;

      --  -------------------------------------------------------
      --  Multi-dataset path: snapshot each input, apply per-
      --  dataset RENAME/KEEP/DROP, sort by BY vars if needed,
      --  then combine and install.
      --  -------------------------------------------------------
   procedure Execute_USE_Multi is
         procedure Free_Snap is new Ada.Unchecked_Deallocation
           (SData.Transient_Table.Table,
            SData.Merge.Table_Access);

         Snapshots  : SData.Merge.Table_Vectors.Vector;
         Warnings   : SData.Merge.Warning_Vectors.Vector;
         Combined   : SData.Transient_Table.Table;
         By_Names   : SData.Transient_Table.Name_Vectors.Vector;
         Provenance : SData.Merge.Provenance_Vectors.Vector;

         --  Free every snapshot accumulated so far and clear the
         --  vector.  Called on both the success path and from the
         --  exception handler so that no heap allocation leaks
         --  regardless of where an exception is raised.
         procedure Free_All_Snapshots is
            Tmp : SData.Merge.Table_Access;
         begin
            for Ptr of Snapshots loop
               Tmp := Ptr;
               Free_Snap (Tmp);
            end loop;
            Snapshots.Clear;
         end Free_All_Snapshots;

   begin
         --  Alias-uniqueness check: mirror the SAVE-side pattern.
         --  Walk the dataset list before allocating any snapshots so
         --  that a duplicate alias fails fast without leaking heap.
         declare
            package U is new Ada.Containers.Indefinite_Hashed_Sets
              (Element_Type        => String,
               Hash                => Ada.Strings.Hash,
               Equivalent_Elements => "=");
            Seen_USE_Aliases : U.Set;
         begin
            for Spec_Idx in 1 .. Natural (Stmt.Dataset_List.Length) loop
               declare
                  Spec : constant Dataset_Spec_Access :=
                            Stmt.Dataset_List (Spec_Idx);
               begin
                  if Spec.Alias_Len > 0 then
                     declare
                        A : constant String :=
                           To_Upper (Spec.Alias (1 .. Spec.Alias_Len));
                     begin
                        if Seen_USE_Aliases.Contains (A) then
                           raise SData_Core.Script_Error
                             with "duplicate USE alias: "
                                  & Spec.Alias (1 .. Spec.Alias_Len);
                        end if;
                        Seen_USE_Aliases.Include (A);
                     end;
                  end if;
               end;
            end loop;
         end;

         --  Convert statement-level BY vars once (Match/Interleave/
         --  Join modes only).
         if Stmt.Mode = MM_Match
            or else Stmt.Mode = MM_Interleave
            or else Stmt.Mode = MM_Join
         then
            Convert_Variable_List (Stmt.By_Vars, By_Names);
         end if;

         --  Clear the read-only IN= name set (and its auto-drop
         --  registration) at the start of every multi-dataset USE.
         --  Single-dataset USE clears it below.
         Clear_Readonly_IN_Names;
         Clear_Auto_Drop_IN_Names;

         begin
            --  Process each dataset spec.
            for Spec_Idx in 1 .. Natural (Stmt.Dataset_List.Length) loop
               declare
                  Spec     : constant Dataset_Spec_Access :=
                                Stmt.Dataset_List (Spec_Idx);
                  Snap_Ptr : constant SData.Merge.Table_Access :=
                                new SData.Transient_Table.Table;
                  --  Resolve delimiter / header / charset against
                  --  OPTIONS state in core (single authority — see
                  --  ADR / Evans E1).  Format stays consumer-side.
                  Eff : constant SData_Core.Commands.Use_Defaults :=
                     SData_Core.Commands.Resolve_Use_Defaults
                       (Delimiter           =>
                           Dlm_To_Str
                             (Spec.Opts.DLM_Val
                                (1 .. Spec.Opts.DLM_Len)),
                        Delimiter_Specified => Spec.Opts.DLM_Len > 0,
                        Read_Header         => Spec.Opts.Header_Val,
                        Header_Specified    =>
                           Spec.Opts.Header_Specified,
                        Charset             =>
                           Spec.Opts.Charset_Val
                             (1 .. Spec.Opts.Charset_Len),
                        Charset_Specified   =>
                           Spec.Opts.Charset_Len > 0);
                  Eff_Fmt : constant SData_Core.Config.Format_Type :=
                     (if Spec.Opts.Format_Specified
                      then Spec.Opts.Fmt_Override
                      else SData_Core.Config.Input_Format);
               begin
                  --  Track the allocation immediately so the
                  --  exception handler always sees it.
                  Snapshots.Append (Snap_Ptr);

                  --  Load file into the global table.
                  SData_Core.Commands.Execute_USE
                    (File_Name   =>
                        (if Spec.Is_Mock then "MOCK"
                         else Spec.File_Path (1 .. Spec.File_Len)),
                     Fmt         => Eff_Fmt,
                     Sheet_Name  => Spec.Opts.Sheet_Name
                                      (1 .. Spec.Opts.Sheet_Name_Len),
                     Delimiter   =>
                        Eff.Delimiter (1 .. Eff.Delimiter_Len),
                     Read_Header => Eff.Read_Header,
                     Charset     =>
                        Eff.Charset (1 .. Eff.Charset_Len),
                     Skip_Rows   => Spec.Opts.Skip_Val,
                     Max_Rows    => Spec.Opts.Maxrows_Val,
                     Nscan_Rows  => Spec.Opts.NSCAN_Val,
                     Missing_Tokens =>
                        Spec.Opts.Missing_Val
                           (1 .. Spec.Opts.Missing_Len),
                     Declared_Types =>
                        Spec.Opts.Types_Val
                           (1 .. Spec.Opts.Types_Len),
                     Is_Mock     => Spec.Is_Mock);

                  --  Snapshot the global table into a transient
                  --  copy -- filtered by this spec's IF=, if any
                  --  (ADR-074/sdata#92). Build_IF_Include must run
                  --  here, while the just-loaded raw table (this
                  --  spec's original column names) is still the
                  --  active singleton -- before this copy, and
                  --  before RENAME=/KEEP=/DROP= below mutate it.
                  Snap_Ptr.all :=
                     (if Spec.Opts.IF_Expr /= null
                      then SData.Transient_Table.Snapshot_From_Current
                             (Include =>
                                Build_IF_Include (Spec.Opts.IF_Expr))
                      else SData.Transient_Table
                             .Snapshot_From_Current);

                  --  Apply per-dataset RENAME / KEEP / DROP.
                  if Spec.Opts.Keep_Vars /= null
                     and then Spec.Opts.Drop_Vars /= null
                  then
                     raise SData_Core.Script_Error
                       with "KEEP and DROP cannot both be specified"
                            & " on the same USE dataset spec";
                  end if;

                  if Spec.Opts.Rename_Pairs /= null then
                     declare
                        Pairs : SData.Transient_Table
                                   .Rename_Map_Vectors.Vector;
                     begin
                        Convert_Rename_List
                          (Spec.Opts.Rename_Pairs, Pairs);
                        Snap_Ptr.Apply_Rename (Pairs);
                     end;
                  end if;

                  if Spec.Opts.Keep_Vars /= null then
                     declare
                        Names : SData.Transient_Table
                                   .Name_Vectors.Vector;
                     begin
                        Convert_Variable_List
                          (Spec.Opts.Keep_Vars, Names);
                        Snap_Ptr.Apply_Keep (Names);
                     end;
                  end if;

                  if Spec.Opts.Drop_Vars /= null then
                     declare
                        Names : SData.Transient_Table
                                   .Name_Vectors.Vector;
                     begin
                        Convert_Variable_List
                          (Spec.Opts.Drop_Vars, Names);
                        Snap_Ptr.Apply_Drop (Names);
                     end;
                  end if;

                  --  For Match/Interleave/Join: verify BY vars are
                  --  present and sort the snapshot.
                  if Stmt.Mode = MM_Match
                     or else Stmt.Mode = MM_Interleave
                     or else Stmt.Mode = MM_Join
                  then
                     for N of By_Names loop
                        if not Snap_Ptr.Has_Column
                                  (To_String (N))
                        then
                           raise SData_Core.Script_Error
                             with "/BY=" & To_String (N)
                                  & " is not present in dataset "
                                  & Spec.File_Path
                                      (1 .. Spec.File_Len);
                        end if;
                     end loop;
                     Snap_Ptr.Sort_By (By_Names);
                  end if;

                  --  IN= provenance columns are added after the
                  --  combiner runs (see below).
               end;
            end loop;

            --  Combine all snapshots into one result table.
            case Stmt.Mode is
               when MM_Positional =>
                  Combined := SData.Merge.Combine_Positional
                                (Snapshots, Warnings, Provenance);
               when MM_Match =>
                  Combined := SData.Merge.Combine_Match
                                (Snapshots, By_Names, Warnings,
                                 Provenance);
               when MM_Interleave =>
                  Combined := SData.Merge.Combine_Interleave
                                (Snapshots, By_Names, Warnings,
                                 Provenance);
               when MM_Join =>
                  Combined := SData.Merge.Combine_Join
                                (Snapshots, By_Names, Warnings,
                                 Provenance);
               when MM_Append =>
                  Combined := SData.Merge.Combine_Append
                                (Snapshots, Warnings, Provenance);
               when MM_Single =>
                  null;  --  not reached; handled by the outer if
            end case;

            --  Materialise IN= columns as Integer columns in
            --  Combined.  For each dataset spec that carries an
            --  IN= name, add one Integer column populated 1/0
            --  row-by-row from the Provenance bitmask.
            --
            --  If the requested IN= column name already exists in
            --  Combined (collision with a real data column) we raise
            --  Script_Error rather than silently overwriting data.
            --  Duplicate IN= names across specs also raise an error.
            declare
               package IN_Name_Sets is new
                  Ada.Containers.Indefinite_Hashed_Sets
                    (Element_Type        => String,
                     Hash                => Ada.Strings.Hash,
                     Equivalent_Elements => "=");
               Seen_IN_Names : IN_Name_Sets.Set;
            begin
               for Spec_Idx in 1 .. Natural (Stmt.Dataset_List.Length)
               loop
                  declare
                     Spec : constant Dataset_Spec_Access :=
                               Stmt.Dataset_List (Spec_Idx);
                  begin
                     if Spec.Opts.IN_Name_Len > 0 then
                        declare
                           IN_Name : constant String :=
                              Spec.Opts.IN_Name
                                 (1 .. Spec.Opts.IN_Name_Len);
                           IN_Upper : constant String :=
                              To_Upper (IN_Name);
                        begin
                           --  Duplicate IN= name across specs.
                           if Seen_IN_Names.Contains (IN_Upper) then
                              raise SData_Core.Script_Error
                                with "duplicate IN= name: " & IN_Name;
                           end if;
                           Seen_IN_Names.Include (IN_Upper);

                           if Combined.Has_Column (IN_Name) then
                              raise SData_Core.Script_Error
                                with "IN= name """ & IN_Name
                                     & """ collides with an existing"
                                     & " column in the combined table";
                           end if;
                           Combined.Add_Column
                             (IN_Name, SData_Core.Table.Col_Integer);
                           for R in 1 ..
                              SData.Transient_Table.Row_Count (Combined)
                           loop
                              declare
                                 Bit : constant Boolean :=
                                    Spec_Idx <=
                                       Natural (Provenance.Length)
                                    and then
                                       Provenance (R).Contributors
                                          (Spec_Idx);
                                 Val : constant SData_Core.Values.Value
                                    := (Kind =>
                                          SData_Core.Values.Val_Integer,
                                        Int_Val =>
                                          (if Bit then 1 else 0));
                              begin
                                 Combined.Set_Value (R, IN_Name, Val);
                              end;
                           end loop;
                           --  Register as read-only so LET/SET
                           --  assignments are rejected, and schedule
                           --  automatic removal after the next RUN
                           --  (design.md: IN= is a "temporary"
                           --  provenance variable -- see
                           --  Auto_Drop_IN_Names's declaration
                           --  comment for the full mechanism).
                           Register_Readonly_IN_Name (IN_Upper);
                           Register_Auto_Drop_IN_Name (IN_Upper);
                        end;
                     end if;
                  end;
               end loop;
            end;

            --  Install the combined result as the active global table.
            SData.Transient_Table.Install_To_Current (Combined);

            --  Refresh the PDV to reflect the new merged schema.
            SData_Core.Variables.Refresh_PDV_Names;
            SData_Core.Variables.Register_Subscripted_Columns;

            --  Free per-input snapshot heap allocations.
            Free_All_Snapshots;

            --  Emit accumulated warnings to stderr.
            for W of Warnings loop
               SData_Core.IO.Put_Line_Error
                 ("warning: " & To_String (W));
            end loop;

            --  Cancel any active REPEAT state (mirrors legacy
            --  Execute_USE behavior).
            SData_Core.Config.Runtime.End_Repeat;

            --  Cache merged column names for bookkeeping.
            Input_File_Columns.Clear;
            for I in 1 .. Column_Count loop
               Input_File_Columns.Include (Column_Name (I));
            end loop;
            --  Warn for any column whose name collides with a
            --  reserved keyword.
            SData_Core.Commands.Warn_Reserved_Columns
              (SData.Reserved_Keywords.Set);

            Debug_Trace ("USE (multi): merged "
                         & Ada.Strings.Fixed.Trim
                              (Natural'Image
                                 (Natural
                                    (Stmt.Dataset_List.Length)),
                               Ada.Strings.Both)
                         & " datasets ("
                         & Ada.Strings.Fixed.Trim
                              (Natural'Image
                                 (SData_Core.Table.Row_Count),
                               Ada.Strings.Both)
                         & " records, "
                         & Ada.Strings.Fixed.Trim
                              (Natural'Image
                                 (SData_Core.Table.Column_Count),
                               Ada.Strings.Both)
                         & " variables)", 1);
         exception
            when others =>
               Free_All_Snapshots;
               raise;
         end;
   end Execute_USE_Multi;

begin
   if Stmt.Mode = MM_Single then
      Execute_USE_Single;
   else
      Execute_USE_Multi;
   end if;
   Clear_Deferred_Program;
end Execute_USE;
