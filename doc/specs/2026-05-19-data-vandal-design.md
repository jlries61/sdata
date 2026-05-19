# data-vandal — Design Specification

**Date:** 2026-05-19  
**Status:** Approved  
**Scope:** New standalone application + sdata-core shared library + VANDALIZE removal from SData

---

## 1. Overview

`data-vandal` is a standalone Ada interpreter for controlled data degradation. It loads tabular
data, applies VANDALIZE operations (with optional row filtering via SELECT), and saves the result.
Its command set is a deliberate subset of SData's language — enough to load, configure, and save
data, with VANDALIZE as the sole operational command.

VANDALIZE is simultaneously **removed from SData**. It moves exclusively to data-vandal. Scripts
that use only the commands listed in Section 6 are syntactically identical between SData and
data-vandal; they run in either interpreter without modification.

---

## 2. Repository & Crate Layout

Three sibling directories under `~/Develop/`:

```
~/Develop/
├── sdata/          # existing — loses VANDALIZE; gains sdata-core dependency
├── sdata-core/     # new Alire library crate (path dependency during development)
└── data-vandal/    # new application crate
```

`sdata-core` is an Alire library crate (no `executables` entry). Both consumer crates reference it
via a local path pin:

```toml
# in sdata/alire.toml and data-vandal/alire.toml
[[pins]]
sdata_core = { path = "../sdata-core" }
```

When `sdata-core` is sufficiently stable it gets its own git repository and an Alire index entry;
the pin becomes a normal `[[depends-on]]`. That promotion requires a one-line change in each
consumer's `alire.toml`.

---

## 3. sdata-core: Package Boundary

Ada enumeration types are closed — `Token_Kind` and `Statement_Kind` cannot be extended after
definition. Therefore **sdata-core contains no lexer, AST, or parser code.** Each application owns
its complete token set and grammar. The shared code is the data layer, the evaluator, and the
command execution procedures.

### 3.1 Packages Moving from sdata → sdata-core

All packages are renamed from `SData.*` to `SData_Core.*`. Logic is unchanged; only the package
prefix changes.

| Current (sdata) | Moved to (sdata-core) |
|---|---|
| `SData.Table` | `SData_Core.Table` |
| `SData.Values` | `SData_Core.Values` |
| `SData.Variables` | `SData_Core.Variables` |
| `SData.Statistics` | `SData_Core.Statistics` |
| `SData.CSV` | `SData_Core.CSV` |
| `SData.File_IO` | `SData_Core.File_IO` |
| `SData.File_IO.CSV` | `SData_Core.File_IO.CSV` |
| `SData.File_IO.ODF` | `SData_Core.File_IO.ODF` |
| `SData.File_IO.OOXML` | `SData_Core.File_IO.OOXML` |
| `SData.File_IO.Helpers` | `SData_Core.File_IO.Helpers` |
| `SData.IO` | `SData_Core.IO` |
| `SData.Config` | `SData_Core.Config` |
| `SData.Signals` | `SData_Core.Signals` |
| `SData.Evaluator` | `SData_Core.Evaluator` |
| `SData.Evaluator.Aggregate_Fns` | `SData_Core.Evaluator.Aggregate_Fns` |
| `SData.Evaluator.Distrib_Fns` | `SData_Core.Evaluator.Distrib_Fns` |
| `SData.Evaluator.Misc_Fns` | `SData_Core.Evaluator.Misc_Fns` |
| `SData.Evaluator.Nav_Fns` | `SData_Core.Evaluator.Nav_Fns` |
| `SData.Evaluator.Numeric_Fns` | `SData_Core.Evaluator.Numeric_Fns` |
| `SData.Evaluator.String_Fns` | `SData_Core.Evaluator.String_Fns` |

The expression AST types (currently part of `SData.AST`) that the evaluator operates on move with
it into `SData_Core.Evaluator`. Statement AST types remain in each application's own AST package.

### 3.2 New Packages Added to sdata-core

**`SData_Core.Interpreter_State`**

A record type holding all interpreter-level state shared between the common command procedures:
current file path (FPATH), output path, active table, save-on-run flag, header mode, and the
persistent SELECT filter expression. Both applications embed this record in their own interpreter
state structures.

**`SData_Core.Commands`**

One procedure per shared command, each accepting the `Interpreter_State` record plus plain Ada
values extracted by the calling application's parser. No AST node types cross the boundary.

