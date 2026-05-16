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
         Put_Line ("VANDALIZE complete. " &
            Ada.Strings.Fixed.Trim (Natural'Image (SData.Table.Row_Count),
                                    Ada.Strings.Both) &
            " records processed.");
      when others => null;
   end case;
end Execute_Declarative;