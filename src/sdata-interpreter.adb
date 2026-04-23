with SData.Help;
with SData.Table;     use SData.Table;
with SData.Values;    use SData.Values;
with SData.Variables; use SData.Variables;
with SData.Evaluator; use SData.Evaluator;
with GNAT.Strings; use GNAT.Strings;
with SData.System;
with SData.Statistics;
with SData.Parser; use SData.Parser;
with Ada.Streams.Stream_IO;
with Ada.Exceptions;
with SData.File_IO;
with SData.Config;         use SData.Config;
with SData.Config.Runtime;
with SData.IO;        use SData.IO;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Containers.Vectors;
with Ada.Strings.Hash;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;    use Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;

--  SData.Interpreter — statement executor and data step engine.
--
--  Execution model (three tiers):
--    Declarative       Commands such as USE, BY, SELECT, REPEAT, SAVE, FPATH
--                      execute immediately and configure interpreter state.
--    Immediate         RUN, SORT, NEW, NAMES, SYSTEM, HELP execute immediately
--                      but are not purely declarative.
--    Deferred          LET, SET, PRINT, IF, FOR, WHILE, WRITE, DELETE are
--                      queued in the statement list between two RUN markers and
--                      executed once per record inside Run_One_Step.
--
--  Data step (Run_One_Step):
--    1. Optionally rebuild the SELECT filter index map.
--    2. Determine the iteration count (logical row count when filtered,
--       Repeat_Count when REPEAT is active, or Row_Count otherwise).
--    3. For each logical row: load the PDV, set BOG/EOG indicators, execute
--       the deferred statement body, then flush the PDV to the output table
--       (unless an explicit WRITE has already done so or the record was
--       deleted).
--    4. Commit the output table, clear the stale filter map, and reset
--       Repeat_Active so subsequent RUNs iterate the committed table.
--
--  SELECT filter:
--    Select_Filter_Expr stores the filter expression persistently across RUNs.
--    At the start of each Run_One_Step the expression is re-evaluated for
--    every physical row to build a fresh Index_Array (logical→physical map).
--    All navigation functions (RECNO, BOF, EOF, BOG, EOG, LAG, NEXT) then
--    operate in logical space; filtered-out rows are completely invisible.

