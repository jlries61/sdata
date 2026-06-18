# Quoted Identifiers + Reserved-Keyword Warning — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users reference column names that collide with reserved keywords via backtick-quoted identifiers (`` `AS` ``), and warn at USE time when a loaded column matches a reserved keyword — in both sdata and data-vandal.

**Architecture:** Each consumer owns its lexer/AST/parser (ADR-040), so the lexer token + parser-site changes are implemented twice. The one shared piece is an additive sdata-core helper `Warn_Reserved_Columns` plus a runtime toggle `Options_Warn_Reserved`, gated inside the helper. sdata exposes the toggle via `OPTIONS WARNRESERVED`; data-vandal gains a new minimal OPTIONS command (P3) exposing only `WARNRESERVED`.

**Tech Stack:** Ada 2012, GNAT/GPRbuild, Alire. sdata-core consumed via path pin. Tests: `make check` (unit binaries + `.cmd` integration tests) in each consumer.

**Spec:** `doc/specs/2026-05-30-quoted-identifiers-design.md` (scope reconciled 2026-06-17).

**Cross-crate gate (run after each phase that touches the relevant crate):**
```bash
cd ~/Develop/sdata-core && alr build        # if sdata-core changed
cd ~/Develop/sdata && make check             # 202 integration + unit suites
cd ~/Develop/data-vandal && make check       # 44 tests
```
All three must be green before a phase is considered shippable.

**Conventions discovered (use the real names — the spec sketch was approximate):**
- Lexer token record field is `Length` (NOT `Text_Len`); type is `SData.Lexer.Token` (data-vandal: `Data_Vandal.Lexer.Token`).
- Error reporting facility: `SData_Core.IO.Put_Line_Error (Item : String)`.
- Table is package-global singleton: `SData_Core.Table.Column_Count` / `SData_Core.Table.Column_Name (I)` take **no** Table argument. The warning helper therefore reads the current table directly.
- OPTIONS runtime state lives in `SData_Core.Config.Runtime`; setters in `SData_Core.Config.Runtime.Internal`; per-key `Execute_OPTIONS_*` in `SData_Core.Commands`.
- sdata OPTIONS dispatch + no-arg display: `src/sdata-interpreter-execute_declarative.adb` (~lines 791–870).

---

## File Structure

**Phase 1 — sdata + sdata-core**

sdata-core (shared, additive):
- Modify `~/Develop/sdata-core/src/sdata_core-config-runtime.ads` — add `Options_Warn_Reserved` getter + private `_Value`.
- Modify `~/Develop/sdata-core/src/sdata_core-config-runtime.adb` — getter body + reset default.
- Modify `~/Develop/sdata-core/src/sdata_core-config-runtime-internal.ads` / `.adb` — `Set_Options_Warn_Reserved`.
- Modify `~/Develop/sdata-core/src/sdata_core-commands.ads` / `.adb` — `Execute_OPTIONS_WarnReserved` + `Reserved_Keyword_Sets` package + `Warn_Reserved_Columns`.

sdata (this crate):
- Modify `src/lexer/sdata-lexer.ads` — add `Token_Quoted_Identifier`, `Token_Bad`.
- Modify `src/lexer/sdata-lexer.adb` — scan backtick-quoted identifiers; `with SData_Core.IO`.
- Modify `src/parser/sdata-parser.adb` — add `Is_Identifier_Token` / `Identifier_Text` helpers; route all 18 `Token_Identifier` sites.
- Create `src/sdata-reserved_keywords.ads` (+ `.adb` if needed) — the sdata reserved-keyword set.
- Modify `src/sdata-interpreter-execute_declarative.adb` — `WARNRESERVED` dispatch + display line; call `Warn_Reserved_Columns` after USE (single + multi-dataset call sites in `src/sdata-interpreter.adb`).
- Modify `src/sdata-help.adb` — document `OPTIONS WARNRESERVED` + backtick syntax.
- Modify `man/man1/sdata.1`, `doc/design.md` — same.
- Tests: `tests/csv_unit_test.adb` or lexer unit test for token-level cases; new `.cmd` integration tests + `tests/expected/*.out`; regenerate `tests/expected/help_all.out` + options snapshots.

**Phase 2 — data-vandal quoted-ids + warning**
- Modify `~/Develop/data-vandal/src/lexer/data_vandal-lexer.ads` / `.adb` — `Token_Quoted_Identifier`, `Token_Bad`, scan.
- Modify `~/Develop/data-vandal/src/parser/data_vandal-parser.adb` — helpers + 12 sites.
- Create `~/Develop/data-vandal/src/data_vandal-reserved_keywords.ads` — data-vandal keyword set.
- Modify data-vandal USE path (`data_vandal-interpreter.adb` + `data_vandal_main.adb`) — call `Warn_Reserved_Columns`.
- Tests under `~/Develop/data-vandal/tests/`.

**Phase 3 — data-vandal OPTIONS command**
- Modify data-vandal lexer (`Token_OPTIONS`), AST (`Stmt_OPTIONS` + fields), parser (parse OPTIONS), interpreter (dispatch + no-arg display).
- Wire `WARNRESERVED` → `SData_Core.Commands.Execute_OPTIONS_WarnReserved`.
- Modify `~/Develop/data-vandal/man/man1/data-vandal.1`, `data_vandal-help.adb`.
- Tests under `~/Develop/data-vandal/tests/`.

---

# PHASE 1 — sdata + sdata-core

## Task 1: sdata-core — `Options_Warn_Reserved` runtime toggle

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-config-runtime.ads`
- Modify: `~/Develop/sdata-core/src/sdata_core-config-runtime.adb`
- Modify: `~/Develop/sdata-core/src/sdata_core-config-runtime-internal.ads`
- Modify: `~/Develop/sdata-core/src/sdata_core-config-runtime-internal.adb`

- [ ] **Step 1: Add the getter declaration**

In `sdata_core-config-runtime.ads`, after the line declaring `function Options_SAVEOVERWRT return Boolean;` (line ~82), add:

```ada
   function Options_Warn_Reserved      return Boolean;
```

In the private part, after `Options_SAVEOVERWRT_Value : Boolean := True;` (line ~160), add:

```ada
   Options_Warn_Reserved_Value : Boolean := True;
```

- [ ] **Step 2: Add the getter body + reset default**

In `sdata_core-config-runtime.adb`, alongside `function Options_SAVEOVERWRT return Boolean is (Options_SAVEOVERWRT_Value);` (line ~38), add:

```ada
   function Options_Warn_Reserved      return Boolean is (Options_Warn_Reserved_Value);
