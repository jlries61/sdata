# VANDALIZE Command — Design Specification

**Date:** 2026-05-15
**Status:** Approved
**Author:** John L. Ries

---

## 1. Overview

`VANDALIZE` is an **immediate** command (same tier as SORT, NEW, NAMES) that adds a
noisy copy of a permanent variable to the current table. Three noise operations are
available — perturbation, shuffling, and added missingness — and may be combined in
a single statement. They are applied as mutually exclusive alternatives selected by a
multinomial probability draw; the residual probability leaves the cell unchanged.

Primary use cases: synthetic data generation, anonymisation, and sensitivity testing.

---

## 2. Syntax

```
VANDALIZE <source-var> INTO <dest-var>
    [/PERTURB[=<prob>[,<sd-frac>]]]
    [/SHUFFLE[=<prob>]]
    [/MISS[=<prob>]]
    [/BY=<var>[,<var>...]]
```

### 2.1 Source and destination

- `<source-var>` must be an existing **permanent** variable (a column in the current
  table). Temporary variables created by SET are not allowed.
- `<dest-var>` names the output column. It is created if it does not exist; if it
  already exists it is overwritten in full once all output values are computed.
- Source and destination may be the **same** variable (in-place vandalization). The
  column is replaced only after all output values have been computed, so the read and
  write passes never overlap.
- **Arrays:** if `<source-var>` is a defined array (ARRAY or DIM), `<dest-var>` must
  also be an array name. VANDALIZE is applied independently to each element pair
  (source element i → dest element i). The destination array is created or overwritten
  with the same number of elements as the source array.

### 2.2 Operations

At least one of `/PERTURB`, `/SHUFFLE`, `/MISS` must be specified.

#### /PERTURB[=<prob>[,<sd-frac>]]

Adds a random amount to the cell drawn from the normal distribution with mean 0 and
standard deviation equal to sd-frac × σ, where σ is the sample standard deviation of
the source column (or the within-group standard deviation when `/BY=` is active).
Formally: noise ~ Normal(mean = 0, σ_noise = sd-frac × σ).

- `<prob>`: probability that the cell is perturbed. Default **1.0**.
- `<sd-frac>`: noise standard deviation as a fraction of the source column's sample
  standard deviation σ. Default **0.01**.
- Use `.` as a placeholder to accept the default for `<prob>` while supplying
  `<sd-frac>`: e.g. `/PERTURB=.,0.05` means prob=1.0, sd-frac=0.05.
- **Requires a floating-point source variable** (no name suffix). Script_Error if the
  source has a `%` or `$` suffix.
- Script_Error if the source column (or BY-group) has fewer than two non-missing
  values, because the sample standard deviation is undefined.

#### /SHUFFLE[=<prob>]

Replaces the cell's value with a value drawn uniformly at random from the non-missing
values of the source column within the same BY-group (or the full column if `/BY=` is
not specified).

- `<prob>`: probability that the cell is shuffled. Default **1.0**.
- Applicable to all variable types (float, integer, string).

#### /MISS[=<prob>]

Sets the cell to missing.

- `<prob>`: probability that the cell is set to missing. Default **1.0**.
- Applicable to all variable types.

### 2.3 /BY=<var>[,<var>...]

Specifies one or more stratification variables. Operations are computed and applied
independently within each BY-group:

- PERTURB: standard deviation is computed per group.
- SHUFFLE: values are permuted within each group independently.
- MISS: the multinomial draw is per-cell and is not affected by grouping.

`/BY=` in VANDALIZE is **local** to the command; it is independent of any active
global BY statement. All named BY variables must be permanent variables in the current
table.

---

## 3. Type Rules

Variable types are determined by name suffix: no suffix = float, `%` = integer,
`$` = string.

| Source suffix | PERTURB | SHUFFLE | MISS |
|---|---|---|---|
| _(none)_ — float | Yes | Yes | Yes |
| `%` — integer | Script_Error | Yes | Yes |
| `$` — string | Script_Error | Yes | Yes |

The destination variable's name suffix must match the source variable's name suffix.
Mismatch → Script_Error. For in-place vandalization, type compatibility is guaranteed
by definition and no check is needed.

For array vandalization the suffix rule applies element-wise. All elements of a DIM or
ARRAY variable share the same suffix; the array type is determined from the first
element.

---

## 4. Probability Model

Operations are **mutually exclusive per cell**. A single uniform draw u ~ Uniform(0, 1)
determines the cell's fate, using cumulative thresholds in fixed order:

```
[0,                              p_miss)  → Missing
[p_miss,           p_miss+p_shuffle)      → Shuffled value
[p_miss+p_shuffle, p_miss+p_shuffle+p_perturb) → Perturbed value
[sum,              1.0)                   → Original value unchanged
```

The ordering (MISS → SHUFFLE → PERTURB) is an internal implementation detail. Because
the intervals are non-overlapping, the order does not affect the statistical properties.

**Constraint:** The sum of all specified probabilities must be ≤ 1.0. Script_Error if
violated. The residual probability (1.0 − sum) is the implicit "no change" category; it
is never an error for the sum to be less than 1.0.

### 4.1 Cells with missing source values

If a source cell is already missing, the output is always missing regardless of which
operation the multinomial draw selects. Missing source values are also excluded from the
SHUFFLE pool.

---

## 5. Execution Model

### 5.1 Command tier

VANDALIZE is an **immediate** command. It does **not** trigger an implicit RUN. Any
pending deferred statements (LET, SET, PRINT, etc.) remain queued in the program buffer
and execute on the next explicit RUN. VANDALIZE operates on the table in its current
state — the values it reads are those stored in the table at the moment VANDALIZE
executes, not the values that pending deferred statements would produce. This behaviour
is intentional and consistent with SORT.

### 5.2 Execution steps

1. Validate source variable exists as a permanent column.
2. Validate name-suffix compatibility between source and dest; if dest already exists,
   validate it has the same suffix as source.
3. Validate operation/type compatibility (PERTURB requires float source).
4. Validate sum of specified probabilities ≤ 1.0.
5. If `/BY=` is specified, validate all BY variables exist as permanent columns.
6. **Collect** all source column values into a working array (all physical rows).
7. If `/BY=` is specified, compute group membership for all rows by comparing BY
   variable values directly from the table (independent of global BY state).
8. If PERTURB is active: compute sample standard deviation per group (or globally) over
   non-missing values using the two-pass accumulator (N, Sum, Sum_Sq). Raise
   Script_Error if any group has fewer than two non-missing values.
9. If SHUFFLE is active: build a Fisher-Yates shuffled index array per group (or
   globally), drawing swap indices via `Uniform_RN`. Missing source values are excluded
   from the shuffle pool.
10. **Generate** all output values in a single pass over all physical rows:
    - Draw u ~ Uniform_RN(0.0, 1.0) for each row.
    - Apply the multinomial rule to select the output value.
    - If the source cell is missing, output is missing unconditionally.
11. If dest column does not exist, add it to the table with the source column's type.
12. **Write** all output values to the dest column (Set_Value per row).

For arrays, steps 6–12 repeat independently for each source/dest element pair.

---

## 6. Error Conditions

| Condition | Error |
|---|---|
| Source variable not found in table | Script_Error |
| Source is a temporary (SET) variable | Script_Error |
| No operation specified | Script_Error |
| Name-suffix mismatch between source and dest | Script_Error |
| Dest exists with different suffix from source | Script_Error |
| PERTURB specified for an integer or string variable | Script_Error |
| Sum of probabilities > 1.0 | Script_Error |
| Any BY variable not found in table | Script_Error |
| Source group has < 2 non-missing values and PERTURB is active | Script_Error |
| Source is an array and dest is a scalar (or vice versa) | Script_Error |
| Source array and dest array have different sizes | Script_Error |

---

## 7. Implementation Architecture

### 7.1 Files to modify

| File | Change |
|---|---|
| `src/lexer/sdata-lexer.ads` | Add `Token_Dot` to `Token_Kind` |
| `src/lexer/sdata-lexer.adb` | Add `when '.' => T.Kind := Token_Dot; Advance (Ctx);` in the punctuation case; add `Token_VANDALIZE` to `Token_Kind`; add `"VANDALIZE"` keyword |
| `src/ast/sdata-ast.ads` | Add `Stmt_VANDALIZE` to `Statement_Kind`; add AST variant (§7.2) |
| `src/ast/sdata-ast.adb` | Free `Vand_By_Vars` variable list in `Free_Program` |
| `src/parser/sdata-parser.adb` | Parse VANDALIZE statement (§7.3) |
| `src/sdata-interpreter.adb` | Add `Stmt_VANDALIZE` to `Is_Immediate`; add dispatch case in `Execute_Statement` routing to `Execute_Declarative` |
| `src/sdata-interpreter-execute_declarative.adb` | Add `when Stmt_VANDALIZE =>` handler |
| `src/sdata-help.adb` | Add VANDALIZE help entry (§7.4) |
| `man/man1/sdata.1` | Document VANDALIZE |

