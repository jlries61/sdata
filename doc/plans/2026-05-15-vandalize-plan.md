# VANDALIZE Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `VANDALIZE <source> INTO <dest> [/PERTURB] [/SHUFFLE] [/MISS] [/BY=]` immediate command, which adds a noisy copy of a permanent table column.

**Architecture:** VANDALIZE follows the same pattern as SORT: immediate tier, handled in `Execute_Declarative`, operating directly on `SData.Table` without triggering RUN. A single uniform draw per row selects which noise operation applies (or none), keeping operations mutually exclusive. BY-group stratification uses a save/restore wrapper around the global BY state.

**Tech Stack:** Ada 2012, GNAT/GPRbuild, `SData.Table`, `SData.Statistics` (Normal_RN, Uniform_RN), `Ada.Numerics.Elementary_Functions` (Sqrt for SD computation).

---

## File Map

| File | Change |
|---|---|
| `src/lexer/sdata-lexer.ads` | Add `Token_Dot`, `Token_VANDALIZE`, `Token_INTO` |
| `src/lexer/sdata-lexer.adb` | Handle `.` → Token_Dot; register VANDALIZE, INTO keywords |
| `src/ast/sdata-ast.ads` | Add `Stmt_VANDALIZE` to `Statement_Kind`; add AST variant |
| `src/ast/sdata-ast.adb` | Free `Vand_By_Vars` in `Free` |
| `src/parser/sdata-parser.adb` | Parse VANDALIZE statement |
| `src/sdata-interpreter.adb` | Add `Stmt_VANDALIZE` to `Is_Immediate`; route to `Execute_Declarative`; add `with Ada.Numerics.Elementary_Functions` |
| `src/sdata-interpreter-execute_declarative.adb` | `when Stmt_VANDALIZE =>` handler |
| `src/sdata-help.adb` | `Help_VANDALIZE` procedure + dispatch table entry |
| `man/man1/sdata.1` | VANDALIZE entry in Immediate commands section |
| `tests/vandalize_errors.cmd` + `.exitcode` | Error validation tests |
| `tests/vandalize_miss.cmd` | MISS operation tests |
| `tests/vandalize_shuffle.cmd` | SHUFFLE operation tests |
| `tests/vandalize_perturb.cmd` | PERTURB operation tests |
| `tests/vandalize_by.cmd` | BY stratification test |
| `tests/vandalize_inplace.cmd` | In-place (source = dest) test |
| `tests/vandalize_array.cmd` | DIM array test |
| `tests/expected/vandalize_*.out` | Expected outputs for all tests |

---

## Task 1: Lexer — Token_Dot, Token_INTO, Token_VANDALIZE

**Files:**
- Modify: `src/lexer/sdata-lexer.ads:28-38`
- Modify: `src/lexer/sdata-lexer.adb:304-310` (keyword table), `src/lexer/sdata-lexer.adb:356-400` (punctuation case)

- [ ] **Step 1: Add Token_Dot and Token_INTO to Token_Kind in sdata-lexer.ads**

  In `sdata-lexer.ads`, line 29, change:
  ```ada
        Token_TO, Token_STEP, Token_BREAK,
  ```
  to:
  ```ada
        Token_TO, Token_STEP, Token_BREAK, Token_INTO,
  ```

  On line 35, change:
  ```ada
        Token_Comma, Token_Semicolon, Token_Colon, -- ,, ;, :
  ```
  to:
  ```ada
        Token_Comma, Token_Semicolon, Token_Colon, Token_Dot, -- ,, ;, :, .
  ```

  On line 28, append `Token_VANDALIZE` to the keyword list:
  ```ada
        Token_REM, Token_HELP, Token_END, Token_RUN, Token_QUIT, Token_NAMES, Token_LIST, Token_DISPLAY,
        Token_TO, Token_STEP, Token_BREAK, Token_INTO, Token_VANDALIZE,
  ```

- [ ] **Step 2: Register keywords in sdata-lexer.adb**

  In `sdata-lexer.adb` after line 307 (`elsif Upper = "BREAK" then T.Kind := Token_BREAK;`), add:
  ```ada
               elsif Upper = "INTO"      then T.Kind := Token_INTO;
               elsif Upper = "VANDALIZE" then T.Kind := Token_VANDALIZE;
  ```

- [ ] **Step 3: Handle '.' as Token_Dot in punctuation case**

  In `sdata-lexer.adb`, in the `case C is` block (around line 357), before the `when others =>` line, add:
  ```ada
               when '.' => T.Kind := Token_Dot; Advance (Ctx);
  ```

- [ ] **Step 4: Build to verify**

  ```bash
  cd /home/jries/Develop/sdata && alr build
  ```
  Expected: build succeeds with no new errors.

- [ ] **Step 5: Commit**

  ```bash
  git add src/lexer/sdata-lexer.ads src/lexer/sdata-lexer.adb
  git commit -m "feat: add Token_Dot, Token_INTO, Token_VANDALIZE to lexer"
  ```

---

## Task 2: AST — Stmt_VANDALIZE variant

**Files:**
- Modify: `src/ast/sdata-ast.ads:117-252`
- Modify: `src/ast/sdata-ast.adb:125-130`

- [ ] **Step 1: Add Stmt_VANDALIZE to Statement_Kind**

  In `sdata-ast.ads`, line 159, change:
  ```ada
        Stmt_OPTIONS         -- Set runtime option (OPTIONS key value)
     );
  ```
  to:
  ```ada
        Stmt_OPTIONS,        -- Set runtime option (OPTIONS key value)
        Stmt_VANDALIZE       -- Add noisy copy of a column (immediate)
     );
  ```

- [ ] **Step 2: Add VANDALIZE variant to Statement record**

  In `sdata-ast.ads`, line 250 (in the `case Kind is` record, before `when others =>`), add:
  ```ada
           when Stmt_VANDALIZE =>
              Vand_Source_Name : String (1 .. Max_Name_Len);
              Vand_Source_Len  : Natural;
              Vand_Dest_Name   : String (1 .. Max_Name_Len);
              Vand_Dest_Len    : Natural;
              Vand_Perturb     : Boolean := False;
              Vand_Shuffle     : Boolean := False;
              Vand_Miss        : Boolean := False;
              Vand_Pprob       : Float   := 1.0;
              Vand_SD_Frac     : Float   := 0.01;
              Vand_Sprob       : Float   := 1.0;
              Vand_Mprob       : Float   := 0.05;
              Vand_By_Vars     : Variable_List;
  ```

- [ ] **Step 3: Free Vand_By_Vars in sdata-ast.adb**

  In `sdata-ast.adb`, add a new `when` arm before `when others =>` in the `Free` procedure (around line 127):
  ```ada
              when Stmt_VANDALIZE =>
                 Free (Stmt.Vand_By_Vars);
  ```

- [ ] **Step 4: Build**

  ```bash
  alr build
  ```
  Expected: build succeeds.

- [ ] **Step 5: Commit**

  ```bash
  git add src/ast/sdata-ast.ads src/ast/sdata-ast.adb
  git commit -m "feat: add Stmt_VANDALIZE AST variant"
  ```

---

## Task 3: Parser — parse VANDALIZE

**Files:**
- Modify: `src/parser/sdata-parser.adb` (add case after Token_DISPLAY block, around line 1352)

- [ ] **Step 1: Write a failing error integration test**

  Create `tests/vandalize_errors.cmd`:
  ```
  -- Test VANDALIZE parse/validation errors

  -- Error: no INTO keyword
  NEW
  REPEAT 3
  LET X = RECNO()
  RUN
  VANDALIZE X OOPS Y /MISS=1.0
  QUIT
  ```

  Create `tests/vandalize_errors.exitcode`:
  ```
  1
  ```

  Create `tests/expected/vandalize_errors.out`:
  ```
  RUN complete. 3 records and 1 variables processed.
  Error: VANDALIZE: expected INTO.
  ```

