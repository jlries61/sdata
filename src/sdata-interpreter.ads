--  Package SData.Interpreter implements the Command Execution Engine.
--  It takes a linked list of AST statements (the "program") and executes them
--  in order, managing data loading, the implicit record loop (Data Step), 
--  and data export.

with SData.AST; use SData.AST;

package SData.Interpreter is

   --  Executes the provided AST program.
   --  This process involves multiple passes:
   --  1.  Declarative load pass (USE).
   --  2.  Data step iteration (implicit loop over all records in the Data Table).
   --  3.  Declarative save pass (SAVE).
   procedure Execute (Prog : Statement_Access);

end SData.Interpreter;
