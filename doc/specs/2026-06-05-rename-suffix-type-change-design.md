# Design: Suffix-Driven Type Change on RENAME

**Date:** 2026-06-05
**Status:** Approved (brainstorming)
**Scope:** sdata + sdata-core

## Problem

In sdata, a variable's type is denoted by its name suffix: `$` = character
(string), `%` = integer, no suffix = floating point. This rule is applied when
importing a CSV (header suffix sets the column type) and when assigning via
`LET`/`SET` (the target name's suffix coerces the value). It is **not** applied
by `RENAME`.

Today `RENAME` — whether the standalone statement or the `rename=(...)` dataset
option on `USE`/`SAVE` — changes only a column's *name* and never its stored
type. `Rename_Column` (`sdata_core-table.adb`) and `Apply_Rename`
(`sdata-transient_table.adb`) both copy the existing column/entry and overwrite
only the `Name` field, leaving `Typ` untouched. As a result
`USE foo(rename=(x=x%))` produces a column literally named `X%` whose stored type
is still floating point — a name/type mismatch.

The desired behavior: the suffix should determine the type. A rename that adds,
removes, or changes a suffix should change the column's type and convert its
values accordingly.

This spec covers **option #1**, scoped to the **`USE`/`SAVE` `rename=()` option**
only: convert *within* the numeric family (float ↔ integer) and **reject** renames
that cross the numeric ↔ character boundary. Converting across that boundary
(string ↔ numeric) is explicitly out of scope and may be revisited after SData
1.0. The standalone `RENAME` statement stays name-only (see *Scope* and *Out of
Scope* for why).

## Rule

For each rename pair, derive the **target type** from the *new* name's suffix:

| New-name suffix | Target type     |
|-----------------|-----------------|
| `$`             | `Col_String`    |
| `%`             | `Col_Integer`   |
| none            | `Col_Numeric`   |

Compare the target type against the column's current stored `Typ`:

| From → To                       | Action                              |
|---------------------------------|-------------------------------------|
| same type                       | pure rename (current behavior)      |
| float ↔ integer                 | rename **and convert all values**   |
| numeric/integer ↔ string        | **error — abort the statement**     |

This enforces the rule already documented in `doc/design.txt` ("A numeric
variable may not be assigned a character variable name and vice versa"), which
was never implemented, and adds the within-numeric conversion the document is
silent on. No documented rule is reversed.

### Why target type is derived from the new suffix, not compared to the old

Post-import, a column's stored `Typ` always agrees with its name suffix:
CSV data scanning only ever infers `Col_Numeric` or `Col_String`
(`sdata_core-file_io-csv.adb:371`); `Col_Integer` arises *only* from an explicit
`%` header suffix; and string columns are the only ones whose name gets a suffix
auto-appended (`:390-395`). Therefore the column's authoritative source type is
its stored `Typ`, and a rename that keeps the suffix never triggers a
conversion. The rule reads target from the new suffix and source from stored
`Typ`.

## Conversion Semantics

Reuse the existing coercion rules — no new behavior is introduced:

- **float → integer:** truncate toward zero via `Float'Truncation`. Matches
  `LET x% = 3.7` → `3` (`sdata-interpreter-execute_assignment.adb:125`) and
  `Coerce_Value` (`sdata_core-table.adb:260`). **Truncation, not rounding.**
- **integer → float:** promote via `Float(Int_Val)`.
- **missing:** passes through unchanged.
- **special floats (±inf):** follow whatever `Coerce_Value` already does for
  numeric → integer; no new edge-case handling is added.

## Error Semantics

- A cross-boundary pair (numeric/integer ↔ string, either direction) is a hard
  error that **aborts the entire RENAME** with a clear message, e.g.
  `RENAME: cannot change X (numeric) to character name X$`.
- **All-or-nothing:** a multi-pair rename is evaluated as a set. If *any* pair is
  a cross-boundary error, **no** pair is applied. `Apply_Rename` already has a
  pre-apply validation pass (duplicate source, duplicate target, collision);
  the boundary check is added there as an additional validation loop, *before*
  any entry is mutated, so a failure aborts with nothing applied.
- **Validation ordering:** the boundary check runs **after** the existing
  duplicate-source / duplicate-target / collision checks, so those error
  messages (and their tests) continue to fire first when applicable.

## Scope — USE/SAVE `rename=()` only

Only the transient-table path is changed:

1. `USE foo(rename=(...))` → `Apply_Rename` (`sdata-interpreter-execute_declarative.adb:267`).
2. `SAVE "f" (rename=(...))` → `Apply_Rename` (`sdata-interpreter.adb:1045`).

Both funnel through `SData.Transient_Table.Apply_Rename`, which operates on a
fully in-memory transient table — no disk-spill interaction.

### Discovered gap: single-dataset USE / single-target SAVE ignored paren options

During implementation, integration testing revealed that per-dataset/per-target
paren options (`rename=`/`keep=`/`drop=`) were applied **only** in the
multi-dataset `USE` and multi-target `SAVE` code paths. A *single*-dataset
`USE "f" (...)` (the `MM_Single` branch in
`sdata-interpreter-execute_declarative.adb`) and a *single*-target `SAVE "f" (...)`
(the legacy pending-save path: `Execute_SAVE` registers a pending whole-table
write that `Flush_Pending_Save` performs in sdata-core) **silently ignored**
those options entirely. This is pre-existing behavior, independent of the retype
change — but it means the headline case `USE foo(rename=(x=x%))` (a single
dataset) never reached `Apply_Rename`.

This spec is therefore extended to make the single paths honour their paren
options (rename, keep, and drop — for consistency), reusing the same
`Apply_Rename`/`Apply_Keep`/`Apply_Drop` + `Install_To_Current` machinery:

- **Single USE (`MM_Single`):** after `Execute_USE`, if the dataset spec
  (`Stmt.Dataset_List.First_Element.Opts`) carries options, snapshot the global
  table, apply rename → keep → drop (with the same KEEP/DROP-exclusivity check),
  and `Install_To_Current`. This runs **before** the `Input_File_Columns` cache
  is populated so the cache reflects the post-projection schema.
- **Single SAVE:** when the single target carries options
  (`Stmt.Save_List.First_Element.Opts`), route it through the existing
  multi-target **registration** path instead of `Legacy_Execute_SAVE`. Per-record
  auto-flush (no explicit `WRITE`) populates the target buffer, and the
  multi-target flush projects rename → keep → drop (already including the retype)
  and writes. An optionless single SAVE stays on the legacy path unchanged, so
  existing single-SAVE behavior is untouched.

Because the multi-target SAVE flush and the USE snapshot path both call
`Apply_Rename`, the retype logic (and boundary rejection) applies uniformly
across single and multi forms with no additional code.

The standalone `RENAME` **statement** (`Rename_Column` on the global
`SData_Core.Table`) is **deliberately left name-only** and is out of scope here:
the global table spills row-segments to SQLite typed by `Col.Typ`, so retyping a
materialized column would have to rewrite the on-disk store as well. Deferred to
a post-1.0 revisit. See *Out of Scope*.

## Implementation Shape

Two changes, plus docs:

1. **Shared value-level helper** in sdata-core:
   `SData_Core.Values.Convert_Value (V : Value; Target : Value_Kind) return Value`
   (+ `Conversion_Error : exception`). Encapsulates the truncate / promote /
   missing-passthrough rules above. Raises `Conversion_Error` if a string is
   involved on either side (string value with a numeric target, or string target
   with a numeric value) — i.e. the numeric ↔ character boundary. The existing
   `SData_Core.Table.Coerce_Value` is refactored to delegate its two numeric
   promotions (integer→numeric, numeric→integer) to `Convert_Value`, so the
   truncation rule lives in exactly one place. Behavior is unchanged and guarded
   by the existing `csv_unit_test` / `sdata_unit_test` suites.

2. **`Apply_Rename`** (transient `Col_Entry`, which has its own `Typ` field and
   per-column value vectors in `T.Data`) gains:
   - two private local helpers: `Type_From_Name (Name) return Column_Type`
     (suffix → type, mirroring the evaluator's `Get_Expected_Kind`) and
     `Kind_Of (Column_Type) return Value_Kind`;
   - a **boundary-validation loop** (after the existing checks): for each pair,
     compare `Type_From_Name(new)` against the matched column's current `Typ`;
     if exactly one side is `Col_String`, raise `Rename_Error` with a clear
     message — nothing has been mutated yet (all-or-nothing);
   - in the existing apply loop, when `Type_From_Name(new) /= Entry_Val.Typ`,
     convert every value in `T.Data (I)` via
     `Convert_Value(v, Kind_Of(target))` and set `Entry_Val.Typ := target`
     **in addition to** `Entry_Val.Name := P.New_Name`.

Because `Install_To_Current` copies each transient column's `Typ`
(`sdata-transient_table.adb:173`) and values (`:182`), and the SAVE writer reads
the transient `Typ`/values directly, converting both fields keeps the transient
table internally consistent for both downstream consumers.

### Behavior note (new)

Under this rule, renaming a string column to a name **without** `$` (e.g.
`rename=(NAME$=LABEL)`) is a numeric ↔ character boundary crossing and is now an
**error**; the string column must be renamed to a `$`-suffixed name
(`NAME$=LABEL$`). No existing test exercises a suffix-changing `rename=()`, so
none break, but this is a user-visible behavior change to document.

## Testing

Integration (`tests/*.cmd`), all via `USE`/`SAVE` `rename=()`:

- float → integer via `rename=(X=Y%)` truncates values (e.g. `3.7` → `3`).
- integer → float via `rename=(N%=M)` promotes values.
- cross-boundary numeric → character `rename=(X=Y$)` errors, applies nothing.
- cross-boundary character → numeric `rename=(S$=T)` errors, applies nothing.
- plain rename (suffix unchanged, `rename=(X=Y)`) does **not** convert —
  regression guard.
- multi-pair rename where one pair is cross-boundary: nothing applied
  (all-or-nothing guard).

Unit (`sdata_unit_test`):

- the shared `Convert_Value` helper for each direction incl. missing and the
  boundary-crossing `Conversion_Error`.

## Documentation

- `doc/design.txt` / `doc/design.odt`: add a sentence clarifying that
  float ↔ integer renames convert values (truncating toward zero for float →
  integer) while numeric ↔ character renames are rejected.
- `man/man1/sdata.1`: note the same under the `USE`/`SAVE` `RENAME=` option.
- **ADR** (short): record that the `USE`/`SAVE` `rename=()` option now applies the
  suffix-determines-type rule for the numeric family (float ↔ integer convert,
  truncating toward zero) and enforces the previously-documented
  numeric ↔ character prohibition; that the standalone `RENAME` statement remains
  name-only because retyping a spill-capable global-table column is deferred; and
  that option #2 (string ↔ numeric conversion) is deferred past SData 1.0.

## Out of Scope

- **Standalone `RENAME` statement** retyping the global `SData_Core.Table`.
  Deferred — the global table spills to SQLite typed by `Col.Typ`, so a retype
  would have to rewrite the on-disk store. May be revisited post-1.0. `RENAME`
  stays name-only.
- String ↔ numeric conversion on rename (option #2). Deferred; may be revisited
  after SData 1.0.
- Any change to CSV import type inference or `LET`/`SET` coercion.
