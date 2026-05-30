# APPEND — Fifth Merge Mode (Vertical Concatenation)

**Date:** 2026-05-30
**Status:** Approved (design phase) — execution deferred
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
- **Column set**: union of input columns, taken in input order (matches
  `Build_Schema` from the other combiners). Column-name collisions across
  inputs follow the same last-wins rule with one warning per collision.
- **Per-row values**: for each output row that came from input `i`, columns
  that exist in `i` carry that input's value; columns that exist only in
  other inputs are missing.
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

## Combine_Append algorithm

```ada
function Combine_Append
  (Inputs    : Table_Vectors.Vector;
   Warnings  : in out Warning_Vectors.Vector;
   Provenance : in out Provenance_Vectors.Vector)
   return SData.Transient_Table.Table
is
   Result  : SData.Transient_Table.Table;
   Sources : Source_Vectors.Vector;
begin
   Build_Schema (Result, Sources, Inputs, Warnings);
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
               for C in 1 .. Natural (Sources.Length) loop
                  declare
                     Col_Out : constant String :=
                        SData.Transient_Table.Column_Name (Result, C);
                     V : SData_Core.Values.Value;
                  begin
                     if SData.Transient_Table.Has_Column (T.all, Col_Out) then
                        V := T.Get_Value (R, Col_Out);
                     else
                        V := (Kind => SData_Core.Values.Val_Missing);
                     end if;
                     Result.Set_Value (R_Out, Col_Out, V);
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

About 35 lines including comments. Closely mirrors `Combine_Interleave`
minus the cursor/key machinery.

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

Label combiner tests `CA-NN` for consistency with `CP/CM/CI/CJ-NN`.

## Open questions deferred to implementation

- Whether `APPEND` should be a contextual keyword or unconditional
  reserved word. **Reserved** by default per the C1 policy decision.
  Same as INTERLEAVE/JOIN.

## Spec self-review

- **Coverage:** semantics, lexer, AST, parser, executor, combiner,
  error handling, tests all addressed.
- **Internal consistency:** mode-determination table covers all
  combinations; mutex rules consistent across spec.
- **Scope:** small — ~50 lines of new Ada, ~7 integration tests, ~5 unit
  tests, 1 enum literal, 1 token. Single focused PR.
- **Ambiguity:** none expected; APPEND is a well-known operation and the
  semantics are tightly specified above.