### 7.2 AST variant for Stmt_VANDALIZE

```ada
when Stmt_VANDALIZE =>
   Vand_Source_Name : String (1 .. Max_Name_Len);
   Vand_Source_Len  : Natural;
   Vand_Dest_Name   : String (1 .. Max_Name_Len);
   Vand_Dest_Len    : Natural;
   Vand_Perturb     : Boolean := False;
   Vand_Shuffle     : Boolean := False;
   Vand_Miss        : Boolean := False;
   Vand_Pprob       : Float   := 1.0;   -- /PERTURB probability
   Vand_SD_Frac     : Float   := 0.01;  -- /PERTURB sd fraction
   Vand_Sprob       : Float   := 1.0;   -- /SHUFFLE probability
   Vand_Mprob       : Float   := 1.0;   -- /MISS probability
   Vand_By_Vars     : Variable_List;    -- null if /BY= not specified
```

All probability and fraction defaults are set at parse time so the executor always
has final values; no sentinel values are needed.

### 7.3 Parser sketch

```
Token_VANDALIZE
  → consume source name (Token_Identifier)
  → consume Token_INTO (or Token_Identifier with text "INTO")
  → consume dest name (Token_Identifier)
  → loop on Token_Slash:
      /PERTURB → Vand_Perturb := True
                 if Token_Equal follows:
                   next token is Token_Dot → prob stays 1.0 (placeholder)
                              or Token_Numeric_Literal → Vand_Pprob := value
                   if Token_Comma follows:
                     next Token_Numeric_Literal → Vand_SD_Frac := value
      /SHUFFLE → Vand_Shuffle := True
                 if Token_Equal follows: Vand_Sprob := numeric value
      /MISS    → Vand_Miss := True
                 if Token_Equal follows: Vand_Mprob := numeric value
      /BY      → consume Token_Equal
                 parse comma-separated variable names into Vand_By_Vars
```

`INTO` should be registered in the lexer as `Token_INTO`, or detected as a
Token_Identifier whose upper-cased text is "INTO" — whichever matches existing
practice for similar two-keyword constructs in the grammar.

### 7.4 Standard deviation computation

Implement inline in the VANDALIZE executor using the same two-pass accumulator as
`Handle_Std_Fn` in `sdata-evaluator-aggregate_fns.adb`. Do not call into the
evaluator; VANDALIZE has no expression evaluation context.

```ada
--  Over non-missing values in the group:
N      : Natural    := 0;
Sum    : Long_Float := 0.0;
Sum_Sq : Long_Float := 0.0;
--  After accumulation:
SD := Float (Sqrt ((Sum_Sq - Sum ** 2 / Long_Float (N)) / Long_Float (N - 1)));
```

### 7.5 Fisher-Yates shuffle

Build a local index array Idx(1..N) initialised to 1..N (non-missing row indices in
the group). For i from N down to 2, swap Idx(i) with Idx(j) where
j = 1 + Integer(Uniform_RN(0.0, 1.0) * Float(i)). The shuffled source value for
output row k is Source(Idx(shuffled_position(k))).

---

## 8. HELP Text

```
Command: VANDALIZE <source> INTO <dest>
             [/PERTURB[=<prob>[,<sd-frac>]]] [/SHUFFLE[=<prob>]]
             [/MISS[=<prob>]] [/BY=<var>[,<var>...]]

Adds a noisy copy of a permanent variable to the current table.
At least one of /PERTURB, /SHUFFLE, /MISS must be specified.
The sum of all probabilities must be <= 1.0; the remainder is
the implicit probability of leaving the cell unchanged.

Operations are mutually exclusive per cell (one uniform draw per row):
  /PERTURB  Add noise ~ Normal(mean=0, sigma=sd-frac x StdDev). Float only.
            prob default 1.0; sd-frac default 0.01.
            Use '.' to keep the prob default: /PERTURB=.,0.05
  /SHUFFLE  Replace with a random value from the same group (or column).
  /MISS     Set cell to missing.

Source and dest may be the same variable (in-place replacement).
Arrays are supported; each element is vandalized independently.
/BY= stratifies by group; independent of any active global BY statement.

VANDALIZE does not trigger a RUN. Pending deferred statements are
unaffected and execute on the next RUN.

Examples:
  VANDALIZE INCOME INTO INCOME_V /PERTURB=.,0.05 /MISS=0.02
  VANDALIZE NAME$ INTO NAME_V$ /SHUFFLE=0.3 /BY=REGION
  VANDALIZE X INTO X /MISS=0.1
```
