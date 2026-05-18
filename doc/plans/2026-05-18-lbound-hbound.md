# LBOUND / HBOUND Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `HBOUND` as a SAS-compatible alias for `UBOUND`, and add full HELP and man-page documentation for all three array-bound functions (`LBOUND`, `UBOUND`, `HBOUND`).

**Architecture:** `HBOUND` is registered in the dispatch table pointing to the existing `Handle_Ubound` handler, following the same alias pattern used for `LOGE`/`LN`, `LAGC$`/`LAG`, etc. `LBOUND` and `UBOUND` already work; this PR adds the missing SAS alias and fills the documentation gap that exists for all three.

**Tech Stack:** Ada 2012, GNAT/GPRbuild via Alire. Build: `alr build`. All tests: `make check` (unit tests + 131 `.cmd` integration tests).

---

## Files

| Action | File | Change |
|---|---|---|
| Modify | `src/sdata-evaluator.adb:152-153` | Add `"HBOUND"` to `Is_Identifier_Ref_Function` |
| Modify | `src/sdata-evaluator-misc_fns.adb:364` | Register `HBOUND` in dispatch table |
| Modify | `src/sdata-help.adb` | Add key constants, help procedures, table entries, update index line |
| Modify | `man/man1/sdata.1:642-643` | Insert new `.SS Arrays` subsection |
| Modify | `tests/sdata_unit_test.adb:431-433` | Add E-14 HBOUND check; renumber E-14→E-15, E-15→E-16 |
| Modify | `tests/new_functions_test.cmd:53` | Add two `PRINT HBOUND(...)` lines |
| Modify | `tests/expected/new_functions_test.out` | Add two result lines after UBOUND(B) |
| Modify | `tests/expected/help_index.out:24` | Add `HBOUND` to Arrays line |
| Create | `tests/help_lbound.cmd` | `HELP LBOUND` integration test |
| Create | `tests/expected/help_lbound.out` | Expected output for HELP LBOUND |
| Create | `tests/help_ubound.cmd` | `HELP UBOUND` integration test |
| Create | `tests/expected/help_ubound.out` | Expected output for HELP UBOUND |
| Create | `tests/help_hbound.cmd` | `HELP HBOUND` integration test |
| Create | `tests/expected/help_hbound.out` | Expected output for HELP HBOUND |
| Regen  | `tests/expected/help_all.out` | Regenerate after help table entries are added |

---

## Task 1: Failing unit test for HBOUND identifier-ref

**Files:**
- Modify: `tests/sdata_unit_test.adb:431-433`

- [ ] **Step 1.1: Insert failing unit test and renumber**

Open `tests/sdata_unit_test.adb`. Replace lines 431–433 (the block ending the identifier-ref section) with:

```ada
   Check ("E-13 UBOUND is identifier-ref",       Is_Identifier_Ref_Function ("UBOUND"), True);
   Check ("E-14 HBOUND is identifier-ref",       Is_Identifier_Ref_Function ("HBOUND"), True);
   Check ("E-15 ABS is not identifier-ref",      Is_Identifier_Ref_Function ("ABS"),    False);
   Check ("E-16 SQRT is not identifier-ref",     Is_Identifier_Ref_Function ("SQRT"),   False);
```

- [ ] **Step 1.2: Build and verify E-14 fails**

```bash
alr build 2>&1 | tail -5
./bin/sdata_unit_test 2>&1 | grep -E "E-14|FAILED|passed"
```

Expected: build succeeds; `E-14 HBOUND is identifier-ref` reports FAILED (returns False, not True). Overall unit test suite reports a failure.

---

## Task 2: Failing integration test for HBOUND

**Files:**
- Modify: `tests/new_functions_test.cmd:53`

- [ ] **Step 2.1: Add HBOUND prints to integration test script**

Open `tests/new_functions_test.cmd`. After line 53 (`PRINT UBOUND(B)`), insert two lines so the LBOUND/UBOUND/HBOUND block reads:

```
-- LBOUND / UBOUND: custom and default subscript ranges
DIM A(3 TO 7)
DIM B(5)
PRINT LBOUND(A)
PRINT UBOUND(A)
PRINT LBOUND(B)
PRINT UBOUND(B)
PRINT HBOUND(A)
PRINT HBOUND(B)
```

