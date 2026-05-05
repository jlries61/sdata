# DIM Array Resize Comment Cleanup and Expand/Shift Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove two stale comments left over from before the dangling-column fix and add regression tests for the expand and shift resize scenarios.

**Architecture:** Single `if` block comment replacement in `Dim_Array` inside `src/sdata-variables.adb`. Two new test scripts using the existing `make check` diff harness; expected output is captured from `./bin/sdata` after verifying correctness.

**Tech Stack:** Ada 2012, GNAT, `alr build`, `make check`.

---

### Task 1: Remove stale comments and add expand/shift regression tests

**Files:**
- Modify: `src/sdata-variables.adb:519-520`
- Create: `tests/dim_array_expand.cmd`
- Create: `tests/dim_array_shift.cmd`
- Create: `tests/expected/dim_array_expand.out`
- Create: `tests/expected/dim_array_shift.out`

Work from: `/home/jries/Develop/sdata`

- [ ] **Step 1: Create the two test scripts**

```bash
printf 'REPEAT 1\nDIM A(1 TO 3)\nLET A(1) = 10\nLET A(2) = 20\nLET A(3) = 30\nRUN\nNAMES\nREPEAT 1\nDIM A(1 TO 5)\nLET A(4) = 40\nLET A(5) = 50\nRUN\nNAMES\n' > tests/dim_array_expand.cmd

printf 'REPEAT 1\nDIM A(1 TO 5)\nLET A(1) = 10\nLET A(2) = 20\nLET A(3) = 30\nLET A(4) = 40\nLET A(5) = 50\nRUN\nNAMES\nREPEAT 1\nDIM A(3 TO 7)\nLET A(6) = 60\nLET A(7) = 70\nRUN\nNAMES\n' > tests/dim_array_shift.cmd
```

- [ ] **Step 2: Confirm both tests fail with the correct TDD failure**

```bash
make check 2>&1 | grep "dim_array_expand\|dim_array_shift"
```

Expected:

```
Testing tests/dim_array_expand.cmd... FAILED (no expected output file)
Testing tests/dim_array_shift.cmd... FAILED (no expected output file)
```

If either shows a different failure reason (e.g., a non-zero exit code or a content mismatch against a stale `.out`), stop and investigate. The only acceptable failure at this stage is `(no expected output file)`.

- [ ] **Step 3: Apply the comment fix to src/sdata-variables.adb**

Find lines 519–520. Replace:

```ada
               -- Resizing - For now, clear all old elements, then recreate new.
               -- TODO: Optimize for expansion/contraction to preserve values
```

With:

```ada
               -- Drop orphaned columns (outside new range); kept columns and their data are preserved.
```

The surrounding context for reference — the replacement goes immediately before the `for I in` loop:

```ada
               end if;
               
               -- Drop orphaned columns (outside new range); kept columns and their data are preserved.
               for I in Existing_Def.Start_Index .. Existing_Def.End_Index loop
```

- [ ] **Step 4: Build and confirm zero warnings**

```bash
alr build 2>&1 | grep -E "warning|error" | grep -v "^$"
```

Expected: no output (zero warnings, zero errors). If any warnings appear, fix them before continuing.

- [ ] **Step 5: Capture expected output for both tests**

```bash
./bin/sdata tests/dim_array_expand.cmd > tests/expected/dim_array_expand.out 2>&1
./bin/sdata tests/dim_array_shift.cmd  > tests/expected/dim_array_shift.out  2>&1
```

- [ ] **Step 6: Verify the captured output is correct**

```bash
cat tests/expected/dim_array_expand.out
```

The expand output must show **3 column names** after the first `NAMES` (`A(1)`, `A(2)`, `A(3)`) and **5 column names** after the second `NAMES` (`A(1)` through `A(5)`). If it shows 5 columns in both NAMES blocks, the expand path is broken — check that `alr build` rebuilt the binary.

```bash
cat tests/expected/dim_array_shift.out
```

The shift output must show **5 column names** after the first `NAMES` (`A(1)` through `A(5)`) and **5 column names** after the second `NAMES` (`A(3)` through `A(7)`). Crucially, `A(1)` and `A(2)` must be **absent** from the second NAMES block. If they appear, the orphan-drop guard is failing for the shift case — check the binary is fresh.

- [ ] **Step 7: Run make check to confirm all 110 tests pass**

```bash
make check 2>&1 | tail -3
```

Expected:

```
All 110 tests passed.
```

If either new test fails with an output mismatch, compare the diff printed by `make check` against what you expect. A mismatch here usually means the capture in Step 5 picked up an extra blank line or the NAMES formatter produces a slightly different layout than anticipated. Re-run the capture for just the failing test and re-run `make check`.

- [ ] **Step 8: Commit**

```bash
git add src/sdata-variables.adb tests/dim_array_expand.cmd tests/dim_array_shift.cmd tests/expected/dim_array_expand.out tests/expected/dim_array_shift.out
git commit -m "$(cat <<'EOF'
tests: add expand and shift resize tests; remove stale TODO comment

DIM array resize already handles all three scenarios correctly (shrink
covered by dim_array_resize.cmd). Add dim_array_expand.cmd (1→3 to 1→5)
and dim_array_shift.cmd (1→5 to 3→7) to cover the remaining cases.
Remove the now-inaccurate "clear all elements / TODO preserve values"
comments — the implementation has been correct since the dangling-column
fix in 8349462.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```
