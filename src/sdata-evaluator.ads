--  Package SData.Evaluator implements the Expression Evaluation Engine.
--  It takes AST expression nodes and returns computed 'Value' records,
--  interacting with SData.Variables for symbol lookups.

with SData.AST;    use SData.AST;
with SData.Values; use SData.Values;
private with Ada.Containers.Vectors;
private with Ada.Containers.Indefinite_Hashed_Maps;
private with Ada.Strings.Hash;

package SData.Evaluator is

   --  Computes the value of an AST expression.
   function Evaluate (Expr : Expression_Access) return Value;

   --  Converts any numeric value kind to Float for calculation.
   function Convert_To_Float (V : Value) return Float;

   --  Returns the expected kind of value based on name suffix
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

private

   --  Type infrastructure shared by the parent body and all private child
   --  packages that implement handler families.

   package Value_Vectors is new Ada.Containers.Vectors
      (Index_Type   => Positive,
       Element_Type => Value,
       "="          => SData.Values."=");

   use type Ada.Containers.Count_Type;

   type Fn_Handler is access function
      (Name : String; Vals : Value_Vectors.Vector) return Value;

   package Fn_Maps is new Ada.Containers.Indefinite_Hashed_Maps
      (Key_Type        => String,
       Element_Type    => Fn_Handler,
       Hash            => Ada.Strings.Hash,
       Equivalent_Keys => "=");

   --  Per-record BY-group boundary indicators.  Written exclusively by
   --  Set_Group_Boundary; read by the BOG/EOG handler families.
   BOG_Flag : Boolean := False;
   EOG_Flag : Boolean := False;

   --  Global dispatch table — populated during elaboration by each handler
   --  family's private child package.
   Dispatch_Table : Fn_Maps.Map;

   --  Helpers used by every handler family.
   function Has_Args (Vals : Value_Vectors.Vector; N : Positive) return Boolean;
   function Num_Result (V : Float) return Value;
   function Handle_Domain_Error (Msg : String) return Value;

end SData.Evaluator;
