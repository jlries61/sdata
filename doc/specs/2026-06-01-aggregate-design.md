# AGGREGATE Command — Design Specification

**Date:** 2026-06-01
**Status:** Draft, approved for implementation planning
**Author:** John L. Ries (with Claude assistance)

## 1. Overview

`AGGREGATE` is a new immediate-execution command that collapses the current
data table into one row per BY group, computing aggregate functions on chosen
input columns. The command:

- Reads its grouping from the active `BY` statement (no `/BY=` option).
- Respects the active `SELECT` filter.
- Writes its result both to the in-memory table and (if a `SAVE` is pending) to
  the output dataset, mirroring the `Execute_OUTPUT_Table` pattern used by
  data-vandal's `VANDALIZE`.
- Clears the active `SELECT`, the active `BY`, and the pending `SAVE` once it
  has run.

The implementation lives in `sdata-core` as a shared
`Execute_AGGREGATE` procedure (Approach A from brainstorming), parallel to
`Execute_USE`, `Execute_SAVE`, `Execute_RUN`, and related shared commands.

## 2. Syntax & grammar

```
AGGREGATE <outvar>=<function>(<invar>) [<outvar>=<function>(<invar>) ...]
```

- `<outvar>` — identifier for the new output column. May end in `$` to denote
  character. The suffix must match the function's return type given the input
  type (the same rule the language applies everywhere else).
- `<function>` — case-insensitive name of a registered aggregate function.
  Initial set: `SUM`, `MEAN`, `STD`, `VAR`, `MIN`, `MAX`, `N`, `NMISS`,
  `GMEAN`, `HMEAN`, `MEDIAN`. Any function later added to the aggregate
  dispatch table is automatically eligible; no grammar change required.
  Non-aggregate functions (`SQRT`, `LEN$`, …) are rejected at parse time.
- `<invar>` — one of:
  1. **Scalar column name**, e.g. `price`. Output `<outvar>` is a scalar column.
  2. **Registered array name**, e.g. `a` (per ADR-041). Output `<outvar>` is
     an array with the input array's bounds; element-wise:
     `<outvar>(i) = <function>(<invar>(i))` over each group.
  3. **Array element with positive integer literal subscript**, e.g. `x(1)`.
     Treated as the scalar column it resolves to; output is scalar.
- Argument is required for every function except `N`. `N()` with no argument
  means "group size" and yields an integer scalar. `NMISS` requires an
  argument like every other aggregate.
- At least one outvar spec is required. Specs are separated by whitespace.
- There is no `/BY=` clause. Grouping is taken from the active `BY` statement.

### AST

A new `Stmt_AGGREGATE` node carries a vector of specs. Each spec is:

```
type Aggregate_Spec is record
   Outvar      : Unbounded_String;
   Fn_Name     : Unbounded_String;
   Invar_Kind  : (Empty, Scalar, Array_Element, Array_Name);
   Invar_Name  : Unbounded_String;   -- empty when Invar_Kind = Empty
   Invar_Index : Natural;            -- used only when Invar_Kind = Array_Element
end record;
```

The node is classified as **immediate** — it executes the moment the parser
emits it, alongside `RUN`, `SORT`, `NEW`, `NAMES`, `SYSTEM`, `HELP`.

## 3. Semantics

### 3.1 Inputs to the operation

- The current data table (column-store).
- The active BY-variable list, retrieved via `SData_Core.Table.By_Var_Name(I)`.
  Possibly empty.
- The active `SELECT` filter, possibly inactive.
- The parsed spec vector.

### 3.2 Group identification

A *group* is a maximal run of consecutive rows — in the logical view, after the
`SELECT` filter — whose BY-variable values are all identical. With no active
`BY`, the entire filtered table is one group.

**No auto-sort.** Groups are identified by a single forward pass, matching the
existing `RUN` semantics. If the same BY-key value appears in two non-adjacent
runs, those runs produce two separate output rows.

### 3.3 Per-group aggregation

For each group, in physical row order:

1. For each spec, accumulate the state appropriate to that function:
   - **Scalar input**: one accumulator.
   - **Array input** of length k: k accumulators, one per element.
2. At end of group, finalize each accumulator to produce one value
   (scalar input) or k values (array input).
3. `N()` with no argument: the accumulator is simply the group row count.

Missing-value handling follows existing aggregate-function semantics: missings
are skipped during accumulation; if no non-missing values are seen, the result
is missing. `N` always returns an integer count (possibly zero).

### 3.4 Output table construction

A fresh table is built with this schema, in this order:

1. The active BY variables (each preserved, one row per group with the group's
   defining values).
2. Each outvar spec, in the order listed on the command. Scalar specs
   contribute one column; array specs contribute k contiguous columns
   registered as a subscripted array per ADR-041.

The fresh table replaces the current in-memory table. Subscripted-column
registration is refreshed via `Register_Subscripted_Columns`. The column-cursor
cache is invalidated.

### 3.5 Empty input

If the filtered input has zero rows, the output table is created with the
correct schema and zero rows. No warnings.

### 3.6 Post-execution side effects

Applied in this order, after the new table is committed:

1. **If `SAVE` is pending**: flush the new table via `Execute_OUTPUT_Table`,
   then clear the pending SAVE. Mirrors the VANDALIZE pattern (ADR-042).
2. **Clear the active `SELECT` filter.** Its expression may reference columns
   that no longer exist.
3. **Clear the active BY-variable list.** The grouping has been "consumed";
   subsequent operations are ungrouped unless the user issues a new `BY`.
4. The deferred-program buffer is already empty by precondition (see §5).
5. `Filter_Map` and column-cursor cache state are invalidated.

### 3.7 Determinism & cost

- Single forward scan: O(N × S) where N is filtered row count and S is the
  sum of spec sizes (scalar = 1, array = k).
- `MEDIAN` buffers values for the duration of one group, matching the existing
  per-expression MEDIAN behavior. No new memory exposure beyond what
  `MEDIAN()` already implies.
- The new table is built incrementally using existing `Table` append paths, so
  SQLite spill engages automatically when the configured limit is exceeded.

## 4. Type handling

### 4.1 Function-input type matrix

Existing aggregate functions accept input types as follows:

| Function | Numeric | Character |
|---|---|---|
| `SUM`, `MEAN`, `STD`, `VAR`, `MIN`, `MAX`, `GMEAN`, `HMEAN`, `MEDIAN` | yes | no |
| `N` | yes | yes |
| `NMISS` | yes | yes |

Future additions (e.g., `MODE`) may extend the character-input set.

### 4.2 Dispatch metadata refactor

To let AGGREGATE perform its pre-execution type check without hard-coding the
matrix, the aggregate dispatch table is widened from
`name → handler` to:

```
type Aggregate_Metadata is record
   Handler            : Aggregate_Handler_Access;
   Accepts_Numeric    : Boolean;
   Accepts_Character  : Boolean;
end record;
```

`SData_Core.Evaluator.Aggregate_Fns.Register` is updated to insert the
appropriate flags for each registered function. A new public accessor
`function Lookup (Name : String) return Aggregate_Metadata` exposes the entry
to AGGREGATE without changing the function-call evaluator path (which still
needs only the handler, retrieved via the same accessor or the existing
internal map).

Future aggregate functions register with the flags that suit them; no AGGREGATE
change is needed when MODE (or any successor) lands.

### 4.3 Outvar `$`-suffix rule

The outvar's `$`-suffix must match the function's return type given the input
type. Concretely:

- `N` always returns integer → outvar must not end in `$`.
- `NMISS` always returns integer → outvar must not end in `$`.
- For all other current aggregates: input is numeric, output is numeric → outvar
  must not end in `$`.
- When future character-returning aggregates (e.g., a character `MODE`) are
  added, the outvar must end in `$` if and only if the function's return type
  on the given input is character.

## 5. Error handling

