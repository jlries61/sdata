package SData.AST is

   type Expression_Kind is (
      Expr_Numeric_Literal,
      Expr_String_Literal,
      Expr_Variable,
      Expr_Binary_Op,
      Expr_Unary_Op,
      Expr_Function_Call
   );

   type Binary_Op is (Op_Add, Op_Sub, Op_Mul, Op_Div, Op_Pow, Op_Eq, Op_Ne, Op_Lt, Op_Le, Op_Gt, Op_Ge);
   type Unary_Op is (Op_Neg);

   type Expression;
   type Expression_Access is access Expression;

   type Expression (Kind : Expression_Kind) is record
      case Kind is
         when Expr_Numeric_Literal =>
            Value : Float;
         when Expr_String_Literal =>
            Str_Value : String (1 .. 1024);
            Str_Length : Natural;
         when Expr_Variable =>
            Var_Name : String (1 .. 32);
            Var_Len  : Natural;
         when Expr_Binary_Op =>
            Left  : Expression_Access;
            Right : Expression_Access;
            Op    : Binary_Op;
         when Expr_Unary_Op =>
            Operand : Expression_Access;
            UOp     : Unary_Op;
         when Expr_Function_Call =>
            Func_Name : String (1 .. 32);
            Func_Len  : Natural;
            -- Arguments could be a list, simplified for now
      end case;
   end record;

   type Variable_Range is record
      Start_Name : String (1 .. 32);
      Start_Len  : Natural;
      End_Name   : String (1 .. 32);
      End_Len    : Natural;
      Is_Range   : Boolean := False;
   end record;

   type Variable_List_Node;
   type Variable_List is access Variable_List_Node;
   type Variable_List_Node is record
      Var  : Variable_Range;
      Next : Variable_List;
   end record;

   type Statement_Kind is (
      Stmt_LET,
      Stmt_PRINT,
      Stmt_USE,
      Stmt_SAVE,
      Stmt_KEEP,
      Stmt_DROP,
      Stmt_IF,
      Stmt_FOR,
      Stmt_WHILE,
      Stmt_REPEAT,
      Stmt_END
   );

   type Statement;
   type Statement_Access is access Statement;

   type Statement (Kind : Statement_Kind) is record
      Next : Statement_Access;
      case Kind is
         when Stmt_LET =>
            Var_Name : String (1 .. 32);
            Var_Len  : Natural;
            Expr     : Expression_Access;
         when Stmt_PRINT =>
            Print_Expr : Expression_Access;
         when Stmt_USE | Stmt_SAVE =>
            File_Path : String (1 .. 1024);
            File_Len  : Natural;
         when Stmt_KEEP | Stmt_DROP =>
            Vars : Variable_List;
         when others =>
            null;
      end case;
   end record;

end SData.AST;