- [ ] **Step 2: Run the test to verify it fails (currently parses as identifier)**

  ```bash
  make -C /home/jries/Develop/sdata check 2>&1 | grep -E "vandalize|FAILED|passed"
  ```
  Expected: `vandalize_errors.cmd... FAILED` (Token_VANDALIZE not yet in parser).

- [ ] **Step 3: Add the VANDALIZE parser case**

  In `src/parser/sdata-parser.adb`, immediately after the `when Token_DISPLAY =>` block (around line 1352), add:

  ```ada
           when Token_VANDALIZE =>
              declare
                 Src_Tok  : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                 Into_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                 Dst_Tok  : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
              begin
                 if Src_Tok.Kind /= Token_Identifier then
                    raise Script_Error with "VANDALIZE: expected source variable name.";
                 end if;
                 if Into_Tok.Kind /= Token_INTO then
                    raise Script_Error with "VANDALIZE: expected INTO.";
                 end if;
                 if Dst_Tok.Kind /= Token_Identifier then
                    raise Script_Error with "VANDALIZE: expected destination variable name.";
                 end if;
                 Stmt := new Statement (Stmt_VANDALIZE);
                 Stmt.Vand_Source_Len := Src_Tok.Length;
                 Stmt.Vand_Source_Name (1 .. Src_Tok.Length) :=
                    To_Upper (Src_Tok.Text (1 .. Src_Tok.Length));
                 Stmt.Vand_Dest_Len := Dst_Tok.Length;
                 Stmt.Vand_Dest_Name (1 .. Dst_Tok.Length) :=
                    To_Upper (Dst_Tok.Text (1 .. Dst_Tok.Length));
                 --  Parse slash options.
                 loop
                    exit when Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Slash;
                    declare
                       Discard   : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                       Flag_Tok  : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                       Flag_Name : constant String :=
                          To_Upper (Flag_Tok.Text (1 .. Flag_Tok.Length));
                    begin
                       if Flag_Name = "PERTURB" then
                          Stmt.Vand_Perturb := True;
                          if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Equal then
                             declare Eq : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                             begin pragma Unreferenced (Eq); end;
                             declare
                                V1 : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                             begin
                                if V1.Kind = Token_Numeric_Literal then
                                   Stmt.Vand_Pprob :=
                                      Float'Value (V1.Text (1 .. V1.Length));
                                elsif V1.Kind /= Token_Dot then
                                   raise Script_Error with
                                      "/PERTURB=: expected probability or '.'";
                                end if;
                             end;
                             if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Comma then
                                declare Cm : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                                begin pragma Unreferenced (Cm); end;
                                declare
                                   V2 : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                                begin
                                   if V2.Kind /= Token_Numeric_Literal then
                                      raise Script_Error with
                                         "/PERTURB=: expected sd-fraction after ','";
                                   end if;
                                   Stmt.Vand_SD_Frac :=
                                      Float'Value (V2.Text (1 .. V2.Length));
                                end;
                             end if;
                          end if;
                       elsif Flag_Name = "SHUFFLE" then
                          Stmt.Vand_Shuffle := True;
                          if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Equal then
                             declare Eq : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                             begin pragma Unreferenced (Eq); end;
                             declare
                                V : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                             begin
                                if V.Kind /= Token_Numeric_Literal then
                                   raise Script_Error with "/SHUFFLE=: expected probability";
                                end if;
                                Stmt.Vand_Sprob := Float'Value (V.Text (1 .. V.Length));
                             end;
                          end if;
                       elsif Flag_Name = "MISS" then
                          Stmt.Vand_Miss := True;
                          if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Equal then
                             declare Eq : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                             begin pragma Unreferenced (Eq); end;
                             declare
                                V : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                             begin
                                if V.Kind /= Token_Numeric_Literal then
                                   raise Script_Error with "/MISS=: expected probability";
                                end if;
                                Stmt.Vand_Mprob := Float'Value (V.Text (1 .. V.Length));
                             end;
                          end if;
                       elsif Flag_Name = "BY" then
                          if Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Equal then
                             raise Script_Error with "/BY: expected '='";
                          end if;
                          declare Eq : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                          begin pragma Unreferenced (Eq); end;
                          loop
                             declare
                                VT : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                                VN : Variable_List_Node;
                             begin
                                if VT.Kind /= Token_Identifier then
                                   raise Script_Error with
                                      "/BY=: expected variable name";
                                end if;
                                VN.Var.Start_Len := VT.Length;
                                VN.Var.Start_Name (1 .. VT.Length) :=
                                   To_Upper (VT.Text (1 .. VT.Length));
                                VN.Var.Is_Range := False;
                                VN.Next := Stmt.Vand_By_Vars;
                                Stmt.Vand_By_Vars := new Variable_List_Node'(VN);
                             end;
                             exit when Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Comma;
                             declare Cm : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                             begin pragma Unreferenced (Cm); end;
                          end loop;
                       else
                          raise Script_Error with
                             "VANDALIZE: unknown option /" & Flag_Name;
                       end if;
                    end;
                 end loop;
                 if not Stmt.Vand_Perturb and then
                    not Stmt.Vand_Shuffle and then
                    not Stmt.Vand_Miss
                 then
                    raise Script_Error with
                       "VANDALIZE: at least one of /PERTURB, /SHUFFLE, /MISS required.";
                 end if;
              end;
  ```

- [ ] **Step 4: Build**

  ```bash
  alr build
  ```
  Expected: build succeeds.

- [ ] **Step 5: Run the error test**

  ```bash
  make -C /home/jries/Develop/sdata check 2>&1 | grep -E "vandalize|FAILED|passed"
  ```
  Expected: `vandalize_errors.cmd... PASSED`.

- [ ] **Step 6: Commit**

  ```bash
  git add src/parser/sdata-parser.adb tests/vandalize_errors.cmd tests/vandalize_errors.exitcode tests/expected/vandalize_errors.out
  git commit -m "feat: parse VANDALIZE statement; add error validation test"
  ```

---

## Task 4: Interpreter wiring — Is_Immediate, dispatch, stub handler

**Files:**
- Modify: `src/sdata-interpreter.adb:82-88` (Is_Immediate), `src/sdata-interpreter.adb:610-613` (dispatch)
- Modify: `src/sdata-interpreter-execute_declarative.adb:300-302` (stub when clause)

- [ ] **Step 1: Write a "stub reaches handler" integration test**

  Create `tests/vandalize_stub.cmd`:
  ```
  -- VANDALIZE reaches the handler without crashing.
  NEW
  REPEAT 3
  LET X = RECNO()
  RUN
  VANDALIZE X INTO X_V /MISS=1.0
  QUIT
  ```

  Create `tests/expected/vandalize_stub.out`:
  ```
  RUN complete. 3 records and 1 variables processed.
  VANDALIZE complete. 3 records processed.
  ```

- [ ] **Step 2: Run the test to confirm it fails (VANDALIZE not dispatched yet)**

  ```bash
  make -C /home/jries/Develop/sdata check 2>&1 | grep vandalize
  ```
  Expected: `vandalize_stub.cmd... FAILED`.

- [ ] **Step 3: Add Stmt_VANDALIZE to Is_Immediate in sdata-interpreter.adb**

  Change lines 87-88 from:
  ```ada
           Stmt_ECHO | Stmt_SORT | Stmt_BY | Stmt_SELECT_FILTER | Stmt_SUBMIT |
           Stmt_SYSTEM | Stmt_PROGRAM_DELETE | Stmt_OPTIONS;
  ```
  to:
  ```ada
           Stmt_ECHO | Stmt_SORT | Stmt_BY | Stmt_SELECT_FILTER | Stmt_SUBMIT |
           Stmt_SYSTEM | Stmt_PROGRAM_DELETE | Stmt_OPTIONS | Stmt_VANDALIZE;
  ```

