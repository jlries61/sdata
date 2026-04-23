--  Package SData.Interpreter implements the Command Execution Engine.
--  It takes a linked list of AST statements (the "program") and executes them
--  in order, managing data loading, the implicit record loop (Data Step), 
--  and data export.

with SData.AST; use SData.AST;

package SData.Interpreter is

   --  Executes the provided AST program.
   procedure Execute (Prog : Statement_Access);

   --  Adds a statement to the global active program (for REPL deferred execution).
   --  Source is the source text of the statement (for LIST display).
   procedure Add_To_Active_Program (Stmt : Statement_Access; Source : String := "");

   --  Returns the number of entries in the program buffer.
   function Program_Buffer_Length return Natural;

   --  Clears the global active program.
   procedure Clear_Active_Program;

   --  Executes the global active program.
   procedure Run_Active_Program;

   --  Returns True if a statement of the given kind executes immediately in
   --  the REPL rather than being queued for the next RUN (data step).
   --  Add new statement kinds here when they should not be deferred.
   function Is_Immediate (Kind : Statement_Kind) return Boolean;

   procedure Set_Interactive (Val : Boolean);

end SData.Interpreter;