All AGGREGATE errors abort the command **before** any side effect. No partial
table mutation, no SAVE flush, no SELECT/BY clearing on failure. On success,
errors during the SAVE flush behave the same as any other `Execute_OUTPUT_Table`
failure: the in-memory replacement has already happened and is not rolled back
(matches VANDALIZE today). All errors use the existing `Execute_Record_Error`
path; ERR/ERL are populated for downstream `IF` tests.

### 5.1 Error catalog

| # | Condition | Message | Phase |
|---|---|---|---|
| 1 | Empty spec list | `AGGREGATE: at least one outvar spec required` | parse |
| 2 | Unknown function name | `AGGREGATE: '<name>' is not a registered aggregate function` | parse |
| 3 | Function other than `N` invoked with no argument | `AGGREGATE: function '<name>' requires an argument` | parse |
| 4 | Unknown invar (not a column, array, or array element) | `AGGREGATE: unknown variable '<name>'` | pre-exec |
| 5 | Array element subscript out of range | `AGGREGATE: subscript <i> out of range for array '<name>' (1..<k>)` | pre-exec |
| 6 | Function does not accept the input column's type | `AGGREGATE: function '<fn>' does not accept input of type <T>` | pre-exec |
| 7 | Outvar `$`-suffix disagrees with function return type | `AGGREGATE: outvar '<name>' suffix mismatch — function '<fn>' on input '<invar>' returns <type>` | pre-exec |
| 8 | `<outvar>` collides with an active BY variable | `AGGREGATE: outvar '<name>' collides with active BY variable` | pre-exec |
| 9 | Two specs share the same outvar name | `AGGREGATE: duplicate outvar name '<name>'` | parse |
| 10 | Deferred program buffer non-empty | `AGGREGATE: pending program statements exist; issue RUN or NEW first` | pre-exec |
| 11 | SAVE flush failure | `AGGREGATE: SAVE flush failed: <inner message>` | post-exec |

### 5.2 Warnings

| # | Condition | Message |
|---|---|---|
| W1 | Outvar pre-exists with different bounds/shape (array→array with different k, scalar→array, or array→scalar) | `AGGREGATE: resizing existing variable '<name>' (<old shape> → <new shape>)` |

Pre-existence with the same shape requires no warning.

### 5.3 Pre-execution validation order

Inside `Execute_AGGREGATE`, after the parser has produced a syntactically valid
spec vector, validation proceeds in the order: 4 → 5 → 6 → 7 → 8 → 10. Errors
report only the first failing spec.

## 6. Examples

### 6.1 Whole-table summary (no BY)

```
USE "sales.csv"
AGGREGATE total = SUM(amount)  mean_amt = MEAN(amount)  n_recs = N()
DISPLAY
```

Output: one row, three columns `total`, `mean_amt`, `n_recs`.

### 6.2 Per-group summary with SAVE

```
USE "survey.csv"
SORT state$ region$
BY state$ region$
SAVE "summary.csv"
AGGREGATE pop = SUM(population)  med_income = MEDIAN(income)  n = N()
```

Output table (in memory and on disk): `state$`, `region$`, `pop`,
`med_income`, `n`. The pending SAVE is cleared by AGGREGATE; the BY list is
cleared too.

### 6.3 Array input

```
USE "scores.csv"   # columns score(1)..score(10)
BY student_id
AGGREGATE mscore = MEAN(score)  hi_score = MAX(score)
```

Output columns: `student_id`, `mscore(1)..mscore(10)`,
`hi_score(1)..hi_score(10)`. One row per student.

### 6.4 Mixing array, array element, and scalar

```
BY group_id
AGGREGATE m_all = MEAN(x)  m_first = MEAN(x(1))  total_y = SUM(y)
```

Output columns: `group_id`, `m_all(1)..m_all(k)`, `m_first`, `total_y`.

### 6.5 SELECT respected

```
USE "transactions.csv"
SELECT amount > 0
BY customer_id
AGGREGATE n_pos = N()  pos_total = SUM(amount)
```

Only positive-amount rows contribute. SELECT is cleared post-AGGREGATE.

