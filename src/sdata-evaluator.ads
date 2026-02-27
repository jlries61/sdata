--  Package SData.Evaluator performs the actual calculation of expressions.
--  It traverses the AST (Abstract Syntax Tree) recursively to produce a 'Value'
--  based on literals, variables, operators, and functions.

with SData.AST;    use SData.AST;
with SData.Values; use SData.Values;

package SData.Evaluator is

   --  Recursively evaluates an expression and returns the resulting Value.
   --  Handles missing value propagation automatically.
   function Evaluate (Expr : Expression_Access) return Value;

   --  Utility to convert a Value to a Float (handles Integer promotion).
   function Convert_To_Float (V : Value) return Float;

end SData.Evaluator;
