# Design: SET/LET Storage-Class Redefinition Becomes a Hard Error (issue #56)

**Date:** 2026-07-24
**Issue:** [#56](https://github.com/jlries61/sdata/issues/56) — "SET on a loaded column silently drops it (verb-determined storage class, §3.5)"
**Status:** Approved (design), pending implementation plan
**Scope:** sdata-core (`SData_Core.Variables`) + sdata (docs, HELP, man page, tests, `alire.toml` floor); data-vandal inherits via sdata-core, verified by the two-consumer gate.

## 1. Problem

The assignment verb (`LET` vs `SET`) silently determines — and can silently change —
a variable's storage class:

- `SET x = ...` on an existing **loaded/permanent table column** demotes it to a
  temporary session variable, dropping it from the table, with only a stderr
  warning (`Warning: Column 'X' dropped from table and converted to session
  variable.`) and exit code 0.
- `LET x = ...` on an existing **temporary session variable** silently promotes it
  to permanent (a table column), again with no error.

The demotion direction is a genuine data-integrity footgun (same family as
issues #50–#52): a user who typed `SET` instead of `LET`, or who wanted a scratch
calculation under a name that happens to collide with a loaded column, silently
loses that column from the output with no actionable signal.

It also causes a real data-corruption bug, not just a surprising warning.
`Set_Temporary`'s call to `Table.Drop_Column` removes the column from
`Data_Table` and `Column_Order` (shifting every later column's index down by
one) but does not touch the parallel `PDV_Names`/`PDV_Vec`/`PDV_Index`
structures, which assume positional correspondence with table columns. Every
subsequent row's `Load_PDV_From_Table` then reads every column *after* the
demoted one into the wrong PDV slot, corrupting them for the rest of the RUN.
`Flush_PDV_To_Output` then re-emits the stale demoted name as an output column
(re-added under `Add_Output_Column`, using values from the now-corrupted PDV),
producing the malformed `SAVE` output reported in the issue. This mutation is
unique among schema changes in happening out-of-band, mid-record-loop, while
the PDV is in active use — `Execute_KEEP`/`Execute_DROP` also call
`Drop_Column`, but only from `Apply_Pending_Mods`, which runs after
`Commit_Output_Table` and before the next `Initialize_PDV`, so they never hit
a live PDV.

Separately, `design.md` contradicts itself: §3.5 "Redefinition Rules" states
"If permanent variable/array redefined by SET, it becomes temporary," while the
`SET` command-reference row (line 959) already claims "A SET statement that
attempts to write to a permanent variable will fail with an error message."
The two have never agreed.

## 2. Decision

**Prohibit both redefinition directions.** `LET` and `SET` each only operate on
a name already owned by their matching storage class (or a brand-new name);
attempting to redefine a name across storage classes raises `Script_Error`
(exit 1) instead of silently converting it. No new syntax, no `/TEMP`-style
modifier, and no other escape hatch is added.

- `SET x = ...` where `x` is an existing table column → hard error.
- `LET x = ...` where `x` is an existing genuine temporary variable → hard error.

To recompute a variable in place, use the verb that already owns it (`LET` for
a column, `SET` for a temp var). To deliberately convert a name's storage
class, use the existing explicit primitives, unchanged by this issue:

- Column → temp: `DROP x` (takes effect at the end of the next `RUN`, per
  existing `DROP` semantics — design.md line 807 already documents that a
  dropped variable "may be redefined with a LET or SET statement"), then
  `SET x = ...` after that `RUN` completes.
- Temp → column: `UNSET x` (immediate — deletes the temp symbol), then
  `LET x = ...` to create a fresh column.

This mirrors the array-assignment precedent already enforced in
`Execute_Array_Assignment` (`sdata-interpreter-execute_assignment.adb:20-26`),
which already raises `Script_Error` for `LET` on a temporary array element or
`SET` on a permanent/virtual array element. This fix brings scalars in line
with the rule arrays already follow.

**Rejected alternative:** keep implicit conversion but only make the demotion
direction (SET-on-column) an error while leaving LET-on-temp-var promotion as
silent, matching the issue's "minimum" suggestion literally. Rejected because
the promotion direction has the identical verb-decides-storage-class problem
in miniature (surprising, undocumented-as-a-feature-anywhere-except-one-test
behavior) and because symmetric prohibition is simpler to reason about and
document than an asymmetric rule that requires explaining why one direction is
fine and the other isn't.

**Rejected alternative:** add a new explicit conversion modifier (e.g.
`SET /TEMP x = ...`). Rejected as unnecessary — `DROP`+`SET` and `UNSET`+`LET`
already provide explicit, non-silent conversion paths using existing,
documented commands, and no test, doc passage, or example script anywhere in
the repository relies on the implicit verb-coupled conversion as an
intentional feature (the only test that exercises it,
`tests/variable_scoping.cmd` "Test 3: Promotion," treats it as the thing under
test, not a dependency of some other feature).

## 3. Mechanism

Both procedures live in `~/Develop/sdata-core/src/sdata_core-variables.adb`.

**`Set_Temporary` (SET handler, lines 45–63):** replace the
`Put_Line_Error` + `Drop_Column` demotion with a raise:

```
if SData_Core.Table.Has_Column (Upper_Name) then
   raise Script_Error with
     "SET cannot redefine permanent variable """ & Upper_Name
     & """; use LET to recompute it in place, or DROP it "
     & "(effective after the next RUN) to convert it to a "
     & "temporary variable";
end if;
```

**`Set_Permanent` (LET handler, lines 66–93):** replace the silent
`Temp_Symbols.Delete` promotion with a raise, guarded exactly the same way the
existing code already distinguishes a genuine temporary variable from a
held-permanent variable's carry-over shadow (`Reset_PDV_Non_Held` mirrors held
permanent variables' values into `Temp_Symbols` so they survive across
records — that is not a promotion candidate, just an ordinary update to an
already-permanent variable):

```
if Temp_Symbols.Contains (Upper_Name) and then not Is_Held (Upper_Name) then
   raise Script_Error with
     "LET cannot redefine temporary variable """ & Upper_Name
     & """; use SET to recompute it in place, or UNSET it to "
     & "convert it to a permanent variable";
end if;
```

Both raises use `SData_Core.Script_Error` (`sdata_core.ads:19`), visible
without an explicit `with` clause since `Variables` is a child package of
`SData_Core`. `Execute_Assignment`'s existing exception handling
(`sdata-interpreter-execute_assignment.adb:193-201`) already re-raises
`SData_Core.Script_Error`/`Script_Error` unchanged, so no changes are needed
on the sdata side to surface the error with exit 1.

The `.ads` docstrings for both procedures
(`sdata_core-variables.ads:18,21` — "Fails if name matches a table column" /
"If it was temporary, it's moved to the table") already describe the *new*
behavior (the first is already accurate; the second needs updating to match
the new prohibition rather than silent promotion) — no doc drift to fix on
`Set_Temporary`'s comment, but `Set_Permanent`'s needs a rewrite.

**Side effect:** since the demotion path never calls `Drop_Column` anymore,
the malformed-`SAVE` corruption described in §1 becomes unreachable — `SET` on
a loaded column now errors before any table mutation happens. This closes the
"worth auditing independently" bug the issue flagged, as a consequence of the
primary fix rather than a separate patch.

## 4. Documentation

- **`design.md` §3.5 "Redefinition Rules"** (lines 264–266): replace the
  "Permanent → Temporary" / "Temporary → Permanent" bullets with a statement
  that `LET`/`SET` may not redefine a name across storage classes; it is an
  error, with `DROP`+`SET` / `UNSET`+`LET` as the explicit conversion paths.
  Leave the "Temporary → Permanent via KEEP" bullet (line 266) untouched — it
  is a different, already-explicit mechanism unrelated to verb-implied
  conversion, out of scope here.
- **`design.md` SET/LET command-reference rows**: reconcile with the new
  behavior. The `SET` row (line 959) already states the post-fix behavior for
  its own direction and needs no change; add the symmetric statement to the
  `LET` row for the promotion direction. Note in the commit/PR description
  that this resolves the doc's prior internal self-contradiction.
- **HELP** (`src/sdata-help.adb`): add the new hard-error behavior to the
  `LET`/`SET` HELP topics; regenerate `tests/expected/help_all.out`.
- **Man page** (`man/man1/sdata.1`): same addition to the LET/SET entries.
- **sdata-core `docs/decisions/`**: new `ADR-0010` recording the decision to
  decouple-by-prohibition rather than decouple-by-explicit-modifier, per the
  stability-contract rule that a significant semantic shift to shared
  `Variables` behavior warrants an ADR. Cross-link from sdata's `doc/adrs.md`
  if a corresponding sdata-side ADR number is warranted (precedent: ADR-045
  through ADR-049 are sdata-side ADRs about sdata-core's own command surface;
  this one is the reverse — sdata-core recording a decision about scalar
  variable semantics consumed by both applications).
- **sdata-core `docs/api/reference.html`**: regenerate via
  `scripts/gen-reference.sh` if the `.ads` docstring text changes (it does,
  for `Set_Permanent`).
- **sdata-core `.ssd/current.yml`**: add an entry for this change (non-trivial
  semantic change to shared `Variables` behavior), per sdata-core's
  `CLAUDE.md` cross-repo tracking rule (ADR-0009).

## 5. Tests

- **New regression tests** (sdata `tests/*.cmd`), following the
  `sort_undefined_var`/`by_undefined_var` precedent from issue #50 (`.cmd` +
  `.exitcode` + `expected/*.out`):
  - `set_on_loaded_column.cmd` — `USE` a dataset, `SET` an existing column,
    assert exit 1 and the expected error message; assert the table/output are
    unaffected (no partial mutation).
  - `let_on_temp_var.cmd` — `SET` a temp var, then `LET` the same name, assert
    exit 1 and the expected error message.
  - `let_on_held_temp_var.cmd` (or folded into an existing HOLD test) —
    confirm a `LET` on a **held permanent** variable (whose value is mirrored
    into `Temp_Symbols` by `Reset_PDV_Non_Held`) still succeeds normally and
    is *not* misclassified as a temp-var redefinition. This is the one
    guard-condition subtlety in the fix and needs explicit coverage.
  - `set_save_demotion_repro.cmd` — the exact repro from the issue (`SET A =
    A * 10` on a loaded column, then `SAVE`) now fails cleanly with exit 1 and
    produces no malformed output file, per the earlier agreement to add a
    regression test proving this scenario is subsumed by the hard-error fix
    rather than merely no-longer-reachable-in-theory.
