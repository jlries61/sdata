--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Execute_Print (Stmt : Statement_Access) is
begin
   if Stmt.Print_Args = null then
      declare
         N : constant Natural := Column_Count;
      begin
         if N > 0 then
            for I in 1 .. N loop
               declare
                  Name : constant String := Column_Name (I);
                  Val  : constant Value  := Get (Name);
               begin
                  Put (Name & ": " & To_String_Formatted (Val) & "  ");
               end;
            end loop;
            New_Line;
         end if;
      end;
   else
      declare Current_Arg : Expression_List := Stmt.Print_Args;
      begin
         while Current_Arg /= null loop
            if Current_Arg.Expr.Kind = Expr_Variable then
               declare
                  VName : constant String := To_Upper (Current_Arg.Expr.Var_Name (1 .. Current_Arg.Expr.Var_Len));
               begin
                  if Has_Array (VName) then
                     declare Start_Idx, End_Idx : Integer;
                     begin
                        Get_Array_Bounds (VName, Start_Idx, End_Idx);
                        for I in Start_Idx .. End_Idx loop
                           Put (To_String_Formatted (Get_Array_Element (VName, I)));
                           if I /= End_Idx then Put (" "); end if;
                        end loop;
                     end;
                  else
                     Put (To_String_Formatted (Evaluate (Current_Arg.Expr)));
                  end if;
               end;
            elsif Current_Arg.Expr.Kind = Expr_Array_Access
               or else Current_Arg.Expr.Kind = Expr_Function_Call
            then
               declare
                  AName    : constant String := To_Upper ((if Current_Arg.Expr.Kind = Expr_Array_Access
                                                            then Current_Arg.Expr.Arr_Name (1 .. Current_Arg.Expr.Arr_Len)
                                                            else Current_Arg.Expr.Func_Name (1 .. Current_Arg.Expr.Func_Len)));
                  Sub_List : Expression_List := (if Current_Arg.Expr.Kind = Expr_Array_Access
                                                 then Current_Arg.Expr.Arr_Idx
                                                 else Current_Arg.Expr.Arguments);
                  First_Arg : Boolean := True;
               begin
                  if Has_Array (AName) then
                     while Sub_List /= null loop
                        if not First_Arg then Put (" "); end if;
                        if Sub_List.Is_Range then
                           declare
                              Lo_Val : constant Value := Evaluate (Sub_List.Expr);
                              Hi_Val : constant Value := Evaluate (Sub_List.Expr_End);
                              Lo, Hi : Integer;
                           begin
                              if Lo_Val.Kind = Val_Integer then Lo := Integer (Lo_Val.Int_Val);
                              else Lo := Integer (Real'Floor (Convert_To_Real (Lo_Val))); end if;
                              if Hi_Val.Kind = Val_Integer then Hi := Integer (Hi_Val.Int_Val);
                              else Hi := Integer (Real'Floor (Convert_To_Real (Hi_Val))); end if;
                              for I in Lo .. Hi loop
                                 Put (To_String_Formatted (Get_Array_Element (AName, I)));
                                 if I /= Hi then Put (" "); end if;
                              end loop;
                           end;
                        else
                           declare
                              Idx_Val : constant Value := Evaluate (Sub_List.Expr);
                              Idx     : Integer;
                           begin
                              if Idx_Val.Kind = Val_Integer then Idx := Integer (Idx_Val.Int_Val);
                              else Idx := Integer (Real'Floor (Convert_To_Real (Idx_Val))); end if;
                              Put (To_String_Formatted (Get_Array_Element (AName, Idx)));
                           end;
                        end if;
                        Sub_List := Sub_List.Next;
                        First_Arg := False;
                     end loop;
                  else
                     Put (To_String_Formatted (Evaluate (Current_Arg.Expr)));
                  end if;
               end;
            else
               Put (To_String_Formatted (Evaluate (Current_Arg.Expr)));
            end if;
            if Current_Arg.Next /= null then Put (" "); end if;
            Current_Arg := Current_Arg.Next;
         end loop;
         New_Line;
      end;
   end if;
end Execute_Print;