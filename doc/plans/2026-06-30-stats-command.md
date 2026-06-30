# STATS Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `STATS` command (SData's PROC MEANS analogue) that computes summary statistics per numeric variable, prints them, and replaces the in-memory table — reusing the AGGREGATE aggregate-function machinery.

**Architecture:** STATS is an **immediate** command. Computation reuses the registered aggregate handlers (`Eval.Call_Function` + `Is_Aggregate`/`Lookup`) and a **shared BY-group-scan helper** factored out of `Execute_AGGREGATE` (approach A). The result table — schema `[BY vars] + _NAME_$ + one column per statistic`, one row per (BY group × variable) — is built via the standard build-and-swap path and swapped into the in-memory table; a pending SAVE is flushed; SELECT/BY are cleared. The sdata interpreter layer adds the lexer token, AST node, parser, dispatch + pending-deferred guard, and prints the result via the existing DISPLAY renderer unless `/NOPRINT`.

**Tech Stack:** Ada 2012, GNAT/GPRbuild, Alire. Two crates: `~/Develop/sdata-core` (shared library — computation/build-swap) and `~/Develop/sdata` (interpreter — lexer/AST/parser/dispatch/HELP/docs). `~/Develop/data-vandal` is a third consumer that must stay green though untouched.

## Global Constraints

- **Spec:** `doc/specs/2026-06-30-stats-command-design.md` is the contract. Every task implements part of it.
- **sdata-core changes are additive** → patch bump `0.1.18 → 0.1.19`; consumer floor `^0.1.16` is **unchanged** (do not edit the `sdata_core = "^0.1.16"` constraint in `sdata/alire.toml` or `data-vandal/alire.toml`).
- **sdata gets a minor bump** `0.11.1 → 0.12.0` (new command), via `scripts/bump-version.sh`.
- **Mandatory three-way local gate before any src-touching commit:** `cd ~/Develop/sdata-core && alr build` → `cd ~/Develop/sdata && make check` (all integration tests green) → `cd ~/Develop/data-vandal && make check` (must stay green).
- **Never use `--no-verify`.** All integration tests must pass before committing.
- **User-facing surface trio must stay in sync** (CLAUDE.md): built-in HELP (+ `tests/expected/help_all.out` snapshot), man page `man/man1/sdata.1`, design doc `doc/design.md`.
- **Default statistics** when `/STATS` omitted: `N MIN MEAN MAX STD`. **Allowed set** = registered aggregates: `N NMISS SUM MEAN STD VAR MIN MAX GMEAN HMEAN MEDIAN`.
- **Stat column types:** `N` and `NMISS` → `Col_Integer`; every other statistic → `Col_Numeric`.
- **`_NAME_$`** holds the analysis-variable name. No `/NAME=` override in v1.
- **STATS becomes a reserved keyword.**

---

### Task 1: Extract shared BY-group-scan helper in sdata-core (approach A)

Factor the group-boundary scan and the per-group value gather out of `Execute_AGGREGATE` into private helpers in `sdata_core-commands.adb`, so `Execute_STATS` can reuse them. **Behavior of AGGREGATE must be byte-for-byte identical** — this is a pure refactor, verified by the existing AGGREGATE integration tests.

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-commands.adb` (Execute_AGGREGATE ~632–1029; add helpers before it)

**Interfaces:**
- Produces (private to the package body, visible to other `Execute_*` in the body):
  - `package Group_Vectors is new Ada.Containers.Vectors (Positive, Row_Vectors.Vector, Row_Vectors."=");`
  - `function Collect_Groups return Group_Vectors.Vector;` — rebuilds the SELECT filter map, walks the logical view, and returns consecutive BY-key groups (each a `Row_Vectors.Vector` of physical row indices). Whole filtered table is one group when `By_Var_Count = 0`.
  - `function Group_Values (Rows : Row_Vectors.Vector; Col : String) return Eval.Value_Array;` — gathers one column's values across a group's physical rows.

- [ ] **Step 1: Confirm the AGGREGATE baseline is green (regression anchor)**

Run: `cd ~/Develop/sdata-core && alr build && cd ~/Develop/sdata && make check 2>&1 | tail -5`
Expected: build OK; all integration tests pass (the AGGREGATE `aggregate_*.cmd` tests are the regression anchor for this task).

- [ ] **Step 2: Add the shared helpers**

In `~/Develop/sdata-core/src/sdata_core-commands.adb`, just before `procedure Execute_AGGREGATE`, add (note `Row_Vectors` is already declared in the body):

```ada
   --  Shared BY-group scan (used by AGGREGATE and STATS).  A "group" is a
   --  vector of physical row indices.  Reflects the active SELECT filter via
   --  Rebuild_Filter_Map and partitions the logical view into consecutive
   --  BY-key runs (the whole filtered table is one group when no BY is active).
   package Group_Vectors is new Ada.Containers.Vectors
     (Positive, Row_Vectors.Vector, Row_Vectors."=");

   function Collect_Groups return Group_Vectors.Vector is
      Groups : Group_Vectors.Vector;
      Group  : Row_Vectors.Vector;
      Prev_P : Positive := 1;
   begin
      Rebuild_Filter_Map;
      for L in 1 .. Tbl.Logical_Row_Count loop
         declare
            P : constant Positive := Tbl.Logical_To_Physical (L);
         begin
            if L = 1 then
               Group.Append (P);
            elsif Tbl.By_Var_Count = 0
              or else Tbl.In_Same_Group (P, Prev_P)
            then
               Group.Append (P);
            else
               Groups.Append (Group);
               Group.Clear;
               Group.Append (P);
            end if;
            Prev_P := P;
         end;
      end loop;
      if not Group.Is_Empty then
         Groups.Append (Group);
      end if;
      return Groups;
   end Collect_Groups;

   --  Gather one column's values across a group's physical rows.
   function Group_Values (Rows : Row_Vectors.Vector; Col : String)
      return Eval.Value_Array
   is
      A : Eval.Value_Array (1 .. Integer (Rows.Length));
      I : Positive := 1;
   begin
      for P of Rows loop
         A (I) := Tbl.Get_Value (P, Col);
         I := I + 1;
      end loop;
      return A;
   end Group_Values;
