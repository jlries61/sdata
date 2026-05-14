# Debug Log Levels Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single `Debug_Mode` boolean with a three-level `Debug_Level` integer (0=off, 1=sparse I/O, 2=+record/flow, 3=+assignments); `--debug` with no argument stays level 3.

**Architecture:** `sdata-config.ads` gains `Debug_Level : Natural := 0`. `Debug_Trace` in `sdata-interpreter.adb` takes an explicit `Level` parameter and fires only when `Debug_Level >= Level`. All ~15 call sites are tagged with their level; the CLI gains `--debug=N` parsing; `OPTIONS DEBUG N` sets the level at runtime.

**Tech Stack:** Ada 2012, GNAT/GPRbuild, Alire. Build: `alr build`. Test: `make check` (131 integration tests + 5 unit test binaries).

---

## File Map

| File | Change |
|---|---|
| `src/sdata-config.ads` | `Debug_Mode : Boolean` → `Debug_Level : Natural` |
| `src/sdata-interpreter.adb` | `Debug_Trace` signature + body; step-mode check; DELETE/SELECT/RUN traces |
| `src/sdata-interpreter-process_one_record.adb` | `Debug_Mode` → `Debug_Level >= 2` |
| `src/sdata_main.adb` | `--debug` arm + new `--debug=N` arm; help line |
| `src/sdata-interpreter-execute_assignment.adb` | 4 `Debug_Trace` calls → `Level => 3` |
| `src/sdata-interpreter-execute_control_flow.adb` | 5 `Debug_Trace` calls → `Level => 2` |
| `src/sdata-interpreter-execute_declarative.adb` | USE trace → `Level => 1`; `OPTIONS DEBUG` display + handler |
| `src/sdata-interpreter-execute_io.adb` | SUBMIT trace → `Level => 1` |
| `src/sdata-help.adb` | `Help_DEBUGGER` rewrite with level table |
| `man/man1/sdata.1` | `--debug` entry updated |
| `tests/debug_level1.cmd` + `.expected` | New integration test |
| `tests/debug_level2.cmd` + `.expected` | New integration test |
| `tests/debug_level3.cmd` + `.expected` | New integration test |
| `tests/debug_options.cmd` + `.expected` | New integration test |

---

## Task 1: Replace `Debug_Mode` with `Debug_Level` in config and core interpreter

This task makes everything compile with existing behaviour preserved. `Debug_Trace`
gets a temporary default `Level := 2` so the ~15 call sites in other files
continue to compile unchanged until Task 3 tags them explicitly.

**Files:**
- Modify: `src/sdata-config.ads:43`
- Modify: `src/sdata-interpreter.adb:183-188` (Debug_Trace body)
- Modify: `src/sdata-interpreter.adb:823` (step-mode check)
- Modify: `src/sdata-interpreter.adb:585` (DELETE trace)
- Modify: `src/sdata-interpreter.adb:745,747,752` (SELECT traces)
- Modify: `src/sdata-interpreter.adb:870` (RUN complete trace)
- Modify: `src/sdata-interpreter-process_one_record.adb:35`
- Modify: `src/sdata_main.adb:376`

- [ ] **Step 1: Replace the config variable**

In `src/sdata-config.ads`, replace line 43:
```ada
   Debug_Mode         : Boolean := False; -- If True, trace each statement and record to stderr.
```
with:
```ada
   Debug_Level        : Natural := 0;     -- 0=off 1=I/O 2=+record/flow 3=+assignments
```

- [ ] **Step 2: Update `Debug_Trace` in interpreter body**

In `src/sdata-interpreter.adb`, replace lines 183–188:
```ada
   procedure Debug_Trace (Msg : String) is
   begin
      if SData.Config.Debug_Mode then
         Put_Line_Error ("[debug] " & Msg);
      end if;
   end Debug_Trace;
```
with:
```ada
   procedure Debug_Trace (Msg : String; Level : Positive := 2) is
   begin
      if SData.Config.Debug_Level >= Level then
         Put_Line_Error ("[debug] " & Msg);
      end if;
   end Debug_Trace;
```
The `Level := 2` default is **temporary** — it keeps all existing call sites
compiling. It is removed in Task 3 after every site is tagged explicitly.

- [ ] **Step 3: Update step-mode check**

