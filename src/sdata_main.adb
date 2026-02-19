with Ada.Text_IO; use Ada.Text_IO;
with Ada.Command_Line; use Ada.Command_Line;
with Ada.Streams.Stream_IO;
with SData.Lexer; use SData.Lexer;
with SData.Parser; use SData.Parser;
with SData.AST; use SData.AST;

with SData.Interpreter; use SData.Interpreter;

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
begin
   if Argument_Count < 1 then
      Print_Usage;
      return;
   end if;

   for I in 1 .. Argument_Count loop
      declare
         Arg : constant String := Argument (I);
      begin
         if Arg = "-h" or Arg = "--help" then
            Print_Usage;
            return;
         elsif Arg (1) /= '-' then
            Filename (1 .. Arg'Length) := Arg;
            Filename_Len := Arg'Length;
         end if;
      end;
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
      Put_Line ("An error occurred.");
end SData_Main;
