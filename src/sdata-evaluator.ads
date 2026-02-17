with SData.AST;    use SData.AST;
with SData.Values; use SData.Values;

package SData.Evaluator is

   function Evaluate (Expr : Expression_Access) return Value;

end SData.Evaluator;