```

If `Execute_AGGREGATE` already defines a nested `Group_Values`, delete the nested copy and use this shared one (rename collision: remove the local).

- [ ] **Step 3: Refactor Execute_AGGREGATE to use Collect_Groups**

In `Execute_AGGREGATE`, replace the inline `for L in 1 .. Tbl.Logical_Row_Count loop … Emit_Group(Group) …` scan (and its preceding `Rebuild_Filter_Map;`) with:

```ada
      Tbl.Initialize_Output_Table;
      for D of Descs loop
         Tbl.Add_Output_Column (To_String (D.Name), D.Ctype);
      end loop;

      for G of Collect_Groups loop
         Emit_Group (G);
      end loop;
```

Keep `Emit_Group` as-is (it now calls the shared `Group_Values`). Leave validation, post-commit (Commit_Output_Table / Register_Subscripted_Columns / SAVE flush / Execute_SELECT(null) / Clear_By_Vars) unchanged.

- [ ] **Step 4: Build sdata-core and run the regression**

Run: `cd ~/Develop/sdata-core && alr build && cd ~/Develop/sdata && make check 2>&1 | tail -5`
Expected: build OK; **all** integration tests pass with no diffs (AGGREGATE behavior unchanged).

- [ ] **Step 5: Confirm data-vandal still builds (additive-only check)**

Run: `cd ~/Develop/data-vandal && make check 2>&1 | tail -3`
Expected: green (data-vandal does not call the new helpers; this confirms no accidental public-surface change).

- [ ] **Step 6: Commit**

```bash
cd ~/Develop/sdata-core
git add src/sdata_core-commands.adb
git commit -m "refactor(commands): extract shared Collect_Groups/Group_Values for AGGREGATE

Pure refactor preparing for STATS reuse (approach A). AGGREGATE behavior
unchanged; verified by the full sdata integration suite.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Add Stats_Options + Execute_STATS to sdata-core

Add the public `Stats_Options` type and `Execute_STATS` procedure. This is the computational core: resolve variables/stats, validate, build the row-per-(group×variable) table, swap it in, flush SAVE, clear SELECT/BY.

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-commands.ads` (after `Execute_TRANSPOSE`, ~line 255)
- Modify: `~/Develop/sdata-core/src/sdata_core-commands.adb` (after `Execute_TRANSPOSE` body)

**Interfaces:**
- Consumes: `Collect_Groups`, `Group_Values` (Task 1); `Eval.Is_Aggregate`, `Eval.Lookup`, `Eval.Call_Function`, `Eval.Value_Array`; `Tbl.*` accessors; `Vars.Register_Subscripted_Columns`, `Vars.Has_Array`, `Vars.Get_Array_Bounds`, `Vars.Get_Array_Element_Column`, `Vars.Refresh_PDV_Names`.
- Produces:
  - `type Stats_Options is record Var_List, Stat_List : SData_Core.Table.Name_Vectors.Vector; end record;`
  - `procedure Execute_STATS (Options : Stats_Options);`

- [ ] **Step 1: Declare the public API in the spec**

In `~/Develop/sdata-core/src/sdata_core-commands.ads`, after the `Execute_TRANSPOSE` declaration (~line 255), add:

```ada
   ----------------------------------------------------------------
   --  STATS — compute summary statistics for the chosen (or, by default,
   --  all numeric) variables, one row per (active BY group x variable),
   --  with one column per requested statistic.  Reuses the registered
   --  aggregate functions.  Mirrors AGGREGATE's build-and-swap: on success
   --  the fresh stats table replaces the in-memory table, a pending SAVE is
   --  flushed, and the active SELECT and BY are cleared.  All validation
   --  precedes any side effect.  Printing is the caller's concern.
   --
   --    Var_List   analysis variables; empty => all numeric columns (minus BY).
   --               A whole-array base name expands to its elements.
   --    Stat_List  registered aggregate names; empty => N MIN MEAN MAX STD.
   type Stats_Options is record
      Var_List  : SData_Core.Table.Name_Vectors.Vector;
      Stat_List : SData_Core.Table.Name_Vectors.Vector;
   end record;

   procedure Execute_STATS (Options : Stats_Options);
