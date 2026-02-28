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
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Strings.Hash;

package body SData.Interpreter is

   --  Forward declarations for internal logic.
   procedure Execute_Statement (Stmt : Statement_Access);
   procedure Execute_List (List : Statement_Access; Boundary : Statement_Access := null);
   
   Max_Submit_Level : constant := 10;
   Submit_Level     : Natural := 0;

   --  Set to track columns provided by the input file (to skip reset).
   package Name_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type => String,
      Hash         => Ada.Strings.Hash,
      Equivalent_Elements => "=");
   Input_File_Columns : Name_Sets.Set;

   --  Column modifications state.
   type Column_Mod_Kind is (Mod_Keep, Mod_Drop);
   type Column_Mod_Node;
   type Column_Mod_List is access Column_Mod_Node;
   type Column_Mod_Node is record
      Kind : Column_Mod_Kind;
      Name : String (1 .. 32);
      Len  : Natural;
      Next : Column_Mod_List;
   end record;

   Pending_Mods : Column_Mod_List := null;

   --  Global program for REPL mode.
   Active_Program_Head : Statement_Access := null;
   Active_Program_Tail : Statement_Access := null;

   procedure Add_To_Active_Program (Stmt : Statement_Access) is
   begin
      if Stmt = null then return; end if;
      Stmt.Next := null;
      if Active_Program_Head = null then
         Active_Program_Head := Stmt;
         Active_Program_Tail := Stmt;
      else
         Active_Program_Tail.Next := Stmt;
         Active_Program_Tail := Stmt;
      end if;
   end Add_To_Active_Program;

   procedure Clear_Active_Program is
   begin
      Active_Program_Head := null;
      Active_Program_Tail := null;
   end Clear_Active_Program;

   procedure Run_Active_Program is
   begin
      if Active_Program_Head /= null then
         declare
            Prog : constant Statement_Access := Active_Program_Head;
         begin
            Clear_Active_Program;
            Execute (Prog);
         end;
      end if;
   end Run_Active_Program;

   procedure Add_Pending_Mod (Kind : Column_Mod_Kind; Name : String) is
      New_Mod : constant Column_Mod_List := new Column_Mod_Node;
      Last : Column_Mod_List := Pending_Mods;
      Upper : constant String := To_Upper (Name);
   begin
      New_Mod.Kind := Kind; New_Mod.Len := Upper'Length;
      New_Mod.Name (1 .. Upper'Length) := Upper; New_Mod.Next := null;
      if Pending_Mods = null then Pending_Mods := New_Mod;
      else
         while Last.Next /= null loop Last := Last.Next; end loop;
         Last.Next := New_Mod;
      end if;
   end Add_Pending_Mod;

   procedure Apply_Pending_Mods is
      use SData.Table;
      Col_Names : GNAT.Strings.String_List_Access := Get_Column_Names;
      Current : Column_Mod_List;
      Keep_List_Exists : Boolean := False;
   begin
      if Pending_Mods = null or Col_Names = null then return; end if;
      Current := Pending_Mods;
      while Current /= null loop
         if Current.Kind = Mod_Keep then Keep_List_Exists := True; exit; end if;
         Current := Current.Next;
      end loop;
      if Keep_List_Exists then
         for I in Col_Names'Range loop
            declare Name : constant String := Col_Names(I).all; Should_Keep : Boolean := False;
            begin
               Current := Pending_Mods;
               while Current /= null loop
                  if Current.Name (1 .. Current.Len) = Name then
                     Should_Keep := (Current.Kind = Mod_Keep);
                  end if;
                  Current := Current.Next;
               end loop;
               if not Should_Keep then Drop_Column (Name); end if;
            end;
         end loop;
      else
         Current := Pending_Mods;
         while Current /= null loop
            if Current.Kind = Mod_Drop then Drop_Column (Current.Name (1 .. Current.Len)); end if;
            Current := Current.Next;
         end loop;
      end if;
      Pending_Mods := null; GNAT.Strings.Free (Col_Names);
   end Apply_Pending_Mods;

   procedure Expand_Range (Kind : Column_Mod_Kind; Range_Spec : Variable_Range) is
      use SData.Table;
      Col_Names : GNAT.Strings.String_List_Access := Get_Column_Names;
      Start_Name : constant String := (if Range_Spec.Start_Len in 1 .. 32 then To_Upper (Range_Spec.Start_Name (1 .. Range_Spec.Start_Len)) else "");
      End_Name   : constant String := (if Range_Spec.End_Len in 1 .. 32 then To_Upper (Range_Spec.End_Name (1 .. Range_Spec.End_Len)) else "");
      Start_Idx  : Natural := 0;
      End_Idx    : Natural := 0;
   begin
      if not Range_Spec.Is_Range then
         Add_Pending_Mod (Kind, Start_Name); return;
      end if;
      if Col_Names = null then return; end if;
      for I in Col_Names'Range loop
         if To_Upper (Col_Names (I).all) = Start_Name then Start_Idx := I; end if;
         if To_Upper (Col_Names (I).all) = End_Name then End_Idx := I; end if;
      end loop;
      if Start_Idx > 0 and End_Idx > 0 then
         if Start_Idx > End_Idx then
            declare Temp : constant Natural := Start_Idx; begin Start_Idx := End_Idx; End_Idx := Temp; end;
         end if;
         for I in Start_Idx .. End_Idx loop Add_Pending_Mod (Kind, Col_Names (I).all); end loop;
      else
         Add_Pending_Mod (Kind, Start_Name); Add_Pending_Mod (Kind, End_Name);
      end if;
      GNAT.Strings.Free (Col_Names);
   end Expand_Range;

   function Get_Expected_Kind (Name : String) return Value_Kind is
   begin
      if Name'Length > 0 then
         if Name (Name'Last) = '$' then return Val_String;
         elsif Name (Name'Last) = '%' then return Val_Integer; end if;
      end if;
      return Val_Numeric;
   end Get_Expected_Kind;

   procedure Execute_List (List : Statement_Access; Boundary : Statement_Access := null) is
      Current : Statement_Access := List;
   begin
      while Current /= null and then Current /= Boundary loop
         Execute_Statement (Current);
         if Current.Kind = Stmt_QUIT then return;
         elsif Current.Kind = Stmt_END then exit; end if;
         Current := Current.Next;
      end loop;
   end Execute_List;

   procedure Execute_Statement (Stmt : Statement_Access) is
   begin
       if Stmt = null then return; end if;
       case Stmt.Kind is
            when Stmt_LET | Stmt_SET =>
               declare
                  Var_Name_Str : constant String := Stmt.Var_Name(1 .. Stmt.Var_Len);
                  Expected     : constant Value_Kind := Get_Expected_Kind (Var_Name_Str);
                  Result       : Value := Evaluate (Stmt.Expr);
               begin
                  if Result.Kind /= Val_Missing then
                     if Expected = Val_Integer and Result.Kind /= Val_Integer then
                        Result := (Kind => Val_Integer, Int_Val => Integer (Float'Truncation (Convert_To_Float(Result))));
                     elsif Expected = Val_Numeric and Result.Kind = Val_Integer then
                        -- Promote integer to float.
                        Result := (Kind => Val_Numeric, Num_Val => Float (Result.Int_Val));
                     elsif Expected /= Result.Kind and not (Expected = Val_Numeric and Result.Kind = Val_Integer) then
                        raise Type_Mismatch_Error with "Cannot assign " & Result.Kind'Image & " to " & Expected'Image;
                     end if;
                  end if;
                  
                  if Stmt.Kind = Stmt_LET then
                     Set_Permanent (Var_Name_Str, Result);
                  else
                     Set_Temporary (Var_Name_Str, Result);
                  end if;
               exception
                  when Type_Mismatch_Error => Put_Line ("Error: Type mismatch for variable " & Var_Name_Str);
                  when others => Put_Line ("Error: Assignment failed for " & Var_Name_Str);
               end;
            when Stmt_PRINT =>
               if Stmt.Print_Args = null then
                  declare Col_Names : GNAT.Strings.String_List_Access := Get_Column_Names;
                  begin
                     if Col_Names /= null then
                        for I in Col_Names'Range loop
                           declare Name : constant String := Col_Names(I).all; Val : constant Value := Get_Value(Get_Current_Record_Index, Name);
                           begin Put (Name & ": " & To_String(Val) & "  "); end;
                        end loop;
                        New_Line; GNAT.Strings.Free(Col_Names);
                     end if;
                  end;
               else
                  declare Current_Arg : Expression_List := Stmt.Print_Args;
                  begin
                     while Current_Arg /= null loop
                        Put (To_String (Evaluate (Current_Arg.Expr)));
                        if Current_Arg.Next /= null then Put (" "); end if;
                        Current_Arg := Current_Arg.Next;
                     end loop;
                     New_Line;
                  end;
               end if;
            when Stmt_USE =>
               declare File_Name : constant String := Stmt.File_Path(1 .. Stmt.File_Len);
               begin
                  if File_Name = "mock" or File_Name = "mock_data" then
                     Clear; Add_Column ("ID", Col_Integer); Add_Column ("NAME", Col_String); Add_Column ("SALARY", Col_Numeric);
                     for I in 1 .. 3 loop
                        Add_Row; Set_Value (I, "ID", (Kind => Val_Integer, Int_Val => I));
                        Set_Value (I, "SALARY", (Kind => Val_Numeric, Num_Val => 50000.0 + Float(I - 1) * 10000.0));
                     end loop;
                     Set_Value(1, "NAME", (Kind => Val_String, Str_Val => "Alice" & (1 .. 1019 => ' '), Str_Len => 5));
                     Set_Value(2, "NAME", (Kind => Val_String, Str_Val => "Bob" & (1 .. 1021 => ' '), Str_Len => 3));
                     Set_Value(3, "NAME", (Kind => Val_String, Str_Val => "Charlie" & (1 .. 1017 => ' '), Str_Len => 7));
                  else SData.File_IO.Open_Input (File_Name, SData.Config.Input_Format); end if;
               end;
               Input_File_Columns.Clear;
               declare Col_Names : GNAT.Strings.String_List_Access := Get_Column_Names;
               begin
                  if Col_Names /= null then
                     for I in Col_Names'Range loop Input_File_Columns.Include (To_Upper (Col_Names (I).all)); end loop;
                     GNAT.Strings.Free (Col_Names);
                  end if;
               end;
               if not SData.Config.Quiet_Mode and then Stmt.File_Path(1 .. Stmt.File_Len) /= "mock_data" 
                 and then Stmt.File_Path(1 .. Stmt.File_Len) /= "mock" then
                  Put_Line ("Dataset opened: " & Stmt.File_Path(1 .. Stmt.File_Len));
               end if;
            when Stmt_REPEAT =>
               SData.Config.Repeat_Active := True;
               SData.Config.Repeat_Count := Stmt.Count;
               Input_File_Columns.Clear;
            when Stmt_SAVE =>
               SData.Config.Save_File_Path (1 .. Stmt.File_Len) := Stmt.File_Path (1 .. Stmt.File_Len);
               SData.Config.Save_File_Len := Stmt.File_Len;
               SData.Config.Save_File_Fmt := SData.Config.Output_Format;
               SData.Config.Save_File_Active := True;
            when Stmt_KEEP | Stmt_DROP =>
               declare Curr_Var : Variable_List := Stmt.Vars;
                       K : constant Column_Mod_Kind := (if Stmt.Kind = Stmt_KEEP then Mod_Keep else Mod_Drop);
               begin
                  while Curr_Var /= null loop
                     Expand_Range (K, Curr_Var.Var);
                     Curr_Var := Curr_Var.Next;
                  end loop;
               end;
            when Stmt_RENAME =>
               declare Curr : Rename_List := Stmt.Rename_Pairs;
               begin
                  while Curr /= null loop
                     Rename_Column (Curr.Old_Name (1 .. Curr.Old_Len), Curr.New_Name (1 .. Curr.New_Len));
                     Curr := Curr.Next;
                  end loop;
               end;
            when Stmt_NAMES =>
               declare Col_Names : GNAT.Strings.String_List_Access := Get_Column_Names;
               begin
                  if Col_Names /= null then
                     for I in Col_Names'Range loop Put(Col_Names(I).all & " "); end loop;
                     New_Line; GNAT.Strings.Free(Col_Names);
                  end if;
               end;
            when Stmt_IF =>
               if Is_True (Evaluate (Stmt.Condition)) then Execute_Statement (Stmt.Then_Branch);
               elsif Stmt.Else_Branch /= null then Execute_Statement (Stmt.Else_Branch); end if;
            when Stmt_WHILE =>
               while Is_True (Evaluate (Stmt.While_Cond)) loop Execute_List (Stmt.While_Body); end loop;
            when Stmt_FOR =>
               declare Start_Val : constant Value := Evaluate (Stmt.For_Start);
                       End_Val   : constant Value := Evaluate (Stmt.For_End);
                       Step_Val  : Value := (Kind => Val_Numeric, Num_Val => 1.0);
                       Current_I : Float;
               begin
                  if Stmt.For_Step /= null then Step_Val := Evaluate (Stmt.For_Step); end if;
                  begin
                     declare
                        S : constant Float := Convert_To_Float (Start_Val);
                        E : constant Float := Convert_To_Float (End_Val);
                        ST : constant Float := Convert_To_Float (Step_Val);
                     begin
                        Current_I := S;
                        loop
                           if ST >= 0.0 then exit when Current_I > E;
                           else exit when Current_I < E; end if;
                           Set_Permanent (Stmt.For_Var (1 .. Stmt.For_Var_Len), (Kind => Val_Numeric, Num_Val => Current_I));
                           Execute_List (Stmt.For_Body);
                           Current_I := Current_I + ST;
                        end loop;
                     end;
                  exception when others => null; end;
               end;
            when Stmt_SUBMIT =>
               if Submit_Level >= Max_Submit_Level then Put_Line ("Error: Maximum SUBMIT recursion level reached.");
               else
                  Submit_Level := Submit_Level + 1;
                  declare Filename : constant String := Stmt.File_Path (1 .. Stmt.File_Len);
                          File : Ada.Streams.Stream_IO.File_Type; Stream : Ada.Streams.Stream_IO.Stream_Access;
                  begin
                     Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Filename);
                     Stream := Ada.Streams.Stream_IO.Stream (File);
                     declare Source : String (1 .. Integer (Ada.Streams.Stream_IO.Size (File)));
                             Ctx : SData.Parser.Parser_Context; Prog : Statement_Access;
                     begin
                        String'Read (Stream, Source); Ada.Streams.Stream_IO.Close (File);
                        SData.Parser.Initialize (Ctx, Source); Prog := SData.Parser.Parse_Program (Ctx);
                        Execute (Prog);
                     end;
                  exception when others => Put_Line ("Error: Failed to SUBMIT file " & Filename); end;
                  Submit_Level := Submit_Level - 1;
               end if;
            when Stmt_RUN =>
               Run_Active_Program;
            when Stmt_NEW =>
               Clear;
               Clear_Temporary;
               SData.Config.Repeat_Active := False;
               SData.Config.Repeat_Count := 0;
               Input_File_Columns.Clear;
            when others => null;
         end case;
   end Execute_Statement;

   procedure Execute (Prog : Statement_Access) is
      Step_Start : Statement_Access := Prog;
      Current    : Statement_Access;
      Num_Records : Natural;
      Explicit_Loop_Trigger : Boolean;

      procedure Run_One_Step (Start, Boundary : Statement_Access) is
         Iter : Statement_Access;
      begin
         Iter := Start;
         Num_Records := 0;
         Explicit_Loop_Trigger := False;
         while Iter /= null and then Iter /= Boundary loop
            case Iter.Kind is
               when Stmt_USE | Stmt_REPEAT | Stmt_KEEP | Stmt_DROP | Stmt_RENAME | Stmt_SAVE | Stmt_NEW =>
                  Execute_Statement (Iter);
                  if Iter.Kind = Stmt_USE or Iter.Kind = Stmt_REPEAT then 
                     Explicit_Loop_Trigger := True; 
                     if Iter.Kind = Stmt_USE then Num_Records := Row_Count; else Num_Records := SData.Config.Repeat_Count; end if;
                  end if;
               when others => null;
            end case;
            Iter := Iter.Next;
         end loop;
         if not Explicit_Loop_Trigger then
            Num_Records := (if Row_Count > 0 then Row_Count else 1);
            if Num_Records = 1 and Row_Count = 0 then
               -- This is an implicit REPEAT 1. Ensure a row exists.
               Add_Row;
            end if;
         end if;
         for I in 1 .. Num_Records loop
            Set_Current_Record_Index (I);
            if Explicit_Loop_Trigger or Row_Count > 0 then
               declare
                  Col_Names : GNAT.Strings.String_List_Access := Get_Column_Names;
               begin
                  if Col_Names /= null then
                     if I > Row_Count then Add_Row; end if;
                     for C in Col_Names'Range loop
                        declare Name : constant String := To_Upper (Col_Names(C).all);
                        begin if not Input_File_Columns.Contains (Name) then Set_Value (I, Name, (Kind => Val_Missing)); end if; end;
                     end loop;
                     GNAT.Strings.Free (Col_Names);
                  end if;
               end;
            end if;
            Iter := Start;
            while Iter /= null and then Iter /= Boundary loop
               case Iter.Kind is
                  when Stmt_LET | Stmt_SET | Stmt_PRINT | Stmt_NAMES | Stmt_IF | Stmt_WHILE | Stmt_FOR | Stmt_SUBMIT =>
                     Execute_Statement(Iter);
                  when others => null;
               end case;
               Iter := Iter.Next;
            end loop;
         end loop;
         Set_Current_Record_Index (0);
         Apply_Pending_Mods;
         if SData.Config.Save_File_Active then
            SData.File_IO.Open_Output (SData.Config.Save_File_Path (1 .. SData.Config.Save_File_Len), SData.Config.Save_File_Fmt);
            if not SData.Config.Quiet_Mode then Put_Line ("Dataset saved: " & SData.Config.Save_File_Path (1 .. SData.Config.Save_File_Len)); end if;
            SData.Config.Save_File_Active := False;
         end if;
         Clear_Temporary;
      end Run_One_Step;

   begin
      Current := Prog;
      while Current /= null loop
         if Current.Kind = Stmt_RUN then
            Run_One_Step (Step_Start, Current);
            Step_Start := Current.Next;
         end if;
         Current := Current.Next;
      end loop;
   end Execute;

end SData.Interpreter;
