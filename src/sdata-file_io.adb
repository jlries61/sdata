with Ada.Text_IO;   use Ada.Text_IO;
with Ada.Strings.Fixed; use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Ada.Containers.Vectors;
with SData.Table;     use SData.Table;
with SData.Values;    use SData.Values;
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

   -------------------
   -- Run_SSConvert --
   -------------------
   procedure Run_SSConvert (In_File, Out_File : String) is
      Args : GNAT.OS_Lib.Argument_List (1 .. 2);
      Success : Boolean;
      Executable : GNAT.OS_Lib.String_Access := GNAT.OS_Lib.Locate_Exec_On_Path ("ssconvert");
   begin
      if Executable = null then
         raise Program_Error with "ssconvert executable not found on PATH";
      end if;
      Args (1) := new String'(In_File);
      Args (2) := new String'(Out_File);
      GNAT.OS_Lib.Spawn (Executable.all, Args, Success);
      GNAT.OS_Lib.Free (Args (1));
      GNAT.OS_Lib.Free (Args (2));
      GNAT.OS_Lib.Free (Executable);
      if not Success then
         raise Program_Error with "ssconvert failed to convert " & In_File & " to " & Out_File;
      end if;
   end Run_SSConvert;

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

   ----------------
   -- Open_Input --
   ----------------
   procedure Open_Input (File_Name : String; Fmt : Format_Type) is
      Actual_Fmt : Format_Type := Fmt;
      Ext_Idx : Natural := 0;
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
            Parse_CSV (File_Name);
         when ODF =>
            declare
               Temp_CSV : constant String := File_Name & ".tmp.csv";
               OK : Boolean;
            begin
               Run_SSConvert (File_Name, Temp_CSV);
               Parse_CSV (Temp_CSV);
               GNAT.OS_Lib.Delete_File (Temp_CSV, OK);
            end;
         when OOXML =>
            Parse_OOXML (File_Name);
      end case;

      if not SData.Config.Quiet_Mode then
         Put_Line ("Dataset opened: " & File_Name);
      end if;
   end Open_Input;

   -----------------
   -- Open_Output --
   -----------------
   procedure Open_Output (File_Name : String; Fmt : Format_Type) is
      Actual_Fmt : Format_Type := Fmt;
      Ext_Idx : Natural := 0;
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
            Write_CSV (File_Name);
         when ODF | OOXML =>
            declare
               Temp_CSV : constant String := File_Name & ".tmp.csv";
               OK : Boolean;
            begin
               Write_CSV (Temp_CSV);
               Run_SSConvert (Temp_CSV, File_Name);
               GNAT.OS_Lib.Delete_File (Temp_CSV, OK);
            end;
      end case;
   end Open_Output;

   ---------------
   -- Parse_CSV --
   ---------------
   procedure Parse_CSV (File_Name : String) is
      File : File_Type;
      type String_Array is array (Positive range <>) of Unbounded_String;
      
      function Split (L : String) return String_Array is
         Start : Positive := L'First;
         Pos   : Natural;
         Count : Natural := 0;
      begin
         if L'Length = 0 then return (1 .. 0 => Null_Unbounded_String); end if;
         for I in L'Range loop if L (I) = ',' then Count := Count + 1; end if; end loop;
         declare
            Res : String_Array (1 .. Count + 1);
            Idx : Positive := 1;
         begin
            loop
               Pos := Index (L (Start .. L'Last), ",");
               if Pos = 0 then
                  Res (Idx) := To_Unbounded_String (Trim (L (Start .. L'Last), Ada.Strings.Both));
                  exit;
               else
                  Res (Idx) := To_Unbounded_String (Trim (L (Start .. Pos - 1), Ada.Strings.Both));
                  Start := Pos + 1;
                  Idx := Idx + 1;
               end if;
            end loop;
            return Res;
         end;
      end Split;

      procedure Process_Row (Fields : String_Array; Names : String_List) is
      begin
         Add_Row;
         for I in Fields'Range loop
            if I <= Names'Length then
               declare
                  Val_Str : constant String := To_String (Fields (I));
                  Val : Value;
               begin
                  if Val_Str = "" or Val_Str = "." then
                     Val := (Kind => Val_Missing);
                  else
                     begin
                        Val := (Kind => Val_Numeric, Num_Val => Float'Value (Val_Str));
                     exception
                        when others =>
                           Val := (Kind => Val_String, Str_Val => Val_Str & (1 .. 1024 - Val_Str'Length => ' '), Str_Len => Val_Str'Length);
                     end;
                  end if;
                  Set_Value (Row_Count, Names (I).all, Val);
               end;
            end if;
         end loop;
      end Process_Row;

      Header_Line, First_Data_Line : Unbounded_String;
      Has_Header, Has_Data : Boolean := False;
   begin
      Open (File, In_File, File_Name);
      if not End_Of_File (File) then
         Header_Line := To_Unbounded_String (Get_Line (File));
         Has_Header := True;
      end if;
      if not End_Of_File (File) then
         First_Data_Line := To_Unbounded_String (Get_Line (File));
         Has_Data := True;
      end if;
      if Has_Header then
         declare
            Headers : constant String_Array := Split (To_String (Header_Line));
            Names   : String_List (1 .. Headers'Length);
            Data_Fields : String_Array (1 .. Headers'Length) := (others => Null_Unbounded_String);
         begin
            if Has_Data then
               declare
                  DF : constant String_Array := Split (To_String (First_Data_Line));
               begin
                  for I in DF'Range loop
                     if I <= Data_Fields'Length then
                        Data_Fields (I) := DF (I);
                     end if;
                  end loop;
               end;
            end if;
            Clear;
            for I in Headers'Range loop
               declare
                  Name : constant String := Safe_Name (To_String (Headers (I)), "COL" & Trim (I'Img, Ada.Strings.Both));
                  Typ  : Column_Type := Col_String;
                  Val_Str : constant String := To_String (Data_Fields (I));
               begin
                  Names (I) := new String'(Name);
                  if Val_Str /= "" and then Val_Str /= "." then
                     begin
                        declare Dummy : Float; 
                        begin 
                           Dummy := Float'Value (Val_Str); 
                           Typ := (if Dummy = 0.0 or else Dummy /= 0.0 then Col_Numeric else Col_String);
                        end;
                     exception
                        when others => null;
                     end;
                  end if;
                  Add_Column (Name, Typ);
               end;
            end loop;
            if Has_Data then
               Process_Row (Data_Fields, Names);
            end if;
            while not End_Of_File (File) loop
               Process_Row (Split (Get_Line (File)), Names);
            end loop;
            for I in Names'Range loop
               Free (Names (I));
            end loop;
         end;
      end if;
      Close (File);
   exception
      when others =>
         if Is_Open (File) then Close (File); end if;
         raise;
   end Parse_CSV;

   ---------------
   -- Write_CSV --
   ---------------
   procedure Write_CSV (File_Name : String) is
      File : File_Type;
      Col_Names : GNAT.Strings.String_List_Access := Get_Column_Names;
   begin
      Create (File, Out_File, File_Name);
      if Col_Names /= null then
         for I in Col_Names'Range loop
            Put (File, Col_Names (I).all);
            if I /= Col_Names'Last then Put (File, ","); end if;
         end loop;
         New_Line (File);
         for R in 1 .. Row_Count loop
            for C in Col_Names'Range loop
               declare
                  Val : constant Value := Get_Value (R, Col_Names (C).all);
               begin
                  if Val.Kind = Val_Numeric then
                     Put (File, Trim (Val.Num_Val'Img, Ada.Strings.Both));
                  elsif Val.Kind = Val_Integer then
                     Put (File, Trim (Val.Int_Val'Img, Ada.Strings.Both));
                  elsif Val.Kind = Val_String then
                     Put (File, Val.Str_Val (1 .. Val.Str_Len));
                  else
                     Put (File, ".");
                  end if;
               end;
               if C /= Col_Names'Last then Put (File, ","); end if;
            end loop;
            New_Line (File);
         end loop;
      end if;
      Close (File);
      if Col_Names /= null then GNAT.Strings.Free (Col_Names); end if;
   exception
      when others =>
         if Is_Open (File) then Close (File); end if;
         if Col_Names /= null then GNAT.Strings.Free (Col_Names); end if;
         raise;
   end Write_CSV;

   ------------------
   -- Parse_ODF --
   ------------------
   procedure Parse_ODF (File_Name : String) is
   begin
      Open_Input (File_Name, ODF);
   end Parse_ODF;

   -----------------
   -- Parse_OOXML --
   -----------------
   procedure Parse_OOXML (File_Name : String) is
      use DOM.Core;
      use DOM.Core.Nodes;
      use DOM.Core.Elements;

      Temp_Shared : constant String := File_Name & ".sharedStrings.xml";
      Temp_Sheet  : constant String := File_Name & ".sheet1.xml";
      
      package String_Vectors is new Ada.Containers.Vectors (Index_Type => Natural, Element_Type => Unbounded_String);
      Shared_Strings : String_Vectors.Vector;

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
         when others => null;
      end Load_Shared_Strings;

      procedure Load_Sheet (Zip_Info : Zip.Zip_Info) is
         Reader : DOM.Readers.Tree_Reader;
         Input  : Input_Sources.File.File_Input;
         Doc    : DOM.Core.Document;
         Rows, Cells : Node_List;
         Success : Boolean;
         Header_Names : GNAT.Strings.String_List_Access;

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
                           begin return (Kind => Val_String, Str_Val => S & (1 .. 1024 - S'Length => ' '), Str_Len => S'Length); end;
                        end if;
                     end;
                  elsif T_Attr = "str" then
                     return (Kind => Val_String, Str_Val => Val_Str & (1 .. 1024 - Val_Str'Length => ' '), Str_Len => Val_Str'Length);
                  else
                     begin return (Kind => Val_Numeric, Num_Val => Float'Value (Val_Str)); exception when others => null; end;
                  end if;
               end;
            elsif Length (IS_List) > 0 then
               declare
                  T_Nodes : Node_List := Get_Elements_By_Tag_Name (DOM.Core.Element (Item (IS_List, 0)), "t");
               begin
                  if Length (T_Nodes) > 0 then
                     declare S : constant String := Get_Text (Item (T_Nodes, 0));
                     begin Free (T_Nodes); Free (V_List); Free (IS_List);
                           return (Kind => Val_String, Str_Val => S & (1 .. 1024 - S'Length => ' '), Str_Len => S'Length); end;
                  end if;
                  Free (T_Nodes);
               end;
            end if;
            Free (V_List); Free (IS_List);
            return (Kind => Val_Missing);
         end Get_Cell_Value;

      begin
         UnZip.Extract (from => Zip_Info, what => "xl/worksheets/sheet1.xml", rename => Temp_Sheet);
         Input_Sources.File.Open (Temp_Sheet, Input);
         DOM.Readers.Parse (Reader, Input);
         Doc := DOM.Readers.Get_Tree (Reader);
         Input_Sources.File.Close (Input);

         Rows := DOM.Core.Documents.Get_Elements_By_Tag_Name (Doc, "row");
         Clear;

         if Length (Rows) > 0 then
            -- Headers
            Cells := Get_Elements_By_Tag_Name (DOM.Core.Element (Item (Rows, 0)), "c");
            for I in 0 .. Length (Cells) - 1 loop
               declare
                  V : constant Value := Get_Cell_Value (Item (Cells, I));
                  Name : constant String := (if V.Kind = Val_String then V.Str_Val (1 .. V.Str_Len) else "COL" & Trim (Integer (I + 1)'Img, Ada.Strings.Both));
               begin
                  Add_Column (Safe_Name (Name, "COL" & Trim (Integer (I + 1)'Img, Ada.Strings.Both)), (if V.Kind = Val_Numeric then Col_Numeric else Col_String));
               end;
            end loop;
            Free (Cells);
            Header_Names := Get_Column_Names;

            -- Data Rows
            for I in 1 .. Length (Rows) - 1 loop
               Add_Row;
               Cells := Get_Elements_By_Tag_Name (DOM.Core.Element (Item (Rows, I)), "c");
               for J in 0 .. Length (Cells) - 1 loop
                  if J < Header_Names'Length then
                     declare
                        V : constant Value := Get_Cell_Value (Item (Cells, J));
                     begin
                        if V.Kind /= Val_Missing then
                           Set_Value (Row_Count, Header_Names (J + 1).all, V);
                        end if;
                     exception
                        when others => null; -- Handle type mismatch or other errors gracefully
                     end;
                  end if;
               end loop;
               Free (Cells);
            end loop;
            GNAT.Strings.Free (Header_Names);
         end if;

         Free (Rows);
         DOM.Readers.Free (Reader);
         GNAT.OS_Lib.Delete_File (Temp_Sheet, Success);
      end Load_Sheet;

      Zip_Info : Zip.Zip_Info;
   begin
      Zip.Load (Zip_Info, File_Name);
      Load_Shared_Strings (Zip_Info);
      Load_Sheet (Zip_Info);
   exception
      when others =>
         if GNAT.OS_Lib.Is_Regular_File (Temp_Shared) then declare OK : Boolean; begin GNAT.OS_Lib.Delete_File (Temp_Shared, OK); end; end if;
         if GNAT.OS_Lib.Is_Regular_File (Temp_Sheet) then declare OK : Boolean; begin GNAT.OS_Lib.Delete_File (Temp_Sheet, OK); end; end if;
         raise Program_Error with "Failed to parse OOXML file: " & File_Name;
   end Parse_OOXML;

   procedure Write_ODF (File_Name : String) is
   begin
      Open_Output (File_Name, ODF);
   end Write_ODF;

   procedure Write_OOXML (File_Name : String) is
   begin
      Open_Output (File_Name, OOXML);
   end Write_OOXML;

end SData.File_IO;
