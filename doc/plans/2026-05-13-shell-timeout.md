# ADR-037 SYSTEM/SHELL Timeout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a configurable SYSTEM/SHELL timeout defaulting to 300 s in batch mode and unlimited (0) in interactive mode, as specified by ADR-037.

**Architecture:** `Shell_Timeout_Default` in `SData.Config` (startup-constant, set by CLI after arg parsing) holds the reset value; `Options_Shell_Timeout` in `SData.Config.Runtime` is the live per-run value (reset to `Shell_Timeout_Default` by NEW). `Shell_Execute` in `sdata-system.adb` uses the POSIX `timeout(1)` utility as a prefix when the value is non-zero and the platform is non-Windows; exit code 124 from `timeout` raises `Script_Error`. The `OPTIONS SHELLTIMEOUT N` command writes to `Options_Shell_Timeout` at runtime.

**Tech Stack:** Ada 2012, GNAT.OS_Lib (integer-return Spawn), POSIX `timeout(1)` from GNU coreutils.

---

### Task 1: Add Config State

**Files:**
- Modify: `src/sdata-config.ads`
- Modify: `src/sdata-config-runtime.ads`
- Modify: `src/sdata-config-runtime.adb`

- [ ] **Step 1: Add `Shell_Timeout_Default` to `SData.Config`**

  In `src/sdata-config.ads`, add after the `Debug_Mode` line (currently line 43):

  ```ada
     Shell_Timeout_Default : Natural := 0;
  ```

  The declaration fits between `Debug_Mode` and the blank line before `Version_Major`. The initial value 0 is a placeholder; `sdata_main.adb` sets it to 300 (batch) or 0 (interactive) after parsing CLI arguments.

- [ ] **Step 2: Add `Options_Shell_Timeout` to `SData.Config.Runtime`**

  In `src/sdata-config-runtime.ads`, add after the `IEEE_Divide` line (currently line 37):

  ```ada
     Options_Shell_Timeout : Natural                          := 0;
  ```

- [ ] **Step 3: Reset `Options_Shell_Timeout` in `Reset`**

  In `src/sdata-config-runtime.adb`, add after the `IEEE_Divide` reset line (currently line 29):

  ```ada
        Options_Shell_Timeout := SData.Config.Shell_Timeout_Default;
  ```

- [ ] **Step 4: Build to verify no compilation errors**

  ```bash
  alr build
  ```

  Expected: build succeeds with no warnings.

- [ ] **Step 5: Commit**

  ```bash
  git add src/sdata-config.ads src/sdata-config-runtime.ads src/sdata-config-runtime.adb
  git commit -m "feat: add Shell_Timeout_Default and Options_Shell_Timeout config state (ADR-037)"
  ```

---

### Task 2: CLI `--shell-timeout=N` Flag and Batch Default

**Files:**
- Modify: `src/sdata_main.adb`

- [ ] **Step 1: Add `--shell-timeout=N` parsing**

  In `src/sdata_main.adb`, add the following block after the `--clen=N` elif block (after line 345, before `elsif Arg = "-p" then`):

  ```ada
           elsif Arg'Length > 15 and then Arg (1 .. 15) = "--shell-timeout=" then
              begin
                 SData.Config.Shell_Timeout_Default :=
                    Natural'Value (Arg (16 .. Arg'Last));
              exception
                 when Constraint_Error =>
                    Put_Line_Error ("Error: argument to --shell-timeout must be a non-negative integer");
                    Set_Exit_Status (Failure);
                    return;
              end;
  ```

  The `--shell-timeout=N` form (with `=`) mirrors `--clen=N`. A space-separated `--shell-timeout N` form is not needed for parity with existing flags; all numeric flags use either short form (space) or long form (equals).

