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
      when others => null;
   end case;
end Execute_Declarative;