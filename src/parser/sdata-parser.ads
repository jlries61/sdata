--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

--  Package SData.Parser implements a recursive descent parser for the SData language.
--  It takes a stream of tokens from the lexer and organizes them into an AST
--  consisting of linked statements and expressions.

with SData.Lexer;           use SData.Lexer;
with SData.AST;             use SData.AST;

package SData.Parser is

   --  Holds the state required for parsing, primarily the lexer context.
   type Parser_Context is record
      Lex_Ctx : Lexer_Context;
   end record;

   --  Initializes the parser and the underlying lexer with the source code.
   --  Raised when a multi-line statement (IF, FOR, SELECT, etc.) hits EOF
   Incomplete_Statement : exception;

   procedure Initialize (Ctx : in out Parser_Context; Source : String);

   --  Parses the entire source code and returns the root of the statement list.
   --  Returns null if the source is empty.
   function Parse_Program (Ctx : in out Parser_Context) return Statement_Access;

   --  True when parsing stopped at end-of-source immediately after a
   --  trailing-comma line continuation (a statement ending with a comma).
   --  The interactive REPL uses this to keep buffering and prompt for the
   --  continuation line rather than executing a half-finished statement.
   function Ended_With_Continuation (Ctx : Parser_Context) return Boolean;

end SData.Parser;