- **Fixture churn**: rewrite `tests/variable_scoping.cmd` "Test 3: Promotion
  (LET promotes SET)" — it currently asserts the promotion behavior this
  issue prohibits (`SET PROMOTED = 1` then `LET PROMOTED = PROMOTED + 9`
  expecting a permanent variable with value 10). Replace it with an assertion
  that this sequence now raises the new error; regenerate
  `tests/expected/variable_scoping.out` and its `.exitcode` accordingly.
  Audit the rest of that file for any other now-invalid assumptions.
- **HELP snapshot**: regenerate `tests/expected/help_all.out` after the HELP
  text change.
- **Cross-crate gate** (per sdata's and sdata-core's `CLAUDE.md`): `cd
  ~/Develop/sdata-core && alr build`, then `make check` in `sdata` (333+
  integration tests plus the new ones), then `make check` in `data-vandal`.
  A search of data-vandal's test scripts found no `LET`/`SET` storage-class
  transitions, so no data-vandal test changes are anticipated, but the gate
  is still mandatory.

## 6. Versioning

- **sdata-core**: bump `alire.toml` version (this is a behavioral change to
  shared, public `Variables` procedures consumed by both applications); tag
  `vX.Y.Z` after the bump, per sdata-core's own versioning convention (no Ada
  version constants there).
