# Multi-Dataset USE (Merge) and Multi-Target SAVE Design

**Date:** 2026-05-27
**Status:** Approved (design phase)
**Scope:** sdata interpreter; additive helpers in sdata-core

## Context

sdata's current data-step model is single-table: `USE` loads exactly one input
into the current table, the data step iterates that table, and `SAVE` writes the
current table to one output. There is no SAS-style `MERGE` / `SET` / `INTERLEAVE`
facility and no way to route different records to different outputs.

This spec extends `USE` to combine multiple inputs (four merge modes) and
extends `SAVE` to register multiple outputs with per-record routing via the
existing `WRITE` statement. It also introduces SAS-style per-dataset options
(`KEEP`, `DROP`, `RENAME`, `IN`) on `USE` and per-target options
(`KEEP`, `DROP`, `RENAME`, `IF`) on `SAVE`.

## Goals

- Combine 2+ input datasets via positional, match (full outer), interleave, or
  Cartesian-join semantics under one `USE` statement.
- Support per-dataset `KEEP` / `DROP` / `RENAME` / `IN` on `USE`.
- Register multiple output datasets in one `SAVE` and route records per target
  via per-target `IF=` filters or via explicit `WRITE target` statements.
- Support per-target `KEEP` / `DROP` / `RENAME` / `IF` on `SAVE` without
  mutating the in-memory table.
- Preserve full backward compatibility with the existing 140 integration tests
  and all current single-dataset USE/SAVE/WRITE scripts.

## Non-Goals

- Streaming merge (multi-reader state machine). Out of scope; this spec uses
  materialized merge — each input is loaded into a transient table and the
  combined result becomes the current table.
- SQL-style relational join syntax beyond `/JOIN` (no `LEFT`/`RIGHT`/`FULL`
  variants in this iteration; full-outer semantics in match merge plus `IN=`
  variables cover the common cases).
- Merge support in data-vandal. Data-vandal is a single-source tool; the new
  merge orchestration lives in sdata only.
- A `/NOSORT` option on `/BY=`. Sdata auto-sorts inputs by `BY` vars
  internally; an opt-out is deferred until profiling shows it matters.

## 1. Grammar

### USE

```
USE dataset_spec [, dataset_spec ...] [ /whole_statement_option ... ]

dataset_spec := filename [AS alias] [ ( per_dataset_option ... ) ]

per_dataset_option :=
      KEEP=name_list
    | DROP=name_list
    | RENAME=(old=new [, old=new ...])
    | IN=varname
    | FMT=fmt
    | HEADER=YES|NO
    | CHARSET=enc
    | DLM=str
    | NSCAN=n
    | SKIP=n
    | MAXROWS=n

whole_statement_option :=
      BY=var_list
    | INTERLEAVE
    | JOIN
```

### SAVE

```
SAVE save_spec [, save_spec ...] [ /whole_statement_option ... ]

save_spec := filename [AS alias] [ ( per_target_option ... ) ]

per_target_option :=
      KEEP=name_list
    | DROP=name_list
    | RENAME=(old=new [, old=new ...])
    | IF=expr
    | FMT=fmt
    | HEADER=YES|NO
    | CHARSET=enc
```

### WRITE

```
WRITE [target [, target ...]]

target := alias | filename
```

`WRITE` with no arguments retains current semantics: write the PDV to all
registered output targets (respecting per-target `IF=` filters), and suppress
the auto end-of-record flush for the current iteration. With arguments, writes
only to the named targets (still respecting their `IF=` filters) and suppresses
auto-flush for the iteration.

### Lexical notes

- `AS`, `INTERLEAVE`, `JOIN` are contextual keywords — they have keyword
  meaning only inside a `USE`/`SAVE` statement and remain valid as user
  variable names elsewhere. The parser, not the lexer, decides.
- Within a per-dataset or per-target option paren block, options are
  separated by commas. KEEP / DROP value lists are space-separated column
  names (matching the existing standalone `KEEP`/`DROP` command syntax).
  Example: `customers(KEEP=id name, IN=hasCust, RENAME=(amt=amount))`.

### Backward compatibility

Existing single-dataset `USE foo.csv /HEADER=NO` continues to parse: when
exactly one `dataset_spec` is present and the spec carries no parenthesised
option block, slash-options at the end of the statement are treated as
per-dataset options on that single spec. Identical handling for `SAVE`.

The existing single-target `WRITE` with no arguments retains current behavior.

## 2. Merge semantics