- [ ] **Step 2.2: Verify integration test now fails**

```bash
./bin/sdata tests/new_functions_test.cmd > /tmp/nft_actual.out 2>&1
diff tests/expected/new_functions_test.out /tmp/nft_actual.out
```

Expected: `diff` shows that the actual output is missing the two new lines (`7` and `5` for HBOUND(A) and HBOUND(B)), because HBOUND is not yet registered.

---

## Task 3: Implement HBOUND in the evaluator

**Files:**
- Modify: `src/sdata-evaluator.adb:152-153`
- Modify: `src/sdata-evaluator-misc_fns.adb:364`

- [ ] **Step 3.1: Add HBOUND to Is_Identifier_Ref_Function**

Open `src/sdata-evaluator.adb`. At line 152–153, change:

```ada
      return U in "LAG" | "LAGC$" | "NEXT" | "NEXTC$" | "OBS" | "OBSC$"
                | "LBOUND" | "UBOUND";
```

to:

```ada
      return U in "LAG" | "LAGC$" | "NEXT" | "NEXTC$" | "OBS" | "OBSC$"
                | "LBOUND" | "UBOUND" | "HBOUND";
```

- [ ] **Step 3.2: Register HBOUND in the dispatch table**

Open `src/sdata-evaluator-misc_fns.adb`. After line 364 (`Dispatch_Table.Insert ("UBOUND", ...)`), insert:

```ada
      Dispatch_Table.Insert ("HBOUND",  Handle_Ubound'Access);
```

So the block reads:

```ada
      Dispatch_Table.Insert ("LBOUND",  Handle_Lbound'Access);
      Dispatch_Table.Insert ("UBOUND",  Handle_Ubound'Access);
      Dispatch_Table.Insert ("HBOUND",  Handle_Ubound'Access);
```

- [ ] **Step 3.3: Build**

```bash
alr build 2>&1 | tail -5
```

Expected: build succeeds with no errors.

---

## Task 4: Update expected outputs and verify all tests pass

**Files:**
- Modify: `tests/expected/new_functions_test.out`
- Modify: `tests/sdata_unit_test.adb` (already done — just verifying)

- [ ] **Step 4.1: Update new_functions_test.out**

Open `tests/expected/new_functions_test.out`. After line 26 (which contains `5`, the result of `UBOUND(B)`), insert two new lines:

```
7
5
```

The file from line 23 onwards should now read:

```
3
7
1
5
7
5
0.00000
0.56714
1.00000
RUN complete. 1 records and 10 variables processed.
```

- [ ] **Step 4.2: Run make check and confirm all tests pass**

```bash
make check 2>&1 | tail -20
```

Expected: all unit tests pass (including E-14 HBOUND); `new_functions_test` passes; all 131 integration tests pass. Zero failures.

- [ ] **Step 4.3: Commit evaluator changes**

```bash
git add src/sdata-evaluator.adb src/sdata-evaluator-misc_fns.adb \
        tests/sdata_unit_test.adb \
        tests/new_functions_test.cmd tests/expected/new_functions_test.out
git commit -m "feat: add HBOUND as SAS-compatible alias for UBOUND"
```

---

## Task 5: Add HELP procedures and table entries

**Files:**
- Modify: `src/sdata-help.adb`

- [ ] **Step 5.1: Add Help_LBOUND and Help_UBOUND procedures**

Open `src/sdata-help.adb`. After line 817 (the end of `Help_OBS`), before the `-- Special functions` banner at line 819, insert a new section:

```ada
   -- ==========================================================================
   --  Array functions
   -- ==========================================================================

   procedure Help_LBOUND is
   begin
      Put_Line ("Function: LBOUND(arrayname)");
      Put_Line ("Returns the lower bound (first valid subscript) of the named array.");
      Put_Line ("Works for both virtual arrays (ARRAY) and real arrays (DIM).");
      Put_Line ("Returns missing if the array does not exist.");
      Put_Line ("The array name may be given unquoted: LBOUND(A) is equivalent to LBOUND(""A"").");
      Put_Line ("See also: UBOUND, HBOUND");
   end Help_LBOUND;

   procedure Help_UBOUND is
   begin
      Put_Line ("Function: UBOUND(arrayname) / HBOUND(arrayname)");
      Put_Line ("Returns the upper bound (last valid subscript) of the named array.");
      Put_Line ("HBOUND is the SAS-compatible spelling; UBOUND is retained for compatibility.");
      Put_Line ("Works for both virtual arrays (ARRAY) and real arrays (DIM).");
      Put_Line ("Returns missing if the array does not exist.");
      Put_Line ("The array name may be given unquoted: UBOUND(A) is equivalent to UBOUND(""A"").");
      Put_Line ("See also: LBOUND");
   end Help_UBOUND;

```

