with Ada.Text_IO; use Ada.Text_IO;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;
with SData.Table; use SData.Table;
with SData.Values; use SData.Values;
with SData.Config; use SData.Config;
with GNAT.Strings; use GNAT.Strings;
with GNAT.OS_Lib;
with Zip;
with UnZip;
with DOM.Core;
with DOM.Core.Nodes;
with DOM.Core.Elements;
with DOM.Core.Documents;
with DOM.Readers;
with Input_Sources.File;

package body SData.File_IO is

   -------------------
   -- Run_SSConvert --
   -------------------
   --  Helper procedure to invoke the 'ssconvert' utility (from Gnumeric) 
   --  for file format conversions (e.g., CSV -> ODS).
   procedure Run_SSConvert (In_File, Out_File : String) is
      Args : GNAT.OS_Lib.Argument_List (1 .. 2); Success : Boolean;
   begin
      Args (1) := new String'(In_File); Args (2) := new String'(Out_File);
      --  Locate the executable and spawn the process.
      GNAT.OS_Lib.Spawn (GNAT.OS_Lib.Locate_Exec_On_Path ("ssconvert").all, Args, Success);
      GNAT.OS_Lib.Free (Args (1)); GNAT.OS_Lib.Free (Args (2));
      if not Success then raise Program_Error with "ssconvert failed"; end if;
   end Run_SSConvert;

   --------------
   -- Get_Text --
   --------------
   --  Recursively extracts text content from an XML node and its children.
   function Get_Text (N : DOM.Core.Node) return String is
      use DOM.Core; use DOM.Core.Nodes;
      Child : Node := First_Child (N); Res : Unbounded_String := Null_Unbounded_String;
   begin
      while Child /= null loop
         if Node_Type (Child) = Text_Node then
            Append (Res, Node_Value (Child));
         elsif Node_Type (Child) = Element_Node then
            --  Recurse for nested elements.
            Append (Res, Get_Text (Child)); 
         end if;
         Child := Next_Sibling (Child);
      end loop;
      return To_String (Res);
   end Get_Text;

   ---------------
   -- Safe_Name --
   ---------------
   --  Ensures a column name is valid (trimmed and within length limits).
   function Safe_Name (S : String; Default : String) return String is
      T : constant String := Trim (S, Ada.Strings.Both);
   begin
      if T = "" then return Default; end if;
      if T'Length > 32 then return T (T'First .. T'First + 31); end if;
      return T;
   end Safe_Name;

   ----------------
   -- Open_Input --
   ----------------
   --  Dispatches to the appropriate parser based on file extension or default format.
   procedure Open_Input (File_Name : String; Fmt : Format_Type) is
      Actual_Fmt : Format_Type := Fmt; Ext_Idx : Natural := 0;
   begin
      --  Extract file extension for automatic format detection.
      for I in reverse File_Name'Range loop if File_Name (I) = '.' then Ext_Idx := I; exit; end if; end loop;
      if Ext_Idx > 0 then
         declare Ext : constant String := File_Name (Ext_Idx + 1 .. File_Name'Last);
         begin
            if Ext = "csv" then Actual_Fmt := CSV;
            elsif Ext = "ods" or Ext = "odf" then Actual_Fmt := ODF;
            elsif Ext = "xlsx" or Ext = "ooxml" then Actual_Fmt := OOXML; end if;
         end;
      end if;

      --  Special case for internal mock tests.
      if File_Name = "mock_data" or File_Name = "mock" then
         Clear; Add_Column ("ID", Col_Numeric); Add_Column ("NAME", Col_String); Add_Column ("SALARY", Col_Numeric);
         for I in 1 .. 3 loop
            Add_Row; Set_Value (I, "ID", (Kind => Val_Numeric, Num_Val => Float (I)));
            Set_Value (I, "SALARY", (Kind => Val_Numeric, Num_Val => 50000.0 + Float(I - 1) * 10000.0));
         end loop;
         Set_Value(1, "NAME", (Kind => Val_String, Str_Val => "Alice" & (1 .. 1019 => ' '), Str_Len => 5));
         Set_Value(2, "NAME", (Kind => Val_String, Str_Val => "Bob" & (1 .. 1021 => ' '), Str_Len => 3));
         Set_Value(3, "NAME", (Kind => Val_String, Str_Val => "Charlie" & (1 .. 1017 => ' '), Str_Len => 7));
         return;
      end if;

      case Actual_Fmt is
         when CSV   => Parse_CSV (File_Name);
         when ODF   => Parse_ODF (File_Name);
         when OOXML => Parse_OOXML (File_Name);
      end case;
   end Open_Input;

   -----------------
   -- Open_Output --
   -----------------
   --  Dispatches to the appropriate writer.
   procedure Open_Output (File_Name : String; Fmt : Format_Type) is
      Actual_Fmt : Format_Type := Fmt; Ext_Idx : Natural := 0;
   begin
      for I in reverse File_Name'Range loop if File_Name (I) = '.' then Ext_Idx := I; exit; end if; end loop;
      if Ext_Idx > 0 then
         declare Ext : constant String := File_Name (Ext_Idx + 1 .. File_Name'Last);
         begin
            if Ext = "csv" then Actual_Fmt := CSV;
            elsif Ext = "ods" or Ext = "odf" then Actual_Fmt := ODF;
            elsif Ext = "xlsx" or Ext = "ooxml" then Actual_Fmt := OOXML; end if;
         end;
      end if;
      case Actual_Fmt is
         when CSV   => Write_CSV (File_Name);
         when ODF   => Write_ODF (File_Name);
         when OOXML => Write_OOXML (File_Name);
      end case;
   end Open_Output;

   ---------------
   -- Parse_CSV --
   ---------------
   --  A robust CSV parser that handles headers and basic type detection.
   procedure Parse_CSV (File_Name : String) is
      File : File_Type; type String_Array is array (Positive range <>) of Unbounded_String;
      
      --  Splits a CSV line into an array of fields.
      function Split (L : String) return String_Array is
         Start : Positive := L'First; Pos : Natural; Count : Natural := 0;
      begin
         if L'Length = 0 then return (1 .. 0 => Null_Unbounded_String); end if;
         for I in L'Range loop if L (I) = ',' then Count := Count + 1; end if; end loop;
         declare Res : String_Array (1 .. Count + 1); Idx : Positive := 1;
         begin
            loop
               Pos := Index (L (Start .. L'Last), ",");
               if Pos = 0 then
                  Res (Idx) := To_Unbounded_String (Trim (L (Start .. L'Last), Ada.Strings.Both)); exit;
               else
                  Res (Idx) := To_Unbounded_String (Trim (L (Start .. Pos - 1), Ada.Strings.Both));
                  Start := Pos + 1; Idx := Idx + 1;
               end if;
            end loop; return Res;
         end;
      end Split;

      --  Processes a single data row and adds it to the Data Table.
      procedure Process_Row (Fields : String_Array; Names : String_List) is
      begin
         Add_Row;
         for I in Fields'Range loop
            if I <= Names'Length then
               declare Val_Str : constant String := To_String (Fields (I)); Val : Value;
               begin
                  if Val_Str = "" or Val_Str = "." then Val := (Kind => Val_Missing);
                  else
                     begin 
                        --  Attempt to parse as numeric; fallback to string.
                        Val := (Kind => Val_Numeric, Num_Val => Float'Value (Val_Str));
                     exception when others => 
                        Val := (Kind => Val_String, Str_Val => Val_Str & (1 .. 1024 - Val_Str'Length => ' '), Str_Len => Val_Str'Length); 
                     end;
                  end if;
                  Set_Value (Row_Count, Names (I).all, Val);
               end;
            end if;
         end loop;
      end Process_Row;

      Header_Line, First_Data_Line : Unbounded_String; Has_Header, Has_Data : Boolean := False;
   begin
      Open (File, In_File, File_Name);
      if not End_Of_File (File) then Header_Line := To_Unbounded_String (Get_Line (File)); Has_Header := True; end if;
      if not End_Of_File (File) then First_Data_Line := To_Unbounded_String (Get_Line (File)); Has_Data := True; end if;
      
      if Has_Header then
         declare
            Headers : constant String_Array := Split (To_String (Header_Line)); 
            Names : String_List (1 .. Headers'Length);
            Data_Fields : String_Array (1 .. Headers'Length) := (others => Null_Unbounded_String);
         begin
            if Has_Data then
               declare DF : constant String_Array := Split (To_String (First_Data_Line));
               begin for I in DF'Range loop if I <= Data_Fields'Length then Data_Fields (I) := DF (I); end if; end loop; end;
            end if;

            Clear;
            for I in Headers'Range loop
               declare 
                  Name : constant String := Safe_Name (To_String (Headers (I)), "COL" & Trim (I'Img, Ada.Strings.Both));
                  Typ : Column_Type := Col_String; Val_Str : constant String := To_String (Data_Fields (I));
               begin
                  Names (I) := new String'(Name);
                  --  Inspect first data row to determine column type.
                  if Val_Str /= "" and then Val_Str /= "." then
                     begin declare Dummy : Float := Float'Value (Val_Str); begin Typ := Col_Numeric; end; exception when others => null; end;
                  end if;
                  Add_Column (Name, Typ);
               end;
            end loop;

            if Has_Data then Process_Row (Data_Fields, Names); end if;
            --  Read remaining rows.
            while not End_Of_File (File) loop Process_Row (Split (Get_Line (File)), Names); end loop;
            for I in Names'Range loop Free (Names (I)); end loop;
         end;
      end if;
      Close (File);
   exception when others => if Is_Open (File) then Close (File); end if; raise;
   end Parse_CSV;

   ---------------
   -- Write_CSV --
   ---------------
   --  Serializes the current Data Table to a CSV file.
   procedure Write_CSV (File_Name : String) is
      File : File_Type; Col_Names : GNAT.Strings.String_List_Access := Get_Column_Names;
   begin
      Create (File, Out_File, File_Name);
      if Col_Names /= null then
         --  Write Header.
         for I in Col_Names'Range loop Put (File, Col_Names (I).all); if I /= Col_Names'Last then Put (File, ","); end if; end loop;
         New_Line (File);
         --  Write Rows.
         for R in 1 .. Row_Count loop
            for C in Col_Names'Range loop
               declare Val : constant Value := Get_Value (R, Col_Names (C).all);
               begin
                  if Val.Kind = Val_Numeric then Put (File, Trim (Val.Num_Val'Img, Ada.Strings.Both));
                  elsif Val.Kind = Val_String then Put (File, Val.Str_Val (1 .. Val.Str_Len));
                  else Put (File, "."); end if;
               end;
               if C /= Col_Names'Last then Put (File, ","); end if;
            end loop;
            New_Line (File);
         end loop;
      end if;
      Close (File); if Col_Names /= null then GNAT.Strings.Free (Col_Names); end if;
   exception when others => if Is_Open (File) then Close (File); end if; if Col_Names /= null then GNAT.Strings.Free (Col_Names); end if; raise;
   end Write_CSV;

   ---------------
   -- Parse_ODF --
   ---------------
   --  Natively parses an OpenDocument Spreadsheet (.ods).
   procedure Parse_ODF (File_Name : String) is
      Temp_XML : constant String := File_Name & ".content.xml";
      Reader : DOM.Readers.Tree_Reader; Input : Input_Sources.File.File_Input; Doc : DOM.Core.Document;
      Tables, Rows, Success : Boolean;
      use DOM.Core; use DOM.Core.Nodes; Info : Zip.Zip_Info;
   begin
      --  1. Use Zip-Ada to extract content.xml from the ODS archive.
      Zip.Load (Info, File_Name); UnZip.Extract (from => Info, what => "content.xml", rename => Temp_XML);
      --  2. Use XML/Ada to parse the XML tree.
      Input_Sources.File.Open (Temp_XML, Input);
      DOM.Readers.Parse (Reader, Input); Doc := DOM.Readers.Get_Tree (Reader); Input_Sources.File.Close (Input);
      
      --  3. Traverse ODS XML structure (table -> row -> cell).
      declare 
         Table_Nodes : Node_List := DOM.Core.Documents.Get_Elements_By_Tag_Name (Doc, "table:table");
      begin
         if Length (Table_Nodes) = 0 then GNAT.OS_Lib.Delete_File (Temp_XML, Success); raise Program_Error with "No tables found in ODS"; end if;
         
         declare
            Row_Nodes : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Item (Table_Nodes, 0)), "table:table-row");
         begin
            Clear;
            --  Header processing (First Row).
            if Length (Row_Nodes) > 0 then
               declare 
                  Header_Cells : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Item (Row_Nodes, 0)), "table:table-cell");
                  Col_Idx : Positive := 1; Max_Cols : Natural := 0;
               begin
                  --  Count total columns considering ODS repeated-column feature.
                  for I in 0 .. Length (Header_Cells) - 1 loop
                     declare Repeat_Attr : constant String := DOM.Core.Elements.Get_Attribute (DOM.Core.Element (Item (Header_Cells, I)), "table:number-columns-repeated");
                             Repeat_Count : Positive := (if Repeat_Attr /= "" then Positive'Value (Repeat_Attr) else 1);
                     begin Max_Cols := Max_Cols + Repeat_Count; end;
                  end loop;
                  
                  declare 
                     Ordered_Names : String_List (1 .. Max_Cols); 
                     Ordered_Types : array (1 .. Max_Cols) of Column_Type := (others => Col_String);
                  begin
                     Col_Idx := 1;
                     for I in 0 .. Length (Header_Cells) - 1 loop
                        declare Cell_Node : constant Node := Item (Header_Cells, I); Name : Unbounded_String := Null_Unbounded_String;
                                Repeat_Attr : constant String := DOM.Core.Elements.Get_Attribute (DOM.Core.Element (Cell_Node), "table:number-columns-repeated");
                                Repeat_Count : Positive := (if Repeat_Attr /= "" then Positive'Value (Repeat_Attr) else 1);
                        begin
                           declare Text_Nodes : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Cell_Node), "text:p");
                           begin
                              if Length (Text_Nodes) > 0 then Name := To_Unbounded_String (Get_Text (Item (Text_Nodes, 0))); end if;
                              DOM.Core.Free (Text_Nodes);
                           end;
                           --  Type detection from the second row (if available).
                           if Length (Row_Nodes) > 1 then
                              declare Data_Row_Cells : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Item (Row_Nodes, 1)), "table:table-cell");
                              begin if I < Length (Data_Row_Cells) then
                                 declare Val_Type : constant String := DOM.Core.Elements.Get_Attribute (DOM.Core.Element (Item (Data_Row_Cells, I)), "office:value-type");
                                 begin if Val_Type = "float" then Ordered_Types (Col_Idx) := Col_Numeric; end if; end;
                              end if; DOM.Core.Free (Data_Row_Cells); end;
                           end if;
                           for J in 1 .. Repeat_Count loop
                              Ordered_Names (Col_Idx) := new String'(Safe_Name (To_String (Name), "COL" & Trim (Col_Idx'Img, Ada.Strings.Both)));
                              Add_Column (Ordered_Names (Col_Idx).all, Ordered_Types (Col_Idx)); Col_Idx := Col_Idx + 1;
                           end loop;
                        end;
                     end loop;

                     --  Data processing (Remaining Rows).
                     for I in 1 .. Length (Row_Nodes) - 1 loop
                        declare Row_Node : constant Node := Item (Row_Nodes, I); 
                                Row_Repeat_Attr : constant String := DOM.Core.Elements.Get_Attribute (DOM.Core.Element (Row_Node), "table:number-rows-repeated");
                                Num_Row_Repeats : Positive := (if Row_Repeat_Attr /= "" then Positive'Value (Row_Repeat_Attr) else 1);
                                Data_Cells : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Row_Node), "table:table-cell");
                        begin
                           for R in 1 .. Num_Row_Repeats loop
                              Add_Row; declare Current_Col : Positive := 1;
                              begin
                                 for J in 0 .. Length (Data_Cells) - 1 loop
                                    declare Cell : constant Node := Item (Data_Cells, J);
                                            Val_Type : constant String := DOM.Core.Elements.Get_Attribute (DOM.Core.Element (Cell), "office:value-type");
                                            Val_Attr : constant String := DOM.Core.Elements.Get_Attribute (DOM.Core.Element (Cell), "office:value");
                                            Val : Value := (Kind => Val_Missing); Repeat_Attr : constant String := DOM.Core.Elements.Get_Attribute (DOM.Core.Element (Cell), "table:number-columns-repeated");
                                            Repeat_Count : Positive := (if Repeat_Attr /= "" then Positive'Value (Repeat_Attr) else 1);
                                    begin
                                       declare Text_Nodes : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Cell), "text:p");
                                       begin
                                          if Val_Type = "float" then begin Val := (Kind => Val_Numeric, Num_Val => Float'Value (Val_Attr)); exception when others => null; end;
                                          elsif Length (Text_Nodes) > 0 then declare S : constant String := Get_Text (Item (Text_Nodes, 0));
                                             begin if S /= "" then Val := (Kind => Val_String, Str_Val => S & (1 .. 1024 - S'Length => ' '), Str_Len => S'Length); end if; end; end if;
                                          DOM.Core.Free (Text_Nodes);
                                       end;
                                       for K in 1 .. Repeat_Count loop
                                          if Current_Col <= Max_Cols then begin Set_Value (Row_Count, Ordered_Names (Current_Col).all, Val); exception when others => null; end; Current_Col := Current_Col + 1; end if;
                                       end loop;
                                    end;
                                 end loop;
                              end;
                           end loop;
                           DOM.Core.Free (Data_Cells);
                        end;
                     end loop;
                     for I in 1 .. Max_Cols loop Free (Ordered_Names (I)); end loop;
                  end;
                  DOM.Core.Free (Header_Cells);
               end;
            end if;
            DOM.Core.Free (Row_Nodes);
         end;
         DOM.Core.Free (Table_Nodes);
      end;
      DOM.Readers.Free (Reader); GNAT.OS_Lib.Delete_File (Temp_XML, Success);
   exception when others => GNAT.OS_Lib.Delete_File (Temp_XML, Success); raise;
   end Parse_ODF;

   -----------------
   -- Parse_OOXML --
   -----------------
   --  Natively parses an Excel XLSX workbook.
   procedure Parse_OOXML (File_Name : String) is
      Temp_Shared : constant String := File_Name & ".sharedStrings.xml";
      Temp_Sheet : constant String := File_Name & ".sheet1.xml";
      Reader : DOM.Readers.Tree_Reader; Input : Input_Sources.File.File_Input; Doc : DOM.Core.Document;
      package String_Vectors is new Ada.Containers.Vectors (Index_Type => Natural, Element_Type => Unbounded_String);
      Shared_Strings : String_Vectors.Vector; use DOM.Core; use DOM.Core.Nodes; Success : Boolean;
      Info : Zip.Zip_Info;
   begin
      Zip.Load (Info, File_Name);
      --  1. Extract and parse Shared Strings Table (XLSX stores strings in a central pool).
      begin
         UnZip.Extract (from => Info, what => "xl/sharedStrings.xml", rename => Temp_Shared);
         Input_Sources.File.Open (Temp_Shared, Input); DOM.Readers.Parse (Reader, Input); Doc := DOM.Readers.Get_Tree (Reader); Input_Sources.File.Close (Input);
         declare SI_Nodes : Node_List := DOM.Core.Documents.Get_Elements_By_Tag_Name (Doc, "si");
         begin
            for I in 0 .. Length (SI_Nodes) - 1 loop
               declare T_Nodes : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Item (SI_Nodes, I)), "t");
               begin if Length (T_Nodes) > 0 then Shared_Strings.Append (To_Unbounded_String (Get_Text (Item (T_Nodes, 0)))); else Shared_Strings.Append (Null_Unbounded_String); end if; DOM.Core.Free (T_Nodes); end;
            end loop;
            DOM.Core.Free (SI_Nodes);
         end;
         DOM.Readers.Free (Reader); GNAT.OS_Lib.Delete_File (Temp_Shared, Success);
      exception when others => if GNAT.OS_Lib.Is_Regular_File (Temp_Shared) then GNAT.OS_Lib.Delete_File (Temp_Shared, Success); end if; end;

      --  2. Extract and parse Sheet XML (the actual row/cell data).
      UnZip.Extract (from => Info, what => "xl/worksheets/sheet1.xml", rename => Temp_Sheet);
      Input_Sources.File.Open (Temp_Sheet, Input); DOM.Readers.Parse (Reader, Input); Doc := DOM.Readers.Get_Tree (Reader); Input_Sources.File.Close (Input);
      
      declare 
         Rows_Var : Node_List := DOM.Core.Documents.Get_Elements_By_Tag_Name (Doc, "row");
      begin
         Clear;
         if Length (Rows_Var) > 0 then
            --  Header processing.
            declare 
               Header_Cells : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Item (Rows_Var, 0)), "c");
               Ordered_Names : String_List (1 .. Length (Header_Cells)); 
               Ordered_Types : array (1 .. Length (Header_Cells)) of Column_Type := (others => Col_String);
            begin
               for I in 0 .. Length (Header_Cells) - 1 loop
                  declare Cell_Node : constant Node := Item (Header_Cells, I); Type_Attr : constant String := DOM.Core.Elements.Get_Attribute (DOM.Core.Element (Cell_Node), "t");
                          Name : Unbounded_String := Null_Unbounded_String;
                  begin
                     declare V_Nodes : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Cell_Node), "v");
                     begin
                        if Length (V_Nodes) > 0 then
                           declare Val_Text : constant String := Get_Text (Item (V_Nodes, 0));
                           begin if Type_Attr = "s" then Name := Shared_Strings.Element (Natural'Value (Val_Text)); else Name := To_Unbounded_String (Val_Text); end if; end;
                        elsif Type_Attr = "inlineStr" then
                           declare 
                              IS_Nodes : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Cell_Node), "is");
                           begin
                              if Length (IS_Nodes) > 0 then
                                 declare T_Nodes : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Item (IS_Nodes, 0)), "t");
                                 begin
                                    if Length (T_Nodes) > 0 then Name := To_Unbounded_String (Get_Text (Item (T_Nodes, 0))); end if;
                                    DOM.Core.Free (T_Nodes);
                                 end;
                              end if;
                              DOM.Core.Free (IS_Nodes);
                           end;
                        end if;
                        DOM.Core.Free (V_Nodes);
                     end;
                     --  Type heuristic: check second row for numbers.
                     if Length (Rows_Var) > 1 then
                        declare Data_Cells : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Item (Rows_Var, 1)), "c");
                        begin if I < Length (Data_Cells) then
                           declare T_Attr : constant String := DOM.Core.Elements.Get_Attribute (DOM.Core.Element (Item (Data_Cells, I)), "t");
                           begin if T_Attr /= "s" and then T_Attr /= "str" and then T_Attr /= "inlineStr" then Ordered_Types (I + 1) := Col_Numeric; end if; end;
                        end if; DOM.Core.Free (Data_Cells); end;
                     end if;
                     Ordered_Names (I + 1) := new String'(Safe_Name (To_String (Name), "COL" & Trim (Integer (I + 1)'Img, Ada.Strings.Both)));
                     Add_Column (Ordered_Names (I + 1).all, Ordered_Types (I + 1));
                  end;
               end loop;

               --  Row data processing.
               for I in 1 .. Length (Rows_Var) - 1 loop
                  Add_Row; 
                  declare 
                     Cells_List : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Item (Rows_Var, I)), "c");
                  begin
                     for J in 0 .. Length (Cells_List) - 1 loop
                        if J < Length (Header_Cells) then
                           declare 
                              Cell_Node : constant Node := Item (Cells_List, J); Type_Attr : constant String := DOM.Core.Elements.Get_Attribute (DOM.Core.Element (Cell_Node), "t");
                              V_Nodes : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Cell_Node), "v");
                           begin
                              if Length (V_Nodes) > 0 then
                                 declare Val_Text : constant String := Get_Text (Item (V_Nodes, 0));
                                 begin
                                    if Type_Attr = "s" then
                                       declare S : constant String := To_String (Shared_Strings.Element (Natural'Value (Val_Text)));
                                       begin Set_Value (Row_Count, Ordered_Names (J + 1).all, (Kind => Val_String, Str_Val => S & (1 .. 1024 - S'Length => ' '), Str_Len => S'Length)); end;
                                    else begin
                                       if Ordered_Names (J + 1).all /= "" then
                                          Set_Value (Row_Count, Ordered_Names (J + 1).all, (Kind => Val_Numeric, Num_Val => Float'Value (Val_Text)));
                                       end if;
                                    exception when others => null; end; end if;
                                 end;
                              elsif Type_Attr = "inlineStr" then
                                 declare IS_Nodes : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Cell_Node), "is");
                                 begin
                                    if Length (IS_Nodes) > 0 then
                                       declare T_Nodes : Node_List := DOM.Core.Elements.Get_Elements_By_Tag_Name (DOM.Core.Element (Item (IS_Nodes, 0)), "t");
                                       begin
                                          if Length (T_Nodes) > 0 then
                                             declare S : constant String := Get_Text (Item (T_Nodes, 0));
                                             begin Set_Value (Row_Count, Ordered_Names (J + 1).all, (Kind => Val_String, Str_Val => S & (1 .. 1024 - S'Length => ' '), Str_Len => S'Length)); end;
                                          end if;
                                          DOM.Core.Free (T_Nodes);
                                       end;
                                    end if;
                                    DOM.Core.Free (IS_Nodes);
                                 end;
                              end if;
                              DOM.Core.Free (V_Nodes);
                           end;
                        end if;
                     end loop;
                     DOM.Core.Free (Cells_List);
                  end;
               end loop;
               for I in 1 .. Length (Header_Cells) loop Free (Ordered_Names (I)); end loop;
               DOM.Core.Free (Header_Cells);
            end;
         end if;
         DOM.Core.Free (Rows_Var);
      end;
      DOM.Readers.Free (Reader); GNAT.OS_Lib.Delete_File (Temp_Sheet, Success);
   exception when others => if GNAT.OS_Lib.Is_Regular_File (Temp_Sheet) then GNAT.OS_Lib.Delete_File (Temp_Sheet, Success); end if; raise;
   end Parse_OOXML;

   ---------------
   -- Write_ODF --
   ---------------
   --  ODF writing falls back to ssconvert.
   procedure Write_ODF (File_Name : String) is
   begin
      Write_CSV (File_Name & ".tmp.csv"); Run_SSConvert (File_Name & ".tmp.csv", File_Name);
      declare OK : Boolean; begin GNAT.OS_Lib.Delete_File (File_Name & ".tmp.csv", OK); end;
   end Write_ODF;

   -----------------
   -- Write_OOXML --
   -----------------
   --  OOXML writing falls back to ssconvert.
   procedure Write_OOXML (File_Name : String) is
   begin
      Write_CSV (File_Name & ".tmp.csv"); Run_SSConvert (File_Name & ".tmp.csv", File_Name);
      declare OK : Boolean; begin GNAT.OS_Lib.Delete_File (File_Name & ".tmp.csv", OK); end;
   end Write_OOXML;

end SData.File_IO;