```

In the same file's reset/initialize routine (where `Options_SAVEOVERWRT_Value := True;` appears, line ~84), add:

```ada
      Options_Warn_Reserved_Value := True;
```

- [ ] **Step 3: Add the setter**

In `sdata_core-config-runtime-internal.ads`, after `procedure Set_Options_SAVEOVERWRT (Value : Boolean);` (line ~53):

```ada
   procedure Set_Options_Warn_Reserved      (Value : Boolean);
```

In `sdata_core-config-runtime-internal.adb`, after the `Set_Options_SAVEOVERWRT` body (line ~119):

```ada
   procedure Set_Options_Warn_Reserved (Value : Boolean) is
   begin
      Options_Warn_Reserved_Value := Value;
   end Set_Options_Warn_Reserved;
```

- [ ] **Step 4: Build sdata-core**

Run: `cd ~/Develop/sdata-core && alr build`
Expected: clean build, no errors.

- [ ] **Step 5: Commit**

```bash
cd ~/Develop/sdata-core
git add src/sdata_core-config-runtime.ads src/sdata_core-config-runtime.adb \
        src/sdata_core-config-runtime-internal.ads src/sdata_core-config-runtime-internal.adb
git commit -m "feat(config): add Options_Warn_Reserved runtime toggle (default on)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

> **Note:** sdata-core changes require a PR (server-enforced; see repo conventions). The agentic worker should accumulate the Phase-1 sdata-core commits on a branch and open a PR at the end of the phase, OR follow the user's preferred sdata-core workflow. Do NOT push directly to sdata-core `main`.

---

## Task 2: sdata-core — `Warn_Reserved_Columns` helper + `Execute_OPTIONS_WarnReserved`

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-commands.ads`
- Modify: `~/Develop/sdata-core/src/sdata_core-commands.adb`

- [ ] **Step 1: Declare the keyword-set type, helper, and OPTIONS executor**

In `sdata_core-commands.ads`, add near the top of the package spec a context clause and the set package. At the top of the file with the other `with` clauses add:

```ada
with Ada.Containers.Indefinite_Ordered_Sets;
```

Inside the package spec, near the other `Execute_OPTIONS_*` declarations (line ~247), add:

```ada
   --  Reserved-keyword warning support (per quoted-identifiers design,
   --  2026-05-30; promoted to sdata-core 2026-06-17 as the one shareable
   --  sliver). Each consumer passes its own grammar-specific keyword set.
   package Reserved_Keyword_Sets is
     new Ada.Containers.Indefinite_Ordered_Sets (String);

   --  Walk the current table's columns; for each upper-cased column name
   --  that is a member of Keywords, emit one stderr warning. No-op when
   --  Config.Runtime.Options_Warn_Reserved is False (gating lives here, the
   --  single authority — callers do not check the toggle).
   procedure Warn_Reserved_Columns (Keywords : Reserved_Keyword_Sets.Set);

   procedure Execute_OPTIONS_WarnReserved (Value : Boolean);
