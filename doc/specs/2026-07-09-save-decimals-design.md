# SAVE `/DECIMALS=N` — Design Spec

**Date:** 2026-07-09
**Status:** Approved (brainstorming), pending implementation plan
**Feature slug:** `save-decimals`
**Affected crates:** `sdata` (parser/AST/interpreter/docs), `sdata-core` (execution, Runtime, CSV/ODF/OOXML writers)

## 1. Summary

Two coupled changes to how `SAVE` writes floating-point numbers:

1. **Precision bugfix (all three writers, always on).** Today every writer emits raw
   `Float'Image`, which GNAT renders at only **6 significant digits** (`Float'Digits = 6`)
   — already lossy for a 32-bit `Float` (which needs 9 significant digits to round-trip).
   All three writers change to render finite floats at **round-trip precision derived
   from the numeric type** (single `Float` → 9 significant digits), trailing zeros
   trimmed. A plain `SAVE` to any format now reproduces the stored single-precision value
   exactly. **This changes existing `.csv`/`.ods`/`.xlsx` output bytes** and requires
   regenerating expected-output fixtures.

2. **New option `/DECIMALS=N`.** Controls displayed/stored precision, applying to all
   three formats but with **deliberately different mechanics per format**:
   - **CSV** — round the stored text value to `N` decimal places, then **strip trailing
     zeros** and any bare trailing `.` (true data reduction; the file loses precision).
   - **ODS / OOXML** — keep the round-trip-precise stored numeric value and attach a
     **fixed-N-decimal display number-format** so cells *show* `N` decimals (no data
     reduction; full precision retained in `office:value` / `<v>`).

When `/DECIMALS=` is **absent**, output follows change (1): round-trip precision, not the
old 6-digit form.

## 2. Motivation

Users saving tabular results want controlled precision — to reduce CSV noise/size, or to
present spreadsheet values at a fixed number of decimals. There is no current way to do
this at save time (`OPTIONS DIGITS` only affects console/PRINT and is consulted by no
writer). Separately, the current `Float'Image` write path silently truncates every saved
float to 6 significant digits — e.g. `123456.789` is stored as `123457` even in
spreadsheets — which is a latent precision bug the display-format feature would otherwise
paper over. This spec fixes both together.

## 3. Semantics

### 3.1 Default rendering (no `/DECIMALS=`) — the precision bugfix

Every finite `Val_Numeric` cell in **all three** writers is rendered at **round-trip
precision for the current numeric type**, with trailing zeros and any bare trailing `.`
trimmed. For the current 32-bit `Float` that is **9 significant digits**.

- The digit count is **derived from the type**, not hardcoded — computed from the float
  type's model mantissa (single `Float` → 9; if the type is later widened to `Long_Float`
  per §9, the same code yields 17 automatically).
- **Notation:** human-friendly general form — fixed notation where the magnitude permits
  without precision loss, exponential otherwise; trailing zeros trimmed. *(Exact
  notation-selection rule is an implementation detail; flagged for review — see §10.)*
- Spreadsheets store this round-trip rendering in `office:value` / `<v>`; ODF's cached
  `<text:p>` uses the same rendering.

### 3.2 `/DECIMALS=N` meaning

`N` is a **count of decimal places** (digits after the point), **not** significant digits.

| Case | CSV behavior | Spreadsheet (ODS/OOXML) behavior |
|---|---|---|
| `N = 0` | Round to nearest integer: `3.14`→`3`, `3.99`→`4` | Display with 0 decimals: `3` (stored value still round-trip) |
| `N ≥ 1` (e.g. 2) | Round to N, trim trailing zeros: `3.14159`→`3.14`, `0.50`→`0.5`, `100`→`100` | Fixed N decimals shown: `0.50`, `100.00` (stored value still round-trip) |
| `N` large | Harmless; no visible effect | Harmless |
| `N` negative | **Parse/validation error** | **Parse/validation error** |

### 3.3 Trailing-zero policy (intentional asymmetry, distinct rationales)

- **CSV** trims trailing zeros (variable width): `0.5`, `100`.
- **Spreadsheets** show fixed `N` decimals (columns align): `0.50`, `100.00`.

The same data saved as `.csv` vs `.xlsx` with `/DECIMALS=2` therefore *looks* different
(`0.5` vs `0.50`). This is **intended**, driven by two different rationales:

- **CSV — information/space.** The CSV cell text *is* the data; trailing zeros carry no
  additional information while consuming space. Trimming removes pure redundancy.
