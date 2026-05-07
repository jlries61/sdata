# Parse_CSV Internal Decomposition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose the 392-line `Parse_CSV` monolith in `src/sdata-file_io.adb` into four clearly-named internal passes so each concern is independently readable.

**Architecture:** Three body-level procedures (`Split_Into_Lines`, `Load_As_UTF16`, `Detect_And_Load`) and two supporting type declarations are lifted out of their current nested scopes. The 100-line `Load_Columns_And_Data` local procedure is split into `Infer_Column_Types` + `Load_Data_Rows`. No new files, no spec changes, no observable behaviour change. All 125 snapshot tests must continue to pass after every commit.

**Tech Stack:** Ada 2012, GNAT 15, `alr build`, `make check`.

---

## File Structure

Only `src/sdata-file_io.adb` changes.

```
src/sdata-file_io.adb
  package body SData.File_IO
    [NEW] Max_CSV_Cols : constant := 4_096           ← body-level constant
    [NEW] package Line_Vecs  (moved from Parse_CSV)  ← body-level instantiation
    [NEW] type Name_Array    is array (1..Max_CSV_Cols) of String_Access
    [NEW] type Col_Type_Array is array (1..Max_CSV_Cols) of Column_Type
    [NEW] procedure Split_Into_Lines  (moved from Parse_CSV; +All_Lines param)
    [NEW] procedure Load_As_UTF16     (moved from nested declare block; +3 params)
    [NEW] procedure Detect_And_Load   (moved from nested declare block; +3 params)
    procedure Open_Output  [unchanged]
    procedure Parse_CSV
      [REMOVED] package Line_Vecs (was line 296)
      [REMOVED] procedure Split_Into_Lines (was lines 316-338)
      [REMOVED] procedure Load_Columns_And_Data (was lines 406-507)
      [NEW local] N_Cols, Col_Names, Col_Types shared variables
      [NEW local] procedure Infer_Column_Types (first half of old Load_Columns_And_Data)
      [NEW local] procedure Load_Data_Rows     (second half of old Load_Columns_And_Data)
      [SIMPLIFIED] charset dispatch declare block (was lines 509-593)
```

---

## Task 1: Verify baseline

**Files:** none

- [ ] **Step 1: Confirm all tests pass before any changes**

```bash
alr exec -- make check
```

Expected: `All 125 tests passed.`

If any test fails, stop — do not proceed until the baseline is clean.

---

## Task 2: Move `Line_Vecs` to body level; add type declarations

**Files:**
- Modify: `src/sdata-file_io.adb:281-296`

The `package Line_Vecs` instantiation currently lives inside `Parse_CSV`'s declarative region (line 296). Moving it to body level is a prerequisite for body-level procedures to reference `Line_Vecs.Vector`. We add the two fixed-array types and the constant here too.

- [ ] **Step 1: Add body-level declarations after `end Open_Output;` (line 281)**

Insert the following block between `end Open_Output;` and the `-- Parse_CSV --` banner comment:

```ada
   ----------------------
   -- CSV parse helpers --
   ----------------------

   --  Practical upper bound on columns for type-inference buffers.
   Max_CSV_Cols : constant := 4_096;

   package Line_Vecs is new Ada.Containers.Vectors (Positive, Unbounded_String);

   type Name_Array     is array (1 .. Max_CSV_Cols) of String_Access;
   type Col_Type_Array is array (1 .. Max_CSV_Cols) of Column_Type;

```

- [ ] **Step 2: Remove `package Line_Vecs` from Parse_CSV's declarative region**

Delete this line from Parse_CSV's local declarations (currently line 296):

```ada
      package Line_Vecs is new Ada.Containers.Vectors (Positive, Unbounded_String);
```

The variable `All_Lines : Line_Vecs.Vector;` on line 297 stays — it references the now-body-level `Line_Vecs`.

- [ ] **Step 3: Build**

```bash
alr build 2>&1 | tail -5
```

