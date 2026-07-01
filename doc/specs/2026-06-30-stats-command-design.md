# STATS command — design spec

- **Date:** 2026-06-30
- **Status:** Approved (design); pending implementation plan
- **Feature slug:** stats-command
- **Author:** John L. Ries (with Claude Code, SSD `/ssd feature` brainstorming pass)
- **Related ADRs:** ADR-046 (AGGREGATE), ADR-047 (TRANSPOSE); this feature adds **ADR-048**

## 1. Summary

`STATS` is SData's analogue to SAS `PROC MEANS`: an **immediate** command that
computes summary statistics for the numeric variables of the current table,
prints them as a report, and replaces the in-memory table with the resulting
statistics table.

`STATS` reuses the existing registered aggregate-function machinery (the
`Dispatch_Table` of `Handle_*` aggregate handlers and the `Aggregate_Metadata`
side-table introduced by ADR-046) for **all** computation, and it follows the
same **build-and-swap** output model as AGGREGATE and TRANSPOSE. Functionally it
is a "transposed AGGREGATE": where AGGREGATE produces one row per BY group with
one column per `outvar=fn(invar)` clause, STATS produces one row per
(BY group × analysis variable) with one column per requested statistic.

## 2. Syntax

```
STATS [var1 var2 ...] [/STATS=stat1 stat2 ...] [/NOPRINT]
```

### 2.1 Bare variable list

The analysis variables. **Omitted ⇒ all numeric columns** of the current table,
in column order, **excluding the active BY variables**.

A variable reference may be:

- a **scalar** numeric (or, when explicitly named, character — see §4.3) column;
- a **whole array** base name `x`, which expands to one analysis variable per
  element `x(1) … x(k)`;
- an **array element** such as `x(2)`.

### 2.2 `/STATS=` option

A space-separated list of registered aggregate-function names. **Omitted ⇒
`N MIN MEAN MAX STD`** (in that order). The order given is the column order of
the stat columns in the result. The allowed set is the full aggregate registry:

```
N  NMISS  SUM  MEAN  STD  VAR  MIN  MAX  GMEAN  HMEAN  MEDIAN
```

A name that is not a registered aggregate is rejected at validation time.

### 2.3 `/NOPRINT` option

Suppress the printed report. The in-memory table is **still replaced**, and a
pending SAVE is **still written**. (Because the replacement always happens,
`/NOPRINT` is always meaningful — there is no "did nothing" degenerate case.)

### 2.4 Option grammar

`/STATS=` and `/NOPRINT` are USE/TRANSPOSE-style slash-options: case-insensitive,
order-independent, and each may appear **at most once** (a duplicate is an error).
The bare variable list, if present, precedes the slash-options.

## 3. Result table schema

The result table — which is **both** the stored (swapped-in / SAVEd) table and
the source of the printed report — has this schema:

```
[ active BY vars... ]  +  _NAME_$  +  [ one column per requested statistic ]
```

- **BY variables:** the active BY columns, repeated per group (as in AGGREGATE).
- **`_NAME_$`:** a character column holding the analysis-variable name, e.g.
  `"x"`, `"y(2)"`. (Reuses TRANSPOSE's `_NAME_$` convention. **No `/NAME=`
  override in v1** — deliberately omitted as YAGNI; the TRANSPOSE precedent
  exists if a future version wants it.)
- **Stat columns:** named verbatim by the aggregate-function name (`N`, `MIN`,
  `MEAN`, `MAX`, `STD`, …), in the order requested. `N` and `NMISS` are
  **integer** columns; every other statistic is a **float** column.

**Row ordering:** one row per (BY group × analysis variable), ordered by group
first, then by the variable order from §2.1.

## 4. Execution model