- **Spreadsheet — presentation consistency.** The full-precision value is retained in the
  stored `office:value` / `<v>` regardless, so no information is at stake; the display
  format's only goal is consistent, aligned presentation, which fixed N-decimal
  formatting provides.

HELP, man page, and design.md must state this explicitly so it is never "fixed" by
mistake.

### 3.4 Cells that are never affected

In all three formats, both the precision bugfix and `/DECIMALS=` affect **only finite
`Val_Numeric` (float) cells**:

- **Integer columns** (`Val_Integer`) — unchanged rendering; no rounding, and no display
  format applied in spreadsheets.
- **String columns** (`Val_String`) — unchanged.
- **Missing** (`.`) — unchanged.
- **`Inf` / `-Inf`** — unchanged (still `Inf`/`-Inf` in CSV; existing inline-string /
  guarded form in spreadsheets).

### 3.5 Data model per format (with `/DECIMALS=N`)

- **CSV**: the rounded, trimmed text *is* the cell — precision reduced in the file.
- **ODS**: `office:value` retains the round-trip-precise value; a `<number:number-style>`
  governs display; the cached `<text:p>` is set to the fixed-N-decimal rendering so
  cache-honoring apps agree with the format.
- **OOXML**: `<v>` retains the round-trip-precise value; a `styles.xml` `numFmt` +
  `cellXfs` entry, referenced by each numeric cell's `s=` index, governs display.

## 4. Syntax

Both forms, mirroring the existing value-carrying SAVE options (`DLM`, `CHARSET`,
`SHEET`, `HEADER`):

```
SAVE "out.csv"  /DECIMALS=2                        -- whole-statement slash form
SAVE "a.csv" (DECIMALS=2), "b.xlsx" (DECIMALS=4)   -- per-target paren form
```

- All three formats honor `DECIMALS`; none ignore it.
- `N` must be a **non-negative integer literal**. A negative value or non-integer token is
  a parse error: `/DECIMALS= requires a non-negative integer`.

## 5. Architecture

Code placement follows the crate split: **parsing/AST in `sdata`**, **execution, Runtime
state, and all writers in `sdata-core`**.

### 5.1 Parse (sdata)

Mirror the `DLM`/`SHEET` value-carrying pattern end to end:

1. **AST** (`src/ast/sdata-ast.ads`): add to the shared `Spec_Options` record
   `Decimals_Specified : Boolean := False;` and `Decimals_Val : Natural := 0;`, plus
   matching flat fields on the `Stmt_SAVE` variant for the single-target legacy path.
2. **Parser** (`src/parser/sdata-parser.adb`): handle `DECIMALS=` in **both** parse sites
   — `Parse_Spec_Options` (paren form) and `Apply_Legacy_Slash_Option` (slash form).
   Validate the value token is a non-negative integer; negative/non-integer → parse error.
   Copy into the flat `Stmt` fields in the single-target back-compat block.

### 5.2 Plumb through Execute_SAVE (sdata-core) — additive, contract-safe

`Execute_SAVE` is public API depended on by **both** sdata and data-vandal. Add **one
defaulted parameter at the end** so existing callers stay source-compatible:

```ada
procedure Execute_SAVE
  (File_Name    : String;
   Fmt          : SData_Core.Config.Format_Type;
   Sheet_Name   : String  := "";
   Delimiter    : String  := ",";
   Write_Header : Boolean := True;
   Charset      : String  := "";
   Decimals     : Integer := -1);   -- NEW; -1 = unset (default round-trip rendering)
```

- `-1` sentinel = "no `/DECIMALS=` given" ⇒ writers use §3.1 round-trip rendering with no
  display format / no CSV rounding.
- `Execute_SAVE` stashes the value via a **new** `SData_Core.Config.Runtime` setter
  `Set_Save_Decimals` (+ getter), alongside `Set_Save_DLM/Header/Charset`.
- `Flush_Pending_Save` reads it and passes it into `Open_Output`.
- `Open_Output` (`file_io.adb`) also gains a defaulted `Decimals : Integer := -1`,
  forwarded to whichever writer runs (`Write_CSV`/`Write_ODF`/`Write_OOXML`).
- **Interpreter** (sdata) computes the effective value from `Stmt.Decimals_Specified` and
  passes it at every `Execute_SAVE` call site, including the multi-target flush path
  (`sdata-interpreter.adb` ~1837) and `execute_declarative.adb`.

