# Design Spec — Uniform 64-bit Numeric Types

**Date:** 2026-07-13
**Status:** Approved (brainstorming), pending implementation plan
**Issue:** [#54](https://github.com/jlries61/sdata/issues/54)
**Scope:** `sdata-core` (numeric model), with spec (`doc/design.md`) updates and
consumer rebuilds (sdata, data-vandal).

## 1. Background & Decision

design.md §2.2 specifies *platform-dependent* float precision (double on 64-bit,
single on 32-bit, quad on 128-bit). The implementation instead uses Ada's
predefined `Float` (32-bit single) and `Integer` (32-bit signed) on every
platform — self-consistent, but neither matches the spec nor gives the precision
and range a statistical tool wants.

Three resolutions were considered:

1. **Spec-as-written (platform-dependent).** Rejected — makes numeric results
   non-reproducible across architectures, the opposite of what a data tool needs.
2. **Selectable precision (compile-time or runtime, 32↔64).** Rejected — the only
   real payoff is *in-memory* footprint (the SQLite spill already stores 64-bit
   `REAL`/`INTEGER`), and it adds permanent complexity (a compute-vs-storage type
   seam, a build scenario variable or a runtime column variant) to the hottest
   data structure, for a tool with essentially one user. Not worth it.
3. **Uniform 64-bit (this spec).** Fixed IEEE 754 double floats and 64-bit signed
   integers everywhere. Simplest coherent model, portable, higher precision and
   range, and — because the widths are centralized behind two aliases —
   selectability remains a one-file change if it is ever genuinely needed.

**Decision: option 3.** The numeric footprint doubling this implies is accepted;
the disk-spill path already handles datasets too large for memory.

## 2. Goals

- Floating-point values are **IEEE 754 double precision**, fixed on every
  platform.
- Integer values are **64-bit signed** (range −2⁶³ … 2⁶³−1), fixed on every
  platform.
- Both widths are defined **once**, as named types, and used everywhere via those
  names — so a future precision change (or a revival of selectability) is a
  single-file edit, not a 344-site sweep.
- Resolve the design.md §2.2 spec/code gap and the stale §2.4 overflow bounds.

## 3. Non-Goals

- **No selectable/switchable precision.** Explicitly abandoned (see §1). The
  centralization keeps it *possible* later; we are not building it.
- **No 128-bit quad support.** There are no mainstream 128-bit targets and GNAT's
  wider float is not portable quad; the platform-dependent table is deleted, not
  reinterpreted.
- **No change to the character type** or to missing-value semantics (those are
  issues #55 and the SAVE/`DIGITS` machinery, tracked separately).

## 4. Design

### 4.1 Central numeric types (`sdata_core-values.ads`)

```ada
--  The interpreter's numeric types.  Defined once here and used everywhere;
--  changing precision is a change to these two lines.
type Real is digits 15;                       --  portable IEEE 754 double
type Int  is range -2**63 .. 2**63 - 1;       --  portable 64-bit signed
```

Rationale for the exact forms:

- `digits 15` pins at least double precision portably; on GNAT it maps to the
  64-bit IEEE double. Preferable to `subtype Real is Long_Float` because it states
  the requirement rather than the GNAT mapping (both are double in practice).
- `range -2**63 .. 2**63-1` pins a true 64-bit integer on **all** targets. Note
  `Long_Integer` is 32-bit on 32-bit targets, so it is **not** used; a range type
  guarantees the width and makes Ada raise `Constraint_Error` on overflow (which
  we map to the documented overflow error — §4.6).

Both are fully supported by GNAT on 32-bit platforms (word size refers to
pointers, not FPU/integer-arithmetic width), so this change costs no platform
reach.

### 4.2 `Value` record & evaluator

- `Value.Num_Val : Real;` (was `Float`).
- `Value.Int_Val : Int;` (was `Integer`).
- `Evaluator.Value_Info.Int_Value : Int` (the parsed integer-literal field; was
  `Integer`).
- Internal helpers keep their names but change types: `Convert_To_Float` returns
  `Real` (name retained to bound the diff; a rename to `Convert_To_Real` is
  optional and out of scope), `Num_Result`, `Is_Inf (F : Real)`,
  `Pos_Inf`/`Neg_Inf : Real`.
- Every `Float`/`Integer` used as an sdata *value* (~344 sites across 17
  sdata-core files, plus sdata) routes through `Real`/`Int`. Loop indices, string
  lengths, and other genuinely-machine quantities stay `Integer`/`Natural` — only
  *data values* migrate.

### 4.3 Elementary math functions

The five evaluator files currently `with`/`use`
`Ada.Numerics.Elementary_Functions` (the predefined `Float` instantiation). Since
`Real` is a distinct type, replace this with a single generic instantiation:

```ada
package Real_Functions is new Ada.Numerics.Generic_Elementary_Functions (Real);
```

placed once (e.g. a child or a shared spec) and `use`d where the trig/log/pow
functions are needed. `Ada.Numerics.Pi` / `Ada.Numerics.e` are universal reals and
convert to `Real` unchanged.

### 4.4 Numeric rendering (round-trip digits)

`Image_Round_Trip (X : Float)` currently emits **9** significant digits (enough to
round-trip single precision). For double it must emit **17** significant digits to
round-trip exactly. Update the function to take `Real` and use 17. `DIGITS`
(display decimal places, default 5) and `SAVE /DECIMALS` are unaffected in
mechanics, but the *default* round-trip `SAVE`/`PRINT` rendering of a
non-round-number float will now show more digits.

**Consequence:** expected-output fixtures that show default float formatting will
change and must be regenerated and verified. This is the largest test-churn
source in the change.

### 4.5 Integer literals & `MAXINT`

- The sdata lexer/parser must accept integer literals up to 2⁶³−1 (currently
  capped at the 32-bit range) and store them in `Int`.
- The `MAXINT` function currently returns 2³¹−1; it returns `Int'Last` (2⁶³−1)
  after the change. Audit any other integer-limit constants.

### 4.6 Overflow semantics

- Integer overflow: arithmetic on the `Int` range type raises `Constraint_Error`
  on out-of-range results, already mapped to the documented "operation fails with
  an error message" (§2.4). The boundary moves from ±2³¹ to ±2⁶³.
- Float overflow: unchanged in policy (fails or produces Inf per the existing
  `IEEE_DIVIDE`/Inf handling); only the type widens.

### 4.7 Int↔Real conversion & exactness

§2.3's rules are unchanged (integer→float promotes; float→integer truncates toward
zero). The exactness boundary in *mixed-mode* arithmetic improves: a 64-bit
integer above 2⁵³ cannot be represented exactly as a double, versus the old 2²⁴
boundary for 32-bit int / single float. This is strictly better and rarely hit;
it warrants one sentence in design.md §2.3, not special handling.

### 4.8 Column storage & file I/O

- In-memory numeric column vectors hold `Real` (8 bytes) and integer columns hold
  `Int` (8 bytes) — the accepted footprint doubling.
- CSV/ODF/OOXML readers parse into `Real`/`Int`; writers render via the updated
  round-trip path (§4.4). Parsing must accept the wider integer range.

### 4.9 SQLite spill (no schema change)

SQLite `REAL` is already an 8-byte IEEE double and `INTEGER` is already 8-byte, so
the spilled schema and affinities are unchanged. Widening values *toward* SQLite's
existing widths removes a narrowing that happened on spill/reload; no migration.

### 4.10 design.md updates

- **§2.2** — replace the platform-dependent float table with "IEEE 754 double
  precision, fixed on all platforms"; change Integer to "64-bit signed integer."
- **§2.4** — update integer overflow bounds to ±2⁶³; reconcile float-overflow
  wording with the existing Inf behavior (ties into #57 but the bounds must move
  here).
- **§2.3** — add the one-sentence 2⁵³ mixed-mode exactness note.
- Man page and HELP have no precision-specific text to change (verify `MAXINT`
  wording if any).

## 5. Backward Compatibility & Versioning

- **Results become more accurate**, not different-for-its-own-sake: double-width
  computation and storage. Not bit-identical to the old single-precision output.
- **Default float rendering widens** (up to 17 sig digits) for non-round values;
  users wanting narrow output already have `DIGITS` and `SAVE /DECIMALS`.
- **Integer range expands** ±2³¹ → ±2⁶³; previously-overflowing scripts now
  succeed.
- Behavior-visible → **minor** version bumps. sdata-core minor bump; both
  consumers rebuild and bump their `sdata_core` floor; consumer-tests `ref:`
  advanced per the usual release dance.

## 6. Risks

1. **Test-output churn** from wider default float rendering (§4.4). Mitigation:
   regenerate fixtures deliberately, eyeball diffs for correctness (more digits of
   the *same* value = expected; a *different* value = bug).
2. **Missed migration site** — a `Float`/`Integer` left in a value path yields a
   type error at compile time (Ada's distinct types make this loud, not silent),
   so the compiler is the safety net.
3. **Elementary-functions instantiation** must be threaded to all five evaluator
   files; a missed `use` is a compile error.
4. **Performance** — double arithmetic is the same speed as single on 64-bit
   hardware; memory bandwidth for the doubled column vectors is the only real
   cost, already accepted.

## 7. Testing

- `make check` green at the new widths (sdata) and `alr build` (sdata-core), plus
  `cd ~/Develop/data-vandal && make check` (cross-crate gate).
- New integration tests:
  - large-integer round-trip beyond 2³¹ (e.g. `LET N% = 5000000000` then
    `SAVE`/reload) — fails today, must pass.
  - double-precision retention (a value needing >7 significant digits survives a
    `SAVE`/`USE` round-trip).
  - integer overflow at the new 2⁶³ boundary reports a clean error.
- Regenerate and verify all fixtures affected by wider float rendering.

## 8. Migration Outline (details → implementation plan)

1. Add `Real`/`Int` to `sdata_core-values.ads`; migrate `Value`, helpers, and the
   round-trip renderer (9→17).
2. Add the `Generic_Elementary_Functions (Real)` instantiation; convert the five
   evaluator files.
3. Migrate the remaining sdata-core value sites; then the sdata lexer/parser
   (integer-literal range), evaluator glue, and any `Integer`-typed value fields.
4. `MAXINT` → `Int'Last`; audit overflow constants.
5. Update design.md §2.2/§2.4/§2.3.
6. Regenerate fixtures; add the new tests; run the full cross-crate gate.
7. Version bumps + release dance.

## 9. Cross-crate Coordination

Per CLAUDE.md: build sdata-core, then `make check` in sdata, then
`cd ~/Develop/data-vandal && make check` — all three green before pushing. Bump
`sdata_core` and both consumers' floors; advance `consumer-tests.yml` `ref:`.
