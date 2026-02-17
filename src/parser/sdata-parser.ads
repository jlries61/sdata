with SData.Lexer; use SData.Lexer;
with SData.AST;   use SData.AST;

package SData.Parser is

   type Parser_Context is record
      Lex_Ctx : Lexer_Context;
   end record;

   procedure Initialize (Ctx : in out Parser_Context; Source : String);
   function Parse_Program (Ctx : in out Parser_Context) return Statement_Access;

end SData.Parser;
