# TABLES Command — Design Specification

**Date:** 2026-07-03
**Status:** Approved (brainstorming complete; implementation plan to follow)
**ADR:** ADR-049 (to be written during implementation)
**Analogue:** SAS `PROC FREQ` / its `TABLES` statement

---

## 1. Purpose

Add a new immediate command, `TABLES`, that produces **frequency and
crosstabulation reports** — SData's analogue of SAS `PROC FREQ`. It supports
one-way frequency tables, two-way crosstabulations, and multiway (three or more)
tabulations, with optional chi-square-family statistics.

`TABLES` is a **print-only reporting command**. Unlike STATS / AGGREGATE /
TRANSPOSE, it does **not** replace the working table, touch the PDV, flush a
pending SAVE, or clear SELECT/BY. It reads the current table and renders a report
to output (respecting the pager). After `TABLES` runs, all interpreter state is
exactly as it was before.

### 1.1 Scope for this version ("Tier 2.5")

Included:

- One-way, two-way, and multiway frequency tabulation.
- Counts: frequency, percent, cumulative frequency, cumulative percent (1-way and
  list forms); cell frequency, cell percent, row percent, column percent, and
  row/column/grand totals (2-way grid).
- Optional statistics (`/CHISQ`): the **complete chi-square family** plus phi,
  contingency coefficient, and Cramér's V (see §6).

Explicitly deferred to a **later feature** (not in this version):

- Fisher's exact test (r×c network algorithm) and 2×2 exact test.
- Ordinal / nominal measures of association with asymptotic standard errors
  (Gamma, Kendall's tau-b, Stuart's tau-c, Somers' D, lambda, uncertainty
  coefficients).
- Odds ratio / relative risk.
- `WEIGHT` variables.

Rationale for the tier boundary: the chi-square family and Cramér's V are all
short formulas that feed the **already-existing** `SData_Core.Statistics`
special functions (`Chi_Square_CDF`, `Incomplete_Gamma_P`, `Log_Gamma`), so they
cost roughly one day beyond a bare Pearson chi-square. The deferred items are
dominated by ASE-correctness validation and the Fisher network algorithm, which
are a separate multi-week effort.

---

## 2. Syntax

```
TABLES request [request ...] [/ option ...]
```

- A **request** is either:
  - a single variable name — a **one-way** table (`TABLES region;`), or
  - two or more variable names joined by `*` — a **crossing**
    (`TABLES region*product;` two-way; `TABLES region*product*year;` multiway).
- **Multiple requests** may appear in one statement, separated by whitespace:
  `TABLES sex race sex*race;` prints three tables.
- A trailing `/ option ...` clause applies to **all** requests in the statement
  (SAS semantics; there are no per-request options).
- Request variables may be **float, integer, or character**. Continuous floats
  are permitted; each distinct value becomes a level (SAS-like — the user's
  responsibility to bin first if that is not desired).
- `TABLES` becomes a **reserved word** (lexer keyword `Token_TABLES` +
  `reserved_keywords` sync), consistent with AGGREGATE / TRANSPOSE / STATS.

### 2.1 Options

| Option | Applies to | Effect |
|---|---|---|
| `/CHISQ` | 1-way, 2-way | Request chi-square-family statistics (see §6). No-op-with-warning for 3+ way. |
| `/MISSING` | all | Treat missing values as a valid category (default excludes them; see §5). |
| `/ORDER=FREQ` | all | Order levels by **descending frequency** (default: by value). |
| `/LIST` | 2-way | Force **list-format** rendering instead of the grid (see §4.4). No-op for 1-way; redundant-but-harmless for 3+ way (already list). |
| `/NOCUM` | 1-way, list | Suppress the cumulative frequency / cumulative percent columns. |
| `/NOPERCENT` | all | Suppress the overall cell **percent** figure. |

Option parsing follows the established USE-style slash-option loop
(cf. `Parse_STATS`, `Parse_TRANSPOSE`). Duplicate options and malformed
`/ORDER=` values are parse-time errors.

---

## 3. Semantics

### 3.1 Filtering and grouping

- **SELECT** is honored: only logically selected rows are counted (same logical-
  space iteration STATS uses).