- [ ] **Step 4: Add dispatch route in Execute_Statement**

  Change lines 610-613 from:
  ```ada
           when Stmt_USE | Stmt_SAVE | Stmt_SORT | Stmt_BY | Stmt_REPEAT
              | Stmt_SELECT_FILTER | Stmt_DIGITS | Stmt_RSEED | Stmt_NEW
              | Stmt_OPTIONS =>
              Execute_Declarative (Stmt);
  ```
  to:
  ```ada
           when Stmt_USE | Stmt_SAVE | Stmt_SORT | Stmt_BY | Stmt_REPEAT
              | Stmt_SELECT_FILTER | Stmt_DIGITS | Stmt_RSEED | Stmt_NEW
              | Stmt_OPTIONS | Stmt_VANDALIZE =>
              Execute_Declarative (Stmt);
  ```

- [ ] **Step 5: Add with clause for Elementary_Functions to sdata-interpreter.adb**

  After line 27 (`with Ada.Text_IO.Unbounded_IO;`), add:
  ```ada
  with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;
  ```

- [ ] **Step 6: Add stub when clause in execute_declarative.adb**

  In `src/sdata-interpreter-execute_declarative.adb`, change line 301 (`when others => null;`) to add a new arm before it:
  ```ada
        when Stmt_VANDALIZE =>
           Put_Line ("VANDALIZE complete. " &
              Ada.Strings.Fixed.Trim (Natural'Image (SData.Table.Row_Count),
                                      Ada.Strings.Both) &
              " records processed.");
        when others => null;
  ```

- [ ] **Step 7: Build**

  ```bash
  alr build
  ```
  Expected: build succeeds.

- [ ] **Step 8: Run tests**

  ```bash
  make -C /home/jries/Develop/sdata check 2>&1 | grep -E "vandalize|FAILED|passed"
  ```
  Expected: `vandalize_stub.cmd... PASSED`, `vandalize_errors.cmd... PASSED`.

- [ ] **Step 9: Commit**

  ```bash
  git add src/sdata-interpreter.adb src/sdata-interpreter-execute_declarative.adb tests/vandalize_stub.cmd tests/expected/vandalize_stub.out
  git commit -m "feat: wire Stmt_VANDALIZE into Is_Immediate and Execute_Declarative stub"
  ```

---

## Task 5: VANDALIZE executor — validation + MISS operation

**Files:**
- Modify: `src/sdata-interpreter-execute_declarative.adb` (replace stub with full MISS handler)
- Create: `tests/vandalize_miss.cmd`, `tests/expected/vandalize_miss.out`

This task replaces the stub with real validation and implements the MISS operation. MISS (probability=1.0) is deterministic: every cell becomes missing. That lets us test without RSEED.

- [ ] **Step 1: Write the MISS test**

  Create `tests/vandalize_miss.cmd`:
  ```
  -- Test VANDALIZE /MISS operation.

  -- Part 1: /MISS=1.0 makes all cells missing; N() aggregate confirms.
  NEW
  REPEAT 5
  LET X = RECNO()
  RUN
  VANDALIZE X INTO X_V /MISS=1.0
  RUN
  PRINT "N(X_V) should be 0:" N(X_V)
  PRINT "NMISS(X_V) should be 5:" NMISS(X_V)
  RUN

  -- Part 2: /MISS=0.0 leaves all cells unchanged; output = source.
  NEW
  REPEAT 5
  LET X = RECNO()
  RUN
  VANDALIZE X INTO X_V /MISS=0.0
  RUN
  PRINT "N(X_V) should be 5:" N(X_V)
  PRINT "SUM(X_V) should be 15:" SUM(X_V)
  RUN

  -- Part 3: error — probability sum > 1.0
  NEW
  REPEAT 3
  LET X = RECNO()
  RUN
  VANDALIZE X INTO X_V /MISS=0.7 /SHUFFLE=0.5
  QUIT
  ```

  Create `tests/vandalize_miss.exitcode`:
  ```
  1
  ```

  Create `tests/expected/vandalize_miss.out`:
  ```
  RUN complete. 5 records and 1 variables processed.
  VANDALIZE complete. 5 records processed.
  RUN complete. 5 records and 1 variables processed.
  N(X_V) should be 0: 0
  NMISS(X_V) should be 5: 5
  RUN complete. 5 records and 0 variables processed.
  RUN complete. 5 records and 1 variables processed.
  VANDALIZE complete. 5 records processed.
  RUN complete. 5 records and 2 variables processed.
  N(X_V) should be 5: 5.00000
  SUM(X_V) should be 15: 15.0000
  RUN complete. 5 records and 2 variables processed.
  RUN complete. 3 records and 1 variables processed.
  Error: VANDALIZE: sum of probabilities exceeds 1.0.
  ```

  > **Note:** The exact `N()` and `SUM()` output format (decimal places) depends on the DIGITS setting. Run `bin/sdata tests/vandalize_miss.cmd` after implementing and capture actual output:
  > ```bash
  > bin/sdata tests/vandalize_miss.cmd > tests/expected/vandalize_miss.out 2>&1
  > ```
  > Then verify the values match expectations before committing the expected output.

- [ ] **Step 2: Confirm the test fails**

  ```bash
  make -C /home/jries/Develop/sdata check 2>&1 | grep vandalize_miss
  ```
  Expected: `FAILED`.

