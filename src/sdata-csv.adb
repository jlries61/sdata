with Ada.Strings;
with Ada.Strings.Fixed;     use Ada.Strings.Fixed;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body SData.CSV is

   --  Fast decimal parser: handles integers and simple N.M decimals
   --  without invoking the Ada runtime.  Scientific notation and other
   --  edge cases fall through to Float'Value.
   --  Returns True and sets Result for any valid floating-point value.
   --  Returns False only if the string cannot represent a number.
   function Try_Fast_Float (S : String; Result : out Float) return Boolean is
      I         : Integer := S'First;
      Whole     : Float   := 0.0;
      Frac      : Float   := 0.0;
      Denom     : Float   := 1.0;
      Sign      : Float   := 1.0;
      After_Dot : Boolean := False;
      Has_Digit : Boolean := False;
   begin
      if I > S'Last then return False; end if;
      if    S (I) = '-' then Sign := -1.0; I := I + 1;
      elsif S (I) = '+' then               I := I + 1;
      end if;
      while I <= S'Last loop
         case S (I) is
            when '0' .. '9' =>
               Has_Digit := True;
               if After_Dot then
                  Denom := Denom * 10.0;
                  Frac  := Frac + Float (Character'Pos (S (I)) - 48) / Denom;
               else
                  Whole := Whole * 10.0 + Float (Character'Pos (S (I)) - 48);
               end if;
            when '.' =>
               if After_Dot then return False; end if;
               After_Dot := True;
            when 'E' | 'e' | 'D' | 'd' =>
               begin
                  Result := Float'Value (S);
                  return True;
               exception
                  when others => return False;
               end;
            when others => return False;
         end case;
         I := I + 1;
      end loop;
      if not Has_Digit then return False; end if;
      Result := Sign * (Whole + Frac);
      return True;
   end Try_Fast_Float;

   function Is_Numeric_Field (F : String) return Boolean is
      Dummy : Float;
   begin
      return Try_Fast_Float (F, Dummy);
   end Is_Numeric_Field;

   function At_Delimiter (Line      : String;
                           Pos       : Positive;
                           Delimiter : String) return Boolean is
      DLen : constant Positive :=
         (if Delimiter'Length > 0 then Delimiter'Length else 1);
   begin
      pragma Assert (Delimiter'Length > 0);
      if Pos + DLen - 1 > Line'Last then return False; end if;
      if DLen = 1 then return Line (Pos) = Delimiter (Delimiter'First); end if;
      return Line (Pos .. Pos + DLen - 1) = Delimiter;
   end At_Delimiter;

   function CSV_Field_End (Line      : String;
                            From      : Positive;
                            Delimiter : String) return Natural is
      I : Positive := From;
      Q : Character;
   begin
      if I > Line'Last then return 0; end if;
      if Line (I) = '"' or else Line (I) = ''' then
         Q := Line (I);
         I := I + 1;
         while I <= Line'Last loop
            if Line (I) = Q then
               if I < Line'Last and then Line (I + 1) = Q then
                  I := I + 2;   --  doubled quote → literal
               else
                  I := I + 1;   --  closing quote
                  exit;
               end if;
            else
               I := I + 1;
            end if;
         end loop;
         --  After the closing quote, the next chars must be the delimiter.
         if At_Delimiter (Line, I, Delimiter) then return I; end if;
         return 0;
      else
         for K in From .. Line'Last loop
            if At_Delimiter (Line, K, Delimiter) then return K; end if;
         end loop;
         return 0;
      end if;
   end CSV_Field_End;

   function CSV_Unquote (Raw : String) return String is
      T : constant String := Trim (Raw, Ada.Strings.Both);
      Q : Character;
      R : Unbounded_String;
      I : Positive;
   begin
      if T'Length >= 2
         and then (T (T'First) = '"' or else T (T'First) = ''')
         and then T (T'Last) = T (T'First)
      then
         Q := T (T'First);
         I := T'First + 1;
         while I <= T'Last - 1 loop
            if T (I) = Q and then I < T'Last - 1 and then T (I + 1) = Q then
               Append (R, Q);
               I := I + 2;
            else
               Append (R, T (I));
               I := I + 1;
            end if;
         end loop;
         return To_String (R);
      end if;
      return T;
   end CSV_Unquote;

   function Split_Indices (Line      : String;
                            Delimiter : String;
                            N_Fields  : out Natural) return Field_Array is
      Res   : Field_Array;
      Start : Integer := Line'First;
      Count : Natural := 0;
      DLen  : constant Positive :=
         (if Delimiter'Length > 0 then Delimiter'Length else 1);
   begin
      N_Fields := 0;
      if Line'Length = 0 then return Res; end if;
      loop
         declare
            Delim : constant Natural := CSV_Field_End (Line, Start, Delimiter);
         begin
            Count := Count + 1;
            if Count <= Max_Fields then
               Res (Count).S := Start;
               Res (Count).E := (if Delim > 0 then Delim - 1 else Line'Last);
            end if;
            exit when Delim = 0;
            Start := Delim + DLen;
         end;
      end loop;
      N_Fields := Count;
      return Res;
   end Split_Indices;

end SData.CSV;
