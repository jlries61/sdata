# Evaluator Expression Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add 45 unit tests (EV-01..EV-45) to `tests/evaluator_unit_test.adb` that exercise the expression-tree evaluation path in `SData.Evaluator` — literals, arithmetic, operator precedence, comparisons, boolean logic, missing propagation, string operations, variable references, functions inside expressions, error conditions, and language constants.

**Architecture:** All 45 tests are added to the single existing test program (`tests/evaluator_unit_test.adb`). Three new `with` clauses enable the parser (`SData.Parser`), AST types (`SData.AST`), and temp-variable API (`SData.Variables`). Two new helper functions — `Eval(S)` and `Raises_Expr(S)` — use `SData.Parser.Parse_Program` on `"LET _R = " & S` to obtain an `Expression_Access`, call `SData.Evaluator.Evaluate` on it, and return the result. All 101 existing tests remain unmodified.

**Tech Stack:** Ada 2012, GNAT toolchain via `gprbuild -P sdata.gpr`, `SData.Parser` (recursive-descent parser), `SData.AST` (variant-record AST + `Free_Program`), `SData.Variables` (`Set_Temporary`, `Clear_Temporary`), `SData.Evaluator.Evaluate`.

---

## File Structure

| File | Change |
|---|---|
| `tests/evaluator_unit_test.adb` | Add 3 with-clauses, 2 helpers (`Eval`, `Raises_Expr`), 45 test assertions |

No new files are created; no other files are modified.

---

### Task 1: Helpers + arithmetic/literal tests (EV-01..EV-16)

**Files:**
- Modify: `tests/evaluator_unit_test.adb:5-12` (with-clauses block)
- Modify: `tests/evaluator_unit_test.adb:141-153` (add `Eval` + `Raises_Expr` after `FS2`)
- Modify: `tests/evaluator_unit_test.adb:619-622` (insert EV-01..EV-16 before the summary block)

- [ ] **Step 1: Confirm baseline tests all pass**

```bash
gprbuild -P sdata.gpr && ./bin/evaluator_unit_test
```

Expected: last line is ` 101 passed, 0 failed.`

- [ ] **Step 2: Add the three new `with` clauses**

In `tests/evaluator_unit_test.adb`, add after the existing `with SData.Statistics;` line (currently line 11):

```ada
with SData.AST;       use SData.AST;
with SData.Parser;
with SData.Variables; use SData.Variables;
```

- [ ] **Step 3: Add `Eval` and `Raises_Expr` helpers in the declaration section**

Add directly after the closing `end FS2;` (currently before `V : Value;` near line 153):

```ada
   function Eval (S : String) return Value is
      Ctx  : SData.Parser.Parser_Context;
      Prog : Statement_Access;
      V    : Value;
   begin
      SData.Parser.Initialize (Ctx, "LET _R = " & S);
      Prog := SData.Parser.Parse_Program (Ctx);
      V := Evaluate (Prog.Expr);
      Free_Program (Prog);
      return V;
   exception
      when others =>
         Free_Program (Prog);
         raise;
   end Eval;

   function Raises_Expr (S : String) return Boolean is
      V : Value;
   begin
      V := Eval (S);
      return V.Kind = Val_Missing;
   exception
      when others => return True;
   end Raises_Expr;
```

- [ ] **Step 4: Add EV-01..EV-16 in the test body**

Insert directly before the two blank `Put_Line ("");` lines that precede `Put_Line (Passed'Image...)`:

