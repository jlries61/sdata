# Quoted Identifiers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the design in `doc/specs/2026-05-30-quoted-identifiers-design.md` — add backtick-quoted identifier syntax (`` `name` ``) so users can reference column names that collide with reserved keywords, plus a USE-time warning when a loaded column matches a reserved keyword.

**Architecture:** A new `Token_Quoted_Identifier` token kind; two parser helpers (`Is_Identifier_Token`, `Identifier_Text`); a reserved-keyword check after USE installs the table. No sdata-core changes; no semantic changes to identifier resolution.

**Tech Stack:** Ada 2012, Alire, existing sdata test framework.

---

## Pre-flight

- [ ] **Step 0.1: Verify clean working tree on the right branch**

  ```bash
  cd /home/jries/Develop/sdata && git status && git branch --show-current
  ```

  Expected: clean tree on a feature branch (or `main` if shipping directly — confirm with user first).

- [ ] **Step 0.2: Run the existing test suite to capture baseline**

  ```bash
  cd /home/jries/Develop/sdata && make check
  cd /home/jries/Develop/data-vandal && make check
  ```

  Record the test counts before starting.

---

## Task 1: Add Token_Quoted_Identifier to the lexer

**Files:**
- Modify: `/home/jries/Develop/sdata/src/lexer/sdata-lexer.ads`
- Modify: `/home/jries/Develop/sdata/src/lexer/sdata-lexer.adb`

- [ ] **Step 1: Add the token kind**

  In `sdata-lexer.ads`, find the `Token_Kind` enum. Add `Token_Quoted_Identifier` alongside `Token_Identifier`:

  ```ada
        Token_Identifier,
        Token_Quoted_Identifier,
        ...
  ```

