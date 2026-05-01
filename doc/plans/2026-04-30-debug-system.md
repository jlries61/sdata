# Debug System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the SData debug system: enriched `--debug` passive trace, `BREAK`/`BREAK WHEN` deferred statement, and an interactive inspection REPL with `PRINT`/`RECORD`/`CONTINUE`/`STEP`/`RUN` commands.

**Architecture:** `BREAK` is a new AST node (`Stmt_BREAK`) parsed from the data-step body; the interpreter executes it by calling an inspection REPL procedure. The REPL loads any requested record into the PDV, evaluates `PRINT` expressions using the existing evaluator, and returns a `Step_Action` tag that tells `Run_One_Step` whether to pause again after the next record. All trace output uses two new private helpers (`Debug_Trace`, `Debug_Value`).

**Tech Stack:** Ada 2012, GNAT/gprbuild. No new packages — all changes confined to `src/sdata-interpreter.adb`, `src/ast/sdata-ast.ads`, `src/lexer/sdata-lexer.adb`, `src/lexer/sdata-lexer.ads`, `src/parser/sdata-parser.adb`, `man/man1/sdata.1`.

---

## File Map

| File | Change |
|---|---|
| `src/lexer/sdata-lexer.ads` | Add `Token_BREAK` to `Token_Kind` enum |
| `src/lexer/sdata-lexer.adb` | Add `elsif Upper = "BREAK"` keyword branch |
| `src/ast/sdata-ast.ads` | Add `Stmt_BREAK` to `Statement_Kind`; no new fields needed (uses existing `Expr`) |
| `src/parser/sdata-parser.adb` | Add `when Token_BREAK` case in `Parse_Statement`; add `when Stmt_BREAK` in `Resolve_Stmt` |
| `src/sdata-interpreter.adb` | (1) Add `Debug_Trace`/`Debug_Value` helpers and replace two existing inline debug blocks; (2) enrich trace points across statement handlers; (3) add `Step_Action` type + `Inspect_PDV` REPL procedure; (4) add `Stmt_BREAK` handler in `Execute_Statement`; (5) integrate step-mode pause into `Process_One_Record`/`Run_One_Step` |
| `man/man1/sdata.1` | Add `BREAK` and `BREAK WHEN` to command reference; expand `--debug` description |
| `tests/debug_trace.cmd` | New test: passive trace output |
| `tests/debug_trace.flags` | `--debug` |
| `tests/expected/debug_trace.out` | Expected combined stdout+stderr output |
| `tests/break_basic.cmd` | New test: unconditional `BREAK` in non-interactive context |
| `tests/expected/break_basic.out` | Emits `[debug] BREAK: record 1 paused (non-interactive — continuing)` and continues |
| `tests/break_when.cmd` | New test: `BREAK WHEN RECNO() = 3` |
| `tests/expected/break_when.out` | Three-record run; break fires on record 3 only |

---

## Task 1: Add `Token_BREAK` to the lexer

**Files:**
- Modify: `src/lexer/sdata-lexer.ads`
- Modify: `src/lexer/sdata-lexer.adb`

- [ ] **Step 1: Add `Token_BREAK` to `Token_Kind`**

In `src/lexer/sdata-lexer.ads`, in the `Token_Kind` enumeration, add `Token_BREAK` after `Token_STEP` (the last keyword before the operators block):

```ada
      Token_TO, Token_STEP, Token_BREAK,
```

- [ ] **Step 2: Add keyword recognition in the lexer body**

In `src/lexer/sdata-lexer.adb`, after the line:
```ada
               elsif Upper = "STEP" then T.Kind := Token_STEP;
```
add:
```ada
               elsif Upper = "BREAK" then T.Kind := Token_BREAK;
```

- [ ] **Step 3: Build to verify no compile errors**

```
alr build 2>&1 | tail -5
```
Expected: build succeeds (unused token warning is fine — the parser handles it next).

- [ ] **Step 4: Commit**

```bash
git add src/lexer/sdata-lexer.ads src/lexer/sdata-lexer.adb
git commit -m "Add Token_BREAK to lexer"
```

---

## Task 2: Add `Stmt_BREAK` to the AST and parse it

**Files:**
- Modify: `src/ast/sdata-ast.ads`
- Modify: `src/parser/sdata-parser.adb`

- [ ] **Step 1: Add `Stmt_BREAK` to `Statement_Kind`**

In `src/ast/sdata-ast.ads`, in the `Statement_Kind` enumeration, add `Stmt_BREAK` after `Stmt_DELETE`:

```ada
      Stmt_DELETE, -- Drop current record
      Stmt_BREAK,  -- Pause execution for inspection (BREAK / BREAK WHEN <expr>)
```

`Stmt_BREAK` uses the existing common `Expr` field for the optional condition (null = unconditional).

- [ ] **Step 2: Parse `BREAK` and `BREAK WHEN <expr>` in `Parse_Statement`**

In `src/parser/sdata-parser.adb`, inside `Parse_Statement`, add a new `when Token_BREAK =>` case. Place it after the `when Token_DELETE =>` case:

```ada
         when Token_BREAK =>
            declare
               S : constant Statement_Access :=
                  new Statement (Stmt_BREAK);
            begin
               S.Expr := null;
               if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_WHEN then
                  declare
                     Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                  begin
                     S.Expr := Parse_Expression (Ctx);
                  end;
               end if;
               Stmt := S;
            end;
```

- [ ] **Step 3: Add `Stmt_BREAK` to `Resolve_Stmt`**

In `src/sdata-interpreter.adb`, inside `Resolve_Stmt`, add a `when Stmt_BREAK` arm so the condition expression (if present) gets its variable indices resolved:

```ada
            when Stmt_BREAK =>
               Resolve_Expr (S.Expr);   --  S.Expr is null for unconditional BREAK
```

Place it after the `when Stmt_RSEED` arm (around line 1824).

- [ ] **Step 4: Add `Stmt_BREAK` to `Process_One_Record`'s allowed-statement set**

In `Process_One_Record`, the inner `case Iter.Kind` arms whitelist which statement kinds are executed inside a data step. Add `Stmt_BREAK` to the allowed list (around line 1673):

```ada
            when Stmt_LET | Stmt_SET | Stmt_PRINT | Stmt_NAMES | Stmt_IF
               | Stmt_WHILE | Stmt_FOR | Stmt_LOOP_REPEAT | Stmt_SELECT
               | Stmt_DELETE | Stmt_BREAK | Stmt_WRITE | Stmt_OUTPUT | Stmt_ECHO
               | Stmt_HOLD | Stmt_UNHOLD | Stmt_DIM
               | Stmt_BY | Stmt_DIGITS | Stmt_HELP =>
```

- [ ] **Step 5: Add `Stmt_BREAK` stub to `Execute_Statement`**

In `Execute_Statement`, add a stub case so it compiles without warnings (implementation comes in Task 5):

```ada
         when Stmt_BREAK =>
            null;  --  Full handler added in Task 5
```

- [ ] **Step 6: Build and verify no compile errors**

```
alr build 2>&1 | tail -5
```
Expected: clean build.

- [ ] **Step 7: Commit**

```bash
git add src/ast/sdata-ast.ads src/parser/sdata-parser.adb src/sdata-interpreter.adb
git commit -m "Add Stmt_BREAK to AST, parser, and resolver"
```

---

## Task 3: Add `Debug_Trace` / `Debug_Value` helpers and replace existing inline debug blocks

**Files:**
- Modify: `src/sdata-interpreter.adb`

The existing two inline debug blocks are:
1. Line ~1436: `Execute_Statement` generic print (`[debug] STMT_KIND`)
2. Line ~1641: `Process_One_Record` record header (`[debug] -- record N`)

Both will be replaced by calls to the new helpers.

- [ ] **Step 1: Write the failing test for the helper output format**

Create `tests/debug_trace.cmd`:
```
NEW
REPEAT 3
LET X = RECNO()
RUN
QUIT
```

Create `tests/debug_trace.flags`:
```
--debug
```

Create `tests/expected/debug_trace.out` (the combined stdout+stderr the test harness captures):
```
[debug] -- record 1 (physical 1)
[debug] LET X = 1
[debug] -- record 2 (physical 2)
[debug] LET X = 2
[debug] -- record 3 (physical 3)
[debug] LET X = 3
RUN complete. 3 records and 1 variables processed.
```

Run the test to confirm it currently fails (existing trace produces different output):
```
make check 2>&1 | grep debug_trace
```
Expected: `FAILED (output mismatch)` or `FAILED (no expected output file)`.

- [ ] **Step 2: Add `Debug_Trace` and `Debug_Value` as private procedures/functions**

In `src/sdata-interpreter.adb`, near the top of the package body (after the `use` clauses, before the first procedure), add:

```ada
   procedure Debug_Trace (Msg : String) is
   begin
      if SData.Config.Debug_Mode then
         Put_Line_Error ("[debug] " & Msg);
      end if;
   end Debug_Trace;

   function Debug_Value (V : Value) return String is
   begin
      case V.Kind is
         when Val_Numeric  => return Ada.Strings.Fixed.Trim (Float'Image (V.Num_Val), Ada.Strings.Both);
         when Val_Integer  => return Ada.Strings.Fixed.Trim (Integer'Image (V.Int_Val), Ada.Strings.Both);
         when Val_String   => return """" & To_String (V.Str_Val) & """";
         when Val_Missing  => return "<missing>";
      end case;
   end Debug_Value;
```

Note: `Ada.Strings.Fixed` and `Ada.Strings` are already in scope via existing `use` clauses. Confirm with:
```bash
grep "Ada.Strings" /home/jries/Develop/sdata/src/sdata-interpreter.adb | head -5
```

If not already present, add `with Ada.Strings.Fixed; use Ada.Strings.Fixed;` to the withs at the top of the file.

- [ ] **Step 3: Replace the generic `Execute_Statement` debug block**

Find and remove the existing inline block at ~line 1436:
```ada
      if SData.Config.Debug_Mode then
         declare
            Image : constant String := Stmt.Kind'Image;
         begin
            --  Strip the "STMT_" prefix (5 characters) for readability.
            Put_Line_Error ("[debug] " & Image (Image'First + 5 .. Image'Last));
         end;
      end if;
```