```ada
   ---------------------------------------------------------------------------
   --  Expression evaluator tests (EV-01 .. EV-16): Literals and arithmetic
   ---------------------------------------------------------------------------

   Put_Line ("--- EV: Expression Evaluator Tests ---");

   --  EV-01: Integer literal
   Check_Int ("EV-01: integer literal 1", Eval ("1"), 1);

   --  EV-02: Float literal
   Check_Num ("EV-02: float literal 1.5", Eval ("1.5"), 1.5);

   --  EV-03: String literal
   Check_Str ("EV-03: string literal ""hello""", Eval ("""hello"""), "hello");

   --  EV-04: Integer addition -> Val_Integer
   Check_Int ("EV-04: 2 + 3 = 5 (Val_Integer)", Eval ("2 + 3"), 5);

   --  EV-05: Integer subtraction -> Val_Integer
   Check_Int ("EV-05: 7 - 2 = 5 (Val_Integer)", Eval ("7 - 2"), 5);

   --  EV-06: Integer multiplication -> Val_Integer
   Check_Int ("EV-06: 3 * 4 = 12 (Val_Integer)", Eval ("3 * 4"), 12);

   --  EV-07: Integer / integer always yields Val_Numeric (not integer division)
   Check_Num ("EV-07: 7 / 2 = 3.5 (Val_Numeric)", Eval ("7 / 2"), 3.5);

   --  EV-08: Integer ** integer always yields Val_Numeric
   Check_Num ("EV-08: 2 ** 3 = 8.0 (Val_Numeric)", Eval ("2 ** 3"), 8.0);

   --  EV-09: Float operand promotes result to Val_Numeric
   Check_Num ("EV-09: 1.5 + 0.5 = 2.0 (Val_Numeric)", Eval ("1.5 + 0.5"), 2.0);

   --  EV-10: Operator precedence: * binds tighter than +
   Check_Int ("EV-10: 2 + 3 * 4 = 14", Eval ("2 + 3 * 4"), 14);

   --  EV-11: Parentheses override precedence
   Check_Int ("EV-11: (2 + 3) * 4 = 20", Eval ("(2 + 3) * 4"), 20);

   --  EV-12: Unary minus on integer -> Val_Integer
   Check_Int ("EV-12: -5 (Val_Integer)", Eval ("-5"), -5);

   --  EV-13: Unary minus on float -> Val_Numeric
   Check_Num ("EV-13: -1.5 (Val_Numeric)", Eval ("-1.5"), -1.5);

   --  EV-14: Left-associative subtraction: 10 - 3 - 2 = 5 (not 10 - (3-2) = 9)
   Check_Int ("EV-14: 10 - 3 - 2 = 5", Eval ("10 - 3 - 2"), 5);

   --  EV-15: Mixed integer + float -> Val_Numeric
   Check_Num ("EV-15: 2 + 3.0 = 5.0 (Val_Numeric)", Eval ("2 + 3.0"), 5.0);

   --  EV-16: 6 / 2 is still Val_Numeric (integer operands, division always float)
   Check_Num ("EV-16: 6 / 2 = 3.0 (Val_Numeric)", Eval ("6 / 2"), 3.0);
```

- [ ] **Step 5: Build**

```bash
gprbuild -P sdata.gpr
```

Expected: compiles without errors.

- [ ] **Step 6: Run and verify 16 new passes**

```bash
./bin/evaluator_unit_test
```

Expected last line: ` 117 passed, 0 failed.`

- [ ] **Step 7: Commit**

