# APPEND — Fifth Merge Mode (Vertical Concatenation)

**Date:** 2026-05-30 (type-handling refinement added 2026-06-03)
**Status:** Approved (design phase) — implementation in progress
**Scope:** sdata interpreter only; one additive `Combine_Append` in `SData.Merge`

## Context

sdata's current four merge modes (positional, match, interleave, Cartesian join)
all align inputs by either row index or BY key. None of them performs the
simple "stack rows of A on top of rows of B" operation that SAS calls `SET`.

The original brainstorm for the merge feature noted SAS-style SET as one
candidate model but deferred it — `INTERLEAVE` covers the BY-sorted variant.
The user has since identified APPEND (the un-sorted concatenation) as
a natural fifth mode before the next round of language work.

## Goals

- Add `/APPEND` as a fifth `USE` merge mode: stack rows from each input in
  spec order with column-union semantics. No BY-sort.
- Reuse the existing merge infrastructure (Spec_Options, Build_Schema,
  Provenance, per-dataset KEEP/DROP/RENAME/IN) — no new top-level command,
  no new dispatch path.

## Non-Goals

- A new `APPEND` standalone command (SAS-pattern, separate from `USE`).
  Considered and rejected because it would duplicate Execute_USE's load /
  snapshot / project / combine machinery. The `/APPEND` slash-option on
  `USE` fits cleanly into the existing 4 → 5 modes pattern.
- Any change to APPEND's behavior when /BY= is also specified — that's
  what `/INTERLEAVE` is for; specifying both is a parse error.
- A "horizontal" APPEND variant. Vertical-only.

## Semantics

```
USE a, b [, c ...] /APPEND
```

- **Row count**: `sum(Row_Count(a), Row_Count(b), ...)` — every input row
  appears once in the output.
- **Row order**: input order. All rows of `a` come first, then all rows of
  `b`, then `c`, and so on. Within an input, rows preserve their original
  order.
- **Column set**: union of input columns, keyed by exact name
  (case-insensitive), taken in input order.
- **Type reconciliation** (refinement, 2026-06-03): unlike the other four
  modes — which emit each output row from a single input and therefore reuse
  the shared `Build_Schema` first-wins/last-wins rule — APPEND stacks values
  from *multiple* inputs into the *same* column, so a same-named column's
  output type must be reconciled across all contributors:
  - both numeric-family → promote: `Col_Integer` + `Col_Numeric` →
    `Col_Numeric`; identical types unchanged.
  - both `Col_String` → `Col_String`.
  - one numeric-family **and** one `Col_String` under the same exact name →
    **split into two columns**: numeric data stays in `name`; string data is
    routed to `name$` (append `$`; if a `name$` `Col_String` column already
    exists, merge the string values into it). This guarantees the numeric and
    character versions of a field never share a column, and the character
    column always carries the `$` suffix.
  Because every reader forces a `$` suffix onto any column it infers as
  character, and forces character type onto any `$`-suffixed name regardless
  of its data (CSV `csv.adb:302-305`; ODF/OOXML via `Apply_Dollar_Override`),
  a numeric `X` and a character `X$` already carry distinct names once read —
  so for file inputs the numeric/character separation happens structurally at
  read time and the split branch above is only reached for in-memory or
  computed columns that bypass the convention. It is kept as a defensive
  guarantee.
- **Per-row values**: for each output row from input `i`, each output column
  that input `i` supplies (under its reconciled or split destination name)
  carries that input's value; output columns input `i` does not supply are
  missing.
- **No type-based errors**: APPEND never fails on column type grounds — the
  split rule absorbs the only otherwise-incompatible case. There is no
  per-collision warning (a same-named column across inputs is the normal,
  intended way to stack a field).
- **Per-dataset options**: `KEEP=`, `DROP=`, `RENAME=()`, and `IN=` work
  identically to the other multi-dataset modes. RENAME applies first, then
  KEEP, then DROP. Both KEEP and DROP on the same dataset is an error.
