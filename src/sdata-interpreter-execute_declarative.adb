--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Execute_Declarative (Stmt : Statement_Access) is

   --  Convert a DLM string (e.g. "," "\t" "TAB" "|") to a single Character.
   function Dlm_To_Str (S : String) return String is
      U : constant String := To_Upper (S);
   begin
      if U'Length = 0                then return ","; end if;
      if U = "\T" or else U = "TAB" then return "" & ASCII.HT; end if;
      if U = "NEWLINE"              then return "" & ASCII.LF; end if;
      if U = "PIPE"                 then return "|"; end if;
      if U = "SPACE"                then return " "; end if;
      if U = "COMMA"                then return ","; end if;
      return S;
   end Dlm_To_Str;

begin
   case Stmt.Kind is
      when Stmt_USE =>
         --  Helper: convert an AST Variable_List linked list to a
         --  Transient_Table Name_Vectors.Vector of unbounded strings.
         declare
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

         begin
            if Stmt.Mode = MM_Single then
               --  -------------------------------------------------------
               --  Legacy single-dataset path — no behavioral change.
               --  -------------------------------------------------------
               declare
                  File_Name : constant String :=
                     (if Stmt.Is_Mock then "MOCK"
                      else Stmt.File_Path (1 .. Stmt.File_Len));
                  Eff_DLM   : constant String :=
                     (if Stmt.DLM_Len > 0
                      then Dlm_To_Str (Stmt.DLM_Path (1 .. Stmt.DLM_Len))
                      else SData_Core.Config.Runtime.Options_CSVDLM
                              (1 .. SData_Core.Config.Runtime.Options_CSVDLM_Len));
                  Eff_Header  : constant Boolean :=
                     (if Stmt.Header_Specified
                      then Stmt.Header_Val
                      else SData_Core.Config.Runtime.Options_Header);
                  Eff_Charset : constant String :=
                     (if Stmt.Output_CHARSET_Len > 0
                      then Stmt.Output_CHARSET_Val (1 .. Stmt.Output_CHARSET_Len)
                      else SData_Core.Config.Runtime.Options_CHARSET
                              (1 .. SData_Core.Config.Runtime.Options_CHARSET_Len));
                  Eff_Fmt : constant SData_Core.Config.Format_Type :=
                     (if Stmt.Format_Specified then Stmt.Fmt_Override
                      else SData_Core.Config.Input_Format);
               begin
                  SData_Core.Commands.Execute_USE
                    (File_Name   => File_Name,
                     Fmt         => Eff_Fmt,
                     Sheet_Name  => Stmt.Sheet_Name (1 .. Stmt.Sheet_Name_Len),
                     Delimiter   => Eff_DLM,
                     Read_Header => Eff_Header,
                     Charset     => Eff_Charset,
                     Skip_Rows   => Stmt.Skip_Val,
                     Max_Rows    => Stmt.Maxrows_Val,
                     Nscan_Rows  => Stmt.NSCAN_Val,
                     Is_Mock     => Stmt.Is_Mock);
               end;
               --  Cache column names from the file so future bookkeeping can
               --  tell the difference between original and derived columns.
               Input_File_Columns.Clear;
               for I in 1 .. Column_Count loop
                  Input_File_Columns.Include (Column_Name (I));
               end loop;
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
            else
               --  -------------------------------------------------------
               --  Multi-dataset path: snapshot each input, apply per-
               --  dataset RENAME/KEEP/DROP, sort by BY vars if needed,
               --  then combine and install.
               --  -------------------------------------------------------
               declare
                  procedure Free_Snap is new Ada.Unchecked_Deallocation
                    (SData.Transient_Table.Table,
                     SData.Merge.Table_Access);

                  Snapshots : SData.Merge.Table_Vectors.Vector;
                  Warnings  : SData.Merge.Warning_Vectors.Vector;
                  Combined  : SData.Transient_Table.Table;
                  By_Names  : SData.Transient_Table.Name_Vectors.Vector;
               begin
                  --  Convert statement-level BY vars once (Match/Interleave/
                  --  Join modes only).
                  if Stmt.Mode = MM_Match
                     or else Stmt.Mode = MM_Interleave
                     or else Stmt.Mode = MM_Join
                  then
                     Convert_Variable_List (Stmt.By_Vars, By_Names);
                  end if;

                  --  Process each dataset spec.
                  for Spec_Idx in 1 .. Natural (Stmt.Dataset_List.Length) loop
                     declare
                        Spec     : constant Dataset_Spec_Access :=
                                      Stmt.Dataset_List (Spec_Idx);
                        Snap_Ptr : SData.Merge.Table_Access :=
                                      new SData.Transient_Table.Table;
                        Eff_DLM  : constant String :=
                           (if Spec.Opts.DLM_Len > 0
                            then Dlm_To_Str
                                   (Spec.Opts.DLM_Val
                                       (1 .. Spec.Opts.DLM_Len))
                            else SData_Core.Config.Runtime.Options_CSVDLM
                                    (1 .. SData_Core.Config.Runtime
                                             .Options_CSVDLM_Len));
                        Eff_Header : constant Boolean :=
                           (if Spec.Opts.Header_Specified
                            then Spec.Opts.Header_Val
                            else SData_Core.Config.Runtime.Options_Header);
                        Eff_Charset : constant String :=
                           (if Spec.Opts.Charset_Len > 0
                            then Spec.Opts.Charset_Val
                                    (1 .. Spec.Opts.Charset_Len)
                            else SData_Core.Config.Runtime.Options_CHARSET
                                    (1 .. SData_Core.Config.Runtime
                                             .Options_CHARSET_Len));
                        Eff_Fmt : constant SData_Core.Config.Format_Type :=
                           (if Spec.Opts.Format_Specified
                            then Spec.Opts.Fmt_Override
                            else SData_Core.Config.Input_Format);
                     begin
                        --  Load file into the global table.
                        SData_Core.Commands.Execute_USE
                          (File_Name   =>
                              (if Spec.Is_Mock then "MOCK"
                               else Spec.File_Path (1 .. Spec.File_Len)),
                           Fmt         => Eff_Fmt,
                           Sheet_Name  => Spec.Opts.Sheet_Name
                                            (1 .. Spec.Opts.Sheet_Name_Len),
                           Delimiter   => Eff_DLM,
                           Read_Header => Eff_Header,
                           Charset     => Eff_Charset,
                           Skip_Rows   => Spec.Opts.Skip_Val,
                           Max_Rows    => Spec.Opts.Maxrows_Val,
                           Nscan_Rows  => Spec.Opts.NSCAN_Val,
                           Is_Mock     => Spec.Is_Mock);

                        --  Snapshot the global table into a transient copy.
                        Snap_Ptr.all :=
                           SData.Transient_Table.Snapshot_From_Current;

                        --  Apply per-dataset RENAME / KEEP / DROP.
                        if Spec.Opts.Keep_Vars /= null
                           and then Spec.Opts.Drop_Vars /= null
                        then
                           Free_Snap (Snap_Ptr);
                           for P of Snapshots loop
                              declare
                                 Tmp : SData.Merge.Table_Access := P;
                              begin
                                 Free_Snap (Tmp);
                              end;
                           end loop;
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
                                 Free_Snap (Snap_Ptr);
                                 for P of Snapshots loop
                                    declare
                                       Tmp : SData.Merge.Table_Access := P;
                                    begin
                                       Free_Snap (Tmp);
                                    end;
                                 end loop;
                                 raise SData_Core.Script_Error
                                   with "/BY=" & To_String (N)
                                        & " is not present in dataset "
                                        & Spec.File_Path
                                            (1 .. Spec.File_Len);
                              end if;
                           end loop;
                           Snap_Ptr.Sort_By (By_Names);
                        end if;

                        --  IN= variable registration is deferred to
                        --  Required Follow-on A (per-row provenance).
                        --  Spec.Opts.IN_Name_Len is accepted by the
                        --  parser but not yet wired here.

                        Snapshots.Append (Snap_Ptr);
                     end;
                  end loop;

                  --  Combine all snapshots into one result table.
                  case Stmt.Mode is
                     when MM_Positional =>
                        Combined := SData.Merge.Combine_Positional
                                      (Snapshots, Warnings);
                     when MM_Match =>
                        Combined := SData.Merge.Combine_Match
                                      (Snapshots, By_Names, Warnings);
                     when MM_Interleave =>
                        Combined := SData.Merge.Combine_Interleave
                                      (Snapshots, By_Names, Warnings);
                     when MM_Join =>
                        Combined := SData.Merge.Combine_Join
                                      (Snapshots, By_Names, Warnings);
                     when MM_Single =>
                        null;  --  not reached; handled by the outer if
                  end case;

                  --  Install the combined result as the active global table.
                  SData.Transient_Table.Install_To_Current (Combined);

                  --  Refresh the PDV to reflect the new merged schema.
                  SData_Core.Variables.Refresh_PDV_Names;
                  SData_Core.Variables.Register_Subscripted_Columns;

                  --  Free per-input snapshot heap allocations.
                  for P of Snapshots loop
                     declare
                        Tmp : SData.Merge.Table_Access := P;
                     begin
                        Free_Snap (Tmp);
                     end;
                  end loop;

                  --  Emit accumulated warnings to stderr.
                  for W of Warnings loop
                     SData_Core.IO.Put_Line_Error
                       ("warning: " & To_String (W));
                  end loop;

                  --  Cancel any active REPEAT state (mirrors legacy
                  --  Execute_USE behavior).
                  SData_Core.Config.Runtime.Repeat_Active := False;
                  SData_Core.Config.Runtime.Repeat_Count  := 0;

                  --  Cache merged column names for bookkeeping.
                  Input_File_Columns.Clear;
                  for I in 1 .. Column_Count loop
                     Input_File_Columns.Include (Column_Name (I));
                  end loop;

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
               end;
            end if;
         end;
      when Stmt_SAVE =>
         declare
            File_Name : constant String :=
               (if Stmt.File_Len = 0 then ""
                else Stmt.File_Path (1 .. Stmt.File_Len));
            Eff_DLM   : constant String :=
               (if Stmt.DLM_Len > 0
                then Dlm_To_Str (Stmt.DLM_Path (1 .. Stmt.DLM_Len))
                else SData_Core.Config.Runtime.Options_CSVDLM
                        (1 .. SData_Core.Config.Runtime.Options_CSVDLM_Len));
            Eff_Header : constant Boolean :=
               (if Stmt.Header_Specified
                then Stmt.Header_Val
                else SData_Core.Config.Runtime.Options_Header);
            Eff_Charset : constant String :=
               (if Stmt.Output_CHARSET_Len > 0
                then Stmt.Output_CHARSET_Val (1 .. Stmt.Output_CHARSET_Len)
                else "");
            Eff_Fmt : constant SData_Core.Config.Format_Type :=
               (if Stmt.Format_Specified then Stmt.Fmt_Override
                else SData_Core.Config.Output_Format);
         begin
            SData_Core.Commands.Execute_SAVE
              (File_Name    => File_Name,
               Fmt          => Eff_Fmt,
               Sheet_Name   => Stmt.Sheet_Name (1 .. Stmt.Sheet_Name_Len),
               Delimiter    => Eff_DLM,
               Write_Header => Eff_Header,
               Charset      => Eff_Charset);
         end;
      when Stmt_SORT =>
         declare
            Curr_Var : Variable_List := Stmt.Sort_Vars;
            Count    : Natural := 0;
            Tmp      : Variable_List := Curr_Var;
         begin
            while Tmp /= null loop Count := Count + 1; Tmp := Tmp.Next; end loop;
            if Count > 0 then
               declare
                  Crit : Sort_Criteria_Array (1 .. Count);
                  Idx  : Positive := 1;
               begin
                  while Curr_Var /= null loop
                     Crit (Idx).Name := (others => ' ');
                     Crit (Idx).Name (1 .. Curr_Var.Var.Start_Len) := To_Upper (Curr_Var.Var.Start_Name (1 .. Curr_Var.Var.Start_Len));
                     Crit (Idx).Len := Curr_Var.Var.Start_Len;
                     Crit (Idx).Dir := Ascending;
                     Idx := Idx + 1; Curr_Var := Curr_Var.Next;
                  end loop;
                  Sort (Crit);
               end;
            end if;
            declare
               RC : constant String := Natural'Image (SData_Core.Table.Row_Count);
               VC : constant String := Natural'Image (SData_Core.Table.Column_Count);
            begin
               Put_Line ("SORT complete. " &
                         RC (RC'First + 1 .. RC'Last) & " records and " &
                         VC (VC'First + 1 .. VC'Last) & " variables processed.");
            end;
            --  Flush any pending SAVE and rebuild the SELECT filter map on the
            --  freshly sorted table.  Delegating to Execute_RUN keeps the save
            --  path in sync with the one used by explicit RUN statements.
            SData_Core.Commands.Execute_RUN;
         end;
      when Stmt_BY =>
         if SData_Core.Table.Column_Count = 0 and then not SData_Core.Config.Runtime.Repeat_Active then
            raise Script_Error with "BY statement requires an active dataset (use USE or REPEAT first).";
         end if;
         SData_Core.Table.Clear_By_Vars;
         declare
            Curr_Var : Variable_List := Stmt.Sort_Vars;
            Count    : Natural := 0;
            Tmp      : Variable_List := Curr_Var;
         begin
            while Tmp /= null loop Count := Count + 1; Tmp := Tmp.Next; end loop;
            if Count > 0 then
               declare
                  Crit : Sort_Criteria_Array (1 .. Count);
                  Idx  : Positive := 1;
               begin
                  while Curr_Var /= null loop
                     Crit (Idx).Name := (others => ' ');
                     Crit (Idx).Name (1 .. Curr_Var.Var.Start_Len) := To_Upper (Curr_Var.Var.Start_Name (1 .. Curr_Var.Var.Start_Len));
                     Crit (Idx).Len := Curr_Var.Var.Start_Len;
                     Crit (Idx).Dir := Ascending;
                     SData_Core.Table.Add_By_Var (To_Upper (Curr_Var.Var.Start_Name (1 .. Curr_Var.Var.Start_Len)));
                     Idx := Idx + 1; Curr_Var := Curr_Var.Next;
                  end loop;
                  Sort (Crit);
               end;
            end if;
         end;
      when Stmt_REPEAT =>
         SData_Core.Table.Clear;
         SData_Core.Commands.Execute_REPEAT (Stmt.Count);
         Input_File_Columns.Clear;
      when Stmt_SELECT_FILTER =>
         --  Pass a deep copy of the AST expression; the runtime now owns the
         --  installed filter expression and frees it when superseded or when
         --  NEW resets state.  The AST node still owns Stmt.Expr and frees it
         --  when the program buffer is cleared.
         SData_Core.Commands.Execute_SELECT
            (SData.AST.Copy_Expression (Stmt.Expr));
      when Stmt_DIGITS =>
         SData_Core.Config.Print_Digits := Stmt.Digits_Count;
      when Stmt_RSEED =>
         declare
            V : constant Value := Evaluate (Stmt.Seed_Expr);
            S : constant Integer :=
               (if V.Kind = Val_Integer then V.Int_Val
                else Integer (Convert_To_Float (V)));
         begin
            SData_Core.Statistics.Set_Seed (S);
         end;
      when Stmt_NEW =>
         SData_Core.Table.Clear;
         SData_Core.Variables.Clear_Temporary;
         SData_Core.Variables.Initialize_PDV;
         Clear_Active_Program;
         Clear_Registered_Saves;
         SData_Core.Commands.Execute_NEW;
      when Stmt_OPTIONS =>
         declare
            Key : constant String :=
               Stmt.Options_Key (1 .. Stmt.Options_Key_Len);
            Val : constant String :=
               Stmt.Options_Val (1 .. Stmt.Options_Val_Len);
            Val_Upper : constant String := To_Upper (Val);

            function Dlm_Display (S : String) return String is
            begin
               if S'Length = 0       then return """,""";  end if;
               if S (S'First) = ','  then return """,""";  end if;
               if S (S'First) = ASCII.HT then return """\t"""; end if;
               if S (S'First) = ASCII.LF then return "NEWLINE"; end if;
               if S (S'First) = '|'  then return """|""";  end if;
               if S (S'First) = ' '  then return "SPACE";  end if;
               return """" & S & """";
            end Dlm_Display;

            function Bool_Display (B : Boolean) return String is
            begin
               return (if B then "YES" else "NO");
            end Bool_Display;

         begin
            if Key = "" then
               Put_Line ("OPTIONS MAXINTAB "    & Ada.Strings.Fixed.Trim (SData_Core.Config.Max_Table_Cells'Image, Ada.Strings.Both));
               Put_Line ("OPTIONS MAXTEMPMEM "  & Ada.Strings.Fixed.Trim (SData_Core.Config.Max_Temp_Vars'Image, Ada.Strings.Both));
               Put_Line ("OPTIONS CSVDLM "      & Dlm_Display (SData_Core.Config.Runtime.Options_CSVDLM (1 .. SData_Core.Config.Runtime.Options_CSVDLM_Len)));
               Put_Line ("OPTIONS HEADER "      & Bool_Display (SData_Core.Config.Runtime.Options_Header));
               Put_Line ("OPTIONS SAVEOVERWRT " & Bool_Display (SData_Core.Config.Runtime.Options_SAVEOVERWRT));
               Put_Line ("OPTIONS TXTFMT "      & SData_Core.Config.Runtime.Options_TXTFMT (1 .. SData_Core.Config.Runtime.Options_TXTFMT_Len));
               Put_Line ("OPTIONS CHARSET "     &
                  (if SData_Core.Config.Runtime.Options_CHARSET_Len = 0 then "AUTO"
                   else SData_Core.Config.Runtime.Options_CHARSET (1 .. SData_Core.Config.Runtime.Options_CHARSET_Len)));
               Put_Line ("OPTIONS IEEE_DIVIDE " & Bool_Display (SData_Core.Config.Runtime.IEEE_Divide));
               Put_Line ("OPTIONS SHELLTIMEOUT " & Ada.Strings.Fixed.Trim (SData_Core.Config.Runtime.Options_Shell_Timeout'Image, Ada.Strings.Both));
               Put_Line ("OPTIONS DEBUG " & Ada.Strings.Fixed.Trim (SData_Core.Config.Debug_Level'Image, Ada.Strings.Both));
            elsif Key = "MAXINTAB" then
               SData_Core.Config.Max_Table_Cells := Natural'Value (Val);
            elsif Key = "MAXTEMPMEM" then
               SData_Core.Config.Max_Temp_Vars := Natural'Value (Val);
            elsif Key = "CSVDLM" then
               SData_Core.Commands.Execute_OPTIONS_CSVDLM (Dlm_To_Str (Val));
            elsif Key = "HEADER" then
               SData_Core.Commands.Execute_OPTIONS_Header (Val_Upper = "YES");
            elsif Key = "SAVEOVERWRT" then
               SData_Core.Commands.Execute_OPTIONS_SAVEOVERWRT
                  (Val_Upper = "YES");
            elsif Key = "TXTFMT" then
               SData_Core.Commands.Execute_OPTIONS_TXTFMT (Val_Upper);
            elsif Key = "CHARSET" then
               SData_Core.Commands.Execute_OPTIONS_CHARSET (Val);
            elsif Key = "IEEE_DIVIDE" then
               SData_Core.Commands.Execute_OPTIONS_IEEE_Divide
                  (Val_Upper = "YES");
            elsif Key = "SHELLTIMEOUT" then
               SData_Core.Commands.Execute_OPTIONS_Shell_Timeout
                  (Natural'Value (Val));
            elsif Key = "DEBUG" then
               SData_Core.Config.Debug_Level := Natural'Value (Val);
            else
               Put_Line_Error ("Warning: Unknown OPTIONS key: " & Key);
            end if;
         exception
            when Constraint_Error =>
               Put_Line_Error
                  ("Error: Invalid value for OPTIONS " & Key & ": " & Val);
         end;
      when others => null;
   end case;
end Execute_Declarative;