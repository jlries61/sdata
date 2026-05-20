--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

with SData_Core.IO;        use SData_Core.IO;
with SData_Core.Evaluator; use SData_Core.Evaluator;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with Ada.Strings.Unbounded;   use Ada.Strings.Unbounded;
with SData_Core.Config;
with SData_Core.Variables; use SData_Core.Variables;

--  SData.Parser — recursive-descent parser for the SData command language.
--
--  Entry points:
--    Parse_Statement  parse one statement from an already-initialised context
--    Parse_Program    parse a complete statement list until EOF
--
--  Expression parsing uses a precedence-climbing (Pratt) algorithm:
--    Parse_Expression → Parse_Expression_1(min_prec=1) → Parse_Primary
--  Get_Precedence maps each binary operator token to a numeric level; higher
--  numbers bind more tightly.  Parse_Expression_1 recurses with (prec+1) for
--  left-associative operators so that equal-precedence operators associate left.
--
--  Statements are a flat case dispatch in Parse_Statement.  Some statements
--  (IF, FOR, WHILE, SELECT) recurse back into Parse_Statement / Parse_Block /
--  Parse_If_Body to collect their sub-statement lists.
--
--  The SELECT token is overloaded across three distinct forms:
--    SELECT /ALL          → Stmt_SELECT_FILTER with null Expr (cancel filter)
--    SELECT <expr>        → Stmt_SELECT_FILTER with non-null Expr (set filter)
--    SELECT [<expr>] CASE → Stmt_SELECT (control structure / multi-way branch)
--  The parser distinguishes these by peeking at the token after the optional
--  expression.

