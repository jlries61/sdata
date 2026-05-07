# Dynamic Field Array Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all fixed-size column-count arrays (`Field_Array`, `Name_Array`, `Col_Type_Array`) with `Ada.Containers.Vectors`, eliminating the `Max_Fields = 65_536` and `Max_CSV_Cols = 4_096` hard-coded limits so that CSV parsing is bounded only by available memory.

**Architecture:** `Split_Indices` changes from a function returning a fixed `Field_Array` to a procedure taking a `Field_Vectors.Vector` `in out`. The `Col_Names` and `Col_Types` closure variables in `Parse_CSV` become vectors. `Process_Line_Direct` drops its `Names : String_List` parameter and reads `Col_Names` from the enclosing scope. All three changes are mechanically coupled (the `Split_Indices` signature change breaks its callers in `sdata-file_io.adb` until Task 3 is complete), so Tasks 2 and 3 are staged and committed together in Task 3.

**Tech Stack:** Ada 2012 / GNAT, `Ada.Containers.Vectors`, `GNAT.Strings`

---

## Files changed

| File | What changes |
|------|-------------|
| `src/sdata-csv.ads` | Remove `Max_Fields`, `Field_Array`; add `Field_Vectors` package; change `Split_Indices` to a procedure |
| `src/sdata-csv.adb` | Replace `Split_Indices` body |
| `src/sdata-file_io.adb` | Remove `Max_CSV_Cols`, `Name_Array`, `Col_Type_Array`; add `Col_Name_Vecs`, `Col_Type_Vecs`; update `Parse_CSV` closure vars, `Process_Line_Direct`, `Infer_Column_Types`, `Load_Data_Rows` |

---

## Task 1: Verify baseline

**Files:** none changed

- [ ] **Step 1: Confirm all 125 tests pass**

```bash
cd /home/jries/Develop/sdata
make check 2>&1 | tail -5
```

Expected last line: `All 125 tests passed.`

Stop if any test fails — do not proceed until the baseline is green.

---

## Task 2: Update the CSV tokenizer (`sdata-csv.ads` + `sdata-csv.adb`)

**Files:**
- Modify: `src/sdata-csv.ads` (lines 1–26 — full replacement)
- Modify: `src/sdata-csv.adb` (lines 141–166 — `Split_Indices` body)

> **Note:** After this task the project will NOT compile — `sdata-file_io.adb` still references `Field_Array` and the old `Split_Indices` signature. Stage these files but do NOT commit yet. The build is fixed in Task 3.

- [ ] **Step 1: Replace `src/sdata-csv.ads` entirely**

The new spec removes `Max_Fields` and `Field_Array`, adds `with Ada.Containers.Vectors`, instantiates `Field_Vectors`, and changes `Split_Indices` from a function to a procedure.

```ada
with Ada.Containers.Vectors;

package SData.CSV is

   type Field_Pair is record S, E : Natural; end record;

   package Field_Vectors is new Ada.Containers.Vectors (Positive, Field_Pair);

   function Try_Fast_Float   (S         : String;
                               Result    : out Float) return Boolean;

   function Is_Numeric_Field (F : String) return Boolean;

   function At_Delimiter     (Line      : String;
                               Pos       : Positive;
                               Delimiter : String) return Boolean;

   function CSV_Field_End    (Line      : String;
                               From      : Positive;
                               Delimiter : String) return Natural;

   function CSV_Unquote      (Raw : String) return String;

   procedure Split_Indices   (Line      : String;
                               Delimiter : String;
                               Fields    : in out Field_Vectors.Vector);

end SData.CSV;
```

- [ ] **Step 2: Replace the `Split_Indices` body in `src/sdata-csv.adb`**

Replace lines 141–166 (the entire `Split_Indices` function) with this procedure:

```ada
   procedure Split_Indices (Line      : String;
                             Delimiter : String;
                             Fields    : in out Field_Vectors.Vector) is
      Start : Integer  := Line'First;
      DLen  : constant Positive := Delimiter'Length;
   begin
      Fields.Clear;
      if Line'Length = 0 then return; end if;
      loop
         declare
            Delim : constant Natural := CSV_Field_End (Line, Start, Delimiter);
         begin
            Fields.Append
               ((S => Start,
                 E => (if Delim > 0 then Delim - 1 else Line'Last)));
            exit when Delim = 0;
            Start := Delim + DLen;
         end;
      end loop;
   end Split_Indices;
```

- [ ] **Step 3: Stage (do not commit yet)**

```bash
git add src/sdata-csv.ads src/sdata-csv.adb
git status
```

Expected: both files staged, nothing else.

---

## Task 3: Update the CSV parser (`sdata-file_io.adb`) and commit all