Defaulted params ⇒ **data-vandal compiles unchanged** and the `consumer-tests.yml`-pinned
older sdata still builds against the new sdata-core.

### 5.3 Shared float rendering (sdata-core)

Two rendering needs, both new:

- **Round-trip renderer** `Image_Round_Trip (X : Float) return String` — §3.1: render at
  round-trip significant digits derived from the type, human-friendly notation, trailing
  zeros + bare `.` trimmed. Used by all three writers for finite floats whenever
  `Decimals < 0`, **and** for the round-trip-precise stored value in spreadsheets even
  when `Decimals >= 0`.
- **Fixed-decimals renderer** `Image_Fixed_Decimals (X : Float; Decimals : Natural)
  return String` — CSV `/DECIMALS=` path (§3.2): `Decimals = 0` → round to nearest integer
  (`Float'Rounding`, with an out-of-integer-range fallback); `Decimals ≥ 1` →
  `Ada.Text_IO.Float_IO.Put (Aft => Decimals, Exp => 0)` then strip trailing zeros + bare
  `.`.

Placement: a small shared helper (e.g. in `sdata_core-values` or a `file_io` helper unit)
so all three writers call the same code rather than re-inlining, replacing the three
independent `Float'Image` sites. The round-trip digit count is computed once from the
float type's model mantissa.

**CSV cell site** (`file_io-csv.adb:688-699`): finite `Val_Numeric` →
`Image_Fixed_Decimals` when `Decimals >= 0`, else `Image_Round_Trip`. `Inf`/`-Inf`,
integers, strings, missing untouched.

### 5.4 ODF writer (`file_io-odf.adb`)

- **Always:** the numeric cell's `office:value` and `<text:p>` use `Image_Round_Trip`
  (replacing `Float'Image`).
- **When `Decimals >= 0`:** additionally (a) declare the `number:` and `style:`
  namespaces on the `<office:document-content>` root; (b) inject one
  `<office:automatic-styles>` block before `<office:body>` with a `<number:number-style>`
  containing `<number:number number:decimal-places="N" number:min-decimal-places="N"/>`
  (both set = fixed, trailing zeros kept), wrapped in a
  `<style:style style:family="table-cell" style:data-style-name="…">`; (c) add
  `table:style-name="…"` to the numeric cell (`odf.adb:471`) and set its `<text:p>` to the
  fixed-N-decimal rendering (while `office:value` keeps the round-trip value). Integer
  cells stay bare.

### 5.5 OOXML writer (`file_io-ooxml.adb`)