```

- [ ] **Step 2: Implement Execute_STATS in the body**

In `~/Develop/sdata-core/src/sdata_core-commands.adb`, after the `Execute_TRANSPOSE` body, add. (Adjust the local package renames — `Tbl`, `Eval`, `Vars`, `Config` — to match the renames already used at the top of the body; reuse the same `Flush_Pending_Save` and `Execute_SELECT` helpers AGGREGATE uses.)

```ada
   procedure Execute_STATS (Options : Stats_Options) is
      use Ada.Strings.Unbounded;

      type Var_Rec is record
         Name    : Unbounded_String;
         Is_Char : Boolean;
      end record;
      package Var_Recs is new Ada.Containers.Vectors (Positive, Var_Rec);

      Stats : SData_Core.Table.Name_Vectors.Vector;
      Vlist : Var_Recs.Vector;

      function Is_By (Name : String) return Boolean is
      begin
         for I in 1 .. Tbl.By_Var_Count loop
            if To_Upper (Tbl.By_Var_Name (I)) = To_Upper (Name) then
               return True;
            end if;
         end loop;
         return False;
      end Is_By;

      procedure Add_Var (Name : String) is
      begin
         Vlist.Append
           ((Name    => To_Unbounded_String (Name),
             Is_Char => Tbl."=" (Tbl.Get_Column_Type (Name), Tbl.Col_String)));
      end Add_Var;
   begin
      --  1. Resolve the statistic list (default N MIN MEAN MAX STD).
      if Options.Stat_List.Is_Empty then
         Stats.Append (To_Unbounded_String ("N"));
         Stats.Append (To_Unbounded_String ("MIN"));
         Stats.Append (To_Unbounded_String ("MEAN"));
         Stats.Append (To_Unbounded_String ("MAX"));
         Stats.Append (To_Unbounded_String ("STD"));
      else
         Stats := Options.Stat_List;
      end if;
      for S of Stats loop
         if not Eval.Is_Aggregate (To_String (S)) then
            raise SData_Core.Script_Error with
              "STATS: '" & To_String (S)
              & "' is not a registered aggregate function";
         end if;
      end loop;

      --  2. Resolve the variable list.
      if Options.Var_List.Is_Empty then
         for I in 1 .. Tbl.Column_Count loop
            declare
               Name : constant String := Tbl.Column_Name (I);
            begin
               if not Is_By (Name)
                 and then not Tbl."=" (Tbl.Get_Column_Type (Name), Tbl.Col_String)
               then
                  Add_Var (Name);
               end if;
            end;
         end loop;
      else
         for V of Options.Var_List loop
            declare
               Name : constant String := To_String (V);
            begin
               if Vars.Has_Array (Name) then
                  declare
                     Lo, Hi : Integer;
                  begin
                     Vars.Get_Array_Bounds (Name, Lo, Hi);
                     for K in Lo .. Hi loop
                        Add_Var (Vars.Get_Array_Element_Column (Name, K));
                     end loop;
                  end;
               elsif Tbl.Has_Column (Name) then
                  Add_Var (Name);
               else
                  raise SData_Core.Script_Error with
                    "STATS: unknown variable '" & Name & "'";
               end if;
            end;
         end loop;
      end if;

      if Vlist.Is_Empty then
         raise SData_Core.Script_Error with
           "STATS: no variables to summarize";
      end if;

      --  3. Type rule: a character variable is valid only if every requested
      --     statistic accepts character input (i.e. only N / NMISS).
      for V of Vlist loop
         if V.Is_Char then
            for S of Stats loop
               if not Eval.Lookup (To_String (S)).Accepts_Character then
                  raise SData_Core.Script_Error with
                    "STATS: statistic '" & To_String (S)
                    & "' cannot be applied to character variable '"
                    & To_String (V.Name) & "'";
               end if;
            end loop;
         end if;
      end loop;

      --  4. Build the output schema: BY vars + _NAME_$ + one col per stat.
      Tbl.Initialize_Output_Table;
      for I in 1 .. Tbl.By_Var_Count loop
         Tbl.Add_Output_Column
           (Tbl.By_Var_Name (I), Tbl.Get_Column_Type (Tbl.By_Var_Name (I)));
      end loop;
      Tbl.Add_Output_Column ("_NAME_$", Tbl.Col_String);
      for S of Stats loop
         declare
            U : constant String := To_Upper (To_String (S));
         begin
            Tbl.Add_Output_Column
              (U, (if U = "N" or else U = "NMISS"
                   then Tbl.Col_Integer else Tbl.Col_Numeric));
         end;
      end loop;

      --  5. Scan groups; one output row per (group x variable).
      for G of Collect_Groups loop
         declare
            First_Phys : constant Positive := G.First_Element;
         begin
            for V of Vlist loop
               Tbl.Add_Output_Row;
               declare
                  R   : constant Positive := Tbl.Output_Row_Count;
                  Col : Positive := 1;
               begin
                  for I in 1 .. Tbl.By_Var_Count loop
                     Tbl.Set_Output_Value_By_Col
                       (R, Col, Tbl.Get_Value (First_Phys, Tbl.By_Var_Name (I)));
                     Col := Col + 1;
                  end loop;
                  Tbl.Set_Output_Value_By_Col
                    (R, Col, (Kind => Val_String, Str_Val => V.Name));
                  Col := Col + 1;
                  for S of Stats loop
                     Tbl.Set_Output_Value_By_Col
                       (R, Col,
                        Eval.Call_Function
                          (To_String (S),
                           Group_Values (G, To_String (V.Name))));
                     Col := Col + 1;
                  end loop;
               end;
            end loop;
         end;
      end loop;

      --  6. Commit, re-register arrays, flush SAVE, clear SELECT/BY.
      Tbl.Commit_Output_Table;
      Tbl.Clear_Index_Map;
      Vars.Refresh_PDV_Names;
      Vars.Register_Subscripted_Columns;

      if SData_Core.Config.Runtime.Save_File_Active then
         begin
            Flush_Pending_Save;
         exception
            when E : others =>
               raise SData_Core.Script_Error with
                 "STATS: SAVE flush failed: "
                 & Ada.Exceptions.Exception_Message (E);
         end;
      end if;

      Execute_SELECT (null);
      Tbl.Clear_By_Vars;
   end Execute_STATS;
```

Notes for the implementer:
- `Val_String` is from `SData_Core.Values` (already visible to the body via the `Values`/`Eval` use). If unqualified `Val_String` does not resolve, qualify it (e.g. `SData_Core.Values.Val_String`) consistent with how `Val_Integer` is referenced in `Emit_Group`.
- `To_Upper` is `Ada.Characters.Handling.To_Upper` (string overload) — match the existing import used elsewhere in this body.
- If `Get_Array_Bounds` / `Get_Array_Element_Column` signatures differ slightly from the calls above, adjust to the real `SData_Core.Variables` spec (the array accessors confirmed present).

- [ ] **Step 3: Build sdata-core**

Run: `cd ~/Develop/sdata-core && alr build 2>&1 | tail -15`
Expected: compiles clean. (End-to-end behavior is exercised by integration tests after the sdata wiring in Task 3.)

- [ ] **Step 4: Confirm both consumers still build against the additive API**

Run: `cd ~/Develop/sdata && make check 2>&1 | tail -3 && cd ~/Develop/data-vandal && make check 2>&1 | tail -3`
Expected: both green (no behavior change yet; this proves the new public symbol does not break consumers).

- [ ] **Step 5: Commit**

```bash
cd ~/Develop/sdata-core
git add src/sdata_core-commands.ads src/sdata_core-commands.adb
git commit -m "feat(commands): add Execute_STATS (PROC MEANS computation core)

Row-per-(BY group x variable) stats table via build-and-swap, reusing the
aggregate dispatch and the shared Collect_Groups helper. Additive public
surface (Stats_Options + Execute_STATS); consumer floor unchanged.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Wire the STATS command into the sdata interpreter (lexer → AST → parser → dispatch)

Add the lexer token + reserved word, the `Stmt_STATS` AST node, `Parse_STATS`, and the immediate-dispatch `Execute_Stats` (guard + AST→core conversion + call + DISPLAY-reuse print). Because adding `Stmt_STATS` to the AST enum forces every `case Kind` to cover it, the whole interpreter chain lands together and is verified by a first integration smoke test.

