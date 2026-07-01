--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

--  Package SData.Lexer performs lexical analysis, converting raw source code (String)
--  into a stream of meaningful 'Token' records. It handles keywords, literals,
--  operators, and tracks position (line/column) for error reporting.

with Ada.Strings.Unbounded;

package SData.Lexer is

   --  Categories of tokens recognized by the lexer.
   type Token_Kind is (
      Token_EOF,               -- End of file
      Token_Identifier,        -- Variables and function names
      Token_Quoted_Identifier, -- `backtick-quoted` identifier (reserved words / spaces)
      Token_String_Literal,    -- "Quoted strings"
      Token_Numeric_Literal,   -- 123.45
      Token_Bad,               -- Lex error sentinel (e.g. unterminated quoted identifier)

      -- Keywords (Commands / Commands that are reserved words)
      Token_USE, Token_MOCK, Token_SAVE, Token_KEEP, Token_DROP, Token_HOLD, Token_UNHOLD, Token_NEW,
      Token_IF, Token_THEN, Token_ELSE, Token_ELSEIF, Token_FOR, Token_NEXT, Token_WHILE, Token_WEND,
      Token_REPEAT, Token_UNTIL, Token_SELECT, Token_CASE, Token_WHEN, Token_OTHERWISE, Token_SUBMIT,
      Token_LET, Token_SET, Token_UNSET, Token_DIM, Token_ARRAY, Token_SYSTEM,
      Token_PRINT, Token_WRITE, Token_OUTPUT, Token_ECHO,
      Token_BY, Token_SORT, Token_RENAME, Token_DELETE, Token_RSEED, Token_NOT, Token_AND, Token_OR, Token_XOR,
      Token_OPTIONS, Token_DIGITS, Token_FPATH, Token_HEADER, Token_ALL,
      Token_REM, Token_HELP, Token_END, Token_RUN, Token_QUIT, Token_NAMES, Token_LIST, Token_DISPLAY,
      Token_AGGREGATE,
      Token_TRANSPOSE,
      Token_STATS,
      Token_INSERT,
      Token_TO, Token_STEP, Token_BREAK, Token_INTO,
      Token_AS, Token_IN, Token_INTERLEAVE, Token_JOIN, Token_APPEND,

      -- Operators and Punctuation
      Token_Plus, Token_Minus, Token_Star, Token_Slash, Token_Caret, -- +, -, *, /, ^
      Token_Equal, Token_Not_Equal, Token_Less, Token_Less_Equal, Token_Greater, Token_Greater_Equal, -- =, <>, <, <=, >, >=
      Token_Left_Paren, Token_Right_Paren, Token_Left_Brace, Token_Right_Brace, -- (, ), {, }
      Token_Comma, Token_Semicolon, Token_Colon, Token_Dot, -- ,, ;, :, .
      Token_Dollar,          -- standalone $ (INSERT $)
      Token_Pipe,            -- | or || (delimiter value)
      Token_Newline,         -- Explicit newline tracking
      Token_Range_Dash       -- Used in variable ranges: NAME1-NAME5
   );

   --  Maximum length of any single token's raw text (identifiers, string
   --  literals, numeric literals).  Enforced implicitly by slice assignment
   --  in the lexer; tokens longer than this raise Constraint_Error.
   Max_Token_Len : constant := 1024;

   --  Represents a single lexical unit.
   type Token is record
      Kind   : Token_Kind;
      Text   : String (1 .. Max_Token_Len); -- Raw text content of the token
      Length : Natural := 0;                -- Length of text in the buffer
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

   --  True when the token stream just reached end-of-source immediately
   --  after consuming a trailing-comma line continuation (a statement
   --  ending with a comma, per the design spec).  The interactive REPL
   --  uses this to keep buffering and prompt for the continuation line
   --  instead of treating the statement as complete.
   function Ended_With_Continuation (Ctx : Lexer_Context) return Boolean;

private
   --  The internal state of the lexer.
   type Lexer_Context is record
      Source      : Ada.Strings.Unbounded.Unbounded_String; -- Input source code
      Source_Len  : Natural := 0;                            -- Total length of source
      Pos         : Positive := 1;        -- Current read position in Source
      Line        : Positive := 1;        -- Current line counter
      Column      : Positive := 1;        -- Current column counter
      Peeked      : Token;                -- Buffer for Peek_Next_Token
      Has_Peeked  : Boolean := False;     -- Flag for peek state
      --  Set when an EOF token is produced right after a trailing-comma
      --  continuation was consumed with no following content.
      Continued_At_EOF : Boolean := False;
   end record;

end SData.Lexer;