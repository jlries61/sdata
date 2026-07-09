# SAVE `/DECIMALS=N` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a `/DECIMALS=N` option to `SAVE` (CSV rounds+trims the text; ODS/OOXML keep full precision and attach a fixed-N-decimal display format), and fix the latent 6-significant-digit `Float'Image` truncation in all three writers by rendering floats at round-trip precision.

**Architecture:** Two shared renderers in `SData_Core.Values` replace the inlined `Float'Image` in the CSV/ODF/OOXML writers. `Execute_SAVE`/`Open_Output` gain a defaulted `Decimals : Integer := -1` (−1 = unset) threaded to the writers; the sdata parser adds the option in both the paren and slash forms and the interpreter computes the effective value at both SAVE dispatch paths. sdata-core changes are additive and merge first (sdata CI clones `sdata-core@main`).

**Tech Stack:** Ada 2012, GNAT/GPRbuild, Alire. Two crates: `sdata` (`~/Develop/sdata`, parser/AST/interpreter/docs/tests) and `sdata-core` (`~/Develop/sdata-core`, execution/writers/values). Consumed via a path pin, so a local `make check` in sdata validates both layers.

## Global Constraints

- **Design spec:** `doc/specs/2026-07-09-save-decimals-design.md` (authoritative for behavior).
- **Merge order:** sdata-core PR merges **before** the sdata PR. sdata-core & data-vandal require PRs; sdata may push to main but this feature uses a PR.
- **Version bumps:** sdata-core `0.1.26 → 0.1.27`; sdata `0.13.3 → 0.14.0`. Raise the floor `sdata_core = "^0.1.26"` → `"^0.1.27"` in **both** `sdata/alire.toml` and `data-vandal/alire.toml`; bump `sdata-core`'s `.github/workflows/consumer-tests.yml` `ref:` to the new sdata tag.
- **Public `.ads` change ⇒ regenerate** `sdata-core/docs/api/reference.html` via `scripts/gen-reference.sh` (the `build.yml` api-reference job fails otherwise).
- **Cross-crate gate (mandatory before any push):** `cd ~/Develop/sdata-core && alr build`, then `cd ~/Develop/sdata && make check`, then `cd ~/Develop/data-vandal && make check`. All three green. Never use `--no-verify`.
- **User-facing surface stays in sync in the same change:** HELP (`src/sdata-help.adb` + regenerate `tests/expected/help_all.out` and any `*_options` snapshot), man page (`man/man1/sdata.1`), design doc (`doc/design.md`).
- **Sentinel:** `Decimals = -1` means "no `/DECIMALS=` given" ⇒ round-trip default rendering, no CSV rounding, no spreadsheet number-format.
- **Do not** reintroduce a hardcoded bundled sdata-core version in packaging files.

---

# PHASE A — sdata-core (branch `add-save-decimals`, PR, merge first)

Create the branch first:

```bash
cd ~/Develop/sdata-core && git checkout -b add-save-decimals
```

