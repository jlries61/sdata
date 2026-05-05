# DIM Array Resize: Comment Cleanup and Expand/Shift Tests

## Goal

Remove two stale comments left over from before the dangling-column fix, and add
regression tests for the expand and shift resize scenarios.

## Background

Before the dangling-column fix (commit 8349462), `Dim_Array` had a `null` stub for
permanent arrays and two comments describing an intent that was never implemented:

```ada
-- Resizing - For now, clear all old elements, then recreate new.
-- TODO: Optimize for expansion/contraction to preserve values
```

The fix made the implementation correct: orphaned columns (outside the new range) are
dropped; kept columns (inside the new range) and their data are untouched;
`Create_Real_Elements` adds any new columns for an expanded range. The three resize
scenarios all work:

| Scenario | Example | Outcome |
|---|---|---|
| Shrink | DIM A(1 TO 5) → DIM A(1 TO 3) | A(4), A(5) dropped; A(1)–A(3) retained |
| Expand | DIM A(1 TO 3) → DIM A(1 TO 5) | A(1)–A(3) retained; A(4), A(5) added empty |
| Shift  | DIM A(1 TO 5) → DIM A(3 TO 7) | A(1), A(2) dropped; A(3)–A(5) retained; A(6), A(7) added empty |

The shrink scenario is covered by `tests/dim_array_resize.cmd`. Expand and shift are
not tested. The two stale comments are now misleading.

## Source Change

**File:** `src/sdata-variables.adb`, lines 519–520.

Replace:

```ada
               -- Resizing - For now, clear all old elements, then recreate new.
               -- TODO: Optimize for expansion/contraction to preserve values
```

With:

```ada
               -- Drop orphaned columns (outside new range); kept columns and their data are preserved.
```

## New Tests

Both tests follow the same NAMES-based pattern as `dim_array_resize.cmd`.

### Expand test

**File:** `tests/dim_array_expand.cmd`

```
REPEAT 1
DIM A(1 TO 3)
LET A(1) = 10
LET A(2) = 20
LET A(3) = 30
RUN
NAMES
REPEAT 1
DIM A(1 TO 5)
LET A(4) = 40
LET A(5) = 50
RUN
NAMES
```

Expected: first NAMES shows A(1)–A(3); second NAMES shows A(1)–A(5).

### Shift test

**File:** `tests/dim_array_shift.cmd`

```
REPEAT 1
DIM A(1 TO 5)
LET A(1) = 10
LET A(2) = 20
LET A(3) = 30
LET A(4) = 40
LET A(5) = 50
RUN
NAMES
REPEAT 1
DIM A(3 TO 7)
LET A(6) = 60
LET A(7) = 70
RUN
NAMES
```

Expected: first NAMES shows A(1)–A(5); second NAMES shows A(3)–A(7) (A(1) and A(2)
absent).

### Expected output capture

```bash
./bin/sdata tests/dim_array_expand.cmd > tests/expected/dim_array_expand.out 2>&1
./bin/sdata tests/dim_array_shift.cmd  > tests/expected/dim_array_shift.out  2>&1
```

Captured output is verified manually before committing.

## What Is Not Changing

- No functional behavior changes — all three resize scenarios already work correctly.
- No changes to `sdata-table.adb`, `Create_Real_Elements`, or any other file.
- No explicit value-assertion test (PRINT after resize without re-assigning): NAMES
  confirming column presence is sufficient since `Drop_Column` is the only mutation
  and is never called for in-range columns.

## Success Criteria

1. `alr build` succeeds with zero warnings.
2. `make check` passes all 110 tests (108 existing + 2 new).
3. Second NAMES in `dim_array_expand.cmd` shows 5 columns.
4. Second NAMES in `dim_array_shift.cmd` shows A(3)–A(7) with A(1) and A(2) absent.
