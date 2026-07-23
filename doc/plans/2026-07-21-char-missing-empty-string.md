# Character Missing = Empty String (#55) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make an empty (zero-length) character value *be* the character missing value throughout SData, removing the `""`-is-both ambiguity (issue #55).

**Architecture:** Establish one invariant — a `Val_String` of length 0 never exists at runtime — enforced at two chokepoints in sdata-core: the `Evaluate` expression wrapper (normalizes every expression/sub-expression result) and `Coerce_Value` (normalizes every stored value). CSV read already normalizes a blank field to missing. With the invariant in place, `LEN("")`/empty concatenation propagate missing automatically, while `MISSING`/`N`/`NMISS` (already correct) are unchanged. A string-function sweep guards each built-in against a now-missing argument.

**Tech Stack:** Ada 2012, GNAT via Alire (`alr build`), path-pinned sibling crates (sdata → sdata-core; data-vandal → sdata-core).

## Global Constraints

- **sdata-core requires a PR** (no direct push); sdata allows direct push to main but this work uses a feature branch.
- **Branches:** sdata-core `feat/55-char-missing-empty-string` (new); sdata `feat/55-char-missing-empty-string` (already exists, holds the spec commit `8f2d815`); data-vandal — no code change expected.
- **Cross-crate gate before any push:** `cd ~/Develop/sdata-core && alr build`, then `cd ~/Develop/sdata && make check` (all integration + unit), then `cd ~/Develop/data-vandal && make check`. All three green.
- **Path pin hides floor drift** (per CLAUDE.md): bumping the `sdata_core = "^X.Y.Z"` floor is required when consuming new sdata-core *semantics*, even though local builds pass regardless.
- **Versions (confirm at release, Task 6):** sdata-core `0.2.0 → 0.3.0`, sdata `0.15.0 → 0.16.0`, data-vandal `0.8.0 → 0.9.0`; both consumer floors `→ ^0.3.0`; sdata-core `consumer-tests.yml` `ref: → v0.16.0`.
- **Commit trailer** (every commit): `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- **Merge order at release:** sdata-core PR first (consumers' CI clones `sdata-core@main`).
- **Missing renders as `"."`** via `To_String`; no writer change (round-trip stays faithful).

---

### Task 1: sdata-core — storage normalization in `Coerce_Value`

Every value stored in a table cell flows through `Coerce_Value` (called by `Set_Value_Upper`). Normalizing an empty `Val_String` to `Val_Missing` here guarantees no column/PDV ever holds `""`, covering `N`/`NMISS` over a column, BY-group distinctness, comparisons, and SAVE — for both sdata and data-vandal.

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-table.adb` (`Coerce_Value`, currently starting at line 211)
- Test: `~/Develop/sdata/tests/sdata_unit_test.adb` (adds assertions to the existing Table section)

**Interfaces:**
- Consumes: `SData_Core.Table.Set_Value (Row : Positive; Column_Name : String; Val : Value)`, `Get_Value (...) return Value` (existing).
- Produces: post-condition — after `Set_Value` of a `Val_String` whose payload is `""`, `Get_Value` on that cell returns a `Value` of `Kind = Val_Missing`.

- [ ] **Step 1: Write the failing test**

In `~/Develop/sdata/tests/sdata_unit_test.adb`, after the existing `NAME$` cell tests (near line 130, following the `Set_Value (1, "NAME$", ...)` block), add:

```ada
   --  Issue #55: an empty character value is stored as missing, not "".
   Set_Value (1, "NAME$", (Kind => Val_String, Str_Val => To_Unbounded_String ("")));
   V := Get_Value (1, "NAME$");
   Check_Kind ("T-55a empty string stored as missing", V.Kind, Val_Missing);
```

