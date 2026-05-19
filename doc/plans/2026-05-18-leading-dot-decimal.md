# Leading-Dot Decimal Literal Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the lexer so that leading-dot decimal literals (`.05`, `.1`, `.5`) tokenize as `Token_Numeric_Literal` rather than crashing the parser.

**Architecture:** Single change in the `when '.' =>` branch of `src/lexer/sdata-lexer.adb` (line 400): after advancing past the dot, peek at the next character; if it is a digit, build a `Token_Numeric_Literal` whose text is `"0."` followed by the digit run; otherwise emit `Token_Dot` unchanged. No parser or evaluator changes are needed.

**Tech Stack:** Ada 2012, GNAT/GPRbuild, Alire. Build: `alr build`. Tests: `make check`.

---

## File map

| Action | Path | What changes |
|---|---|---|
| Modify | `src/lexer/sdata-lexer.adb:400` | `when '.' =>` branch — leading-dot detection |
| Create | `tests/leading_dot_decimal_test.cmd` | Integration test (expressions + VANDALIZE) |
| Create | `tests/expected/leading_dot_decimal_test.out` | Expected output for integration test |
| Modify | `tests/evaluator_unit_test.adb` | Add LD-01–LD-04 unit tests |

---

## Task 1: Write the failing integration test

**Files:**
- Create: `tests/leading_dot_decimal_test.cmd`
- Create: `tests/expected/leading_dot_decimal_test.out`

- [ ] **Step 1: Create the test script**

Create `tests/leading_dot_decimal_test.cmd` with this exact content:

```
-- Test leading-dot decimal literals (.5, .05, .1)
-- Bug: lexer emitted Token_Dot + Token_Numeric("05") for ".05"

-- Part 1: leading-dot in expression contexts
REPEAT 1
PRINT .5
PRINT .05
PRINT (.05 + .1)
IF .3 < .4 THEN PRINT "ok"
PRINT MISSING(.)
RUN

-- Part 2: leading-dot in VANDALIZE option arguments
-- /MISS=.0 means 0% miss probability, so X_V equals X exactly
NEW
REPEAT 3
LET X = RECNO()
RUN
VANDALIZE X INTO X_V /MISS=.0
RUN
PRINT X X_V
RUN

QUIT
```

- [ ] **Step 2: Create the expected output file**

Create `tests/expected/leading_dot_decimal_test.out` with this exact content:

```
0.50000
0.05000
0.15000
ok
1
RUN complete. 1 records and 0 variables processed.
RUN complete. 3 records and 1 variables processed.
VANDALIZE complete. 3 records processed.
RUN complete. 3 records and 2 variables processed.
1.00000 1.00000
2.00000 2.00000
3.00000 3.00000
RUN complete. 3 records and 2 variables processed.
```

- [ ] **Step 3: Verify the test fails before the fix**

Run:
```bash
make check 2>&1 | grep -A 5 "leading_dot"
```

Expected: `FAILED (output mismatch)` or an exit-code failure. The interpreter will produce an error such as `Unrecognized command "05"` instead of the expected numeric output.

---

## Task 2: Write the failing evaluator unit tests

**Files:**
- Modify: `tests/evaluator_unit_test.adb`

The file already has an `Eval (S : String) return Value` helper (around line 149) that parses and evaluates `"LET _R = " & S`. Use it directly. There is also a `Check_Missing` procedure and `Check_Num` for float checks.

- [ ] **Step 1: Add the LD test block**

Insert the following block immediately before the final two `Put_Line` calls at the bottom of `tests/evaluator_unit_test.adb` (before the line that reads `Put_Line (Passed'Image & " passed," & Failed'Image & " failed.");`):

```ada
   Put_Line ("");
   Put_Line ("--- LD: Leading-Dot Decimal Literals ---");

   --  LD-01: .5 evaluates to 0.5
   Check_Num ("LD-01: .5 = 0.5",       Eval (".5"),       0.5);

   --  LD-02: .05 evaluates to 0.05
   Check_Num ("LD-02: .05 = 0.05",     Eval (".05"),      0.05);

   --  LD-03: arithmetic with two leading-dot literals
   Check_Num ("LD-03: .05 + .1 = 0.15", Eval (".05 + .1"), 0.15);

   --  LD-04: bare dot must still be missing (regression guard)
   Check_Missing ("LD-04: bare dot is still missing", Eval ("."));
```

