# Parse_ODF / Parse_OOXML Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decompose the monolithic `Load_Content` (Parse_ODF) and `Load_Sheet` (Parse_OOXML) procedures in `src/sdata-file_io.adb` into named single-responsibility sub-procedures, and eliminate duplicated INF-detection logic shared across both parsers.

**Architecture:** Pure internal decomposition — no new files, no new packages. Each monolith is split into three named nested procedures (header collection, schema inference, data loading) with clean parameter boundaries. A shared `Detect_Inf` private function eliminates three copies of the same INF-string-detection code. A package-level `Name_Vecs` instantiation (replacing two identical per-procedure instantiations) enables a shared `Apply_Dollar_Override` helper. No observable behaviour changes; all existing tests remain green throughout.

**Tech Stack:** Ada 2012, GNAT/GPRbuild, Alire. Build: `alr build`. Test: `make check`.

---

## Background

`src/sdata-file_io.adb` (~1758 lines) contains two XML parsers:

| Procedure | Location | Current structure |
|-----------|----------|-------------------|
| `Parse_ODF` | lines 891–1163 | one nested `Load_Content` procedure (254 lines) with interleaved header/inference/data phases |
| `Parse_OOXML` | lines 1168–1557 | three nested procedures; `Load_Sheet` (226 lines) still interleaves header/inference/data |

Both parsers duplicate:
- INF-string detection (`"INF"`, `"+INF"`, `"INFINITY"`, etc.) — appears in ODF `Get_Cell_Value` once, OOXML `Get_Cell_Value` twice (in the `t="str"` and `<is>` branches)
- `$`-suffix column-type override — identical 8-line block in each parser's type-inference phase
- `package Name_Vecs is new Ada.Containers.Vectors (Positive, Unbounded_String)` — declared separately in both `Load_Content` and `Load_Sheet`

The baseline test count before this refactor: 128 integration tests + 270 unit tests (all passing). Every task ends with `make check` confirming no regression.

---

## File Map

| File | Action | What changes |
|------|--------|-------------|
| `src/sdata-file_io.adb` | Modify | All changes — hoisted `Name_Vecs`, new `Detect_Inf`, `Apply_Dollar_Override`; decomposed `Load_Content` and `Load_Sheet` |

No other files change.

---

### Task 1: Hoist `Name_Vecs`, add `Detect_Inf`, add `Apply_Dollar_Override`

Establishes the shared infrastructure before the decomposition tasks. No logic changes — only moves and extracts code that already exists.

**Files:**
- Modify: `src/sdata-file_io.adb`

- [ ] **Step 1: Confirm baseline passes**

```bash
make check 2>&1 | tail -3
```
Expected: `All 128 tests passed.`

- [ ] **Step 2: Hoist `Name_Vecs` to package-body scope**

Read `src/sdata-file_io.adb` line 30 (`package body SData.File_IO is`) and line 48 (end of `Get_Text`).

Currently both `Load_Content` (inside `Parse_ODF`) and `Load_Sheet` (inside `Parse_OOXML`) contain an identical local declaration:
```ada
package Name_Vecs is new Ada.Containers.Vectors (Positive, Unbounded_String);
```
(In `Load_Content` this is at the top of the procedure; in `Load_Sheet` it is on approximately line 1318.)

Add a single package-level instantiation immediately after the `package body SData.File_IO is` line (line 30), before `Get_Text`:

```ada
package body SData.File_IO is

   --  Shared column-name vector type used by Parse_ODF and Parse_OOXML.
   package Name_Vecs is new Ada.Containers.Vectors (Positive, Unbounded_String);

   --  Helper for DOM node traversal
   function Get_Text (N : DOM.Core.Node) return String is
```

Then delete the two local `package Name_Vecs is new ...` declarations inside `Load_Content` and `Load_Sheet`. Each is a single line — remove it and the surrounding blank line.

- [ ] **Step 3: Add `Detect_Inf` private helper**

After the `Get_Text` body (after approximately line 48) and before the `Safe_Name` function, insert:

```ada
   --  Returns Pos_Inf, Neg_Inf, or Val_Missing for INF-variant strings.
   --  Used by both Parse_ODF and Parse_OOXML Get_Cell_Value helpers.
   function Detect_Inf (S : String) return Value is
      SU : constant String := To_Upper (S);
   begin
      if SU = "INF" or else SU = "+INF"
         or else SU = "INFINITY" or else SU = "+INFINITY"
      then
         return (Kind => Val_Numeric, Num_Val => Pos_Inf);
      elsif SU = "-INF" or else SU = "-INFINITY" then
         return (Kind => Val_Numeric, Num_Val => Neg_Inf);
      end if;
      return (Kind => Val_Missing);
   end Detect_Inf;
```

- [ ] **Step 4: Add `Apply_Dollar_Override` shared helper**

After `Detect_Inf` and before `Safe_Name`, insert:

```ada
   --  Forces Col_String for any column whose name ends in '$'.
   --  Shared by Parse_ODF and Parse_OOXML type-inference phases.
   procedure Apply_Dollar_Override
      (Col_Name_Vec : Name_Vecs.Vector;
       Col_Types    : in out Column_Type_Array) is
   begin
      for I in 1 .. Natural (Col_Name_Vec.Length) loop
         declare
            Raw : constant String := To_String (Col_Name_Vec (I));
         begin
            if Raw'Length > 0 and then Raw (Raw'Last) = '$' then
               Col_Types (I) := Col_String;
            end if;
         end;
      end loop;
   end Apply_Dollar_Override;
```

**Note on `Column_Type_Array`:** this is an unconstrained array type used only within the procedure bodies, so it can't be a parameter type as-is without a named type declaration. Use the following local named type instead — declare it immediately before `Apply_Dollar_Override`:

```ada
   type Column_Type_Array is array (Positive range <>) of Column_Type;
```

Then the `Apply_Dollar_Override` signature above works correctly.

- [ ] **Step 5: Update ODF `Get_Cell_Value` to use `Detect_Inf`**

In `Parse_ODF` → `Load_Content` → `Get_Cell_Value` (approximately lines 923–936), the existing INF handling is:

```ada
            elsif Length (P_List) > 0 then
               declare
                  S  : constant String := Get_Text (Item (P_List, 0));
                  SU : constant String := To_Upper (S);
               begin
                  Free (P_List);
                  if SU = "INF" or else SU = "+INF"
                     or else SU = "INFINITY" or else SU = "+INFINITY"
                  then
                     return (Kind => Val_Numeric, Num_Val => Pos_Inf);
                  elsif SU = "-INF" or else SU = "-INFINITY" then
                     return (Kind => Val_Numeric, Num_Val => Neg_Inf);
                  end if;
                  return (Kind => Val_String, Str_Val => To_Unbounded_String (S));
               end;
```

Replace with:

```ada
            elsif Length (P_List) > 0 then
               declare
                  S   : constant String := Get_Text (Item (P_List, 0));
                  Inf : constant Value  := Detect_Inf (S);
               begin
                  Free (P_List);
                  if Inf.Kind /= Val_Missing then return Inf; end if;
                  return (Kind => Val_String, Str_Val => To_Unbounded_String (S));
               end;
```

- [ ] **Step 6: Update OOXML `Get_Cell_Value` to use `Detect_Inf`**

In `Parse_OOXML` → `Load_Sheet` → `Get_Cell_Value`, there are two INF-detection blocks:

**Block A** (the `T_Attr = "str"` branch, approximately lines 1341–1353):
```ada
                  elsif T_Attr = "str" then
                     declare
                        SU : constant String := To_Upper (Val_Str);
                     begin
                        if SU = "INF" or else SU = "+INF"
                           or else SU = "INFINITY" or else SU = "+INFINITY"
                        then
                           Free (V_List); Free (IS_List);
                           return (Kind => Val_Numeric, Num_Val => Pos_Inf);
                        elsif SU = "-INF" or else SU = "-INFINITY" then
                           Free (V_List); Free (IS_List);
                           return (Kind => Val_Numeric, Num_Val => Neg_Inf);
                        end if;
                        return (Kind => Val_String, Str_Val => To_Unbounded_String (Val_Str));
                     end;
```

Replace with:

```ada
                  elsif T_Attr = "str" then
                     declare
                        Inf : constant Value := Detect_Inf (Val_Str);
                     begin
                        Free (V_List); Free (IS_List);
                        if Inf.Kind /= Val_Missing then return Inf; end if;
                        return (Kind => Val_String, Str_Val => To_Unbounded_String (Val_Str));
                     end;
```

**Block B** (the `IS_List` branch, approximately lines 1362–1376):
```ada
                  if Length (T_Nodes) > 0 then
                     declare
                        S  : constant String := Get_Text (Item (T_Nodes, 0));
                        SU : constant String := To_Upper (S);
                     begin
                        Free (T_Nodes); Free (V_List); Free (IS_List);
                        if SU = "INF" or else SU = "+INF"
                           or else SU = "INFINITY" or else SU = "+INFINITY"
                        then
                           return (Kind => Val_Numeric, Num_Val => Pos_Inf);
                        elsif SU = "-INF" or else SU = "-INFINITY" then
                           return (Kind => Val_Numeric, Num_Val => Neg_Inf);
                        end if;
                        return (Kind => Val_String, Str_Val => To_Unbounded_String (S));
                     end;
```

Replace with:

```ada
                  if Length (T_Nodes) > 0 then
                     declare
                        S   : constant String := Get_Text (Item (T_Nodes, 0));
                        Inf : constant Value  := Detect_Inf (S);
                     begin
                        Free (T_Nodes); Free (V_List); Free (IS_List);
                        if Inf.Kind /= Val_Missing then return Inf; end if;
                        return (Kind => Val_String, Str_Val => To_Unbounded_String (S));
                     end;
```

- [ ] **Step 7: Build and run tests**

```bash
alr build 2>&1 | tail -5
```
Expected: zero errors. Then:

```bash
make check 2>&1 | tail -3
```
Expected: `All 128 tests passed.`

- [ ] **Step 8: Commit**

```bash
git add src/sdata-file_io.adb
git commit -m "Refactor: hoist Name_Vecs, extract Detect_Inf and Apply_Dollar_Override"
```

---

### Task 2: Decompose Parse_ODF `Load_Content`

Splits the 254-line `Load_Content` body into three named sub-procedures: `Collect_Headers`, `Infer_And_Create_Schema`, and `Load_ODF_Data_Rows`. The outer `Load_Content` body becomes a 12-line orchestrator that calls these three in sequence.

**Files:**
- Modify: `src/sdata-file_io.adb`

- [ ] **Step 1: Add `Collect_ODF_Headers` nested inside `Load_Content`**

Inside `Load_Content` (after `Get_Cell_Value` and before the `begin` of the procedure body), add:

```ada
         --  Phase 1: collect column names from the header row.
         --  Raises SData.Script_Error for merged cells.
         procedure Collect_ODF_Headers
            (Row0         : DOM.Core.Node;
             Col_Name_Vec : in out Name_Vecs.Vector) is
            Cells : DOM.Core.Node_List :=
               Get_Elements_By_Tag_Name (DOM.Core.Element (Row0), "table:table-cell");
         begin
            for I in 0 .. Length (Cells) - 1 loop
               declare
                  Cell        : constant DOM.Core.Node := Item (Cells, I);
                  Col_Spanned : constant String :=
                     Get_Attribute (DOM.Core.Element (Cell), "table:number-columns-spanned");
                  Row_Spanned : constant String :=
                     Get_Attribute (DOM.Core.Element (Cell), "table:number-rows-spanned");
               begin
                  if (Col_Spanned /= "" and then Positive'Value (Col_Spanned) > 1) or else
                     (Row_Spanned /= "" and then Positive'Value (Row_Spanned) > 1)
                  then
                     Free (Cells);
                     raise SData.Script_Error
                        with "ODS file contains merged cells, which are not supported.";
                  end if;
                  declare
                     Repeat_Attr  : constant String :=
                        Get_Attribute (DOM.Core.Element (Cell), "table:number-columns-repeated");
                     Repeat_Count : constant Positive :=
                        (if Repeat_Attr = "" then 1 else Positive'Value (Repeat_Attr));
                     P_Nodes      : DOM.Core.Node_List :=
                        Get_Elements_By_Tag_Name (DOM.Core.Element (Cell), "text:p");
                     Base_Name    : constant String :=
                        (if Length (P_Nodes) > 0 then Get_Text (Item (P_Nodes, 0)) else "");
                  begin
                     Free (P_Nodes);
                     for K in 1 .. Repeat_Count loop
                        exit when Base_Name = "" and K > 1;
                        declare
                           Idx_Num    : constant Natural :=
                              Natural (Col_Name_Vec.Length) + 1;
                           Idx        : constant String :=
                              Trim (Idx_Num'Img, Ada.Strings.Both);
                           Final_Name : constant String :=
                              (if Base_Name = "" then "COL" & Idx
                               else Base_Name &
                                  (if Repeat_Count > 1
                                   then "_" & Trim (K'Img, Ada.Strings.Both)
                                   else ""));
                        begin
                           Col_Name_Vec.Append
                              (To_Unbounded_String (Safe_Name (Final_Name, "COL" & Idx)));
                        end;
                     end loop;
                  end;
               end;
            end loop;
            Free (Cells);
         end Collect_ODF_Headers;
```

