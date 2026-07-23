# Design: Character Missing Value and Empty String (issue #55)

**Date:** 2026-07-17
**Issue:** [#55](https://github.com/jlries61/sdata/issues/55) — "character missing value and empty string are conflated (`""` is both)"
**Status:** Approved (design), pending implementation plan
**Scope:** sdata-core (evaluator, table storage, value construction) + sdata (assignment coercion, docs) + data-vandal (inherited via sdata-core; verified by the two-consumer gate)

## 1. Problem

The character missing value and a legitimately-empty string are both `""`, and the
system behaves inconsistently about which one `""` is:

```
REPEAT 1
LET S$ = ""
PRINT MISSING(S$)     -- 1   (treated as MISSING)
PRINT LEN(S$)         -- 0   (treated as a real empty string)
PRINT S$ + "x"        -- x   (concatenated as a literal empty string)
RUN
```

`design.md` §2.5 is internally contradictory: it defines the character missing value
**as** the empty string (line 79) while also stating "Null strings (`""`) in string
operations shall be taken literally" (line 84). Those two rules cannot both hold.

## 2. Decision

**Adopt the SPM/SAS model: an empty (zero-length) character value *is* the character
missing value.** There is no separate "empty string" concept for character data. This
is the heritage-faithful choice — SAS and SPM treat a blank/empty character value as
missing, and provide no distinct character-missing sentinel (only numeric missing has
special codes).

Rejected alternative (distinct sentinel, the SQL/R `NULL`/`NA` vs `''` model): it would
let a genuine empty string coexist with missing, but it diverges from the language's
heritage, cannot round-trip through CSV without a non-standard convention, and — most
importantly — is not what SPM/SAS do. See issue #55 for the fuller comparison.

## 3. Model — one representation

**Invariant: a `Val_String` of length 0 never exists in the running system.** The single
representation of "no character value" is `Val_Missing`. The ambiguity is removed by
construction, not by patching each function that inspects a string.

This reframes which functions are "wrong." Under this model:

- `MISSING("")`, `N`, and `NMISS` are **already correct** — an empty character value is
  missing, so counting it as missing is right. Their existing `Length = 0` checks
  (`misc_fns.adb:26`, `aggregate_fns.adb:106,119`) stay as cheap defense-in-depth.
- `LEN("")` and `"" + "x"` are the actual offenders: they treat empty *literally* when
  it should propagate as missing. Establishing the invariant fixes both automatically —
  `LEN` and concatenation receive `Val_Missing` (not an empty `Val_String`) and already
  propagate missing.

## 4. Mechanism — normalization chokepoints

An empty string is normalized to `Val_Missing` at every point it could enter the system:

1. **Expression evaluation** — `SData_Core.Evaluator`, at the tail of `Evaluate`: any
   `Val_String` result whose payload has length 0 is returned as `Val_Missing` instead.
   Because every sub-expression is itself evaluated (and therefore normalized), this one
   change makes the `""` literal → missing, `TRIM("   ")` → missing, and any empty
   operand poison its enclosing expression — uniformly and in a single place. This covers
   all expression-level behavior: literals, string-function results, concatenation,
   `LEN`, `MISSING`.

2. **Storage** — `SData_Core.Table.Set_Value` (and the transient-table setter), plus
   sdata's `Coerce_For_Scalar` (`sdata-interpreter-execute_assignment.adb`): an empty
   `Val_String` written to a cell/PDV is stored as `Val_Missing`. This keeps every path
   that reads *stored* values without going through `Evaluate` consistent — `N`/`NMISS`
   over a column, BY-group distinctness, value comparison (`"="`/`"<"`), and SAVE output.
   Placing the storage normalization in sdata-core `Set_Value` means **data-vandal
   inherits it for free**.

3. **CSV/spreadsheet read** — already correct: `file_io-csv.adb:222` maps a blank field
   (and a `"."` field) to `Val_Missing`. No change required.

Two chokepoints (evaluate + store) plus the already-correct read path together guarantee
the invariant across expression, storage, and I/O paths.

## 5. Behavioral changes (user-visible)

| Expression | Before | After |
|---|---|---|
| `LEN("")` | `0` | missing |
| `first$ + " " + last$` (a part empty) | partial string (`"John "`) | missing |
| `MISSING("")` | `1` | `1` (unchanged) |
| `N` / `NMISS` over blank char cells | counts blank as missing | unchanged |
| BY-group on a char column with blanks | blanks were a distinct `""` group in some paths | blanks are the single missing group |

The propagation in row 2 is the deliberate consequence of the model: an empty part makes
the whole expression missing, exactly as a numeric missing already poisons arithmetic.

## 6. I/O round-trip

Faithful under this model with **no writer change**: a missing character cell renders as
`"."` via `To_String` (`values.adb:74`) and reads back as `Val_Missing`. Because no empty
strings exist, none can be lost. Rendering character-missing as a blank CSV field instead
of `"."` (the strict SAS convention) is a separate cosmetic/interop decision that would
churn existing fixtures; it is **out of scope** for #55 and left as a possible future
tweak.

## 7. Correctness hazard — string-function argument sweep (main implementation risk)

Once `""` becomes `Val_Missing`, a string-function argument that was previously a
non-missing empty `Val_String` now arrives as `Val_Missing`. Any function that reads
`.Str_Val` on such an argument without first checking `Kind` will raise `Constraint_Error`
(a `Val_Missing` record has no `Str_Val` component). The empty-needle special cases in
`INDEX`/`SUBSTR`-family functions (`string_fns.adb:222,250`, `misc_fns.adb:232`) are the
obvious spots, but the whole family must be audited.

**Requirement:** every string built-in must propagate missing (return `Val_Missing`) for
any missing argument *before* touching its string payload. Many already do this (e.g.
`ASCII` at `string_fns.adb:178`, `ORD` at `nav_fns.adb:38` guard `Kind /= Val_String`);
the plan will verify each one and add guards where absent. The empty-needle branches
become unreachable (a needle can no longer be a non-missing empty string) and may be left
in place as dead-but-harmless defense, or simplified — implementer's discretion, noted per
site.

## 8. Documentation

- **`design.md` §2.5** (line 84): remove "Null strings (`""`) in string operations shall
  be taken literally." Reword the representation/propagation so it states that an empty
  (zero-length) character value **is** the character missing value and propagates as
  missing through all string operations, consistent with line 83 ("Operations on missing
  values shall result in missing values"). (Leave the pre-existing `shalfunctionl` typo on
  line 86 to issue #57; out of scope here.)
- **`design.md` §3.6** (line 330, character literals): keep "Missing character value:
  empty string (`""`)" but ensure it reads as *the* character missing value, not "an empty
  string distinct from missing."
- **`design.md` §8.5 / §2.5**: add a one-line note that character data has a single
  missing value (the empty string); the future special-missing codes (`.i`/`.n`, §8.5
  line 2043) are a numeric-only extension.
- **HELP** (`src/sdata-help.adb`): audit the `LEN` and `MISSING` topic text for any
  empty-string wording; update if it claims `LEN("")` is 0. Regenerate
  `tests/expected/help_all.out` only if the HELP text changes.
- **Man page** (`man/man1/sdata.1`): audit the FUNCTIONS section (`LEN`, `MISSING`) for the
  same wording.

## 9. Tests

- **Regression tests** (new `.cmd` integration tests): `LEN("")` → missing; empty-part
  concatenation → missing; `MISSING(TRIM("   "))` → 1; a blank field save→load round-trip
  stays missing; BY-group over a char column with blanks yields a single missing group.
- **Fixture churn**: any existing test that exercises `LEN` on an empty string or empty
  concatenation will change output; regenerate the affected expected files. `make check`
  will surface them.
- **Cross-crate gate**: `cd ~/Develop/sdata-core && alr build`, then `make check` in sdata,
  then `make check` in data-vandal — all green before commit (per CLAUDE.md).

## 10. Out of scope

- Rendering character-missing as a blank CSV field instead of `"."` (§6).
- The #57 pandoc typos and other design-doc cleanups.
- Numeric special-missing codes (`.i`/`.n`, §8.5) — unrelated future work.
- `Is_True`/boolean truthiness of a blank value: with the invariant, `IF(S$)` on a blank
  evaluates `IF(missing)`; the plan will confirm the existing missing-in-boolean behavior
  is unchanged, but no new boolean semantics are introduced here.

## 11. Affected files (anticipated)

**sdata-core:**
- `src/sdata_core-evaluator.adb` — `Evaluate` tail normalization
- `src/sdata_core-table.adb` — `Set_Value` storage normalization
- `src/sdata_core-evaluator-string_fns.adb`, `-misc_fns.adb`, `-nav_fns.adb`,
  `-aggregate_fns.adb` — missing-argument guard sweep (§7)

**sdata:**
- `src/sdata-interpreter-execute_assignment.adb` — `Coerce_For_Scalar` normalization
- `doc/design.md` — §2.5/§3.6/§8.5
- `src/sdata-help.adb`, `man/man1/sdata.1` — if wording changes
- `tests/*.cmd`, `tests/expected/*` — new regression tests + fixture regen

**data-vandal:** none expected (inherits sdata-core normalization); confirmed by
`make check`.