- **Active BY is honored (SAS-faithful):** a separate set of tables is produced
  for **each active BY group**, each printed under a header identifying the group
  key values. The existing consecutive-group scan (the `Collect_Groups` model used
  by AGGREGATE/STATS) is reused to walk the groups. With no active BY, the whole
  (SELECT-filtered) table is one implicit group and no group header is printed.
- Because `TABLES` is print-only, **BY and SELECT are left intact** afterward
  (contrast STATS/AGGREGATE, which clear them after a build-and-swap).

### 3.2 Pending-deferred guard

`TABLES` raises, before doing any work, if deferred program statements are queued:

```
TABLES: pending program statements exist; issue RUN or NEW first
```

This is consistent with STATS/AGGREGATE and guarantees the report reflects
fully-processed data rather than a pre-transformation snapshot. (Implementation:
the same `Pending_Deferred > 0` check used by `Execute_Stats` /
`Execute_Aggregate`.)

### 3.3 No state mutation

`TABLES` does not: replace the table, add/rename columns, alter the PDV, flush a
pending SAVE, or clear SELECT/BY. Its only effect is emitted report text.

---

## 4. Report layouts

All numeric formatting follows the existing display conventions (percentages to
two decimals; counts as integers). Each table is preceded by a title line naming
the request (and, under BY, a group header).

### 4.1 One-way table

Columns: level, **Frequency**, **Percent**, **Cum Freq**, **Cum Percent**
(cumulative columns suppressed by `/NOCUM`; percent suppressed by `/NOPERCENT`).
A **Total** row closes the table. If any missing values were excluded, a
`Frequency Missing = N` line is printed beneath.

```
Frequency table for REGION

REGION      Frequency    Percent    Cum Freq    Cum Percent
--------    ---------    -------    --------    -----------
East              120      30.00         120          30.00
North              90      22.50         210          52.50
South             190      47.50         400         100.00
--------    ---------    -------
Total             400     100.00

Frequency Missing = 5
```

### 4.2 Two-way table (grid, default)

A contingency grid: rows = levels of the first variable, columns = levels of the
second, plus **Total** row and column and a grand total. Each interior cell shows,
stacked:

- **Frequency**
- **Percent** (of grand total) — suppressed by `/NOPERCENT`
- **Row Percent**
- **Col Percent**

A small **legend box** above the table explains the four stacked cell numbers.
`Frequency Missing = N` is printed beneath if applicable. (There are no
`/NOROW` / `/NOCOL` options in this version; row% and col% always appear in the
grid.)

### 4.3 Multiway table (3+ variables) — list form

Per the approved design, a request of three or more variables is **always**
rendered in **list form** (never as stacked 2-way grids), to keep the report
readable. One row per **observed** combination of all crossing variables, with
columns: the crossing variables, then **Frequency**, **Percent**, **Cum Freq**,
**Cum Percent** (subject to `/NOCUM`, `/NOPERCENT`). Only observed combinations
appear (no zero-count rows).

### 4.4 List form for two-way tables (`/LIST`)

`/LIST` renders a two-way request in the same list form as §4.3 (one row per
observed `A,B` combination, with Frequency / Percent / Cum Freq / Cum Percent)
instead of the grid. Row% / Col% do not appear in list form — they are a grid
concept. `/LIST` changes **presentation only**; it never affects whether
statistics are computed (see §6.3).

---

## 5. Missing-value handling

- **Default:** missing values (missing float/integer, empty character) are
  **excluded** from the table body and from **all** percentage denominators, but
  their count is reported as a `Frequency Missing = N` line beneath the table. For
  a crossing, a row/observation is excluded if **any** of its crossing variables
  is missing (SAS behavior), and the excluded count is reported.
- **`/MISSING`:** missing is promoted to an ordinary category — it appears as its
  own level (row/column/list entry) and is counted in all percentages. No separate
  "Frequency Missing" line is printed in this mode.

---

## 6. Statistics (`/CHISQ`)

Requested by `/CHISQ`. Behavior depends on the table dimension.

### 6.1 One-way + `/CHISQ` — goodness-of-fit

An **equal-proportions goodness-of-fit** chi-square: tests whether the observed
one-way frequencies are consistent with a uniform distribution across the `k`
observed levels. Statistic `Σ (obs − exp)² / exp` with `exp = N/k`, `DF = k − 1`,
p-value `1 − Chi_Square_CDF(stat, DF)`.

### 6.2 Two-way + `/CHISQ` — chi-square family

