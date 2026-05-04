# BY Group Edge Cases — Bug Fix and Regression Tests

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix a silent bug where `SELECT` filtering to zero records is ignored when `BY` is active, and add four regression/edge-case tests covering the BY group machinery.

**Architecture:** One-line bug fix in `sdata-table.adb`; four new `.cmd` + `.out` test pairs captured from the corrected binary.

**Tech Stack:** Ada 2012 / GNAT; `alr build`; `make check` test harness.

---

## Background

### The Bug

`SData.Table.Set_Index_Map` skips heap allocation when the filter matches zero records:

```ada
procedure Set_Index_Map (Map : Index_Array) is
begin
   Clear_Index_Map;
   if Map'Length > 0 then        -- ← wrong: leaves Filter_Map = null
      Filter_Map := new Index_Array'(Map);
   end if;
end Set_Index_Map;
```

`Filter_Map = null` is the sentinel for "no filter active." So when `SELECT` eliminates all records, `Logical_Row_Count` returns the full physical row count and `Is_Filtered` returns False — both wrong. The data step silently runs over all records instead of zero.

### The Fix

Remove the guard. A zero-length `Index_Array` is valid Ada; `Filter_Map'Length = 0` then makes `Logical_Row_Count` return 0 and `Is_Filtered` return True correctly.

```ada
procedure Set_Index_Map (Map : Index_Array) is
begin
   Clear_Index_Map;
   Filter_Map := new Index_Array'(Map);   -- null-range array is valid Ada
end Set_Index_Map;
```

No other functions require changes: `Logical_Row_Count` already branches on `Filter_Map = null` vs non-null; after the fix, a zero-match filter leaves a non-null pointer with `'Length = 0`, returning 0. `Logical_To_Physical` is never called when `Logical_Count = 0` (the loop doesn't execute), so the fallback branch in that function is unreachable in this case.

### Affected File

- **Modify:** `src/sdata-table.adb` — `Set_Index_Map` procedure (currently lines ~493–499)

---

## Test Cases

All four tests follow the standard harness: `.cmd` script in `tests/`, expected output in `tests/expected/`. Expected output is captured from the binary **after** the bug fix.

### Test 1: `by_select_empty` — zero-match SELECT regression

Verifies that a `SELECT` expression that eliminates all records causes the data step to process zero records, not all records.

```
REPEAT 3
LET X = RECNO()
RUN

BY X
SELECT X < 0
PRINT "SHOULD NOT APPEAR"
RUN
QUIT
```

Expected: second RUN reports `0 records`; no `PRINT` output appears.

### Test 2: `by_single_group` — all records same BY key

When all records share the same BY key there is exactly one group. BOG fires only on the first record; EOG fires only on the last; all interior records see BOG=0, EOG=0.

```
REPEAT 4
LET KEY = 1
LET VAL = RECNO()
RUN

BY KEY
PRINT VAL BOG() EOG()
RUN
QUIT
```

Expected BOG/EOG pattern: (1,0), (0,0), (0,0), (0,1).

### Test 3: `by_all_singletons` — every record a distinct BY key

When every record has a unique BY key there are N groups of one record each. Every record is simultaneously the first and last in its group: BOG=1 and EOG=1 for all rows.

```
REPEAT 4
LET KEY = RECNO()
LET VAL = RECNO()
RUN

BY KEY
PRINT VAL BOG() EOG()
RUN
QUIT
```

Expected: all four rows show BOG=1, EOG=1.

### Test 4: `by_compound` — compound BY key

Tests the multi-variable loop in `Is_First_In_Group` / `Is_Last_In_Group`. A group boundary fires when *either* BY variable changes.

```
REPEAT 8
LET IDX = RECNO()
LET A = IF(IDX <= 4, 1, 2)
LET B = IF(MOD(IDX, 2) = 1, 1, 2)
RUN

BY A B
PRINT A B BOG() EOG()
RUN
QUIT
```

After `BY A B` sort the four groups are (A=1,B=1)×2, (A=1,B=2)×2, (A=2,B=1)×2, (A=2,B=2)×2. Expected BOG/EOG pattern within each group: (1,0) then (0,1).

---

## Success Criterion

`make check` passes with **114 tests** (110 existing + 4 new). The `by_select_empty` test must fail before the bug fix is applied (confirming it is a true regression guard) and pass after.
