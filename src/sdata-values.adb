with Ada.Strings.Fixed; use Ada.Strings.Fixed;

package body SData.Values is

   ------------------
   -- To_String --
   ------------------
   --  Converts the internal Value representation to a human-readable string.
   function To_String (V : Value) return String is
   begin
      case V.Kind is
         when Val_Numeric =>
            declare
               --  Use standard Float'Image and trim extra spaces.
               Img : String := Float'Image (V.Num_Val);
            begin
               return Trim (Img, Ada.Strings.Both);
            end;
         when Val_String =>
            --  Return exactly the part of the buffer that contains the string.
            return V.Str_Val (1 .. V.Str_Len);
         when Val_Missing =>
            --  Missing values are represented as a single dot in output.
            return ".";
      end case;
   end To_String;

   -------------
   -- Is_True --
   -------------
   --  Evaluation logic for boolean contexts (like IF statements).
   function Is_True (V : Value) return Boolean is
   begin
      case V.Kind is
         when Val_Numeric =>
            --  Numeric values follow the standard "non-zero is true" rule.
            return V.Num_Val /= 0.0;
         when others =>
            --  Strings and missing values are always considered False in a boolean context.
            return False;
      end case;
   end Is_True;

end SData.Values;