```

- [ ] **Step 2: Write the failing test (sdata-core unit test)**

sdata-core has its own unit tests. Locate the table/commands unit test driver:

Run: `ls ~/Develop/sdata-core/tests/ 2>/dev/null; grep -rln "Warn_Reserved\|Reserved_Keyword" ~/Develop/sdata-core/tests/ 2>/dev/null`

If a suitable driver exists (e.g. a commands or table unit test), add a test that:
1. Builds a small table with a column named `AS` (use the existing table-construction helpers the driver already uses).
2. Sets `Config.Runtime.Internal.Set_Options_Warn_Reserved (True)`.
3. Calls `Warn_Reserved_Columns` with a set containing `"AS"`.
4. Asserts the call completes (and, if the test harness can capture stderr, that the warning text appears).

If no unit driver cleanly supports stderr capture, rely on the sdata integration test `use_reserved_column_warning.cmd` (Task 9) as the behavioral test and keep this step to a compile-only smoke check. Document which path was taken in the commit message.

Run the driver build to confirm the new test fails to compile/link against the not-yet-implemented body.
Expected: FAIL (`Warn_Reserved_Columns` body missing).

- [ ] **Step 3: Implement the bodies**

In `sdata_core-commands.adb`, add `with`/`use` for the table and config if not already present (`SData_Core.Table`, `SData_Core.IO`, `SData_Core.Config.Runtime`, `SData_Core.Config.Runtime.Internal`). Then add the bodies:

```ada
   procedure Warn_Reserved_Columns (Keywords : Reserved_Keyword_Sets.Set) is
      use Ada.Characters.Handling;
   begin
      if not SData_Core.Config.Runtime.Options_Warn_Reserved then
         return;
      end if;
      for I in 1 .. SData_Core.Table.Column_Count loop
         declare
            Upper : constant String := To_Upper (SData_Core.Table.Column_Name (I));
         begin
            if Keywords.Contains (Upper) then
               SData_Core.IO.Put_Line_Error
                 ("warning: column """ & Upper
                  & """ matches a reserved keyword; reference it as `"
                  & Upper & "` or rename it");
            end if;
         end;
      end loop;
   end Warn_Reserved_Columns;

   procedure Execute_OPTIONS_WarnReserved (Value : Boolean) is
   begin
      SData_Core.Config.Runtime.Internal.Set_Options_Warn_Reserved (Value);
   end Execute_OPTIONS_WarnReserved;
```

Add `with Ada.Characters.Handling;` to the file's context clauses if absent.

- [ ] **Step 4: Build sdata-core**

Run: `cd ~/Develop/sdata-core && alr build`
Expected: clean build.

- [ ] **Step 5: Run sdata-core unit tests**

Run: `cd ~/Develop/sdata-core && make check` (or the project's test target)
Expected: PASS (including any new test from Step 2).

- [ ] **Step 6: Commit**

```bash
cd ~/Develop/sdata-core
git add src/sdata_core-commands.ads src/sdata_core-commands.adb tests/
git commit -m "feat(commands): add Warn_Reserved_Columns + Execute_OPTIONS_WarnReserved

Additive sdata-core API (pin-safe). Gating on Options_Warn_Reserved lives
inside the helper (single authority). Per quoted-identifiers design.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: sdata lexer — `Token_Quoted_Identifier` + `Token_Bad`

**Files:**
- Modify: `src/lexer/sdata-lexer.ads`
- Modify: `src/lexer/sdata-lexer.adb`

- [ ] **Step 1: Add token kinds**

In `src/lexer/sdata-lexer.ads`, in the `Token_Kind` enumeration, after `Token_String_Literal,` (line 17) add `Token_Quoted_Identifier,` and after `Token_Numeric_Literal,` add `Token_Bad,` — e.g.:

```ada
      Token_EOF,             -- End of file
      Token_Identifier,      -- Variables and function names
      Token_Quoted_Identifier, -- `backtick-quoted` identifier (any reserved word / spaces)
      Token_String_Literal,  -- "Quoted strings"
      Token_Numeric_Literal, -- 123.45
      Token_Bad,             -- Lex error sentinel (e.g. unterminated quoted identifier)
```

- [ ] **Step 2: Write the failing lexer unit test**

Find the lexer/sdata unit test driver:

Run: `grep -rln "Get_Next_Token\|SData.Lexer" tests/*.adb`

In the matching driver (likely `tests/sdata_unit_test.adb`), add tests:

```ada
   --  Quoted identifiers
   declare
      Ctx : SData.Lexer.Lexer_Context;
      T   : SData.Lexer.Token;
   begin
      SData.Lexer.Initialize (Ctx, "`AS`");
      T := SData.Lexer.Get_Next_Token (Ctx);
      Assert (T.Kind = SData.Lexer.Token_Quoted_Identifier, "backtick AS kind");
      Assert (T.Text (1 .. T.Length) = "AS", "backtick AS text");
   end;
   declare
      Ctx : SData.Lexer.Lexer_Context;
      T   : SData.Lexer.Token;
   begin
      SData.Lexer.Initialize (Ctx, "`as`");
      T := SData.Lexer.Get_Next_Token (Ctx);
      Assert (T.Text (1 .. T.Length) = "as", "case preserved at token level");
   end;
   declare
      Ctx : SData.Lexer.Lexer_Context;
      T   : SData.Lexer.Token;
   begin
      SData.Lexer.Initialize (Ctx, "`a.b c`");
      T := SData.Lexer.Get_Next_Token (Ctx);
      Assert (T.Text (1 .. T.Length) = "a.b c", "spaces and dots verbatim");
   end;
   declare  --  empty -> Token_Bad
      Ctx : SData.Lexer.Lexer_Context;
      T   : SData.Lexer.Token;
   begin
      SData.Lexer.Initialize (Ctx, "``");
      T := SData.Lexer.Get_Next_Token (Ctx);
      Assert (T.Kind = SData.Lexer.Token_Bad, "empty backticks -> Token_Bad");
   end;
   declare  --  unterminated at EOF -> Token_Bad
      Ctx : SData.Lexer.Lexer_Context;
      T   : SData.Lexer.Token;
   begin
      SData.Lexer.Initialize (Ctx, "`AS");
      T := SData.Lexer.Get_Next_Token (Ctx);
      Assert (T.Kind = SData.Lexer.Token_Bad, "EOF before close -> Token_Bad");
   end;
```

(Match the driver's actual assertion helper name/signature — `Assert` is illustrative; mirror the existing tests in that file.)

- [ ] **Step 3: Run the test to verify it fails**

Run: `make build && ./bin/sdata_unit_test` (or the driver's exact name/target)
Expected: FAIL — `Token_Quoted_Identifier`/`Token_Bad` recognised but lexer never produces them (kind mismatch), or compile error if helpers referenced before existing.

- [ ] **Step 4: Implement the scan**

In `src/lexer/sdata-lexer.adb`, add `with SData_Core.IO; use SData_Core.IO;` to the context clauses (lines ~5–6). Then, in `Get_Next_Token_Internal`, add a new branch for the backtick. Insert it after the single-quoted string-literal branch (after line 359, before the `else` punctuation `case` at line 362):

```ada
         --  Backtick-quoted identifier: `name`. Lets users reference column
         --  names that collide with reserved keywords or contain spaces/dots.
         --  Content is verbatim (no escapes); newline or EOF before the
         --  closing backtick, or empty content, is a lex error.
         elsif C = '`' then
            Advance (Ctx); -- skip opening backtick
            while not Is_End_Of_Source (Ctx)
              and then Current_Char (Ctx) /= '`'
              and then Current_Char (Ctx) /= ASCII.LF
            loop
               T.Length := T.Length + 1;
               T.Text (T.Length) := Current_Char (Ctx);
               Advance (Ctx);
            end loop;
            if Is_End_Of_Source (Ctx) or else Current_Char (Ctx) = ASCII.LF then
               Put_Line_Error
                 ("Error: unterminated quoted identifier at line"
                  & T.Line'Image);
               T.Kind   := Token_Bad;
               T.Length := 0;
            elsif T.Length = 0 then
               Put_Line_Error
                 ("Error: empty quoted identifier at line" & T.Line'Image);
               Advance (Ctx); -- skip closing backtick
               T.Kind := Token_Bad;
            else
               Advance (Ctx); -- skip closing backtick
               T.Kind := Token_Quoted_Identifier;
            end if;
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `make build && ./bin/sdata_unit_test`
Expected: PASS (the 5 new assertions).

- [ ] **Step 6: Commit**

```bash
git add src/lexer/sdata-lexer.ads src/lexer/sdata-lexer.adb tests/
git commit -m "feat(lexer): recognise backtick-quoted identifiers

New Token_Quoted_Identifier and Token_Bad. Newline/EOF before close or
empty content is a lex error via Put_Line_Error.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: sdata parser — identifier helpers + route all sites

**Files:**
- Modify: `src/parser/sdata-parser.adb`

- [ ] **Step 1: Add the two helpers**

Near the top of the package body (after the context clauses / first declarations), add:

```ada
   --  A quoted identifier (`name`) is accepted anywhere a bare identifier is.
   function Is_Identifier_Token (T : SData.Lexer.Token) return Boolean is
     (T.Kind = SData.Lexer.Token_Identifier
        or else T.Kind = SData.Lexer.Token_Quoted_Identifier);

   --  Raw identifier text (verbatim; callers upper-case on lookup as before).
   function Identifier_Text (T : SData.Lexer.Token) return String is
     (T.Text (1 .. T.Length));
```

(If the body already `use`s `SData.Lexer`, drop the qualification.)

- [ ] **Step 2: Write a failing integration test for the simplest site (PRINT)**

Create `tests/quoted_id_print.cmd`:

```
USE "tests/data/reserved_cols.csv"
PRINT `AS`
```

Create the data file `tests/data/reserved_cols.csv` (if not already present):

```
ID,AS,USE
1,10,100
2,20,200
```

Create the expected output `tests/expected/quoted_id_print.out` reflecting what `PRINT` emits for column `AS` (mirror the format other `*_print` expected files use — run an equivalent PRINT on a non-reserved column first to learn the exact format, then write the expected file).

- [ ] **Step 3: Run to verify it fails**

Run: `make check` (or the single-test runner the suite uses, e.g. `tests/run_one.sh quoted_id_print` if present)
Expected: FAIL — `` `AS` `` currently does not parse as an identifier in the PRINT argument list (it lexes as `Token_Quoted_Identifier`, which the parser site does not yet accept).

- [ ] **Step 4: Route every `Token_Identifier` site through the helper**

Run: `grep -n "Token_Identifier" src/parser/sdata-parser.adb` (18 sites; see line list in the spec/recon).

For each site, apply the mechanical transformation:

- `T.Kind = Token_Identifier` → `Is_Identifier_Token (T)`
- `T.Kind /= Token_Identifier` → `not Is_Identifier_Token (T)`
- `Token_Identifier | X | Y` (case/membership) → add `Token_Quoted_Identifier` to the alternative list, e.g. `Token_Identifier | Token_Quoted_Identifier | X | Y`
- wherever the matched token's text is then read as `Tok.Text (1 .. Tok.Length)` for an identifier, switch to `Identifier_Text (Tok)` for clarity.

Concrete examples (names will vary per site — adapt the local token variable):

```ada
   --  before
   exit when Tok.Kind /= Token_Identifier;
   --  after
   exit when not Is_Identifier_Token (Tok);
```

```ada
   --  before (case alternative, line ~57 / ~411)
   when Token_Identifier | Token_Numeric_Literal =>
   --  after
   when Token_Identifier | Token_Quoted_Identifier | Token_Numeric_Literal =>
```

```ada
   --  before
   if Alias_Tok.Kind /= Token_Identifier then
   --  after
   if not Is_Identifier_Token (Alias_Tok) then
```

Work through all 18 occurrences. After editing, re-run the grep and confirm every remaining bare `Token_Identifier` is intentional (e.g. inside the `Is_Identifier_Token` helper definition itself, or a context where a quoted identifier must NOT be accepted — there should be none of the latter per the spec).

- [ ] **Step 5: Run the PRINT test to verify it passes**

Run: `make check`
Expected: `quoted_id_print` PASSES; no regressions in the rest of the suite.

- [ ] **Step 6: Commit**

```bash
git add src/parser/sdata-parser.adb tests/quoted_id_print.cmd \
        tests/data/reserved_cols.csv tests/expected/quoted_id_print.out
git commit -m "feat(parser): accept quoted identifiers at all identifier sites

Add Is_Identifier_Token/Identifier_Text helpers; route all 18 Token_Identifier
sites. First integration test: PRINT \`AS\`.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: sdata — integration tests for the remaining syntactic positions

**Files (create each):** `tests/quoted_id_let_lhs.cmd`, `tests/quoted_id_rename.cmd`, `tests/quoted_id_keep.cmd`, `tests/quoted_id_drop.cmd`, `tests/quoted_id_by.cmd`, `tests/quoted_id_per_dataset_keep.cmd`, `tests/quoted_id_per_dataset_rename.cmd`, `tests/quoted_id_save_if.cmd`, `tests/quoted_id_write_target_alias.cmd` — plus matching `tests/expected/<name>.out` for each.

For each test below: write the `.cmd`, run `make check` to see it fail or produce output, capture/author the correct `tests/expected/<name>.out` (verify the output is *semantically correct*, not just whatever the binary emits), then re-run to confirm PASS. Commit in small batches (2–3 tests per commit).

- [ ] **Step 1: LET LHS** — `tests/quoted_id_let_lhs.cmd`

```
USE "tests/data/reserved_cols.csv"
LET `AS` = 5
PRINT `AS`
```
Expected: every row's `AS` column is 5.

- [ ] **Step 2: RENAME** — `tests/quoted_id_rename.cmd`

```
USE "tests/data/reserved_cols.csv"
RENAME `AS`=ASCOL
NAMES
```
Expected `NAMES`: `ID ASCOL USE` (bare names, no backticks — display behavior unchanged).

- [ ] **Step 3: KEEP** — `tests/quoted_id_keep.cmd`

```
USE "tests/data/reserved_cols.csv"
KEEP `AS`
NAMES
```
Expected `NAMES`: `AS`.

- [ ] **Step 4: DROP** — `tests/quoted_id_drop.cmd`

```
USE "tests/data/reserved_cols.csv"
DROP `AS`
NAMES
```
Expected `NAMES`: `ID USE`.

- [ ] **Step 5: BY** — `tests/quoted_id_by.cmd`

```
USE "tests/data/reserved_cols.csv"
BY `AS`
RUN
```
Expected: runs without "Unrecognized command"; BY group on `AS` established. (Author the expected output by running an equivalent BY on a non-reserved column to learn the format.)

- [ ] **Step 6: Per-dataset KEEP=** — `tests/quoted_id_per_dataset_keep.cmd`

```
USE "tests/data/reserved_cols.csv" (KEEP=`AS` ID)
NAMES
```
Expected `NAMES`: `ID AS` (whatever order the loader preserves — verify).

- [ ] **Step 7: Per-dataset RENAME=()** — `tests/quoted_id_per_dataset_rename.cmd`

```
USE "tests/data/reserved_cols.csv" (RENAME=(`AS`=AS_COL))
NAMES
```
Expected `NAMES`: `ID AS_COL USE`.

- [ ] **Step 8: SAVE IF= referencing a quoted id** — `tests/quoted_id_save_if.cmd`

```
USE "tests/data/reserved_cols.csv"
SAVE "tests/tmp/qid_if.csv" (IF=`AS`>10)
```
Expected: only rows where `AS` > 10 are written (verify by reading back or via the suite's SAVE-output assertion pattern). Clean up `tests/tmp/qid_if.csv` per the suite's convention.

- [ ] **Step 9: WRITE target + AS alias quoting** — `tests/quoted_id_write_target_alias.cmd`

```
USE "tests/data/reserved_cols.csv"
SAVE "tests/tmp/qid_alias.csv" AS `AS`
WRITE `AS`
```
Expected: validates an alias name can itself be quoted and a WRITE target can be quoted. Author expected output from the SAVE/WRITE format the suite already uses.

- [ ] **Step 10: Run the full suite + commit**

Run: `make check`
Expected: all new `quoted_id_*` tests PASS; total integration count rises by 9.

```bash
git add tests/quoted_id_*.cmd tests/expected/quoted_id_*.out
git commit -m "test: quoted identifiers across all syntactic positions

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: sdata — reserved-keyword set

**Files:**
- Create: `src/sdata-reserved_keywords.ads`

- [ ] **Step 1: Define the set**

Extract the canonical keyword list from `src/lexer/sdata-lexer.adb` (the `Upper = "…"` chain, lines 245–313). Create `src/sdata-reserved_keywords.ads`:

```ada
--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later

with SData_Core.Commands;

package SData.Reserved_Keywords is

   --  The set of sdata reserved keywords, upper-cased. Source of truth is the
   --  keyword chain in SData.Lexer (src/lexer/sdata-lexer.adb); keep in sync.
   --  Passed to SData_Core.Commands.Warn_Reserved_Columns at USE time.
   function Set return SData_Core.Commands.Reserved_Keyword_Sets.Set;

end SData.Reserved_Keywords;
```

And `src/sdata-reserved_keywords.adb`:

```ada
--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later

package body SData.Reserved_Keywords is

   function Set return SData_Core.Commands.Reserved_Keyword_Sets.Set is
      use SData_Core.Commands.Reserved_Keyword_Sets;
      S : SData_Core.Commands.Reserved_Keyword_Sets.Set := Empty_Set;
   begin
      --  Mirror SData.Lexer's keyword chain. Command/keyword tokens only;
      --  NOT operators/punctuation. Keep alphabetical for review.
      for K of String_Array'(
        +"ALL", +"AND", +"APPEND", +"ARRAY", +"AS", +"BREAK", +"BY", +"CASE",
        +"DELETE", +"DIGITS", +"DIM", +"DISPLAY", +"DROP", +"ECHO", +"ELSE",
        +"ELSEIF", +"END", +"FOR", +"FPATH", +"HEADER", +"HELP", +"HOLD",
        +"IF", +"IN", +"INTERLEAVE", +"INTO", +"JOIN", +"KEEP", +"LET",
        +"LIST", +"MOCK", +"NAMES", +"NEW", +"NEXT", +"NOT", +"OPTIONS",
        +"OR", +"OTHERWISE", +"OUTPUT", +"PRINT", +"QUIT", +"REM", +"RENAME",
        +"REPEAT", +"RSEED", +"RUN", +"SAVE", +"SELECT", +"SET", +"SORT",
        +"STEP", +"SUBMIT", +"SYSTEM", +"THEN", +"TO", +"UNHOLD", +"UNSET",
        +"UNTIL", +"USE", +"WEND", +"WHEN", +"WHILE", +"WRITE", +"XOR")
      loop
         S.Insert (K);
      end loop;
      return S;
   end Set;

end SData.Reserved_Keywords;
```

**Implementation note:** `Reserved_Keyword_Sets` is `Indefinite_Ordered_Sets (String)`, so elements are plain `String`. The `+"..."`/`String_Array` sugar above is illustrative — use the simplest concrete form that compiles, e.g. a local `array (Positive range <>) of access constant String` is awkward with `String`; prefer just a sequence of `S.Insert ("ALL"); S.Insert ("AND"); …` statements, OR iterate a constant `array (1 .. N) of Unbounded_String`. Pick one and make it compile. The exact keyword list MUST match the lexer chain — cross-check against lines 245–313 of `sdata-lexer.adb`.

- [ ] **Step 2: Build**

Run: `make build`
Expected: clean compile.

- [ ] **Step 3: Commit**

```bash
git add src/sdata-reserved_keywords.ads src/sdata-reserved_keywords.adb
git commit -m "feat: sdata reserved-keyword set for USE-time warning

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: sdata — call `Warn_Reserved_Columns` after USE

**Files:**
- Modify: `src/sdata-interpreter-execute_declarative.adb` (single-dataset path, after `Execute_USE_Single` completes, ~line 184)
- Modify: `src/sdata-interpreter.adb` (multi-dataset path, after `Install_To_Current`, lines ~1075 and ~1091)

- [ ] **Step 1: Write the failing warning test**

Create `tests/use_reserved_column_warning.cmd`:

```
USE "tests/data/reserved_cols.csv"
```

The suite must assert the warning text appears on **stderr**. Inspect how the suite captures stderr for existing warning/error tests (e.g. grep `tests/` for an existing `*.err` expected-file convention or a `2>&1` redirect in the runner):

Run: `ls tests/expected/*.err 2>/dev/null | head; grep -rln "2>&1\|stderr" tests/ scripts/ Makefile 2>/dev/null | head`

Author the expected artifact in whatever form the suite uses (e.g. `tests/expected/use_reserved_column_warning.err` or a combined `.out`) containing:

```
warning: column "AS" matches a reserved keyword; reference it as `AS` or rename it
warning: column "USE" matches a reserved keyword; reference it as `USE` or rename it
```

(The data file has both `AS` and `USE` reserved columns; `ID` is not reserved. Order follows column order.)

- [ ] **Step 2: Run to verify it fails**

Run: `make check`
Expected: FAIL — no warning emitted yet.

- [ ] **Step 3: Add the call at the single-dataset USE site**

In `src/sdata-interpreter-execute_declarative.adb`, after the single-dataset load completes (end of `Execute_USE_Single`, around line 184, after the table is installed), add:

```ada
            SData_Core.Commands.Warn_Reserved_Columns
              (SData.Reserved_Keywords.Set);
```

Add `with SData.Reserved_Keywords;` to the unit's context clauses if not visible.

- [ ] **Step 4: Add the call at the multi-dataset USE site**

In `src/sdata-interpreter.adb`, after each `SData.Transient_Table.Install_To_Current (...)` for the USE merge result (lines ~1075 and ~1091), add the same call:

```ada
                  SData_Core.Commands.Warn_Reserved_Columns
                    (SData.Reserved_Keywords.Set);
```

Ensure it runs once per completed USE, not once per dataset. If both lines 1075 and 1091 are alternative branches of the same USE completion, add it once at the common continuation point; if they are genuinely distinct completion paths, add to each. Verify by reading the surrounding control flow.

- [ ] **Step 5: Run to verify it passes**

Run: `make check`
Expected: `use_reserved_column_warning` PASSES; no other regressions.

- [ ] **Step 6: Commit**

```bash
git add src/sdata-interpreter-execute_declarative.adb src/sdata-interpreter.adb \
        tests/use_reserved_column_warning.cmd tests/expected/use_reserved_column_warning.*
git commit -m "feat: warn at USE when a column matches a reserved keyword

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: sdata — `OPTIONS WARNRESERVED` key + suppression test

**Files:**
- Modify: `src/sdata-interpreter-execute_declarative.adb` (OPTIONS dispatch ~line 836+, and no-arg display ~line 817–830)

- [ ] **Step 1: Write the failing suppression test**

Create `tests/quoted_id_warn_suppress.cmd`:

```
OPTIONS WARNRESERVED NO
USE "tests/data/reserved_cols.csv"
```

Expected artifact: **no** warning lines on stderr (empty `.err`, or per the suite's convention for "no stderr"). Also create `tests/quoted_id_warn_display.cmd` to cover the display path:

```
OPTIONS WARNRESERVED NO
OPTIONS
```

Expected (`.out`): the full OPTIONS listing now includes a line `OPTIONS WARNRESERVED NO` (and `YES` by default). Capture the existing OPTIONS listing first to author the exact expected block.

- [ ] **Step 2: Run to verify it fails**

Run: `make check`
Expected: FAIL — `WARNRESERVED` is an unrecognized OPTIONS key; warning still appears; display lacks the line.

- [ ] **Step 3: Add the dispatch branch**

In `src/sdata-interpreter-execute_declarative.adb`, in the OPTIONS `elsif Key = "…"` chain (after the `SAVEOVERWRT`/`PROGRESS` branches, ~line 857), add:

```ada
            elsif Key = "WARNRESERVED" then
               SData_Core.Commands.Execute_OPTIONS_WarnReserved
                 (Val_Upper = "YES");
```

(Match the surrounding branches' exact value-parsing idiom — `Val_Upper` is the upper-cased value already used by `HEADER`/`SAVEOVERWRT`.)

- [ ] **Step 4: Add the no-arg display line**

In the OPTIONS no-arg display block (~line 817–830), after the `PROGRESS` line (line 830), add:

```ada
               Put_Line ("OPTIONS WARNRESERVED " & Bool_Display (SData_Core.Config.Runtime.Options_Warn_Reserved));
```

- [ ] **Step 5: Run to verify it passes**

Run: `make check`
Expected: both new tests PASS.

- [ ] **Step 6: Commit**

```bash
git add src/sdata-interpreter-execute_declarative.adb tests/quoted_id_warn_*.cmd \
        tests/expected/quoted_id_warn_*
git commit -m "feat: OPTIONS WARNRESERVED to suppress reserved-keyword warning

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: sdata — user-facing docs (HELP, man, design.md) + snapshots

**Files:**
- Modify: `src/sdata-help.adb`
- Modify: `man/man1/sdata.1`
- Modify: `doc/design.md`
- Regenerate: `tests/expected/help_all.out` and any `*options*` snapshot

- [ ] **Step 1: Update built-in HELP**

In `src/sdata-help.adb`: (a) document `OPTIONS WARNRESERVED YES|NO` in the OPTIONS topic alongside `HEADER`/`SAVEOVERWRT`; (b) document the backtick quoted-identifier notation in the syntax/identifiers topic ("Use `` `name` `` to reference a column whose name is a reserved keyword or contains spaces."). Find the OPTIONS topic text:

Run: `grep -n "SAVEOVERWRT\|PROGRESS\|HEADER" src/sdata-help.adb`

- [ ] **Step 2: Update the man page**

In `man/man1/sdata.1`: add `WARNRESERVED` to the OPTIONS key list, and add quoted-identifier notation to the LANGUAGE OVERVIEW (line ~138). Match existing groff formatting.

- [ ] **Step 3: Update the design doc**

In `doc/design.md`: document the backtick quoted-identifier syntax (in the identifier/lexical section) and the `WARNRESERVED` OPTIONS key (in the OPTIONS table). Match the existing HTML-table format for the OPTIONS entry.

- [ ] **Step 4: Regenerate HELP snapshot**

Run: `make build && ./bin/sdata <<< "HELP /ALL" > tests/expected/help_all.out` (use the exact mechanism the suite uses to generate this snapshot — check `scripts/` or the Makefile for a regen target before hand-editing). Also regenerate any options-display snapshot that lists OPTIONS keys.

Run: `make check`
Expected: `help_all` and options snapshots PASS with the new content.

- [ ] **Step 5: Commit**

```bash
git add src/sdata-help.adb man/man1/sdata.1 doc/design.md tests/expected/help_all.out tests/expected/*options*
git commit -m "docs: document quoted identifiers + OPTIONS WARNRESERVED (HELP, man, design)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Phase 1 — cross-crate gate + ship

- [ ] **Step 1: Full cross-crate gate**

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && make check
cd ~/Develop/data-vandal && make check
```
Expected: all green. (data-vandal unchanged in P1 but must still build/pass against the new sdata-core.)

- [ ] **Step 2: sdata-core PR**

Open a PR for the sdata-core changes (Tasks 1–2) per repo conventions (sdata-core requires PRs). After merge, ensure sdata's path pin / version constraint still resolves. If sdata-core's version was bumped, update `sdata/alire.toml` and `data-vandal/alire.toml` per CLAUDE.md, and bump sdata-core's `consumer-tests.yml` ref if a release tag was cut.

- [ ] **Step 3: Run `/ssd gate` on the sdata branch**

The SSD review gate (code-reviewer) must show no BLOCKER/MAJOR before merge.

- [ ] **Step 4: Update SSD state**

Mark P1 done in `.ssd/current.yml`; record handoff notes for P2 in `.ssd/current.notes.yml`.

---

# PHASE 2 — data-vandal quoted identifiers + warning

> Mirrors Tasks 3, 4, 6, 7 against data-vandal's own lexer/parser. The sdata-core helper from P1 is reused as-is (no sdata-core change in P2).

## Task 11: data-vandal lexer — `Token_Quoted_Identifier` + `Token_Bad`

**Files:**
- Modify: `~/Develop/data-vandal/src/lexer/data_vandal-lexer.ads`
- Modify: `~/Develop/data-vandal/src/lexer/data_vandal-lexer.adb`

- [ ] **Step 1:** Add `Token_Quoted_Identifier` and `Token_Bad` to `Data_Vandal.Lexer.Token_Kind` (after `Token_Identifier` / `Token_Numeric_Literal`, mirroring Task 3 Step 1).
- [ ] **Step 2:** Write failing lexer unit tests in data-vandal's lexer test driver (find via `grep -rln "Get_Next_Token" ~/Develop/data-vandal/tests/`), mirroring Task 3 Step 2 (backtick `AS`, case preserved, spaces/dots, empty→Bad, EOF→Bad).
- [ ] **Step 3:** Run to verify FAIL.
- [ ] **Step 4:** Add `with Data_Vandal.IO;` or the data-vandal error facility (`grep -n "Put_Line_Error\|with " ~/Develop/data-vandal/src/lexer/data_vandal-lexer.adb`; data-vandal also depends on `SData_Core.IO` — use `SData_Core.IO.Put_Line_Error`). Insert the backtick branch into data-vandal's `Get_Next_Token_Internal` mirroring Task 3 Step 4 (its string-literal scan is at ~lines 218–266; place the backtick branch adjacent, before the punctuation `case`).
- [ ] **Step 5:** Run to verify PASS.
- [ ] **Step 6:** Commit (data-vandal requires a PR/branch — accumulate; do not push to `main`).

## Task 12: data-vandal parser — helpers + route all 12 sites

**Files:**
- Modify: `~/Develop/data-vandal/src/parser/data_vandal-parser.adb`

- [ ] **Step 1:** Add `Is_Identifier_Token` / `Identifier_Text` helpers (mirror Task 4 Step 1, using `Data_Vandal.Lexer`).
- [ ] **Step 2:** Create `~/Develop/data-vandal/tests/quoted_id_keep.cmd` (KEEP is a shared data-vandal command) plus a data CSV with a reserved column and the matching expected file. Run to verify FAIL.
- [ ] **Step 3:** `grep -n "Token_Identifier" ~/Develop/data-vandal/src/parser/data_vandal-parser.adb` (12 sites) and route each through the helper (same transformations as Task 4 Step 4).
- [ ] **Step 4:** Run `cd ~/Develop/data-vandal && make check` → PASS.
- [ ] **Step 5:** Add a focused subset of position tests relevant to data-vandal's grammar (it has USE, KEEP, DROP, SELECT, ARRAY, BY, SAVE, OUTPUT, FPATH, VANDALIZE — NOT LET/SET/PRINT/RENAME). Create `quoted_id_*.cmd` for KEEP, DROP, BY, per-dataset KEEP=, SELECT filter, and VANDALIZE column targets, each with expected output.
- [ ] **Step 6:** Commit.

## Task 13: data-vandal — reserved-keyword set + USE warning

**Files:**
- Create: `~/Develop/data-vandal/src/data_vandal-reserved_keywords.ads` / `.adb`
- Modify: data-vandal USE path — `~/Develop/data-vandal/src/data_vandal-interpreter.adb` (~line 76) and `~/Develop/data-vandal/src/data_vandal_main.adb` (~line 424, the `-u` path)

- [ ] **Step 1:** Create the data-vandal keyword set (mirror Task 6) extracting data-vandal's keyword chain from `data_vandal-lexer.adb` lines ~278–318 (USE, FPATH, OUTPUT, SELECT, KEEP, DROP, ARRAY, VANDALIZE, RUN, HELP, RSEED, QUIT, EXIT, INTO, MISS, SHUFFLE, PERTURB, SENTINEL, ASTEXT, BY, STYLE, CASE, SAVE, NOT, AND, OR). Expose `Data_Vandal.Reserved_Keywords.Set` returning `SData_Core.Commands.Reserved_Keyword_Sets.Set`.
- [ ] **Step 2:** Write failing warning test `~/Develop/data-vandal/tests/use_reserved_column_warning.cmd` (load CSV with a column named e.g. `BY` or `KEEP`; assert warning on stderr per data-vandal's test convention).
- [ ] **Step 3:** Run → FAIL.
- [ ] **Step 4:** Add `SData_Core.Commands.Warn_Reserved_Columns (Data_Vandal.Reserved_Keywords.Set);` after the USE load in both the interpreter dispatch (`Stmt_USE`, after `Execute_USE`, ~line 76+) and the `-u` CLI path in `data_vandal_main.adb` (~line 424+). Add the `with`.
- [ ] **Step 5:** Run → PASS. Note the toggle defaults ON and data-vandal cannot change it until P3 — that is expected.
- [ ] **Step 6:** Commit.

## Task 14: Phase 2 — cross-crate gate + ship

- [ ] **Step 1:** `cd ~/Develop/data-vandal && make check` (green) and re-run sdata `make check` (unaffected).
- [ ] **Step 2:** Open data-vandal PR; `/ssd gate`; merge.
- [ ] **Step 3:** Update SSD state; handoff notes for P3.

---

# PHASE 3 — data-vandal OPTIONS command (+ wire WARNRESERVED)

> This is the genuinely-separate feature: data-vandal has no OPTIONS command today. Build a minimal one exposing only `WARNRESERVED`.

## Task 15: data-vandal lexer + AST — OPTIONS statement

**Files:**
- Modify: `~/Develop/data-vandal/src/lexer/data_vandal-lexer.{ads,adb}`
- Modify: `~/Develop/data-vandal/src/ast/data_vandal-ast.{ads,adb}`

- [ ] **Step 1:** Add `Token_OPTIONS` to `Data_Vandal.Lexer.Token_Kind` (command-keyword group) and an `elsif Upper = "OPTIONS" then T.Kind := Token_OPTIONS;` branch in the keyword chain (~line 278+).
- [ ] **Step 2:** In `data_vandal-ast.ads`, add a `Stmt_OPTIONS` statement-kind variant with fields mirroring sdata's (`Options_Key`/`Options_Key_Len`/`Options_Val`/`Options_Val_Len`, sized from existing `Max_*` constants — check what data-vandal's AST uses for bounded strings). Add any required `Free`/finalization arm in `data_vandal-ast.adb` (Stmt_OPTIONS holds only fixed strings, so no heap to free — mirror a similar leaf statement).
- [ ] **Step 3:** Build → clean compile (no parser/interp use yet).
- [ ] **Step 4:** Commit.

## Task 16: data-vandal parser — parse `OPTIONS key value`

**Files:**
- Modify: `~/Develop/data-vandal/src/parser/data_vandal-parser.adb`

- [ ] **Step 1:** Write failing test `~/Develop/data-vandal/tests/options_warnreserved.cmd`:

```
OPTIONS WARNRESERVED NO
OPTIONS
```
Expected `.out`: an OPTIONS listing showing `OPTIONS WARNRESERVED NO`. (Author after the display path exists; for now expect a parse-success smoke.)

- [ ] **Step 2:** Run → FAIL ("Unrecognized command OPTIONS" or parse error).
- [ ] **Step 3:** Add a parse arm for `Token_OPTIONS`: consume the key identifier (accept `Token_Identifier`/`Token_Quoted_Identifier` — though keys are bare), then an optional value token (identifier or `YES`/`NO`); with no key, produce a "display all" OPTIONS statement (key length 0). Populate the `Stmt_OPTIONS` node. Mirror sdata's OPTIONS parse shape (`grep -n "Stmt_OPTIONS\|Options_Key" src/parser/sdata-parser.adb` in sdata for reference).
- [ ] **Step 4:** Build → clean. (Test still fails at execution until Task 17.)
- [ ] **Step 5:** Commit.

## Task 17: data-vandal interpreter — dispatch + no-arg display + wire WARNRESERVED

**Files:**
- Modify: `~/Develop/data-vandal/src/data_vandal-interpreter.adb`

- [ ] **Step 1:** Add a `when Stmt_OPTIONS =>` arm to the interpreter's statement dispatch (alongside `Stmt_USE` etc., ~line 65+). Extract key (upper-cased) and value (upper-cased). Logic:

```ada
         when Stmt_OPTIONS =>
            declare
               Key : constant String := To_Upper (S.Options_Key (1 .. S.Options_Key_Len));
               Val_Upper : constant String := To_Upper (S.Options_Val (1 .. S.Options_Val_Len));
            begin
               if S.Options_Key_Len = 0 then
                  --  Display all (minimal: just the one key data-vandal exposes).
                  Put_Line ("OPTIONS WARNRESERVED "
                            & (if SData_Core.Config.Runtime.Options_Warn_Reserved
                               then "YES" else "NO"));
               elsif Key = "WARNRESERVED" then
                  SData_Core.Commands.Execute_OPTIONS_WarnReserved (Val_Upper = "YES");
               else
                  Put_Line_Error ("Error: unknown OPTIONS key """ & Key & """");
               end if;
            end;
```

Add `with`/`use` for `Ada.Characters.Handling`, `SData_Core.Config.Runtime`, `SData_Core.Commands`, and the IO package as needed (match what the unit already imports).

- [ ] **Step 2:** Author the expected output for `options_warnreserved.cmd` (now that the display path exists) and a suppression test `~/Develop/data-vandal/tests/use_reserved_warn_suppress.cmd`:

```
OPTIONS WARNRESERVED NO
USE "tests/data/reserved_cols.csv"
```
Expected: no warning on stderr.

- [ ] **Step 3:** Run `cd ~/Develop/data-vandal && make check` → PASS.
- [ ] **Step 4:** Commit.

## Task 18: data-vandal — docs (man page + HELP)

**Files:**
- Modify: `~/Develop/data-vandal/man/man1/data-vandal.1`
- Modify: `~/Develop/data-vandal/src/data_vandal-help.adb`

- [ ] **Step 1:** Document the new `OPTIONS WARNRESERVED YES|NO` command and the backtick quoted-identifier notation in the man page (mirror sdata's wording, adapted to data-vandal's command set).
- [ ] **Step 2:** Add an OPTIONS entry + quoted-identifier note to `data_vandal-help.adb`. If data-vandal has a HELP snapshot test, regenerate it.
- [ ] **Step 3:** `make check` → PASS.
- [ ] **Step 4:** Commit.

## Task 19: Phase 3 — final cross-crate gate + ship

- [ ] **Step 1:** Full gate: sdata-core `alr build`, sdata `make check`, data-vandal `make check` — all green.
- [ ] **Step 2:** data-vandal PR; `/ssd gate`; merge.
- [ ] **Step 3:** Close the feature in `.ssd/current.yml`; archive artifacts; update memory if any durable facts emerged (e.g. data-vandal now has an OPTIONS command).

---

## Self-Review (plan vs spec)

**Spec coverage:**
- Syntax (backtick quoted identifier) → Task 3 (lexer), Task 4 (parser). ✅
- Lexer token + errors (newline/EOF/empty) → Task 3 + lexer unit tests. ✅
- Parser helpers + all sites → Task 4 (sdata, 18), Task 12 (data-vandal, 12). ✅
- USE-time warning → Task 2 (helper), Task 7 (sdata wiring), Task 13 (data-vandal wiring). ✅
- sdata-core helper promotion (Decision 2) → Task 2. ✅
- Gating inside helper (Decision 3) → Task 2 Step 3. ✅
- OPTIONS WARNRESERVED (Decision 4) → Task 8 (sdata), Tasks 15–17 (data-vandal OPTIONS command). ✅
- Display behavior unchanged (bare names) → asserted in Tasks 2/5 (RENAME/NAMES expected output has no backticks). ✅
- Docs in all three references → Task 9 (sdata HELP/man/design + snapshots), Task 18 (data-vandal man/HELP). ✅
- Integration tests (one per position) → Tasks 4–5 (sdata), Task 12 (data-vandal subset). ✅
- Warning test → Task 7 (sdata), Task 13 (data-vandal). ✅
- Both crates (Decision 1) → P1+P2+P3. ✅
- 3-phase shippable sequence → P1 Task 10, P2 Task 14, P3 Task 19. ✅

**Placeholder scan:** Task 6 Step 1 flags its own `+"..."` sugar as illustrative and instructs picking a concrete compiling form — acceptable (the surrounding Indefinite_Ordered_Sets API and keyword list are concrete). All other code steps are concrete. Expected-output `.out`/`.err` files are authored against real binary output per each test's instructions (the suite's snapshot convention), since exact formatting cannot be hand-divined without running the existing format — each such step instructs running an equivalent command first to learn the format.

**Type/name consistency:** `Reserved_Keyword_Sets` (package), `Warn_Reserved_Columns (Keywords : ...Set)`, `Execute_OPTIONS_WarnReserved (Value : Boolean)`, `Options_Warn_Reserved` (getter), `Set_Options_Warn_Reserved` (setter), `Token_Quoted_Identifier`, `Token_Bad`, `Is_Identifier_Token`/`Identifier_Text` — used consistently across all tasks. Field `Length` (not `Text_Len`) and parameterless `Column_Count`/`Column_Name` used throughout.

**Known follow-ups (out of scope, logged):** data-vandal OPTIONS exposes only `WARNRESERVED` this cycle; the full CSVDLM/HEADER/CHARSET surface and any backtick-in-CSV-header edge case remain deferred per the spec.