| Options                | Mode             | Row count per BY group (or total if no BY) | Notes |
|------------------------|------------------|--------------------------------------------|-------|
| (none)                 | Positional       | `max(N₁..Nₖ)`; shorter sides padded missing | Combined by row index |
| `/BY=k`                | Match (full outer) | `max(N₁..Nₖ)` per group; shorter sides recycle | Warning per BY group where ≥2 sides have >1 row |
| `/BY=k /INTERLEAVE`    | Interleave       | `sum(N₁..Nₖ)` per group                     | Rows emitted in BY-sorted order |
| `/BY=k /JOIN`          | Cartesian inner join | `N₁ × N₂ × ... × Nₖ` per group           | Unmatched groups dropped; warning if group product exceeds `OPTIONS JOIN_WARN_THRESHOLD` (default 1_000_000) |

**Column-name collisions** (across inputs, excluding BY variables): rightmost
dataset wins. One warning emitted per colliding column name (not per row).
`RENAME=` is the user's tool to resolve collisions.

**RENAME / KEEP / DROP order per dataset:** RENAME applies first (so KEEP/DROP
refer to the new names), then KEEP, then DROP. Specifying both KEEP and DROP
for the same dataset is an error.

**RENAME chain semantics:** all rename pairs within one `RENAME=()` block are
applied simultaneously based on the *original* column names, not sequentially.
`RENAME=(a=b, b=c)` renames the original `a` to `b` and the original `b` to
`c` in one step (no collision), matching SAS semantics. Two pairs with the
same source name (`RENAME=(a=b, a=c)`) is an error. Two pairs with the same
target name (`RENAME=(a=c, b=c)`) is an error.

**IN= variables** are temporary integer scalars (0 or 1) per logical record,
named per the per-dataset option. They live in the PDV like any other temp
variable but are read-only from user code.

**BY-sort requirement:** sdata auto-sorts each input by the `BY` variables
before merging (silent, in-memory, via the existing sort path). User does not
have to pre-sort.

**Mutual exclusivity:** `/INTERLEAVE` and `/JOIN` may not both appear; either
requires `/BY=`. `/BY=` without `/INTERLEAVE` or `/JOIN` means match-merge.

**Single-dataset USE** skips the merge code path entirely. No semantic change.

## 3. Multi-output semantics

### SAVE registration

`SAVE` is declarative (current behavior). Each `save_spec` registers one output
in a runtime vector of pending-save records. An empty `SAVE` (`SAVE` alone)
clears all registrations, preserving the current cancel semantics. A subsequent
`SAVE` statement replaces the current registration list.

### Per-target options

- `KEEP` / `DROP` / `RENAME`: applied to the *output projection* at write time.
  The in-memory PDV is not mutated.
- `IF=expr`: row-level filter evaluated per record per target. A record only
  reaches that target if the expression is true (absent `IF=` means always true).
- `FMT` / `HEADER` / `CHARSET`: per-target file-format options; defaults match
  current single-target behavior.

### Auto-flush

At end-of-record, if no `WRITE` statement fired during that iteration, sdata
iterates the registered targets; for each, evaluates the `IF=` filter, applies
`KEEP`/`DROP`/`RENAME` to project the PDV, and writes if the filter passes.
Each registered target receives the record unless its filter says otherwise.

### WRITE behavior

- `WRITE` (no args): write PDV to every registered target (respecting per-target
  `IF=` filters); suppress this iteration's auto-flush.
- `WRITE target [, target ...]`: write only to the named targets (respecting
  their `IF=` filters); suppress auto-flush for the iteration.
- Multiple `WRITE` statements in one iteration are allowed; the same target
  written twice produces two records (matches SAS `OUTPUT`).
- Naming an unregistered target is a runtime error.

### Aliases

`AS alias` gives a target a short handle for `WRITE`. Aliases are scoped to the
current registration list; a new `SAVE` statement replaces the alias namespace.
Aliases must be unique within a SAVE statement.

### Cancel / lifetime

`SAVE` registrations outlive a `USE` (current behavior: `USE → SAVE → USE → RUN`
still writes via the registered SAVE). Registrations are cleared only by an
empty `SAVE` statement, by end-of-program, or by a successful `RUN` flush.

## 4. Architecture

### sdata (this crate)

**AST extensions** (`src/sdata-ast.{ads,adb}`):

- `Stmt_USE` carries `Datasets : Dataset_Spec_Vectors.Vector` plus
  `By_Vars : Name_Vectors.Vector` and `Mode : (Positional | Match | Interleave | Join)`.
- `Dataset_Spec` carries filename, optional alias, per-dataset options
  (KEEP/DROP/RENAME map/IN/FMT/HEADER/CHARSET/DLM/NSCAN/SKIP/MAXROWS).
- `Stmt_SAVE` carries `Targets : Save_Spec_Vectors.Vector`.
- `Save_Spec` carries filename, optional alias, per-target options
  (KEEP/DROP/RENAME/IF expression/FMT/HEADER/CHARSET).
- `Stmt_WRITE` carries `Targets : Name_Vectors.Vector` (empty = no-arg form).