In `src/sdata-interpreter.adb`, find the line (around 823) that reads:
```ada
         SData.Config.Debug_Mode and then SData.IO.Is_Interactive;
```
Replace with:
```ada
         SData.Config.Debug_Level > 0 and then SData.IO.Is_Interactive;
```

- [ ] **Step 4: Tag the three trace calls in the interpreter body**

Still in `src/sdata-interpreter.adb`:

Line ~585 — DELETE:
```ada
            Debug_Trace ("DELETE: record marked");
```
→
```ada
            Debug_Trace ("DELETE: record marked", 2);
```

Lines ~745, ~747 — SELECT KEPT/DROPPED:
```ada
                        Debug_Trace ("SELECT → KEPT");
                     else
                        Debug_Trace ("SELECT → DROPPED");
```
→
```ada
                        Debug_Trace ("SELECT → KEPT", 2);
                     else
                        Debug_Trace ("SELECT → DROPPED", 2);
```

Lines ~752–756 — SELECT summary:
```ada
                  Debug_Trace ("SELECT → "
                               & Ada.Strings.Fixed.Trim (Natural'Image (Count), Ada.Strings.Both)
                               & " of "
                               & Ada.Strings.Fixed.Trim (Natural'Image (Total), Ada.Strings.Both)
                               & " records kept");
```
→
```ada
                  Debug_Trace ("SELECT → "
                               & Ada.Strings.Fixed.Trim (Natural'Image (Count), Ada.Strings.Both)
                               & " of "
                               & Ada.Strings.Fixed.Trim (Natural'Image (Total), Ada.Strings.Both)
                               & " records kept", 2);
```

Lines ~870–874 — RUN complete:
```ada
               Debug_Trace ("RUN complete: "
                            & RC (RC'First + 1 .. RC'Last)
                            & " records, "
                            & VC (VC'First + 1 .. VC'Last)
                            & " variables");
```
→
```ada
               Debug_Trace ("RUN complete: "
                            & RC (RC'First + 1 .. RC'Last)
                            & " records, "
                            & VC (VC'First + 1 .. VC'Last)
                            & " variables", 1);
```

- [ ] **Step 5: Update process_one_record**

In `src/sdata-interpreter-process_one_record.adb`, replace line 35:
```ada
      if SData.Config.Debug_Mode then
```
with:
```ada
      if SData.Config.Debug_Level >= 2 then
```

- [ ] **Step 6: Update sdata_main.adb existing --debug arm**

In `src/sdata_main.adb`, replace line 376:
```ada
            Debug_Mode := True;
```
with:
```ada
            SData.Config.Debug_Level := 3;
```
(Remove `Debug_Mode :=` — the variable no longer exists. The `with SData.Config;
use SData.Config;` at the top of the file makes `Debug_Level` visible directly,
but since `Debug_Mode` is gone you need the qualified form or an explicit use.
Check whether the file uses `use SData.Config;` — if so, `Debug_Level := 3`
is sufficient; if not, use `SData.Config.Debug_Level := 3`.)

- [ ] **Step 7: Build**

```bash
alr build
```
Expected: success. All existing call sites in subunits still compile because
`Debug_Trace` still has its default `Level := 2`.

- [ ] **Step 8: Run tests**

```bash
make check
```
Expected: `All 131 tests passed.` Existing `--debug` behaviour is unchanged
(level 3 = everything fires).

- [ ] **Step 9: Commit**

```bash
git add src/sdata-config.ads src/sdata-interpreter.adb \
        src/sdata-interpreter-process_one_record.adb src/sdata_main.adb
git commit -m "refactor: replace Debug_Mode boolean with Debug_Level integer (0-3)"
```

---

## Task 2: Add `--debug=N` CLI parsing

**Files:**
- Modify: `src/sdata_main.adb`

- [ ] **Step 1: Add the `--debug=N` arm**

In `src/sdata_main.adb`, after the `elsif Arg = "--debug" then` block (which now sets `Debug_Level := 3`), add a new `elsif` immediately after:

```ada
         elsif Arg'Length > 8
            and then Arg (Arg'First .. Arg'First + 7) = "--debug="
         then
            declare
               Level_Str : constant String :=
                  Arg (Arg'First + 8 .. Arg'Last);
               N         : Natural;
            begin
               N := Natural'Value (Level_Str);
               if N > 3 then
                  Put_Line_Error ("Warning: --debug level" & N'Image
                                  & " exceeds maximum (3); using 3");
                  SData.Config.Debug_Level := 3;
               else
                  SData.Config.Debug_Level := N;
               end if;
            exception
               when Constraint_Error =>
                  Put_Line_Error ("Error: invalid --debug level: "
                                  & Level_Str);
                  Set_Exit_Status (Failure);
                  return;
            end;
```

- [ ] **Step 2: Update the help line**

In `src/sdata_main.adb`, replace line 87:
```ada
      Put_Line ("  --debug                  Trace each statement and record number to stderr");
```
with:
```ada
      Put_Line ("  --debug[=N]              Trace execution to stderr");
      Put_Line ("                           1=I/O only  2=+record/flow  3=+assignments (default 3)");
```

- [ ] **Step 3: Build and verify**

```bash
alr build
./bin/sdata --help 2>&1 | grep -A1 debug
```
Expected output includes:
```
  --debug[=N]              Trace execution to stderr
                           1=I/O only  2=+record/flow  3=+assignments (default 3)
```

- [ ] **Step 4: Quick smoke test**

```bash
printf 'USE tests/data/sample.csv\nLET X = 1\nRUN\n' > /tmp/_smoke.cmd
./bin/sdata -q --debug=1 /tmp/_smoke.cmd 2>&1 | grep '^\[debug\]'
```
Expected: two lines only — `[debug] USE: opened ...` and `[debug] RUN complete: ...`

```bash
./bin/sdata -q --debug=2 /tmp/_smoke.cmd 2>&1 | grep '^\[debug\]'
```
Expected: USE line + one `[debug] -- record N` per row + RUN complete line. No `LET`.

- [ ] **Step 5: Run full test suite**

```bash
make check
```
Expected: `All 131 tests passed.`

- [ ] **Step 6: Commit**

```bash
git add src/sdata_main.adb
git commit -m "feat: add --debug=N CLI flag for configurable trace verbosity"
```

---

## Task 3: Tag all subunit call sites; remove temporary default

After this task the compiler will catch any future missed `Debug_Trace` call site
because `Level` has no default.

**Files:**
- Modify: `src/sdata-interpreter-execute_assignment.adb`
- Modify: `src/sdata-interpreter-execute_control_flow.adb`
- Modify: `src/sdata-interpreter-execute_declarative.adb`
- Modify: `src/sdata-interpreter-execute_io.adb`
- Modify: `src/sdata-interpreter.adb` (remove default)

- [ ] **Step 1: Tag execute_assignment.adb — all four calls to Level 3**

In `src/sdata-interpreter-execute_assignment.adb`:

Line ~43 — slice assignment:
```ada
               Debug_Trace (Prefix & Var_Name & "("
                            & Ada.Strings.Fixed.Trim (Integer'Image (Lo), Ada.Strings.Both)
                            & ":"
                            & Ada.Strings.Fixed.Trim (Integer'Image (Hi), Ada.Strings.Both)
                            & ") = " & Debug_Value (Result));
```
→ add `, 3` before the closing `)`:
```ada
               Debug_Trace (Prefix & Var_Name & "("
                            & Ada.Strings.Fixed.Trim (Integer'Image (Lo), Ada.Strings.Both)
                            & ":"
                            & Ada.Strings.Fixed.Trim (Integer'Image (Hi), Ada.Strings.Both)
                            & ") = " & Debug_Value (Result), 3);
```

Line ~65 — list assignment:
```ada
               Debug_Trace (Prefix & Var_Name & "(...) = " & Debug_Value (Result));
```
→
```ada
               Debug_Trace (Prefix & Var_Name & "(...) = " & Debug_Value (Result), 3);
```

Line ~82–84 — single-index assignment:
```ada
            Debug_Trace (Prefix & Var_Name & "("
                         & Ada.Strings.Fixed.Trim (Integer'Image (Idx), Ada.Strings.Both)
                         & ") = " & Debug_Value (Result));
```
→
```ada
            Debug_Trace (Prefix & Var_Name & "("
                         & Ada.Strings.Fixed.Trim (Integer'Image (Idx), Ada.Strings.Both)
                         & ") = " & Debug_Value (Result), 3);
```