Computed from the `r × c` contingency matrix of counts (expected
`E_ij = row_i · col_j / N`):

| Statistic | Notes |
|---|---|
| Pearson Chi-Square | `Σ (O−E)²/E`, `DF = (r−1)(c−1)` |
| Likelihood-Ratio Chi-Square (G²) | `2 Σ O·ln(O/E)`, same DF |
| Continuity-Adj. Chi-Square | **2×2 only** (Yates), `DF = 1` |
| Mantel-Haenszel Chi-Square | `(N−1)·r²`, `DF = 1` |
| Phi Coefficient | `√(χ²/N)` |
| Contingency Coefficient | `√(χ²/(χ²+N))` |
| Cramér's V | `√(χ²/(N·min(r−1,c−1)))` |

All p-values use the existing `Chi_Square_CDF`. A **warning** is printed when more
than 20% of expected cell counts are below 5 (SAS-style validity caveat), plus the
sample size `N`.

Output block (representative):

```
Statistic                        DF        Value      Prob
----------------------------------------------------------
Chi-Square                        4       23.4567    0.0001
Likelihood Ratio Chi-Square       4       22.1013    0.0002
Mantel-Haenszel Chi-Square        1        8.9021    0.0028
Phi Coefficient                            0.2421
Contingency Coefficient                    0.2353
Cramer's V                                 0.1712

Sample Size = 400
```

(For a 2×2 table, a "Continuity-Adj. Chi-Square" row with DF=1 is added.)

### 6.3 Three-or-more-way + `/CHISQ`

**Not computed in this version.** A multiway request is rendered as a descriptive
list (§4.3); no per-stratum statistics are produced. If `/CHISQ` is supplied with
a 3+ way request, a warning is emitted and the statistics are skipped:

```
TABLES: /CHISQ is not computed for tables of three or more variables
```

### 6.4 `/LIST` and statistics

`/LIST` affects presentation only. A `2-way /LIST /CHISQ` request still computes
and prints the §6.2 statistics block — the statistics derive from the contingency
matrix, independent of display format.

---

## 7. Architecture and placement

### 7.1 sdata-core (additive)

Add **pure contingency-table statistics functions** to `SData_Core.Statistics`
(the natural home — all special functions already live there). They take a matrix
of counts and return a result record; they perform no I/O and know nothing about
tables, SELECT, or BY.

Illustrative interface (final names/shape settled during implementation):

```ada
type Count_Matrix is array (Positive range <>, Positive range <>) of Natural;

type Chi_Square_Result is record
   DF                : Natural;
   N                 : Natural;
   Pearson_Stat      : Float;   Pearson_P      : Float;
   LR_Stat           : Float;   LR_P           : Float;
   MH_Stat           : Float;   MH_P           : Float;
   Has_Yates         : Boolean; --  True only for 2x2
   Yates_Stat        : Float;   Yates_P        : Float;
   Phi               : Float;
   Contingency       : Float;
   Cramers_V         : Float;
   Pct_Expected_Lt_5 : Float;   --  drives the small-expected-count warning
   Min_Expected      : Float;
end record;

function Chi_Square_Tests (Counts : Count_Matrix) return Chi_Square_Result;

--  One-way equal-proportions goodness-of-fit.
function Goodness_Of_Fit (Counts : Count_Vector) return GOF_Result;
```

These get **unit tests in sdata-core's harness** validated against known
references (e.g., SAS/textbook worked examples).

**Versioning:** additive → sdata-core patch bump (0.1.21 → **0.1.22**). Because
sdata's TABLES handler **calls** these new functions, the **floor in
`sdata/alire.toml` must bump `^0.1.20 → ^0.1.22`** (the `../sdata-core` path pin
otherwise hides this drift from `make check` — a known project gotcha). Update
sdata-core's `consumer-tests.yml` `ref:` per CLAUDE.md as well.

### 7.2 sdata (the bulk — sdata-only command)

TABLES shares nothing with data-vandal (unlike AGGREGATE/STATS, whose build-and-
swap machinery data-vandal reuses), so the command itself is genuinely sdata-only:

- **Lexer** — `Token_TABLES` + `reserved_keywords` sync (`src/lexer/sdata-lexer.*`).
- **AST** — `Stmt_TABLES` discriminant carrying the request list (each request is
  an ordered variable list) and the parsed option flags
  (`src/ast/sdata-ast.ads/adb` + `Free` arm).
