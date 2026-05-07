# Dynamic Field Array Design

**Goal:** Replace all fixed-size column-count arrays with dynamic containers, eliminating the
`Max_Fields` and `Max_CSV_Cols` hard-coded limits. CSV parsing becomes bounded only by available
memory, matching the behaviour of the ODS and XLSX parsers.

**Architecture:** `Field_Array` (returned by value from `Split_Indices`) is replaced by
`Field_Vectors.Vector` passed `in out`. The closure variables `Col_Names` and `Col_Types` inside
`Parse_CSV` become vectors. `Process_Line_Direct` loses its `Names : String_List` parameter and
closes over `Col_Names` directly. Three constants and two array types are deleted; two new vector
package instantiations are added at body level in `sdata-file_io.adb`.

**Files changed:** `src/sdata-csv.ads`, `src/sdata-csv.adb`, `src/sdata-file_io.adb` only.
No spec changes, no new tests, identical observable behaviour.

---

## Changes by file

### `src/sdata-csv.ads`

Add `with Ada.Containers.Vectors;` at the top.

Remove:
```ada
Max_Fields : constant := 65_536;
type Field_Array is array (1 .. Max_Fields) of Field_Pair;
```

Add:
```ada
package Field_Vectors is new Ada.Containers.Vectors (Positive, Field_Pair);
```

Change `Split_Indices` from a function returning `Field_Array` to a procedure:
```ada
-- Old:
function Split_Indices (Line      : String;
                        Delimiter : String;
                        N_Fields  : out Natural) return Field_Array;

-- New:
procedure Split_Indices (Line      : String;
                         Delimiter : String;
                         Fields    : in out Field_Vectors.Vector);
```

The caller is responsible for passing a vector; the procedure calls `Fields.Clear` on entry and
appends one `Field_Pair` per parsed field. `N_Fields` is eliminated — callers use
`Natural (Fields.Length)`.

---

### `src/sdata-csv.adb`

Replace the `Split_Indices` body:

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

The `Count <= Max_Fields` guard and the `Res` array are gone.

---

### `src/sdata-file_io.adb`

#### Body-level declarations

Remove:
```ada
Max_CSV_Cols : constant := 4_096;
type Name_Array     is array (1 .. Max_CSV_Cols) of GNAT.Strings.String_Access;
type Col_Type_Array is array (1 .. Max_CSV_Cols) of Column_Type;
```

Add (alongside the existing `package Line_Vecs` instantiation):
```ada
package Col_Name_Vecs is new Ada.Containers.Vectors
   (Positive, GNAT.Strings.String_Access);
package Col_Type_Vecs is new Ada.Containers.Vectors
   (Positive, Column_Type);
```

#### `Parse_CSV` local declarations

Remove:
```ada
N_Cols    : Natural         := 0;
Col_Names : Name_Array      := (others => null);
Col_Types : Col_Type_Array  := (others => Col_Numeric);
```

Add:
```ada
Col_Names : Col_Name_Vecs.Vector;
Col_Types : Col_Type_Vecs.Vector;
```

`N_Cols` is eliminated throughout; use `Natural (Col_Names.Length)` where the count is needed.

#### `Process_Line_Direct`

Remove the `Names : String_List` parameter. The procedure closes over `Col_Names` directly.

```ada
-- Old signature:
procedure Process_Line_Direct (Line : String; Names : String_List) is

-- New signature:
procedure Process_Line_Direct (Line : String) is
```

Inside the body, replace:
- `Names'Length`  →  `Natural (Col_Names.Length)`
- `Names (Field_Count).all`  →  `Col_Names (Field_Count).all`

All three call sites in `Load_Data_Rows` drop the `Names` argument.

#### `Infer_Column_Types`

Replace the fixed-array locals with a vector and a dynamic stack array:

```ada
procedure Infer_Column_Types (H_Str : String; Names_From_Header : Boolean) is
   H_Fields : Field_Vectors.Vector;
   N_Hdr    : Natural;
begin
   Split_Indices (H_Str, Delimiter, H_Fields);
   N_Hdr := Natural (H_Fields.Length);

   declare
      Col_Determined : array (1 .. N_Hdr) of Boolean := (others => False);
   begin
      Col_Types := Col_Type_Vecs.To_Vector
         (Col_Numeric, Ada.Containers.Count_Type (N_Hdr));
      Col_Names.Clear;

      --  $-suffix rule: columns whose header already ends in "$" are forced string.
      if Names_From_Header then
         for I in 1 .. N_Hdr loop
            declare
               Raw : constant String :=
                  Trim (H_Str (H_Fields (I).S .. H_Fields (I).E), Ada.Strings.Both);
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
                           CSV_Unquote (D_Str (D_Fields (I).S .. D_Fields (I).E));
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

Key points:
- `H_Fields` is local, created fresh per call.
- `D_Fields` is declared inside the scan block but outside the loop so the vector's internal buffer
  is reused across iterations (capacity grows to the maximum field count seen, then stays there).
- `Col_Determined` is a dynamically-sized stack array — valid Ada 2012, cheap (one byte per column).
- `Col_Types` is pre-filled via `To_Vector` rather than element-by-element, then updated with
  `Replace_Element`.

#### `Load_Data_Rows`

Remove `Names : String_List (1 .. N_Cols)`. All column information is read directly from the
`Col_Names` and `Col_Types` closure vectors.

```ada
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
         if Needs_ASCII_Chk then Validate_ASCII (Line_Buf (1 .. Line_Last)); end if;
         Process_Line_Direct (Line_Buf (1 .. Line_Last));
      end loop;
   end if;

   for SA of Col_Names loop Free (SA); end loop;
   Col_Names.Clear;
end Load_Data_Rows;
```

---

## What is NOT changed

- `Parse_ODF` and `Parse_OOXML` — already use dynamic vectors; no `Field_Array` dependency.
- `Is_Numeric_Field`, `CSV_Field_End`, `CSV_Unquote`, `At_Delimiter` in `sdata-csv.adb` — unchanged.
- All local procedures in `Parse_CSV` other than the three above — unchanged.
- The `sdata-csv.ads` public functions `Is_Numeric_Field`, `At_Delimiter`, `CSV_Field_End`,
  `CSV_Unquote` — unchanged.
- No spec (`.ads`) changes outside `sdata-csv.ads`.

---

## Testing

Run `make check` after the refactor; all 125 tests must pass. No new test cases are needed — this
is a pure structural change with identical observable behaviour.
