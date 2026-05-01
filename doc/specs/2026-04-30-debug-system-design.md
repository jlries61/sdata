# Debug System Design

**Date:** 2026-04-30
**Version target:** post-0.6.5
**Status:** Approved for implementation

---

## Overview

SData already accepts `--debug` at the CLI and stores it in `SData.Config.Debug_Mode`, and two skeletal trace points exist in `sdata-interpreter.adb`. This design enriches those traces and adds interactive inspection capability.

The system has two parts:

1. **Passive trace** — enriched `--debug` output to stderr showing what each statement did
2. **Interactive inspection** — a mini-REPL triggered by a `BREAK` statement or by step mode under `--debug`, allowing the user to examine and navigate the PDV without re-running the script

---

## Mental Model

Permanent scalar variables are **vectors** — each holds one value per record in the internal table. Permanent arrays are **matrices**. Temporary variables behave like conventional programming language variables: a single value in scope for the current execution context.

This distinction matters for debugging: when investigating `LAG()`, `NEXT()`, or any computation that depends on neighbouring records, the values at adjacent rows are as relevant as the value at the current record. Record navigation exists to support this.

---

## Part 1: Passive Trace Enrichment

### Helper procedures (private, `sdata-interpreter.adb`)

```ada
procedure Debug_Trace (Msg : String);
--  Emits "[debug] " & Msg to stderr iff Debug_Mode is True.

function Debug_Value (V : Value) return String;
--  Formats a Value for debug output:
--    Val_Numeric  → "5.00000"
--    Val_Integer  → "3"
--    Val_String   → """hello"""  (with surrounding quotes)
--    Val_Missing  → "<missing>"
```

These replace the two existing inline `if Debug_Mode then Put_Line_Error` blocks and are used by all new trace points.

### Trace points

| Event | Output format |
|---|---|
| LET/SET scalar | `[debug] LET X = 5.00000` |
| LET/SET array element | `[debug] LET A(2) = 99.00000` |
| IF condition | `[debug] IF → TRUE` or `[debug] IF → FALSE (skipping N)` |
| ELSE branch | `[debug] ELSE → taken` |
| SELECT filter | `[debug] SELECT → KEPT` or `[debug] SELECT → DROPPED` |
| DELETE | `[debug] DELETE: record marked` |
| FOR iteration | `[debug] FOR I = 3` |
| BY group start | appended to record line: `  [BY GROUP START: DEPT="Sales"]` |
| BY group change | appended to record line: `  [BY GROUP CHANGE: DEPT "Sales" → "Marketing"]` |
| USE opened | `[debug] USE: opened sales.csv (50 records, 3 variables)` |
| RUN complete | `[debug] RUN complete: 50 records, 3 variables` |
| SUBMIT entered | `[debug] SUBMIT: entering bonus_report.sdata` |

**Not traced:** individual function calls within expressions, variable reads, PRINT output, ECHO output, WHILE/WEND/REPEAT/UNTIL loop boundaries.

### Record header line (existing, extended)

The existing record trace:
```
[debug] -- record 1 (physical 1)
```
is extended with an optional BY annotation:
```
[debug] -- record 1 (physical 1)  [BY GROUP START: DEPT="Sales"]
[debug] -- record 3 (physical 3)  [BY GROUP CHANGE: DEPT "Sales" → "Marketing"]
```

---

## Part 2: Interactive Inspection

### Inspection mini-REPL

When execution pauses, the interpreter enters an inspection prompt. The prompt label shows the current inspection record:

```
[debug:record 5]> PRINT SALARY
45000.00000
[debug:record 5]> RECORD 23
[debug] loaded record 23 into PDV
[debug:record 23]> PRINT SALARY
112000.00000
[debug:record 23]> RECORD -1
[debug] loaded record 22 into PDV
[debug:record 22]> PRINT SALARY
98000.00000
[debug:record 22]> CONTINUE
```

The inspection position (which record's values are in the PDV) is independent of the execution position. Navigating to record 23 does not change which record is processed when `CONTINUE` is issued.

#### Commands

| Command | Aliases | Effect |
|---|---|---|
| `PRINT <expr>` | | Evaluates and prints any SData expression, including aggregates |
| `RECORD N` | | Loads absolute record N into the PDV; updates prompt label |
| `RECORD +N` | | Advances N records from current inspection position |
| `RECORD -N` | | Goes back N records from current inspection position |
| `CONTINUE` | `C` | Resumes execution from the paused point |
| `STEP` | `S` | Resumes to the next record then pauses again |
| `RUN` | | Resumes to completion with no further automatic pausing |

`PRINT` reuses the existing expression evaluator: `PRINT MEAN(SALARY)`, `PRINT LOG(X + 1)`, `PRINT NAME$` all work. Aggregate functions operate over the full table regardless of inspection position.

`RECORD N/+N/-N` clamps silently at record 1 and the logical row count rather than raising an error.

#### Non-interactive context

When stdin is not a TTY (piped or redirected batch run), `BREAK` emits the debug state line to stderr and continues automatically without waiting for input. Step mode behaves as passive trace only.

### BREAK statement

**Syntax:**
```
BREAK
BREAK WHEN <boolean-expr>
```

`BREAK` is a **deferred statement** — valid only inside a data step (between `RUN` and the preceding statements). It has no effect in immediate mode.

`BREAK` always pauses. `BREAK WHEN <expr>` pauses only when the condition evaluates to true, e.g.:

```
BREAK WHEN RECNO() = 50
BREAK WHEN SALARY > 100000
BREAK WHEN NAME$ = "Smith"
```

**AST:** `Stmt_BREAK` with an optional condition field (`Expr : Expression_Access := null`; null means unconditional).

**Parser:** `BREAK` with no following token (or a non-`WHEN` token) → unconditional. `BREAK WHEN` → parse boolean expression into condition field.

### Step mode under `--debug`

When `--debug` is active, after printing each record header line and before executing that record's statements, the interpreter automatically enters the inspection REPL. The user can inspect the PDV (loaded from the table for that record), navigate to any other record, then:

- `CONTINUE` — processes the current record's statements and advances to the next record, pausing again
- `STEP` — same as CONTINUE in this context
- `RUN` — processes the current and all remaining records without further pausing

Step mode can be disabled mid-run by typing `RUN` at the prompt.

---

## Implementation Scope

All changes are confined to `src/sdata-interpreter.adb` and `src/sdata-ast.ads` / `src/sdata-parser.adb` (for `Stmt_BREAK`). No new packages. No changes to `sdata-config.ads`, `sdata_main.adb`, or the man page beyond adding `BREAK`/`BREAK WHEN` to the command reference.

**Estimated new code:** ~150–200 lines across the trace points, the inspection REPL loop, the `BREAK` handler, and the two helper procedures.

---

## Testing

New test cases:

| Test | What it verifies |
|---|---|
| `debug_trace.cmd` + `.flags` (`--debug`) | Passive trace output for LET, IF, SELECT, BY group change |
| `break_basic.cmd` | `BREAK` in a non-interactive context continues automatically |
| `break_when.cmd` | `BREAK WHEN RECNO() = N` pauses on the right record (non-interactive: continues) |

Interactive REPL behaviour (RECORD navigation, CONTINUE, STEP) is not automatable with the current `make check` harness and is covered by manual testing.

---

## Future Extensions (out of scope)

- Statement-level stepping (pause before each statement, not just each record)
- `WATCH <var>` — automatic break when a variable's value changes
- Verbosity levels (`--debug=1/2/3`)
- `DEBUG` immediate-mode statement for PDV snapshot on demand