- [ ] **Step 2: Build sdata-core and run the test to verify it fails**

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && alr build && ./bin/sdata_unit_test | grep 'T-55a'
```
Expected: `FAIL: T-55a empty string stored as missing  got kind=VAL_STRING  expected Val_Missing`

- [ ] **Step 3: Implement the normalization guard**

In `~/Develop/sdata-core/src/sdata_core-table.adb`, at the very top of `Coerce_Value`'s body (before the existing `if Val.Kind = Val_Missing then return Val; end if;`), insert:

```ada
      --  Issue #55: a zero-length character value IS the missing value.
      --  Normalize it here so no column/PDV ever stores an empty string;
      --  this keeps N/NMISS, BY-group distinctness, comparison, and SAVE
      --  consistent for every consumer (sdata and data-vandal).
      if Val.Kind = Val_String and then Length (Val.Str_Val) = 0 then
         return (Kind => Val_Missing);
      end if;
```

(`Length` and `Str_Val` are already visible in this body via `Ada.Strings.Unbounded`.)

- [ ] **Step 4: Rebuild and run the test to verify it passes**

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && alr build && ./bin/sdata_unit_test | grep 'T-55a'
```
Expected: `PASS: T-55a empty string stored as missing`

- [ ] **Step 5: Commit (two repos)**

```bash
cd ~/Develop/sdata-core && git checkout -b feat/55-char-missing-empty-string 2>/dev/null || git checkout feat/55-char-missing-empty-string
git add src/sdata_core-table.adb
git commit -m "feat: empty character value stored as missing (#55)

Normalize a zero-length Val_String to Val_Missing at the top of
Coerce_Value, the single storage chokepoint, so no column/PDV holds
an empty string.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"

cd ~/Develop/sdata
git add tests/sdata_unit_test.adb
git commit -m "test: empty character value stored as missing (#55)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: sdata-core — expression normalization (`Evaluate` wrapper)

`Evaluate` has many early returns, so normalization goes in a thin public wrapper over the (renamed) recursive body. Because the recursive descent inside the body calls `Evaluate` by name, wrapping it normalizes **every** sub-expression: the `""` literal, string-function results, and operands entering concatenation. This is what makes `LEN("")`, `TRIM("   ")`, and `first$ + "" ` collapse to missing.

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-evaluator.adb` (`Evaluate`, currently starting at line 462)
- Test: `~/Develop/sdata/tests/evaluator_unit_test.adb`

**Interfaces:**
- Consumes: `SData_Core.Evaluator.Parse_Expression (Text : String) return Expression_Access`, `Evaluate (Expr : Expression_Access) return Value` (existing public API in `evaluator.ads`).
- Produces: post-condition — `Evaluate` returns `Val_Missing` for any expression whose result would be a zero-length `Val_String` (the `""` literal, `TRIM` of blanks, an empty concatenation input).

- [ ] **Step 1: Write the failing test**

In `~/Develop/sdata/tests/evaluator_unit_test.adb`, in the main test body (before the final pass/fail summary), add:

```ada
   --  Issue #55: an empty character value is missing at expression level.
   declare
      --  Parse_Expression argument is the sdata source text; Ada doubles
      --  each embedded quote.  """""" is the sdata literal "" (empty string);
      --  "LEN("""")" is LEN(""); "TRIM$("""")" is TRIM$("").
      E_Empty : constant Expression_Access := Parse_Expression ("""""");
      E_Len   : constant Expression_Access := Parse_Expression ("LEN("""")");
      E_Cat   : constant Expression_Access := Parse_Expression ("""a"" + """"");
   begin
      Check_Missing ("55-eval empty literal is missing", Evaluate (E_Empty));
      Check_Missing ("55-eval LEN(empty) is missing",    Evaluate (E_Len));
      Check_Missing ("55-eval a + empty is missing",     Evaluate (E_Cat));
   end;
```

- [ ] **Step 2: Build and run the test to verify it fails**

```bash
cd ~/Develop/sdata && alr build && ./bin/evaluator_unit_test | grep '55-eval'
```
Expected: three `FAIL:` lines (the empty literal returns `VAL_STRING`, `LEN` returns `VAL_INTEGER` 0, concat returns `VAL_STRING` "a").

- [ ] **Step 3: Implement the wrapper**

