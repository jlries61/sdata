--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Execute_Metadata (Stmt : Statement_Access) is
begin
   case Stmt.Kind is
      when Stmt_KEEP | Stmt_DROP | Stmt_HOLD | Stmt_UNHOLD | Stmt_UNSET =>
         declare Curr_Var : Variable_List := Stmt.Vars;
         begin
            if Stmt.Kind = Stmt_UNSET then
               while Curr_Var /= null loop
                  SData_Core.Variables.Unset (To_Upper (Curr_Var.Var.Start_Name (1 .. Curr_Var.Var.Start_Len)));
                  Curr_Var := Curr_Var.Next;
               end loop;
            elsif Stmt.Kind = Stmt_KEEP or Stmt.Kind = Stmt_DROP then
               declare K : constant Column_Mod_Kind := (if Stmt.Kind = Stmt_KEEP then Mod_Keep else Mod_Drop);
               begin
                  while Curr_Var /= null loop
                     Expand_Range (K, Curr_Var.Var);
                     Curr_Var := Curr_Var.Next;
                  end loop;
               end;
            else
               declare
                  State : constant Boolean := (Stmt.Kind = Stmt_HOLD);
                  procedure Set_Hold_For_Range (Range_Spec : Variable_Range) is
                     Start_Name : constant String := (if Range_Spec.Start_Len in 1 .. Max_Name_Len then To_Upper (Range_Spec.Start_Name (1 .. Range_Spec.Start_Len)) else "");
                     End_Name   : constant String := (if Range_Spec.End_Len in 1 .. Max_Name_Len then To_Upper (Range_Spec.End_Name (1 .. Range_Spec.End_Len)) else "");
                     Start_Idx, End_Idx : Natural := 0;
                  begin
                     if not Range_Spec.Is_Range then
                        Set_Hold (Start_Name, State);
                     elsif Range_Spec.Is_Colon_Range then
                        declare
                           Names : constant Name_Vectors.Vector :=
                              Expand_Colon_Names (Start_Name, End_Name, Create_Missing => True);
                        begin
                           for N of Names loop Set_Hold (To_String (N), State); end loop;
                        end;
                     else
                        for I in 1 .. Column_Count loop
                           declare Name : constant String := Column_Name (I); begin
                              if Name = Start_Name then Start_Idx := I; end if;
                              if Name = End_Name   then End_Idx   := I; end if;
                           end;
                        end loop;
                        if Start_Idx > 0 and End_Idx > 0 then
                           if Start_Idx > End_Idx then
                              declare T : constant Natural := Start_Idx; begin Start_Idx := End_Idx; End_Idx := T; end;
                           end if;
                           for I in Start_Idx .. End_Idx loop Set_Hold (Column_Name (I), State); end loop;
                        end if;
                     end if;
                  end Set_Hold_For_Range;
               begin
                  if Curr_Var = null then
                     for I in 1 .. Column_Count loop
                        Set_Hold (Column_Name (I), State);
                     end loop;
                  else
                     while Curr_Var /= null loop
                        Set_Hold_For_Range (Curr_Var.Var);
                        Curr_Var := Curr_Var.Next;
                     end loop;
                  end if;
               end;
            end if;
         end;
      when Stmt_RENAME =>
         declare Curr : Rename_List := Stmt.Rename_Pairs;
         begin
            while Curr /= null loop
               Rename_Column (Curr.Old_Name (1 .. Curr.Old_Len), Curr.New_Name (1 .. Curr.New_Len));
               Curr := Curr.Next;
            end loop;
         end;
      when Stmt_ARRAY =>
         if Stmt.Arr_Name_Len = 0 then
            --  ARRAY with no name: list all defined virtual arrays.
            SData_Core.Commands.Execute_ARRAY ("", Name_Vectors.Empty_Vector);
         elsif Stmt.Arr_Vars = null then
            --  ARRAY <name>: undefine the named virtual array.
            SData_Core.Commands.Execute_ARRAY
               (Stmt.Arr_Name (1 .. Stmt.Arr_Name_Len),
                Name_Vectors.Empty_Vector);
         else
            declare
               V        : Name_Vectors.Vector;
               Curr_Var : Variable_List := Stmt.Arr_Vars;
               procedure Resolve_Range (Range_Spec : Variable_Range) is
                  Start_Name : constant String := (if Range_Spec.Start_Len in 1 .. Max_Name_Len then To_Upper (Range_Spec.Start_Name (1 .. Range_Spec.Start_Len)) else "");
                  End_Name   : constant String := (if Range_Spec.End_Len in 1 .. Max_Name_Len then To_Upper (Range_Spec.End_Name (1 .. Range_Spec.End_Len)) else "");
                  Start_Idx, End_Idx : Natural := 0;
               begin
                  if not Range_Spec.Is_Range then
                     if Has_Array (Start_Name) then
                        declare Lo, Hi : Integer;
                        begin
                           Get_Array_Bounds (Start_Name, Lo, Hi);
                           for I in Lo .. Hi loop
                              V.Append (To_Unbounded_String (Start_Name & "(" & Ada.Strings.Fixed.Trim (Integer'Image (I), Ada.Strings.Both) & ")"));
                           end loop;
                        end;
                     else
                        V.Append (To_Unbounded_String (Start_Name));
                     end if;
                  elsif Range_Spec.Is_Colon_Range then
                     declare
                        Names : constant Name_Vectors.Vector :=
                           Expand_Colon_Names (Start_Name, End_Name, Create_Missing => True);
                     begin
                        for N of Names loop V.Append (N); end loop;
                     end;
                  else
                     for I in 1 .. Column_Count loop
                        declare Name : constant String := Column_Name (I); begin
                           if Name = Start_Name then Start_Idx := I; end if;
                           if Name = End_Name   then End_Idx   := I; end if;
                        end;
                     end loop;
                     if Start_Idx > 0 and End_Idx > 0 then
                        if Start_Idx > End_Idx then
                           declare T : constant Natural := Start_Idx; begin Start_Idx := End_Idx; End_Idx := T; end;
                        end if;
                        for I in Start_Idx .. End_Idx loop V.Append (To_Unbounded_String (Column_Name (I))); end loop;
                     end if;
                  end if;
               end Resolve_Range;
            begin
               while Curr_Var /= null loop
                  Resolve_Range (Curr_Var.Var);
                  Curr_Var := Curr_Var.Next;
               end loop;
               SData_Core.Commands.Execute_ARRAY
                  (Stmt.Arr_Name (1 .. Stmt.Arr_Name_Len), V);
            exception
               when E : others =>
                  raise Script_Error with "Error defining array " & Stmt.Arr_Name (1 .. Stmt.Arr_Name_Len) & ": " & Ada.Exceptions.Exception_Message (E);
            end;
         end if;
      when Stmt_DIM =>
         declare
            function Eval_Bound (Expr : Expression_Access; Label : String) return Integer is
               V : constant Value := Evaluate (Expr);
            begin
               if V.Kind = Val_Integer then return V.Int_Val;
               elsif V.Kind = Val_Numeric then return Integer (Float'Floor (V.Num_Val));
               elsif V.Kind = Val_String then raise Script_Error with Label & " bound must be numeric, not character";
               else raise Script_Error with Label & " bound is missing";
               end if;
            end Eval_Bound;
            Start_Idx : constant Integer := Eval_Bound (Stmt.Arr_Start_Expr, "Lower");
            End_Idx   : constant Integer := Eval_Bound (Stmt.Arr_End_Expr, "Upper");
         begin
            SData_Core.Commands.Execute_DIM
               (Stmt.Arr_Name (1 .. Stmt.Arr_Name_Len),
                Start_Idx, End_Idx, Stmt.Is_Temporary_Dim);
         exception
            when E : others =>
               raise Script_Error with "Error defining array " & Stmt.Arr_Name (1 .. Stmt.Arr_Name_Len) & ": " & Ada.Exceptions.Exception_Message (E);
         end;
      when Stmt_NAMES =>
         declare
            S_Names : constant String_List_Access := Get_Session_Names;
            N_Cols  : constant Natural := Column_Count;
         begin
            Put_Line ("Permanent Variables (Table Columns):");
            if N_Cols > 0 then
               for I in 1 .. N_Cols loop Put (Column_Name (I) & " "); end loop;
               New_Line;
            else Put_Line ("(none)"); end if;
            Put_Line ("Session Variables (SET):");
            if S_Names /= null and then S_Names'Length > 0 then
               for I in S_Names'Range loop Put (S_Names (I).all & " "); end loop;
               New_Line;
            else Put_Line ("(none)"); end if;
            if S_Names /= null then declare Old : String_List_Access := S_Names; begin GNAT.Strings.Free (Old); end; end if;
         end;
      when Stmt_LIST =>
         --  LIST always shows the program buffer.
         if Active_Program_Vec.Is_Empty then
            Put_Line ("(Empty program buffer)");
         else
            for I in Active_Program_Vec.First_Index .. Active_Program_Vec.Last_Index loop
               declare
                  S : constant String := To_String (Active_Program_Vec (I).Source);
               begin
                  Put (Ada.Strings.Fixed.Trim (I'Image, Ada.Strings.Both) & ": ");
                  Put_Line (if S = "" then "?" else S);
               end;
            end loop;
         end if;

      when Stmt_DISPLAY =>
         declare
            V    : Name_Vectors.Vector;
            Rows : constant Natural := SData_Core.Table.Logical_Row_Count;
         begin
            if Stmt.Vars = null then
               for I in 1 .. Column_Count loop
                  V.Append (To_Unbounded_String (Column_Name (I)));
               end loop;
            else
               declare
                  Curr : Variable_List := Stmt.Vars;
                  procedure Resolve (R : Variable_Range) is
                     U_Start : constant String := To_Upper (R.Start_Name (1 .. R.Start_Len));
                     U_End   : constant String := (if R.Is_Range then To_Upper (R.End_Name (1 .. R.End_Len)) else "");
                     S_Idx, E_Idx : Natural := 0;
                  begin
                     if not R.Is_Range then
                        V.Append (To_Unbounded_String (U_Start));
                     elsif R.Is_Colon_Range then
                        declare
                           Names : constant Name_Vectors.Vector :=
                              Expand_Colon_Names (U_Start, U_End, Create_Missing => False);
                        begin
                           for N of Names loop V.Append (N); end loop;
                        end;
                     else
                        for I in 1 .. Column_Count loop
                           declare Name : constant String := Column_Name (I); begin
                              if Name = U_Start then S_Idx := I; end if;
                              if Name = U_End   then E_Idx := I; end if;
                           end;
                        end loop;
                        if S_Idx > 0 and E_Idx > 0 then
                           if S_Idx > E_Idx then
                              declare T : constant Natural := S_Idx; begin S_Idx := E_Idx; E_Idx := T; end;
                           end if;
                           for I in S_Idx .. E_Idx loop
                              V.Append (To_Unbounded_String (Column_Name (I)));
                           end loop;
                        end if;
                     end if;
                  end Resolve;
               begin
                  while Curr /= null loop
                     Resolve (Curr.Var);
                     Curr := Curr.Next;
                  end loop;
               end;
            end if;

            if V.Is_Empty then
               Put_Line ("(No columns to display)");
               return;
            end if;

            Put ("REC# ");
            for Name of V loop Put (To_String (Name) & " "); end loop;
            New_Line;

            for R in 1 .. Rows loop
               declare
                  Phys_R : constant Positive := SData_Core.Table.Logical_To_Physical (R);
               begin
                  Put (Ada.Strings.Fixed.Trim (R'Image, Ada.Strings.Both) & " ");
                  for Name of V loop
                     Put (To_String_Formatted (Get_Value_Upper (Phys_R, To_String (Name))) & " ");
                  end loop;
                  New_Line;
               end;
            end loop;
         end;
      when others => null;
   end case;
end Execute_Metadata;