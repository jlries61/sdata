# SAVE `/DECIMALS=N` — Design Spec

**Date:** 2026-07-09
**Status:** Approved (brainstorming), pending implementation plan
**Feature slug:** `save-decimals`
**Affected crates:** `sdata` (parser/AST/interpreter/docs), `sdata-core` (execution, Runtime, CSV/ODF/OOXML writers)

## 1. Summary

Add a new option, `/DECIMALS=N`, to the `SAVE` command controlling the precision of
floating-point values in output. The option applies to **all three** output formats
(CSV, ODS, OOXML) but with **deliberately different mechanics per format**:

- **CSV** — round the stored text value to `N` decimal places, then **strip trailing
  zeros** and any bare trailing `.` (true data reduction; the file loses precision).
- **ODS / OOXML** — keep the **full-precision** stored numeric value and attach a
  **display number-format** so cells *show* `N` decimals (no data reduction).

The option is absent by default; when absent, output is **byte-for-byte identical to
today** in all three formats.

## 2. Motivation

CSV/ODS/OOXML numeric output currently emits raw `Float'Image` (GNAT default: one
significant digit before the point, `E` exponent form, ~9 significant digits, e.g.
`1.50000000E+02`). Users saving tabular results frequently want controlled precision —
either to reduce CSV file size / noise, or to present spreadsheet values at a fixed
number of decimals. There is no current way to do this at save time; `OPTIONS DIGITS`
only affects console/PRINT rendering and is not consulted by any writer.

## 3. Semantics

### 3.1 Meaning of `N`

`N` is a **count of decimal places** (digits after the decimal point), **not**
significant digits.

| Case | CSV behavior | Spreadsheet (ODS/OOXML) behavior |
|---|---|---|
| `N = 0` | Round to nearest integer: `3.14`→`3`, `3.99`→`4` | Display with 0 decimals: `3` |
| `N ≥ 1` (e.g. 2) | Round to N, trim trailing zeros: `3.14159`→`3.14`, `0.50`→`0.5`, `100`→`100` | Fixed N decimals: `0.50`, `100.00` |
| `N` large (beyond float precision) | Harmless; no visible effect | Harmless |
| `N` negative | **Parse/validation error** | **Parse/validation error** |

### 3.2 Trailing-zero policy (intentional asymmetry)

- **CSV** trims trailing zeros (variable width): `0.5`, `100`.
- **Spreadsheets** show fixed `N` decimals (columns align): `0.50`, `100.00`.

This means the same data saved as `.csv` vs `.xlsx` with `/DECIMALS=2` will *look*
different (`0.5` vs `0.50`). This asymmetry is **intended**, not a defect, and the two
cases are driven by **different rationales**:

- **CSV — information/space.** The CSV cell text *is* the data, and trailing zeros carry
  no additional information while consuming unnecessary space. Trimming them removes
  pure redundancy from the file.
- **Spreadsheet — presentation consistency.** The full-precision value is retained in
  the stored `office:value` / `<v>` regardless, so no information is at stake. The only
  goal of the display format is **consistent, aligned presentation**, which fixed
  N-decimal formatting provides.

The spec, HELP, man page, and design.md must state this explicitly so it is never
"fixed" by mistake.

### 3.3 Cells that are never affected

In all three formats, `/DECIMALS=` affects **only finite `Val_Numeric` (float) cells**:

- **Integer columns** (`Val_Integer`) — unchanged; no rounding, and no display format
  applied in spreadsheets.
- **String columns** (`Val_String`) — unchanged.
- **Missing** (`.`) — unchanged.
- **`Inf` / `-Inf`** — unchanged (still emitted as `Inf`/`-Inf` in CSV and as the
  existing inline-string / guarded form in spreadsheets).

### 3.4 Data model

- **CSV**: the rounded, trimmed text *is* the cell — precision is lost in the file.
- **ODS**: `office:value` retains full precision (`Float'Image`); a
  `<number:number-style>` governs display; the cached `<text:p>` display text is set to
  the fixed-N-decimal rendering so cache-honoring apps agree with the format.
- **OOXML**: `<v>` retains full precision; a `styles.xml` `numFmt` + `cellXfs` entry,
  referenced by each numeric cell's `s=` index, governs display.

## 4. Syntax

Both forms are supported, mirroring the existing value-carrying SAVE options
(`DLM`, `CHARSET`, `SHEET`, `HEADER`):

```
SAVE "out.csv"  /DECIMALS=2                        -- whole-statement slash form
SAVE "a.csv" (DECIMALS=2), "b.xlsx" (DECIMALS=4)   -- per-target paren form
```