- **Parser** — `Parse_TABLES`: request loop (`var [* var ...]` repeated), then the
  slash-option loop; parse-time validation (duplicate options, bad `/ORDER=`,
  empty request).
- **Dispatch** — immediate execution in `sdata-interpreter.adb`
  (`Execute_Statement` arm → `Execute_Tables`), with the pending-deferred guard.
- **Handler** — new subunit **`sdata-interpreter-execute_tables.adb`** that, for
  each request × each BY group:
  1. builds the contingency counts by reading the table in logical (SELECT-
     honoring) space and tallying value-tuples → counts, applying the
     missing-value policy and the level ordering;
  2. when `/CHISQ`, calls the `SData_Core.Statistics` kernels;
  3. renders the appropriate layout (§4) to output via the existing I/O/pager.
- **HELP** — `Help_TABLES` topic in `src/sdata-help.adb`; regenerate the
  `HELP /ALL` snapshot (`tests/expected/help_all.out`) and any options-display
  expected output.

### 7.3 Rationale for the split

Numeric kernels are reusable, pure, and belong with the other statistical
routines (testable in core's harness). Counting and rendering are TABLES-specific
presentation logic with no other consumer, so they stay in sdata. This keeps the
cross-crate interface minimal (just matrices in, result records out).

---

## 8. User-facing documentation (all updated in the same change)

Per CLAUDE.md's "keep the user-facing surface in sync" rule:

1. **Built-in HELP** — `src/sdata-help.adb` `Help_TABLES`; regenerate
   `tests/expected/help_all.out` and affected `*_options` snapshots.
2. **Man page** — `man/man1/sdata.1` (new TABLES section alongside STATS).
3. **Design doc** — `doc/design.md` §7.1 Commands table (new TABLES row) and a
   TABLES subsection describing syntax, options, layouts, and statistics.
4. **ADR-049** — `doc/adrs.md`: records the print-only reporting model, the
   multiway-as-list decision, the Tier-2.5 statistics boundary, and the
   core-computes-kernels / sdata-renders split.

---

## 9. Testing

- **sdata-core unit tests**: `Chi_Square_Tests` and `Goodness_Of_Fit` against
  worked references (2×2, r×c, degenerate rows/cols, small-expected-count flag).
- **sdata integration tests** (`tests/*.cmd` + `tests/expected/`): one-way,
  two-way grid, multiway list, `/LIST` on two-way, `/CHISQ` (1-way GOF, 2-way
  family, 2×2 Yates row, 3+way skip-with-warning), `/MISSING` vs default missing
  line, `/ORDER=FREQ`, `/NOCUM`, `/NOPERCENT`, BY-group repetition, SELECT
  interaction, the pending-deferred guard, multiple requests per statement, and
  error paths (empty request, duplicate/bad options).
- **HELP snapshot** regeneration.
- **Cross-crate gate** before any src-touching commit: `cd ~/Develop/sdata-core &&
  alr build`, then `cd ~/Develop/sdata && make check`, then
  `cd ~/Develop/data-vandal && make check` (data-vandal is unchanged but must stay
  green).

---

## 10. Decisions on record (judgment calls confirmed during brainstorming)

1. **Output model:** print-only report; no table replacement, no state mutation.
2. **Statistics scope:** Tier 2.5 — chi-square family + Cramér's V; Fisher/ASE
   measures/odds-ratio deferred.
3. **Syntax:** multiple requests per statement; `/options` apply to all requests.
4. **BY:** honored (separate table set per group).
5. **Missing:** SAS default (exclude + `Frequency Missing` line) plus `/MISSING`.
6. **Ordering:** by value default, `/ORDER=FREQ` option.
7. **Cell trimming:** `/NOCUM` and `/NOPERCENT` only (no `/NOROW`/`/NOCOL` in v1).
8. **Pending-deferred guard:** enforced, consistent with STATS/AGGREGATE.
9. **Multiway (3+):** always list form.
10. **1-way `/CHISQ`:** equal-proportions goodness-of-fit.
11. **3+way `/CHISQ`:** skip with a warning.
12. **`/LIST`:** forces list format for a two-way table; presentation-only.
13. **Placement:** numeric kernels additive in `SData_Core.Statistics`; command
    (parse/count/render) sdata-only. Floor bump `^0.1.20 → ^0.1.22`.
