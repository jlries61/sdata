# TRANSPOSE Command — Design Specification

**Date:** 2026-06-01
**Status:** Draft, approved for implementation planning
**Author:** John L. Ries (with Claude assistance)

## 1. Overview

`TRANSPOSE` is a new immediate-execution command that reshapes the current
table — each transposed input column becomes one output row, and either each
input row becomes one output column (via an array) or named subsets of input
rows become named output columns (via an /ID variable). If a `BY` statement is
active, each BY block is transposed separately into the same output table.
Like `AGGREGATE`, `TRANSPOSE`:

- Reads from the in-memory table; respects the active `SELECT` filter.
- Replaces the in-memory table with the transposed result.
- Writes the result to the output dataset if a `SAVE` is pending (mirroring
  `Execute_OUTPUT_Table` / VANDALIZE / AGGREGATE), and clears the pending SAVE.
- Clears the active `SELECT` and `BY` once it has run.

The implementation lives in `sdata-core` as a shared `Execute_TRANSPOSE`
procedure, parallel to `Execute_AGGREGATE`, `Execute_USE`, `Execute_SAVE`, and
related shared commands.

## 2. Syntax & grammar

```
TRANSPOSE [/KEEP=<varlist>] [/DROP=<varlist>] [/NAME=<varname>]
          [/ID=<varname>] [/ARRAY=<varname>]
```

- `<varlist>` — one or more whitespace-separated identifiers. Each is either a
  scalar column name or an array name; the latter expands to all element
  columns of that array. At least one item is required if the option is
  present.
- `<varname>` — a single identifier. For `/NAME`, must end in `$` (it names a
  character column). For `/ID`, names an existing column whose values become
  output column names. For `/ARRAY`, names a new array to be created by
  TRANSPOSE.
- Options may appear in any order. Each option may appear at most once.
- `/ID` and `/ARRAY` are mutually exclusive. If neither is specified, an
  implicit `/ARRAY=_X_` is used.
- `/KEEP` and `/DROP` combine as `(KEEP ∖ DROP)`. With only `/KEEP`, the
  transposed set is the KEEP list. With only `/DROP`, the transposed set is
  all non-BY columns minus the DROP list (and minus the `/ID` column if `/ID`
  is used). With neither, the transposed set is all non-BY columns (minus
  `/ID`).
- `/NAME` defaults to `_NAME_$` if not specified.

### AST

A new `Stmt_TRANSPOSE` node carries the options:

```
type Transpose_Options is record
   Keep_List   : Name_Vectors.Vector;     -- empty = "not specified"
   Drop_List   : Name_Vectors.Vector;
   Name_Col    : Unbounded_String;        -- "" = default _NAME_$
   Id_Col      : Unbounded_String;
   Array_Name  : Unbounded_String;        -- defaults to _X_ when neither /ID
                                          --   nor /ARRAY is specified
   Has_Id      : Boolean;
   Has_Array   : Boolean;
end record;
```

The node is classified as **immediate** — it executes the moment the parser
emits it, alongside `RUN`, `SORT`, `NEW`, `AGGREGATE`.

## 3. Semantics

### 3.1 Inputs

- The current data table (column-store).
- The active BY-variable list, retrieved via
  `SData_Core.Table.By_Var_Name(I)`. Possibly empty.
- The active `SELECT` filter, possibly inactive.
- The parsed `Transpose_Options` record.

### 3.2 Resolving the transposed set

Computed once, before scanning:

1. Compute the **KEEP set** of candidate column names:
   - If `Keep_List` is non-empty: union of all names in `Keep_List`, expanding
     any array names to their element columns.
   - Else: every column in the current table that is not in the active BY
     list.
2. Compute the **DROP set** similarly from `Drop_List` (empty if not given).
3. **Transposed set** = `(KEEP) ∖ (DROP) ∖ {ID column, if /ID is used} ∖ (BY columns)`.
4. **Type-uniformity check**: every column in the transposed set must share a
   single type (all numeric or all character). Otherwise error #8.
5. The transposed set is preserved in **column order** — the order columns
   appear in the input schema. Each input column in the set becomes one row
   in each block's portion of the output.

### 3.3 Block identification