Delete it entirely. The enriched per-handler traces added in Task 4 will replace this.

- [ ] **Step 4: Replace the `Process_One_Record` debug block**

Find the existing block at ~line 1640:
```ada
      if SData.Config.Debug_Mode then
         Put_Line_Error ("[debug] -- record" & Logical_I'Image
                         & " (physical" & Phys_I'Image & ")");
      end if;
```

Move it to **after** `Load_PDV_From_Table (Phys_I)` (and after the BOG/EOG block) so BY group annotation can be appended in Task 4. For now, replace it with:

```ada
      --  Moved to after Load_PDV_From_Table — see BY group annotation in Task 4
      Debug_Trace ("-- record" & Logical_I'Image & " (physical" & Phys_I'Image & ")");
```

Place the `Debug_Trace` call immediately after the BOG/EOG `end if` (around line 1665), still before `Iter := Start`.

- [ ] **Step 5: Build and run tests**

```
alr build && make check 2>&1 | tail -10
```
The `debug_trace` test will still likely fail because Task 4 hasn't added the enriched LET trace yet. That is expected. All other tests should pass.

- [ ] **Step 6: Commit**

```bash
git add src/sdata-interpreter.adb
git commit -m "Add Debug_Trace/Debug_Value helpers; replace inline debug blocks"
```

---

## Task 4: Passive trace enrichment

**Files:**
- Modify: `src/sdata-interpreter.adb`

Add `Debug_Trace` calls in each statement handler as specified in the design.

- [ ] **Step 1: Trace LET/SET scalar and array assignments**

In `Execute_Assignment`, after `Set_Permanent` / `Set_Temporary` is called (around line 600), add:

```ada
         --  Scalar assignment
         if Stmt.Kind = Stmt_LET then
            Set_Permanent (Var_Name_Str, Result);
         else
            Set_Temporary (Var_Name_Str, Result);
         end if;
         Debug_Trace ((if Stmt.Kind = Stmt_LET then "LET " else "SET ")
                      & Var_Name_Str & " = " & Debug_Value (Result));
```

For array element assignment, add a Debug_Trace call in the three assignment branches (slice, list, single). After the scalar block, array assignments are in separate `if Stmt.Is_Array then` branches. Add after each `Set_Array_Element` call:

For single-subscript (around line 564):
```ada
               Set_Array_Element (Var_Name_Str, Idx, Result);
               Debug_Trace ((if Stmt.Kind = Stmt_LET then "LET " else "SET ")
                            & Var_Name_Str & "(" & Ada.Strings.Fixed.Trim (Integer'Image (Idx), Ada.Strings.Both)
                            & ") = " & Debug_Value (Result));
```

For slice (the `for I in Lo .. Hi loop`):
```ada
                  for I in Lo .. Hi loop
                     Set_Array_Element (Var_Name_Str, I, Result);
                  end loop;
                  Debug_Trace ((if Stmt.Kind = Stmt_LET then "LET " else "SET ")
                               & Var_Name_Str & "("
                               & Ada.Strings.Fixed.Trim (Integer'Image (Lo), Ada.Strings.Both)
                               & ":"
                               & Ada.Strings.Fixed.Trim (Integer'Image (Hi), Ada.Strings.Both)
                               & ") = " & Debug_Value (Result));
```

For list assignment (after the `while Node /= null` loop ends):
```ada
                  Debug_Trace ((if Stmt.Kind = Stmt_LET then "LET " else "SET ")
                               & Var_Name_Str & "(...) = " & Debug_Value (Result));
```

- [ ] **Step 2: Trace DELETE**

In `Execute_Statement`, in the `when Stmt_DELETE =>` arm:

```ada
         when Stmt_DELETE =>
            Current_Record_Deleted := True;
            Debug_Trace ("DELETE: record marked");
```

- [ ] **Step 3: Trace SELECT filter**

SELECT filter execution is in `Rebuild_Filter_Map`. The filter is applied per-record in a loop. Add after the `SData.Table.Set_Index_Map` call a summary trace:

```ada
               SData.Table.Set_Index_Map (Passing (1 .. Count));
               Debug_Trace ("SELECT → " & Ada.Strings.Fixed.Trim (Natural'Image (Count), Ada.Strings.Both)
                            & " of " & Ada.Strings.Fixed.Trim (Natural'Image (Total), Ada.Strings.Both) & " records kept");
```

Also add per-record kept/dropped trace inside the `for R in 1 .. Total loop` (design spec says `[debug] SELECT → KEPT` or `[debug] SELECT → DROPPED`):

```ada
                  if Is_True (Evaluate (Select_Filter_Expr)) then
                     Count := Count + 1;
                     Passing (Count) := R;
                     Debug_Trace ("SELECT → KEPT (record" & R'Image & ")");
                  else
                     Debug_Trace ("SELECT → DROPPED (record" & R'Image & ")");
                  end if;
```

- [ ] **Step 4: Trace IF condition and ELSE**

In `Execute_Control_Flow`, find the `when Stmt_IF =>` arm. The condition is evaluated and then a branch is taken. Wrap the branch selection:

```ada
            when Stmt_IF =>
               declare
                  Cond_Val : constant Boolean := Is_True (Evaluate (Stmt.Condition));
               begin
                  if Cond_Val then
                     Debug_Trace ("IF → TRUE");
                     Execute_List (Stmt.Then_Branch);
                  else
                     if Stmt.Else_Branch /= null then
                        Debug_Trace ("IF → FALSE");
                        Debug_Trace ("ELSE → taken");
                        Execute_List (Stmt.Else_Branch);
                     else
                        Debug_Trace ("IF → FALSE (skipping)");
                     end if;
                  end if;
               end;
```

Read the existing `Execute_Control_Flow` IF arm before editing to verify the exact structure:
```bash
grep -n "Stmt_IF\|Is_True\|Evaluate\|Then_Branch\|Else_Branch" /home/jries/Develop/sdata/src/sdata-interpreter.adb | head -20
```

- [ ] **Step 5: Trace FOR iteration**

In `Execute_Control_Flow`, in the `when Stmt_FOR =>` arm, find where the loop variable is set each iteration and add a trace there. The loop variable is set via `Set_Temporary` each iteration. Add after the set:

```ada
               --  (existing loop variable assignment)
               Debug_Trace ("FOR " & For_Var_Name & " = " & Debug_Value (Loop_Val));
```

Read the actual FOR arm to confirm the variable name and value:
```bash
grep -n "Stmt_FOR\|For_Var\|For_Body" /home/jries/Develop/sdata/src/sdata-interpreter.adb | head -15
```

- [ ] **Step 6: Trace RUN complete**

The RUN-complete message is emitted in `Execute` (around line 1889):
```ada
               Put_Line ("RUN complete. " & ...);
```

Add a debug trace immediately before or after it (keep the existing `Put_Line` — `Debug_Trace` goes to stderr, `Put_Line` to stdout):

```ada
               Debug_Trace ("RUN complete: "
                            & RC (RC'First + 1 .. RC'Last) & " records, "
                            & VC (VC'First + 1 .. VC'Last) & " variables");
```

- [ ] **Step 7: Trace USE opened**

In `Execute_IO`, in the `when Stmt_USE =>` arm, after the file is opened and record/variable counts are available, add:

```ada
               Debug_Trace ("USE: opened " & Path_Str
                            & " (" & Ada.Strings.Fixed.Trim (Natural'Image (SData.Table.Row_Count), Ada.Strings.Both)
                            & " records, "
                            & Ada.Strings.Fixed.Trim (Natural'Image (SData.Table.Column_Count), Ada.Strings.Both)
                            & " variables)");
```

Read the USE arm to find the right insertion point:
```bash
grep -n "Stmt_USE\|Open_Input\|Row_Count\|Column_Count" /home/jries/Develop/sdata/src/sdata-interpreter.adb | head -20
```

- [ ] **Step 8: Trace SUBMIT entered**

In `Execute_IO`, in the `when Stmt_SUBMIT =>` arm, before the recursive call:

```ada
               Debug_Trace ("SUBMIT: entering " & Path_Str);
```

- [ ] **Step 9: Trace BY group in record header**

The record header `Debug_Trace` call added in Task 3 Step 4 needs BY group annotation. The header is emitted after the BOG/EOG block. Read the current state:

```bash
sed -n '1634,1670p' /home/jries/Develop/sdata/src/sdata-interpreter.adb
```

Replace the simple `Debug_Trace ("-- record ...")` call with an annotated version. The BOG/EOG values and `Current_By_Vars` are in scope:

```ada
      declare
         Header : Ada.Strings.Unbounded.Unbounded_String :=
            Ada.Strings.Unbounded.To_Unbounded_String
               ("-- record" & Logical_I'Image & " (physical" & Phys_I'Image & ")");
      begin
         if SData.Config.Debug_Mode and then not Current_By_Vars.Is_Empty then
            if BOG_Val then
               Ada.Strings.Unbounded.Append (Header, "  [BY GROUP START:");
               for V of Current_By_Vars loop
                  declare
                     Name : constant String := Ada.Strings.Unbounded.To_String (V);
                     Val  : constant Value  := SData.Variables.Get (Name);
                  begin
                     Ada.Strings.Unbounded.Append (Header, " " & Name & "=" & Debug_Value (Val));
                  end;
               end loop;
               Ada.Strings.Unbounded.Append (Header, "]");
            elsif not BOG_Val and then Logical_I > 1 then
               --  Check if any BY var changed from previous record
               --  (EOG of previous record means new group starts next)
               --  We detect a group change by checking if the previous record was EOG.
               --  Since we have BOG/EOG for the current record, if current is not BOG
               --  but previous was EOG, this is a change.  Actually: if BOG_Val is False
               --  for current record, the previous was not EOG.  Group change = current
               --  BOG_Val True (handled above).  Only annotate START/CHANGE on BOG records.
               null;
            end if;
         end if;
         Debug_Trace (Ada.Strings.Unbounded.To_String (Header));
      end;
```

Note: `Ada.Strings.Unbounded` should already be in scope. Verify:
```bash
grep "Ada.Strings.Unbounded" /home/jries/Develop/sdata/src/sdata-interpreter.adb | head -3
```