- **Provenance / IN= variables**: bit `i` of the per-row provenance is set
  iff that row originated from input `i`. Since APPEND emits each row from
  exactly one input, exactly one bit is set per row. `IN=name` materializes
  as an Integer column whose value is 1 for rows from the requesting input
  and 0 otherwise — same semantics as the other modes.

## Mutual exclusivity

- `/APPEND` requires multiple datasets. Single-dataset USE with `/APPEND`
  is a parse error.
- `/APPEND` combined with `/BY=`, `/INTERLEAVE`, or `/JOIN` is a parse
  error. Use `/INTERLEAVE` if you want BY-sorted stacking.

## Lexical / grammar

No new keyword needed. `APPEND` is currently unused. It becomes a new
reserved keyword (consistent with the AS/IN/INTERLEAVE/JOIN policy decided
under issue C1).

```
whole_statement_option := ... | INTERLEAVE | JOIN | APPEND
```

Token addition mirrors Task 5's pattern: `Token_APPEND` in
`sdata-lexer.{ads,adb}` recognised unconditionally.

## AST changes

Extend `SData.AST.Merge_Mode` (currently `MM_Single | MM_Positional |
MM_Match | MM_Interleave | MM_Join`) with `MM_Append`.

No other AST changes needed — `Dataset_Spec_Vectors` already supports any
number of inputs.

## Parser changes

In `Parse_USE_Stmt`, the slash-option dispatch already handles
`Token_INTERLEAVE` and `Token_JOIN` as flags. Add `Token_APPEND` as a
parallel case. In mode determination:

| Datasets | /BY | /INTERLEAVE | /JOIN | /APPEND | Mode |
|----------|-----|-------------|-------|---------|------|
| 1 | – | – | – | – | MM_Single |
| ≥2 | – | – | – | – | MM_Positional |
| ≥2 | + | – | – | – | MM_Match |
| ≥2 | + | + | – | – | MM_Interleave |
| ≥2 | + | – | + | – | MM_Join |
| ≥2 | – | – | – | + | MM_Append |

Validation errors (mode mutex):
- `/APPEND` with `/BY=`, `/INTERLEAVE`, or `/JOIN` → parse error
- `/APPEND` with one dataset → parse error
- The existing `/INTERLEAVE` + `/JOIN` mutex stays in place

## Executor (Execute_USE)

The existing multi-dataset orchestration handles per-spec load / snapshot /
project / sort. For `MM_Append`:

- Auto-sort is skipped — APPEND preserves input order. The sort step is
  currently gated by "Match | Interleave | Join"; add a `not Append`
  check (or restate as positive list).
- Dispatch to a new `SData.Merge.Combine_Append (Inputs, Provenance)`
  (no By_Vars parameter — append doesn't need them).
- Everything else (warnings, install, IN= column materialisation,
  snapshot cleanup) works unchanged.

## Schema reconciliation (`Build_Append_Schema`)

APPEND does **not** reuse the shared `Build_Schema` (which is first-wins on
type and last-wins on source). Instead it uses a dedicated pass that:

1. Walks inputs left→right; for each input column name (case-insensitive),
   look up the reconciled output column:
   - not yet present → add it with that input's type, and record a routing
     entry `(input_idx, src_name) → dest_name`.
   - present and the two types are both numeric-family → set the output type
     to the promotion (`Numeric` if either is `Numeric`, else `Integer`);
     route to the same `dest_name`.
   - present as numeric-family but this input's column is `Col_String` (or
     vice-versa) → apply the **split**: ensure a `dest = name & "$"`
     `Col_String` column exists (create if absent) and route this input's
     column there, leaving the numeric column under `name`.
   - both `Col_String` → route to the same `dest_name`.
2. Yields, per input, a map from its source column names to destination
   output column names. The value-copy loop below routes through this map
   rather than assuming `dest_name = src_name`.

Integer values flowing into a promoted `Col_Numeric` column are converted on
copy (an `Integer` `Value` is read and stored as `Numeric`).

## Combine_Append algorithm

