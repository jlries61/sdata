--  Package SData.Lexer performs lexical analysis, converting raw source code (String)
--  into a stream of meaningful 'Token' records. It handles keywords, literals,
--  operators, and tracks position (line/column) for error reporting.

package SData.Lexer is

   --  Categories of tokens recognized by the lexer.
   type Token_Kind is (
      Token_EOF,             -- End of file
      Token_Identifier,      -- Variables and function names
      Token_String_Literal,  -- "Quoted strings"
      Token_Numeric_Literal, -- 123.45

      -- Keywords (Commands / Commands that are reserved words)
      Token_USE, Token_SAVE, Token_KEEP, Token_DROP, Token_HOLD, Token_UNHOLD, Token_NEW,
      Token_IF, Token_THEN, Token_ELSE, Token_FOR, Token_NEXT, Token_WHILE, Token_WEND,
      Token_REPEAT, Token_UNTIL, Token_SELECT, Token_CASE, Token_WHEN, Token_OTHERWISE, Token_SUBMIT,
      Token_LET, Token_SET, Token_DIM, Token_ARRAY,
      Token_PRINT, Token_WRITE, Token_OUTPUT, Token_ECHO,
      Token_BY, Token_SORT, Token_RENAME, Token_DELETE,
      Token_OPTIONS, Token_DIGITS, Token_FPATH, Token_HEADER,
      Token_REM, Token_HELP, Token_END, Token_RUN, Token_QUIT, Token_NAMES,
      Token_TO, Token_STEP,

      -- Operators and Punctuation
      Token_Plus, Token_Minus, Token_Star, Token_Slash, Token_Caret, -- +, -, *, /, ^
      Token_Equal, Token_Not_Equal, Token_Less, Token_Less_Equal, Token_Greater, Token_Greater_Equal, -- =, <>, <, <=, >, >=
      Token_Left_Paren, Token_Right_Paren, Token_Left_Brace, Token_Right_Brace, -- (, ), {, }
      Token_Comma, Token_Semicolon, Token_Colon, -- ,, ;, :
      Token_Newline,         -- Explicit newline tracking
      Token_Range_Dash       -- Used in variable ranges: NAME1-NAME5
   );

   --  Represents a single lexical unit.
   type Token is record
      Kind   : Token_Kind;
      Text   : String (1 .. 1024); -- Raw text content of the token
      Length : Natural := 0;       -- Length of text in the buffer
      Line   : Positive;           -- Source line where token starts
      Column : Positive;           -- Source column where token starts
   end record;

   --  Encapsulates the state of the lexer during processing.
   type Lexer_Context is private;

   --  Prepares the lexer with a source string.
   procedure Initialize (Ctx : in out Lexer_Context; Source : String);

   --  Extracts and returns the next token from the input stream.
   function Get_Next_Token (Ctx : in out Lexer_Context) return Token;

   --  Looks at the next token without advancing the lexer's position.
   function Peek_Next_Token (Ctx : in out Lexer_Context) return Token;

private
   --  The internal state of the lexer.
   type Lexer_Context is record
      Source      : String (1 .. 10000); -- Buffer for the input source code
      Source_Len  : Natural := 0;         -- Total length of source
      Pos         : Positive := 1;        -- Current read position in Source
      Line        : Positive := 1;        -- Current line counter
      Column      : Positive := 1;        -- Current column counter
      Peeked      : Token;                -- Buffer for Peek_Next_Token
      Has_Peeked  : Boolean := False;     -- Flag for peek state
   end record;

end SData.Lexer;