**Files:**
- Modify: `~/Develop/sdata/src/lexer/sdata-lexer.ads` (token enum, after `Token_TRANSPOSE,` ~line 32)
- Modify: `~/Develop/sdata/src/lexer/sdata-lexer.adb` (keyword recogniser, after the `"TRANSPOSE"` arm ~line 295)
- Modify: `~/Develop/sdata/src/sdata-reserved_keywords.adb` (insert `"STATS"` between `"SORT"` and `"STEP"`)
- Modify: `~/Develop/sdata/src/ast/sdata-ast.ads` (enum entry + variant fields)
- Modify: `~/Develop/sdata/src/parser/sdata-parser.adb` (`Parse_STATS` + dispatch arm)
- Modify: `~/Develop/sdata/src/sdata-interpreter.adb` (`Is_Immediate`, `Execute_Stats`, dispatch arm)
- Modify: `~/Develop/sdata/src/sdata-interpreter-execute_metadata.adb` (factor a reusable whole-table display)
- Create: `~/Develop/sdata/tests/stats_basic.cmd`
- Create: `~/Develop/sdata/tests/expected/stats_basic.out`

**Interfaces:**
- Consumes: `SData_Core.Commands.Stats_Options` / `Execute_STATS` (Task 2); `Parse_Variable_List`; `Variable_List` (`Var.Start_Name (1 .. Var.Start_Len)`).
- Produces: `Token_STATS`; `Stmt_STATS` with fields `Stats_Vars : Variable_List`, `Stats_Stats : Variable_List`, `Stats_No_Print : Boolean := False`; `procedure Execute_Stats`; `procedure Display_All_Columns` (in execute_metadata).

- [ ] **Step 1: Write the failing smoke test**

Create `~/Develop/sdata/tests/stats_basic.cmd`:

```
-- STATS: default statistics for all numeric variables (no BY).
USE "tests/data/sample.csv"
STATS
QUIT
```

The expected output will be captured in Step 11 once the feature works. First, prove it currently fails (STATS unrecognized).

- [ ] **Step 2: Run it to confirm STATS is unrecognized**

Run: `cd ~/Develop/sdata && ./bin/sdata tests/stats_basic.cmd 2>&1 | head`
Expected: a parse/lex error (STATS not a known command) — confirms the feature is absent.

- [ ] **Step 3: Add the lexer token**

In `src/lexer/sdata-lexer.ads`, after the `Token_TRANSPOSE,` line, add:

```ada
Token_STATS,
```

In `src/lexer/sdata-lexer.adb`, after the `elsif Upper = "TRANSPOSE" then T.Kind := Token_TRANSPOSE;` line, add:

```ada
               elsif Upper = "STATS" then T.Kind := Token_STATS;
```

- [ ] **Step 4: Register STATS as a reserved keyword**

In `src/sdata-reserved_keywords.adb`, between `S.Insert ("SORT");` and `S.Insert ("STEP");`, add:

```ada
      S.Insert ("STATS");
```

- [ ] **Step 5: Add the AST node**

In `src/ast/sdata-ast.ads`, in the `Statement_Kind` enum, after `Stmt_TRANSPOSE,` add:

```ada
      Stmt_STATS,          -- Compute table statistics (immediate)
```

In the `Statement` variant record, after the `when Stmt_TRANSPOSE => …` branch and before `when Stmt_PROGRAM_INSERT =>`, add:

```ada
         when Stmt_STATS =>
            Stats_Vars     : Variable_List;   --  analysis vars (empty = all numeric)
            Stats_Stats    : Variable_List;   --  statistics (empty = N MIN MEAN MAX STD)
            Stats_No_Print : Boolean := False;
```

- [ ] **Step 6: Add Parse_STATS and its dispatch arm**

In `src/parser/sdata-parser.adb`, add `Parse_STATS` (model the slash loop on `Parse_TRANSPOSE`). Use `Parse_Variable_List` for both the bare list and the `/STATS=` list (it reads consecutive identifiers and stops at the first non-identifier such as `/` or end-of-statement):

```ada
   --  Parses "STATS [var ...] [/STATS=stat ...] [/NOPRINT]".  The bare list
   --  (analysis variables) is optional; slash-options follow.  Parse-time
   --  errors: duplicate /STATS, duplicate /NOPRINT, /STATS without '=' or list.
   procedure Parse_STATS
     (Ctx  : in out Parser_Context;
      Stmt : Statement_Access)
   is
      Saw_STATS    : Boolean := False;
      Saw_NOPRINT  : Boolean := False;
   begin
      --  Optional bare variable list (stops at '/' or end of statement).
      Stmt.Stats_Vars := Parse_Variable_List (Ctx);

      loop
         exit when Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Slash;
         declare
            Discard   : constant Token := Get_Next_Token (Ctx.Lex_Ctx);  --  '/'
            Flag_Tok  : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
            Flag_Name : constant String :=
              To_Upper (Flag_Tok.Text (1 .. Flag_Tok.Length));
            pragma Unreferenced (Discard);
         begin
            if Flag_Name = "STATS" then
               if Saw_STATS then
                  raise Script_Error with
                    "STATS: /STATS may be specified at most once";
               end if;
               Saw_STATS := True;
               if Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Equal then
                  raise Script_Error with "STATS: expected '=' after /STATS";
               end if;
               declare
                  Eat : constant Token := Get_Next_Token (Ctx.Lex_Ctx);  --  '='
                  pragma Unreferenced (Eat);
               begin
                  Stmt.Stats_Stats := Parse_Variable_List (Ctx);
               end;
               if Stmt.Stats_Stats = null then
                  raise Script_Error with
                    "STATS: /STATS= requires at least one statistic";
               end if;
            elsif Flag_Name = "NOPRINT" then
               if Saw_NOPRINT then
                  raise Script_Error with
                    "STATS: /NOPRINT may be specified at most once";
               end if;
               Saw_NOPRINT := True;
               Stmt.Stats_No_Print := True;
            else
               raise Script_Error with
                 "STATS: unknown option '/" & Flag_Name & "'";
            end if;
         end;
      end loop;
   end Parse_STATS;
```

In the `Parse_Statement` dispatch `case`, after the `when Token_TRANSPOSE =>` arm, add:

```ada
         when Token_STATS =>
            Stmt := new Statement (Stmt_STATS);
            Parse_STATS (Ctx, Stmt);
```