- **sdata**: bump the `sdata_core = "^X.Y.Z"` floor in `alire.toml` to the new
  sdata-core version; run `scripts/bump-version.sh` for sdata's own version
  bump (new command-visible behavior via HELP/man page changes); tag
  `vX.Y.Z`.
- **data-vandal**: bump its `sdata_core` floor to match, per the packaging
  convention already documented in sdata's `CLAUDE.md` (never hardcode the
  bundled sdata-core version elsewhere — only the floor constraint needs
  updating here).

## 7. Out of scope

- Any redesign of `KEEP`'s temp→permanent promotion mechanism (design.md line
  266) — that is an explicit, already-distinct mechanism from verb-implied
  conversion and is not touched by this issue.
- Auditing whether `Execute_KEEP` actually implements "listing a temporary
  variable/array in KEEP makes it permanent" as literally described (a
  tangential gap noticed during investigation: `Execute_KEEP` only prunes
  columns not in the list; it does not appear to promote temp vars named in
  the list). Worth a separate issue if confirmed, not part of #56.
- Any change to `HOLD`/`UNHOLD`/held-variable semantics beyond the guard
  clause in §3 needed to avoid misclassifying held-permanent variables as
  temp-var redefinitions.

## 8. Affected files (anticipated)

**sdata-core:**
- `src/sdata_core-variables.adb` — `Set_Temporary`, `Set_Permanent`
- `src/sdata_core-variables.ads` — `Set_Permanent` docstring
- `docs/decisions/ADR-0010-*.md` — new ADR
- `docs/api/reference.html` — regenerated
- `alire.toml` — version bump
- `.ssd/current.yml` — new entry

**sdata:**
- `doc/design.md` — §3.5, SET/LET reference rows
- `src/sdata-help.adb` — LET/SET HELP topics
- `man/man1/sdata.1` — LET/SET entries
- `tests/set_on_loaded_column.cmd`, `tests/let_on_temp_var.cmd`,
  `tests/let_on_held_temp_var.cmd`, `tests/set_save_demotion_repro.cmd` (new,
  plus matching `.exitcode`/`expected/*.out`)
- `tests/variable_scoping.cmd`, `tests/expected/variable_scoping.out` —
  rewritten Test 3
- `tests/expected/help_all.out` — regenerated
- `alire.toml` — `sdata_core` floor bump

**data-vandal:** `alire.toml` floor bump only; no test changes anticipated
(confirmed by `make check`).
