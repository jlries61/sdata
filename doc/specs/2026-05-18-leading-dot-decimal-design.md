# Design: Leading-dot decimal literal support

**Date:** 2026-05-18  
**Status:** Approved

## Summary

Fix the lexer so that leading-dot decimal literals such as `.05`, `.1`, and `.5`
are recognized as numeric literals rather than a bare dot followed by a separate
integer token.  This is a language-wide fix; the immediate trigger was
VANDALIZE options (`/perturb=.05,.1`) but the bug affects every context where a
numeric literal can appear.

## Background

The sdata lexer (`src/lexer/sdata-lexer.adb`) handles the dot character at
line 400:

```ada
when '.' => T.Kind := Token_Dot; Advance (Ctx);
```

This unconditionally emits `Token_Dot` for any `.` in the source, even when
the immediately following character is a digit.  As a result, `.05` is
tokenized as:

```
Token_Dot
Token_Numeric_Literal("05")
```

instead of the correct:

```
Token_Numeric_Literal("0.05")
```

Ada's `Float'Value` requires at least one digit before the decimal point, so
the normalized form `"0.05"` is the correct text to store.

**Observed failure:** `vandalize crim into crimnoise /perturb=.05,.1 /miss=.1`
produces `Unrecognized command "05" at line 8`.  The same failure occurs for
any expression containing a leading-dot literal, e.g. `LET X = .5`.

## Existing uses of Token_Dot that must be preserved

| Context | Example | Behaviour after fix |
|---|---|---|
| Missing-value literal | `LET X = .` | `.` not followed by digit → Token_Dot → `Parse_Primary` returns `Expr_Missing` — unchanged |
| Record-separator in BY output | internal only | Token_Dot never produced for this; unchanged |
| VANDALIZE `/PERTURB=.` | bare dot means "use default" | `.` not followed by digit → Token_Dot → VANDALIZE parser reads default — unchanged |

## Approach

Single change in the `when '.' =>` branch of the lexer.  After advancing past
the dot, check whether the current character is a digit.  If yes, build a
`Token_Numeric_Literal` whose text starts with `"0."` followed by all
subsequent digit characters.  If no, emit `Token_Dot` as before.

No changes are needed in the parser, evaluator, or any other component.

## Detailed Changes

### 1. `src/lexer/sdata-lexer.adb` — line 400

Replace:

```ada
when '.' => T.Kind := Token_Dot; Advance (Ctx);
```

With:

```ada
when '.' =>
   Advance (Ctx);
   if not Is_End_Of_Source (Ctx) and then Is_Digit (Current_Char (Ctx)) then
      T.Kind := Token_Numeric_Literal;
      T.Length := 2;
      T.Text (1) := '0';
      T.Text (2) := '.';
      while not Is_End_Of_Source (Ctx) and then Is_Digit (Current_Char (Ctx)) loop
         T.Length := T.Length + 1;
         T.Text (T.Length) := Current_Char (Ctx);
         Advance (Ctx);
      end loop;
   else
      T.Kind := Token_Dot;
   end if;
```

**Edge cases handled:**

| Input | Token produced | Text |
|---|---|---|
| `.05` | Token_Numeric_Literal | `"0.05"` |
| `.1` | Token_Numeric_Literal | `"0.1"` |
| `.5` | Token_Numeric_Literal | `"0.5"` |
| `.` (end of source) | Token_Dot | n/a |
| `.` (followed by letter) | Token_Dot | n/a |
| `.` (bare, before comma) | Token_Dot | n/a |

Note: the fix does not handle `.05e3` (scientific notation with leading dot).
Scientific notation with leading digits already works; the leading-dot +
exponent form is not used in sdata scripts and is out of scope.

### 2. `tests/leading_dot_decimal_test.cmd` — new integration test

```
set x = .5
print x
set y = .05 + .1
print y
if .3 < .4 then print "ok"
```

### 3. `tests/expected/leading_dot_decimal_test.out` — new expected output

```
0.5
0.15
ok
```

### 4. `tests/sdata_unit_test.adb` — new unit test

Add alongside the existing E-series checks:

```ada
Check ("E-15 leading-dot .05 is numeric", Evaluate_Numeric (".05"), 0.05);
Check ("E-16 leading-dot .1 is numeric",  Evaluate_Numeric (".1"),  0.1);
Check ("E-17 bare dot is missing",        Is_Missing (Evaluate ("."),  True);
```

(Exact helper names to match existing test infrastructure.)

## Behaviour Specification

| Expression | Before fix | After fix |
|---|---|---|
| `LET X = .5` | parse error | X = 0.5 |
| `LET X = .05 + .1` | parse error | X = 0.15 |
| `IF X > .3` | parse error | works correctly |
| `/perturb=.05,.1` | "Unrecognized command '05'" | perturb prob=0.05, sd-frac=0.1 |
| `/miss=.1` | "Unrecognized command '1'" | miss prob=0.1 |
| `/shuffle=.1` | "Unrecognized command '1'" | shuffle prob=0.1 |
| `LET X = .` | X = missing | X = missing (unchanged) |
| `/perturb=.` | use default | use default (unchanged) |

## Out of Scope

- Leading-dot scientific notation (`.5e3`)
- Trailing-dot literals (`5.` without fractional part) — these already work
- Any parser or evaluator changes