A *block* is a maximal run of consecutive rows — in the logical view, after
`SELECT` — whose BY-variable values are all identical. With no active `BY`,
the entire filtered table is one block. **No auto-sort.** Same scan strategy
as `AGGREGATE` and `RUN`.

### 3.4 Pre-scan: determine output schema

Before any output is emitted, a first pass determines:

- **/ARRAY case**: `K = max(rows_in_block_i)` over all blocks. The output
  array has bound `1..K` (subject to §3.7 for empty input).
- **/ID case**: walk every row of every block; accumulate the union of `/ID`
  values in first-encounter order. Within each block, detect duplicates
  (error #6) and validate each `/ID` value as a legal column identifier
  (error #7).

With no active `BY`, the pre-scan reduces to a single pass: `K = rows_in_table`
for /ARRAY; the ID set is just the ID values in input row order for /ID.

### 3.5 Output table construction

A fresh table is built with this column order:

1. **BY columns** (preserved). Each output row in a given block carries the
   block's BY-key values.
2. **`<Name_Col>`** (default `_NAME_$`). Character column. Each output row
   holds the name of the original column it represents.
3. **Transposed value columns**:
   - **/ARRAY case**: `<Array_Name>(1)..<Array_Name>(K)`, registered as a
     DIM-style real array via
     `SData_Core.Variables.Dim_Array (Name => Array_Name, Start_Idx => 1,
     End_Idx => K)`. Followed by `Register_Subscripted_Columns` so
     subscripted access is wired up. The `<Array_Name>`'s `$`-suffix must
     match the transposed set's type: numeric set → no `$`; character set →
     trailing `$`. Mismatch is error #11.

     > **Reconciliation note (2026-06-25):** The `Dim_Array` call above is
     > **incorrect** as a build mechanism. `Dim_Array` (variables.adb:528)
     > writes the *live* data table via `Add_Column` and cannot participate in
     > the `Initialize_Output_Table` → `Commit_Output_Table` build sequence
     > (it operates on the wrong seam). The **as-built** implementation (see
     > ADR-047 and `.ssd/features/transpose/01-architect.md` §C3) adds
     > individually-named `_X_(1)..(K)` columns via `Add_Output_Column`, then
     > calls `Register_Subscripted_Columns` after `Commit_Output_Table`.
     > `Register_Subscripted_Columns` auto-detects the `name(n)` pattern and
     > registers the DIM array; the element `Column_Type` is passed explicitly
     > to `Add_Output_Column` (`Col_String` for a `$` array, else `Col_Numeric`).
     > The spec text above reflects the original design intent; the ADR captures
     > the correction.

   - **/ID case**: one standalone real column per union-ID value, in
     first-encounter order. Each column has the type of the transposed set
     (numeric or character). **Column-name `$`-suffix rule for /ID values:**
     if the transposed set is character, the output column name is the /ID
     value with a trailing `$` appended if not already present; if the
     transposed set is numeric, /ID values ending in `$` are rejected as
     error #7 (illegal column identifier for a numeric column).

The fresh table replaces the current in-memory table.
Column-cursor cache is invalidated.

### 3.6 Emitting rows (per block)

For each block, for each column `C` in the transposed set (in column order):

1. Emit one output row with:
   - **BY columns** ← the block's BY-key values.
   - **`<Name_Col>`** ← the literal name of `C` (e.g., `"score"`, `"height"`).
   - **Transposed value columns** ←
     - **/ARRAY case**: `<Array_Name>(j)` ← the value of `C` at the *j*-th
       row of the block. For blocks shorter than K, positions beyond the
       block's row count are missing.
     - **/ID case**: each column `<id_value>` ← the value of `C` at the
       input row whose `/ID` value equals `<id_value>`. For ID values not
       present in this block, the column is missing.

### 3.7 Empty input

If the filtered input has zero rows, the output table is created with:

- BY columns.
- `<Name_Col>`.
- **No transposed value columns.** The `/ARRAY` is not created (no `Dim_Array`
  call), and the `/ID` union is empty so no value columns exist.

The table has zero rows. No warnings.

### 3.8 Post-execution side effects

Applied in this order, after the new table is committed:

1. **If `SAVE` is pending**: flush the new table via `Execute_OUTPUT_Table`,
   then clear the pending SAVE. Mirrors VANDALIZE (ADR-042) and AGGREGATE.
2. **Clear the active `SELECT` filter.** Its expression may reference columns
   that no longer exist.
3. **Clear the active BY-variable list.** The grouping has been consumed.
4. The deferred-program buffer is already empty by precondition (see §4).
5. `Filter_Map` and column-cursor cache state are invalidated.

### 3.9 Determinism & cost

- Two-pass scan when BY is active: first pass for output schema (K for
  /ARRAY, ID union for /ID); second pass to emit rows. O(N) per pass.
- Single-pass possible when no BY is active and /ARRAY is used (`K = N` is
  known up front) — implementation may collapse the two passes in that case.
- /ID union: O(distinct ID count) memory in the pre-scan dictionary.
- Output table grows via existing `Table` append paths; SQLite spill engages
  automatically when configured.

## 4. Error handling

All TRANSPOSE errors abort the command **before** any side effect (no table
mutation, no SAVE flush, no SELECT/BY clearing). On success, errors during
the SAVE flush behave the same as in AGGREGATE / VANDALIZE: the in-memory
replacement has already happened and is not rolled back. All errors use the
existing `Execute_Record_Error` path; ERR/ERL are populated.

### 4.1 Error catalog

| # | Condition | Message | Phase |
|---|---|---|---|
| 1 | Both `/ID` and `/ARRAY` specified | `TRANSPOSE: /ID and /ARRAY are mutually exclusive` | parse |
| 2 | `/KEEP=` or `/DROP=` present with empty list | `TRANSPOSE: /<KEEP\|DROP>= requires at least one variable` | parse |
| 3 | `/NAME` value does not end in `$` | `TRANSPOSE: /NAME column '<name>' must end in $ (character column required)` | parse |
| 4 | Unknown variable in `/KEEP` or `/DROP` (not a column or array) | `TRANSPOSE: unknown variable '<name>' in /<KEEP\|DROP>` | pre-exec |
| 5 | `/ID` column does not exist | `TRANSPOSE: /ID column '<name>' does not exist` | pre-exec |
| 6 | Two rows in the same block share an `/ID` value | `TRANSPOSE: duplicate /ID value '<v>' in BY group <...>` | scan |
| 7 | `/ID` value is not a legal column identifier | `TRANSPOSE: /ID value '<v>' is not a legal column identifier` | scan |
| 8 | Transposed set mixes numeric and character columns | `TRANSPOSE: columns to transpose must share a type (numeric or character); got mixed` | pre-exec |
| 9 | Transposed set is empty after applying KEEP/DROP/ID exclusions | `TRANSPOSE: no columns to transpose (transposed set is empty)` | pre-exec |
| 10 | Generated output column name appears more than once (e.g., `/NAME` value = BY var; `/ARRAY` name = BY var; an `/ID` value equals a BY var name or the `/NAME` column's name) | `TRANSPOSE: output column name '<name>' collides with <source>` | pre-exec |
| 11 | `/ARRAY` name's `$`-suffix does not match the transposed set's type (numeric set with `$`-suffix name; character set without `$`-suffix name) | `TRANSPOSE: /ARRAY name '<name>' type mismatch — transposed set is <numeric\|character>` | pre-exec |
| 12 | Deferred program buffer non-empty | `TRANSPOSE: pending program statements exist; issue RUN or NEW first` | pre-exec |
| 13 | SAVE flush failure | `TRANSPOSE: SAVE flush failed: <inner message>` | post-exec |

### 4.2 No warnings

TRANSPOSE has no defined warnings. Every irregular condition is either an
error or a silent normal case (e.g., empty input).

### 4.3 Pre-execution validation order

Inside `Execute_TRANSPOSE`, after the parser has produced a syntactically
valid options record (errors 1–3 caught), pre-exec validation proceeds in the
order: 4 → 5 → 8 (after transposed set is resolved) → 9 → 11 → 10 → 12.
Errors 6 and 7 are detected during the first scan pass (§3.4) and abort
before any output table is built.

## 5. Examples

### 5.1 Simplest case (no BY, no /ID, no /ARRAY)

Input:
```
id    score    height
A     95       170
B     87       165
C     92       180
```

```
TRANSPOSE /DROP=id
```

Output (`_X_` is the default array; `_X_` bound = 3):
```
_NAME_$   _X_(1)   _X_(2)   _X_(3)
score     95       87       92
height    170      165      180
```

### 5.2 With /ID

Same input.

```
TRANSPOSE /ID=id
```

Output (`id` auto-excluded from the transposed set; its values become column
names):
```
_NAME_$   A    B    C
score     95   87   92
height    170  165  180
```

### 5.3 With BY and /ID (varying ID sets)

Input:
```
class$    id    score    height
P         A     95       170
P         B     87       165
Q         A     90       175
Q         C     88       172
```

```
BY class$
TRANSPOSE /ID=id
```

Pre-scan: ID union across blocks = `{A, B, C}` in first-encounter order.
Output (C is missing in block P; B is missing in block Q; `.` denotes
missing):
```
class$    _NAME_$   A    B     C
P         score     95   87    .
P         height    170  165   .
Q         score     90   .     88
Q         height    175  .     172
```

### 5.4 With BY and /ARRAY

Same input as 5.3.

```
BY class$
TRANSPOSE /DROP=id
```

Pre-scan: max block size K = 2. Output:
```
class$    _NAME_$   _X_(1)   _X_(2)
P         score     95       87
P         height    170      165
Q         score     90       88
Q         height    175      172
```

If block Q had only one row, `_X_(2)` would be missing for Q's output rows;
`_X_` would still be bound `1..2`.

### 5.5 With /KEEP, /DROP, /NAME

Input:
```
id    score    height    weight    notes$
A     95       170       65        "fit"
B     87       165       70        "avg"
```

```
TRANSPOSE /KEEP=score height weight /DROP=weight /ID=id /NAME=measure$
```

Transposed set = `{score, height, weight} \ {weight} = {score, height}`.
Output:
```
measure$  A    B
score     95   87
height    170  165
```

### 5.6 With SAVE pending

```
USE "raw.csv"
SAVE "wide.csv"
TRANSPOSE /ID=measurement$
```

Output table is written to `wide.csv` immediately; pending SAVE is cleared.

### 5.7 With SELECT active

```
USE "data.csv"
SELECT region$ = "north"
TRANSPOSE /DROP=region$ /ID=site_id
```

Only rows where `region$ = "north"` participate. SELECT is cleared
post-TRANSPOSE.

### 5.8 Errors

Mixed types in transposed set:
```
USE "data.csv"   # score is numeric, label$ is character
TRANSPOSE /KEEP=score label$
# TRANSPOSE: columns to transpose must share a type (numeric or character); got mixed
```

Duplicate /ID values within a block:
```
BY group$
TRANSPOSE /ID=id   # two rows in group "P" both have id="A"
# TRANSPOSE: duplicate /ID value 'A' in BY group group$=P
```

Output collision (/NAME value equals a BY variable name):
```
BY region$
TRANSPOSE /NAME=region$ /ID=site
# TRANSPOSE: output column name 'region$' collides with active BY variable
```

## 6. Implementation footprint

### 6.1 sdata-core

| File | Change |
|---|---|
| `src/sdata_core-commands.ads` | Add public `Transpose_Options` record (using the existing `Name_Vectors.Vector` instantiation in the package). Add `procedure Execute_TRANSPOSE (Options : Transpose_Options)`. |
| `src/sdata_core-commands.adb` | Implement `Execute_TRANSPOSE`: validate (errors #4–#11) → resolve transposed set (§3.2) → pre-scan for /ARRAY bound or /ID union (§3.4) → build output table per §3.5 → emit rows per §3.6 → swap the new table in → optional SAVE flush via `Execute_OUTPUT_Table` → clear pending SAVE, SELECT, and BY (§3.8). |
| `src/sdata_core-table.ads` / `.adb` | No change required. Existing append-column / append-row primitives plus `Register_Subscripted_Columns` cover the implementation needs (confirmed). |
| `src/sdata_core-variables.ads` / `.adb` | No change required. `Dim_Array` is **not used** by the as-built implementation (see §3.5 reconciliation note and ADR-047 §C3); `Register_Subscripted_Columns` performs array wiring post-commit. |

### 6.2 sdata

| File | Change |
|---|---|
| `src/sdata-ast.ads` | Add `Stmt_TRANSPOSE` to `Statement_Kind`. Add fields for the `Transpose_Options` payload. |
| `src/sdata-ast.adb` | Pretty-print / finalize support for the new node. |
| `src/sdata-lexer.adb` | No change expected. `TRANSPOSE` / `/KEEP` / `/DROP` / `/NAME` / `/ID` / `/ARRAY` parse on existing identifier / option-keyword paths. Confirm during implementation. |
| `src/sdata-parser.ads` / `.adb` | Add `Parse_TRANSPOSE`. Recognize option clauses in any order, enforce at-most-once per option, build the `Transpose_Options` record. Catches parse-time errors #1, #2, #3. |
| `src/sdata-interpreter.adb` | Add `TRANSPOSE` to the immediate-command dispatch (alongside `RUN` / `SORT` / `NEW` / `AGGREGATE`). Add the program-buffer guard (error #11). Dispatch handler unpacks the options record and calls `SData_Core.Commands.Execute_TRANSPOSE`. Update the three-tier execution comment block. |
| `src/sdata-help.adb` | New `HELP TRANSPOSE` topic. |

### 6.3 data-vandal

No required changes. `Execute_TRANSPOSE` is available for future use but no
current data-vandal feature needs it.

### 6.4 Public-API impact

- Additive changes to `SData_Core.Commands`: new record type, new procedure.
  No existing signatures change.
- **sdata-core version bump: patch** (per ADR-043 — purely additive, no
  breaking signature changes). A patch bump satisfies the existing
  `sdata_core = "^0.1.0"` constraint in sdata's `alire.toml`, so no consumer
  constraint update is needed.

### 6.5 Memory & spill

- Pre-scan first pass: O(N) — only block boundaries, block sizes, and (for
  /ID) the value union are accumulated. No row buffering.
- Emission pass: rows are read from the column store column-by-column. No
  simultaneous block buffering required.
- /ID union storage: O(distinct ID count) in the pre-scan dictionary.
- Output table grows via existing `Table` append paths; SQLite spill engages
  automatically when configured.

### 6.6 Build & validation

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && make check
cd ~/Develop/data-vandal && make check
```

All three must succeed before commit.

## 7. Testing strategy

### 7.1 Integration tests (sdata `tests/*.cmd`)

New scripts (with paired expected-output files in the existing harness
format). 31 new tests.

| File | Scenario |
|---|---|
| `transpose_basic.cmd` | No BY, no /ID; default `/ARRAY=_X_` |
| `transpose_id.cmd` | No BY, with /ID; first-encounter ordering |
| `transpose_by_id.cmd` | BY + /ID; consistent ID sets |
| `transpose_by_id_union.cmd` | BY + /ID; differing ID sets; union-of-IDs |
| `transpose_by_array.cmd` | BY + /ARRAY; varying block sizes; max-K bound and padding |
| `transpose_keep.cmd` | /KEEP only |
| `transpose_drop.cmd` | /DROP only |
| `transpose_keep_drop.cmd` | Both /KEEP and /DROP; (KEEP ∖ DROP) |
| `transpose_keep_array_expansion.cmd` | /KEEP names an array; expansion to element columns |
| `transpose_name.cmd` | Custom `/NAME=measure$` |
| `transpose_id_auto_exclude.cmd` | /ID column also in /KEEP; auto-excluded silently |
| `transpose_select_active.cmd` | SELECT respected; cleared post-TRANSPOSE |
| `transpose_save_flush.cmd` | SAVE flushed and cleared |
| `transpose_by_cleared.cmd` | BY cleared post-TRANSPOSE |
| `transpose_empty_input.cmd` | Empty filtered input; schema only |
| `transpose_consecutive_runs.cmd` | Unsorted BY; same key in two non-adjacent runs |
| `transpose_default_array.cmd` | No /ID, no /ARRAY → default `_X_` |
| `transpose_character_set_id.cmd` | Character transposed set with /ID; verify auto-`$` suffix on /ID-derived column names |
| `transpose_character_set_array.cmd` | Character transposed set with /ARRAY; verify `$`-suffix array name is required and respected |
| `transpose_id_and_array.cmd` (err) | Error #1 |
| `transpose_empty_keep.cmd` (err) | Error #2 |
| `transpose_name_no_dollar.cmd` (err) | Error #3 |
| `transpose_unknown_keep.cmd` (err) | Error #4 |
| `transpose_unknown_id.cmd` (err) | Error #5 |
| `transpose_dup_id.cmd` (err) | Error #6 |
| `transpose_bad_id_value.cmd` (err) | Error #7 |
| `transpose_mixed_types.cmd` (err) | Error #8 |
| `transpose_empty_set.cmd` (err) | Error #9 |
| `transpose_collision_by.cmd` (err) | Error #10 (/NAME value = BY var) |
| `transpose_collision_name_array.cmd` (err) | Error #10 (/NAME value = /ARRAY name) |
| `transpose_array_suffix_mismatch.cmd` (err) | Error #11 (/ARRAY name `$`-suffix doesn't match transposed set type) |
| `transpose_buffer_nonempty.cmd` (err) | Error #12 |

### 7.2 Unit tests

- **sdata (`tests/sdata_unit_test.adb`)**: ~6 parser-construction cases:
  - Bare `TRANSPOSE` (all defaults).
  - `/KEEP` + `/DROP` combined.
  - `/ID` only.
  - `/ARRAY` only.
  - `/NAME` with custom value.
  - Mutual exclusion check (`/ID` + `/ARRAY` → parse error).
- **sdata-core in-crate driver (`tests/run-tests.sh`)**: no new test
  required. The existing public-API coverage and the 28 integration tests
  exercise `Execute_TRANSPOSE` end-to-end.

## 8. Documentation updates

| Document | Change |
|---|---|
| `doc/design.odt` (and regenerated `doc/design.txt`) | New section under "Commands" describing TRANSPOSE: syntax, semantics, BY/SELECT/SAVE interaction, option-by-option behavior, error catalog summary. Cross-reference to AGGREGATE for the shared "immediate command that replaces the table" pattern. |
| `man/man1/sdata.1` | New `.TP`/`.B TRANSPOSE` block under "Immediate commands". Brief syntax line, paragraph each on the five options, semantics summary; cross-references to BY, SAVE, SELECT, AGGREGATE. |
| `doc/adrs.md` | A new ADR will be added **at implementation time** (number depends on AGGREGATE landing first) capturing the non-obvious decisions: type-uniformity requirement, union-of-IDs across blocks, max-K array bound across blocks, /ID auto-exclusion from the transposed set, error-on-output-collision. |
| `doc/architecture.md` | One-line update in the shared-commands list to mention `Execute_TRANSPOSE`. |
| `src/sdata-help.adb` | `HELP TRANSPOSE` topic: syntax, option semantics, brief examples, pointer to man page. |
| `CLAUDE.md` (sdata) | One-line addition to the immediate-command list. |
| `README.md` (sdata) | Optional: bullet under feature highlights. |

## 9. Versioning

After implementation:

- `cd ~/Develop/sdata-core && # bump alire.toml patch`, tag `vX.Y.Z+1`.
- `cd ~/Develop/sdata && scripts/bump-version.sh <next> "TRANSPOSE command"`,
  tag `v<next>`.

The sdata-core constraint in sdata's `alire.toml` continues to be satisfied;
no consumer constraint update is needed.

## 10. Out of scope

- **Wide-to-long aggregation** (combining transposition with summarization).
  Use `AGGREGATE` first, then `TRANSPOSE`.
- **Multiple ID variables** (compound column-name construction). One `/ID`
  variable only in this version.
- **`/PREFIX=` for /ID column names** (e.g., `id_A`, `id_B`). Achievable with
  RENAME if needed; not part of this spec.
- **Wildcard or column-range syntax in `/KEEP` / `/DROP`** (e.g., `score1-score10`).
  Array names already cover the common case.
- **Non-identifier ID values via quoted columns**. Rejected per error #7;
  could be reconsidered later if user demand emerges.
- **Specifying the transposed-value-column type explicitly** (e.g., to coerce
  numeric to character). Out of scope; user can `LET` a converted copy first.