- [ ] **Step 3: Implement validation + MISS in execute_declarative.adb**

  Replace the `when Stmt_VANDALIZE =>` stub with the full implementation below. This block goes inside the `case Stmt.Kind is` in `Execute_Declarative`. The implementation uses `SData.Table`, `SData.Statistics`, `SData.Values`, and `Ada.Strings.Fixed` — all of which are available from the parent interpreter's `with` clauses.

  ```ada
        when Stmt_VANDALIZE =>
           declare
              Src : constant String :=
                 To_Upper (Stmt.Vand_Source_Name (1 .. Stmt.Vand_Source_Len));
              Dst : constant String :=
                 To_Upper (Stmt.Vand_Dest_Name (1 .. Stmt.Vand_Dest_Len));
              N   : constant Natural := SData.Table.Row_Count;

              function Suffix (Name : String) return Character is
              begin
                 if Name'Length = 0 then return ' '; end if;
                 if Name (Name'Last) = '%' then return '%'; end if;
                 if Name (Name'Last) = '$' then return '$'; end if;
                 return ' ';
              end Suffix;

              function Col_Type_Of (S : Character)
                 return SData.Table.Column_Type is
              begin
                 if S = '%' then return SData.Table.Col_Integer; end if;
                 if S = '$' then return SData.Table.Col_String;  end if;
                 return SData.Table.Col_Numeric;
              end Col_Type_Of;

           begin
              --  Validate source exists.
              if not SData.Table.Has_Column (Src) then
                 raise Script_Error with
                    "VANDALIZE: source variable '" & Src & "' not found.";
              end if;

              --  Validate suffix compatibility.
              if Suffix (Src) /= Suffix (Dst) then
                 raise Script_Error with
                    "VANDALIZE: source and destination name suffixes must match.";
              end if;
              if SData.Table.Has_Column (Dst) then
                 --  Destination exists: type must match source (both numeric,
                 --  integer, or string, as encoded by suffix).
                 if Suffix (Src) /= Suffix (Dst) then
                    raise Script_Error with
                       "VANDALIZE: destination '" & Dst &
                       "' exists with incompatible type.";
                 end if;
              end if;

              --  PERTURB requires float source.
              if Stmt.Vand_Perturb and then Suffix (Src) /= ' ' then
                 raise Script_Error with
                    "VANDALIZE: /PERTURB requires a floating-point variable (no suffix).";
              end if;

              --  Validate probability sum.
              declare
                 Total : Float := 0.0;
              begin
                 if Stmt.Vand_Miss    then Total := Total + Stmt.Vand_Mprob; end if;
                 if Stmt.Vand_Shuffle then Total := Total + Stmt.Vand_Sprob; end if;
                 if Stmt.Vand_Perturb then Total := Total + Stmt.Vand_Pprob; end if;
                 if Total > 1.0 then
                    raise Script_Error with
                       "VANDALIZE: sum of probabilities exceeds 1.0.";
                 end if;
              end;

              --  Validate BY variables.
              if Stmt.Vand_By_Vars /= null then
                 declare Curr : Variable_List := Stmt.Vand_By_Vars; begin
                    while Curr /= null loop
                       declare
                          BV : constant String :=
                             To_Upper (Curr.Var.Start_Name (1 .. Curr.Var.Start_Len));
                       begin
                          if not SData.Table.Has_Column (BV) then
                             raise Script_Error with
                                "VANDALIZE /BY: variable '" & BV & "' not found.";
                          end if;
                       end;
                       Curr := Curr.Next;
                    end loop;
                 end;
              end if;

              --  Collect source values.
              declare
                 type Value_Array is array (1 .. N) of SData.Values.Value;
                 Src_Vals : Value_Array;
                 Out_Vals : Value_Array;

                 --  Group assignment (0 = all one group).
                 type Group_Array is array (1 .. N) of Natural;
                 Groups : Group_Array := (others => 1);

                 --  Probability thresholds (fixed order: MISS, SHUFFLE, PERTURB).
                 P_Miss    : constant Float :=
                    (if Stmt.Vand_Miss    then Stmt.Vand_Mprob else 0.0);
                 P_Shuffle : constant Float :=
                    (if Stmt.Vand_Shuffle then Stmt.Vand_Sprob else 0.0);
                 P_Perturb : constant Float :=
                    (if Stmt.Vand_Perturb then Stmt.Vand_Pprob else 0.0);
                 T_Miss    : constant Float := P_Miss;
                 T_Shuffle : constant Float := T_Miss    + P_Shuffle;
                 T_Perturb : constant Float := T_Shuffle + P_Perturb;

              begin
                 for R in 1 .. N loop
                    Src_Vals (R) := SData.Table.Get_Value_Upper (R, Src);
                 end loop;

                 --  Compute BY-group assignments if /BY= specified.
                 if Stmt.Vand_By_Vars /= null then
                    --  Save global BY vars, install local ones, compute groups,
                    --  then restore.
                    declare
                       Saved_Count : constant Natural := SData.Table.By_Var_Count;
                       type Saved_Name_Array is
                          array (1 .. Natural'Max (1, Saved_Count)) of
                             Ada.Strings.Unbounded.Unbounded_String;
                       Saved_Names : Saved_Name_Array;
                    begin
                       for I in 1 .. Saved_Count loop
                          Saved_Names (I) := Ada.Strings.Unbounded.To_Unbounded_String
                             (SData.Table.By_Var_Name (I));
                       end loop;

                       SData.Table.Clear_By_Vars;
                       declare Curr : Variable_List := Stmt.Vand_By_Vars; begin
                          while Curr /= null loop
                             SData.Table.Add_By_Var
                                (To_Upper (Curr.Var.Start_Name (1 .. Curr.Var.Start_Len)));
                             Curr := Curr.Next;
                          end loop;
                       end;

                       --  Assign consecutive group IDs (requires table sorted by BY vars).
                       declare
                          Next_G : Natural := 1;
                       begin
                          Groups (1) := 1;
                          for R in 2 .. N loop
                             if SData.Table.In_Same_Group (R, R - 1) then
                                Groups (R) := Groups (R - 1);
                             else
                                Next_G     := Next_G + 1;
                                Groups (R) := Next_G;
                             end if;
                          end loop;
                       end;

                       --  Restore global BY vars.
                       SData.Table.Clear_By_Vars;
                       for I in 1 .. Saved_Count loop
                          SData.Table.Add_By_Var
                             (Ada.Strings.Unbounded.To_String (Saved_Names (I)));
                       end loop;
                    end;
                 end if;

                 --  Generate output values.
                 for R in 1 .. N loop
                    --  Missing source propagates unconditionally.
                    if Src_Vals (R).Kind = SData.Values.Val_Missing then
                       Out_Vals (R) := (Kind => SData.Values.Val_Missing);
                    else
                       declare
                          U : constant Float :=
                             SData.Statistics.Uniform_RN (0.0, 1.0);
                       begin
                          if U < T_Miss then
                             Out_Vals (R) := (Kind => SData.Values.Val_Missing);
                          else
                             Out_Vals (R) := Src_Vals (R);  -- SHUFFLE/PERTURB: placeholder
                          end if;
                       end;
                    end if;
                 end loop;

                 --  Create destination column if absent.
                 if not SData.Table.Has_Column (Dst) then
                    SData.Table.Add_Column (Dst, Col_Type_Of (Suffix (Src)));
                 end if;

                 --  Write output values.
                 for R in 1 .. N loop
                    SData.Table.Set_Value_Upper (R, Dst, Out_Vals (R));
                 end loop;

                 Put_Line ("VANDALIZE complete. " &
                    Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Both) &
                    " records processed.");
              end;
           end;
  ```

- [ ] **Step 4: Build**

  ```bash
  alr build
  ```
  Expected: build succeeds.

- [ ] **Step 5: Capture actual MISS test output and verify it matches expectations**

  ```bash
  bin/sdata tests/vandalize_miss.cmd > /tmp/vand_miss_actual.txt 2>&1
  cat /tmp/vand_miss_actual.txt
  ```

  Verify: N(X_V) = 0, NMISS(X_V) = 5 in Part 1; N(X_V) = 5, SUM(X_V) = 15 in Part 2; error message in Part 3.

  If the exact output differs from `tests/expected/vandalize_miss.out` (e.g. different decimal places), update the expected file:
  ```bash
  cp /tmp/vand_miss_actual.txt tests/expected/vandalize_miss.out
  ```

- [ ] **Step 6: Run all tests**

  ```bash
  make -C /home/jries/Develop/sdata check 2>&1 | tail -5
  ```
  Expected: all 137 tests pass.

- [ ] **Step 7: Commit**

  ```bash
  git add src/sdata-interpreter-execute_declarative.adb tests/vandalize_miss.cmd tests/vandalize_miss.exitcode tests/expected/vandalize_miss.out
  git commit -m "feat: implement VANDALIZE validation and /MISS operation"
  ```

---

## Task 6: VANDALIZE executor — SHUFFLE operation

**Files:**
- Modify: `src/sdata-interpreter-execute_declarative.adb` (replace SHUFFLE placeholder in output loop)
- Create: `tests/vandalize_shuffle.cmd`, `tests/expected/vandalize_shuffle.out`

SHUFFLE with prob=1.0 permutes all values. With a fixed RSEED the permutation is reproducible. We also verify that with prob=0.0 no shuffling occurs (output = source).

- [ ] **Step 1: Write the SHUFFLE test**

  Create `tests/vandalize_shuffle.cmd`:
  ```
  -- Test VANDALIZE /SHUFFLE operation.

  -- Part 1: /SHUFFLE=0.0 — no cells shuffled; output equals source.
  NEW
  REPEAT 5
  LET X = RECNO() * 10
  RUN
  VANDALIZE X INTO X_V /SHUFFLE=0.0
  RUN
  PRINT "SUM(X_V) should be 150:" SUM(X_V)
  PRINT "MIN(X_V) should be 10:" MIN(X_V)
  PRINT "MAX(X_V) should be 50:" MAX(X_V)
  RUN

  -- Part 2: /SHUFFLE=1.0 — all cells shuffled; sum/min/max unchanged.
  NEW
  RSEED 42
  REPEAT 5
  LET X = RECNO() * 10
  RUN
  VANDALIZE X INTO X_V /SHUFFLE=1.0
  RUN
  PRINT "SUM(X_V) should be 150:" SUM(X_V)
  PRINT "MIN(X_V) should be 10:" MIN(X_V)
  PRINT "MAX(X_V) should be 50:" MAX(X_V)
  RUN

  QUIT
  ```

  > **Note:** Do not create `tests/expected/vandalize_shuffle.out` yet. Step 4 captures real output after the implementation compiles and runs.