Lines ~171–172 — scalar LET/SET:
```ada
      Debug_Trace ((if Stmt.Kind = Stmt_LET then "LET " else "SET ")
                   & Var_Name_Str & " = " & Debug_Value (Result));
```
→
```ada
      Debug_Trace ((if Stmt.Kind = Stmt_LET then "LET " else "SET ")
                   & Var_Name_Str & " = " & Debug_Value (Result), 3);
```

- [ ] **Step 2: Tag execute_control_flow.adb — all five calls to Level 2**

In `src/sdata-interpreter-execute_control_flow.adb`:

```ada
               Debug_Trace ("IF → TRUE");
```
→ `Debug_Trace ("IF → TRUE", 2);`

```ada
                  Debug_Trace ("IF → FALSE");
                  Debug_Trace ("ELSE → taken");
```
→
```ada
                  Debug_Trace ("IF → FALSE", 2);
                  Debug_Trace ("ELSE → taken", 2);
```

```ada
                  Debug_Trace ("IF → FALSE (skipping)");
```
→ `Debug_Trace ("IF → FALSE (skipping)", 2);`

```ada
                     Debug_Trace ("FOR " & For_Var_Name & " = " & Debug_Value (Loop_Val));
```
→ `Debug_Trace ("FOR " & For_Var_Name & " = " & Debug_Value (Loop_Val), 2);`

- [ ] **Step 3: Tag execute_declarative.adb USE trace — Level 1**

In `src/sdata-interpreter-execute_declarative.adb`, find the `Debug_Trace ("USE: opened "` call (around line 58). It spans multiple lines and ends with `)`. Add `, 1` before the final `)`:

```ada
         Debug_Trace ("USE: opened "
                      & Stmt.File_Path (1 .. Stmt.File_Len)
                      & " ("
                      & Ada.Strings.Fixed.Trim (Natural'Image (SData.Table.Row_Count), Ada.Strings.Both)
                      & " records, "
                      & Ada.Strings.Fixed.Trim (Natural'Image (SData.Table.Column_Count), Ada.Strings.Both)
                      & " variables)", 1);
```
(The existing call ends with `& " variables)"` — add `, 1` after it before the semicolon.)

- [ ] **Step 4: Tag execute_io.adb SUBMIT trace — Level 1**

In `src/sdata-interpreter-execute_io.adb`, line ~34:
```ada
                  Debug_Trace ("SUBMIT: entering "
                               & Stmt.File_Path (1 .. Stmt.File_Len));
```
→
```ada
                  Debug_Trace ("SUBMIT: entering "
                               & Stmt.File_Path (1 .. Stmt.File_Len), 1);
```

- [ ] **Step 5: Remove the temporary default from Debug_Trace**

In `src/sdata-interpreter.adb`, change the signature:
```ada
   procedure Debug_Trace (Msg : String; Level : Positive := 2) is
```
to:
```ada
   procedure Debug_Trace (Msg : String; Level : Positive) is
```

- [ ] **Step 6: Build — compiler will catch any missed call site**

```bash
alr build
```
Expected: success with no errors. If any error like `missing parameter "Level"` appears, find the call site and add the appropriate level before continuing.

- [ ] **Step 7: Run tests**

```bash
make check
```
Expected: `All 131 tests passed.`

- [ ] **Step 8: Commit**

```bash
git add src/sdata-interpreter-execute_assignment.adb \
        src/sdata-interpreter-execute_control_flow.adb \
        src/sdata-interpreter-execute_declarative.adb \
        src/sdata-interpreter-execute_io.adb \
        src/sdata-interpreter.adb
git commit -m "refactor: tag all Debug_Trace call sites with explicit verbosity levels"
```

---

## Task 4: Add `OPTIONS DEBUG N`

**Files:**
- Modify: `src/sdata-interpreter-execute_declarative.adb`

- [ ] **Step 1: Add `OPTIONS DEBUG` to the display block**

In `src/sdata-interpreter-execute_declarative.adb`, find the block that prints the bare `OPTIONS` display (around line 234). It ends with:
```ada
               Put_Line ("OPTIONS SHELLTIMEOUT " & Ada.Strings.Fixed.Trim (SData.Config.Runtime.Options_Shell_Timeout'Image, Ada.Strings.Both));
```
Add immediately after:
```ada
               Put_Line ("OPTIONS DEBUG "
                         & Ada.Strings.Fixed.Trim
                             (SData.Config.Debug_Level'Image, Ada.Strings.Both));
```

