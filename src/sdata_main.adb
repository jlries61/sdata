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

   Ctx : Parser_Context;
   Prog : Statement_Access;
   Current : Statement_Access;
begin
   if Argument_Count < 1 then
      Put_Line ("Usage: sdata_main <filename>");
      return;
   end if;

   declare
      Source : constant String := Read_File (Argument (1));
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