In `~/Develop/sdata-core/src/sdata_core-evaluator.adb`: rename the existing `function Evaluate (Expr : Expression_Access) return Value is ... end Evaluate;` (line 462 to its `end Evaluate;`) to `Eval_Raw`, **leaving every internal `Evaluate (...)` recursive call unchanged** (they will now bind to the public wrapper). Rename only the declaration line and the closing `end`:

```ada
   --  Raw expression evaluation.  Every recursive sub-evaluation below calls
   --  the public Evaluate wrapper, so intermediate results are normalized too.
   function Eval_Raw (Expr : Expression_Access) return Value is
   begin
      ... (body unchanged) ...
   end Eval_Raw;
```

Then, immediately after `end Eval_Raw;`, add the wrapper:

```ada
   function Evaluate (Expr : Expression_Access) return Value is
      Result : constant Value := Eval_Raw (Expr);
   begin
      --  Issue #55: a zero-length character value IS the missing value.
      --  Normalizing here (and, via the recursion above, at every level)
      --  makes LEN("")/empty-concat/TRIM$("") propagate missing while the
      --  MISSING/N/NMISS family stays correct.
      if Result.Kind = Val_String and then Length (Result.Str_Val) = 0 then
         return (Kind => Val_Missing);
      end if;
      return Result;
   end Evaluate;
```

`Evaluate` is declared in `evaluator.ads`, so `Eval_Raw` may call it without a forward declaration.

- [ ] **Step 4: Build and run the test to verify it passes**

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && alr build && ./bin/evaluator_unit_test | grep '55-eval'
```
Expected: three `PASS:` lines. (If `LEN(empty)` now *crashes* rather than fails, that is expected — Task 3 adds the missing-argument guard; you may temporarily comment the `55-eval LEN` line and restore it after Task 3. Prefer doing Task 3 next.)

- [ ] **Step 5: Commit (two repos)**

```bash
cd ~/Develop/sdata-core
git add src/sdata_core-evaluator.adb
git commit -m "feat: empty character expression result is missing (#55)