**Files:**
- Modify: `src/sdata-file_io.adb` — body-level declarations, `Process_Line_Direct`, `Infer_Column_Types`, `Load_Data_Rows`

After this task the build must be clean and all 125 tests must pass. Then commit everything (Tasks 2 + 3 together).

### Part A: Body-level declarations (around line 287–293)

- [ ] **Step 1: Remove `Max_CSV_Cols`, `Name_Array`, `Col_Type_Array`; add two vector packages**

Find this block (lines 287–293):
```ada
   --  Practical upper bound on columns for type-inference buffers.
   Max_CSV_Cols : constant := 4_096;

   package Line_Vecs is new Ada.Containers.Vectors (Positive, Unbounded_String);

   type Name_Array     is array (1 .. Max_CSV_Cols) of GNAT.Strings.String_Access;
   type Col_Type_Array is array (1 .. Max_CSV_Cols) of Column_Type;
```

Replace with:
```ada
   package Line_Vecs     is new Ada.Containers.Vectors (Positive, Unbounded_String);
   package Col_Name_Vecs is new Ada.Containers.Vectors
      (Positive, GNAT.Strings.String_Access);
   package Col_Type_Vecs is new Ada.Containers.Vectors (Positive, Column_Type);
```

### Part B: `Parse_CSV` local declarations (around line 496–501)

- [ ] **Step 2: Replace the three fixed closure variables with two vectors**

Find (lines 496–501):
```ada
      N_Cols    : Natural         := 0;
      Col_Names : Name_Array     := (others => null);
      Col_Types : Col_Type_Array := (others => Col_Numeric);

      --  Pass 3 helper: scan up to NSCAN rows to determine column types and names.
      --  Sets N_Cols, Col_Names(1..N_Cols), Col_Types(1..N_Cols).
```

Replace with:
```ada
      Col_Names : Col_Name_Vecs.Vector;
      Col_Types : Col_Type_Vecs.Vector;

      --  Pass 3 helper: scan up to NSCAN rows to determine column types and names.
      --  Populates Col_Names and Col_Types vectors.
```

### Part C: `Process_Line_Direct` (lines 445–483)

- [ ] **Step 3: Remove the `Names` parameter; close over `Col_Names` directly**

Find the entire procedure (lines 445–483):
```ada
      procedure Process_Line_Direct (Line : String; Names : String_List) is
         DLen        : constant Positive :=
            (if Delimiter'Length > 0 then Delimiter'Length else 1);
         Start       : Integer := Line'First;
         Field_Count : Natural := 0;
      begin
         if Max_Rows > 0 and then Rows_Written >= Max_Rows then return; end if;
         Rows_Written := Rows_Written + 1;
         Add_Row;
         loop
            declare
               Delim_Pos : constant Natural := CSV_Field_End (Line, Start, Delimiter);
               Val       : Value;
               Num       : Float;
            begin
               declare
                  Raw : constant String :=
                     (if Delim_Pos > 0 then Line (Start .. Delim_Pos - 1)
                      else                  Line (Start .. Line'Last));
                  F   : constant String := CSV_Unquote (Raw);
               begin
                  Field_Count := Field_Count + 1;
                  if Field_Count <= Names'Length then
                     if F = "" or else F = "." then
                        Val := (Kind => Val_Missing);
                     elsif Try_Fast_Float (F, Num) then
                        Val := (Kind => Val_Numeric, Num_Val => Num);
                     else
                        Val := (Kind    => Val_String,
                                Str_Val => To_Unbounded_String (F));
                     end if;
                     Set_Value_Upper (Row_Count, Names (Field_Count).all, Val);
                  end if;
               end;
               exit when Delim_Pos = 0;
               Start := Delim_Pos + DLen;
            end;
         end loop;
      end Process_Line_Direct;
```

Replace with:
```ada
      procedure Process_Line_Direct (Line : String) is
         DLen        : constant Positive :=
            (if Delimiter'Length > 0 then Delimiter'Length else 1);
         Start       : Integer := Line'First;
         Field_Count : Natural := 0;
      begin
         if Max_Rows > 0 and then Rows_Written >= Max_Rows then return; end if;
         Rows_Written := Rows_Written + 1;
         Add_Row;
         loop
            declare
               Delim_Pos : constant Natural := CSV_Field_End (Line, Start, Delimiter);
               Val       : Value;
               Num       : Float;
            begin
               declare
                  Raw : constant String :=
                     (if Delim_Pos > 0 then Line (Start .. Delim_Pos - 1)
                      else                  Line (Start .. Line'Last));
                  F   : constant String := CSV_Unquote (Raw);
               begin
                  Field_Count := Field_Count + 1;
                  if Field_Count <= Natural (Col_Names.Length) then
                     if F = "" or else F = "." then
                        Val := (Kind => Val_Missing);
                     elsif Try_Fast_Float (F, Num) then
                        Val := (Kind => Val_Numeric, Num_Val => Num);
                     else
                        Val := (Kind    => Val_String,
                                Str_Val => To_Unbounded_String (F));
                     end if;
                     Set_Value_Upper (Row_Count, Col_Names (Field_Count).all, Val);
                  end if;
               end;
               exit when Delim_Pos = 0;
               Start := Delim_Pos + DLen;
            end;
         end loop;
      end Process_Line_Direct;
```