- [ ] **Step 2: Set batch/interactive default after the arg-parsing loop**

  In `src/sdata_main.adb`, add the following block after the `end loop;` that closes the arg-parsing loop (after line 400), before the `--  Validate -p / --noshell interaction.` comment:

  ```ada
     --  Set the shell-timeout default based on batch vs interactive mode,
     --  unless the user already set it explicitly via --shell-timeout=N.
     --  Batch mode: 300 s.  Interactive mode: 0 (unlimited).
     if SData.Config.Shell_Timeout_Default = 0 and then Filename_Len > 0 then
        SData.Config.Shell_Timeout_Default := 300;
     end if;
     SData.Config.Runtime.Options_Shell_Timeout :=
        SData.Config.Shell_Timeout_Default;
  ```

  Note: this also handles the case where `--shell-timeout=0` was passed explicitly (the condition `Shell_Timeout_Default = 0` would be true, but `Filename_Len > 0` would also be true, so it would be overridden to 300 — wrong). To handle explicit `--shell-timeout=0` correctly, track whether the flag was set:

  Replace the parsing block from Step 1 with:

  ```ada
           elsif Arg'Length > 15 and then Arg (1 .. 15) = "--shell-timeout=" then
              begin
                 SData.Config.Shell_Timeout_Default :=
                    Natural'Value (Arg (16 .. Arg'Last));
                 Shell_Timeout_Explicit := True;
              exception
                 when Constraint_Error =>
                    Put_Line_Error ("Error: argument to --shell-timeout must be a non-negative integer");
                    Set_Exit_Status (Failure);
                    return;
              end;
  ```

  And add the local variable declaration at the top of the procedure's local variable block (alongside `Filename_Len`, `Idx`, etc.):

  ```ada
     Shell_Timeout_Explicit : Boolean := False;
  ```

  Then the post-loop block becomes:

  ```ada
     if not Shell_Timeout_Explicit and then Filename_Len > 0 then
        SData.Config.Shell_Timeout_Default := 300;
     end if;
     SData.Config.Runtime.Options_Shell_Timeout :=
        SData.Config.Shell_Timeout_Default;
  ```

- [ ] **Step 3: Build to verify**

  ```bash
  alr build
  ```

  Expected: clean build.

- [ ] **Step 4: Smoke-test CLI flag**

  Create `tests/shell_timeout_cli.cmd` (just prints so we can see it ran):

  ```
  -- Verify --shell-timeout is accepted and sets OPTIONS SHELLTIMEOUT
  OPTIONS
  QUIT
  ```

  Add `tests/shell_timeout_cli.flags`:

  ```
  --shell-timeout=60
  ```

  We cannot add expected output for this test yet (OPTIONS SHELLTIMEOUT not in the handler yet) — skip for now; add the `.out` file in Task 4.

- [ ] **Step 5: Commit**

  ```bash
  git add src/sdata_main.adb
  git commit -m "feat: parse --shell-timeout=N CLI flag; default 300 s in batch mode (ADR-037)"
  ```

---

### Task 3: Implement Timeout in `Shell_Execute`

**Files:**
- Modify: `src/sdata-system.adb`

- [ ] **Step 1: Write the failing integration test**

  Create `tests/shell_timeout_kill.cmd`:

  ```
  -- SYSTEM command that exceeds its timeout must raise Script_Error
  OPTIONS SHELLTIMEOUT 1
  SYSTEM "sleep 3"
  QUIT
  ```

  Create `tests/expected/shell_timeout_kill.out`:

  ```
  Error: SYSTEM command timed out after 1 seconds
  ```

  Create `tests/shell_timeout_kill.exitcode`:

  ```
  1
  ```

- [ ] **Step 2: Run test to verify it fails (no timeout applied yet)**

  ```bash
  make check 2>&1 | grep shell_timeout_kill
  ```

  Expected: `FAILED` (sleep 3 completes, sdata exits 0, output mismatch or exit-code mismatch).

- [ ] **Step 3: Add `with` clauses to `sdata-system.adb`**

  At the top of `src/sdata-system.adb`, add two new `with` lines after the existing `with Ada.Environment_Variables;` line:

  ```ada
  with Ada.Text_IO;
  with SData.Config.Runtime;
  ```

- [ ] **Step 4: Add package-body `Timeout_Warned` flag**

  Inside `package body SData.System is`, before `Is_Windows`, add:

  ```ada
     Timeout_Warned : Boolean := False;
  ```

