package SData.CSV is

   Max_Fields : constant := 65_536;
   type Field_Pair  is record S, E : Natural; end record;
   type Field_Array is array (1 .. Max_Fields) of Field_Pair;

   function Try_Fast_Float   (S         : String;
                               Result    : out Float) return Boolean;

   function Is_Numeric_Field (F : String) return Boolean;

   function At_Delimiter     (Line      : String;
                               Pos       : Positive;
                               Delimiter : String) return Boolean;

   function CSV_Field_End    (Line      : String;
                               From      : Positive;
                               Delimiter : String) return Natural;

   function CSV_Unquote      (Raw : String) return String;

   function Split_Indices    (Line      : String;
                               Delimiter : String;
                               N_Fields  : out Natural) return Field_Array;

end SData.CSV;
