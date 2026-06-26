# INSERT Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an immediate `INSERT [n|$]` command that positions a sticky insertion cursor in the REPL program buffer so deferred statements land at a chosen point instead of only at the end.

**Architecture:** New lexer token (`Token_INSERT`) and standalone-`$` token (`Token_Dollar`); new AST node `Stmt_PROGRAM_INSERT`; parser rule; interpreter cursor state (`Append_Mode`/`Insert_Point`) honored by `Add_To_Active_Program`, set by a new `Execute_Program_Insert`, reset by `Clear_Active_Program`, and adjusted by `Execute_Program_Delete`; `LIST` gains a marker line. Pure `sdata`-crate change — `sdata-core` is untouched.

**Tech Stack:** Ada 2012, GNAT via Alire (`alr build`), `make check` test harness. Spec: `doc/specs/2026-06-26-insert-command-design.md`.

## Global Constraints

- **`sdata` crate only.** Do not modify `~/Develop/sdata-core/src/`. No version bump of either crate is required for this feature work itself (the maintainer bumps `sdata`'s version separately when releasing).
- **Cursor is sticky:** persists across `RUN`; reset to append only by `NEW` (via `Clear_Active_Program`) or another `INSERT`.
- **Out-of-range `INSERT n` (n > buffer length): warn AND clamp to end** (append mode).
- **REPL-only behavior.** The program buffer (`Active_Program_Vec`) is populated only in interactive mode; the `.cmd` integration harness runs batch mode where the buffer stays empty (see `tests/list_test.cmd`). Therefore **all behavioral tests for this feature are unit tests in `tests/interpreter_unit_test.adb`**, driven through the public REPL API and (for display) `SData_Core.IO.Open_Output` capture. Do NOT attempt `.cmd` integration tests for cursor/LIST behavior.
- **User-facing surface must stay in sync** (per `CLAUDE.md`): built-in HELP (+ regenerate `tests/expected/help_all.out`), man page `man/man1/sdata.1`, and `doc/design.md` — all updated in Task 5.
- **`make check` must be fully green before each commit** (5 unit-test binaries + 202 integration tests). Never use `--no-verify`.
- Commit message trailer: end every commit with
  `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `src/lexer/sdata-lexer.ads` | Declare `Token_INSERT`, `Token_Dollar` | 1 |
| `src/lexer/sdata-lexer.adb` | Map `"INSERT"` keyword; map standalone `$` | 1 |
| `src/ast/sdata-ast.ads` | `Stmt_PROGRAM_INSERT` enum literal + variant fields | 1 |
| `src/parser/sdata-parser.adb` | Parse `INSERT [n｜$]` → `Stmt_PROGRAM_INSERT` | 1 |
| `src/sdata-reserved_keywords.adb` | Add `"INSERT"` to reserved-word set | 1 |
| `src/sdata-interpreter.adb` | Cursor state, `Execute_Program_Insert`, `Add_To_Active_Program` honoring cursor, `Is_Immediate`, dispatch, `Clear_Active_Program` reset, DELETE adjustment | 2, 3 |
| `src/sdata-interpreter-execute_metadata.adb` | `LIST` marker line | 4 |
| `tests/interpreter_unit_test.adb` | All behavioral unit tests (parser, cursor, DELETE adjust, LIST capture) | 1–4 |
| `src/sdata-help.adb` | `Help_INSERT`, dispatch table, summary lines | 5 |
| `tests/expected/help_all.out` | Regenerated HELP /ALL snapshot | 5 |
| `man/man1/sdata.1` | `INSERT` man entry | 5 |
| `doc/design.md` | `INSERT` command-table row | 5 |

---

### Task 1: Parse `INSERT [n|$]` into `Stmt_PROGRAM_INSERT`

Lexer token + standalone `$` token + AST node + parser rule + reserved-word entry. Deliverable: the parser turns `INSERT`, `INSERT 0`, `INSERT 5`, `INSERT $` into a `Stmt_PROGRAM_INSERT` node with correct fields. Verified by a parser unit test.

**Files:**
- Modify: `src/lexer/sdata-lexer.ads` (token enum)
- Modify: `src/lexer/sdata-lexer.adb` (keyword map + symbol dispatch)
- Modify: `src/ast/sdata-ast.ads` (enum literal + variant)
- Modify: `src/parser/sdata-parser.adb` (case arm)
- Modify: `src/sdata-reserved_keywords.adb` (reserved set)
- Test: `tests/interpreter_unit_test.adb`

**Interfaces:**
- Produces (AST): `Stmt_PROGRAM_INSERT` with fields `Insert_At_End : Boolean := True;`, `Insert_Line : Natural := 0;`, and `Insert_Bad : Boolean := False;`. `Insert_At_End = True` means "append at end" (`$`, bare `INSERT`, or out-of-range — though range is checked later in Task 2). `Insert_At_End = False` with `Insert_Line = n` means "after line n" (`n = 0` = beginning). `Insert_Bad = True` means the argument was negative (e.g. `INSERT -3`) — a runtime warning + no-op, handled in Task 2.
- Produces (lexer): `Token_INSERT`, `Token_Dollar`.

- [ ] **Step 1: Write the failing test**

Add a new helper and test section to `tests/interpreter_unit_test.adb`. Place the helper next to the existing `Run` helper (after line 104), and the test block in a new section near the end of the test body (before the final summary print). The helper parses one statement and returns its head node without executing it:

```ada
   --  Parse a single statement and return its AST head (caller frees).
   function Parse_One (Source : String) return Statement_Access is
      Ctx : SData.Parser.Parser_Context;
   begin
      SData.Parser.Initialize (Ctx, Source);
      return SData.Parser.Parse_Program (Ctx);
   end Parse_One;
```

Test block (new section "I: INSERT command"):

```ada
   Put_Line ("--- I: INSERT command ---");

   --  IN-01: INSERT $ parses to end-of-buffer.
   declare
      P : Statement_Access := Parse_One ("INSERT $");
   begin
      Check ("IN-01: INSERT $ kind", P.Kind = Stmt_PROGRAM_INSERT, True);
      Check ("IN-01: INSERT $ at end", P.Insert_At_End, True);
      SData.AST.Free_Program (P);
   end;

   --  IN-02: bare INSERT defaults to end-of-buffer.
   declare
      P : Statement_Access := Parse_One ("INSERT");
   begin
      Check ("IN-02: bare INSERT at end", P.Insert_At_End, True);
      SData.AST.Free_Program (P);
   end;

   --  IN-03: INSERT 0 parses to beginning (line 0).
   declare
      P : Statement_Access := Parse_One ("INSERT 0");
   begin
      Check ("IN-03: INSERT 0 not-at-end", P.Insert_At_End, False);
      Check ("IN-03: INSERT 0 line", P.Insert_Line, 0);
      SData.AST.Free_Program (P);
   end;

   --  IN-04: INSERT 5 parses to after line 5.
   declare
      P : Statement_Access := Parse_One ("INSERT 5");
   begin
      Check ("IN-04: INSERT 5 not-at-end", P.Insert_At_End, False);
      Check ("IN-04: INSERT 5 line", P.Insert_Line, 5);
      SData.AST.Free_Program (P);
   end;

   --  IN-04b: INSERT -3 parses as an invalid (negative) argument.
   declare
      P : Statement_Access := Parse_One ("INSERT -3");
   begin
      Check ("IN-04b: INSERT -3 flagged bad", P.Insert_Bad, True);
      SData.AST.Free_Program (P);
   end;
```

(`Check` for `Boolean` and `Integer` already exist at lines 32 and 44; `Insert_Line` is `Natural`, which the `Integer` overload accepts.)

- [ ] **Step 2: Run the test to verify it fails to compile**

Run: `cd ~/Develop/sdata && alr build 2>&1 | head -30`
Expected: compile error — `Stmt_PROGRAM_INSERT` / `Insert_At_End` / `Insert_Line` not declared (proves the new symbols don't exist yet).

- [ ] **Step 3: Add the lexer tokens**

In `src/lexer/sdata-lexer.ads`, add `Token_INSERT` to the keyword group (line 30, alongside `Token_LIST`):

```ada
      Token_REM, Token_HELP, Token_END, Token_RUN, Token_QUIT, Token_NAMES, Token_LIST, Token_DISPLAY,
      Token_INSERT,
```

Add `Token_Dollar` to the punctuation group (line 40, after `Token_Dot`):

```ada
      Token_Comma, Token_Semicolon, Token_Colon, Token_Dot, -- ,, ;, :, .
      Token_Dollar,          -- standalone $ (INSERT $)
```

In `src/lexer/sdata-lexer.adb`, add the keyword mapping next to the `LIST` mapping (line 325):

```ada
               elsif Upper = "LIST" then T.Kind := Token_LIST;
               elsif Upper = "INSERT" then T.Kind := Token_INSERT;
```

Add a `$` arm to the symbol dispatch `case` (after the `':'` arm at line 439):

```ada
               when ':' => T.Kind := Token_Colon; Advance (Ctx);
               when '$' =>
                  T.Kind := Token_Dollar;
                  T.Text (1) := '$';
                  T.Length := 1;
                  Advance (Ctx);
```

- [ ] **Step 4: Add the AST node**

In `src/ast/sdata-ast.ads`, add the enum literal after `Stmt_TRANSPOSE` (line 296). Add a comma after `Stmt_TRANSPOSE` and the new literal:

```ada
      Stmt_TRANSPOSE,      -- Reshape table columns to rows (immediate)
      Stmt_PROGRAM_INSERT  -- Set program-buffer insertion cursor (immediate)
   );