(If `Parse_STATS` is referenced before its body, add a forward declaration alongside `Parse_TRANSPOSE`'s, matching the file's existing convention.)

- [ ] **Step 7: Factor a reusable whole-table display**

In `src/sdata-interpreter-execute_metadata.adb`, extract the no-argument DISPLAY rendering (the `REC#` header + row loop using `Logical_To_Physical` and `To_String_Formatted`) into a parameterless procedure that displays **all** columns of the current table, and call it from the `Stmt_DISPLAY` arm when no variables are named:

```ada
   --  Render every column of the current (filtered) table to console, in the
   --  DISPLAY format (REC# header + one line per logical row).  Shared by the
   --  bare DISPLAY command and by STATS' default printout.
   procedure Display_All_Columns is
      V    : constant ... := <all current column names, as the DISPLAY arm builds them>;
      Rows : constant Natural := SData_Core.Table.Logical_Row_Count;
   begin
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
```

Replace the inline body of the bare-DISPLAY case with a call to `Display_All_Columns`, leaving the `DISPLAY varlist` (named-columns) path unchanged. Expose `Display_All_Columns` so the interpreter can call it (add its declaration to the package spec or the relevant private declarations, following how other execute_metadata helpers are exposed). **The existing `display*.cmd` integration tests must remain green** — this extraction is behavior-preserving.

- [ ] **Step 8: Add Execute_Stats and its dispatch in the interpreter**

In `src/sdata-interpreter.adb`, add `Stmt_STATS` to the `Is_Immediate` set (alongside `Stmt_TRANSPOSE`):

```ada
         Stmt_TRANSPOSE | Stmt_STATS | Stmt_PROGRAM_INSERT;
```

Add the `Execute_Stats` procedure (model on `Execute_Transpose`):

```ada
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
         Execute_Metadata.Display_All_Columns;   --  qualify per the real package path
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
```

In the `Execute_Statement` dispatch `case`, after `when Stmt_TRANSPOSE => Execute_Transpose (Stmt);`, add:

```ada
         when Stmt_STATS =>
            Execute_Stats (Stmt);
```