- A non-CSV/non-spreadsheet interaction does not arise (only three formats exist).
- A format that does not apply a given target's `DECIMALS` does not exist — all three
  honor it. (Earlier framing that spreadsheets would *ignore* it is superseded by §3.)
- `N` must be a **non-negative integer literal**. A negative value or a non-integer
  token is a parse error: `/DECIMALS= requires a non-negative integer`.

## 5. Architecture

Code placement follows the crate split: **parsing/AST in `sdata`**, **execution,
Runtime state, and all writers in `sdata-core`**.

### 5.1 Parse (sdata)

Mirror the `DLM`/`SHEET` value-carrying pattern end to end:

1. **AST** (`src/ast/sdata-ast.ads`): add to the shared `Spec_Options` record
   `Decimals_Specified : Boolean := False;` and `Decimals_Val : Natural := 0;`, and
   matching flat fields on the `Stmt_SAVE` variant for the single-target legacy path.
2. **Parser** (`src/parser/sdata-parser.adb`): handle `DECIMALS=` in **both** parse
   sites — `Parse_Spec_Options` (paren form) and `Apply_Legacy_Slash_Option` (slash
   form). Validate the value token is a non-negative integer; negative/non-integer →
   parse error. Copy into the flat `Stmt` fields in the single-target back-compat block
   (alongside the existing `DLM_Path`/`Sheet_Name` copies).

### 5.2 Plumb through Execute_SAVE (sdata-core) — additive, contract-safe

`Execute_SAVE` is public API depended on by **both** sdata and data-vandal. Add **one
defaulted parameter at the end** so existing callers are source-compatible:

```ada
procedure Execute_SAVE
  (File_Name    : String;
   Fmt          : SData_Core.Config.Format_Type;
   Sheet_Name   : String  := "";
   Delimiter    : String  := ",";
   Write_Header : Boolean := True;
   Charset      : String  := "";
   Decimals     : Integer := -1);   -- NEW; -1 = unset / current behavior
```

- `-1` sentinel = "no `/DECIMALS=` given" ⇒ every writer takes its existing path.
- `Execute_SAVE` stashes the value via a **new** `SData_Core.Config.Runtime` setter
  `Set_Save_Decimals` (+ getter), alongside `Set_Save_DLM/Header/Charset`.
- `Flush_Pending_Save` reads it and passes it into `Open_Output`.
- `Open_Output` (`file_io.adb`) also gains a defaulted `Decimals : Integer := -1` and
  forwards it to whichever writer runs (`Write_CSV`/`Write_ODF`/`Write_OOXML`).
- **Interpreter** (sdata) computes the effective value from `Stmt.Decimals_Specified`
  and passes it at every `Execute_SAVE` call site, including the multi-target flush path
  (`sdata-interpreter.adb` ~1837) and `execute_declarative.adb`.

Because the added parameters are defaulted, **data-vandal compiles unchanged** and the
`consumer-tests.yml`-pinned older sdata still builds against the new sdata-core.

### 5.3 CSV formatter (sdata-core `file_io-csv.adb`)

Private helper:

```ada
function Format_CSV_Decimals (X : Float; Decimals : Natural) return String;
```

- `Decimals = 0` → round to nearest integer via `Float'Rounding (X)` and image it, with
  a guard/fallback for magnitudes outside the integer range (fall back to a
  no-fractional-part fixed rendering rather than raising).
- `Decimals ≥ 1` → `Ada.Text_IO.Float_IO.Put (Buf, X, Aft => Decimals, Exp => 0)` for
  fixed-notation rounding, then **strip trailing zeros and a bare trailing `.`**.

At the cell-write site (`csv.adb:688-699`): if `Decimals >= 0` **and** the cell is a
finite `Val_Numeric`, use the helper; otherwise the existing `Float'Image` path.
`Inf`/`-Inf`, integers, strings, and missing are untouched.

### 5.4 ODF display format (sdata-core `file_io-odf.adb`)