- [ ] **Step 2: Implement Fisher-Yates SHUFFLE**

  After the BY-group assignment block and before the output value generation loop in `execute_declarative.adb`, add the shuffle index table:

  ```ada
                 --  Build per-group Fisher-Yates shuffle index for SHUFFLE.
                 type Index_Array is array (1 .. Natural'Max (1, N)) of Positive;
                 Shuffle_Src : Index_Array := (others => 1);
                 --  Shuffle_Src(R) = the source row whose value row R draws from.
  ```

  Then, after all BY-group assignments, add:

  ```ada
                 if Stmt.Vand_Shuffle then
                    --  For each group, collect row indices, apply Fisher-Yates,
                    --  then store the mapping.
                    declare
                       Max_G : Natural := 1;
                    begin
                       for R in 1 .. N loop
                          if Groups (R) > Max_G then Max_G := Groups (R); end if;
                       end loop;
                       for G in 1 .. Max_G loop
                          --  Count rows in this group.
                          declare
                             G_Count : Natural := 0;
                          begin
                             for R in 1 .. N loop
                                if Groups (R) = G then G_Count := G_Count + 1; end if;
                             end loop;
                             if G_Count > 0 then
                                declare
                                   G_Rows : array (1 .. G_Count) of Positive;
                                   G_Idx  : Natural := 0;
                                begin
                                   for R in 1 .. N loop
                                      if Groups (R) = G then
                                         G_Idx := G_Idx + 1;
                                         G_Rows (G_Idx) := R;
                                      end if;
                                   end loop;
                                   --  Fisher-Yates shuffle on G_Rows.
                                   for I in reverse 2 .. G_Count loop
                                      declare
                                         J : constant Positive :=
                                            1 + Integer (SData.Statistics.Uniform_RN
                                               (0.0, 1.0) * Float (I));
                                         J_Clamped : constant Positive :=
                                            (if J > I then I else J);
                                         Tmp : constant Positive := G_Rows (I);
                                      begin
                                         G_Rows (I) := G_Rows (J_Clamped);
                                         G_Rows (J_Clamped) := Tmp;
                                      end;
                                   end loop;
                                   --  Record mapping: Shuffle_Src(original_row) = shuffled_source.
                                   for I in 1 .. G_Count loop
                                      Shuffle_Src (G_Rows (I)) := G_Rows (I);
                                   end loop;
                                   --  Rebuild: position I in the group draws from G_Rows(I).
                                   --  We need the inverse: for each row, where does it get its value?
                                   declare
                                      Orig_Rows : array (1 .. G_Count) of Positive;
                                      Idx2 : Natural := 0;
                                   begin
                                      for R in 1 .. N loop
                                         if Groups (R) = G then
                                            Idx2 := Idx2 + 1;
                                            Orig_Rows (Idx2) := R;
                                         end if;
                                      end loop;
                                      for I in 1 .. G_Count loop
                                         Shuffle_Src (Orig_Rows (I)) := G_Rows (I);
                                      end loop;
                                   end;
                                end;
                             end if;
                          end;
                       end loop;
                    end;
                 end if;
  ```

  Then update the output generation loop to handle SHUFFLE (replace the `else Out_Vals (R) := Src_Vals (R)` placeholder):

  ```ada
                          if U < T_Miss then
                             Out_Vals (R) := (Kind => SData.Values.Val_Missing);
                          elsif U < T_Shuffle then
                             Out_Vals (R) := Src_Vals (Shuffle_Src (R));
                          else
                             Out_Vals (R) := Src_Vals (R);  -- PERTURB placeholder
                          end if;
  ```

- [ ] **Step 3: Build**

  ```bash
  alr build
  ```
  Expected: build succeeds.

- [ ] **Step 4: Capture shuffle test output and verify**

  ```bash
  bin/sdata tests/vandalize_shuffle.cmd > tests/expected/vandalize_shuffle.out 2>&1
  cat tests/expected/vandalize_shuffle.out
  ```

  Verify: Part 1 SUM=150, MIN=10, MAX=50. Part 2 SUM=150, MIN=10, MAX=50 (values shuffled but set is preserved).

- [ ] **Step 5: Run all tests**

  ```bash
  make -C /home/jries/Develop/sdata check 2>&1 | tail -5
  ```
  Expected: all 138 tests pass.

- [ ] **Step 6: Commit**

  ```bash
  git add src/sdata-interpreter-execute_declarative.adb tests/vandalize_shuffle.cmd tests/expected/vandalize_shuffle.out
  git commit -m "feat: implement VANDALIZE /SHUFFLE with Fisher-Yates per-group permutation"
  ```

---

## Task 7: VANDALIZE executor — PERTURB operation

**Files:**
- Modify: `src/sdata-interpreter-execute_declarative.adb` (replace PERTURB placeholder)
- Create: `tests/vandalize_perturb.cmd`, `tests/expected/vandalize_perturb.out`

With sd-frac=0.0 the noise SD is zero, so Normal(0,0) = 0 and output = source. This is deterministic and does not require RSEED. With sd-frac=0.01 and RSEED=42 the output is reproducible.

- [ ] **Step 1: Write the PERTURB test**

  Create `tests/vandalize_perturb.cmd`:
  ```
  -- Test VANDALIZE /PERTURB operation.

  -- Part 1: /PERTURB=1.0,0.0 — zero noise; output equals source exactly.
  NEW
  REPEAT 5
  LET X = RECNO() * 10
  RUN
  VANDALIZE X INTO X_V /PERTURB=1.0,0.0
  RUN
  PRINT "SUM(X_V) should be 150:" SUM(X_V)
  PRINT "MIN(X_V) should be 10:" MIN(X_V)
  RUN

  -- Part 2: /PERTURB — some noise; with RSEED output is reproducible.
  NEW
  RSEED 7
  REPEAT 5
  LET X = RECNO() * 10
  RUN
  VANDALIZE X INTO X_V /PERTURB=1.0,0.1
  RUN
  PRINT "Values (should differ from 10,20,30,40,50 but be close):"
  PRINT X X_V
  RUN

  -- Part 3: error — PERTURB on integer variable
  NEW
  REPEAT 3
  LET N% = RECNO()
  RUN
  VANDALIZE N% INTO N_V% /PERTURB
  QUIT
  ```

  Create `tests/vandalize_perturb.exitcode`:
  ```
  1
  ```

  (Capture expected output after implementation — see Step 4.)