The BY GROUP CHANGE annotation from the design spec occurs when the BY group variable value differs from the previous record. Since we have group boundaries via `Is_First_In_Group` / `Is_Last_In_Group`, annotate only on `BOG_Val = True` records (which covers both first-record-in-dataset and group transitions). The design's "CHANGE" label is appropriate when `Logical_I > 1 and BOG_Val`. Simplify:

```ada
      declare
         Header : Ada.Strings.Unbounded.Unbounded_String :=
            Ada.Strings.Unbounded.To_Unbounded_String
               ("-- record" & Logical_I'Image & " (physical" & Phys_I'Image & ")");
      begin
         if SData.Config.Debug_Mode and then not Current_By_Vars.Is_Empty
            and then BOG_Val
         then
            declare
               Label : constant String :=
                  (if Logical_I = 1 then "BY GROUP START" else "BY GROUP CHANGE");
            begin
               Ada.Strings.Unbounded.Append (Header, "  [" & Label & ":");
               for V of Current_By_Vars loop
                  declare
                     Name : constant String := Ada.Strings.Unbounded.To_String (V);
                     Val  : constant Value  := SData.Variables.Get (Name);
                  begin
                     Ada.Strings.Unbounded.Append
                        (Header, " " & Name & "=" & Debug_Value (Val));
                  end;
               end loop;
               Ada.Strings.Unbounded.Append (Header, "]");
            end;
         end if;
         Debug_Trace (Ada.Strings.Unbounded.To_String (Header));
      end;
```

This block needs `BOG_Val` in scope, so it must live inside the same `declare` block that computes `BOG_Val`. Check the existing code around line 1648 — `BOG_Val` is declared in a nested `declare` block. Move the header emission into that block.

- [ ] **Step 10: Update the expected test output and run**

Now update `tests/expected/debug_trace.out` to match the actual trace output including LET traces:

```
[debug] -- record 1 (physical 1)
[debug] LET X = 1
[debug] -- record 2 (physical 2)
[debug] LET X = 2
[debug] -- record 3 (physical 3)
[debug] LET X = 3
RUN complete. 3 records and 1 variables processed.
```

```
alr build && make check 2>&1 | grep -E "debug_trace|PASSED|FAILED"
```
Expected: `debug_trace` test PASSED. All others still pass.

- [ ] **Step 11: Commit**

```bash
git add src/sdata-interpreter.adb tests/debug_trace.cmd tests/debug_trace.flags tests/expected/debug_trace.out
git commit -m "Enrich --debug passive trace with per-statement and BY group annotation"
```

---

## Task 5: Inspection mini-REPL

**Files:**
- Modify: `src/sdata-interpreter.adb`

The REPL is a private procedure `Inspect_PDV` that:
1. Records the execution record index (so `CONTINUE` resumes at the right row)
2. Loops reading lines from stdin
3. Dispatches `PRINT`, `RECORD`, `CONTINUE`/`C`, `STEP`/`S`, `RUN` commands
4. Returns a `Step_Action` tag to the caller

- [ ] **Step 1: Define `Step_Action` type**

Near the top of the package body (after `Debug_Value`), add:

```ada
   type Step_Action is (Action_Continue, Action_Step, Action_Run);
   --  Return value from Inspect_PDV:
   --    Action_Continue — process current record, then pause again (CONTINUE or STEP)
   --    Action_Run      — process current and all remaining records without pausing
```

- [ ] **Step 2: Write `Inspect_PDV`**

Add the following procedure to the package body (before `Execute_Statement`):