- **Always:** the numeric cell's `<v>` uses `Image_Round_Trip` (replacing `Float'Image`).
- **When `Decimals >= 0`:** additionally (a) add a new `xl/styles.xml` part with the
  mandatory `<fonts>/<fills>/<borders>/<cellStyleXfs>` skeleton plus a `<numFmts>` custom
  entry (`formatCode="0"` for N=0, else `"0."` + N zeros) and a
  `<cellXfs><xf numFmtId=… applyNumberFormat="1"/>`; (b) add the `/xl/styles.xml` Override
  to `[Content_Types].xml`; (c) add the styles `<Relationship>` to
  `xl/_rels/workbook.xml.rels`; (d) add `s="<index>"` to each numeric `<c>`
  (`ooxml.adb:599`). Integer cells stay bare; `<v>` always keeps the round-trip value.

### 5.6 Format-code / digit derivation

From `N`, build each writer's dialect: ODF `number:decimal-places="N"`
(= `min-decimal-places="N"`); OOXML `formatCode` = `"0"` (N=0) or `"0."` + `N` zeros. The
round-trip significant-digit count (§3.1) is computed from the float type's model mantissa
so it tracks any future type widening.

## 6. Cross-crate release

Order: **sdata-core merges first** (sdata CI clones `sdata-core@main`).

- **sdata-core** — additive API only. Regenerate `docs/api/reference.html`
  (`scripts/gen-reference.sh`) because public `.ads` files change (`commands.ads`,
  `file_io.ads`, `config.ads`, and any new helper spec), or the `build.yml` api-reference
  job fails. Bump **0.1.26 → 0.1.27**.
- **sdata** — parser/AST/interpreter + docs. Bump **0.13.3 → 0.14.0** via
  `scripts/bump-version.sh`. Raise `sdata/alire.toml` floor to **`^0.1.27`**.
- **data-vandal** — code untouched (defaulted params). Bump its `alire.toml` `sdata_core`
  constraint to `^0.1.27`; run its `make check` in the two-consumer gate. **Note:**
  data-vandal's own expected-output fixtures containing saved floats will shift from the
  round-trip precision change and must be regenerated there too.
- Bump `sdata-core`'s `consumer-tests.yml` `ref:` to the new sdata tag.
- **Local gate before pushing:** `cd ~/Develop/sdata-core && alr build`, then `make check`
  in sdata and in data-vandal — all three green.

## 7. User-facing surface (all in the same change — per CLAUDE.md)

- **HELP** — `src/sdata-help.adb` SAVE topic gains `/DECIMALS=N`; regenerate
  `tests/expected/help_all.out` and any `*_options` / `options_display` snapshot listing
  SAVE options.
- **Man page** — `man/man1/sdata.1` SAVE synopsis + option description.
- **Design doc** — `doc/design.md`: document `/DECIMALS=`, the CSV-trims vs
  spreadsheet-fixed asymmetry, **and** that saved floats now use round-trip precision
  (note: still single-precision per the current data model; see §9).
- **ADR-050** in `doc/adrs.md` — records per-format `/DECIMALS` semantics, the
  round-trip-precision bugfix (default output byte change), defaulted-parameter plumbing
  (contract safety), and the display-format-vs-value-rounding split.
- **architecture.md** — note the new shared float-rendering helper + spreadsheet style
  layer.

## 8. Test plan

**Note — expected-output churn:** the §3.1 precision change alters existing saved-float
bytes across all three formats. Every integration/unit fixture that captures saved numeric
output must be regenerated and reviewed (not blindly accepted) to confirm the new values
are the correct round-trip renderings.

### 8.1 Integration (`.cmd`, sdata `tests/`)

- **Round-trip default:** `SAVE` a value like `123456.789` / `1.0/3.0` to CSV, ODS, OOXML
  with **no** `/DECIMALS=`; assert ≥9-significant-digit round-trip output (not the old
  6-digit form).
- **CSV `/DECIMALS=`:** rounds + trims (`3.14159`→`3.14`, `0.50`→`0.5`, `100`→`100`); `N=0`
  → integer; **negative N → parse error**; per-target paren form with differing N;
  whole-statement form across multiple CSV targets.
- **Spreadsheet `/DECIMALS=`:** save `.ods` and `.xlsx`; assert the **stored value stays
  round-trip precise** and the **number-format is present** (unzip + grep XML for
  `number:number-style` / `numFmt` + `s=`); integer cells carry no format; `Inf`/missing
  untouched.

### 8.2 Unit

- `Image_Round_Trip` edge cases: values needing 9 digits, exact integers (trailing-zero
  trim → `150`), very large / very small magnitudes (notation selection), `Inf`.
- `Image_Fixed_Decimals` edge cases: N=0 rounding incl. ties, trailing-zero + bare-`.`
  trim, N≥1, `Inf`, out-of-integer-range fallback.
- ODF/OOXML format-code construction (N=0 vs N≥1) in `file_io_unit_test`.

## 9. Out of scope (YAGNI / deferred)

- **Widening internal precision to platform-native (double on 64-bit).** design.md
  §"Floating Point Numeric" (lines 42–49) mandates precision by machine architecture
  (64-bit → IEEE 754 double), but the code uses plain 32-bit `Float`. This
  design-vs-code conformance gap is **deferred to the planned codebase-vs-design audit**.
  This feature targets round-trip of the *current* single-precision `Float`; because the
  §3.1 renderer derives its digit count from the type, it will emit full double precision
  automatically once that audit widens the type. Neither ODF nor OOXML constrains stored
  values to 32-bit (both are decimal text read as binary64), so the file formats already
  accommodate the eventual widening.
- Per-column precision (a single `N` per SAVE target only).
- Significant-digits mode; user-configurable scientific-notation control.
- Applying a display format to integer or string columns.
- Coupling to `OPTIONS DIGITS` (console setting stays independent).
- Rounding-mode configurability (standard-library fixed-notation rounding for CSV `N≥1`;
  `Float'Rounding` for `N=0`).

## 10. Open points for review

- **Round-trip notation selection (§3.1).** The exact rule for choosing fixed vs
  exponential form in the default renderer (and any threshold) is left to the
  implementation plan. Confirm the human-friendly-general-form intent is right, or specify
  a stricter rule (e.g. always fixed, or always match today's exponential style but with
  round-trip digits).
