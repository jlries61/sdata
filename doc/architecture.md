# SData Architecture

## Overview

SData is a Systat BASIC-style statistical data language implemented as an Ada 2012
interpreter. A script consists of a sequence of *statements* that configure, transform,
and report on tabular data. Execution is split into three tiers, and the central
abstraction is the *data step*.

---

## Repository Layout

Since v0.8.0, sdata is split across three sibling crates:

```
~/Develop/
├── sdata/          this repository — interactive interpreter (sdata binary)
├── sdata-core/     shared Alire library — data layer, evaluator, command exec
└── data-vandal/    sister application — controlled data degradation (former VANDALIZE)
```

`sdata` and `data-vandal` both depend on `sdata-core` via an Alire path pin
during development and a `^0.1.0` version constraint that takes effect when
sdata-core eventually ships to the Alire community index. The three crates
release on independent schedules; see [ADR-039](adrs.md), [ADR-040](adrs.md),
and [ADR-043](adrs.md) for the rationale.

The remainder of this document describes the sdata application. For the
shared layer's contract, read `~/Develop/sdata-core/src/sdata_core.ads` and
`sdata_core-commands.ads`; for the data-vandal application, see the design
spec at `doc/specs/2026-05-19-data-vandal-design.md` and that crate's
own README.

---

## Package Map

Packages prefixed `SData.*` live in this repository; `SData_Core.*` packages
live in `sdata-core/`. The `SData_Core.Commands` package exposes one
`Execute_*` procedure per command shared with data-vandal — both applications
dispatch through it instead of duplicating the execution logic.

```
sdata_main
  └── SData.Interpreter      statement executor and data step engine (this crate)
        │   Subunits: execute_assignment, execute_print,
        │             execute_control_flow, execute_metadata,
        │             execute_declarative, execute_io,
        │             resolve_expr_indices, inspect_pdv,
        │             process_one_record
        ├── SData.Parser           token stream → AST          (this crate)
        │     └── SData.Lexer      keyword/token recogniser    (this crate)
        ├── SData.AST              statement AST node types    (this crate)
        ├── SData.Merge            merge combiner algorithms (positional / match
        │                             / interleave / join) (this crate)
        ├── SData.Transient_Table  mutation-free in-memory table value type
        │                             used by merge + per-target SAVE buffers (this crate)
        ├── SData.Help             HELP topic dispatcher       (this crate)
        ├── SData.Reserved_Keywords  upcased reserved-keyword set, mirroring the
        │                             lexer chain; feeds the USE-time warning (this crate)
        ├── SData.Version          version + copyright strings (this crate; ADR-043)
        ├── SData.System           sdata-only SYSTEM wrapper   (this crate)
        └── SData_Core.Commands    shared command execution    (sdata-core)
              ├── SData_Core.Evaluator   AST expression → Value          (sdata-core)
              │     ├── Aggregate_Fns / Distrib_Fns / Misc_Fns           (sdata-core)
              │     └── Nav_Fns / Numeric_Fns / String_Fns               (sdata-core)
              ├── SData_Core.Variables   PDV + symbol table              (sdata-core)
              ├── SData_Core.Table       in-memory 2-D tabular store     (sdata-core)
              ├── SData_Core.File_IO     CSV / ODF / OOXML read-write    (sdata-core)
              ├── SData_Core.Statistics  aggregate / statistical funcs   (sdata-core)
              ├── SData_Core.Values      core Value variant type         (sdata-core)
              ├── SData_Core.Config      static configuration constants  (sdata-core)
              │     └── Runtime          mutable interpreter state       (sdata-core)
              ├── SData_Core.IO          stdin/stdout/pager I/O          (sdata-core)
              ├── SData_Core.Signals     SIGINT/SIGTERM cleanup          (sdata-core)
              └── SData_Core.System      shell execution + privilege     (sdata-core)
```