```ada
   procedure Inspect_PDV
     (Logical_I     :        Positive;
      Logical_Count :        Natural;
      Action        :    out Step_Action)
   is
      use Ada.Strings.Unbounded;
      use Ada.Characters.Handling;

      Inspect_I   : Positive := Logical_I;
      Saved_Phys  : constant Positive :=
         SData.Table.Logical_To_Physical (Logical_I);

      procedure Load_Inspect_Record (L : Positive) is
         P : constant Positive := SData.Table.Logical_To_Physical (L);
      begin
         SData.Table.Set_Current_Record_Index (P);
         SData.Variables.Load_PDV_From_Table (P);
         Put_Line_Error ("[debug] loaded record" & L'Image & " into PDV");
      end Load_Inspect_Record;

   begin
      Action := Action_Continue;

      if not SData.IO.Is_Interactive then
         Put_Line_Error ("[debug] BREAK: record" & Logical_I'Image
                         & " paused (non-interactive — continuing)");
         return;
      end if;

      loop
         declare
            Prompt : constant String :=
               "[debug:record" & Ada.Strings.Fixed.Trim (Positive'Image (Inspect_I), Ada.Strings.Both) & "]> ";
            Line   : Ada.Strings.Unbounded.Unbounded_String;
         begin
            Put_Error (Prompt);
            Ada.Text_IO.Unbounded_IO.Get_Line (Ada.Text_IO.Standard_Error, Line);
            declare
               S     : constant String := Ada.Strings.Fixed.Trim (To_String (Line), Ada.Strings.Both);
               Upper : constant String := To_Upper (S);
            begin
               if Upper = "CONTINUE" or else Upper = "C" then
                  --  Restore execution record and return
                  SData.Table.Set_Current_Record_Index (Saved_Phys);
                  SData.Variables.Load_PDV_From_Table (Saved_Phys);
                  Action := Action_Continue;
                  return;

               elsif Upper = "STEP" or else Upper = "S" then
                  SData.Table.Set_Current_Record_Index (Saved_Phys);
                  SData.Variables.Load_PDV_From_Table (Saved_Phys);
                  Action := Action_Step;
                  return;

               elsif Upper = "RUN" then
                  SData.Table.Set_Current_Record_Index (Saved_Phys);
                  SData.Variables.Load_PDV_From_Table (Saved_Phys);
                  Action := Action_Run;
                  return;

               elsif Upper'Length >= 6 and then Upper (Upper'First .. Upper'First + 5) = "RECORD" then
                  --  Parse RECORD N, RECORD +N, RECORD -N
                  declare
                     Rest   : constant String :=
                        Ada.Strings.Fixed.Trim (S (S'First + 6 .. S'Last), Ada.Strings.Both);
                     Target : Integer;
                  begin
                     if Rest'Length = 0 then
                        Put_Line_Error ("Usage: RECORD N | RECORD +N | RECORD -N");
                     else
                        if Rest (Rest'First) = '+' then
                           Target := Inspect_I +
                              Integer'Value (Rest (Rest'First + 1 .. Rest'Last));
                        elsif Rest (Rest'First) = '-' then
                           Target := Inspect_I -
                              Integer'Value (Rest (Rest'First + 1 .. Rest'Last));
                        else
                           Target := Integer'Value (Rest);
                        end if;
                        --  Clamp to [1 .. Logical_Count]
                        if Target < 1 then Target := 1; end if;
                        if Target > Logical_Count then Target := Logical_Count; end if;
                        Inspect_I := Target;
                        Load_Inspect_Record (Inspect_I);
                     end if;
                  exception
                     when Constraint_Error =>
                        Put_Line_Error ("Invalid record number: " & Rest);
                  end;

               elsif S'Length >= 5
                  and then To_Upper (S (S'First .. S'First + 4)) = "PRINT"
               then
                  --  Evaluate the expression after PRINT using the existing evaluator
                  declare
                     Expr_Str : constant String :=
                        Ada.Strings.Fixed.Trim (S (S'First + 5 .. S'Last), Ada.Strings.Both);
                  begin
                     if Expr_Str'Length = 0 then
                        Put_Line_Error ("Usage: PRINT <expr>");
                     else
                        declare
                           Ctx    : SData.Parser.Parser_Context;
                           Expr_A : SData.AST.Expression_Access;
                           Val    : Value;
                        begin
                           SData.Parser.Initialize (Ctx, Expr_Str);
                           Expr_A := SData.Parser.Parse_Expression (Ctx);
                           Val := Evaluate (Expr_A);
                           SData.AST.Free_Expression (Expr_A);
                           Put_Line (To_String_Formatted (Val));
                        exception
                           when E : others =>
                              Put_Line_Error ("Error: " & Ada.Exceptions.Exception_Message (E));
                        end;
                     end if;
                  end;

               elsif S'Length = 0 then
                  null;  --  Empty line: re-show prompt

               else
                  Put_Line_Error ("Unknown command: " & S);
                  Put_Line_Error ("Commands: PRINT <expr>  RECORD N/+N/-N  CONTINUE  STEP  RUN");
               end if;
            end;
         end;
      end loop;
   end Inspect_PDV;
```

This procedure needs `Ada.Text_IO.Unbounded_IO` and `SData.Parser` (for `Parse_Expression`). Check what's already with'd in the interpreter:

```bash
grep -n "^with\|^use" /home/jries/Develop/sdata/src/sdata-interpreter.adb | head -30
```

Add any missing `with` clauses at the top of `sdata-interpreter.adb`. Likely needed:
- `with Ada.Text_IO.Unbounded_IO;`  (for `Get_Line` to `Unbounded_String`)

`SData.Parser` may already be with'd for `Parse_Statement`; check and add if missing. Also check `Put_Error` — it emits to stderr without newline; verify it exists in `SData.IO` or use `Ada.Text_IO.Put (Ada.Text_IO.Standard_Error, Prompt)`.

```bash
grep -n "Put_Error\|procedure Put" /home/jries/Develop/sdata/src/sdata-io.ads
```

If `Put_Error` doesn't exist, use:
```ada
            Ada.Text_IO.Put (Ada.Text_IO.Standard_Error, Prompt);
```

- [ ] **Step 3: Build and verify**

```
alr build 2>&1 | tail -10
```
Expected: clean build.

- [ ] **Step 4: Commit**

```bash
git add src/sdata-interpreter.adb
git commit -m "Add Inspect_PDV REPL procedure"
```

---

## Task 6: Wire BREAK handler and step mode

**Files:**
- Modify: `src/sdata-interpreter.adb`

- [ ] **Step 1: Implement `Stmt_BREAK` in `Execute_Statement`**

Replace the stub `when Stmt_BREAK => null;` with the real handler:

```ada
         when Stmt_BREAK =>
            --  BREAK fires immediately if unconditional; otherwise only when condition is true.
            --  Inspect_PDV is called in Process_One_Record (which has Logical_I/Count in scope),
            --  so here we only need to raise a dedicated exception that Process_One_Record catches.
            if Stmt.Expr = null or else Is_True (Evaluate (Stmt.Expr)) then
               raise Break_Triggered;
            end if;
```

`Break_Triggered` is a new exception. Declare it near the top of the package body:

```ada
   Break_Triggered : exception;
```

- [ ] **Step 2: Add `Step_Mode` flag and handle `Break_Triggered` in `Process_One_Record`**

`Process_One_Record` needs to know whether to enter the REPL and what action to return upward. Add a parameter:

```ada
   procedure Process_One_Record (Logical_I        : Positive;
                                  Logical_Count    : Natural;
                                  Start            : Statement_Access;
                                  Boundary         : Statement_Access;
                                  Global_Has_Write : Boolean;
                                  Pause_After      : Boolean := False;
                                  Action           : out Step_Action) is
```

Inside the procedure, after the statement loop (`while Iter /= null ...`), add:

```ada
      --  Handle pause: explicit BREAK or step mode
      declare
         Should_Pause : Boolean := Pause_After;
      begin
         null;  --  populated in step 3 below
      end;
```

Wrap the inner statement loop in a handler for `Break_Triggered`:

```ada
      begin
         while Iter /= null and then Iter /= Boundary loop
            case Iter.Kind is
               when Stmt_LET | Stmt_SET | ... | Stmt_BREAK | ... =>
                  begin
                     Execute_Statement (Iter);
                  exception
                     when Break_Triggered =>
                        Inspect_PDV (Logical_I, Logical_Count, Action);
                        goto After_Loop;
                     when E : Script_Error => ...
                     when E : others => ...
                  end;
               when others => null;
            end case;
            exit when Current_Record_Deleted;
            Iter := Iter.Next;
         end loop;
         <<After_Loop>>
      end;
```

After the loop (label `After_Loop`), if `Pause_After` is true (step mode) and no BREAK already fired, call `Inspect_PDV`:

```ada
      if Pause_After then
         Inspect_PDV (Logical_I, Logical_Count, Action);
      else
         Action := Action_Run;  --  no pause: just keep going
      end if;
```

Note: Ada labeled loops require `<<Label>>` before the statement that follows the exit point. Alternatively, use a `Done : Boolean` flag instead of a goto. The goto is simpler here:

```ada
      Loop_Done : declare
         Break_Fired : Boolean := False;
         Act         : Step_Action := Action_Continue;
      begin
         begin
            while Iter /= null and then Iter /= Boundary loop
               ...
               begin
                  Execute_Statement (Iter);
               exception
                  when Break_Triggered =>
                     Inspect_PDV (Logical_I, Logical_Count, Act);
                     Break_Fired := True;
                     exit;
                  ...
               end;
               exit when Current_Record_Deleted;
               Iter := Iter.Next;
            end loop;
         end;
         if not Break_Fired and then Pause_After then
            Inspect_PDV (Logical_I, Logical_Count, Act);
         end if;
         Action := Act;
      end Loop_Done;
```

- [ ] **Step 3: Thread `Step_Action` through `Run_One_Step`**

`Run_One_Step` calls `Process_One_Record` in a loop. Thread the step mode through:

```ada
   procedure Run_One_Step (Start, Boundary : Statement_Access) is
      ...
      Step_Mode : Boolean := SData.Config.Debug_Mode and SData.IO.Is_Interactive;
      Act       : Step_Action := Action_Continue;
   begin
      ...
      for Logical_I in 1 .. Logical_Count loop
         Process_One_Record (Logical_I, Logical_Count, Start, Boundary,
                             Global_Has_Write,
                             Pause_After => Step_Mode,
                             Action      => Act);
         if Act = Action_Run then
            Step_Mode := False;  --  RUN command: disable further pausing
         end if;
      end loop;
      ...
   end Run_One_Step;
```

For all existing calls to `Process_One_Record` (there is only one, in `Run_One_Step`), the new parameters have defaults so no other callers need updating.

- [ ] **Step 4: Build and verify**

```
alr build 2>&1 | tail -10
```
Expected: clean build.

- [ ] **Step 5: Commit**

```bash
git add src/sdata-interpreter.adb
git commit -m "Wire BREAK handler and step-mode pause into data step execution"
```

---

## Task 7: Write BREAK tests

**Files:**
- Create: `tests/break_basic.cmd`
- Create: `tests/expected/break_basic.out`
- Create: `tests/break_when.cmd`
- Create: `tests/expected/break_when.out`

The test harness is non-interactive (stdin is not a TTY), so `Inspect_PDV` will emit the non-interactive message and return immediately.

- [ ] **Step 1: Create `break_basic.cmd`**

```
NEW
REPEAT 2
LET X = RECNO()
BREAK
RUN
PRINT X
RUN
QUIT
```

- [ ] **Step 2: Determine expected output and create `break_basic.out`**