- [ ] **Step 2: Implement PERTURB**

  Before the output generation loop, add SD computation per group:

  ```ada
                 --  Compute per-group standard deviation for PERTURB.
                 type SD_Array is array (1 .. Natural'Max (1, N)) of Float;
                 Group_SD : SD_Array := (others => 0.0);
  ```

  After the shuffle index build block, add:

  ```ada
                 if Stmt.Vand_Perturb then
                    declare
                       Max_G : Natural := 1;
                    begin
                       for R in 1 .. N loop
                          if Groups (R) > Max_G then Max_G := Groups (R); end if;
                       end loop;
                       for G in 1 .. Max_G loop
                          declare
                             Cnt    : Natural    := 0;
                             Sum    : Long_Float := 0.0;
                             Sum_Sq : Long_Float := 0.0;
                          begin
                             for R in 1 .. N loop
                                if Groups (R) = G and then
                                   Src_Vals (R).Kind = SData.Values.Val_Numeric
                                then
                                   declare
                                      FV : constant Long_Float :=
                                         Long_Float (Src_Vals (R).Num_Val);
                                   begin
                                      Cnt    := Cnt + 1;
                                      Sum    := Sum    + FV;
                                      Sum_Sq := Sum_Sq + FV ** 2;
                                   end;
                                end if;
                             end loop;
                             if Cnt < 2 then
                                raise Script_Error with
                                   "VANDALIZE /PERTURB: group has fewer than 2 " &
                                   "non-missing values (standard deviation undefined).";
                             end if;
                             declare
                                NF    : constant Long_Float := Long_Float (Cnt);
                                Var_V : constant Long_Float :=
                                   (Sum_Sq - Sum ** 2 / NF) / (NF - 1.0);
                                SD_V  : constant Float :=
                                   Sqrt (Float (Var_V));
                             begin
                                for R in 1 .. N loop
                                   if Groups (R) = G then
                                      Group_SD (R) := Stmt.Vand_SD_Frac * SD_V;
                                   end if;
                                end loop;
                             end;
                          end;
                       end loop;
                    end;
                 end if;
  ```

  Update the output generation loop to handle PERTURB (replace the `else Out_Vals (R) := Src_Vals (R)` placeholder):

  ```ada
                          if U < T_Miss then
                             Out_Vals (R) := (Kind => SData.Values.Val_Missing);
                          elsif U < T_Shuffle then
                             Out_Vals (R) := Src_Vals (Shuffle_Src (R));
                          elsif U < T_Perturb then
                             Out_Vals (R) :=
                                (Kind    => SData.Values.Val_Numeric,
                                 Num_Val => Src_Vals (R).Num_Val +
                                    SData.Statistics.Normal_RN (0.0, Group_SD (R)));
                          else
                             Out_Vals (R) := Src_Vals (R);
                          end if;
  ```

- [ ] **Step 3: Build**

  ```bash
  alr build
  ```
  Expected: build succeeds.

- [ ] **Step 4: Capture PERTURB test output and verify**

  ```bash
  bin/sdata tests/vandalize_perturb.cmd > tests/expected/vandalize_perturb.out 2>&1
  cat tests/expected/vandalize_perturb.out
  ```

  Verify: Part 1 SUM=150 exactly. Part 2 values differ from source but are numerically close. Part 3 ends with the PERTURB-on-integer error.

- [ ] **Step 5: Run all tests**

  ```bash
  make -C /home/jries/Develop/sdata check 2>&1 | tail -5
  ```
  Expected: all 139 tests pass (vandalize_stub still passes — the stub test now works because MISS handles it).

- [ ] **Step 6: Commit**

  ```bash
  git add src/sdata-interpreter-execute_declarative.adb tests/vandalize_perturb.cmd tests/vandalize_perturb.exitcode tests/expected/vandalize_perturb.out
  git commit -m "feat: implement VANDALIZE /PERTURB with per-group normal noise"
  ```

---

## Task 8: BY stratification + in-place + combined operations tests

**Files:**
- Create: `tests/vandalize_by.cmd`, `tests/expected/vandalize_by.out`
- Create: `tests/vandalize_inplace.cmd`, `tests/expected/vandalize_inplace.out`
- Create: `tests/vandalize_combined.cmd`, `tests/expected/vandalize_combined.out`

The BY-group code was already implemented in Task 5. This task just adds tests to exercise it.

- [ ] **Step 1: Write the BY test**

  Create `tests/vandalize_by.cmd`:
  ```
  -- Test /BY= stratification: shuffle stays within groups.
  -- Two groups: GRP=1 (values 1,2,3) and GRP=2 (values 10,20,30).
  -- After full-shuffle, GRP=1 rows contain only values from {1,2,3}
  -- and GRP=2 rows contain only values from {10,20,30}.
  NEW
  RSEED 17
  REPEAT 6
  IF RECNO() <= 3 THEN LET GRP = 1 ELSE LET GRP = 2
  IF RECNO() <= 3 THEN LET X = RECNO() ELSE LET X = (RECNO()-3) * 10
  RUN
  SORT GRP
  VANDALIZE X INTO X_V /SHUFFLE=1.0 /BY=GRP
  RUN
  PRINT GRP X X_V
  RUN
  QUIT
  ```

  Capture output after build (Step 2). Verify visually: rows with GRP=1 have X_V in {1,2,3}; rows with GRP=2 have X_V in {10,20,30}.

- [ ] **Step 2: Write the in-place test**

  Create `tests/vandalize_inplace.cmd`:
  ```
  -- Test VANDALIZE in-place (source = destination).
  NEW
  REPEAT 5
  LET X = RECNO() * 10
  RUN
  VANDALIZE X INTO X /MISS=1.0
  RUN
  PRINT "NMISS(X) should be 5:" NMISS(X)
  RUN
  QUIT
  ```

  Create `tests/expected/vandalize_inplace.out`:
  ```
  RUN complete. 5 records and 1 variables processed.
  VANDALIZE complete. 5 records processed.
  RUN complete. 5 records and 1 variables processed.
  NMISS(X) should be 5: 5
  RUN complete. 5 records and 1 variables processed.
  ```

  Adjust decimal format if needed by running `bin/sdata tests/vandalize_inplace.cmd`.

- [ ] **Step 3: Write the combined operations test**

  Create `tests/vandalize_combined.cmd`:
  ```
  -- Test VANDALIZE with /MISS + /SHUFFLE combined (prob sum = 0.6, remainder = 0.4 unchanged).
  -- With 10 records and RSEED=99:
  --   ~2 cells missing, ~4 cells shuffled, ~4 cells unchanged.
  -- We verify that: NMISS(X_V) >= 0, N(X_V) >= 0, values in X_V are subset of {1..10} or missing.
  -- SUM(X_V) <= SUM(X) since some cells are missing.
  NEW
  RSEED 99
  REPEAT 10
  LET X = RECNO()
  RUN
  VANDALIZE X INTO X_V /MISS=0.2 /SHUFFLE=0.4
  RUN
  PRINT "N(X_V):" N(X_V)
  PRINT "NMISS(X_V):" NMISS(X_V)
  RUN
  QUIT
  ```

  Capture output after build; verify N + NMISS = 10.

- [ ] **Step 4: Build and capture expected outputs**

  ```bash
  alr build
  bin/sdata tests/vandalize_by.cmd > tests/expected/vandalize_by.out 2>&1
  bin/sdata tests/vandalize_combined.cmd > tests/expected/vandalize_combined.out 2>&1
  ```

  Adjust `tests/expected/vandalize_inplace.out` if needed:
  ```bash
  bin/sdata tests/vandalize_inplace.cmd > tests/expected/vandalize_inplace.out 2>&1
  ```

- [ ] **Step 5: Run all tests**

  ```bash
  make -C /home/jries/Develop/sdata check 2>&1 | tail -5
  ```
  Expected: all 142 tests pass.

- [ ] **Step 6: Commit**

  ```bash
  git add tests/vandalize_by.cmd tests/expected/vandalize_by.out \
          tests/vandalize_inplace.cmd tests/expected/vandalize_inplace.out \
          tests/vandalize_combined.cmd tests/expected/vandalize_combined.out
  git commit -m "test: add VANDALIZE BY, in-place, and combined operation tests"
  ```

---

## Task 9: DIM Array support

**Files:**
- Modify: `src/sdata-interpreter-execute_declarative.adb` (wrap existing logic in a helper; expand arrays)
- Create: `tests/vandalize_array.cmd`, `tests/expected/vandalize_array.out`

For a DIM array `X` with bounds Start..End, element column names in the table are `X(1)`, `X(2)`, etc. (from `Get_Real_Var_Name` in variables.adb, format `Name & "(" & Trim(Image(I)) & ")"`). `Has_Array(Name)` returns True; `Get_Array_Bounds` returns Start_Idx and End_Idx.