**Parser** (`src/sdata-parser.adb`):

- `Parse_Dataset_Spec` and `Parse_Save_Spec` handle `filename [AS alias] [(opts)]`.
- `Parse_Per_Dataset_Options` and `Parse_Per_Target_Options` consume the paren
  block (key=value sequences separated by whitespace or commas).
- Existing `Parse_Slash_Options` machinery handles whole-statement options after
  the dataset list.
- `Parse_USE` and `Parse_SAVE` consume a comma-separated spec list; the
  single-spec path with trailing slash-options is preserved for back-compat by
  folding those slash-options into the spec when no paren block is present.
- `Parse_WRITE` optionally consumes a comma-separated target list.

**Lexer** (`src/sdata-lexer.adb`):

- `AS`, `INTERLEAVE`, `JOIN`, `IN`, `RENAME` recognised in dataset-spec context
  (some already known as standalone-command keywords).
- Existing paren-token lexing is reused.

**Interpreter:**

- `src/sdata-interpreter-execute_declarative.adb` — `Execute_USE` rewritten:
  1. For each `Dataset_Spec`: load into a transient `Table` via a new
     sdata-core helper that returns the table (rather than installing it);
     then apply RENAME → KEEP → DROP via new `SData_Core.Table` helpers.
  2. When `/BY=`: auto-sort each transient table by the BY vars (existing
     sdata-core sort helper).
  3. Combine transient tables into a single result table via the new
     `SData.Merge` package (positional / match / interleave / join).
  4. Install the combined table as the current table; register IN= columns
     as temporary PDV variables; emit collision warnings; cancel any REPEAT.

- `src/sdata-merge.{ads,adb}` (new) — the four combiner algorithms as pure
  functions over `SData_Core.Table` inputs producing one `Table` output.
  Independently unit-testable.

- `src/sdata-interpreter-execute_declarative.adb` — `Execute_SAVE` rewritten:
  parses spec list into a `Pending_Save_Vectors.Vector` stored in interpreter
  state. Empty SAVE clears the vector.

- `src/sdata-interpreter-execute_io.adb` — `Execute_WRITE` rewritten:
  resolves target names against the registered list; for each chosen target
  (or all, if no args) evaluates the IF= filter, projects the PDV via
  KEEP/DROP/RENAME, and appends to the target's writer. Sets a per-record
  "write fired" flag.

- `src/sdata-interpreter-process_one_record.adb` — at end-of-record, if the
  per-record "write fired" flag is unset, iterate registered SAVE targets and
  apply the same project-and-write path.

- `src/sdata-interpreter.adb` — at end of `RUN`: close all SAVE target writers,
  clear the registration list (mirrors current single-SAVE flush-at-RUN).

### sdata-core (additive only — no breaking changes)

New `SData_Core.Table` helpers (purely additive):

- `procedure Rename_Column (T : in out Table; Old_Name, New_Name : String);`
- `procedure Apply_Keep (T : in out Table; Names : Name_Vectors.Vector);`
- `procedure Apply_Drop (T : in out Table; Names : Name_Vectors.Vector);`
- `procedure Sort_By (T : in out Table; Vars : Name_Vectors.Vector);` (if not
  already exposed at this level).
- A "load to transient Table" variant of file I/O that returns a `Table`
  rather than installing it as the current table. May reuse existing
  `SData_Core.File_IO.Read_*` if those already produce a `Table` value.

`Execute_USE`, `Execute_SAVE`, and all other `Commands.Execute_*` signatures
remain unchanged. Data-vandal compiles and runs unchanged.

### Runtime state (sdata interpreter)

- `Registered_Saves : Pending_Save_Vectors.Vector` — the multi-target SAVE
  registration list. Single-target SAVE either updates this vector (single
  entry) or continues to use the existing `Runtime` single-pending-SAVE field;
  the implementation plan will choose one path for consistency.
- `Write_Fired_This_Iter : Boolean` — reset per record in
  `process_one_record`, set by `Execute_WRITE`, consulted at end-of-record.

## 5. Error handling

### USE-time errors (fail the statement, no partial state change)

- Per-dataset file not found / unreadable / wrong format — same path as today.
- `/BY=` variable not present in every input — error naming the variable and
  dataset.
- KEEP and DROP both specified for the same dataset — error.
- KEEP/DROP/RENAME referencing a non-existent column — silent-ignore
  (consistent with current standalone KEEP/DROP behavior).
- RENAME target name collides with an existing (non-renamed) column in the
  same dataset — error.
- RENAME has two pairs with the same source name, or two pairs with the same
  target name — error (see §2 RENAME chain semantics).