- [ ] **Step 2: Add the `OPTIONS DEBUG` handler arm**

Find the `elsif Key = "SHELLTIMEOUT" then` arm (around line 283). Add a new arm immediately after its body:

```ada
            elsif Key = "DEBUG" then
               SData.Config.Debug_Level := Natural'Value (Val);
```

The existing `when Constraint_Error` handler at the bottom of the OPTIONS block covers invalid values automatically.

- [ ] **Step 3: Build**

```bash
alr build
```
Expected: success.

- [ ] **Step 4: Smoke test OPTIONS DEBUG**

```ada
-- write this to /tmp/_opts_dbg.cmd temporarily:
-- OPTIONS DEBUG 1
-- USE tests/data/sample.csv
-- LET X = 1
-- RUN
```

```bash
printf 'OPTIONS DEBUG 1\nUSE tests/data/sample.csv\nLET X = 1\nRUN\n' \
  > /tmp/_opts_dbg.cmd
./bin/sdata -q /tmp/_opts_dbg.cmd 2>&1 | grep '^\[debug\]'
```
Expected: `[debug] USE: opened ...` and `[debug] RUN complete: ...` — no `-- record`, no `LET`.

```bash
printf 'OPTIONS\n' | ./bin/sdata 2>/dev/null | grep DEBUG
```
Expected: `OPTIONS DEBUG 0` (since no --debug flag was passed).

- [ ] **Step 5: Run tests**

```bash
make check
```
Expected: `All 131 tests passed.`

- [ ] **Step 6: Commit**

```bash
git add src/sdata-interpreter-execute_declarative.adb
git commit -m "feat: add OPTIONS DEBUG N for runtime debug level control"
```

---

## Task 5: Update help text and man page

**Files:**
- Modify: `src/sdata-help.adb`
- Modify: `man/man1/sdata.1`

- [ ] **Step 1: Rewrite `Help_DEBUGGER` in sdata-help.adb**

In `src/sdata-help.adb`, replace the `Help_DEBUGGER` procedure body (from the
`Put_Line ("Debug mode: --debug flag")` line to the final
`Put_Line ("See also: HELP BREAK ...")` line) with:

```ada
      Put_Line ("Debug mode: --debug[=N] flag  (N = 1, 2, or 3; default 3)");
      Put_Line ("Enables trace output to stderr and interactive step mode.");
      New_Line;
      Put_Line ("Verbosity levels:");
      Put_Line ("  1  sparse   I/O transitions only");
      Put_Line ("  2  normal   Level 1 + per-record header + control-flow outcomes");
      Put_Line ("  3  verbose  Level 2 + every LET/SET assignment");
      New_Line;
      Put_Line ("Level 1 trace events:");
      Put_Line ("  [debug] USE: opened file.csv (N records, M variables)");
      Put_Line ("  [debug] SUBMIT: entering script.sdata");
      Put_Line ("  [debug] RUN complete: N records, M variables");
      New_Line;
      Put_Line ("Level 2 adds:");
      Put_Line ("  [debug] -- record N (physical P)  [BY GROUP ...]");
      Put_Line ("  [debug] IF -> TRUE / FALSE");
      Put_Line ("  [debug] ELSE -> taken");
      Put_Line ("  [debug] FOR I = 3");
      Put_Line ("  [debug] SELECT -> KEPT / DROPPED");
      Put_Line ("  [debug] SELECT -> N of M records kept");
      Put_Line ("  [debug] DELETE: record marked");
      New_Line;
      Put_Line ("Level 3 adds:");
      Put_Line ("  [debug] LET X = 5.00000         each scalar or array assignment");
      Put_Line ("  [debug] SET X = 5.00000");
      New_Line;
      Put_Line ("Runtime control:  OPTIONS DEBUG N  (0 disables tracing)");
      New_Line;
      Put_Line ("Step mode (--debug[=N] + interactive stdin):");
      Put_Line ("  After each record header, execution pauses at the inspection prompt.");
      Put_Line ("  CONTINUE/C processes the current record and advances to the next.");
      Put_Line ("  STEP/S is equivalent to CONTINUE in step mode.");
      Put_Line ("  RUN at the prompt disables step mode and runs to completion.");
      New_Line;
      Put_Line ("The inspection prompt ([debug:record N]>) accepts the same commands as");
      Put_Line ("BREAK: PRINT, RECORD, CONTINUE, STEP, RUN.  Record navigation at the");
      Put_Line ("prompt does not affect which record is processed when execution resumes.");
      New_Line;
      Put_Line ("See also: HELP BREAK for the BREAK / BREAK WHEN deferred statement.");
```

