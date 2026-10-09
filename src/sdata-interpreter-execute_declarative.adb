--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Execute_Declarative (Stmt : Statement_Access) is
begin
   case Stmt.Kind is
      when Stmt_USE =>
         Execute_USE (Stmt);

      when Stmt_SAVE =>
         declare
            procedure Legacy_Execute_SAVE is
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
               Eff_Decimals : constant Integer :=
                  (if Stmt.Decimals_Specified then Stmt.Decimals_Val else -1);
            begin
               SData_Core.Commands.Execute_SAVE
                 (File_Name    => File_Name,
                  Fmt          => Eff_Fmt,
                  Sheet_Name   => Stmt.Sheet_Name (1 .. Stmt.Sheet_Name_Len),
                  Delimiter    => Eff_DLM,
                  Write_Header => Eff_Header,
                  Charset      => Eff_Charset,
                  Decimals     => Eff_Decimals,
                  Missing_Token => Stmt.Missing_Val (1 .. Stmt.Missing_Len));
            end Legacy_Execute_SAVE;
         begin
            --  Empty SAVE: clear everything (both legacy and multi-target).
            --  The parser leaves Save_List empty and File_Len = 0 for bare SAVE.
            if Natural (Stmt.Save_List.Length) = 0 then
               Clear_Registered_Saves;
               SData_Core.Config.Runtime.Clear_Pending_Save;
               return;
            end if;

            --  Single-target legacy path: the parser always puts the file into
            --  Save_List (Length = 1) and also copies it into the legacy Stmt
            --  fields.  Delegate to the legacy handler so that single-target
            --  SAVE continues to work exactly as before -- UNLESS the target
            --  carries per-target paren options (RENAME/KEEP/DROP), which the
            --  legacy pending-save path ignores.  In that case fall through to
            --  the registration path below so the multi-target flush applies
            --  the options (per-record auto-flush populates the buffer when no
            --  WRITE fires).
            if Natural (Stmt.Save_List.Length) = 1
               and then Stmt.Save_List.First_Element.Opts.Rename_Pairs = null
               and then Stmt.Save_List.First_Element.Opts.Keep_Vars = null
               and then Stmt.Save_List.First_Element.Opts.Drop_Vars = null
               and then Stmt.Save_List.First_Element.Opts.IF_Expr = null
            then
               Legacy_Execute_SAVE;
               return;
            end if;

            --  Multi-target (Save_List.Length >= 2): replace prior registrations.
            Clear_Registered_Saves;

            --  Validate aliases, file paths, and KEEP+DROP exclusivity.
            declare
               package U is new Ada.Containers.Indefinite_Hashed_Sets
                 (Element_Type        => String,
                  Hash                => Ada.Strings.Hash,
                  Equivalent_Elements => "=");
               Seen_Alias : U.Set;
               Seen_File  : U.Set;
            begin
               for Spec_Idx in 1 .. Natural (Stmt.Save_List.Length) loop
                  declare
                     Spec : constant Save_Spec_Access :=
                               Stmt.Save_List (Spec_Idx);
                  begin
                     if Spec.Alias_Len > 0 then
                        declare
                           A : constant String :=
                              To_Upper (Spec.Alias (1 .. Spec.Alias_Len));
                        begin
                           if Seen_Alias.Contains (A) then
                              raise SData_Core.Script_Error
                                 with "duplicate SAVE alias: "
                                    & Spec.Alias (1 .. Spec.Alias_Len);
                           end if;
                           Seen_Alias.Include (A);
                        end;
                     end if;
                     declare
                        F : constant String :=
                           To_Upper (Spec.File_Path (1 .. Spec.File_Len));
                     begin
                        if Seen_File.Contains (F) then
                           raise SData_Core.Script_Error
                              with "duplicate SAVE file: "
                                 & Spec.File_Path (1 .. Spec.File_Len);
                        end if;
                        Seen_File.Include (F);
                     end;
                     if Spec.Opts.Keep_Vars /= null
                        and then Spec.Opts.Drop_Vars /= null
                     then
                        raise SData_Core.Script_Error
                           with "KEEP and DROP cannot both be specified on SAVE";
                     end if;
                  end;
               end loop;
            end;

            --  Register each target.
            for Spec_Idx in 1 .. Natural (Stmt.Save_List.Length) loop
               declare
                  Spec : constant Save_Spec_Access :=
                            Stmt.Save_List (Spec_Idx);
                  T    : constant Save_Target_Access := new Save_Target;
               begin
                  T.File_Path :=
                     To_Unbounded_String (Spec.File_Path (1 .. Spec.File_Len));
                  if Spec.Alias_Len > 0 then
                     T.Alias :=
                        To_Unbounded_String (Spec.Alias (1 .. Spec.Alias_Len));
                  end if;
                  T.Opts := Spec.Opts;
                  --  ADR-062/issue #76: unknown-function and arity checking
                  --  on the target's IF= expression, once at registration
                  --  time -- not on every record when Should_Write
                  --  evaluates it during WRITE's flush. Check_Undefined =>
                  --  False: a variable referenced in IF= may legitimately
                  --  be defined by a later statement, before the first
                  --  WRITE actually flushes this target, so undefined-
                  --  variable checking must not fire here (systems-designer
                  --  finding, 02-systems-designer.md). Check_Expr no-ops on
                  --  a null expression, so no guard is needed when IF= was
                  --  not specified.
                  Check_Expr (T.Opts.IF_Expr, Check_Undefined => False);
                  Registered_Saves.Append (T);
               end;
            end loop;
         end;
      when Stmt_SORT =>
         declare
            Curr_Var : Variable_List := Stmt.Sort_Vars;
            Count    : Natural := 0;
            Tmp      : Variable_List := Curr_Var;
         begin
            while Tmp /= null loop Count := Count + 1; Tmp := Tmp.Next; end loop;
            --  A SORT variable must name an existing table column; otherwise the
            --  sort silently treats every key as missing and leaves the data
            --  unordered while still reporting success (issue #50).  The common
            --  trigger is omitting the type suffix (column N%, script SORT N).
            --  Reject it loudly, mirroring SELECT's undefined-variable posture.
            --  Validated unconditionally (issue #67): this used to be skipped when
            --  Column_Count = 0 on the theory that the vars could be forward
            --  references to a later LET in the same REPEAT body, but SORT can no
            --  longer appear inside a REPEAT body at all (issue #66 rejects it
            --  outright while Repeat_Active) -- so by the time this runs, either
            --  the table already has real columns or there is no pending body to
            --  forward-reference into, and Column_Count = 0 means the name was
            --  simply never a column.
            declare
               V : Variable_List := Curr_Var;
            begin
               while V /= null loop
                  if not SData_Core.Table.Has_Column
                           (V.Var.Start_Name (1 .. V.Var.Start_Len))
                  then
                     raise Script_Error with
                       "undefined variable """
                       & V.Var.Start_Name (1 .. V.Var.Start_Len) & """";
                  end if;
                  V := V.Next;
               end loop;
            end;
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
            --  freshly sorted table.  Delegating to Execute_Commit_Step keeps
            --  the save path in sync with the one used by explicit RUN
            --  statements (which also commit the step).
            SData_Core.Commands.Execute_Commit_Step;
         end;
      when Stmt_BY =>
         if SData_Core.Table.Column_Count = 0 and then not SData_Core.Config.Runtime.Repeat_Active then
            raise Script_Error with "BY statement requires an active dataset (use USE or REPEAT first).";
         end if;
         --  sdata-core ADR-0013: BY no longer sorts the input table --
         --  it is purely declarative, establishing
         --  the BY variables that grouping consumers key on, exactly as
         --  design.md sec5.2 documents ("Blocks need not be in sorted
         --  order"; "Blocks with same value combination but not consecutive
         --  are treated as separate blocks"). Ordinary RUN group navigation
         --  (Group_Flags) already worked this way -- it was only ever wrong
         --  because of this statement's own side effect on the data it
         --  compared. AGGREGATE/STATS/TRANSPOSE/TABLES, which do need every
         --  same-key row grouped together regardless of adjacency, now get
         --  that via SData_Core.Table.Partition_By_Key (through
         --  SData_Core.Commands.Group_Boundaries), not via a pre-sorted
         --  table.
         --
         --  Inside a data step the parser leaves the BY statement in the
         --  per-record body, so it is dispatched once per record; the guard
         --  below makes the 2nd..Nth dispatch a cheap no-op instead of
         --  redundantly clearing and re-registering the same BY variables
         --  every record.
         declare
            Curr_Var : Variable_List := Stmt.Sort_Vars;
            Count    : Natural := 0;
            Tmp      : Variable_List := Curr_Var;

            function Already_Established return Boolean is
               C : Variable_List := Stmt.Sort_Vars;
            begin
               if Count = 0 or else Count /= SData_Core.Table.By_Var_Count then
                  return False;
               end if;
               for I in 1 .. Count loop
                  if To_Upper (C.Var.Start_Name (1 .. C.Var.Start_Len))
                       /= SData_Core.Table.By_Var_Name (I)
                  then
                     return False;
                  end if;
                  C := C.Next;
               end loop;
               return True;
            end Already_Established;
         begin
            while Tmp /= null loop Count := Count + 1; Tmp := Tmp.Next; end loop;
            if Count = 0 then
               --  Bare BY cancels grouping.
               SData_Core.Table.Clear_By_Vars;
            elsif not Already_Established then
               --  Every BY variable must name an existing table column.  A
               --  misspelled name (e.g. dropped type suffix) would otherwise
               --  sort on all-missing keys and establish a bogus single group,
               --  silently corrupting BY-group logic (issue #50, as for SORT).
               --  Validated unconditionally (issue #67): this used to be skipped
               --  when Column_Count = 0 on the theory that the vars could be
               --  forward references to a later LET in the same REPEAT body, but
               --  a genuine forward reference and an undefined name are provably
               --  indistinguishable in that window -- Group_Flags collapses a
               --  from-scratch REPEAT body to one implicit group regardless of
               --  which BY names were given (see ADR-051's Root Cause), so the
               --  exemption protected no observable behavior, only a footgun.
               declare
                  V : Variable_List := Curr_Var;
               begin
                  while V /= null loop
                     if not SData_Core.Table.Has_Column
                              (V.Var.Start_Name (1 .. V.Var.Start_Len))
                     then
                        raise Script_Error with
                          "undefined variable """
                          & V.Var.Start_Name (1 .. V.Var.Start_Len) & """";
                     end if;
                     V := V.Next;
                  end loop;
               end;
               SData_Core.Table.Clear_By_Vars;
               while Curr_Var /= null loop
                  SData_Core.Table.Add_By_Var
                    (To_Upper (Curr_Var.Var.Start_Name (1 .. Curr_Var.Var.Start_Len)));
                  Curr_Var := Curr_Var.Next;
               end loop;
            end if;
         end;
      when Stmt_REPEAT =>
         Clear_Deferred_Program;
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
         --  ADR-062/issue #76: unknown-function and arity checking on the
         --  seed expression, before it's evaluated -- reuses the same
         --  static analysis PRINT already gets.
         Check_Statement (Stmt, Check_Undefined => False);
         declare
            V : constant Value := Evaluate (Stmt.Seed_Expr);
            S : constant Integer :=
               (if V.Kind = Val_Integer then Integer (V.Int_Val)
                else Integer (Convert_To_Real (V)));
         begin
            SData_Core.Statistics.Set_Seed (S);
         end;
      when Stmt_NEW =>
         if Stmt.Program_Only then
            Clear_Program_Only;
         else
            SData_Core.Table.Clear;
            SData_Core.Variables.Clear_Temporary;
            SData_Core.Variables.Initialize_PDV;
            Clear_Active_Program;
            Clear_Target_Buffers;
            Clear_Registered_Saves;
            Clear_Readonly_IN_Names;
            Clear_Auto_Drop_IN_Names;
            Clear_Warned_Submit_Paths;
            SData_Core.Commands.Execute_NEW;
         end if;
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
               Put_Line ("OPTIONS JOIN_WARN_THRESHOLD " & Ada.Strings.Fixed.Trim (SData_Core.Config.Runtime.Options_Join_Warn_Threshold'Image, Ada.Strings.Both));
               Put_Line ("OPTIONS PROGRESS " & Bool_Display (SData_Core.Config.Progress));
               Put_Line ("OPTIONS WARNRESERVED " & Bool_Display (SData_Core.Config.Runtime.Options_Warn_Reserved));
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
            elsif Key = "JOIN_WARN_THRESHOLD" then
               SData_Core.Commands.Execute_OPTIONS_Join_Warn_Threshold
                  (Natural'Value (Val));
            elsif Key = "PROGRESS" then
               SData_Core.Config.Progress := (Val_Upper = "YES");
            elsif Key = "WARNRESERVED" then
               SData_Core.Commands.Execute_OPTIONS_WarnReserved (Val_Upper = "YES");
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