Expected: `Success: Build finished successfully`

- [ ] **Step 4: Run tests**

```bash
alr exec -- make check
```

Expected: `All 125 tests passed.`

- [ ] **Step 5: Commit**

```bash
git add src/sdata-file_io.adb
git commit -m "Refactor: move Line_Vecs to body level; add Name_Array/Col_Type_Array types"
```

---

## Task 3: Lift `Split_Into_Lines` to body level

**Files:**
- Modify: `src/sdata-file_io.adb`

`Split_Into_Lines` currently closes over `All_Lines` from `Parse_CSV`. Moving it to body level makes it available to `Load_As_UTF16` (which will be lifted in Task 4). The signature gains an explicit `All_Lines : in out Line_Vecs.Vector` parameter.

- [ ] **Step 1: Add body-level `Split_Into_Lines` after the type declarations (after `Col_Type_Array`)**

```ada
   procedure Split_Into_Lines (S : String; All_Lines : in out Line_Vecs.Vector) is
      Start : Natural := S'First;
      I     : Natural := S'First;
   begin
      while I <= S'Last loop
         if S (I) = ASCII.LF then
            declare
               E : Natural := I - 1;
            begin
               if E >= Start and then S (E) = ASCII.CR then
                  E := E - 1;
               end if;
               All_Lines.Append (To_Unbounded_String
                  (if E >= Start then S (Start .. E) else ""));
            end;
            Start := I + 1;
         end if;
         I := I + 1;
      end loop;
      if Start <= S'Last then
         All_Lines.Append (To_Unbounded_String (S (Start .. S'Last)));
      end if;
   end Split_Into_Lines;

```

- [ ] **Step 2: Remove local `Split_Into_Lines` from Parse_CSV's declarative region**

Delete lines 316–338 (the local `procedure Split_Into_Lines` body). Keep all surrounding code intact.

- [ ] **Step 3: Update the call inside the nested `Load_As_UTF16`**