- [ ] **Step 2: Update the man page --debug entry**

In `man/man1/sdata.1`, find the `.B \-\-debug` block (around line 108). Replace
the existing entry:

```nroff
.B \-\-debug
Enables debug mode.
Emits trace output to standard error for each statement executed:
...
```

with:

```nroff
.B \-\-debug\fR[\fB=\fIN\fR]
Enables debug mode.
.I N
selects the verbosity level (default\~3 if omitted):
.RS
.TP
.B 1\ (sparse)
I/O transitions only:
.BR USE ,
.BR SUBMIT ,
and
.B RUN
completion events.
.TP
.B 2\ (normal)
Level\~1 plus a header line per record (annotated with BY\-group transitions),
.BR IF / ELSE
condition outcomes,
.B FOR
loop iterations,
.B SELECT
filter decisions (plus a kept/dropped summary line), and
.B DELETE
marks.
.TP
.B 3\ (verbose)
Level\~2 plus every
.BR LET / SET
assignment (scalar and array).
.RE
.IP
The verbosity level can be changed inside a script with
.BR "OPTIONS DEBUG " N .
In interactive sessions, any non-zero level enables execution pausing before
each record at the inspection prompt
.RB ( [debug:record\ N]> ).
```

- [ ] **Step 3: Build and verify help output**

```bash
alr build
./bin/sdata 2>&1 <<'EOF'
HELP DEBUGGER
QUIT
EOF
```
Expected: the new three-level help text appears on stderr/stdout.

- [ ] **Step 4: Run tests**

```bash
make check
```
Expected: `All 131 tests passed.`

- [ ] **Step 5: Commit**

```bash
git add src/sdata-help.adb man/man1/sdata.1
git commit -m "docs: update --debug help text and man page for three-level verbosity"
```

---

## Task 6: Add integration tests

Four tests verify each level and the OPTIONS path. Each test uses SYSTEM to
run a sub-sdata process with specific flags, redirects its stderr to a temp
file, then greps for expected/absent strings.

**Files:**
- Create: `tests/debug_level1.cmd` + `tests/debug_level1.expected`
- Create: `tests/debug_level2.cmd` + `tests/debug_level2.expected`
- Create: `tests/debug_level3.cmd` + `tests/debug_level3.expected`
- Create: `tests/debug_options.cmd`  + `tests/debug_options.expected`

The inner script used by all four tests:

```
USE tests/data/sample.csv
LET X = VAL1 + 1
RUN
```

This exercises USE (level 1), per-record header (level 2), and LET (level 3).
`sample.csv` has 6 rows and 4 columns; `VAL1` is numeric so the LET is valid.

- [ ] **Step 1: Create `tests/debug_level1.cmd`**

```sdata
-- Verify --debug=1: I/O traces present; record headers and assignments absent
SYSTEM "printf 'USE tests/data/sample.csv\nLET X = VAL1 + 1\nRUN\n' > /tmp/_sdata_dbg.cmd"
SYSTEM "./bin/sdata -q --debug=1 /tmp/_sdata_dbg.cmd 2>/tmp/_sdata_dbg.txt"
SYSTEM "grep -qF 'USE: opened' /tmp/_sdata_dbg.txt"
SYSTEM "grep -qF 'RUN complete' /tmp/_sdata_dbg.txt"
SYSTEM "test $(grep -cF '-- record' /tmp/_sdata_dbg.txt) -eq 0"
SYSTEM "test $(grep -cF 'LET X' /tmp/_sdata_dbg.txt) -eq 0"
PRINT "debug_level1: OK"
```

- [ ] **Step 2: Create `tests/debug_level1.expected`**

```
debug_level1: OK
```
(single line, terminated with a newline)

- [ ] **Step 3: Create `tests/debug_level2.cmd`**

