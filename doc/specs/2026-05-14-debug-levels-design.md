# Design: Configurable `--debug` Log Levels

**Date:** 2026-05-14
**Status:** Approved
**ADR:** none — no architectural decision required; this is a flag enhancement

---

## 1. Problem

`--debug` is a single on/off boolean. Every trace category fires together:
per-record headers, IF/ELSE/FOR outcomes, SELECT filter results, and every
LET/SET assignment. On a 10 000-record dataset with frequent assignments, the
output is too voluminous to be useful when the developer only wants to see
I/O transitions or control-flow outcomes.

The standards review rates `--debug` at 6/10 because it has no configurable
verbosity.

---

## 2. Goal

Replace the boolean with a three-level verbosity dial. `--debug` with no
argument preserves existing behaviour exactly. `--debug=N` activates only the
traces at level N and below.

---

## 3. Level Definitions

| Level | Name | What fires |
|---|---|---|
| 0 | off | nothing (default) |
| 1 | sparse | I/O transitions: USE open, SUBMIT enter/exit, RUN complete |
| 2 | normal | Level 1 + per-record header + IF/ELSE/FOR outcomes + SELECT KEPT/DROPPED + DELETE |
| 3 | verbose | Level 2 + every LET/SET assignment (scalar and array) |

`--debug` with no argument sets level 3, identical to the current `--debug`
behaviour.

---

## 4. Architecture

### 4.1 `sdata-config.ads`

Replace:
```ada
Debug_Mode  : Boolean := False;
```
with:
```ada
Debug_Level : Natural := 0;
```

All existing consumers of `Debug_Mode` are internal to `sdata-interpreter.adb`
and its subunits; no package outside the interpreter package reads this flag
directly.

### 4.2 `Debug_Trace` in `sdata-interpreter.adb`

Add a `Level` parameter (default 2 to match existing call sites that omit it,
though every call site will be updated explicitly):

```ada
procedure Debug_Trace (Msg : String; Level : Positive) is
begin
   if SData.Config.Debug_Level >= Level then
      Put_Line_Error ("[debug] " & Msg);
   end if;
end Debug_Trace;
```

No default for `Level` — all call sites must be explicit after the change, so
the compiler catches any missed site.

### 4.3 Call-site level assignments

Every existing `Debug_Trace` call is tagged with a level:

**Level 1 — I/O transitions:**

| File | Message |
|---|---|
| `execute_declarative.adb` | `USE: opened <file> (N records, M variables)` |
| `execute_io.adb` | `SUBMIT: entering <path>` |
| `sdata-interpreter.adb` | `RUN complete: N records, M variables` |

**Level 2 — Record + control flow:**

| File | Message |
|---|---|
| `process_one_record.adb` | `-- record N (physical P)  [BY GROUP ...]` header |
| `execute_control_flow.adb` | `IF → TRUE`, `IF → FALSE`, `ELSE → taken`, `IF → FALSE (skipping)` |
| `execute_control_flow.adb` | `FOR <var> = <val>` (each iteration) |
| `sdata-interpreter.adb` | `SELECT → KEPT`, `SELECT → DROPPED`, `SELECT → N of M records kept` |
| `sdata-interpreter.adb` | `DELETE: record marked` |

**Level 3 — Assignments:**

| File | Message |
|---|---|
| `execute_assignment.adb` | `LET <var> = <val>` (scalar) |
| `execute_assignment.adb` | `SET <var> = <val>` (scalar) |
| `execute_assignment.adb` | `LET/SET <var>(<idx>) = <val>` (single array element) |
| `execute_assignment.adb` | `LET/SET <var>(<range>) = <val>` (slice) |
| `execute_assignment.adb` | `LET/SET <var>(...) = <val>` (list assignment) |

The two direct `Put_Line_Error` calls in `inspect_pdv.adb` (the BREAK
non-interactive notice and the "loaded record N into PDV" navigation message)
are left unchanged — they are interactive debugger session messages, not
general trace output, and only execute when `Inspect_PDV` is already active.

### 4.4 Step mode (BREAK + interactive)

The expression that enables single-step inspection:

```ada
-- before
SData.Config.Debug_Mode and then SData.IO.Is_Interactive

-- after
SData.Config.Debug_Level > 0 and then SData.IO.Is_Interactive
```

