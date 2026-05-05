# BY Group Edge Cases Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix a silent bug where SELECT filtering to zero records is ignored, then add four BY group edge-case regression tests.

**Architecture:** One-line removal in `Set_Index_Map` (sdata-table.adb) fixes the bug; four `.cmd`/`.out` pairs added to the standard test harness cover the regression and three additional BY group edge cases.

**Tech Stack:** Ada 2012 / GNAT; `alr build`; `make check` harness (runs `./bin/sdata <file>.cmd`, diffs against `tests/expected/<file>.out`).

---

## Files

- **Modify:** `src/sdata-table.adb` lines 493–499 — remove the `Map'Length > 0` guard from `Set_Index_Map`
- **Create:** `tests/by_select_empty.cmd`
- **Create:** `tests/expected/by_select_empty.out`
- **Create:** `tests/by_single_group.cmd`
- **Create:** `tests/expected/by_single_group.out`
- **Create:** `tests/by_all_singletons.cmd`
- **Create:** `tests/expected/by_all_singletons.out`
- **Create:** `tests/by_compound.cmd`
- **Create:** `tests/expected/by_compound.out`

---

### Task 1: Fix Set_Index_Map and add the regression test

**Files:**
- Modify: `src/sdata-table.adb:493–499`
- Create: `tests/by_select_empty.cmd`
- Create: `tests/expected/by_select_empty.out`

- [ ] **Step 1: Write the regression test script**

Create `tests/by_select_empty.cmd` with this exact content:

```
-- Regression: SELECT that matches zero records must produce 0-record RUN,
-- not silently run over all records.
REPEAT 3
LET X = RECNO()
RUN

BY X
SELECT X < 0
PRINT "SHOULD NOT APPEAR"
RUN
QUIT
```

- [ ] **Step 2: Run the test against the unfixed binary to confirm it fails**

```bash
./bin/sdata tests/by_select_empty.cmd
```

Expected (buggy) output — PRINT fires for all three records, which is wrong:

```
RUN complete. 3 records and 1 variables processed.
SHOULD NOT APPEAR
SHOULD NOT APPEAR
SHOULD NOT APPEAR
RUN complete. 3 records and 1 variables processed.
```

If the output does NOT show "SHOULD NOT APPEAR", the bug is already fixed and this task is done. Otherwise continue.

- [ ] **Step 3: Apply the fix in src/sdata-table.adb**

Locate `Set_Index_Map` (around line 493). Replace:

```ada
   procedure Set_Index_Map (Map : Index_Array) is
   begin
      Clear_Index_Map;
      if Map'Length > 0 then
         Filter_Map := new Index_Array'(Map);
      end if;
   end Set_Index_Map;
```

With:

```ada
   procedure Set_Index_Map (Map : Index_Array) is
   begin
      Clear_Index_Map;
      Filter_Map := new Index_Array'(Map);
   end Set_Index_Map;
```

The only change is removing the `if Map'Length > 0 then` guard and its `end if;`. A zero-length `Index_Array` is valid Ada; the non-null pointer with `'Length = 0` then causes `Logical_Row_Count` to return 0 and `Is_Filtered` to return True — both correct.

- [ ] **Step 4: Build**

```bash
alr build 2>&1 | tail -5
```

Expected: build succeeds with no errors. If it fails, check the edit — the only change is removing two lines.

- [ ] **Step 5: Run the regression test and capture its expected output**

```bash
./bin/sdata tests/by_select_empty.cmd > tests/expected/by_select_empty.out
cat tests/expected/by_select_empty.out
```

Expected content (verify manually — "SHOULD NOT APPEAR" must NOT be present, second RUN must show 0 records):

```
RUN complete. 3 records and 1 variables processed.
RUN complete. 0 records and 1 variables processed.
```

- [ ] **Step 6: Run the full test suite to confirm no regressions**

```bash
make check 2>&1 | tail -5
```

Expected: 111 tests pass (110 existing + 1 new). If any existing test fails, the fix has a side effect — investigate before continuing.

- [ ] **Step 7: Commit**

```bash
git add src/sdata-table.adb tests/by_select_empty.cmd tests/expected/by_select_empty.out
git commit -m "fix: Set_Index_Map zero-match filter bug; add regression test

When SELECT matched zero records, the if Map'Length > 0 guard left
Filter_Map = null, indistinguishable from 'no filter active'. The data
step then ran over all physical rows instead of zero. Removing the guard
lets a zero-length Index_Array be allocated; Logical_Row_Count returns 0
and Is_Filtered returns True correctly.

Regression: tests/by_select_empty.cmd"
```

---

### Task 2: Add three BY group edge-case tests