Guarded on `Decimals >= 0` (absent ⇒ today's exact bytes). All inline in `content.xml`:

1. Declare the `number:` and `style:` namespaces on the `<office:document-content>`
   root (currently only `office`/`table`/`text`).
2. Inject one `<office:automatic-styles>` block before `<office:body>`, containing a
   `<number:number-style>` with
   `<number:number number:decimal-places="N" number:min-decimal-places="N"/>` (both set
   = fixed, trailing zeros kept), wrapped in
   `<style:style style:family="table-cell" style:data-style-name="…">`.
3. Add `table:style-name="…"` to the **numeric** cell emit (`odf.adb:471`); integer
   cells (`odf.adb:478`) stay bare.
4. Set the numeric cell's `<text:p>` cached display text to the fixed-N-decimal
   rendering while `office:value` retains full precision.

### 5.5 OOXML display format (sdata-core `file_io-ooxml.adb`)

Guarded on `Decimals >= 0` (absent ⇒ today's exact bytes):

1. Add a new `xl/styles.xml` part with the mandatory
   `<fonts>/<fills>/<borders>/<cellStyleXfs>` skeleton Excel requires, **plus** a
   `<numFmts>` custom entry (`formatCode="0"` for N=0, else `"0."` + N zeros) and a
   `<cellXfs><xf numFmtId=… applyNumberFormat="1"/>`.
2. Add the `/xl/styles.xml` Override to `[Content_Types].xml`.
3. Add the styles `<Relationship>` to `xl/_rels/workbook.xml.rels`.
4. Add `s="<index>"` to each **numeric** `<c>` (`ooxml.adb:599`); integer cells
   (`ooxml.adb:605`) stay bare; `<v>` keeps full precision.

### 5.6 Format-code construction

From `N`, build each writer's dialect: ODF `number:decimal-places="N"`
(= `min-decimal-places="N"`); OOXML `formatCode` = `"0"` (N=0) or `"0."` followed by
`N` `0`s. N=0 ⇒ integer display in both.

## 6. Cross-crate release

Order: **sdata-core merges first** (sdata CI clones `sdata-core@main`).

- **sdata-core** — additive only. Regenerate `docs/api/reference.html`
  (`scripts/gen-reference.sh`) because public `.ads` files change (`commands.ads`,
  `file_io.ads`, `config.ads`), or the `build.yml` api-reference job fails. Bump
  **0.1.26 → 0.1.27**.
- **sdata** — parser/AST/interpreter + docs. Bump **0.13.3 → 0.14.0** via
  `scripts/bump-version.sh`. Raise `sdata/alire.toml` floor to **`^0.1.27`**.
- **data-vandal** — code untouched (defaulted params). Bump its `alire.toml`
  `sdata_core` constraint to `^0.1.27`; run its `make check` in the two-consumer gate.
- Bump `sdata-core`'s `consumer-tests.yml` `ref:` to the new sdata tag.
- **Local gate before pushing:** `cd ~/Develop/sdata-core && alr build`, then `make
  check` in sdata and in data-vandal — all three green.

## 7. User-facing surface (all in the same change — per CLAUDE.md)

- **HELP** — `src/sdata-help.adb` SAVE topic gains `/DECIMALS=N`; regenerate
  `tests/expected/help_all.out` and any `*_options` / `options_display` snapshot that
  lists SAVE options.
- **Man page** — `man/man1/sdata.1` SAVE synopsis + option description.
- **Design doc** — `doc/design.md` SAVE command reference; document the
  CSV-trims-zeros vs spreadsheet-fixed asymmetry explicitly.
- **ADR-050** in `doc/adrs.md` — records per-format semantics, defaulted-parameter
  plumbing (contract safety), and the display-format-vs-value-rounding split.
- **architecture.md** — add a note on the new writer style layer if warranted.

## 8. Test plan

### 8.1 Integration (`.cmd`, sdata `tests/`)

- **CSV**: `/DECIMALS=2` rounds + trims (`3.14159`→`3.14`, `0.50`→`0.5`, `100`→`100`);
  `N=0` → integer; **negative N → parse error**; per-target paren form with differing
  N; whole-statement form across multiple CSV targets.
- **Spreadsheet**: save `.ods` and `.xlsx` with `/DECIMALS=2`; assert the **stored
  value stays full precision** and the **number-format is present** (unzip + grep the
  XML for `number:number-style` / `numFmt` + `s=`); integer cells carry no format;
  `Inf`/missing untouched.
- **Regression**: absent option ⇒ byte-identical output in all three formats.

### 8.2 Unit

- `Format_CSV_Decimals` edge cases (N=0 rounding incl. ties, trailing-zero trim,
  bare-`.` trim, `Inf`, very large / very small magnitudes) in the csv or file_io
  unit-test binary.
- ODF/OOXML format-code construction (N=0 vs N≥1) in `file_io_unit_test`.

## 9. Out of scope (YAGNI)

- Per-column precision (a single `N` per SAVE target only).
- Significant-digits mode or scientific-notation control.
- Applying a display format to integer or string columns.
- Coupling to `OPTIONS DIGITS` (console setting stays independent).
- Rounding-mode configurability (uses the standard library's fixed-notation rounding
  for CSV `N≥1` and `Float'Rounding` for `N=0`).