- [ ] **Step 5: Replace `Shell_Execute` with timeout-aware implementation**

  Replace the entire `Shell_Execute` procedure body (lines 77–104 in the current file) with:

  ```ada
     procedure Shell_Execute (Command : String := ""; Success : out Boolean) is
     begin
        if Command = "" then
           declare
              Path : GNAT.OS_Lib.String_Access;
           begin
              Resolve_Interactive_Shell (Path);
              GNAT.OS_Lib.Spawn (Path.all, (1 .. 0 => null), Success);
              Free (Path);
           end;
        else
           declare
              Timeout_Val : constant Natural :=
                 SData.Config.Runtime.Options_Shell_Timeout;
              Path      : GNAT.OS_Lib.String_Access;
              Posix     : Boolean;
              Exit_Code : Integer;
           begin
              Resolve_Shell (Path, Posix);
              declare
                 Shell_Arg : constant String :=
                    (if Posix then "-c" else "/c");
              begin
                 if Timeout_Val > 0 and then not Is_Windows then
                    declare
                       TO_Path : GNAT.OS_Lib.String_Access :=
                          GNAT.OS_Lib.Locate_Exec_On_Path ("timeout");
                    begin
                       if TO_Path /= null then
                          declare
                             T_Img : constant String := Timeout_Val'Image;
                             T_Str : constant String :=
                                T_Img (T_Img'First + 1 .. T_Img'Last);
                             Args : GNAT.OS_Lib.Argument_List :=
                                (new String'(T_Str),
                                 new String'(Path.all),
                                 new String'(Shell_Arg),
                                 new String'(Command));
                          begin
                             Exit_Code :=
                                GNAT.OS_Lib.Spawn (TO_Path.all, Args);
                             for I in Args'Range loop
                                Free (Args (I));
                             end loop;
                          end;
                          Free (TO_Path);
                       else
                          if not Timeout_Warned then
                             Ada.Text_IO.Put_Line
                                (Ada.Text_IO.Standard_Error,
                                 "Warning: 'timeout' not found on PATH; "
                                 & "SHELLTIMEOUT has no effect.");
                             Timeout_Warned := True;
                          end if;
                          declare
                             Args : GNAT.OS_Lib.Argument_List :=
                                (new String'(Shell_Arg),
                                 new String'(Command));
                          begin
                             Exit_Code :=
                                GNAT.OS_Lib.Spawn (Path.all, Args);
                             for I in Args'Range loop
                                Free (Args (I));
                             end loop;
                          end;
                       end if;
                    end;
                 else
                    declare
                       Args : GNAT.OS_Lib.Argument_List :=
                          (new String'(Shell_Arg), new String'(Command));
                    begin
                       Exit_Code := GNAT.OS_Lib.Spawn (Path.all, Args);
                       for I in Args'Range loop Free (Args (I)); end loop;
                    end;
                 end if;
              end;
              Free (Path);
              if Exit_Code = 124 then
                 declare
                    T_Img : constant String := Timeout_Val'Image;
                    T_Str : constant String :=
                       T_Img (T_Img'First + 1 .. T_Img'Last);
                 begin
                    raise Script_Error with
                       "SYSTEM command timed out after " & T_Str & " seconds";
                 end;
              end if;
              Success := (Exit_Code = 0);
           end;
        end if;
     end Shell_Execute;
  ```

  Note: `Script_Error` is visible without a package qualifier because `SData.System` is a child of `SData`; the parent's public declarations are directly visible in child package bodies.

- [ ] **Step 6: Build to verify**

  ```bash
  alr build
  ```

  Expected: clean build, no warnings.

- [ ] **Step 7: Run the new integration test**

  ```bash
  make check 2>&1 | grep shell_timeout_kill
  ```

  Expected: `PASSED`.

- [ ] **Step 8: Commit**

  ```bash
  git add src/sdata-system.adb \
          tests/shell_timeout_kill.cmd \
          tests/expected/shell_timeout_kill.out \
          tests/shell_timeout_kill.exitcode
  git commit -m "feat: implement SYSTEM/SHELL timeout via timeout(1); raise Script_Error on exit 124 (ADR-037)"
  ```