```bash
git add tests/evaluator_unit_test.adb
git commit -m "$(cat <<'EOF'
Test: EV-01..EV-16 expression evaluator — literals and arithmetic

Adds Eval/Raises_Expr helpers and 16 tests covering numeric/string
literals, all arithmetic operators, precedence, and unary minus.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Comparison and boolean operator tests (EV-17..EV-32)

**Files:**
- Modify: `tests/evaluator_unit_test.adb` (insert EV-17..EV-32 after EV-16 block)

- [ ] **Step 1: Add EV-17..EV-32 in the test body**

Insert directly after the EV-16 test line (still before the summary block):

```ada
   ---------------------------------------------------------------------------
   --  EV-17 .. EV-32: Comparison and boolean operators
   ---------------------------------------------------------------------------

   --  EV-17: Equal — true
   Check_Int ("EV-17: 3 = 3 -> 1", Eval ("3 = 3"), 1);

   --  EV-18: Equal — false
   Check_Int ("EV-18: 3 = 4 -> 0", Eval ("3 = 4"), 0);

   --  EV-19: Not-equal — true
   Check_Int ("EV-19: 3 <> 4 -> 1", Eval ("3 <> 4"), 1);

   --  EV-20: Less-than — true
   Check_Int ("EV-20: 3 < 4 -> 1", Eval ("3 < 4"), 1);

   --  EV-21: Less-than-or-equal — equal case
   Check_Int ("EV-21: 3 <= 3 -> 1", Eval ("3 <= 3"), 1);

   --  EV-22: Greater-than — true
   Check_Int ("EV-22: 4 > 3 -> 1", Eval ("4 > 3"), 1);

   --  EV-23: Greater-than-or-equal — false
   Check_Int ("EV-23: 3 >= 4 -> 0", Eval ("3 >= 4"), 0);

   --  EV-24: AND — both true -> 1
   Check_Int ("EV-24: 1 AND 1 -> 1", Eval ("1 AND 1"), 1);

   --  EV-25: AND — one false -> 0
   Check_Int ("EV-25: 1 AND 0 -> 0", Eval ("1 AND 0"), 0);

   --  EV-26: OR — one true -> 1
   Check_Int ("EV-26: 0 OR 1 -> 1", Eval ("0 OR 1"), 1);

   --  EV-27: OR — both false -> 0
   Check_Int ("EV-27: 0 OR 0 -> 0", Eval ("0 OR 0"), 0);

   --  EV-28: XOR — both same -> 0
   Check_Int ("EV-28: 1 XOR 1 -> 0", Eval ("1 XOR 1"), 0);

   --  EV-29: XOR — different -> 1
   Check_Int ("EV-29: 1 XOR 0 -> 1", Eval ("1 XOR 0"), 1);

   --  EV-30: NOT on non-zero -> 0
   Check_Int ("EV-30: NOT 1 -> 0", Eval ("NOT 1"), 0);

   --  EV-31: NOT on zero -> 1
   Check_Int ("EV-31: NOT 0 -> 1", Eval ("NOT 0"), 1);

   --  EV-32: Compound boolean: (3 < 2) OR (5 > 4) -> 1
   Check_Int ("EV-32: (3 < 2) OR (5 > 4) -> 1", Eval ("(3 < 2) OR (5 > 4)"), 1);
```

- [ ] **Step 2: Build**

```bash
gprbuild -P sdata.gpr
```

Expected: compiles without errors.

- [ ] **Step 3: Run and verify 16 new passes**

```bash
./bin/evaluator_unit_test
```

Expected last line: ` 133 passed, 0 failed.`

- [ ] **Step 4: Commit**

```bash
git add tests/evaluator_unit_test.adb
git commit -m "$(cat <<'EOF'
Test: EV-17..EV-32 expression evaluator — comparisons and boolean ops

16 tests covering all six comparison operators (=, <>, <, <=, >, >=),
AND/OR/XOR, NOT, and a compound boolean expression.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: String ops, variable refs, functions in expressions, error cases, constants (EV-33..EV-45)

**Files:**
- Modify: `tests/evaluator_unit_test.adb` (insert EV-33..EV-45 after EV-32 block)

- [ ] **Step 1: Add EV-33..EV-45 in the test body**

Insert directly after the EV-32 test line (still before the summary block):