The pseudocode below shows the no-split happy path for clarity; the real
implementation routes each source column through the `Build_Append_Schema`
destination map (so `Col_Out` is the *destination* name, not necessarily the
source name) and converts integer→numeric on promoted columns.

```ada
function Combine_Append
  (Inputs    : Table_Vectors.Vector;
   Warnings  : in out Warning_Vectors.Vector;
   Provenance : in out Provenance_Vectors.Vector)
   return SData.Transient_Table.Table
is
   Result  : SData.Transient_Table.Table;
   Routes  : Route_Map;  --  (input_idx, src_name) -> dest_name, from below
begin
   Build_Append_Schema (Result, Routes, Inputs);  --  promotion + $-split
   for I in 1 .. Natural (Inputs.Length) loop
      declare
         T : constant Table_Access := Inputs (I);
         N : constant Natural :=
                SData.Transient_Table.Row_Count (T.all);
      begin
         for R in 1 .. N loop
            Result.Add_Row;
            declare
               R_Out : constant Positive :=
                  SData.Transient_Table.Row_Count (Result);
            begin
               --  Every output cell defaults to missing; then route each
               --  source column of input T to its destination column.
               for C in 1 .. SData.Transient_Table.Column_Count (Result) loop
                  Result.Set_Value
                    (R_Out,
                     SData.Transient_Table.Column_Name (Result, C),
                     (Kind => SData_Core.Values.Val_Missing));
               end loop;
               for SC in 1 .. SData.Transient_Table.Column_Count (T.all) loop
                  declare
                     Src  : constant String :=
                        SData.Transient_Table.Column_Name (T.all, SC);
                     Dest : constant String := Routes.Dest (I, Src);
                     V    : SData_Core.Values.Value := T.Get_Value (R, Src);
                  begin
                     --  Integer -> Numeric on a promoted destination column.
                     if SData.Transient_Table.Get_Column_Type (Result, Dest)
                          = SData_Core.Table.Col_Numeric
                        and then V.Kind = SData_Core.Values.Val_Integer
                     then
                        V := Promote_To_Numeric (V);
                     end if;
                     Result.Set_Value (R_Out, Dest, V);
                  end;
               end loop;
            end;
            --  Provenance: exactly one bit set (input I)
            declare
               Mask : Row_Provenance;
            begin
               for J in 1 .. Natural (Inputs.Length) loop
                  Mask.Contributors.Append (J = I);
               end loop;
               Provenance.Append (Mask);
            end;
         end loop;
      end;
   end loop;
   return Result;
end Combine_Append;
```

Closer to ~70 lines with `Build_Append_Schema` and the routing/promotion
logic. The `Warnings` parameter is retained for signature uniformity with the
other combiners (the executor dispatch is mode-uniform) but APPEND emits no
warnings.

## Error handling

- Per-spec errors (file not found, KEEP+DROP conflict, RENAME duplicates,
  IN= name collision) → identical to other modes; the existing
  Execute_USE code handles them.
- `/APPEND` combined with `/BY=`, `/INTERLEAVE`, or `/JOIN` → parse error
  with message "/APPEND cannot be combined with /BY, /INTERLEAVE, or /JOIN".
- Single-dataset `/APPEND` → parse error "/APPEND requires multiple datasets".

## Documentation

- Man page: extend the merge-mode table in the USE section to include
  APPEND. One-paragraph description.
- `doc/specs/2026-05-27-merge-multi-output-design.md`: append a brief
  note that APPEND was added as a fifth mode (or leave it alone — the
  original spec is a snapshot, not a living document).
- `doc/architecture.md`: no change needed.

## Testing

### Integration tests

- `tests/use_merge_append_two.cmd` — two inputs with disjoint columns.
  A has columns ID,X with 2 rows; B has columns ID,Y with 2 rows.
  Expected output: 4 rows total. First two rows have X populated, Y
  missing; last two rows have Y populated, X missing. ID populated in
  all four rows.
- `tests/use_merge_append_three.cmd` — three inputs to verify multi-way
  works.
