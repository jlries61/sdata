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
with Ada.Containers.Vectors;
with Ada.Strings.Hash;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;

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

   --  State for Data Step record processing.
   Current_Record_Deleted : Boolean := False;
   Explicit_Output_Count  : Natural := 0;

   package Snapshot_Collector_Alias renames SData.Variables.Snapshot_Collector;
   Collector : Snapshot_Collector_Alias.Vector;

   function Has_Output_Statement (Stmt : Statement_Access) return Boolean is
      Curr : Statement_Access := Stmt;
   begin
      while Curr /= null loop
         if Curr.Kind = Stmt_OUTPUT then return True; end if;
         
         case Curr.Kind is
            when Stmt_IF =>
               if Has_Output_Statement (Curr.Then_Branch) or else
                  Has_Output_Statement (Curr.Else_Branch) then
                  return True;
               end if;
            when Stmt_FOR =>
               if Has_Output_Statement (Curr.For_Body) then return True; end if;
            when Stmt_WHILE =>
               if Has_Output_Statement (Curr.While_Body) then return True; end if;
            when Stmt_LOOP_REPEAT =>
               if Has_Output_Statement (Curr.Repeat_Body) then return True; end if;
            when Stmt_SELECT =>
               declare
                  Branch : Case_Branch := Curr.Branches;
               begin
                  while Branch /= null loop
                     if Has_Output_Statement (Branch.Branch_Body) then return True; end if;
                     Branch := Branch.Next;
                  end loop;
               end;
               if Has_Output_Statement (Curr.Otherwise_Part) then return True; end if;
            when others => null;
         end case;
         
         Curr := Curr.Next;
      end loop;
      return False;
   end Has_Output_Statement;

   -- For BY statement processing
   package By_Group_Names is new Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Unbounded_String);
   Current_By_Vars : By_Group_Names.Vector;
   
   -- Global program for REPL mode.
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

   -- Helper to recursively find aggregate function calls in an expression
   procedure Scan_Expr_For_Aggs (Expr : Expression_Access; Found : in out Name_Sets.Set) is
   begin
      if Expr = null then return; end if;
      case Expr.Kind is
         when Expr_Function_Call =>
            declare
               F_Name : constant String := To_Upper (Expr.Func_Name (1 .. Expr.Func_Len));
            begin
               if F_Name = "SUM" or F_Name = "MEAN" or F_Name = "STD" or F_Name = "VAR" or 
                  F_Name = "MIN" or F_Name = "MAX" or F_Name = "N" or F_Name = "NMISS" then
                  -- Verify it has exactly one variable argument
                  if Expr.Arguments /= null and then Expr.Arguments.Next = null and then 
                     Expr.Arguments.Expr.Kind = Expr_Variable then
                     declare
                        V_Name : constant String := To_Upper (Expr.Arguments.Expr.Var_Name (1 .. Expr.Arguments.Expr.Var_Len));
                     begin
                        Found.Include (F_Name & ":" & V_Name);
                     end;
                  end if;
               end if;
               -- Recurse into arguments
               declare Arg : Expression_List := Expr.Arguments;
               begin while Arg /= null loop Scan_Expr_For_Aggs (Arg.Expr, Found); Arg := Arg.Next; end loop; end;
            end;
         when Expr_Binary_Op =>
            Scan_Expr_For_Aggs (Expr.Left, Found);
            Scan_Expr_For_Aggs (Expr.Right, Found);
         when Expr_Unary_Op =>
            Scan_Expr_For_Aggs (Expr.Operand, Found);
         when Expr_Array_Access =>
            Scan_Expr_For_Aggs (Expr.Arr_Idx, Found);
         when others => null;
      end case;
   end Scan_Expr_For_Aggs;

   -- Scans a statement list for aggregate calls
   procedure Scan_Statements_For_Aggs (List, Boundary : Statement_Access; Found : in out Name_Sets.Set) is
      Curr : Statement_Access := List;
   begin
      while Curr /= null and then Curr /= Boundary loop
         case Curr.Kind is
            when Stmt_LET | Stmt_SET =>
               Scan_Expr_For_Aggs (Curr.Expr, Found);
               if Curr.Is_Array then Scan_Expr_For_Aggs (Curr.Arr_Idx, Found); end if;
            when Stmt_PRINT =>
               declare Arg : Expression_List := Curr.Print_Args;
               begin while Arg /= null loop Scan_Expr_For_Aggs (Arg.Expr, Found); Arg := Arg.Next; end loop; end;
            when Stmt_IF =>
               Scan_Expr_For_Aggs (Curr.Condition, Found);
               Scan_Statements_For_Aggs (Curr.Then_Branch, null, Found);
               Scan_Statements_For_Aggs (Curr.Else_Branch, null, Found);
            when Stmt_SELECT =>
               Scan_Expr_For_Aggs (Curr.Selector, Found);
               declare B : Case_Branch := Curr.Branches;
               begin
                  while B /= null loop
                     declare C : Expression_List := B.Conditions;
                     begin while C /= null loop Scan_Expr_For_Aggs (C.Expr, Found); C := C.Next; end loop; end;
                     Scan_Statements_For_Aggs (B.Branch_Body, null, Found);
                     B := B.Next;
                  end loop;
               end;
               Scan_Statements_For_Aggs (Curr.Otherwise_Part, null, Found);
            when Stmt_WHILE =>
               Scan_Expr_For_Aggs (Curr.While_Cond, Found);
               Scan_Statements_For_Aggs (Curr.While_Body, null, Found);
            when Stmt_FOR =>
               Scan_Expr_For_Aggs (Curr.For_Start, Found);
               Scan_Expr_For_Aggs (Curr.For_End, Found);
               Scan_Expr_For_Aggs (Curr.For_Step, Found);
               Scan_Statements_For_Aggs (Curr.For_Body, null, Found);
            when others => null;
         end case;
         Curr := Curr.Next;
      end loop;
   end Scan_Statements_For_Aggs;

   procedure Calculate_Aggregates (Start, Boundary : Statement_Access) is
      use SData.Table;
      Needed : Name_Sets.Set;
   begin
      Scan_Statements_For_Aggs (Start, Boundary, Needed);
      Clear_Aggregates;
      if Needed.Is_Empty or Row_Count = 0 then return; end if;

      for Req of Needed loop
         declare
            Sep   : constant Natural := Ada.Strings.Fixed.Index (Req, ":");
            Func  : constant String := Req (Req'First .. Sep - 1);
            Var   : constant String := Req (Sep + 1 .. Req'Last);
         begin
            if Current_By_Vars.Is_Empty then
               -- Global Aggregate
               declare
                  Sum, Sum_Sq, Min_V, Max_V : Long_Float := 0.0;
                  N_Count, NMISS_Count : Natural := 0;
                  First_Val : Boolean := True;
               begin
                  for R in 1 .. Row_Count loop
                     declare V : constant Value := Get_Value (R, Var);
                     begin
                        if V.Kind = Val_Missing then
                           NMISS_Count := NMISS_Count + 1;
                        else
                           declare FV : constant Long_Float := Long_Float (Convert_To_Float (V));
                           begin
                              N_Count := N_Count + 1;
                              Sum := Sum + FV;
                              Sum_Sq := Sum_Sq + FV**2;
                              if First_Val then
                                 Min_V := FV; Max_V := FV; First_Val := False;
                              else
                                 if FV < Min_V then Min_V := FV; end if;
                                 if FV > Max_V then Max_V := FV; end if;
                              end if;
                           end;
                        end if;
                     end;
                  end loop;
                  
                  declare
                     Result : Value := (Kind => Val_Missing);
                     NF : constant Long_Float := Long_Float (N_Count);
                  begin
                     if Func = "SUM" then Result := (Kind => Val_Numeric, Num_Val => Float (Sum));
                     elsif Func = "MEAN" then
                        if N_Count > 0 then Result := (Kind => Val_Numeric, Num_Val => Float (Sum / NF)); end if;
                     elsif Func = "MIN" then
                        if N_Count > 0 then Result := (Kind => Val_Numeric, Num_Val => Float (Min_V)); end if;
                     elsif Func = "MAX" then
                        if N_Count > 0 then Result := (Kind => Val_Numeric, Num_Val => Float (Max_V)); end if;
                     elsif Func = "N" then Result := (Kind => Val_Integer, Int_Val => N_Count);
                     elsif Func = "NMISS" then Result := (Kind => Val_Integer, Int_Val => NMISS_Count);
                     elsif Func = "VAR" or Func = "STD" then
                        if N_Count > 1 then
                           declare Variance : constant Long_Float := (Sum_Sq - (Sum**2 / NF)) / (NF - 1.0);
                           begin
                              if Func = "VAR" then Result := (Kind => Val_Numeric, Num_Val => Float (Variance));
                              else Result := (Kind => Val_Numeric, Num_Val => Sqrt (Float (Variance))); end if;
                           end;
                        end if;
                     end if;
                     Store_Aggregate (Func, Var, "", Result);
                  end;
               end;
            else
               -- Grouped Aggregates
               declare
                  Group_Start : Positive := 1;
               begin
                  while Group_Start <= Row_Count loop
                     declare
                        Group_End : Positive := Group_Start;
                        Sum, Sum_Sq, Min_V, Max_V : Long_Float := 0.0;
                        N_Count, NMISS_Count : Natural := 0;
                        First_Val : Boolean := True;
                        Group_Key : Unbounded_String := Null_Unbounded_String;
                     begin
                        -- Construct group key
                        for BV of Current_By_Vars loop
                           Append (Group_Key, To_String (Get_Value (Group_Start, To_String (BV))) & "|");
                        end loop;

                        -- Find end of group
                        while Group_End < Row_Count loop
                           declare Match : Boolean := True;
                           begin
                              for BV of Current_By_Vars loop
                                 if not (Get_Value (Group_Start, To_String (BV)) = Get_Value (Group_End + 1, To_String (BV))) then
                                    Match := False; exit;
                                 end if;
                              end loop;
                              exit when not Match;
                              Group_End := Group_End + 1;
                           end;
                        end loop;

                        -- Calculate for group
                        for R in Group_Start .. Group_End loop
                           declare V : constant Value := Get_Value (R, Var);
                           begin
                              if V.Kind = Val_Missing then
                                 NMISS_Count := NMISS_Count + 1;
                              else
                                 declare FV : constant Long_Float := Long_Float (Convert_To_Float (V));
                                 begin
                                    N_Count := N_Count + 1;
                                    Sum := Sum + FV;
                                    Sum_Sq := Sum_Sq + FV**2;
                                    if First_Val then
                                       Min_V := FV; Max_V := FV; First_Val := False;
                                    else
                                       if FV < Min_V then Min_V := FV; end if;
                                       if FV > Max_V then Max_V := FV; end if;
                                    end if;
                                 end;
                              end if;
                           end;
                        end loop;

                        declare
                           Result : Value := (Kind => Val_Missing);
                           NF : constant Long_Float := Long_Float (N_Count);
                        begin
                           if Func = "SUM" then Result := (Kind => Val_Numeric, Num_Val => Float (Sum));
                           elsif Func = "MEAN" then
                              if N_Count > 0 then Result := (Kind => Val_Numeric, Num_Val => Float (Sum / NF)); end if;
                           elsif Func = "MIN" then
                              if N_Count > 0 then Result := (Kind => Val_Numeric, Num_Val => Float (Min_V)); end if;
                           elsif Func = "MAX" then
                              if N_Count > 0 then Result := (Kind => Val_Numeric, Num_Val => Float (Max_V)); end if;
                           elsif Func = "N" then Result := (Kind => Val_Integer, Int_Val => N_Count);
                           elsif Func = "NMISS" then Result := (Kind => Val_Integer, Int_Val => NMISS_Count);
                           elsif Func = "VAR" or Func = "STD" then
                              if N_Count > 1 then
                                 declare Variance : constant Long_Float := (Sum_Sq - (Sum**2 / NF)) / (NF - 1.0);
                                 begin
                                    if Func = "VAR" then Result := (Kind => Val_Numeric, Num_Val => Float (Variance));
                                    else Result := (Kind => Val_Numeric, Num_Val => Sqrt (Float (Variance))); end if;
                                 end;
                              end if;
                           end if;
                           Store_Aggregate (Func, Var, To_String (Group_Key), Result);
                        end;
                        Group_Start := Group_End + 1;
                     end;
                  end loop;
               end;
            end if;
         end;
      end loop;
   end Calculate_Aggregates;

   procedure Execute_Statement (Stmt : Statement_Access) is
   begin
       if Stmt = null then return; end if;
       case Stmt.Kind is
            when Stmt_LET | Stmt_SET =>
               declare
                  Var_Name_Str : constant String := Stmt.Var_Name(1 .. Stmt.Var_Len);
                  Expected     : Value_Kind;
                  Result       : Value := Evaluate (Stmt.Expr);
               begin
                  if Stmt.Is_Array then
                     declare
                        Idx_Val : constant Value := Evaluate (Stmt.Arr_Idx);
                        Idx : Natural;
                     begin
                        if Idx_Val.Kind = Val_Integer then Idx := Idx_Val.Int_Val;
                        elsif Idx_Val.Kind = Val_Numeric then Idx := Natural (Float'Floor (Idx_Val.Num_Val));
                        else Idx := 0; end if;

                        if Idx > 0 then
                           Set_Array_Element (Var_Name_Str, Idx, Result);
                        end if;
                     end;
                  else
                     Expected := Get_Expected_Kind (Var_Name_Str);
                     
                     -- Check for existence and type if already permanent
                     declare
                        Existing_Kind : constant Value_Kind := Get_Type (Var_Name_Str);
                     begin
                        if Existing_Kind /= Val_Missing then
                           if Expected /= Result.Kind and not (Expected = Val_Numeric and Result.Kind = Val_Integer) then
                              raise Type_Mismatch_Error with "Cannot assign " & Result.Kind'Image & " to " & Expected'Image;
                           end if;
                           -- Double check actual kind for dynamic variables without suffixes
                           if Existing_Kind = Val_String and Result.Kind /= Val_String then
                              raise Type_Mismatch_Error with "Cannot assign numeric to string variable " & Var_Name_Str;
                           elsif Existing_Kind /= Val_String and Result.Kind = Val_String then
                              raise Type_Mismatch_Error with "Cannot assign string to numeric variable " & Var_Name_Str;
                           end if;
                        end if;
                     end;

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
                  end if;
               exception
                  when Type_Mismatch_Error => Put_Line ("Error: Type mismatch for variable " & Var_Name_Str);
                  when others => Put_Line ("Error: Assignment failed for " & Var_Name_Str);
               end;
            when Stmt_PRINT =>
               if Stmt.Print_Args = null then
                  declare
                     Col_Names : constant String_List_Access := Get_Column_Names;
                  begin
                     if Col_Names /= null then
                        for I in Col_Names'Range loop
                           declare
                              Name : constant String := To_Upper (Col_Names (I).all);
                              Val  : constant Value  := Get (Name);
                           begin
                              Put (Name & ": " & To_String (Val) & "  ");
                           end;
                        end loop;
                        New_Line;
                        declare
                           Old_List : String_List_Access := Col_Names;
                        begin
                           GNAT.Strings.Free (Old_List);
                        end;
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
                  --  Open_Input already prints success for some formats.
                  null;
               end if;
            when Stmt_SORT =>
               declare
                  Curr_Var : Variable_List := Stmt.Sort_Vars;
                  -- Count vars
                  Count : Natural := 0;
                  Tmp : Variable_List := Curr_Var;
               begin
                  while Tmp /= null loop Count := Count + 1; Tmp := Tmp.Next; end loop;
                  if Count > 0 then
                     declare
                        Crit : Sort_Criteria_Array (1 .. Count);
                        Idx : Positive := 1;
                     begin
                        while Curr_Var /= null loop
                           Crit (Idx).Name := (others => ' ');
                           Crit (Idx).Name (1 .. Curr_Var.Var.Start_Len) := To_Upper (Curr_Var.Var.Start_Name (1 .. Curr_Var.Var.Start_Len));
                           Crit (Idx).Len := Curr_Var.Var.Start_Len;
                           Crit (Idx).Dir := Ascending; -- For now, all ascending.
                           Idx := Idx + 1; Curr_Var := Curr_Var.Next;
                        end loop;
                        Sort (Crit);
                     end;
                  end if;
               end;
            when Stmt_BY =>
               declare
                  Curr_Var : Variable_List := Stmt.Sort_Vars;
               begin
                  Current_By_Vars.Clear;
                  while Curr_Var /= null loop
                     Current_By_Vars.Append (To_Unbounded_String (To_Upper (Curr_Var.Var.Start_Name (1 .. Curr_Var.Var.Start_Len))));
                     Curr_Var := Curr_Var.Next;
                  end loop;
               end;
            when Stmt_REPEAT =>
               SData.Config.Repeat_Active := True;
               SData.Config.Repeat_Count := Stmt.Count;
               Input_File_Columns.Clear;
            when Stmt_SAVE =>
               SData.Config.Save_File_Path (1 .. Stmt.File_Len) := Stmt.File_Path (1 .. Stmt.File_Len);
               SData.Config.Save_File_Len := Stmt.File_Len;
               SData.Config.Save_File_Fmt := SData.Config.Output_Format;
               SData.Config.Save_File_Active := True;
            when Stmt_KEEP | Stmt_DROP | Stmt_HOLD | Stmt_UNHOLD =>
               declare
                  Curr_Var : Variable_List := Stmt.Vars;
               begin
                  if Stmt.Kind = Stmt_KEEP or Stmt.Kind = Stmt_DROP then
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
                           Col_Names : GNAT.Strings.String_List_Access := Get_Column_Names;
                           Start_Name : constant String := (if Range_Spec.Start_Len in 1 .. 32 then To_Upper (Range_Spec.Start_Name (1 .. Range_Spec.Start_Len)) else "");
                           End_Name   : constant String := (if Range_Spec.End_Len in 1 .. 32 then To_Upper (Range_Spec.End_Name (1 .. Range_Spec.End_Len)) else "");
                           Start_Idx, End_Idx : Natural := 0;
                        begin
                           if not Range_Spec.Is_Range then
                              Set_Hold (Start_Name, State);
                           elsif Col_Names /= null then
                              for I in Col_Names'Range loop
                                 if To_Upper (Col_Names (I).all) = Start_Name then Start_Idx := I; end if;
                                 if To_Upper (Col_Names (I).all) = End_Name then End_Idx := I; end if;
                              end loop;
                              if Start_Idx > 0 and End_Idx > 0 then
                                 if Start_Idx > End_Idx then
                                    declare T : constant Natural := Start_Idx; begin Start_Idx := End_Idx; End_Idx := T; end;
                                 end if;
                                 for I in Start_Idx .. End_Idx loop Set_Hold (Col_Names (I).all, State); end loop;
                              end if;
                              GNAT.Strings.Free (Col_Names);
                           end if;
                        end Set_Hold_For_Range;
                     begin
                        while Curr_Var /= null loop
                           Set_Hold_For_Range (Curr_Var.Var);
                           Curr_Var := Curr_Var.Next;
                        end loop;
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
            when Stmt_ARRAY | Stmt_DIM =>
               declare
                  S : constant Statement_Access := Stmt;
                  V : Name_Vectors.Vector;
                  Curr_Var : Variable_List := S.Arr_Vars;

                  procedure Resolve_Range (Range_Spec : Variable_Range) is
                     Col_Names : GNAT.Strings.String_List_Access := Get_Column_Names;
                     Start_Name : constant String := (if Range_Spec.Start_Len in 1 .. 32 then To_Upper (Range_Spec.Start_Name (1 .. Range_Spec.Start_Len)) else "");
                     End_Name   : constant String := (if Range_Spec.End_Len in 1 .. 32 then To_Upper (Range_Spec.End_Name (1 .. Range_Spec.End_Len)) else "");
                     Start_Idx, End_Idx : Natural := 0;
                  begin
                     if not Range_Spec.Is_Range then
                        V.Append (To_Unbounded_String (Start_Name));
                     elsif Col_Names /= null then
                        for I in Col_Names'Range loop
                           if To_Upper (Col_Names (I).all) = Start_Name then Start_Idx := I; end if;
                           if To_Upper (Col_Names (I).all) = End_Name then End_Idx := I; end if;
                        end loop;
                        if Start_Idx > 0 and End_Idx > 0 then
                           if Start_Idx > End_Idx then
                              declare T : constant Natural := Start_Idx; begin Start_Idx := End_Idx; End_Idx := T; end;
                           end if;
                           for I in Start_Idx .. End_Idx loop
                              V.Append (To_Unbounded_String (Col_Names (I).all));
                           end loop;
                        end if;
                        GNAT.Strings.Free (Col_Names);
                     end if;
                  end Resolve_Range;
               begin
                  while Curr_Var /= null loop
                     Resolve_Range (Curr_Var.Var);
                     Curr_Var := Curr_Var.Next;
                  end loop;
                  Define_Array (S.Arr_Name (1 .. S.Arr_Name_Len), V);
               exception
                  when others => Put_Line ("Error defining array " & S.Arr_Name (1 .. S.Arr_Name_Len)); raise;
               end;
            when Stmt_NAMES =>
               declare
                  -- Merge Table columns and Permanent PDV symbols
                  T_Names : constant String_List_Access := Get_Column_Names;
                  P_Names : constant String_List_Access := Get_PDV_Names;
               begin
                  if T_Names /= null then
                     for I in T_Names'Range loop
                        Put (T_Names (I).all & " ");
                     end loop;
                  end if;
                  
                  if P_Names /= null then
                     for I in P_Names'Range loop
                        declare
                           Name : constant String := P_Names (I).all;
                           Found_In_Table : Boolean := False;
                        begin
                           if T_Names /= null then
                              for J in T_Names'Range loop
                                 if T_Names (J).all = Name then Found_In_Table := True; exit; end if;
                              end loop;
                           end if;
                           if not Found_In_Table then
                              Put (Name & " ");
                           end if;
                        end;
                     end loop;
                  end if;
                  New_Line;

                  if T_Names /= null then
                     declare Old : String_List_Access := T_Names; begin GNAT.Strings.Free (Old); end;
                  end if;
                  if P_Names /= null then
                     declare Old : String_List_Access := P_Names; begin GNAT.Strings.Free (Old); end;
                  end if;
               end;
            when Stmt_SELECT =>
               declare
                  Selector_Val : Value := (Kind => Val_Missing);
                  Has_Selector : constant Boolean := Stmt.Selector /= null;
                  Matched      : Boolean := False;
                  Branch       : Case_Branch := Stmt.Branches;
               begin
                  if Has_Selector then
                     Selector_Val := Evaluate (Stmt.Selector);
                  end if;
                  
                  while Branch /= null loop
                     Matched := False;
                     if Has_Selector then
                        -- Match selector against condition list
                        declare
                           Cond_Node : Expression_List := Branch.Conditions;
                        begin
                           while Cond_Node /= null loop
                              if Evaluate (Cond_Node.Expr) = Selector_Val then
                                 Matched := True; exit;
                              end if;
                              Cond_Node := Cond_Node.Next;
                           end loop;
                        end;
                     else
                        -- Case where SELECT has no expression: conditions are boolean tests
                        if Is_True (Evaluate (Branch.Conditions.Expr)) then
                           Matched := True;
                        end if;
                     end if;
                     
                     if Matched then
                        Execute_Statement (Branch.Branch_Body);
                        exit;
                     end if;
                     Branch := Branch.Next;
                  end loop;
                  
                  if not Matched and then Stmt.Otherwise_Part /= null then
                     Execute_Statement (Stmt.Otherwise_Part);
                  end if;
               end;
            when Stmt_DELETE =>
               Current_Record_Deleted := True;
            when Stmt_OUTPUT =>
               Explicit_Output_Count := Explicit_Output_Count + 1;
               Collector.Append (SData.Variables.Take_PDV_Snapshot);
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
         Step_Has_Output : constant Boolean := Has_Output_Statement (Start);

         function Is_First_In_Group (Idx : Positive) return Boolean is
         begin
            if Idx = 1 or Current_By_Vars.Is_Empty then return True; end if;
            for V of Current_By_Vars loop
               declare
                  Name : constant String := To_String (V);
               begin
                  if not (Get_Value (Idx, Name) = Get_Value (Idx - 1, Name)) then return True; end if;
               end;
            end loop;
            return False;
         end Is_First_In_Group;

         function Is_Last_In_Group (Idx : Positive) return Boolean is
         begin
            if Idx = Num_Records or Current_By_Vars.Is_Empty then return True; end if;
            for V of Current_By_Vars loop
               declare
                  Name : constant String := To_String (V);
               begin
                  if not (Get_Value (Idx, Name) = Get_Value (Idx + 1, Name)) then return True; end if;
               end;
            end loop;
            return False;
         end Is_Last_In_Group;

      begin
         Iter := Start;
         Num_Records := 0;
         Explicit_Loop_Trigger := False;
         Current_By_Vars.Clear;
         Initialize_PDV;
         Collector.Clear;
         
         while Iter /= null and then Iter /= Boundary loop
            case Iter.Kind is
               when Stmt_USE | Stmt_REPEAT | Stmt_KEEP | Stmt_DROP | Stmt_RENAME | Stmt_SAVE | Stmt_NEW | Stmt_HOLD | Stmt_UNHOLD | Stmt_ARRAY | Stmt_DIM | Stmt_SORT | Stmt_BY =>
                  Execute_Statement (Iter);
                  if Iter.Kind = Stmt_USE or Iter.Kind = Stmt_REPEAT then 
                     Explicit_Loop_Trigger := True; 
                     if Iter.Kind = Stmt_USE then Num_Records := Row_Count; else Num_Records := SData.Config.Repeat_Count; end if;
                  end if;
               when others => null;
            end case;
            Iter := Iter.Next;
         end loop;

         -- Pre-calculate aggregates based on the current state of the table
         Calculate_Aggregates (Start, Boundary);

         if not Explicit_Loop_Trigger then
            Num_Records := (if Row_Count > 0 then Row_Count else 1);
         end if;

         for I in 1 .. Num_Records loop
            Set_Current_Record_Index (I);

            -- Construct and set Group Key for this record
            if not Current_By_Vars.Is_Empty then
               declare
                  Group_Key : Unbounded_String := Null_Unbounded_String;
               begin
                  for BV of Current_By_Vars loop
                     Append (Group_Key, To_String (Get_Value (I, To_String (BV))) & "|");
                  end loop;
                  Set_Current_Group_Key (To_String (Group_Key));
               end;
            else
               Set_Current_Group_Key ("");
            end if;
            
            -- Step 1: Initialize PDV for this record
            Reset_PDV_Non_Held;
            if Explicit_Loop_Trigger or Row_Count > 0 then
               if I <= Row_Count then
                  Load_PDV_From_Table (I);
               else
                  -- Logic for REPEAT: ensure current columns are in PDV
                  -- but they will be missing by default from Reset_PDV_Non_Held.
                  null;
               end if;
            end if;

            -- Set First. and Last. indicators
            if not Current_By_Vars.Is_Empty then
               for V of Current_By_Vars loop
                  declare
                     Name : constant String := To_String (V);
                  begin
                     Set_Temporary ("FIRST." & Name, (Kind => Val_Integer, Int_Val => (if Is_First_In_Group (I) then 1 else 0)));
                     Set_Temporary ("LAST." & Name, (Kind => Val_Integer, Int_Val => (if Is_Last_In_Group (I) then 1 else 0)));
                  end;
               end loop;
            end if;

            Iter := Start;
            Current_Record_Deleted := False;
            Explicit_Output_Count  := 0;

            while Iter /= null and then Iter /= Boundary loop
               case Iter.Kind is
                  when Stmt_LET | Stmt_SET | Stmt_PRINT | Stmt_NAMES | Stmt_IF | Stmt_WHILE | Stmt_FOR | Stmt_SUBMIT | Stmt_SELECT | Stmt_DELETE | Stmt_OUTPUT | Stmt_HOLD | Stmt_UNHOLD | Stmt_ARRAY | Stmt_DIM | Stmt_SORT | Stmt_BY =>
                     Execute_Statement(Iter);
                  when others => null;
               end case;
               exit when Current_Record_Deleted;
               Iter := Iter.Next;
            end loop;
            
            if not Current_Record_Deleted and then (not Step_Has_Output) then
               Collector.Append (SData.Variables.Take_PDV_Snapshot);
            end if;
         end loop;
         
         Commit_Snapshots_To_Table (Collector);
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