```ada
procedure Execute_USE    (State : in out Interpreter_State; Path   : String);
procedure Execute_SAVE   (State : in out Interpreter_State; Path   : String);
procedure Execute_FPATH  (State : in out Interpreter_State; Path   : String);
procedure Execute_OUTPUT (State : in out Interpreter_State; Path   : String);
procedure Execute_SELECT (State : in out Interpreter_State;
                          Expr  : SData_Core.Evaluator.Expression_Access);
procedure Execute_KEEP   (State : in out Interpreter_State; Vars   : Variable_List);
procedure Execute_DROP   (State : in out Interpreter_State; Vars   : Variable_List);
procedure Execute_ARRAY  (State : in out Interpreter_State; Name   : String;
                          Vars  : Variable_List);
procedure Execute_DIM    (State : in out Interpreter_State; Name   : String;
                          Start : Integer; Stop : Integer);
procedure Execute_RUN    (State : in out Interpreter_State);
```

All file I/O, table manipulation, path resolution, and filter-map rebuilding live in these
procedures — written once, used by both applications.

`Execute_SELECT` accepts an already-parsed `Expression_Access`. Each application's parser is
responsible for calling `SData_Core.Evaluator.Parse_Expression` on the token stream to produce
this value before invoking `Execute_SELECT`. `SData_Core.Evaluator` exports
`Parse_Expression` for this purpose, making the expression parser a shared entry point consumed
by both application parsers.

### 3.3 Auto-Detection of Subscripted Columns

`SData_Core.Variables` gains `Register_Subscripted_Columns`, called by `Execute_USE` after every
file load. It scans the loaded column names for the pattern `name(n)` (where `n` is a positive
integer), groups all subscripts sharing the same base name (gaps in the numeric sequence are
permitted), and registers each group as a DIM array in the variable registry. Both applications
receive this automatically; no user command is required.

---

## 4. data-vandal: Internal Structure

`data-vandal` is a thin application layer on top of `sdata-core`. Its source tree:

```
data-vandal/
├── alire.toml                              -- crate: data_vandal; binary: data-vandal
├── src/
│   ├── data_vandal_main.adb               -- entry point: arg parsing, REPL/script loop
│   ├── lexer/
│   │   └── data_vandal-lexer.ads/adb      -- tokens for the supported command set
│   ├── ast/
│   │   └── data_vandal-ast.ads            -- statement kinds: subset + Stmt_VANDALIZE
│   ├── parser/
│   │   └── data_vandal-parser.ads/adb     -- grammar for all supported commands
│   ├── data_vandal-interpreter.ads/adb    -- read-eval loop; routes to SData_Core.Commands
│   ├── data_vandal-execute_vandalize.ads/adb  -- VANDALIZE executor
│   └── data_vandal-help.ads/adb           -- HELP command + per-command entries
├── tests/
│   └── *.cmd                              -- integration tests (ported from sdata vandalize_*.cmd)
└── man/
    └── man1/data-vandal.1                 -- man page
```

Package hierarchy root: `Data_Vandal.*`

### 4.1 Interpreter Loop

The interpreter is a simple parse-and-dispatch loop. There is no deferred statement queue, no PDV
pipeline, and no `Run_One_Step`. VANDALIZE is an immediate command; the loop is: parse one
statement → execute it → repeat. `RUN` rebuilds the SELECT filter map (via
`Execute_RUN` in `SData_Core.Commands`) and, if `OUTPUT` was set without an explicit `SAVE`,
writes the table to the output path.

### 4.2 VANDALIZE Executor

`Data_Vandal.Execute_VANDALIZE` is a direct port of the VANDALIZE section of
`sdata-interpreter-execute_declarative.adb` (~360 lines), with three mechanical changes:

1. Package prefix renamed: `SData.*` → `Data_Vandal.*` for application packages,
   `SData.*` → `SData_Core.*` for data-layer packages.
2. Interpreter state accessed via `SData_Core.Interpreter_State` rather than interpreter-internal
   variables.
3. BY-group save/restore operates on the shared state record.

No algorithmic changes. Full VANDALIZE syntax is preserved, including `/MISS`, `/SHUFFLE`,
`/PERTURB`, `/BY=`, `INTO`, and array (DIM-style) source support via auto-detected arrays.

### 4.3 Array Support

`DIM` is not a command in data-vandal. Subscripted variables are registered automatically at `USE`
time (see §3.3). VANDALIZE's array iteration operates on whatever arrays the auto-detection
registered. `ARRAY` (named variable groups) is supported for use with `/BY=` grouping.