> **Note:** Before the lexer fix is applied, `Eval (".5")` will propagate an
> exception (the parser sees `Token_Dot` as a missing-value literal, then hits
> the orphaned `5` token). The test binary will exit non-zero, which `make check`
> reports as a unit-test failure. This is the expected pre-fix behaviour.

- [ ] **Step 2: Build and verify unit tests fail**

Run:
```bash
alr build && make check 2>&1 | grep -E "LD-|unit tests FAILED|leading_dot"
```

Expected: build succeeds; either the evaluator unit test binary crashes (exception) or `make check` reports unit tests FAILED.

---

## Task 3: Implement the lexer fix

**Files:**
- Modify: `src/lexer/sdata-lexer.adb:400`

- [ ] **Step 1: Open the file and locate the target line**

In `src/lexer/sdata-lexer.adb`, find line 400. It reads:

```ada
               when '.' => T.Kind := Token_Dot; Advance (Ctx);
```

This is inside the `case` statement within `Get_Next_Token_Internal`, after the `|` (pipe) handling block.

- [ ] **Step 2: Replace the `when '.' =>` clause**

Replace that single line with:

```ada
               when '.' =>
                  Advance (Ctx);
                  if not Is_End_Of_Source (Ctx)
                     and then Is_Digit (Current_Char (Ctx))
                  then
                     T.Kind := Token_Numeric_Literal;
                     T.Length := 2;
                     T.Text (1) := '0';
                     T.Text (2) := '.';
                     while not Is_End_Of_Source (Ctx)
                        and then Is_Digit (Current_Char (Ctx))
                     loop
                        T.Length := T.Length + 1;
                        T.Text (T.Length) := Current_Char (Ctx);
                        Advance (Ctx);
                     end loop;
                  else
                     T.Kind := Token_Dot;
                  end if;
```

The `Is_End_Of_Source` guard is a buffer-safety check: after advancing past `.`, we must verify a next character exists before calling `Current_Char`. If `.` is the last character in the source, we emit `Token_Dot` (missing-value literal), which is the correct interpretation.

- [ ] **Step 3: Build**

Run:
```bash
alr build
```

Expected: build completes with no errors or warnings.

---

## Task 4: Verify all tests pass and commit

- [ ] **Step 1: Run the full test suite**

Run:
```bash
make check
```

Expected: all unit tests pass; the new `leading_dot_decimal_test` integration test passes; no previously-passing tests regress. Final line should be similar to:
```
All 132 tests passed.
```
(Count may differ by ±1 depending on suite total; what matters is 0 failures.)

- [ ] **Step 2: If the integration test output does not match**

If `leading_dot_decimal_test` shows an output-mismatch diff, inspect it:
```bash
cat tests/leading_dot_decimal.diff
```

Adjust `tests/expected/leading_dot_decimal_test.out` to match the actual output exactly, then re-run `make check`. The only acceptable reason to adjust the expected file is cosmetic formatting differences (whitespace, trailing newline); the numeric values and `ok` line must appear.

- [ ] **Step 3: Commit**

```bash
git add src/lexer/sdata-lexer.adb \
        tests/leading_dot_decimal_test.cmd \
        tests/expected/leading_dot_decimal_test.out \
        tests/evaluator_unit_test.adb
git commit -m "$(cat <<'EOF'
fix: lexer recognizes leading-dot decimal literals (.05, .1, .5)

Previously the '.' clause unconditionally emitted Token_Dot, splitting
.05 into Token_Dot + Token_Numeric("05") and crashing the parser.
Now peeks at the next char; if a digit follows, produces
Token_Numeric_Literal("0.05") so Ada Float'Value can convert it.
Bare dot still emits Token_Dot (missing-value literal) unchanged.

Fixes VANDALIZE /perturb=.05,.1 /miss=.1 /shuffle=.1 and all other
leading-dot literal contexts.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```