---

### Task 4: `OPTIONS SHELLTIMEOUT` in Interpreter

**Files:**
- Modify: `src/sdata-interpreter.adb`
- Modify: `tests/expected/options_display.out`
- Create: `tests/shell_timeout_options.cmd`, `tests/expected/shell_timeout_options.out`
- Complete: `tests/shell_timeout_cli.flags` / add `tests/expected/shell_timeout_cli.out`

- [ ] **Step 1: Write failing integration test for OPTIONS SHELLTIMEOUT**

  Create `tests/shell_timeout_options.cmd`:

  ```
  -- OPTIONS SHELLTIMEOUT sets the shell timeout
  OPTIONS SHELLTIMEOUT 60
  OPTIONS
  QUIT
  ```

  Create `tests/expected/shell_timeout_options.out`:

  ```
  OPTIONS MAXINTAB 50000000
  OPTIONS MAXTEMPMEM 0
  OPTIONS CSVDLM ","
  OPTIONS HEADER YES
  OPTIONS SAVEOVERWRT YES
  OPTIONS TXTFMT AUTO
  OPTIONS CHARSET AUTO
  OPTIONS IEEE_DIVIDE NO
  OPTIONS SHELLTIMEOUT 60
  ```

- [ ] **Step 2: Run to verify it fails**

  ```bash
  make check 2>&1 | grep shell_timeout_options
  ```

  Expected: `FAILED` (unknown OPTIONS key warning appears instead of the SHELLTIMEOUT line).

- [ ] **Step 3: Add `SHELLTIMEOUT` to the no-arg OPTIONS display**

  In `src/sdata-interpreter.adb`, add after the `IEEE_DIVIDE` display line (currently line 1559):

  ```ada
                    Put_Line ("OPTIONS SHELLTIMEOUT " & Ada.Strings.Fixed.Trim (SData.Config.Runtime.Options_Shell_Timeout'Image, Ada.Strings.Both));
  ```

- [ ] **Step 4: Add `SHELLTIMEOUT` to the OPTIONS key handler**

  In `src/sdata-interpreter.adb`, add after the `IEEE_DIVIDE` elsif block (currently lines 1595–1596, before `else Put_Line_Error ...`):

  ```ada
                 elsif Key = "SHELLTIMEOUT" then
                    SData.Config.Runtime.Options_Shell_Timeout :=
                       Natural'Value (Val);
  ```

- [ ] **Step 5: Update `tests/expected/options_display.out`**

  The options_display test runs in batch mode (300 s default). Append the new line to `tests/expected/options_display.out`:

  ```
  OPTIONS SHELLTIMEOUT 300
  ```

  The full file should now read:

  ```
  OPTIONS MAXINTAB 50000000
  OPTIONS MAXTEMPMEM 0
  OPTIONS CSVDLM ","
  OPTIONS HEADER YES
  OPTIONS SAVEOVERWRT YES
  OPTIONS TXTFMT AUTO
  OPTIONS CHARSET AUTO
  OPTIONS IEEE_DIVIDE NO
  OPTIONS SHELLTIMEOUT 300
  ```

- [ ] **Step 6: Add expected output for the CLI-flag smoke test**

  Create `tests/expected/shell_timeout_cli.out`:

  ```
  OPTIONS MAXINTAB 50000000
  OPTIONS MAXTEMPMEM 0
  OPTIONS CSVDLM ","
  OPTIONS HEADER YES
  OPTIONS SAVEOVERWRT YES
  OPTIONS TXTFMT AUTO
  OPTIONS CHARSET AUTO
  OPTIONS IEEE_DIVIDE NO
  OPTIONS SHELLTIMEOUT 60
  ```

  (The `--shell-timeout=60` flag overrides the batch default of 300.)

- [ ] **Step 7: Build and run all tests**

  ```bash
  alr build && make check
  ```

  Expected: all tests pass, including `shell_timeout_options`, `shell_timeout_cli`, and the unchanged `options_display`.

