# DIM Array Resize: Dangling Column Cleanup

## Goal

Fix a correctness bug in `Dim_Array`: when a permanent array is re-DIM'd to a
smaller range, table columns for indices outside the new bounds are silently
left in the table. They should be dropped.

## Background

Permanent real array elements are stored as named table columns (e.g., `A(1)`,
`A(2)`, …). When `DIM A(1:5)` is followed by `DIM A(1:3)`, the resize path in
`Dim_Array` currently does nothing for permanent elements — it leaves `A(4)`
and `A(5)` as orphaned columns in `Data_Table`. A subsequent `NAMES` or `SAVE`
would expose those columns even though the array no longer covers them.

Temporary array elements are handled correctly: the same loop deletes them from
`Temp_Symbols`.

## The Fix

**File:** `src/sdata-variables.adb`, inside `Dim_Array`, lines 526–531.

Replace:

```ada
if not Existing_Def.Is_Temporary and then SData.Table.Has_Column (Var_Name) then
   -- For simplicity, let's just leave old columns for now if permanent.
   -- A separate garbage collection might be needed.
   null;
end if;
```

With:

```ada
if not Existing_Def.Is_Temporary and then SData.Table.Has_Column (Var_Name)
   and then (I < Start_Idx or else I > End_Idx)
then
   SData.Table.Drop_Column (Var_Name);
end if;
```

**Why the guard `I < Start_Idx or else I > End_Idx`:**
Columns in the overlapping range (present in both old and new bounds) are left
alone. Their existing data survives, and `Create_Real_Elements` will not
recreate them (it skips columns that already exist via `Has_Column`). Only
truly orphaned columns — those outside the new range — are dropped.

`Drop_Column` is already part of the public Table API (`sdata-table.ads:55`)
and is used by the interpreter's `DROP` statement handler. No new API needed.

## What Is Not Changing

- Temporary array resize path — already correct.
- `Create_Real_Elements` — untouched.
- The `-- TODO: Optimize for expansion/contraction to preserve values` comment
  — that refers to the separate value-preservation feature (deferred). Only
  the stale "leave old columns for now" comment is removed.
- No changes to `sdata-table.adb` or any other file.

## Test

**File:** `tests/dim_array_resize.cmd`

```
DIM A(1:5)
NAMES
DIM A(1:3)
NAMES
```

**Expected behavior after fix:**
- First `NAMES`: lists `A(1)`, `A(2)`, `A(3)`, `A(4)`, `A(5)`
- Second `NAMES`: lists only `A(1)`, `A(2)`, `A(3)`

This test **currently fails** (both NAMES calls show 5 columns). It passes
after the fix. Expected output is captured from `./bin/sdata` after the fix is
applied.

## Success Criteria

1. `alr build` succeeds with zero warnings.
2. `tests/dim_array_resize.cmd` passes (second NAMES shows 3 columns).
3. `make check` passes all 108 tests.
