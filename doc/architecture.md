# SData Architecture

## Overview

SData is a Systat BASIC-style statistical data language implemented as an Ada 2012
interpreter. A script consists of a sequence of *statements* that configure, transform,
and report on tabular data. Execution is split into three tiers, and the central
abstraction is the *data step*.

---

## Package Map

```
sdata_main
  └── SData.Interpreter      statement executor and data step engine
        ├── SData.Parser      token stream → AST
        │     └── SData.Lexer keyword/token recogniser
        ├── SData.Evaluator   AST expression → Value
        │     └── SData.Variables  symbol table (temporary + permanent vars)
        ├── SData.Table       in-memory 2-D tabular store
        ├── SData.File_IO     CSV / ODF / OOXML read-write
        ├── SData.Help        data-driven HELP topic dispatcher
        ├── SData.Statistics  aggregate and statistical functions
        ├── SData.System      SYSTEM command wrapper
        └── SData.Values      core Value variant type (Numeric | String | Missing)
```

---

## Three Execution Tiers

Every statement belongs to exactly one tier. Tier membership determines *when* the
statement executes relative to the data step.

### Tier 1 — Declarative

Commands that configure interpreter state. They execute immediately when the
interpreter encounters them and shape the data step that follows.

| Command | Effect |
|---|---|
| `USE` | Load an input dataset (CSV, ODF, OOXML) |
| `SAVE` | Designate an output path for the next RUN |
| `REPEAT n` | Synthesise *n* blank records instead of reading a file |
| `SELECT expr` | Install a row filter; rows not matching are invisible to deferred commands |
| `SELECT /ALL` | Clear the filter |
| `BY var …` | Set BY-group variables for BOG/EOG indicators |
| `BY` (bare) | Clear BY grouping |
| `FPATH path` | Set the script search path for SUBMIT |
| `HOLD var …` | Retain a variable's value across records |
| `UNHOLD [var …]` | Cancel one or all holds |
| `ARRAY name v1 v2 …` | Bind an indexed alias over existing variables |
| `RENAME old=new …` | Rename columns in the active dataset |
| `DIM var[n]` | Pre-allocate a numeric array |

### Tier 2 — Immediate

Commands that trigger an action at once, outside any data step. They are not queued.

| Command | Effect |
|---|---|
| `RUN` | Execute the pending deferred statement list (see Data Step below) |
| `NEW` | Reset interpreter state; discard deferred list and pending configuration |
| `SORT BY var … [/DESC]` | Sort the current table in place |
| `NAMES` | Print column names of the current dataset |
| `SYSTEM cmd` | Pass a shell command to the OS |
| `HELP [topic]` | Print help text |
| `QUIT` / `END` | Exit the interpreter |
| `SUBMIT file` | Execute another script file |

### Tier 3 — Deferred

Commands that are *queued* after a declarative preamble and *executed once per record*
when `RUN` is reached. Each record is processed by walking the entire deferred list
from top to bottom.

| Command | Notes |
|---|---|
| `LET var = expr` | Assign expression result to a temporary or permanent variable |
| `SET var = expr` | Synonym for LET |
| `PRINT expr …` | Write values to output |
| `WRITE` | Explicitly flush the current record to the output table |
| `DELETE` | Drop the current record from the output table |
| `IF / ELSEIF / ELSE / END IF` | Conditional branching (block and inline forms) |
| `FOR var = lo TO hi [BY step]` | Counted loop |
| `WHILE expr` | Condition-controlled loop |
| `NEXT` | Advance a FOR counter |
| `ECHO msg` | Print a literal string (not record-scoped output) |

---

## The Data Step (`Run_One_Step`)

`RUN` invokes `Run_One_Step`, which performs the following in order:

1. **Rebuild the filter index** — If a `SELECT` filter is active, re-evaluate it
   against every physical row to build a logical→physical index array. Rows that
   do not satisfy the filter are invisible for the remainder of the step.

2. **Determine iteration count** — If `REPEAT n` is active, iterate *n* times over
   blank records. Otherwise iterate over logical rows (filtered) or all physical rows.

3. **For each logical row:**
   - Load the *Program Data Vector* (PDV): copy the row's column values into the
     active variable set and apply any `HOLD`ed carry-over values.
   - Set group indicators: `BOG` (beginning of group) and `EOG` (end of group)
     based on the `BY` variable values of the previous and next rows.
   - Execute the deferred statement list top-to-bottom.
   - If `DELETE` was not issued and `WRITE` was not issued explicitly, flush the PDV
     back to the output table automatically.

4. **Commit** — Replace the active table with the output table, clear the stale
   filter map, and reset `REPEAT_Active` so subsequent `RUN`s iterate the committed
   data.

---

## Variable Scoping

Variables live in one of two namespaces managed by `SData.Variables`:

- **Temporary** — Exist only in memory for the duration of the data step. Created by
  `LET`/`SET` when the name does not correspond to a column in the active table.
  Reset to *missing* at the start of each record unless `HOLD` is active.

- **Permanent** — Correspond to a column in the active table. Reading fetches the
  current row's cell; writing flushes back to the PDV (and eventually to the output
  table at step commit).

The `Value` type (`SData.Values`) is a variant record with four states: `Numeric`
(64-bit float), `Integer`, `String` (unbounded), and `Missing` (SQL NULL equivalent).
The `MISSING()` function tests for this state.

---

## Navigation Functions in Filtered / Grouped Context

All navigation functions operate in *logical* space — filtered-out rows are completely
invisible:

| Function | Returns |
|---|---|
| `RECNO()` | Current logical row number (1-based) |
| `BOF()` | True on the first logical row |
| `EOF()` | True on the last logical row |
| `BOG()` | True when the current row starts a new BY group |
| `EOG()` | True when the current row ends a BY group |
| `LAG(var[, n])` | Value of *var* from *n* logical rows earlier |
| `NEXT(var[, n])` | Value of *var* from *n* logical rows ahead |

---

## Pipeline Summary

```
Script file / REPL input
        │
        ▼
  SData.Lexer          characters → tokens
        │
        ▼
  SData.Parser         tokens → Statement AST list
        │
        ▼
  SData.Interpreter    dispatches by tier
    ├── Declarative → configure state immediately
    ├── Immediate   → act immediately (RUN triggers the data step)
    └── Deferred    → queue; execute once per record inside Run_One_Step
                           │
                           ▼
                     SData.Evaluator   expression nodes → Values
                     SData.Variables   symbol lookup / write-back
                     SData.Table       row read / output flush
```

---

## Architecture Decision Records

Significant design choices — language selection, execution model, table storage strategy,
CLI conventions, test approach, and per-session architectural calls — are recorded in
`doc/adrs.md` (32 decisions, ADR-001 through ADR-032). Each entry captures the context,
the decision, the alternatives considered, and the rationale. Consult it before proposing
a structural change that might relitigate a settled question.
