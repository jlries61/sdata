--  Package SData.Interpreter implements the Command Execution Engine.
--  It takes a linked list of AST statements (the "program") and executes them
--  in order, managing data loading, the implicit record loop (Data Step), 
--  and data export.

with SData.AST; use SData.AST;

package SData.Interpreter is

   --  Raised when a statement fails during execution.  The exception message
   --  contains the formatted, user-readable error text.  Main catches this
   --  silently (the message has already been printed by the interpreter).
   Script_Error : exception;

   --  Executes the provided AST program.
   procedure Execute (Prog : Statement_Access);

   --  Adds a statement to the global active program (for REPL deferred execution).
   procedure Add_To_Active_Program (Stmt : Statement_Access);

   --  Clears the global active program.
   procedure Clear_Active_Program;

   --  Executes the global active program.
   procedure Run_Active_Program;

   procedure Set_Interactive (Val : Boolean);

end SData.Interpreter;