### 4.4 Help

`HELP` covers only the commands data-vandal supports. `HELP VANDALIZE` output is identical to
SData's current text. Help is not shared from sdata-core; data-vandal maintains its own
`Data_Vandal.Help` package.

---

## 5. Changes to SData

### 5.1 Removed

| Artifact | Location |
|---|---|
| `Token_VANDALIZE` | `src/lexer/sdata-lexer.ads` |
| `Stmt_VANDALIZE` and its AST variant | `src/ast/sdata-ast.ads` |
| VANDALIZE parser case | `src/parser/sdata-parser.adb` |
| VANDALIZE `Is_Immediate` entry and case branch | `src/sdata-interpreter.adb` |
| VANDALIZE executor section | `src/sdata-interpreter-execute_declarative.adb` |
| `Help_VANDALIZE` | `src/sdata-help.adb` |
| VANDALIZE man page entry | `man/man1/sdata.1` |
| All 13 `vandalize_*.cmd` integration tests | `tests/` → move to `data-vandal/tests/` |

ADR-038 (VANDALIZE design) is updated to status **Superseded**, with a note pointing to the
data-vandal repository.

### 5.2 Renamed

All moved packages (`SData.Table`, `SData.Values`, etc.) are referenced as `SData_Core.*`
throughout the remaining sdata source. This is a mechanical find-and-replace across `with` and
`use` clauses — no logic changes.

The nine moved packages are deleted from `sdata/src/`. The `sdata` crate acquires a path pin on
`sdata-core` in `alire.toml`.

### 5.3 DIM Scope Narrowed

SData retains the `DIM` command. Its role narrows: `DIM` is only for creating subscripted
variables that do not yet exist in the input data. Auto-detection (§3.3) handles variables already
present in a loaded file. Existing scripts are unaffected — `DIM` before `USE` pre-declares;
`DIM` after `USE` extends or creates.

### 5.4 Regression Requirement

SData's 118 non-VANDALIZE integration tests must all pass after the refactor with no behaviour
changes to any remaining command.

---

## 6. Command Set & Script Compatibility

### data-vandal Command Set

| Command | Kind | Notes |
|---|---|---|
| `FPATH <path>` | Declarative | Sets search path for USE and SAVE |
| `USE <file>` | Declarative | Loads CSV/ODS/XLSX; auto-registers subscripted columns as arrays |
| `OUTPUT <file>` | Declarative | Sets default output path |
| `SELECT <expr>` | Declarative | Row filter; full SData expression language via sdata-core evaluator |
| `KEEP <var> [<var>...]` | Declarative | Retain only named columns |
| `DROP <var> [<var>...]` | Declarative | Remove named columns |
| `ARRAY <name> <var> [<var>...]` | Declarative | Named variable group (for use with /BY=) |
| `VANDALIZE <src> [INTO <dest>] [/MISS[=...]] [/SHUFFLE[=...]] [/PERTURB[=...]] [/BY=...]` | Immediate | Full syntax preserved |
| `RUN` | Immediate | Separator; rebuilds SELECT filter; triggers save if OUTPUT set |
| `HELP [<topic>]` | Immediate | Covers all supported commands |
| `QUIT` / `EXIT` | Immediate | Exits interactive mode |

### Script Portability

A `.cmd` file that uses only commands from the table above runs identically in both SData and
data-vandal. data-vandal rejects unknown commands (including `LET`, `SET`, `PRINT`, `FOR`,
`WHILE`, `SORT`, `BY`, `DIM`, and all others not in the table) with a clear parse error.

`LET`, `SET`, and other transformation commands are intentionally absent. Users needing those
operations run them in SData first, then pass the result to data-vandal.

---

## 7. External Dependencies

`sdata-core` inherits all of sdata's current Alire dependencies, since it contains the packages
that use them:

- `zipada` — ODS (ODF) file support
- `xmlada` — OOXML file support  
- `mathpaqs` — statistical distribution functions
- `ada_sqlite3` — SQLite disk spill for large tables

`data-vandal` depends only on `sdata-core`; it acquires the above transitively.

---

## 8. Out of Scope

- Publishing `sdata-core` to the Alire community index (deferred; path dependency is sufficient
  while both consumers are under active development).
- Interactive mode enhancements (readline, history) beyond what sdata already provides.
- New VANDALIZE operations or syntax changes.
- Any SData command not listed in §6.