```ada
   ---------------------------------------------------------------------------
   --  EV-33 .. EV-45: Strings, variable refs, functions in expressions,
   --  error cases, language constants
   ---------------------------------------------------------------------------

   --  EV-33: String concatenation via Op_Add
   Check_Str ("EV-33: ""hello"" + "" world""",
              Eval ("""hello"" + "" world"""), "hello world");

   --  EV-34: String equality — true
   Check_Int ("EV-34: ""abc"" = ""abc"" -> 1", Eval ("""abc"" = ""abc"""), 1);

   --  EV-35: String inequality — true
   Check_Int ("EV-35: ""abc"" <> ""xyz"" -> 1", Eval ("""abc"" <> ""xyz"""), 1);

   --  EV-36: Variable reference — integer arithmetic
   --  Sets a temp var X=5 so that Eval("X + 1") can resolve it.
   Set_Temporary ("X", (Kind => Val_Integer, Int_Val => 5));
   Check_Int ("EV-36: X + 1 (X=5) -> 6", Eval ("X + 1"), 6);
   Clear_Temporary;

   --  EV-37: Variable reference — float arithmetic
   Set_Temporary ("Y", (Kind => Val_Numeric, Num_Val => 2.5));
   Check_Num ("EV-37: Y * 2 (Y=2.5) -> 5.0", Eval ("Y * 2"), 5.0);
   Clear_Temporary;

   --  EV-38: Missing variable propagates through binary op
   Set_Temporary ("M", (Kind => Val_Missing));
   Check_Missing ("EV-38: M + 5 (M=missing) -> missing", Eval ("M + 5"));
   Clear_Temporary;

   --  EV-39: Missing variable propagates through comparison
   Set_Temporary ("M", (Kind => Val_Missing));
   Check_Missing ("EV-39: M = 0 (M=missing) -> missing", Eval ("M = 0"));
   Clear_Temporary;

   --  EV-40: Function call result used in arithmetic expression
   Check_Num ("EV-40: SQRT(9.0) + 1.0 = 4.0", Eval ("SQRT(9.0) + 1.0"), 4.0);

   --  EV-41: ABS returns Val_Integer for integer argument; multiply stays integer
   Check_Int ("EV-41: ABS(-3) * 2 = 6", Eval ("ABS(-3) * 2"), 6);

   --  EV-42: Integer division by zero raises Script_Error
   Check ("EV-42: 1 / 0 raises or missing", Raises_Expr ("1 / 0"), True);

   --  EV-43: TRUE constant (zero-arg function fallback) -> Val_Integer 1
   Check_Int ("EV-43: TRUE -> 1", Eval ("TRUE"), 1);

   --  EV-44: FALSE constant -> Val_Integer 0
   Check_Int ("EV-44: FALSE -> 0", Eval ("FALSE"), 0);

   --  EV-45: NOT TRUE -> Val_Integer 0
   Check_Int ("EV-45: NOT TRUE -> 0", Eval ("NOT TRUE"), 0);
```

- [ ] **Step 2: Build**

```bash
gprbuild -P sdata.gpr
```

Expected: compiles without errors.

- [ ] **Step 3: Run and verify 13 new passes**

```bash
./bin/evaluator_unit_test
```

Expected last line: ` 146 passed, 0 failed.`

- [ ] **Step 4: Run the full test suite**

```bash
make check
```

Expected: all unit tests and all integration tests pass.

- [ ] **Step 5: Commit**

```bash
git add tests/evaluator_unit_test.adb
git commit -m "$(cat <<'EOF'
Test: EV-33..EV-45 expression evaluator — strings, variables, functions, errors

13 tests: string concat/comparison, variable reference with missing propagation,
function-in-expression, division-by-zero error handling, TRUE/FALSE/NOT TRUE
language constants. Brings evaluator_unit_test to 146 tests.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Self-Review

**Spec coverage:**
- Literals (numeric, float, string) → EV-01..EV-03 ✓
- All arithmetic operators (+, -, *, /, **) → EV-04..EV-09 ✓
- Operator precedence and parentheses → EV-10..EV-11 ✓
- Unary minus (int and float) → EV-12..EV-13 ✓
- Left-associativity → EV-14 ✓
- Mixed type promotion → EV-15..EV-16 ✓
- All six comparison operators → EV-17..EV-23 ✓
- AND/OR/XOR/NOT → EV-24..EV-31 ✓
- Compound boolean → EV-32 ✓
- String concatenation → EV-33 ✓
- String comparisons → EV-34..EV-35 ✓
- Variable references (int, float) → EV-36..EV-37 ✓
- Missing propagation (binary op, comparison) → EV-38..EV-39 ✓
- Function in expression → EV-40..EV-41 ✓
- Division by zero error path → EV-42 ✓
- TRUE/FALSE/NOT constants → EV-43..EV-45 ✓

**No placeholders:** all steps contain complete, compilable Ada code.

**Type consistency:** `Eval` returns `Value`; `Check_Int`/`Check_Num`/`Check_Str`/`Check_Missing` each expect a `Value` as their second argument — matches the existing helper signatures throughout the file. `Raises_Expr` returns `Boolean`; uses the `Check (Name; Got, Expected : Boolean)` overload — also already present.
