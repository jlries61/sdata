with Ada.Strings.Fixed; use Ada.Strings.Fixed;

package body SData.Values is

   function To_String (V : Value) return String is
   begin
      case V.Kind is
         when Val_Numeric =>
            declare
               Img : String := Float'Image (V.Num_Val);
            begin
               return Trim (Img, Ada.Strings.Both);
            end;
         when Val_String =>
            return V.Str_Val (1 .. V.Str_Len);
         when Val_Missing =>
            return ".";
      end case;
   end To_String;

   function Is_True (V : Value) return Boolean is
   begin
      case V.Kind is
         when Val_Numeric =>
            return V.Num_Val /= 0.0;
         when others =>
            return False;
      end case;
   end Is_True;

end SData.Values;