```sdata
-- Verify --debug=2: I/O + record headers present; assignments absent
SYSTEM "printf 'USE tests/data/sample.csv\nLET X = VAL1 + 1\nRUN\n' > /tmp/_sdata_dbg.cmd"
SYSTEM "./bin/sdata -q --debug=2 /tmp/_sdata_dbg.cmd 2>/tmp/_sdata_dbg.txt"
SYSTEM "grep -qF 'USE: opened' /tmp/_sdata_dbg.txt"
SYSTEM "grep -qF '-- record 1' /tmp/_sdata_dbg.txt"
SYSTEM "grep -qF 'RUN complete' /tmp/_sdata_dbg.txt"
SYSTEM "test $(grep -cF 'LET X' /tmp/_sdata_dbg.txt) -eq 0"
PRINT "debug_level2: OK"
```

- [ ] **Step 4: Create `tests/debug_level2.expected`**

```
debug_level2: OK
```

- [ ] **Step 5: Create `tests/debug_level3.cmd`**

```sdata
-- Verify --debug=3: I/O + record headers + assignments all present
SYSTEM "printf 'USE tests/data/sample.csv\nLET X = VAL1 + 1\nRUN\n' > /tmp/_sdata_dbg.cmd"
SYSTEM "./bin/sdata -q --debug=3 /tmp/_sdata_dbg.cmd 2>/tmp/_sdata_dbg.txt"
SYSTEM "grep -qF 'USE: opened' /tmp/_sdata_dbg.txt"
SYSTEM "grep -qF '-- record 1' /tmp/_sdata_dbg.txt"
SYSTEM "grep -qF 'RUN complete' /tmp/_sdata_dbg.txt"
SYSTEM "test $(grep -cF 'LET X =' /tmp/_sdata_dbg.txt) -gt 0"
PRINT "debug_level3: OK"
```

- [ ] **Step 6: Create `tests/debug_level3.expected`**

```
debug_level3: OK
```

- [ ] **Step 7: Create `tests/debug_options.cmd`**

```sdata
-- Verify OPTIONS DEBUG N sets level at runtime (level 1: records absent)
SYSTEM "printf 'OPTIONS DEBUG 1\nUSE tests/data/sample.csv\nLET X = VAL1 + 1\nRUN\n' > /tmp/_sdata_dbg.cmd"
SYSTEM "./bin/sdata -q /tmp/_sdata_dbg.cmd 2>/tmp/_sdata_dbg.txt"
SYSTEM "grep -qF 'USE: opened' /tmp/_sdata_dbg.txt"
SYSTEM "grep -qF 'RUN complete' /tmp/_sdata_dbg.txt"
SYSTEM "test $(grep -cF '-- record' /tmp/_sdata_dbg.txt) -eq 0"
SYSTEM "test $(grep -cF 'LET X' /tmp/_sdata_dbg.txt) -eq 0"
PRINT "debug_options: OK"
```

- [ ] **Step 8: Create `tests/debug_options.expected`**

```
debug_options: OK
```

- [ ] **Step 9: Run full test suite**

```bash
make check
```
Expected: `All 135 tests passed.` (131 existing + 4 new)

If any new test fails, run it in isolation to see the actual vs expected output:

```bash
./bin/sdata tests/debug_level1.cmd > /tmp/out.txt 2>&1
diff tests/debug_level1.expected /tmp/out.txt
```

- [ ] **Step 10: Commit**

```bash
git add tests/debug_level1.cmd tests/debug_level1.expected \
        tests/debug_level2.cmd tests/debug_level2.expected \
        tests/debug_level3.cmd tests/debug_level3.expected \
        tests/debug_options.cmd tests/debug_options.expected
git commit -m "test: add integration tests for --debug=N levels and OPTIONS DEBUG"
```

---

## Standards Review Update

After all tasks pass, update `doc/SOFTWARE_STANDARDS_REVIEW.md`:

- §7.1 Observability: `Debug tracing | Yes (--debug) | 6/10` → `8/10 — three configurable levels`
- §7 section header: `65/100` → `66/100` (one sub-score up 2 pts = +1 weighted)
- Add annotation and update total (624 → 625/800)

```bash
git add doc/SOFTWARE_STANDARDS_REVIEW.md
git commit -m "doc: update standards review for configurable debug levels"
```