Ada enumeration types are closed, so `Token_Kind`, `Statement_Kind`, and
`Expression_Kind` cannot be shared across applications. sdata-core therefore
contains no lexer, AST, or parser — each consumer owns its complete grammar
and hands string-form expressions to `SData_Core.Evaluator.Parse_Expression`
for SELECT-filter compilation. See [ADR-040](adrs.md) for the full rationale.

---

## Quoted Identifiers and the Reserved-Keyword Warning

A column or variable whose name collides with a reserved keyword (or contains
spaces/dots) is referenced with the backtick form `` `name` `` — the language
spec is in `doc/design.md` §3.2. The implementation is a textbook example of the
ADR-040 "design once, implement twice, share only the data-level sliver" pattern,
and it spans all three crates:

- **Lexer (per consumer).** Each grammar adds a `Token_Quoted_Identifier` kind —
  the lexer consumes a leading backtick, scans to the closing backtick, and
  returns the inner text (verbatim, upper-cased on lookup like any identifier).
  A malformed sequence (unterminated, embedded newline, or empty `` `` ``) emits
  one `Put_Line_Error` and yields `Token_Bad`, which the parser maps to a quiet
  `return null` (single diagnostic, no double error).

- **Parser (per consumer).** All identifier-accepting sites route through a
  helper pair — `Is_Identifier_Token` (accepts bare *or* quoted) and
  `Identifier_Text` (reads `T.Text (1 .. T.Length)`) — so quoting works
  uniformly wherever a bare identifier is accepted. No AST or semantic change:
  a quoted identifier resolves to exactly the same name as its bare form.

- **Reserved-keyword set (per consumer).** Each crate owns its own upcased set
  mirroring its lexer keyword chain — `SData.Reserved_Keywords` and
  `Data_Vandal.Reserved_Keywords`. The lists are grammar-specific and stay in
  their crates; only the *warning mechanism* is shared.

- **USE-time warning (shared, in sdata-core).** After a successful `USE`, each
  consumer calls `SData_Core.Commands.Warn_Reserved_Columns (Keywords)` — passing
  its own set — which walks the package-global `SData_Core.Table` and emits one
  advisory per column whose name matches a keyword. Gating lives **inside** the
  helper, keyed on the shared runtime toggle
  `SData_Core.Config.Runtime.Options_Warn_Reserved` (default `True`), so the
  suppression semantics are identical in both consumers. `OPTIONS WARNRESERVED
  YES|NO` flips the toggle via the shared
  `SData_Core.Commands.Execute_OPTIONS_WarnReserved`. This additive sdata-core
  surface is pin-safe for `consumer-tests.yml` and first ships in sdata-core
  **0.1.16**; both consumers therefore constrain `sdata_core ^0.1.16`.

data-vandal had no `OPTIONS` command before this feature; a minimal one
(`Token_OPTIONS` → `Stmt_OPTIONS` → `Parse_OPTIONS` → interpreter dispatch,
with a no-arg display and a non-fatal warning on unknown keys) was added to host
`WARNRESERVED`. The full design record, including the resolved deferred
questions, is in `doc/specs/2026-05-30-quoted-identifiers-design.md`.

---

## Three Execution Tiers

Every statement belongs to exactly one tier. Tier membership determines *when* the
statement executes relative to the data step.

### Tier 1 — Declarative

Commands that configure interpreter state. They execute immediately when the
interpreter encounters them and shape the data step that follows.

| Command | Effect |
|---|---|
| `USE` | Load one or more input datasets (CSV, ODF, OOXML); multi-dataset form supports positional / match / interleave / Cartesian-join merge via `/BY=` / `/INTERLEAVE` / `/JOIN` |
| `SAVE` | Designate one or more output targets for the next RUN; per-target `KEEP=` / `DROP=` / `RENAME=` / `IF=` filter applied at write time |
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
| `DIM var[n]` | Pre-allocate a numeric array (creates new arrays only; columns matching `name(n)` in loaded data are auto-registered at `USE` time per [ADR-041](adrs.md)) |

