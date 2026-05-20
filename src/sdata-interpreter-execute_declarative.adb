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
         --  Cache column names from the file so future bookkeeping can tell
         --  the difference between original and derived columns.
         Input_File_Columns.Clear;
         for I in 1 .. Column_Count loop
            Input_File_Columns.Include (Column_Name (I));
         end loop;
         Debug_Trace ("USE: opened "
                      & Stmt.File_Path (1 .. Stmt.File_Len)
                      & " ("
                      & Ada.Strings.Fixed.Trim (Natural'Image (SData_Core.Table.Row_Count), Ada.Strings.Both)
                      & " records, "
                      & Ada.Strings.Fixed.Trim (Natural'Image (SData_Core.Table.Column_Count), Ada.Strings.Both)
                      & " variables)", 1);
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
         SData_Core.Config.Runtime.Repeat_Active := True;
         SData_Core.Config.Runtime.Repeat_Count := Stmt.Count;
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
         SData_Core.Config.Runtime.Reset;
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
               declare
                  DS : constant String := Dlm_To_Str (Val);
                  DL : constant Natural := Natural'Min (DS'Length, 8);
               begin
                  SData_Core.Config.Runtime.Options_CSVDLM := (others => ' ');
                  SData_Core.Config.Runtime.Options_CSVDLM (1 .. DL) := DS (DS'First .. DS'First + DL - 1);
                  SData_Core.Config.Runtime.Options_CSVDLM_Len := DL;
               end;
            elsif Key = "HEADER" then
               SData_Core.Config.Runtime.Options_Header := (Val_Upper = "YES");
            elsif Key = "SAVEOVERWRT" then
               SData_Core.Config.Runtime.Options_SAVEOVERWRT := (Val_Upper = "YES");
            elsif Key = "TXTFMT" then
               declare
                  VL : constant Natural := Natural'Min (Val_Upper'Length, 8);
               begin
                  SData_Core.Config.Runtime.Options_TXTFMT := (others => ' ');
                  SData_Core.Config.Runtime.Options_TXTFMT (1 .. VL) :=
                     Val_Upper (Val_Upper'First .. Val_Upper'First + VL - 1);
                  SData_Core.Config.Runtime.Options_TXTFMT_Len := VL;
               end;
            elsif Key = "CHARSET" then
               declare
                  VL : constant Natural := Natural'Min (Val'Length, 64);
               begin
                  SData_Core.Config.Runtime.Options_CHARSET := (others => ' ');
                  SData_Core.Config.Runtime.Options_CHARSET (1 .. VL) :=
                     Val (Val'First .. Val'First + VL - 1);
                  SData_Core.Config.Runtime.Options_CHARSET_Len := VL;
               end;
            elsif Key = "IEEE_DIVIDE" then
               SData_Core.Config.Runtime.IEEE_Divide := (Val_Upper = "YES");
            elsif Key = "SHELLTIMEOUT" then
               SData_Core.Config.Runtime.Options_Shell_Timeout :=
                  Natural'Value (Val);
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
      when Stmt_VANDALIZE =>
         declare
            Src : constant String :=
               To_Upper (Stmt.Vand_Source_Name (1 .. Stmt.Vand_Source_Len));
            Dst : constant String :=
               To_Upper (Stmt.Vand_Dest_Name (1 .. Stmt.Vand_Dest_Len));
            N   : constant Natural := SData_Core.Table.Row_Count;

            function Suffix (Name : String) return Character is
            begin
               if Name'Length = 0 then return ' '; end if;
               if Name (Name'Last) = '%' then return '%'; end if;
               if Name (Name'Last) = '$' then return '$'; end if;
               return ' ';
            end Suffix;

            function Col_Type_Of (S : Character) return SData_Core.Table.Column_Type is
            begin
               if S = '%' then return SData_Core.Table.Col_Integer; end if;
               if S = '$' then return SData_Core.Table.Col_String;  end if;
               return SData_Core.Table.Col_Numeric;
            end Col_Type_Of;

            --  Core logic for a single source/destination column pair.
            --  Captures N and Stmt from the enclosing scope.
            procedure Vandalize_One_Column (Src_Col, Dst_Col : String) is
               type Value_Array is array (1 .. Natural'Max (1, N)) of SData_Core.Values.Value;
               Src_Vals : Value_Array;
               Out_Vals : Value_Array;

               --  Group assignment (all 1 when no /BY=).
               type Group_Array is array (1 .. Natural'Max (1, N)) of Natural;
               Groups : Group_Array := (others => 1);

               --  Probability thresholds (fixed order: MISS, SHUFFLE, PERTURB).
               P_Miss    : constant Float :=
                  (if Stmt.Vand_Miss    then Stmt.Vand_Mprob else 0.0);
               P_Shuffle : constant Float :=
                  (if Stmt.Vand_Shuffle then Stmt.Vand_Sprob else 0.0);
               P_Perturb : constant Float :=
                  (if Stmt.Vand_Perturb then Stmt.Vand_Pprob else 0.0);
               T_Miss    : constant Float := P_Miss;
               T_Shuffle : constant Float := T_Miss    + P_Shuffle;
               T_Perturb : constant Float := T_Shuffle + P_Perturb;

               type Index_Array is array (1 .. Natural'Max (1, N)) of Positive;
               Shuffle_Src : Index_Array := (others => 1);

               --  Per-row SD of the row's BY-group (for PERTURB).
               type SD_Row_Array is array (1 .. Natural'Max (1, N)) of Float;
               pragma Warnings (Off, "* is not modified *");
               SD_For_Row : SD_Row_Array := (others => 0.0);
               pragma Warnings (On, "* is not modified *");

            begin
               for R in 1 .. N loop
                  Src_Vals (R) := SData_Core.Table.Get_Value_Upper (R, Src_Col);
               end loop;

               --  Initialize Shuffle_Src to identity (each row draws from itself).
               for R in 1 .. N loop
                  Shuffle_Src (R) := R;
               end loop;

               --  Compute BY-group assignments if /BY= specified.
               if Stmt.Vand_By_Vars /= null then
                  declare
                     Saved_Count : constant Natural := SData_Core.Table.By_Var_Count;
                     type Saved_Name_Array is
                        array (1 .. Natural'Max (1, Saved_Count)) of
                           Ada.Strings.Unbounded.Unbounded_String;
                     Saved_Names : Saved_Name_Array;
                  begin
                     for I in 1 .. Saved_Count loop
                        Saved_Names (I) :=
                           Ada.Strings.Unbounded.To_Unbounded_String
                              (SData_Core.Table.By_Var_Name (I));
                     end loop;

                     SData_Core.Table.Clear_By_Vars;
                     declare
                        Curr : Variable_List := Stmt.Vand_By_Vars;
                     begin
                        while Curr /= null loop
                           SData_Core.Table.Add_By_Var
                              (To_Upper (Curr.Var.Start_Name (1 .. Curr.Var.Start_Len)));
                           Curr := Curr.Next;
                        end loop;
                     end;

                     --  Assign consecutive group IDs using In_Same_Group.
                     --  Requires table is sorted by BY vars (same assumption as BY).
                     declare
                        Next_G : Natural := 1;
                     begin
                        Groups (1) := 1;
                        for R in 2 .. N loop
                           if SData_Core.Table.In_Same_Group (R, R - 1) then
                              Groups (R) := Groups (R - 1);
                           else
                              Next_G     := Next_G + 1;
                              Groups (R) := Next_G;
                           end if;
                        end loop;
                     end;

                     --  Restore global BY vars.
                     SData_Core.Table.Clear_By_Vars;
                     for I in 1 .. Saved_Count loop
                        SData_Core.Table.Add_By_Var
                           (Ada.Strings.Unbounded.To_String (Saved_Names (I)));
                     end loop;
                  end;
               end if;

               --  Build per-group Fisher-Yates shuffle index for SHUFFLE.
               if Stmt.Vand_Shuffle then
                  declare
                     Max_G : Natural := 1;
                  begin
                     for R in 1 .. N loop
                        if Groups (R) > Max_G then Max_G := Groups (R); end if;
                     end loop;
                     for G in 1 .. Max_G loop
                        --  Count rows in this group.
                        declare
                           G_Count : Natural := 0;
                        begin
                           for R in 1 .. N loop
                              if Groups (R) = G then G_Count := G_Count + 1; end if;
                           end loop;
                           if G_Count > 0 then
                              declare
                                 G_Rows : array (1 .. G_Count) of Positive;
                                 G_Idx  : Natural := 0;
                              begin
                                 --  Collect non-missing rows.
                                 for R in 1 .. N loop
                                    if Groups (R) = G and then
                                       Src_Vals (R).Kind /= SData_Core.Values.Val_Missing
                                    then
                                       G_Idx := G_Idx + 1;
                                       G_Rows (G_Idx) := R;
                                    end if;
                                 end loop;
                                 --  Fisher-Yates shuffle on G_Rows (G_Idx non-missing rows).
                                 for I in reverse 2 .. G_Idx loop
                                    declare
                                       J_Raw     : constant Integer :=
                                          1 + Integer (SData_Core.Statistics.Uniform_RN
                                             (0.0, 1.0) * Float (I));
                                       J         : constant Positive :=
                                          (if J_Raw < 1 then 1
                                           elsif J_Raw > I then I
                                           else J_Raw);
                                       Tmp : constant Positive := G_Rows (I);
                                    begin
                                       G_Rows (I) := G_Rows (J);
                                       G_Rows (J) := Tmp;
                                    end;
                                 end loop;
                                 --  Build Shuffle_Src mapping: Orig_Rows(i) draws from G_Rows(i).
                                 declare
                                    Orig_Rows : array (1 .. G_Count) of Positive;
                                    Idx2 : Natural := 0;
                                 begin
                                    for R in 1 .. N loop
                                       if Groups (R) = G then
                                          Idx2 := Idx2 + 1;
                                          Orig_Rows (Idx2) := R;
                                       end if;
                                    end loop;
                                    --  Map each row to its shuffled source.
                                    --  Rows with missing source get source = self (will be
                                    --  overridden in output loop by the missing check).
                                    for I in 1 .. G_Idx loop
                                       Shuffle_Src (Orig_Rows (I)) := G_Rows (I);
                                    end loop;
                                 end;
                              end;
                           end if;
                        end;
                     end loop;
                  end;
               end if;

               --  Compute per-group SD for PERTURB (two-pass per group).
               if Stmt.Vand_Perturb then
                  declare
                     Max_G : Natural := 1;
                  begin
                     for R in 1 .. N loop
                        if Groups (R) > Max_G then Max_G := Groups (R); end if;
                     end loop;
                     for G in 1 .. Max_G loop
                        declare
                           N_G    : Natural := 0;
                           Sum_G  : Float   := 0.0;
                           SumSq_G : Float  := 0.0;
                           SD_G   : Float   := 0.0;
                        begin
                           for R in 1 .. N loop
                              if Groups (R) = G and then
                                 Src_Vals (R).Kind = SData_Core.Values.Val_Numeric
                              then
                                 N_G    := N_G + 1;
                                 Sum_G  := Sum_G  + Src_Vals (R).Num_Val;
                                 SumSq_G := SumSq_G + Src_Vals (R).Num_Val ** 2;
                              end if;
                           end loop;
                           if N_G >= 2 then
                              declare
                                 Mean_G   : constant Float := Sum_G / Float (N_G);
                                 Variance : constant Float :=
                                    SumSq_G / Float (N_G) - Mean_G ** 2;
                              begin
                                 SD_G := (if Variance > 0.0 then Sqrt (Variance) else 0.0);
                              end;
                           end if;
                           for R in 1 .. N loop
                              if Groups (R) = G then
                                 SD_For_Row (R) := SD_G;
                              end if;
                           end loop;
                        end;
                     end loop;
                  end;
               end if;

               --  Generate output values.
               for R in 1 .. N loop
                  if Src_Vals (R).Kind = SData_Core.Values.Val_Missing then
                     Out_Vals (R) := (Kind => SData_Core.Values.Val_Missing);
                  else
                     declare
                        U : constant Float :=
                           SData_Core.Statistics.Uniform_RN (0.0, 1.0);
                     begin
                        if U < T_Miss then
                           Out_Vals (R) := (Kind => SData_Core.Values.Val_Missing);
                        elsif U < T_Shuffle then
                           Out_Vals (R) := Src_Vals (Shuffle_Src (R));
                        elsif U < T_Perturb then
                           Out_Vals (R) :=
                              (Kind    => SData_Core.Values.Val_Numeric,
                               Num_Val => Src_Vals (R).Num_Val
                                  + SData_Core.Statistics.Normal_RN
                                       (0.0, SD_For_Row (R) * Stmt.Vand_SD_Frac));
                        else
                           Out_Vals (R) := Src_Vals (R);
                        end if;
                     end;
                  end if;
               end loop;

               --  Create destination column if absent.
               if not SData_Core.Table.Has_Column (Dst_Col) then
                  SData_Core.Table.Add_Column (Dst_Col, Col_Type_Of (Suffix (Src_Col)));
               end if;

               --  Write output values.
               for R in 1 .. N loop
                  SData_Core.Table.Set_Value_Upper (R, Dst_Col, Out_Vals (R));
               end loop;
            end Vandalize_One_Column;

         begin
            --  Validate source exists (as a column or as an array base name).
            if not SData_Core.Variables.Has_Array (Src)
               and then not SData_Core.Table.Has_Column (Src)
            then
               raise Script_Error with
                  "VANDALIZE: source variable '" & Src & "' not found.";
            end if;

            --  Validate suffix compatibility.
            if Suffix (Src) /= Suffix (Dst) then
               raise Script_Error with
                  "VANDALIZE: source and destination name suffixes must match.";
            end if;
            if SData_Core.Table.Has_Column (Dst) then
               if Suffix (Src) /= Suffix (Dst) then
                  raise Script_Error with
                     "VANDALIZE: destination '" & Dst &
                     "' exists with incompatible type.";
               end if;
            end if;

            --  PERTURB requires float source.
            if Stmt.Vand_Perturb and then Suffix (Src) /= ' ' then
               raise Script_Error with
                  "VANDALIZE: /PERTURB requires a floating-point variable (no suffix).";
            end if;

            --  Validate probability sum.
            declare
               Total : Float := 0.0;
            begin
               if Stmt.Vand_Miss    then Total := Total + Stmt.Vand_Mprob; end if;
               if Stmt.Vand_Shuffle then Total := Total + Stmt.Vand_Sprob; end if;
               if Stmt.Vand_Perturb then Total := Total + Stmt.Vand_Pprob; end if;
               if Total > 1.0 then
                  raise Script_Error with
                     "VANDALIZE: sum of probabilities exceeds 1.0.";
               end if;
            end;

            --  Validate BY variables.
            if Stmt.Vand_By_Vars /= null then
               declare
                  Curr : Variable_List := Stmt.Vand_By_Vars;
               begin
                  while Curr /= null loop
                     declare
                        BV : constant String :=
                           To_Upper (Curr.Var.Start_Name (1 .. Curr.Var.Start_Len));
                     begin
                        if not SData_Core.Table.Has_Column (BV) then
                           raise Script_Error with
                              "VANDALIZE /BY: variable '" & BV & "' not found.";
                        end if;
                     end;
                     Curr := Curr.Next;
                  end loop;
               end;
            end if;

            --  Dispatch: array (DIM or virtual) or scalar column.
            if SData_Core.Variables.Has_Array (Src) then
               declare
                  Start_Idx, End_Idx : Integer;
               begin
                  SData_Core.Variables.Get_Array_Bounds (Src, Start_Idx, End_Idx);
                  for I in Start_Idx .. End_Idx loop
                     declare
                        I_Str   : constant String :=
                           Ada.Strings.Fixed.Trim (Integer'Image (I), Ada.Strings.Both);
                        Src_Col : constant String :=
                           SData_Core.Variables.Get_Array_Element_Column (Src, I);
                        Dst_Col : constant String := Dst & "(" & I_Str & ")";
                     begin
                        Vandalize_One_Column (Src_Col, Dst_Col);
                     end;
                  end loop;
                  --  Register destination as a DIM array so element access
                  --  expressions (e.g. COPY(1)) resolve via Has_Array.
                  if not SData_Core.Variables.Has_Array (Dst) then
                     SData_Core.Variables.Dim_Array (Dst, Start_Idx, End_Idx,
                                                Is_Temp => False);
                  end if;
               end;
            else
               Vandalize_One_Column (Src, Dst);
            end if;

            Put_Line ("VANDALIZE complete. " &
               Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Both) &
               " records processed.");
         end;
      when others => null;
   end case;
end Execute_Declarative;