- [ ] **Step 5.2: Add key constants**

Still in `src/sdata-help.adb`. After the last key constant (`K_LRN`, currently the last entry before the `C`/`F`/`N` Boolean constants), add:

```ada
   K_LBOUND  : aliased constant String := "LBOUND";
   K_UBOUND  : aliased constant String := "UBOUND";
   K_HBOUND  : aliased constant String := "HBOUND";
```

- [ ] **Step 5.3: Add Help_Table entries**

In the `Help_Table` array, find the record-navigation block ending with:

```ada
      (K_OBSCS'Access,    Help_OBS'Access,      N, N),   --  alias
      --  Special functions
```

Insert between those two lines:

```ada
      --  Array functions
      (K_LBOUND'Access,   Help_LBOUND'Access,   N, F),
      (K_UBOUND'Access,   Help_UBOUND'Access,   N, F),
      (K_HBOUND'Access,   Help_UBOUND'Access,   N, N),   --  SAS alias
```

- [ ] **Step 5.4: Update Help_Index Arrays line**

In `Help_Index` (near line 39), change:

```ada
      Put_Line ("  Arrays:      LBOUND, UBOUND");
```

to:

```ada
      Put_Line ("  Arrays:      LBOUND, UBOUND, HBOUND");
```

- [ ] **Step 5.5: Build**

```bash
alr build 2>&1 | tail -5
```

Expected: succeeds.

---

## Task 6: Create HELP integration tests

**Files:**
- Create: `tests/help_lbound.cmd` and `tests/expected/help_lbound.out`
- Create: `tests/help_ubound.cmd` and `tests/expected/help_ubound.out`
- Create: `tests/help_hbound.cmd` and `tests/expected/help_hbound.out`
- Modify: `tests/expected/help_index.out:24`

- [ ] **Step 6.1: Create help_lbound test**

Create `tests/help_lbound.cmd`:
```
HELP LBOUND
```

Create `tests/expected/help_lbound.out`:
```
Function: LBOUND(arrayname)
Returns the lower bound (first valid subscript) of the named array.
Works for both virtual arrays (ARRAY) and real arrays (DIM).
Returns missing if the array does not exist.
The array name may be given unquoted: LBOUND(A) is equivalent to LBOUND("A").
See also: UBOUND, HBOUND
```

- [ ] **Step 6.2: Create help_ubound test**

Create `tests/help_ubound.cmd`:
```
HELP UBOUND
```

Create `tests/expected/help_ubound.out`:
```
Function: UBOUND(arrayname) / HBOUND(arrayname)
Returns the upper bound (last valid subscript) of the named array.
HBOUND is the SAS-compatible spelling; UBOUND is retained for compatibility.
Works for both virtual arrays (ARRAY) and real arrays (DIM).
Returns missing if the array does not exist.
The array name may be given unquoted: UBOUND(A) is equivalent to UBOUND("A").
See also: LBOUND
```

- [ ] **Step 6.3: Create help_hbound test**

Create `tests/help_hbound.cmd`:
```
HELP HBOUND
```

Create `tests/expected/help_hbound.out` with the same content as `help_ubound.out` (HBOUND is an alias pointing to the same handler):
```
Function: UBOUND(arrayname) / HBOUND(arrayname)
Returns the upper bound (last valid subscript) of the named array.
HBOUND is the SAS-compatible spelling; UBOUND is retained for compatibility.
Works for both virtual arrays (ARRAY) and real arrays (DIM).
Returns missing if the array does not exist.
The array name may be given unquoted: UBOUND(A) is equivalent to UBOUND("A").
See also: LBOUND
```

- [ ] **Step 6.4: Update help_index.out**

