with Ada.Text_IO; use Ada.Text_IO;

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
   function Parse_Statement (Ctx : in out Parser_Context) return Statement_Access;
   function Parse_Rename_List (Ctx : in out Parser_Context) return Rename_List;

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
         when Token_Minus =>
            declare
               Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
            begin
               Node := new Expression (Expr_Unary_Op);
               Node.UOp := Op_Neg;
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
                     if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Left_Paren then
                        Node := new Expression (Expr_Function_Call);
                        Node.Func_Len := Actual_Tok.Length;
                        Node.Func_Name (1 .. Actual_Tok.Length) := Actual_Tok.Text (1 .. Actual_Tok.Length);
                        declare
                           Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); -- Consume '('
                           Last_Arg : Expression_List := null;
                        begin
                           if Peek_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Right_Paren then
                              loop
                                 declare
                                    Arg_Expr : constant Expression_Access := Parse_Expression (Ctx);
                                    New_Arg  : constant Expression_List := new Expression_List_Node'(Expr => Arg_Expr, Next => null);
                                 begin
                                    if Node.Arguments = null then
                                       Node.Arguments := New_Arg;
                                    else
                                       Last_Arg.Next := New_Arg;
                                    end if;
                                    Last_Arg := New_Arg;
                                 end;

                                 if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Comma then
                                    declare
                                       Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
                                    begin null; end;
                                 else
                                    exit;
                                 end if;
                              end loop;
                           end if;

                           if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Right_Paren then
                              Put_Line ("Error: Expected ')'");
                           end if;
                        end;
                        return Node;
                     elsif Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Left_Brace then
                        Node := new Expression (Expr_Array_Access);
                        Node.Arr_Len := Actual_Tok.Length;
                        Node.Arr_Name (1 .. Actual_Tok.Length) := Actual_Tok.Text (1 .. Actual_Tok.Length);
                        declare
                           Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); -- Consume '{'
                        begin
                           Node.Arr_Idx := Parse_Expression (Ctx);
                           if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Right_Brace then
                              Put_Line ("Error: Expected '}' after array index");
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
               if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_Left_Brace then
                  Is_Arr := True;
                  declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin
                     A_Idx := Parse_Expression (Ctx);
                     if Get_Next_Token (Ctx.Lex_Ctx).Kind /= Token_Right_Brace then
                        Put_Line ("Error: Expected '}' in array assignment");
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
            declare
               Val_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
            begin
               Stmt := new Statement (Stmt_REPEAT);
               Stmt.Count := Natural'Value (Val_Tok.Text (1 .. Val_Tok.Length));
            end;

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
                     if P.Kind = Token_Comma or else P.Kind = Token_Semicolon then
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

         when Token_USE | Token_SAVE | Token_SUBMIT =>
            declare
               File_Tok : constant Token := Get_Next_Token (Ctx.Lex_Ctx);
            begin
               if Tok.Kind = Token_USE then Stmt := new Statement (Stmt_USE);
               elsif Tok.Kind = Token_SAVE then Stmt := new Statement (Stmt_SAVE);
               else Stmt := new Statement (Stmt_SUBMIT); end if;
               Stmt.File_Len := File_Tok.Length;
               Stmt.File_Path (1 .. File_Tok.Length) := File_Tok.Text (1 .. File_Tok.Length);
               loop
                  declare Peeked : constant Token := Peek_Next_Token (Ctx.Lex_Ctx);
                  begin
                     if Peeked.Kind = Token_Slash or else Peeked.Kind = Token_String_Literal then
                        declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
                     else exit; end if;
                  end;
               end loop;
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
                  
                  --  In the new model, the dimension is implicit based on the length of the variable list.
                  --  We initialize it to a placeholder; the interpreter will determine the true size.
                  Stmt.Arr_Dim := 1; 
                  
                  Stmt.Arr_Vars := Parse_Variable_List (Ctx);
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

         when Token_DELETE | Token_OUTPUT =>
            Stmt := new Statement ((if Tok.Kind = Token_DELETE then Stmt_DELETE else Stmt_OUTPUT));

         when Token_RENAME =>
            Stmt := new Statement (Stmt_RENAME);
            Stmt.Rename_Pairs := Parse_Rename_List (Ctx);

         when Token_RUN =>
            Stmt := new Statement (Stmt_RUN);

         when Token_IF =>
            Stmt := new Statement (Stmt_IF);
            Stmt.Condition := Parse_Expression (Ctx);
            if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_THEN then
               declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
            end if;
            Stmt.Then_Branch := Parse_Statement (Ctx);
            if Peek_Next_Token (Ctx.Lex_Ctx).Kind = Token_ELSE then
               declare Discard : constant Token := Get_Next_Token (Ctx.Lex_Ctx); begin null; end;
               Stmt.Else_Branch := Parse_Statement (Ctx);
            end if;

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

         when Token_END | Token_QUIT | Token_NAMES | Token_NEW =>
            Stmt := new Statement ((if Tok.Kind = Token_END then Stmt_END 
                                     elsif Tok.Kind = Token_QUIT then Stmt_QUIT 
                                     elsif Tok.Kind = Token_NEW then Stmt_NEW
                                     else Stmt_NAMES));

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