- [ ] **Step 1: Write the array test**

  Create `tests/vandalize_array.cmd`:
  ```
  -- Test VANDALIZE on a DIM array.
  -- DIM X(3) creates X(1), X(2), X(3). VANDALIZE X INTO Y with /MISS=1.0
  -- creates Y(1), Y(2), Y(3), all missing.
  NEW
  REPEAT 4
  DIM X(3)
  LET X(1) = RECNO() * 1
  LET X(2) = RECNO() * 10
  LET X(3) = RECNO() * 100
  RUN
  VANDALIZE X INTO Y /MISS=1.0
  RUN
  PRINT "NMISS(Y(1)) should be 4:" NMISS(Y(1))
  PRINT "NMISS(Y(2)) should be 4:" NMISS(Y(2))
  PRINT "NMISS(Y(3)) should be 4:" NMISS(Y(3))
  RUN
  QUIT
  ```

- [ ] **Step 2: Implement array expansion in the VANDALIZE handler**

  Declare `Vandalize_One_Column` as a local procedure **inside the outer `declare` block** of `when Stmt_VANDALIZE =>`, after `Col_Type_Of` and before the `begin`. The procedure takes `Src_Col` and `Dst_Col` as explicit String parameters and captures `N` and `Stmt` from the enclosing scope (`N` is declared in the outer `declare`; `Stmt` is the `Execute_Declarative` parameter visible throughout the body). Move everything from the inner `declare` block that starts with `type Value_Array` (Task 5 Step 3, including Task 6 Step 2 and Task 7 Step 2 additions) into the procedure, substituting `Src_Col` and `Dst_Col` for the old `Src` and `Dst` in the collection and write loops. Move `Put_Line ("VANDALIZE complete...")` out of the inner block to the outer `begin`, after the dispatch.

  Outer `declare` block structure after this refactoring:

  ```ada
        when Stmt_VANDALIZE =>
           declare
              Src : constant String :=
                 To_Upper (Stmt.Vand_Source_Name (1 .. Stmt.Vand_Source_Len));
              Dst : constant String :=
                 To_Upper (Stmt.Vand_Dest_Name (1 .. Stmt.Vand_Dest_Len));
              N   : constant Natural := SData.Table.Row_Count;

              function Suffix (Name : String) return Character is ...  -- unchanged
              function Col_Type_Of (S : Character)
                 return SData.Table.Column_Type is ...                 -- unchanged

              procedure Vandalize_One_Column (Src_Col, Dst_Col : String) is
                 --  Captures N from the outer declare block.
                 --  Captures Stmt (Execute_Declarative parameter) for probability
                 --  values and Vand_By_Vars.
                 --  Src_Col / Dst_Col are the actual table column names to read/write.
                 type Value_Array is array (1 .. N) of SData.Values.Value;
                 Src_Vals    : Value_Array;
                 Out_Vals    : Value_Array;
                 type Group_Array is array (1 .. N) of Natural;
                 Groups      : Group_Array := (others => 1);
                 P_Miss      : constant Float :=
                    (if Stmt.Vand_Miss    then Stmt.Vand_Mprob else 0.0);
                 P_Shuffle   : constant Float :=
                    (if Stmt.Vand_Shuffle then Stmt.Vand_Sprob else 0.0);
                 P_Perturb   : constant Float :=
                    (if Stmt.Vand_Perturb then Stmt.Vand_Pprob else 0.0);
                 T_Miss      : constant Float := P_Miss;
                 T_Shuffle   : constant Float := T_Miss    + P_Shuffle;
                 T_Perturb   : constant Float := T_Shuffle + P_Perturb;
                 type Index_Array is array (1 .. Natural'Max (1, N)) of Positive;
                 Shuffle_Src : Index_Array := (others => 1);
                 type SD_Array is array (1 .. Natural'Max (1, N)) of Float;
                 Group_SD    : SD_Array    := (others => 0.0);
              begin
                 --  Source value collection: read Src_Col (not Src).
                 for R in 1 .. N loop
                    Src_Vals (R) := SData.Table.Get_Value_Upper (R, Src_Col);
                 end loop;
                 --  BY-group assignment block from Task 5 Step 3 — unchanged,
                 --  since it reads Stmt.Vand_By_Vars (captured from enclosing scope).
                 if Stmt.Vand_By_Vars /= null then
                    ... (save/compute/restore block, identical to Task 5 Step 3) ...
                 end if;
                 --  Fisher-Yates shuffle index build from Task 6 Step 2 — unchanged.
                 if Stmt.Vand_Shuffle then
                    ... (per-group F-Y block, identical to Task 6 Step 2) ...
                 end if;
                 --  Per-group SD computation from Task 7 Step 2 — unchanged.
                 if Stmt.Vand_Perturb then
                    ... (per-group SD block, identical to Task 7 Step 2) ...
                 end if;
                 --  Output generation loop from Task 7 Step 2 (final form) — unchanged.
                 for R in 1 .. N loop
                    if Src_Vals (R).Kind = SData.Values.Val_Missing then
                       Out_Vals (R) := (Kind => SData.Values.Val_Missing);
                    else
                       declare U : constant Float :=
                          SData.Statistics.Uniform_RN (0.0, 1.0);
                       begin
                          if    U < T_Miss    then
                             Out_Vals (R) := (Kind => SData.Values.Val_Missing);
                          elsif U < T_Shuffle then
                             Out_Vals (R) := Src_Vals (Shuffle_Src (R));
                          elsif U < T_Perturb then
                             Out_Vals (R) :=
                                (Kind    => SData.Values.Val_Numeric,
                                 Num_Val => Src_Vals (R).Num_Val +
                                    SData.Statistics.Normal_RN (0.0, Group_SD (R)));
                          else
                             Out_Vals (R) := Src_Vals (R);
                          end if;
                       end;
                    end if;
                 end loop;
                 --  Write results: create Dst_Col if absent, then Set_Value_Upper.
                 if not SData.Table.Has_Column (Dst_Col) then
                    SData.Table.Add_Column (Dst_Col, Col_Type_Of (Suffix (Src_Col)));
                 end if;
                 for R in 1 .. N loop
                    SData.Table.Set_Value_Upper (R, Dst_Col, Out_Vals (R));
                 end loop;
                 --  No Put_Line here — moved to outer begin.
              end Vandalize_One_Column;

           begin
              --  Validation block from Task 5 Step 3 — unchanged.
              if not SData.Table.Has_Column (Src) then
                 raise Script_Error with
                    "VANDALIZE: source variable '" & Src & "' not found.";
              end if;
              ... (remaining validation: suffix check, PERTURB/float, prob sum, BY vars) ...

              --  Dispatch: array or scalar.
              if SData.Variables.Has_Array (Src) then
                 declare
                    Start_Idx, End_Idx : Integer;
                 begin
                    SData.Variables.Get_Array_Bounds (Src, Start_Idx, End_Idx);
                    for I in Start_Idx .. End_Idx loop
                       declare
                          I_Str   : constant String :=
                             Ada.Strings.Fixed.Trim (Integer'Image (I), Ada.Strings.Both);
                          Src_Col : constant String := Src & "(" & I_Str & ")";
                          Dst_Col : constant String := Dst & "(" & I_Str & ")";
                       begin
                          Vandalize_One_Column (Src_Col, Dst_Col);
                       end;
                    end loop;
                 end;
              else
                 Vandalize_One_Column (Src, Dst);
              end if;

              Put_Line ("VANDALIZE complete. " &
                 Ada.Strings.Fixed.Trim (Natural'Image (N), Ada.Strings.Both) &
                 " records processed.");
           end;
  ```

  **Summary of what moves where:**
  - **Into the procedure:** everything inside the inner `declare` that begins with `type Value_Array` in Task 5 Step 3, plus the Task 6 and Task 7 variable declarations and their code blocks. The only substitution needed is `Src` → `Src_Col` and `Dst` → `Dst_Col` in the collection loop, the `Add_Column` call, and the write loop.
  - **Stays in outer `begin`:** the entire validation block (source exists, suffix match, PERTURB/float check, probability sum ≤ 1.0, BY var existence).
  - **Removed from inner block:** `Put_Line ("VANDALIZE complete...")` — now emitted once in the outer `begin` after the dispatch.

  Note: `SData.Variables` is already accessible from the interpreter's `with` clauses.

