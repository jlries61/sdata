with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Streams.Stream_IO;
with Ada.Exceptions; use Ada.Exceptions;
with SData.Lexer; use SData.Lexer;
with SData.Parser; use SData.Parser;
with SData.AST; use SData.AST;

with SData.Interpreter; use SData.Interpreter;
with SData.Config; use SData.Config;
with SData.File_IO; use SData.File_IO;

procedure SData_Main is
   
   function Read_File (Filename : String) return String is
      File : Ada.Streams.Stream_IO.File_Type;
      Stream : Ada.Streams.Stream_IO.Stream_Access;
   begin
      Ada.Streams.Stream_IO.Open (File, Ada.Streams.Stream_IO.In_File, Filename);
      Stream := Ada.Streams.Stream_IO.Stream (File);
      declare
         Result : String (1 .. Integer (Ada.Streams.Stream_IO.Size (File)));
      begin
         String'Read (Stream, Result);
         Ada.Streams.Stream_IO.Close (File);
         return Result;
      end;
   end Read_File;

   procedure Print_Usage is
   begin
      Put_Line ("Usage: sdata_main [options] <filename>");
      Put_Line ("Options:");
      Put_Line ("  -h, --help    Show this help message");
      Put_Line ("  -m <size>     Set max in-memory table size (not yet implemented)");
      Put_Line ("  --clen <len>  Set max character variable length (not yet implemented)");
      Put_Line ("  --noshell     Disable SHELL command (not yet implemented)");
      Put_Line ("  -u, --infmt   Input dataset and format (not yet implemented)");
      Put_Line ("  -s, --outfmt  Output dataset and format (not yet implemented)");
      Put_Line ("  -o            Console output file (not yet implemented)");
      Put_Line ("  -q            Suppress console output (not yet implemented)");
      Put_Line ("  -t            Max temporary variable memory (not yet implemented)");
      Put_Line ("  -p            Pager specification (not yet implemented)");
   end Print_Usage;

   Ctx : Parser_Context;
   Prog : Statement_Access;
   Filename : String (1 .. 1024);
   Filename_Len : Natural := 0;
   Idx : Positive := 1;
begin
   if Argument_Count < 1 then
      Print_Usage;
      return;
   end if;

   while Idx <= Argument_Count loop
      declare
         Arg : constant String := Argument (Idx);
      begin
         if Arg = "-h" or Arg = "--help" then
            Print_Usage;
            return;
         elsif Arg = "-q" then
            Quiet_Mode := True;
         elsif Arg = "-o" then
            if Idx < Argument_Count then
               Idx := Idx + 1;
               declare
                  Val : constant String := Argument (Idx);
               begin
                  Output_File (1 .. Val'Length) := Val;
                  Output_File_Len := Val'Length;
               end;
            end if;
         elsif Arg = "-u" or Arg = "--infmt" then
            if Idx < Argument_Count then
               Idx := Idx + 1;
               declare
                  Val : constant String := Argument (Idx);
               begin
                  if Val = "csv" then Input_Format := CSV;
                  elsif Val = "odf" then Input_Format := ODF;
                  elsif Val = "ooxml" then Input_Format := OOXML;
                  end if;
               end;
            end if;
         elsif Arg = "-s" or Arg = "--outfmt" then
            if Idx < Argument_Count then
               Idx := Idx + 1;
               declare
                  Val : constant String := Argument (Idx);
               begin
                  if Val = "csv" then Output_Format := CSV;
                  elsif Val = "odf" then Output_Format := ODF;
                  elsif Val = "ooxml" then Output_Format := OOXML;
                  end if;
               end;
            end if;
         elsif Arg(1) /= '-' then
            Filename (1 .. Arg'Length) := Arg;
            Filename_Len := Arg'Length;
            -- Auto-detect format from extension
            declare
               Ext_Idx : Natural := 0;
            begin
               for J in reverse 1 .. Filename_Len loop
                  if Filename (J) = '.' then
                     Ext_Idx := J;
                     exit;
                  end if;
               end loop;
               if Ext_Idx > 0 then
                  declare
                     Ext : constant String := Filename (Ext_Idx + 1 .. Filename_Len);
                  begin
                     if Ext = "csv" then Input_Format := CSV; Output_Format := CSV;
                     elsif Ext = "ods" or Ext = "odf" then Input_Format := ODF; Output_Format := ODF;
                     elsif Ext = "xlsx" or Ext = "ooxml" then Input_Format := OOXML; Output_Format := OOXML;
                     end if;
                  end;
               end if;
            end;
         end if;
      end;
      Idx := Idx + 1;
   end loop;

   if Filename_Len = 0 then
      Print_Usage;
      return;
   end if;

   declare
      Source : constant String := Read_File (Filename (1 .. Filename_Len));
   begin
      Initialize (Ctx, Source);
      
      -- Debug: Print all tokens
      -- Put_Line ("Tokens:");
      -- declare
      --    T : Token;
      --    L : Lexer_Context := Ctx.Lex_Ctx;
      -- begin
      --    loop
      --       T := Get_Next_Token (L);
      --       Put_Line (T.Kind'Image & ": '" & T.Text (1 .. T.Length) & "' (Line:" & T.Line'Image & ", Col:" & T.Column'Image & ")");
      --       exit when T.Kind = Token_EOF;
      --    end loop;
      -- end;

      Initialize (Ctx, Source);
      Prog := Parse_Program (Ctx);
      
      -- Put_Line ("Execution Output:");
      Execute (Prog);
   end;

exception
   when E : others =>
      Put_Line ("An error occurred: " & Exception_Name (E) & ": " & Exception_Message (E));
end SData_Main;