- [ ] **Step 8: Commit**

  ```bash
  git add src/sdata-interpreter.adb \
          tests/shell_timeout_options.cmd \
          tests/expected/shell_timeout_options.out \
          tests/shell_timeout_cli.cmd \
          tests/shell_timeout_cli.flags \
          tests/expected/shell_timeout_cli.out \
          tests/expected/options_display.out
  git commit -m "feat: add OPTIONS SHELLTIMEOUT handler and display (ADR-037)"
  ```

---

### Task 5: Help Text Updates

**Files:**
- Modify: `src/sdata-help.adb`

- [ ] **Step 1: Update `Help_SYSTEM`**

  Replace the current `Help_SYSTEM` body (lines 115–121 in `src/sdata-help.adb`) with:

  ```ada
     procedure Help_SYSTEM is
     begin
        Put_Line ("Command: SYSTEM ""command""");
        Put_Line ("Executes an external shell command. Disabled by --noshell.");
        Put_Line ("Uses /bin/sh on POSIX systems to avoid profile script side-effects.");
        Put_Line ("A timeout is applied when OPTIONS SHELLTIMEOUT > 0 (requires timeout(1) on PATH).");
        Put_Line ("If the command exceeds the timeout, Script_Error is raised.");
        Put_Line ("Default timeout: 300 s in batch mode, 0 (unlimited) in interactive mode.");
        Put_Line ("Override at startup with --shell-timeout=N; override at runtime with OPTIONS SHELLTIMEOUT N.");
        Put_Line ("Execution: Immediate -- the shell command is launched at once.");
     end Help_SYSTEM;
  ```

- [ ] **Step 2: Update `Help_OPTIONS`**

  In `src/sdata-help.adb`, add the following line after the `IEEE_DIVIDE` line in `Help_OPTIONS` (after the line ending `"Cleared by NEW."`):

  ```ada
        Put_Line ("  OPTIONS SHELLTIMEOUT n     : SYSTEM/SHELL timeout in seconds (0 = unlimited). Cleared by NEW.");
  ```

  Also add a new CLI flag entry after the `--clen <n>` line:

  ```ada
        Put_Line ("  --shell-timeout=N            : Set SYSTEM/SHELL timeout in seconds (0 = unlimited)");
  ```

- [ ] **Step 3: Build and verify help output**

  ```bash
  alr build
  echo 'HELP SYSTEM
  QUIT' | ./bin/sdata
  ```

  Expected: the new timeout lines appear.

  ```bash
  echo 'HELP OPTIONS
  QUIT' | ./bin/sdata
  ```

  Expected: `OPTIONS SHELLTIMEOUT n` line and `--shell-timeout=N` line appear.

- [ ] **Step 4: Run full test suite**

  ```bash
  make check
  ```

  Expected: all tests pass.

- [ ] **Step 5: Commit**

  ```bash
  git add src/sdata-help.adb
  git commit -m "docs: update HELP SYSTEM and HELP OPTIONS for SHELLTIMEOUT (ADR-037)"
  ```

---

### Task 6: Man Page Updates

**Files:**
- Modify: `man/man1/sdata.1`

- [ ] **Step 1: Add `--shell-timeout` CLI option**

  In `man/man1/sdata.1`, add the following entry after the `--noshell` entry (after the `Useful in restricted or multi\-user environments.` line, before `\-k`):

  ```nroff
  .TP
  .BI \-\-shell\-timeout " seconds"
  Set the timeout for
  .B SYSTEM
  commands and the
  .B SHELL()
  function.
  A value of 0 disables the timeout (unlimited).
  The default is 300 seconds in batch mode and 0 in interactive mode.
  Requires the
  .BR timeout (1)
  utility on
  .BR PATH ;
  if
  .BR timeout (1)
  is absent a one-time warning is printed and the limit is not enforced.
  The timeout can also be adjusted at runtime with
  .BR "OPTIONS SHELLTIMEOUT" .
  ```

