# DIM Array Resize Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the dangling-column bug where re-DIM'ing a permanent array to a smaller range leaves the out-of-range table columns in place.

**Architecture:** Single `if` block replacement in `Dim_Array` inside `src/sdata-variables.adb`. The existing `SData.Table.Drop_Column` API (already used by the interpreter's `DROP` statement) is called for each old-range index that falls outside the new bounds. One new regression test using the existing `make check` diff harness.

**Tech Stack:** Ada 2012, GNAT, `alr build`, `make check`.

---

### Task 1: Fix dangling column cleanup in Dim_Array

**Files:**
- Modify: `src/sdata-variables.adb:526-532`
- Create: `tests/dim_array_resize.cmd`
- Create: `tests/expected/dim_array_resize.out`

Work from: `/home/jries/Develop/sdata`

- [ ] **Step 1: Write the failing test**

Create `tests/dim_array_resize.cmd` with exactly this content:

```
DIM A(1:5)
NAMES
DIM A(1:3)
NAMES
```

```bash
printf 'DIM A(1:5)\nNAMES\nDIM A(1:3)\nNAMES\n' > tests/dim_array_resize.cmd
```

- [ ] **Step 2: Run make check to confirm the test fails cleanly**

```bash
make check 2>&1 | grep "dim_array_resize"
```

Expected:

```
Testing tests/dim_array_resize.cmd... FAILED (no expected output file)
```

If it shows any other failure reason, stop and investigate. `(no expected output file)` is the correct TDD failure at this stage.

- [ ] **Step 3: Apply the fix to src/sdata-variables.adb**

Find lines 526–532 (the `if … null; end if;` block inside the resize loop). Replace:

```ada
                     if not Existing_Def.Is_Temporary and then SData.Table.Has_Column (Var_Name) then
                        -- For permanent real array elements, we should remove column if it's outside new bounds
                        -- but not if it's within the new bounds (to avoid data loss)
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

**What changed:**
- Added the guard `and then (I < Start_Idx or else I > End_Idx)` so only out-of-range columns are dropped.
- Replaced `null` with `SData.Table.Drop_Column (Var_Name)`.
- Removed the four stale comments. The `-- TODO: Optimize for expansion/contraction to preserve values` comment on line 520 is **left in place** — it refers to a separate future feature.

- [ ] **Step 4: Build and confirm zero warnings**

```bash
alr build 2>&1 | grep -E "warning|error" | grep -v "^$"
```

Expected: no output (zero warnings, zero errors). If the build fails, check the indentation of the replacement block — Ada is sensitive to indentation only for readability, but mismatched `end if` or missing `then` will cause a compile error.

- [ ] **Step 5: Capture expected output**

```bash
./bin/sdata tests/dim_array_resize.cmd > tests/expected/dim_array_resize.out 2>&1
```

- [ ] **Step 6: Verify the captured output shows the fix worked**

```bash
cat tests/expected/dim_array_resize.out
```

The output must show exactly **5 column names** after the first `NAMES` and exactly **3 column names** after the second `NAMES`. The column names will appear as `A(1)`, `A(2)`, etc. (exact format depends on the NAMES formatter).

If the second NAMES block still shows 5 columns, the fix did not take effect — check that `alr build` actually rebuilt the binary (look for `obj/` timestamps or re-run `alr build` explicitly).

- [ ] **Step 7: Run make check to confirm all 108 tests pass**

```bash
make check 2>&1 | tail -3
```

Expected:

```
All 108 tests passed.
```

- [ ] **Step 8: Commit**

```bash
git add src/sdata-variables.adb tests/dim_array_resize.cmd tests/expected/dim_array_resize.out
git commit -m "$(cat <<'EOF'
fix: drop out-of-range columns when re-DIM'ing a permanent array

When DIM A(1:5) is followed by DIM A(1:3), columns A(4) and A(5) were
silently left in the table. Replace the null stub with a Drop_Column
call guarded by (I < Start_Idx or else I > End_Idx) so only orphaned
columns are removed; overlapping columns retain their data.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```