package body SData.Parser is

   ------------------
   -- Initialize --
   ------------------
   procedure Initialize (Ctx : in out Parser_Context; Source : String) is
   begin
      Initialize (Ctx.Lex_Ctx, Source);
   end Initialize;

   ---------------------------------------------------------------------------
   --  Token_To_String — reconstruct the source text of a single token.
   --
   --  Used by Collect_Line_Text to rebuild a parseable string from the token
   --  stream for forwarding to SData_Core.Evaluator.Parse_Expression.
   --  String literals are re-quoted (Ada style: "..." with "" for embedded ").
   --  Operator tokens are mapped to their canonical character sequences.
   ---------------------------------------------------------------------------
   function Token_To_String (T : Token) return String is
      Raw : constant String := T.Text (1 .. T.Length);
   begin
      case T.Kind is
         when Token_Identifier | Token_Numeric_Literal =>
            return Raw;
         when Token_String_Literal =>
            --  Re-quote: scan for embedded '"' and double them.
            declare
               Buf : String (1 .. Raw'Length * 2 + 2);
               Len : Natural := 0;
            begin
               Len := Len + 1; Buf (Len) := '"';
               for Ch of Raw loop
                  if Ch = '"' then
                     Len := Len + 1; Buf (Len) := '"';
                     Len := Len + 1; Buf (Len) := '"';
                  else
                     Len := Len + 1; Buf (Len) := Ch;
                  end if;
               end loop;
               Len := Len + 1; Buf (Len) := '"';
               return Buf (1 .. Len);
            end;
         --  Keywords that appear in expressions:
         when Token_NOT  => return "NOT";
         when Token_AND  => return "AND";
         when Token_OR   => return "OR";
         when Token_XOR  => return "XOR";
         when Token_IF   => return "IF";
         when Token_NEXT => return "NEXT";
         --  Operators and punctuation:
         when Token_Plus          => return "+";
         when Token_Minus         => return "-";
         when Token_Star          => return "*";
         when Token_Slash         => return "/";
         when Token_Caret         => return "**";
         when Token_Equal         => return "=";
         when Token_Not_Equal     => return "<>";
         when Token_Less          => return "<";
         when Token_Less_Equal    => return "<=";
         when Token_Greater       => return ">";
         when Token_Greater_Equal => return ">=";
         when Token_Left_Paren    => return "(";
         when Token_Right_Paren   => return ")";
         when Token_Left_Brace    => return "(";  -- treat {} as ()
         when Token_Right_Brace   => return ")";
         when Token_Comma         => return ",";
         when Token_Colon         => return ":";
         when Token_Dot           => return ".";
         when others => return Raw;
      end case;
   end Token_To_String;

   ---------------------------------------------------------------------------
   --  Collect_Select_Filter_Text — drain the token stream for a SELECT filter
   --  expression, reconstructing tokens as a space-separated string suitable
   --  for SData_Core.Evaluator.Parse_Expression.
   --
   --  Stops (without consuming) at:
   --    Token_Newline, Token_EOF, Token_Slash, Token_Semicolon, Token_Colon,
   --    Token_CASE, Token_WHEN, Token_OTHERWISE.
   --
   --  Top-level commas (outside parentheses) separate conjuncts in a SELECT
   --  filter; they are converted to " AND " in the output so that the resulting
   --  string parses as a single expression.  Commas inside parentheses (e.g.,
   --  function arguments) are preserved as-is.
   ---------------------------------------------------------------------------
   function Collect_Select_Filter_Text (Ctx : in out Parser_Context) return String is
      Buf         : Unbounded_String := Null_Unbounded_String;
      Tok         : Token;
      First_Token : Boolean := True;
      Depth       : Natural := 0; -- parenthesis depth
   begin
      loop
         declare
            P : constant Token_Kind := Peek_Next_Token (Ctx.Lex_Ctx).Kind;
         begin
            exit when P = Token_Newline   or else P = Token_EOF   or else
                      P = Token_Slash     or else P = Token_Semicolon or else
                      P = Token_CASE      or else P = Token_WHEN  or else
                      P = Token_OTHERWISE or else P = Token_Colon;
         end;
         Tok := Get_Next_Token (Ctx.Lex_Ctx);
         --  Track paren depth so we only promote top-level commas.
         if Tok.Kind = Token_Left_Paren or else Tok.Kind = Token_Left_Brace then
            Depth := Depth + 1;
         elsif Tok.Kind = Token_Right_Paren or else Tok.Kind = Token_Right_Brace then
            if Depth > 0 then Depth := Depth - 1; end if;
         end if;
         --  Top-level comma → conjunct separator (AND).
         if Tok.Kind = Token_Comma and then Depth = 0 then
            Append (Buf, " AND");
            First_Token := False;
         else
            if not First_Token then
               Append (Buf, " ");
            end if;
            Append (Buf, Token_To_String (Tok));
            First_Token := False;
         end if;
      end loop;
      return To_String (Buf);
   end Collect_Select_Filter_Text;

   --  Forward declarations for mutual recursion.
   function Parse_Expression (Ctx : in out Parser_Context) return Expression_Access;
   function Parse_Expression_List (Ctx : in out Parser_Context; Closing : Token_Kind) return Expression_List;
   function Parse_Statement (Ctx : in out Parser_Context) return Statement_Access;
   --  Parse an IF/ELSEIF statement starting from the condition (IF token already consumed).
   function Parse_If_Statement (Ctx : in out Parser_Context) return Statement_Access;

   --  Parse a block of statements for the body of a block-form IF clause.
   --  Stops when it encounters ELSE, ELSEIF, or END (any of which is consumed).
   --  Returns the terminating token kind via Term_Kind.
   function Parse_If_Body (Ctx      : in out Parser_Context;
                           Term_Kind : out Token_Kind) return Statement_Access;

   function Parse_Select_Body (Ctx : in out Parser_Context) return Statement_Access;

   function Parse_Select_Body (Ctx : in out Parser_Context) return Statement_Access is
      First, Current, New_Stmt : Statement_Access := null;
   begin
      loop
         --  Skip blank lines / colons.
         while Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Newline or else
               Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Colon loop
            declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
         end loop;
         --  Check for next case or end select.
         declare Peek : constant Token_Kind := Peek_Next_Token (Ctx.Lex_Ctx).Kind; begin
            exit when Peek = Token_CASE or else Peek = Token_WHEN or else
                      Peek = Token_OTHERWISE or else Peek = Token_END or else
                      Peek = Token_EOF;
         end;
         New_Stmt := Parse_Statement (Ctx);
         if New_Stmt = null then return First; end if;
         if First = null then First := New_Stmt; Current := New_Stmt;
         else Current.Next := New_Stmt; Current := New_Stmt; end if;
      end loop;
      return First;
   end Parse_Select_Body;

   function Parse_If_Body (Ctx      : in out Parser_Context;
                           Term_Kind : out Token_Kind) return Statement_Access is
      First, Current, New_Stmt : Statement_Access := null;
   begin
      loop
         --  Skip blank lines / colons.
         while Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Newline or else
               Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Colon loop
            declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
         end loop;
         --  Check terminators.
         declare Peek : constant Token_Kind := Peek_Next_Token (Ctx.Lex_Ctx).Kind; begin
            if Peek = Token_ELSE or else Peek = Token_ELSEIF or else
               Peek = Token_END
            then
               declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
               Term_Kind := Peek;
               return First;
            elsif Peek = Token_EOF then
               raise Incomplete_Statement;
            end if;
         end;
         New_Stmt := Parse_Statement (Ctx);
         if New_Stmt = null then Term_Kind := Token_EOF; return First; end if;
         if First = null then First := New_Stmt; Current := New_Stmt;
         else Current.Next := New_Stmt; Current := New_Stmt; end if;
      end loop;
   end Parse_If_Body;

   --  Parse an IF (or ELSEIF) statement starting from the condition expression.
   --  The IF/ELSEIF keyword has already been consumed by the caller.
   function Parse_If_Statement (Ctx : in out Parser_Context) return Statement_Access is
      S : constant Statement_Access := new Statement (Stmt_IF);
   begin
      S.Condition := Parse_Expression (Ctx);
      if Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_THEN then
         raise Script_Error with "Expected THEN after IF condition.";
      else
         declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
      end if;
      if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Newline or else
         Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_EOF
      then
         --  Block form.
         declare Term : Token_Kind; begin
            S.Then_Branch := Parse_If_Body (Ctx, Term);
            if Term = Token_ELSEIF then
               S.Else_Branch := Parse_If_Statement (Ctx);
            elsif Term = Token_ELSE then
               declare Term2 : Token_Kind; begin
                  S.Else_Branch := Parse_If_Body (Ctx, Term2);
                  if Term2 = Token_END and then
                     Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_IF then
                     declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
                  end if;
               end;
            elsif Term = Token_END then
               if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_IF then
                  declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
               end if;
               S.Else_Branch := null;
            end if;
         end;
      else
         --  Inline form.
         S.Then_Branch := Parse_Statement (Ctx);
         if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_ELSEIF then
            declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
            S.Else_Branch := Parse_If_Statement (Ctx);
         elsif Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_ELSE then
            declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
            S.Else_Branch := Parse_Statement (Ctx);
         else
            S.Else_Branch := null;
         end if;
      end if;
      return S;
   end Parse_If_Statement;
   function Parse_Rename_List (Ctx : in out Parser_Context) return Rename_List;

   ---------------------------
   -- Parse_Expression_List --
   ---------------------------
   function Parse_Expression_List (Ctx : in out Parser_Context; Closing : Token_Kind) return Expression_List is
      Head, Last, New_Node : Expression_List := null;
   begin
      if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Closing then
         return null;
      end if;

      loop
         declare
            Expr     : constant Expression_Access := Parse_Expression (Ctx);
            Is_Range : Boolean := False;
            Expr_End : Expression_Access := null;
         begin
            if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Colon then
               declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
               Is_Range := True;
               Expr_End := Parse_Expression (Ctx);
            end if;

            New_Node := new Expression_List_Node'(Expr     => Expr,
                                             Is_Range => Is_Range,
                                             Expr_End => Expr_End,
                                             Next     => null);
            if Head = null then
               Head := New_Node;
            else
               Last.Next := New_Node;
            end if;
            Last := New_Node;
         end;

         if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Comma then
            declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
         else
            exit;
         end if;
      end loop;

      return Head;
   end Parse_Expression_List;

   -----------------
   -- Parse_Block --
   -----------------
   --  Parses a sequence of statements until a specific terminating token is reached.
   function Parse_Block (Ctx : in out Parser_Context; End_Tok : Token_Kind) return Statement_Access is
      First, Current, New_Stmt : Statement_Access := null;
   begin
      loop
         --  Skip separators.
         while Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Newline or else 
               Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Colon loop
            declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
         end loop;

         --  Check if we've reached the end of the block or EOF.
         if Peek_Next_Token (Ctx.Lex_Ctx).Kind = End_Tok then
            declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
            exit;
         elsif Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_EOF then
            raise Incomplete_Statement;
         end if;

         New_Stmt := Parse_Statement (Ctx);
         if New_Stmt = null then exit; end if;

         if First = null then
            First := New_Stmt;
            Current := New_Stmt;
         else
            Current.Next := New_Stmt;
            Current := New_Stmt;
         end if;
      end loop;
      return First;
   end Parse_Block;

   -------------------
   -- Parse_Primary --
   -------------------
   --  Parses the smallest complete unit of an expression: a literal, a
   --  parenthesised sub-expression, a variable reference, or a function call.
   --
   --  Token_NEXT and Token_IF are lexed as keywords but can also appear as
   --  function calls (e.g. NEXT("X") or IF(cond, t, f)).  They are therefore
   --  handled identically to Token_Identifier here: if followed by '(' or '{'
   --  they become an Expr_Function_Call node; otherwise an Expr_Variable node.
   function Parse_Primary (Ctx : in out Parser_Context) return Expression_Access is
      Tok : constant Token := Peek_Next_Token (Ctx.Lex_Ctx);
      Node : Expression_Access;
   begin
      case Tok.Kind is
         when Token_Minus | Token_NOT =>
            declare
               Op_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
            begin
               Node := new Expression (Expr_Unary_Op);
               Node.UOp := (if Op_Tok.Kind = Token_NOT then Op_Not else Op_Neg);
               Node.Operand := Parse_Primary (Ctx);
               return Node;
            end;
         when others =>
            declare
               Actual_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
            begin
               case Actual_Tok.Kind is
                  when Token_Numeric_Literal =>
                     Node := new Expression (Expr_Numeric_Literal);
                     declare
                        S       : constant String := Actual_Tok.Text (1 .. Actual_Tok.Length);
                        Has_Dot : Boolean := False;
                     begin
                        for Ch of S loop
                           if Ch = '.' then Has_Dot := True; exit; end if;
                        end loop;
                        Node.Value := Float'Value (S);
                        if not Has_Dot then
                           begin
                              Node.Int_Value  := Integer'Value (S);
                              Node.Is_Integer := True;
                           exception
                              when Constraint_Error => null;  --  Exceeds Integer'Last; stay Float.
                           end;
                        end if;
                     end;
                     return Node;

                  when Token_String_Literal =>
                     Node := new Expression (Expr_String_Literal);
                     Node.Str_Value := To_Unbounded_String (Actual_Tok.Text (1 .. Actual_Tok.Length));
                     return Node;

                  when Token_Identifier | Token_NEXT | Token_IF =>
                     if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Left_Paren or else
                        Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Left_Brace then
                        declare
                           LP : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                           Closing : constant Token_Kind := (if LP.Kind = Token_Left_Paren then Token_Right_Paren else Token_Right_Brace);
                        begin
                           if Has_Array (To_Upper (Actual_Tok.Text (1 .. Actual_Tok.Length))) then
                              Node := new Expression (Expr_Array_Access);
                              Node.Arr_Len := Actual_Tok.Length;
                              Node.Arr_Name (1 .. Actual_Tok.Length) := Actual_Tok.Text (1 .. Actual_Tok.Length);
                              Node.Arr_Idx := Parse_Expression_List (Ctx, Closing);
                           else
                              Node := new Expression (Expr_Function_Call);
                              Node.Func_Len := Actual_Tok.Length;
                              Node.Func_Name (1 .. Actual_Tok.Length) := Actual_Tok.Text (1 .. Actual_Tok.Length);
                              Node.Arguments := Parse_Expression_List (Ctx, Closing);
                           end if;

                           declare
                              Next_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                           begin
                              if Next_Tok.Kind /= Closing then
                                 Put_Line_Error ("Error: Expected closing '" &
                                    (if Closing = Token_Right_Paren then ")" else "]") &
                                    "' after arguments of """ &
                                    Actual_Tok.Text (1 .. Actual_Tok.Length) & """");
                              end if;
                           end;
                        end;
                        return Node;
                     else
                        Node := new Expression (Expr_Variable);
                        Node.Var_Len := Actual_Tok.Length;
                        Node.Var_Name (1 .. Actual_Tok.Length) := Actual_Tok.Text (1 .. Actual_Tok.Length);
                        return Node;
                     end if;

                  when Token_Left_Paren =>
                     Node := Parse_Expression (Ctx);
                     if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Right_Paren then
                        Put_Line_Error ("Error: Expected ')' to close parenthesised expression");
                     end if;
                     return Node;

                  when Token_Dot =>
                     return new Expression (Expr_Missing);

                  when others =>
                     return null;
               end case;
            end;
      end case;
   end Parse_Primary;

   --------------------
   -- Get_Precedence --
   --------------------
   function Get_Precedence (Kind : Token_Kind) return Integer is
   begin
      case Kind is
         when Token_OR | Token_XOR => return 5;
         when Token_AND => return 6;
         when Token_Equal | Token_Not_Equal | Token_Less | Token_Less_Equal | Token_Greater | Token_Greater_Equal => return 10;
         when Token_Plus | Token_Minus => return 20;
         when Token_Star | Token_Slash => return 30;
         when Token_Caret => return 40;
         when others => return 0;
      end case;
   end Get_Precedence;

   -------------------
   -- To_Binary_Op --
   -------------------
   function To_Binary_Op (Kind : Token_Kind) return Binary_Op is
   begin
      case Kind is
         when Token_Plus => return Op_Add;
         when Token_Minus => return Op_Sub;
         when Token_Star => return Op_Mul;
         when Token_Slash => return Op_Div;
         when Token_Caret => return Op_Pow;
         when Token_Equal => return Op_Eq;
         when Token_Not_Equal => return Op_Ne;
         when Token_Less => return Op_Lt;
         when Token_Less_Equal => return Op_Le;
         when Token_Greater => return Op_Gt;
         when Token_Greater_Equal => return Op_Ge;
         when Token_AND => return Op_And;
         when Token_OR => return Op_Or;
         when Token_XOR => return Op_Xor;
         when others => raise Program_Error;
      end case;
   end To_Binary_Op;

   ------------------------
   -- Parse_Expression_1 --
   ------------------------
   --  Precedence-climbing (Pratt) binary-operator parser.
   --  Starts by parsing a primary, then repeatedly peeks at the next token:
   --    * If its precedence is below Min_Precedence, stop.
   --    * Otherwise consume the operator and recurse with (prec + 1) as the
   --      new minimum, which makes all built-in operators left-associative
   --      (a right-associative operator would recurse with the same prec).
   function Parse_Expression_1 (Ctx : in out Parser_Context; Min_Precedence : Integer) return Expression_Access is
      Left : Expression_Access := Parse_Primary (Ctx);
   begin
      if Left = null then return null; end if;

      loop
         declare
            Tok : constant Token := Peek_Next_Token (Ctx.Lex_Ctx);
            Prec : constant Integer := Get_Precedence (Tok.Kind);
         begin
            if Prec < Min_Precedence then
               exit;
            end if;
            
            declare
               Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
               Right : constant Expression_Access := Parse_Expression_1 (Ctx, Prec + 1);
               New_Node : Expression_Access;
            begin
               if Right = null then
                  Put_Line_Error ("Error: Expected expression after operator");
                  exit;
               end if;
               New_Node := new Expression (Expr_Binary_Op);
               New_Node.Left := Left;
               New_Node.Right := Right;
               New_Node.Op := To_Binary_Op (Tok.Kind);
               Left := New_Node;
            end;
         end;
      end loop;
      return Left;
   end Parse_Expression_1;

   ----------------------
   -- Parse_Expression --
   ----------------------
   function Parse_Expression (Ctx : in out Parser_Context) return Expression_Access is
   begin
      return Parse_Expression_1 (Ctx, 1);
   end Parse_Expression;

   -------------------------
   -- Parse_Variable_List --
   -------------------------
   --  Parses a whitespace- or comma-separated list of variable names, with
   --  optional range syntax.  A range is written as either A-Z or A:Z and
   --  expands at execution time to all columns between the two named columns
   --  in their current table order.  Each entry is stored as a Variable_Range
   --  node; Is_Range is True only for the two-name form.
   function Parse_Variable_List (Ctx : in out Parser_Context) return Variable_List is
      First : Variable_List := null;
      Last  : Variable_List := null;
      Tok   : Token;
   begin
      loop
         Tok := Peek_Next_Token (Ctx.Lex_Ctx);
         exit when Tok.Kind /= Token_Identifier;
         
         Tok := Get_Next_Token (Ctx.Lex_Ctx);
         declare
            Node : constant Variable_List := new Variable_List_Node;
         begin
            Node.Var.Start_Name (1 .. Tok.Length) := Tok.Text (1 .. Tok.Length);
            Node.Var.Start_Len := Tok.Length;
            
            declare
               P : constant Token := Peek_Next_Token (Ctx.Lex_Ctx);
            begin
               if P.Kind = Token_Minus or else P.Kind = Token_Colon then
                  declare
                     Sep     : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                     End_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                  begin
                     if End_Tok.Kind /= Token_Identifier then
                        Put_Line_Error ("Error: Expected identifier after '" & Sep.Kind'Image & "' in range");
                     else
                        Node.Var.Is_Range       := True;
                        Node.Var.Is_Colon_Range := (Sep.Kind = Token_Colon);
                        Node.Var.End_Name (1 .. End_Tok.Length) := End_Tok.Text (1 .. End_Tok.Length);
                        Node.Var.End_Len := End_Tok.Length;
                     end if;
                  end;
               end if;
            end;
            
            if First = null then
               First := Node;
            else
               Last.Next := Node;
            end if;
            Last := Node;
         end;
         
         if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Comma then
            declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
         end if;
      end loop;
      return First;
   end Parse_Variable_List;

   -----------------------
   -- Parse_Rename_List --
   -----------------------
   function Parse_Rename_List (Ctx : in out Parser_Context) return Rename_List is
      First : Rename_List := null;
      Last  : Rename_List := null;
      Tok   : Token;
   begin
      loop
         Tok := Get_Next_Token (Ctx.Lex_Ctx);
         exit when Tok.Kind /= Token_Identifier;

         declare
            Pair : constant Rename_List := new Rename_Pair_Node;
         begin
            Pair.Old_Len := Tok.Length;
            Pair.Old_Name (1 .. Tok.Length) := Tok.Text (1 .. Tok.Length);
            
            if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Equal then
               Put_Line_Error ("Error: Expected '=' in RENAME list");
            end if;
            
            Tok := Get_Next_Token (Ctx.Lex_Ctx);
            if Tok.Kind /= Token_Identifier then
               Put_Line_Error ("Error: Expected identifier after '=' in RENAME list");
            end if;
            
            Pair.New_Len := Tok.Length;
            Pair.New_Name (1 .. Tok.Length) := Tok.Text (1 .. Tok.Length);
            
            if First = null then First := Pair; else Last.Next := Pair; end if;
            Last := Pair;
         end;

         if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Comma then
            declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
         else
            exit;
         end if;
      end loop;
      return First;
   end Parse_Rename_List;

   ---------------------
   -- Parse_Statement --
   ---------------------
   function Parse_Statement (Ctx : in out Parser_Context) return Statement_Access is
      Tok : Token := Get_Next_Token (Ctx.Lex_Ctx);
      Stmt : Statement_Access;
   begin
      while Tok.Kind = Token_Colon or else Tok.Kind = Token_Newline loop
         Tok := Get_Next_Token (Ctx.Lex_Ctx);
      end loop;

      if Tok.Kind = Token_EOF then
         return null;
      end if;

      case Tok.Kind is
         when Token_LET | Token_SET =>
            declare
               Var_Tok      : constant Token  := Get_Next_Token (Ctx.Lex_Ctx);
               Is_Arr       : Boolean         := False;
               A_Idx        : Expression_Access := null;
               A_Idx_List   : Expression_List := null;
               A_Is_Slice   : Boolean         := False;
            begin
               if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Left_Paren or else
                  Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Left_Brace then
                  Is_Arr := True;
                  declare
                     LP      : constant Token      := Get_Next_Token (Ctx.Lex_Ctx);
                     Closing : constant Token_Kind :=
                        (if LP.Kind = Token_Left_Paren then Token_Right_Paren else Token_Right_Brace);
                     First   : constant Expression_Access := Parse_Expression (Ctx);
                     Peek    : constant Token_Kind := Peek_Next_Token (Ctx.Lex_Ctx).Kind;
                  begin
                     if Peek = Token_Colon then
                        --  Range form: (lo : hi) — assign to every element lo..hi
                        declare
                           Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); -- consume ':'
                           Second  : constant Expression_Access := Parse_Expression (Ctx);
                           Lo_Node : constant Expression_List :=
                              new Expression_List_Node'(Expr => First,  Next => null, others => <>);
                           Hi_Node : constant Expression_List :=
                              new Expression_List_Node'(Expr => Second, Next => null, others => <>);
                        begin
                           Lo_Node.Next := Hi_Node;
                           A_Idx_List   := Lo_Node;
                           A_Is_Slice   := True;
                        end;
                     elsif Peek = Token_Comma then
                        --  List form: (i, j, k, ...) — assign to each listed index
                        declare
                           Head : constant Expression_List :=
                              new Expression_List_Node'(Expr => First, Next => null, others => <>);
                           Last : Expression_List := Head;
                        begin
                           while Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Comma loop
                              declare
                                 Discard  : constant Token := Get_Next_Token (Ctx.Lex_Ctx); -- ','
                                 New_Node : constant Expression_List :=
                                    new Expression_List_Node'(Expr => Parse_Expression (Ctx), Next => null, others => <>);
                              begin
                                 Last.Next := New_Node;
                                 Last      := New_Node;
                              end;
                           end loop;
                           A_Idx_List := Head;
                        end;
                     else
                        --  Single-index form (existing behaviour)
                        A_Idx := First;
                     end if;
                     if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Closing then
                        Put_Line_Error ("Error: Expected matching closing parenthesis/brace in array assignment");
                     end if;
                  end;
               end if;

               if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Equal then
                  Put_Line_Error ("Error: Expected '=' after variable name """ &
                     Var_Tok.Text (1 .. Var_Tok.Length) & """ in " &
                     (if Tok.Kind = Token_LET then "LET" else "SET") & " statement");
               end if;

               Stmt := new Statement ((if Tok.Kind = Token_LET then Stmt_LET else Stmt_SET));
               Stmt.Var_Len      := Var_Tok.Length;
               Stmt.Var_Name (1 .. Var_Tok.Length) := Var_Tok.Text (1 .. Var_Tok.Length);
               Stmt.Is_Array     := Is_Arr;
               Stmt.Arr_Idx      := A_Idx;
               Stmt.Arr_Idx_List := A_Idx_List;
               Stmt.Arr_Is_Slice := A_Is_Slice;
               Stmt.Expr         := Parse_Expression (Ctx);
            end;

         when Token_REPEAT =>
            --  If the next token is a newline (or EOF/colon) it is a REPEAT/UNTIL
            --  loop block; otherwise it is REPEAT n (data-step record count).
            if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Newline or else
               Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_EOF or else
               Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Colon
            then
               Stmt := new Statement (Stmt_LOOP_REPEAT);
               Stmt.Repeat_Body := Parse_Block (Ctx, Token_UNTIL);
               Stmt.Until_Cond  := Parse_Expression (Ctx);
            else
               declare
                  Val_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
               begin
                  Stmt := new Statement (Stmt_REPEAT);
                  Stmt.Count := Natural'Value (Val_Tok.Text (1 .. Val_Tok.Length));
               end;
            end if;

         when Token_PRINT =>
            Stmt := new Statement (Stmt_PRINT);
            Stmt.Print_Args := null;
            declare
               Last_Arg : Expression_List := null;
               Expr : Expression_Access;
            begin
               loop
                  declare
                     P : constant Token := Peek_Next_Token (Ctx.Lex_Ctx);
                  begin
                     exit when P.Kind = Token_Newline or else P.Kind = Token_Colon or else P.Kind = Token_EOF
                               or else P.Kind = Token_ELSE or else P.Kind = Token_ELSEIF;
                     if P.Kind = Token_Comma or else P.Kind = Token_Semicolon then
                        declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
                     end if;
                  end;

                  Expr := Parse_Expression (Ctx);
                  exit when Expr = null;

                  declare
                     New_Arg : constant Expression_List := new Expression_List_Node'(Expr => Expr, Next => null, others => <>);
                  begin
                     if Stmt.Print_Args = null then Stmt.Print_Args := New_Arg;
                     else Last_Arg.Next := New_Arg; end if;
                     Last_Arg := New_Arg;
                  end;
               end loop;
            end;

         when Token_USE | Token_SAVE | Token_SUBMIT | Token_SYSTEM | Token_FPATH =>
            declare
               File_Tok : Token;
               Peeked   : Token;
            begin
               if Tok.Kind = Token_USE then Stmt := new Statement (Stmt_USE);
               elsif Tok.Kind = Token_SAVE then Stmt := new Statement (Stmt_SAVE);
               elsif Tok.Kind = Token_SUBMIT then Stmt := new Statement (Stmt_SUBMIT);
               elsif Tok.Kind = Token_SYSTEM then Stmt := new Statement (Stmt_SYSTEM);
               else Stmt := new Statement (Stmt_FPATH); end if;
               
               Peeked := Peek_Next_Token (Ctx.Lex_Ctx);
               
               if Peeked.Kind = Token_Newline or else Peeked.Kind = Token_Semicolon or else Peeked.Kind = Token_EOF then
                  Stmt.File_Len := 0;
               elsif Peeked.Kind = Token_Slash then
                  -- Starts with a flag, so no file path
                  Stmt.File_Len := 0;
               else
                  File_Tok := Get_Next_Token (Ctx.Lex_Ctx);
                  
                  if Tok.Kind = Token_USE and then File_Tok.Kind = Token_MOCK then
                     Stmt.Is_Mock := True;
                     Stmt.File_Len := 0;
                  else
                     Stmt.File_Len := File_Tok.Length;
                     Stmt.File_Path (1 .. File_Tok.Length) := File_Tok.Text (1 .. File_Tok.Length);
                     -- Rule: Unquoted filenames converted to uppercase
                     if File_Tok.Kind /= Token_String_Literal then
                        for I in 1 .. Stmt.File_Len loop
                           Stmt.File_Path (I) := To_Upper (Stmt.File_Path (I));
                        end loop;
                     end if;
                     --  Sheet selection: "filename[sheetname]" syntax.
                     --  If the filename ends with [...], extract the bracket
                     --  contents as the sheet name and remove them from the path.
                     if Stmt.File_Len > 2
                        and then Stmt.File_Path (Stmt.File_Len) = ']'
                     then
                        declare
                           Open_Pos : Natural := 0;
                        begin
                           for I in reverse 1 .. Stmt.File_Len - 1 loop
                              if Stmt.File_Path (I) = '[' then
                                 Open_Pos := I;
                                 exit;
                              end if;
                           end loop;
                           if Open_Pos > 0 then
                              declare
                                 SLen : constant Natural :=
                                    Natural'Min (Stmt.File_Len - Open_Pos - 1, 64);
                              begin
                                 Stmt.Sheet_Name (1 .. SLen) :=
                                    Stmt.File_Path (Open_Pos + 1 .. Open_Pos + SLen);
                                 Stmt.Sheet_Name_Len := SLen;
                                 Stmt.File_Len := Open_Pos - 1;
                              end;
                           end if;
                        end;
                     end if;
                  end if;
               end if;

               if Tok.Kind = Token_FPATH then
                  -- Handle FPATH flags
                  declare
                     procedure Process_Flag (T : Token) is
                        Flag_Name : constant String := To_Upper (T.Text (1 .. T.Length));
                     begin
                        if Flag_Name = "USE" or T.Kind = Token_USE then Stmt.Use_Flag := True;
                        elsif Flag_Name = "SAVE" or T.Kind = Token_SAVE then Stmt.Save_Flag := True;
                        elsif Flag_Name = "SUBMIT" or T.Kind = Token_SUBMIT then Stmt.Submit_Flag := True;
                        elsif Flag_Name = "OUTPUT" or T.Kind = Token_OUTPUT then Stmt.Output_Flag := True;
                        end if;
                     end Process_Flag;
                  begin
                     loop
                        Peeked := Peek_Next_Token (Ctx.Lex_Ctx);
                        if Peeked.Kind = Token_Slash then
                           declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                                   Flag_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                           begin
                              Process_Flag (Flag_Tok);
                           end;
                        elsif Peeked.Kind = Token_USE or else Peeked.Kind = Token_SAVE or else Peeked.Kind = Token_SUBMIT or else Peeked.Kind = Token_OUTPUT then
                           Process_Flag (Get_Next_Token (Ctx.Lex_Ctx));
                        else
                           exit;
                        end if;
                     end loop;
                  end;
               else
                  -- For USE/SAVE/SUBMIT/SYSTEM/OUTPUT, parse optional slashes/params
                  loop
                     Peeked := Peek_Next_Token (Ctx.Lex_Ctx);
                     if Peeked.Kind = Token_Slash then
                        declare 
                           Discard  : Token := Get_Next_Token (Ctx.Lex_Ctx); 
                           Flag_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                           Flag_Name : constant String := To_Upper (Flag_Tok.Text (1 .. Flag_Tok.Length));
                        begin
                           Peeked := Peek_Next_Token (Ctx.Lex_Ctx);
                           if Peeked.Kind = Token_Equal then
                              Discard := Get_Next_Token (Ctx.Lex_Ctx);
                              declare
                                 Val_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                                 Val_Str : constant String := To_Upper (Val_Tok.Text (1 .. Val_Tok.Length));
                              begin
                                 if Flag_Name = "FMT" then
                                    Stmt.Format_Specified := True;
                                    if Val_Str = "CSV" then Stmt.Fmt_Override := SData_Core.Config.CSV;
                                    elsif Val_Str = "ODF" or else Val_Str = "ODS" then Stmt.Fmt_Override := SData_Core.Config.ODF;
                                    elsif Val_Str = "OOXML" or else Val_Str = "XLSX" then Stmt.Fmt_Override := SData_Core.Config.OOXML;
                                    end if;
                                 elsif Flag_Name = "NSCAN" then
                                    Stmt.NSCAN_Val := Natural'Value (Val_Tok.Text (1 .. Val_Tok.Length));
                                 elsif Flag_Name = "SKIP" then
                                    Stmt.Skip_Val := Natural'Value (Val_Tok.Text (1 .. Val_Tok.Length));
                                 elsif Flag_Name = "MAXROWS" then
                                    Stmt.Maxrows_Val := Natural'Value (Val_Tok.Text (1 .. Val_Tok.Length));
                                 elsif Flag_Name = "HEADER" then
                                    Stmt.Header_Specified := True;
                                    Stmt.Header_Val := (Val_Str = "YES");
                                 elsif Flag_Name = "DLM" then
                                    Stmt.DLM_Len := Val_Tok.Length;
                                    Stmt.DLM_Path (1 .. Val_Tok.Length) := Val_Tok.Text (1 .. Val_Tok.Length);
                                 elsif Flag_Name = "CHARSET" then
                                    --  Consume multi-token charset names (e.g. UTF - 16 LE)
                                    declare
                                       Buf : String (1 .. 64) := (others => ' ');
                                       Len : Natural := Val_Tok.Length;
                                       P2  : Token;
                                    begin
                                       Buf (1 .. Len) := Val_Tok.Text (1 .. Len);
                                       P2 := Peek_Next_Token (Ctx.Lex_Ctx);
                                       if P2.Kind = Token_Minus then
                                          declare
                                             Discard2 : Token := Get_Next_Token (Ctx.Lex_Ctx);
                                             Mid_Tok  : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                                             M_Len    : constant Natural := Mid_Tok.Length;
                                          begin
                                             pragma Unreferenced (Discard2);
                                             Buf (Len + 1) := '-';
                                             Buf (Len + 2 .. Len + 1 + M_Len) :=
                                                Mid_Tok.Text (1 .. M_Len);
                                             Len := Len + 1 + M_Len;
                                             P2 := Peek_Next_Token (Ctx.Lex_Ctx);
                                             if P2.Kind = Token_Identifier then
                                                declare
                                                   S_Upper : constant String :=
                                                      To_Upper (P2.Text (1 .. P2.Length));
                                                begin
                                                   if S_Upper = "LE" or else S_Upper = "BE" then
                                                      declare
                                                         Suf_Tok : constant Token :=
                                                            Get_Next_Token (Ctx.Lex_Ctx);
                                                         S_Len   : constant Natural := Suf_Tok.Length;
                                                      begin
                                                         Buf (Len + 1 .. Len + S_Len) :=
                                                            Suf_Tok.Text (1 .. S_Len);
                                                         Len := Len + S_Len;
                                                      end;
                                                   end if;
                                                end;
                                             end if;
                                          end;
                                       end if;
                                       Stmt.Output_CHARSET_Val (1 .. Len) := Buf (1 .. Len);
                                       Stmt.Output_CHARSET_Len := Len;
                                    end;
                                 end if;
                              end;
                           end if;
                        end;
                     else exit; end if;
                  end loop;
               end if;
            end;

         when Token_KEEP | Token_DROP | Token_HOLD | Token_UNHOLD | Token_UNSET =>
            if Tok.Kind = Token_KEEP then Stmt := new Statement (Stmt_KEEP);
            elsif Tok.Kind = Token_DROP then Stmt := new Statement (Stmt_DROP);
            elsif Tok.Kind = Token_HOLD then Stmt := new Statement (Stmt_HOLD);
            elsif Tok.Kind = Token_UNSET then Stmt := new Statement (Stmt_UNSET);
            else Stmt := new Statement (Stmt_UNHOLD); end if;
            Stmt.Vars := Parse_Variable_List (Ctx);

         when Token_ARRAY | Token_DIM =>
            declare
               New_Kind : constant Statement_Kind := (if Tok.Kind = Token_ARRAY then Stmt_ARRAY else Stmt_DIM);
            begin
               Stmt := new Statement (New_Kind);
               if New_Kind = Stmt_ARRAY then
                  declare
                     P_Arr : constant Token := Peek_Next_Token (Ctx.Lex_Ctx);
                  begin
                     if P_Arr.Kind = Token_Newline or else P_Arr.Kind = Token_Semicolon
                        or else P_Arr.Kind = Token_EOF
                     then
                        null;  --  Bare ARRAY: list virtual arrays (Arr_Name_Len stays 0)
                     else
                        declare
                           Name_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                        begin
                           Stmt.Arr_Name_Len := Name_Tok.Length;
                           Stmt.Arr_Name (1 .. Name_Tok.Length) := Name_Tok.Text (1 .. Name_Tok.Length);
                           Stmt.Arr_Vars := Parse_Variable_List (Ctx);
                        end;
                     end if;
                  end;
               else
                  --  DIM arrayname (lower TO upper) [/TEMP]
                  declare
                     Name_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                  begin
                     Stmt.Arr_Name_Len := Name_Tok.Length;
                     Stmt.Arr_Name (1 .. Name_Tok.Length) := Name_Tok.Text (1 .. Name_Tok.Length);
                     declare
                        Tok_LP : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                     begin
                        if Tok_LP.Kind /= Token_Left_Paren then
                           Put_Line_Error ("Error: Expected '(' after DIM array name");
                           return null;
                        end if;

                        Stmt.Arr_Start_Expr := Parse_Expression (Ctx);
                        if Stmt.Arr_Start_Expr = null then
                           Put_Line_Error ("Error: Expected bound expression in DIM");
                           return null;
                        end if;

                        declare
                           Tok_Next : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                        begin
                           if Tok_Next.Kind = Token_TO then
                              Stmt.Arr_End_Expr := Parse_Expression (Ctx);
                              if Stmt.Arr_End_Expr = null then
                                 Put_Line_Error ("Error: Expected upper bound expression after TO");
                                 return null;
                              end if;
                              if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Right_Paren then
                                 Put_Line_Error ("Error: Expected ')' after DIM bounds");
                                 return null;
                              end if;
                           elsif Tok_Next.Kind = Token_Right_Paren then
                              Stmt.Arr_End_Expr := Stmt.Arr_Start_Expr;
                              Stmt.Arr_Start_Expr := new Expression (Expr_Numeric_Literal);
                              Stmt.Arr_Start_Expr.Value      := 1.0;
                              Stmt.Arr_Start_Expr.Is_Integer := True;
                              Stmt.Arr_Start_Expr.Int_Value  := 1;
                           else
                              Put_Line_Error ("Error: Expected TO or ')' in DIM bounds");
                              return null;
                           end if;
                        end;
                     end;

                     if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Slash then
                        declare
                           Discard_Slash : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                           Tok_Temp      : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                        begin
                           if Tok_Temp.Length >= 4 and then To_Upper (Tok_Temp.Text (1 .. 4)) = "TEMP" then
                              Stmt.Is_Temporary_Dim := True;
                           else
                              Put_Line_Error ("Error: Expected TEMP after / in DIM statement");
                              return null;
                           end if;
                        end;
                     end if;
                  end;
               end if;
            end;

         when Token_SELECT =>
            --  Three-way disambiguation (see package header for overview):
            --    1. SELECT /ALL  — slash token comes first; no expression.
            --    2. SELECT CASE / SELECT WHEN — no leading expression, or an
            --       expression immediately followed by CASE/WHEN/OTHERWISE.
            --    3. SELECT <expr> — expression not followed by CASE/WHEN;
            --       treated as a record-filter predicate.
            --
            --  For case 3 (SELECT_FILTER), tokens are collected into a plain
            --  string and parsed by SData_Core.Evaluator.Parse_Expression so
            --  that the same parser can be used standalone by data-vandal.
            --  Top-level commas in the token stream are converted to " AND " by
            --  Collect_Select_Filter_Text before the string is forwarded.
            declare
               First_Branch, Last_Branch : Case_Branch := null;
               Tok_Local : Token;
               Saved_Expr : Expression_Access := null;
               Is_Block : Boolean := False;
            begin
               if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Slash then
                  --  SELECT /ALL cancels any active record filter.
                  --  Consume the slash, then the ALL flag.
                  declare
                     Discard_Slash : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                     Flag_Tok      : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                  begin
                     if Flag_Tok.Kind /= Token_ALL then
                        Put_Line_Error ("Error: Expected ALL after SELECT /");
                     end if;
                  end;
                  Stmt := new Statement (Stmt_SELECT_FILTER);
                  --  Stmt.Expr remains null, signalling filter cancellation.
               else
               --  Collect the optional expression text (everything up to CASE /
               --  WHEN / OTHERWISE / EOL / EOF), converting top-level commas to
               --  AND conjunctions in the process.
               declare
                  Collected : constant String := Collect_Select_Filter_Text (Ctx);
               begin
                  if Collected'Length > 0 then
                     Saved_Expr :=
                        SData_Core.Evaluator.Parse_Expression (Collected);
                  end if;
               end;

               -- Skip separators to see if a CASE/WHEN/OTHERWISE follows.
               loop
                  Tok_Local := Peek_Next_Token (Ctx.Lex_Ctx);
                  exit when Tok_Local.Kind /= Token_Newline and then Tok_Local.Kind /= Token_Colon;
                  declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
               end loop;

               --  EOF here means SELECT appeared at end of input with no CASE following.
               --  In interactive mode the REPL catches this and waits for more input;
               --  in batch mode it means an unterminated block.
               if Tok_Local.Kind = Token_EOF then
                  raise Incomplete_Statement;
               end if;

               Is_Block := Tok_Local.Kind = Token_CASE or else
                           Tok_Local.Kind = Token_WHEN or else
                           Tok_Local.Kind = Token_OTHERWISE;

               if not Is_Block then
                  -- Record filter form: SELECT <expr>
                  -- (Top-level commas were already converted to AND conjunctions
                  --  by Collect_Select_Filter_Text, so no further comma loop is
                  --  needed here.)
                  Stmt := new Statement (Stmt_SELECT_FILTER);
                  Stmt.Expr := Saved_Expr;
               else
                  -- Control structure form: SELECT [<expr>] CASE...
                  Stmt := new Statement (Stmt_SELECT);
                  Stmt.Selector := Saved_Expr;
                  
                  loop
                     exit when Tok_Local.Kind = Token_END;
                     if Tok_Local.Kind = Token_EOF then
                        raise Incomplete_Statement;
                     end if;
                     
                     if Tok_Local.Kind = Token_CASE or else Tok_Local.Kind = Token_WHEN then
                        declare
                           Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                           Branch : constant Case_Branch := new Case_Branch_Node;
                           LP : constant Boolean := Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Left_Paren;
                        begin
                           if LP then
                              declare Discard_LP : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
                           end if;

                           declare
                              Last_Cond : Expression_List := null;
                           begin
                              loop
                                 declare
                                    E : constant Expression_Access := Parse_Expression (Ctx);
                                    L : constant Expression_List := new Expression_List_Node'(Expr => E, Next => null, others => <>);
                                 begin
                                    if Branch.Conditions = null then Branch.Conditions := L; else Last_Cond.Next := L; end if;
                                    Last_Cond := L;
                                 end;
                                 exit when Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Comma;
                                 declare Discard_Comma : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
                              end loop;
                           end;

                           if LP then
                              if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Right_Paren then
                                 Put_Line_Error ("Error: Expected ')' after CASE conditions");
                              end if;
                           end if;

                           Branch.Branch_Body := Parse_Select_Body (Ctx);
                           if First_Branch = null then First_Branch := Branch; else Last_Branch.Next := Branch; end if;
                           Last_Branch := Branch;
                        end;
                     elsif Tok_Local.Kind = Token_OTHERWISE then
                        declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                        begin Stmt.Otherwise_Part := Parse_Select_Body (Ctx); end;
                     else
                        -- Should not happen due to exit when Tok_Local.Kind not case/end
                        declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
                     end if;

                     -- Skip separators for next iteration.
                     loop
                        Tok_Local := Peek_Next_Token (Ctx.Lex_Ctx);
                        exit when Tok_Local.Kind /= Token_Newline and then Tok_Local.Kind /= Token_Colon;
                        declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
                     end loop;
                  end loop;

                  if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Token_END then
                     Put_Line_Error ("Error: Expected END after SELECT");
                  end if;
                  if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_SELECT then
                     declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
                  end if;
                  Stmt.Branches := First_Branch;
               end if;
               end if; --  end else (not Token_ALL)
            end;

         when Token_SORT | Token_BY =>
            Stmt := new Statement ((if Tok.Kind = Token_SORT then Stmt_SORT else Stmt_BY));
            Stmt.Sort_Vars := Parse_Variable_List (Ctx);

         when Token_DELETE =>
            declare
               Next_Tok : constant Token := Peek_Next_Token (Ctx.Lex_Ctx);
            begin
               if Next_Tok.Kind = Token_Numeric_Literal then
                  --  DELETE n[-m]: immediate program buffer deletion
                  declare
                     Num_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                     From_Num : Positive;
                  begin
                     From_Num := Positive (Float'Value (Num_Tok.Text (1 .. Num_Tok.Length)));
                     Stmt := new Statement (Stmt_PROGRAM_DELETE);
                     Stmt.Delete_From := From_Num;
                     Stmt.Delete_To   := From_Num;
                     declare
                        Maybe_Minus : constant Token := Peek_Next_Token (Ctx.Lex_Ctx);
                     begin
                        if Maybe_Minus.Kind = Token_Minus then
                           declare
                              Ignored  : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                              To_Tok   : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                              pragma Unreferenced (Ignored);
                           begin
                              Stmt.Delete_To := Positive (Float'Value (To_Tok.Text (1 .. To_Tok.Length)));
                           end;
                        end if;
                     end;
                  end;
               else
                  --  Bare DELETE: deferred, marks current record for deletion
                  Stmt := new Statement (Stmt_DELETE);
               end if;
            end;
         when Token_BREAK =>
            declare
               S : constant Statement_Access :=
                  new Statement (Stmt_BREAK);
            begin
               S.Expr := null;
               if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_WHEN then
                  declare
                     Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                     pragma Unreferenced (Discard);
                  begin
                     S.Expr := Parse_Expression (Ctx);
                  end;
               end if;
               Stmt := S;
            end;

         when Token_WRITE =>
            Stmt := new Statement (Stmt_WRITE);

         when Token_RSEED =>
            Stmt := new Statement (Stmt_RSEED);
            Stmt.Seed_Expr := Parse_Expression (Ctx);

         when Token_OUTPUT =>
            declare
               Tok_Next : constant Token := Peek_Next_Token (Ctx.Lex_Ctx);
            begin
               Stmt := new Statement (Stmt_OUTPUT);
               if Tok_Next.Kind = Token_String_Literal or else 
                  Tok_Next.Kind = Token_Identifier or else
                  (Tok_Next.Kind >= Token_USE and then Tok_Next.Kind <= Token_STEP) then
                  declare
                     File_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                  begin
                     Stmt.File_Len := File_Tok.Length;
                     Stmt.File_Path (1 .. File_Tok.Length) := File_Tok.Text (1 .. File_Tok.Length);
                     -- Rule: Unquoted filenames converted to uppercase
                     if File_Tok.Kind /= Token_String_Literal then
                        for I in 1 .. Stmt.File_Len loop
                           Stmt.File_Path (I) := To_Upper (Stmt.File_Path (I));
                        end loop;
                     end if;
                  end;
               else
                  Stmt.File_Len := 0; -- Cancel output redirection
               end if;
               -- Parse OUTPUT-specific flags: /FMT= and /CHARSET=
               loop
                  declare P : constant Token := Peek_Next_Token (Ctx.Lex_Ctx);
                  begin
                     if P.Kind = Token_Slash then
                        declare
                           Discard   : Token := Get_Next_Token (Ctx.Lex_Ctx);
                           Flag_Tok  : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                           Flag_Name : constant String := To_Upper (Flag_Tok.Text (1 .. Flag_Tok.Length));
                        begin
                           Discard := Peek_Next_Token (Ctx.Lex_Ctx);
                           if Discard.Kind = Token_Equal then
                              Discard := Get_Next_Token (Ctx.Lex_Ctx);
                              declare
                                 Val_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                                 Val_Str : constant String := To_Upper (Val_Tok.Text (1 .. Val_Tok.Length));
                              begin
                                 if Flag_Name = "FMT" then
                                    declare
                                       L : constant Natural := Natural'Min (Val_Str'Length, 8);
                                    begin
                                       Stmt.Output_FMT_Val (1 .. L) := Val_Str (Val_Str'First .. Val_Str'First + L - 1);
                                       Stmt.Output_FMT_Len := L;
                                    end;
                                 elsif Flag_Name = "CHARSET" then
                                    declare
                                       Buf : String (1 .. 64) := (others => ' ');
                                       Len : Natural := Val_Tok.Length;
                                       P2  : Token;
                                    begin
                                       Buf (1 .. Len) := Val_Tok.Text (1 .. Len);
                                       P2 := Peek_Next_Token (Ctx.Lex_Ctx);
                                       if P2.Kind = Token_Minus then
                                          declare
                                             Discard2 : Token := Get_Next_Token (Ctx.Lex_Ctx);
                                             Mid_Tok  : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                                             M_Len    : constant Natural := Mid_Tok.Length;
                                          begin
                                             pragma Unreferenced (Discard2);
                                             Buf (Len + 1) := '-';
                                             Buf (Len + 2 .. Len + 1 + M_Len) :=
                                                Mid_Tok.Text (1 .. M_Len);
                                             Len := Len + 1 + M_Len;
                                             P2 := Peek_Next_Token (Ctx.Lex_Ctx);
                                             if P2.Kind = Token_Identifier then
                                                declare
                                                   S_Upper : constant String :=
                                                      To_Upper (P2.Text (1 .. P2.Length));
                                                begin
                                                   if S_Upper = "LE" or else S_Upper = "BE" then
                                                      declare
                                                         Suf_Tok : constant Token :=
                                                            Get_Next_Token (Ctx.Lex_Ctx);
                                                         S_Len   : constant Natural := Suf_Tok.Length;
                                                      begin
                                                         Buf (Len + 1 .. Len + S_Len) :=
                                                            Suf_Tok.Text (1 .. S_Len);
                                                         Len := Len + S_Len;
                                                      end;
                                                   end if;
                                                end;
                                             end if;
                                          end;
                                       end if;
                                       Stmt.Output_CHARSET_Val (1 .. Len) := Buf (1 .. Len);
                                       Stmt.Output_CHARSET_Len := Len;
                                    end;
                                 end if;
                              end;
                           end if;
                        end;
                     else exit; end if;
                  end;
               end loop;
            end;

         when Token_ECHO =>
            declare
               Val_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
            begin
               Stmt := new Statement (Stmt_ECHO);
               if To_Upper(Val_Tok.Text(1..Val_Tok.Length)) = "ON" then
                  Stmt.Echo_State := True;
               else
                  Stmt.Echo_State := False;
               end if;
            end;

         when Token_DIGITS =>
            declare
               Val_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
            begin
               Stmt := new Statement (Stmt_DIGITS);
               Stmt.Digits_Count := Natural'Value (Val_Tok.Text (1 .. Val_Tok.Length));
            end;

         when Token_OPTIONS =>
            declare
               Peek : constant Token_Kind := Peek_Next_Token (Ctx.Lex_Ctx).Kind;
            begin
               Stmt := new Statement (Stmt_OPTIONS);
               if Peek /= Token_Newline and then Peek /= Token_EOF then
                  declare
                     Key_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                     Val_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                     Key_Str : constant String :=
                        To_Upper (Key_Tok.Text (1 .. Key_Tok.Length));
                     Val_Str : constant String := Val_Tok.Text (1 .. Val_Tok.Length);
                     K_Len   : constant Natural :=
                        Natural'Min (Key_Tok.Length, Max_Name_Len);
                     V_Len   : constant Natural :=
                        Natural'Min (Val_Tok.Length, 256);
                  begin
                     Stmt.Options_Key (1 .. K_Len) := Key_Str (Key_Str'First .. Key_Str'First + K_Len - 1);
                     Stmt.Options_Key_Len := K_Len;
                     Stmt.Options_Val (1 .. V_Len) := Val_Str (Val_Str'First .. Val_Str'First + V_Len - 1);
                     Stmt.Options_Val_Len := V_Len;
                  end;
               end if;
               --  Options_Key_Len = 0 means bare OPTIONS — display current values.
            end;

         when Token_RENAME =>
            Stmt := new Statement (Stmt_RENAME);
            Stmt.Rename_Pairs := Parse_Rename_List (Ctx);

         when Token_RUN =>
            Stmt := new Statement (Stmt_RUN);

         when Token_IF =>
            --  Delegate to Parse_If_Statement (IF token already consumed).
            Stmt := Parse_If_Statement (Ctx);

         when Token_WHILE =>
            Stmt := new Statement (Stmt_WHILE);
            Stmt.While_Cond := Parse_Expression (Ctx);
            Stmt.While_Body := Parse_Block (Ctx, Token_WEND);

         when Token_FOR =>
            Stmt := new Statement (Stmt_FOR);
            declare
               Var_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
               Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); -- '='
            begin
               Stmt.For_Var_Len := Var_Tok.Length;
               Stmt.For_Var (1 .. Var_Tok.Length) := Var_Tok.Text (1 .. Var_Tok.Length);
               Stmt.For_Start := Parse_Expression (Ctx);
               if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_TO then
                  declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
               end if;
               Stmt.For_End := Parse_Expression (Ctx);
               if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_STEP then
                  declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
                  Stmt.For_Step := Parse_Expression (Ctx);
               end if;
               Stmt.For_Body := Parse_Block (Ctx, Token_NEXT);
               
               --  Skip the optional variable name after NEXT.
               if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Identifier then
                  declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
               end if;
            end;

         when Token_DISPLAY =>
            Stmt := new Statement (Stmt_DISPLAY);
            Stmt.Vars := Parse_Variable_List (Ctx);

         when Token_VANDALIZE =>
            declare
               Src_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
            begin
               if Src_Tok.Kind /= Token_Identifier then
                  raise Script_Error with "VANDALIZE: expected source variable name.";
               end if;
               Stmt := new Statement (Stmt_VANDALIZE);
               Stmt.Vand_Source_Len := Src_Tok.Length;
               Stmt.Vand_Source_Name (1 .. Src_Tok.Length) :=
                  To_Upper (Src_Tok.Text (1 .. Src_Tok.Length));
               --  INTO <dest> is optional; omitting it implies in-place (dest = source).
               if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_INTO then
                  declare
                     Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                     Dst_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                     pragma Unreferenced (Discard);
                  begin
                     if Dst_Tok.Kind /= Token_Identifier then
                        raise Script_Error with "VANDALIZE: expected destination variable name.";
                     end if;
                     Stmt.Vand_Dest_Len := Dst_Tok.Length;
                     Stmt.Vand_Dest_Name (1 .. Dst_Tok.Length) :=
                        To_Upper (Dst_Tok.Text (1 .. Dst_Tok.Length));
                  end;
               else
                  Stmt.Vand_Dest_Len := Stmt.Vand_Source_Len;
                  Stmt.Vand_Dest_Name (1 .. Stmt.Vand_Source_Len) :=
                     Stmt.Vand_Source_Name (1 .. Stmt.Vand_Source_Len);
               end if;
               --  Parse slash options.
               loop
                  exit when Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Slash;
                  declare
                     Discard   : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                     Flag_Tok  : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                     Flag_Name : constant String :=
                        To_Upper (Flag_Tok.Text (1 .. Flag_Tok.Length));
                     pragma Unreferenced (Discard);
                  begin
                     if Flag_Name = "PERTURB" then
                        Stmt.Vand_Perturb := True;
                        if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Equal then
                           declare
                              Eq : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                              pragma Unreferenced (Eq);
                              V1 : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                           begin
                              if V1.Kind = Token_Numeric_Literal then
                                 Stmt.Vand_Pprob :=
                                    Float'Value (V1.Text (1 .. V1.Length));
                              elsif V1.Kind /= Token_Dot then
                                 raise Script_Error with
                                    "/PERTURB=: expected probability or '.'";
                              end if;
                           end;
                           if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Comma then
                              declare
                                 Cm : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                                 V2 : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                                 pragma Unreferenced (Cm);
                              begin
                                 if V2.Kind /= Token_Numeric_Literal then
                                    raise Script_Error with
                                       "/PERTURB=: expected sd-fraction after ','";
                                 end if;
                                 Stmt.Vand_SD_Frac :=
                                    Float'Value (V2.Text (1 .. V2.Length));
                              end;
                           end if;
                        end if;
                     elsif Flag_Name = "SHUFFLE" then
                        Stmt.Vand_Shuffle := True;
                        if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Equal then
                           declare
                              Eq : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                              V  : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                              pragma Unreferenced (Eq);
                           begin
                              if V.Kind /= Token_Numeric_Literal then
                                 raise Script_Error with "/SHUFFLE=: expected probability";
                              end if;
                              Stmt.Vand_Sprob := Float'Value (V.Text (1 .. V.Length));
                           end;
                        end if;
                     elsif Flag_Name = "MISS" then
                        Stmt.Vand_Miss := True;
                        if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Equal then
                           declare
                              Eq : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                              V  : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                              pragma Unreferenced (Eq);
                           begin
                              if V.Kind /= Token_Numeric_Literal then
                                 raise Script_Error with "/MISS=: expected probability";
                              end if;
                              Stmt.Vand_Mprob := Float'Value (V.Text (1 .. V.Length));
                           end;
                        end if;
                     elsif Flag_Name = "BY" then
                        if Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Equal then
                           raise Script_Error with "/BY: expected '='";
                        end if;
                        declare
                           Eq : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                           pragma Unreferenced (Eq);
                        begin
                           loop
                              declare
                                 VT : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                                 VN : Variable_List_Node;
                              begin
                                 if VT.Kind /= Token_Identifier then
                                    raise Script_Error with
                                       "/BY=: expected variable name";
                                 end if;
                                 VN.Var.Start_Len := VT.Length;
                                 VN.Var.Start_Name (1 .. VT.Length) :=
                                    To_Upper (VT.Text (1 .. VT.Length));
                                 VN.Var.Is_Range := False;
                                 VN.Next := Stmt.Vand_By_Vars;
                                 Stmt.Vand_By_Vars := new Variable_List_Node'(VN);
                              end;
                              exit when Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Comma;
                              declare
                                 Cm : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                                 pragma Unreferenced (Cm);
                              begin
                                 null;
                              end;
                           end loop;
                        end;
                     else
                        raise Script_Error with
                           "VANDALIZE: unknown option /" & Flag_Name;
                     end if;
                  end;
               end loop;
               if not Stmt.Vand_Perturb and then
                  not Stmt.Vand_Shuffle and then
                  not Stmt.Vand_Miss
               then
                  raise Script_Error with
                     "VANDALIZE: at least one of /PERTURB, /SHUFFLE, /MISS required.";
               end if;
            end;

         when Token_END | Token_QUIT | Token_NAMES | Token_LIST | Token_NEW | Token_HELP =>
            declare
               K : constant Statement_Kind := (if Tok.Kind = Token_END then Stmt_END
                                             elsif Tok.Kind = Token_QUIT then Stmt_QUIT
                                             elsif Tok.Kind = Token_NEW then Stmt_NEW
                                             elsif Tok.Kind = Token_HELP then Stmt_HELP
                                             elsif Tok.Kind = Token_LIST then Stmt_LIST
                                             else Stmt_NAMES);
            begin
               Stmt := new Statement (K);
               if K = Stmt_HELP then
                  declare
                     Next_T : constant Token := Peek_Next_Token (Ctx.Lex_Ctx);
                  begin
                     if Next_T.Kind = Token_Slash then
                        declare
                           Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                           Arg_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                        begin
                           if To_Upper(Arg_Tok.Text(1..Arg_Tok.Length)) = "ALL" then
                              Stmt.Var_Len := 4;
                              Stmt.Var_Name (1 .. 4) := "/ALL";
                           end if;
                        end;
                     elsif Next_T.Kind /= Token_Newline and then Next_T.Kind /= Token_Colon and then 
                           Next_T.Kind /= Token_Semicolon and then Next_T.Kind /= Token_EOF then
                        declare
                           Arg_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                        begin
                           Stmt.Var_Len := (if Arg_Tok.Length > Max_Name_Len then Max_Name_Len else Arg_Tok.Length);
                           Stmt.Var_Name (1 .. Stmt.Var_Len) := Arg_Tok.Text (1 .. Stmt.Var_Len);
                        end;
                     else
                        Stmt.Var_Len := 0;
                     end if;
                  end;
               end if;
            end;

         when Token_REM =>
            --  REM (or its "--" alias, already converted by the lexer) introduces
            --  a comment that runs to end-of-line.  The lexer consumes the rest of
            --  the token text as the REM token itself, so skipping it and parsing
            --  the next statement is all that is needed here.
            return Parse_Statement (Ctx);

         when others =>
            Put_Line_Error ("Error: Unrecognized command """ & Tok.Text (1 .. Tok.Length) &
               """ at line " & Tok.Line'Image & " — type HELP for a list of commands");
            return null;
      end case;

      if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Colon or else Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Newline then
         declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
      end if;

      return Stmt;
   end Parse_Statement;

   -------------------
   -- Parse_Program --
   -------------------
   function Parse_Program (Ctx : in out Parser_Context) return Statement_Access is
      First, Current, New_Stmt : Statement_Access := null;
   begin
      loop
         New_Stmt := Parse_Statement (Ctx);
         exit when New_Stmt = null;
         if First = null then First := New_Stmt; Current := New_Stmt;
         else Current.Next := New_Stmt; Current := New_Stmt; end if;
      end loop;
      return First;
   end Parse_Program;

end SData.Parser;