Two changes: `Names'Length` → `Natural (Col_Names.Length)` and `Names (Field_Count).all` → `Col_Names (Field_Count).all`.

### Part D: `Infer_Column_Types` (lines 502–574)

- [ ] **Step 4: Replace `Infer_Column_Types` with the vector-based version**

Find the entire procedure (lines 502–574):
```ada
      --  Pass 3 helper: scan up to NSCAN rows to determine column types and names.
      --  Populates Col_Names and Col_Types vectors.
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

Replace with:
```ada
      --  Pass 3 helper: scan up to NSCAN rows to determine column types and names.
      --  Populates Col_Names and Col_Types vectors.
      procedure Infer_Column_Types
         (H_Str : String; Names_From_Header : Boolean)
      is
         H_Fields : Field_Vectors.Vector;
         N_Hdr    : Natural;
      begin
         Split_Indices (H_Str, Delimiter, H_Fields);
         N_Hdr := Natural (H_Fields.Length);

         Col_Types := Col_Type_Vecs.To_Vector
            (Col_Numeric, Ada.Containers.Count_Type (N_Hdr));
         Col_Names.Clear;

         declare
            Col_Determined : array (1 .. N_Hdr) of Boolean := (others => False);
         begin
            --  Columns whose header already ends in "$" are forced character.
            if Names_From_Header then
               for I in 1 .. N_Hdr loop
                  declare
                     Raw : constant String :=
                        Trim (H_Str (H_Fields (I).S .. H_Fields (I).E),
                              Ada.Strings.Both);
                  begin
                     if Raw'Length > 0 and then Raw (Raw'Last) = '$' then
                        Col_Types.Replace_Element (I, Col_String);
                        Col_Determined (I) := True;
                     end if;
                  end;
               end loop;
            end if;

            --  Scan data rows to determine remaining column types.
            declare
               D_Fields : Field_Vectors.Vector;
            begin
               for R in 1 .. Scan_Count loop
                  declare
                     D_Str : constant String := To_String (Scan_Lines (R));
                  begin
                     Split_Indices (D_Str, Delimiter, D_Fields);
                     for I in 1 .. N_Hdr loop
                        if not Col_Determined (I)
                           and then I <= Natural (D_Fields.Length)
                        then
                           declare
                              F : constant String :=
                                 CSV_Unquote
                                    (D_Str (D_Fields (I).S .. D_Fields (I).E));
                           begin
                              if F /= "" and then F /= "." then
                                 Col_Types.Replace_Element
                                    (I, (if Is_Numeric_Field (F) then Col_Numeric
                                         else Col_String));
                                 Col_Determined (I) := True;
                              end if;
                           end;
                        end if;
                     end loop;
                  end;
               end loop;
            end;

            --  Build column names; append "$" to string columns that lack it.
            for I in 1 .. N_Hdr loop
               declare
                  Base_Name : constant String :=
                     (if Names_From_Header
                      then Safe_Name
                              (CSV_Unquote (H_Str (H_Fields (I).S .. H_Fields (I).E)),
                               "COL" & Trim (I'Img, Ada.Strings.Both))
                      else "COL" & Trim (I'Img, Ada.Strings.Both));
                  Name : constant String :=
                     (if Col_Types (I) = Col_String
                         and then (Base_Name'Length = 0
                                   or else Base_Name (Base_Name'Last) /= '$')
                      then Base_Name & "$"
                      else Base_Name);
               begin
                  Col_Names.Append (new String'(Name));
               end;
            end loop;
         end;
      end Infer_Column_Types;
```

Key changes from the old version:
- `H_Idx : constant Field_Array` → `H_Fields : Field_Vectors.Vector` (declared before the `begin`, populated via procedure call)
- `N_Hdr` computed from `H_Fields.Length` after calling `Split_Indices`
- `Col_Determined` moves inside a `declare` block because it depends on `N_Hdr` which is now a runtime value set in the `begin` section
- `Col_Types := (others => Col_Numeric)` → `Col_Type_Vecs.To_Vector (Col_Numeric, ...)`
- `Col_Names := (others => null)` → `Col_Names.Clear`
- `Col_Types (I) := Col_String` → `Col_Types.Replace_Element (I, Col_String)`
- `D_Idx : constant Field_Array` inside the loop → `D_Fields : Field_Vectors.Vector` declared once before the loop (reused across iterations; `Split_Indices` calls `Fields.Clear` on entry, so the buffer grows to the widest line seen and stays there)
- `Col_Names (I) := new String'(Name)` → `Col_Names.Append (new String'(Name))`
- `N_Cols := N_Hdr` removed — `N_Cols` no longer exists

### Part E: `Load_Data_Rows` (lines 577–619)

- [ ] **Step 5: Replace `Load_Data_Rows` with the vector-based version**

Find the entire procedure (lines 577–619):
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

         for I in Names'Range loop
            Free (Names (I));
            Col_Names (I) := null;
         end loop;
      end Load_Data_Rows;
```

Replace with:
```ada
      --  Pass 4 helper: register columns, stream scan lines and remaining file rows.
      procedure Load_Data_Rows is
         N : constant Natural := Natural (Col_Names.Length);
      begin
         Clear;
         for I in 1 .. N loop
            Add_Column (Col_Names (I).all, Col_Types (I));
         end loop;

         if Has_File_Header and then Scan_Count = 0 then
            SData.IO.Put_Line_Error
               ("Warning: File contains a header but no data records.");
         end if;

         --  Replay buffered scan rows.
         for R in 1 .. Scan_Count loop
            exit when Max_Rows > 0 and then Rows_Written >= Max_Rows;
            Process_Line_Direct (To_String (Scan_Lines (R)));
         end loop;

         --  Stream the remainder of the file.
         if Is_Buffered then
            while All_Lines_Idx < Natural (All_Lines.Length) loop
               exit when Max_Rows > 0 and then Rows_Written >= Max_Rows;
               All_Lines_Idx := All_Lines_Idx + 1;
               Process_Line_Direct (To_String (All_Lines (All_Lines_Idx)));
            end loop;
         else
            while not Ada.Text_IO.End_Of_File (File) loop
               exit when Max_Rows > 0 and then Rows_Written >= Max_Rows;
               Ada.Text_IO.Get_Line (File, Line_Buf.all, Line_Last);
               if Needs_ASCII_Chk then
                  Validate_ASCII (Line_Buf (1 .. Line_Last));
               end if;
               Process_Line_Direct (Line_Buf (1 .. Line_Last));
            end loop;
         end if;

         for SA of Col_Names loop Free (SA); end loop;
         Col_Names.Clear;
      end Load_Data_Rows;
```

Key changes:
- `Names : String_List (1 .. N_Cols)` → `N : constant Natural := Natural (Col_Names.Length)` (no `String_List` alias needed)
- Column registration loop uses `Col_Names (I).all` and `Col_Types (I)` directly — no `Names` array built
- All three `Process_Line_Direct (... , Names)` calls drop the `Names` argument
- Free loop: `for I in Names'Range loop Free (Names (I)); Col_Names (I) := null; end loop` → `for SA of Col_Names loop Free (SA); end loop; Col_Names.Clear`

### Part F: Build, test, commit

- [ ] **Step 6: Build the project**

```bash
cd /home/jries/Develop/sdata
make 2>&1 | tail -10
```

Expected: `Success: Build finished successfully` (no errors or warnings about `Field_Array`, `Max_Fields`, `N_Cols`, `Names`).

If there are compilation errors, the most likely causes and fixes:
- `Field_Array` reference remaining → search for any surviving `Field_Array` or `N_Fields` identifier: `grep -n "Field_Array\|N_Fields\|Max_Fields\|Max_CSV_Cols\|Name_Array\|Col_Type_Array\|N_Cols\b" src/sdata-file_io.adb src/sdata-csv.adb src/sdata-csv.ads`
- `use SData.CSV` in `sdata-file_io.adb` already brings `Field_Vectors` into scope — no additional `use` needed for the procedure call
- `Col_Type_Vecs.To_Vector` needs `Ada.Containers` visible — `sdata-file_io.adb` already has `with Ada.Containers.Vectors` at line 14

- [ ] **Step 7: Run the full test suite**

```bash
make check 2>&1 | tail -5
```

Expected: `All 125 tests passed.`

- [ ] **Step 8: Commit all three files together**

```bash
git add src/sdata-csv.ads src/sdata-csv.adb src/sdata-file_io.adb
git commit -m "$(cat <<'EOF'
Refactor: replace Field_Array and fixed column arrays with dynamic vectors

Remove Max_Fields (65536) and Max_CSV_Cols (4096). Split_Indices becomes a
procedure taking Field_Vectors.Vector in out. Col_Names and Col_Types in
Parse_CSV are now vectors; Process_Line_Direct closes over Col_Names directly.
CSV column count is now bounded only by available memory.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```
