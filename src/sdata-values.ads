--  Package SData.Values defines the core data types used within the SData interpreter.
--  It provides a variant record type 'Value' that can represent numeric (Float),
--  string, or missing values, along with utility functions for conversion and truth testing.

package SData.Values is

   --  Kind of data stored in a Value record.
   type Value_Kind is (Val_Numeric, Val_String, Val_Missing);

   --  The main data container for the interpreter.
   --  Missing values are explicitly represented as Val_Missing.
   type Value (Kind : Value_Kind := Val_Missing) is record
      case Kind is
         when Val_Numeric =>
            Num_Val : Float;
         when Val_String =>
            --  Strings are stored as fixed-length arrays with a current length tracker.
            Str_Val : String (1 .. 1024);
            Str_Len : Natural;
         when Val_Missing =>
            null;
      end case;
   end record;

   --  Converts a Value to its string representation (e.g., for PRINT).
   function To_String (V : Value) return String;

   --  Determines the boolean truth of a value. 
   --  By convention, non-zero numeric values are True, strings and missing are False.
   function Is_True (V : Value) return Boolean;

end SData.Values;
