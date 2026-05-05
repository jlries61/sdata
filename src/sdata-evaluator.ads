--  Package SData.Evaluator implements the Expression Evaluation Engine.
--  It takes AST expression nodes and returns computed 'Value' records,
--  interacting with SData.Variables for symbol lookups.

with SData.AST;    use SData.AST;
with SData.Values; use SData.Values;

package SData.Evaluator is

   --  Computes the value of an AST expression.
   function Evaluate (Expr : Expression_Access) return Value;

   --  Converts any numeric value kind to Float for calculation.
   function Convert_To_Float (V : Value) return Float;
   
   -- Returns the expected kind of value based on name suffix
   function Get_Expected_Kind (Name : String) return Value_Kind;

   --  Returns True for functions whose first argument is passed as a variable
   --  *name* rather than the variable's evaluated value (LAG, NEXT, OBS and
   --  their character variants).  Used by the parser, evaluator, and any code
   --  that walks the expression AST.
   function Is_Identifier_Ref_Function (N : String) return Boolean;

   --  Set_Group_Boundary — update the BOG/EOG indicators before each record.
   --
   --  Caller: SData.Interpreter.Process_One_Record, called exactly once per
   --  record at the start of the deferred program body, after Group_Flags
   --  determines the boundary values from the physical row sequence and the
   --  active BY-variable list.
   --
   --  Both flags are set atomically; the evaluator makes no assertion about
   --  their values.  The BOG() and EOG() expression functions read these flags
   --  during Evaluate; behaviour is undefined if they are read before the first
   --  call in a data step.
   procedure Set_Group_Boundary (BOG, EOG : Boolean);

end SData.Evaluator;
