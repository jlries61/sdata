with Ada.Text_IO;   use Ada.Text_IO;
with SData.Table;     use SData.Table;
with SData.Values;    use SData.Values;
with SData.Variables; use SData.Variables;
with SData.Evaluator; use SData.Evaluator;
with GNAT.Strings; use GNAT.Strings;
with SData.File_IO;
with SData.Config;
with SData.Parser;
with Ada.Streams.Stream_IO;

package body SData.Interpreter is

   --  Forward declarations for the internal statement dispatchers.
   procedure Execute_Statement (Stmt : Statement_Access);
   procedure Execute_List (List : Statement_Access);
   
   --  Recursion level for SUBMIT to avoid infinite loops.
   Max_Submit_Level : constant := 10;
   Submit_Level     : Natural := 0;

   function Get_Expected_Kind (Name : String) return Value_Kind is
   begin
      if Name'Length > 0 then
         if Name (Name'Last) = '$' then
            return Val_String;
         elsif Name (Name'Last) = '%' then
            return Val_Integer;
         end if;
      end if;
      return Val_Numeric;
   end Get_Expected_Kind;

   ------------------
   -- Execute_List --
   ------------------
   procedure Execute_List (List : Statement_Access) is
      Current : Statement_Access := List;
   begin
      while Current /= null loop
         Execute_Statement (Current);
         if Current.Kind = Stmt_QUIT then
            return;
         elsif Current.Kind = Stmt_END then
            exit;
         end if;
         Current := Current.Next;
      end loop;
   end Execute_List;

   -----------------------
   -- Execute_Statement --
   -----------------------
   procedure Execute_Statement (Stmt : Statement_Access) is
   begin
       if Stmt = null then return; end if;
       
       case Stmt.Kind is
            when Stmt_LET =>
               --  Handle assignment: LET VAR = EXPR
               declare
                  Var_Name_Str : constant String := Stmt.Var_Name(1 .. Stmt.Var_Len);
                  Expected     : constant Value_Kind := Get_Expected_Kind (Var_Name_Str);
                  Result       : Value := Evaluate (Stmt.Expr);
               begin
                  --  Enforce type conversion based on suffix.
                  if Result.Kind /= Val_Missing then
                     if Expected = Val_Integer and Result.Kind /= Val_Integer then
                        -- Truncate float to integer.
                        Result := (Kind => Val_Integer, Int_Val => Integer (Float'Truncation (Result.Num_Val)));
                     elsif Expected = Val_Numeric and Result.Kind = Val_Integer then
                        -- Promote integer to float.
                        Result := (Kind => Val_Numeric, Num_Val => Float (Result.Int_Val));
                     elsif Expected /= Result.Kind then
                        raise Type_Mismatch_Error with "Cannot assign " & Result.Kind'Image & " to " & Expected'Image;
                     end if;
                  end if;

                  --  Assignment Rule: If we are in a Data Step and the variable matches
                  --  a column name, update the table cell for the current record.
                  if Row_Count > 0 and then Get_Current_Record_Index > 0 
                    and then Has_Column (Var_Name_Str) 
                  then
                     Set_Value (Get_Current_Record_Index, Var_Name_Str, Result);
                  else
                     Set (Var_Name_Str, Result);
                  end if;
               exception
                  when Type_Mismatch_Error =>
                     Put_Line ("Error: Type mismatch for variable " & Var_Name_Str);
                  when others =>
                     Put_Line ("Error: Assignment failed for " & Var_Name_Str);
               end;
            
            when Stmt_PRINT =>
               if Stmt.Print_Args = null then
                  --  Print all columns for the current record.
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
                  --  Evaluate and print each argument in the list.
                  declare
                     Current_Arg : Expression_List := Stmt.Print_Args;
                  begin
                     while Current_Arg /= null loop
                        Put (To_String (Evaluate (Current_Arg.Expr)));
                        if Current_Arg.Next /= null then
                           Put (" "); -- space between args
                        end if;
                        Current_Arg := Current_Arg.Next;
                     end loop;
                     New_Line;
                  end;
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
                     for I in Col_Names'Range loop Put(Col_Names(I).all & " "); end loop;
                     New_Line;
                     GNAT.Strings.Free(Col_Names);
                  end if;
               end;

            when Stmt_IF =>
               if Is_True (Evaluate (Stmt.Condition)) then
                  Execute_Statement (Stmt.Then_Branch);
               elsif Stmt.Else_Branch /= null then
                  Execute_Statement (Stmt.Else_Branch);
               end if;

            when Stmt_WHILE =>
               while Is_True (Evaluate (Stmt.While_Cond)) loop
                  Execute_List (Stmt.While_Body);
               end loop;

            when Stmt_FOR =>
               declare
                  Start_Val : constant Value := Evaluate (Stmt.Start_Expr);
                  End_Val   : constant Value := Evaluate (Stmt.End_Expr);
                  Step_Val  : Value := (Kind => Val_Numeric, Num_Val => 1.0);
                  Current_I : Float;
               begin
                  if Stmt.Step_Expr /= null then
                     Step_Val := Evaluate (Stmt.Step_Expr);
                  end if;

                  if Start_Val.Kind = Val_Numeric and End_Val.Kind = Val_Numeric and Step_Val.Kind = Val_Numeric then
                     Current_I := Start_Val.Num_Val;
                     loop
                        if Step_Val.Num_Val >= 0.0 then
                           exit when Current_I > End_Val.Num_Val;
                        else
                           exit when Current_I < End_Val.Num_Val;
                        end if;

                        Set (Stmt.For_Var (1 .. Stmt.For_Var_Len), (Kind => Val_Numeric, Num_Val => Current_I));
                        Execute_List (Stmt.For_Body);
                        Current_I := Current_I + Step_Val.Num_Val;
                     end loop;
                  end if;
               end;

            when Stmt_SUBMIT =>
               if Submit_Level >= Max_Submit_Level then
                  Put_Line ("Error: Maximum SUBMIT recursion level reached.");
               else
                  Submit_Level := Submit_Level + 1;
                  declare
                     Filename : constant String := Stmt.File_Path (1 .. Stmt.File_Len);
                     File : Ada.Streams.Stream_IO.File_Type;
                     Stream : Ada.Streams.Stream_IO.Stream_Access;
                  begin
                     Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Filename);
                     Stream := Ada.Streams.Stream_IO.Stream (File);
                     declare
                        Source : String (1 .. Integer (Ada.Streams.Stream_IO.Size (File)));
                        Ctx : SData.Parser.Parser_Context;
                        Prog : Statement_Access;
                     begin
                        String'Read (Stream, Source);
                        Ada.Streams.Stream_IO.Close (File);
                        SData.Parser.Initialize (Ctx, Source);
                        Prog := SData.Parser.Parse_Program (Ctx);
                        Execute (Prog);
                     end;
                  exception
                     when others =>
                        Put_Line ("Error: Failed to SUBMIT file " & Filename);
                  end;
                  Submit_Level := Submit_Level - 1;
               end if;

            when Stmt_END | Stmt_QUIT =>
               null;

            when others =>
               null;
         end case;
   end Execute_Statement;

   -------------
   -- Execute --
   -------------
   procedure Execute (Prog : Statement_Access) is
      Current : Statement_Access := Prog;
      Data_Step_Active : Boolean := False;
   begin
      --  PASS 1: Identify Data Step.
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
      
      --  PASS 2: Execution.
      if Data_Step_Active then
         for I in 1 .. Row_Count loop
            Set_Current_Record_Index(I);
            Current := Prog;
            while Current /= null loop
               case Current.Kind is
                  when Stmt_LET | Stmt_PRINT | Stmt_NAMES | Stmt_IF | Stmt_WHILE | Stmt_FOR | Stmt_SUBMIT =>
                     Execute_Statement(Current);
                  when Stmt_END => exit;
                  when Stmt_QUIT => return;
                  when others => null;
               end case;
               Current := Current.Next;
            end loop;
         end loop;
      else
         Execute_List (Prog);
      end if;

      --  PASS 3: Finalize.
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