- [ ] **Step 2: Add `Infer_And_Create_ODF_Schema` nested inside `Load_Content`**

Immediately after `Collect_ODF_Headers`, add:

```ada
         --  Phase 2: infer column types from first data row; create columns.
         --  Applies '$'-suffix override before inference.
         procedure Infer_And_Create_ODF_Schema
            (Col_Name_Vec : Name_Vecs.Vector;
             Row1_Present : Boolean;
             Row1         : DOM.Core.Node) is
            N         : constant Natural := Natural (Col_Name_Vec.Length);
            Col_Types : Column_Type_Array (1 .. N) := (others => Col_Numeric);
         begin
            Apply_Dollar_Override (Col_Name_Vec, Col_Types);
            if Row1_Present then
               declare
                  Data_Cells : DOM.Core.Node_List :=
                     Get_Elements_By_Tag_Name
                        (DOM.Core.Element (Row1), "table:table-cell");
                  Col_Idx : Natural := 0;
               begin
                  for J in 0 .. Length (Data_Cells) - 1 loop
                     Col_Idx := Col_Idx + 1;
                     exit when Col_Idx > N;
                     if Get_Cell_Value (Item (Data_Cells, J)).Kind = Val_String then
                        Col_Types (Col_Idx) := Col_String;
                     end if;
                  end loop;
                  Free (Data_Cells);
               end;
            end if;
            for I in 1 .. N loop
               declare
                  Raw_Name   : constant String := To_String (Col_Name_Vec (I));
                  Final_Name : constant String :=
                     (if Col_Types (I) = Col_String
                         and then (Raw_Name'Length = 0
                                   or else Raw_Name (Raw_Name'Last) /= '$')
                      then Raw_Name & "$"
                      else Raw_Name);
               begin
                  Add_Column (Final_Name, Col_Types (I));
               end;
            end loop;
         end Infer_And_Create_ODF_Schema;
```

- [ ] **Step 3: Add `Load_ODF_Data_Rows` nested inside `Load_Content`**

Immediately after `Infer_And_Create_ODF_Schema`, add:

```ada
         --  Phase 3: load data rows (index 1 .. N-1 in the Rows node list).
         procedure Load_ODF_Data_Rows
            (Rows      : DOM.Core.Node_List;
             Col_Count : Natural) is
            Rows_To_Skip : Natural := Skip_Rows;
            Rows_Written : Natural := 0;
         begin
            for I in 1 .. Length (Rows) - 1 loop
               declare
                  Row_Node         : constant DOM.Core.Node := Item (Rows, I);
                  Row_Repeat_Attr  : constant String :=
                     Get_Attribute (DOM.Core.Element (Row_Node),
                                    "table:number-rows-repeated");
                  Row_Repeat_Count : constant Positive :=
                     (if Row_Repeat_Attr = "" then 1
                      else Positive'Value (Row_Repeat_Attr));
               begin
                  exit when Row_Repeat_Count > 1000;
                  exit when Max_Rows > 0 and then Rows_Written >= Max_Rows;
                  for R_Count in 1 .. Row_Repeat_Count loop
                     if Rows_To_Skip > 0 then
                        Rows_To_Skip := Rows_To_Skip - 1;
                     else
                        exit when Max_Rows > 0 and then Rows_Written >= Max_Rows;
                        Rows_Written := Rows_Written + 1;
                        Add_Row;
                        declare
                           Cells   : DOM.Core.Node_List :=
                              Get_Elements_By_Tag_Name
                                 (DOM.Core.Element (Row_Node), "table:table-cell");
                           Col_Idx : Positive := 1;
                        begin
                           for J in 0 .. Length (Cells) - 1 loop
                              declare
                                 Cell         : constant DOM.Core.Node :=
                                    Item (Cells, J);
                                 Repeat_Attr  : constant String :=
                                    Get_Attribute (DOM.Core.Element (Cell),
                                                   "table:number-columns-repeated");
                                 Repeat_Count : constant Positive :=
                                    (if Repeat_Attr = "" then 1
                                     else Positive'Value (Repeat_Attr));
                                 Val : constant Value := Get_Cell_Value (Cell);
                              begin
                                 for K in 1 .. Repeat_Count loop
                                    if Col_Idx <= Col_Count then
                                       if Val.Kind /= Val_Missing then
                                          begin
                                             Set_Value (Row_Count,
                                                        Column_Name (Col_Idx), Val);
                                          exception
                                             when E : others =>
                                                if not SData.Config.Quiet_Mode then
                                                   Put_Line_Error
                                                      ("Warning: ODF import skipped cell at row" &
                                                       Row_Count'Image &
                                                       ", column """ &
                                                       Column_Name (Col_Idx) & """: " &
                                                       Ada.Exceptions.Exception_Message (E));
                                                end if;
                                          end;
                                       end if;
                                       Col_Idx := Col_Idx + 1;
                                    end if;
                                 end loop;
                              end;
                              exit when Col_Idx > Col_Count;
                           end loop;
                           Free (Cells);
                        end;
                     end if;
                  end loop;
               end;
            end loop;
         end Load_ODF_Data_Rows;
```

- [ ] **Step 4: Replace the `Load_Content` body**

The existing body of `Load_Content` (after `begin`, approximately lines 943–1152) interleaves all three phases in one large block. Replace everything from the first `begin` of `Load_Content` (after the local declarations of the three sub-procedures above) through `end Load_Content;` with:

```ada
      begin
         UnZip.Extract (from => Zip_Info, what => "content.xml", rename => Temp_XML);

         --  Formula detection: scan content.xml for ODF formula attributes.
         --  If found, try LibreOffice to recalculate before parsing.
         if Has_Formulas_XML (Temp_XML, Is_ODF => True) then
            declare
               Converted : constant String :=
                  Convert_Via_LibreOffice (File_Name, ODF);
               OK : Boolean;
            begin
               if Converted /= "" then
                  GNAT.OS_Lib.Delete_File (Temp_XML, OK);
                  DOM.Readers.Free (Reader);
                  Parse_OOXML (Converted);
                  GNAT.OS_Lib.Delete_File (Converted, OK);
                  return;
               end if;
               if not SData.Config.Quiet_Mode then
                  Put_Line_Error
                     ("Warning: formula cells found in ODS file but LibreOffice " &
                      "is not available; using cached values.");
               end if;
            end;
         end if;

         Input_Sources.File.Open (Temp_XML, Input);
         DOM.Readers.Parse (Reader, Input);
         Doc := DOM.Readers.Get_Tree (Reader);
         Input_Sources.File.Close (Input);

         Tables := DOM.Core.Documents.Get_Elements_By_Tag_Name (Doc, "table:table");
         if Length (Tables) = 0 then
            Free (Tables); DOM.Readers.Free (Reader);
            raise SData.Script_Error with "No tables found in ODS file";
         end if;

         declare
            Target_Idx : Natural := 0;
         begin
            if Sheet_Name /= "" then
               for T in 0 .. Length (Tables) - 1 loop
                  if Get_Attribute (DOM.Core.Element (Item (Tables, T)),
                                    "table:name") = Sheet_Name
                  then
                     Target_Idx := T;
                     exit;
                  end if;
               end loop;
            end if;
            Rows := Get_Elements_By_Tag_Name
               (DOM.Core.Element (Item (Tables, Target_Idx)), "table:table-row");
         end;
         Clear;

         if Length (Rows) > 0 then
            declare
               Col_Name_Vec : Name_Vecs.Vector;
            begin
               Collect_ODF_Headers (Item (Rows, 0), Col_Name_Vec);
               Infer_And_Create_ODF_Schema
                  (Col_Name_Vec,
                   Row1_Present => Length (Rows) > 1,
                   Row1         => Item (Rows, 1));
               Load_ODF_Data_Rows (Rows, Col_Count => Column_Count);
            end;
         end if;

         Free (Rows);
         Free (Tables);
         DOM.Readers.Free (Reader);
         GNAT.OS_Lib.Delete_File (Temp_XML, Success);
      end Load_Content;
```