The nested `Load_As_UTF16` (still inside Parse_CSV's charset `declare` block) calls `Split_Into_Lines` with one argument. Update it to pass `All_Lines` explicitly:

Old:
```ada
               Split_Into_Lines (UTF8 (Start_At .. UTF8'Last));
```

New:
```ada
               Split_Into_Lines (UTF8 (Start_At .. UTF8'Last), All_Lines);
```

- [ ] **Step 4: Build**

```bash
alr build 2>&1 | tail -5
```

Expected: `Success: Build finished successfully`

- [ ] **Step 5: Run tests**

```bash
alr exec -- make check
```

Expected: `All 125 tests passed.`

- [ ] **Step 6: Commit**

```bash
git add src/sdata-file_io.adb
git commit -m "Refactor: lift Split_Into_Lines to body level"
```

---

## Task 4: Lift `Load_As_UTF16` to body level

**Files:**
- Modify: `src/sdata-file_io.adb`

`Load_As_UTF16` is currently nested inside a `declare` block in Parse_CSV's body (lines 515–555). It closes over `File_Name`, `All_Lines`, and `Is_Buffered`. Moving it to body level makes the charset dispatch chain explicit.

- [ ] **Step 1: Add body-level `Load_As_UTF16` after `Split_Into_Lines`**

```ada
   procedure Load_As_UTF16
      (File_Name   : String;
       Scheme      : Ada.Strings.UTF_Encoding.Encoding_Scheme;
       All_Lines   : in out Line_Vecs.Vector;
       Is_Buffered : out Boolean)
   is
      F    : Ada.Streams.Stream_IO.File_Type;
      Sz   : constant Ada.Directories.File_Size :=
         Ada.Directories.Size (File_Name);
      Buf  : Ada.Streams.Stream_Element_Array
         (1 .. Ada.Streams.Stream_Element_Offset (Sz));
      Last : Ada.Streams.Stream_Element_Offset;
      Raw  : String (1 .. Natural (Sz));
   begin
      Is_Buffered := False;
      Ada.Streams.Stream_IO.Open
         (F, Ada.Streams.Stream_IO.In_File, File_Name);
      Ada.Streams.Stream_IO.Read (F, Buf, Last);
      Ada.Streams.Stream_IO.Close (F);
      for I in 1 .. Natural (Last) loop
         Raw (I) :=
            Character'Val (Buf (Ada.Streams.Stream_Element_Offset (I)));
      end loop;
      declare
         UTF8     : constant String :=
            Ada.Strings.UTF_Encoding.Conversions.Convert
               (Raw (1 .. Natural (Last)), Scheme,
                Ada.Strings.UTF_Encoding.UTF_8);
         Start_At : Natural := UTF8'First;
      begin
         if UTF8'Length >= 3
            and then UTF8 (UTF8'First .. UTF8'First + 2) = BOM_8
         then
            Start_At := UTF8'First + 3;
         end if;
         Split_Into_Lines (UTF8 (Start_At .. UTF8'Last), All_Lines);
         Is_Buffered := True;
      end;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (F) then
            Ada.Streams.Stream_IO.Close (F);
         end if;
         raise;
   end Load_As_UTF16;

```

- [ ] **Step 2: Remove nested `Load_As_UTF16` from Parse_CSV's `declare` block**

Delete lines 515–555 (the nested `procedure Load_As_UTF16` from its header to `end Load_As_UTF16;`). Keep `procedure Detect_And_Load` and the surrounding `declare` block intact.

- [ ] **Step 3: Update calls inside the nested `Detect_And_Load`**

The nested `Detect_And_Load` (still inside the `declare` block) calls `Load_As_UTF16` with one argument. Update both calls to the body-level signature:

Old:
```ada
               Load_As_UTF16 (Ada.Strings.UTF_Encoding.UTF_16LE);
```
New:
```ada
               Load_As_UTF16 (File_Name, Ada.Strings.UTF_Encoding.UTF_16LE,
                              All_Lines, Is_Buffered);
```

Old:
```ada
               Load_As_UTF16 (Ada.Strings.UTF_Encoding.UTF_16BE);
```
New:
```ada
               Load_As_UTF16 (File_Name, Ada.Strings.UTF_Encoding.UTF_16BE,
                              All_Lines, Is_Buffered);
```

- [ ] **Step 4: Update direct calls in Parse_CSV's charset dispatch**

In Parse_CSV's body, the two direct calls to `Load_As_UTF16` (before the `Detect_And_Load` call) also need updating:

Old:
```ada
            Load_As_UTF16 (Ada.Strings.UTF_Encoding.UTF_16LE);
```
New:
```ada
            Load_As_UTF16 (File_Name, Ada.Strings.UTF_Encoding.UTF_16LE,
                           All_Lines, Is_Buffered);
```

Old:
```ada
            Load_As_UTF16 (Ada.Strings.UTF_Encoding.UTF_16BE);
```
New:
```ada
            Load_As_UTF16 (File_Name, Ada.Strings.UTF_Encoding.UTF_16BE,
                           All_Lines, Is_Buffered);
```

- [ ] **Step 5: Build**

```bash
alr build 2>&1 | tail -5
```

Expected: `Success: Build finished successfully`

- [ ] **Step 6: Run tests**

```bash
alr exec -- make check
```

Expected: `All 125 tests passed.`

- [ ] **Step 7: Commit**

```bash
git add src/sdata-file_io.adb
git commit -m "Refactor: lift Load_As_UTF16 to body level"
```

---

## Task 5: Lift `Detect_And_Load` to body level; simplify charset section

**Files:**
- Modify: `src/sdata-file_io.adb`

`Detect_And_Load` is the last procedure still nested in the `declare` block. Once it moves to body level, the entire charset `declare` block (currently lines 509–593) collapses to a clean 13-line `declare` block with no nested procedures.

- [ ] **Step 1: Add body-level `Detect_And_Load` after `Load_As_UTF16`**

```ada
   procedure Detect_And_Load
      (File_Name   : String;
       All_Lines   : in out Line_Vecs.Vector;
       Is_Buffered : out Boolean)
   is
      F      : Ada.Streams.Stream_IO.File_Type;
      Detect : Ada.Streams.Stream_Element_Array (1 .. 4);
      Last   : Ada.Streams.Stream_Element_Offset;
   begin
      Is_Buffered := False;
      Ada.Streams.Stream_IO.Open
         (F, Ada.Streams.Stream_IO.In_File, File_Name);
      Ada.Streams.Stream_IO.Read (F, Detect, Last);
      Ada.Streams.Stream_IO.Close (F);
      if Last >= 2
         and then Detect (1) = 16#FF# and then Detect (2) = 16#FE#
      then
         Load_As_UTF16 (File_Name, Ada.Strings.UTF_Encoding.UTF_16LE,
                        All_Lines, Is_Buffered);
      elsif Last >= 2
         and then Detect (1) = 16#FE# and then Detect (2) = 16#FF#
      then
         Load_As_UTF16 (File_Name, Ada.Strings.UTF_Encoding.UTF_16BE,
                        All_Lines, Is_Buffered);
      end if;
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (F) then
            Ada.Streams.Stream_IO.Close (F);
         end if;
         raise;
   end Detect_And_Load;

```

- [ ] **Step 2: Replace the entire charset `declare` block in Parse_CSV's body**

The current block (lines 509–593) is a large `declare` block containing the nested `Detect_And_Load` procedure, plus the charset dispatch logic. Replace the entire block with this compact form:

```ada
      --  Pass 1: resolve charset; optionally transcode and buffer whole file.
      declare
         UC : constant String := To_Upper (Trim (Charset, Ada.Strings.Both));
      begin
         if UC = "UTF-16" or else UC = "UTF-16LE" then
            Load_As_UTF16 (File_Name, Ada.Strings.UTF_Encoding.UTF_16LE,
                           All_Lines, Is_Buffered);
         elsif UC = "UTF-16BE" then
            Load_As_UTF16 (File_Name, Ada.Strings.UTF_Encoding.UTF_16BE,
                           All_Lines, Is_Buffered);
         elsif UC = "" or else UC = "AUTO" then
            Detect_And_Load (File_Name, All_Lines, Is_Buffered);
         elsif UC = "ASCII" then
            Needs_ASCII_Chk := True;
         end if;
      end;
```

- [ ] **Step 3: Add a section comment before the header/scan collection block**

Immediately after the charset `declare` block, add:

```ada
      --  Pass 2: open file (non-buffered path); collect header + scan lines.
```

before `if not Is_Buffered then`.

- [ ] **Step 4: Build**

```bash
alr build 2>&1 | tail -5
```

Expected: `Success: Build finished successfully`

- [ ] **Step 5: Run tests**

```bash
alr exec -- make check
```

Expected: `All 125 tests passed.`

- [ ] **Step 6: Commit**

```bash
git add src/sdata-file_io.adb
git commit -m "Refactor: lift Detect_And_Load to body level; simplify charset dispatch"
```

---

## Task 6: Split `Load_Columns_And_Data` into `Infer_Column_Types` + `Load_Data_Rows`

**Files:**
- Modify: `src/sdata-file_io.adb`

`Load_Columns_And_Data` (lines 406–507) mixes type inference with table creation and row streaming. Split it into two named local procedures. Shared state (`N_Cols`, `Col_Names`, `Col_Types`) is declared as closure variables in `Parse_CSV`'s declarative region.

- [ ] **Step 1: Add three closure variables to Parse_CSV's declarative region**

After the `Header_Line : Unbounded_String;` declaration (near the `Scan_Lines`/`Scan_Count` block), add:

```ada
      N_Cols    : Natural         := 0;
      Col_Names : Name_Array     := (others => null);
      Col_Types : Col_Type_Array := (others => Col_Numeric);
```

- [ ] **Step 2: Replace `Load_Columns_And_Data` with `Infer_Column_Types`**

Delete the entire `procedure Load_Columns_And_Data` (lines 406–507). In its place, add `Infer_Column_Types`:

```ada
      --  Pass 3 helper: scan up to NSCAN rows to determine column types and names.
      --  Sets N_Cols, Col_Names(1..N_Cols), Col_Types(1..N_Cols).
      procedure Infer_Column_Types
         (H_Str : String; Names_From_Header : Boolean)
      is
         N_Hdr : Natural;
         H_Idx : constant Field_Array :=
            Split_Indices (H_Str, Delimiter, N_Hdr);
         Col_Determined : array (1 .. N_Hdr) of Boolean := (others => False);
      begin
         N_Cols    := N_Hdr;
         Col_Types := (others => Col_Numeric);
         Col_Names := (others => null);

         --  Columns whose header already ends in "$" are forced character.
         if Names_From_Header then
            for I in 1 .. N_Hdr loop
               declare
                  Raw : constant String :=
                     Trim (H_Str (H_Idx (I).S .. H_Idx (I).E), Ada.Strings.Both);
               begin
                  if Raw'Length > 0 and then Raw (Raw'Last) = '$' then
                     Col_Types (I)      := Col_String;
                     Col_Determined (I) := True;
                  end if;
               end;
            end loop;
         end if;

         --  Scan data rows to determine remaining column types.
         for R in 1 .. Scan_Count loop
            declare
               D_Str : constant String := To_String (Scan_Lines (R));
               N_Fld : Natural;
               D_Idx : constant Field_Array :=
                  Split_Indices (D_Str, Delimiter, N_Fld);
            begin
               for I in 1 .. N_Hdr loop
                  if not Col_Determined (I) and then I <= N_Fld then
                     declare
                        F : constant String :=
                           CSV_Unquote (D_Str (D_Idx (I).S .. D_Idx (I).E));
                     begin
                        if F /= "" and then F /= "." then
                           Col_Types (I) :=
                              (if Is_Numeric_Field (F) then Col_Numeric
                               else Col_String);
                           Col_Determined (I) := True;
                        end if;
                     end;
                  end if;
               end loop;
            end;
         end loop;

         --  Build column names; append "$" to string columns that lack it.
         for I in 1 .. N_Hdr loop
            declare
               Base_Name : constant String :=
                  (if Names_From_Header
                   then Safe_Name
                           (CSV_Unquote (H_Str (H_Idx (I).S .. H_Idx (I).E)),
                            "COL" & Trim (I'Img, Ada.Strings.Both))
                   else "COL" & Trim (I'Img, Ada.Strings.Both));
               Name : constant String :=
                  (if Col_Types (I) = Col_String
                      and then (Base_Name'Length = 0
                                or else Base_Name (Base_Name'Last) /= '$')
                   then Base_Name & "$"
                   else Base_Name);
            begin
               Col_Names (I) := new String'(Name);
            end;
         end loop;
      end Infer_Column_Types;
```

- [ ] **Step 3: Add `Load_Data_Rows` immediately after `Infer_Column_Types`**

```ada
      --  Pass 4 helper: register columns, stream scan lines and remaining file rows.
      procedure Load_Data_Rows is
         Names : String_List (1 .. N_Cols);
      begin
         Clear;
         for I in 1 .. N_Cols loop
            Names (I) := Col_Names (I);
            Add_Column (Col_Names (I).all, Col_Types (I));
         end loop;

         if Has_File_Header and then Scan_Count = 0 then
            SData.IO.Put_Line_Error
               ("Warning: File contains a header but no data records.");
         end if;

         --  Replay buffered scan rows.
         for R in 1 .. Scan_Count loop
            exit when Max_Rows > 0 and then Rows_Written >= Max_Rows;
            Process_Line_Direct (To_String (Scan_Lines (R)), Names);
         end loop;

         --  Stream the remainder of the file.
         if Is_Buffered then
            while All_Lines_Idx < Natural (All_Lines.Length) loop
               exit when Max_Rows > 0 and then Rows_Written >= Max_Rows;
               All_Lines_Idx := All_Lines_Idx + 1;
               Process_Line_Direct (To_String (All_Lines (All_Lines_Idx)), Names);
            end loop;
         else
            while not Ada.Text_IO.End_Of_File (File) loop
               exit when Max_Rows > 0 and then Rows_Written >= Max_Rows;
               Ada.Text_IO.Get_Line (File, Line_Buf.all, Line_Last);
               if Needs_ASCII_Chk then
                  Validate_ASCII (Line_Buf (1 .. Line_Last));
               end if;
               Process_Line_Direct (Line_Buf (1 .. Line_Last), Names);
            end loop;
         end if;

         for I in Names'Range loop Free (Names (I)); end loop;
      end Load_Data_Rows;
```

- [ ] **Step 4: Update Parse_CSV's body to call the two new procedures**

Find the two `Load_Columns_And_Data` calls at the bottom of `Parse_CSV`'s body (currently lines 663–668):

```ada
      if Has_File_Header then
         Load_Columns_And_Data (To_String (Header_Line), Names_From_Header => True);
      elsif Scan_Count > 0 then
         --  No header: synthesise column names from the first data row's field count.
         Load_Columns_And_Data (To_String (Scan_Lines (1)), Names_From_Header => False);
      end if;
```

Replace with:

```ada
      --  Passes 3 + 4: infer column types, create table columns, stream rows.
      if Has_File_Header then
         Infer_Column_Types (To_String (Header_Line), Names_From_Header => True);
         Load_Data_Rows;
      elsif Scan_Count > 0 then
         Infer_Column_Types (To_String (Scan_Lines (1)), Names_From_Header => False);
         Load_Data_Rows;
      end if;
```

- [ ] **Step 5: Build**

```bash
alr build 2>&1 | tail -5
```

Expected: `Success: Build finished successfully`

If GNAT warns about unused variables (e.g., `Col_Names` or `Col_Types` visible before they are used), those are benign — the variables are written by `Infer_Column_Types` and read by `Load_Data_Rows`. Investigate any error.

- [ ] **Step 6: Run tests**

```bash
alr exec -- make check
```

Expected: `All 125 tests passed.`

- [ ] **Step 7: Commit**

```bash
git add src/sdata-file_io.adb
git commit -m "Refactor: split Load_Columns_And_Data into Infer_Column_Types + Load_Data_Rows"
```

---

## Final Verification

- [ ] **Step 1: Confirm the Parse_CSV body is now ~80 lines of orchestration**

```bash
grep -n "procedure Parse_CSV\|end Parse_CSV" src/sdata-file_io.adb
```

Subtract the start line from the end line. The body (from `begin` to `end Parse_CSV`) should be approximately 80 lines. The declarative region (local procedure declarations) is separate.

- [ ] **Step 2: Confirm all 125 tests still pass**

```bash
alr exec -- make check
```

Expected: `All 125 tests passed.`

- [ ] **Step 3: Update the standards review document**

In `doc/SOFTWARE_STANDARDS_REVIEW.md`, mark Priority 3 resolved:

```markdown
| 3 | ~~Decompose `Parse_CSV` into tokenizer + type-inference passes~~ | Code Quality | ~~2–3 days~~ | ~~Grows worse with each format quirk added~~ **Fixed <SHA>** |
```

Replace `<SHA>` with the short SHA of the Task 6 commit.

- [ ] **Step 4: Commit the annotation**

```bash
git add doc/SOFTWARE_STANDARDS_REVIEW.md
git commit -m "Annotate standards review: Priority 3 Parse_CSV decomposition resolved"
```