- [ ] **Step 2: Extend the `SYSTEM` command entry**

  Replace the current SYSTEM man page entry (lines 262–265):

  ```nroff
  .TP
  .B SYSTEM \fIcmd\fR
  Run an external shell command.
  Disabled by
  .BR \-\-noshell .
  ```

  with:

  ```nroff
  .TP
  .B SYSTEM \fIcmd\fR
  Run an external shell command.
  Disabled by
  .BR \-\-noshell .
  A timeout is applied when
  .B OPTIONS SHELLTIMEOUT
  is greater than 0; the command is killed and a
  .B Script_Error
  is raised if it exceeds the limit.
  See
  .B \-\-shell\-timeout
  and
  .B OPTIONS SHELLTIMEOUT
  for details.
  ```

- [ ] **Step 3: Add `OPTIONS` command entry in the Immediate commands section**

  In the Immediate commands subsection (`.SS Immediate commands`), add after the SUBMIT entry (after line 260) and before the SYSTEM entry:

  ```nroff
  .TP
  .B OPTIONS [\fIkey value\fR]
  Set or display runtime options.
  With no arguments, lists all current option values.
  Key\-value pairs include
  .B SHELLTIMEOUT \fIn\fR
  (SYSTEM/SHELL timeout in seconds; 0 = unlimited; reset to startup default by
  .BR NEW ),
  .B IEEE_DIVIDE YES|NO
  (float division by zero returns +/\-Inf),
  .B CSVDLM \fIdelim\fR
  (CSV field delimiter),
  .B HEADER YES|NO
  (CSV header row),
  .B SAVEOVERWRT YES|NO
  (overwrite files on SAVE),
  .B TXTFMT AUTO|LF|CRLF|CR
  (output line ending),
  .B CHARSET \fIname\fR
  (character set label),
  .B MAXINTAB \fIn\fR
  (in-memory table cell limit),
  and
  .B MAXTEMPMEM \fIn\fR
  (temporary variable limit).
  ```

- [ ] **Step 4: Verify man page renders**

  ```bash
  man man/man1/sdata.1
  ```

  Expected: no groff errors; new `--shell-timeout` entry visible under OPTIONS; SYSTEM entry shows timeout note; new OPTIONS command entry visible.

- [ ] **Step 5: Run full test suite**

  ```bash
  make check
  ```

  Expected: all tests pass.

- [ ] **Step 6: Commit**

  ```bash
  git add man/man1/sdata.1
  git commit -m "docs: document --shell-timeout, OPTIONS SHELLTIMEOUT, and OPTIONS command in man page (ADR-037)"
  ```

---

## Self-Review

**Spec coverage check:**

| ADR-037 requirement | Covered by |
|---|---|
| `Shell_Timeout` in `SData.Config.Runtime` | Task 1 (`Options_Shell_Timeout`) |
| `--shell-timeout=N` CLI flag | Task 2 |
| Default 300 s batch, 0 interactive | Task 2 post-loop block |
| `OPTIONS SHELLTIMEOUT N` runtime override | Task 4 |
| No-arg OPTIONS display | Task 4 Step 3 |
| Implementation via `timeout(1)` | Task 3 |
| Exit code 124 → `Script_Error` | Task 3 Step 5 |
| Graceful degradation if `timeout` absent | Task 3 Step 5 (warn-once) |
| `SHELL()` evaluator function inherits | Automatic — `Handle_Shell` calls `Shell_Execute` |
| Man page `--shell-timeout` | Task 6 Step 1 |
| Man page SYSTEM timeout note | Task 6 Step 2 |
| HELP SYSTEM updated | Task 5 Step 1 |
| HELP OPTIONS updated | Task 5 Step 2 |

**Placeholder scan:** None found.

**Type consistency:** `Options_Shell_Timeout` is `Natural` throughout. `Shell_Timeout_Default` is `Natural`. `Natural'Value` used for parsing. `Timeout_Val'Image` used for display (leading space stripped by `T_Img'First + 1`). Consistent.

**Existing test regressions:** `options_display.out` updated in Task 4 Step 5 to include `OPTIONS SHELLTIMEOUT 300`.
