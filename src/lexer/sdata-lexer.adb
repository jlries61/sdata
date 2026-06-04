--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

with Ada.Characters.Handling;  use Ada.Characters.Handling;
with Ada.Strings.Unbounded;    use Ada.Strings.Unbounded;

package body SData.Lexer is

   ------------------
   -- Initialize --
   ------------------
   --  Prepares the lexer with the input source code.
   procedure Initialize (Ctx : in out Lexer_Context; Source : String) is
   begin
      Ctx.Source     := To_Unbounded_String (Source);
      Ctx.Source_Len := Source'Length;
      Ctx.Pos := 1;
      Ctx.Line := 1;
      Ctx.Column := 1;
      Ctx.Has_Peeked := False;
   end Initialize;

   -----------------------
   -- Is_End_Of_Source --
   -----------------------
   function Is_End_Of_Source (Ctx : Lexer_Context) return Boolean is
   begin
      return Ctx.Pos > Ctx.Source_Len;
   end Is_End_Of_Source;

   ------------------
   -- Current_Char --
   ------------------
   function Current_Char (Ctx : Lexer_Context) return Character is
   begin
      if Is_End_Of_Source (Ctx) then
         return ASCII.NUL;
      else
         return Element (Ctx.Source, Ctx.Pos);
      end if;
   end Current_Char;

   -------------
   -- Advance --
   -------------
   --  Moves the read pointer forward by one character and updates line/column.
   procedure Advance (Ctx : in out Lexer_Context) is
   begin
      if not Is_End_Of_Source (Ctx) then
         if Element (Ctx.Source, Ctx.Pos) = ASCII.LF then
            --  Newline reached, increment line and reset column.
            Ctx.Line := Ctx.Line + 1;
            Ctx.Column := 1;
         else
            Ctx.Column := Ctx.Column + 1;
         end if;
         Ctx.Pos := Ctx.Pos + 1;
      end if;
   end Advance;

   ----------------------------
   -- Get_Next_Token_Internal --
   ----------------------------
   --  The core logic of the lexer. Skips whitespace and comments, 
   --  and identifies the next token.
   function Get_Next_Token_Internal (Ctx : in out Lexer_Context) return Token is
      T : Token;
   begin
      --  Skip whitespace and handle line continuations/comments.
      loop
         --  Skip simple whitespace.
         while not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) in ' ' | ASCII.HT | ASCII.CR loop
            Advance (Ctx);
         end loop;

         --  Handle line continuation: trailing comma before a newline.
         if not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) = ',' then
            declare
               Saved_Pos : constant Positive := Ctx.Pos;
               Saved_Col : constant Positive := Ctx.Column;
               Saved_Line : constant Positive := Ctx.Line;
               Found_Newline : Boolean := False;
            begin
               Advance (Ctx); -- Consume ','
               -- Skip spaces/tabs/carriage returns.
               while not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) in ' ' | ASCII.HT | ASCII.CR loop
                  Advance (Ctx);
               end loop;
               
               -- If next char is a newline, we have a continuation.
               if not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) = ASCII.LF then
                  Advance (Ctx); -- Consume LF
                  Found_Newline := True;
                  -- Skip whitespace and comments on the following line(s).
                  loop
                     while not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) in ' ' | ASCII.HT | ASCII.CR | ASCII.LF loop
                        Advance (Ctx);
                     end loop;
                     
                     -- Skip comments starting with '--' during continuation.
                     if not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) = '-' then
                        declare
                           Saved_Comment_Pos : constant Positive := Ctx.Pos;
                        begin
                           Advance (Ctx);
                           if not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) = '-' then
                              while not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) /= ASCII.LF loop
                                 Advance (Ctx);
                              end loop;
                           else
                              Ctx.Pos := Saved_Comment_Pos;
                              exit;
                           end if;
                        end;
                     elsif not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) = ',' then
                        -- Multiple commas allowed for multi-line continuation.
                        declare
                           Saved_C_Pos : constant Positive := Ctx.Pos;
                        begin
                           Advance (Ctx);
                           while not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) in ' ' | ASCII.HT | ASCII.CR loop
                              Advance (Ctx);
                           end loop;
                           if not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) = ASCII.LF then
                              Advance (Ctx);
                           else
                              Ctx.Pos := Saved_C_Pos;
                              exit;
                           end if;
                        end;
                     else
                        exit;
                     end if;
                  end loop;
               end if;

               if Found_Newline then
                  --  Continuation detected, restart skipping whitespace for the next token.
                  goto Continue_Loop;
               else
                  --  Just a normal comma, backtrack to it and return it as a token later.
                  Ctx.Pos := Saved_Pos;
                  Ctx.Column := Saved_Col;
                  Ctx.Line := Saved_Line;
                  exit;
               end if;
            end;
         elsif not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) = '-' then
            --  Handle comments starting with '--'.
            declare
               Saved_Pos : constant Positive := Ctx.Pos;
            begin
               Advance (Ctx);
               if not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) = '-' then
                  --  Comment detected, skip to end of line.
                  while not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) /= ASCII.LF loop
                     Advance (Ctx);
                  end loop;
                  goto Continue_Loop;
               else
                  --  Not a comment, treat as a normal minus operator later.
                  Ctx.Pos := Saved_Pos;
                  exit;
               end if;
            end;
         elsif not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) = ASCII.LF then
            --  Newline reached, return it as an explicit token (statement separator).
            T.Kind := Token_Newline;
            T.Line := Ctx.Line;
            T.Column := Ctx.Column;
            T.Text (1) := ' ';
            T.Length := 1;
            Advance (Ctx);
            return T;
         else
            exit;
         end if;
         <<Continue_Loop>>
         null;
      end loop;

      T.Line := Ctx.Line;
      T.Column := Ctx.Column;
      T.Length := 0;

      if Is_End_Of_Source (Ctx) then
         T.Kind := Token_EOF;
         return T;
      end if;

      declare
         C : constant Character := Current_Char (Ctx);
      begin
         --  Identify Numeric Literals.
         if Is_Digit (C) then
            T.Kind := Token_Numeric_Literal;
            while not Is_End_Of_Source (Ctx) and then (Is_Digit (Current_Char (Ctx)) or Current_Char (Ctx) = '.') loop
               T.Length := T.Length + 1;
               T.Text (T.Length) := Current_Char (Ctx);
               Advance (Ctx);
            end loop;
            -- E-notation: consume E/e followed by optional sign and digits.
            if not Is_End_Of_Source (Ctx)
               and then (Current_Char (Ctx) = 'E' or else Current_Char (Ctx) = 'e')
            then
               declare
                  Saved_Pos : constant Positive := Ctx.Pos;
                  Saved_Len : constant Natural   := T.Length;
               begin
                  T.Length := T.Length + 1;
                  T.Text (T.Length) := Current_Char (Ctx);
                  Advance (Ctx);
                  if not Is_End_Of_Source (Ctx)
                     and then (Current_Char (Ctx) = '+' or else Current_Char (Ctx) = '-')
                  then
                     T.Length := T.Length + 1;
                     T.Text (T.Length) := Current_Char (Ctx);
                     Advance (Ctx);
                  end if;
                  if not Is_End_Of_Source (Ctx) and then Is_Digit (Current_Char (Ctx)) then
                     while not Is_End_Of_Source (Ctx) and then Is_Digit (Current_Char (Ctx)) loop
                        T.Length := T.Length + 1;
                        T.Text (T.Length) := Current_Char (Ctx);
                        Advance (Ctx);
                     end loop;
                  else
                     Ctx.Pos := Saved_Pos;
                     T.Length := Saved_Len;
                  end if;
               end;
            end if;

         elsif Is_Letter (C) then
            while not Is_End_Of_Source (Ctx) and then (Is_Alphanumeric (Current_Char (Ctx)) or Current_Char (Ctx) = '_' or Current_Char (Ctx) = '$' or Current_Char (Ctx) = '%' or Current_Char (Ctx) = '.') loop
               T.Length := T.Length + 1;
               T.Text (T.Length) := Current_Char (Ctx);
               Advance (Ctx);
            end loop;

            --  Perform keyword lookup (Case-Insensitive).
            declare
               Upper : constant String := To_Upper (T.Text (1 .. T.Length));
            begin
               if Upper = "USE" or Upper = "/USE" then T.Kind := Token_USE;
               elsif Upper = "MOCK" or Upper = "/MOCK" then T.Kind := Token_MOCK;
               elsif Upper = "SAVE" or Upper = "/SAVE" then T.Kind := Token_SAVE;
               elsif Upper = "KEEP" then T.Kind := Token_KEEP;
               elsif Upper = "DROP" then T.Kind := Token_DROP;
               elsif Upper = "HOLD" then T.Kind := Token_HOLD;
               elsif Upper = "UNHOLD" then T.Kind := Token_UNHOLD;
               elsif Upper = "NEW" then T.Kind := Token_NEW;
               elsif Upper = "IF" then T.Kind := Token_IF;
               elsif Upper = "THEN" then T.Kind := Token_THEN;
               elsif Upper = "ELSEIF" then T.Kind := Token_ELSEIF;
               elsif Upper = "ELSE" then T.Kind := Token_ELSE;
               elsif Upper = "FOR" then T.Kind := Token_FOR;
               elsif Upper = "NEXT" then T.Kind := Token_NEXT;
               elsif Upper = "WHILE" then T.Kind := Token_WHILE;
               elsif Upper = "WEND" then T.Kind := Token_WEND;
               elsif Upper = "REPEAT" then T.Kind := Token_REPEAT;
               elsif Upper = "UNTIL" then T.Kind := Token_UNTIL;
               elsif Upper = "SELECT" then T.Kind := Token_SELECT;
               elsif Upper = "CASE" then T.Kind := Token_CASE;
               elsif Upper = "WHEN" then T.Kind := Token_WHEN;
               elsif Upper = "OTHERWISE" then T.Kind := Token_OTHERWISE;
               elsif Upper = "SUBMIT" or Upper = "/SUBMIT" then T.Kind := Token_SUBMIT;
               elsif Upper = "LET" then T.Kind := Token_LET;
               elsif Upper = "SET" then T.Kind := Token_SET;
               elsif Upper = "UNSET" then T.Kind := Token_UNSET;
               elsif Upper = "DIM" then T.Kind := Token_DIM;
               elsif Upper = "ARRAY" then T.Kind := Token_ARRAY;
               elsif Upper = "SYSTEM" or Upper = "/SYSTEM" then T.Kind := Token_SYSTEM;
               elsif Upper = "PRINT" then T.Kind := Token_PRINT;
               elsif Upper = "WRITE" then T.Kind := Token_WRITE;
               elsif Upper = "OUTPUT" or Upper = "/OUTPUT" then T.Kind := Token_OUTPUT;
               elsif Upper = "ECHO" then T.Kind := Token_ECHO;
               elsif Upper = "BY" then T.Kind := Token_BY;
               elsif Upper = "SORT" then T.Kind := Token_SORT;
               elsif Upper = "RENAME" then T.Kind := Token_RENAME;
               elsif Upper = "DELETE" then T.Kind := Token_DELETE;
               elsif Upper = "RSEED" then T.Kind := Token_RSEED;
               elsif Upper = "NOT" then T.Kind := Token_NOT;
               elsif Upper = "AND" then T.Kind := Token_AND;
               elsif Upper = "OR" then T.Kind := Token_OR;
               elsif Upper = "XOR" then T.Kind := Token_XOR;
               elsif Upper = "OPTIONS" then T.Kind := Token_OPTIONS;
               elsif Upper = "DIGITS" then T.Kind := Token_DIGITS;
               elsif Upper = "FPATH" then T.Kind := Token_FPATH;
               elsif Upper = "HEADER" then T.Kind := Token_HEADER;
               elsif Upper = "ALL" or Upper = "/ALL" then T.Kind := Token_ALL;
               elsif Upper = "AS" then T.Kind := Token_AS;
               elsif Upper = "IN" then T.Kind := Token_IN;
               elsif Upper = "INTERLEAVE" then T.Kind := Token_INTERLEAVE;
               elsif Upper = "JOIN" then T.Kind := Token_JOIN;
               elsif Upper = "APPEND" then T.Kind := Token_APPEND;
               elsif Upper = "REM" then 
                  T.Kind := Token_REM;
                  -- Skip rest of line for REM command (comment).
                  while not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) /= ASCII.LF loop
                     Advance (Ctx);
                  end loop;
               elsif Upper = "HELP" then T.Kind := Token_HELP;
               elsif Upper = "END" then T.Kind := Token_END;
               elsif Upper = "QUIT" then T.Kind := Token_QUIT;
               elsif Upper = "RUN" then T.Kind := Token_RUN;
               elsif Upper = "NAMES" then T.Kind := Token_NAMES;
               elsif Upper = "LIST" then T.Kind := Token_LIST;
               elsif Upper = "DISPLAY" then T.Kind := Token_DISPLAY;
               elsif Upper = "TO" then T.Kind := Token_TO;
               elsif Upper = "STEP" then T.Kind := Token_STEP;
               elsif Upper = "BREAK"     then T.Kind := Token_BREAK;
               elsif Upper = "INTO"      then T.Kind := Token_INTO;
               else
                  T.Kind := Token_Identifier;
               end if;
            end;

         --  Identify String Literals.
         elsif C = '"' then
            T.Kind := Token_String_Literal;
            Advance (Ctx); -- skip opening quote
            while not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) /= '"' loop
               T.Length := T.Length + 1;
               T.Text (T.Length) := Current_Char (Ctx);
               Advance (Ctx);
               -- Handle escaped quotes (double-double quotes).
               if not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) = '"' then
                  declare
                     Saved_Pos : constant Positive := Ctx.Pos;
                  begin
                     Advance (Ctx);
                     if not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) = '"' then
                        -- Embedded quote found: ""
                        null;
                     else
                        -- End of string reached, backtrack to the closing quote.
                        Ctx.Pos := Saved_Pos;
                        exit;
                     end if;
                  end;
               end if;
            end loop;
            if not Is_End_Of_Source (Ctx) then
               Advance (Ctx); -- skip closing quote
            end if;

         --  Single-quoted string literals.
         elsif C = ''' then
            T.Kind := Token_String_Literal;
            Advance (Ctx); -- skip opening quote
            while not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) /= ''' loop
               T.Length := T.Length + 1;
               T.Text (T.Length) := Current_Char (Ctx);
               Advance (Ctx);
            end loop;
            if not Is_End_Of_Source (Ctx) then
               Advance (Ctx); -- skip closing quote
            end if;

         --  Identify punctuation and operators.
         else
            case C is
               when '+' => T.Kind := Token_Plus; Advance (Ctx);
               when '-' => T.Kind := Token_Minus; Advance (Ctx);
               when '*' => T.Kind := Token_Star; Advance (Ctx);
               when '/' => T.Kind := Token_Slash; Advance (Ctx);
               when '^' => T.Kind := Token_Caret; Advance (Ctx);
               when '=' => T.Kind := Token_Equal; Advance (Ctx);
               when '<' =>
                  Advance (Ctx);
                  if not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) = '=' then
                     T.Kind := Token_Less_Equal; Advance (Ctx);
                  elsif not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) = '>' then
                     T.Kind := Token_Not_Equal; Advance (Ctx);
                  else
                     T.Kind := Token_Less;
                  end if;
               when '>' =>
                  Advance (Ctx);
                  if not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) = '=' then
                     T.Kind := Token_Greater_Equal; Advance (Ctx);
                  else
                     T.Kind := Token_Greater;
                  end if;
               when '(' => T.Kind := Token_Left_Paren; Advance (Ctx);
               when ')' => T.Kind := Token_Right_Paren; Advance (Ctx);
               when '{' => T.Kind := Token_Left_Brace; Advance (Ctx);
               when '}' => T.Kind := Token_Right_Brace; Advance (Ctx);
               when ',' => T.Kind := Token_Comma; Advance (Ctx);
               when ';' => T.Kind := Token_Semicolon; Advance (Ctx);
               when ':' => T.Kind := Token_Colon; Advance (Ctx);
               when '|' =>
                  T.Kind := Token_Pipe;
                  T.Text (1) := '|';
                  T.Length := 1;
                  Advance (Ctx);
                  --  Consume a second '|' if present (e.g. DLM=||).
                  if not Is_End_Of_Source (Ctx) and then Current_Char (Ctx) = '|' then
                     T.Text (2) := '|';
                     T.Length := 2;
                     Advance (Ctx);
                  end if;
               when '.' =>
                  Advance (Ctx);
                  if not Is_End_Of_Source (Ctx)
                     and then Is_Digit (Current_Char (Ctx))
                  then
                     T.Kind := Token_Numeric_Literal;
                     T.Length := 2;
                     T.Text (1) := '0';
                     T.Text (2) := '.';
                     while not Is_End_Of_Source (Ctx)
                        and then Is_Digit (Current_Char (Ctx))
                     loop
                        T.Length := T.Length + 1;
                        T.Text (T.Length) := Current_Char (Ctx);
                        Advance (Ctx);
                     end loop;
                  else
                     T.Kind := Token_Dot;
                  end if;
               when others =>
                  --  Unknown character, skip it and move on.
                  Advance (Ctx);
                  return Get_Next_Token_Internal (Ctx);
            end case;
         end if;
      end;

      return T;
   end Get_Next_Token_Internal;

   --------------------
   -- Get_Next_Token --
   --------------------
   function Get_Next_Token (Ctx : in out Lexer_Context) return Token is
   begin
      if Ctx.Has_Peeked then
         Ctx.Has_Peeked := False;
         return Ctx.Peeked;
      else
         return Get_Next_Token_Internal (Ctx);
      end if;
   end Get_Next_Token;

   ---------------------
   -- Peek_Next_Token --
   ---------------------
   function Peek_Next_Token (Ctx : in out Lexer_Context) return Token is
   begin
      if not Ctx.Has_Peeked then
         Ctx.Peeked := Get_Next_Token_Internal (Ctx);
         Ctx.Has_Peeked := True;
      end if;
      return Ctx.Peeked;
   end Peek_Next_Token;

end SData.Lexer;