--  Package SData.Parser implements a recursive descent parser for the SData language.
--  It takes a stream of tokens from the lexer and organizes them into an AST
--  consisting of linked statements and expressions.

with SData.Lexer; use SData.Lexer;
with SData.AST;   use SData.AST;

package SData.Parser is

   --  Holds the state required for parsing, primarily the lexer context.
   type Parser_Context is record
      Lex_Ctx : Lexer_Context;
   end record;

   --  Initializes the parser and the underlying lexer with the source code.
   procedure Initialize (Ctx : in out Parser_Context; Source : String);

   --  Parses the entire source code and returns the root of the statement list.
   --  Returns null if the source is empty.
   function Parse_Program (Ctx : in out Parser_Context) return Statement_Access;

end SData.Parser;
