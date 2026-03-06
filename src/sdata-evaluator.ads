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

   -- Indicators for BY group boundaries
   function Is_BOG return Boolean;
   function Is_EOG return Boolean;

   procedure Set_BOG (Val : Boolean);
   procedure Set_EOG (Val : Boolean);

end SData.Evaluator;
