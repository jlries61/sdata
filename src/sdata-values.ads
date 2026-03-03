--  Package SData.Values defines the core data types used within the SData interpreter.
--  It provides a variant record type 'Value' that can represent numeric (Float),
--  integer (Integer), string, or missing values, along with utility functions.

package SData.Values is

   --  Kind of data stored in a Value record.
   type Value_Kind is (Val_Numeric, Val_Integer, Val_String, Val_Missing);

   --  The main data container for the interpreter.
   type Value (Kind : Value_Kind := Val_Missing) is record
      case Kind is
         when Val_Numeric =>
            Num_Val : Float;
         when Val_Integer =>
            Int_Val : Integer;
         when Val_String =>
            Str_Val : String (1 .. 1024);
            Str_Len : Natural;
         when Val_Missing =>
            null;
      end case;
   end record;

   --  Converts a Value to its string representation.
   --  Integers are formatted without decimals or scientific notation.
   function To_String (V : Value) return String;

   --  Determines the boolean truth of a value. 
   function Is_True (V : Value) return Boolean;

   --  Comparison functions
   function "=" (L, R : Value) return Boolean;
   function "<" (L, R : Value) return Boolean;

end SData.Values;