BREAK works at any active debug level.

---

## 5. CLI (`sdata_main.adb`)

```
--debug        sets Debug_Level := 3  (unchanged behaviour)
--debug=N      sets Debug_Level := N  (N must be in 0..3)
```

Parsing logic (after current `--debug` arm):

```ada
elsif Arg = "--debug" then
   SData.Config.Debug_Level := 3;
elsif Arg'Length > 8
   and then Arg (Arg'First .. Arg'First + 7) = "--debug="
then
   declare
      N : constant Natural :=
         Natural'Value (Arg (Arg'First + 8 .. Arg'Last));
   begin
      if N > 3 then
         Put_Line_Error ("Warning: --debug level " & N'Image
                         & " exceeds maximum (3); using 3");
         SData.Config.Debug_Level := 3;
      else
         SData.Config.Debug_Level := N;
      end if;
   exception
      when Constraint_Error =>
         Put_Line_Error ("Error: invalid --debug level: "
                         & Arg (Arg'First + 8 .. Arg'Last));
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
   end;
```

Updated help line:
```
--debug[=N]   Trace execution to stderr (1=sparse 2=normal 3=verbose; default 3)
```

---

## 6. OPTIONS command

`OPTIONS DEBUG N` — sets `Debug_Level` at runtime, allowing scripts to narrow
tracing to a specific segment:

```sdata
OPTIONS DEBUG 1    -- only I/O transitions from here
USE mydata.csv
RUN
OPTIONS DEBUG 3    -- full tracing for the next step
RUN
OPTIONS DEBUG 0    -- back off
```

Changes in `execute_declarative.adb`:

1. Add to the bare `OPTIONS` display block:
   ```ada
   Put_Line ("OPTIONS DEBUG "
             & Ada.Strings.Fixed.Trim
                 (SData.Config.Debug_Level'Image, Ada.Strings.Both));
   ```
2. Add handler arm:
   ```ada
   elsif Key = "DEBUG" then
      SData.Config.Debug_Level := Natural'Value (Val);
   ```
   Values > 3 are accepted (silently clamped is out of scope; extra-high
   values just mean "everything fires", which is harmless and consistent with
   SHELLTIMEOUT accepting large values).

The existing `when Constraint_Error` handler at the bottom of the OPTIONS
block covers invalid values for free.

---

## 7. Documentation

### 7.1 `sdata_main.adb` help text

```
--debug[=N]   Trace each statement and record number to stderr
              1=I/O transitions only, 2=+control flow, 3=+assignments (default 3)
```

### 7.2 `src/sdata-help.adb` DEBUGGER topic

Update the "Debug mode: --debug flag" section to list all three levels and
their output. The existing trace-message table is extended with a Level column.

### 7.3 `man/man1/sdata.1`

Update the `.B \-\-debug` entry to document `--debug=N` and the level
meanings.

---

## 8. Testing

Three new integration tests. Each uses a small shell wrapper (same pattern as
`shell_timeout_test.cmd`): run `sdata --debug=N script 2>out.txt`, then
`grep` the captured stderr.

| Test file | Flag | Asserts present | Asserts absent |
|---|---|---|---|
| `tests/debug_level1.cmd` | `--debug=1` | `USE:`, `RUN complete` | `-- record`, `IF →`, `LET` |
| `tests/debug_level2.cmd` | `--debug=2` | `USE:`, `-- record`, `IF →` | `LET`, `SET` |
| `tests/debug_level3.cmd` | `--debug=3` | `USE:`, `-- record`, `IF →`, `LET` | _(nothing absent)_ |

A fourth test `debug_options.cmd` exercises `OPTIONS DEBUG N` at runtime:
enables level 1 inside the script, verifies RUN-complete appears but
record headers do not.

---

## 9. Out of Scope

- Structured JSON output format — not requested; adds complexity for minimal
  gain in a CLI batch tool
- Log file redirection (`--debug-file=path`) — stderr redirect at the shell
  level (`2>out.txt`) is sufficient
- Per-subsystem category flags (e.g. `--debug=assign,flow`) — the ladder
  covers the identified need more simply
- Levels above 3 — no additional trace sites exist to populate them