Open `tests/expected/help_index.out`. Find line 24:
```
  Arrays:      LBOUND, UBOUND
```
Change it to:
```
  Arrays:      LBOUND, UBOUND, HBOUND
```

- [ ] **Step 6.5: Regenerate help_all.out**

The `HELP /ALL` output now includes LBOUND and UBOUND entries (they were absent before). Regenerate the expected file:

```bash
./bin/sdata tests/help_all.cmd > tests/expected/help_all.out 2>&1
```

Then visually inspect the new content to confirm it looks correct:

```bash
grep -A7 "LBOUND\|UBOUND\|HBOUND" tests/expected/help_all.out
```

Expected: the three entries appear in the FUNCTION REFERENCE section of the `HELP /ALL` output, with `HBOUND` absent (it has `In_Func => N` so it is treated as an alias and omitted from the reference listing).

- [ ] **Step 6.6: Run make check**

```bash
make check 2>&1 | tail -20
```

Expected: all tests pass. Count should now be 134 integration tests (131 original + help_lbound, help_ubound, help_hbound).

- [ ] **Step 6.7: Commit help changes**

```bash
git add src/sdata-help.adb \
        tests/help_lbound.cmd tests/expected/help_lbound.out \
        tests/help_ubound.cmd tests/expected/help_ubound.out \
        tests/help_hbound.cmd tests/expected/help_hbound.out \
        tests/expected/help_index.out tests/expected/help_all.out
git commit -m "docs: add HELP entries for LBOUND, UBOUND, and HBOUND"
```

---

## Task 7: Add man-page Arrays subsection

**Files:**
- Modify: `man/man1/sdata.1:642-643`

- [ ] **Step 7.1: Insert Arrays subsection**

Open `man/man1/sdata.1`. Find the boundary between the `Special` subsection and `Statistical distributions` subsection — specifically after line 642 (`Reset to 0 by`) and its following `.BR NEW .` line, immediately before `.SS Statistical distributions`. Insert:

```nroff
.SS Arrays
.BR LBOUND ( arrayname )
\(em lower bound (first valid subscript) of the named array.
.br
.BR UBOUND ( arrayname )\ /\ HBOUND ( arrayname )
\(em upper bound (last valid subscript) of the named array.
.B HBOUND
is the SAS\-compatible spelling;
.B UBOUND
is retained for compatibility.
.br
Both functions accept the array name as a bare identifier or as a string literal.
Returns missing if the array does not exist.
```

The result should read (in context):

```nroff
Reset to 0 by
.BR NEW .
.SS Arrays
.BR LBOUND ( arrayname )
\(em lower bound (first valid subscript) of the named array.
.br
.BR UBOUND ( arrayname )\ /\ HBOUND ( arrayname )
\(em upper bound (last valid subscript) of the named array.
.B HBOUND
is the SAS\-compatible spelling;
.B UBOUND
is retained for compatibility.
.br
Both functions accept the array name as a bare identifier or as a string literal.
Returns missing if the array does not exist.
.SS Statistical distributions
```

- [ ] **Step 7.2: Verify man page renders without errors**

```bash
man -l man/man1/sdata.1 2>&1 | grep -i "error\|warning" | head -5
```

Expected: no errors. (If `man -l` is unavailable, try `groff -man -Tascii man/man1/sdata.1 > /dev/null`.)

- [ ] **Step 7.3: Run make check one final time**

```bash
make check 2>&1 | tail -5
```

Expected: all tests pass (man page change has no automated test, but confirming nothing else broke).

- [ ] **Step 7.4: Commit man page**

```bash
git add man/man1/sdata.1
git commit -m "docs: document LBOUND, UBOUND, HBOUND in man page"
```

---

## Verification checklist

After all tasks are done, confirm:

- [ ] `HBOUND(A)` returns `End_Index` of array A (same as `UBOUND(A)`)
- [ ] `LBOUND(A)` returns `Start_Index` of array A (unchanged)
- [ ] `HELP LBOUND`, `HELP UBOUND`, `HELP HBOUND` all produce output
- [ ] `HELP` (bare) shows `Arrays:      LBOUND, UBOUND, HBOUND`
- [ ] `man/man1/sdata.1` contains an Arrays subsection under FUNCTIONS
- [ ] `make check` passes (all 134 integration tests + unit tests)
