--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

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
with Ada.Text_IO.Unbounded_IO;

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

   --  Per-record execution context, created once per data step and threaded
   --  through the entire execution chain.  Eliminates the Global_Record_Deleted
   --  package variable and makes per-record state visible in signatures.
   --  BY variable names are queried directly from SData.Table (single source
   --  of truth); no local copy is kept here.
   type Step_Context is record
      Deleted : Boolean := False;
      BOG     : Boolean := False;
      EOG     : Boolean := False;
   end record;

   --  Program buffer vector — canonical program store; provides both indexed
   --  access (LIST, DELETE) and traversal order for RUN.
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
         Stmt_SYSTEM | Stmt_PROGRAM_DELETE | Stmt_OPTIONS | Stmt_VANDALIZE;
   end Is_Immediate;

   procedure Set_Interactive (Val : Boolean) is
   begin
      SData.IO.Set_Interactive (Val);
   end Set_Interactive;

   type Step_Action is (Action_Continue, Action_Step, Action_Run);

   --  Result type for the Group_Flags pure function.
   type Group_Flags_Result is record
      BOG : Boolean;
      EOG : Boolean;
   end record;

   --  Forward declarations for internal logic.
   procedure Execute_Statement    (Stmt : Statement_Access; Ctx : in out Step_Context);
   procedure Execute_List         (List : Statement_Access; Ctx : in out Step_Context; Boundary : Statement_Access := null);
   procedure Execute_Assignment      (Stmt : Statement_Access);
   procedure Execute_Print        (Stmt : Statement_Access);
   procedure Execute_Control_Flow (Stmt : Statement_Access; Ctx : in out Step_Context);
   procedure Execute_Metadata        (Stmt : Statement_Access);
   procedure Execute_Program_Delete  (Stmt : Statement_Access);
   procedure Execute_Declarative     (Stmt : Statement_Access);
   procedure Execute_IO           (Stmt : Statement_Access);
   function  Group_Flags (Logical_I     : Positive;
                          Logical_Count : Natural)
                          return Group_Flags_Result;
   procedure Rebuild_Filter_Map;
   procedure Process_One_Record   (Logical_I        : Positive;
                                    Logical_Count    : Natural;
                                    Start            : Statement_Access;
                                    Boundary         : Statement_Access;
                                    Global_Has_Write : Boolean;
                                    Ctx              : in out Step_Context;
                                    Pause_After      : Boolean := False;
                                    Action           : out Step_Action);
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
      Name : String (1 .. Max_Name_Len);
      Len  : Natural;
      Next : Column_Mod_List;
   end record;

   procedure Free_Mod is new Ada.Unchecked_Deallocation (Column_Mod_Node, Column_Mod_List);

   Pending_Mods      : Column_Mod_List := null;
   Pending_Mods_Tail : Column_Mod_List := null;

   --  Persistent SELECT filter expression.  Set by Stmt_SELECT_FILTER and
   --  cleared by NEW.  The filter map is rebuilt from this expression at the
   --  start of every RUN so that it is always valid against the current table.
   Select_Filter_Expr : Expression_Access := null;



   procedure Add_To_Active_Program (Stmt : Statement_Access; Source : String := "") is
   begin
      if Stmt = null then return; end if;
      Active_Program_Vec.Append ((Stmt => Stmt, Source => To_Unbounded_String (Source)));
   end Add_To_Active_Program;

   procedure Clear_Active_Program is
   begin
      SData.AST.Free_Expression (Select_Filter_Expr);
      for E of Active_Program_Vec loop
         SData.AST.Free_Program (E.Stmt);
      end loop;
      Active_Program_Vec.Clear;
      SData.Table.Clear_Index_Map;
      SData.Table.Clear_By_Vars;
   end Clear_Active_Program;

   procedure Debug_Trace (Msg : String; Level : Positive) is
   begin
      if SData.Config.Debug_Level >= Level then
         Put_Line_Error ("[debug] " & Msg);
      end if;
   end Debug_Trace;

   function Debug_Value (V : Value) return String is
   begin
      case V.Kind is
         when Val_Numeric  =>
            return To_String_Formatted (V);
         when Val_Integer  =>
            return To_String_Formatted (V);
         when Val_String   =>
            return """" & To_String (V.Str_Val) & """";
         when Val_Missing  =>
            return "<missing>";
      end case;
   end Debug_Value;

   Break_Triggered : exception;

   procedure Inspect_PDV
     (Logical_I     :        Positive;
      Logical_Count :        Natural;
      Action        :    out Step_Action)
   is separate;

   function Program_Buffer_Length return Natural is
     (Natural (Active_Program_Vec.Length));

   procedure Run_Active_Program is
   begin
      if Active_Program_Vec.Is_Empty then
         Execute (null);
      else
         declare
            Last    : constant Positive := Natural (Active_Program_Vec.Length);
            Run_Cap : Statement_Access := new Statement (Stmt_RUN);
         begin
            --  Transiently chain vector entries and cap with a synthetic
            --  Stmt_RUN so Execute's outer loop triggers deferred processing.
            --  The program persists across RUN; only NEW/USE/REPEAT replaces it.
            for I in 1 .. Last - 1 loop
               Active_Program_Vec (I).Stmt.Next :=
                  Active_Program_Vec (I + 1).Stmt;
            end loop;
            Active_Program_Vec (Last).Stmt.Next := Run_Cap;
            Execute (Active_Program_Vec (1).Stmt);
            --  Unchain: restore all Next pointers to null, then free the cap.
            for I in 1 .. Last loop
               Active_Program_Vec (I).Stmt.Next := null;
            end loop;
            SData.AST.Free_Program (Run_Cap);
         end;
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

   --  Splits Name into an alphabetic prefix and trailing integer suffix.
   --  Returns True on success; Prefix and Num are set on success only.
   function Split_Numeric_Suffix (Name   :     String;
                                   Prefix : out Unbounded_String;
                                   Num    : out Natural) return Boolean is
      I : Integer := Name'Last;
   begin
      while I >= Name'First and then Name (I) in '0' .. '9' loop
         I := I - 1;
      end loop;
      if I = Name'Last then
         Prefix := Null_Unbounded_String; Num := 0; return False;
      end if;
      Prefix := To_Unbounded_String (Name (Name'First .. I));
      Num    := Natural'Value (Name (I + 1 .. Name'Last));
      return True;
   end Split_Numeric_Suffix;

   --  Expand a colon range (Start_Name:End_Name) into a numerically ordered
   --  vector of names.  Returns an empty vector if either name lacks a
   --  numeric suffix or the alphabetic prefixes differ.
   --  When Create_Missing is True, variables not found in the current table
   --  are added as missing-valued columns (used for ARRAY declarations).
   function Expand_Colon_Names (Start_Name    : String;
                                 End_Name      : String;
                                 Create_Missing : Boolean := False)
      return Name_Vectors.Vector
   is
      Result       : Name_Vectors.Vector;
      Start_Prefix : Unbounded_String;
      End_Prefix   : Unbounded_String;
      Start_Num    : Natural;
      End_Num      : Natural;
      Lo, Hi       : Natural;
   begin
      if not Split_Numeric_Suffix (Start_Name, Start_Prefix, Start_Num) or else
         not Split_Numeric_Suffix (End_Name,   End_Prefix,   End_Num)
      then
         return Result;  -- names lack numeric suffixes — silent no-op
      end if;
      if Start_Prefix /= End_Prefix then
         return Result;  -- mismatched prefixes — silent no-op
      end if;
      Lo := Natural'Min (Start_Num, End_Num);
      Hi := Natural'Max (Start_Num, End_Num);
      declare
         Pfx : constant String := To_String (Start_Prefix);
      begin
         for N in Lo .. Hi loop
            declare
               Var_Name : constant String :=
                  Pfx & Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Both);
            begin
               if Create_Missing and then not Has_Column (Var_Name) then
                  Add_Column (Var_Name, Col_Numeric);
               end if;
               Result.Append (To_Unbounded_String (Var_Name));
            end;
         end loop;
      end;
      return Result;
   end Expand_Colon_Names;

   procedure Expand_Range (Kind : Column_Mod_Kind; Range_Spec : Variable_Range) is
      Start_Name : constant String := (if Range_Spec.Start_Len in 1 .. Max_Name_Len then To_Upper (Range_Spec.Start_Name (1 .. Range_Spec.Start_Len)) else "");
      End_Name   : constant String := (if Range_Spec.End_Len in 1 .. Max_Name_Len then To_Upper (Range_Spec.End_Name (1 .. Range_Spec.End_Len)) else "");
      Start_Idx, End_Idx : Natural := 0;
   begin
      if not Range_Spec.Is_Range then
         Add_Pending_Mod (Kind, Start_Name);
      elsif Range_Spec.Is_Colon_Range then
         --  Colon range: numeric order; no creation for DROP, create for others.
         declare
            Names : constant Name_Vectors.Vector :=
               Expand_Colon_Names (Start_Name, End_Name,
                                   Create_Missing => (Kind /= Mod_Drop));
         begin
            for N of Names loop
               Add_Pending_Mod (Kind, To_String (N));
            end loop;
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

   --  LET / SET — body extracted to subunit.
   procedure Execute_Assignment (Stmt : Statement_Access) is separate;

   --  PRINT — format and emit expression list or bare column dump.
   procedure Execute_Print (Stmt : Statement_Access) is separate;

   --  IF / WHILE / FOR / LOOP_REPEAT / SELECT — all control flow constructs.
   procedure Execute_Control_Flow (Stmt : Statement_Access; Ctx : in out Step_Context) is separate;

   --  KEEP / DROP / HOLD / UNHOLD / UNSET / RENAME / ARRAY / DIM / NAMES.
   procedure Execute_Metadata (Stmt : Statement_Access) is separate;

   --  Execute_Program_Delete — removes entries From..To (1-based) from the
   --  program buffer vector.
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
   end Execute_Program_Delete;

   --  USE / SAVE / SORT / BY / REPEAT / SELECT (filter) / DIGITS / RSEED / NEW / OPTIONS.
   procedure Execute_Declarative (Stmt : Statement_Access) is separate;

   --  SUBMIT / SYSTEM / OUTPUT / FPATH — external interaction and I/O routing.
   procedure Execute_IO (Stmt : Statement_Access) is separate;

   procedure Execute_Statement (Stmt : Statement_Access; Ctx : in out Step_Context) is

   begin
      if Stmt = null then return; end if;
      case Stmt.Kind is
         when Stmt_HELP =>
            SData.Help.Print_Help (Stmt.Var_Name (1 .. Stmt.Var_Len));
         when Stmt_RUN =>
            Run_Active_Program;
         when Stmt_QUIT | Stmt_END =>
            null;  --  Handled by loop termination in Execute.
         when Stmt_DELETE =>
            Ctx.Deleted := True;
            Debug_Trace ("DELETE: record marked", 2);
         when Stmt_BREAK =>
            if Stmt.Expr = null or else Is_True (Evaluate (Stmt.Expr)) then
               raise Break_Triggered;
            end if;
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
            Execute_Control_Flow (Stmt, Ctx);
         when Stmt_KEEP | Stmt_DROP | Stmt_HOLD | Stmt_UNHOLD | Stmt_UNSET
            | Stmt_RENAME | Stmt_ARRAY | Stmt_DIM | Stmt_NAMES | Stmt_LIST | Stmt_DISPLAY =>
            Execute_Metadata (Stmt);
         when Stmt_PROGRAM_DELETE =>
            Execute_Program_Delete (Stmt);
         when Stmt_USE | Stmt_SAVE | Stmt_SORT | Stmt_BY | Stmt_REPEAT
            | Stmt_SELECT_FILTER | Stmt_DIGITS | Stmt_RSEED | Stmt_NEW
            | Stmt_OPTIONS | Stmt_VANDALIZE =>
            Execute_Declarative (Stmt);
         when Stmt_SUBMIT | Stmt_SYSTEM | Stmt_OUTPUT | Stmt_FPATH =>
            Execute_IO (Stmt);
         pragma Warnings (Off, "choice is redundant");
         when others => null;
         pragma Warnings (On, "choice is redundant");
      end case;
   end Execute_Statement;

   procedure Execute_List (List : Statement_Access; Ctx : in out Step_Context; Boundary : Statement_Access := null) is
      Curr : Statement_Access := List;
   begin
      if List = null then return; end if;
      while Curr /= null and then Curr /= Boundary loop
         Execute_Statement (Curr, Ctx);
         exit when Ctx.Deleted;
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
   --  Group_Flags — compute BOG and EOG for one logical row.
   --
   --  Accepts the BY variable list as an explicit parameter so the function
   --  reads no global interpreter state; its result is fully determined by
   --  its arguments and the current table contents.  This is the seam that
   --  makes BY-group logic independently inspectable and testable.
   function Group_Flags (Logical_I     : Positive;
                         Logical_Count : Natural)
                         return Group_Flags_Result
   is
      Phys_Curr : constant Positive := SData.Table.Logical_To_Physical (Logical_I);
   begin
      --  During REPEAT the input table is empty; BY variables have no data to
      --  compare, so all generated records form one implicit group.
      if SData.Table.Row_Count = 0 then
         return (BOG => Logical_I = 1, EOG => Logical_I = Logical_Count);
      end if;
      return
        (BOG => (Logical_I = 1) or else
                not SData.Table.In_Same_Group
                      (Phys_Curr, SData.Table.Logical_To_Physical (Logical_I - 1)),
         EOG => (Logical_I = Logical_Count) or else
                not SData.Table.In_Same_Group
                      (Phys_Curr, SData.Table.Logical_To_Physical (Logical_I + 1)));
   end Group_Flags;

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
                        Debug_Trace ("SELECT → KEPT", 2);
                     else
                        Debug_Trace ("SELECT → DROPPED", 2);
                     end if;
                  end loop;
                  SData.Table.Set_Current_Record_Index (Saved_Physical);
                  SData.Table.Set_Index_Map (Passing (1 .. Count));
                  Debug_Trace ("SELECT → "
                               & Ada.Strings.Fixed.Trim (Natural'Image (Count), Ada.Strings.Both)
                               & " of "
                               & Ada.Strings.Fixed.Trim (Natural'Image (Total), Ada.Strings.Both)
                               & " records kept", 2);
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
                                  Global_Has_Write : Boolean;
                                  Ctx              : in out Step_Context;
                                  Pause_After      : Boolean := False;
                                  Action           : out Step_Action) is separate;

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
   end Commit_Step;

   --  Resolve_Expr_Indices — walk every Expr_Variable node reachable from the
   --  statement list and cache its PDV slot index.  Called once per RUN after
   --  Initialize_PDV has built the PDV_Index map, so the cache is valid for
   --  the entire data step without any per-row hash lookup.
   procedure Resolve_Expr_Indices (Start, Boundary : Statement_Access) is separate;

   --  Run_One_Step — executes the deferred statement list once per record.
   --  Start..Boundary is the slice of the statement list belonging to this RUN.
   procedure Run_One_Step (Start, Boundary : Statement_Access) is
      Global_Has_Write : constant Boolean := Has_Output_Statement (Start, Boundary);
      Num_Records      : constant Natural :=
         (if SData.Config.Runtime.Repeat_Active then SData.Config.Runtime.Repeat_Count
          else (if Row_Count > 0 then Row_Count else 1));
      Step_Mode : Boolean :=
         SData.Config.Debug_Level > 0 and then SData.IO.Is_Interactive;
      Act       : Step_Action := Action_Continue;
      Ctx       : Step_Context;
   begin
      Initialize_PDV;
      Resolve_Expr_Indices (Start, Boundary);
      SData.Table.Initialize_Output_Table;
      Rebuild_Filter_Map;
      declare
         Logical_Count : constant Natural :=
            (if SData.Table.Is_Filtered then SData.Table.Logical_Row_Count
             else Num_Records);
      begin
         for Logical_I in 1 .. Logical_Count loop
            Process_One_Record (Logical_I, Logical_Count, Start, Boundary,
                                Global_Has_Write, Ctx,
                                Pause_After => Step_Mode,
                                Action      => Act);
            if Act = Action_Run then
               Step_Mode := False;
            end if;
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
               Debug_Trace ("RUN complete: "
                            & RC (RC'First + 1 .. RC'Last)
                            & " records, "
                            & VC (VC'First + 1 .. VC'Last)
                            & " variables", 1);
               if not SData.Config.Quiet_Mode then
                  Put_Line ("RUN complete. " &
                            RC (RC'First + 1 .. RC'Last) & " records and " &
                            VC (VC'First + 1 .. VC'Last) & " variables processed.");
               end if;
            end;
            Step_Start := Current.Next;
         elsif Current.Kind /= Stmt_LET and then Current.Kind /= Stmt_SET
            and then Current.Kind /= Stmt_PRINT  and then Current.Kind /= Stmt_IF
            and then Current.Kind /= Stmt_FOR     and then Current.Kind /= Stmt_WHILE
            and then Current.Kind /= Stmt_LOOP_REPEAT and then Current.Kind /= Stmt_SELECT
            and then Current.Kind /= Stmt_DELETE  and then Current.Kind /= Stmt_WRITE
            and then Current.Kind /= Stmt_DIM     and then Current.Kind /= Stmt_BREAK
         then
            declare
               Outer_Ctx : Step_Context;
            begin
               Execute_Statement (Current, Outer_Ctx);
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