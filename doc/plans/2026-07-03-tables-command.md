# TABLES Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a print-only `TABLES` command (SAS `PROC FREQ` analogue) producing one-way, two-way, and multiway frequency/crosstabulation reports with optional chi-square-family statistics.

**Architecture:** Pure contingency-table statistics kernels are added to `SData_Core.Statistics` (additive, unit-tested in sdata-core's harness). Everything else is sdata-only: lexer token, `Stmt_TABLES` AST node carrying a linked list of "requests" (each a crossing of variables), `Parse_TABLES`, immediate dispatch with a pending-deferred guard, and a new subunit `sdata-interpreter-execute_tables.adb` that builds contingency counts from the table (respecting SELECT + honoring BY via public accessors), calls the kernels when `/CHISQ`, and renders the report through `SData_Core.IO`.

**Tech Stack:** Ada 2012, GNAT/GPRbuild, Alire (path pin to `../sdata-core`). Integration tests are `tests/*.cmd` diffed against `tests/expected/*.out` by `make check`. Unit tests are plain-assertion Ada drivers.

## Global Constraints

- **Spec:** `doc/specs/2026-07-03-tables-command-design.md` is authoritative; consult it for any behavior not spelled out here.
- **Scope = Tier 2.5:** counts + chi-square family (Pearson, Likelihood-Ratio, Continuity-Adjusted for 2×2, Mantel-Haenszel) + phi, contingency coefficient, Cramér's V. **No** Fisher's exact, ordinal/nominal ASE measures, odds ratio, or WEIGHT.
- **Print-only:** `TABLES` never mutates the table, PDV, SAVE, SELECT, or BY. Its only effect is emitted report text.
- **Options:** `/CHISQ /MISSING /ORDER=FREQ /LIST /NOCUM /NOPERCENT`. Trailing `/options` apply to **all** requests in the statement.
- **Reserved word:** `TABLES` becomes reserved (lexer keyword + `src/sdata-reserved_keywords.adb` sync).
- **Statistics live in sdata-core** (`SData_Core.Statistics`), additive. Command parse/count/render is **sdata-only**.
- **Versioning at release:** sdata `0.12.3 → 0.13.0` (new command, minor bump via `scripts/bump-version.sh`); sdata-core `0.1.21 → 0.1.22` (additive). **Bump sdata's floor `sdata_core = "^0.1.20"` → `"^0.1.22"`** in `alire.toml` — the `../sdata-core` path pin hides this drift from `make check`, so it must be done deliberately. Bump sdata-core `consumer-tests.yml` `ref:` to `v0.13.0`.
- **Cross-crate gate before any src-touching commit:** `cd ~/Develop/sdata-core && alr build`, then `cd ~/Develop/sdata && make check` (must be green; count grows past 299), then `cd ~/Develop/data-vandal && make check` (unchanged but must stay green). Never use `--no-verify`.
- **Tests use `diff -wu`** (whitespace-insensitive): output token/number order must match; column alignment need not be pixel-perfect.
- **User-facing surface sync (same change):** built-in HELP (`src/sdata-help.adb` + `tests/expected/help_all.out` snapshot), man page (`man/man1/sdata.1`), design doc (`doc/design.md`), and ADR-049 (`doc/adrs.md`).
- **ADR number:** ADR-049 (highest existing is ADR-048).

---

## File Structure

**sdata-core (additive):**
- Modify `src/sdata_core-statistics.ads` — add `Count_Matrix`, `Count_Vector`, `Chi_Square_Result`, `GOF_Result` types and `Chi_Square_Tests`, `Goodness_Of_Fit` functions.
- Modify `src/sdata_core-statistics.adb` — implement them.
- Modify `tests/statistics_tests.adb` — add unit tests.

**sdata (the command):**
- Modify `src/lexer/sdata-lexer.ads` — `Token_TABLES` in `Token_Kind`.
- Modify `src/lexer/sdata-lexer.adb` — keyword recognition.
- Modify `src/sdata-reserved_keywords.adb` — `S.Insert ("TABLES");`.
- Modify `src/ast/sdata-ast.ads` — `Table_Request` type, `Stmt_TABLES` enum literal + variant arm.
- Modify `src/ast/sdata-ast.adb` — `Free` arm for `Stmt_TABLES`.
- Modify `src/parser/sdata-parser.adb` — `Parse_TABLES` + statement dispatch arm.
- Modify `src/sdata-parser.ads` (if `Parse_TABLES` needs a spec) — otherwise local.
- Modify `src/sdata-interpreter.adb` — forward decl, `is separate` binding, dispatch arm, `Pending_Deferred` guard wrapper `Execute_Tables`.
- Create `src/sdata-interpreter-execute_tables.adb` — the counting engine + renderers (the bulk).
- Modify `src/sdata-help.adb` — `Help_TABLES` + registration.
- Create `tests/data/freq.csv` and other fixtures; `tests/tables_*.cmd` + `tests/expected/tables_*.out`.
- Modify `tests/expected/help_all.out` — regenerated snapshot.
- Modify `man/man1/sdata.1`, `doc/design.md`, `doc/adrs.md`.

---

## Task 1: sdata-core — chi-square-family kernel (`Chi_Square_Tests`)

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-statistics.ads`
- Modify: `~/Develop/sdata-core/src/sdata_core-statistics.adb`
- Test: `~/Develop/sdata-core/tests/statistics_tests.adb`

**Interfaces:**
- Consumes: existing `Chi_Square_CDF (X, DF : Float) return Float`.
- Produces:
  ```ada
  type Count_Matrix is array (Positive range <>, Positive range <>) of Natural;

  type Chi_Square_Result is record
     Valid             : Boolean := False;  --  False if any margin is zero / degenerate
     R, C              : Natural := 0;       --  rows, cols
     N                 : Natural := 0;       --  grand total
     DF                : Natural := 0;
     Pearson_Stat      : Float := 0.0;   Pearson_P    : Float := 1.0;
     LR_Stat           : Float := 0.0;   LR_P         : Float := 1.0;
     MH_Stat           : Float := 0.0;   MH_P         : Float := 1.0;
     Has_Yates         : Boolean := False;   --  True only when R=2 and C=2
     Yates_Stat        : Float := 0.0;   Yates_P      : Float := 1.0;
     Phi               : Float := 0.0;
     Contingency       : Float := 0.0;
     Cramers_V         : Float := 0.0;
     Min_Expected      : Float := 0.0;
     Pct_Expected_Lt_5 : Float := 0.0;       --  0..100, drives the small-expected warning
  end record;

  function Chi_Square_Tests (Counts : Count_Matrix) return Chi_Square_Result;
  ```

- [ ] **Step 1: Write the failing unit tests.** In `tests/statistics_tests.adb`, add a `with SData_Core.Statistics;` visibility (already present) and insert this block before the summary print (near line 270). Expected values are hand-computed for the 2×2 table `[[10,20],[30,40]]` (N=100, all E: 12/18/28/42):

```ada
--  ==== Chi_Square_Tests: 2x2 [[10,20],[30,40]] ====
declare
   M : Count_Matrix (1 .. 2, 1 .. 2) :=
     (1 => (10, 20), 2 => (30, 40));
   R : constant Chi_Square_Result := Chi_Square_Tests (M);
begin
   Assert (R.Valid,                                   "ChiSq 2x2 valid");
   Assert (R.N = 100,                                 "ChiSq 2x2 N=100");
   Assert (R.DF = 1,                                  "ChiSq 2x2 DF=1");
   Assert (Approx (R.Pearson_Stat, 0.79365, 1.0e-3),  "ChiSq 2x2 Pearson");
   Assert (Approx (R.Pearson_P,    0.373,   1.0e-2),  "ChiSq 2x2 Pearson p");
   Assert (Approx (R.LR_Stat,      0.80424, 1.0e-3),  "ChiSq 2x2 LR");
   Assert (R.Has_Yates,                               "ChiSq 2x2 has Yates");
   Assert (Approx (R.Yates_Stat,   0.44643, 1.0e-3),  "ChiSq 2x2 Yates");
   Assert (Approx (R.MH_Stat,      0.78571, 1.0e-3),  "ChiSq 2x2 MH");
   Assert (Approx (R.Phi,          0.08909, 1.0e-3),  "ChiSq 2x2 phi");
   Assert (Approx (R.Cramers_V,    0.08909, 1.0e-3),  "ChiSq 2x2 Cramer V");
   Assert (Approx (R.Contingency,  0.08874, 1.0e-3),  "ChiSq 2x2 contingency");
end;

--  ==== Chi_Square_Tests: 2x3, no Yates, expected>=5 all ====
declare
   --  [[20,30,50],[30,20,50]] : N=200, DF=2
   M : Count_Matrix (1 .. 2, 1 .. 3) :=
     (1 => (20, 30, 50), 2 => (30, 20, 50));
   R : constant Chi_Square_Result := Chi_Square_Tests (M);
begin
   Assert (R.DF = 2,                    "ChiSq 2x3 DF=2");
   Assert (not R.Has_Yates,             "ChiSq 2x3 no Yates");
   Assert (R.Valid,                     "ChiSq 2x3 valid");
   Assert (Approx (R.Pct_Expected_Lt_5, 0.0, 1.0e-6), "ChiSq 2x3 no low cells");
end;

--  ==== Degenerate: a zero-margin column -> Valid=False ====
declare
   M : Count_Matrix (1 .. 2, 1 .. 2) := (1 => (5, 0), 2 => (7, 0));
   R : constant Chi_Square_Result := Chi_Square_Tests (M);
begin
   Assert (not R.Valid,   "ChiSq zero-margin invalid");
end;
```

- [ ] **Step 2: Add the type + function declarations** to `sdata_core-statistics.ads` (after the existing distribution declarations, before `private`):

```ada
   ------------------------------------------------------------------
   --  Contingency-table tests (SAS PROC FREQ /CHISQ analogue).      --
   --  Pure: take a matrix / vector of counts, return the statistics. --
   ------------------------------------------------------------------
   type Count_Matrix is array (Positive range <>, Positive range <>) of Natural;
   type Count_Vector is array (Positive range <>) of Natural;

   type Chi_Square_Result is record
      Valid             : Boolean := False;
      R, C              : Natural := 0;
      N                 : Natural := 0;
      DF                : Natural := 0;
      Pearson_Stat      : Float := 0.0;   Pearson_P    : Float := 1.0;
      LR_Stat           : Float := 0.0;   LR_P         : Float := 1.0;
      MH_Stat           : Float := 0.0;   MH_P         : Float := 1.0;
      Has_Yates         : Boolean := False;
      Yates_Stat        : Float := 0.0;   Yates_P      : Float := 1.0;
      Phi               : Float := 0.0;
      Contingency       : Float := 0.0;
      Cramers_V         : Float := 0.0;
      Min_Expected      : Float := 0.0;
      Pct_Expected_Lt_5 : Float := 0.0;
   end record;

   type GOF_Result is record
      Valid  : Boolean := False;
      K      : Natural := 0;    --  number of categories
      N      : Natural := 0;
      DF     : Natural := 0;
      Stat   : Float := 0.0;
      P      : Float := 1.0;
   end record;

   --  Chi-square family for an R x C table of observed counts.
   function Chi_Square_Tests (Counts : Count_Matrix) return Chi_Square_Result;

   --  Equal-proportions goodness-of-fit for a one-way count vector.
   function Goodness_Of_Fit (Counts : Count_Vector) return GOF_Result;
```

- [ ] **Step 3: Implement `Chi_Square_Tests`** in `sdata_core-statistics.adb` (add near the other CDF-based functions; compute in `Long_Float`, return `Float`). `Goodness_Of_Fit` is implemented in Task 2.

```ada
   function Chi_Square_Tests (Counts : Count_Matrix) return Chi_Square_Result is
      Rn   : constant Natural := Counts'Length (1);
      Cn   : constant Natural := Counts'Length (2);
      Res  : Chi_Square_Result;
      Row  : array (1 .. Rn) of Long_Float := (others => 0.0);
      Col  : array (1 .. Cn) of Long_Float := (others => 0.0);
      Tot  : Long_Float := 0.0;
      Low  : Natural := 0;                 --  cells with expected < 5
      Cells : constant Natural := Rn * Cn;
      P_Sum, LR_Sum, Y_Sum, Min_E : Long_Float;
   begin
      Res.R := Rn; Res.C := Cn;
      --  Marginals.
      for I in 1 .. Rn loop
         for J in 1 .. Cn loop
            declare O : constant Long_Float := Long_Float (Counts (Counts'First (1) + I - 1,
                                                                    Counts'First (2) + J - 1));
            begin
               Row (I) := Row (I) + O;
               Col (J) := Col (J) + O;
               Tot := Tot + O;
            end;
         end loop;
      end loop;
      Res.N := Natural (Tot);
      Res.DF := (Rn - 1) * (Cn - 1);

      --  Degenerate guard: any zero margin, or DF = 0, or N = 0.
      if Tot = 0.0 or else Res.DF = 0 then
         Res.Valid := False; return Res;
      end if;
      for I in 1 .. Rn loop
         if Row (I) = 0.0 then Res.Valid := False; return Res; end if;
      end loop;
      for J in 1 .. Cn loop
         if Col (J) = 0.0 then Res.Valid := False; return Res; end if;
      end loop;

      P_Sum := 0.0; LR_Sum := 0.0; Y_Sum := 0.0; Min_E := Long_Float'Last;
      for I in 1 .. Rn loop
         for J in 1 .. Cn loop
            declare
               O : constant Long_Float := Long_Float (Counts (Counts'First (1) + I - 1,
                                                                Counts'First (2) + J - 1));
               E : constant Long_Float := Row (I) * Col (J) / Tot;
            begin
               if E < Min_E then Min_E := E; end if;
               if E < 5.0 then Low := Low + 1; end if;
               P_Sum := P_Sum + (O - E) ** 2 / E;
               if O > 0.0 then
                  LR_Sum := LR_Sum + O * Log (O / E);
               end if;
               if Rn = 2 and then Cn = 2 then
                  Y_Sum := Y_Sum + (abs (O - E) - 0.5) ** 2 / E;
               end if;
            end;
         end loop;
      end loop;

      Res.Valid := True;
      Res.Min_Expected := Float (Min_E);
      Res.Pct_Expected_Lt_5 := Float (100.0 * Long_Float (Low) / Long_Float (Cells));

      Res.Pearson_Stat := Float (P_Sum);
      Res.Pearson_P := 1.0 - Chi_Square_CDF (Res.Pearson_Stat, Float (Res.DF));

      Res.LR_Stat := Float (2.0 * LR_Sum);
      Res.LR_P := 1.0 - Chi_Square_CDF (Res.LR_Stat, Float (Res.DF));

      --  Mantel-Haenszel = (N-1) * Pearson-corr^2; for these design matrices we
      --  use the identity (N-1) * Pearson_chisq / N only for 2x2; for general
      --  RxC SAS uses (N-1) r^2 where r is the Pearson correlation of the
      --  row/col scores. Use integer scores 1..R, 1..C.
      declare
         Mean_R, Mean_C, Sxx, Syy, Sxy : Long_Float := 0.0;
      begin
         for I in 1 .. Rn loop Mean_R := Mean_R + Long_Float (I) * Row (I); end loop;
         for J in 1 .. Cn loop Mean_C := Mean_C + Long_Float (J) * Col (J); end loop;
         Mean_R := Mean_R / Tot;  Mean_C := Mean_C / Tot;
         for I in 1 .. Rn loop
            Sxx := Sxx + Row (I) * (Long_Float (I) - Mean_R) ** 2;
         end loop;
         for J in 1 .. Cn loop
            Syy := Syy + Col (J) * (Long_Float (J) - Mean_C) ** 2;
         end loop;
         for I in 1 .. Rn loop
            for J in 1 .. Cn loop
               declare O : constant Long_Float :=
                  Long_Float (Counts (Counts'First (1) + I - 1, Counts'First (2) + J - 1));
               begin
                  Sxy := Sxy + O * (Long_Float (I) - Mean_R) * (Long_Float (J) - Mean_C);
               end;
            end loop;
         end loop;
         if Sxx > 0.0 and then Syy > 0.0 then
            declare Rho : constant Long_Float := Sxy / Sqrt (Sxx * Syy);
            begin
               Res.MH_Stat := Float ((Tot - 1.0) * Rho * Rho);
            end;
         else
            Res.MH_Stat := 0.0;
         end if;
         Res.MH_P := 1.0 - Chi_Square_CDF (Res.MH_Stat, 1.0);
      end;

      --  Association measures derived from Pearson.
      Res.Phi := Float (Sqrt (P_Sum / Tot));
      Res.Contingency := Float (Sqrt (P_Sum / (P_Sum + Tot)));
      declare
         M : constant Long_Float := Long_Float (Natural'Min (Rn - 1, Cn - 1));
      begin
         Res.Cramers_V := Float (Sqrt (P_Sum / (Tot * M)));
      end;

      if Rn = 2 and then Cn = 2 then
         Res.Has_Yates := True;
         Res.Yates_Stat := Float (Y_Sum);
         Res.Yates_P := 1.0 - Chi_Square_CDF (Res.Yates_Stat, 1.0);
      end if;

      return Res;
   end Chi_Square_Tests;
```

Ensure the body has `Log` and `Sqrt` visible: `Ada.Numerics.Long_Elementary_Functions` (add the `with`/`use` if not already present — check the top of `sdata_core-statistics.adb`; it already uses `Exp`/`Log` for `Incomplete_Gamma_P`, so the instance is available — reuse the same name).

- [ ] **Step 4: Build sdata-core and run the tests.**

Run: `cd ~/Develop/sdata-core && alr build 2>&1 | tail -5 && ./tests/bin/statistics_tests`
Expected: build clean; summary line shows the new asserts passing, `0 failed`.

- [ ] **Step 5: Commit.**

```bash
cd ~/Develop/sdata-core
git checkout -b feature/tables-command-kernels
git add src/sdata_core-statistics.ads src/sdata_core-statistics.adb tests/statistics_tests.adb
git commit -m "feat: add Chi_Square_Tests contingency kernel to Statistics

Additive: R×C chi-square family (Pearson, likelihood-ratio, Yates for
2×2, Mantel-Haenszel) plus phi, contingency coefficient, Cramér's V,
and small-expected-count metrics. Unit-tested against hand-computed
2×2 and 2×3 references. Supports the forthcoming sdata TABLES /CHISQ.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: sdata-core — goodness-of-fit kernel (`Goodness_Of_Fit`)

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-statistics.adb`
- Test: `~/Develop/sdata-core/tests/statistics_tests.adb`

**Interfaces:**
- Consumes: `Count_Vector`, `GOF_Result` (declared in Task 1).
- Produces: `Goodness_Of_Fit (Counts : Count_Vector) return GOF_Result`.

- [ ] **Step 1: Write the failing unit test.** Counts `[10,20,30]`, k=3, N=60, E=20 each → χ²=10, DF=2, p=exp(-5)=0.006738:

```ada
--  ==== Goodness_Of_Fit: [10,20,30] equal-proportions ====
declare
   V : Count_Vector (1 .. 3) := (10, 20, 30);
   R : constant GOF_Result := Goodness_Of_Fit (V);
begin
   Assert (R.Valid,                          "GOF valid");
   Assert (R.K = 3 and R.N = 60,             "GOF k=3 N=60");
   Assert (R.DF = 2,                         "GOF DF=2");
   Assert (Approx (R.Stat, 10.0, 1.0e-4),    "GOF stat=10");
   Assert (Approx (R.P, 0.006738, 1.0e-4),   "GOF p=exp(-5)");
end;

--  Single category or empty -> invalid (DF=0).
declare
   V : Count_Vector (1 .. 1) := (1 => 42);
   R : constant GOF_Result := Goodness_Of_Fit (V);
begin
   Assert (not R.Valid,   "GOF single-category invalid");
end;
```

- [ ] **Step 2: Run to verify it fails.**
Run: `cd ~/Develop/sdata-core && alr build 2>&1 | tail -5`
Expected: FAIL to compile — `Goodness_Of_Fit` body not yet defined (or link error). This confirms the test references the missing function.

- [ ] **Step 3: Implement `Goodness_Of_Fit`** in `sdata_core-statistics.adb`:

```ada
   function Goodness_Of_Fit (Counts : Count_Vector) return GOF_Result is
      K   : constant Natural := Counts'Length;
      Res : GOF_Result;
      Tot : Long_Float := 0.0;
      S   : Long_Float := 0.0;
      E   : Long_Float;
   begin
      Res.K := K;
      for X of Counts loop Tot := Tot + Long_Float (X); end loop;
      Res.N := Natural (Tot);
      if K < 2 or else Tot = 0.0 then
         Res.Valid := False; return Res;
      end if;
      Res.DF := K - 1;
      E := Tot / Long_Float (K);
      for X of Counts loop
         S := S + (Long_Float (X) - E) ** 2 / E;
      end loop;
      Res.Stat := Float (S);
      Res.P := 1.0 - Chi_Square_CDF (Res.Stat, Float (Res.DF));
      Res.Valid := True;
      return Res;
   end Goodness_Of_Fit;
```

- [ ] **Step 4: Build and run tests.**
Run: `cd ~/Develop/sdata-core && alr build 2>&1 | tail -5 && ./tests/bin/statistics_tests`
Expected: build clean; `0 failed`.

- [ ] **Step 5: Commit.**

```bash
cd ~/Develop/sdata-core
git add src/sdata_core-statistics.adb tests/statistics_tests.adb
git commit -m "feat: add Goodness_Of_Fit equal-proportions kernel

One-way equal-proportions chi-square goodness-of-fit, for TABLES
one-way /CHISQ. Unit-tested against [10,20,30] (chi2=10, DF=2,
p=exp(-5)).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

> After Task 2, open the sdata-core PR later (Task 13 coordinates versions). The `../sdata-core` path pin means sdata builds against these functions immediately without a version bump.

---

## Task 3: sdata — lexer token, reserved word, AST node

**Files:**
- Modify: `src/lexer/sdata-lexer.ads` (Token_Kind enum, ~line 32)
- Modify: `src/lexer/sdata-lexer.adb` (keyword recognition, ~line 294)
- Modify: `src/sdata-reserved_keywords.adb` (~line 68)
- Modify: `src/ast/sdata-ast.ads` (types + enum + variant)
- Modify: `src/ast/sdata-ast.adb` (`Free` arm)

**Interfaces:**
- Produces (AST, consumed by Parser in Task 4 and handler in Tasks 5–10):
  ```ada
  type Table_Request_Node;
  type Table_Request is access Table_Request_Node;
  type Table_Request_Node is record
     Vars : Variable_List;      --  ordered vars in this crossing (A*B*C => A,B,C)
     Next : Table_Request;      --  next request in the statement
  end record;
  --  In Statement variant:
  when Stmt_TABLES =>
     Requests        : Table_Request;
     Table_CHISQ     : Boolean := False;
     Table_MISSING   : Boolean := False;
     Table_LIST      : Boolean := False;
     Table_NOCUM     : Boolean := False;
     Table_NOPERCENT : Boolean := False;
     Table_Order_Freq : Boolean := False;   --  /ORDER=FREQ
  ```

- [ ] **Step 1: Add the lexer token.** In `src/lexer/sdata-lexer.ads`, after `Token_STATS,` (line 33) add:

```ada
      Token_TABLES,
```

- [ ] **Step 2: Add keyword recognition.** In `src/lexer/sdata-lexer.adb`, after the `Token_STATS` line (line 296) add:

```ada
      elsif Upper = "TABLES" then T.Kind := Token_TABLES;
```

- [ ] **Step 3: Add the reserved-word sync.** In `src/sdata-reserved_keywords.adb`, alongside the other `S.Insert` calls (alphabetical vicinity of "STATS"/"TRANSPOSE") add:

```ada
   S.Insert ("TABLES");
```

- [ ] **Step 4: Add the AST request type and statement variant.** In `src/ast/sdata-ast.ads`, after the `Variable_List` declaration (~line 36) add the `Table_Request` types shown in **Interfaces**. Add `Stmt_TABLES` to the `Statement_Kind` enum (after `Stmt_STATS`):

```ada
   Stmt_TABLES,         -- Frequency / crosstabulation report (immediate, print-only)
```

Add the variant arm shown in **Interfaces** to the `Statement` variant record (after the `when Stmt_STATS =>` arm).

- [ ] **Step 5: Add the `Free` arm.** In `src/ast/sdata-ast.adb`, in the `Free` procedure case statement, add (mirroring the STATS arm). You need a local recursive free for the request chain — add a nested helper at the top of `Free` or a file-local procedure:

```ada
   when Stmt_TABLES =>
      declare
         Req : Table_Request := Stmt.Requests;
         Nxt : Table_Request;
      begin
         while Req /= null loop
            Nxt := Req.Next;
            Free (Req.Vars);           --  existing Variable_List Free
            Free_Request (Req);        --  Unchecked_Deallocation for Table_Request
            Req := Nxt;
         end loop;
      end;
```

Declare `procedure Free_Request is new Ada.Unchecked_Deallocation (Table_Request_Node, Table_Request);` near the existing `Variable_List` deallocator in `sdata-ast.adb`.

- [ ] **Step 6: Build to verify it compiles.** (No parser arm yet, so `TABLES` still won't parse — that's fine; this task only wires the token/AST.)
Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -5`
Expected: clean build (the new enum literal is unreferenced in dispatch until Task 4/5 — if the compiler warns `Stmt_TABLES` not covered in a `case`, add a temporary `when Stmt_TABLES => null;` to the interpreter dispatch and parser dispatch, which Task 4/5 replace).

- [ ] **Step 7: Commit.**

```bash
cd ~/Develop/sdata
git checkout -b feature/tables-command
git add src/lexer/sdata-lexer.ads src/lexer/sdata-lexer.adb \
        src/sdata-reserved_keywords.adb src/ast/sdata-ast.ads src/ast/sdata-ast.adb \
        src/sdata-interpreter.adb src/parser/sdata-parser.adb
git commit -m "feat(tables): lexer token, reserved word, and AST node

Add Token_TABLES, TABLES reserved-word sync, Stmt_TABLES with a
Table_Request linked list (one node per crossing) and the six option
flags, plus the Free arm. No parsing/dispatch behavior yet.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: sdata — `Parse_TABLES`

**Files:**
- Modify: `src/parser/sdata-parser.adb` (add `Parse_TABLES`; add dispatch arm ~line 2677)

**Interfaces:**
- Consumes: `Table_Request` AST (Task 3); `Parse_Variable_List`, `Peek_Next_Token`, `Get_Next_Token`, `Is_Identifier_Token`, `Identifier_Text`, `Token_Star`, `Token_Slash`, `Token_Equal`, `Script_Error`.
- Produces: a populated `Stmt_TABLES` node.

A **request** = one identifier, optionally followed by `* identifier` repeated. Requests repeat until `/` or end of statement. Then the `/option` loop.

- [ ] **Step 1: Write a failing integration test for the parse (error path).** Create `tests/tables_parse_errors.cmd`:

```
-- TABLES parser: empty request and unknown option are rejected.
USE "tests/data/freq.csv"
TABLES /CHISQ
QUIT
```

Create `tests/expected/tables_parse_errors.out`:

```
Dataset opened: tests/data/freq.csv
Error: TABLES: expected a variable name
```

(The exact error prefix must match how the interpreter prints a `Script_Error`. Verify against an existing parser-error expected file, e.g. grep `tests/expected` for `Error:` lines from a STATS/TRANSPOSE bad-option test, and match that surrounding format precisely — adjust the expected line to the real format.)

- [ ] **Step 2: Create the data fixture** `tests/data/freq.csv`:

```
REGION$,PRODUCT$
East,A
East,A
East,B
West,A
West,B
West,B
```

- [ ] **Step 3: Run to verify it fails** (TABLES not yet parsed → wrong/unknown-command error, not our message).
Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -3 && ./bin/sdata tests/tables_parse_errors.cmd`
Expected: output differs from expected (no `TABLES: expected a variable name`).

- [ ] **Step 4: Implement `Parse_TABLES`** in `src/parser/sdata-parser.adb` (place near `Parse_STATS`). It mirrors the `Parse_TRANSPOSE` slash-loop idiom:

```ada
   procedure Parse_TABLES
     (Ctx  : in out Parser_Context;
      Stmt : Statement_Access)
   is
      First_Req  : Table_Request := null;
      Last_Req   : Table_Request := null;
      Saw_ORDER  : Boolean := False;
   begin
      --  One or more requests, each: ident (* ident)*
      loop
         exit when not Is_Identifier_Token (Peek_Next_Token (Ctx.Lex_Ctx));
         declare
            Req  : constant Table_Request := new Table_Request_Node;
            V1   : Variable_List := null;
            VL   : Variable_List := null;
            function New_Var (T : Token) return Variable_List is
               N : constant Variable_List := new Variable_List_Node;
            begin
               N.Var.Start_Name (1 .. T.Length) := Identifier_Text (T);
               N.Var.Start_Len := T.Length;
               return N;
            end New_Var;
         begin
            declare T : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
            begin V1 := New_Var (T); VL := V1; end;
            --  crossing: * ident ...
            while Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Star loop
               declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                       T2 : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                       pragma Unreferenced (Discard);
               begin
                  if not Is_Identifier_Token (T2) then
                     raise Script_Error with
                       "TABLES: expected a variable name after '*'";
                  end if;
                  VL.Next := New_Var (T2);
                  VL := VL.Next;
               end;
            end loop;
            Req.Vars := V1;
            if First_Req = null then First_Req := Req; else Last_Req.Next := Req; end if;
            Last_Req := Req;
         end;
      end loop;

      if First_Req = null then
         raise Script_Error with "TABLES: expected a variable name";
      end if;
      Stmt.Requests := First_Req;

      --  Options: /CHISQ /MISSING /LIST /NOCUM /NOPERCENT /ORDER=FREQ
      loop
         exit when Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Slash;
         declare
            Discard  : constant Token := Get_Next_Token (Ctx.Lex_Ctx);  --  '/'
            Flag_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
            Flag     : constant String := To_Upper (Flag_Tok.Text (1 .. Flag_Tok.Length));
            pragma Unreferenced (Discard);
         begin
            if Flag = "CHISQ" then
               if Stmt.Table_CHISQ then raise Script_Error with "TABLES: /CHISQ may be specified at most once"; end if;
               Stmt.Table_CHISQ := True;
            elsif Flag = "MISSING" then
               if Stmt.Table_MISSING then raise Script_Error with "TABLES: /MISSING may be specified at most once"; end if;
               Stmt.Table_MISSING := True;
            elsif Flag = "LIST" then
               if Stmt.Table_LIST then raise Script_Error with "TABLES: /LIST may be specified at most once"; end if;
               Stmt.Table_LIST := True;
            elsif Flag = "NOCUM" then
               if Stmt.Table_NOCUM then raise Script_Error with "TABLES: /NOCUM may be specified at most once"; end if;
               Stmt.Table_NOCUM := True;
            elsif Flag = "NOPERCENT" then
               if Stmt.Table_NOPERCENT then raise Script_Error with "TABLES: /NOPERCENT may be specified at most once"; end if;
               Stmt.Table_NOPERCENT := True;
            elsif Flag = "ORDER" then
               if Saw_ORDER then raise Script_Error with "TABLES: /ORDER may be specified at most once"; end if;
               Saw_ORDER := True;
               if Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Equal then
                  raise Script_Error with "TABLES: expected '=' after /ORDER";
               end if;
               declare Eq : constant Token := Get_Next_Token (Ctx.Lex_Ctx); pragma Unreferenced (Eq);
                       Val_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                       Val : constant String := To_Upper (Val_Tok.Text (1 .. Val_Tok.Length));
               begin
                  if Val = "FREQ" then
                     Stmt.Table_Order_Freq := True;
                  elsif Val = "INTERNAL" then
                     Stmt.Table_Order_Freq := False;   --  default
                  else
                     raise Script_Error with "TABLES: /ORDER= must be FREQ or INTERNAL";
                  end if;
               end;
            else
               raise Script_Error with "TABLES: unknown option '/" & Flag & "'";
            end if;
         end;
      end loop;
   end Parse_TABLES;
```

Add the statement dispatch arm near the `when Token_STATS =>` case (~line 2677):

```ada
         when Token_TABLES =>
            Stmt := new Statement (Stmt_TABLES);
            Parse_TABLES (Ctx, Stmt);
```

Also add a temporary interpreter dispatch arm so the build links (Task 5 fills it in): in `src/sdata-interpreter.adb` `Execute_Statement`, replace any temporary `when Stmt_TABLES => null;` with `when Stmt_TABLES => Execute_Tables (Stmt);` only in Task 5. For now, keep a temporary `when Stmt_TABLES => raise SData_Core.Script_Error with "TABLES: not yet implemented";` so parse errors surface but execution is stubbed.

- [ ] **Step 5: Run the parse-error test.**
Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -3 && ./bin/sdata tests/tables_parse_errors.cmd | diff -wu tests/expected/tables_parse_errors.out -`
Expected: no diff (empty request rejected with the exact message). If the error-line format differs, correct the expected file to the real interpreter format and re-run.

- [ ] **Step 6: Commit.**

```bash
cd ~/Develop/sdata
git add src/parser/sdata-parser.adb src/sdata-interpreter.adb \
        tests/tables_parse_errors.cmd tests/expected/tables_parse_errors.out tests/data/freq.csv
git commit -m "feat(tables): Parse_TABLES with request list and options

Parse one-or-more crossing requests (ident (*ident)*) plus the option
loop (/CHISQ /MISSING /LIST /NOCUM /NOPERCENT /ORDER=FREQ|INTERNAL),
with duplicate/unknown/empty-request errors. Execution stubbed until
the handler lands.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: sdata — handler scaffold + counting engine + one-way rendering

**Files:**
- Modify: `src/sdata-interpreter.adb` (forward decl, `is separate`, dispatch arm, `Execute_Tables` guard wrapper)
- Create: `src/sdata-interpreter-execute_tables.adb` (the counting engine + one-way renderer; extended in Tasks 6–10)
- Create: `tests/tables_oneway.cmd`, `tests/expected/tables_oneway.out`

**Interfaces:**
- Consumes: `Stmt_TABLES` AST (Task 3); public Table API (`Logical_Row_Count`, `Logical_To_Physical`, `By_Var_Count`, `By_Var_Name`, `In_Same_Group`, `Get_Value`, `Column_Count`, `Column_Name`); `SData_Core.Values.Value` (public variant, `Kind`, `Num_Val`, `Int_Val`, `Str_Val`, `To_String_Formatted`); `SData_Core.IO.Put_Line`/`New_Line`; `Pending_Deferred`.
- Produces internal (file-local) types reused by later tasks:
  ```ada
  type Level is record
     Val   : SData_Core.Values.Value;
     Disp  : Unbounded_String;      --  To_String_Formatted (Val), or "." for missing
     Count : Natural := 0;          --  marginal count in the current table/group
  end record;
  package Level_Vectors is new Ada.Containers.Vectors (Positive, Level);
  --  Build_Levels: distinct sorted levels of one column across a set of physical rows.
  --  Cell_Count:   joint count for an index-tuple (via a Hashed_Map keyed on the
  --                packed level-index string "i1|i2|...").
  ```

**Design of the counting engine (implement once here; Tasks 6–7 render other shapes over it):**
1. `Group_Rows` — replicate `Collect_Groups`: walk `1 .. Logical_Row_Count`, map to physical, split into groups on `not In_Same_Group` when `By_Var_Count > 0`. Returns a vector of row-index vectors. (Private, since sdata-core's is not visible.)
2. For a request (list of column names `V(1..k)`) within one group's rows:
   - For each `V(i)`, `Build_Levels` → sorted `Level_Vectors.Vector` of distinct present values (skip `Val_Missing` and empty strings unless `/MISSING`; when `/MISSING`, include a synthetic missing level with `Disp = "."`). Sort by value (numeric when both operands numeric/integer; else by `Disp`); if `/ORDER=FREQ`, sort by `Count` descending, ties by value.
   - `Missing_Count` — rows excluded because any `V(i)` is missing (only meaningful when not `/MISSING`).
   - Joint counts: a `Hashed_Map` from packed key → Natural. For each row, resolve each `V(i)`'s level index; if any is missing-excluded, skip and bump `Missing_Count`; else increment the map.
3. One-way (`k = 1`) renders directly from `Level(1)` counts.

- [ ] **Step 1: Write the failing one-way test.** `tests/tables_oneway.cmd`:

```
-- TABLES one-way frequency on a character column.
USE "tests/data/freq.csv"
TABLES REGION$
QUIT
```

Expected `tests/expected/tables_oneway.out` (REGION East=3, West=3; 50% each; whitespace-insensitive):

```
Dataset opened: tests/data/freq.csv
Frequency table for REGION$

REGION$ Frequency Percent Cum_Freq Cum_Percent
East 3 50.00 3 50.00
West 3 50.00 6 100.00
Total 6 100.00

TABLES complete.
```

(Header token `Cum_Freq`/`Cum_Percent` are single tokens to keep `diff -w` matching predictable. Use those exact spellings in the renderer.)

- [ ] **Step 2: Run to verify it fails** (handler still stubbed → "not yet implemented").
Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -3 && ./bin/sdata tests/tables_oneway.cmd`
Expected: prints the stub error, not the table.

- [ ] **Step 3: Wire the handler.** In `src/sdata-interpreter.adb`: (a) add forward declaration near the other `Execute_*` decls: `procedure Execute_Tables (Stmt : Statement_Access);` (b) add `procedure Execute_Tables (Stmt : Statement_Access) is separate;` (c) replace the temporary dispatch arm with `when Stmt_TABLES => Execute_Tables (Stmt);`.

- [ ] **Step 4: Create the subunit** `src/sdata-interpreter-execute_tables.adb` with the guard, the counting engine, and one-way rendering:

```ada
separate (SData.Interpreter)
procedure Execute_Tables (Stmt : Statement_Access) is
   package Values renames SData_Core.Values;
   package IO     renames SData_Core.IO;
   use type Values.Value_Kind;

   --  ---- counting-engine types (reused by Tasks 6-10) ----
   type Level is record
      Val   : Values.Value;
      Disp  : Unbounded_String;
      Count : Natural := 0;
   end record;
   package Level_Vectors is new Ada.Containers.Vectors (Positive, Level);

   function Is_Present (V : Values.Value; Include_Missing : Boolean) return Boolean is
   begin
      if V.Kind = Values.Val_Missing then return Include_Missing; end if;
      if V.Kind = Values.Val_String
        and then Ada.Strings.Unbounded.Length (V.Str_Val) = 0
      then
         return Include_Missing;
      end if;
      return True;
   end Is_Present;

   function Disp_Of (V : Values.Value) return Unbounded_String is
   begin
      if V.Kind = Values.Val_Missing
        or else (V.Kind = Values.Val_String
                 and then Ada.Strings.Unbounded.Length (V.Str_Val) = 0)
      then
         return To_Unbounded_String (".");
      end if;
      return To_Unbounded_String (Values.To_String_Formatted (V));
   end Disp_Of;

   function Numeric (V : Values.Value) return Boolean is
     (V.Kind = Values.Val_Numeric or else V.Kind = Values.Val_Integer);

   function As_Float (V : Values.Value) return Float is
     (if V.Kind = Values.Val_Integer then Float (V.Int_Val) else V.Num_Val);

   --  Value-order comparison for two levels.
   function Level_Less (A, B : Level) return Boolean is
   begin
      if Numeric (A.Val) and then Numeric (B.Val) then
         return As_Float (A.Val) < As_Float (B.Val);
      end if;
      return A.Disp < B.Disp;
   end Level_Less;

   package Level_Sorting is new Level_Vectors.Generic_Sorting ("<" => Level_Less);

   function Freq_Greater (A, B : Level) return Boolean is
     (if A.Count /= B.Count then A.Count > B.Count else Level_Less (A, B));
   package Freq_Sorting is new Level_Vectors.Generic_Sorting ("<" => Freq_Greater);

   Order_Freq      : constant Boolean := Stmt.Table_Order_Freq;
   Include_Missing : constant Boolean := Stmt.Table_MISSING;

   --  Build the distinct, ordered levels of Col across the given physical rows.
   function Build_Levels (Rows : Row_Index_Vectors.Vector; Col : String)
      return Level_Vectors.Vector
   is
      Levels : Level_Vectors.Vector;
      function Find (D : Unbounded_String) return Natural is
      begin
         for I in Levels.First_Index .. Levels.Last_Index loop
            if Levels (I).Disp = D then return I; end if;
         end loop;
         return 0;
      end Find;
   begin
      for P of Rows loop
         declare
            V : constant Values.Value := SData_Core.Table.Get_Value (P, Col);
         begin
            if Is_Present (V, Include_Missing) then
               declare
                  D : constant Unbounded_String := Disp_Of (V);
                  Idx : constant Natural := Find (D);
               begin
                  if Idx = 0 then
                     Levels.Append ((Val => V, Disp => D, Count => 1));
                  else
                     declare L : Level := Levels (Idx);
                     begin L.Count := L.Count + 1; Levels.Replace_Element (Idx, L); end;
                  end if;
               end;
            end if;
         end;
      end loop;
      if Order_Freq then Freq_Sorting.Sort (Levels);
      else Level_Sorting.Sort (Levels); end if;
      return Levels;
   end Build_Levels;

   --  ---- group splitting (replicates sdata-core Collect_Groups via public API) ----
   package Group_Of_Rows is new Ada.Containers.Vectors (Positive, Row_Index_Vectors.Vector,
                                                          Row_Index_Vectors."=");
   function Group_Rows return Group_Of_Rows.Vector is
      Groups : Group_Of_Rows.Vector;
      Group  : Row_Index_Vectors.Vector;
      Prev_P : Positive := 1;
   begin
      for L in 1 .. SData_Core.Table.Logical_Row_Count loop
         declare P : constant Positive := SData_Core.Table.Logical_To_Physical (L);
         begin
            if L = 1 then
               Group.Append (P);
            elsif SData_Core.Table.By_Var_Count = 0
              or else SData_Core.Table.In_Same_Group (P, Prev_P)
            then
               Group.Append (P);
            else
               Groups.Append (Group); Group.Clear; Group.Append (P);
            end if;
            Prev_P := P;
         end;
      end loop;
      if not Group.Is_Empty then Groups.Append (Group); end if;
      return Groups;
   end Group_Rows;

   --  ---- one-way renderer ----
   procedure Render_One_Way (Rows : Row_Index_Vectors.Vector; Col : String) is
      Levels : constant Level_Vectors.Vector := Build_Levels (Rows, Col);
      Total  : Natural := 0;
      Missing : Natural := 0;
      Cum    : Natural := 0;
      Show_Pct : constant Boolean := not Stmt.Table_NOPERCENT;
      Show_Cum : constant Boolean := not Stmt.Table_NOCUM;
   begin
      for L of Levels loop Total := Total + L.Count; end loop;
      --  missing rows for a single var = present-guarded rows not counted
      for P of Rows loop
         if not Is_Present (SData_Core.Table.Get_Value (P, Col), Include_Missing) then
            Missing := Missing + 1;
         end if;
      end loop;

      IO.Put_Line ("Frequency table for " & Col);
      IO.New_Line;
      --  header
      declare H : Unbounded_String := To_Unbounded_String (Col & " Frequency");
      begin
         if Show_Pct then Append (H, " Percent"); end if;
         if Show_Cum then Append (H, " Cum_Freq"); end if;
         if Show_Cum and then Show_Pct then Append (H, " Cum_Percent"); end if;
         IO.Put_Line (To_String (H));
      end;
      for L of Levels loop
         Cum := Cum + L.Count;
         declare
            Line : Unbounded_String := L.Disp & " " & Trim (L.Count'Image, Both);
            Pct  : constant Float := (if Total = 0 then 0.0 else 100.0 * Float (L.Count) / Float (Total));
            CPct : constant Float := (if Total = 0 then 0.0 else 100.0 * Float (Cum) / Float (Total));
         begin
            if Show_Pct then Append (Line, " " & Fmt2 (Pct)); end if;
            if Show_Cum then Append (Line, " " & Trim (Cum'Image, Both)); end if;
            if Show_Cum and then Show_Pct then Append (Line, " " & Fmt2 (CPct)); end if;
            IO.Put_Line (To_String (Line));
         end;
      end loop;
      declare T : Unbounded_String := To_Unbounded_String ("Total " & Trim (Total'Image, Both));
      begin
         if Show_Pct then Append (T, " 100.00"); end if;
         IO.Put_Line (To_String (T));
      end;
      if not Include_Missing and then Missing > 0 then
         IO.New_Line;
         IO.Put_Line ("Frequency Missing = " & Trim (Missing'Image, Both));
      end if;
   end Render_One_Way;

   --  Dispatch one request within one group (extended in Tasks 6-10).
   procedure Render_Request (Rows : Row_Index_Vectors.Vector; Req : Table_Request) is
      K : Natural := 0;
      Cur : Variable_List := Req.Vars;
   begin
      while Cur /= null loop K := K + 1; Cur := Cur.Next; end loop;
      if K = 1 then
         Render_One_Way (Rows, Req.Vars.Var.Start_Name (1 .. Req.Vars.Var.Start_Len));
      else
         IO.Put_Line ("(multiway rendering added in a later task)");   --  replaced in Task 6/7
      end if;
   end Render_Request;

begin
   if Pending_Deferred > 0 then
      raise SData_Core.Script_Error with
        "TABLES: pending program statements exist; issue RUN or NEW first";
   end if;

   declare
      Groups : constant Group_Of_Rows.Vector := Group_Rows;
      Multi_Group : constant Boolean := SData_Core.Table.By_Var_Count > 0 and then Natural (Groups.Length) > 1;
      GI : Natural := 0;
   begin
      for G of Groups loop
         GI := GI + 1;
         if Multi_Group then
            --  BY header (extended/verified in Task 9)
            IO.Put_Line ("----- BY group" & GI'Image & " -----");
         end if;
         declare Req : Table_Request := Stmt.Requests;
         begin
            while Req /= null loop
               Render_Request (G, Req);
               IO.New_Line;
               Req := Req.Next;
            end loop;
         end;
      end loop;
   end;
   IO.Put_Line ("TABLES complete.");
end Execute_Tables;
```

**Notes for the coder:**
- Add the needed `with`/`use` at the top of the parent body if not visible to the subunit: `Ada.Strings.Unbounded`, `Ada.Containers.Vectors`, `SData_Core.Values`, `SData_Core.IO`, `SData_Core.Table`. A subunit inherits the parent's context clauses, so prefer adding `with` clauses to `sdata-interpreter.adb`.
- `Row_Index_Vectors` — declare `package Row_Index_Vectors is new Ada.Containers.Vectors (Positive, Positive);` in the parent body if not already present (search first; the interpreter may already have one).
- `Fmt2 (X : Float) return String` — a two-decimal formatter. Add a file-local helper:
  ```ada
  function Fmt2 (X : Float) return String is
     package F_IO is new Ada.Text_IO.Float_IO (Float);
     Buf : String (1 .. 32); 
  begin
     F_IO.Put (Buf, X, Aft => 2, Exp => 0);
     return Trim (Buf, Both);
  end Fmt2;
  ```
- `Trim`/`Both` come from `Ada.Strings.Fixed`/`Ada.Strings`.

- [ ] **Step 5: Build and run the one-way test.**
Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -5 && ./bin/sdata tests/tables_oneway.cmd | diff -wu tests/expected/tables_oneway.out -`
Expected: no diff. If the numbers are right but tokens differ, reconcile the expected file to the real output (verify East=3/West=3/50.00 by hand first — they must be correct, not just captured).

- [ ] **Step 6: Run the full suite** to confirm no regression.
Run: `cd ~/Develop/sdata && make check 2>&1 | tail -15`
Expected: all integration tests pass (count = prior 299 + the new `tables_oneway` and `tables_parse_errors`).

- [ ] **Step 7: Commit.**

```bash
cd ~/Develop/sdata
git add src/sdata-interpreter.adb src/sdata-interpreter-execute_tables.adb \
        tests/tables_oneway.cmd tests/expected/tables_oneway.out
git commit -m "feat(tables): handler scaffold, counting engine, one-way tables

Add Execute_Tables subunit with the group-splitting + level-building
counting engine (public-API replica of Collect_Groups) and one-way
frequency rendering (Frequency/Percent/Cum, Total, Frequency Missing).
Pending-deferred guard. Crossings render a placeholder until later
tasks.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: sdata — two-way grid rendering + `Count_Matrix` bridge

**Files:**
- Modify: `src/sdata-interpreter-execute_tables.adb` (add `Render_Two_Way_Grid`; call from `Render_Request` when `k=2` and not `/LIST`)
- Create: `tests/tables_twoway.cmd`, `tests/expected/tables_twoway.out`

**Interfaces:**
- Consumes: `Build_Levels`, `Level_Vectors` (Task 5); joint-count map.
- Produces: `Build_Count_Matrix (Rows, V1, V2, L1, L2) return SData_Core.Statistics.Count_Matrix` (reused by Task 10 for `/CHISQ`).

- [ ] **Step 1: Write the failing two-way test.** `tests/tables_twoway.cmd`:

```
-- TABLES two-way crosstabulation (grid).
USE "tests/data/freq.csv"
TABLES REGION$*PRODUCT$
QUIT
```

Hand-computed cells (East,A=2; East,B=1; West,A=1; West,B=2; row/col totals 3/3/3/3; grand 6). Expected `tests/expected/tables_twoway.out` (cells stacked as Frequency, Percent, Row%, Col% — verify the four numbers per cell):

```
Dataset opened: tests/data/freq.csv
Table of REGION$ by PRODUCT$

Cell contents: Frequency Percent Row_Percent Col_Percent

REGION$ PRODUCT$=A PRODUCT$=B Total
East 2 33.33 66.67 66.67 1 16.67 33.33 33.33 3
West 1 16.67 33.33 33.33 2 33.33 66.67 66.67 3
Total 3 3 6

TABLES complete.
```

(Because `diff -w` collapses whitespace, the stacked cell numbers appear on one logical row per source row; keep the renderer's per-cell number order Frequency, Percent, Row%, Col%. Adjust exact tokens to the real output after verifying the four numbers per cell by hand.)

- [ ] **Step 2: Run to verify it fails** (currently prints the placeholder).
Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -3 && ./bin/sdata tests/tables_twoway.cmd | diff -wu tests/expected/tables_twoway.out -`
Expected: diff (placeholder vs grid).

- [ ] **Step 3: Implement the joint-count helper and grid renderer.** Add to the subunit:

```ada
   --  Packed key "i|j" for the joint-count map.
   package Count_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type => String, Element_Type => Natural,
      Hash => Ada.Strings.Hash, Equivalent_Keys => "=");

   function Level_Index (Levels : Level_Vectors.Vector; D : Unbounded_String) return Natural is
   begin
      for I in Levels.First_Index .. Levels.Last_Index loop
         if Levels (I).Disp = D then return I; end if;
      end loop;
      return 0;
   end Level_Index;

   procedure Render_Two_Way_Grid (Rows : Row_Index_Vectors.Vector; V1, V2 : String) is
      L1 : constant Level_Vectors.Vector := Build_Levels (Rows, V1);
      L2 : constant Level_Vectors.Vector := Build_Levels (Rows, V2);
      Joint : Count_Maps.Map;
      Grand : Natural := 0;
      Missing : Natural := 0;
      Show_Pct : constant Boolean := not Stmt.Table_NOPERCENT;
   begin
      for P of Rows loop
         declare
            A : constant Values.Value := SData_Core.Table.Get_Value (P, V1);
            B : constant Values.Value := SData_Core.Table.Get_Value (P, V2);
         begin
            if Is_Present (A, Include_Missing) and then Is_Present (B, Include_Missing) then
               declare
                  I : constant Natural := Level_Index (L1, Disp_Of (A));
                  J : constant Natural := Level_Index (L2, Disp_Of (B));
                  Key : constant String := Trim (I'Image, Both) & "|" & Trim (J'Image, Both);
               begin
                  if Joint.Contains (Key) then Joint.Replace (Key, Joint (Key) + 1);
                  else Joint.Insert (Key, 1); end if;
                  Grand := Grand + 1;
               end;
            else
               Missing := Missing + 1;
            end if;
         end;
      end loop;

      IO.Put_Line ("Table of " & V1 & " by " & V2);
      IO.New_Line;
      IO.Put_Line ("Cell contents: Frequency" &
                   (if Show_Pct then " Percent" else "") & " Row_Percent Col_Percent");
      IO.New_Line;
      --  column header
      declare H : Unbounded_String := To_Unbounded_String (V1);
      begin
         for C of L2 loop Append (H, " " & V2 & "=" & To_String (C.Disp)); end loop;
         Append (H, " Total");
         IO.Put_Line (To_String (H));
      end;
      for I in L1.First_Index .. L1.Last_Index loop
         declare Line : Unbounded_String := L1 (I).Disp; Row_Tot : Natural := L1 (I).Count;
         begin
            for J in L2.First_Index .. L2.Last_Index loop
               declare
                  Key : constant String := Trim (I'Image, Both) & "|" & Trim (J'Image, Both);
                  F   : constant Natural := (if Joint.Contains (Key) then Joint (Key) else 0);
                  Pct : constant Float := (if Grand = 0 then 0.0 else 100.0 * Float (F) / Float (Grand));
                  RP  : constant Float := (if L1 (I).Count = 0 then 0.0 else 100.0 * Float (F) / Float (L1 (I).Count));
                  CP  : constant Float := (if L2 (J).Count = 0 then 0.0 else 100.0 * Float (F) / Float (L2 (J).Count));
               begin
                  Append (Line, " " & Trim (F'Image, Both));
                  if Show_Pct then Append (Line, " " & Fmt2 (Pct)); end if;
                  Append (Line, " " & Fmt2 (RP) & " " & Fmt2 (CP));
               end;
            end loop;
            Append (Line, " " & Trim (Row_Tot'Image, Both));
            IO.Put_Line (To_String (Line));
         end;
      end loop;
      --  Totals row
      declare T : Unbounded_String := To_Unbounded_String ("Total");
      begin
         for C of L2 loop Append (T, " " & Trim (C.Count'Image, Both)); end loop;
         Append (T, " " & Trim (Grand'Image, Both));
         IO.Put_Line (To_String (T));
      end;
      if not Include_Missing and then Missing > 0 then
         IO.New_Line;
         IO.Put_Line ("Frequency Missing = " & Trim (Missing'Image, Both));
      end if;
   end Render_Two_Way_Grid;

   --  Build an R x C count matrix for /CHISQ (Task 10).
   function Build_Count_Matrix (Rows : Row_Index_Vectors.Vector; V1, V2 : String;
                                L1, L2 : Level_Vectors.Vector)
      return SData_Core.Statistics.Count_Matrix
   is
      M : SData_Core.Statistics.Count_Matrix
            (1 .. Natural (L1.Length), 1 .. Natural (L2.Length)) := (others => (others => 0));
   begin
      for P of Rows loop
         declare
            A : constant Values.Value := SData_Core.Table.Get_Value (P, V1);
            B : constant Values.Value := SData_Core.Table.Get_Value (P, V2);
         begin
            if Is_Present (A, Include_Missing) and then Is_Present (B, Include_Missing) then
               M (Level_Index (L1, Disp_Of (A)), Level_Index (L2, Disp_Of (B))) :=
                 M (Level_Index (L1, Disp_Of (A)), Level_Index (L2, Disp_Of (B))) + 1;
            end if;
         end;
      end loop;
      return M;
   end Build_Count_Matrix;
```

Update `Render_Request`: when `K = 2` and not `Stmt.Table_LIST`, call `Render_Two_Way_Grid (Rows, name1, name2)`. (List path for `K=2 and /LIST`, and `K>=3`, is Task 7.) Extract the two names by walking `Req.Vars`.

- [ ] **Step 4: Build and run the two-way test.**
Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -5 && ./bin/sdata tests/tables_twoway.cmd | diff -wu tests/expected/tables_twoway.out -`
Expected: no diff (after reconciling expected tokens to verified values).

- [ ] **Step 5: Full suite.**
Run: `cd ~/Develop/sdata && make check 2>&1 | tail -12`
Expected: green.

- [ ] **Step 6: Commit.**

```bash
cd ~/Develop/sdata
git add src/sdata-interpreter-execute_tables.adb tests/tables_twoway.cmd tests/expected/tables_twoway.out
git commit -m "feat(tables): two-way grid rendering + Count_Matrix bridge

Render the classic contingency grid (cell Frequency/Percent/Row%/Col%,
row/col/grand totals, legend) and add Build_Count_Matrix feeding the
forthcoming /CHISQ path.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: sdata — multiway + `/LIST` list rendering

**Files:**
- Modify: `src/sdata-interpreter-execute_tables.adb` (add `Render_List`; call for `K>=3`, or `K=2 and /LIST`)
- Create: `tests/tables_multiway.cmd`, `tests/expected/tables_multiway.out`, `tests/tables_list.cmd`, `tests/expected/tables_list.out`

**Interfaces:**
- Consumes: `Build_Levels`, joint counting.
- Produces: `Render_List` (one row per observed combination, columns = crossing vars + Frequency/Percent/Cum_Freq/Cum_Percent).

- [ ] **Step 1: Write failing tests.** `tests/tables_list.cmd` (2-way forced to list):

```
-- TABLES two-way in list form.
USE "tests/data/freq.csv"
TABLES REGION$*PRODUCT$ /LIST
QUIT
```

Expected `tests/expected/tables_list.out` (observed combos East,A=2; East,B=1; West,A=1; West,B=2; ordered by value; cumulative over the listing):

```
Dataset opened: tests/data/freq.csv
Table of REGION$ by PRODUCT$

REGION$ PRODUCT$ Frequency Percent Cum_Freq Cum_Percent
East A 2 33.33 2 33.33
East B 1 16.67 3 50.00
West A 1 16.67 4 66.67
West B 2 33.33 6 100.00

TABLES complete.
```

`tests/tables_multiway.cmd` (3-way; needs a third column — extend the fixture). Create `tests/data/freq3.csv`:

```
REGION$,PRODUCT$,YEAR
East,A,1
East,A,1
East,B,2
West,A,1
West,B,2
West,B,2
```

```
-- TABLES three-way (always list form).
USE "tests/data/freq3.csv"
TABLES REGION$*PRODUCT$*YEAR
QUIT
```

Expected `tests/expected/tables_multiway.out` (observed combos in value order: East A 1 =2; East B 2 =1; West A 1 =1; West B 2 =2):

```
Dataset opened: tests/data/freq3.csv
Table of REGION$ by PRODUCT$ by YEAR

REGION$ PRODUCT$ YEAR Frequency Percent Cum_Freq Cum_Percent
East A 1 2 33.33 2 33.33
East B 2 1 16.67 3 50.00
West A 1 1 16.67 4 66.67
West B 2 2 33.33 6 100.00

TABLES complete.
```

- [ ] **Step 2: Run to verify failure** (multiway currently placeholder; `/LIST` two-way still hits the grid).
Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -3 && ./bin/sdata tests/tables_list.cmd | diff -wu tests/expected/tables_list.out -`
Expected: diff.

- [ ] **Step 3: Implement `Render_List`.** Generalize joint counting to `k` columns keyed on the packed tuple of level indices, iterate observed tuples in value order:

```ada
   procedure Render_List (Rows : Row_Index_Vectors.Vector; Req : Table_Request) is
      --  Collect column names and per-column level vectors.
      type Name_Arr is array (Positive range <>) of Unbounded_String;
      K : Natural := 0;
      C : Variable_List := Req.Vars;
      Show_Pct : constant Boolean := not Stmt.Table_NOPERCENT;
      Show_Cum : constant Boolean := not Stmt.Table_NOCUM;
   begin
      while C /= null loop K := K + 1; C := C.Next; end loop;
      declare
         Names  : Name_Arr (1 .. K);
         Levels : array (1 .. K) of Level_Vectors.Vector;
         Joint  : Count_Maps.Map;
         Grand  : Natural := 0;
         Missing : Natural := 0;
      begin
         C := Req.Vars;
         for I in 1 .. K loop
            Names (I) := To_Unbounded_String (C.Var.Start_Name (1 .. C.Var.Start_Len));
            Levels (I) := Build_Levels (Rows, To_String (Names (I)));
            C := C.Next;
         end loop;
         --  Joint counts keyed on "i1|i2|...".
         for P of Rows loop
            declare
               Key : Unbounded_String; OK : Boolean := True;
            begin
               for I in 1 .. K loop
                  declare V : constant Values.Value :=
                     SData_Core.Table.Get_Value (P, To_String (Names (I)));
                  begin
                     if not Is_Present (V, Include_Missing) then OK := False; exit; end if;
                     if I > 1 then Append (Key, "|"); end if;
                     Append (Key, Trim (Level_Index (Levels (I), Disp_Of (V))'Image, Both));
                  end;
               end loop;
               if OK then
                  if Joint.Contains (To_String (Key)) then
                     Joint.Replace (To_String (Key), Joint (To_String (Key)) + 1);
                  else Joint.Insert (To_String (Key), 1); end if;
                  Grand := Grand + 1;
               else Missing := Missing + 1;
               end if;
            end;
         end loop;

         --  Title.
         declare T : Unbounded_String := "Table of " & Names (1);
         begin
            for I in 2 .. K loop Append (T, " by " & Names (I)); end loop;
            IO.Put_Line (To_String (T));
         end;
         IO.New_Line;
         declare H : Unbounded_String;
         begin
            for I in 1 .. K loop Append (H, To_String (Names (I)) & " "); end loop;
            Append (H, "Frequency");
            if Show_Pct then Append (H, " Percent"); end if;
            if Show_Cum then Append (H, " Cum_Freq"); end if;
            if Show_Cum and then Show_Pct then Append (H, " Cum_Percent"); end if;
            IO.Put_Line (To_String (H));
         end;
         --  Enumerate tuples in value order via nested lexicographic walk over Levels.
         declare
            Cum : Natural := 0;
            Idx : array (1 .. K) of Positive := (others => 1);
            Done : Boolean := (for some I in 1 .. K => Natural (Levels (I).Length) = 0);
         begin
            while not Done loop
               declare
                  Key : Unbounded_String;
               begin
                  for I in 1 .. K loop
                     if I > 1 then Append (Key, "|"); end if;
                     Append (Key, Trim (Idx (I)'Image, Both));
                  end loop;
                  if Joint.Contains (To_String (Key)) then
                     declare
                        F : constant Natural := Joint (To_String (Key));
                        Line : Unbounded_String;
                        Pct : constant Float := (if Grand = 0 then 0.0 else 100.0 * Float (F) / Float (Grand));
                     begin
                        Cum := Cum + F;
                        for I in 1 .. K loop Append (Line, To_String (Levels (I)(Idx (I)).Disp) & " "); end loop;
                        Append (Line, Trim (F'Image, Both));
                        if Show_Pct then Append (Line, " " & Fmt2 (Pct)); end if;
                        if Show_Cum then Append (Line, " " & Trim (Cum'Image, Both)); end if;
                        if Show_Cum and then Show_Pct then
                           Append (Line, " " & Fmt2 (if Grand = 0 then 0.0 else 100.0 * Float (Cum) / Float (Grand)));
                        end if;
                        IO.Put_Line (To_String (Line));
                     end;
                  end if;
                  --  increment odometer (last index fastest) to keep value order
                  declare Carry : Integer := K;
                  begin
                     loop
                        if Idx (Carry) < Natural (Levels (Carry).Length) then
                           Idx (Carry) := Idx (Carry) + 1; exit;
                        else
                           Idx (Carry) := 1; Carry := Carry - 1;
                           if Carry = 0 then Done := True; exit; end if;
                        end if;
                     end loop;
                  end;
               end;
            end loop;
         end;
         if not Include_Missing and then Missing > 0 then
            IO.New_Line; IO.Put_Line ("Frequency Missing = " & Trim (Missing'Image, Both));
         end if;
      end;
   end Render_List;
```

Update `Render_Request`: `K=1` → one-way; `K=2 and not /LIST` → grid; otherwise (`K=2 and /LIST`, or `K>=3`) → `Render_List`.

- [ ] **Step 4: Build and run both new tests.**
Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -5 && for t in tables_list tables_multiway; do ./bin/sdata tests/$t.cmd | diff -wu tests/expected/$t.out - && echo "$t OK"; done`
Expected: both OK (reconcile expected tokens to verified counts).

- [ ] **Step 5: Full suite.**
Run: `cd ~/Develop/sdata && make check 2>&1 | tail -12`
Expected: green.

- [ ] **Step 6: Commit.**

```bash
cd ~/Develop/sdata
git add src/sdata-interpreter-execute_tables.adb \
        tests/tables_list.cmd tests/expected/tables_list.out \
        tests/tables_multiway.cmd tests/expected/tables_multiway.out tests/data/freq3.csv
git commit -m "feat(tables): multiway and /LIST list-form rendering

K>=3 requests and two-way /LIST render as a value-ordered listing of
observed combinations (Frequency/Percent/Cum). Odometer enumeration
keeps level order.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: sdata — `/MISSING`, `/ORDER=FREQ`, `/NOCUM`, `/NOPERCENT` behavior tests

**Files:**
- Create: `tests/tables_missing.cmd`+`.out`, `tests/tables_order_freq.cmd`+`.out`, `tests/tables_nocum.cmd`+`.out`, `tests/tables_nopercent.cmd`+`.out`
- Create fixture: `tests/data/freq_miss.csv`

The option *plumbing* already exists (Task 4 flags; Tasks 5–7 honor `Include_Missing`, `Order_Freq`, `Show_Cum`, `Show_Pct`). This task adds the **tests** that lock the behavior in. If any test exposes a bug, fix the renderer in the same task.

- [ ] **Step 1: Missing fixture + tests.** `tests/data/freq_miss.csv` (a missing char and a `.` numeric):

```
REGION$,PRODUCT$
East,A
East,
West,A
,B
```

`tests/tables_missing.cmd` — default (excluded, count reported):

```
USE "tests/data/freq_miss.csv"
TABLES REGION$
QUIT
```

Default one-way REGION: East=2, West=1, one row REGION missing → `Frequency Missing = 1`, Total=3. Expected `tests/expected/tables_missing.out`:

```
Dataset opened: tests/data/freq_miss.csv
Frequency table for REGION$

REGION$ Frequency Percent Cum_Freq Cum_Percent
East 2 66.67 2 66.67
West 1 33.33 3 100.00
Total 3 100.00

Frequency Missing = 1
```

`tests/tables_missing_incl.cmd` — `/MISSING` (missing becomes a `.` level, counted; no missing line):

```
USE "tests/data/freq_miss.csv"
TABLES REGION$ /MISSING
QUIT
```

Expected `tests/expected/tables_missing_incl.out` (East=2, West=1, `.`=1, Total=4; `.` sorts last):

```
Dataset opened: tests/data/freq_miss.csv
Frequency table for REGION$

REGION$ Frequency Percent Cum_Freq Cum_Percent
East 2 50.00 2 50.00
West 1 25.00 3 75.00
. 1 25.00 4 100.00
Total 4 100.00
```

- [ ] **Step 2: `/ORDER=FREQ` test.** Use `tests/data/freq3.csv` PRODUCT (A=2, B... recount from freq3: PRODUCT A appears rows 1,2,4 =3; B rows 3,5,6 =3 — tie). Instead use a fixture with a clear frequency order. Create `tests/data/freq_ord.csv`:

```
G$
b
a
a
a
b
b
b
```

`a`=3, `b`=4. `tests/tables_order_freq.cmd`:

```
USE "tests/data/freq_ord.csv"
TABLES G$ /ORDER=FREQ
QUIT
```

Expected `tests/expected/tables_order_freq.out` (b first, then a):

```
Dataset opened: tests/data/freq_ord.csv
Frequency table for G$

G$ Frequency Percent Cum_Freq Cum_Percent
b 4 57.14 4 57.14
a 3 42.86 7 100.00
Total 7 100.00
```

- [ ] **Step 3: `/NOCUM` and `/NOPERCENT` tests** over `tests/data/freq.csv` REGION:

`tests/tables_nocum.cmd` → header omits Cum columns. Expected `tests/expected/tables_nocum.out`:

```
Dataset opened: tests/data/freq.csv
Frequency table for REGION$

REGION$ Frequency Percent
East 3 50.00
West 3 50.00
Total 6 100.00
```

`tests/tables_nopercent.cmd` → omits Percent (and Cum_Percent, since it depends on Percent). Expected `tests/expected/tables_nopercent.out`:

```
Dataset opened: tests/data/freq.csv
Frequency table for REGION$

REGION$ Frequency Cum_Freq
East 3 3
West 3 6
Total 6
```

- [ ] **Step 4: Run each new test; fix renderer if any diff is a real bug.**
Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -3 && for t in tables_missing tables_missing_incl tables_order_freq tables_nocum tables_nopercent; do ./bin/sdata tests/$t.cmd | diff -wu tests/expected/$t.out - && echo "$t OK"; done`
Expected: all OK.

- [ ] **Step 5: Full suite.**
Run: `cd ~/Develop/sdata && make check 2>&1 | tail -12`
Expected: green.

- [ ] **Step 6: Commit.**

```bash
cd ~/Develop/sdata
git add tests/tables_missing*.cmd tests/expected/tables_missing*.out \
        tests/tables_order_freq.cmd tests/expected/tables_order_freq.out \
        tests/tables_nocum.cmd tests/expected/tables_nocum.out \
        tests/tables_nopercent.cmd tests/expected/tables_nopercent.out \
        tests/data/freq_miss.csv tests/data/freq_ord.csv \
        src/sdata-interpreter-execute_tables.adb
git commit -m "test(tables): lock /MISSING /ORDER=FREQ /NOCUM /NOPERCENT behavior

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: sdata — BY-group handling

**Files:**
- Modify: `src/sdata-interpreter-execute_tables.adb` (finalize the BY-group header format)
- Create: `tests/tables_by.cmd`, `tests/expected/tables_by.out`, fixture `tests/data/freq_by.csv`

BY plumbing exists (Task 5 `Group_Rows` loop). This task pins the header format and verifies per-group repetition. Choose a concrete header: `BY <var1>=<v1> <var2>=<v2>` using the group's first physical row values.

- [ ] **Step 1: Replace the placeholder BY header** in `Execute_Tables` with a real one:

```ada
   procedure Put_By_Header (First_Phys : Positive) is
      H : Unbounded_String := To_Unbounded_String ("----- BY");
   begin
      for I in 1 .. SData_Core.Table.By_Var_Count loop
         Append (H, " " & SData_Core.Table.By_Var_Name (I) & "="
                 & Values.To_String_Formatted
                     (SData_Core.Table.Get_Value (First_Phys, SData_Core.Table.By_Var_Name (I))));
      end loop;
      Append (H, " -----");
      IO.Put_Line (To_String (H));
   end Put_By_Header;
```

Call `Put_By_Header (G.First_Element)` when `Multi_Group` (replace the `"----- BY group N -----"` line).

- [ ] **Step 2: Write the failing BY test.** `tests/data/freq_by.csv` (sorted by G, as BY requires sorted input):

```
G$,X$
p,a
p,a
p,b
q,a
q,b
q,b
```

`tests/tables_by.cmd`:

```
USE "tests/data/freq_by.csv"
BY G$
TABLES X$
QUIT
```

Expected `tests/expected/tables_by.out` (group p: a=2,b=1; group q: a=1,b=2):

```
Dataset opened: tests/data/freq_by.csv
----- BY G$=p -----
Frequency table for X$

X$ Frequency Percent Cum_Freq Cum_Percent
a 2 66.67 2 66.67
b 1 33.33 3 100.00
Total 3 100.00

----- BY G$=q -----
Frequency table for X$

X$ Frequency Percent Cum_Freq Cum_Percent
a 1 33.33 1 33.33
b 2 66.67 3 100.00
Total 3 100.00

TABLES complete.
```

Verify BY/SELECT are untouched afterward: add to the same `.cmd` a `NAMES` or a second `TABLES X$` and confirm identical output (BY still active). Keep the expected file consistent with whatever you add.

- [ ] **Step 3: Run.**
Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -3 && ./bin/sdata tests/tables_by.cmd | diff -wu tests/expected/tables_by.out -`
Expected: no diff.

- [ ] **Step 4: Full suite.**
Run: `cd ~/Develop/sdata && make check 2>&1 | tail -12`
Expected: green.

- [ ] **Step 5: Commit.**

```bash
cd ~/Develop/sdata
git add src/sdata-interpreter-execute_tables.adb tests/tables_by.cmd tests/expected/tables_by.out tests/data/freq_by.csv
git commit -m "feat(tables): per-BY-group tables with group headers

Honor active BY: one table set per group under a 'BY var=val' header;
BY/SELECT left intact afterward (print-only).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: sdata — `/CHISQ` wiring

**Files:**
- Modify: `src/sdata-interpreter-execute_tables.adb` (emit stats block for 1-way and 2-way; warn-and-skip for 3+way)
- Create: `tests/tables_chisq_2way.cmd`+`.out`, `tests/tables_chisq_1way.cmd`+`.out`, `tests/tables_chisq_multiway.cmd`+`.out`

**Interfaces:**
- Consumes: `SData_Core.Statistics.Chi_Square_Tests`, `Goodness_Of_Fit`; `Build_Count_Matrix` (Task 6); `Build_Levels`.

- [ ] **Step 1: Emit the 2-way stats block.** After a two-way render (both grid and `/LIST`), when `Stmt.Table_CHISQ`, build the matrix and print. Add a helper and call it from `Render_Request` for `K=2`:

```ada
   procedure Put_Chisq_2Way (Rows : Row_Index_Vectors.Vector; V1, V2 : String) is
      L1 : constant Level_Vectors.Vector := Build_Levels (Rows, V1);
      L2 : constant Level_Vectors.Vector := Build_Levels (Rows, V2);
      M  : constant SData_Core.Statistics.Count_Matrix := Build_Count_Matrix (Rows, V1, V2, L1, L2);
      R  : constant SData_Core.Statistics.Chi_Square_Result := SData_Core.Statistics.Chi_Square_Tests (M);
   begin
      IO.New_Line;
      IO.Put_Line ("Statistic DF Value Prob");
      if not R.Valid then
         IO.Put_Line ("(chi-square not computed: a row or column total is zero)");
         return;
      end if;
      IO.Put_Line ("Chi-Square " & Trim (R.DF'Image, Both) & " " & Fmt4 (R.Pearson_Stat) & " " & Fmt4 (R.Pearson_P));
      IO.Put_Line ("Likelihood_Ratio_Chi-Square " & Trim (R.DF'Image, Both) & " " & Fmt4 (R.LR_Stat) & " " & Fmt4 (R.LR_P));
      if R.Has_Yates then
         IO.Put_Line ("Continuity-Adj._Chi-Square 1 " & Fmt4 (R.Yates_Stat) & " " & Fmt4 (R.Yates_P));
      end if;
      IO.Put_Line ("Mantel-Haenszel_Chi-Square 1 " & Fmt4 (R.MH_Stat) & " " & Fmt4 (R.MH_P));
      IO.Put_Line ("Phi_Coefficient " & Fmt4 (R.Phi));
      IO.Put_Line ("Contingency_Coefficient " & Fmt4 (R.Contingency));
      IO.Put_Line ("Cramers_V " & Fmt4 (R.Cramers_V));
      IO.New_Line;
      IO.Put_Line ("Sample_Size = " & Trim (R.N'Image, Both));
      if R.Pct_Expected_Lt_5 > 20.0 then
         IO.Put_Line ("WARNING: over 20% of cells have expected count < 5; chi-square may be invalid.");
      end if;
   end Put_Chisq_2Way;
```

Add `Fmt4` (four-decimal) analogous to `Fmt2`.

- [ ] **Step 2: Emit the 1-way GOF block.** When `K=1` and `Stmt.Table_CHISQ`, after the one-way render:

```ada
   procedure Put_Chisq_1Way (Rows : Row_Index_Vectors.Vector; Col : String) is
      L : constant Level_Vectors.Vector := Build_Levels (Rows, Col);
      V : SData_Core.Statistics.Count_Vector (1 .. Natural (L.Length));
      Idx : Positive := 1;
   begin
      for Lv of L loop V (Idx) := Lv.Count; Idx := Idx + 1; end loop;
      declare R : constant SData_Core.Statistics.GOF_Result := SData_Core.Statistics.Goodness_Of_Fit (V);
      begin
         IO.New_Line;
         IO.Put_Line ("Chi-Square Goodness-of-Fit (equal proportions)");
         if R.Valid then
            IO.Put_Line ("Chi-Square " & Trim (R.DF'Image, Both) & " " & Fmt4 (R.Stat) & " " & Fmt4 (R.P));
         else
            IO.Put_Line ("(not computed: fewer than two categories)");
         end if;
      end;
   end Put_Chisq_1Way;
```

- [ ] **Step 3: Warn-and-skip for 3+way.** In `Render_Request`, when `K >= 3` and `Stmt.Table_CHISQ`, after the list render:

```ada
   IO.Put_Line ("TABLES: /CHISQ is not computed for tables of three or more variables");
```

- [ ] **Step 4: Write tests with hand-computed stats.** `tests/tables_chisq_2way.cmd` over `tests/data/freq.csv` REGION×PRODUCT (2×2 counts [[2,1],[1,2]], N=6, all E=1.5): Pearson=0.6667 DF=1; Yates present; verify by hand and reconcile. `tests/tables_chisq_1way.cmd` over a fixture with counts [10,20,30] → χ²=10 DF=2 p=0.0067 (reuse a fixture that yields those counts, e.g. a 60-row file, OR use freq.csv REGION which is 3/3 → χ²=0, p=1.0000 for a simpler exact check):

`tests/tables_chisq_1way.cmd`:

```
USE "tests/data/freq.csv"
TABLES REGION$ /CHISQ
QUIT
```

REGION 3/3 → GOF χ²=0, DF=1, p=1.0000. Expected tail:

```
Chi-Square Goodness-of-Fit (equal proportions)
Chi-Square 1 0.0000 1.0000
```

`tests/tables_chisq_multiway.cmd` over `freq3.csv` with `/CHISQ` → list + skip warning. Expected tail includes:

```
TABLES: /CHISQ is not computed for tables of three or more variables
```

Generate the 2-way expected file by running after implementation and verifying Pearson≈0.6667, DF=1 by hand.

- [ ] **Step 5: Run the new tests.**
Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -5 && for t in tables_chisq_1way tables_chisq_2way tables_chisq_multiway; do ./bin/sdata tests/$t.cmd | diff -wu tests/expected/$t.out - && echo "$t OK"; done`
Expected: all OK (reconcile 2-way numbers to verified hand values).

- [ ] **Step 6: Full suite.**
Run: `cd ~/Develop/sdata && make check 2>&1 | tail -12`
Expected: green.

- [ ] **Step 7: Commit.**

```bash
cd ~/Develop/sdata
git add src/sdata-interpreter-execute_tables.adb tests/tables_chisq_*.cmd tests/expected/tables_chisq_*.out
git commit -m "feat(tables): /CHISQ statistics wiring

1-way equal-proportions GOF; 2-way chi-square family (Pearson, LR,
Yates for 2x2, Mantel-Haenszel, phi, contingency, Cramer's V) with the
small-expected-count warning; 3+way skip-with-warning.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 11: sdata — built-in HELP + snapshot

**Files:**
- Modify: `src/sdata-help.adb` (add `Help_TABLES`, register it)
- Modify: `tests/expected/help_all.out` (regenerated)
- Modify: `tests/expected/*options*` snapshots only if a TABLES key appears there (it does not; skip if grep finds nothing)

- [ ] **Step 1: Add `Help_TABLES`** in `src/sdata-help.adb` (mirror `Help_STATS` structure, ~line 267):

```ada
   procedure Help_TABLES is
   begin
      Put_Line ("Command: TABLES request [request ...] [/CHISQ] [/MISSING] [/LIST]");
      Put_Line ("                [/ORDER=FREQ] [/NOCUM] [/NOPERCENT]");
      Put_Line ("Print frequency and crosstabulation reports (SAS PROC FREQ analogue).");
      Put_Line ("A request is one variable (one-way table) or variables joined by '*'");
      Put_Line ("(A*B two-way; A*B*C multiway). Multiple requests per statement are");
      Put_Line ("allowed; options apply to all requests. Print-only: the data table,");
      Put_Line ("SELECT, and BY are left unchanged.");
      Put_Line ("  /CHISQ      chi-square family (Pearson, likelihood-ratio, Mantel-");
      Put_Line ("              Haenszel, continuity-adjusted for 2x2) plus phi,");
      Put_Line ("              contingency coefficient, Cramer's V. One-way: equal-");
      Put_Line ("              proportions goodness-of-fit. Not computed for 3+ way.");
      Put_Line ("  /MISSING    treat missing as a valid category (default: excluded,");
      Put_Line ("              reported as 'Frequency Missing = N').");
      Put_Line ("  /ORDER=FREQ order levels by descending frequency (default: by value).");
      Put_Line ("  /LIST       render a two-way table in list form (default for 3+ way).");
      Put_Line ("  /NOCUM      suppress cumulative columns (one-way / list).");
      Put_Line ("  /NOPERCENT  suppress the overall cell percent.");
      Put_Line ("Honors the active SELECT filter and produces one table set per active");
      Put_Line ("BY group. Refuses to run while un-run deferred statements are pending.");
      Put_Line ("Execution: Immediate (print-only). See man page sdata(1).");
   end Help_TABLES;
```

Register it in `Help_Table` (near the STATS entry, ~line 1479), marking COMMAND-reference only:

```ada
     (K_TABLES'Access,     Help_TABLES'Access,     C, N),
```

Declare `K_TABLES : aliased constant String := "TABLES";` alongside the other `K_*` topic-key constants (find `K_STATS`).

- [ ] **Step 2: Build.**
Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -3`
Expected: clean.

- [ ] **Step 3: Verify the topic works, then regenerate the snapshot.**
Run: `cd ~/Develop/sdata && ./bin/sdata <<< "HELP TABLES"` (eyeball) then `./bin/sdata <<< "HELP /ALL" > tests/expected/help_all.out 2>&1`
Expected: `HELP TABLES` prints the topic; snapshot regenerated with the TABLES block under COMMAND REFERENCE.

- [ ] **Step 4: Full suite** (the `help_all` integration test now matches the new snapshot).
Run: `cd ~/Develop/sdata && make check 2>&1 | tail -12`
Expected: green.

- [ ] **Step 5: Commit.**

```bash
cd ~/Develop/sdata
git add src/sdata-help.adb tests/expected/help_all.out
git commit -m "docs(tables): built-in HELP topic + HELP /ALL snapshot

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 12: docs — man page, design.md, ADR-049

**Files:**
- Modify: `man/man1/sdata.1` (new TABLES section after STATS, ~line 664)
- Modify: `doc/design.md` (new row in the §7.1 Commands table, ~line 987, and a TABLES subsection)
- Modify: `doc/adrs.md` (ADR-049)

This is a documentation-only commit → per CLAUDE.md, **no `make check` required** (but it does not touch src, so that exemption applies).

- [ ] **Step 1: Man page.** After the STATS `.RE`/`.PP` block (~line 664), add a TABLES section mirroring the STATS groff structure: the synopsis line `.B TABLES\fR ...`, a prose paragraph, and a `.RS`/`.TP` list for `/CHISQ /MISSING /ORDER= /LIST /NOCUM /NOPERCENT`, plus the print-only + BY + pending-deferred notes. Model the markup on the quoted STATS section.

- [ ] **Step 2: design.md.** Add a TABLES `<tr>` to the §7.1 Commands table (after the STATS row at line 987), following the exact HTML pattern (name / syntax / "Immediate Execution" / description). Description must cover: request/crossing syntax, all six options, print-only semantics, 1-way vs 2-way vs multiway-list output, /CHISQ tiers (1-way GOF, 2-way family, 3+way skip), missing handling, BY behavior, and the pending-deferred guard. Cross-reference STATS/AGGREGATE.

- [ ] **Step 3: ADR-049.** Append to `doc/adrs.md`:

```markdown
## ADR-049: TABLES command — print-only frequency/crosstabulation reporting

**Status:** Accepted (2026-07-03)

**Context:** Users want a SAS PROC FREQ analogue for one-way, two-way, and
multiway frequency tables with chi-square statistics.

**Decision:**
- TABLES is **print-only** — it renders a report and never mutates the table,
  PDV, SAVE, SELECT, or BY. This diverges from STATS/AGGREGATE/TRANSPOSE
  (build-and-swap) because a crosstab is inherently 2-D and has no other consumer.
- **Multiway (3+ variables)** always renders in **list form** (one row per
  observed combination), avoiding unreadable stacked 2-way grids. `/LIST` extends
  list form to two-way tables on demand; presentation-only.
- Statistics scope is **Tier 2.5**: the chi-square family (Pearson, likelihood-
  ratio, continuity-adjusted for 2×2, Mantel-Haenszel) plus phi, contingency
  coefficient, and Cramér's V. Fisher's exact, ordinal/nominal ASE measures, and
  odds ratio/relative risk are deferred. One-way `/CHISQ` is an equal-proportions
  goodness-of-fit; 3+way `/CHISQ` is skipped with a warning.
- **Placement:** the pure contingency-table kernels (`Chi_Square_Tests`,
  `Goodness_Of_Fit`) are additive in `SData_Core.Statistics` (reusable, unit-
  tested); counting and rendering are sdata-only (`Execute_Tables` subunit),
  since TABLES shares nothing with data-vandal.

**Consequences:** New reserved word TABLES. sdata-core 0.1.22 (additive); sdata
floor bumped to ^0.1.22. Honors SELECT and active BY (one table set per group).
```

- [ ] **Step 4: Commit.**

```bash
cd ~/Develop/sdata
git add man/man1/sdata.1 doc/design.md doc/adrs.md
git commit -m "docs(tables): man page, design.md command entry, ADR-049

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 13: release — versions, floor bump, consumer-tests ref, final cross-crate gate

**Files:**
- sdata-core: `alire.toml` (version), plus any files `scripts/bump-version.sh` touches there — sdata-core is bumped manually or via its own script.
- sdata: version bump via `scripts/bump-version.sh`; `alire.toml` floor.
- sdata-core: `.github/workflows/consumer-tests.yml` (`ref:`).

- [ ] **Step 1: Bump sdata-core to 0.1.22.** Edit `~/Develop/sdata-core/alire.toml` `version = "0.1.22"`. (sdata-core has no multi-file bump script equivalent to sdata's; if it has one, use it.) Commit on the sdata-core branch:

```bash
cd ~/Develop/sdata-core
git add alire.toml
git commit -m "chore: bump version to 0.1.22 (additive contingency-table kernels)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 2: Bump sdata to 0.13.0.**
Run: `cd ~/Develop/sdata && scripts/bump-version.sh 0.13.0 "Add TABLES command (PROC FREQ analogue): one-way, two-way, and multiway frequency/crosstabulation reports with optional chi-square-family statistics"`
Expected: updates the 9 files listed in CLAUDE.md.

- [ ] **Step 3: Bump the sdata-core floor.** Edit `~/Develop/sdata/alire.toml`: change `sdata_core = "^0.1.20"` → `sdata_core = "^0.1.22"`. (The path pin line stays.) This is mandatory — the path pin hides the drift from `make check`.

- [ ] **Step 4: Bump sdata-core consumer-tests ref.** Edit `~/Develop/sdata-core/.github/workflows/consumer-tests.yml`: set the sdata `ref:` to `v0.13.0`. Commit on the sdata-core branch.

- [ ] **Step 5: Final three-way cross-crate gate.**
Run:
```bash
cd ~/Develop/sdata-core && alr build 2>&1 | tail -3
cd ~/Develop/sdata && make check 2>&1 | tail -15
cd ~/Develop/data-vandal && make check 2>&1 | tail -8
```
Expected: sdata-core builds; sdata green (299 + ~15 new tables tests + unchanged); data-vandal green (unchanged).

- [ ] **Step 6: Commit the sdata release.**

```bash
cd ~/Develop/sdata
git add -A
git commit -m "chore: bump version to 0.13.0; sdata-core floor ^0.1.22

TABLES command release. Floor bumped to require the sdata-core version
that ships the contingency-table kernels (path pin otherwise hides the
drift).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 7: Open PRs and coordinate merge.** sdata-core PR first (adds kernels + version + consumer-tests ref), then sdata PR (depends on sdata-core@main via its CI clone). Per CLAUDE.md: sdata-core and data-vandal require PRs; sdata allows direct push but a PR is fine. After merge, tag `v0.1.22` (sdata-core) and `v0.13.0` (sdata).

---

## Self-Review

**Spec coverage:** §2 syntax → Tasks 3–4; §2.1 options → Task 4 (parse) + Tasks 5–10 (behavior); §3 SELECT/BY/guard → Tasks 5, 9; §4.1 one-way → Task 5; §4.2 two-way grid → Task 6; §4.3 multiway list → Task 7; §4.4 /LIST → Task 7; §5 missing → Task 8; §6.1 1-way GOF → Tasks 2, 10; §6.2 2-way family → Tasks 1, 10; §6.3 3+way skip → Task 10; §6.4 /LIST+stats → Task 10 (stats independent of display); §7.1 core kernels → Tasks 1–2; §7.2 sdata command → Tasks 3–11; §8 docs (HELP/man/design/ADR) → Tasks 11–12; §9 testing → per-task + Task 13 gate; §10 decisions → all. No gaps.

**Placeholder scan:** No "TBD"/"implement later". The `Render_Request` placeholder string in Task 5 is explicitly replaced in Tasks 6–7 (noted at each). Expected `.out` token spellings are flagged "reconcile to verified values after running" — the *values* are hand-computed and stated; only exact token layout is confirmed against real output (standard practice for this repo's `diff -w` tests).

**Type consistency:** `Chi_Square_Result`/`GOF_Result`/`Count_Matrix`/`Count_Vector` declared in Task 1, used identically in Tasks 2, 6, 10. `Level`/`Level_Vectors`/`Build_Levels`/`Build_Count_Matrix`/`Level_Index`/`Count_Maps`/`Fmt2`/`Fmt4`/`Render_One_Way`/`Render_Two_Way_Grid`/`Render_List`/`Render_Request` named consistently across Tasks 5–10. `Table_Request`/`Stmt_TABLES` fields (`Requests`, `Table_CHISQ`, `Table_MISSING`, `Table_LIST`, `Table_NOCUM`, `Table_NOPERCENT`, `Table_Order_Freq`) declared in Task 3, used unchanged in Tasks 4–10. `Row_Index_Vectors` introduced in Task 5 and reused throughout.