- `tests/use_merge_append_with_in.cmd` — `USE a (IN=fromA), b (IN=fromB)
  /APPEND`. Verify each row has exactly one of fromA/fromB set to 1.
- `tests/use_merge_append_per_ds_keep.cmd` — per-dataset KEEP=
  exercised on each input.
- `tests/use_merge_append_dollar_split.cmd` — input A has numeric column
  `VAL`; input B has character column `VAL$`. Confirm the output keeps both
  `VAL` (numeric, populated for A's rows, missing for B's) and `VAL$`
  (character, populated for B's rows, missing for A's). This is the normal
  read-time separation, verifying APPEND preserves it.
- `tests/use_merge_append_int_promote.cmd` — input A's `N` is integer-typed,
  input B's `N` is float-typed; confirm the merged `N` is numeric and A's
  integer values survive as numerics.
- `tests/use_merge_err_append_with_by.cmd` — `/APPEND /BY=k` → expected
  parse error.
- `tests/use_merge_err_append_single.cmd` — single-dataset `/APPEND` →
  expected parse error.
- `tests/use_merge_err_append_with_join.cmd` — `/APPEND /JOIN` → parse
  error.

### Unit tests (sdata_unit_test.adb)

- `CA-01` two-input disjoint columns: 4 output rows, correct column
  population.
- `CA-02` two-input overlapping columns: collision warning, last wins.
- `CA-03` three-input disjoint columns: 6 output rows.
- `CA-04` mismatched row counts: each input contributes its actual row
  count (no padding).
- `CA-05` provenance verification: each row's mask has exactly one bit set
  matching the contributing input index.
- `CA-06` integer/numeric promotion: input A column `N` is `Col_Integer`,
  input B column `N` is `Col_Numeric`; output `N` is `Col_Numeric` and A's
  values read back as numerics equal to the originals.
- `CA-07` numeric/string split: input A column `VAL` is numeric, input B has
  a same-base-name `Col_String` column reached under exact name `VAL` (an
  in-memory table constructed to bypass the `$` convention). Output has both
  `VAL` (numeric, A's rows populated / B's missing) and `VAL$` (string, B's
  rows populated / A's missing).
- `CA-08` split merge-into-existing: input A has numeric `VAL` and string
  `VAL$`; input B has a `Col_String` column under exact name `VAL`. The split
  routes B's `VAL` strings into the existing `VAL$` column rather than
  creating a second one.

Label combiner tests `CA-NN` for consistency with `CP/CM/CI/CJ-NN`.

## Open questions deferred to implementation

- Whether `APPEND` should be a contextual keyword or unconditional
  reserved word. **Reserved** by default per the C1 policy decision.
  Same as INTERLEAVE/JOIN.

## Spec self-review

- **Coverage:** semantics, type reconciliation (promotion + `$`-split),
  lexer, AST, parser, executor, combiner, error handling, tests all
  addressed.
- **Internal consistency:** mode-determination table covers all
  combinations; mutex rules consistent across spec; the no-type-error rule in
  Semantics matches the dropped Script_Error case in Error handling.
- **Scope:** small–moderate — ~70 lines of new Ada (combiner +
  `Build_Append_Schema`), ~9 integration tests, ~8 unit tests, 1 enum
  literal, 1 token. Single focused PR.
- **Ambiguity:** none expected; APPEND is a well-known operation and the
  semantics — including the numeric/character split keyed on the `$`
  convention — are tightly specified above.

## Revision history

- **2026-05-30** — Original spec (vertical concatenation, union/last-wins
  collision). Approved, execution deferred.
- **2026-06-03** — Type-handling refinement: same-named columns are
  type-reconciled across inputs (integer→numeric promotion; numeric-vs-string
  split into `name` / `name$`) via a dedicated `Build_Append_Schema` pass
  instead of the shared `Build_Schema`; per-collision warning dropped. APPEND
  still never raises on type grounds (the split absorbs the only otherwise
  incompatible case). Added unit tests CA-06…CA-08 and two integration tests.
  Status moved to implementation in progress.
