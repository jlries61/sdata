# Parse_CSV Internal Decomposition Design

> **For agentic workers:** Use superpowers:writing-plans then superpowers:subagent-driven-development to implement this spec.

**Goal:** Decompose `Parse_CSV` in `src/sdata-file_io.adb` into four clearly-named internal passes so that each concern is independently readable and the procedure body becomes an ~80-line orchestrator.

**Architecture:** Three body-level procedures (`Load_As_UTF16`, `Detect_And_Load`, and the `Line_Vecs` package instantiation) are lifted out of their current nested scope. The existing `Load_Columns_And_Data` local procedure is split into two local procedures: `Infer_Column_Types` and `Load_Data_Rows`. No new files, no spec changes, no observable behaviour change.

**Files changed:** `src/sdata-file_io.adb` only.

---

## The Four Passes

### Pass 1: Charset resolution (body-level)

`Detect_And_Load` and `Load_As_UTF16` currently live inside a `declare` block in `Parse_CSV`'s body, closing over `All_Lines` and `Is_Buffered`. They move to package-body level with explicit `out` parameters.

```ada
procedure Load_As_UTF16
   (File_Name   : String;
    Scheme      : Ada.Strings.UTF_Encoding.Encoding_Scheme;
    All_Lines   : out Line_Vecs.Vector;
    Is_Buffered : out Boolean);

procedure Detect_And_Load
   (File_Name   : String;
    All_Lines   : out Line_Vecs.Vector;
    Is_Buffered : out Boolean);
```

`Load_As_UTF16` always sets `Is_Buffered := True` on success; it re-raises on exception after closing the stream file (existing cleanup logic preserved). `Detect_And_Load` sets `Is_Buffered := False` if no UTF-16 BOM is found.

`package Line_Vecs` (the `Ada.Containers.Vectors` instantiation) moves from inside `Parse_CSV` to package-body level — prerequisite for the body-level procedures to reference the type.

### Pass 2: Header and scan-line collection (inline in Parse_CSV body)

Remains inline — extracting it into a named procedure would require passing `File`, `Line_Buf`, `All_Lines`, `Is_Buffered`, and five output variables, producing more noise than clarity. A section comment marks it.

Produces: `Header_Line`, `Has_File_Header`, `Scan_Lines (1 .. NSCAN)`, `Scan_Count`.

### Pass 3: Type inference (local procedure)

```ada
procedure Infer_Column_Types
   (H_Str             : String;
    Names_From_Header : Boolean;
    N_Cols            : out Natural;
    Col_Names         : out Name_Array;
    Col_Types         : out Col_Type_Array);
```

`Name_Array` and `Col_Type_Array` are fixed-bound arrays (upper bound `Max_Fields`, matching the existing `Field_Array` pattern) declared at package-body level. `Col_Type_Array` element type is `Column_Type` from `SData.Table`. `Name_Array` element type is `String_Access` (GNAT.Strings).

This is the first half of the current `Load_Columns_And_Data`: it reads `Scan_Lines` and `Scan_Count` from the enclosing `Parse_CSV` scope (they remain closure variables), applies the `$`-suffix header rule, runs the scan loop, and returns populated arrays.

### Pass 4: Data loading (local procedure)

```ada
procedure Load_Data_Rows
   (N_Cols    : Natural;
    Col_Names : Name_Array;
    Col_Types : Col_Type_Array);
```

This is the second half of `Load_Columns_And_Data`: calls `Clear`, calls `Add_Column` for each column, processes buffered scan lines through `Process_Line_Direct`, then streams remaining lines (buffered or text-file path). Reads `Is_Buffered`, `All_Lines`, `All_Lines_Idx`, `File`, `Line_Buf`, `Needs_ASCII_Chk`, `Max_Rows`, `Rows_Written` from the enclosing scope.

Frees `Names` entries on exit (existing `for I in Names'Range loop Free (Names (I)); end loop` logic, now using `Col_Names`).

---

## Parse_CSV Body After Refactor

```ada
begin
   -- Pass 1: resolve charset, optionally buffer whole file
   declare
      UC : constant String := To_Upper (Trim (Charset, Ada.Strings.Both));
   begin
      if UC = "UTF-16" or else UC = "UTF-16LE" then
         Load_As_UTF16 (File_Name, UTF_16LE, All_Lines, Is_Buffered);
      elsif UC = "UTF-16BE" then
         Load_As_UTF16 (File_Name, UTF_16BE, All_Lines, Is_Buffered);
      elsif UC = "" or else UC = "AUTO" then
         Detect_And_Load (File_Name, All_Lines, Is_Buffered);
      elsif UC = "ASCII" then
         Needs_ASCII_Chk := True;
      end if;
   end;

   -- Pass 2: open file (non-buffered path), collect header + scan lines
   if not Is_Buffered then
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, File_Name);
   end if;
   -- ... (header read, skip rows, scan-line buffering — unchanged logic) ...

   -- Passes 3 + 4: infer types, create columns, stream data
   if Has_File_Header then
      Infer_Column_Types (To_String (Header_Line), True,  N_Cols, Col_Names, Col_Types);
      Load_Data_Rows (N_Cols, Col_Names, Col_Types);
   elsif Scan_Count > 0 then
      Infer_Column_Types (To_String (Scan_Lines (1)), False, N_Cols, Col_Names, Col_Types);
      Load_Data_Rows (N_Cols, Col_Names, Col_Types);
   end if;

   Free_Buf (Line_Buf);
   if Ada.Text_IO.Is_Open (File) then Ada.Text_IO.Close (File); end if;
exception
   when others =>
      Free_Buf (Line_Buf);
      if Ada.Text_IO.Is_Open (File) then Ada.Text_IO.Close (File); end if;
      raise;
end Parse_CSV;
```

---

## Local Procedures Unchanged

`Validate_ASCII`, `Split_Into_Lines`, and `Process_Line_Direct` remain as local procedures inside `Parse_CSV`. They are already small, well-named, and their closure dependencies are appropriate.

---

## Error Handling

No new exception handlers. The existing `when others =>` cleanup block at the end of `Parse_CSV` continues to cover all passes. `Load_As_UTF16` and `Detect_And_Load` preserve their existing re-raise-after-close pattern.

---

## Testing

No new test cases needed. This is a pure internal refactor with identical observable behaviour. Run `make check` after the refactor; all 125 tests must pass.