## Task 1: Round-trip and fixed-decimals renderers in `SData_Core.Values`

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-values.ads` (add two public functions after `To_String_Formatted`, currently line 45)
- Modify: `~/Develop/sdata-core/src/sdata_core-values.adb` (add a private helper + two bodies)
- Test: `~/Develop/sdata-core/tests/values_tests.adb`

**Interfaces:**
- Produces:
  - `function Image_Round_Trip (X : Float) return String;` — shortest fixed-notation decimal that reads back to exactly `X`, trailing zeros trimmed; exponential fallback for extreme magnitudes; `Inf`/`-Inf`/`0` handled.
  - `function Image_Fixed_Decimals (X : Float; Decimals : Natural) return String;` — round `X` to `Decimals` places, trim trailing zeros and a bare `.`; `Decimals = 0` rounds to nearest integer.

- [ ] **Step 1: Write the failing tests** — append inside `Values_Tests` before the final summary `Put_Line`/exit block in `~/Develop/sdata-core/tests/values_tests.adb`:

```ada
   --  Image_Round_Trip: clean cases are exact; others must round-trip.
   Assert (Image_Round_Trip (0.0)    = "0",    "RT 0.0");
   Assert (Image_Round_Trip (150.0)  = "150",  "RT 150.0");
   Assert (Image_Round_Trip (0.5)    = "0.5",  "RT 0.5");
   Assert (Image_Round_Trip (-2.5)   = "-2.5", "RT -2.5");
   Assert (Image_Round_Trip (100.0)  = "100",  "RT 100.0");
   Assert (Float'Value (Image_Round_Trip (0.1))        = 0.1,        "RT 0.1 round-trips");
   Assert (Float'Value (Image_Round_Trip (1.0 / 3.0))  = 1.0 / 3.0,  "RT 1/3 round-trips");
   Assert (Float'Value (Image_Round_Trip (123456.789)) = Float'(123456.789),
           "RT 123456.789 round-trips");
   Assert (Image_Round_Trip (Pos_Inf) = "Inf",  "RT Pos_Inf");
   Assert (Image_Round_Trip (Neg_Inf) = "-Inf", "RT Neg_Inf");

   --  Image_Fixed_Decimals: round + trim trailing zeros; N=0 -> integer.
   Assert (Image_Fixed_Decimals (3.14159, 2) = "3.14", "FD 3.14159 @2");
   Assert (Image_Fixed_Decimals (0.5,     2) = "0.5",  "FD 0.5 @2 trims");
   Assert (Image_Fixed_Decimals (100.0,   2) = "100",  "FD 100 @2 trims to int");
   Assert (Image_Fixed_Decimals (3.14159, 0) = "3",    "FD 3.14159 @0");
   Assert (Image_Fixed_Decimals (3.99,    0) = "4",    "FD 3.99 @0 rounds up");
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ~/Develop/sdata-core && gprbuild -q -p -P tests/sdata_core_tests.gpr 2>&1 | head`
Expected: compile FAIL — `"Image_Round_Trip" is undefined` / `"Image_Fixed_Decimals" is undefined`.

- [ ] **Step 3: Declare the two functions** in `sdata_core-values.ads` immediately after the `To_String_Formatted` declaration (after line 45):

```ada

   --  Round-trip float rendering used by the CSV/ODF/OOXML writers for the
   --  default (no /DECIMALS) numeric output: the shortest fixed-notation
   --  decimal that reads back to exactly X, trailing zeros trimmed, with an
   --  exponential fallback for extreme magnitudes.  Reproduces the stored
   --  single-precision Float exactly (Float'Image emits only 6 significant
   --  digits and is lossy).
   function Image_Round_Trip (X : Float) return String;

   --  Fixed-decimals rendering for SAVE /DECIMALS=N on CSV: round X to
   --  Decimals places, then trim trailing zeros and any bare '.'.
   --  Decimals = 0 rounds to the nearest integer.
   function Image_Fixed_Decimals (X : Float; Decimals : Natural) return String;
```

- [ ] **Step 4: Implement the bodies** — add to `sdata_core-values.adb` (a private helper plus the two functions; place them after `To_String_Formatted`'s body, i.e. after line 112). `Trim`, `Ada.Strings.Both`, and `Ada.Text_IO` are already visible in this body (used by `To_String_Formatted`).

```ada
   --  Strip trailing zeros in the fractional part and a trailing bare '.'.
   --  Strings with no '.', or any exponent ('E'/'e'), are returned unchanged.
   function Trim_Trailing_Zeros (S : String) return String is
      Has_Dot : Boolean := False;
   begin
      for Ch of S loop
         if Ch = 'E' or else Ch = 'e' then
            return S;
         elsif Ch = '.' then
            Has_Dot := True;
         end if;
      end loop;
      if not Has_Dot then
         return S;
      end if;
      declare
         Last : Integer := S'Last;
      begin
         while Last >= S'First and then S (Last) = '0' loop
            Last := Last - 1;
         end loop;
         if Last >= S'First and then S (Last) = '.' then
            Last := Last - 1;
         end if;
         return S (S'First .. Last);
      end;
   end Trim_Trailing_Zeros;

   function Image_Round_Trip (X : Float) return String is
      package Float_IO is new Ada.Text_IO.Float_IO (Float);
      Buf : String (1 .. 128);
   begin
      if Is_Inf (X) then
         return (if X > 0.0 then "Inf" else "-Inf");
      end if;
      if X = 0.0 then
         return "0";
      end if;
      --  Integer-valued fast path (also avoids Aft=0 in Float_IO.Put).
      declare
         R : constant Float := Float'Rounding (X);
      begin
         if R = X and then abs R < Float (Integer'Last) then
            return Trim (Integer'Image (Integer (R)), Ada.Strings.Both);
         end if;
      end;
      --  Shortest fixed-notation form (Aft >= 1) that reads back exactly.
      for Aft in 1 .. 17 loop
         begin
            Float_IO.Put (Buf, X, Aft => Aft, Exp => 0);
            declare
               S : constant String := Trim (Buf, Ada.Strings.Both);
            begin
               if Float'Value (S) = X then
                  return Trim_Trailing_Zeros (S);
               end if;
            end;
         exception
            when others => null;  --  field overflow etc.; try next Aft
         end;
      end loop;
      --  Fallback: exponential, 9 significant digits.
      Float_IO.Put (Buf, X, Aft => 8, Exp => 2);
      return Trim (Buf, Ada.Strings.Both);
   end Image_Round_Trip;

   function Image_Fixed_Decimals (X : Float; Decimals : Natural) return String is
      package Float_IO is new Ada.Text_IO.Float_IO (Float);
      Buf : String (1 .. 128);
   begin
      if Is_Inf (X) then
         return (if X > 0.0 then "Inf" else "-Inf");
      end if;
      if Decimals = 0 then
         declare
            R : constant Float := Float'Rounding (X);
         begin
            if abs R < Float (Integer'Last) then
               return Trim (Integer'Image (Integer (R)), Ada.Strings.Both);
            else
               return Image_Round_Trip (R);
            end if;
         end;
      end if;
      Float_IO.Put (Buf, X, Aft => Decimals, Exp => 0);
      return Trim_Trailing_Zeros (Trim (Buf, Ada.Strings.Both));
   end Image_Fixed_Decimals;
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `cd ~/Develop/sdata-core && gprbuild -q -p -P tests/sdata_core_tests.gpr && tests/bin/values_tests`
Expected: PASS lines only; no `FAIL:` lines; final line reports 0 failed.

- [ ] **Step 6: Commit**

```bash
cd ~/Develop/sdata-core
git add src/sdata_core-values.ads src/sdata_core-values.adb tests/values_tests.adb
git commit -m "feat(values): round-trip + fixed-decimals float renderers"
```

## Task 2: CSV writer — round-trip default + `/DECIMALS`, thread `Decimals` to `Open_Output`

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-file_io.ads:40-46` (`Open_Output` spec)
- Modify: `~/Develop/sdata-core/src/sdata_core-file_io.adb:96-138` (`Open_Output` body + writer calls)
- Modify: `~/Develop/sdata-core/src/sdata_core-file_io-csv.adb:550-554` (`Write_CSV` signature) and `:683-704` (numeric cell)
- Modify: `~/Develop/sdata-core/src/sdata_core-file_io-odf.adb:406` (`Write_ODF` signature only — body in Task 3)
- Modify: `~/Develop/sdata-core/src/sdata_core-file_io-ooxml.adb:501` (`Write_OOXML` signature only — body in Task 4)
- Test: `~/Develop/sdata/tests/file_io_unit_test.adb` (round-trip through parse)

**Interfaces:**
- Consumes: `SData_Core.Values.Image_Round_Trip`, `Image_Fixed_Decimals` (Task 1).
- Produces: `Open_Output (…; Decimals : Integer := -1)`; `Write_CSV/Write_ODF/Write_OOXML (…; Decimals : Integer := -1)`.

- [ ] **Step 1: Write the failing tests** — append inside `File_IO_Unit_Test` (before the final summary), in `~/Develop/sdata/tests/file_io_unit_test.adb`. These write via `Open_Output` and read back via `Parse_CSV`. Add a numeric-string `Check` if not already present is unnecessary — use the existing `Check (Name, Got, Expected : String)` on `To_String`.

```ada
   --  Round-trip default: a value 6-digit Float'Image would corrupt survives.
   Parse_CSV ("tests/data/precision_src.csv");
   SData_Core.File_IO.Open_Output ("tests/data/rt_out.csv", SData_Core.Config.CSV);
   Parse_CSV ("tests/data/rt_out.csv");
   V := Get_Value (1, "X");
   Check ("CSV round-trip preserves X",
          Float'Value (To_String (V)) = Float'(123456.789), True);

   --  /DECIMALS=2 rounds the stored CSV text.
   Parse_CSV ("tests/data/precision_src.csv");
   SData_Core.File_IO.Open_Output ("tests/data/dec_out.csv", SData_Core.Config.CSV,
                                   Decimals => 2);
   Parse_CSV ("tests/data/dec_out.csv");
   V := Get_Value (2, "X");   --  row 2 X = 3.14159 in the fixture
   Check ("CSV DECIMALS=2 rounds X to 3.14", To_String (V), "3.14");
```

Create the fixture `~/Develop/sdata/tests/data/precision_src.csv`:

```
X,LABEL$
123456.789,a
3.14159,b
0.5,c
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ~/Develop/sdata && make check 2>&1 | grep -E "FAIL|Decimals|error:" | head`
Expected: FAIL — either a compile error (`Open_Output` has no `Decimals` parameter) or the two new `FAIL:` assertions.

- [ ] **Step 3: Add `Decimals` to `Open_Output` spec** — `sdata_core-file_io.ads:40-46` becomes:

```ada
   procedure Open_Output (File_Name       : String;
                          Fmt             : Format_Type;
                          Sheet_Name      : String  := "";
                          Delimiter       : String  := ",";
                          Write_Header    : Boolean := True;
                          Allow_Overwrite : Boolean := True;
                          Charset         : String  := "";
                          Decimals        : Integer := -1);
```

- [ ] **Step 4: Thread it in `Open_Output` body** — `sdata_core-file_io.adb`: mirror the new parameter on the body's parameter list (lines 96-102) and pass it in the dispatch `case` (lines 130-137):

```ada
      case Actual_Fmt is
         when SData_Core.Config.CSV =>
            Write_CSV (File_Name, Delimiter, Write_Header, Allow_Overwrite,
                       Charset, Decimals);
         when SData_Core.Config.ODF =>
            Write_ODF (File_Name, Sname, Decimals);
         when SData_Core.Config.OOXML =>
            Write_OOXML (File_Name, Sname, Decimals);
      end case;
```

- [ ] **Step 5: Add `Decimals` to the three writer signatures.**
  - `sdata_core-file_io-csv.adb:550-554` → add `Decimals : Integer := -1` as the last parameter of `Write_CSV`.
  - `sdata_core-file_io-odf.adb:406` → `procedure Write_ODF (File_Name : String; Sheet_Name : String := "Sheet1"; Decimals : Integer := -1) is`
  - `sdata_core-file_io-ooxml.adb:501` → `procedure Write_OOXML (File_Name : String; Sheet_Name : String := "Sheet1"; Decimals : Integer := -1) is`

  (ODF/OOXML bodies are unchanged in this task — they accept and ignore `Decimals`; `pragma Unreferenced (Decimals);` is **not** needed because Tasks 3/4 use it next, but if the build warns as errors, add it and remove it in the next task.)

- [ ] **Step 6: Implement the CSV numeric cell** — replace `sdata_core-file_io-csv.adb:688-693` (the `if Val.Kind = Val_Numeric then … end if;` inner block) with:

```ada
                     if Val.Kind = Val_Numeric then
                        if Is_Inf (Val.Num_Val) then
                           Write_String
                              (if Val.Num_Val > 0.0 then "Inf" else "-Inf");
                        elsif Decimals >= 0 then
                           Write_String
                              (SData_Core.Values.Image_Fixed_Decimals
                                 (Val.Num_Val, Decimals));
                        else
                           Write_String
                              (SData_Core.Values.Image_Round_Trip (Val.Num_Val));
                        end if;
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `cd ~/Develop/sdata-core && alr build && cd ~/Develop/sdata && make check 2>&1 | grep -E "FAIL|round-trip|DECIMALS=2" `
Expected: the two new checks PASS; no `FAIL:` lines. (Some existing `.cmd` fixtures that dump a saved CSV may now differ — regenerate them in Task 10; if `make check` reports integration diffs here they are expected and handled there.)

- [ ] **Step 8: Commit**

```bash
cd ~/Develop/sdata-core
git add src/sdata_core-file_io.ads src/sdata_core-file_io.adb \
        src/sdata_core-file_io-csv.adb src/sdata_core-file_io-odf.adb \
        src/sdata_core-file_io-ooxml.adb
git commit -m "feat(csv): round-trip default + /DECIMALS rounding; thread Decimals"
cd ~/Develop/sdata
git add tests/file_io_unit_test.adb tests/data/precision_src.csv
git commit -m "test(file_io): CSV round-trip + DECIMALS rounding via Open_Output"
```

## Task 3: ODF writer — round-trip default + fixed-decimals display style

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-file_io-odf.adb:429-439` (root + automatic-styles) and `:469-475` (numeric cell)
- Test: `~/Develop/sdata/tests/file_io_unit_test.adb` (read-back value preserved) + an integration `.cmd` in Task 10 for style presence.

**Interfaces:**
- Consumes: `Image_Round_Trip`, `Image_Fixed_Decimals`; the `Decimals` param added in Task 2.

- [ ] **Step 1: Write the failing test** — append in `file_io_unit_test.adb`:

```ada
   --  ODF keeps full precision in office:value regardless of /DECIMALS.
   Parse_CSV ("tests/data/precision_src.csv");
   SData_Core.File_IO.Open_Output ("tests/data/dec_out.ods", SData_Core.Config.ODF,
                                   Decimals => 2);
   Parse_ODF ("tests/data/dec_out.ods");
   V := Get_Value (1, "X");
   Check ("ODF stored value stays full precision",
          Float'Value (To_String (V)) = Float'(123456.789), True);
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ~/Develop/sdata-core && alr build && cd ~/Develop/sdata && make check 2>&1 | grep -E "FAIL: ODF stored"`
Expected: FAIL — the current writer stores 6-digit `Float'Image`, so the read-back value differs from `123456.789`.

- [ ] **Step 3: Root element + automatic-styles** — replace `sdata_core-file_io-odf.adb:431-437` (the single `Append (S1, "<office:document-content …");`) with:

```ada
         if Decimals >= 0 then
            Append (S1,
               "<office:document-content xmlns:office=""urn:oasis:names:tc:opendocument:xmlns:office:1.0"" " &
               "xmlns:table=""urn:oasis:names:tc:opendocument:xmlns:table:1.0"" " &
               "xmlns:text=""urn:oasis:names:tc:opendocument:xmlns:text:1.0"" " &
               "xmlns:number=""urn:oasis:names:tc:opendocument:xmlns:datastyle:1.0"" " &
               "xmlns:style=""urn:oasis:names:tc:opendocument:xmlns:style:1.0"" " &
               "office:version=""1.2"">" & ASCII.LF);
            declare
               DP : constant String := Trim (Decimals'Img, Ada.Strings.Both);
            begin
               Append (S1,
                  "<office:automatic-styles>" &
                  "<number:number-style style:name=""NDEC"">" &
                  "<number:number number:decimal-places=""" & DP &
                  """ number:min-decimal-places=""" & DP & """/>" &
                  "</number:number-style>" &
                  "<style:style style:name=""ceDEC"" style:family=""table-cell"" " &
                  "style:data-style-name=""NDEC""/>" &
                  "</office:automatic-styles>" & ASCII.LF);
            end;
         else
            Append (S1,
               "<office:document-content xmlns:office=""urn:oasis:names:tc:opendocument:xmlns:office:1.0"" " &
               "xmlns:table=""urn:oasis:names:tc:opendocument:xmlns:table:1.0"" " &
               "xmlns:text=""urn:oasis:names:tc:opendocument:xmlns:text:1.0"" " &
               "office:version=""1.2"">" & ASCII.LF);
         end if;
```

- [ ] **Step 4: Numeric cell** — replace the numeric `else` branch at `sdata_core-file_io-odf.adb:469-474`:

```ada
                        else
                           declare
                              RT   : constant String :=
                                 SData_Core.Values.Image_Round_Trip (V.Num_Val);
                              Disp : constant String :=
                                 (if Decimals >= 0
                                  then SData_Core.Values.Image_Fixed_Decimals
                                          (V.Num_Val, Decimals)
                                  else RT);
                              Sty  : constant String :=
                                 (if Decimals >= 0
                                  then " table:style-name=""ceDEC""" else "");
                           begin
                              Append (S1,
                                 "<table:table-cell" & Sty &
                                 " office:value-type=""float"" office:value=""" &
                                 RT & """>" &
                                 "<text:p>" & Disp &
                                 "</text:p></table:table-cell>");
                           end;
                        end if;
```

- [ ] **Step 5: Run to verify it passes**

Run: `cd ~/Develop/sdata-core && alr build && cd ~/Develop/sdata && make check 2>&1 | grep -E "FAIL: ODF|ODF stored"`
Expected: `ODF stored value stays full precision` PASSes; no ODF `FAIL:`.

- [ ] **Step 6: Commit**

```bash
cd ~/Develop/sdata-core
git add src/sdata_core-file_io-odf.adb
git commit -m "feat(odf): round-trip office:value + fixed-decimals number-style"
cd ~/Develop/sdata && git add tests/file_io_unit_test.adb
git commit -m "test(file_io): ODF stored value stays full precision"
```

## Task 4: OOXML writer — round-trip default + `styles.xml` number format

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-file_io-ooxml.adb` — `[Content_Types].xml` (513-521), `xl/_rels/workbook.xml.rels` (538-543), new `xl/styles.xml` part, numeric `<c>` (600-604).
- Test: `~/Develop/sdata/tests/file_io_unit_test.adb`.

**Interfaces:**
- Consumes: `Image_Round_Trip`; the `Decimals` param from Task 2.

- [ ] **Step 1: Write the failing test** — append in `file_io_unit_test.adb`:

```ada
   --  OOXML keeps full precision in <v> regardless of /DECIMALS.
   Parse_CSV ("tests/data/precision_src.csv");
   SData_Core.File_IO.Open_Output ("tests/data/dec_out.xlsx", SData_Core.Config.OOXML,
                                   Decimals => 2);
   Parse_OOXML ("tests/data/dec_out.xlsx");
   V := Get_Value (1, "X");
   Check ("OOXML stored value stays full precision",
          Float'Value (To_String (V)) = Float'(123456.789), True);
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ~/Develop/sdata-core && alr build && cd ~/Develop/sdata && make check 2>&1 | grep -E "FAIL: OOXML"`
Expected: FAIL — current writer stores 6-digit `Float'Image`.

- [ ] **Step 3: `[Content_Types].xml` with optional styles Override** — replace the first `Add_String (Info, …, "[Content_Types].xml");` (ooxml.adb:513-521) with:

```ada
      declare
         Styles_Override : constant String :=
            (if Decimals >= 0
             then "<Override PartName=""/xl/styles.xml"" " &
                  "ContentType=""application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml""/>"
             else "");
      begin
         Add_String (Info,
            "<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?>" &
            "<Types xmlns=""http://schemas.openxmlformats.org/package/2006/content-types"">" &
            "<Default Extension=""rels"" ContentType=""application/vnd.openxmlformats-package.relationships+xml""/>" &
            "<Default Extension=""xml"" ContentType=""application/xml""/>" &
            "<Override PartName=""/xl/workbook.xml"" ContentType=""application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml""/>" &
            "<Override PartName=""/xl/worksheets/sheet1.xml"" ContentType=""application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml""/>" &
            Styles_Override &
            "</Types>",
            "[Content_Types].xml");
      end;
```

- [ ] **Step 4: `workbook.xml.rels` with optional styles relationship** — replace the `Add_String (Info, …, "xl/_rels/workbook.xml.rels");` (ooxml.adb:538-543) with:

```ada
      declare
         Styles_Rel : constant String :=
            (if Decimals >= 0
             then "<Relationship Id=""rId2"" Type=""http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles"" Target=""styles.xml""/>"
             else "");
      begin
         Add_String (Info,
            "<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?>" &
            "<Relationships xmlns=""http://schemas.openxmlformats.org/package/2006/relationships"">" &
            "<Relationship Id=""rId1"" Type=""http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"" Target=""worksheets/sheet1.xml""/>" &
            Styles_Rel &
            "</Relationships>",
            "xl/_rels/workbook.xml.rels");
      end;
```

- [ ] **Step 5: Emit `xl/styles.xml`** — insert immediately after the `workbook.xml.rels` `Add_String` (before the `declare S1 : Unbounded_String; begin` worksheet block):

```ada
      if Decimals >= 0 then
         declare
            Fmt_Code : constant String :=
               (if Decimals = 0 then "0"
                else "0." & (1 .. Decimals => '0'));
         begin
            Add_String (Info,
               "<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?>" &
               "<styleSheet xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"">" &
               "<numFmts count=""1""><numFmt numFmtId=""164"" formatCode=""" & Fmt_Code & """/></numFmts>" &
               "<fonts count=""1""><font><sz val=""11""/><name val=""Calibri""/></font></fonts>" &
               "<fills count=""2""><fill><patternFill patternType=""none""/></fill>" &
               "<fill><patternFill patternType=""gray125""/></fill></fills>" &
               "<borders count=""1""><border><left/><right/><top/><bottom/><diagonal/></border></borders>" &
               "<cellStyleXfs count=""1""><xf numFmtId=""0"" fontId=""0"" fillId=""0"" borderId=""0""/></cellStyleXfs>" &
               "<cellXfs count=""2"">" &
               "<xf numFmtId=""0"" fontId=""0"" fillId=""0"" borderId=""0"" xfId=""0""/>" &
               "<xf numFmtId=""164"" fontId=""0"" fillId=""0"" borderId=""0"" xfId=""0"" applyNumberFormat=""1""/>" &
               "</cellXfs>" &
               "</styleSheet>",
               "xl/styles.xml");
         end;
      end if;
```

- [ ] **Step 6: Numeric `<c>` — round-trip `<v>` + optional `s="1"`** — replace the numeric `else` branch at ooxml.adb:600-604:

```ada
                        else
                           declare
                              Sattr : constant String :=
                                 (if Decimals >= 0 then " s=""1""" else "");
                           begin
                              Append (S1,
                                 "<c r=""" & Ref & """" & Sattr & "><v>" &
                                 SData_Core.Values.Image_Round_Trip (V.Num_Val) &
                                 "</v></c>");
                           end;
                        end if;
```

- [ ] **Step 7: Run to verify it passes**

Run: `cd ~/Develop/sdata-core && alr build && cd ~/Develop/sdata && make check 2>&1 | grep -E "FAIL: OOXML|OOXML stored"`
Expected: `OOXML stored value stays full precision` PASSes; no OOXML `FAIL:`.

- [ ] **Step 8: Commit**

```bash
cd ~/Develop/sdata-core
git add src/sdata_core-file_io-ooxml.adb
git commit -m "feat(ooxml): round-trip <v> + styles.xml fixed-decimals numFmt"
cd ~/Develop/sdata && git add tests/file_io_unit_test.adb
git commit -m "test(file_io): OOXML stored value stays full precision"
```

## Task 5: `Execute_SAVE` `Decimals` param + Runtime state + flush wiring

**Files:**
- Modify: `~/Develop/sdata-core/src/sdata_core-config-runtime.ads` (getter + state var), `sdata_core-config-runtime.adb` (getter body + reset)
- Modify: `~/Develop/sdata-core/src/sdata_core-config-runtime-internal.ads` (setter spec), `sdata_core-config-runtime-internal.adb` (setter body)
- Modify: `~/Develop/sdata-core/src/sdata_core-commands.ads:92-98` (`Execute_SAVE` spec) and `sdata_core-commands.adb:404-436` (body) and `:280-313` (`Flush_Pending_Save`)
- Test: `~/Develop/sdata-core/tests/commands_tests.adb`

**Interfaces:**
- Produces: `Execute_SAVE (…; Decimals : Integer := -1)`; `Runtime.Save_Decimals return Integer`; `Runtime.Internal.Set_Save_Decimals (Value : Integer)`.

- [ ] **Step 1: Write the failing test** — append in `~/Develop/sdata-core/tests/commands_tests.adb` (follow that file's existing assert idiom; it `with`s `SData_Core.Config`):

```ada
   --  Set_Save_Decimals round-trips through the Runtime getter.
   SData_Core.Config.Runtime.Internal.Set_Save_Decimals (2);
   Assert (SData_Core.Config.Runtime.Save_Decimals = 2, "Save_Decimals set to 2");
   SData_Core.Config.Runtime.Internal.Set_Save_Decimals (-1);
   Assert (SData_Core.Config.Runtime.Save_Decimals = -1, "Save_Decimals reset to -1");
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd ~/Develop/sdata-core && gprbuild -q -p -P tests/sdata_core_tests.gpr 2>&1 | head`
Expected: compile FAIL — `Save_Decimals`/`Set_Save_Decimals` undefined.

- [ ] **Step 3: Runtime getter + state** — in `sdata_core-config-runtime.ads`, add the getter spec alongside the others (after line 96):

```ada
   function Save_Decimals    return Integer;
```

and the private state variable in the private part (after the `Save_Charset_Len_Value` block, ~line 180):

```ada
   Save_Decimals_Value    : Integer := -1;   --  -1 = no /DECIMALS given
```

In `sdata_core-config-runtime.adb`, add the expression body (after line 53):

```ada
   function Save_Decimals    return Integer is (Save_Decimals_Value);
```

and reset it in the reset block (after the `Save_Charset_Len_Value := 0;` line, ~100):

```ada
      Save_Decimals_Value       := -1;
```

- [ ] **Step 4: Internal setter** — in `sdata_core-config-runtime-internal.ads` add (after line 32):

```ada
   procedure Set_Save_Decimals (Value : Integer);
```

and in `sdata_core-config-runtime-internal.adb` add the body:

```ada
   procedure Set_Save_Decimals (Value : Integer) is
   begin
      Save_Decimals_Value := Value;
   end Set_Save_Decimals;
```

- [ ] **Step 5: Run the Runtime test to verify it passes**

Run: `cd ~/Develop/sdata-core && gprbuild -q -p -P tests/sdata_core_tests.gpr && tests/bin/commands_tests`
Expected: the two new asserts PASS.

- [ ] **Step 6: `Execute_SAVE` param + stash** — in `sdata_core-commands.ads:92-98` add `Decimals : Integer := -1` as the last parameter. In `sdata_core-commands.adb`, mirror it on the body signature (404-411) and add, inside the `declare … begin` block after `Set_Save_Charset (…)` (before the `end;`):

```ada
         SData_Core.Config.Runtime.Internal.Set_Save_Decimals (Decimals);
```

- [ ] **Step 7: `Flush_Pending_Save` passes it through** — in `sdata_core-commands.adb`, add the argument to the `Open_Output` call (after the `Save_Charset (…)` argument):

```ada
             SData_Core.Config.Runtime.Save_Charset
                (1 .. SData_Core.Config.Runtime.Save_Charset_Len),
             SData_Core.Config.Runtime.Save_Decimals);
```

- [ ] **Step 8: Regenerate API reference + build**

Run:
```bash
cd ~/Develop/sdata-core && scripts/gen-reference.sh && alr build
```
Expected: builds clean; `docs/api/reference.html` regenerated (now reflects the new public `Execute_SAVE`/`Open_Output`/`Runtime.Save_Decimals`).

- [ ] **Step 9: Commit**

```bash
cd ~/Develop/sdata-core
git add src/sdata_core-config-runtime.ads src/sdata_core-config-runtime.adb \
        src/sdata_core-config-runtime-internal.ads src/sdata_core-config-runtime-internal.adb \
        src/sdata_core-commands.ads src/sdata_core-commands.adb \
        tests/commands_tests.adb docs/api/reference.html
git commit -m "feat(commands): Execute_SAVE Decimals param + Runtime save-decimals state"
```

## Task 6: sdata-core version bump

**Files:** Modify `~/Develop/sdata-core/alire.toml:3`.

- [ ] **Step 1: Bump the version**

Edit `alire.toml` line 3: `version = "0.1.26"` → `version = "0.1.27"`.

- [ ] **Step 2: Verify full sdata-core suite**

Run: `cd ~/Develop/sdata-core && alr build && tests/run-tests.sh`
Expected: `==> All test drivers passed.`

- [ ] **Step 3: Commit + push branch + open PR**

```bash
cd ~/Develop/sdata-core
git add alire.toml && git commit -m "chore: bump sdata-core 0.1.26 -> 0.1.27 (SAVE /DECIMALS support)"
git push -u origin add-save-decimals
gh pr create --title "SAVE /DECIMALS: renderers, writer plumbing, round-trip precision (v0.1.27)" \
   --body "Additive Execute_SAVE/Open_Output Decimals param; round-trip + fixed-decimals renderers; CSV/ODF/OOXML writers. See sdata doc/specs/2026-07-09-save-decimals-design.md. Merges before the sdata PR."
```

> **Do not merge yet.** Return here after Phase B is green locally so both PRs can be merged in order (Task 12).

---

# PHASE B — sdata (branch `add-save-decimals`, PR, merge after sdata-core)

```bash
cd ~/Develop/sdata && git checkout -b add-save-decimals
```

All Phase B work builds against the **local** sdata-core branch via the path pin, so `make check` validates end to end before sdata-core is merged.

## Task 7: AST fields for `DECIMALS`

**Files:** Modify `~/Develop/sdata/src/ast/sdata-ast.ads` — `Spec_Options` (59-83) and `Stmt_SAVE` variant (214-250).

**Interfaces:**
- Produces: `Spec_Options.Decimals_Specified : Boolean`, `Spec_Options.Decimals_Val : Natural`; same two on the `Stmt_SAVE` flat fields.

- [ ] **Step 1: Add to `Spec_Options`** — after the `DLM_Len` field (line 70):

```ada
      Decimals_Specified : Boolean := False;   --  SAVE only
      Decimals_Val       : Natural := 0;
```

- [ ] **Step 2: Add to the `Stmt_SAVE` flat fields** — after `DLM_Len` (line 233):

```ada
            Decimals_Specified : Boolean := False;
            Decimals_Val       : Natural := 0;
```

- [ ] **Step 3: Build to verify it compiles**

Run: `cd ~/Develop/sdata && alr build 2>&1 | tail -3`
Expected: builds clean (fields are unused so far).

- [ ] **Step 4: Commit**

```bash
cd ~/Develop/sdata && git add src/ast/sdata-ast.ads
git commit -m "feat(ast): DECIMALS fields on Spec_Options and Stmt_SAVE"
```

## Task 8: Parser — `DECIMALS` (paren + slash) with validation + back-compat copy

**Files:** Modify `~/Develop/sdata/src/parser/sdata-parser.adb` — paren chain (before the `else` at ~919), slash chain (~1046), back-compat copy (1633-1662). Test: `~/Develop/sdata/tests/interpreter_unit_test.adb`.

**Interfaces:**
- Consumes: `Spec_Options.Decimals_*` (Task 7). `Peek_Next_Token`, `Get_Next_Token`, `Token_Minus`, `Put_Line_Error` are already in scope in this unit.

- [ ] **Step 1: Write the failing parser test** — append in `~/Develop/sdata/tests/interpreter_unit_test.adb` (follow its existing `Parse`/assert idiom; it `with`s `SData.Parser`, `SData.AST`). Parse a single-target SAVE and assert the flat fields:

```ada
   declare
      Prog : SData.AST.Program_Access :=
         SData.Parser.Parse_String ("SAVE ""x.csv"" / DECIMALS=3" & ASCII.LF);
      St   : constant SData.AST.Statement_Access := Prog.First_Element;  --  adapt to the file's accessor
   begin
      Assert (St.Decimals_Specified, "DECIMALS parsed / specified");
      Assert (St.Decimals_Val = 3,   "DECIMALS value = 3");
      SData.AST.Free_Program (Prog);
   end;
```

> If the file exposes a different parse entry point (e.g. a `Parse_One` helper), use it; the assertion targets are `St.Decimals_Specified` / `St.Decimals_Val`.

- [ ] **Step 2: Run to verify it fails**

Run: `cd ~/Develop/sdata && make check 2>&1 | grep -E "FAIL|DECIMALS"`
Expected: FAIL — `Decimals_Specified` is `False` (parser doesn't handle the flag yet).

- [ ] **Step 3: Paren form** — in `Parse_Spec_Options`, add before the final `else` (parser.adb:919):

```ada
                  elsif Key_Up = "DECIMALS" then
                     declare
                        Peek : constant Token := Peek_Next_Token (Ctx.Lex_Ctx);
                     begin
                        if Peek.Kind = Token_Minus then
                           Put_Line_Error
                             ("Error: /DECIMALS= requires a non-negative integer");
                           declare
                              D1 : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                              D2 : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                              pragma Unreferenced (D1, D2);
                           begin null; end;
                        else
                           declare
                              Val_Tok : constant Token :=
                                 Get_Next_Token (Ctx.Lex_Ctx);
                           begin
                              Opts.Decimals_Val :=
                                 Natural'Value (Val_Tok.Text (1 .. Val_Tok.Length));
                              Opts.Decimals_Specified := True;
                           exception
                              when Constraint_Error =>
                                 Put_Line_Error
                                   ("Error: /DECIMALS= requires a non-negative integer");
                           end;
                        end if;
                     end;
```

- [ ] **Step 4: Slash form** — in `Apply_Legacy_Slash_Option`, add a branch in the `elsif` chain (after the `DLM` branch, ~parser.adb:1053). `Val_Tok` is already read at the top of this procedure; a negative arrives as `Val_Tok.Kind = Token_Minus`:

```ada
            elsif Flag_Name = "DECIMALS" then
               if Val_Tok.Kind = Token_Minus then
                  Put_Line_Error
                    ("Error: /DECIMALS= requires a non-negative integer");
                  declare
                     D : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                     pragma Unreferenced (D);
                  begin null; end;
               else
                  begin
                     Opts.Decimals_Val :=
                        Natural'Value (Val_Tok.Text (1 .. Val_Tok.Length));
                     Opts.Decimals_Specified := True;
                  exception
                     when Constraint_Error =>
                        Put_Line_Error
                          ("Error: /DECIMALS= requires a non-negative integer");
                  end;
               end if;
```

- [ ] **Step 5: Back-compat copy** — in the single-target block (parser.adb:1653-1655, after the `DLM_Len`/`DLM_Path` copy):

```ada
               Stmt.Decimals_Specified := Spec.Opts.Decimals_Specified;
               Stmt.Decimals_Val       := Spec.Opts.Decimals_Val;
```

- [ ] **Step 6: Run to verify it passes**

Run: `cd ~/Develop/sdata && make check 2>&1 | grep -E "FAIL|DECIMALS (parsed|value)"`
Expected: both new asserts PASS.

- [ ] **Step 7: Commit**

```bash
cd ~/Develop/sdata && git add src/parser/sdata-parser.adb tests/interpreter_unit_test.adb
git commit -m "feat(parser): SAVE /DECIMALS (paren + slash) with non-negative validation"
```

## Task 9: Interpreter — thread `Decimals` at both SAVE dispatch paths

**Files:** Modify `~/Develop/sdata/src/sdata-interpreter-execute_declarative.adb:549-579` (legacy single-target) and `~/Develop/sdata/src/sdata-interpreter.adb:1765-1852` (multi-target `Commit_Step`).

**Interfaces:**
- Consumes: `Stmt.Decimals_*`; `T.Opts.Decimals_*` (flows via `T.Opts := Spec.Opts`); `Execute_SAVE (…; Decimals)`; `Open_Output (…; Decimals)`.

- [ ] **Step 1: Legacy single-target** — in `Legacy_Execute_SAVE`, add an effective value after `Eff_Fmt` (execute_declarative.adb:571):

```ada
               Eff_Decimals : constant Integer :=
                  (if Stmt.Decimals_Specified then Stmt.Decimals_Val else -1);
```

and add the argument to the `Execute_SAVE` call (after `Charset => Eff_Charset`):

```ada
                  Charset      => Eff_Charset,
                  Decimals     => Eff_Decimals);
```

- [ ] **Step 2: Multi-target** — in `Commit_Step` (interpreter.adb, in the `for B of Target_Buffers` declare block after `Sheet`), add:

```ada
                  Eff_Decimals : constant Integer :=
                     (if T.Opts.Decimals_Specified then T.Opts.Decimals_Val
                      else -1);
```

and add the argument to the `Open_Output` call (interpreter.adb:1836-1843, after `Charset => Eff_Charset`):

```ada
                        Charset         => Eff_Charset,
                        Decimals        => Eff_Decimals);
```

- [ ] **Step 3: Build + smoke test**

Run:
```bash
cd ~/Develop/sdata && alr build && \
printf 'USE "mock"\nSAVE "tests/data/smoke_dec.csv" / DECIMALS=2\nRUN\nSYSTEM "cat tests/data/smoke_dec.csv"\nSYSTEM "rm -f tests/data/smoke_dec.csv"\nQUIT\n' > /tmp/smoke.cmd && ./bin/sdata /tmp/smoke.cmd
```
Expected: the catted CSV shows the SALARY column rounded/trimmed to ≤2 decimals (e.g. `50000` not `50000.00000`).

- [ ] **Step 4: Commit**

```bash
cd ~/Develop/sdata
git add src/sdata-interpreter-execute_declarative.adb src/sdata-interpreter.adb
git commit -m "feat(interpreter): thread SAVE /DECIMALS to both dispatch paths"
```

## Task 10: Integration tests + regenerate affected fixtures

**Files:** Create several `~/Develop/sdata/tests/*.cmd` + `tests/expected/*.out` (+ `.exitcode` where noted). Regenerate any existing fixture that dumps a saved file.

**Interfaces:** Consumes the full feature (Tasks 1-9).

- [ ] **Step 1: CSV round-trip + `/DECIMALS` exact-text test** — create `tests/decimals_csv.cmd`:

```
-- SAVE /DECIMALS on CSV: round + trim; default save round-trips.
USE "tests/data/precision_src.csv"
SAVE "tests/data/dc_default.csv"
RUN
SYSTEM "echo === default ==="
SYSTEM "cat tests/data/dc_default.csv"
USE "tests/data/precision_src.csv"
SAVE "tests/data/dc_2.csv" / DECIMALS=2
RUN
SYSTEM "echo === decimals=2 ==="
SYSTEM "cat tests/data/dc_2.csv"
USE "tests/data/precision_src.csv"
SAVE "tests/data/dc_0.csv" / DECIMALS=0
RUN
SYSTEM "echo === decimals=0 ==="
SYSTEM "cat tests/data/dc_0.csv"
SYSTEM "rm -f tests/data/dc_default.csv tests/data/dc_2.csv tests/data/dc_0.csv"
QUIT
```

Generate + verify + save expected:
```bash
cd ~/Develop/sdata && ./bin/sdata tests/decimals_csv.cmd | tee tests/expected/decimals_csv.out
```
Verify by eye: `=== default ===` shows `123456.79`/`3.14159`/`0.5` (round-trip, trimmed); `=== decimals=2 ===` shows `123456.79`/`3.14`/`0.5`; `=== decimals=0 ===` shows `123457`/`3`/`0` (or `1` — confirm rounding of 0.5). Then commit the `.out` as-is.

- [ ] **Step 2: Per-target + multi-format test** — create `tests/decimals_per_target.cmd`:

```
-- Per-target DECIMALS; a spreadsheet target keeps full precision.
USE "tests/data/precision_src.csv"
SAVE "tests/data/pt_a.csv" (DECIMALS=1), "tests/data/pt_b.csv" (DECIMALS=3)
RUN
SYSTEM "echo === a (1dp) ==="
SYSTEM "cat tests/data/pt_a.csv"
SYSTEM "echo === b (3dp) ==="
SYSTEM "cat tests/data/pt_b.csv"
SYSTEM "rm -f tests/data/pt_a.csv tests/data/pt_b.csv"
QUIT
```

Generate: `./bin/sdata tests/decimals_per_target.cmd | tee tests/expected/decimals_per_target.out` and verify differing precision per target; commit.

- [ ] **Step 3: Negative-N parse error** — create `tests/decimals_negative.cmd`:

```
USE "tests/data/precision_src.csv"
SAVE "tests/data/neg.csv" / DECIMALS=-1
RUN
SYSTEM "rm -f tests/data/neg.csv"
QUIT
```

Generate the expected output and capture the real exit code:
```bash
cd ~/Develop/sdata
./bin/sdata tests/decimals_negative.cmd > tests/expected/decimals_negative.out 2>&1; echo "exit=$?"
```
Confirm the output contains `Error: /DECIMALS= requires a non-negative integer`. If `exit` was non-zero, write it: `printf '%s' "<code>" > tests/decimals_negative.exitcode` (omit the file if exit was 0). Commit the `.out` (+ `.exitcode` if created).

- [ ] **Step 4: Spreadsheet number-format presence** — create `tests/decimals_xlsx_style.cmd` (requires `unzip`, present on CI Ubuntu):

```
USE "tests/data/precision_src.csv"
SAVE "tests/data/style.xlsx" / DECIMALS=2
RUN
SYSTEM "unzip -p tests/data/style.xlsx xl/styles.xml | grep -o 'formatCode=\"0.00\"'"
SYSTEM "unzip -p tests/data/style.xlsx xl/worksheets/sheet1.xml | grep -o 's=\"1\"' | head -1"
SYSTEM "rm -f tests/data/style.xlsx"
QUIT
```

Generate: `./bin/sdata tests/decimals_xlsx_style.cmd | tee tests/expected/decimals_xlsx_style.out`; verify it prints `formatCode="0.00"` and `s="1"`; commit.

- [ ] **Step 5: Regenerate existing fixtures that dump saved files** — find them and update only the genuinely-changed ones:

```bash
cd ~/Develop/sdata
grep -rln 'SYSTEM .*cat\|SYSTEM .*unzip' tests/*.cmd
make check 2>&1 | grep -A3 "FAIL" | head -40
```
For each failing integration test whose diff is purely the new round-trip float rendering in a dumped file, regenerate its expected output:
```bash
base=<name>; ./bin/sdata tests/$base.cmd > tests/expected/$base.out 2>&1
```
Inspect each diff (`git diff tests/expected/$base.out`) to confirm the change is only float-rendering (e.g. `1.50000E+02` → `150`), not a regression, before staging.

- [ ] **Step 6: Full check**

Run: `cd ~/Develop/sdata && make check`
Expected: all unit binaries pass; all integration tests pass (0 failures).

- [ ] **Step 7: Commit**

```bash
cd ~/Develop/sdata
git add tests/decimals_csv.cmd tests/decimals_per_target.cmd tests/decimals_negative.cmd \
        tests/decimals_xlsx_style.cmd tests/expected/decimals_*.out tests/decimals_negative.exitcode 2>/dev/null
git add -A tests/expected
git commit -m "test: SAVE /DECIMALS integration + regenerate round-trip fixtures"
```

## Task 11: User-facing docs — HELP, man page, design.md, ADR-050, architecture

**Files:** `src/sdata-help.adb`, `tests/expected/help_all.out` (+ options snapshots), `man/man1/sdata.1`, `doc/design.md`, `doc/adrs.md`, `doc/architecture.md`.

- [ ] **Step 1: HELP** — in `src/sdata-help.adb:Help_SAVE`, extend the synopsis and Options block. Change the first line to include `[/DECIMALS=N]` and add under Options (after the `/HEADER=val` line):

```ada
      Put_Line ("Command: SAVE ""filename[sheet]"" [/FMT=format] [/HEADER=YES|NO] [/DECIMALS=N]");
```
```ada
      Put_Line ("  /DECIMALS=N  Round floating-point output to N decimal places");
      Put_Line ("               (N >= 0).  CSV: rounds the stored value and trims");
      Put_Line ("               trailing zeros.  ODF/OOXML: keeps full precision and");
      Put_Line ("               applies a fixed N-decimal display format.");
```

- [ ] **Step 2: Regenerate HELP snapshots**

Run:
```bash
cd ~/Develop/sdata && alr build
./bin/sdata -c "HELP /ALL" > tests/expected/help_all.out 2>&1   # use the project's actual HELP-dump invocation
git diff --stat tests/expected/
```
> Use whatever command the repo already uses to produce `help_all.out` (check the `.cmd` that generates it, e.g. `tests/help_all.cmd`). Regenerate any `*_options` / `options_display` snapshot only if it lists SAVE options.

- [ ] **Step 3: Man page** — in `man/man1/sdata.1`, add `/DECIMALS=N` to the SAVE entry (LANGUAGE OVERVIEW / command reference), describing the CSV-trims vs spreadsheet-fixed behavior in one or two lines matching the surrounding groff style.

- [ ] **Step 4: design.md** — in `doc/design.md`, in the SAVE command reference table, document `/DECIMALS=N`, the CSV-trims-zeros vs spreadsheet-fixed asymmetry, and a note that saved floats now use round-trip precision (still single-precision per the current data model). Cross-reference: this is the authoritative language spec.

- [ ] **Step 5: ADR-050** — append to `doc/adrs.md` (next contiguous number after ADR-049) an ADR titled "SAVE /DECIMALS and round-trip float output", recording: per-format semantics (CSV value-rounding vs spreadsheet display-format), the round-trip-precision bugfix and its byte-change to default output, the defaulted-parameter plumbing for contract safety, and the deferral of platform-native (double) precision to the planned design-vs-code audit.

- [ ] **Step 6: architecture.md** — add a sentence to `doc/architecture.md` noting the shared `Image_Round_Trip`/`Image_Fixed_Decimals` renderers in `SData_Core.Values` and the spreadsheet number-format style emission.

- [ ] **Step 7: Verify + commit**

Run: `cd ~/Develop/sdata && make check 2>&1 | tail -5`
Expected: green (help_all snapshot now matches).

```bash
git add src/sdata-help.adb tests/expected/help_all.out man/man1/sdata.1 \
        doc/design.md doc/adrs.md doc/architecture.md
git add tests/expected 2>/dev/null
git commit -m "docs: SAVE /DECIMALS in HELP, man, design.md, ADR-050, architecture"
```

## Task 12: Release — versions, floors, cross-crate gate, merge

**Files:** `sdata` (via `scripts/bump-version.sh` + `alire.toml` floor), `data-vandal/alire.toml` (+ regenerated fixtures), `sdata-core/.github/workflows/consumer-tests.yml`.

- [ ] **Step 1: Bump sdata + floor**

```bash
cd ~/Develop/sdata
scripts/bump-version.sh 0.14.0 "SAVE /DECIMALS=N + round-trip float output"
```
Then edit `alire.toml`: `sdata_core = "^0.1.26"` → `sdata_core = "^0.1.27"`.

- [ ] **Step 2: data-vandal floor + fixtures**

```bash
cd ~/Develop/data-vandal
# edit alire.toml: sdata_core = "^0.1.27"
make check 2>&1 | tail -20
```
If data-vandal has expected-output fixtures that dump saved floats, regenerate the genuinely-changed ones (same round-trip cause), inspect each diff, and commit. Expected end state: `make check` green (143 integration tests).

- [ ] **Step 3: Three-way cross-crate gate**

```bash
cd ~/Develop/sdata-core && alr build && \
cd ~/Develop/sdata && make check && \
cd ~/Develop/data-vandal && make check
```
Expected: all three green.

- [ ] **Step 4: Commit sdata release + push + PR**

```bash
cd ~/Develop/sdata
git add -A && git commit -m "chore: bump sdata 0.13.3 -> 0.14.0; floor ^0.1.27 (SAVE /DECIMALS)"
git push -u origin add-save-decimals
gh pr create --title "SAVE /DECIMALS=N (v0.14.0)" \
   --body "Adds SAVE /DECIMALS=N and round-trip float output. Depends on sdata-core v0.1.27 (merge that PR first). Spec: doc/specs/2026-07-09-save-decimals-design.md."
```

- [ ] **Step 5: Merge in order + tag**

```bash
# 1) Merge the sdata-core PR (Task 6) first; then:
cd ~/Develop/sdata-core && git checkout main && git pull
git tag -a v0.1.27 -m "Version 0.1.27" && git push origin v0.1.27
# 2) Bump consumer-tests.yml ref -> v0.14.0 (new sdata tag) via a follow-up sdata-core PR or same branch, then:
# 3) Merge the sdata PR; then:
cd ~/Develop/sdata && git checkout main && git pull
git tag -a v0.14.0 -m "Version 0.14.0" && git push origin v0.14.0
# 4) data-vandal floor bump -> its own PR/commit.
```

- [ ] **Step 6: Final verification**

Run: confirm the merged CI is green on both repos (`gh pr checks` before merge; `gh run list` after). Update `.ssd/current.yml` archived entry for `save-decimals` with the landed summary.

---

## Self-Review

**Spec coverage:** §3.1 round-trip default → Tasks 2/3/4 (`Image_Round_Trip` in all writers) + Task 1. §3.2 `/DECIMALS` semantics → Task 8 (parse) + Tasks 2 (CSV) / 3 (ODF) / 4 (OOXML). §3.3 asymmetry/rationale → docs Task 11. §3.4 unaffected cells → writers leave integer/string/missing/Inf branches untouched (Tasks 2-4). §4 both syntax forms + validation → Task 8. §5.2 additive plumbing → Tasks 2/5. §5.3 renderers → Task 1. §5.4/5.5 styles → Tasks 3/4. §6 release → Tasks 6/12. §7 docs → Task 11. §8 tests → Tasks 1-5 (unit) + Task 10 (integration). §9 deferral → ADR-050 (Task 11). §10 notation → resolved to shortest-round-trip fixed-preferred (Task 1).

**Placeholder scan:** two intentional "adapt to the file's accessor" notes (Task 8 Step 1, Task 11 Step 2) point at repo-specific entry points the implementer confirms by reading the file; the assertion targets and regenerate commands are concrete. No `TODO`/`TBD`.

**Type consistency:** `Image_Round_Trip (Float) return String` and `Image_Fixed_Decimals (Float; Natural) return String` used identically in Tasks 1-4. `Decimals : Integer := -1` sentinel consistent across `Open_Output`, `Execute_SAVE`, all three writers, `Runtime.Save_Decimals`, and both interpreter paths. AST `Decimals_Specified : Boolean` / `Decimals_Val : Natural` consistent across ast/parser/interpreter.