Split Evaluate into a recursive Eval_Raw plus a thin Evaluate wrapper
that normalizes a zero-length Val_String result to Val_Missing.  Because
the recursion calls the wrapper, every sub-expression is normalized, so
LEN(\"\")/empty-concat/TRIM\$(\"\") propagate missing.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"

cd ~/Develop/sdata
git add tests/evaluator_unit_test.adb
git commit -m "test: empty character expression result is missing (#55)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: sdata-core — string-function missing-argument sweep

Once `""` normalizes to `Val_Missing`, a string built-in that previously received a non-missing empty `Val_String` now receives `Val_Missing`. Any handler that reads `.Str_Val` on such an argument without a `Kind` guard raises `Constraint_Error`. Every string-input built-in must return `Val_Missing` for a missing argument before touching its payload.

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-evaluator-string_fns.adb`, `~/Develop/sdata-core/src/sdata_core-evaluator-misc_fns.adb` (and `-nav_fns.adb` if the sweep test flags `ORD`)
- Test: `~/Develop/sdata/tests/evaluator_unit_test.adb`

**Interfaces:**
- Consumes: `SData_Core.Evaluator.Call_Function (Name : String; Args : Value_Array) return Value` (existing).
- Produces: post-condition — for each string-input built-in below, `Call_Function (name, (1 => (Kind => Val_Missing)))` (and the 2-arg forms) returns `Kind = Val_Missing`, never raising.

- [ ] **Step 1: Write the failing test**

In `~/Develop/sdata/tests/evaluator_unit_test.adb`, add (mirroring the file's existing `Call_Function` usage for `Value_Array` construction):

```ada
   --  Issue #55: every string-input built-in propagates a missing argument
   --  instead of dereferencing .Str_Val on a Val_Missing (which would crash).
   declare
      M  : constant Value := (Kind => Val_Missing);
      S  : constant Value := (Kind => Val_String, Str_Val => To_Unbounded_String ("abc"));
   begin
      Check_Missing ("55-arg LEN",    Call_Function ("LEN",    (1 => M)));
      Check_Missing ("55-arg LEFT$",  Call_Function ("LEFT$",  (M, (Kind => Val_Integer, Int_Val => 1))));
      Check_Missing ("55-arg RIGHT$", Call_Function ("RIGHT$", (M, (Kind => Val_Integer, Int_Val => 1))));
      Check_Missing ("55-arg MID$",   Call_Function ("MID$",   (M, (Kind => Val_Integer, Int_Val => 1), (Kind => Val_Integer, Int_Val => 1))));
      Check_Missing ("55-arg SEG$",   Call_Function ("SEG$",   (M, (Kind => Val_Integer, Int_Val => 1), (Kind => Val_Integer, Int_Val => 1))));
      Check_Missing ("55-arg TRIM$",  Call_Function ("TRIM$",  (1 => M)));
      Check_Missing ("55-arg LTRIM$", Call_Function ("LTRIM$", (1 => M)));
      Check_Missing ("55-arg RTRIM$", Call_Function ("RTRIM$", (1 => M)));
      Check_Missing ("55-arg ASCII",  Call_Function ("ASCII",  (1 => M)));
      Check_Missing ("55-arg UPPER$", Call_Function ("UPPER$", (1 => M)));
      Check_Missing ("55-arg LOWER$", Call_Function ("LOWER$", (1 => M)));
      Check_Missing ("55-arg POS",    Call_Function ("POS",    (S, M)));
      Check_Missing ("55-arg POS2",   Call_Function ("POS",    (M, S)));
      Check_Missing ("55-arg INSTR",  Call_Function ("INSTR",  (S, M)));
      Check_Missing ("55-arg VAL",    Call_Function ("VAL",    (1 => M)));
      Check_Missing ("55-arg NUM",    Call_Function ("NUM",    (1 => M)));
      Check_Missing ("55-arg INDEX",  Call_Function ("INDEX",  (S, M)));
      Check_Missing ("55-arg MATCH",  Call_Function ("MATCH",  (S, M)));
   end;
```

- [ ] **Step 2: Build and run the test to verify it fails / crashes**

```bash
cd ~/Develop/sdata && alr build && ./bin/evaluator_unit_test | grep '55-arg' || echo "(crash before summary = a handler dereferenced a missing arg)"
```
Expected: one or more `FAIL:` lines, or the binary aborts with `CONSTRAINT_ERROR` at the first unguarded handler.

- [ ] **Step 3: Add the guard to each flagged handler**

In `~/Develop/sdata-core/src/sdata_core-evaluator-string_fns.adb` and `-misc_fns.adb`, for **each** handler named above, ensure the first statement after argument extraction rejects a missing (or non-string, where the argument is expected to be a string) argument. The idiom, applied per handler to its string argument(s):

```ada
      --  Issue #55: propagate a missing character argument (an empty string
      --  is missing) rather than dereferencing .Str_Val on a Val_Missing.
      if V.Kind /= Val_String then
         return (Kind => Val_Missing);
      end if;
```

For two-argument search handlers (`POS`, `INSTR`, `INDEX`, `MATCH`), guard **both** the haystack and needle before the existing `Length (Needle.Str_Val) = 0` checks (`string_fns.adb:222,250`, `misc_fns.adb:232`); those empty-needle branches become unreachable and may be left as harmless dead code. Handlers that already guard (`ASCII` at `string_fns.adb:178`, `ORD` at `nav_fns.adb:38`) need no change. `VAL`/`NUM` (string→number) must return missing for a missing string argument.

- [ ] **Step 4: Rebuild and run the test to verify all pass**

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && alr build && ./bin/evaluator_unit_test | grep '55-arg'
```
Expected: every `55-arg …` line is `PASS:`, binary runs to its summary without aborting.

- [ ] **Step 5: Commit (two repos)**