- `/INTERLEAVE` and `/JOIN` both present — parse error.
- `/INTERLEAVE` or `/JOIN` without `/BY=` — parse error.
- IN= variable name collides with a real column name in any input — error.
- IN= variable name collides between datasets (two `IN=foo`) — error.
- Alias collides with another alias in the same USE — error.
- Single dataset with `/JOIN` or `/INTERLEAVE` — error.

### USE-time warnings (one per occurrence, not per row)

- Column-name collision across inputs (last wins).
- N:M overlap in match merge (per BY group).
- `/JOIN` group product exceeds `OPTIONS JOIN_WARN_THRESHOLD` (per BY group).

### SAVE-time errors

- Two targets with the same alias — error.
- Two targets writing the same filename — error.
- KEEP and DROP both specified for the same target — error.
- `IF=` expression references a variable not in the PDV — error at SAVE-bind
  time.
- Target file unwriteable / directory missing — same path as today; deferred
  to write time.

### WRITE-time errors

- Named target not in the registered SAVE list — runtime error with the
  unknown name.
- `WRITE` before any `SAVE` has registered — runtime error.
- `WRITE` with empty target list (`WRITE ,`) — parse error.

### Per-record behavior

- `IF=` filter evaluation failure (e.g., type mismatch) — error, terminates run.
- Zero records survive all filters — output files still created with header
  only (or empty depending on `/HEADER=`), matching current single-SAVE
  zero-row behavior.

### Cleanup

- SIGINT mid-merge: existing sdata-core signals cleanup closes transient
  tables; extended to close any open SAVE target writers.

### Memory

- Worst-case footprint during USE is the sum of all transient input tables
  plus the combined output table. The existing SQLite spill mechanism applies
  to each.

## 6. Testing strategy

### Integration tests (`tests/*.cmd`, following the existing pattern)

**Merge:**

- Positional merge — equal row counts, mismatched counts (short side padded),
  three+ datasets, with KEEP/DROP/RENAME per dataset.
- Match merge (default full outer) — 1:1, 1:M, M:1, N:M (verify warning),
  unmatched keys on each side, three-way merge.
- Interleave — two and three datasets, overlapping and disjoint BY groups,
  auto-sort verified by feeding unsorted input.
- Cartesian join — N:M produces N*M, unmatched groups dropped,
  `JOIN_WARN_THRESHOLD` warning trip.
- `IN=` variables — values correct across all four modes, naming collision
  rejected.
- Column collision warning — fired once per name, not per row; last-wins value
  verified.
- Per-dataset RENAME→KEEP→DROP order verified by one test exercising all
  three on one input.
- Backward-compat: every existing single-USE `.cmd` test continues to pass.

**Multi-output:**

- Two SAVE targets with no WRITE — both receive every record.
- Two SAVE targets with per-target `IF=` filters — records partition correctly.
- `WRITE target` routes correctly; auto-flush suppressed when WRITE fires.
- WRITE to alias vs filename both work.
- Multiple WRITE statements in one iteration — two records to same target.
- WRITE to unknown target — runtime error.
- Per-target KEEP/DROP/RENAME — output columns differ per file; live PDV
  unchanged.
- Backward-compat: every existing single-SAVE `.cmd` test continues to pass.

**Errors:**

- Every error condition listed in §5 — one focused `.cmd` test each asserting
  exit code and stderr.

### Unit tests (additions to `bin/sdata_unit_test`)

- `SData_Core.Table` new helpers (`Rename_Column`, `Apply_Keep`, `Apply_Drop`)
  — round-trip and edge cases (rename to existing name, keep/drop empty list,
  drop all columns).
- `SData.Merge` package — pure-function tests for each of the four combiner
  algorithms with constructed `Table` inputs and asserted output table shape
  and values.

### Build validation

- `make check` (sdata, 140 + new tests) passes.
- `cd ~/Develop/data-vandal && make check` (11 tests) passes — verifies
  additive sdata-core changes did not break the other consumer.
- `cd ~/Develop/sdata-core && alr build` succeeds.

### TDD order of authorship

1. sdata-core helper unit tests + helpers.
2. `SData.Merge` combiner unit tests + algorithms.
3. Grammar parser tests (one `.cmd` per parse error).
4. Semantic integration tests for each merge mode and multi-output scenario.
5. Error-condition integration tests from §5.

## Open questions deferred to implementation plan

- Whether to migrate single-target SAVE off the `Runtime` single-pending-SAVE
  field entirely (use the new vector always) or keep both paths.
- Exact lexer changes vs reuse for paren / `AS` recognition in dataset-spec
  contexts.
- Whether `Sort_By` already exists at the public `SData_Core.Table` API or
  needs adding alongside the other helpers.
- Whether `SData_Core.File_IO.Read_*` already returns a `Table` value or
  always installs into Runtime — affects the "load to transient table"
  helper's shape.

These are scoping questions the implementation plan will resolve by reading
the current sdata-core code; they do not affect the user-visible design.
