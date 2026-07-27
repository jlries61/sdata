# SET/LET Storage-Class Hard Error (#56) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `SET` on an existing loaded/permanent table column, and `LET` on an existing genuine temporary variable, raise a hard error (exit 1) instead of silently converting the variable's storage class — closing issue #56 and, as a side effect, the malformed-`SAVE` corruption it also caused.

**Architecture:** Both conversions are decided in exactly two procedures in shared code — `SData_Core.Variables.Set_Temporary` (the `SET` handler) and `Set_Permanent` (the `LET` handler), in `~/Develop/sdata-core/src/sdata_core-variables.adb`. Each currently detects the cross-storage-class case and silently converts it (drop-and-warn for SET, delete-and-promote for LET); each is changed to raise `SData_Core.Script_Error` instead. No new syntax. The existing `Execute_Assignment` exception handling in `sdata-interpreter-execute_assignment.adb` already re-raises `Script_Error` unchanged, so the error surfaces with exit 1 with no sdata-side code change. A guard already present in `Set_Permanent` (`not Is_Held (Upper_Name)`) distinguishes a genuine temporary variable from a held-permanent variable's carry-over shadow in `Temp_Symbols` — that guard is preserved so `LET` on a held permanent variable keeps working (proven by the existing `hold_test.cmd`).

**Tech Stack:** Ada 2012, GNAT via Alire (`alr build`), path-pinned sibling crates (sdata → sdata-core; data-vandal → sdata-core).

## Global Constraints