Note: `Col_Count` is now a local variable in `Load_ODF_Data_Rows`; remove the outer `Col_Count : Natural := 0;` declaration from `Load_Content`'s local variable section if it was only used in the old data-loading block.

- [ ] **Step 5: Build and run tests**

```bash
alr build 2>&1 | grep -E "error:|warning:" | grep -v "pragma Warnings" | head -20
```
Expected: no errors. (Some `-gnatwu` warnings for the `R_Count` loop variable in `Load_ODF_Data_Rows` may appear — suppress with `pragma Warnings (Off, R_Count);` inside the loop if needed.)

```bash
make check 2>&1 | tail -3
```
Expected: `All 128 tests passed.`

- [ ] **Step 6: Commit**

```bash
git add src/sdata-file_io.adb
git commit -m "Refactor: decompose Parse_ODF Load_Content into three named phases"
```

---

### Task 3: Decompose Parse_OOXML `Load_Sheet`

Splits the 226-line `Load_Sheet` body into three named sub-procedures, mirroring the Task 2 pattern. `Load_Sheet` becomes a 15-line orchestrator.

**Files:**
- Modify: `src/sdata-file_io.adb`

- [ ] **Step 1: Add `Collect_OOXML_Headers` nested inside `Load_Sheet`**

Inside `Load_Sheet` (after `Get_Cell_Value` and before `begin`), add:

```ada
         --  Phase 1: collect column names from the OOXML header row.
         procedure Collect_OOXML_Headers
            (Row0         : DOM.Core.Node;
             Col_Name_Vec : in out Name_Vecs.Vector) is
            Cells : DOM.Core.Node_List :=
               Get_Elements_By_Tag_Name (DOM.Core.Element (Row0), "c");
         begin
            for I in 0 .. Length (Cells) - 1 loop
               declare
                  V   : constant Value  := Get_Cell_Value (Item (Cells, I));
                  Idx : constant String :=
                     Trim (Integer (I + 1)'Img, Ada.Strings.Both);
                  Nam : constant String :=
                     (if V.Kind = Val_String
                      then SData.Values.To_String (V)
                      else "COL" & Idx);
               begin
                  Col_Name_Vec.Append
                     (To_Unbounded_String (Safe_Name (Nam, "COL" & Idx)));
               end;
            end loop;
            Free (Cells);
         end Collect_OOXML_Headers;
```

- [ ] **Step 2: Add `Infer_And_Create_OOXML_Schema` nested inside `Load_Sheet`**

Immediately after `Collect_OOXML_Headers`, add:

```ada
         --  Phase 2: infer column types from first data row; create columns.
         procedure Infer_And_Create_OOXML_Schema
            (Col_Name_Vec : Name_Vecs.Vector;
             Row1_Present : Boolean;
             Row1         : DOM.Core.Node) is
            N         : constant Natural := Natural (Col_Name_Vec.Length);
            Col_Types : Column_Type_Array (1 .. N) := (others => Col_Numeric);
         begin
            Apply_Dollar_Override (Col_Name_Vec, Col_Types);
            if Row1_Present then
               declare
                  Data_Cells : DOM.Core.Node_List :=
                     Get_Elements_By_Tag_Name (DOM.Core.Element (Row1), "c");
                  Col_Idx : Natural := 0;
               begin
                  for J in 0 .. Length (Data_Cells) - 1 loop
                     Col_Idx := Col_Idx + 1;
                     exit when Col_Idx > N;
                     if Get_Cell_Value (Item (Data_Cells, J)).Kind = Val_String then
                        Col_Types (Col_Idx) := Col_String;
                     end if;
                  end loop;
                  Free (Data_Cells);
               end;
            end if;
            for I in 1 .. N loop
               declare
                  Raw_Name   : constant String := To_String (Col_Name_Vec (I));
                  Final_Name : constant String :=
                     (if Col_Types (I) = Col_String
                         and then (Raw_Name'Length = 0
                                   or else Raw_Name (Raw_Name'Last) /= '$')
                      then Raw_Name & "$"
                      else Raw_Name);
               begin
                  Add_Column (Final_Name, Col_Types (I));
               end;
            end loop;
         end Infer_And_Create_OOXML_Schema;
```

- [ ] **Step 3: Add `Load_OOXML_Data_Rows` nested inside `Load_Sheet`**

Immediately after `Infer_And_Create_OOXML_Schema`, add:

```ada
         --  Phase 3: load data rows into the table.
         procedure Load_OOXML_Data_Rows
            (Rows      : DOM.Core.Node_List;
             Col_Count : Natural) is
            Rows_To_Skip : Natural := Skip_Rows;
            Rows_Written : Natural := 0;
         begin
            for I in 1 .. Length (Rows) - 1 loop
               exit when Max_Rows > 0 and then Rows_Written >= Max_Rows;
               if Rows_To_Skip > 0 then
                  Rows_To_Skip := Rows_To_Skip - 1;
               else
                  Rows_Written := Rows_Written + 1;
                  Add_Row;
                  declare
                     Cells : DOM.Core.Node_List :=
                        Get_Elements_By_Tag_Name
                           (DOM.Core.Element (Item (Rows, I)), "c");
                  begin
                     for J in 0 .. Length (Cells) - 1 loop
                        if J < Col_Count then
                           declare
                              V : constant Value :=
                                 Get_Cell_Value (Item (Cells, J));
                           begin
                              if V.Kind /= Val_Missing then
                                 Set_Value (Row_Count,
                                            Column_Name (J + 1), V);
                              end if;
                           exception
                              when E : others =>
                                 if not SData.Config.Quiet_Mode then
                                    Put_Line_Error
                                       ("Warning: OOXML import skipped cell at row" &
                                        Row_Count'Image &
                                        ", column """ &
                                        Column_Name (J + 1) & """: " &
                                        Ada.Exceptions.Exception_Message (E));
                                 end if;
                           end;
                        end if;
                     end loop;
                     Free (Cells);
                  end;
               end if;
            end loop;
         end Load_OOXML_Data_Rows;
```

- [ ] **Step 4: Replace the `Load_Sheet` body**

Replace everything from the `begin` of `Load_Sheet` (after the three sub-procedure declarations above) through the final `end Load_Sheet;` with:

```ada
      begin
         UnZip.Extract (from => Zip_Info, what => Sheet_XML_Path, rename => Temp_Sheet);

         --  Formula detection: scan for <f> elements.
         if Has_Formulas_XML (Temp_Sheet, Is_ODF => False) then
            declare
               Converted : constant String :=
                  Convert_Via_LibreOffice (File_Name, OOXML);
               OK : Boolean;
            begin
               if Converted /= "" then
                  GNAT.OS_Lib.Delete_File (Temp_Sheet, OK);
                  DOM.Readers.Free (Reader);
                  Parse_ODF (Converted);
                  GNAT.OS_Lib.Delete_File (Converted, OK);
                  return;
               end if;
               if not SData.Config.Quiet_Mode then
                  Put_Line_Error
                     ("Warning: formula cells found in XLSX file but LibreOffice " &
                      "is not available; using cached values.");
               end if;
            end;
         end if;

         Input_Sources.File.Open (Temp_Sheet, Input);
         DOM.Readers.Parse (Reader, Input);
         Doc := DOM.Readers.Get_Tree (Reader);
         Input_Sources.File.Close (Input);

         declare
            Merged : DOM.Core.Node_List :=
               DOM.Core.Documents.Get_Elements_By_Tag_Name (Doc, "mergeCells");
         begin
            if Length (Merged) > 0 then
               Free (Merged);
               DOM.Readers.Free (Reader);
               raise SData.Script_Error
                  with "XLSX file contains merged cells, which are not supported.";
            end if;
            Free (Merged);
         end;

         Rows := DOM.Core.Documents.Get_Elements_By_Tag_Name (Doc, "row");
         Clear;

         if Length (Rows) > 0 then
            declare
               Col_Name_Vec : Name_Vecs.Vector;
            begin
               Collect_OOXML_Headers (Item (Rows, 0), Col_Name_Vec);
               Infer_And_Create_OOXML_Schema
                  (Col_Name_Vec,
                   Row1_Present => Length (Rows) > 1,
                   Row1         => Item (Rows, 1));
               Load_OOXML_Data_Rows (Rows, Col_Count => Column_Count);
            end;
         end if;

         Free (Rows);
         DOM.Readers.Free (Reader);
         GNAT.OS_Lib.Delete_File (Temp_Sheet, Success);
      end Load_Sheet;
```

Remove the `Col_Count : Natural := 0;` declaration from `Load_Sheet`'s local variable section if it was only used in the old data-loading block.

- [ ] **Step 5: Build and run tests**

```bash
alr build 2>&1 | grep -E "error:" | head -20
```
Expected: no errors.

```bash
make check 2>&1 | tail -3
```
Expected: `All 128 tests passed.`

- [ ] **Step 6: Confirm evaluator unit tests still pass**

```bash
./bin/evaluator_unit_test 2>&1 | tail -3
```
Expected: `101 passed, 0 failed.`

- [ ] **Step 7: Commit**

```bash
git add src/sdata-file_io.adb
git commit -m "Refactor: decompose Parse_OOXML Load_Sheet into three named phases"
```

---

## Self-Review Notes

**Spec coverage:** All three objectives covered — `Detect_Inf` extraction (Task 1), `Load_Content` decomposition (Task 2), `Load_Sheet` decomposition (Task 3). `Apply_Dollar_Override` shared helper eliminates duplicate `$`-suffix code (Task 1). `Name_Vecs` hoisted to package-body scope enables sharing (Task 1).

**Placeholder scan:** None. All code blocks are complete and compilable.

**Type consistency:**
- `Column_Type_Array` declared once at package-body scope (Task 1) and used by `Infer_And_Create_ODF_Schema` (Task 2) and `Infer_And_Create_OOXML_Schema` (Task 3).
- `Name_Vecs.Vector` is the single shared type from the hoisted package (Task 1); all sub-procedures use it.
- `Apply_Dollar_Override` signature: `(Name_Vecs.Vector; in out Column_Type_Array)` — consistent across Tasks 2 and 3.

**Known Ada subtlety:** `Infer_And_Create_ODF_Schema` and `Infer_And_Create_OOXML_Schema` call `Item (Rows, 1)` for `Row1` regardless of `Row1_Present`. The `Row1` parameter is only dereferenced inside the `if Row1_Present then` branch, so this is safe. However, `Item (Rows, 1)` itself may be called with `Length(Rows) = 1` (i.e., only a header row). In DOM.Core, `Item (List, index)` where index ≥ Length returns `null`. The caller passes `Row1 => Item (Rows, 1)` inside a `if Length (Rows) > 0 then` block; when `Length(Rows) = 1`, `Item(Rows, 1)` returns `null`, but `Row1_Present` is `False`, so the `null` node is never dereferenced. This is safe but subtle — add a comment to that effect in the orchestrator body if it is not obvious.

**What this does NOT change:**
- External API of `Parse_ODF` and `Parse_OOXML` — signatures unchanged
- Error messages — all preserved verbatim
- `Has_Formulas_XML` / `Convert_Via_LibreOffice` / formula-detection paths — untouched
- `Find_Sheet_XML_Path` and `Load_Shared_Strings` in `Parse_OOXML` — untouched
- `Get_Cell_Value` helpers — only the INF-detection code inside them changes (Task 1)