```bash
cd ~/Develop/sdata-core
git add src/sdata_core-evaluator-string_fns.adb src/sdata_core-evaluator-misc_fns.adb
git commit -m "fix: string built-ins propagate missing character arguments (#55)

With empty strings now normalized to missing, guard each string-input
built-in to return Val_Missing for a missing argument before reading
.Str_Val, preventing Constraint_Error.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"

cd ~/Develop/sdata
git add tests/evaluator_unit_test.adb
git commit -m "test: string built-ins propagate missing character arguments (#55)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: sdata — documentation (design.md, HELP, man page)

The language spec must state the resolved model and drop the self-contradictory clause. Per CLAUDE.md, syntax/semantics references (design doc, HELP, man page) stay in sync.

**Files:**
- Modify: `~/Develop/sdata/doc/design.md` (§2.5 line ~84, §3.6 line ~330, §8.5 line ~2043)
- Modify (only if wording changes): `~/Develop/sdata/src/sdata-help.adb`, `~/Develop/sdata/man/man1/sdata.1`
- Possibly regen: `~/Develop/sdata/tests/expected/help_all.out` (only if HELP text changes)

**Interfaces:** none (documentation).

- [ ] **Step 1: Edit design.md §2.5**

In `~/Develop/sdata/doc/design.md`, replace the contradictory propagation bullet (line 84, `- Null strings (*""*) in string operations shall be taken literally.`) with:

```markdown
- An empty (zero-length) character value **is** the character missing value; there is no distinct "empty string." Empty character values therefore propagate as missing through all string operations (e.g. *LEN("")* and *"" + "x"* are missing), consistent with the rule above that operations on missing values yield missing values.
```

Leave line 79 (`- Character missing value: empty string (*""*).`) as-is — it is now unambiguous. Do **not** touch the pre-existing `shalfunctionl` typo on line 86 (tracked in #57).

- [ ] **Step 2: Edit design.md §3.6 and §8.5**

At line ~330 (`- Missing character value: empty string (*""*).`), change to make it clearly *the* missing value:

```markdown
  - The character missing value is the empty string (*""*); an empty character literal denotes missing.
```

In §8.5 (Future Extensions, near line 2043), append a clarifying note under the special-missing bullet:

```markdown
- (Character data has a single missing value — the empty string; the special
  missing codes above are a numeric-only extension.)
