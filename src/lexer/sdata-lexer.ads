package SData.Lexer is

   type Token_Kind is (
      Token_EOF,
      Token_Identifier,
      Token_String_Literal,
      Token_Numeric_Literal,

      -- Keywords (Commands)
      Token_USE, Token_SAVE, Token_KEEP, Token_DROP, Token_HOLD, Token_UNHOLD, Token_NEW,
      Token_IF, Token_THEN, Token_ELSE, Token_FOR, Token_NEXT, Token_WHILE, Token_WEND,
      Token_REPEAT, Token_UNTIL, Token_SELECT, Token_CASE, Token_SUBMIT,
      Token_LET, Token_SET, Token_DIM, Token_ARRAY,
      Token_PRINT, Token_OUTPUT, Token_ECHO,
      Token_BY, Token_SORT, Token_RENAME, Token_DELETE,
      Token_OPTIONS, Token_DIGITS, Token_FPATH, Token_HEADER,
      Token_REM, Token_HELP, Token_END, Token_RUN,

      -- Operators and Punctuation
      Token_Plus, Token_Minus, Token_Star, Token_Slash, Token_Caret,
      Token_Equal, Token_Not_Equal, Token_Less, Token_Less_Equal, Token_Greater, Token_Greater_Equal,
      Token_Left_Paren, Token_Right_Paren, Token_Comma, Token_Semicolon, Token_Colon,
      Token_Newline,
      Token_Range_Dash -- For NAME1-NAME5
   );

   type Token is record
      Kind   : Token_Kind;
      Text   : String (1 .. 1024); -- Simple fixed size for now
      Length : Natural := 0;
      Line   : Positive;
      Column : Positive;
   end record;

   type Lexer_Context is private;

   procedure Initialize (Ctx : in out Lexer_Context; Source : String);
   function Get_Next_Token (Ctx : in out Lexer_Context) return Token;
   function Peek_Next_Token (Ctx : in out Lexer_Context) return Token;

private
   type Lexer_Context is record
      Source      : String (1 .. 10000); -- Limited for now
      Source_Len  : Natural := 0;
      Pos         : Positive := 1;
      Line        : Positive := 1;
      Column      : Positive := 1;
      Peeked      : Token;
      Has_Peeked  : Boolean := False;
   end record;

end SData.Lexer;
