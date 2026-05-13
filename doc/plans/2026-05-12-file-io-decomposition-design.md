# Design: Decompose sdata-file_io.adb into Child Packages

**Date:** 2026-05-12
**Status:** Approved, pending implementation

## Problem

`sdata-file_io.adb` is 1,842 lines containing three unrelated parsers (CSV, ODF,
OOXML), two writers, and a collection of shared helpers. The file is difficult to
navigate and violates the one-clear-purpose principle.

## Approved Design

### Package Structure

| Package | Files | Contents |
|---|---|---|
| `SData.File_IO` | `sdata-file_io.ads/.adb` | `Open_Input`, `Open_Output` only |
| `SData.File_IO.Helpers` | `sdata-file_io-helpers.ads/.adb` | Private child — shared helpers |
| `SData.File_IO.CSV` | `sdata-file_io-csv.ads/.adb` | `Parse_CSV`, `Write_CSV` |
| `SData.File_IO.ODF` | `sdata-file_io-odf.ads/.adb` | `Parse_ODF`, `Write_ODF` |
| `SData.File_IO.OOXML` | `sdata-file_io-ooxml.ads/.adb` | `Parse_OOXML`, `Write_OOXML` |

`SData.File_IO.Helpers` is declared `private package` — only packages within the
`SData.File_IO` subtree can `with` it.

### Helpers Contents (~200 lines)

Shared across two or more format packages:

| Helper | Used by |
|---|---|
| `Get_Text` | ODF + OOXML |
| `Detect_Inf` | CSV + ODF + OOXML |
| `Apply_Dollar_Override` | CSV + ODF + OOXML |
| `Safe_Name` | CSV + ODF + OOXML |
| `Has_Formulas_XML` | ODF (pre-convert probe) |
| `Convert_Via_LibreOffice` | ODF + OOXML fallback |
| `Col_To_Letters` | Write_CSV + Write_OOXML |
| `Escape_XML` | Write_ODF + Write_OOXML |

### CSV Package (~500 lines)

Public: `Parse_CSV`, `Write_CSV`.
Body-private (not shared): `Split_Into_Lines`, `Load_As_UTF16`, `Detect_And_Load`,
`File_Base`, `File_Stem`.

### ODF Package (~430 lines)

Public: `Parse_ODF`, `Write_ODF`.
Body-private: DOM traversal helpers, cell-type dispatch.

### OOXML Package (~430 lines)

Public: `Parse_OOXML`, `Write_OOXML`.
Body-private: `Find_Sheet_XML_Path`, `Load_Shared_Strings`.

### Build

`default.gpr` sources `src/` by directory glob — no GPR edits needed.

## Migration

**`src/sdata-interpreter.adb`:** Add three `with`/`use` clauses:
```ada
with SData.File_IO.CSV;   use SData.File_IO.CSV;
with SData.File_IO.ODF;   use SData.File_IO.ODF;
with SData.File_IO.OOXML; use SData.File_IO.OOXML;
```
Call sites unchanged (`use` makes bare names visible). `Open_Input`/`Open_Output`
remain on the parent package (already `with`'d).

**`tests/file_io_unit_test.adb`:** Same three `with`/`use` additions; 73 test
calls themselves are unchanged.

No other callers (`sdata-file_io` is `with`'d only in those two files).

## Testing Strategy

The 73 existing `file_io_unit_test` tests serve as the safety net. No new behavior
is introduced; all 300+ tests must pass before and after.

Implementation order (each step verified green before the next):

1. Extract `SData.File_IO.Helpers`
2. Extract `SData.File_IO.CSV`
3. Extract `SData.File_IO.ODF`
4. Extract `SData.File_IO.OOXML`
5. Trim parent spec/body; update `interpreter.adb` and `file_io_unit_test.adb`
6. Run full `make check`
