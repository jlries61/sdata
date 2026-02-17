package SData.Values is

   type Value_Kind is (Val_Numeric, Val_String, Val_Missing);

   type Value (Kind : Value_Kind := Val_Missing) is record
      case Kind is
         when Val_Numeric =>
            Num_Val : Float;
         when Val_String =>
            Str_Val : String (1 .. 1024);
            Str_Len : Natural;
         when Val_Missing =>
            null;
      end case;
   end record;

   function To_String (V : Value) return String;
   function Is_True (V : Value) return Boolean;

end SData.Values;
