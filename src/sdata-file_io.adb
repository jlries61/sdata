with Ada.Text_IO;
with Ada.Streams.Stream_IO;
with Ada.Streams;
with Ada.Directories;
with Ada.Strings.UTF_Encoding;             use Ada.Strings.UTF_Encoding;
with Ada.Strings.UTF_Encoding.Conversions;
with SData.Config.Runtime;
with Ada.Unchecked_Deallocation;
with Ada.Exceptions;
with SData.IO;        use SData.IO;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;
with SData.Table;     use SData.Table;
with SData.Values;    use SData.Values;
with GNAT.Strings; use GNAT.Strings;
with GNAT.OS_Lib;
with Zip;
with UnZip;
with Zip.Create;
with DOM.Core;
with DOM.Core.Nodes;
with DOM.Core.Elements;
with DOM.Core.Documents;
with DOM.Readers;
with Input_Sources.File;

package body SData.File_IO is

   --  Helper for DOM node traversal
   function Get_Text (N : DOM.Core.Node) return String is
      use DOM.Core;
      use DOM.Core.Nodes;
      Child : Node := First_Child (N);
      Res : Unbounded_String := Null_Unbounded_String;
   begin
      while Child /= null loop
         if Node_Type (Child) = Text_Node then
            Append (Res, Node_Value (Child));
         elsif Node_Type (Child) = Element_Node then
            Append (Res, Get_Text (Child));
         end if;
         Child := Next_Sibling (Child);
      end loop;
      return To_String (Res);
   end Get_Text;

   ---------------
   -- Safe_Name --
   ---------------
   function Safe_Name (S : String; Default : String) return String is
      T : constant String := Trim (S, Ada.Strings.Both);
   begin
      if T = "" then return Default; end if;
      if T'Length > 32 then return T (T'First .. T'First + 31); end if;
      return T;
   end Safe_Name;

   -- Helper to convert column index (1-based) to Excel letters (A, B, ..., Z, AA, ...)
   function Col_To_Letters (Col : Positive) return String is
      C : Natural := Col;
      Res : String (1 .. 10);
      Idx : Natural := 10;
   begin
      while C > 0 loop
         declare
            Remm : constant Natural := (C - 1) mod 26;
         begin
            Res (Idx) := Character'Val (Character'Pos ('A') + Remm);
            C := (C - 1) / 26;
            Idx := Idx - 1;
         end;
      end loop;
      return Res (Idx + 1 .. 10);
   end Col_To_Letters;

   -- Helper to escape XML special characters
   function Escape_XML (S : String) return String is
      Res : Unbounded_String := Null_Unbounded_String;
   begin
      for I in S'Range loop
         case S (I) is
            when '&'  => Append (Res, "&amp;");
            when '<'  => Append (Res, "&lt;");
            when '>'  => Append (Res, "&gt;");
            when '"'  => Append (Res, "&quot;");
            when '''  => Append (Res, "&apos;");
            when others => Append (Res, S (I));
         end case;
      end loop;
      return To_String (Res);
   end Escape_XML;

   --  Returns the base filename (without directory) of a path.
   function File_Base (File_Name : String) return String is
   begin
      for I in reverse File_Name'Range loop
         if File_Name (I) = '/' or File_Name (I) = '\' then
            return File_Name (I + 1 .. File_Name'Last);
         end if;
      end loop;
      return File_Name;
   end File_Base;

   --  Returns the stem of a filename (base name without extension).
   function File_Stem (Base : String) return String is
   begin
      for I in reverse Base'Range loop
         if Base (I) = '.' then
            return Base (Base'First .. I - 1);
         end if;
      end loop;
      return Base;
   end File_Stem;

   --  Quick scan: returns True if the named (already-extracted) XML temp file
   --  contains any spreadsheet formula marker ("<f>" or "<f " for OOXML,
   --  "table:formula=" for ODF).
   function Has_Formulas_XML (Temp_File : String; Is_ODF : Boolean) return Boolean is
      File   : Ada.Text_IO.File_Type;
      Line   : String (1 .. 8192);
      Last   : Natural;
      Marker : constant String := (if Is_ODF then "table:formula=" else "<f");
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Temp_File);
      while not Ada.Text_IO.End_Of_File (File) loop
         Ada.Text_IO.Get_Line (File, Line, Last);
         if Ada.Strings.Fixed.Index (Line (1 .. Last), Marker) > 0 then
            Ada.Text_IO.Close (File);
            return True;
         end if;
      end loop;
      Ada.Text_IO.Close (File);
      return False;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then Ada.Text_IO.Close (File); end if;
         return False;
   end Has_Formulas_XML;

   --  Attempt to recalculate formulas by converting the spreadsheet via LibreOffice
   --  headless mode.  Returns the path of the freshly-converted file (caller must
   --  delete it), or "" when LibreOffice is unavailable or the conversion fails.
   --
   --  Strategy: convert to the OPPOSITE format (xlsx→ods or ods→xlsx) so the output
   --  filename never collides with the source.  The converted file has all formulas
   --  replaced by their calculated results as cached values, which our parser reads.
   function Convert_Via_LibreOffice
     (File_Name : String; Fmt : Format_Type) return String
   is
      --  Avoid String_Access ambiguity with GNAT.Strings by qualifying explicitly.
      Soffice_Acc : GNAT.OS_Lib.String_Access :=
         GNAT.OS_Lib.Locate_Exec_On_Path ("soffice");
      Target_Ext : constant String := (if Fmt = ODF then "xlsx" else "ods");
      Dir        : constant String := "/tmp/";
      Base_Stem  : constant String := File_Stem (File_Base (File_Name));
      Converted  : constant String := Dir & Base_Stem & "." & Target_Ext;

      --  Build Argument_List with explicitly-typed access values.
      A1 : GNAT.OS_Lib.String_Access := new String'("--headless");
      A2 : GNAT.OS_Lib.String_Access := new String'("--convert-to");
      A3 : GNAT.OS_Lib.String_Access := new String'(Target_Ext);
      A4 : GNAT.OS_Lib.String_Access := new String'("--outdir");
      A5 : GNAT.OS_Lib.String_Access := new String'(Dir);
      Args : constant GNAT.OS_Lib.Argument_List := (1 => A1, 2 => A2, 3 => A3, 4 => A4, 5 => A5);
      Status : Integer;
   begin
      if Soffice_Acc = null then
         return "";
      end if;
      Status := GNAT.OS_Lib.Spawn (Soffice_Acc.all, Args);
      GNAT.OS_Lib.Free (Soffice_Acc);
      GNAT.OS_Lib.Free (A1); GNAT.OS_Lib.Free (A2); GNAT.OS_Lib.Free (A3);
      GNAT.OS_Lib.Free (A4); GNAT.OS_Lib.Free (A5);
      if Status = 0 and then GNAT.OS_Lib.Is_Regular_File (Converted) then
         return Converted;
      end if;
      return "";
   end Convert_Via_LibreOffice;

   procedure Open_Input (File_Name   : String;
                         Fmt         : Format_Type;
                         Sheet_Name  : String  := "";
                         Delimiter   : String  := ",";
                         Read_Header : Boolean := True;
                         Charset     : String  := "") is
      Actual_Fmt : Format_Type := Fmt;
      Ext_Idx : Natural := 0;
      U_Name  : constant String := To_Upper (File_Name);
   begin
      if U_Name = "MOCK" or U_Name = "MOCK_DATA" then
         Clear; Add_Column ("ID", Col_Integer); Add_Column ("NAME$", Col_String); Add_Column ("SALARY", Col_Numeric);
         for I in 1 .. 3 loop
            Add_Row; Set_Value (I, "ID", (Kind => Val_Integer, Int_Val => I));
            Set_Value (I, "SALARY", (Kind => Val_Numeric, Num_Val => 50000.0 + Float(I - 1) * 10000.0));
         end loop;
         Set_Value(1, "NAME$", (Kind => Val_String, Str_Val => To_Unbounded_String ("Alice")));
         Set_Value(2, "NAME$", (Kind => Val_String, Str_Val => To_Unbounded_String ("Bob")));
         Set_Value(3, "NAME$", (Kind => Val_String, Str_Val => To_Unbounded_String ("Charlie")));
         if not SData.Config.Quiet_Mode then
            Put_Line ("Generating mock data...");
         end if;
         return;
      end if;

      for I in reverse File_Name'Range loop
         if File_Name (I) = '.' then
            Ext_Idx := I;
            exit;
         end if;
      end loop;

      if Ext_Idx > 0 then
         declare
            Ext : constant String := File_Name (Ext_Idx + 1 .. File_Name'Last);
         begin
            if Ext = "csv" then Actual_Fmt := CSV;
            elsif Ext = "ods" or Ext = "odf" then Actual_Fmt := ODF;
            elsif Ext = "xlsx" or Ext = "ooxml" then Actual_Fmt := OOXML; end if;
         end;
      end if;

      case Actual_Fmt is
         when CSV =>
            Parse_CSV (File_Name, Delimiter, Read_Header, Charset);
         when ODF =>
            Parse_ODF (File_Name, Sheet_Name);
         when OOXML =>
            Parse_OOXML (File_Name, Sheet_Name);
      end case;

      if not SData.Config.Quiet_Mode then
         Put_Line ("Dataset opened: " & File_Name);
      end if;
   end Open_Input;

   -----------------
   -- Open_Output --
   -----------------
   procedure Open_Output (File_Name       : String;
                          Fmt             : Format_Type;
                          Sheet_Name      : String  := "";
                          Delimiter       : String  := ",";
                          Write_Header    : Boolean := True;
                          Allow_Overwrite : Boolean := True;
                          Charset         : String  := "") is
      Actual_Fmt : Format_Type := Fmt;
      Ext_Idx : Natural := 0;
      Sname   : constant String := (if Sheet_Name = "" then "Sheet1" else Sheet_Name);
   begin
      for I in reverse File_Name'Range loop
         if File_Name (I) = '.' then
            Ext_Idx := I;
            exit;
         end if;
      end loop;

      if Ext_Idx > 0 then
         declare
            Ext : constant String := File_Name (Ext_Idx + 1 .. File_Name'Last);
         begin
            if Ext = "csv" then Actual_Fmt := CSV;
            elsif Ext = "ods" or Ext = "odf" then Actual_Fmt := ODF;
            elsif Ext = "xlsx" or Ext = "ooxml" then Actual_Fmt := OOXML; end if;
         end;
      end if;

      case Actual_Fmt is
         when CSV =>
            Write_CSV (File_Name, Delimiter, Write_Header, Allow_Overwrite, Charset);
         when ODF =>
            Write_ODF (File_Name, Sname);
         when OOXML =>
            Write_OOXML (File_Name, Sname);
      end case;
   end Open_Output;

   ---------------
   -- Parse_CSV --
   ---------------
   procedure Parse_CSV (File_Name   : String;
                        Delimiter   : String  := ",";
                        Read_Header : Boolean := True;
                        Charset     : String  := "") is
      File : Ada.Text_IO.File_Type;

      --  Charset handling: buffered path for UTF-16, ASCII validation flag.
      package Line_Vecs is new Ada.Containers.Vectors (Positive, Unbounded_String);
      All_Lines       : Line_Vecs.Vector;
      All_Lines_Idx   : Natural := 0;
      Is_Buffered     : Boolean := False;
      Needs_ASCII_Chk : Boolean := False;

      procedure Validate_ASCII (S : String) is
      begin
         for I in S'Range loop
            if Character'Pos (S (I)) > 127 then
               SData.IO.Put_Line_Error
                  ("Warning: non-ASCII byte (value" &
                   Integer'Image (Character'Pos (S (I))) &
                   ") found in """ & File_Name & """");
               return;
            end if;
         end loop;
      end Validate_ASCII;

      procedure Split_Into_Lines (S : String) is
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

      --  Single heap-allocated line buffer shared for the entire parse.
      --  1 MB handles all real-world CSV lines; lines longer than this
      --  are not supported (Get_Line will truncate and subsequent calls
      --  will read the remainder as the next "line", producing garbled data).
      Max_Line : constant := 1_048_576;
      subtype Line_Buf_T is String (1 .. Max_Line);
      type    Line_Buf_Access is access Line_Buf_T;
      procedure Free_Buf is new
         Ada.Unchecked_Deallocation (Line_Buf_T, Line_Buf_Access);

      Line_Buf  : Line_Buf_Access := new Line_Buf_T;
      Line_Last : Natural := 0;

      --  Fast decimal parser: handles integers and simple N.M decimals
      --  without invoking the Ada runtime.  Scientific notation and other
      --  edge cases fall through to Float'Value.
      --  Returns True and sets Result for any valid floating-point value.
      --  Returns False only if the string cannot represent a number.
      function Try_Fast_Float (S : String; Result : out Float) return Boolean is
         I         : Integer := S'First;
         Whole     : Float   := 0.0;
         Frac      : Float   := 0.0;
         Denom     : Float   := 1.0;
         Sign      : Float   := 1.0;
         After_Dot : Boolean := False;
         Has_Digit : Boolean := False;
      begin
         if I > S'Last then return False; end if;
         if    S (I) = '-' then Sign := -1.0; I := I + 1;
         elsif S (I) = '+' then               I := I + 1;
         end if;
         while I <= S'Last loop
            case S (I) is
               when '0' .. '9' =>
                  Has_Digit := True;
                  if After_Dot then
                     Denom := Denom * 10.0;
                     Frac  := Frac + Float (Character'Pos (S (I)) - 48) / Denom;
                  else
                     Whole := Whole * 10.0 + Float (Character'Pos (S (I)) - 48);
                  end if;
               when '.' =>
                  if After_Dot then return False; end if;
                  After_Dot := True;
               when 'E' | 'e' | 'D' | 'd' =>
                  --  Scientific notation: fall back to Ada runtime.
                  begin
                     Result := Float'Value (S);
                     return True;
                  exception
                     when others => return False;
                  end;
               when others => return False;
            end case;
            I := I + 1;
         end loop;
         if not Has_Digit then return False; end if;
         Result := Sign * (Whole + Frac);
         return True;
      end Try_Fast_Float;

      --  Scan forward from Pos, honouring quote-enclosed fields.
      --  Returns the position of the first byte of the delimiter that ends the
      --  field, or 0 if no delimiter was found (final field).  Supports
      --  multi-character delimiters.  Quoted fields follow the spec: same-type
      --  doubled quotes are treated as a literal quote; the opposite quote type
      --  is taken literally inside a quoted field.
      DLen : constant Positive :=
         (if Delimiter'Length > 0 then Delimiter'Length else 1);

      function At_Delimiter (Line : String; Pos : Positive) return Boolean is
      begin
         if Pos + DLen - 1 > Line'Last then return False; end if;
         if DLen = 1 then return Line (Pos) = Delimiter (Delimiter'First); end if;
         return Line (Pos .. Pos + DLen - 1) = Delimiter;
      end At_Delimiter;

      function CSV_Field_End (Line : String; From : Positive) return Natural is
         I : Positive := From;
         Q : Character;
      begin
         if I > Line'Last then return 0; end if;
         if Line (I) = '"' or else Line (I) = ''' then
            Q := Line (I);
            I := I + 1;
            while I <= Line'Last loop
               if Line (I) = Q then
                  if I < Line'Last and then Line (I + 1) = Q then
                     I := I + 2;   --  doubled quote → literal
                  else
                     I := I + 1;   --  closing quote
                     exit;
                  end if;
               else
                  I := I + 1;
               end if;
            end loop;
            --  After the closing quote, the next chars must be the delimiter.
            if At_Delimiter (Line, I) then return I; end if;
            return 0;
         else
            for K in From .. Line'Last loop
               if At_Delimiter (Line, K) then return K; end if;
            end loop;
            return 0;
         end if;
      end CSV_Field_End;

      --  Extract the unquoted, unescaped value from a raw CSV field slice.
      --  For quoted fields: strips surrounding quotes and collapses doubled
      --  same-type quotes.  For unquoted fields: returns Trim(Raw).
      function CSV_Unquote (Raw : String) return String is
         T : constant String := Trim (Raw, Ada.Strings.Both);
         Q : Character;
         R : Unbounded_String;
         I : Positive;
      begin
         if T'Length >= 2
            and then (T (T'First) = '"' or else T (T'First) = ''')
            and then T (T'Last) = T (T'First)
         then
            Q := T (T'First);
            I := T'First + 1;
            while I <= T'Last - 1 loop
               if T (I) = Q and then I < T'Last - 1 and then T (I + 1) = Q then
                  Append (R, Q);
                  I := I + 2;
               else
                  Append (R, T (I));
                  I := I + 1;
               end if;
            end loop;
            return To_String (R);
         end if;
         return T;
      end CSV_Unquote;

      --  Process one CSV line with RFC-4180-style quote handling.
      procedure Process_Line_Direct (Line : String; Names : String_List) is
         Start       : Integer := Line'First;
         Field_Count : Natural := 0;
      begin
         Add_Row;
         loop
            declare
               Delim_Pos : constant Natural := CSV_Field_End (Line, Start);
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

      --  Determine whether a field string is numeric (for NSCAN type detection).
      function Is_Numeric_Field (F : String) return Boolean is
         Dummy : Float;
      begin
         return Try_Fast_Float (F, Dummy);
      end Is_Numeric_Field;

      --  Parse a CSV line into up to Max_Fields field slices stored as
      --  (start, end) index pairs into the Line string.  Used only during
      --  the NSCAN type-detection phase (at most 20 rows).
      Max_Fields : constant := 65536;
      type Field_Pair is record S, E : Natural; end record;
      type Field_Array is array (1 .. Max_Fields) of Field_Pair;

      function Split_Indices (Line : String; N_Fields : out Natural)
         return Field_Array
      is
         Res   : Field_Array;
         Start : Integer := Line'First;
         Count : Natural := 0;
      begin
         N_Fields := 0;
         if Line'Length = 0 then return Res; end if;
         loop
            declare
               Delim : constant Natural := CSV_Field_End (Line, Start);
            begin
               Count := Count + 1;
               if Count <= Max_Fields then
                  Res (Count).S := Start;
                  Res (Count).E := (if Delim > 0 then Delim - 1 else Line'Last);
               end if;
               exit when Delim = 0;
               Start := Delim + DLen;
            end;
         end loop;
         N_Fields := Count;
         return Res;
      end Split_Indices;

      Has_File_Header : Boolean := False;
      NSCAN       : constant := 20;

      --  Store up to NSCAN scan lines as Unbounded_Strings for type detection.
      --  Only 20 rows — the allocation cost is negligible.
      type UB_Array is array (1 .. NSCAN) of Unbounded_String;
      Scan_Lines  : UB_Array;
      Scan_Count  : Natural := 0;
      Header_Line : Unbounded_String;

      --  Inner helper: detect types, build columns, and stream data rows.
      procedure Load_Columns_And_Data
         (H_Str  : String;
          Names_From_Header : Boolean)
      is
         N_Hdr : Natural;
         H_Idx : constant Field_Array := Split_Indices (H_Str, N_Hdr);
         Names : String_List (1 .. N_Hdr);
         Col_Determined : array (1 .. N_Hdr) of Boolean     := (others => False);
         Col_Types      : array (1 .. N_Hdr) of Column_Type := (others => Col_Numeric);
      begin
         --  Per spec: a column whose header already ends in "$" is forced character.
         if Names_From_Header then
            for I in 1 .. N_Hdr loop
               declare
                  Raw : constant String :=
                     Trim (H_Str (H_Idx (I).S .. H_Idx (I).E), Ada.Strings.Both);
               begin
                  if Raw'Length > 0 and then Raw (Raw'Last) = '$' then
                     Col_Types (I) := Col_String;
                     Col_Determined (I) := True;
                  end if;
               end;
            end loop;
         end if;

         --  Detect column types from up to NSCAN scan rows.
         for R in 1 .. Scan_Count loop
            declare
               D_Str : constant String := To_String (Scan_Lines (R));
               N_Fld : Natural;
               D_Idx : constant Field_Array := Split_Indices (D_Str, N_Fld);
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

         Clear;
         for I in 1 .. N_Hdr loop
            declare
               Base_Name : constant String :=
                  (if Names_From_Header
                   then Safe_Name (CSV_Unquote (H_Str (H_Idx (I).S .. H_Idx (I).E)),
                                   "COL" & Trim (I'Img, Ada.Strings.Both))
                   else "COL" & Trim (I'Img, Ada.Strings.Both));
               --  Per spec: append "$" to string column names that don't already end in "$"
               Name : constant String :=
                  (if Col_Types (I) = Col_String
                      and then (Base_Name'Length = 0
                                or else Base_Name (Base_Name'Last) /= '$')
                   then Base_Name & "$"
                   else Base_Name);
            begin
               Names (I) := new String'(Name);
               Add_Column (Name, Col_Types (I));
            end;
         end loop;

         if Names_From_Header and then Scan_Count = 0 then
            SData.IO.Put_Line_Error
               ("Warning: File contains a header but no data records.");
         end if;

         --  Process buffered scan lines (all of them when no-header mode).
         for R in 1 .. Scan_Count loop
            Process_Line_Direct (To_String (Scan_Lines (R)), Names);
         end loop;

         --  Process remaining lines (text file or pre-loaded buffer).
         if Is_Buffered then
            while All_Lines_Idx < Natural (All_Lines.Length) loop
               All_Lines_Idx := All_Lines_Idx + 1;
               Process_Line_Direct (To_String (All_Lines (All_Lines_Idx)), Names);
            end loop;
         else
            while not Ada.Text_IO.End_Of_File (File) loop
               Ada.Text_IO.Get_Line (File, Line_Buf.all, Line_Last);
               if Needs_ASCII_Chk then
                  Validate_ASCII (Line_Buf (1 .. Line_Last));
               end if;
               Process_Line_Direct (Line_Buf (1 .. Line_Last), Names);
            end loop;
         end if;

         for I in Names'Range loop Free (Names (I)); end loop;
      end Load_Columns_And_Data;

   begin
      --  Charset setup: determine encoding and load whole file for UTF-16.
      declare
         use Ada.Streams;
         UC : constant String := To_Upper (Trim (Charset, Ada.Strings.Both));

         procedure Load_As_UTF16
            (Scheme : Ada.Strings.UTF_Encoding.Encoding_Scheme)
         is
            F    : Ada.Streams.Stream_IO.File_Type;
            Sz   : constant Ada.Directories.File_Size :=
               Ada.Directories.Size (File_Name);
            Buf  : Ada.Streams.Stream_Element_Array
               (1 .. Ada.Streams.Stream_Element_Offset (Sz));
            Last : Ada.Streams.Stream_Element_Offset;
            Raw  : String (1 .. Natural (Sz));
         begin
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
               Split_Into_Lines (UTF8 (Start_At .. UTF8'Last));
               Is_Buffered := True;
            end;
         exception
            when others =>
               if Ada.Streams.Stream_IO.Is_Open (F) then
                  Ada.Streams.Stream_IO.Close (F);
               end if;
               raise;
         end Load_As_UTF16;

         procedure Detect_And_Load is
            F      : Ada.Streams.Stream_IO.File_Type;
            Detect : Ada.Streams.Stream_Element_Array (1 .. 4);
            Last   : Ada.Streams.Stream_Element_Offset;
         begin
            Ada.Streams.Stream_IO.Open
               (F, Ada.Streams.Stream_IO.In_File, File_Name);
            Ada.Streams.Stream_IO.Read (F, Detect, Last);
            Ada.Streams.Stream_IO.Close (F);
            if Last >= 2
               and then Detect (1) = 16#FF# and then Detect (2) = 16#FE#
            then
               Load_As_UTF16 (Ada.Strings.UTF_Encoding.UTF_16LE);
            elsif Last >= 2
               and then Detect (1) = 16#FE# and then Detect (2) = 16#FF#
            then
               Load_As_UTF16 (Ada.Strings.UTF_Encoding.UTF_16BE);
            end if;
         exception
            when others =>
               if Ada.Streams.Stream_IO.Is_Open (F) then
                  Ada.Streams.Stream_IO.Close (F);
               end if;
               raise;
         end Detect_And_Load;

      begin
         if UC = "UTF-16" or else UC = "UTF-16LE" then
            Load_As_UTF16 (Ada.Strings.UTF_Encoding.UTF_16LE);
         elsif UC = "UTF-16BE" then
            Load_As_UTF16 (Ada.Strings.UTF_Encoding.UTF_16BE);
         elsif UC = "" or else UC = "AUTO" then
            Detect_And_Load;
         elsif UC = "ASCII" then
            Needs_ASCII_Chk := True;
         end if;
      end;

      --  Open text file for non-buffered (ASCII / UTF-8 / no charset) path.
      if not Is_Buffered then
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, File_Name);
      end if;

      if Is_Buffered then
         --  Header and scan lines come from the pre-loaded buffer.
         if Read_Header and then Natural (All_Lines.Length) >= 1 then
            Header_Line     := All_Lines (1);
            Has_File_Header := True;
            All_Lines_Idx   := 1;
         end if;
         while All_Lines_Idx < Natural (All_Lines.Length)
            and then Scan_Count < NSCAN
         loop
            All_Lines_Idx := All_Lines_Idx + 1;
            Scan_Count    := Scan_Count + 1;
            Scan_Lines (Scan_Count) := All_Lines (All_Lines_Idx);
         end loop;
      else
         if Read_Header then
            --  Read the first line as a named header; strip UTF-8 BOM if present.
            if not Ada.Text_IO.End_Of_File (File) then
               Ada.Text_IO.Get_Line (File, Line_Buf.all, Line_Last);
               declare
                  L : constant String := Line_Buf (1 .. Line_Last);
               begin
                  if L'Length >= 3
                     and then L (L'First .. L'First + 2) = BOM_8
                  then
                     Header_Line :=
                        To_Unbounded_String (L (L'First + 3 .. L'Last));
                  else
                     Header_Line := To_Unbounded_String (L);
                  end if;
               end;
               Has_File_Header := True;
            end if;
         end if;

         --  Buffer up to NSCAN data lines for column-type detection.
         while not Ada.Text_IO.End_Of_File (File)
            and then Scan_Count < NSCAN
         loop
            Ada.Text_IO.Get_Line (File, Line_Buf.all, Line_Last);
            if Needs_ASCII_Chk then
               Validate_ASCII (Line_Buf (1 .. Line_Last));
            end if;
            Scan_Count := Scan_Count + 1;
            Scan_Lines (Scan_Count) :=
               To_Unbounded_String (Line_Buf (1 .. Line_Last));
         end loop;
      end if;

      if Has_File_Header then
         Load_Columns_And_Data (To_String (Header_Line), Names_From_Header => True);
      elsif Scan_Count > 0 then
         --  No header: synthesise column names from the first data row's field count.
         Load_Columns_And_Data (To_String (Scan_Lines (1)), Names_From_Header => False);
      end if;

      Free_Buf (Line_Buf);
      if Ada.Text_IO.Is_Open (File) then Ada.Text_IO.Close (File); end if;
   exception
      when others =>
         Free_Buf (Line_Buf);
         if Ada.Text_IO.Is_Open (File) then Ada.Text_IO.Close (File); end if;
         raise;
   end Parse_CSV;

   ---------------
   -- Write_CSV --
   ---------------
   procedure Write_CSV (File_Name       : String;
                        Delimiter       : String  := ",";
                        Write_Header    : Boolean := True;
                        Allow_Overwrite : Boolean := True;
                        Charset         : String  := "") is
      use Ada.Directories;

      TXTFMT_Len : constant Natural := SData.Config.Runtime.Options_TXTFMT_Len;
      TXTFMT_Raw : constant String  :=
         (if TXTFMT_Len > 0 then SData.Config.Runtime.Options_TXTFMT (1 .. TXTFMT_Len)
          else "AUTO");
      EOL : constant String :=
         (if    TXTFMT_Raw = "CRLF" then "" & ASCII.CR & ASCII.LF
          elsif TXTFMT_Raw = "CR"   then "" & ASCII.CR
          else                           "" & ASCII.LF);

      Eff_Charset  : constant String :=
         To_Upper (Trim (Charset, Ada.Strings.Both));
      Is_UTF16     : constant Boolean :=
         Eff_Charset = "UTF-16" or else
         Eff_Charset = "UTF-16LE" or else
         Eff_Charset = "UTF-16BE";
      Is_UTF16BE_W : constant Boolean := Eff_Charset = "UTF-16BE";
      Is_ASCII_Chk : constant Boolean := Eff_Charset = "ASCII";
      Out_Scheme   : constant Ada.Strings.UTF_Encoding.Encoding_Scheme :=
         (if Is_UTF16BE_W
          then Ada.Strings.UTF_Encoding.UTF_16BE
          else Ada.Strings.UTF_Encoding.UTF_16LE);
      Out_BOM      : constant String :=
         (if Is_UTF16 then (if Is_UTF16BE_W then BOM_16BE else BOM_16LE)
          else "");

      File  : Ada.Streams.Stream_IO.File_Type;
      Strm  : Ada.Streams.Stream_IO.Stream_Access;
      N     : constant Natural := Column_Count;
      D_Str : constant String := Delimiter;

      procedure Write_String (S : String) is
      begin
         if Is_UTF16 then
            String'Write (Strm,
               Ada.Strings.UTF_Encoding.Conversions.Convert
                  (S, Ada.Strings.UTF_Encoding.UTF_8, Out_Scheme));
         else
            if Is_ASCII_Chk then
               for I in S'Range loop
                  if Character'Pos (S (I)) > 127 then
                     SData.IO.Put_Line_Error
                        ("Warning: non-ASCII byte (value" &
                         Integer'Image (Character'Pos (S (I))) &
                         ") in output for """ & File_Name & """");
                     exit;
                  end if;
               end loop;
            end if;
            String'Write (Strm, S);
         end if;
      end Write_String;

   begin
      if not Allow_Overwrite and then Exists (File_Name) then
         SData.IO.Put_Line_Error
            ("Error: SAVE aborted — file already exists: " & File_Name &
             " (use OPTIONS SAVEOVERWRT YES to allow overwriting)");
         raise Save_Refused;
      end if;
      Ada.Streams.Stream_IO.Create (File, Ada.Streams.Stream_IO.Out_File, File_Name);
      Strm := Ada.Streams.Stream_IO.Stream (File);
      if Is_UTF16 then
         String'Write (Strm, Out_BOM);
      end if;
      if N > 0 then
         if Write_Header then
            for I in 1 .. N loop
               Write_String (Column_Name (I));
               if I /= N then Write_String (D_Str); end if;
            end loop;
            Write_String (EOL);
         end if;
         for R in 1 .. Row_Count loop
            for C in 1 .. N loop
               declare
                  Val : constant Value := Get_Value_Upper (R, Column_Name (C));
               begin
                  if Val.Kind = Val_Numeric then
                     Write_String (Trim (Val.Num_Val'Img, Ada.Strings.Both));
                  elsif Val.Kind = Val_Integer then
                     Write_String (Trim (Val.Int_Val'Img, Ada.Strings.Both));
                  elsif Val.Kind = Val_String then
                     Write_String (SData.Values.To_String (Val));
                  end if;
                  --  Missing values: write nothing (consecutive delimiters per spec)
               end;
               if C /= N then Write_String (D_Str); end if;
            end loop;
            Write_String (EOL);
         end loop;
      end if;
      Ada.Streams.Stream_IO.Close (File);
   exception
      when others =>
         if Ada.Streams.Stream_IO.Is_Open (File) then
            Ada.Streams.Stream_IO.Close (File);
         end if;
         raise;
   end Write_CSV;

   ------------------
   --  Parse_ODF  --
   ------------------
   procedure Parse_ODF (File_Name : String; Sheet_Name : String := "") is
      use DOM.Core;
      use DOM.Core.Nodes;
      use DOM.Core.Elements;

      Temp_XML : constant String := File_Name & ".content.xml";

      procedure Load_Content (Zip_Info : Zip.Zip_Info) is
         package Name_Vecs is new Ada.Containers.Vectors (Positive, Unbounded_String);
         Reader : DOM.Readers.Tree_Reader;
         Input  : Input_Sources.File.File_Input;
         Doc    : DOM.Core.Document;
         Tables, Rows, Cells : Node_List;
         Success : Boolean;
         Col_Count : Natural := 0;

         function Get_Cell_Value (Cell_Node : Node) return Value is
            Val_Type : constant String := Get_Attribute (DOM.Core.Element (Cell_Node), "office:value-type");
            P_List   : Node_List := Get_Elements_By_Tag_Name (DOM.Core.Element (Cell_Node), "text:p");
         begin
            if Val_Type = "float" or Val_Type = "currency" or Val_Type = "percentage" then
               declare
                  V_Attr : constant String := Get_Attribute (DOM.Core.Element (Cell_Node), "office:value");
               begin
                  Free (P_List);
                  begin
                     return (Kind => Val_Numeric, Num_Val => Float'Value (V_Attr));
                  exception
                     when others => return (Kind => Val_Missing);
                  end;
               end;
            elsif Length (P_List) > 0 then
               declare
                  S : constant String := Get_Text (Item (P_List, 0));
               begin
                  Free (P_List);
                  return (Kind => Val_String, Str_Val => To_Unbounded_String (S));
               end;
            end if;
            Free (P_List);
            return (Kind => Val_Missing);
         end Get_Cell_Value;

      begin
         UnZip.Extract (from => Zip_Info, what => "content.xml", rename => Temp_XML);

         --  Formula detection: scan content.xml for ODF formula attributes.
         --  If found, try LibreOffice to recalculate before parsing.
         if Has_Formulas_XML (Temp_XML, Is_ODF => True) then
            declare
               Converted : constant String :=
                  Convert_Via_LibreOffice (File_Name, ODF);
               OK        : Boolean;
            begin
               if Converted /= "" then
                  --  Re-entered via the converted xlsx; clean up and return.
                  GNAT.OS_Lib.Delete_File (Temp_XML, OK);
                  DOM.Readers.Free (Reader);
                  Parse_OOXML (Converted);
                  GNAT.OS_Lib.Delete_File (Converted, OK);
                  return;
               end if;
               if not SData.Config.Quiet_Mode then
                  Put_Line_Error ("Warning: formula cells found in ODS file but LibreOffice " &
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
            raise Program_Error with "No tables found in ODS file";
         end if;

         --  Select the target table: by name if Sheet_Name is non-empty,
         --  otherwise use the first table found.
         declare
            Target_Idx : Natural := 0; -- 0-based index into Tables
         begin
            if Sheet_Name /= "" then
               for T in 0 .. Length (Tables) - 1 loop
                  if Get_Attribute (DOM.Core.Element (Item (Tables, T)), "table:name") = Sheet_Name then
                     Target_Idx := T;
                     exit;
                  end if;
               end loop;
               --  If name not found, fall back silently to first sheet (index 0).
            end if;
            Rows := Get_Elements_By_Tag_Name (DOM.Core.Element (Item (Tables, Target_Idx)), "table:table-row");
         end;
         Clear;

         if Length (Rows) > 0 then
            --  Collect column names from header row, infer types from first
            --  data row, then create columns with the correct types.
            declare
               Col_Name_Vec : Name_Vecs.Vector;
            begin
            Cells := Get_Elements_By_Tag_Name (DOM.Core.Element (Item (Rows, 0)), "table:table-cell");
            for I in 0 .. Length (Cells) - 1 loop
               declare
                  Cell : constant Node := Item (Cells, I);
                  Col_Spanned : constant String := Get_Attribute (DOM.Core.Element (Cell), "table:number-columns-spanned");
                  Row_Spanned : constant String := Get_Attribute (DOM.Core.Element (Cell), "table:number-rows-spanned");
               begin
                  if (Col_Spanned /= "" and then Positive'Value (Col_Spanned) > 1) or else
                     (Row_Spanned /= "" and then Positive'Value (Row_Spanned) > 1) then
                     Free (Cells); DOM.Readers.Free (Reader);
                     raise SData.Script_Error with "ODS file contains merged cells, which are not supported.";
                  end if;

                  declare
                     Repeat_Attr   : constant String   := Get_Attribute (DOM.Core.Element (Cell), "table:number-columns-repeated");
                  Repeat_Count  : constant Positive := (if Repeat_Attr = "" then 1 else Positive'Value (Repeat_Attr));
                  P_Nodes_Local : Node_List := Get_Elements_By_Tag_Name (DOM.Core.Element (Cell), "text:p");
                  Base_Name     : constant String   := (if Length (P_Nodes_Local) > 0 then Get_Text (Item (P_Nodes_Local, 0)) else "");
               begin
                  Free (P_Nodes_Local);
                  for K in 1 .. Repeat_Count loop
                     exit when Base_Name = "" and K > 1;
                     declare
                        Idx_Num    : constant Natural := Natural (Col_Name_Vec.Length) + 1;
                        Idx        : constant String := Trim (Idx_Num'Img, Ada.Strings.Both);
                        Final_Name : constant String := (if Base_Name = "" then "COL" & Idx
                                                         else Base_Name & (if Repeat_Count > 1 then "_" & Trim (K'Img, Ada.Strings.Both) else ""));
                     begin
                        Col_Name_Vec.Append (To_Unbounded_String (Safe_Name (Final_Name, "COL" & Idx)));
                     end;
                  end loop;
               end;
            end;
            end loop;
            Free (Cells);

            --  Infer column types from the first data row using ODF's explicit
            --  office:value-type attribute.  Default to Col_Numeric; switch to
            --  Col_String only when a cell value is non-numeric.
            declare
               N         : constant Natural := Positive (Col_Name_Vec.Length);
               Col_Types : array (1 .. N) of Column_Type := (others => Col_Numeric);
               Data_Cells : Node_List;
               Col_Idx    : Natural := 0;
            begin
               --  Per spec: column names already ending in "$" are forced character.
               for I in 1 .. N loop
                  declare
                     Raw : constant String := To_String (Col_Name_Vec (I));
                  begin
                     if Raw'Length > 0 and then Raw (Raw'Last) = '$' then
                        Col_Types (I) := Col_String;
                     end if;
                  end;
               end loop;
               if Length (Rows) > 1 then
                  Data_Cells := Get_Elements_By_Tag_Name (DOM.Core.Element (Item (Rows, 1)), "table:table-cell");
                  for J in 0 .. Length (Data_Cells) - 1 loop
                     Col_Idx := Col_Idx + 1;
                     exit when Col_Idx > N;
                     declare V : constant Value := Get_Cell_Value (Item (Data_Cells, J)); begin
                        if V.Kind = Val_String then Col_Types (Col_Idx) := Col_String; end if;
                     end;
                  end loop;
                  Free (Data_Cells);
               end if;
               for I in 1 .. N loop
                  declare
                     Raw_Name  : constant String := To_String (Col_Name_Vec (I));
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
            end;
            Col_Count := Column_Count;

            -- Data Rows
            for I in 1 .. Length (Rows) - 1 loop
               declare
                  Row_Node : constant Node := Item (Rows, I);
                  Row_Repeat_Attr : constant String := Get_Attribute (DOM.Core.Element (Row_Node), "table:number-rows-repeated");
                  Row_Repeat_Count : constant Positive := (if Row_Repeat_Attr = "" then 1 else Positive'Value (Row_Repeat_Attr));
               begin
                  -- Heuristic: If we see a huge number of repeated rows, it's usually just empty padding at the end of the sheet
                  exit when Row_Repeat_Count > 1000;

                  for R_Count in 1 .. Row_Repeat_Count loop
                     Add_Row;
                     Cells := Get_Elements_By_Tag_Name (DOM.Core.Element (Row_Node), "table:table-cell");
                     declare
                        Col_Idx : Positive := 1;
                     begin
                        for J in 0 .. Length (Cells) - 1 loop
                           declare
                              Cell : constant Node := Item (Cells, J);
                              Repeat_Attr : constant String := Get_Attribute (DOM.Core.Element (Cell), "table:number-columns-repeated");
                              Repeat_Count : constant Positive := (if Repeat_Attr = "" then 1 else Positive'Value (Repeat_Attr));
                              Val : constant Value := Get_Cell_Value (Cell);
                           begin
                              for K in 1 .. Repeat_Count loop
                                 if Col_Idx <= Col_Count then
                                    if Val.Kind /= Val_Missing then
                                       begin
                                          Set_Value (Row_Count, Column_Name (Col_Idx), Val);
                                       exception
                                          when E : others =>
                                             if not SData.Config.Quiet_Mode then
                                                Put_Line_Error ("Warning: ODF import skipped cell at row" &
                                                   Row_Count'Image & ", column """ &
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
                     end;
                     Free (Cells);
                  end loop;
               end;
            end loop;
         end;
         end if;

         Free (Rows);
         Free (Tables);
         DOM.Readers.Free (Reader);
         GNAT.OS_Lib.Delete_File (Temp_XML, Success);
      end Load_Content;

      Zip_Info : Zip.Zip_Info;
   begin
      Zip.Load (Zip_Info, File_Name);
      Load_Content (Zip_Info);
   exception
      when E : others =>
         if GNAT.OS_Lib.Is_Regular_File (Temp_XML) then declare OK : Boolean; begin GNAT.OS_Lib.Delete_File (Temp_XML, OK); end; end if;
         raise Program_Error with "Failed to parse ODS file """ & File_Name & """: " &
            Ada.Exceptions.Exception_Message (E);
   end Parse_ODF;

   -----------------
   -- Parse_OOXML --
   -----------------
   procedure Parse_OOXML (File_Name : String; Sheet_Name : String := "") is
      use DOM.Core;
      use DOM.Core.Nodes;
      use DOM.Core.Elements;

      Temp_Shared   : constant String := File_Name & ".sharedStrings.xml";
      Temp_Sheet    : constant String := File_Name & ".sheet.xml";
      Temp_Workbook : constant String := File_Name & ".workbook.xml";
      Temp_Rels     : constant String := File_Name & ".workbook.rels.xml";

      package String_Vectors is new Ada.Containers.Vectors (Index_Type => Natural, Element_Type => Unbounded_String);
      Shared_Strings : String_Vectors.Vector;

      --  Resolve the zip-internal path for the target sheet.
      --  Parses xl/workbook.xml to find the r:id for the named (or first) sheet,
      --  then resolves it through xl/_rels/workbook.xml.rels.
      function Find_Sheet_XML_Path (Zip_Info : Zip.Zip_Info) return String is
         WB_Reader : DOM.Readers.Tree_Reader;
         WB_Input  : Input_Sources.File.File_Input;
         WB_Doc    : DOM.Core.Document;
         Sheets    : Node_List;
         Found_RId : Unbounded_String := Null_Unbounded_String;
         Success   : Boolean;
      begin
         begin
            UnZip.Extract (from => Zip_Info, what => "xl/workbook.xml", rename => Temp_Workbook);
         exception
            when others => return "xl/worksheets/sheet1.xml"; -- no workbook, use default
         end;

         Input_Sources.File.Open (Temp_Workbook, WB_Input);
         DOM.Readers.Parse (WB_Reader, WB_Input);
         WB_Doc := DOM.Readers.Get_Tree (WB_Reader);
         Input_Sources.File.Close (WB_Input);
         Sheets := DOM.Core.Documents.Get_Elements_By_Tag_Name (WB_Doc, "sheet");

         if Sheet_Name = "" then
            --  Use first sheet
            if Length (Sheets) > 0 then
               Found_RId := To_Unbounded_String (
                  Get_Attribute (DOM.Core.Element (Item (Sheets, 0)), "r:id"));
            end if;
         else
            for I in 0 .. Length (Sheets) - 1 loop
               if Get_Attribute (DOM.Core.Element (Item (Sheets, I)), "name") = Sheet_Name then
                  Found_RId := To_Unbounded_String (
                     Get_Attribute (DOM.Core.Element (Item (Sheets, I)), "r:id"));
                  exit;
               end if;
            end loop;
         end if;

         Free (Sheets);
         DOM.Readers.Free (WB_Reader);
         GNAT.OS_Lib.Delete_File (Temp_Workbook, Success);

         if Length (Found_RId) = 0 then
            return "xl/worksheets/sheet1.xml"; -- name not found, fall back
         end if;

         --  Resolve rId → file path via xl/_rels/workbook.xml.rels
         declare
            RL_Reader : DOM.Readers.Tree_Reader;
            RL_Input  : Input_Sources.File.File_Input;
            RL_Doc    : DOM.Core.Document;
            RL_List   : Node_List;
            Found_Tgt : Unbounded_String := Null_Unbounded_String;
         begin
            begin
               UnZip.Extract (from => Zip_Info, what => "xl/_rels/workbook.xml.rels",
                              rename => Temp_Rels);
            exception
               when others => return "xl/worksheets/sheet1.xml";
            end;

            Input_Sources.File.Open (Temp_Rels, RL_Input);
            DOM.Readers.Parse (RL_Reader, RL_Input);
            RL_Doc := DOM.Readers.Get_Tree (RL_Reader);
            Input_Sources.File.Close (RL_Input);
            RL_List := DOM.Core.Documents.Get_Elements_By_Tag_Name (RL_Doc, "Relationship");

            for I in 0 .. Length (RL_List) - 1 loop
               if Get_Attribute (DOM.Core.Element (Item (RL_List, I)), "Id") = To_String (Found_RId)
               then
                  Found_Tgt := To_Unbounded_String (
                     Get_Attribute (DOM.Core.Element (Item (RL_List, I)), "Target"));
                  exit;
               end if;
            end loop;

            Free (RL_List);
            DOM.Readers.Free (RL_Reader);
            GNAT.OS_Lib.Delete_File (Temp_Rels, Success);

            if Length (Found_Tgt) = 0 then
               return "xl/worksheets/sheet1.xml";
            end if;
            --  Target is relative to xl/: e.g. "worksheets/sheet2.xml"
            return "xl/" & To_String (Found_Tgt);
         end;
      end Find_Sheet_XML_Path;

      procedure Load_Shared_Strings (Zip_Info : Zip.Zip_Info) is
         Reader : DOM.Readers.Tree_Reader;
         Input  : Input_Sources.File.File_Input;
         Doc    : DOM.Core.Document;
         SI_Nodes, T_Nodes : Node_List;
         Success : Boolean;
      begin
         begin
            UnZip.Extract (from => Zip_Info, what => "xl/sharedStrings.xml", rename => Temp_Shared);
         exception
            when others => return; -- No shared strings file
         end;

         Input_Sources.File.Open (Temp_Shared, Input);
         DOM.Readers.Parse (Reader, Input);
         Doc := DOM.Readers.Get_Tree (Reader);
         Input_Sources.File.Close (Input);

         SI_Nodes := DOM.Core.Documents.Get_Elements_By_Tag_Name (Doc, "si");
         for I in 0 .. Length (SI_Nodes) - 1 loop
            T_Nodes := Get_Elements_By_Tag_Name (DOM.Core.Element (Item (SI_Nodes, I)), "t");
            if Length (T_Nodes) > 0 then
               Shared_Strings.Append (To_Unbounded_String (Get_Text (Item (T_Nodes, 0))));
            else
               Shared_Strings.Append (Null_Unbounded_String);
            end if;
            Free (T_Nodes);
         end loop;

         Free (SI_Nodes);
         DOM.Readers.Free (Reader);
         GNAT.OS_Lib.Delete_File (Temp_Shared, Success);
      exception
         when E : others =>
            if not SData.Config.Quiet_Mode then
               Put_Line_Error ("Warning: OOXML shared strings failed to load; string cells will be missing: " &
                  Ada.Exceptions.Exception_Message (E));
            end if;
      end Load_Shared_Strings;

      procedure Load_Sheet (Zip_Info : Zip.Zip_Info; Sheet_XML_Path : String) is
         Reader : DOM.Readers.Tree_Reader;
         Input  : Input_Sources.File.File_Input;
         Doc    : DOM.Core.Document;
         Rows, Cells : Node_List;
         Success : Boolean;
         Col_Count : Natural := 0;
         package Name_Vecs is new Ada.Containers.Vectors (Positive, Unbounded_String);

         function Get_Cell_Value (Cell_Node : Node) return Value is
            T_Attr : constant String := Get_Attribute (DOM.Core.Element (Cell_Node), "t");
            V_List : Node_List := Get_Elements_By_Tag_Name (DOM.Core.Element (Cell_Node), "v");
            IS_List : Node_List := Get_Elements_By_Tag_Name (DOM.Core.Element (Cell_Node), "is");
         begin
            if Length (V_List) > 0 then
               declare
                  Val_Str : constant String := Get_Text (Item (V_List, 0));
               begin
                  Free (V_List); Free (IS_List);
                  if T_Attr = "s" then
                     declare
                        Idx : constant Natural := Natural'Value (Val_Str);
                     begin
                        if Idx < Natural (Shared_Strings.Length) then
                           declare S : constant String := To_String (Shared_Strings.Element (Idx));
                           begin return (Kind => Val_String, Str_Val => To_Unbounded_String (S)); end;
                        end if;
                     end;
                  elsif T_Attr = "str" then
                     return (Kind => Val_String, Str_Val => To_Unbounded_String (Val_Str));
                  else
                     begin return (Kind => Val_Numeric, Num_Val => Float'Value (Val_Str)); exception when Constraint_Error => null; end;
                  end if;
               end;
            elsif Length (IS_List) > 0 then
               declare
                  T_Nodes : Node_List := Get_Elements_By_Tag_Name (DOM.Core.Element (Item (IS_List, 0)), "t");
               begin
                  if Length (T_Nodes) > 0 then
                     declare S : constant String := Get_Text (Item (T_Nodes, 0));
                     begin Free (T_Nodes); Free (V_List); Free (IS_List);
                           return (Kind => Val_String, Str_Val => To_Unbounded_String (S)); end;
                  end if;
                  Free (T_Nodes);
               end;
            end if;
            Free (V_List); Free (IS_List);
            return (Kind => Val_Missing);
         end Get_Cell_Value;

      begin
         UnZip.Extract (from => Zip_Info, what => Sheet_XML_Path, rename => Temp_Sheet);

         --  Formula detection: scan for <f> elements.
         --  If found, try LibreOffice to recalculate before parsing.
         if Has_Formulas_XML (Temp_Sheet, Is_ODF => False) then
            declare
               Converted : constant String :=
                  Convert_Via_LibreOffice (File_Name, OOXML);
               OK : Boolean;
            begin
               if Converted /= "" then
                  --  Re-enter via converted ODS (formulas recalculated).
                  GNAT.OS_Lib.Delete_File (Temp_Sheet, OK);
                  DOM.Readers.Free (Reader);
                  Parse_ODF (Converted);
                  GNAT.OS_Lib.Delete_File (Converted, OK);
                  return;
               end if;
               if not SData.Config.Quiet_Mode then
                  Put_Line_Error ("Warning: formula cells found in XLSX file but LibreOffice " &
                     "is not available; using cached values.");
               end if;
            end;
         end if;

         Input_Sources.File.Open (Temp_Sheet, Input);
         DOM.Readers.Parse (Reader, Input);
         Doc := DOM.Readers.Get_Tree (Reader);
         Input_Sources.File.Close (Input);

         declare
            Merged : Node_List := DOM.Core.Documents.Get_Elements_By_Tag_Name (Doc, "mergeCells");
         begin
            if Length (Merged) > 0 then
               Free (Merged);
               DOM.Readers.Free (Reader);
               raise SData.Script_Error with "XLSX file contains merged cells, which are not supported.";
            end if;
            Free (Merged);
         end;

         Rows := DOM.Core.Documents.Get_Elements_By_Tag_Name (Doc, "row");
         Clear;

         if Length (Rows) > 0 then
            --  Collect column names from header row, infer types from first
            --  data row, then create columns with the correct types.
            declare
               Col_Name_Vec : Name_Vecs.Vector;
            begin
               Cells := Get_Elements_By_Tag_Name (DOM.Core.Element (Item (Rows, 0)), "c");
               for I in 0 .. Length (Cells) - 1 loop
                  declare
                     V    : constant Value  := Get_Cell_Value (Item (Cells, I));
                     Idx  : constant String := Trim (Integer (I + 1)'Img, Ada.Strings.Both);
                     Name : constant String := (if V.Kind = Val_String
                                                then SData.Values.To_String (V)
                                                else "COL" & Idx);
                  begin
                     Col_Name_Vec.Append (To_Unbounded_String (Safe_Name (Name, "COL" & Idx)));
                  end;
               end loop;
               Free (Cells);

               --  Infer column types from the first data row.
               declare
                  N          : constant Natural := Natural (Col_Name_Vec.Length);
                  Col_Types  : array (1 .. N) of Column_Type := (others => Col_Numeric);
                  Data_Cells : Node_List;
                  Col_Idx    : Natural := 0;
               begin
                  --  Per spec: column names already ending in "$" are forced character.
                  for I in 1 .. N loop
                     declare
                        Raw : constant String := To_String (Col_Name_Vec (I));
                     begin
                        if Raw'Length > 0 and then Raw (Raw'Last) = '$' then
                           Col_Types (I) := Col_String;
                        end if;
                     end;
                  end loop;
                  if Length (Rows) > 1 then
                     Data_Cells := Get_Elements_By_Tag_Name (DOM.Core.Element (Item (Rows, 1)), "c");
                     for J in 0 .. Length (Data_Cells) - 1 loop
                        Col_Idx := Col_Idx + 1;
                        exit when Col_Idx > N;
                        declare V : constant Value := Get_Cell_Value (Item (Data_Cells, J)); begin
                           if V.Kind = Val_String then Col_Types (Col_Idx) := Col_String; end if;
                        end;
                     end loop;
                     Free (Data_Cells);
                  end if;
                  for I in 1 .. N loop
                     declare
                        Raw_Name  : constant String := To_String (Col_Name_Vec (I));
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
               end;
            end;
            Col_Count := Column_Count;

            -- Data Rows
            for I in 1 .. Length (Rows) - 1 loop
               Add_Row;
               Cells := Get_Elements_By_Tag_Name (DOM.Core.Element (Item (Rows, I)), "c");
               for J in 0 .. Length (Cells) - 1 loop
                  if J < Col_Count then
                     declare
                        V : constant Value := Get_Cell_Value (Item (Cells, J));
                     begin
                        if V.Kind /= Val_Missing then
                           Set_Value (Row_Count, Column_Name (J + 1), V);
                        end if;
                     exception
                        when E : others =>
                           if not SData.Config.Quiet_Mode then
                              Put_Line_Error ("Warning: OOXML import skipped cell at row" &
                                 Row_Count'Image & ", column """ &
                                 Column_Name (J + 1) & """: " &
                                 Ada.Exceptions.Exception_Message (E));
                           end if;
                     end;
                  end if;
               end loop;
               Free (Cells);
            end loop;
         end if;

         Free (Rows);
         DOM.Readers.Free (Reader);
         GNAT.OS_Lib.Delete_File (Temp_Sheet, Success);
      end Load_Sheet;

      Zip_Info : Zip.Zip_Info;
   begin
      Zip.Load (Zip_Info, File_Name);
      Load_Shared_Strings (Zip_Info);
      declare
         Sheet_Path : constant String := Find_Sheet_XML_Path (Zip_Info);
      begin
         Load_Sheet (Zip_Info, Sheet_Path);
      end;
   exception
      when E : others =>
         declare OK : Boolean; begin
            if GNAT.OS_Lib.Is_Regular_File (Temp_Shared)   then GNAT.OS_Lib.Delete_File (Temp_Shared,   OK); end if;
            if GNAT.OS_Lib.Is_Regular_File (Temp_Sheet)    then GNAT.OS_Lib.Delete_File (Temp_Sheet,    OK); end if;
            if GNAT.OS_Lib.Is_Regular_File (Temp_Workbook) then GNAT.OS_Lib.Delete_File (Temp_Workbook, OK); end if;
            if GNAT.OS_Lib.Is_Regular_File (Temp_Rels)     then GNAT.OS_Lib.Delete_File (Temp_Rels,     OK); end if;
         end;
         raise Program_Error with "Failed to parse OOXML file """ & File_Name & """: " &
            Ada.Exceptions.Exception_Message (E);
   end Parse_OOXML;

   -----------------
   -- Write_OOXML --
   -----------------
   procedure Write_OOXML (File_Name : String; Sheet_Name : String := "Sheet1") is
      use Zip.Create;
      Info : Zip_Create_Info;
      Z_File_Stream : aliased Zip_File_Stream;
      N     : constant Natural := Column_Count;
      Sname : constant String  := (if Sheet_Name = "" then "Sheet1" else Sheet_Name);
   begin
      if N = 0 then return; end if;
      
      Create_Archive (Info, Z_File_Stream'Unchecked_Access, File_Name);

      -- 1. [Content_Types].xml
      Add_String (Info,
         "<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?>" &
         "<Types xmlns=""http://schemas.openxmlformats.org/package/2006/content-types"">" &
         "<Default Extension=""rels"" ContentType=""application/vnd.openxmlformats-package.relationships+xml""/>" &
         "<Default Extension=""xml"" ContentType=""application/xml""/>" &
         "<Override PartName=""/xl/workbook.xml"" ContentType=""application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml""/>" &
         "<Override PartName=""/xl/worksheets/sheet1.xml"" ContentType=""application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml""/>" &
         "</Types>",
         "[Content_Types].xml");

      -- 2. _rels/.rels
      Add_String (Info,
         "<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?>" &
         "<Relationships xmlns=""http://schemas.openxmlformats.org/package/2006/relationships"">" &
         "<Relationship Id=""rId1"" Type=""http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument"" Target=""xl/workbook.xml""/>" &
         "</Relationships>",
         "_rels/.rels");
      
      -- 3. xl/workbook.xml
      Add_String (Info,
         "<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?>" &
         "<workbook xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"" xmlns:r=""http://schemas.openxmlformats.org/officeDocument/2006/relationships"">" &
         "<sheets><sheet name=""" & Escape_XML (Sname) & """ sheetId=""1"" r:id=""rId1""/></sheets>" &
         "</workbook>",
         "xl/workbook.xml");

      -- 4. xl/_rels/workbook.xml.rels
      Add_String (Info,
         "<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?>" &
         "<Relationships xmlns=""http://schemas.openxmlformats.org/package/2006/relationships"">" &
         "<Relationship Id=""rId1"" Type=""http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet"" Target=""worksheets/sheet1.xml""/>" &
         "</Relationships>",
         "xl/_rels/workbook.xml.rels");

      -- 5. xl/worksheets/sheet1.xml
      declare
         S1 : Unbounded_String;
      begin
         Append (S1, "<?xml version=""1.0"" encoding=""UTF-8"" standalone=""yes""?>" & ASCII.LF);
         Append (S1, "<worksheet xmlns=""http://schemas.openxmlformats.org/spreadsheetml/2006/main"">" & ASCII.LF);
         Append (S1, "<sheetData>" & ASCII.LF);
         
         -- Header Row
         Append (S1, "<row r=""1"">");
         for C in 1 .. N loop
            declare
               Ref : constant String := Col_To_Letters (C) & "1";
               Val : constant String := Escape_XML (Column_Name (C));
            begin
               Append (S1, "<c r=""" & Ref & """ t=""inlineStr""><is><t>" & Val & "</t></is></c>");
            end;
         end loop;
         Append (S1, "</row>" & ASCII.LF);

         -- Data Rows
         for R in 1 .. Row_Count loop
            Append (S1, "<row r=""" & Trim (Integer (R + 1)'Img, Ada.Strings.Both) & """>");
            for C in 1 .. N loop
               declare
                  Ref : constant String := Col_To_Letters (C) & Trim (Integer (R + 1)'Img, Ada.Strings.Both);
                  V   : constant Value := Get_Value (R, Column_Name (C));
               begin
                  case V.Kind is
                     when Val_Numeric =>
                        Append (S1, "<c r=""" & Ref & """><v>" & Trim (V.Num_Val'Img, Ada.Strings.Both) & "</v></c>");
                     when Val_Integer =>
                        Append (S1, "<c r=""" & Ref & """><v>" & Trim (V.Int_Val'Img, Ada.Strings.Both) & "</v></c>");
                     when Val_String =>
                        Append (S1, "<c r=""" & Ref & """ t=""inlineStr""><is><t>" & Escape_XML (SData.Values.To_String (V)) & "</t></is></c>");
                     when Val_Missing =>
                        null; -- Skip empty cells
                  end case;
               end;
            end loop;
            Append (S1, "</row>" & ASCII.LF);
         end loop;

         Append (S1, "</sheetData>" & ASCII.LF);
         Append (S1, "</worksheet>");
         Add_String (Info, S1, "xl/worksheets/sheet1.xml");
      end;

      Finish (Info);
   end Write_OOXML;

   ---------------
   -- Write_ODF --
   ---------------
   procedure Write_ODF (File_Name : String; Sheet_Name : String := "Sheet1") is
      use Zip.Create;
      Info : Zip_Create_Info;
      Z_File_Stream : aliased Zip_File_Stream;
      N     : constant Natural := Column_Count;
      Sname : constant String  := (if Sheet_Name = "" then "Sheet1" else Sheet_Name);
   begin
      if N = 0 then return; end if;

      Create_Archive (Info, Z_File_Stream'Unchecked_Access, File_Name);

      -- 1. mimetype (Store only, no compression)
      Add_String (Info, "application/vnd.oasis.opendocument.spreadsheet", "mimetype");

      -- 2. META-INF/manifest.xml
      Add_String (Info,
         "<?xml version=""1.0"" encoding=""UTF-8""?>" &
         "<manifest:manifest xmlns:manifest=""urn:oasis:names:tc:opendocument:xmlns:manifest:1.0"" manifest:version=""1.2"">" &
         "<manifest:file-entry manifest:full-path=""/"" manifest:version=""1.2"" manifest:media-type=""application/vnd.oasis.opendocument.spreadsheet""/>" &
         "<manifest:file-entry manifest:full-path=""content.xml"" manifest:media-type=""text/xml""/>" &
         "</manifest:manifest>",
         "META-INF/manifest.xml");

      -- 3. content.xml
      declare
         S1 : Unbounded_String;
      begin
         Append (S1, "<?xml version=""1.0"" encoding=""UTF-8""?>" & ASCII.LF);
         Append (S1, "<office:document-content xmlns:office=""urn:oasis:names:tc:opendocument:xmlns:office:1.0"" " &
                      "xmlns:table=""urn:oasis:names:tc:opendocument:xmlns:table:1.0"" " &
                      "xmlns:text=""urn:oasis:names:tc:opendocument:xmlns:text:1.0"" " &
                      "office:version=""1.2"">" & ASCII.LF);
         Append (S1, "<office:body><office:spreadsheet>" & ASCII.LF);
         Append (S1, "<table:table table:name=""" & Escape_XML (Sname) & """>" & ASCII.LF);

         -- Header Row
         Append (S1, "<table:table-row>");
         for C in 1 .. N loop
            Append (S1, "<table:table-cell office:value-type=""string""><text:p>" & Escape_XML (Column_Name (C)) & "</text:p></table:table-cell>");
         end loop;
         Append (S1, "</table:table-row>" & ASCII.LF);

         -- Data Rows
         for R in 1 .. Row_Count loop
            Append (S1, "<table:table-row>");
            for C in 1 .. N loop
               declare
                  V : constant Value := Get_Value (R, Column_Name (C));
               begin
                  case V.Kind is
                     when Val_Numeric =>
                        Append (S1, "<table:table-cell office:value-type=""float"" office:value=""" & Trim (V.Num_Val'Img, Ada.Strings.Both) & """>" &
                                "<text:p>" & Trim (V.Num_Val'Img, Ada.Strings.Both) & "</text:p></table:table-cell>");
                     when Val_Integer =>
                        Append (S1, "<table:table-cell office:value-type=""float"" office:value=""" & Trim (V.Int_Val'Img, Ada.Strings.Both) & """>" &
                                "<text:p>" & Trim (V.Int_Val'Img, Ada.Strings.Both) & "</text:p></table:table-cell>");
                     when Val_String =>
                        Append (S1, "<table:table-cell office:value-type=""string""><text:p>" & Escape_XML (SData.Values.To_String (V)) & "</text:p></table:table-cell>");
                     when Val_Missing =>
                        Append (S1, "<table:table-cell/>");
                  end case;
               end;
            end loop;
            Append (S1, "</table:table-row>" & ASCII.LF);
         end loop;

         Append (S1, "</table:table></office:spreadsheet></office:body></office:document-content>");
         Add_String (Info, S1, "content.xml");
      end;

      Finish (Info);
   end Write_ODF;

end SData.File_IO;