Run the test manually to capture actual output:
```bash
./bin/sdata tests/break_basic.cmd > /tmp/break_basic_actual.txt 2>&1
cat /tmp/break_basic_actual.txt
```

The expected output should be:
```
[debug] BREAK: record 1 paused (non-interactive — continuing)
[debug] BREAK: record 2 paused (non-interactive — continuing)
RUN complete. 2 records and 1 variables processed.
1
2
RUN complete. 2 records and 1 variables processed.
```

If the actual output differs, update accordingly. Copy it:
```bash
cp /tmp/break_basic_actual.txt tests/expected/break_basic.out
```

- [ ] **Step 3: Create `break_when.cmd`**

```
NEW
REPEAT 3
LET X = RECNO()
BREAK WHEN RECNO() = 2
RUN
PRINT X
RUN
QUIT
```

- [ ] **Step 4: Determine expected output and create `break_when.out`**

```bash
./bin/sdata tests/break_when.cmd > /tmp/break_when_actual.txt 2>&1
cat /tmp/break_when_actual.txt
```

Expected:
```
[debug] BREAK: record 2 paused (non-interactive — continuing)
RUN complete. 3 records and 1 variables processed.
1
2
3
RUN complete. 3 records and 1 variables processed.
```

Copy to expected:
```bash
cp /tmp/break_when_actual.txt tests/expected/break_when.out
```

- [ ] **Step 5: Run full test suite**

```
make check 2>&1 | tail -5
```
Expected: all tests pass (including the 3 new debug/BREAK tests).

- [ ] **Step 6: Commit**

```bash
git add tests/break_basic.cmd tests/expected/break_basic.out \
        tests/break_when.cmd tests/expected/break_when.out
git commit -m "Add BREAK and BREAK WHEN tests"
```

---

## Task 8: Update the man page

**Files:**
- Modify: `man/man1/sdata.1`

- [ ] **Step 1: Find insertion point for BREAK**

```bash
grep -n "DELETE\|BREAK\|\.SS\|\.TP" /home/jries/Develop/sdata/man/man1/sdata.1 | head -30
```

- [ ] **Step 2: Add BREAK entry in the COMMANDS section**

Add after the DELETE entry:

```nroff
.TP
.B BREAK
Pauses execution and enters the interactive debug inspection REPL (see
.BR \-\-debug ).
Has no effect when stdin is not a TTY\[char46]
.TP
.B BREAK WHEN \fIexpr\fR
Pauses only when the boolean expression
.I expr
evaluates to true (e\[char46]g\[char46],
.B BREAK WHEN RECNO() = 50
or
.B BREAK WHEN SALARY > 100000 ).
Valid only inside a data step.
```

- [ ] **Step 3: Expand the `--debug` option description**

Find the `--debug` option entry:
```bash
grep -n "debug\|Debug" /home/jries/Develop/sdata/man/man1/sdata.1 | head -10
```

Replace or expand the existing entry to describe:
- Enriched trace output to stderr for LET/SET, IF, SELECT, DELETE, FOR, BY group, USE, RUN, SUBMIT
- Step mode: pauses before each record's statements with an interactive `[debug:record N]>` prompt
- Inspection commands: `PRINT <expr>`, `RECORD N / +N / -N`, `CONTINUE`, `STEP`, `RUN`

- [ ] **Step 4: Build and run tests**

```
alr build && make check 2>&1 | tail -5
```
Expected: all tests pass.

- [ ] **Step 5: Commit**

```bash
git add man/man1/sdata.1
git commit -m "Document BREAK/BREAK WHEN and enriched --debug in man page"
```

---

## Spec Coverage Checklist

| Spec Requirement | Task |
|---|---|
| `Debug_Trace` / `Debug_Value` helpers | Task 3 |
| Replace existing inline debug blocks | Task 3 |
| LET/SET scalar trace | Task 4 step 1 |
| LET/SET array element trace | Task 4 step 1 |
| IF/ELSE trace | Task 4 step 4 |
| SELECT filter per-record trace | Task 4 step 3 |
| DELETE trace | Task 4 step 2 |
| FOR iteration trace | Task 4 step 5 |
| BY group annotation on record header | Task 4 step 9 |
| USE opened trace | Task 4 step 7 |
| RUN complete trace | Task 4 step 6 |
| SUBMIT entered trace | Task 4 step 8 |
| `Stmt_BREAK` AST node | Task 2 step 1 |
| `Token_BREAK` lexer keyword | Task 1 |
| Parse `BREAK` / `BREAK WHEN <expr>` | Task 2 step 2 |
| Resolve BREAK condition expression | Task 2 step 3 |
| `Inspect_PDV` REPL (PRINT/RECORD/CONTINUE/STEP/RUN) | Task 5 |
| `RECORD +N / -N` relative navigation | Task 5 step 2 |
| Non-interactive context: auto-continue | Task 5 step 2 |
| Step mode under `--debug` | Task 6 step 3 |
| `break_basic.cmd` test | Task 7 |
| `break_when.cmd` test | Task 7 |
| `debug_trace.cmd` test | Task 3 step 1 |
| Man page BREAK entry | Task 8 |
| Man page `--debug` expansion | Task 8 |