### 6.6 Errors

```
BY region$
AGGREGATE region$ = MIN(temp)
# AGGREGATE: outvar 'region$' collides with active BY variable
```

```
BY region$
LET hot = temp > 30
AGGREGATE n = N()
# AGGREGATE: pending program statements exist; issue RUN or NEW first
```

## 7. Implementation footprint

### 7.1 sdata-core

| File | Change |
|---|---|
| `src/sdata_core-evaluator-aggregate_fns.ads` | Add the `Aggregate_Metadata` record type and public `Lookup` accessor. |
| `src/sdata_core-evaluator-aggregate_fns.adb` | Change the internal dispatch map's value type to `Aggregate_Metadata`. Update `Register` to pass the flags: N and NMISS → `(True, True)`; all others → `(True, False)`. |
| `src/sdata_core-commands.ads` | Add public `Aggregate_Spec` record, `Aggregate_Spec_Vectors` instantiation, and `Execute_AGGREGATE (Specs : Aggregate_Spec_Vectors.Vector)` procedure declaration. |
| `src/sdata_core-commands.adb` | Implement `Execute_AGGREGATE`: validate, group-scan, accumulate, build the output table, swap, optional SAVE flush, clear SELECT and BY. |

### 7.2 sdata

| File | Change |
|---|---|
| `src/sdata-ast.ads` | Add `Stmt_AGGREGATE` to `Statement_Kind` and associated payload. |
| `src/sdata-ast.adb` | Pretty-print / finalize support for the new node. |
| `src/sdata-parser.ads/adb` | Add `Parse_AGGREGATE`. Builds the `Aggregate_Spec_Vectors.Vector`. Catches parse-time errors #1, #2, #3, #9. |
| `src/sdata-interpreter.adb` | Add `AGGREGATE` to the immediate-command dispatch. Pre-exec program-buffer check (error #10). Dispatch handler calls `SData_Core.Commands.Execute_AGGREGATE`. Update the three-tier execution comment block. |
| `src/sdata-help.adb` | New `HELP AGGREGATE` topic. |
| `src/sdata-lexer.adb` | No change expected; `AGGREGATE` parses as an identifier on the existing path. Confirm during implementation. |

### 7.3 data-vandal

No required changes. `Execute_AGGREGATE` is available for future use but no
current data-vandal feature needs it.

### 7.4 Public-API impact

- Additive changes to `SData_Core.Commands`: new types and a new procedure. No
  existing signatures change.
- `SData_Core.Evaluator.Aggregate_Fns`: the dispatch table's internal value
  type changes, but the public handler signature is unchanged. The new
  `Lookup` accessor is additive.
- **sdata-core version bump: patch** (per ADR-043 — purely additive, no
  breaking signature changes). A patch bump satisfies the existing
  `sdata_core = "^0.1.0"` constraint in sdata's `alire.toml`, so no consumer
  constraint update is needed.

### 7.5 Memory & spill

- Per-group accumulator state: O(spec count × array length). Bounded and small
  for non-MEDIAN specs.
- MEDIAN buffering: bounded to one group at a time; matches existing
  `MEDIAN()` exposure.
- Output table grows via existing `Table` append paths; SQLite spill engages
  automatically when configured.

### 7.6 Build & validation

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && make check
cd ~/Develop/data-vandal && make check
```

All three must succeed before commit.

## 8. Testing strategy

### 8.1 Integration tests (sdata `tests/*.cmd`)

New scripts (with paired expected-output files in the existing harness format).
Integration suite grows from 140 → 158.

| File | Scenario |
|---|---|
| `aggregate_basic.cmd` | Whole-table summary, no BY |
| `aggregate_by_single.cmd` | Single-BY-var grouping |
| `aggregate_by_multi.cmd` | Multi-BY-var grouping |
| `aggregate_by_consecutive_runs.cmd` | Unsorted input, same BY value in two non-adjacent runs |
| `aggregate_array_input.cmd` | Array input → array output |
| `aggregate_array_element.cmd` | Mixed scalar / array-element / array specs |
| `aggregate_array_resize_warn.cmd` | Pre-existing array outvar with different bounds → warning |
| `aggregate_no_arg_n.cmd` | `N()` with no argument |
| `aggregate_select_active.cmd` | SELECT respected, then cleared post-AGGREGATE |
| `aggregate_save_flush.cmd` | SAVE flushed and cleared by AGGREGATE |
| `aggregate_by_cleared.cmd` | Active BY cleared post-AGGREGATE |
| `aggregate_character_min_max.cmd` | Error: `MIN(s$)` → type-mismatch |
| `aggregate_nmiss_no_arg.cmd` | Error: `NMISS()` requires an argument |
| `aggregate_by_collision.cmd` | Error: outvar name = active BY var |
| `aggregate_buffer_nonempty.cmd` | Error: pending deferred statements |
| `aggregate_empty_input.cmd` | Empty filtered input → empty output |
| `aggregate_unknown_fn.cmd` | Error: not a registered aggregate |
| `aggregate_unknown_invar.cmd` | Error: unknown column |

### 8.2 Unit tests

- **sdata-core in-crate driver (`tests/run-tests.sh`)**: a small driver
  exercising `Aggregate_Fns.Lookup` to confirm metadata is populated correctly
  for every registered function. Sanity gate per Beck B1.
- **sdata (`tests/sdata_unit_test.adb`)**: ~6 parser-construction cases
  covering scalar specs, array specs, array-element specs, no-arg `N()`,
  duplicate-outvar detection, and unknown-function detection.

## 9. Documentation updates

| Document | Change |
|---|---|
| `doc/design.odt` (regenerate `doc/design.txt`) | New section under "Commands" describing AGGREGATE: syntax, semantics, BY/SELECT/SAVE interaction, function set, array behavior, error summary. Section 7.x adds a note that aggregate functions accept character input only if their dispatch metadata says so (current set: N, NMISS). |
| `man/man1/sdata.1` | New `.TP`/`.B AGGREGATE` block under "Immediate commands". Brief syntax line and one-paragraph semantics summary. Cross-references to BY, SAVE, SELECT entries. |
| `doc/adrs.md` | A new ADR (ADR-044) will be added **at implementation time** capturing the four non-obvious decisions: active BY only, no auto-sort, write-and-clear SAVE, clear BY post-AGGREGATE. |
| `doc/architecture.md` | One-line update in the shared-commands list to mention `Execute_AGGREGATE`. |
| `src/sdata-help.adb` | `HELP AGGREGATE` topic: syntax, behavior, pointer to man page. |
| `CLAUDE.md` (sdata) | One-line addition to the immediate-command list. |
| `README.md` (sdata) | Optional: bullet under feature highlights. |

## 10. Versioning

After implementation:

- `cd ~/Develop/sdata-core && # bump alire.toml patch`, tag `vX.Y.Z+1`.
- `cd ~/Develop/sdata && scripts/bump-version.sh <next> "AGGREGATE command"`,
  tag `v<next>`.

The sdata-core constraint in sdata's `alire.toml` does not need updating; the
change is backward compatible.

## 11. Out of scope

The following are explicitly out of scope for this spec, listed to set
expectations:

- **Windowed / broadcast aggregates** (each input row receives its group's
  aggregate value without row reduction). A different command entirely; would
  be a follow-up if requested.
- **Expression arguments** (e.g., `total = SUM(price * qty)`). Considered and
  declined; users can compute the intermediate column with `LET` in a prior
  `RUN`.
- **`/BY=` override clause** on AGGREGATE. Considered and declined for
  consistency with the rest of the language.
- **Character `MIN`/`MAX`**. Will become available naturally if/when the
  underlying functions' dispatch metadata is updated to set
  `Accepts_Character := True`. Not part of this spec.
- **MODE function**. Mentioned by the user as a planned future addition; will
  be added as a separate change, registering with the appropriate dispatch
  flags. AGGREGATE will pick it up automatically.