```

Add the variant fields before the `when others => null;` arm of the `Statement` record (line 303):

```ada
         when Stmt_PROGRAM_INSERT =>
            Insert_At_End : Boolean := True;   --  True = append at end ($/bare)
            Insert_Line   : Natural := 0;      --  cursor after line N (0 = start)
            Insert_Bad    : Boolean := False;  --  negative/invalid argument
         when others =>
            null;
```

- [ ] **Step 5: Add the parser rule**

In `src/parser/sdata-parser.adb`, add a `when Token_INSERT =>` arm to the main statement `case` (immediately after the `when Token_DELETE => ... end;` block that ends at line 2650):

```ada
         when Token_INSERT =>
            --  INSERT [ n | $ ] — set the program-buffer insertion cursor.
            --  Numeric n -> after line n (0 = beginning).  $ or nothing -> end.
            Stmt := new Statement (Stmt_PROGRAM_INSERT);
            declare
               Next_Tok : constant Token := Peek_Next_Token (Ctx.Lex_Ctx);
            begin
               if Next_Tok.Kind = Token_Numeric_Literal then
                  declare
                     Num_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                  begin
                     Stmt.Insert_At_End := False;
                     Stmt.Insert_Line   :=
                        Natural (Float'Value (Num_Tok.Text (1 .. Num_Tok.Length)));
                  end;
               elsif Next_Tok.Kind = Token_Minus then
                  --  Negative argument (e.g. INSERT -3): consume the '-' and the
                  --  following number (if any) so they do not dangle, and flag
                  --  the statement invalid for a runtime warning (Task 2).
                  declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                  begin null; end;
                  if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Numeric_Literal then
                     declare Discard2 : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                     begin null; end;
                  end if;
                  Stmt.Insert_At_End := False;
                  Stmt.Insert_Bad    := True;
               elsif Next_Tok.Kind = Token_Dollar then
                  --  Consume the $; end-of-buffer is the default.
                  declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                  begin null; end;
                  Stmt.Insert_At_End := True;
               else
                  --  Bare INSERT — end of buffer.
                  Stmt.Insert_At_End := True;
               end if;
            end;
```

- [ ] **Step 6: Add INSERT to the reserved-word mirror**

In `src/sdata-reserved_keywords.adb`, add the entry in alphabetical position (between `"INTO"` at line 42 and `"JOIN"` at line 43):

```ada
      S.Insert ("INTO");
      S.Insert ("INSERT");
      S.Insert ("JOIN");
```

- [ ] **Step 7: Build and run the parser test**

Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -20 && ./bin/interpreter_unit_test 2>&1 | grep -E "IN-0|FAIL"`
Expected: `IN-01`..`IN-04` all `PASS`; no `FAIL` lines.

- [ ] **Step 8: Full check**

Run: `cd ~/Develop/sdata && make check 2>&1 | tail -15`
Expected: all 5 unit binaries pass and `All 202 tests passed.` (No `.cmd` output changed — `INSERT` is not yet exercised in batch scripts, and `help_all.out` is untouched until Task 5.)

- [ ] **Step 9: Commit**

```bash
cd ~/Develop/sdata
git add src/lexer/sdata-lexer.ads src/lexer/sdata-lexer.adb src/ast/sdata-ast.ads \
        src/parser/sdata-parser.adb src/sdata-reserved_keywords.adb tests/interpreter_unit_test.adb
git commit -m "feat(insert): lexer token, AST node, parser rule for INSERT [n|\$]

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Cursor state — INSERT sets it, Add_To_Active_Program honors it

The interpreter gains `Append_Mode`/`Insert_Point` state. `Execute_Program_Insert` sets it (with confirmation + out-of-range clamp), `Add_To_Active_Program` inserts at the cursor and advances it, `Clear_Active_Program` resets it, `Is_Immediate` + dispatch route the statement. Deliverable: queued statements insert at the cursor; verified by ordering + clamp + reset + confirmation unit tests.

**Files:**
- Modify: `src/sdata-interpreter.adb`
- Test: `tests/interpreter_unit_test.adb`

**Interfaces:**
- Consumes: `Stmt_PROGRAM_INSERT` (`Insert_At_End`, `Insert_Line`) from Task 1; public `Add_To_Active_Program`, `Run_Active_Program`, `Clear_Active_Program`, `Program_Buffer_Length`, `Execute` (from `src/sdata-interpreter.ads`); `SData_Core.IO.Open_Output`/`Close_Output`.
- Produces: internal `procedure Execute_Program_Insert (Stmt : Statement_Access);`; internal state `Append_Mode : Boolean`, `Insert_Point : Natural`.

- [ ] **Step 1: Write the failing tests**

Add a buffer-driven helper and an output-capture helper to `tests/interpreter_unit_test.adb`. Put helpers near `Parse_One` (added in Task 1):

```ada
   --  Queue one deferred statement through the REPL buffer path (honors cursor).
   procedure Queue (Source : String) is
   begin
      SData.Interpreter.Add_To_Active_Program (Parse_One (Source), Source);
   end Queue;

   --  Execute one immediate statement (e.g. INSERT / LIST) through the REPL.
   procedure Immediate (Source : String) is
      P : Statement_Access := Parse_One (Source);
   begin
      SData.Interpreter.Execute (P);
      SData.AST.Free_Program (P);
   end Immediate;

   --  Read an entire text file into a String (for output-capture asserts).
   function Slurp (Path : String) return String is
      F   : Ada.Text_IO.File_Type;
      Acc : Unbounded_String := Null_Unbounded_String;
   begin
      Ada.Text_IO.Open (F, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (F) loop
         Append (Acc, Ada.Text_IO.Get_Line (F) & ASCII.LF);
      end loop;
      Ada.Text_IO.Close (F);
      return To_String (Acc);
   end Slurp;
```

Ensure the test unit has the needed `with`/`use` at the top: `with Ada.Text_IO;`, `with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;`, and `with SData_Core.IO;`. Check the existing context clauses first and add only those not already present.

Test block (append to the "I: INSERT command" section):

```ada
   --  IN-05: default queueing appends (control case): X ends at 2.
   SData.Interpreter.Clear_Active_Program;
   Queue ("LET X = 1");
   Queue ("LET X = 2");
   SData.Interpreter.Run_Active_Program;
   Check ("IN-05: append order -> X=2", GI ("X"), 2);

   --  IN-06: INSERT 0 inserts at the front; reversed order -> X ends at 1.
   SData.Interpreter.Clear_Active_Program;
   Queue ("LET X = 1");
   Immediate ("INSERT 0");
   Queue ("LET X = 2");          --  buffer becomes [X=2, X=1]
   SData.Interpreter.Run_Active_Program;
   Check ("IN-06: INSERT 0 front -> X=1", GI ("X"), 1);

   --  IN-07: cursor advances across consecutive inserts (Y then Z after line 0,
   --  inserted in typed order ahead of the original) -> R = 30.
   SData.Interpreter.Clear_Active_Program;
   Queue ("LET R = 10");
   Immediate ("INSERT 0");
   Queue ("LET R = 20");         --  [R=20, R=10]
   Queue ("LET R = 30");         --  [R=20, R=30, R=10]  (cursor advanced)
   SData.Interpreter.Run_Active_Program;
   Check ("IN-07: cursor advances -> R=10", GI ("R"), 10);

   --  IN-08: buffer length grows by one per queued statement regardless of mode.
   SData.Interpreter.Clear_Active_Program;
   Queue ("LET A = 1");
   Immediate ("INSERT 0");
   Queue ("LET A = 2");
   Check ("IN-08: length after insert", SData.Interpreter.Program_Buffer_Length, 2);

   --  IN-09: out-of-range INSERT clamps to end (append) -> X=2.
   SData.Interpreter.Clear_Active_Program;
   Queue ("LET X = 1");
   Immediate ("INSERT 9");       --  buffer has 1 entry; clamp to end
   Queue ("LET X = 2");          --  appended -> [X=1, X=2]
   SData.Interpreter.Run_Active_Program;
   Check ("IN-09: out-of-range clamps to end -> X=2", GI ("X"), 2);

   --  IN-10: NEW/Clear resets the cursor back to append.
   SData.Interpreter.Clear_Active_Program;
   Immediate ("INSERT 0");       --  cursor at front...
   SData.Interpreter.Clear_Active_Program;  --  ...reset by Clear (NEW path)
   Queue ("LET X = 1");
   Queue ("LET X = 2");          --  must append -> [X=1, X=2]
   SData.Interpreter.Run_Active_Program;
   Check ("IN-10: Clear resets cursor -> X=2", GI ("X"), 2);

   --  IN-17: negative INSERT is rejected and leaves the cursor unchanged.
   --  Cursor parked at beginning; INSERT -3 is a no-op, so the next queued
   --  statement still inserts at the front -> [X=2, X=1] -> final X=1.
   SData.Interpreter.Clear_Active_Program;
   Queue ("LET X = 1");
   Immediate ("INSERT 0");       --  cursor at beginning
   Immediate ("INSERT -3");      --  rejected; cursor unchanged
   Queue ("LET X = 2");          --  still inserts at front -> [X=2, X=1]
   SData.Interpreter.Run_Active_Program;
   Check ("IN-17: negative INSERT no-op -> X=1", GI ("X"), 1);

   --  IN-11: INSERT prints a confirmation (captured via Open_Output).
   declare
      Cap : constant String := Scratch & "insert_confirm.txt";
   begin
      SData.Interpreter.Clear_Active_Program;
      Queue ("LET A = 1");
      Queue ("LET B = 2");
      SData_Core.IO.Open_Output (Cap);
      Immediate ("INSERT 1");
      SData_Core.IO.Close_Output;
      Check ("IN-11: confirmation text",
             Index (Slurp (Cap), "Insertion point set after line 1.") > 0, True);
   end;
```

Add a `Scratch` constant near the top of the test body (after `begin` at line 168), pointing at a writable temp dir:

```ada
   Scratch : constant String := "/tmp/";
```

(`Index` comes from `Ada.Strings.Unbounded` / `Ada.Strings.Fixed`; `Slurp` returns a `String`, so use `Ada.Strings.Fixed.Index` — add `with Ada.Strings.Fixed; use Ada.Strings.Fixed;` if not already present. The file already uses `Ada.Strings.Fixed.Trim`, so the `with` exists; confirm the `use`.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -20`
Expected: compile error — `Execute_Program_Insert` not declared / `Append_Mode` unknown / `Stmt_PROGRAM_INSERT` not handled in `Execute_Statement`. (If it builds, the cursor logic is missing and IN-06/07/09/10/11 will FAIL at runtime.)

- [ ] **Step 3: Declare cursor state**

In `src/sdata-interpreter.adb`, after the `Pending_Deferred : Natural := 0;` declaration (line 93) add:

```ada
   --  Program-buffer insertion cursor (REPL editing, issue #32).
   --  When Append_Mode is True, newly queued deferred statements append
   --  (default).  When False, they are inserted after line Insert_Point
   --  (0 = before line 1) and the cursor advances past each one.  Sticky:
   --  persists across RUN; reset to append only by NEW (Clear_Active_Program)
   --  or another INSERT.
   Append_Mode  : Boolean := True;
   Insert_Point : Natural := 0;
```

- [ ] **Step 4: Add the forward declaration**

After `procedure Execute_Program_Delete (Stmt : Statement_Access);` (line 127) add:

```ada
   procedure Execute_Program_Insert  (Stmt : Statement_Access);
```

- [ ] **Step 5: Make Add_To_Active_Program honor the cursor**

Replace the body of `Add_To_Active_Program` (lines 352-358) with:

```ada
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
```

- [ ] **Step 6: Reset the cursor in Clear_Active_Program**

In `Clear_Active_Program` (lines 360-370), after `Pending_Deferred := 0;` add:

```ada
      Append_Mode  := True;
      Insert_Point := 0;
```

- [ ] **Step 7: Implement Execute_Program_Insert**

Add the body next to `Execute_Program_Delete` (after its `end Execute_Program_Delete;` at line 781):

```ada
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
```

- [ ] **Step 8: Route the statement (Is_Immediate + dispatch)**

In `Is_Immediate` (lines 97-104) add `Stmt_PROGRAM_INSERT` to the membership set — append it to the final line:

```ada
         Stmt_SYSTEM | Stmt_PROGRAM_DELETE | Stmt_OPTIONS | Stmt_AGGREGATE |
         Stmt_TRANSPOSE | Stmt_PROGRAM_INSERT;
```

In `Execute_Statement`, add a dispatch arm next to `Stmt_PROGRAM_DELETE` (after line 1002):

```ada
         when Stmt_PROGRAM_DELETE =>
            Execute_Program_Delete (Stmt);
         when Stmt_PROGRAM_INSERT =>
            Execute_Program_Insert (Stmt);
```

- [ ] **Step 9: Build and run the cursor tests**

Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -20 && ./bin/interpreter_unit_test 2>&1 | grep -E "IN-0|IN-1|FAIL"`
Expected: `IN-05`..`IN-11` all `PASS`; no `FAIL` lines.

- [ ] **Step 10: Full check**

Run: `cd ~/Develop/sdata && make check 2>&1 | tail -15`
Expected: all unit binaries pass; `All 202 tests passed.`

- [ ] **Step 11: Commit**

```bash
cd ~/Develop/sdata
git add src/sdata-interpreter.adb tests/interpreter_unit_test.adb
git commit -m "feat(insert): sticky insertion cursor honored by program buffer

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: DELETE adjusts the insertion cursor

After a program-buffer `DELETE`, shift/clamp `Insert_Point` so the cursor stays meaningful. Deliverable: deleting lines before/inside/after the cursor moves it correctly; verified by ordering unit tests.

**Files:**
- Modify: `src/sdata-interpreter.adb` (`Execute_Program_Delete`)
- Test: `tests/interpreter_unit_test.adb`

**Interfaces:**
- Consumes: `Append_Mode`, `Insert_Point` (Task 2); existing `Stmt.Delete_From`, `Stmt.Delete_To`.

- [ ] **Step 1: Write the failing tests**

Append to the "I: INSERT command" section in `tests/interpreter_unit_test.adb`:

```ada
   --  IN-12: DELETE before the cursor shifts it back so inserts stay in place.
   --  Buffer [A=1, A=2, A=3]; cursor after line 3; delete line 1 -> buffer
   --  [A=2, A=3], cursor now after line 2 (still the end).  Insert A=9 lands
   --  last -> A=9.
   SData.Interpreter.Clear_Active_Program;
   Queue ("LET A = 1");
   Queue ("LET A = 2");
   Queue ("LET A = 3");
   Immediate ("INSERT 3");        --  cursor after line 3
   Immediate ("DELETE 1");        --  removes A=1; cursor -> after line 2
   Queue ("LET A = 9");           --  appended after A=3 -> [A=2, A=3, A=9]
   SData.Interpreter.Run_Active_Program;
   Check ("IN-12: delete-before shifts cursor -> A=9", GI ("A"), 9);

   --  IN-13: DELETE the line the cursor sits after moves cursor before the
   --  deleted span.  Buffer [B=1, B=2, B=3]; cursor after line 2; delete
   --  line 2 -> [B=1, B=3], cursor -> after line 1.  Insert B=7 -> [B=1, B=7,
   --  B=3] -> final B=3.
   SData.Interpreter.Clear_Active_Program;
   Queue ("LET B = 1");
   Queue ("LET B = 2");
   Queue ("LET B = 3");
   Immediate ("INSERT 2");        --  cursor after line 2
   Immediate ("DELETE 2");        --  cursor inside deleted span -> after line 1
   Queue ("LET B = 7");           --  [B=1, B=7, B=3]
   SData.Interpreter.Run_Active_Program;
   Check ("IN-13: delete-at-cursor -> B=3", GI ("B"), 3);

   --  IN-14: DELETE after the cursor leaves it unchanged.  Buffer
   --  [C=1, C=2, C=3]; cursor after line 1; delete line 3 -> [C=1, C=2],
   --  cursor still after line 1.  Insert C=5 -> [C=1, C=5, C=2] -> final C=2.
   SData.Interpreter.Clear_Active_Program;
   Queue ("LET C = 1");
   Queue ("LET C = 2");
   Queue ("LET C = 3");
   Immediate ("INSERT 1");        --  cursor after line 1
   Immediate ("DELETE 3");        --  after cursor -> unchanged
   Queue ("LET C = 5");           --  [C=1, C=5, C=2]
   SData.Interpreter.Run_Active_Program;
   Check ("IN-14: delete-after-cursor -> C=2", GI ("C"), 2);
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -5 && ./bin/interpreter_unit_test 2>&1 | grep -E "IN-12|IN-13|IN-14"`
Expected: IN-12/IN-13/IN-14 `FAIL` (cursor not yet adjusted on DELETE — e.g. IN-13 would give B=2 not B=3).

- [ ] **Step 3: Adjust the cursor in Execute_Program_Delete**

In `src/sdata-interpreter.adb`, in `Execute_Program_Delete`, after the `Pending_Deferred := Natural'Min (...)` statement (the current last lines, ~779-780) and before `end Execute_Program_Delete;`, add:

```ada
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
```

(`From`/`To` are the already-validated `Stmt.Delete_From`/`Stmt.Delete_To` locals in scope.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -5 && ./bin/interpreter_unit_test 2>&1 | grep -E "IN-12|IN-13|IN-14|FAIL"`
Expected: IN-12/IN-13/IN-14 `PASS`; no `FAIL`.

- [ ] **Step 5: Full check**

Run: `cd ~/Develop/sdata && make check 2>&1 | tail -15`
Expected: all unit binaries pass; `All 202 tests passed.`

- [ ] **Step 6: Commit**

```bash
cd ~/Develop/sdata
git add src/sdata-interpreter.adb tests/interpreter_unit_test.adb
git commit -m "feat(insert): DELETE adjusts the insertion cursor

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: LIST marks the insertion point

`LIST` prints a `--> insertion point` line at the cursor location (when not in append mode) or after the last entry (append mode). Deliverable: captured `LIST` output shows the marker at the right place; verified by output-capture unit tests.

**Files:**
- Modify: `src/sdata-interpreter-execute_metadata.adb` (`Stmt_LIST` arm)
- Test: `tests/interpreter_unit_test.adb`

**Interfaces:**
- Consumes: `Append_Mode`, `Insert_Point` (Task 2). NOTE: these are declared in the parent body `src/sdata-interpreter.adb`; `execute_metadata` is a **separate subunit** of that body, so both variables are directly visible — no new accessor needed.

- [ ] **Step 1: Write the failing tests**

Append to the "I: INSERT command" section:

```ada
   --  IN-15: LIST marks the cursor between lines (cursor after line 1).
   declare
      Cap : constant String := Scratch & "list_mid.txt";
      Out_Txt : Unbounded_String;
   begin
      SData.Interpreter.Clear_Active_Program;
      Queue ("LET A = 1");
      Queue ("LET B = 2");
      Immediate ("INSERT 1");
      SData_Core.IO.Open_Output (Cap);
      Immediate ("LIST");
      SData_Core.IO.Close_Output;
      Out_Txt := To_Unbounded_String (Slurp (Cap));
      --  Marker appears, and it appears before "2: " (i.e. between the lines).
      Check ("IN-15: LIST has marker",
             Index (Out_Txt, "--> insertion point") > 0, True);
      Check ("IN-15: marker before line 2",
             Index (Out_Txt, "--> insertion point") < Index (Out_Txt, "2: "),
             True);
   end;

   --  IN-16: append mode -> marker prints after the last entry.
   declare
      Cap : constant String := Scratch & "list_end.txt";
      Out_Txt : Unbounded_String;
   begin
      SData.Interpreter.Clear_Active_Program;
      Queue ("LET A = 1");
      Queue ("LET B = 2");           --  Append_Mode still True (default)
      SData_Core.IO.Open_Output (Cap);
      Immediate ("LIST");
      SData_Core.IO.Close_Output;
      Out_Txt := To_Unbounded_String (Slurp (Cap));
      Check ("IN-16: marker after last line",
             Index (Out_Txt, "2: ") < Index (Out_Txt, "--> insertion point"),
             True);
   end;
```

(`Index` over `Unbounded_String` comes from `Ada.Strings.Unbounded` — already `with`/`use`d per Task 2.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -5 && ./bin/interpreter_unit_test 2>&1 | grep -E "IN-15|IN-16"`
Expected: IN-15/IN-16 `FAIL` (no marker emitted yet).

- [ ] **Step 3: Emit the marker in the LIST arm**

In `src/sdata-interpreter-execute_metadata.adb`, replace the `Stmt_LIST` arm (lines 181-194) with a version that prints the marker. The marker prints before line 1 (cursor 0), between lines (cursor N), or after the last line (append mode):

```ada
      when Stmt_LIST =>
         --  LIST always shows the program buffer, with the insertion-point
         --  marker at the cursor (issue #32).
         if Active_Program_Vec.Is_Empty then
            Put_Line ("(Empty program buffer)");
         else
            if not Append_Mode and then Insert_Point = 0 then
               Put_Line ("   --> insertion point");
            end if;
            for I in Active_Program_Vec.First_Index .. Active_Program_Vec.Last_Index loop
               declare
                  S : constant String := To_String (Active_Program_Vec (I).Source);
               begin
                  Put (Ada.Strings.Fixed.Trim (I'Image, Ada.Strings.Both) & ": ");
                  Put_Line (if S = "" then "?" else S);
               end;
               if not Append_Mode and then Insert_Point = I then
                  Put_Line ("   --> insertion point");
               end if;
            end loop;
            if Append_Mode then
               Put_Line ("   --> insertion point");
            end if;
         end if;
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -5 && ./bin/interpreter_unit_test 2>&1 | grep -E "IN-15|IN-16|FAIL"`
Expected: IN-15/IN-16 `PASS`; no `FAIL`.

- [ ] **Step 5: Full check**

Run: `cd ~/Develop/sdata && make check 2>&1 | tail -15`
Expected: all unit binaries pass; `All 202 tests passed.` (The `list_test.cmd` integration test runs in batch mode where the buffer is empty — its expected output `(Empty program buffer)` is unchanged because the marker only prints for a non-empty buffer.)

- [ ] **Step 6: Commit**

```bash
cd ~/Develop/sdata
git add src/sdata-interpreter-execute_metadata.adb tests/interpreter_unit_test.adb
git commit -m "feat(insert): LIST marks the insertion point

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: User-facing docs — HELP, man page, design.md

Add the `INSERT` reference to all three user-facing surfaces and regenerate the `HELP /ALL` snapshot. Deliverable: HELP has an `INSERT` topic and lists it in summaries; man page and design doc document `INSERT`; `help_all.out` matches.

**Files:**
- Modify: `src/sdata-help.adb`
- Modify: `tests/expected/help_all.out` (regenerated)
- Modify: `man/man1/sdata.1`
- Modify: `doc/design.md`

- [ ] **Step 1: Add the HELP topic procedure**

In `src/sdata-help.adb`, add a `Help_INSERT` procedure immediately after `Help_DELETE` (after line 310):

```ada
   procedure Help_INSERT is
   begin
      Put_Line ("Command: INSERT");
      Put_Line ("Execution: Immediate -- takes effect at once.");
      Put_Line ("Sets the program-buffer insertion point so that subsequently");
      Put_Line ("entered deferred statements are inserted there instead of appended.");
      Put_Line ("  INSERT 0    Insert before the first line (start of program).");
      Put_Line ("  INSERT n    Insert after existing line n (1-based).");
      Put_Line ("  INSERT $    Insert at the end (append).  This is the default.");
      Put_Line ("  INSERT      Bare form; same as INSERT $.");
      Put_Line ("The cursor is sticky: it persists across RUN and advances as lines");
      Put_Line ("are inserted.  NEW or another INSERT resets it.  n past the end");
      Put_Line ("warns and clamps to the end; a negative n is rejected (no-op).");
      Put_Line ("Only meaningful in interactive (REPL) mode.");
      Put_Line ("See LIST (shows the marker) and DELETE.");
   end Help_INSERT;
```

- [ ] **Step 2: Register the topic (constant + dispatch entry)**

Add the key constant after `K_DELETE` (line 1224):

```ada
   K_DELETE       : aliased constant String := "DELETE";
   K_INSERT       : aliased constant String := "INSERT";
```

Add the dispatch-table entry after the `K_DELETE` row (line 1439):

```ada
      (K_DELETE'Access,   Help_DELETE'Access,   C, N),
      (K_INSERT'Access,   Help_INSERT'Access,   C, N),
```

- [ ] **Step 3: Update the command summaries and LIST cross-reference**

In the `Available Commands` block, add `INSERT` to the Data line (line 17) and the Immediate list (line 609):

```ada
      Put_Line ("  Data:        USE, SAVE, RUN, NEW, NAMES, WRITE, DELETE, INSERT, DISPLAY");
```

```ada
      Put_Line ("              SYSTEM, SUBMIT, ECHO, DIGITS, RSEED, OUTPUT, HELP,");
      Put_Line ("              DELETE n[-m], INSERT [n|$], QUIT, END");
```

In `Help_LIST` (line 279), extend the "See also" note:

```ada
      Put_Line ("          DELETE n[-m] to remove program buffer entries.");
      Put_Line ("          INSERT [n|$] to set where new statements are inserted.");
```

- [ ] **Step 4: Build, then regenerate the HELP /ALL snapshot**

Run:
```bash
cd ~/Develop/sdata && alr build 2>&1 | tail -5
./bin/sdata tests/help_all.cmd > tests/expected/help_all.out
git diff --stat tests/expected/help_all.out
```
Expected: build succeeds; the diff shows the new `INSERT` topic and summary lines added to the snapshot. **Eyeball the diff** to confirm only INSERT-related additions appear (no accidental reordering).

- [ ] **Step 5: Update the man page**

In `man/man1/sdata.1`, add an `INSERT` entry in the Immediate-commands section immediately after the `DELETE n[-m]` `.TP` block (the block beginning at line 622). Insert a new `.TP` block:

```groff
.TP
.BR "INSERT " [ \fIn\fR | \fB$\fR ]
Set the program\-buffer insertion point.
.B INSERT 0
inserts before the first line;
.BI INSERT " n"
inserts after existing line
.IR n ;
.B "INSERT $"
(or bare
.BR INSERT )
appends at the end (the default).
The cursor is sticky \(em it persists across
.B RUN
and advances as lines are inserted;
.B NEW
or another
.B INSERT
resets it.
An
.I n
past the end warns and clamps to the end.
Only meaningful in interactive (REPL) mode.
```

- [ ] **Step 6: Update the design doc**

In `doc/design.md`, add an `INSERT` row to the command-reference table immediately after the two `DELETE` rows (after the block ending at line 736, `</tr>` following "Delete the current record..."). Insert:

```html
<tr>
<td><em>INSERT</em></td>
<td><em>INSERT</em> [ &lt;<em>line</em>&gt; | <em>$</em> ]</td>
<td>Immediate Execution</td>
<td>Set the program-buffer insertion point so subsequently entered deferred statements are inserted there instead of appended. <em>INSERT 0</em> inserts before the first line; <em>INSERT n</em> inserts after existing line <em>n</em>; <em>INSERT $</em> (or bare <em>INSERT</em>) appends at the end (the default). The cursor is sticky: it persists across <em>RUN</em> and advances as lines are inserted; <em>NEW</em> or another <em>INSERT</em> resets it. A line number past the end warns and clamps to the end. Only meaningful in interactive (REPL) mode.</td>
</tr>
```

- [ ] **Step 7: Full check**

Run: `cd ~/Develop/sdata && make check 2>&1 | tail -15`
Expected: all unit binaries pass; the `help_all` integration test now matches the regenerated snapshot; `All 202 tests passed.`

- [ ] **Step 8: Commit**

```bash
cd ~/Develop/sdata
git add src/sdata-help.adb tests/expected/help_all.out man/man1/sdata.1 doc/design.md
git commit -m "docs(insert): HELP topic, man page, design.md, help_all snapshot

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Final Verification

- [ ] `cd ~/Develop/sdata && make check` — all 5 unit binaries pass; `All 202 tests passed.`
- [ ] Manual REPL smoke test:
  ```
  printf 'LET A = 1\nLET B = 2\nINSERT 1\nLET C = 3\nLIST\nQUIT\n' | ./bin/sdata
  ```
  Expected listing order: `1: LET A = 1`, `2: LET C = 3`, `--> insertion point` after line 2, `3: LET B = 2` — confirming `LET C = 3` was inserted after line 1 and the cursor advanced.
- [ ] `git log --oneline -5` shows the five feature/doc commits.
- [ ] Close issue #32 referencing the commits (maintainer's call; mention in PR/summary).

## Notes for the implementer

- **Compiler will flag missing case arms.** Adding `Stmt_PROGRAM_INSERT` forces coverage in every `case ... Statement_Kind`. The arms that need it are handled in Task 1 (AST variant `when others` already covers it; `Free_Program` in `src/ast/sdata-ast.adb` has `when others => null`) and Task 2 (`Execute_Statement`). `Process_One_Record` has `when others => null`. If `alr build` reports any other uncovered `case`, add `when Stmt_PROGRAM_INSERT => null;` there — INSERT is immediate and never reaches the per-record deferred path.
- **Why unit tests, not `.cmd` tests:** the `.cmd` harness runs batch mode (`./bin/sdata file.cmd`), where the program buffer is never populated, so INSERT/LIST/DELETE buffer behavior is invisible there. The public REPL API (`Add_To_Active_Program`, `Run_Active_Program`, `Clear_Active_Program`, `Program_Buffer_Length`, `Execute`) plus `SData_Core.IO.Open_Output` capture give deterministic coverage in `interpreter_unit_test`.
- **Out of scope (YAGNI):** the `CHANGE` command (in-place line replacement) the maintainer plans for post-1.0; moving existing lines; cursor history.