- [ ] **Step 3: Build**

  ```bash
  alr build
  ```
  Expected: build succeeds.

- [ ] **Step 4: Capture array test output**

  ```bash
  bin/sdata tests/vandalize_array.cmd > tests/expected/vandalize_array.out 2>&1
  cat tests/expected/vandalize_array.out
  ```

  Verify: three NMISS lines each show 4.

- [ ] **Step 5: Run all tests**

  ```bash
  make -C /home/jries/Develop/sdata check 2>&1 | tail -5
  ```
  Expected: all 143 tests pass.

- [ ] **Step 6: Commit**

  ```bash
  git add src/sdata-interpreter-execute_declarative.adb tests/vandalize_array.cmd tests/expected/vandalize_array.out
  git commit -m "feat: VANDALIZE array support via DIM array expansion"
  ```

---

## Task 10: HELP entry

**Files:**
- Modify: `src/sdata-help.adb`

- [ ] **Step 1: Add Help_VANDALIZE procedure**

  In `sdata-help.adb`, after `Help_DISPLAY` (around line 229), add:

  ```ada
     procedure Help_VANDALIZE is
     begin
        Put_Line ("Command: VANDALIZE <source> INTO <dest>");
        Put_Line ("             [/PERTURB[=<prob>[,<sd-frac>]]]");
        Put_Line ("             [/SHUFFLE[=<prob>]] [/MISS[=<prob>]]");
        Put_Line ("             [/BY=<var>[,<var>...]]");
        Put_Line ("Execution: Immediate");
        Put_Line ("Adds a noisy copy of a permanent variable to the current table.");
        Put_Line ("At least one of /PERTURB, /SHUFFLE, /MISS must be specified.");
        Put_Line ("Sum of probabilities must be <= 1.0; the remainder is 'no change'.");
        Put_Line ("Operations are mutually exclusive per cell (one uniform draw per row):");
        Put_Line ("  /PERTURB  Add noise ~ Normal(mean=0, sigma=sd-frac x StdDev).");
        Put_Line ("            Float variables only. prob default 1.0; sd-frac default 0.01.");
        Put_Line ("            Use '.' for prob default: /PERTURB=.,0.05");
        Put_Line ("  /SHUFFLE  Replace with a random value from the group (or column).");
        Put_Line ("  /MISS     Set cell to missing.");
        Put_Line ("/BY= stratifies by group; independent of any active global BY statement.");
        Put_Line ("Source and dest may be the same variable (in-place replacement).");
        Put_Line ("DIM arrays are supported; each element is vandalized independently.");
        Put_Line ("VANDALIZE does not trigger a RUN. Pending deferred statements");
        Put_Line ("are unaffected and execute on the next RUN.");
        Put_Line ("Examples:");
        Put_Line ("  VANDALIZE INCOME INTO INCOME_V /PERTURB=.,0.05 /MISS=0.02");
        Put_Line ("  VANDALIZE NAME$ INTO NAME_V$ /SHUFFLE=0.3 /BY=REGION");
        Put_Line ("  VANDALIZE X INTO X /MISS=0.1");
     end Help_VANDALIZE;
  ```

- [ ] **Step 2: Register in the dispatch table**

  Add the key constant and dispatch entry alongside `K_SORT` (around line 1114):

  ```ada
     K_VANDALIZE    : aliased constant String := "VANDALIZE";
  ```

  And in the dispatch array (after the K_SORT entry, around line 1324):

  ```ada
        (K_VANDALIZE'Access, Help_VANDALIZE'Access, C, N),
  ```

  Also add "VANDALIZE" to the command summary line at the top (around line 17):
  ```ada
     Put_Line ("  Data:        USE, SAVE, RUN, NEW, NAMES, WRITE, DELETE, DISPLAY, VANDALIZE");
  ```

- [ ] **Step 3: Build and test HELP VANDALIZE**

  ```bash
  alr build
  echo "HELP VANDALIZE" | bin/sdata
  ```
  Expected: the VANDALIZE help text is printed.

- [ ] **Step 4: Run all tests**

  ```bash
  make -C /home/jries/Develop/sdata check 2>&1 | tail -3
  ```
  Expected: all 143 tests pass (help text is untested by integration tests).

- [ ] **Step 5: Commit**

  ```bash
  git add src/sdata-help.adb
  git commit -m "feat: add VANDALIZE HELP entry"
  ```

---

## Task 11: Man page

**Files:**
- Modify: `man/man1/sdata.1`

- [ ] **Step 1: Add VANDALIZE to the Immediate commands section**

  In `man/man1/sdata.1`, after the `DISPLAY` entry (around line 275), add:

  ```groff
  .TP
  .B VANDALIZE \fIsource\fR INTO \fIdest\fR [\fB/PERTURB\fR[\fB=\fIp\fR[\fB,\fIs\fR]]] [\fB/SHUFFLE\fR[\fB=\fIp\fR]] [\fB/MISS\fR[\fB=\fIp\fR]] [\fB/BY=\fIvar\fR[\fB,\fIvar\fR...]]
  Add a noisy copy of permanent variable
  .I source
  to the table as
  .IR dest .
  At least one of
  .BR /PERTURB ,
  .BR /SHUFFLE ,
  or
  .B /MISS
  must be specified; probabilities must sum to \(<= 1.0.
  .B /PERTURB
  adds Normal(0,\fIs\fR\(*x\(*s) noise (float variables only; \fIs\fR defaults to 0.01, probability defaults to 1.0; use
  .B .
  to skip the probability and specify only \fIs\fR: \fB/PERTURB=.,0.05\fR).
  .B /SHUFFLE
  replaces each selected cell with a random value from the same
  .B /BY
  group.
  .B /MISS
  sets selected cells to missing.
  .B /BY=
  stratifies operations by group (independent of any active
  .B BY
  statement).
  Source and destination may be the same variable (in-place).
  DIM arrays are supported.
  Does not trigger an implicit
  .BR RUN .
  ```

- [ ] **Step 2: Verify man page renders**

  ```bash
  man /home/jries/Develop/sdata/man/man1/sdata.1 2>/dev/null | grep -A 20 "VANDALIZE" | head -25
  ```
  Expected: the VANDALIZE entry appears in readable form.

- [ ] **Step 3: Run all tests**

  ```bash
  make -C /home/jries/Develop/sdata check 2>&1 | tail -3
  ```
  Expected: all 143 tests pass.

- [ ] **Step 4: Commit**

  ```bash
  git add man/man1/sdata.1
  git commit -m "doc: add VANDALIZE to man page"
  ```

---

## Task 12: Final check — remove vandalize_stub test

The `vandalize_stub.cmd` test was a stepping-stone. Now that the real VANDALIZE behavior is in place, the expected output in the stub (which uses `/MISS=1.0`) should still pass — but verify it explicitly:

- [ ] **Step 1: Run make check and confirm all tests pass**

  ```bash
  make -C /home/jries/Develop/sdata check 2>&1 | tail -5
  ```
  Expected: all 143 tests pass.

- [ ] **Step 2: If vandalize_stub.cmd now fails** (the stub output no longer matches the real output), update it:

  ```bash
  bin/sdata tests/vandalize_stub.cmd > tests/expected/vandalize_stub.out 2>&1
  git add tests/expected/vandalize_stub.out
  git commit -m "test: update vandalize_stub expected output to match real implementation"
  ```

  If it still passes, no action needed.

- [ ] **Step 3: Final make check**

  ```bash
  make -C /home/jries/Develop/sdata check 2>&1
  ```
  Expected: all 143 tests pass.

- [ ] **Step 4: Commit (if not already clean)**

  ```bash
  git status
  ```
  If nothing pending: no commit needed. If there are changes: commit them.
