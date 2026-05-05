# Parse_CSV Refactor: Extract SData.CSV Package

## Goal

Extract the six pure CSV string helpers from the `Parse_CSV` monolith in
`sdata-file_io.adb` into a new `SData.CSV` package, enabling Ada unit testing
of those helpers. Add a compiled `csv_unit_test` executable exercising all six
functions. No observable behaviour changes.

## Architecture

`SData.CSV` (`src/sdata-csv.ads` / `src/sdata-csv.adb`) is a pure-Ada package
with no dependencies on `SData.Table`, `SData.IO`, or any other SData package.
It owns the CSV field-boundary types and the six algorithmic helpers that are
currently nested inside `Parse_CSV`.

The helpers that have legitimate closure dependencies on `Parse_CSV` local
state remain nested:

| Procedure | Reason it stays nested |
|---|---|
| `Validate_ASCII` | References closure `File_Name` for error message |
| `Split_Into_Lines` | Writes to closure `All_Lines` vector |
| `Process_Line_Direct` | Calls `Add_Row`, `Set_Value_Upper` (Table API); reads `Rows_Written`, `Max_Rows`, `DLen` |
| `Load_Columns_And_Data` | Calls `Clear`, `Add_Column`; reads `Scan_Lines`, `Scan_Count`, `Is_Buffered`, `All_Lines`, `File`, `Line_Buf`, `Needs_ASCII_Chk` |
| `Load_As_UTF16` | Binary file I/O; writes to `All_Lines`, `Is_Buffered` |
| `Detect_And_Load` | Charset detection entry point; calls `Load_As_UTF16` |

`DLen` (the effective delimiter length constant) stays at `Parse_CSV` scope;
the extracted functions accept `Delimiter : String` and compute their own
effective length internally.

## File Changes

| File | Action |
|---|---|
| `src/sdata-csv.ads` | Create — package spec |
| `src/sdata-csv.adb` | Create — package body |
| `src/sdata-file_io.adb` | Modify — remove 6 nested helpers, add `with SData.CSV; use SData.CSV;`, update 3 call sites |
| `tests/csv_unit_test.adb` | Create — standalone test executable |
| `sdata.gpr` | Modify — add `"tests"` to `Source_Dirs`, add `csv_unit_test` to `Main` and `Builder` |
| `Makefile` | Modify — run `./bin/csv_unit_test` before `.cmd` loop in `check` target |

## `SData.CSV` Package Spec

```ada
package SData.CSV is

   Max_Fields : constant := 65_536;
   type Field_Pair  is record S, E : Natural; end record;
   type Field_Array is array (1 .. Max_Fields) of Field_Pair;

   --  Fast non-allocating decimal parser.  Returns True and sets Result for
   --  any valid float value; falls back to Float'Value for scientific notation.
   function Try_Fast_Float   (S         : String;
                               Result    : out Float) return Boolean;

   --  True iff F parses as a number.
   function Is_Numeric_Field (F : String) return Boolean;

   --  True iff Delimiter starts at Pos in Line.
   function At_Delimiter     (Line      : String;
                               Pos       : Positive;
                               Delimiter : String) return Boolean;

   --  Returns the position of the delimiter that ends the field starting at
   --  From, or 0 if this is the final field.  Honours RFC-4180 quoting:
   --  doubled same-type quotes are literal; opposite quote type is literal
   --  inside a quoted field.
   function CSV_Field_End    (Line      : String;
                               From      : Positive;
                               Delimiter : String) return Natural;

   --  Strips surrounding matching quotes and collapses doubled same-type
   --  quotes.  Returns Ada.Strings.Fixed.Trim for unquoted fields.
   function CSV_Unquote      (Raw : String) return String;

   --  Splits Line into Field_Pair boundary records; sets N_Fields to the
   --  actual field count (may exceed Max_Fields for pathological input —
   --  only the first Max_Fields entries are recorded).
   function Split_Indices    (Line      : String;
                               Delimiter : String;
                               N_Fields  : out Natural) return Field_Array;

end SData.CSV;
```

## Call-Site Updates in `sdata-file_io.adb`

Three call sites gain a `Delimiter` argument:

| Location | Before | After |
|---|---|---|
| `Process_Line_Direct:486` | `CSV_Field_End (Line, Start)` | `CSV_Field_End (Line, Start, Delimiter)` |
| `Load_Columns_And_Data:572` | `Split_Indices (H_Str, N_Hdr)` | `Split_Indices (H_Str, Delimiter, N_Hdr)` |
| `Load_Columns_And_Data:597` | `Split_Indices (D_Str, N_Fld)` | `Split_Indices (D_Str, Delimiter, N_Fld)` |

`At_Delimiter` is called only from `CSV_Field_End` and `Split_Indices`; those
calls disappear from the nested procedures and live inside `SData.CSV` only.

Local declarations removed from `Parse_CSV`: `Field_Pair`, `Field_Array`,
`Max_Fields` (replaced by `SData.CSV` exports); the six function/procedure
bodies for `Try_Fast_Float`, `Is_Numeric_Field`, `At_Delimiter`,
`CSV_Field_End`, `CSV_Unquote`, `Split_Indices`.

## `csv_unit_test.adb` — Test Cases (21 total)

| # | Function | Input | Expected |
|---|---|---|---|
| 1 | `Try_Fast_Float` | `"42"` | True, 42.0 |
| 2 | `Try_Fast_Float` | `"-3.14"` | True, −3.14 |
| 3 | `Try_Fast_Float` | `"1.5E3"` | True, 1500.0 |
| 4 | `Try_Fast_Float` | `""` | False |
| 5 | `Try_Fast_Float` | `"abc"` | False |
| 6 | `Is_Numeric_Field` | `"42"` | True |
| 7 | `Is_Numeric_Field` | `"."` | False |
| 8 | `Is_Numeric_Field` | `""` | False |
| 9 | `At_Delimiter` | `"a,b"` pos 2, `","` | True |
| 10 | `At_Delimiter` | `"a,b"` pos 1, `","` | False |
| 11 | `At_Delimiter` | `"a" & ASCII.HT & "b"` pos 2, `"" & ASCII.HT` | True |
| 12 | `CSV_Field_End` | `"a,b,c"` from 1, `","` | 2 |
| 13 | `CSV_Field_End` | `"a,b,c"` from 5, `","` | 0 |
| 14 | `CSV_Field_End` | `"""hi"",b"` from 1, `","` | 5 |
| 15 | `CSV_Unquote` | `"""hello"""` | `hello` |
| 16 | `CSV_Unquote` | `"""he""""llo"""` | `he"llo` |
| 17 | `CSV_Unquote` | `"  hello  "` | `hello` |
| 18 | `CSV_Unquote` | `"'world'"` | `world` |
| 19 | `Split_Indices` | `"a,b,c"` / `","` | N=3; (1,1),(3,3),(5,5) |
| 20 | `Split_Indices` | `""` / `","` | N=0 |
| 21 | `Split_Indices` | `"""a,b"",c"` / `","` | N=2; first field covers quoted span |

The harness prints `PASS`/`FAIL` per case to stdout and exits with status 1 if
any case fails, 0 if all pass.

## `sdata.gpr` Changes

```ada
for Source_Dirs use ("src/**", "tests");
for Main use ("sdata_main.adb", "csv_unit_test.adb");

package Builder is
   for Default_Switches ("Ada") use ("-g");
   for Executable ("sdata_main.adb")     use "sdata";
   for Executable ("csv_unit_test.adb")  use "csv_unit_test";
end Builder;
```

## `Makefile` Change

In the `check` target, before the `.cmd` loop:

```makefile
@echo "Running unit tests..."
@$(TIMEOUT) 30 ./bin/csv_unit_test; \
 if [ $$? -ne 0 ]; then \
   echo "Unit tests FAILED"; exit 1; \
 fi
```

## Error Handling

`SData.CSV` raises no exceptions. `Try_Fast_Float` returns `False` for
unparseable input; `CSV_Field_End` returns `0` for the final field;
`Split_Indices` silently caps at `Max_Fields`. The existing exception behaviour
of `Parse_CSV` is unchanged.

## Testing Strategy

1. `alr build` must succeed with zero warnings after all changes.
2. `./bin/csv_unit_test` must exit 0 with all 21 cases `PASS`.
3. `make check` must pass all existing tests (currently 99) — confirming no
   behavioural regression in `Parse_CSV`.