**Files:**
- Create: `tests/by_single_group.cmd`
- Create: `tests/expected/by_single_group.out`
- Create: `tests/by_all_singletons.cmd`
- Create: `tests/expected/by_all_singletons.out`
- Create: `tests/by_compound.cmd`
- Create: `tests/expected/by_compound.out`

- [ ] **Step 1: Write by_single_group.cmd**

All four records share the same BY key (KEY=1), forming exactly one group. BOG must fire only on record 1; EOG only on record 4; interior records see both as 0.

Create `tests/by_single_group.cmd`:

```
-- Edge case: all records share the same BY key → one group.
-- BOG=1 on first record only; EOG=1 on last record only.
REPEAT 4
LET KEY = 1
LET VAL = RECNO()
RUN

BY KEY
PRINT VAL BOG() EOG()
RUN
QUIT
```

- [ ] **Step 2: Capture by_single_group expected output**

```bash
./bin/sdata tests/by_single_group.cmd > tests/expected/by_single_group.out
cat tests/expected/by_single_group.out
```

Verify manually that the output matches this pattern (exact numeric format will be sdata's standard floating-point):

```
RUN complete. 4 records and 2 variables processed.
1.00000 1.00000 0.00000
2.00000 0.00000 0.00000
3.00000 0.00000 0.00000
4.00000 0.00000 1.00000
RUN complete. 4 records and 3 variables processed.
```

BOG=1 (1.00000) for VAL=1 only; EOG=1 for VAL=4 only; interior rows show 0.00000 for both. If the pattern is wrong, investigate — all four records have KEY=1 so there should be one group.

- [ ] **Step 3: Write by_all_singletons.cmd**

Every record has a unique BY key, producing N groups of exactly one record. Every record must be simultaneously BOG=1 and EOG=1.

Create `tests/by_all_singletons.cmd`:

```
-- Edge case: every record has a distinct BY key → N singleton groups.
-- Every record must show BOG=1 and EOG=1.
REPEAT 4
LET KEY = RECNO()
LET VAL = RECNO()
RUN

BY KEY
PRINT VAL BOG() EOG()
RUN
QUIT
```

- [ ] **Step 4: Capture by_all_singletons expected output**

```bash
./bin/sdata tests/by_all_singletons.cmd > tests/expected/by_all_singletons.out
cat tests/expected/by_all_singletons.out
```

Verify: all four data rows must show BOG=1.00000 and EOG=1.00000:

```
RUN complete. 4 records and 2 variables processed.
1.00000 1.00000 1.00000
2.00000 1.00000 1.00000
3.00000 1.00000 1.00000
4.00000 1.00000 1.00000
RUN complete. 4 records and 3 variables processed.
```

- [ ] **Step 5: Write by_compound.cmd**

Tests the multi-variable path in `Is_First_In_Group` / `Is_Last_In_Group`. Group boundaries fire when *either* BY variable changes. The script produces four groups of two records each: (A=1,B=1), (A=1,B=2), (A=2,B=1), (A=2,B=2).

Create `tests/by_compound.cmd`:

```
-- Edge case: compound BY key (BY A B).
-- Group boundary fires when either A or B changes.
-- Four groups of 2: (1,1) (1,2) (2,1) (2,2). Each group: BOG then EOG.
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

- [ ] **Step 6: Capture by_compound expected output**

```bash
./bin/sdata tests/by_compound.cmd > tests/expected/by_compound.out
cat tests/expected/by_compound.out
```

Verify: after `BY A B` sort the physical order within each group is stable (merge sort). The four groups in sorted order are (A=1,B=1)×2, (A=1,B=2)×2, (A=2,B=1)×2, (A=2,B=2)×2. Within each group the first record shows BOG=1 EOG=0 and the second shows BOG=0 EOG=1:

```
RUN complete. 8 records and 3 variables processed.
1.00000 1.00000 1.00000 0.00000
1.00000 1.00000 0.00000 1.00000
1.00000 2.00000 1.00000 0.00000
1.00000 2.00000 0.00000 1.00000
2.00000 1.00000 1.00000 0.00000
2.00000 1.00000 0.00000 1.00000
2.00000 2.00000 1.00000 0.00000
2.00000 2.00000 0.00000 1.00000
RUN complete. 8 records and 4 variables processed.
```

- [ ] **Step 7: Run the full test suite**

```bash
make check 2>&1 | tail -5
```

Expected: **114 tests pass** (111 from Task 1 + 3 new). If any test fails, inspect the `.tmp` diff file the harness leaves in `tests/`.

- [ ] **Step 8: Commit**

```bash
git add tests/by_single_group.cmd tests/expected/by_single_group.out \
        tests/by_all_singletons.cmd tests/expected/by_all_singletons.out \
        tests/by_compound.cmd tests/expected/by_compound.out
git commit -m "tests: BY group edge cases (single group, all singletons, compound key)"
```
