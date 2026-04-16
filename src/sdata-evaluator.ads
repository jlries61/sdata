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

   -- Indicators for BY group boundaries
   function Is_BOG return Boolean;
   function Is_EOG return Boolean;

   procedure Set_BOG (Val : Boolean);
   procedure Set_EOG (Val : Boolean);

end SData.Evaluator;
