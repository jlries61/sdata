--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

with SData.Help;
with SData_Core.Commands;
with SData_Core.Table;     use SData_Core.Table;
with SData_Core.Values;    use SData_Core.Values;
with SData_Core.Variables; use SData_Core.Variables;
with SData_Core.Evaluator; use SData_Core.Evaluator;
with GNAT.Strings; use GNAT.Strings;
with SData.System;
with SData_Core.Statistics;
with SData.Parser; use SData.Parser;
with Ada.Streams.Stream_IO;
with Ada.Exceptions;
with SData_Core.Config;         use SData_Core.Config;
with SData_Core.Config.Runtime;
with SData_Core.IO;        use SData_Core.IO;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Containers.Vectors;
with Ada.Strings.Hash;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;    use Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with Ada.Text_IO.Unbounded_IO;
with SData.Transient_Table;
with SData.Merge;
with SData.Reserved_Keywords;
with SData_Core.File_IO;

--  SData.Interpreter — statement executor and data step engine.
--
--  Execution model (three tiers):
--    Declarative       Commands such as USE, BY, SELECT, REPEAT, SAVE, FPATH
--                      execute immediately and configure interpreter state.
--    Immediate         RUN, SORT, AGGREGATE, TRANSPOSE, NEW, NAMES, SYSTEM, HELP
--                      execute immediately but are not purely declarative.
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
   --  BY variable names are queried directly from SData_Core.Table (single source
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

   --  Count of deferred statements queued since the most recent RUN (or NEW).
   --  These are "pending / un-run": their per-record effect has not yet been
   --  committed to the table.  AGGREGATE refuses to run while any are pending
   --  (error #10) because it would otherwise silently aggregate the table
   --  without their effect; a RUN (which executes and resets the count) or NEW
   --  resolves the condition.  Maintained by BOTH execution paths — the REPL
   --  (Add_To_Active_Program / Run_Active_Program) and the batch linked-list
   --  walker in Execute — so #10 fires consistently in interactive and script
   --  modes.
   Pending_Deferred : Natural := 0;

   --  Program-buffer insertion cursor (REPL editing, issue #32).
   --  When Append_Mode is True, newly queued deferred statements append
   --  (default).  When False, they are inserted after line Insert_Point
   --  (0 = before line 1) and the cursor advances past each one.  Sticky:
   --  persists across RUN; reset to append only by USE, REPEAT, or NEW
   --  (Clear_Deferred_Program / Clear_Active_Program) or another INSERT.
   Append_Mode  : Boolean := True;
   Insert_Point : Natural := 0;

   function Is_Immediate (Kind : Statement_Kind) return Boolean is
   begin
      return Kind in
         Stmt_USE | Stmt_SAVE | Stmt_KEEP | Stmt_DROP |
         Stmt_RENAME | Stmt_NAMES | Stmt_LIST | Stmt_DISPLAY | Stmt_RUN | Stmt_QUIT | Stmt_END |
         Stmt_HOLD | Stmt_UNHOLD | Stmt_ARRAY | Stmt_DIM | Stmt_REPEAT | Stmt_NEW |
         Stmt_DIGITS | Stmt_HELP | Stmt_OUTPUT | Stmt_RSEED | Stmt_FPATH |
         Stmt_ECHO | Stmt_SORT | Stmt_BY | Stmt_SELECT_FILTER | Stmt_SUBMIT |
         Stmt_SYSTEM | Stmt_PROGRAM_DELETE | Stmt_OPTIONS | Stmt_AGGREGATE |
         Stmt_TRANSPOSE | Stmt_STATS | Stmt_PROGRAM_INSERT;
   end Is_Immediate;

   procedure Set_Interactive (Val : Boolean) is
   begin
      SData_Core.IO.Set_Interactive (Val);
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
   procedure Execute_Program_Insert  (Stmt : Statement_Access);
   procedure Execute_Declarative     (Stmt : Statement_Access);
   procedure Execute_IO           (Stmt : Statement_Access);
   function  Group_Flags (Logical_I     : Positive;
                          Logical_Count : Natural)
                          return Group_Flags_Result;
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

   --  Set of script files currently in the SUBMIT execution chain (for cycle detection).
   Submit_Chain : Name_Sets.Set;

   --  Maximum SUBMIT nesting depth.  Cycle detection (Submit_Chain) catches a
   --  file re-entering itself; this bounds a chain of *distinct* files so deep
   --  nesting cannot exhaust the stack.  Submit_Chain.Length is the current
   --  depth, since one entry is inserted per active SUBMIT level.
   Max_Submit_Depth : constant := 64;

   --  Multi-target SAVE registration. When non-empty, supersedes the
   --  single-target Save_File_* fields in SData_Core.Config.Runtime
   --  for the duration of the next RUN. Cleared by RUN flush, by an
   --  empty SAVE statement, or by NEW.
   type Save_Target is record
      File_Path : Unbounded_String;
      Alias     : Unbounded_String;        --  empty = no alias
      Opts      : SData.AST.Spec_Options;
   end record;
   type Save_Target_Access is access all Save_Target;
   package Save_Target_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Save_Target_Access);
   Registered_Saves : Save_Target_Vectors.Vector;

   --  Names of IN= variables created by the most recent multi-dataset USE.
   --  These are read-only Integer columns carrying provenance; user code is
   --  rejected from overwriting them via LET or SET.  Cleared on NEW or on
   --  any subsequent USE (single or multi-dataset).
   Readonly_IN_Names : Name_Sets.Set;

   procedure Register_Readonly_IN_Name (Name : String) is
   begin
      Readonly_IN_Names.Include (To_Upper (Name));
   end Register_Readonly_IN_Name;

   procedure Clear_Readonly_IN_Names is
   begin
      Readonly_IN_Names.Clear;
   end Clear_Readonly_IN_Names;

   function Is_Readonly_IN_Name (Name : String) return Boolean is
   begin
      return Readonly_IN_Names.Contains (To_Upper (Name));
   end Is_Readonly_IN_Name;

   --  Reset per record; set True by any WRITE that fires during the
   --  iteration; consulted at end-of-record to decide whether to
   --  auto-flush.
   Write_Fired_This_Iter : Boolean := False;

   --  Targets that received a WRITE in the current iteration.
   --  Populated by Execute_Statement (Stmt_WRITE); consumed and cleared by
   --  the end-of-record handler.  Stores Save_Target_Access values
   --  rather than indices so the handler doesn't need to re-look them up.
   package Pending_Write_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Save_Target_Access);
   Pending_Writes_This_Iter : Pending_Write_Vectors.Vector;

   --  Per-target accumulator buffers (Follow-on C: per-record routing).
   --  One buffer per registered SAVE target; populated record-by-record
   --  during the data step; flushed to disk at end of Commit_Step.
   type Target_Buffer is record
      Target      : Save_Target_Access;
      Buffer      : SData.Transient_Table.Table;
      Initialized : Boolean := False;  --  schema lazily set on first append
   end record;
   type Target_Buffer_Access is access all Target_Buffer;
   package Target_Buffer_Vectors is new Ada.Containers.Vectors
     (Index_Type => Positive, Element_Type => Target_Buffer_Access);
   Target_Buffers : Target_Buffer_Vectors.Vector;

   --  Initialize_Target_Buffers — create one empty Target_Buffer per
   --  registered SAVE target.  Called at the start of Run_One_Step when
   --  Registered_Saves is non-empty.  Schema is lazily populated on first
   --  record append (Append_Pdv_To_Buffer).
   procedure Initialize_Target_Buffers is
      procedure Free_TB is new Ada.Unchecked_Deallocation
        (Target_Buffer, Target_Buffer_Access);
   begin
      --  Clear any stale buffers first.
      for B of Target_Buffers loop
         declare Tmp : Target_Buffer_Access := B; begin Free_TB (Tmp); end;
      end loop;
      Target_Buffers.Clear;
      for T of Registered_Saves loop
         declare
            B : constant Target_Buffer_Access := new Target_Buffer;
         begin
            B.Target      := T;
            B.Initialized := False;
            Target_Buffers.Append (B);
         end;
      end loop;
   end Initialize_Target_Buffers;

   --  Append_Pdv_To_Buffer — copy the current PDV state into B.Buffer.
   --  On first call (B.Initialized = False) the PDV schema (all current PDV
   --  slot names, including LET-derived columns) is captured from
   --  SData_Core.Variables.Get_PDV_Names.  This mirrors the columns that
   --  Flush_PDV_To_Output would write to the output table.
   procedure Append_Pdv_To_Buffer (B : Target_Buffer_Access) is
      --  Get_PDV_Names returns a heap-allocated list of all current PDV slot
      --  names (including LET-derived columns), mirroring the columns that
      --  Flush_PDV_To_Output would write.  Freed at the end of this procedure.
      PDV_List : GNAT.Strings.String_List_Access :=
                    SData_Core.Variables.Get_PDV_Names;
      PDV_N    : constant Natural :=
                    (if PDV_List = null then 0 else PDV_List.all'Length);
   begin
      if not B.Initialized then
         --  Lazy schema initialization from the PDV name list.  Column type
         --  is inferred from the current slot value (same logic as
         --  Flush_PDV_To_Output).
         for I in 1 .. PDV_N loop
            declare
               Name : constant String := PDV_List.all (I).all;
               V    : constant SData_Core.Values.Value :=
                         SData_Core.Variables.Get_PDV_Value (I);
               Typ  : SData_Core.Table.Column_Type :=
                         SData_Core.Table.Col_Numeric;
            begin
               if V.Kind = SData_Core.Values.Val_Integer then
                  Typ := SData_Core.Table.Col_Integer;
               elsif V.Kind = SData_Core.Values.Val_String then
                  Typ := SData_Core.Table.Col_String;
               end if;
               B.Buffer.Add_Column (Name, Typ);
            end;
         end loop;
         B.Initialized := True;
      end if;
      --  Append a new row and populate it from the current PDV slot values.
      B.Buffer.Add_Row;
      declare
         R_Out : constant Positive :=
            SData.Transient_Table.Row_Count (B.Buffer);
      begin
         for I in 1 .. PDV_N loop
            declare
               Name : constant String := PDV_List.all (I).all;
               V    : constant SData_Core.Values.Value :=
                         SData_Core.Variables.Get_PDV_Value (I);
            begin
               if B.Buffer.Has_Column (Name) then
                  B.Buffer.Set_Value (R_Out, Name, V);
               end if;
            end;
         end loop;
      end;
      --  Free the heap-allocated String_List returned by Get_PDV_Names.
      GNAT.Strings.Free (PDV_List);
   end Append_Pdv_To_Buffer;

   --  Clear_Target_Buffers — free and clear the Target_Buffers vector.
   --  Called after Commit_Step write loop and by the NEW handler.
   procedure Clear_Target_Buffers is
      procedure Free_TB is new Ada.Unchecked_Deallocation
        (Target_Buffer, Target_Buffer_Access);
   begin
      for B of Target_Buffers loop
         declare Tmp : Target_Buffer_Access := B; begin Free_TB (Tmp); end;
      end loop;
      Target_Buffers.Clear;
   end Clear_Target_Buffers;

   --  Should_Write — evaluate a target's IF= expression.
   --  Returns True when the expression is absent or evaluates to non-zero /
   --  non-missing (i.e. the record should be routed to this target).
   function Should_Write (T : Save_Target_Access) return Boolean is
   begin
      if T.Opts.IF_Expr = null then
         return True;
      end if;
      return Is_True (Evaluate (T.Opts.IF_Expr));
   end Should_Write;

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

   --  Persistent SELECT filter expression now lives in
   --  SData_Core.Config.Runtime.Select_Filter_Expr, managed by
   --  SData_Core.Commands.Execute_SELECT.  The filter map is rebuilt from
   --  that expression at the start of every RUN so that it is always valid
   --  against the current table.



   procedure Add_To_Active_Program (Stmt : Statement_Access; Source : String := "") is
   begin
      if Stmt = null then return; end if;
      if Append_Mode then
         Active_Program_Vec.Append ((Stmt => Stmt, Source => To_Unbounded_String (Source)));
      else
         --  Insert after line Insert_Point (vector index Insert_Point + 1),
         --  then advance the cursor so consecutive inserts keep their order.
         Active_Program_Vec.Insert
           (Before   => Insert_Point + 1,
            New_Item => (Stmt => Stmt, Source => To_Unbounded_String (Source)));
         Insert_Point := Insert_Point + 1;
      end if;
      --  A newly queued deferred statement is pending until the next RUN.
      Pending_Deferred := Pending_Deferred + 1;
   end Add_To_Active_Program;

   procedure Clear_Deferred_Program is
   begin
      for E of Active_Program_Vec loop
         SData.AST.Free_Program (E.Stmt);
      end loop;
      Active_Program_Vec.Clear;
      Pending_Deferred := 0;
      Append_Mode  := True;
      Insert_Point := 0;
   end Clear_Deferred_Program;

   procedure Clear_Active_Program is
   begin
      SData_Core.Config.Runtime.Clear_Select_Filter;
      for E of Active_Program_Vec loop
         SData.AST.Free_Program (E.Stmt);
      end loop;
      Active_Program_Vec.Clear;
      Pending_Deferred := 0;
      Append_Mode  := True;
      Insert_Point := 0;
      SData_Core.Table.Clear_Index_Map;
      SData_Core.Table.Clear_By_Vars;
   end Clear_Active_Program;

   procedure Debug_Trace (Msg : String; Level : Positive) is
   begin
      if SData_Core.Config.Debug_Level >= Level then
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

            --  Restore every transiently-set Next pointer to null and free the
            --  synthetic cap.  This MUST run whether Execute returns normally
            --  or propagates an exception (e.g. a per-record type mismatch in
            --  the REPL, where the error is not continued-on): otherwise the
            --  vector entries stay chained together, and a later
            --  Clear_Active_Program walks one entry's Next chain and frees the
            --  following entries too, double-freeing them on the next loop
            --  iteration (issue #31 — NEW after a failed RUN crashing with
            --  "s-intman.adb:136 explicit raise").
            procedure Unchain is
            begin
               for I in 1 .. Last loop
                  Active_Program_Vec (I).Stmt.Next := null;
               end loop;
               SData.AST.Free_Program (Run_Cap);
            end Unchain;
         begin
            --  Transiently chain vector entries and cap with a synthetic
            --  Stmt_RUN so Execute's outer loop triggers deferred processing.
            --  The program persists across RUN; only NEW/USE/REPEAT replaces it.
            for I in 1 .. Last - 1 loop
               Active_Program_Vec (I).Stmt.Next :=
                  Active_Program_Vec (I + 1).Stmt;
            end loop;
            Active_Program_Vec (Last).Stmt.Next := Run_Cap;
            begin
               Execute (Active_Program_Vec (1).Stmt);
            exception
               when others =>
                  Unchain;
                  raise;
            end;
            Unchain;
         end;
      end if;
      --  The buffer has now been run; nothing is pending.
      Pending_Deferred := 0;
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
   --  Pass 1: if any Mod_Keep entry exists, gather the keep list into a
   --          Name_Vectors.Vector and delegate to Execute_KEEP (which drops
   --          every column NOT in the list).
   --  Pass 2: gather Mod_Drop entries and delegate to Execute_DROP.
   --  This ordering ensures KEEP and DROP can coexist without surprises.
   procedure Apply_Pending_Mods is
      Keep_Names : Name_Vectors.Vector;
      Drop_Names : Name_Vectors.Vector;
      Has_Keep   : Boolean := False;
      Curr       : Column_Mod_List := Pending_Mods;
   begin
      while Curr /= null loop
         case Curr.Kind is
            when Mod_Keep =>
               Has_Keep := True;
               Keep_Names.Append
                  (To_Unbounded_String (Curr.Name (1 .. Curr.Len)));
            when Mod_Drop =>
               Drop_Names.Append
                  (To_Unbounded_String (Curr.Name (1 .. Curr.Len)));
         end case;
         Curr := Curr.Next;
      end loop;

      if Has_Keep then
         SData_Core.Commands.Execute_KEEP (Keep_Names);
      end if;
      if not Drop_Names.Is_Empty then
         SData_Core.Commands.Execute_DROP (Drop_Names);
      end if;

      Clear_Pending_Mods;
   end Apply_Pending_Mods;

   procedure Clear_Registered_Saves is
   begin
      for T of Registered_Saves loop
         --  Opts shares ownership of access fields (Keep_Vars, Drop_Vars,
         --  Rename_Pairs, IF_Expr) with the AST. The AST owns and frees
         --  them via Free_Program; we just null our references.
         T.Opts.Keep_Vars     := null;
         T.Opts.Drop_Vars     := null;
         T.Opts.Rename_Pairs  := null;
         T.Opts.IF_Expr       := null;
         declare
            procedure Free is new Ada.Unchecked_Deallocation
              (Save_Target, Save_Target_Access);
            Tmp : Save_Target_Access := T;
         begin
            Free (Tmp);
         end;
      end loop;
      Registered_Saves.Clear;
   end Clear_Registered_Saves;

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
            Base := SData_Core.Config.Runtime.FPath_Use;
         elsif Cat = "SAVE" then
            Base := SData_Core.Config.Runtime.FPath_Save;
         elsif Cat = "SUBMIT" then
            Base := SData_Core.Config.Runtime.FPath_Submit;
         elsif Cat = "OUTPUT" then
            Base := SData_Core.Config.Runtime.FPath_Output;
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

   --  Render every column of the current (filtered) table to console, in the
   --  DISPLAY format (REC# header + one line per logical row).  Shared by the
   --  bare DISPLAY command (Execute_Metadata) and by STATS' default printout
   --  (Execute_Stats).  Declared here, before the Execute_Metadata stub, so the
   --  metadata subunit can call it.
   procedure Display_All_Columns is
      V    : Name_Vectors.Vector;
      Rows : constant Natural := SData_Core.Table.Logical_Row_Count;
   begin
      for I in 1 .. Column_Count loop
         V.Append (To_Unbounded_String (Column_Name (I)));
      end loop;

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
               Put (To_String_Formatted
                      (Get_Value_Upper (Phys_R, To_String (Name))) & " ");
            end loop;
            New_Line;
         end;
      end loop;
   end Display_All_Columns;

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
      --  Deleting queued lines may have removed pending (un-run) statements;
      --  the pending count can never exceed what remains in the buffer.
      Pending_Deferred :=
        Natural'Min (Pending_Deferred, Natural (Active_Program_Vec.Length));
      --  Keep the insertion cursor meaningful after deletion (issue #32).
      if not Append_Mode then
         declare
            Span : constant Natural := To - From + 1;  --  lines removed
            New_Last : constant Natural := Natural (Active_Program_Vec.Length);
         begin
            if Insert_Point >= To then
               Insert_Point := Insert_Point - Span;       --  cursor after span
            elsif Insert_Point >= From - 1 then
               Insert_Point := From - 1;                  --  cursor inside span
            end if;                                        --  else: before span, keep
            if Insert_Point > New_Last then
               Insert_Point := New_Last;                  --  final clamp
            end if;
         end;
      end if;
   end Execute_Program_Delete;

   --  Execute_Program_Insert — set the program-buffer insertion cursor.
   --  $/bare INSERT -> append mode.  INSERT n -> after line n (0 = start);
   --  n beyond the buffer warns and clamps to end (append).  Prints a
   --  one-line confirmation either way.
   procedure Execute_Program_Insert (Stmt : Statement_Access) is
      Last : constant Natural := Natural (Active_Program_Vec.Length);
   begin
      if Stmt.Insert_Bad then
         Put_Line_Error ("Warning: INSERT line number must be >= 0; "
                         & "insertion point unchanged.");
         return;
      elsif Stmt.Insert_At_End then
         Append_Mode  := True;
         Insert_Point := 0;
         Put_Line ("Insertion point set at end (append).");
      elsif Stmt.Insert_Line > Last then
         Put_Line_Error ("Warning: INSERT line" & Stmt.Insert_Line'Image
                         & " out of range (buffer has" & Last'Image
                         & " entries); inserting at end.");
         Append_Mode  := True;
         Insert_Point := 0;
         Put_Line ("Insertion point set at end (append).");
      elsif Stmt.Insert_Line = 0 then
         Append_Mode  := False;
         Insert_Point := 0;
         Put_Line ("Insertion point set at beginning.");
      else
         Append_Mode  := False;
         Insert_Point := Stmt.Insert_Line;
         Put_Line ("Insertion point set after line"
                   & Stmt.Insert_Line'Image & ".");
      end if;
   end Execute_Program_Insert;

   --  USE / SAVE / SORT / BY / REPEAT / SELECT (filter) / DIGITS / RSEED / NEW / OPTIONS.
   procedure Execute_Declarative (Stmt : Statement_Access) is separate;

   --  SUBMIT / SYSTEM / OUTPUT / FPATH — external interaction and I/O routing.
   procedure Execute_IO (Stmt : Statement_Access) is separate;

   --  Static semantic analyzer over a deferred-statement block [Start, Boundary).
   --  Pass 1 collects names introduced by the block; Pass 2 runs semantic checks
   --  (checks added in Tasks C2-C5).  No-op when Start = null or Start = Boundary.
   --  Not yet called (wired into Execute in a later task); suppress the warning.
   procedure Analyze_Deferred (Start, Boundary : Statement_Access) is separate;

   --  AGGREGATE (immediate).  Enforces error #10 (no pending deferred
   --  statements), converts the AST spec vector into the core spec type, and
   --  delegates the heavy lifting to SData_Core.Commands.Execute_AGGREGATE.
   procedure Execute_Aggregate (Stmt : Statement_Access) is
      Core_Specs : SData_Core.Commands.Aggregate_Spec_Vectors.Vector;
   begin
      --  #10 — there must be no pending (un-run) deferred statements.  A
      --  data-step program that has already been run may remain resident
      --  (RUN does not clear it); only statements queued since the last RUN
      --  block AGGREGATE, since those would otherwise be silently dropped.
      if Pending_Deferred > 0 then
         raise SData_Core.Script_Error with
           "AGGREGATE: pending program statements exist; issue RUN or NEW first";
      end if;

      for I in Stmt.Agg_List.First_Index .. Stmt.Agg_List.Last_Index loop
         declare
            A : constant SData.AST.Aggregate_Spec_Access := Stmt.Agg_List (I);
            C : SData_Core.Commands.Aggregate_Spec;
         begin
            C.Outvar      := To_Unbounded_String (A.Outvar (1 .. A.Outvar_Len));
            C.Fn_Name     := To_Unbounded_String (A.Fn_Name (1 .. A.Fn_Name_Len));
            C.Invar_Name  :=
              To_Unbounded_String (A.Invar_Name (1 .. A.Invar_Name_Len));
            C.Invar_Index := A.Invar_Index;
            case A.Invar_Kind is
               when Invar_Empty         =>
                  C.Invar_Kind := SData_Core.Commands.Invar_Empty;
               when Invar_Scalar        =>
                  C.Invar_Kind := SData_Core.Commands.Invar_Scalar;
               when Invar_Array_Element =>
                  C.Invar_Kind := SData_Core.Commands.Invar_Array_Element;
               when Invar_Array_Name    =>
                  C.Invar_Kind := SData_Core.Commands.Invar_Array_Name;
            end case;
            Core_Specs.Append (C);
         end;
      end loop;

      SData_Core.Commands.Execute_AGGREGATE (Core_Specs);

      declare
         RC : constant String := Natural'Image (SData_Core.Table.Row_Count);
         VC : constant String := Natural'Image (SData_Core.Table.Column_Count);
      begin
         Put_Line ("AGGREGATE complete. " &
                   RC (RC'First + 1 .. RC'Last) & " records and " &
                   VC (VC'First + 1 .. VC'Last) & " variables processed.");
      end;
   end Execute_Aggregate;

   --  TRANSPOSE (immediate).  Enforces error #12 (no pending deferred
   --  statements), converts the AST fields into the core Transpose_Options
   --  type, and delegates the heavy lifting to
   --  SData_Core.Commands.Execute_TRANSPOSE.
   procedure Execute_Transpose (Stmt : Statement_Access) is
      Opts : SData_Core.Commands.Transpose_Options;
   begin
      --  #12 — there must be no pending (un-run) deferred statements.
      if Pending_Deferred > 0 then
         raise SData_Core.Script_Error with
           "TRANSPOSE: pending program statements exist; issue RUN or NEW first";
      end if;

      --  Convert Keep_Vars Variable_List → Keep_List Name_Vectors.Vector.
      declare
         Curr : Variable_List := Stmt.Keep_Vars;
      begin
         while Curr /= null loop
            Opts.Keep_List.Append
              (To_Unbounded_String (Curr.Var.Start_Name (1 .. Curr.Var.Start_Len)));
            Curr := Curr.Next;
         end loop;
      end;

      --  Convert Drop_Vars Variable_List → Drop_List Name_Vectors.Vector.
      declare
         Curr : Variable_List := Stmt.Drop_Vars;
      begin
         while Curr /= null loop
            Opts.Drop_List.Append
              (To_Unbounded_String (Curr.Var.Start_Name (1 .. Curr.Var.Start_Len)));
            Curr := Curr.Next;
         end loop;
      end;

      --  Fixed-string fields → Unbounded_String.  Pass empty strings as-is;
      --  Execute_TRANSPOSE applies the defaults (_NAME_$ and _X_).
      Opts.Name_Col   :=
        To_Unbounded_String (Stmt.Name_Col (1 .. Stmt.Name_Col_Len));
      Opts.Id_Col     :=
        To_Unbounded_String (Stmt.Id_Col (1 .. Stmt.Id_Col_Len));
      Opts.Array_Name :=
        To_Unbounded_String (Stmt.Array_Col (1 .. Stmt.Array_Col_Len));
      Opts.Has_Id    := Stmt.Has_Id;
      Opts.Has_Array := Stmt.Has_Array;

      SData_Core.Commands.Execute_TRANSPOSE (Opts);

      declare
         RC : constant String := Natural'Image (SData_Core.Table.Row_Count);
         VC : constant String := Natural'Image (SData_Core.Table.Column_Count);
      begin
         Put_Line ("TRANSPOSE complete. " &
                   RC (RC'First + 1 .. RC'Last) & " records and " &
                   VC (VC'First + 1 .. VC'Last) & " variables processed.");
      end;
   end Execute_Transpose;

   --  STATS (immediate).  Enforces the pending-deferred guard, converts the
   --  AST lists into the core Stats_Options, delegates to
   --  SData_Core.Commands.Execute_STATS, then prints the result table via the
   --  DISPLAY renderer unless /NOPRINT was given.
   procedure Execute_Stats (Stmt : Statement_Access) is
      Opts : SData_Core.Commands.Stats_Options;
   begin
      if Pending_Deferred > 0 then
         raise SData_Core.Script_Error with
           "STATS: pending program statements exist; issue RUN or NEW first";
      end if;

      declare
         Curr : Variable_List := Stmt.Stats_Vars;
      begin
         while Curr /= null loop
            Opts.Var_List.Append
              (To_Unbounded_String (Curr.Var.Start_Name (1 .. Curr.Var.Start_Len)));
            Curr := Curr.Next;
         end loop;
      end;

      declare
         Curr : Variable_List := Stmt.Stats_Stats;
      begin
         while Curr /= null loop
            Opts.Stat_List.Append
              (To_Unbounded_String (Curr.Var.Start_Name (1 .. Curr.Var.Start_Len)));
            Curr := Curr.Next;
         end loop;
      end;

      SData_Core.Commands.Execute_STATS (Opts);

      if not Stmt.Stats_No_Print then
         Display_All_Columns;
      end if;

      declare
         RC : constant String := Natural'Image (SData_Core.Table.Row_Count);
         VC : constant String := Natural'Image (SData_Core.Table.Column_Count);
      begin
         Put_Line ("STATS complete. " &
                   RC (RC'First + 1 .. RC'Last) & " records and " &
                   VC (VC'First + 1 .. VC'Last) & " variables processed.");
      end;
   end Execute_Stats;

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
            --  Route to named SAVE targets (multi-target path) or fall back
            --  to legacy single-output flush (no Registered_Saves).
            --
            --  Helper: look up a target by alias (first) then file path
            --  (second), case-insensitive.  Returns null when not found.
            declare
               function Find_Target (Name : String) return Save_Target_Access is
                  U : constant String := To_Upper (Name);
               begin
                  for T of Registered_Saves loop
                     if Length (T.Alias) > 0
                        and then To_Upper (To_String (T.Alias)) = U
                     then
                        return T;
                     end if;
                  end loop;
                  for T of Registered_Saves loop
                     if To_Upper (To_String (T.File_Path)) = U then
                        return T;
                     end if;
                  end loop;
                  return null;
               end Find_Target;

               --  Helper: enqueue T for the end-of-record writer.
               procedure Note_Target_Write (T : Save_Target_Access) is
               begin
                  Pending_Writes_This_Iter.Append (T);
               end Note_Target_Write;

            begin
               if Natural (Registered_Saves.Length) = 0 then
                  --  Legacy single-SAVE path — unchanged behaviour.
                  SData_Core.Variables.Flush_PDV_To_Output;
               else
                  --  Multi-target path.
                  if Stmt.Write_Targets = null then
                     --  Bare WRITE: write to every registered target that
                     --  passes its IF= filter.
                     for T of Registered_Saves loop
                        if Should_Write (T) then
                           Note_Target_Write (T);
                        end if;
                     end loop;
                  else
                     --  Named targets: WRITE target1 [, target2 ...].
                     declare
                        Cur : Variable_List := Stmt.Write_Targets;
                     begin
                        while Cur /= null loop
                           declare
                              Name : constant String :=
                                 Cur.Var.Start_Name (1 .. Cur.Var.Start_Len);
                              T    : constant Save_Target_Access :=
                                 Find_Target (Name);
                           begin
                              if T = null then
                                 raise SData_Core.Script_Error
                                    with "WRITE: target not registered: " & Name;
                              end if;
                              if Should_Write (T) then
                                 Note_Target_Write (T);
                              end if;
                           end;
                           Cur := Cur.Next;
                        end loop;
                     end;
                  end if;
               end if;

               Write_Fired_This_Iter := True;
               SData_Core.Table.Set_Record_Explicitly_Written (True);
            end;
         when Stmt_ECHO =>
            SData_Core.IO.Set_Local_Echo (Stmt.Echo_State);
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
         when Stmt_PROGRAM_INSERT =>
            Execute_Program_Insert (Stmt);
         when Stmt_AGGREGATE =>
            Execute_Aggregate (Stmt);
         when Stmt_TRANSPOSE =>
            Execute_Transpose (Stmt);
         when Stmt_STATS =>
            Execute_Stats (Stmt);
         when Stmt_USE | Stmt_SAVE | Stmt_SORT | Stmt_BY | Stmt_REPEAT
            | Stmt_SELECT_FILTER | Stmt_DIGITS | Stmt_RSEED | Stmt_NEW
            | Stmt_OPTIONS =>
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
      Phys_Curr : constant Positive := SData_Core.Table.Logical_To_Physical (Logical_I);
   begin
      --  During REPEAT the input table is empty; BY variables have no data to
      --  compare, so all generated records form one implicit group.
      if SData_Core.Table.Row_Count = 0 then
         return (BOG => Logical_I = 1, EOG => Logical_I = Logical_Count);
      end if;
      return
        (BOG => (Logical_I = 1) or else
                not SData_Core.Table.In_Same_Group
                      (Phys_Curr, SData_Core.Table.Logical_To_Physical (Logical_I - 1)),
         EOG => (Logical_I = Logical_Count) or else
                not SData_Core.Table.In_Same_Group
                      (Phys_Curr, SData_Core.Table.Logical_To_Physical (Logical_I + 1)));
   end Group_Flags;

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

   --  Convert_Variable_List — helper used by both Execute_Declarative (USE
   --  multi-dataset) and Commit_Step (SAVE projection).  Converts an AST
   --  Variable_List linked list to a Transient_Table Name_Vectors.Vector.
   procedure Convert_Variable_List
     (V    : SData.AST.Variable_List;
      Outv : in out SData.Transient_Table.Name_Vectors.Vector)
   is
      Cur : SData.AST.Variable_List := V;
   begin
      while Cur /= null loop
         Outv.Append
           (To_Unbounded_String
              (Cur.Var.Start_Name (1 .. Cur.Var.Start_Len)));
         Cur := Cur.Next;
      end loop;
   end Convert_Variable_List;

   --  Convert_Rename_List — convert an AST Rename_List linked list to a
   --  Transient_Table Rename_Map_Vectors.Vector.
   procedure Convert_Rename_List
     (R    : SData.AST.Rename_List;
      Outv : in out SData.Transient_Table.Rename_Map_Vectors.Vector)
   is
      Cur : SData.AST.Rename_List := R;
   begin
      while Cur /= null loop
         Outv.Append
           ((Old_Name => To_Unbounded_String
                           (Cur.Old_Name (1 .. Cur.Old_Len)),
             New_Name => To_Unbounded_String
                           (Cur.New_Name (1 .. Cur.New_Len))));
         Cur := Cur.Next;
      end loop;
   end Convert_Rename_List;

   --  Commit_Step — finalizes a completed data step: commits the output table,
   --  resets filter/repeat state, applies pending column modifications, and
   --  writes to disk if a SAVE was deferred until after RUN.
   procedure Commit_Step is
   begin
      SData_Core.Table.Set_Logical_Record_Index (0);
      SData_Core.Table.Commit_Output_Table;
      --  The committed table is a new physical row set; clear the stale map
      --  so it is rebuilt fresh at the start of the next RUN.
      SData_Core.Table.Clear_Index_Map;
      --  REPEAT generates records for exactly one RUN.  Subsequent RUNs
      --  must iterate the committed table, not re-use Repeat_Count.
      SData_Core.Commands.Execute_REPEAT (0);
      Set_Current_Record_Index (0);
      Apply_Pending_Mods;
      --  Delegate the end-of-step shared work (filter rebuild against the
      --  newly committed table, plus pending-SAVE flush) to sdata-core so
      --  the same semantics are available to other front ends.
      SData_Core.Commands.Execute_Commit_Step;

      --  Multi-target SAVE flush (Follow-on C): per-record routing.
      --  Each target's buffer was filled during the data step by
      --  Process_One_Record.  Here we write each buffer to disk, applying
      --  per-target KEEP/DROP/RENAME projection (Follow-on B), then restore
      --  the global table to the committed baseline.
      --
      --  Per spec §5: targets with empty (or uninitialized) buffers still
      --  produce a header-only file.  For an uninitialized buffer (no schema
      --  captured because no record was routed there), we fall back to the
      --  committed table's schema with zero data rows.
      if Natural (Registered_Saves.Length) > 0 then
         declare
            --  Committed table snapshot; used to restore the global table
            --  after the write loop.
            Baseline : constant SData.Transient_Table.Table :=
                          SData.Transient_Table.Snapshot_From_Current;

            --  Build a zero-row table that mirrors the committed table's
            --  schema.  Used as fallback for targets whose IF= condition was
            --  never satisfied (buffer uninitialized) so that the output
            --  file receives a header-only file rather than all rows.
            Empty_Schema : SData.Transient_Table.Table;
         begin
            for I in 1 .. SData_Core.Table.Column_Count loop
               declare
                  CName : constant String := SData_Core.Table.Column_Name (I);
               begin
                  Empty_Schema.Add_Column
                    (CName, SData_Core.Table.Get_Column_Type (CName));
               end;
            end loop;

            for B of Target_Buffers loop
               declare
                  T          : constant Save_Target_Access := B.Target;
                  Raw_Path   : constant String := To_String (T.File_Path);
                  Full       : constant String := Full_Path (Raw_Path, "SAVE");
                  Eff_Fmt    : constant SData_Core.Config.Format_Type :=
                     (if T.Opts.Format_Specified
                      then T.Opts.Fmt_Override
                      else SData_Core.Config.Output_Format);
                  Eff_DLM    : constant String :=
                     (if T.Opts.DLM_Len > 0
                      then T.Opts.DLM_Val (1 .. T.Opts.DLM_Len)
                      else SData_Core.Config.Runtime.Options_CSVDLM
                              (1 .. SData_Core.Config.Runtime.Options_CSVDLM_Len));
                  Eff_Header : constant Boolean :=
                     (if T.Opts.Header_Specified
                      then T.Opts.Header_Val
                      else SData_Core.Config.Runtime.Options_Header);
                  Eff_Charset : constant String :=
                     (if T.Opts.Charset_Len > 0
                      then T.Opts.Charset_Val (1 .. T.Opts.Charset_Len)
                      else SData_Core.Config.Runtime.Options_CHARSET
                              (1 .. SData_Core.Config.Runtime.Options_CHARSET_Len));
                  Sheet      : constant String :=
                     T.Opts.Sheet_Name (1 .. T.Opts.Sheet_Name_Len);
                  --  Use the per-target accumulator buffer as the output
                  --  source.  Fall back to Empty_Schema (header-only) when
                  --  the buffer was never initialized (no records routed).
                  Projected  : SData.Transient_Table.Table :=
                     (if B.Initialized then B.Buffer else Empty_Schema);
               begin
                  --  KEEP and DROP are mutually exclusive; guard is redundant
                  --  with validation at SAVE-parse time but enforced here too.
                  if T.Opts.Keep_Vars /= null
                     and then T.Opts.Drop_Vars /= null
                  then
                     raise SData_Core.Script_Error
                       with "KEEP and DROP cannot both be specified on SAVE";
                  end if;

                  --  Apply RENAME → KEEP → DROP on the buffer copy.
                  if T.Opts.Rename_Pairs /= null then
                     declare
                        Pairs : SData.Transient_Table.Rename_Map_Vectors.Vector;
                     begin
                        Convert_Rename_List (T.Opts.Rename_Pairs, Pairs);
                        Projected.Apply_Rename (Pairs);
                     end;
                  end if;

                  if T.Opts.Keep_Vars /= null then
                     declare
                        Names : SData.Transient_Table.Name_Vectors.Vector;
                     begin
                        Convert_Variable_List (T.Opts.Keep_Vars, Names);
                        Projected.Apply_Keep (Names);
                     end;
                  end if;

                  if T.Opts.Drop_Vars /= null then
                     declare
                        Names : SData.Transient_Table.Name_Vectors.Vector;
                     begin
                        Convert_Variable_List (T.Opts.Drop_Vars, Names);
                        Projected.Apply_Drop (Names);
                     end;
                  end if;

                  --  Install the projected buffer as the active table, write,
                  --  then restore baseline before the next iteration.
                  SData.Transient_Table.Install_To_Current (Projected);
                  begin
                     SData_Core.File_IO.Open_Output
                       (File_Name       => Full,
                        Fmt             => Eff_Fmt,
                        Sheet_Name      => Sheet,
                        Delimiter       => Eff_DLM,
                        Write_Header    => Eff_Header,
                        Allow_Overwrite => SData_Core.Config.Runtime.Options_SAVEOVERWRT,
                        Charset         => Eff_Charset);
                     if not SData_Core.Config.Quiet_Mode then
                        Put_Line ("Dataset saved: " & Full);
                     end if;
                  exception
                     when SData_Core.File_IO.Save_Refused => null;
                  end;
                  SData.Transient_Table.Install_To_Current (Baseline);
               end;
            end loop;
         end;
         Clear_Target_Buffers;
         Clear_Registered_Saves;
      end if;

      Write_Fired_This_Iter    := False;
      Pending_Writes_This_Iter.Clear;
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
         (if SData_Core.Config.Runtime.Repeat_Active then SData_Core.Config.Runtime.Repeat_Count
          else (if Row_Count > 0 then Row_Count else 1));
      Step_Mode : Boolean :=
         SData_Core.Config.Debug_Level > 0 and then SData_Core.IO.Is_Interactive;
      Act       : Step_Action := Action_Continue;
      Ctx       : Step_Context;
   begin
      Initialize_PDV;
      Resolve_Expr_Indices (Start, Boundary);
      SData_Core.Table.Initialize_Output_Table;
      SData_Core.Commands.Execute_Rebuild_Filter;
      --  If multi-target SAVE is active, allocate per-target accumulator
      --  buffers.  Records are routed into these during Process_One_Record;
      --  Commit_Step writes each buffer to disk and then clears them.
      if Natural (Registered_Saves.Length) > 0 then
         Initialize_Target_Buffers;
      end if;
      declare
         Logical_Count : constant Natural :=
            (if SData_Core.Table.Is_Filtered then SData_Core.Table.Logical_Row_Count
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
            SData_Core.IO.Show_Progress ("RUN", Logical_I);
         end loop;
         SData_Core.IO.Show_Progress ("RUN", Logical_Count, Final => True);
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
            --  Entry-time semantic checks over the just-completed deferred
            --  body (both batch and interactive, via Run_Active_Program's
            --  synthetic RUN cap).  A rejection raises SData_Core.Script_Error
            --  before any record is processed.
            Analyze_Deferred (Step_Start, Current);
            Run_One_Step (Step_Start, Current);
            declare
               RC : constant String := Natural'Image (SData_Core.Table.Row_Count);
               VC : constant String := Natural'Image (SData_Core.Table.Column_Count);
            begin
               Debug_Trace ("RUN complete: "
                            & RC (RC'First + 1 .. RC'Last)
                            & " records, "
                            & VC (VC'First + 1 .. VC'Last)
                            & " variables", 1);
               if not SData_Core.Config.Quiet_Mode then
                  Put_Line ("RUN complete. " &
                            RC (RC'First + 1 .. RC'Last) & " records and " &
                            VC (VC'First + 1 .. VC'Last) & " variables processed.");
               end if;
            end;
            --  Deferred body just ran; nothing pending until more is queued.
            Pending_Deferred := 0;
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
               --  A new input source cancels any deferred statements queued
               --  before it (design.md:960): advance the deferred-block start
               --  past this statement and drop the pending count so the next
               --  RUN's data step excludes them.
               if Current.Kind = Stmt_USE or else Current.Kind = Stmt_REPEAT then
                  Step_Start := Current.Next;
                  Pending_Deferred := 0;
               end if;
            exception
               when E : Script_Error | SData_Core.Script_Error =>
                  if SData_Core.Config.Continue_On_Error then
                     Put_Line_Error ("Error: " & Ada.Exceptions.Exception_Message (E));
                     SData_Core.Commands.Execute_Record_Error
                        (1, SData_Core.Table.Get_Current_Record_Index);
                  else raise; end if;
               when E : others =>
                  if SData_Core.Config.Continue_On_Error then
                     Put_Line_Error ("Error: " & Ada.Exceptions.Exception_Message (E));
                     SData_Core.Commands.Execute_Record_Error
                        (1, SData_Core.Table.Get_Current_Record_Index);
                  else raise Script_Error with Ada.Exceptions.Exception_Message (E); end if;
            end;
         else
            --  A deferred statement (LET/SET/PRINT/IF/...) skipped by this
            --  walker: it runs later at the next RUN.  Until then it is pending,
            --  which AGGREGATE's #10 guard observes.
            Pending_Deferred := Pending_Deferred + 1;
         end if;
         Current := Current.Next;
      end loop;
   end Execute;

end SData.Interpreter;