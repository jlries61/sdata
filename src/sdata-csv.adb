package body SData.CSV is

   function Try_Fast_Float (S : String; Result : out Float) return Boolean is
      pragma Unreferenced (S);
   begin
      Result := 0.0;
      return False;
   end Try_Fast_Float;

   function Is_Numeric_Field (F : String) return Boolean is
      pragma Unreferenced (F);
   begin
      return False;
   end Is_Numeric_Field;

   function At_Delimiter (Line      : String;
                           Pos       : Positive;
                           Delimiter : String) return Boolean is
      pragma Unreferenced (Line, Pos, Delimiter);
   begin
      return False;
   end At_Delimiter;

   function CSV_Field_End (Line      : String;
                            From      : Positive;
                            Delimiter : String) return Natural is
      pragma Unreferenced (Line, From, Delimiter);
   begin
      return 0;
   end CSV_Field_End;

   function CSV_Unquote (Raw : String) return String is
   begin
      return Raw;
   end CSV_Unquote;

   function Split_Indices (Line      : String;
                            Delimiter : String;
                            N_Fields  : out Natural) return Field_Array is
      pragma Unreferenced (Line, Delimiter);
      Res : Field_Array;
   begin
      N_Fields := 0;
      return Res;
   end Split_Indices;

end SData.CSV;
