# Uniform 64-bit Numeric Types — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace sdata's 32-bit `Float`/`Integer` value types with fixed IEEE 754 double (`Real`) and 64-bit signed (`Int`), centralized behind two aliases.

**Architecture:** Introduce each alias first as a *subtype* of the current predefined type (transparent — code compiles and behaves byte-identically), sweep all value sites onto the alias, verify green, then *flip the alias to a distinct type* (`type Real is digits 15;` / `type Int is range -2**63 .. 2**63-1;`). The flip is where the compiler pinpoints every site that needs a real change (math-function instantiation, rendering width, integer-literal range), isolating all behavior change to two small commits.

**Tech Stack:** Ada 2012, GNAT (Alire toolchain), SQLite spill backend, `make check` integration + unit suite.

**Spec:** `doc/specs/2026-07-13-64bit-numeric-types-design.md`. **Issue:** #54.

## Global Constraints

- **Cross-crate gate (every code change):** `cd ~/Develop/sdata-core && alr build`, then `cd ~/Develop/sdata && make check`, then `cd ~/Develop/data-vandal && make check`. All three green before any commit that touches `sdata-core/src`.
- **Never use `--no-verify`.** All 342+ sdata integration tests and 5 unit binaries must pass.
- **`Real` = `type Real is digits 15;`** (portable IEEE double). **`Int` = `type Int is range -2**63 .. 2**63 - 1;`** (portable 64-bit). Defined once in `sdata-core/src/sdata_core-values.ads`.
- **Migrate only *data-value* `Float`/`Integer`.** Loop counters, array bounds, string lengths, hash indices stay `Integer`/`Natural`/`Positive`. `Float` is almost always a value → near-blanket. `Integer` is mostly machinery → selective (see Task B1 site list).
- **Version:** behavior-visible → sdata-core **minor** bump; bump the `sdata_core` floor in both `sdata/alire.toml` and `data-vandal/alire.toml`; advance `sdata-core`'s `consumer-tests.yml` `ref:`.
- **Commit messages** end with `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.

---

## Task A1: Introduce `Real` as a subtype; sweep Float value sites

Transparent refactor. `subtype Real is Float;` means every change here is a no-op semantically; the payoff is that Task A2's flip then localizes the real work.

**Files:**
- Modify: `sdata-core/src/sdata_core-values.ads` (add subtype; retype `Num_Val`, `Is_Inf`, `Pos_Inf`/`Neg_Inf`, `Image_Round_Trip`, `Image_Fixed_Decimals`, `Convert_To_Float`)
- Modify (sweep `Float`→`Real` at value sites): `sdata-core/src/sdata_core-values.adb`, `sdata_core-evaluator.ads/.adb`, `sdata_core-evaluator-*.adb`, `sdata_core-statistics.ads/.adb`, `sdata_core-csv.ads/.adb`, `sdata_core-file_io*.adb`; and in sdata: `sdata/src/*.adb` value sites (evaluator glue, PRINT formatting).
- Build only; no test file (behavior unchanged).

**Interfaces:**
- Produces: `SData_Core.Values.Real` (currently `subtype Real is Float`); `Value.Num_Val : Real`; `Convert_To_Float (V : Value) return Real`; `Is_Inf (F : Real) return Boolean`; `Image_Round_Trip (X : Real) return String`.

- [ ] **Step 1: Add the subtype and retype the Value record**

In `sdata_core-values.ads`, above the `Value` type:

```ada
--  The interpreter's numeric value types.  Defined once; changing precision
--  is a change to these two lines (see doc/specs/2026-07-13-64bit-numeric-types).
--  Introduced first as subtypes so the site sweep is transparent; strengthened
--  to distinct types in a later step.
subtype Real is Float;
subtype Int  is Integer;
```

Change `Num_Val : Float;` → `Num_Val : Real;` and `Int_Val : Integer;` → `Int_Val : Int;` in the `Value` record. Retype the public declarations: `Is_Inf (F : Real)`, `Pos_Inf, Neg_Inf : Real`, `Image_Round_Trip (X : Real)`, `Image_Fixed_Decimals (X : Real; ...)`, and `Convert_To_Float (...) return Real`.

- [ ] **Step 2: Sweep Float value sites onto Real**

In each `sdata-core` value file, change `Float` → `Real` where it denotes a data value: variable/parameter/return types, `Float(...)` conversions of values, local temporaries in arithmetic. Leave alone: `Ada.Text_IO.Float_IO (Float)` instantiations, `Float'Image`/`Float'Value`/`Float'Rounding` attribute uses, and `Ada.Numerics.Elementary_Functions` — these keep working because `Real` is still a subtype of `Float`, and Task A2 converts them deliberately. Repeat for the 8 sdata value sites.

- [ ] **Step 3: Build sdata-core**

Run: `cd ~/Develop/sdata-core && alr build`
Expected: `Build finished successfully` (subtype is transparent; any error is a genuinely mistyped site — fix it).

- [ ] **Step 4: Cross-crate gate (must be byte-identical)**

Run: `cd ~/Develop/sdata && make check` → `All <N> tests passed.`
Run: `cd ~/Develop/data-vandal && make check` → all pass.
Expected: **zero** fixture diffs (behavior is unchanged). If any `.out` changed, a site was mis-migrated — revert that site.

- [ ] **Step 5: Commit**

```bash
cd ~/Develop/sdata-core && git checkout -b feat/64bit-numeric-types
git add -A && git commit -m "refactor: route Float/Integer value sites through Real/Int subtypes (#54)

Transparent staging step: Real/Int are subtypes of Float/Integer, so
behavior is byte-identical. Sets up the type-strengthening flip.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task A2: Flip `Real` to double precision

Now `Real` becomes a distinct type; the compiler lists every site that assumed `Real = Float`.

**Files:**
- Modify: `sdata_core-values.ads` (`subtype Real is Float;` → `type Real is digits 15;`)
- Create: `sdata-core/src/sdata_core-real_functions.ads` (shared elementary-functions instantiation)
- Modify: `sdata_core-evaluator.adb`, `sdata_core-evaluator-aggregate_fns.adb`, `sdata_core-evaluator-distrib_fns.adb`, `sdata_core-evaluator-misc_fns.adb`, `sdata_core-evaluator-numeric_fns.adb` (swap `Ada.Numerics.Elementary_Functions` → the new instantiation)
- Modify: `sdata_core-values.adb` (`Image_Round_Trip`, `Image_Fixed_Decimals`: `Float_IO (Real)`, `Real'Rounding`/`Real'Value`, integer fast-path bound, exponential-fallback precision)
- Test: regenerate affected `sdata/tests/expected/*.out`; add `sdata/tests/double_precision_roundtrip.cmd`

**Interfaces:**
- Consumes: `Real`, `Int` from Task A1.
- Produces: `type Real is digits 15;`; `package SData_Core.Real_Functions is new Ada.Numerics.Generic_Elementary_Functions (Real);`.

- [ ] **Step 1: Write the failing test (double precision retained across SAVE/USE)**

Create `sdata/tests/double_precision_roundtrip.cmd`:

```
-- Issue #54: a value needing more than single-precision (~7 sig digits) must
-- survive a SAVE/USE round-trip once numeric values are IEEE double.
NEW
REPEAT 1
LET X = 1.2345678901234
SAVE "tests/dpr_out.csv"
RUN
USE "tests/dpr_out.csv"
PRINT X
RUN
QUIT
```

Create `sdata/tests/expected/double_precision_roundtrip.out` with the double-precision value (regenerate exactly in Step 6 after the flip; the point is that today it would round to ~1.23457 and fail).

- [ ] **Step 2: Run it to confirm it fails on current (pre-flip) binary**

Run: `cd ~/Develop/sdata && ./bin/sdata tests/double_precision_roundtrip.cmd`
Expected: prints a single-precision-truncated value (≈ `1.23457`), i.e. loses the extra digits — the pre-flip failure. (Leave the expected file matching the *double* value so the test is red now, green after the flip.)

- [ ] **Step 3: Flip the type**

In `sdata_core-values.ads`: `subtype Real is Float;` → `type Real is digits 15;` (leave `subtype Int is Integer;` for Phase B).

- [ ] **Step 4: Add the elementary-functions instantiation**

Create `sdata-core/src/sdata_core-real_functions.ads`:

```ada
--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later, with GCC Runtime Library Exception 3.1
with Ada.Numerics.Generic_Elementary_Functions;
with SData_Core.Values;

package SData_Core.Real_Functions is
   new Ada.Numerics.Generic_Elementary_Functions (SData_Core.Values.Real);
```

In each of the five evaluator `.adb` files, replace
`with Ada.Numerics.Elementary_Functions; use Ada.Numerics.Elementary_Functions;`
with
`with SData_Core.Real_Functions; use SData_Core.Real_Functions;`.

- [ ] **Step 5: Fix the renderer cascade (compiler-guided)**

`cd ~/Develop/sdata-core && alr build` and fix each error. Expected sites in `sdata_core-values.adb`:
- `package Float_IO is new Ada.Text_IO.Float_IO (Float);` → `(Real)`.
- `Float'Rounding (X)` → `Real'Rounding (X)`; `Float'Value (S)` → `Real'Value (S)`.
- Integer fast-path: `abs R < Float (Integer'Last)` and `Integer (R)` → use `Int` bounds: `abs R < Real (Int'Last)` and `Int (R)` with `Int'Image`. (In this phase `Int` is still `Integer`; this keeps the fast path correct and forward-ready.)
- Exponential fallback: `Float_IO.Put (Buf, X, Aft => 8, Exp => 2)` renders 9 sig digits (single). Change to `Aft => 16` (17 sig digits, double round-trip). Update the "9 significant digits" comment to 17.
- Final `others` safety net: `Float'Image (X)` → `Real'Image (X)`.
- Note: the `for Aft in 1 .. 17 loop` already covers double fixed-notation; no bound change needed there.

Repeat error-fixing until `alr build` is clean.

- [ ] **Step 6: Regenerate affected fixtures and verify each diff**

Run `cd ~/Develop/sdata && make check`. For each failing fixture, regenerate:
`./bin/sdata tests/<name>.cmd > tests/expected/<name>.out 2>&1`
**Verify every diff by eye:** more digits of the *same* number (e.g. `0.1` now `0.10000000000000001`, or an intermediate stat carrying extra places) is expected; a *different* number is a bug — stop and investigate. Regenerate `tests/expected/double_precision_roundtrip.out` here; it must now show the full value.

- [ ] **Step 7: Full cross-crate gate**

Run the three-crate gate (Global Constraints). All green.

- [ ] **Step 8: Commit**

```bash
cd ~/Develop/sdata-core && git add -A && git commit -m "feat: numeric values are IEEE 754 double precision (#54)

Real is now 'digits 15' (portable double); elementary functions move to a
Generic_Elementary_Functions(Real) instantiation; round-trip rendering uses
17 significant digits. Float column values widen single->double.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd ~/Develop/sdata && git add -A && git commit -m "test: double-precision round-trip; regenerate float-format fixtures (#54)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task B1: Sweep Integer value sites onto `Int` (still a subtype)

Selective — only *data-value* integers. Transparent (`Int = Integer`).

**Files & value-integer sites (migrate these; leave all other `Integer`/`Natural`):**
- `sdata_core-values.ads`: `Int_Val` (done in A1) — confirm.
- `sdata_core-evaluator.ads`: `Value_Info.Int_Value : Integer` → `Int`.
- `sdata-ast.ads` (sdata): `Expr_Numeric_Literal` node's `Int_Value : Integer` → `SData_Core.Values.Int`.
- `sdata-parser.adb`: `Node.Int_Value := Integer'Value (S)` — leave `Integer'Value` here for now (subtype), retype the field usage.
- Evaluator integer arithmetic producing `Val_Integer` results, `Convert_To_Float`’s `Float (V.Int_Val)`, and integer column read/write in `file_io`/`csv`.
- `MAXINT` implementation (returns the integer max).
- **Do not migrate:** array subscripts/bounds (`Natural'Value` in parser at lines ~909/938/1094), loop indices, `Row_Count`/`Column_Count`, hash keys, `T.Length`.

**Interfaces:**
- Produces: `Value.Int_Val : Int`; AST `Int_Value : Int`; `MAXINT` returns `Int`.

- [ ] **Step 1: Retype the value-integer sites**

Apply the field/parameter retypes above (`Integer` → `Int` at the listed value sites only).

- [ ] **Step 2: Build sdata-core**

Run: `cd ~/Develop/sdata-core && alr build` → success (subtype transparent).

- [ ] **Step 3: Cross-crate gate — byte-identical**

Run `make check` (sdata) and (data-vandal). Zero fixture diffs expected. A diff means a non-value `Integer` was migrated (e.g. an index) — revert it.

- [ ] **Step 4: Commit**

```bash
cd ~/Develop/sdata-core && git add -A && git commit -m "refactor: route integer VALUE sites through the Int subtype (#54)

Transparent staging: Int is still a subtype of Integer. Value-carrying
integers only (Int_Val, integer literals, MAXINT, integer column I/O);
indices/counts/bounds stay Integer.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
# plus the parallel sdata AST commit
```

---

## Task B2: Flip `Int` to 64-bit

**Files:**
- Modify: `sdata_core-values.ads` (`subtype Int is Integer;` → `type Int is range -2**63 .. 2**63 - 1;`)
- Modify: `sdata-parser.adb` (integer-literal parse `Integer'Value` → `Int'Value`; the sdata lexer already tokenises the digits — only the value conversion changes)
- Modify: evaluator/values integer conversions, `MAXINT` (`Int'Last`), overflow paths
- Test: `sdata/tests/large_integer_roundtrip.cmd`, `sdata/tests/integer_overflow_64bit.cmd`

**Interfaces:**
- Consumes: `Int` from B1.
- Produces: `type Int is range -2**63 .. 2**63 - 1;`; `MAXINT` → `Int'Last`.

- [ ] **Step 1: Write the failing tests**

`sdata/tests/large_integer_roundtrip.cmd`:

```
-- Issue #54: integers beyond the old 32-bit range must round-trip.
NEW
REPEAT 1
LET N% = 5000000000
PRINT N%
SAVE "tests/lir_out.csv"
RUN
USE "tests/lir_out.csv"
PRINT N%
RUN
QUIT
```

Expected (`tests/expected/large_integer_roundtrip.out`): `5000000000` printed twice, plus the RUN-complete lines.

`sdata/tests/integer_overflow_64bit.cmd` with `tests/integer_overflow_64bit.exitcode` = `1`:

```
-- Overflow at the new 64-bit boundary must fail cleanly, not wrap.
NEW
REPEAT 1
LET N% = 9223372036854775807
LET N% = N% + 1
PRINT N%
RUN
QUIT
```

Expected `.out`: an integer-overflow error line (capture exact text in Step 5).

- [ ] **Step 2: Run large-int test on pre-flip binary → fails**

Run: `./bin/sdata tests/large_integer_roundtrip.cmd`
Expected: an overflow/parse error or wrapped value — the literal `5000000000` exceeds 32-bit. Confirms red.

- [ ] **Step 3: Flip the type**

`subtype Int is Integer;` → `type Int is range -2**63 .. 2**63 - 1;`.

- [ ] **Step 4: Fix the cascade (compiler-guided)**

`cd ~/Develop/sdata-core && alr build`; fix each error:
- Integer-literal parse in `sdata-parser.adb`: `Node.Int_Value := Integer'Value (S);` → `Int'Value (S);`.
- `MAXINT` returns `Int'Last`.
- Value conversions: `Float (V.Int_Val)` → `Real (V.Int_Val)`; `Int (Real'Truncation (...))` for real→int per §2.3.
- `Int'Image` wherever integer values are rendered (strip the leading space as existing code does).
- File I/O integer parse/format uses `Int'Value`/`Int'Image`.
- **Overflow mapping:** confirm arithmetic on `Int` raising `Constraint_Error` is caught and surfaced as the documented overflow error (the existing top-level handler in `sdata-interpreter.adb` / evaluator). If a raw `Constraint_Error` escapes, wrap it where integer arithmetic is evaluated with message `"Integer overflow"`.

- [ ] **Step 5: Build, then capture the overflow message and finalize expected outputs**

Run the three-crate build/gate. Run each new test; paste actual overflow text into `tests/expected/integer_overflow_64bit.out`; confirm `large_integer_roundtrip` prints `5000000000` twice.

- [ ] **Step 6: Regenerate any integer-format fixtures**

`Int'Image` output should match `Integer'Image` for in-range values, so diffs should be nil; if any appear, verify they are correct and regenerate.

- [ ] **Step 7: Full cross-crate gate → all green. Commit**

```bash
cd ~/Develop/sdata-core && git add -A && git commit -m "feat: integer values are 64-bit signed (#54)

Int is now 'range -2**63 .. 2**63-1' (portable 64-bit). Integer literals,
MAXINT, and integer column I/O widen; overflow boundary moves to +/-2**63.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
cd ~/Develop/sdata && git add -A && git commit -m "test: large-integer round-trip and 64-bit overflow (#54)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task C1: design.md spec updates

**Files:** Modify `sdata/doc/design.md` (§2.2, §2.3, §2.4). Doc-only — no `make check` required.

- [ ] **Step 1: Rewrite §2.2 numeric types**

Replace the platform-dependent float table with:

```
#### Floating Point Numeric

IEEE 754 double precision (64-bit) on all platforms.

#### Integer

64-bit signed integer (range -9,223,372,036,854,775,808 to 9,223,372,036,854,775,807).
```

- [ ] **Step 2: Update §2.4 overflow bounds**

Change the integer-overflow range to ±2⁶³ (the values above). Leave the float-overflow/Inf wording (reconciled under #57).

- [ ] **Step 3: Add the §2.3 exactness note**

Append to §2.3: "An integer converted to floating point in mixed-mode arithmetic is exact up to 2⁵³; integers of larger magnitude may lose low-order digits when combined with floating-point values."

- [ ] **Step 4: Commit (docs-only)**

```bash
cd ~/Develop/sdata && git add doc/design.md
git commit -m "docs: spec 64-bit numeric types in design.md 2.2/2.3/2.4 (#54)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task D1: Release (version bumps + cross-crate)

**Files:** `sdata-core/alire.toml`, `sdata-core/.github/workflows/consumer-tests.yml`, `sdata/alire.toml`, `data-vandal/alire.toml`, plus sdata's 9 bump-script files.

- [ ] **Step 1: Bump sdata-core (minor)** in `sdata-core/alire.toml`; regenerate `docs/api/reference.html` if any public `.ads` changed (it did — `values.ads`, new `real_functions.ads`): run `sdata-core/scripts/gen-reference.sh` and commit. (See [[sdata-core-api-reference-ci]].)

- [ ] **Step 2: Bump both consumer floors** — set `sdata_core = "^<new>"` in `sdata/alire.toml` and `data-vandal/alire.toml` (the 64-bit API/behavior requires the new sdata-core).

- [ ] **Step 3: Bump sdata** via `scripts/bump-version.sh <new> "64-bit numeric types (#54)"` (minor); answer the prompts N and build/check manually.

- [ ] **Step 4: Advance `consumer-tests.yml` `ref:`** in sdata-core to the new sdata tag once tagged.

- [ ] **Step 5: Full cross-crate gate; tag and push** per the standard release dance (sdata-core first — sdata CI clones sdata-core@main).

---

## Task D2: Dedicated rename commit

Mechanical, compiler-checked. Do this last, on green.

**Files:** all `Convert_To_Float` sites (194 sdata-core, 8 sdata) and `As_Float` (3). `Try_Fast_Float` keeps its name.

- [ ] **Step 1: Rename** `Convert_To_Float` → `Convert_To_Real`, `As_Float` → `As_Real` across `sdata-core/src` and `sdata/src` (search-replace; the declarations too).

- [ ] **Step 2: Build + full cross-crate gate.** Any missed site is a compile error. All green.

- [ ] **Step 3: Commit**

```bash
git commit -am "refactor: rename Convert_To_Float->Convert_To_Real, As_Float->As_Real (#54)

Mechanical rename now that these return/consume Real, not Float.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review Notes (coverage vs spec)

- Spec §4.1 types → Task A1 (subtypes) + A2/B2 (flips). §4.2 Value/evaluator → A1/B1. §4.3 math functions → A2. §4.4 rendering 9→17 → A2 Step 5. §4.5 literals + MAXINT → B1/B2. §4.6 overflow → B2 Step 4. §4.7 exactness note → C1 Step 3. §4.8 storage/file I/O → A1/B1/A2/B2. §4.9 SQLite (no change) → not applicable. §4.10 design.md → C1. §5 versioning → D1. §8 step 7 rename → D2. All spec sections covered.
- Behavior change is confined to A2 (double) and B2 (64-bit); A1/B1 gates assert byte-identical output, so any accidental behavior change is caught before the flips.