### Tier 2 — Immediate

Commands that trigger an action at once, outside any data step. They are not queued.

| Command | Effect |
|---|---|
| `RUN` | Execute the pending deferred statement list (see Data Step below) |
| `NEW` | Reset interpreter state; discard deferred list and pending configuration |
| `SORT BY var … [/DESC]` | Sort the current table in place |
| `AGGREGATE out=fn(in) …` | Collapse the table to one row per active BY group via `SData_Core.Commands.Execute_AGGREGATE` (build-and-swap; flushes pending SAVE; clears SELECT and BY) |
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
  SData.Lexer               characters → tokens             (this crate)
        │
        ▼
  SData.Parser              tokens → Statement AST list     (this crate)
        │
        ▼
  SData.Interpreter         dispatches by tier              (this crate)
    ├── Declarative → SData_Core.Commands.Execute_*  for shared commands
    │               (USE / SAVE / FPATH / OUTPUT / SELECT / KEEP / DROP
    │                / ARRAY / DIM / RUN); local subunits for the rest
    ├── Immediate   → act immediately (RUN triggers the data step)
    └── Deferred    → queue; execute once per record inside Run_One_Step
                           │
                           ▼
                     SData_Core.Evaluator   expression nodes → Values  (sdata-core)
                     SData_Core.Variables   symbol lookup / write-back  (sdata-core)
                     SData_Core.Table       row read / output flush     (sdata-core)
```

---

## Shell Access and SUBMIT — Trust Model

`SYSTEM cmd` and `SHELL cmd` pass their argument to the OS shell (`/bin/sh -c` on
POSIX, `bash -c` / `cmd.exe /c` on Windows). `SUBMIT file` reads and executes another
SData script. All three commands execute with the full permissions of the OS account
that launched the interpreter — no more, no less.

**This is intentional design, not a security gap.** SData's security model is that
the OS account is the permission boundary. SData does not add a second layer on top
of what the system administrator has already granted. The same model is used by every
comparable tool: R's `system()`, SAS's `X` statement, Python's `subprocess`, `make`,
`awk`. Adding an internal allowlist or metacharacter escaping would silently break
legitimate use (pipes, redirects, compound commands) while providing no real security
benefit — an attacker who can run an arbitrary SData script can already do anything
the account permits.

**Operator-level mitigations are available when needed:**

| Flag | Effect |
|---|---|
| `--noshell` | Disables `SYSTEM` and `SHELL`; raises `Script_Error` if either is invoked |
| `--nosubmit` | Disables `SUBMIT`; raises `Script_Error` if invoked |

These flags exist for pipeline operators running scripts from untrusted sources in a
shared environment. They are opt-in — the default is unrestricted, consistent with
every analogous tool in this class.

**Resource control (ADR-037):** `OPTIONS SHELLTIMEOUT n` and the `--shell-timeout=N`
CLI flag limit how long a `SYSTEM`/`SHELL` command may run (seconds; 0 = unlimited).
The default in batch mode is 300 s; interactive mode defaults to 0. Implementation
uses `GNAT.OS_Lib.Non_Blocking_Spawn` with a 0.5-second poll loop — no dependency on
`timeout(1)` or PowerShell.

Do not propose sandboxing, allowlisting, or metacharacter escaping as improvements to
this subsystem. The trust model is settled. See `doc/adrs.md` for the recorded
decisions.

---

## Architecture Decision Records

Significant design choices — language selection, execution model, table storage strategy,
CLI conventions, test approach, the sdata-core / data-vandal split, and per-session
architectural calls — are recorded in `doc/adrs.md` (ADR-001 through ADR-045, with a few
unused numbers in the sequence). Each entry captures the context, the decision, the
alternatives considered, and the rationale. Consult it before proposing a structural
change that might relitigate a settled question.