- [ ] **Step 2: Add lex logic**

  In `sdata-lexer.adb`, find the main character-dispatch in `Get_Next_Token` (the function that reads the next token). Add a branch for backtick (`'`'`):

  ```ada
        elsif Ch = '`' then
           --  Quoted identifier: consume chars up to matching backtick
           declare
              Start_Pos : constant Positive := <current position>;
              Content   : String (1 .. Max_Name_Len);
              Len       : Natural := 0;
              Saw_Close : Boolean := False;
              Next_Ch   : Character;
           begin
              loop
                 Next_Ch := <read next char>;
                 if Next_Ch = '`' then
                    Saw_Close := True;
                    exit;
                 elsif Next_Ch = ASCII.LF or Next_Ch = ASCII.CR then
                    Put_Line_Error ("Error: unterminated quoted identifier (newline at column ...)");
                    exit;
                 elsif <end-of-input> then
                    Put_Line_Error ("Error: unterminated quoted identifier (end of input)");
                    exit;
                 else
                    if Len >= Max_Name_Len then
                       Put_Line_Error ("Error: quoted identifier exceeds Max_Name_Len");
                       exit;
                    end if;
                    Len := Len + 1;
                    Content (Len) := Next_Ch;
                 end if;
              end loop;
              if Saw_Close and Len = 0 then
                 Put_Line_Error ("Error: empty quoted identifier ``");
                 T.Kind := Token_Bad;
              elsif Saw_Close then
                 T.Kind := Token_Quoted_Identifier;
                 T.Text := Content;
                 T.Text_Len := Len;
              else
                 T.Kind := Token_Bad;
              end if;
           end;
  ```

  Replace `Token_Bad` with whatever existing error-token kind the lexer uses (look at how unterminated string literals are handled). Replace `<current position>`, `<read next char>`, `<end-of-input>` with the actual lexer accessor patterns used elsewhere in the same file.

- [ ] **Step 3: Add lexer unit tests**

  If the project has a lexer unit test file, add tests verifying:
  - `` `AS` `` → Token_Quoted_Identifier with Text="AS", Text_Len=2
  - `` `col with space` `` → Text="col with space", Text_Len=14
  - Unterminated (backtick followed by newline or EOF) → Token_Bad / parser error
  - Empty `` `` `` → Token_Bad / parser error

  If there's no dedicated lexer unit test file, defer test coverage to integration tests (Task 4).

- [ ] **Step 4: Build to verify**

  ```bash
  cd /home/jries/Develop/sdata && make build
  ```

  Expected: build succeeds. The new token is unused by the parser yet — that's fine.

- [ ] **Step 5: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/lexer/sdata-lexer.ads src/lexer/sdata-lexer.adb
  git commit -m "$(cat <<'EOF'
  feat(lexer): add Token_Quoted_Identifier for backtick-quoted names

  Scaffolding for the upcoming quoted-identifier syntax. The lexer
  recognises backtick-delimited content and emits a new token kind
  whose Text holds the verbatim content. Parser hookup follows in the
  next commit.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 2: Add parser helpers Is_Identifier_Token and Identifier_Text

**Files:**
- Modify: `/home/jries/Develop/sdata/src/parser/sdata-parser.adb`

- [ ] **Step 1: Add file-body helpers**

  Near the top of `sdata-parser.adb`'s body (alongside other parser helpers), add:

  ```ada
  function Is_Identifier_Token (T : Token_Type) return Boolean is
  begin
     return T.Kind = Token_Identifier
            or else T.Kind = Token_Quoted_Identifier;
  end Is_Identifier_Token;

  function Identifier_Text (T : Token_Type) return String is
  begin
     return T.Text (1 .. T.Text_Len);
  end Identifier_Text;
  ```

- [ ] **Step 2: Build to verify**

  ```bash
  cd /home/jries/Develop/sdata && make build
  ```

  Expected: build succeeds with an unused-function warning for the new helpers — they get callers in Task 3.

- [ ] **Step 3: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/parser/sdata-parser.adb
  git commit -m "$(cat <<'EOF'
  feat(parser): add Is_Identifier_Token / Identifier_Text helpers

  Will replace direct Token_Identifier checks throughout the parser to
  uniformly accept both bare and backtick-quoted identifiers.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 3: Wire the helpers into every identifier-accepting parser site

**Files:**
- Modify: `/home/jries/Develop/sdata/src/parser/sdata-parser.adb`

- [ ] **Step 1: Enumerate all identifier checks**

  ```bash
  cd /home/jries/Develop/sdata
  grep -n "Token_Identifier" src/parser/sdata-parser.adb
  ```

  This list is the work surface. Each line is a candidate site. Read each in context — some may already be intentional (e.g., distinguishing a slash-option flag name from a variable name).

- [ ] **Step 2: Replace each `.Kind = Token_Identifier` check**

  For each site that's checking whether a token is an identifier-style name (variable, column, alias, function name), change:

  ```ada
  if Tok.Kind = Token_Identifier then
  ```

  to:

  ```ada
  if Is_Identifier_Token (Tok) then
  ```

  And any subsequent `Tok.Text (1 .. Tok.Text_Len)` reading the name string, change to:

  ```ada
  Identifier_Text (Tok)
  ```

  Skip sites that are intentionally bare-identifier-only (rare; e.g., a slash-option key name like `/FMT=` — those are matched by string equality, not by token kind).

- [ ] **Step 3: Build incrementally**

  Build after every batch of ~5 site updates to catch type errors early:

  ```bash
  cd /home/jries/Develop/sdata && make build
  ```

  Expected: build succeeds after each batch.

- [ ] **Step 4: Run existing tests**

  ```bash
  cd /home/jries/Develop/sdata && make check
  cd /home/jries/Develop/data-vandal && make check
  ```

  Expected: all existing tests still pass. The helpers are functionally identical to direct checks for bare identifiers; the change is purely additive (now accepting Token_Quoted_Identifier too).

- [ ] **Step 5: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/parser/sdata-parser.adb
  git commit -m "$(cat <<'EOF'
  feat(parser): accept quoted identifiers at every identifier site

  Replace direct Token_Identifier checks throughout the parser with
  Is_Identifier_Token (Task 2 helper) so backtick-quoted identifiers
  work everywhere a bare identifier does: expression atoms, LET/SET
  LHS, KEEP/DROP/RENAME/BY/SORT var lists, ARRAY/DIM names, per-spec
  KEEP=/DROP=/RENAME=/IN=, WRITE targets, and AS alias names.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 4: Add integration tests for each affected syntactic position

**Files:**
- Create: 10 `.cmd` files + matching `tests/expected/*.out`
- Create: `tests/data/keyword_column.csv` (small fixture with a reserved-keyword column)

- [ ] **Step 1: Create the fixture**

  `tests/data/keyword_column.csv`:
  ```
  ID,AS,USE,IN
  1,10,100,1000
  2,20,200,2000
  ```

- [ ] **Step 2: Write each test**

  For each affected syntactic position, write a focused `.cmd` script that exercises the quoted form. Examples:

  `tests/quoted_id_print.cmd`:
  ```
  USE "tests/data/keyword_column.csv"
  PRINT `AS`
  RUN
  NEW
  END
  ```

  Expected output: the AS column values (10, 20) printed across two rows.

  `tests/quoted_id_let_lhs.cmd`:
  ```
  USE "tests/data/keyword_column.csv"
  LET `AS` = `AS` * 2
  PRINT `AS`
  RUN
  NEW
  END
  ```

  Expected output: 20 and 40.

  Continue for the other 8 positions listed in the spec (`KEEP`, `DROP`, `RENAME`, `BY`, per-dataset KEEP=, per-dataset RENAME=, SAVE IF=, WRITE target alias).

  Create matching `tests/expected/<name>.out` files by running each test once and capturing the output.

- [ ] **Step 3: Verify each test passes individually**

  ```bash
  cd /home/jries/Develop/sdata
  make build
  for t in tests/quoted_id_*.cmd; do
     name=$(basename "$t" .cmd)
     ./bin/sdata "$t" > /tmp/actual.out 2>&1
     diff /tmp/actual.out "tests/expected/$name.out" || echo "FAIL: $name"
  done
  ```

- [ ] **Step 4: Run full test suite**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: baseline count + 10 new tests, all pass.

- [ ] **Step 5: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add tests/quoted_id_*.cmd tests/expected/quoted_id_*.out \
          tests/data/keyword_column.csv
  git commit -m "$(cat <<'EOF'
  test(parser): integration tests for quoted-identifier syntax

  One focused test per affected syntactic position: PRINT, LET LHS,
  RENAME, KEEP, DROP, BY, per-dataset KEEP=, per-dataset RENAME=,
  SAVE IF=, WRITE-target alias. Each loads a CSV with reserved-keyword
  columns and exercises the quoted form to confirm it works where the
  bare form would silently fail.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 5: Add the USE-time reserved-keyword warning

**Files:**
- Modify: `/home/jries/Develop/sdata/src/sdata-interpreter-execute_declarative.adb`
- Possibly add: a small helper file `/home/jries/Develop/sdata/src/sdata-reserved_keywords.ads` or similar — or inline the list in execute_declarative.adb.

- [ ] **Step 1: Define the reserved-keyword list**

  Inline a constant array of upper-case strings in the same file as `Execute_USE`, or create a small `SData.Reserved_Keywords` package. The list mirrors the lexer's keyword set: USE, SAVE, KEEP, DROP, RENAME, IF, FOR, WHILE, REPEAT, UNTIL, END, QUIT, NAMES, LIST, SUBMIT, SYSTEM, RSEED, HOLD, UNHOLD, ARRAY, DIM, SORT, BY, SELECT, DELETE, BREAK, WRITE, OUTPUT, ECHO, DIGITS, FPATH, HELP, RUN, NEW, DISPLAY, OPTIONS, AS, IN, INTERLEAVE, JOIN, NEXT, WEND, MOCK, YES, NO, AUTO, CSV, ODF, XLSX, OOXML, ODS.

  Read the lexer body to extract the canonical list. Sort it for readability.

- [ ] **Step 2: Add the warning helper**

  ```ada
  procedure Warn_If_Reserved_Column_Names is
     --  Walk the current SData_Core.Table's columns; emit one
     --  warning per column whose upper-cased name matches a
     --  reserved keyword.
  begin
     for I in 1 .. SData_Core.Table.Column_Count loop
        declare
           Name : constant String := SData_Core.Table.Column_Name (I);
           Up   : constant String := To_Upper (Name);
        begin
           for Kw of Reserved_Keywords loop
              if Up = Kw then
                 SData_Core.IO.Put_Line_Error
                   ("warning: column """ & Name
                      & """ matches a reserved keyword; reference it as `"
                      & Name & "` or rename it");
                 exit;
              end if;
           end loop;
        end;
     end loop;
  end Warn_If_Reserved_Column_Names;
  ```

- [ ] **Step 3: Call it after each USE installs a table**

  In `Execute_USE`, call `Warn_If_Reserved_Column_Names` at the end of both the single-dataset (legacy) and multi-dataset paths, after the table has been installed and any post-install bookkeeping has run.

- [ ] **Step 4: Add an integration test**

  `tests/use_reserved_column_warning.cmd`:
  ```
  USE "tests/data/keyword_column.csv"
  NAMES
  NEW
  END
  ```

  Expected output should include warning lines (one per matching column) before the NAMES output. Capture the actual output and save as the `.out` file.

- [ ] **Step 5: Run tests**

  ```bash
  cd /home/jries/Develop/sdata && make check
  ```

  Expected: all tests pass including the new warning test.

  **Note**: existing tests like `use_merge_positional_eq.cmd` that load CSVs with reserved-keyword columns (none should at the moment, but check) may now emit unexpected warning lines that change their `.exp` output. Update any affected expected outputs.

- [ ] **Step 6: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add src/sdata-interpreter-execute_declarative.adb \
          tests/use_reserved_column_warning.cmd \
          tests/expected/use_reserved_column_warning.out
  git commit -m "$(cat <<'EOF'
  feat(use): warn at USE time when a loaded column matches a reserved keyword

  Walk the installed table after USE and emit one warning per column
  whose name collides with a reserved keyword. Tells the user
  immediately that the column needs the backtick-quoted form
  (\`name\`) or renaming, instead of silently failing later.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 6: Update the man page

**Files:**
- Modify: `/home/jries/Develop/sdata/man/man1/sdata.1`

- [ ] **Step 1: Add a "Quoted Identifiers" subsection**

  Near the LANGUAGE OVERVIEW (around line 138 in the current man page), add a new subsection. Use the existing troff style:

  ```
  .SS Quoted Identifiers
  Any identifier may be written enclosed in backticks
  .RB ( `\fIname\fR` )
  to bypass keyword recognition.  This is the standard escape for
  referencing column names that happen to collide with reserved
  keywords:
  .PP
  .EX
  USE "data.csv"
  PRINT `AS`           -- AS is a reserved keyword, but this works
  RENAME `AS`=AS_COL   -- and so does this
  .EE
  .PP
  Quoted identifiers are case-insensitive like bare identifiers:
  .B `AS`
  and
  .B `as`
  refer to the same name.  The
  .B NAMES
  command and error messages display the bare name without backticks.
  ```

- [ ] **Step 2: Verify groff render**

  ```bash
  groff -man -Tutf8 /home/jries/Develop/sdata/man/man1/sdata.1 > /dev/null 2>&1 && echo OK
  ```

- [ ] **Step 3: Commit**

  ```bash
  cd /home/jries/Develop/sdata
  git add man/man1/sdata.1
  git commit -m "$(cat <<'EOF'
  docs(man): document backtick-quoted identifier syntax

  New LANGUAGE OVERVIEW subsection explaining how to reference column
  names that collide with reserved keywords.

  Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
  EOF
  )"
  ```

---

## Task 7: Final validation

- [ ] **Step 1: Full test suites**

  ```bash
  cd /home/jries/Develop/sdata && make check
  cd /home/jries/Develop/data-vandal && make check
  cd /home/jries/Develop/sdata-core && alr build
  ```

  Expected: all pass.

- [ ] **Step 2: Inspect history**

  ```bash
  cd /home/jries/Develop/sdata && git log --oneline | head -10
  ```

  Verify each commit message is focused and conventional.

---

## Self-Review Summary

- **Spec coverage:** §Syntax → Task 1; §Lexer → Task 1; §Parser → Tasks 2, 3; §USE-time warning → Task 5; §Display → no implementation needed; §Backward compat → covered by existing test re-run in every task; §Testing strategy → Task 4 (10 integration tests) + Task 5 (warning test) + Task 1 (optional lexer unit tests if framework supports).
- **Placeholder scan:** no TBDs or "TODO" in steps; every step has either exact code or precise commands.
- **Risks:** the parser-site enumeration in Task 3 depends on `grep -n Token_Identifier` finding everything. If a site is missed, that syntactic position silently rejects quoted identifiers; the integration tests in Task 4 catch each documented position, but a missed less-common position (e.g., inside a SELECT/CASE branch) might not be tested. Reviewer should sanity-check the affected-sites list against the integration tests.
- **Estimated effort:** 1-2 days of subagent execution (smaller than Follow-on C, larger than the C1/C2/I1 fixes).
