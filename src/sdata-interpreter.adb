with Ada.Text_IO;   use Ada.Text_IO;
with SData.Table;     use SData.Table;
with SData.Values;    use SData.Values;
with SData.Variables; use SData.Variables;
with SData.Evaluator; use SData.Evaluator;
with GNAT.Strings; use GNAT.Strings;
with SData.File_IO;
with SData.Config;

package body SData.Interpreter is

   procedure Execute_Statement (Stmt : Statement_Access);
   
   -- Mock USE for testing
   procedure Mock_Load_Data is
   begin
      Clear;
      Add_Column ("ID", Col_Numeric);
      Add_Column ("NAME", Col_String);
      Add_Column ("SALARY", Col_Numeric);
      
      for I in 1 .. 3 loop
         Add_Row;
         Set_Value (I, "ID", (Kind => Val_Numeric, Num_Val => Float (I)));
         Set_Value (I, "SALARY", (Kind => Val_Numeric, Num_Val => 50000.0 + Float(I - 1) * 10000.0));
      end loop;
      
      Set_Value(1, "NAME", (Kind => Val_String, Str_Val => "Alice" & (1 .. 1019 => ' '), Str_Len => 5));
      Set_Value(2, "NAME", (Kind => Val_String, Str_Val => "Bob" & (1 .. 1021 => ' '), Str_Len => 3));
      Set_Value(3, "NAME", (Kind => Val_String, Str_Val => "Charlie" & (1 .. 1017 => ' '), Str_Len => 7));
   end Mock_Load_Data;

   procedure Execute_Statement (Stmt : Statement_Access) is
   begin
       if Stmt = null then return; end if;
       
       case Stmt.Kind is
            when Stmt_LET =>
               declare
                  Var_Name_Str : constant String := Stmt.Var_Name(1 .. Stmt.Var_Len);
                  Result : constant Value := Evaluate (Stmt.Expr);
               begin
                  if Row_Count > 0 and then Get_Current_Record_Index > 0 
                    and then Has_Column (Var_Name_Str) 
                  then
                     Set_Value (Get_Current_Record_Index, Var_Name_Str, Result);
                  else
                     Set (Var_Name_Str, Result);
                  end if;
               exception
                  when E : Type_Mismatch_Error =>
                     Put_Line ("Error: Type mismatch for variable " & Var_Name_Str);
               end;
            
            when Stmt_PRINT =>
               if Stmt.Print_Expr = null then
                  declare
                     Col_Names : GNAT.Strings.String_List_Access := Get_Column_Names;
                  begin
                     if Col_Names /= null then
                        for I in Col_Names'Range loop
                           declare
                              Name : constant String := Col_Names(I).all;
                              Val : constant Value := Get_Value(Get_Current_Record_Index, Name);
                           begin
                              Put (Name & ": " & To_String(Val) & "  ");
                           end;
                        end loop;
                        New_Line;
                        GNAT.Strings.Free(Col_Names);
                     end if;
                  end;
               else
                  Put_Line (To_String (Evaluate (Stmt.Print_Expr)));
               end if;
               
            when Stmt_USE =>
               SData.File_IO.Open_Input (Stmt.File_Path(1 .. Stmt.File_Len), SData.Config.Input_Format);
               if not SData.Config.Quiet_Mode and then Stmt.File_Path(1 .. Stmt.File_Len) /= "mock_data" 
                 and then Stmt.File_Path(1 .. Stmt.File_Len) /= "mock" then
                  Put_Line ("Dataset opened: " & Stmt.File_Path(1 .. Stmt.File_Len));
               end if;

            when Stmt_SAVE =>
               SData.File_IO.Open_Output (Stmt.File_Path(1 .. Stmt.File_Len), SData.Config.Output_Format);
               if not SData.Config.Quiet_Mode then
                  Put_Line ("Dataset saved: " & Stmt.File_Path(1 .. Stmt.File_Len));
               end if;

            when Stmt_NAMES =>
               declare
                  Col_Names : GNAT.Strings.String_List_Access := Get_Column_Names;
               begin
                  if Col_Names /= null then
                     for I in Col_Names'Range loop
                        Put(Col_Names(I).all & " ");
                     end loop;
                     New_Line;
                     GNAT.Strings.Free(Col_Names);
                  end if;
               end;

            when Stmt_END | Stmt_QUIT =>
               null;

            when others =>
               null;
         end case;
   end Execute_Statement;

   procedure Execute (Prog : Statement_Access) is
      Current : Statement_Access := Prog;
      Data_Step_Active : Boolean := False;
   begin
      -- First pass: execute declarative statements
      while Current /= null loop
         case Current.Kind is
            when Stmt_USE =>
               Execute_Statement(Current);
               Data_Step_Active := True;
            when Stmt_END | Stmt_QUIT =>
               exit;
            when others =>
               null;
         end case;
         Current := Current.Next;
      end loop;
      
      -- Second pass: execute non-declarative statements inside data step loop
      if Data_Step_Active then
         for I in 1 .. Row_Count loop
            Set_Current_Record_Index(I);
            Current := Prog;
            while Current /= null loop
               case Current.Kind is
                  when Stmt_LET | Stmt_PRINT | Stmt_NAMES =>
                     Execute_Statement(Current);
                  when Stmt_END =>
                     exit;
                  when Stmt_QUIT =>
                     return;
                  when others =>
                     null;
               end case;
               Current := Current.Next;
            end loop;
         end loop;
      else
         Current := Prog;
         while Current /= null loop
             Execute_Statement(Current);
             if Current.Kind in Stmt_END | Stmt_QUIT then
                exit;
             end if;
             Current := Current.Next;
         end loop;
      end if;

      -- Third pass: execute final declarative statements (like SAVE)
      Current := Prog;
      while Current /= null loop
         case Current.Kind is
            when Stmt_SAVE =>
               Execute_Statement(Current);
            when others =>
               null;
         end case;
         Current := Current.Next;
      end loop;
   end Execute;

end SData.Interpreter;