- **Design spec:** `doc/specs/2026-07-24-set-let-storage-class-hard-error-design.md` (approved) — this plan implements it exactly; do not relitigate the decision.
- **sdata-core requires a PR** (no direct push to `main`); **sdata allows direct push to `main`**; **data-vandal requires a PR**.
- **Branches:** sdata-core `fix/56-set-let-storage-class` (new, from `main`); sdata may commit directly to `main` for this work (small, well-scoped fix, matching the project's existing direct-push convention) — but if you'd rather keep it reviewable, a feature branch is fine too; data-vandal `chore/56-sdata-core-floor-bump` (new, from `main`).
- **Cross-crate gate before any push, from every task that touches sdata-core:** `cd ~/Develop/sdata-core && alr build`, then `cd ~/Develop/sdata && make check` (all unit + 333+ integration tests), then `cd ~/Develop/data-vandal && make check`. All three green.
- **Path pin hides floor drift** (per sdata's `CLAUDE.md`): sdata's and data-vandal's `alire.toml` `sdata_core = "^X.Y.Z"` floor must be bumped to reflect the new sdata-core version even though the local path pin makes builds pass regardless of the floor value.
- **Versions:** sdata-core `0.3.1 → 0.3.2`; sdata `0.16.1 → 0.16.2`; data-vandal — floor bump only in `alire.toml`, no own version bump (no data-vandal code or behavior changes; confirmed by `grep` finding no LET/SET storage-class usage in its test scripts). Both consumer floors `sdata_core = "^0.3.2"`. sdata-core's `consumer-tests.yml` `ref:` → `v0.16.2` once the sdata tag exists.
- **Commit trailer** (every commit, every repo): `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`.
- **Merge order:** sdata-core PR first (consumers' CI clones `sdata-core@main`), then sdata, then data-vandal.
- **Error message text is exact and must match byte-for-byte between the Ada source and every `tests/expected/*.out` file that shows it** — copy it, don't retype it, when creating expected-output files.
- **New `.cmd` integration tests always run `2>&1`-combined against `./bin/sdata`, diffed with `diff -wu`** (per `Makefile`'s `check` target) — capture expected output by actually running the built binary, not by hand-transcribing.

---

### Task 1: sdata-core — `Set_Temporary` raises on an existing permanent column (SET direction)

`Set_Temporary` is the `SET` handler in `~/Develop/sdata-core/src/sdata_core-variables.adb`. It currently detects that the target name is already a table column and silently warns + drops the column (`Table.Drop_Column`), which is also the root cause of the malformed-`SAVE` corruption (the drop shifts every later column's PDV-to-table index correspondence without updating the PDV, per the design spec §1). This task replaces that with a hard error.

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-variables.adb` (`Set_Temporary`, currently lines 45–63)
- Test: `~/Develop/sdata/tests/sdata_unit_test.adb` (new checks after the existing `V-16` check, before the `Load_PDV_From_Table roundtrip` section header, around line 512)

**Interfaces:**
- Consumes: `SData_Core.Table.Has_Column (Name : String) return Boolean` (existing), `SData_Core.Script_Error` (declared `sdata_core.ads:19`, visible here without an explicit `with` since `Variables` is a child package of `SData_Core`).
- Produces: post-condition — `Set_Temporary (Name, Val)` raises `SData_Core.Script_Error` when `SData_Core.Table.Has_Column (Name)` is `True`; the table's column is untouched (no `Drop_Column` call reached).

- [ ] **Step 1: Write the failing unit test**

In `~/Develop/sdata/tests/sdata_unit_test.adb`, immediately after the existing block ending at line 512 (`Check ("V-16 PDV_Resolve unknown returns 0", PDV_Resolve ("NOSUCHVAR"), 0);`) and before the `---...---` section-header comment for `Load_PDV_From_Table roundtrip`, insert:

```ada
   ---------------------------------------------------------------------------
   --  ── SData_Core.Variables: SET/LET storage-class hard error (#56) ────────
   ---------------------------------------------------------------------------

   --  SET on an existing permanent (table) column must raise, not silently
   --  demote the column to a temporary variable.
   SData_Core.Table.Clear;
   Clear_Temporary;
   SData_Core.Table.Add_Column ("PERMCOL", SData_Core.Table.Col_Numeric);
   declare
      Raised : Boolean := False;
   begin
      Set_Temporary ("PERMCOL", (Kind => Val_Numeric, Num_Val => 1.0));
   exception
      when SData_Core.Script_Error => Raised := True;
   end;
   Check ("V-56a SET on existing column raises", Raised, True);
   Check ("V-56b column survives rejected SET",
          SData_Core.Table.Has_Column ("PERMCOL"), True);
```

- [ ] **Step 2: Build sdata-core, then rebuild sdata's unit test binary and run it to verify the new checks fail**

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && alr build && ./bin/sdata_unit_test 2>&1 | grep 'V-56'
```
Expected: `FAIL: V-56a SET on existing column raises  got=FALSE  expected=TRUE` (the old code warns and drops instead of raising, so `Raised` stays `False`). `V-56b` should already pass (the drop, when it does happen under the old code, actually does remove the column — but don't worry about its exact old-code result; the point of this step is confirming `V-56a` fails).

- [ ] **Step 3: Implement the hard error in `Set_Temporary`**

In `~/Develop/sdata-core/src/sdata_core-variables.adb`, replace lines 45–52 (the full procedure header through the closing `end if;` of the drop block):

```ada
   procedure Set_Temporary (Name : String; Val : Value) is
      Upper_Name : constant String := To_Upper (Name);
   begin
      --  Rule: SET implicitly drops permanent variable from table (Exclusivity)
      if SData_Core.Table.Has_Column (Upper_Name) then
         SData_Core.IO.Put_Line_Error ("Warning: Column '" & Upper_Name & "' dropped from table and converted to session variable.");
         SData_Core.Table.Drop_Column (Upper_Name);
      end if;
```

with:

```ada
   procedure Set_Temporary (Name : String; Val : Value) is
      Upper_Name : constant String := To_Upper (Name);
   begin
      --  Issue #56: SET may not redefine an existing permanent (table)
      --  column.  Storage class is no longer implicitly convertible by the
      --  assignment verb -- silently demoting a loaded column corrupted the
      --  PDV/table positional invariant (Drop_Column mid-record-loop) and
      --  dropped data from SAVE output with only a warning.  Recompute it
      --  with LET, or DROP it explicitly (effective after the next RUN)
      --  before SET-ing a fresh temporary variable of the same name.
      if SData_Core.Table.Has_Column (Upper_Name) then
         raise Script_Error with
           "SET cannot redefine permanent variable """ & Upper_Name
           & """; use LET to recompute it in place, or DROP it "
           & "(effective after the next RUN) to convert it to a "
           & "temporary variable";
      end if;
```

- [ ] **Step 4: Rebuild both and run the unit test to verify it passes**

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && alr build && ./bin/sdata_unit_test 2>&1 | grep 'V-56'
```
Expected: `PASS: V-56a SET on existing column raises` and `PASS: V-56b column survives rejected SET`.

- [ ] **Step 5: Run the full sdata unit + integration suite to confirm no regressions**

```bash
cd ~/Develop/sdata && make check
```
Expected: some pre-existing tests may now fail if they relied on the old silent-demotion behavior — note any failures here; they are expected to be exactly `variable_scoping.cmd` (fixed in Task 7) and nothing else. Do not fix `variable_scoping.cmd` yet; just confirm the failure set is limited to it.

- [ ] **Step 6: Commit the sdata-core change (the `tests/sdata_unit_test.adb` changes commit at the end of Task 2, once all `V-56*` checks — Task 1's and Task 2's — are in place and passing)**

```bash
cd ~/Develop/sdata-core
git checkout -b fix/56-set-let-storage-class
git add src/sdata_core-variables.adb
git commit -m "$(cat <<'EOF'
fix: SET on a loaded column now raises instead of demoting it (#56)

SET on an existing permanent (table) column silently dropped the
column and converted it to a temporary variable, with only a stderr
warning and exit 0. Worse, Drop_Column mutates the table mid-record
loop without updating the parallel PDV, corrupting every column after
the demoted one for the rest of the RUN and producing malformed SAVE
output.

Set_Temporary now raises Script_Error instead. Recompute the variable
with LET, or DROP it explicitly (effective after the next RUN) before
SET-ing a fresh temporary variable of the same name.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: sdata-core — `Set_Permanent` raises on an existing temporary variable (LET direction)

Symmetric fix for the other direction: `LET` on a name that is already a genuine temporary variable currently silently promotes it (deletes it from `Temp_Symbols`, then proceeds to create/update a PDV slot). The existing `not Is_Held (Upper_Name)` guard already distinguishes a real temp var from a held-permanent variable's `Temp_Symbols` shadow — that guard must be preserved so `LET` on a held variable (as in `hold_test.cmd`) keeps working.

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-variables.adb` (`Set_Permanent`, currently lines 66–93)
- Modify: `~/Develop/sdata-core/src/sdata_core-variables.ads` (docstring at line 21)
- Test: `~/Develop/sdata/tests/sdata_unit_test.adb` (new checks appended after Task 1's `V-56b` check)

**Interfaces:**
- Consumes: `Temp_Symbols.Contains (Upper_Name) return Boolean`, `Is_Held (Upper_Name : String) return Boolean` (both existing, `sdata_core-variables.adb`).
- Produces: post-condition — `Set_Permanent (Name, Val)` raises `SData_Core.Script_Error` when `Temp_Symbols.Contains (Upper_Name)` is `True` and `Is_Held (Upper_Name)` is `False`; when `Is_Held` is `True`, behavior is unchanged (succeeds normally, updates the permanent variable).

- [ ] **Step 1: Write the failing unit test**

In `~/Develop/sdata/tests/sdata_unit_test.adb`, immediately after the `V-56b` check added in Task 1, insert:

```ada
   --  LET on an existing genuine temporary variable must raise, not
   --  silently promote it to permanent.
   SData_Core.Table.Clear;
   Clear_Temporary;
   Initialize_PDV;
   Set_Temporary ("TEMPVAR", (Kind => Val_Numeric, Num_Val => 1.0));
   declare
      Raised : Boolean := False;
   begin
      Set_Permanent ("TEMPVAR", (Kind => Val_Numeric, Num_Val => 2.0));
   exception
      when SData_Core.Script_Error => Raised := True;
   end;
   Check ("V-56c LET on existing temp var raises", Raised, True);
   Check ("V-56d temp var survives rejected LET", Defined ("TEMPVAR"), True);
   V := Get ("TEMPVAR");
   Check_Float ("V-56e rejected LET does not change temp value", V.Num_Val, 1.0);
```

- [ ] **Step 2: Rebuild and run to verify the new checks fail**

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && alr build && ./bin/sdata_unit_test 2>&1 | grep 'V-56'
```
Expected: `FAIL: V-56c LET on existing temp var raises  got=FALSE  expected=TRUE` (old code promotes silently instead of raising).

- [ ] **Step 3: Implement the hard error in `Set_Permanent`**

In `~/Develop/sdata-core/src/sdata_core-variables.adb`, replace lines 68–75:

```ada
   procedure Set_Permanent (Name : String; Val : Value) is
      Upper_Name : constant String := To_Upper (Name);
      Cur        : constant PDV_Index_Pkg.Cursor := PDV_Index.Find (Upper_Name);
   begin
      --  Rule: LET implicitly unsets session variable (Promotion/Exclusivity)
      if Temp_Symbols.Contains (Upper_Name) and then not Is_Held (Upper_Name) then
         Temp_Symbols.Delete (Upper_Name);
      end if;
```

with:

```ada
   procedure Set_Permanent (Name : String; Val : Value) is
      Upper_Name : constant String := To_Upper (Name);
      Cur        : constant PDV_Index_Pkg.Cursor := PDV_Index.Find (Upper_Name);
   begin
      --  Issue #56: LET may not redefine an existing genuine temporary
      --  variable.  "Genuine" excludes a HELD permanent variable, whose
      --  current value Reset_PDV_Non_Held mirrors into Temp_Symbols so it
      --  survives across records -- that is an ordinary update to an
      --  already-permanent variable, not a promotion, and must keep
      --  working (see hold_test.cmd).  Recompute a real temp var with SET,
      --  or UNSET it explicitly before LET-ing a fresh permanent variable
      --  of the same name.
      if Temp_Symbols.Contains (Upper_Name) and then not Is_Held (Upper_Name) then
         raise Script_Error with
           "LET cannot redefine temporary variable """ & Upper_Name
           & """; use SET to recompute it in place, or UNSET it to "
           & "convert it to a permanent variable";
      end if;
```

- [ ] **Step 4: Update the `.ads` docstring to match**

In `~/Develop/sdata-core/src/sdata_core-variables.ads`, replace line 21:

```ada
   --  Ensures a variable is permanent. If it was temporary, it's moved to the table.
```

with:

```ada
   --  Ensures a variable is permanent. Fails if the name is an existing
   --  genuine temporary variable (a held-permanent variable's Temp_Symbols
   --  carry-over shadow is not "temporary" for this purpose -- see Is_Held).
```

- [ ] **Step 5: Rebuild and run to verify the new checks pass**

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && alr build && ./bin/sdata_unit_test 2>&1 | grep 'V-56'
```
Expected: all five `V-56*` checks show `PASS`.

- [ ] **Step 6: Run `hold_test.cmd` directly to confirm the `Is_Held` exemption still works**

```bash
cd ~/Develop/sdata
./bin/sdata tests/hold_test.cmd > /tmp/hold_test_actual.out 2>&1
diff -wu tests/expected/hold_test.out /tmp/hold_test_actual.out
```
Expected: no diff output (the existing test, which repeatedly does `HOLD TOTAL` / `LET TOTAL = TOTAL + 1` across records, must still pass unchanged — it is the regression proof that `LET` on a held permanent variable is correctly exempted from the new error).

- [ ] **Step 7: Commit the sdata-core change**

```bash
cd ~/Develop/sdata-core
git add src/sdata_core-variables.adb src/sdata_core-variables.ads
git commit -m "$(cat <<'EOF'
fix: LET on a temporary variable now raises instead of promoting it (#56)

Symmetric to the SET-side fix: LET on an existing genuine temporary
variable silently promoted it to permanent with no error. Set_Permanent
now raises Script_Error instead, preserving the existing Is_Held
exemption so LET on a held permanent variable (hold_test.cmd) is
unaffected -- that is an ordinary update, not a promotion.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 8: Commit the sdata-side unit test changes (both Task 1's and Task 2's `V-56*` checks, since neither was committed yet)**

```bash
cd ~/Develop/sdata
git add tests/sdata_unit_test.adb
git commit -m "$(cat <<'EOF'
test: unit coverage for SET/LET storage-class hard error (#56)

Adds V-56a..V-56e to sdata_unit_test.adb, covering both directions
directly against SData_Core.Variables.Set_Temporary/Set_Permanent:
SET on an existing column raises and leaves the column intact; LET on
an existing genuine temporary variable raises and leaves the temp
variable's value unchanged.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: sdata-core — ADR, API reference regen, version bump, PR

Closes out the sdata-core side: record the decision as an ADR (the stability-contract rule that a significant semantic shift to shared `Variables` behavior warrants one), regenerate the checked-in API reference (the `.ads` docstring changed in Task 2), bump the crate version, and open the PR.

**Files:**
- Create: `~/Develop/sdata-core/docs/decisions/ADR-0010-set-let-storage-class-hard-error.md`
- Modify: `~/Develop/sdata-core/docs/decisions/README.md` (index entry, if the README lists ADRs by number/title — check its current format first)
- Modify: `~/Develop/sdata-core/docs/api/reference.html` (regenerated)
- Modify: `~/Develop/sdata-core/alire.toml` (version bump)

**Interfaces:** none (documentation and packaging only).

- [ ] **Step 1: Check the ADR index format**

```bash
cat ~/Develop/sdata-core/docs/decisions/README.md
```
If it lists each ADR by number/title/status (matching the numbering-and-format conventions already documented there), add a row for ADR-0010 in the same shape as the existing entries once the ADR file exists (Step 2). If it's prose-only with no per-ADR list, skip this file.

- [ ] **Step 2: Write ADR-0010**

Create `~/Develop/sdata-core/docs/decisions/ADR-0010-set-let-storage-class-hard-error.md`:

```markdown
---
id: ADR-0010
title: "SET/LET storage-class redefinition is a hard error, not an implicit conversion"
status: Accepted
date: 2026-07-25
related:
  - ../../sdata/doc/specs/2026-07-24-set-let-storage-class-hard-error-design.md
  - ../../sdata/doc/adrs.md
---

# ADR-0010: SET/LET storage-class redefinition is a hard error, not an implicit conversion

## Status

Accepted.

## Context

`SData_Core.Variables.Set_Temporary` (the `SET` handler) and `Set_Permanent`
(the `LET` handler) previously let the assignment verb silently decide, and
change, a variable's storage class: `SET` on an existing permanent (table)
column demoted it to a temporary variable (dropping the column, with only a
stderr warning); `LET` on an existing genuine temporary variable silently
promoted it to permanent. Both consumers (`sdata`, `data-vandal`) inherit
this behavior directly, since both call these procedures without
modification.

The demotion direction was a genuine data-integrity footgun (sdata issue
[#56](https://github.com/jlries61/sdata/issues/56), same family as sdata
issues #50-#52): a `SET` where `LET` was intended silently dropped a column
from the output with exit code 0. It was also the root cause of a real data
corruption bug: `Set_Temporary`'s call to `Table.Drop_Column` shifted every
later column's position without updating the parallel PDV structures, which
assume positional correspondence with table columns -- corrupting every
column after the demoted one for the rest of the RUN, and reappearing as
stale/malformed `SAVE` output.

Full design rationale, rejected alternatives, and the exact mechanism are in
sdata's `doc/specs/2026-07-24-set-let-storage-class-hard-error-design.md`.

## Decision

Both `Set_Temporary` and `Set_Permanent` raise `SData_Core.Script_Error`
when asked to redefine a name across storage classes, instead of silently
converting it. No new syntax or modifier is introduced. The existing
`Is_Held` guard in `Set_Permanent` is preserved unchanged, so `LET` on a
held-permanent variable (whose value is mirrored into `Temp_Symbols` by
`Reset_PDV_Non_Held` to survive across records) continues to succeed --
that is an ordinary update, not a promotion.

Explicit, deliberate conversion remains possible via existing primitives,
unchanged by this decision: `DROP x` (effective after the next `RUN`) then
`SET x = ...` to convert a column to a temp var; `UNSET x` then
`LET x = ...` to convert a temp var to a column.

## Consequences

**Positive**

- Closes the silent data-loss and PDV/table corruption described above.
- Brings scalar assignment in line with the array-assignment precedent
  already enforced in sdata's `Execute_Array_Assignment`, which already
  raises `Script_Error` for the equivalent wrong-direction cases on array
  elements.
- No API signature change; both consumers pick up the new behavior via the
  version bump with no call-site changes required.

**Negative**

- A script that relied on the old implicit conversion (in either direction)
  now errors instead of silently succeeding. A repository-wide search found
  no test, doc passage, or example script anywhere in sdata, sdata-core, or
  data-vandal that relied on this behavior as an intentional feature -- the
  one sdata test that exercised it (`variable_scoping.cmd` "Test 3:
  Promotion") treated it as the thing under test, not a dependency of some
  other feature, and is rewritten to assert the new error instead.

## Related

- sdata issue [#56](https://github.com/jlries61/sdata/issues/56)
- sdata `doc/specs/2026-07-24-set-let-storage-class-hard-error-design.md`
- sdata issues #50-#52 (the same "silent corruption -> loud error" family)
```

- [ ] **Step 3: Regenerate the API reference**

```bash
cd ~/Develop/sdata-core
scripts/gen-reference.sh
git diff --stat docs/api/reference.html
```
Expected: a diff touching the `Set_Permanent` entry (docstring text changed in Task 2, Step 4). Confirm the new docstring text appears correctly rendered.

- [ ] **Step 4: Bump the version**

In `~/Develop/sdata-core/alire.toml`, change:
```toml
version = "0.3.1"
```
to:
```toml
version = "0.3.2"
```

- [ ] **Step 5: Build once more, then commit and open the PR**

```bash
cd ~/Develop/sdata-core && alr build
git add docs/decisions/ADR-0010-set-let-storage-class-hard-error.md docs/decisions/README.md docs/api/reference.html alire.toml
git commit -m "$(cat <<'EOF'
docs: ADR-0010, API reference regen, version 0.3.2 (#56)

Records the SET/LET storage-class hard-error decision; regenerates
the checked-in API reference for the updated Set_Permanent docstring;
bumps the crate version for the behavioral change.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
git push -u origin fix/56-set-let-storage-class
gh pr create --title "fix: SET/LET storage-class redefinition is a hard error (#56)" --body "$(cat <<'EOF'
## Summary
- `SET` on an existing loaded/permanent column now raises `Script_Error` instead of silently demoting the column and corrupting the PDV/table positional invariant.
- `LET` on an existing genuine temporary variable now raises `Script_Error` instead of silently promoting it. `LET` on a held-permanent variable is unaffected (existing `Is_Held` guard preserved).
- No new syntax. Explicit conversion remains available via `DROP`+`SET` and `UNSET`+`LET`.
- ADR-0010 records the decision; `docs/api/reference.html` regenerated; version bumped to 0.3.2.

Design: sdata `doc/specs/2026-07-24-set-let-storage-class-hard-error-design.md`.
Closes sdata jlries61/sdata#56 (tracked in the sdata repo; this PR is the sdata-core half).

## Test plan
- [ ] `alr build` clean
- [ ] `cd ~/Develop/sdata && make check` green (after Tasks 4-9 land there)
- [ ] `cd ~/Develop/data-vandal && make check` green
EOF
)"
```

---

### Task 4: sdata — regression test: `SET` on a loaded column

**Files:**
- Create: `~/Develop/sdata/tests/set_on_loaded_column.cmd`
- Create: `~/Develop/sdata/tests/set_on_loaded_column.exitcode`
- Create: `~/Develop/sdata/tests/expected/set_on_loaded_column.out`

**Interfaces:**
- Consumes: `SET` statement dispatch (`sdata-interpreter-execute_assignment.adb`) → `SData_Core.Variables.Set_Temporary` (fixed in Task 1).

- [ ] **Step 1: Write the test script**

Create `~/Develop/sdata/tests/set_on_loaded_column.cmd`:

```
-- Issue #56: SET on an existing loaded/permanent column must fail loudly
-- (hard error, exit 1) instead of silently demoting it to a temporary
-- variable and dropping it from the table.
USE MOCK
SET SALARY = SALARY * 2
RUN
```

- [ ] **Step 2: Run it against the now-fixed binary and capture the actual output**

```bash
cd ~/Develop/sdata
./bin/sdata tests/set_on_loaded_column.cmd > /tmp/set_on_loaded_column.actual 2>&1
echo "exit: $?"
cat /tmp/set_on_loaded_column.actual
```
Expected exit: `1`. Expected content (confirm it matches, then use it verbatim):
```
Generating mock data...
Error: SET cannot redefine permanent variable "SALARY"; use LET to recompute it in place, or DROP it (effective after the next RUN) to convert it to a temporary variable
```

- [ ] **Step 3: Save the captured output and exit code as the expected fixtures**

```bash
cp /tmp/set_on_loaded_column.actual tests/expected/set_on_loaded_column.out
printf '1' > tests/set_on_loaded_column.exitcode
```

- [ ] **Step 4: Run it through the Makefile's own test loop to confirm it's wired up correctly**

```bash
./bin/sdata tests/set_on_loaded_column.cmd > tests/set_on_loaded_column.tmp 2>&1; \
echo "actual exit: $?"; \
diff -wu tests/expected/set_on_loaded_column.out tests/set_on_loaded_column.tmp; \
rm -f tests/set_on_loaded_column.tmp
```
Expected: no diff output, exit matches the `.exitcode` file.

- [ ] **Step 5: Commit**

```bash
git add tests/set_on_loaded_column.cmd tests/set_on_loaded_column.exitcode tests/expected/set_on_loaded_column.out
git commit -m "$(cat <<'EOF'
test: SET on a loaded column now fails loudly (#56)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: sdata — regression test: `LET` on a temporary variable

**Files:**
- Create: `~/Develop/sdata/tests/let_on_temp_var.cmd`
- Create: `~/Develop/sdata/tests/let_on_temp_var.exitcode`
- Create: `~/Develop/sdata/tests/expected/let_on_temp_var.out`

**Interfaces:**
- Consumes: `LET` statement dispatch → `SData_Core.Variables.Set_Permanent` (fixed in Task 2).

- [ ] **Step 1: Write the test script**

Create `~/Develop/sdata/tests/let_on_temp_var.cmd`:

```
-- Issue #56: LET on an existing genuine temporary variable must fail loudly
-- (hard error, exit 1) instead of silently promoting it to a permanent
-- table column.
SET PROMOTED = 1
LET PROMOTED = PROMOTED + 9
RUN
```

- [ ] **Step 2: Run it and capture the actual output**

```bash
cd ~/Develop/sdata
./bin/sdata tests/let_on_temp_var.cmd > /tmp/let_on_temp_var.actual 2>&1
echo "exit: $?"
cat /tmp/let_on_temp_var.actual
```
Expected exit: `1`. Expected content:
```
Error: LET cannot redefine temporary variable "PROMOTED"; use SET to recompute it in place, or UNSET it to convert it to a permanent variable
```

- [ ] **Step 3: Save the fixtures**

```bash
cp /tmp/let_on_temp_var.actual tests/expected/let_on_temp_var.out
printf '1' > tests/let_on_temp_var.exitcode
```

- [ ] **Step 4: Verify via diff**

```bash
./bin/sdata tests/let_on_temp_var.cmd > tests/let_on_temp_var.tmp 2>&1; \
echo "actual exit: $?"; \
diff -wu tests/expected/let_on_temp_var.out tests/let_on_temp_var.tmp; \
rm -f tests/let_on_temp_var.tmp
```
Expected: no diff.

- [ ] **Step 5: Commit**

```bash
git add tests/let_on_temp_var.cmd tests/let_on_temp_var.exitcode tests/expected/let_on_temp_var.out
git commit -m "$(cat <<'EOF'
test: LET on a temporary variable now fails loudly (#56)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: sdata — regression test: the issue's original SAVE-corruption repro

Proves the malformed-`SAVE` bug (design spec §1) is subsumed by the Task 1 fix: `SET` on a loaded column now errors before `RUN`'s commit step is ever reached, so the `SAVE` target is never written with corrupted data. The absence of a `RUN complete` line in the captured output is the proof — `Commit_Output_Table` (where the actual file write happens) only runs at the end of a successful `RUN`.

**Files:**
- Create: `~/Develop/sdata/tests/set_save_demotion_repro.cmd`
- Create: `~/Develop/sdata/tests/set_save_demotion_repro.exitcode`
- Create: `~/Develop/sdata/tests/expected/set_save_demotion_repro.out`

**Interfaces:**
- Consumes: `USE`, `SET`, `SAVE`, `RUN` command dispatch (unchanged); `SData_Core.Variables.Set_Temporary` (fixed in Task 1).

- [ ] **Step 1: Write the test script**

Create `~/Develop/sdata/tests/set_save_demotion_repro.cmd`:

```
-- Issue #56: original repro. SET on a loaded column used to silently demote
-- it (dropping it from the table) and corrupt the subsequent SAVE output via
-- a PDV/table desync (Drop_Column mutating the table mid-record-loop). SET
-- must now fail loudly at the point of assignment, before RUN ever reaches
-- the commit step that would actually write the SAVE target -- proven here
-- by the absence of a "RUN complete" line (SAVE's "Dataset saved" message
-- announces the pending target immediately when parsed, but the actual
-- write happens only at RUN's commit, which this error prevents).
USE "tests/data/sample.csv"
SET VAL1 = VAL1 * 10
SAVE "tests/data/set_save_demotion_repro_out.csv"
RUN
```

- [ ] **Step 2: Run it and capture the actual output**

```bash
cd ~/Develop/sdata
./bin/sdata tests/set_save_demotion_repro.cmd > /tmp/set_save_demotion_repro.actual 2>&1
echo "exit: $?"
cat /tmp/set_save_demotion_repro.actual
ls -la tests/data/set_save_demotion_repro_out.csv 2>&1
```
Expected exit: `1`. Expected content:
```
Dataset opened: tests/data/sample.csv
Dataset saved: tests/data/set_save_demotion_repro_out.csv
Error: SET cannot redefine permanent variable "VAL1"; use LET to recompute it in place, or DROP it (effective after the next RUN) to convert it to a temporary variable
```
The `ls` should report "No such file or directory" — `SAVE`'s message only announces the pending target; the actual write never happens because `RUN` aborts before its commit step.

- [ ] **Step 3: Save the fixtures**

```bash
cp /tmp/set_save_demotion_repro.actual tests/expected/set_save_demotion_repro.out
printf '1' > tests/set_save_demotion_repro.exitcode
```

- [ ] **Step 4: Verify via diff, and confirm no stray output file was left behind**

```bash
rm -f tests/data/set_save_demotion_repro_out.csv
./bin/sdata tests/set_save_demotion_repro.cmd > tests/set_save_demotion_repro.tmp 2>&1; \
echo "actual exit: $?"; \
diff -wu tests/expected/set_save_demotion_repro.out tests/set_save_demotion_repro.tmp; \
rm -f tests/set_save_demotion_repro.tmp
ls tests/data/set_save_demotion_repro_out.csv 2>&1  # must report "No such file"
```

- [ ] **Step 5: Commit**

```bash
git add tests/set_save_demotion_repro.cmd tests/set_save_demotion_repro.exitcode tests/expected/set_save_demotion_repro.out
git commit -m "$(cat <<'EOF'
test: original #56 repro (SET + SAVE) now fails before any write (#56)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: sdata — rewrite `variable_scoping.cmd` Test 3

Test 3 ("Promotion (LET promotes SET)") currently asserts the exact behavior this issue prohibits. Remove it; its replacement coverage is Task 5's dedicated test. Tests 1 and 2 in the same file are unaffected (they use disjoint variable names / already-cleared scopes) and are left unchanged.

**Files:**
- Modify: `~/Develop/sdata/tests/variable_scoping.cmd`
- Modify: `~/Develop/sdata/tests/expected/variable_scoping.out`

**Interfaces:** none (test-only change).

- [ ] **Step 1: Confirm the current file fails after Tasks 1-2 (already established in Task 1 Step 5)**

```bash
cd ~/Develop/sdata
./bin/sdata tests/variable_scoping.cmd > /tmp/variable_scoping.actual 2>&1
echo "exit: $?"
diff -wu tests/expected/variable_scoping.out /tmp/variable_scoping.actual
```
Expected: a diff starting around the old "Test 3" output — the old file expected the promotion to succeed (`PROMOTED is now permanent (10): 10.00000`), but the run now aborts with the new `Script_Error` partway through Test 3's `RUN`.

- [ ] **Step 2: Remove Test 3 from the script**

Replace the full contents of `~/Develop/sdata/tests/variable_scoping.cmd` with:

```
REM Test 1: SET vs LET across records
REPEAT 3
SET TEMP_VAR = 100
LET PERM_VAR = 200
SET TEMP_VAR = TEMP_VAR + 1
LET PERM_VAR = PERM_VAR + 1
PRINT "Record" RECNO() ": TEMP =" TEMP_VAR ", PERM =" PERM_VAR
RUN

NEW

REM Test 2: Temporary variables should have disappeared
SET TV = 1
RUN
NEW
PRINT "TV is missing (1):" MISSING(TV)
RUN
END
```

(This drops the blank line, `NEW`, and the "Test 3: Promotion" block — `SET PROMOTED = 1` / `LET PROMOTED = PROMOTED + 9` / `PRINT ...` / `NAMES` / `RUN` — that exercised the now-prohibited behavior; dedicated coverage for that case lives in `let_on_temp_var.cmd`, Task 5.)

- [ ] **Step 3: Regenerate the expected output**

```bash
cd ~/Develop/sdata
./bin/sdata tests/variable_scoping.cmd > tests/expected/variable_scoping.out 2>&1
cat tests/expected/variable_scoping.out
```
Expected content (7 lines, matching Tests 1-2 exactly as before, with nothing from the removed Test 3):
```
Record 1 : TEMP = 101.00000 , PERM = 201.00000
Record 2 : TEMP = 101.00000 , PERM = 201.00000
Record 3 : TEMP = 101.00000 , PERM = 201.00000
RUN complete. 3 records and 1 variables processed.
RUN complete. 1 records and 0 variables processed.
TV is missing (1): 1
RUN complete. 1 records and 0 variables processed.
```

- [ ] **Step 4: Confirm no `.exitcode` file is needed (exit should still be 0)**

```bash
./bin/sdata tests/variable_scoping.cmd > /dev/null 2>&1; echo "exit: $?"
ls tests/variable_scoping.exitcode 2>&1   # must report "No such file" -- default expected exit is 0
```

- [ ] **Step 5: Run the full suite**

```bash
make check
```
Expected: `variable_scoping` now passes; no other test regresses (the failure set from Task 1 Step 5 is now empty).

- [ ] **Step 6: Commit**

```bash
git add tests/variable_scoping.cmd tests/expected/variable_scoping.out
git commit -m "$(cat <<'EOF'
test: drop variable_scoping.cmd's promotion test (#56)

Test 3 exercised LET silently promoting an existing temporary
variable to permanent -- behavior this issue prohibits. Dedicated
coverage for the new hard-error behavior is let_on_temp_var.cmd;
Tests 1-2 in this file are unaffected and unchanged.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: sdata — keep the user-facing surface in sync (design.md, HELP, man page)

Per this project's `CLAUDE.md`, a language-visible behavior change must update all three user-facing references in the same change: `doc/design.md`, `src/sdata-help.adb` (regenerating `tests/expected/help_all.out`), and `man/man1/sdata.1`.

**Files:**
- Modify: `~/Develop/sdata/doc/design.md` (§3.5 lines 264-266; `LET` row line 856; `SET` row line 959)
- Modify: `~/Develop/sdata/src/sdata-help.adb` (`Help_LET` lines 183-188, `Help_SET` lines 190-197)
- Modify: `~/Develop/sdata/tests/expected/help_all.out` (regenerated)
- Modify: `~/Develop/sdata/man/man1/sdata.1` (lines 917-930)

**Interfaces:** none (documentation only).

- [ ] **Step 1: Fix `design.md` §3.5 "Redefinition Rules"**

In `~/Develop/sdata/doc/design.md`, replace lines 264-265:

```markdown
- **Permanent → Temporary:** If permanent variable/array redefined by *SET*, it becomes temporary.
- **Temporary → Permanent:** If temporary variable/array redefined by LET, it becomes permanent.
```

with:

```markdown
- **No implicit cross-class redefinition:** *LET* may not redefine an existing temporary variable, and *SET* may not redefine an existing permanent variable/column; either is an error. Recompute a variable with the verb that already owns it. To convert a name's storage class deliberately: *DROP* it (effective after the next *RUN*), then *SET* it to create a temporary variable of the same name; or *UNSET* a temporary variable, then *LET* it to create a permanent variable of the same name.
```

Leave line 266 ("Temporary → Permanent via KEEP") unchanged — a separate, already-explicit mechanism, out of scope here.

- [ ] **Step 2: Fix the `LET` command-reference row**

In `~/Develop/sdata/doc/design.md`, replace line 856:

```markdown
<p>Defines permanent variables (those in the internal table) only. A <em>LET</em> statement that writes to a temporary variable shall make that variable permanent.</p></td>
```

with:

```markdown
<p>Defines permanent variables (those in the internal table) only. A <em>LET</em> statement that writes to an existing temporary variable shall fail with an error message; use <em>SET</em> to recompute it, or <em>UNSET</em> it first to redefine it as permanent under the same name.</p></td>
```

- [ ] **Step 3: Fix the `SET` command-reference row**

In `~/Develop/sdata/doc/design.md`, replace line 959:

```markdown
<td>Write the output of the expression to a temporary variable, which will disappear after the next <em>RUN</em> statement is executed. A <em>SET</em> statement that attempts to write to a permanent variable will fail with an error message.</td>
```

with:

```markdown
<td>Write the output of the expression to a temporary variable, which will disappear after the next <em>RUN</em> statement is executed. A <em>SET</em> statement that attempts to write to an existing permanent variable/column shall fail with an error message; use <em>LET</em> to recompute it, or <em>DROP</em> it first (effective after the next <em>RUN</em>) to redefine it as temporary under the same name.</td>
```

(This resolves the prior self-contradiction between this row and old §3.5 — note that in the commit message.)

- [ ] **Step 4: Update HELP text**

In `~/Develop/sdata/src/sdata-help.adb`, replace lines 183-188:

```ada
   procedure Help_LET is
   begin
      Put_Line ("Command: LET variable = expression");
      Put_Line ("Creates a permanent column in the table or updates an existing one.");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_LET;
```

with:

```ada
   procedure Help_LET is
   begin
      Put_Line ("Command: LET variable = expression");
      Put_Line ("Creates a permanent column in the table or updates an existing one.");
      Put_Line ("LET on an existing temporary (SET) variable is an error; use SET to");
      Put_Line ("recompute it, or UNSET it first to redefine it as permanent.");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_LET;
```

and replace lines 190-197:

```ada
   procedure Help_SET is
   begin
      Put_Line ("Command: SET variable = expression");
      Put_Line ("Creates a session variable not written to the output table.");
      Put_Line ("SET variables are not reset between records and persist across RUN calls.");
      Put_Line ("They are removed by UNSET or NEW, or when the session ends.");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_SET;
```

with:

```ada
   procedure Help_SET is
   begin
      Put_Line ("Command: SET variable = expression");
      Put_Line ("Creates a session variable not written to the output table.");
      Put_Line ("SET variables are not reset between records and persist across RUN calls.");
      Put_Line ("They are removed by UNSET or NEW, or when the session ends.");
      Put_Line ("SET on an existing permanent (table) variable is an error; use LET to");
      Put_Line ("recompute it, or DROP it first (effective after the next RUN) to");
      Put_Line ("redefine it as temporary.");
      Put_Line ("Execution: Deferred -- executed once per record inside the data step.");
   end Help_SET;
```

- [ ] **Step 5: Regenerate the `HELP /ALL` snapshot**

```bash
cd ~/Develop/sdata
alr build
./bin/sdata tests/help_all.cmd > tests/expected/help_all.out 2>&1
git diff tests/expected/help_all.out
```
Expected: a diff showing exactly the new lines added to the `LET` and `SET` sections, nothing else.

- [ ] **Step 6: Update the man page**

In `~/Develop/sdata/man/man1/sdata.1`, replace lines 917-930:

```
.B LET \fIvar\fR = \fIexpr\fR
Assign a permanent (table) variable.
Array element forms:
.B LET \fIarr\fR(\fIi\fR) = \fIexpr\fR
assigns a single element;
.B LET \fIarr\fR(\fIlo\fR:\fIhi\fR) = \fIexpr\fR
assigns a contiguous slice;
.B LET \fIarr\fR(\fIi\fR,\fIj\fR,...) = \fIexpr\fR
assigns a list of elements.
.TP
.B SET \fIvar\fR = \fIexpr\fR
Assign a temporary variable (not written to the output table).
Array element forms are the same as for
.BR LET .
```

with:

```
.B LET \fIvar\fR = \fIexpr\fR
Assign a permanent (table) variable.
Fails if
.I var
is already an existing temporary (SET) variable; use
.B SET
to recompute it, or
.B UNSET
it first to redefine it as permanent.
Array element forms:
.B LET \fIarr\fR(\fIi\fR) = \fIexpr\fR
assigns a single element;
.B LET \fIarr\fR(\fIlo\fR:\fIhi\fR) = \fIexpr\fR
assigns a contiguous slice;
.B LET \fIarr\fR(\fIi\fR,\fIj\fR,...) = \fIexpr\fR
assigns a list of elements.
.TP
.B SET \fIvar\fR = \fIexpr\fR
Assign a temporary variable (not written to the output table).
Fails if
.I var
is already an existing permanent (table) variable; use
.B LET
to recompute it, or
.B DROP
it first (effective after the next
.BR RUN )
to redefine it as temporary.
Array element forms are the same as for
.BR LET .
```

- [ ] **Step 7: Commit**

```bash
git add doc/design.md src/sdata-help.adb tests/expected/help_all.out man/man1/sdata.1
git commit -m "$(cat <<'EOF'
docs: SET/LET storage-class hard error across design.md, HELP, man page (#56)

Updates all three user-facing references together: design.md's §3.5
redefinition rules (replacing the old implicit-conversion bullets and
resolving its prior self-contradiction with the SET reference row),
HELP text for LET/SET (with regenerated HELP /ALL snapshot), and the
man page's Deferred-statements section.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: sdata — floor bump, version bump, full check, tag

**Files:**
- Modify: `~/Develop/sdata/alire.toml` (`sdata_core` floor; own version via script)
- Modify: 9 files touched by `scripts/bump-version.sh` (see script header)

**Interfaces:** none (packaging only).

- [ ] **Step 1: Bump the `sdata_core` floor**

In `~/Develop/sdata/alire.toml`, change:
```toml
sdata_core = "^0.3.0"
```
to:
```toml
sdata_core = "^0.3.2"
```

- [ ] **Step 2: Run the version bump script**

```bash
cd ~/Develop/sdata
scripts/bump-version.sh 0.16.2 "SET/LET storage-class redefinition is now a hard error (#56)"
```
The script will prompt twice (run tests? / commit?) — answer `y` to running tests (it runs `make check`, which you want to see pass with everything from Tasks 4-8 included) and `y` to committing.

- [ ] **Step 3: If the script's own `make check` run didn't already confirm it, run it explicitly**

```bash
cd ~/Develop/sdata && make check
```
Expected: 100% pass, no failures (this is the full gate: unit tests + all integration tests including the four new/changed ones from Tasks 4-7).

- [ ] **Step 4: Tag the release**

```bash
git tag -a v0.16.2 -m "Version 0.16.2"
```

- [ ] **Step 5: Push (main branch, plus the tag)**

```bash
git push origin main
git push origin v0.16.2
```

---

### Task 10: data-vandal — bump the sdata-core floor

No code or behavior changes expected (confirmed by the earlier search finding no LET/SET storage-class usage in data-vandal's test scripts) — this is a floor-constraint bump plus the mandatory cross-crate verification.

**Files:**
- Modify: `~/Develop/data-vandal/alire.toml` (`sdata_core` floor)

**Interfaces:** none.

- [ ] **Step 1: Create the branch and bump the floor**

```bash
cd ~/Develop/data-vandal
git checkout -b chore/56-sdata-core-floor-bump
```

In `alire.toml`, change:
```toml
sdata_core = "^0.3.0"
```
to:
```toml
sdata_core = "^0.3.2"
```

- [ ] **Step 2: Verify**

```bash
alr build
make check
```
Expected: clean build, all tests pass, no diffs anywhere (confirming the earlier finding that no data-vandal test exercises the changed behavior).

- [ ] **Step 3: Commit and open the PR**

```bash
git add alire.toml
git commit -m "$(cat <<'EOF'
chore: bump sdata-core floor to ^0.3.2 (#56)

sdata-core 0.3.2 makes SET/LET storage-class redefinition a hard
error (SData jlries61/sdata#56). No data-vandal code or test changes
required -- confirmed by make check and by an earlier search finding
no LET/SET storage-class usage in this crate's test scripts.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
git push -u origin chore/56-sdata-core-floor-bump
gh pr create --title "chore: bump sdata-core floor to ^0.3.2 (#56)" --body "$(cat <<'EOF'
## Summary
- Bumps the `sdata_core` floor to `^0.3.2` to track the SET/LET storage-class hard-error fix (sdata-core PR, sdata jlries61/sdata#56).
- No data-vandal code change: confirmed via `make check` and an earlier repo search finding no LET/SET storage-class usage in this crate's tests.

## Test plan
- [ ] `alr build` clean
- [ ] `make check` green
EOF
)"
```

---

### Task 11: sdata-core — bump the `consumer-tests.yml` pin

Keeps sdata-core's stability gate validating a current sdata release, per the crate's own `CLAUDE.md`.

**Files:**
- Modify: `~/Develop/sdata-core/.github/workflows/consumer-tests.yml` (`ref:` line, currently `v0.16.1`)

**Interfaces:** none.

- [ ] **Step 1: Confirm the sdata tag exists (from Task 9)**

```bash
git -C ~/Develop/sdata tag --sort=-creatordate | head -1
```
Expected: `v0.16.2`.

- [ ] **Step 2: Update the pin**

In `~/Develop/sdata-core/.github/workflows/consumer-tests.yml`, change:
```yaml
          ref: v0.16.1
```
to:
```yaml
          ref: v0.16.2
```

- [ ] **Step 3: Commit and open the PR (on the same `fix/56-set-let-storage-class` branch if still open, or a fresh branch if Task 3's PR already merged)**

```bash
cd ~/Develop/sdata-core
git checkout -b ci/bump-sdata-pin-v0.16.2 main   # if Task 3's branch already merged; otherwise reuse it
git add .github/workflows/consumer-tests.yml
git commit -m "$(cat <<'EOF'
ci(consumer-tests): bump sdata pin to v0.16.2 (#56)

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
git push -u origin ci/bump-sdata-pin-v0.16.2
gh pr create --title "ci(consumer-tests): bump sdata pin to v0.16.2" --body "$(cat <<'EOF'
## Summary
- Bumps the consumer-tests.yml sdata ref to v0.16.2, the release containing the SET/LET storage-class hard-error fix (#56), so the stability gate validates a current consumer.
EOF
)"
```

---

### Task 12: sdata-core — final `.ssd/current.yml` entry

Per sdata-core's `CLAUDE.md` cross-repo tracking rule (ADR-0009): a non-trivial sdata-core change must have an entry in *this crate's* `.ssd/current.yml`. This task runs last, after Tasks 3 and 11's PRs have actually merged, so the real PR URLs and merge commit SHAs are known (no placeholders).

**Files:**
- Modify: `~/Develop/sdata-core/.ssd/current.yml`

**Interfaces:** none.

- [ ] **Step 1: Gather the real PR/commit references**

```bash
cd ~/Develop/sdata-core
gh pr list --state merged --search "56" --json number,url,mergeCommit --limit 5
```
Note the PR number/URL/merge commit SHA for both the Task 3 PR (`fix/56-set-let-storage-class`) and the Task 11 PR (`ci/bump-sdata-pin-v0.16.2`).

- [ ] **Step 2: Append the archived entry**

In `~/Develop/sdata-core/.ssd/current.yml`, under the existing `archived:` list (matching the exact shape of neighboring entries — `slug`, `kind`, `phase`, `completed`, `pr_url`, `merge_commit`, `relates_to_finding`, `outcome`), add:

```yaml
  - slug: 56-set-let-storage-class
    kind: feature
    phase: done
    completed: 2026-07-25T00:00:00Z
    pr_url: <PASTE the Task 3 PR URL from Step 1>
    merge_commit: <PASTE the Task 3 PR merge commit SHA from Step 1>
    relates_to_finding: "sdata issue #56 (design review 2026-07-13, same family as #50-#52)"
    outcome: |
      SET on an existing permanent column and LET on an existing genuine
      temporary variable both now raise Script_Error instead of silently
      converting storage class. Closes a data-integrity footgun and the
      PDV/table desync (Drop_Column mid-record-loop) that corrupted SAVE
      output. ADR-0010 records the decision. Version 0.3.1 -> 0.3.2.
      Consumers: sdata 0.16.2 (4 new/changed tests, design.md/HELP/man page
      updated), data-vandal floor bump only (no code change). consumer-tests
      pin bumped to v0.16.2 (PR: <PASTE the Task 11 PR URL from Step 1>).
```

- [ ] **Step 3: Commit on a new branch and open a PR (sdata-core requires PRs, no direct push to `main`)**

```bash
git checkout -b docs/56-ssd-current-yml main
git add .ssd/current.yml
git commit -m "$(cat <<'EOF'
docs(ssd): record #56 storage-class fix in current.yml

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
git push -u origin docs/56-ssd-current-yml
gh pr create --title "docs(ssd): record #56 storage-class fix in current.yml" --body "$(cat <<'EOF'
## Summary
- Records the #56 SET/LET storage-class hard-error fix as an archived workstream in this crate's own .ssd/current.yml, per ADR-0009's cross-repo tracking rule.

Documentation-only; no build/test impact.
EOF
)"
```

---

## Self-Review Notes

- **Spec coverage:** §2 (decision) → Tasks 1-2. §3 (mechanism) → Tasks 1-2. §4 (documentation) → Tasks 3 (ADR, API reference), 8 (design.md/HELP/man page), 12 (.ssd). §5 (tests) → Tasks 1-2 (unit), 4-6 (new integration), 7 (rewritten fixture), Task 2 Step 6 (hold_test.cmd confirmation). §6 (versioning) → Tasks 3, 9, 10, 11. §7 (out of scope) → not implemented, correctly. §8 (affected files) → all present across Tasks 1-12.
- **Placeholder scan:** the only bracketed placeholders (`<PASTE ...>`) are in Task 12, and only because those values are PR URLs/SHAs that provably do not exist until Tasks 3 and 11 merge — Task 12 is explicitly sequenced last and its Step 1 shows the exact command to obtain them.
- **Type/name consistency:** `Set_Temporary`/`Set_Permanent` signatures unchanged throughout; error message text is identical between Task 1/2's Ada source and Tasks 4-6's expected-output captures (captured by running the built binary, not retyped); `V-56a`..`V-56e` check labels used consistently between Task 1 and Task 2's unit-test additions.
