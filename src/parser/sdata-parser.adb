with Ada.Text_IO; use Ada.Text_IO;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with SData.Config;
with SData.Variables; use SData.Variables;

package body SData.Parser is

   ------------------
   -- Initialize --
   ------------------
   procedure Initialize (Ctx : in out Parser_Context; Source : String) is
   begin
      Initialize (Ctx.Lex_Ctx, Source);
   end Initialize;

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
               Peek = Token_END  or else Peek = Token_EOF
            then
               declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
               Term_Kind := Peek;
               return First;
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
      if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_THEN then
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
            Expr : constant Expression_Access := Parse_Expression (Ctx);
         begin
            New_Node := new Expression_List_Node'(Expr => Expr, Next => null);
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
            exit;
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
                     Node.Value := Float'Value (Actual_Tok.Text (1 .. Actual_Tok.Length));
                     return Node;

                  when Token_String_Literal =>
                     Node := new Expression (Expr_String_Literal);
                     Node.Str_Length := Actual_Tok.Length;
                     Node.Str_Value (1 .. Actual_Tok.Length) := Actual_Tok.Text (1 .. Actual_Tok.Length);
                     return Node;

                  when Token_Identifier =>
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

                           if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Closing then
                              Put_Line ("Error: Expected matching closing bracket/paren");
                           end if;
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
                        Put_Line ("Error: Expected ')'");
                     end if;
                     return Node;

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
         when others => raise Program_Error;
      end case;
   end To_Binary_Op;

   ------------------------
   -- Parse_Expression_1 --
   ------------------------
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
                  Put_Line ("Error: Expected expression after operator");
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
            
            if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Minus or else Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Colon then
               declare
                  Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                  End_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
               begin
                  if End_Tok.Kind /= Token_Identifier then
                     Put_Line ("Error: Expected identifier after '" & Discard.Kind'Image & "' in range");
                  else
                     Node.Var.Is_Range := True;
                     Node.Var.End_Name (1 .. End_Tok.Length) := End_Tok.Text (1 .. End_Tok.Length);
                     Node.Var.End_Len := End_Tok.Length;
                  end if;
               end;
            end if;
            
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
               Put_Line ("Error: Expected '=' in RENAME list");
            end if;
            
            Tok := Get_Next_Token (Ctx.Lex_Ctx);
            if Tok.Kind /= Token_Identifier then
               Put_Line ("Error: Expected identifier after '=' in RENAME list");
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
               Var_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
               Is_Arr  : Boolean := False;
               A_Idx   : Expression_Access := null;
            begin
               if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Left_Paren or else 
                  Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Left_Brace then
                  Is_Arr := True;
                  declare 
                     LP : constant Token := Get_Next_Token (Ctx.Lex_Ctx); 
                     Closing : constant Token_Kind := (if LP.Kind = Token_Left_Paren then Token_Right_Paren else Token_Right_Brace);
                  begin
                     A_Idx := Parse_Expression (Ctx);
                     if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Closing then
                        Put_Line ("Error: Expected matching closing parenthesis/brace in array assignment");
                     end if;
                  end;
               end if;
               
               if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Equal then
                  Put_Line ("Error: Expected '=' in assignment");
               end if;

               Stmt := new Statement ((if Tok.Kind = Token_LET then Stmt_LET else Stmt_SET));
               Stmt.Var_Len := Var_Tok.Length;
               Stmt.Var_Name (1 .. Var_Tok.Length) := Var_Tok.Text (1 .. Var_Tok.Length);
               Stmt.Is_Array := Is_Arr;
               Stmt.Arr_Idx := A_Idx;
               Stmt.Expr := Parse_Expression (Ctx);
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
                     exit when P.Kind = Token_Newline or else P.Kind = Token_Colon or else P.Kind = Token_EOF;
                     if P.Kind = Token_Comma then
                        declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
                     end if;
                  end;

                  Expr := Parse_Expression (Ctx);
                  exit when Expr = null;

                  declare
                     New_Arg : constant Expression_List := new Expression_List_Node'(Expr => Expr, Next => null);
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
                                    if Val_Str = "CSV" then Stmt.Fmt_Override := SData.Config.CSV;
                                    elsif Val_Str = "ODF" or else Val_Str = "ODS" then Stmt.Fmt_Override := SData.Config.ODF;
                                    elsif Val_Str = "OOXML" or else Val_Str = "XLSX" then Stmt.Fmt_Override := SData.Config.OOXML;
                                    end if;
                                 elsif Flag_Name = "NSCAN" then
                                    Stmt.NSCAN_Val := Natural'Value (Val_Tok.Text (1 .. Val_Tok.Length));
                                 elsif Flag_Name = "HEADER" then
                                    Stmt.Header_Specified := True;
                                    Stmt.Header_Val := (Val_Str = "YES");
                                 elsif Flag_Name = "DLM" then
                                    Stmt.DLM_Len := Val_Tok.Length;
                                    Stmt.DLM_Path (1 .. Val_Tok.Length) := Val_Tok.Text (1 .. Val_Tok.Length);
                                 end if;
                              end;
                           end if;
                        end;
                     else exit; end if;
                  end loop;
               end if;
            end;

         when Token_KEEP | Token_DROP | Token_HOLD | Token_UNHOLD =>
            if Tok.Kind = Token_KEEP then Stmt := new Statement (Stmt_KEEP);
            elsif Tok.Kind = Token_DROP then Stmt := new Statement (Stmt_DROP);
            elsif Tok.Kind = Token_HOLD then Stmt := new Statement (Stmt_HOLD);
            else Stmt := new Statement (Stmt_UNHOLD); end if;
            Stmt.Vars := Parse_Variable_List (Ctx);

         when Token_ARRAY | Token_DIM =>
            declare
               New_Kind : constant Statement_Kind := (if Tok.Kind = Token_ARRAY then Stmt_ARRAY else Stmt_DIM);
            begin
               Stmt := new Statement (New_Kind);
               declare
                  Name_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
               begin
                  Stmt.Arr_Name_Len := Name_Tok.Length;
                  Stmt.Arr_Name (1 .. Name_Tok.Length) := Name_Tok.Text (1 .. Name_Tok.Length);
                  
                  if New_Kind = Stmt_ARRAY then
                     -- ARRAY arrayname variable_list
                     Stmt.Arr_Vars := Parse_Variable_List (Ctx);
                  else
                     -- DIM arrayname (lower TO upper) [/TEMP]
                     declare
                        Tok_LP : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                     begin
                        if Tok_LP.Kind /= Token_Left_Paren then
                           Put_Line ("Error: Expected '(' after DIM array name");
                           return null;
                        end if;
                        
                        declare
                           Tok_Start : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                        begin
                           if Tok_Start.Kind /= Token_Numeric_Literal then
                              Put_Line ("Error: Expected starting index for DIM array");
                              return null;
                           end if;
                           Stmt.Arr_Start_Idx := Integer'Value (Tok_Start.Text (1 .. Tok_Start.Length));
                           
                           declare
                              Tok_Next : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                           begin
                              if Tok_Next.Kind = Token_TO then
                                 declare
                                    Tok_End : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                                 begin
                                    if Tok_End.Kind /= Token_Numeric_Literal then
                                       Put_Line ("Error: Expected ending index for DIM array after TO");
                                       return null;
                                    end if;
                                    Stmt.Arr_End_Idx := Integer'Value (Tok_End.Text (1 .. Tok_End.Length));
                                    if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Right_Paren then
                                       Put_Line ("Error: Expected ')' after DIM bounds");
                                       return null;
                                    end if;
                                 end;
                              elsif Tok_Next.Kind = Token_Right_Paren then
                                 -- Simple dimension: DIM X(10) means 1 to 10
                                 Stmt.Arr_End_Idx := Stmt.Arr_Start_Idx;
                                 Stmt.Arr_Start_Idx := 1;
                              else
                                 Put_Line ("Error: Expected TO or ')' in DIM bounds");
                                 return null;
                              end if;
                           end;
                        end;
                     end;
                     
                     -- Check for /TEMP
                     if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Slash then
                        declare
                           Discard_Slash : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                           Tok_Temp : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                        begin
                           if Tok_Temp.Length >= 4 and then To_Upper (Tok_Temp.Text (1 .. 4)) = "TEMP" then
                              Stmt.Is_Temporary_Dim := True;
                           else
                              Put_Line ("Error: Expected TEMP after / in DIM statement");
                              return null;
                           end if;
                        end;
                     end if;
                  end if;
               end;
            end;

         when Token_SELECT =>
            declare
               First_Branch, Last_Branch : Case_Branch := null;
               Tok_Local : Token;
            begin
               Stmt := new Statement (Stmt_SELECT);
               if Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_CASE and then
                  Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_WHEN and then
                  Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_OTHERWISE then
                  Stmt.Selector := Parse_Expression (Ctx);
               end if;
               
               loop
                  Tok_Local := Peek_Next_Token (Ctx.Lex_Ctx);
                  exit when Tok_Local.Kind = Token_END or else Tok_Local.Kind = Token_EOF;
                  
                  if Tok_Local.Kind = Token_CASE or else Tok_Local.Kind = Token_WHEN then
                     declare
                        Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                        Branch : constant Case_Branch := new Case_Branch_Node;
                     begin
                        if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Left_Paren then
                           declare
                              Discard_LP : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                              Last_Cond : Expression_List := null;
                           begin
                              loop
                                 declare
                                    E : constant Expression_Access := Parse_Expression (Ctx);
                                    L : constant Expression_List := new Expression_List_Node'(Expr => E, Next => null);
                                 begin
                                    if Branch.Conditions = null then Branch.Conditions := L; else Last_Cond.Next := L; end if;
                                    Last_Cond := L;
                                 end;
                                 exit when Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Comma;
                                 declare Discard_Comma : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
                              end loop;
                              if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Right_Paren then
                                 Put_Line ("Error: Expected ')' after CASE conditions");
                              end if;
                           end;
                        end if;
                        Branch.Branch_Body := Parse_Statement (Ctx);
                        if First_Branch = null then First_Branch := Branch; else Last_Branch.Next := Branch; end if;
                        Last_Branch := Branch;
                     end;
                  elsif Tok_Local.Kind = Token_OTHERWISE then
                     declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                     begin Stmt.Otherwise_Part := Parse_Statement (Ctx); end;
                  else
                     declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
                  end if;
               end loop;
               if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Token_END then
                  Put_Line ("Error: Expected END after SELECT");
               end if;
               Stmt.Branches := First_Branch;
            end;

         when Token_SORT | Token_BY =>
            Stmt := new Statement ((if Tok.Kind = Token_SORT then Stmt_SORT else Stmt_BY));
            Stmt.Sort_Vars := Parse_Variable_List (Ctx);

         when Token_DELETE | Token_WRITE =>
            Stmt := new Statement ((if Tok.Kind = Token_DELETE then Stmt_DELETE else Stmt_WRITE));

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
               -- Skip any options for now
               loop
                  declare P : constant Token := Peek_Next_Token (Ctx.Lex_Ctx);
                  begin
                     if P.Kind = Token_Slash then
                        declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
                        declare Discard_Opt : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
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
            end;

         when Token_END | Token_QUIT | Token_NAMES | Token_NEW | Token_HELP =>
            declare
               K : constant Statement_Kind := (if Tok.Kind = Token_END then Stmt_END 
                                             elsif Tok.Kind = Token_QUIT then Stmt_QUIT 
                                             elsif Tok.Kind = Token_NEW then Stmt_NEW
                                             elsif Tok.Kind = Token_HELP then Stmt_HELP
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
                     elsif Next_T.Kind = Token_Identifier or else
                        Next_T.Kind = Token_LET or else
                        Next_T.Kind = Token_SET or else
                        Next_T.Kind = Token_ARRAY or else
                        Next_T.Kind = Token_DIM or else
                        Next_T.Kind = Token_USE or else
                        Next_T.Kind = Token_SAVE or else
                        Next_T.Kind = Token_RUN or else
                        Next_T.Kind = Token_IF or else
                        Next_T.Kind = Token_BY or else
                        Next_T.Kind = Token_SORT or else
                        Next_T.Kind = Token_HOLD or else
                        Next_T.Kind = Token_UNHOLD or else
                        Next_T.Kind = Token_REPEAT or else
                        Next_T.Kind = Token_NAMES or else
                        Next_T.Kind = Token_KEEP or else
                        Next_T.Kind = Token_DROP or else
                        Next_T.Kind = Token_RENAME or else
                        Next_T.Kind = Token_SELECT or else
                        Next_T.Kind = Token_DELETE or else
                        Next_T.Kind = Token_OUTPUT or else
                        Next_T.Kind = Token_FOR or else
                        Next_T.Kind = Token_WHILE or else
                        Next_T.Kind = Token_DIGITS or else
                        Next_T.Kind = Token_SUBMIT or else
                        Next_T.Kind = Token_NEW or else
                        Next_T.Kind = Token_RSEED or else
                        Next_T.Kind = Token_FPATH or else
                        Next_T.Kind = Token_ECHO or else
                        Next_T.Kind = Token_SYSTEM or else
                        Next_T.Kind = Token_ELSEIF or else
                        Next_T.Kind = Token_NOT or else
                        Next_T.Kind = Token_WRITE or else
                        Next_T.Kind = Token_QUIT then
                        declare
                           Arg_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                        begin
                           Stmt.Var_Len := Arg_Tok.Length;
                           Stmt.Var_Name (1 .. Arg_Tok.Length) := Arg_Tok.Text (1 .. Arg_Tok.Length);
                        end;
                     else
                        Stmt.Var_Len := 0;
                     end if;
                  end;
               end if;
            end;

         when Token_REM =>
            return Parse_Statement (Ctx);

         when others =>
            Put_Line ("Error: Unrecognized command: " & Tok.Kind'Image & " at line " & Tok.Line'Image);
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