(Resolve the exact way to call the factored display: if `Display_All_Columns` lives in the `execute_metadata` separate, expose it so `Execute_Stats` can call it, matching the file's subunit conventions.)

- [ ] **Step 9: Cover Stmt_STATS in any other `case Kind` that is non-exhaustive**

Build will flag every `case Statement_Kind` (or `case Stmt.Kind`) lacking a `when others`. Run the build (next step) and add `Stmt_STATS` (usually to an existing `when others => null` or a no-op arm) wherever the compiler reports a missing case — e.g. pretty-printers, `Is_Immediate`-adjacent helpers. Do not add behavior; just satisfy exhaustiveness consistently with how `Stmt_TRANSPOSE` is handled in each spot.

- [ ] **Step 10: Build the full tree**

Run: `cd ~/Develop/sdata && make build 2>&1 | tail -20`
Expected: compiles clean. Fix any missing-case or signature mismatches surfaced.

- [ ] **Step 11: Capture and verify the smoke test**

Run STATS on the sample data and inspect output:
`cd ~/Develop/sdata && ./bin/sdata tests/stats_basic.cmd`
Confirm by hand that it prints a `REC#`/`_NAME_$`/`N MIN MEAN MAX STD` table — one row per numeric column of `tests/data/sample.csv` — followed by `STATS complete. …`. When correct, capture the fixture:
`./bin/sdata tests/stats_basic.cmd > tests/expected/stats_basic.out`
Then `git diff --stat` and **read** `tests/expected/stats_basic.out` to confirm it matches the schema in the spec (§3).

- [ ] **Step 12: Run the full suite + cross-crate gate**

Run: `cd ~/Develop/sdata && make check 2>&1 | tail -8 && cd ~/Develop/data-vandal && make check 2>&1 | tail -3`
Expected: all sdata integration tests pass (including the new `stats_basic`), data-vandal green.

- [ ] **Step 13: Commit**

```bash
cd ~/Develop/sdata
git add src/lexer/sdata-lexer.ads src/lexer/sdata-lexer.adb \
        src/sdata-reserved_keywords.adb src/ast/sdata-ast.ads \
        src/parser/sdata-parser.adb src/sdata-interpreter.adb \
        src/sdata-interpreter-execute_metadata.adb \
        tests/stats_basic.cmd tests/expected/stats_basic.out
git commit -m "feat(stats): wire STATS command end-to-end (lexer/AST/parser/dispatch)

STATS is an immediate command computing per-variable summary statistics,
replacing the table (build-and-swap via Commands.Execute_STATS) and printing
via the DISPLAY renderer unless /NOPRINT. Pending-deferred guarded like
AGGREGATE/TRANSPOSE. STATS becomes a reserved keyword.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Integration test matrix

Add the full behavioral test matrix as `.cmd` + `expected/*.out` pairs. The Makefile auto-discovers `tests/*.cmd`. Reuse existing fixtures (`tests/data/sample.csv` for plain numeric, and a BY-capable / character-bearing fixture — inspect `tests/data/` and the AGGREGATE/TRANSPOSE tests to pick the right ones).

**Files:**
- Create (each with a matching `tests/expected/<name>.out`):
  - `tests/stats_varlist.cmd` — explicit variable list
  - `tests/stats_custom.cmd` — `/STATS=` with custom set and order
  - `tests/stats_noprint.cmd` — `/NOPRINT` then `DISPLAY` (proves replacement happened, nothing printed by STATS itself)
  - `tests/stats_by.cmd` — BY grouping
  - `tests/stats_save.cmd` — pending SAVE writes the stats table
  - `tests/stats_select.cmd` — active SELECT respected
  - `tests/stats_char_error.cmd` — value stat on a `$` column → error
  - `tests/stats_char_ok.cmd` — `/STATS=N` on a `$` column → ok
  - `tests/stats_array.cmd` — whole-array expansion (one row per element)
  - `tests/stats_no_numeric_error.cmd` — table with no numeric columns → error
  - `tests/stats_pending_error.cmd` — queue a deferred statement, then STATS → error #13

**Interfaces:**
- Consumes: the working STATS command (Task 3). For `.exitcode` on error tests, follow the existing convention (an error test whose `sdata` exits non-zero needs a `tests/<name>.exitcode` if the harness expects one — check how existing `*_error.cmd` tests do it before assuming).

- [ ] **Step 1: Inspect existing error-test and BY/SELECT/SAVE test conventions**

Run: `cd ~/Develop/sdata && ls tests/ | grep -E 'aggregate_|transpose_' && cat tests/aggregate_by.cmd 2>/dev/null; ls tests/*.exitcode 2>/dev/null | head; cat tests/data/sample.csv`
Read 2–3 AGGREGATE tests covering BY, SELECT, SAVE, and an error case to copy the exact idioms (how SAVE targets are named, how errors are expected, whether `.exitcode` files are used).

- [ ] **Step 2: Write each `.cmd` script**

Author the eleven scripts above following the spec semantics (§2–§5) and the idioms from Step 1. Example `tests/stats_by.cmd`:

```
-- STATS: default statistics within BY groups.
USE "tests/data/<by-capable fixture>.csv"
BY <key>
STATS <numeric var>
QUIT
```

Example `tests/stats_pending_error.cmd` (must trip error #13):

```
-- STATS refuses while a deferred statement is pending.
USE "tests/data/sample.csv"
LET z = 1
STATS
QUIT
```

- [ ] **Step 3: Generate each expected fixture, verifying correctness by eye first**

For each script, run it, **read the output to confirm it matches the spec**, then capture:
`./bin/sdata tests/<name>.cmd > tests/expected/<name>.out`
For error tests, confirm the error message text matches the `raise … with "STATS: …"` strings from Tasks 2–3, and add any `.exitcode` file the harness convention requires.

- [ ] **Step 4: Run the full suite**

Run: `cd ~/Develop/sdata && make check 2>&1 | tail -10`
Expected: all tests pass, including the new `stats_*`. Investigate any diff (do not blindly re-capture a fixture — a diff may be a real bug).

- [ ] **Step 5: Cross-crate gate**

Run: `cd ~/Develop/data-vandal && make check 2>&1 | tail -3`
Expected: green.

- [ ] **Step 6: Commit**

```bash
cd ~/Develop/sdata
git add tests/stats_*.cmd tests/expected/stats_*.out tests/stats_*.exitcode 2>/dev/null
git commit -m "test(stats): integration matrix (varlist, /STATS, /NOPRINT, BY, SAVE, SELECT, errors)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: Built-in HELP + snapshot

Add `Help_STATS`, register it, and regenerate the `HELP /ALL` and `HELP` index snapshots.

**Files:**
- Modify: `~/Develop/sdata/src/sdata-help.adb` (`Help_STATS` ~after Help_TRANSPOSE line 262; `K_STATS` constant ~line 1237; dispatch-table row ~line 1453)
- Modify: `~/Develop/sdata/tests/expected/help_all.out` (regenerated)
- Modify: `~/Develop/sdata/tests/expected/help_index.out` (regenerated, if it lists commands)

**Interfaces:**
- Consumes: the help dispatch-table format `(K_xxx'Access, Help_xxx'Access, C, N)` (C = appears in COMMAND REFERENCE; N = not a function alias).

- [ ] **Step 1: Add Help_STATS**

In `src/sdata-help.adb`, after `Help_TRANSPOSE` (~line 262), add:

```ada
   procedure Help_STATS is
   begin
      Put_Line ("Command: STATS [var ...] [/STATS=stat ...] [/NOPRINT]");
      Put_Line ("Computes summary statistics for the chosen variables (default: all");
      Put_Line ("numeric columns), one row per active BY group per variable, with one");
      Put_Line ("column per statistic. The result replaces the Data Table.");
      Put_Line ("  var ...   analysis variables; omit for all numeric columns. A whole");
      Put_Line ("            array name expands to its elements.");
      Put_Line ("  /STATS=   statistics to compute (default: N MIN MEAN MAX STD).");
      Put_Line ("            Any registered aggregate: SUM MEAN STD VAR MIN MAX N NMISS");
      Put_Line ("            GMEAN HMEAN MEDIAN. Only N/NMISS apply to character vars.");
      Put_Line ("  /NOPRINT  replace the table (and write a pending SAVE) without");
      Put_Line ("            printing the result.");
      Put_Line ("Respects the active SELECT filter; flushes a pending SAVE; clears the");
      Put_Line ("active SELECT and BY afterward.");
      Put_Line ("Execution: Immediate -- rebuilds the table at once. See man page sdata(1).");
   end Help_STATS;
```

If `Help_STATS` needs a forward declaration in the file's helper-declaration block (as `Help_TRANSPOSE` has), add it consistently.

- [ ] **Step 2: Register STATS in the help dispatch table**

Add the keyword constant near the others (~line 1237):

```ada
   K_STATS        : aliased constant String := "STATS";
```

Add the dispatch row near the AGGREGATE/TRANSPOSE rows (~line 1453):

```ada
      (K_STATS'Access,      Help_STATS'Access,      C, N),
```

- [ ] **Step 3: Build**

Run: `cd ~/Develop/sdata && make build 2>&1 | tail -5`
Expected: compiles clean.

- [ ] **Step 4: Verify HELP STATS output, then regenerate snapshots**

Check the topic renders:
`printf 'HELP STATS\nQUIT\n' | ./bin/sdata`
Then regenerate the snapshots from their generating scripts (confirm names in the Makefile test list):
```bash
./bin/sdata tests/help_all.cmd > tests/expected/help_all.out
# regenerate the index snapshot too if one exists (e.g. help_index.cmd):
[ -f tests/help_index.cmd ] && ./bin/sdata tests/help_index.cmd > tests/expected/help_index.out
```
**Read** the diffs (`git diff tests/expected/help_all.out`) and confirm the only change is the inserted STATS material (in COMMAND REFERENCE / index ordering) — nothing else shifted.

- [ ] **Step 5: Run the suite**

Run: `cd ~/Develop/sdata && make check 2>&1 | tail -6`
Expected: all green, including `help_all` (and `help_index` if present).

- [ ] **Step 6: Commit**

```bash
cd ~/Develop/sdata
git add src/sdata-help.adb tests/expected/help_all.out tests/expected/help_index.out 2>/dev/null
git commit -m "docs(stats): HELP STATS topic + HELP /ALL snapshot

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: User-facing docs — man page, design.md, ADR-048, architecture.md, CLAUDE.md

Complete the documentation surface (the man-page + design-doc legs of the trio, plus the architectural records).

**Files:**
- Modify: `~/Develop/sdata/man/man1/sdata.1` (STATS entry after the TRANSPOSE block ~line 599; STATS in the LANGUAGE OVERVIEW command list)
- Modify: `~/Develop/sdata/doc/design.md` (new `<tr>` after the TRANSPOSE row ~line 930)
- Modify: `~/Develop/sdata/doc/adrs.md` (index row + full ADR-048)
- Modify: `~/Develop/sdata/doc/architecture.md` (mention STATS among the sdata-only commands)
- Modify: `~/Develop/sdata/CLAUDE.md` (add STATS to the sdata-only command list in "Repository Layout")

**Interfaces:** none (prose/markup only). This is a documentation-only commit per CLAUDE.md — but it touches no `src/`, so the full `make check` is **not** required (CI reruns as backstop). Still build-free: verify groff renders.

- [ ] **Step 1: Man page entry**

In `man/man1/sdata.1`, after the TRANSPOSE entry (~line 599), add a `.B STATS …` block modeled on the AGGREGATE/TRANSPOSE entries:

```
.TP
.B STATS\fR [\fIvar\fB ...]\fR [\fB/STATS=\fIstat\fB ...]\fR [\fB/NOPRINT\fB]
Compute summary statistics for the chosen
.I var
list (default: all numeric columns), producing one output row per active
.B BY
group per variable, with one column per statistic.
The result replaces the data table.
.RS
.TP
.B /STATS=\fIstat ...
Statistics to compute; default
.BR "N MIN MEAN MAX STD" .
Any registered aggregate
.RB ( SUM ", " MEAN ", " STD ", " VAR ", " MIN ", " MAX ", " N ", " NMISS ", " GMEAN ", " HMEAN ", " MEDIAN ).
Only
.B N
and
.B NMISS
may be applied to a character variable.
.TP
.B /NOPRINT
Replace the table (and write a pending
.BR SAVE )
without printing the result.
.RE
.PP
A whole-array name in
.I var
expands to one row per element
.RI ( name (1).. name (K)).
The active
.B SELECT
filter is respected; a pending
.B SAVE
is written; then the active
.B SELECT
and
.B BY
are cleared.
The deferred program buffer must hold no un\-run statements (issue
.B RUN
or
.B NEW
first).
See also
.BR AGGREGATE .
```

Also add `STATS` to the LANGUAGE OVERVIEW command list wherever AGGREGATE/TRANSPOSE appear.

- [ ] **Step 2: design.md command-reference row**

In `doc/design.md`, after the TRANSPOSE `<tr>…</tr>` (~line 930), add (model on the AGGREGATE/TRANSPOSE rows):

```html
<tr>
<td><em>STATS</em></td>
<td><em>STATS</em> [<em>var</em> ...] [/<em>STATS</em>=<em>stat</em> ...] [/<em>NOPRINT</em>]</td>
<td>Immediate Execution</td>
<td>Compute summary statistics for the chosen <em>var</em> list (default: all numeric columns of the table, excluding the active <em>BY</em> variables), producing one output row per active <em>BY</em> group per variable. With no active <em>BY</em>, the whole (<em>SELECT</em>-filtered) table is one group. The output schema is: the active BY variables, then a name column <em>_NAME_$</em> holding each analysis variable's name, then one column per requested statistic. <em>/STATS=</em> lists the statistics (default <em>N MIN MEAN MAX STD</em>); any registered aggregate function is allowed (<em>SUM</em>, <em>MEAN</em>, <em>STD</em>, <em>VAR</em>, <em>MIN</em>, <em>MAX</em>, <em>N</em>, <em>NMISS</em>, <em>GMEAN</em>, <em>HMEAN</em>, <em>MEDIAN</em>); a non-aggregate name is rejected. A character variable is permitted only when every requested statistic accepts character input (currently only <em>N</em> and <em>NMISS</em>). A whole-array name expands to one row per element. <em>N</em> and <em>NMISS</em> columns are integer; the rest are float. The result replaces the in-memory table via build-and-swap; the table is printed (via DISPLAY) unless <em>/NOPRINT</em> is given. The active <em>SELECT</em> filter is respected during the scan; if a <em>SAVE</em> is pending the result is written to it; then the active <em>SELECT</em> and <em>BY</em> are cleared. STATS refuses to run while un-run deferred statements are pending (issue <em>RUN</em> or <em>NEW</em> first). See also <em>AGGREGATE</em>.</td>
</tr>
```

- [ ] **Step 3: ADR-048**

In `doc/adrs.md`, add the index row after the ADR-047 row:

```
| ADR-048 | STATS command — transposed-AGGREGATE layout, always-replace + print/NOPRINT, shared group-scan helper | 2026-06-30 | Accepted |
```

And the full entry after ADR-047 (model on ADR-046/047):

```markdown
### ADR-048: STATS command — transposed-AGGREGATE layout, always-replace + print/NOPRINT, shared group-scan helper
**Date:** 2026-06-30 | **Status:** Accepted

**Context:** STATS (design spec `doc/specs/2026-06-30-stats-command-design.md`) is SData's PROC MEANS analogue: per-variable summary statistics over the current table, grouped by the active BY. It is functionally a "transposed AGGREGATE" and reuses the same aggregate-function dispatch and build-and-swap machinery.

**Decision:**
1. **Result layout is row-per-(BY group × variable), columns = statistics.** Schema: BY vars + `_NAME_$` (the analysis-variable name, reusing TRANSPOSE's name-column convention) + one column per requested statistic. This is the transpose of AGGREGATE's row-per-group/column-per-clause layout and matches the PROC MEANS report orientation. `N`/`NMISS` columns are `Col_Integer`; the rest `Col_Numeric`.
2. **Always replace the in-memory table; print by default, suppress with `/NOPRINT`.** STATS uses the same build-and-swap path as AGGREGATE/TRANSPOSE (always replaces the table, flushes a pending SAVE, clears SELECT/BY). Printing is layered on top in the interpreter via the existing DISPLAY renderer; `/NOPRINT` suppresses only the printout, so the replacement always happens and `/NOPRINT` is never a no-op.
3. **Shared `Collect_Groups`/`Group_Values` helper (approach A).** The BY-group scan was factored out of `Execute_AGGREGATE` into private helpers in `sdata_core-commands.adb` and is now called by both AGGREGATE and STATS, eliminating scan duplication. AGGREGATE behavior is unchanged (verified by its integration tests).
4. **Statistics = the registered aggregate allow-list; default `N MIN MEAN MAX STD`.** `/STATS` names are validated with `Evaluator.Is_Aggregate`; the character-input rule reuses `Aggregate_Metadata.Accepts_Character` (only `N`/`NMISS`). No stat-column renaming and no `/NAME=` override in v1 (YAGNI).
5. **Pending-deferred guard reuses the `Pending_Deferred` counter** established by ADR-046; STATS adds the next error in that lineage ("STATS: pending program statements exist; issue RUN or NEW first").

**Consequences:** STATS is purely additive to sdata-core's public surface (`Stats_Options` + `Execute_STATS` on `Commands`) — a patch bump (sdata-core 0.1.18 → 0.1.19); the `^0.1.16` consumer floor still admits it, so no consumer-constraint change. data-vandal does not use `Execute_STATS` but builds and tests clean against the additive API. STATS becomes a reserved keyword in sdata's lexer. sdata gets a minor bump (0.11.1 → 0.12.0) for the new command.
```

- [ ] **Step 4: architecture.md + CLAUDE.md**

In `doc/architecture.md`, add STATS to the sdata-only command enumeration (wherever AGGREGATE/TRANSPOSE are listed). In `CLAUDE.md`, in the "Repository Layout" paragraph listing sdata-only commands ("LET, SET, PRINT, … SORT, AGGREGATE, TRANSPOSE, …"), add `STATS`.

- [ ] **Step 5: Verify groff renders and prose is consistent**

Run: `cd ~/Develop/sdata && man --warnings -E UTF-8 -l man/man1/sdata.1 >/dev/null 2>man.warn; cat man.warn; rm -f man.warn`
Expected: no groff errors. Spot-check the design.md table renders (GitHub HTML-in-markdown).

- [ ] **Step 6: Commit**

```bash
cd ~/Develop/sdata
git add man/man1/sdata.1 doc/design.md doc/adrs.md doc/architecture.md CLAUDE.md
git commit -m "docs(stats): man page, design.md, ADR-048, architecture, CLAUDE.md

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Version bump + release

Bump sdata-core (patch, additive) and sdata (minor, new command), run the full three-way gate, and tag.

**Files:**
- Modify: `~/Develop/sdata-core/alire.toml` (`0.1.18 → 0.1.19`)
- Modify (via script): the 9 sdata version files (`scripts/bump-version.sh`)

**Interfaces:** none. Final gate is the authority.

- [ ] **Step 1: Bump sdata-core**

Edit `~/Develop/sdata-core/alire.toml` version to `0.1.19`. (sdata-core has no bump script; this is the single source.) Do **not** touch consumer floors.

```bash
cd ~/Develop/sdata-core && alr build 2>&1 | tail -3
git add alire.toml && git commit -m "chore: bump version to 0.1.19 (Execute_STATS)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git tag -a v0.1.19 -m "Version 0.1.19"
```

- [ ] **Step 2: Bump sdata**

Run: `cd ~/Develop/sdata && scripts/bump-version.sh 0.12.0 "Add STATS command (PROC MEANS analogue)"`
Verify it updated all 9 files (`git diff --stat`).

- [ ] **Step 3: Full three-way gate**

Run:
```bash
cd ~/Develop/sdata-core && alr build 2>&1 | tail -3
cd ~/Develop/sdata       && make check 2>&1 | tail -8
cd ~/Develop/data-vandal && make check 2>&1 | tail -3
```
Expected: sdata-core builds; sdata all tests pass; data-vandal all tests pass. **All three green is the release gate.**

- [ ] **Step 4: Commit + tag sdata**

```bash
cd ~/Develop/sdata
git add -A
git commit -m "chore: bump version to 0.12.0 (STATS command)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git tag -a v0.12.0 -m "Version 0.12.0"
```

- [ ] **Step 5: Final verification**

Run: `cd ~/Develop/sdata && git log --oneline -8 && git status`
Expected: clean tree; the STATS commits and the version-bump commit present; tags `v0.1.19` (sdata-core) and `v0.12.0` (sdata) created.

---

## Self-Review

**Spec coverage:**
- §2 syntax (bare list + `/STATS=` + `/NOPRINT`) → Task 3 (Parse_STATS).
- §3 schema (BY + `_NAME_$` + stat cols; integer N/NMISS) → Task 2 (Execute_STATS Step 2, schema build).
- §4 execution (guard, validation, group scan, build-swap, SAVE, clear SELECT/BY) → Tasks 1+2+3.
- §4.5 print via DISPLAY / `/NOPRINT` → Task 3 (Steps 7–8).
- §5 edge cases (empty table, array expansion, duplicate var) → Task 2 logic + Task 4 tests (array; empty/duplicate behavior exercised; empty-table parity to verify against AGGREGATE during Task 2).
- §6 footprint (sdata-core additive, sdata wiring, HELP, docs, tests) → Tasks 2–6.
- §6.5 versions → Task 7.
- §7 cross-crate gate → enforced in every task's verification.
- §8 non-goals (no `/NAME=`, no rename) → honored (not implemented).

**Placeholder scan:** No "TBD"/"implement later". Two explicit verification points are intentional, not placeholders: (a) Task 2 — confirm empty-table behavior matches AGGREGATE; (b) Task 3 Step 7 — the `V` column-name collection mirrors the existing DISPLAY arm (copy its exact local rather than inventing one). Both instruct the implementer to ground against real code.

**Type consistency:** AST fields `Stats_Vars` / `Stats_Stats` / `Stats_No_Print` are used consistently in Tasks 3 (parser sets them; interpreter reads them). Core `Stats_Options.Var_List` / `Stat_List` consistent across Task 2 (def) and Task 3 (use). `Collect_Groups` / `Group_Values` defined in Task 1, consumed in Tasks 1 (AGGREGATE) and 2 (STATS). `Display_All_Columns` defined and called in Task 3.
