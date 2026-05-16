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
         SData.Config.Runtime.Repeat_Active := False;
         SData.Config.Runtime.Repeat_Count := 0;
         declare
            File_Name  : constant String := Stmt.File_Path (1 .. Stmt.File_Len);
            Expanded   : String (1 .. Max_Path_Len);
            Exp_Len    : Natural := 0;
            Eff_DLM     : constant String :=
               (if Stmt.DLM_Len > 0
                then Dlm_To_Str (Stmt.DLM_Path (1 .. Stmt.DLM_Len))
                else SData.Config.Runtime.Options_CSVDLM
                        (1 .. SData.Config.Runtime.Options_CSVDLM_Len));
            Eff_Header  : constant Boolean :=
               (if Stmt.Header_Specified
                then Stmt.Header_Val
                else SData.Config.Runtime.Options_Header);
            Eff_Charset : constant String :=
               (if Stmt.Output_CHARSET_Len > 0
                then Stmt.Output_CHARSET_Val (1 .. Stmt.Output_CHARSET_Len)
                else SData.Config.Runtime.Options_CHARSET
                        (1 .. SData.Config.Runtime.Options_CHARSET_Len));
         begin
            if Stmt.Is_Mock then
               Exp_Len := 4; Expanded (1 .. 4) := "MOCK";
            else
               declare Full : constant String := Full_Path (File_Name, "USE");
               begin Exp_Len := Full'Length; Expanded (1 .. Exp_Len) := Full; end;
            end if;
            SData.File_IO.Open_Input (Expanded (1 .. Exp_Len),
              (if Stmt.Format_Specified then Stmt.Fmt_Override else SData.Config.Input_Format),
              Stmt.Sheet_Name (1 .. Stmt.Sheet_Name_Len),
              Eff_DLM, Eff_Header, Eff_Charset,
              Stmt.Skip_Val, Stmt.Maxrows_Val, Stmt.NSCAN_Val);
         end;
         Input_File_Columns.Clear;
         Refresh_PDV_Names;
         for I in 1 .. Column_Count loop
            Input_File_Columns.Include (Column_Name (I));
         end loop;
         Debug_Trace ("USE: opened "
                      & Stmt.File_Path (1 .. Stmt.File_Len)
                      & " ("
                      & Ada.Strings.Fixed.Trim (Natural'Image (SData.Table.Row_Count), Ada.Strings.Both)
                      & " records, "
                      & Ada.Strings.Fixed.Trim (Natural'Image (SData.Table.Column_Count), Ada.Strings.Both)
                      & " variables)", 1);
      when Stmt_SAVE =>
         if Stmt.File_Len = 0 then
            SData.Config.Runtime.Save_File_Active := False;
            SData.Config.Runtime.Save_File_Len := 0;
         else
            declare
               Full  : constant String := Full_Path (Stmt.File_Path (1 .. Stmt.File_Len), "SAVE");
               SLen  : constant Natural := Stmt.Sheet_Name_Len;
            begin
               SData.Config.Runtime.Save_File_Path (1 .. Full'Length) := Full;
               SData.Config.Runtime.Save_File_Len := Full'Length;
               SData.Config.Runtime.Save_File_Fmt := (if Stmt.Format_Specified then Stmt.Fmt_Override else SData.Config.Output_Format);
               SData.Config.Runtime.Save_Sheet_Name (1 .. SLen) := Stmt.Sheet_Name (1 .. SLen);
               SData.Config.Runtime.Save_Sheet_Name_Len := SLen;
               SData.Config.Runtime.Save_File_Active := True;
               declare
                  Eff_DLM : constant String :=
                     (if Stmt.DLM_Len > 0
                      then Dlm_To_Str (Stmt.DLM_Path (1 .. Stmt.DLM_Len))
                      else SData.Config.Runtime.Options_CSVDLM
                              (1 .. SData.Config.Runtime.Options_CSVDLM_Len));
                  EL : constant Natural := Eff_DLM'Length;
               begin
                  SData.Config.Runtime.Save_DLM (1 .. EL) := Eff_DLM;
                  SData.Config.Runtime.Save_DLM_Len := EL;
               end;
               SData.Config.Runtime.Save_Header :=
                  (if Stmt.Header_Specified
                   then Stmt.Header_Val
                   else SData.Config.Runtime.Options_Header);
               if Stmt.Output_CHARSET_Len > 0 then
                  SData.Config.Runtime.Save_Charset (1 .. Stmt.Output_CHARSET_Len) :=
                     Stmt.Output_CHARSET_Val (1 .. Stmt.Output_CHARSET_Len);
                  SData.Config.Runtime.Save_Charset_Len := Stmt.Output_CHARSET_Len;
               else
                  SData.Config.Runtime.Save_Charset :=
                     SData.Config.Runtime.Options_CHARSET;
                  SData.Config.Runtime.Save_Charset_Len :=
                     SData.Config.Runtime.Options_CHARSET_Len;
               end if;
            end;
         end if;
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
               RC : constant String := Natural'Image (SData.Table.Row_Count);
               VC : constant String := Natural'Image (SData.Table.Column_Count);
            begin
               Put_Line ("SORT complete. " &
                         RC (RC'First + 1 .. RC'Last) & " records and " &
                         VC (VC'First + 1 .. VC'Last) & " variables processed.");
            end;
            if SData.Config.Runtime.Save_File_Active then
               begin
                  SData.File_IO.Open_Output
                     (Full_Path (SData.Config.Runtime.Save_File_Path (1 .. SData.Config.Runtime.Save_File_Len), "SAVE"),
                      SData.Config.Runtime.Save_File_Fmt,
                      SData.Config.Runtime.Save_Sheet_Name (1 .. SData.Config.Runtime.Save_Sheet_Name_Len),
                      SData.Config.Runtime.Save_DLM (1 .. SData.Config.Runtime.Save_DLM_Len),
                      SData.Config.Runtime.Save_Header,
                      SData.Config.Runtime.Options_SAVEOVERWRT,
                      SData.Config.Runtime.Save_Charset
                         (1 .. SData.Config.Runtime.Save_Charset_Len));
                  if not SData.Config.Quiet_Mode then Put_Line ("Dataset saved: " & SData.Config.Runtime.Save_File_Path (1 .. SData.Config.Runtime.Save_File_Len)); end if;
               exception
                  when SData.File_IO.Save_Refused => null;
               end;
               SData.Config.Runtime.Save_File_Active := False;
            end if;
         end;
      when Stmt_BY =>
         if SData.Table.Column_Count = 0 and then not SData.Config.Runtime.Repeat_Active then
            raise Script_Error with "BY statement requires an active dataset (use USE or REPEAT first).";
         end if;
         SData.Table.Clear_By_Vars;
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
                     SData.Table.Add_By_Var (To_Upper (Curr_Var.Var.Start_Name (1 .. Curr_Var.Var.Start_Len)));
                     Idx := Idx + 1; Curr_Var := Curr_Var.Next;
                  end loop;
                  Sort (Crit);
               end;
            end if;
         end;
      when Stmt_REPEAT =>
         SData.Table.Clear;
         SData.Config.Runtime.Repeat_Active := True;
         SData.Config.Runtime.Repeat_Count := Stmt.Count;
         Input_File_Columns.Clear;
      when Stmt_SELECT_FILTER =>
         SData.AST.Free_Expression (Select_Filter_Expr);
         Select_Filter_Expr := SData.AST.Copy_Expression (Stmt.Expr);
         SData.Table.Clear_Index_Map;
      when Stmt_DIGITS =>
         SData.Config.Print_Digits := Stmt.Digits_Count;
      when Stmt_RSEED =>
         declare
            V : constant Value := Evaluate (Stmt.Seed_Expr);
            S : constant Integer :=
               (if V.Kind = Val_Integer then V.Int_Val
                else Integer (Convert_To_Float (V)));
         begin
            SData.Statistics.Set_Seed (S);
         end;
      when Stmt_NEW =>
         SData.Table.Clear;
         SData.Variables.Clear_Temporary;
         SData.Variables.Initialize_PDV;
         Clear_Active_Program;
         SData.Config.Runtime.Reset;
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
               Put_Line ("OPTIONS MAXINTAB "    & Ada.Strings.Fixed.Trim (SData.Config.Max_Table_Cells'Image, Ada.Strings.Both));
               Put_Line ("OPTIONS MAXTEMPMEM "  & Ada.Strings.Fixed.Trim (SData.Config.Max_Temp_Vars'Image, Ada.Strings.Both));
               Put_Line ("OPTIONS CSVDLM "      & Dlm_Display (SData.Config.Runtime.Options_CSVDLM (1 .. SData.Config.Runtime.Options_CSVDLM_Len)));
               Put_Line ("OPTIONS HEADER "      & Bool_Display (SData.Config.Runtime.Options_Header));
               Put_Line ("OPTIONS SAVEOVERWRT " & Bool_Display (SData.Config.Runtime.Options_SAVEOVERWRT));
               Put_Line ("OPTIONS TXTFMT "      & SData.Config.Runtime.Options_TXTFMT (1 .. SData.Config.Runtime.Options_TXTFMT_Len));
               Put_Line ("OPTIONS CHARSET "     &
                  (if SData.Config.Runtime.Options_CHARSET_Len = 0 then "AUTO"
                   else SData.Config.Runtime.Options_CHARSET (1 .. SData.Config.Runtime.Options_CHARSET_Len)));
               Put_Line ("OPTIONS IEEE_DIVIDE " & Bool_Display (SData.Config.Runtime.IEEE_Divide));
               Put_Line ("OPTIONS SHELLTIMEOUT " & Ada.Strings.Fixed.Trim (SData.Config.Runtime.Options_Shell_Timeout'Image, Ada.Strings.Both));
               Put_Line ("OPTIONS DEBUG " & Ada.Strings.Fixed.Trim (SData.Config.Debug_Level'Image, Ada.Strings.Both));
            elsif Key = "MAXINTAB" then
               SData.Config.Max_Table_Cells := Natural'Value (Val);
            elsif Key = "MAXTEMPMEM" then
               SData.Config.Max_Temp_Vars := Natural'Value (Val);
            elsif Key = "CSVDLM" then
               declare
                  DS : constant String := Dlm_To_Str (Val);
                  DL : constant Natural := Natural'Min (DS'Length, 8);
               begin
                  SData.Config.Runtime.Options_CSVDLM := (others => ' ');
                  SData.Config.Runtime.Options_CSVDLM (1 .. DL) := DS (DS'First .. DS'First + DL - 1);
                  SData.Config.Runtime.Options_CSVDLM_Len := DL;
               end;
            elsif Key = "HEADER" then
               SData.Config.Runtime.Options_Header := (Val_Upper = "YES");
            elsif Key = "SAVEOVERWRT" then
               SData.Config.Runtime.Options_SAVEOVERWRT := (Val_Upper = "YES");
            elsif Key = "TXTFMT" then
               declare
                  VL : constant Natural := Natural'Min (Val_Upper'Length, 8);
               begin
                  SData.Config.Runtime.Options_TXTFMT := (others => ' ');
                  SData.Config.Runtime.Options_TXTFMT (1 .. VL) :=
                     Val_Upper (Val_Upper'First .. Val_Upper'First + VL - 1);
                  SData.Config.Runtime.Options_TXTFMT_Len := VL;
               end;
            elsif Key = "CHARSET" then
               declare
                  VL : constant Natural := Natural'Min (Val'Length, 64);
               begin
                  SData.Config.Runtime.Options_CHARSET := (others => ' ');
                  SData.Config.Runtime.Options_CHARSET (1 .. VL) :=
                     Val (Val'First .. Val'First + VL - 1);
                  SData.Config.Runtime.Options_CHARSET_Len := VL;
               end;
            elsif Key = "IEEE_DIVIDE" then
               SData.Config.Runtime.IEEE_Divide := (Val_Upper = "YES");
            elsif Key = "SHELLTIMEOUT" then
               SData.Config.Runtime.Options_Shell_Timeout :=
                  Natural'Value (Val);
            elsif Key = "DEBUG" then
               SData.Config.Debug_Level := Natural'Value (Val);
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
            N   : constant Natural := SData.Table.Row_Count;

            function Suffix (Name : String) return Character is
            begin
               if Name'Length = 0 then return ' '; end if;
               if Name (Name'Last) = '%' then return '%'; end if;
               if Name (Name'Last) = '$' then return '$'; end if;
               return ' ';
            end Suffix;

            function Col_Type_Of (S : Character) return SData.Table.Column_Type is
            begin
               if S = '%' then return SData.Table.Col_Integer; end if;
               if S = '$' then return SData.Table.Col_String;  end if;
               return SData.Table.Col_Numeric;
            end Col_Type_Of;

         begin
            --  Validate source exists.
            if not SData.Table.Has_Column (Src) then
               raise Script_Error with
                  "VANDALIZE: source variable '" & Src & "' not found.";
            end if;

            --  Validate suffix compatibility.
            if Suffix (Src) /= Suffix (Dst) then
               raise Script_Error with
                  "VANDALIZE: source and destination name suffixes must match.";
            end if;
            if SData.Table.Has_Column (Dst) then
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
                        if not SData.Table.Has_Column (BV) then
                           raise Script_Error with
                              "VANDALIZE /BY: variable '" & BV & "' not found.";
                        end if;
                     end;
                     Curr := Curr.Next;
                  end loop;
               end;
            end if;

            --  Collect source values.
            declare
               type Value_Array is array (1 .. Natural'Max (1, N)) of SData.Values.Value;
               Src_Vals : Value_Array;
               Out_Vals : Value_Array;

               --  Group assignment (all 1 when no /BY=).
               type Group_Array is array (1 .. Natural'Max (1, N)) of Natural;
               Groups : Group_Array := (others => 1);
               pragma Unreferenced (Groups);

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
               pragma Unreferenced (T_Shuffle, T_Perturb);

            begin
               for R in 1 .. N loop
                  Src_Vals (R) := SData.Table.Get_Value_Upper (R, Src);
               end loop;

               --  Compute BY-group assignments if /BY= specified.
               if Stmt.Vand_By_Vars /= null then
                  declare
                     Saved_Count : constant Natural := SData.Table.By_Var_Count;
                     type Saved_Name_Array is
                        array (1 .. Natural'Max (1, Saved_Count)) of
                           Ada.Strings.Unbounded.Unbounded_String;
                     Saved_Names : Saved_Name_Array;
                  begin
                     for I in 1 .. Saved_Count loop
                        Saved_Names (I) :=
                           Ada.Strings.Unbounded.To_Unbounded_String
                              (SData.Table.By_Var_Name (I));
                     end loop;

                     SData.Table.Clear_By_Vars;
                     declare
                        Curr : Variable_List := Stmt.Vand_By_Vars;
                     begin
                        while Curr /= null loop
                           SData.Table.Add_By_Var
                              (To_Upper (Curr.Var.Start_Name (1 .. Curr.Var.Start_Len)));
                           Curr := Curr.Next;
                        end loop;
                     end;

                     SData.Table.Clear_By_Vars;
                     for I in 1 .. Saved_Count loop
                        SData.Table.Add_By_Var
                           (Ada.Strings.Unbounded.To_String (Saved_Names (I)));
                     end loop;
                  end;
               end if;

               --  Generate output values (MISS only for now; SHUFFLE/PERTURB in later tasks).
               for R in 1 .. N loop
                  if Src_Vals (R).Kind = SData.Values.Val_Missing then
                     Out_Vals (R) := (Kind => SData.Values.Val_Missing);
                  else
                     declare
                        U : constant Float :=
                           SData.Statistics.Uniform_RN (0.0, 1.0);
                     begin
                        if U < T_Miss then
                           Out_Vals (R) := (Kind => SData.Values.Val_Missing);
                        else
                           Out_Vals (R) := Src_Vals (R);
                        end if;
                     end;
                  end if;
               end loop;

               --  Create destination column if absent.
               if not SData.Table.Has_Column (Dst) then
                  SData.Table.Add_Column (Dst, Col_Type_Of (Suffix (Src)));
               end if;

               --  Write output values.
               for R in 1 .. N loop
                  SData.Table.Set_Value_Upper (R, Dst, Out_Vals (R));
               end loop;

               Put_Line ("VANDALIZE complete. " &
                  Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Both) &
                  " records processed.");
            end;
         end;
      when others => null;
   end case;
end Execute_Declarative;