package body SData.Interpreter is

   package By_Group_Names is new Ada.Containers.Vectors (Index_Type => Positive, Element_Type => Unbounded_String);
   --  Ordered list of BY variable names (upper-cased).  Empty when no BY
   --  grouping is active.  Populated by Stmt_BY; cleared by bare BY or NEW.
   Current_By_Vars : By_Group_Names.Vector;

   --  Program buffer vector — mirrors Active_Program_Head/Tail linked list
   --  but provides indexed access for LIST and DELETE n[-m].
   type Program_Entry is record
      Stmt   : Statement_Access;
      Source : Unbounded_String;
   end record;
   package Program_Vectors is new Ada.Containers.Vectors (Positive, Program_Entry);
   Active_Program_Vec : Program_Vectors.Vector;

   function Is_Immediate (Kind : Statement_Kind) return Boolean is
   begin
      return Kind in
         Stmt_USE | Stmt_SAVE | Stmt_KEEP | Stmt_DROP |
         Stmt_RENAME | Stmt_NAMES | Stmt_LIST | Stmt_DISPLAY | Stmt_RUN | Stmt_QUIT | Stmt_END |
         Stmt_HOLD | Stmt_UNHOLD | Stmt_ARRAY | Stmt_DIM | Stmt_REPEAT | Stmt_NEW |
         Stmt_DIGITS | Stmt_HELP | Stmt_OUTPUT | Stmt_RSEED | Stmt_FPATH |
         Stmt_ECHO | Stmt_SORT | Stmt_BY | Stmt_SELECT_FILTER | Stmt_SUBMIT |
         Stmt_PROGRAM_DELETE;
   end Is_Immediate;

   procedure Set_Interactive (Val : Boolean) is
   begin
      SData.IO.Set_Interactive (Val);
   end Set_Interactive;

   --  Forward declarations for internal logic.
   procedure Execute_Statement    (Stmt : Statement_Access);
   procedure Execute_List         (List : Statement_Access; Boundary : Statement_Access := null);
   procedure Execute_Assignment   (Stmt : Statement_Access);
   procedure Execute_Print        (Stmt : Statement_Access);
   procedure Execute_Control_Flow (Stmt : Statement_Access);
   procedure Execute_Metadata        (Stmt : Statement_Access);
   procedure Execute_Program_Delete  (Stmt : Statement_Access);
   procedure Execute_Declarative     (Stmt : Statement_Access);
   procedure Execute_IO           (Stmt : Statement_Access);
   function  Is_First_In_Group    (Logical_Idx : Positive) return Boolean;
   function  Is_Last_In_Group     (Logical_Idx : Positive; Logical_Count : Natural) return Boolean;
   procedure Rebuild_Filter_Map;
   procedure Process_One_Record   (Logical_I        : Positive;
                                    Logical_Count    : Natural;
                                    Start            : Statement_Access;
                                    Boundary         : Statement_Access;
                                    Global_Has_Write : Boolean);
   procedure Commit_Step;
   procedure Run_One_Step         (Start, Boundary : Statement_Access);

   function Full_Path (Path : String; Category : String) return String;

   --  Set to track columns provided by the input file (to skip reset).
   package Name_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type => String,
      Hash         => Ada.Strings.Hash,
      Equivalent_Elements => "=");
   Input_File_Columns : Name_Sets.Set;

   --  Walks an expression AST and adds to Names every variable name that the
   --  expression reads at evaluation time.  Used by the SELECT filter scan to
   --  determine the minimal set of columns that need to be loaded per row.
   procedure Collect_Filter_Vars (Expr  : Expression_Access;
                                   Names : in out Name_Sets.Set);

   --  Set of script files currently in the SUBMIT execution chain (for cycle detection).
   Submit_Chain : Name_Sets.Set;

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

   procedure Free_Mod is new Ada.Unchecked_Deallocation (Column_Mod_Node, Column_Mod_List);

   Pending_Mods      : Column_Mod_List := null;
   Pending_Mods_Tail : Column_Mod_List := null;

   --  State for Data Step record processing.
   Current_Record_Deleted : Boolean := False;

   --  Persistent SELECT filter expression.  Set by Stmt_SELECT_FILTER and
   --  cleared by NEW.  The filter map is rebuilt from this expression at the
   --  start of every RUN so that it is always valid against the current table.
   Select_Filter_Expr : Expression_Access := null;



   -- Global program for REPL mode.
   Active_Program_Head : Statement_Access := null;
   Active_Program_Tail : Statement_Access := null;

   procedure Add_To_Active_Program (Stmt : Statement_Access; Source : String := "") is
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
      Active_Program_Vec.Append ((Stmt => Stmt, Source => To_Unbounded_String (Source)));
   end Add_To_Active_Program;

   procedure Clear_Active_Program is
   begin
      SData.AST.Free_Expression (Select_Filter_Expr);
      SData.AST.Free_Program (Active_Program_Head);
      Active_Program_Tail := null;
      Active_Program_Vec.Clear;
      SData.Table.Clear_Index_Map;
      Current_By_Vars.Clear;
      SData.Table.Clear_By_Vars;
   end Clear_Active_Program;

   function Program_Buffer_Length return Natural is
     (Natural (Active_Program_Vec.Length));

   procedure Run_Active_Program is
   begin
      if Active_Program_Head /= null then
         declare
            Prog    : constant Statement_Access := Active_Program_Head;
            Tail    : Statement_Access := Prog;
            Run_Cap : Statement_Access := new Statement (Stmt_RUN);
         begin
            --  Cap the chain with a synthetic Stmt_RUN so that Execute's
            --  outer loop calls Run_One_Step on the queued deferred
            --  statements.  The program is NOT cleared - it persists so
            --  that subsequent RUN commands re-execute the same program.
            --  Only NEW, USE, or REPEAT should replace the program.
            while Tail.Next /= null loop
               Tail := Tail.Next;
            end loop;
            Tail.Next := Run_Cap;
            Execute (Prog);
            --  Remove and free the synthetic cap.
            Tail.Next := null;
            SData.AST.Free_Program (Run_Cap);
         end;
      else
         -- No program queued: execute an empty step (e.g. bare RUN in REPL).
         Execute (null);
      end if;
   end Run_Active_Program;

   procedure Add_Pending_Mod (Kind : Column_Mod_Kind; Name : String) is
      New_Mod : constant Column_Mod_List := new Column_Mod_Node;
      Upper   : constant String := To_Upper (Name);
   begin
      New_Mod.Kind := Kind; New_Mod.Len := Upper'Length;
      New_Mod.Name (1 .. Upper'Length) := Upper; New_Mod.Next := null;
      if Pending_Mods = null then Pending_Mods := New_Mod;
      else Pending_Mods_Tail.Next := New_Mod; end if;
      Pending_Mods_Tail := New_Mod;
   end Add_Pending_Mod;

   procedure Clear_Pending_Mods is
   begin
      while Pending_Mods /= null loop
         declare Tmp : Column_Mod_List := Pending_Mods;
         begin Pending_Mods := Pending_Mods.Next; Free_Mod (Tmp);
         end;
      end loop;
      Pending_Mods_Tail := null;
   end Clear_Pending_Mods;

   --  Apply_Pending_Mods — two-pass KEEP-then-DROP logic.
   --  Pass 1: if any Mod_Keep entry exists, build a keep list and drop every
   --          column NOT in that list (implementing KEEP semantics).
   --  Pass 2: apply any explicit Mod_Drop entries.
   --  This ordering ensures KEEP and DROP can coexist without surprises.
   procedure Apply_Pending_Mods is
      Keep_Mods_Exist : Boolean := False;
      Keep_List : Name_Sets.Set;
      Curr : Column_Mod_List := Pending_Mods;
   begin
      -- First, check for KEEP statements and build a keep list
      while Curr /= null loop
         if Curr.Kind = Mod_Keep then
            Keep_Mods_Exist := True;
            Keep_List.Include (Curr.Name(1 .. Curr.Len));
         end if;
         Curr := Curr.Next;
      end loop;

      -- If there was a KEEP statement, drop everything not in the list.
      -- Snapshot names first: Drop_Column modifies Column_Order, so iterating
      -- Column_Name(I) live while dropping would corrupt the index sequence.
      if Keep_Mods_Exist then
         declare
            Snapshot : Name_Vectors.Vector;
         begin
            for I in 1 .. Column_Count loop
               Snapshot.Append (To_Unbounded_String (Column_Name (I)));
            end loop;
            for Name of Snapshot loop
               declare
                  Col_Name : constant String := To_String (Name);
               begin
                  if not Keep_List.Contains (Col_Name) then
                     Drop_Column (Col_Name);
                  end if;
               end;
            end loop;
         end;
      end if;

      -- Now handle explicit drops
      Curr := Pending_Mods;
      while Curr /= null loop
         if Curr.Kind = Mod_Drop then
            Drop_Column (Curr.Name (1 .. Curr.Len));
         end if;
         Curr := Curr.Next;
      end loop;

      Clear_Pending_Mods;
   end Apply_Pending_Mods;

   procedure Expand_Range (Kind : Column_Mod_Kind; Range_Spec : Variable_Range) is
      Start_Name : constant String := (if Range_Spec.Start_Len in 1 .. 32 then To_Upper (Range_Spec.Start_Name (1 .. Range_Spec.Start_Len)) else "");
      End_Name   : constant String := (if Range_Spec.End_Len in 1 .. 32 then To_Upper (Range_Spec.End_Name (1 .. Range_Spec.End_Len)) else "");
      Start_Idx, End_Idx : Natural := 0;
   begin
      if not Range_Spec.Is_Range then
         Add_Pending_Mod (Kind, Start_Name);
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
            for I in Start_Idx .. End_Idx loop
               Add_Pending_Mod (Kind, Column_Name (I));
            end loop;
         end if;
      end if;
   end Expand_Range;

   --  Has_Output_Statement — pre-scan to detect any explicit WRITE within the
   --  current data step body (between two RUN markers).  When a WRITE is found,
   --  the automatic end-of-record flush is suppressed so the step has full
   --  control over which records are written and when.
   function Has_Output_Statement (Stmt : Statement_Access; Boundary : Statement_Access := null) return Boolean is
      Curr : Statement_Access := Stmt;
   begin
      while Curr /= null and then Curr /= Boundary loop
         if Curr.Kind = Stmt_WRITE then return True; end if;

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
                  if Has_Output_Statement (Curr.Otherwise_Part) then return True; end if;
               end;
            when others => null;
         end case;
         Curr := Curr.Next;
      end loop;
      return False;
   end Has_Output_Statement;




   function Full_Path (Path : String; Category : String) return String is
      Cat  : constant String := To_Upper (Category);
      Base : Unbounded_String := Null_Unbounded_String;
      Result : Unbounded_String;

      function Has_Extension (S : String) return Boolean is
      begin
         for I in reverse S'Range loop
            if S (I) = '.' then
               return True;
            elsif S (I) = '/' or else S (I) = '\' then
               return False;
            end if;
         end loop;
         return False;
      end Has_Extension;
   begin
      -- 1. Handle absolute paths
      if Path'Length >= 1 and then (Path (Path'First) = '/' or else (Path'Length >= 2 and then Path (Path'First + 1) = ':')) then
         Result := To_Unbounded_String (Path);
      else
         -- 2. Handle FPATH prepending
         if Cat = "USE" then
            Base := SData.Config.Runtime.FPath_Use;
         elsif Cat = "SAVE" then
            Base := SData.Config.Runtime.FPath_Save;
         elsif Cat = "SUBMIT" then
            Base := SData.Config.Runtime.FPath_Submit;
         elsif Cat = "OUTPUT" then
            Base := SData.Config.Runtime.FPath_Output;
         end if;

         if Base /= Null_Unbounded_String and then To_String (Base) /= "" then
            declare
               B : constant String := To_String (Base);
            begin
               if B (B'Last) = '/' or else B (B'Last) = '\' then
                  Result := To_Unbounded_String (B & Path);
               else
                  Result := To_Unbounded_String (B & "/" & Path);
               end if;
            end;
         else
            Result := To_Unbounded_String (Path);
         end if;
      end if;

      -- 3. Append default extensions if missing
      declare
         S : constant String := To_String (Result);
      begin
         if To_Upper (S) = "MOCK" or else To_Upper (S) = "MOCK_DATA" then
            return S;
         end if;
         if not Has_Extension (S) then
            if Cat = "USE" or else Cat = "SAVE" then
               return S & ".CSV";
            elsif Cat = "SUBMIT" then
               return S & ".CMD";
            elsif Cat = "OUTPUT" then
               return S & ".DAT";
            end if;
         end if;
         return S;
      end;
   end Full_Path;

   --  LET / SET — variable assignment with type coercion and clen enforcement.
   procedure Execute_Assignment (Stmt : Statement_Access) is
      Var_Name_Str : constant String := Stmt.Var_Name (1 .. Stmt.Var_Len);
      Expected     : Value_Kind;
      Result       : Value;  --  Initialised in body so exceptions are caught below
   begin
      Result := Evaluate (Stmt.Expr);
      if Stmt.Is_Array then
         declare
            Idx_Val : constant Value := Evaluate (Stmt.Arr_Idx);
            Idx : Integer;
         begin
            if Idx_Val.Kind = Val_Integer then Idx := Idx_Val.Int_Val;
            elsif Idx_Val.Kind = Val_Numeric then Idx := Integer (Float'Floor (Idx_Val.Num_Val));
            else
               raise Script_Error with "Array index for """ & Var_Name_Str &
                  """ must be numeric, not " &
                  (if Idx_Val.Kind = Val_Missing then "missing" else "a string");
            end if;
            Set_Array_Element (Var_Name_Str, Idx, Result);
         end;
      else
         Expected := Get_Expected_Kind (Var_Name_Str);
         declare
            Existing_Kind : constant Value_Kind := Get_Type (Var_Name_Str);
         begin
            if Existing_Kind /= Val_Missing then
               if Expected /= Result.Kind and not (Expected = Val_Numeric and Result.Kind = Val_Integer) then
                  raise SData.Table.Type_Mismatch_Error with "Cannot assign " & Result.Kind'Image & " to " & Expected'Image;
               end if;
               if Existing_Kind = Val_String and Result.Kind /= Val_String then
                  raise SData.Table.Type_Mismatch_Error with "Cannot assign numeric to string variable " & Var_Name_Str;
               elsif Existing_Kind /= Val_String and Result.Kind = Val_String then
                  raise SData.Table.Type_Mismatch_Error with "Cannot assign string to numeric variable " & Var_Name_Str;
               end if;
            end if;
         end;
         if Result.Kind /= Val_Missing then
            if Expected = Val_Integer and Result.Kind /= Val_Integer then
               Result := (Kind => Val_Integer, Int_Val => Integer (Float'Truncation (Convert_To_Float(Result))));
            elsif Expected = Val_Numeric and Result.Kind = Val_Integer then
               Result := (Kind => Val_Numeric, Num_Val => Float (Result.Int_Val));
            elsif Expected /= Result.Kind and not (Expected = Val_Numeric and Result.Kind = Val_Integer) then
               raise SData.Table.Type_Mismatch_Error with "Cannot assign " & Result.Kind'Image & " to " & Expected'Image;
            end if;
         end if;
         if Result.Kind = Val_String and then
            SData.Config.Max_String_Len > 0 and then
            Length (Result.Str_Val) > SData.Config.Max_String_Len
         then
            Put_Line_Error ("Warning: String truncated to " &
                      Integer'Image (SData.Config.Max_String_Len) & " characters.");
            Result.Str_Val := To_Unbounded_String (Slice (Result.Str_Val, 1, SData.Config.Max_String_Len));
         end if;
         if Stmt.Kind = Stmt_LET then
            Set_Permanent (Var_Name_Str, Result);
         else
            Set_Temporary (Var_Name_Str, Result);
         end if;
      end if;
   exception
      when E : SData.Table.Type_Mismatch_Error =>
         raise Script_Error with "Type mismatch for variable " & Var_Name_Str & ": " & Ada.Exceptions.Exception_Message (E);
      when Script_Error => raise;
      when E : others =>
         raise Script_Error with "Assignment failed for variable " & Var_Name_Str & ": " & Ada.Exceptions.Exception_Message (E);
   end Execute_Assignment;

   --  PRINT — format and emit expression list or bare column dump.
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

   --  IF / WHILE / FOR / LOOP_REPEAT / SELECT — all control flow constructs.
   procedure Execute_Control_Flow (Stmt : Statement_Access) is
   begin
      case Stmt.Kind is
         when Stmt_IF =>
            if Is_True (Evaluate (Stmt.Condition)) then Execute_List (Stmt.Then_Branch);
            elsif Stmt.Else_Branch /= null then Execute_List (Stmt.Else_Branch); end if;
         when Stmt_WHILE =>
            while Is_True (Evaluate (Stmt.While_Cond)) loop Execute_List (Stmt.While_Body); end loop;
         when Stmt_FOR =>
            declare Start_Val : constant Value := Evaluate (Stmt.For_Start);
                    End_Val   : constant Value := Evaluate (Stmt.For_End);
                    Step_Val  : Value := (Kind => Val_Numeric, Num_Val => 1.0);
                    Current_I : Float;
            begin
               if Stmt.For_Step /= null then Step_Val := Evaluate (Stmt.For_Step); end if;
               declare
                  S  : constant Float := Convert_To_Float (Start_Val);
                  E  : constant Float := Convert_To_Float (End_Val);
                  ST : constant Float := Convert_To_Float (Step_Val);
               begin
                  Current_I := S;
                  while (ST > 0.0 and then Current_I <= E) or else (ST < 0.0 and then Current_I >= E) loop
                     Set_Permanent (Stmt.For_Var (1 .. Stmt.For_Var_Len), (Kind => Val_Numeric, Num_Val => Current_I));
                     Execute_List (Stmt.For_Body);
                     Current_I := Current_I + ST;
                  end loop;
               end;
            end;
         when Stmt_LOOP_REPEAT =>
            loop
               Execute_List (Stmt.Repeat_Body);
               exit when Is_True (Evaluate (Stmt.Until_Cond));
            end loop;
         when Stmt_SELECT =>
            declare
               Val     : constant Value := (if Stmt.Selector /= null then Evaluate (Stmt.Selector) else (Kind => Val_Missing));
               Branch  : Case_Branch := Stmt.Branches;
               Matched : Boolean := False;
            begin
               while Branch /= null loop
                  if Stmt.Selector = null then
                     declare Cond : Expression_List := Branch.Conditions;
                     begin
                        while Cond /= null loop
                           if Is_True (Evaluate (Cond.Expr)) then
                              Execute_List (Branch.Branch_Body); Matched := True; exit;
                           end if;
                           Cond := Cond.Next;
                        end loop;
                     end;
                  else
                     declare Cond : Expression_List := Branch.Conditions;
                     begin
                        while Cond /= null loop
                           if Evaluate (Cond.Expr) = Val then
                              Execute_List (Branch.Branch_Body); Matched := True; exit;
                           end if;
                           Cond := Cond.Next;
                        end loop;
                     end;
                  end if;
                  exit when Matched;
                  Branch := Branch.Next;
               end loop;
               if not Matched and then Stmt.Otherwise_Part /= null then
                  Execute_List (Stmt.Otherwise_Part);
               end if;
            end;
         when others => null;
      end case;
   end Execute_Control_Flow;

   --  KEEP / DROP / HOLD / UNHOLD / UNSET / RENAME / ARRAY / DIM / NAMES.
   procedure Execute_Metadata (Stmt : Statement_Access) is
   begin
      case Stmt.Kind is
         when Stmt_KEEP | Stmt_DROP | Stmt_HOLD | Stmt_UNHOLD | Stmt_UNSET =>
            declare Curr_Var : Variable_List := Stmt.Vars;
            begin
               if Stmt.Kind = Stmt_UNSET then
                  while Curr_Var /= null loop
                     SData.Variables.Unset (To_Upper (Curr_Var.Var.Start_Name (1 .. Curr_Var.Var.Start_Len)));
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
                        Start_Name : constant String := (if Range_Spec.Start_Len in 1 .. 32 then To_Upper (Range_Spec.Start_Name (1 .. Range_Spec.Start_Len)) else "");
                        End_Name   : constant String := (if Range_Spec.End_Len in 1 .. 32 then To_Upper (Range_Spec.End_Name (1 .. Range_Spec.End_Len)) else "");
                        Start_Idx, End_Idx : Natural := 0;
                     begin
                        if not Range_Spec.Is_Range then
                           Set_Hold (Start_Name, State);
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
            declare
               V        : Name_Vectors.Vector;
               Curr_Var : Variable_List := Stmt.Arr_Vars;
               procedure Resolve_Range (Range_Spec : Variable_Range) is
                  Start_Name : constant String := (if Range_Spec.Start_Len in 1 .. 32 then To_Upper (Range_Spec.Start_Name (1 .. Range_Spec.Start_Len)) else "");
                  End_Name   : constant String := (if Range_Spec.End_Len in 1 .. 32 then To_Upper (Range_Spec.End_Name (1 .. Range_Spec.End_Len)) else "");
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
               Define_Array (Stmt.Arr_Name (1 .. Stmt.Arr_Name_Len), V);
            exception
               when E : others =>
                  raise Script_Error with "Error defining array " & Stmt.Arr_Name (1 .. Stmt.Arr_Name_Len) & ": " & Ada.Exceptions.Exception_Message (E);
            end;
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
               Dim_Array (Stmt.Arr_Name (1 .. Stmt.Arr_Name_Len), Start_Idx, End_Idx, Stmt.Is_Temporary_Dim);
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
               Rows : constant Natural := SData.Table.Logical_Row_Count;
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
                     Phys_R : constant Positive := SData.Table.Logical_To_Physical (R);
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

   --  Execute_Program_Delete — removes entries From..To (1-based) from the
   --  program buffer and rebuilds the linked list.
   procedure Execute_Program_Delete (Stmt : Statement_Access) is
      From : constant Positive := Stmt.Delete_From;
      To   : constant Positive := Stmt.Delete_To;
      Last : constant Natural  := Natural (Active_Program_Vec.Length);
   begin
      if Last = 0 then
         Put_Line_Error ("Warning: program buffer is empty.");
         return;
      end if;
      if From > Last or else To > Last or else From > To then
         Put_Line_Error ("Warning: DELETE range out of range (buffer has"
                         & Last'Image & " entries).");
         return;
      end if;
      --  Free deleted AST nodes.
      for I in From .. To loop
         declare
            E : Program_Entry := Active_Program_Vec (I);
         begin
            SData.AST.Free_Program (E.Stmt);
         end;
      end loop;
      --  Remove from vector (iterate backwards to preserve indices).
      for I in reverse From .. To loop
         Active_Program_Vec.Delete (I);
      end loop;
      --  Rebuild linked list from remaining vector entries.
      Active_Program_Head := null;
      Active_Program_Tail := null;
      for E of Active_Program_Vec loop
         E.Stmt.Next := null;
         if Active_Program_Head = null then
            Active_Program_Head := E.Stmt;
            Active_Program_Tail := E.Stmt;
         else
            Active_Program_Tail.Next := E.Stmt;
            Active_Program_Tail := E.Stmt;
         end if;
      end loop;
   end Execute_Program_Delete;

   --  USE / SAVE / SORT / BY / REPEAT / SELECT (filter) / DIGITS / RSEED / NEW.
   procedure Execute_Declarative (Stmt : Statement_Access) is
   begin
      case Stmt.Kind is
         when Stmt_USE =>
            SData.Config.Runtime.Repeat_Active := False;
            SData.Config.Runtime.Repeat_Count := 0;
            declare
               File_Name : constant String := Stmt.File_Path (1 .. Stmt.File_Len);
               Expanded  : String (1 .. 1024);
               Exp_Len   : Natural := 0;
            begin
               if Stmt.Is_Mock then
                  Exp_Len := 4; Expanded (1 .. 4) := "MOCK";
               else
                  declare Full : constant String := Full_Path (File_Name, "USE");
                  begin Exp_Len := Full'Length; Expanded (1 .. Exp_Len) := Full; end;
               end if;
               SData.File_IO.Open_Input (Expanded (1 .. Exp_Len),
                 (if Stmt.Format_Specified then Stmt.Fmt_Override else SData.Config.Input_Format),
                 Stmt.Sheet_Name (1 .. Stmt.Sheet_Name_Len));
            end;
            Input_File_Columns.Clear;
            Refresh_PDV_Names;
            for I in 1 .. Column_Count loop
               Input_File_Columns.Include (Column_Name (I));
            end loop;
         when Stmt_SAVE =>
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
                  RC : constant String := Natural'Image (SData.Table.Row_Count);
                  VC : constant String := Natural'Image (SData.Table.Column_Count);
               begin
                  Put_Line ("SORT complete. " &
                            RC (RC'First + 1 .. RC'Last) & " records and " &
                            VC (VC'First + 1 .. VC'Last) & " variables processed.");
               end;
               if SData.Config.Runtime.Save_File_Active then
                  SData.File_IO.Open_Output (Full_Path (SData.Config.Runtime.Save_File_Path (1 .. SData.Config.Runtime.Save_File_Len), "SAVE"), SData.Config.Runtime.Save_File_Fmt, SData.Config.Runtime.Save_Sheet_Name (1 .. SData.Config.Runtime.Save_Sheet_Name_Len));
                  if not SData.Config.Quiet_Mode then Put_Line ("Dataset saved: " & SData.Config.Runtime.Save_File_Path (1 .. SData.Config.Runtime.Save_File_Len)); end if;
                  SData.Config.Runtime.Save_File_Active := False;
               end if;
            end;
         when Stmt_BY =>
            Current_By_Vars.Clear;
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
                        Current_By_Vars.Append (To_Unbounded_String (To_Upper (Curr_Var.Var.Start_Name (1 .. Curr_Var.Var.Start_Len))));
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
         when others => null;
      end case;
   end Execute_Declarative;

   --  SUBMIT / SYSTEM / OUTPUT / FPATH — external interaction and I/O routing.
   procedure Execute_IO (Stmt : Statement_Access) is
   begin
      case Stmt.Kind is
         when Stmt_SUBMIT =>
            declare
               Final : constant String := Full_Path (Stmt.File_Path (1 .. Stmt.File_Len), "SUBMIT");
            begin
               if Submit_Chain.Contains (Final) then
                  raise Script_Error with "Recursive SUBMIT detected: " & Final;
               end if;
               Submit_Chain.Insert (Final);
               declare
                  type String_Access is access String;
                  procedure Free_Buf is new Ada.Unchecked_Deallocation (String, String_Access);
                  File     : Ada.Streams.Stream_IO.File_Type;
                  Stream   : Ada.Streams.Stream_IO.Stream_Access;
                  Contents : String_Access;  --  heap-allocated; avoids stack pressure
               begin
                  Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Final);
                  Contents := new String (1 .. Integer (Ada.Streams.Stream_IO.Size (File)));
                  Stream := Ada.Streams.Stream_IO.Stream (File);
                  String'Read (Stream, Contents.all);
                  Ada.Streams.Stream_IO.Close (File);
                  declare
                     Sub_Ctx  : Parser_Context;
                     Sub_Prog : Statement_Access;
                  begin
                     Initialize (Sub_Ctx, Contents.all);
                     Sub_Prog := Parse_Program (Sub_Ctx);
                     Execute (Sub_Prog);
                     SData.AST.Free_Program (Sub_Prog);
                  end;
                  Free_Buf (Contents);
               exception
                  when Ada.Streams.Stream_IO.Name_Error =>
                     Free_Buf (Contents);
                     Submit_Chain.Delete (Final);
                     raise Script_Error with "SUBMIT: file not found: " & Final;
                  when others =>
                     Free_Buf (Contents);
                     Submit_Chain.Delete (Final);
                     raise;
               end;
               Submit_Chain.Delete (Final);
            end;
         when Stmt_SYSTEM =>
            if SData.Config.Disable_Shell then
               Put_Line_Error ("Error: SYSTEM command is disabled.");
            else
               declare Success : Boolean;
               begin
                  SData.System.Shell_Execute (Stmt.File_Path (1 .. Stmt.File_Len), Success);
               end;
            end if;
         when Stmt_OUTPUT =>
            if SData.IO.Is_Redirected then SData.IO.Close_Output; end if;
            if Stmt.File_Len > 0 then
               SData.IO.Open_Output (Full_Path (Stmt.File_Path (1 .. Stmt.File_Len), "OUTPUT"));
            end if;
         when Stmt_FPATH =>
            declare
               Path      : constant String  := (if Stmt.File_Len > 0 then Stmt.File_Path (1 .. Stmt.File_Len) else "");
               Reset_All : constant Boolean := not (Stmt.Use_Flag or Stmt.Save_Flag or Stmt.Submit_Flag or Stmt.Output_Flag);
            begin
               if Reset_All or Stmt.Use_Flag    then SData.Config.Runtime.FPath_Use    := To_Unbounded_String (Path); end if;
               if Reset_All or Stmt.Save_Flag   then SData.Config.Runtime.FPath_Save   := To_Unbounded_String (Path); end if;
               if Reset_All or Stmt.Submit_Flag then SData.Config.Runtime.FPath_Submit := To_Unbounded_String (Path); end if;
               if Reset_All or Stmt.Output_Flag then SData.Config.Runtime.FPath_Output := To_Unbounded_String (Path); end if;
            end;
         when others => null;
      end case;
   end Execute_IO;

   procedure Execute_Statement (Stmt : Statement_Access) is

   begin
      if Stmt = null then return; end if;
      if SData.Config.Debug_Mode then
         declare
            Image : constant String := Stmt.Kind'Image;
         begin
            --  Strip the "STMT_" prefix (5 characters) for readability.
            Put_Line_Error ("[debug] " & Image (Image'First + 5 .. Image'Last));
         end;
      end if;
      case Stmt.Kind is
         when Stmt_HELP =>
            SData.Help.Print_Help (Stmt.Var_Name (1 .. Stmt.Var_Len));
         when Stmt_RUN =>
            Run_Active_Program;
         when Stmt_QUIT | Stmt_END =>
            null;  --  Handled by loop termination in Execute.
         when Stmt_DELETE =>
            Current_Record_Deleted := True;
         when Stmt_WRITE =>
            SData.Variables.Flush_PDV_To_Output;
            SData.Table.Set_Record_Explicitly_Written (True);
         when Stmt_ECHO =>
            SData.IO.Set_Local_Echo (Stmt.Echo_State);
         when Stmt_LET | Stmt_SET =>
            Execute_Assignment (Stmt);
         when Stmt_PRINT =>
            Execute_Print (Stmt);
         when Stmt_IF | Stmt_WHILE | Stmt_FOR | Stmt_LOOP_REPEAT | Stmt_SELECT =>
            Execute_Control_Flow (Stmt);
         when Stmt_KEEP | Stmt_DROP | Stmt_HOLD | Stmt_UNHOLD | Stmt_UNSET
            | Stmt_RENAME | Stmt_ARRAY | Stmt_DIM | Stmt_NAMES | Stmt_LIST | Stmt_DISPLAY =>
            Execute_Metadata (Stmt);
         when Stmt_PROGRAM_DELETE =>
            Execute_Program_Delete (Stmt);
         when Stmt_USE | Stmt_SAVE | Stmt_SORT | Stmt_BY | Stmt_REPEAT
            | Stmt_SELECT_FILTER | Stmt_DIGITS | Stmt_RSEED | Stmt_NEW =>
            Execute_Declarative (Stmt);
         when Stmt_SUBMIT | Stmt_SYSTEM | Stmt_OUTPUT | Stmt_FPATH =>
            Execute_IO (Stmt);
         pragma Warnings (Off, "choice is redundant");
         when others => null;
         pragma Warnings (On, "choice is redundant");
      end case;
   end Execute_Statement;

   procedure Execute_List (List : Statement_Access; Boundary : Statement_Access := null) is
      Curr : Statement_Access := List;
   begin
      if List = null then return; end if;
      while Curr /= null and then Curr /= Boundary loop
         Execute_Statement (Curr);
         exit when Current_Record_Deleted;
         Curr := Curr.Next;
      end loop;
   end Execute_List;

   ---------------------------
   -- Collect_Filter_Vars  --
   ---------------------------
   --  Walks the filter expression AST recursively, inserting into Names the
   --  upper-cased name of every variable that the expression reads directly.
   --  For identifier-ref functions (LAG/NEXT/OBS and variants) the first
   --  argument is a variable name, not a read of that variable's current PDV
   --  value — those are skipped so we don't load an irrelevant column.
   procedure Collect_Filter_Vars (Expr  : Expression_Access;
                                   Names : in out Name_Sets.Set) is
   begin
      if Expr = null then return; end if;
      case Expr.Kind is
         when Expr_Variable =>
            Names.Include (To_Upper (Expr.Var_Name (1 .. Expr.Var_Len)));
         when Expr_Binary_Op =>
            Collect_Filter_Vars (Expr.Left,    Names);
            Collect_Filter_Vars (Expr.Right,   Names);
         when Expr_Unary_Op =>
            Collect_Filter_Vars (Expr.Operand, Names);
         when Expr_Function_Call =>
            declare
               FName : constant String :=
                  To_Upper (Expr.Func_Name (1 .. Expr.Func_Len));
               Args  : Expression_List := Expr.Arguments;
            begin
               if Is_Identifier_Ref_Function (FName) and then Args /= null then
                  Args := Args.Next;  -- skip the variable-name argument
               end if;
               while Args /= null loop
                  Collect_Filter_Vars (Args.Expr, Names);
                  Args := Args.Next;
               end loop;
            end;
         when Expr_Array_Access =>
            --  The array name is itself a variable reference.
            Names.Include (To_Upper (Expr.Arr_Name (1 .. Expr.Arr_Len)));
            declare
               Idx : Expression_List := Expr.Arr_Idx;
            begin
               while Idx /= null loop
                  Collect_Filter_Vars (Idx.Expr, Names);
                  Idx := Idx.Next;
               end loop;
            end;
         when others =>
            null;  -- Expr_Numeric_Literal and Expr_String_Literal: no variables.
      end case;
   end Collect_Filter_Vars;

   --  Is_First/Last_In_Group operate in logical space when a filter is active:
   --  Logical_Idx is a 1-based position into the filtered view, and
   --  Logical_To_Physical maps it to the actual table row for value comparisons.
   --  When unfiltered, logical == physical.
   function Is_First_In_Group (Logical_Idx : Positive) return Boolean is
      Phys_Curr  : constant Positive := SData.Table.Logical_To_Physical (Logical_Idx);
      Phys_Prev  : Positive;
      Curr_Value : Value;
      Prev_Value : Value;
   begin
      if Logical_Idx = 1 then return True; end if;
      if Current_By_Vars.Is_Empty then return False; end if;
      Phys_Prev := SData.Table.Logical_To_Physical (Logical_Idx - 1);
      for V of Current_By_Vars loop
         Prev_Value := Get_Value (Phys_Prev, To_String (V));
         Curr_Value := Get_Value (Phys_Curr, To_String (V));
         if not (Curr_Value = Prev_Value) then return True; end if;
      end loop;
      return False;
   end Is_First_In_Group;

   function Is_Last_In_Group (Logical_Idx : Positive; Logical_Count : Natural) return Boolean is
      Phys_Curr  : constant Positive := SData.Table.Logical_To_Physical (Logical_Idx);
      Phys_Next  : Positive;
      Curr_Value : Value;
      Next_Value : Value;
   begin
      if Logical_Idx = Logical_Count then return True; end if;
      if Current_By_Vars.Is_Empty then return False; end if;
      Phys_Next := SData.Table.Logical_To_Physical (Logical_Idx + 1);
      for V of Current_By_Vars loop
         Curr_Value := Get_Value (Phys_Curr, To_String (V));
         Next_Value := Get_Value (Phys_Next, To_String (V));
         if not (Curr_Value = Next_Value) then return True; end if;
      end loop;
      return False;
   end Is_Last_In_Group;

   --  Rebuild_Filter_Map — re-evaluates the SELECT filter against the current
   --  table and installs the resulting logical index map.  Called once at the
   --  start of every RUN.  The previous map was cleared by Commit_Output_Table,
   --  so this always works against the up-to-date physical row set.
   --  No-op when no filter is active.
   procedure Rebuild_Filter_Map is
   begin
      if Select_Filter_Expr = null then return; end if;
      declare
         Total          : constant Natural := Row_Count;
         Saved_Physical : constant Natural := SData.Table.Get_Current_Record_Index;
      begin
         if Total = 0 then
            SData.Table.Clear_Index_Map;
         else
            declare
               Filter_Cols : Name_Sets.Set;
            begin
               --  Targeted loading: only columns the filter expression actually
               --  reads are loaded per row.  Temporary variables are excluded —
               --  they are already in the symbol table.
               Collect_Filter_Vars (Select_Filter_Expr, Filter_Cols);
               declare
                  Passing : SData.Table.Index_Array (1 .. Total);
                  Count   : Natural := 0;
               begin
                  for R in 1 .. Total loop
                     SData.Table.Set_Current_Record_Index (R);
                     for Col_Name of Filter_Cols loop
                        if SData.Table.Has_Column (Col_Name) then
                           SData.Variables.Load_PDV_One_Column (R, Col_Name);
                        end if;
                     end loop;
                     if Is_True (Evaluate (Select_Filter_Expr)) then
                        Count := Count + 1;
                        Passing (Count) := R;
                     end if;
                  end loop;
                  SData.Table.Set_Current_Record_Index (Saved_Physical);
                  SData.Table.Set_Index_Map (Passing (1 .. Count));
               end;
            end;
         end if;
      end;
   end Rebuild_Filter_Map;

   --  Process_One_Record — runs one record through the data step body:
   --  sets BOG/EOG flags and FIRST./LAST. temporaries, loads the PDV,
   --  executes the deferred statement list, and auto-flushes if needed.
   procedure Process_One_Record (Logical_I        : Positive;
                                  Logical_Count    : Natural;
                                  Start            : Statement_Access;
                                  Boundary         : Statement_Access;
                                  Global_Has_Write : Boolean) is
      Phys_I : constant Positive := SData.Table.Logical_To_Physical (Logical_I);
      Iter   : Statement_Access;
   begin
      Set_Current_Record_Index (Phys_I);
      SData.Table.Set_Logical_Record_Index (Logical_I);

      if SData.Config.Debug_Mode then
         Put_Line_Error ("[debug] -- record" & Logical_I'Image
                         & " (physical" & Phys_I'Image & ")");
      end if;

      Reset_PDV_Non_Held;
      Load_PDV_From_Table (Phys_I);

      if not Current_By_Vars.Is_Empty then
         declare
            BOG_Val : constant Boolean := Is_First_In_Group (Logical_I);
            EOG_Val : constant Boolean := Is_Last_In_Group (Logical_I, Logical_Count);
         begin
            Set_BOG (BOG_Val);
            Set_EOG (EOG_Val);
            for V of Current_By_Vars loop
               declare Name : constant String := To_String (V); begin
                  Set_Temporary ("FIRST." & Name, (Kind => Val_Integer, Int_Val => (if BOG_Val then 1 else 0)));
                  Set_Temporary ("LAST."  & Name, (Kind => Val_Integer, Int_Val => (if EOG_Val then 1 else 0)));
               end;
            end loop;
         end;
      else
         Set_BOG (Logical_I = 1);
         Set_EOG (Logical_I = Logical_Count);
      end if;

      Iter := Start;
      Current_Record_Deleted := False;
      SData.Table.Set_Record_Explicitly_Written (False);

      while Iter /= null and then Iter /= Boundary loop
         case Iter.Kind is
            when Stmt_LET | Stmt_SET | Stmt_PRINT | Stmt_NAMES | Stmt_IF
               | Stmt_WHILE | Stmt_FOR | Stmt_LOOP_REPEAT | Stmt_SELECT
               | Stmt_DELETE | Stmt_WRITE | Stmt_OUTPUT | Stmt_ECHO
               | Stmt_HOLD | Stmt_UNHOLD | Stmt_ARRAY | Stmt_DIM
               | Stmt_BY | Stmt_DIGITS | Stmt_HELP =>
               begin
                  Execute_Statement (Iter);
               exception
                  when E : Script_Error =>
                     if SData.Config.Continue_On_Error then
                        Put_Line_Error ("Error: " & Ada.Exceptions.Exception_Message (E));
                        SData.Config.Runtime.Last_Error_Code := 1;
                        SData.Config.Runtime.Last_Error_Line := SData.Table.Get_Current_Record_Index;
                     else raise; end if;
                  when E : others =>
                     if SData.Config.Continue_On_Error then
                        Put_Line_Error ("Error: " & Ada.Exceptions.Exception_Message (E));
                        SData.Config.Runtime.Last_Error_Code := 1;
                        SData.Config.Runtime.Last_Error_Line := SData.Table.Get_Current_Record_Index;
                     else raise Script_Error with Ada.Exceptions.Exception_Message (E); end if;
               end;
            when others => null;
         end case;
         exit when Current_Record_Deleted;
         Iter := Iter.Next;
      end loop;

      --  Automatic flush: if the step contains no explicit WRITE and the
      --  record was not deleted, write the final PDV state to the output table.
      if not Current_Record_Deleted and then not Global_Has_Write then
         SData.Variables.Flush_PDV_To_Output;
      end if;
   end Process_One_Record;

   --  Commit_Step — finalizes a completed data step: commits the output table,
   --  resets filter/repeat state, applies pending column modifications, and
   --  writes to disk if a SAVE was deferred until after RUN.
   procedure Commit_Step is
   begin
      SData.Table.Set_Logical_Record_Index (0);
      SData.Table.Commit_Output_Table;
      --  The committed table is a new physical row set; clear the stale map
      --  so it is rebuilt fresh at the start of the next RUN.
      SData.Table.Clear_Index_Map;
      --  REPEAT generates records for exactly one RUN.  Subsequent RUNs
      --  must iterate the committed table, not re-use Repeat_Count.
      SData.Config.Runtime.Repeat_Active := False;
      Set_Current_Record_Index (0);
      Apply_Pending_Mods;
      if SData.Config.Runtime.Save_File_Active then
         SData.File_IO.Open_Output (Full_Path (SData.Config.Runtime.Save_File_Path (1 .. SData.Config.Runtime.Save_File_Len), "SAVE"), SData.Config.Runtime.Save_File_Fmt, SData.Config.Runtime.Save_Sheet_Name (1 .. SData.Config.Runtime.Save_Sheet_Name_Len));
         if not SData.Config.Quiet_Mode then Put_Line ("Dataset saved: " & SData.Config.Runtime.Save_File_Path (1 .. SData.Config.Runtime.Save_File_Len)); end if;
         SData.Config.Runtime.Save_File_Active := False;
      end if;
   end Commit_Step;

   --  Run_One_Step — executes the deferred statement list once per record.
   --  Start..Boundary is the slice of the statement list belonging to this RUN.
   procedure Run_One_Step (Start, Boundary : Statement_Access) is
      Global_Has_Write : constant Boolean := Has_Output_Statement (Start, Boundary);
      Num_Records      : constant Natural :=
         (if SData.Config.Runtime.Repeat_Active then SData.Config.Runtime.Repeat_Count
          else (if Row_Count > 0 then Row_Count else 1));
   begin
      Initialize_PDV;
      SData.Table.Initialize_Output_Table;
      Rebuild_Filter_Map;
      declare
         Logical_Count : constant Natural :=
            (if SData.Table.Is_Filtered then SData.Table.Logical_Row_Count
             else Num_Records);
      begin
         for Logical_I in 1 .. Logical_Count loop
            Process_One_Record (Logical_I, Logical_Count, Start, Boundary, Global_Has_Write);
         end loop;
      end;
      Commit_Step;
   end Run_One_Step;

   --  Execute — walk the statement list, partitioning it into data steps.
   --  A Stmt_RUN node acts as a step boundary: everything between two RUN
   --  markers is a deferred body executed by Run_One_Step.  Declarative and
   --  immediate statements are executed directly here, outside any data step.
   procedure Execute (Prog : Statement_Access) is
      Step_Start : Statement_Access := Prog;
      Current    : Statement_Access;
   begin
      if Prog = null then
         Run_One_Step (null, null);
         return;
      end if;

      Current := Prog;
      while Current /= null loop
         if Current.Kind = Stmt_RUN then
            Run_One_Step (Step_Start, Current);
            declare
               RC : constant String := Natural'Image (SData.Table.Row_Count);
               VC : constant String := Natural'Image (SData.Table.Column_Count);
            begin
               Put_Line ("RUN complete. " &
                         RC (RC'First + 1 .. RC'Last) & " records and " &
                         VC (VC'First + 1 .. VC'Last) & " variables processed.");
            end;
            Step_Start := Current.Next;
         elsif Current.Kind /= Stmt_LET and then Current.Kind /= Stmt_SET
            and then Current.Kind /= Stmt_PRINT  and then Current.Kind /= Stmt_IF
            and then Current.Kind /= Stmt_FOR     and then Current.Kind /= Stmt_WHILE
            and then Current.Kind /= Stmt_LOOP_REPEAT and then Current.Kind /= Stmt_SELECT
            and then Current.Kind /= Stmt_DELETE  and then Current.Kind /= Stmt_WRITE
            and then Current.Kind /= Stmt_DIM     and then Current.Kind /= Stmt_ARRAY
         then
            begin
               Execute_Statement (Current);
            exception
               when E : Script_Error =>
                  if SData.Config.Continue_On_Error then
                     Put_Line_Error ("Error: " & Ada.Exceptions.Exception_Message (E));
                     SData.Config.Runtime.Last_Error_Code := 1;
                     SData.Config.Runtime.Last_Error_Line := SData.Table.Get_Current_Record_Index;
                  else raise; end if;
               when E : others =>
                  if SData.Config.Continue_On_Error then
                     Put_Line_Error ("Error: " & Ada.Exceptions.Exception_Message (E));
                     SData.Config.Runtime.Last_Error_Code := 1;
                     SData.Config.Runtime.Last_Error_Line := SData.Table.Get_Current_Record_Index;
                  else raise Script_Error with Ada.Exceptions.Exception_Message (E); end if;
            end;
         end if;
         Current := Current.Next;
      end loop;
   end Execute;

end SData.Interpreter;