`STATS` is an **immediate** command (tier alongside AGGREGATE, TRANSPOSE, SORT).
All validation precedes any side effect (the ADR-046 / ADR-047 "all errors abort
before any side effect" discipline): on any validation failure the in-memory
table, the pending SAVE, and the active SELECT/BY are left untouched.

### 4.1 Pending-deferred guard

`STATS` refuses to run while un-run deferred statements are pending
(`Pending_Deferred > 0`), the same guard AGGREGATE (error #10/#11 lineage) and
TRANSPOSE (#12) use. This is **new error #13**. Message directs the user to issue
`RUN` or `NEW` first.

### 4.2 Validation

1. Every name in `/STATS` must be a registered aggregate (`Evaluator.Is_Aggregate`);
   otherwise error.
2. Resolve the analysis-variable list:
   - **Explicit list:** each referenced scalar / array / array element must exist;
     a whole-array name expands to its elements.
   - **Default (no list):** every **numeric** scalar column plus every **numeric**
     array element, in table column order, **excluding active BY variables**.
3. **Type rule** (reuses `Aggregate_Metadata.Accepts_Numeric / Accepts_Character`):
   a numeric variable is valid for all stats. A **character** variable is valid
   **only if every requested statistic `Accepts_Character`** — i.e. only when the
   requested set is a subset of `{N, NMISS}`. Requesting `MEAN`/`STD`/`MIN`/… on a
   character variable is an error. (In the default path, character columns are
   simply never auto-selected, so this only arises for an explicitly named
   character variable.)
4. The resolved analysis-variable set must be non-empty; an empty selection
   (e.g. `STATS` on a table with no numeric columns) is an error.

### 4.3 Computation

A single BY-group scan over the current table (the whole table is one group when
no BY is active), **respecting the active SELECT filter**. For each group, for
each analysis variable, each requested statistic is computed by the corresponding
aggregate handler (`Handle_*` via the dispatch table), **ignoring missing
values**. Per the aggregate contract, a statistic over no non-missing values
yields a missing value (and `N`/`NMISS` yield their counts).

### 4.4 Commit (build-and-swap) and clear

On success the freshly built result table replaces the in-memory table via the
standard build-and-swap path
(`Initialize_Output_Table → Add_Output_* → Commit_Output_Table →
Register_Subscripted_Columns → Execute_Commit_Step`). If a SAVE is pending, the
result is written to it. Then the active **SELECT and BY are cleared** (identical
to AGGREGATE/TRANSPOSE post-conditions).

### 4.5 Print

Unless `/NOPRINT` was given, the new in-memory table is rendered to console via
the existing **DISPLAY** table-rendering path (pager-aware console output). No
bespoke report formatter is introduced — the printed report is the result table
rendered the same way `DISPLAY` renders Data Table records.

## 5. Edge cases

- **Empty or fully-filtered table:** behavior **matches AGGREGATE's empty-input
  handling** (an implementation-verification item — confirm against
  `Execute_AGGREGATE` during the build, do not guess). The expected behavior is:
  with no active BY, one row per analysis variable with `N = 0` (and `NMISS = 0`)
  and missing values for the value statistics; with an active BY and no rows,
  zero output rows. If AGGREGATE's actual behavior differs, STATS matches
  AGGREGATE for consistency and the spec is corrected.
- **Whole-array name** in the variable list expands to one analysis variable
  (one output row per group) per array element.
- **Duplicate variable** in the explicit list is processed as given (it yields
  duplicate rows); no de-duplication is performed.

## 6. Implementation footprint

### 6.1 sdata-core (all additive)

In `SData_Core.Commands`:

- A `Stats_Options` record (and supporting variable-reference / statistic-name
  list types) carrying the parsed variable list, statistic list, and `NOPRINT`
  flag.
- `procedure Execute_STATS (Options : Stats_Options)`.
- **Approach A (chosen):** factor the BY-group iteration currently inside
  `Execute_AGGREGATE` into a **shared private helper** that both
  `Execute_AGGREGATE` and `Execute_STATS` call, eliminating scan duplication.
  This is a focused, well-scoped refactor of working code (an "improve the code
  you're working in" change), kept behaviorally identical for AGGREGATE — its
  integration tests must stay byte-for-byte green.

Reuse, do not reimplement: the aggregate `Dispatch_Table` handlers, the
`Aggregate_Metadata` side-table (`Is_Aggregate` / `Lookup`), and the
build-and-swap output helpers.

**Versioning:** purely additive to the public surface → **patch bump**
(sdata-core `0.1.18 → 0.1.19`). The existing `^0.1.16` consumer floor still
admits it; **no consumer-constraint change**. **data-vandal is untouched** — it
inherits the additive API, does not call `Execute_STATS`, and must remain green
(`cd ~/Develop/data-vandal && make check`).

### 6.2 sdata

- **Lexer:** `Token_STATS` + `reserved_keywords` sync. **STATS becomes a reserved
  keyword.**
- **AST:** `Stmt_STATS` node (variable-reference list + statistic-name list +
  `NOPRINT` boolean).
- **Parser:** `Parse_STATS` — a bare variable list followed by USE-style
  slash-options (`/STATS=`, `/NOPRINT`).
- **Dispatch:** immediate execution; pending-deferred guard (error #13);
  delegate to `Commands.Execute_STATS`.
- **HELP:** `Help_STATS`; regenerate the `HELP /ALL` snapshot
  (`tests/expected/help_all.out`) and any options/`help_all` expected output the
  new command line affects.

### 6.3 Documentation (the mandatory trio + records)

Per CLAUDE.md "Keeping the user-facing surface in sync":

- **Built-in HELP** — `src/sdata-help.adb` (`Help_STATS`) + snapshot regen.
- **Man page** — `man/man1/sdata.1` (LANGUAGE OVERVIEW command list + entry).
- **Design doc** — `doc/design.md` (command-reference table entry, modeled on the
  AGGREGATE/TRANSPOSE rows; cross-reference AGGREGATE).
- **ADR-048** — `doc/adrs.md` (STATS: transposed-AGGREGATE layout, always-replace
  + print-by-default/`/NOPRINT`, shared group-scan helper).
- **architecture.md** and the **CLAUDE.md** command list — mention STATS.

### 6.4 Tests

Integration `.cmd` tests under `tests/` (with `tests/expected/` fixtures):

- default statistics (`N MIN MEAN MAX STD`) over all numeric columns;
- explicit variable list;
- `/STATS=` with a custom set and order;
- `/NOPRINT` (table replaced, nothing printed) — paired with a follow-up DISPLAY
  to prove replacement happened;
- BY grouping (one row block per group);
- pending SAVE writes the stats table;
- active SELECT respected during the scan;
- character-variable error (a value stat on a `$` column);
- character variable accepted with `/STATS=N` (or `NMISS`);
- whole-array expansion (one row per element);
- empty-selection error (no numeric columns);
- pending-deferred guard (error #13).

Parser unit tests for `Parse_STATS` (bare list, `/STATS=`, `/NOPRINT`,
duplicate-option error, unknown-stat error).

### 6.5 sdata version

New command → **minor bump → sdata `0.12.0`** (via `scripts/bump-version.sh`),
then an annotated `v0.12.0` tag after merge.

## 7. Cross-crate gate

Because `Execute_STATS` lives in sdata-core, the mandatory three-way local gate
applies before any src-touching commit:

```
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata       && make check     # all integration tests green
cd ~/Develop/data-vandal && make check     # untouched, must stay green
```

## 8. Explicit non-goals (v1)

- No `/NAME=` override for the `_NAME_$` column.
- No custom stat-column renaming (stat columns are always the fn name).
- No percentiles / quantiles beyond `MEDIAN`, and no statistic that lacks a
  registered aggregate function.
- No report-only mode that preserves the working table — STATS **always**
  replaces it (per the approved output model).