```

- [ ] **Step 3: Audit HELP and man page**

```bash
cd ~/Develop/sdata
grep -n -iE 'LEN|MISSING|empty|null string' src/sdata-help.adb
grep -n -iE 'LEN|MISSING|empty|null string' man/man1/sdata.1
```
If either describes `LEN("")` as `0` or an empty string as a literal, update the wording to match the missing-propagation model. If `src/sdata-help.adb` text changes, regenerate the snapshot by re-running the committed `HELP /ALL` script (`tests/help_all.cmd`) into its expected file:

```bash
cd ~/Develop/sdata && alr build   # rebuild so the new HELP text is in the binary
./bin/sdata tests/help_all.cmd > tests/expected/help_all.out
```
Also update any `tests/expected/*options*` snapshot that lists the affected topic. (If no HELP wording change is needed, skip the regen — the snapshot is unaffected.)

- [ ] **Step 4: Commit (docs-only)**

Per CLAUDE.md, a doc-only commit needs no `make check`. If Step 3 changed `sdata-help.adb`, this is **not** doc-only — run the full `make check` first (folded into Task 6's gate is acceptable if you commit help changes there instead).

```bash
cd ~/Develop/sdata
git add doc/design.md
# add src/sdata-help.adb man/man1/sdata.1 tests/expected/help_all.out ONLY if changed
git commit -m "docs: character missing value = empty string, propagates (#55)

Resolve the design.md §2.5 contradiction: an empty character value IS
the missing value and propagates through string operations.  Align §3.6
and note in §8.5 that character has a single missing value.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: sdata — end-to-end integration regression tests

Prove the user-visible behaviors through the `.cmd` integration suite (the harness runs `./bin/sdata <flags> NAME.cmd`, compares stdout to `tests/expected/NAME.out` with `diff -wu`, and checks exit code against `tests/NAME.exitcode`, default 0).

**Files:**
- Create: `~/Develop/sdata/tests/empty_string_missing.cmd` + `tests/expected/empty_string_missing.out`
- Create: `~/Develop/sdata/tests/empty_string_roundtrip.cmd` + `tests/expected/empty_string_roundtrip.out`

**Interfaces:** none (black-box CLI tests).

- [ ] **Step 1: Write the semantics test**

Create `~/Develop/sdata/tests/empty_string_missing.cmd`:

```
-- Issue #55: an empty character value is the missing value; it propagates
-- through string operations, and MISSING/N/NMISS treat it as missing.
NEW
REPEAT 2
LET S$ = ""
LET T$ = S$ + "x"
LET L = LEN(S$)
LET M% = MISSING(S$)
PRINT S$ T$ L M%
RUN
QUIT
```

Create `~/Develop/sdata/tests/expected/empty_string_missing.out`:

```
. . . 1
. . . 1
RUN complete. 2 records and 4 variables processed.
```

(A missing character prints as `.`; `S$`/`T$`/`L` are all missing → `.`; `MISSING(S$)` is `1`. Four columns: `S$`, `T$`, `L`, `M%`. The harness diffs with `diff -wu`, so inter-field spacing is not significant — but verify the exact record/variable-count line against the freshly built binary before committing.)

- [ ] **Step 2: Write the round-trip test**

Create `~/Develop/sdata/tests/empty_string_roundtrip.cmd`:

```
-- Issue #55: a blank character cell round-trips through SAVE/USE as missing.
NEW
REPEAT 2
LET NAME$ = IF(RECNO() = 1, "Alice", "")
LET N% = NMISS(NAME$)
PRINT NAME$ N%
SAVE "tests/data/empty_rt.csv"
RUN
USE "tests/data/empty_rt.csv"
LIST
QUIT
```

Create `~/Develop/sdata/tests/expected/empty_string_roundtrip.out` by running the command **after** Tasks 1–3 are built, then hand-verifying it shows `Alice` for row 1, `.` (missing) for row 2, and `NMISS` counting the blank as missing:

```bash
cd ~/Develop/sdata && ./bin/sdata tests/empty_string_roundtrip.cmd
```
Capture the exact output into the `.out` file and eyeball it against the described behavior before committing. (Generating the expected file from the just-built binary is the project's established practice for output-shape tests; the assertion is the human review here.)

- [ ] **Step 3: Run the two tests through the harness**

```bash
cd ~/Develop/sdata
for t in empty_string_missing empty_string_roundtrip; do
  ./bin/sdata tests/$t.cmd > tests/$t.tmp 2>&1
  diff -wu tests/expected/$t.out tests/$t.tmp && echo "$t PASS"; rm -f tests/$t.tmp
done
```
Expected: both `PASS`.

- [ ] **Step 4: Commit**

```bash
cd ~/Develop/sdata
git add tests/empty_string_missing.cmd tests/expected/empty_string_missing.out \
        tests/empty_string_roundtrip.cmd tests/expected/empty_string_roundtrip.out
git commit -m "test: empty character value is missing end-to-end (#55)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: Cross-crate gate, fixture reconciliation, and release

Run the full suites, fix any fixtures that shift because `LEN("")`/empty-concat now yield missing, then perform the cross-crate release.

**Files:**
- Modify: `~/Develop/sdata/tests/expected/*.out` (only those that shift)
- Modify: `~/Develop/sdata-core/alire.toml`, its `docs/api/reference.html` (only if a public `.ads` changed — none expected here)
- Modify: `~/Develop/sdata/alire.toml` (floor) + the 9 files touched by `scripts/bump-version.sh`
- Modify: `~/Develop/data-vandal/alire.toml` (floor + version)
- Modify: `~/Develop/sdata-core/.github/workflows/consumer-tests.yml` (`ref:`)

**Interfaces:** none.

- [ ] **Step 1: Full sdata suite; reconcile shifted fixtures**

```bash
cd ~/Develop/sdata-core && alr build
cd ~/Develop/sdata && make check 2>&1 | tail -30
```
For each integration test that now FAILS solely because an empty-string result became missing (`.`), inspect the diff, confirm the new output is *correct under the #55 model*, and update `tests/expected/<name>.out` accordingly. Re-run `make check` until green. Commit the fixture updates:

```bash
git add tests/expected
git commit -m "test: reconcile fixtures for empty=missing model (#55)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 2: data-vandal gate (no code change expected)**

```bash
cd ~/Develop/data-vandal && make check 2>&1 | tail -15
```
Expected: green with no source edits (data-vandal inherits `Coerce_Value` normalization). If a data-vandal fixture shifts for the same benign reason, reconcile and commit it on a data-vandal `feat/55-char-missing-empty-string` branch with the same rationale.

- [ ] **Step 3: Bump sdata-core and open its PR (FIRST)**

Confirm no public `.ads` signature changed (the changes are internal to `evaluator.adb`/`table.adb`/`*_fns.adb`); if so, `docs/api/reference.html` needs no regen. Edit `~/Develop/sdata-core/alire.toml` `version = "0.3.0"`, commit, push the branch, open the PR:

```bash
cd ~/Develop/sdata-core
# edit alire.toml: version = "0.3.0"
git add alire.toml && git commit -m "chore: bump sdata-core 0.2.0 -> 0.3.0 (empty=missing, #55)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push -u origin feat/55-char-missing-empty-string
gh pr create --fill --title "feat: character empty value = missing (#55)"
```

- [ ] **Step 4: Bump both consumers' floors + versions and open their PRs**

```bash
cd ~/Develop/sdata
# edit alire.toml: sdata_core = "^0.3.0"
scripts/bump-version.sh 0.16.0 "character empty value is missing (#55)"
git add -A && git commit -m "chore: bump sdata 0.15.0 -> 0.16.0; floor sdata_core ^0.3.0 (#55)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push -u origin feat/55-char-missing-empty-string
gh pr create --fill --title "feat: character empty value = missing (#55)"

cd ~/Develop/data-vandal
# edit alire.toml: version = "0.9.0" and sdata_core = "^0.3.0"
git checkout -b feat/55-char-missing-empty-string 2>/dev/null || git checkout feat/55-char-missing-empty-string
git add alire.toml && git commit -m "chore: bump data-vandal 0.8.0 -> 0.9.0; floor sdata_core ^0.3.0 (#55)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push -u origin feat/55-char-missing-empty-string
gh pr create --fill --title "chore: consume sdata-core 0.3.0 (#55)"
```

- [ ] **Step 5: Post-merge (after the user merges; sdata-core PR first)**

Tag each release and bump the consumer-tests ref (mirrors the #54 flow):

```bash
cd ~/Develop/sdata-core && git checkout main && git pull --ff-only
git tag -a v0.3.0 -m "Version 0.3.0" && git push origin v0.3.0
# edit .github/workflows/consumer-tests.yml: ref: v0.16.0 (open as its own small PR)

cd ~/Develop/sdata && git checkout main && git pull --ff-only
git tag -a v0.16.0 -m "Version 0.16.0" && git push origin v0.16.0

cd ~/Develop/data-vandal && git checkout main && git pull --ff-only
git tag -a v0.9.0 -m "Version 0.9.0" && git push origin v0.9.0

cd ~/Develop/sdata && gh issue close 55 --comment "Resolved: an empty character value is the missing value (SPM/SAS model); released in sdata-core v0.3.0 / sdata v0.16.0 / data-vandal v0.9.0."
```

- [ ] **Step 6: Update project memory**

Record the release (versions, tags, PRs) and mark #55 closed in `project_dev_plan.md`, mirroring the #54 entry.

---

## Notes on decisions already settled (see spec §2, §6, §10)

- **No writer change**: char-missing renders as `"."` and round-trips; rendering it as a blank CSV field is out of scope.
- **`MISSING`/`N`/`NMISS` unchanged**: already correct; their `Length = 0` clauses stay as harmless defense-in-depth.
- **No sdata interpreter code change**: sdata's `Evaluate` is `SData_Core.Evaluator.Evaluate` (`use` clause), so assignment RHS is normalized by Task 2, and storage by Task 1 — verified by Task 5's integration tests, not by editing `Coerce_For_Scalar`.
