--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Execute_Assignment (Stmt : Statement_Access) is

   --  Array assignment: single-index, slice (Lo:Hi), or list (i,j,k).
   --  Ownership rules (LET/SET vs permanent/temporary) are checked here, per
   --  element (ADR-0023): a virtual array's constituents can differ in
   --  storage class, so the array-level Is_Temporary_Array flag (always
   --  False for virtual arrays) cannot decide this for them. A Real_Array's
   --  elements share one class uniformly by construction, so per-element
   --  and array-level agree there -- see
   --  SData_Core.Variables.Array_Element_Is_Temporary's own contract.
   procedure Execute_Array_Assignment
     (Stmt     : Statement_Access;
      Var_Name : String;
      Result   : Value)
   is
      Prefix : constant String := (if Stmt.Kind = Stmt_LET then "LET " else "SET ");

      function Element_Ref (Idx : Integer) return String is
        (Var_Name & "(" & Ada.Strings.Fixed.Trim (Integer'Image (Idx), Ada.Strings.Both) & ")");

      --  Raises if Idx's own constituent doesn't match the verb in use.
      --  Called for every index in the target set before any write in the
      --  same statement happens, so a slice/list spanning constituents of
      --  mixed storage class fails atomically rather than partially.
      procedure Validate_Element (Idx : Integer) is
      begin
         if Stmt.Kind = Stmt_LET and then Array_Element_Is_Temporary (Var_Name, Idx) then
            raise Script_Error with
              "LET statement cannot modify temporary element """ & Element_Ref (Idx)
              & """ of array """ & Var_Name
              & """; use SET, or UNSET the underlying variable to convert it to permanent";
         elsif Stmt.Kind = Stmt_SET and then not Array_Element_Is_Temporary (Var_Name, Idx) then
            raise Script_Error with
              "SET statement cannot modify permanent element """ & Element_Ref (Idx)
              & """ of array """ & Var_Name
              & """; use LET, or DROP the underlying variable (effective after the next RUN) "
              & "to convert it to temporary";
         end if;
      end Validate_Element;
   begin
      if not Has_Array (Var_Name) then
         raise Script_Error with "Array """ & Var_Name & """ is not defined";
      end if;

      if Stmt.Arr_Idx_List /= null then
         if Stmt.Arr_Is_Slice then
            --  Range assignment: ARR(Lo:Hi) = value
            declare
               Lo_Val : constant Value := Evaluate (Stmt.Arr_Idx_List.Expr);
               Hi_Val : constant Value := Evaluate (Stmt.Arr_Idx_List.Next.Expr);
               Lo, Hi : Integer;
            begin
               if Lo_Val.Kind = Val_Integer then Lo := Integer (Lo_Val.Int_Val);
               elsif Lo_Val.Kind = Val_Numeric then Lo := Integer (Real'Floor (Lo_Val.Num_Val));
               else raise Script_Error with "Array slice lower bound for """ & Var_Name & """ must be numeric";
               end if;
               if Hi_Val.Kind = Val_Integer then Hi := Integer (Hi_Val.Int_Val);
               elsif Hi_Val.Kind = Val_Numeric then Hi := Integer (Real'Floor (Hi_Val.Num_Val));
               else raise Script_Error with "Array slice upper bound for """ & Var_Name & """ must be numeric";
               end if;
               for I in Lo .. Hi loop
                  Validate_Element (I);
               end loop;
               for I in Lo .. Hi loop
                  Set_Array_Element (Var_Name, I, Result);
               end loop;
               Debug_Trace (Prefix & Var_Name & "("
                            & Ada.Strings.Fixed.Trim (Integer'Image (Lo), Ada.Strings.Both)
                            & ":"
                            & Ada.Strings.Fixed.Trim (Integer'Image (Hi), Ada.Strings.Both)
                            & ") = " & Debug_Value (Result), 3);
            end;
         else
            --  List assignment: ARR(1,3,5) = value. Indices are evaluated
            --  once into Indices (not re-evaluated for the write pass) so
            --  validation and writing agree on the exact same target set.
            declare
               package Index_Vectors is new Ada.Containers.Vectors (Positive, Integer);
               Node    : Expression_List := Stmt.Arr_Idx_List;
               Idx_Val : Value;
               Idx     : Integer;
               Indices : Index_Vectors.Vector;
            begin
               while Node /= null loop
                  Idx_Val := Evaluate (Node.Expr);
                  if Idx_Val.Kind = Val_Integer then Idx := Integer (Idx_Val.Int_Val);
                  elsif Idx_Val.Kind = Val_Numeric then Idx := Integer (Real'Floor (Idx_Val.Num_Val));
                  else raise Script_Error with "Array index for """ & Var_Name & """ must be numeric";
                  end if;
                  Indices.Append (Idx);
                  Node := Node.Next;
               end loop;
               for I of Indices loop
                  Validate_Element (I);
               end loop;
               for I of Indices loop
                  Set_Array_Element (Var_Name, I, Result);
               end loop;
               Debug_Trace (Prefix & Var_Name & "(...) = " & Debug_Value (Result), 3);
            end;
         end if;
      else
         --  Single-index assignment: ARR(I) = value
         declare
            Idx_Val : constant Value := Evaluate (Stmt.Arr_Idx);
            Idx     : Integer;
         begin
            if Idx_Val.Kind = Val_Integer then Idx := Integer (Idx_Val.Int_Val);
            elsif Idx_Val.Kind = Val_Numeric then Idx := Integer (Real'Floor (Idx_Val.Num_Val));
            else
               raise Script_Error with "Array index for """ & Var_Name
                  & """ must be numeric, not "
                  & (if Idx_Val.Kind = Val_Missing then "missing" else "a string");
            end if;
            Validate_Element (Idx);
            Set_Array_Element (Var_Name, Idx, Result);
            Debug_Trace (Prefix & Var_Name & "("
                         & Ada.Strings.Fixed.Trim (Integer'Image (Idx), Ada.Strings.Both)
                         & ") = " & Debug_Value (Result), 3);
         end;
      end if;
   end Execute_Array_Assignment;

   --  Type compatibility check, Inf guard, and numeric promotion for scalar
   --  assignment.  Returns the coerced value ready to store, or Val_Missing
   --  when Inf->integer conversion is configured to warn rather than raise.
   function Coerce_For_Scalar (Var_Name : String; Raw : Value) return Value is
      Expected      : constant Value_Kind := Get_Expected_Kind (Var_Name);
      Existing_Kind : constant Value_Kind := Get_Type (Var_Name);
      Result        : Value := Raw;
   begin
      --  A missing RHS is assignable to a column of any type: it represents the
      --  absence of a value, not a value of a conflicting type.  Assigning
      --  missing to an EXISTING typed column (e.g. recoding a sentinel to
      --  missing in place) must therefore succeed, exactly as it does for a
      --  new column (issue #51).  The coercion block below already skips a
      --  missing Result; this guard makes the type-compatibility check skip it
      --  too, instead of rejecting missing as "not the expected kind".
      if Existing_Kind /= Val_Missing and then Result.Kind /= Val_Missing then
         if Expected /= Result.Kind and not (Expected = Val_Numeric and Result.Kind = Val_Integer) then
            raise SData_Core.Table.Type_Mismatch_Error with
              "Cannot assign " & Result.Kind'Image & " to " & Expected'Image;
         end if;
         if Existing_Kind = Val_String and Result.Kind /= Val_String then
            raise SData_Core.Table.Type_Mismatch_Error with
              "Cannot assign numeric to string variable " & Var_Name;
         elsif Existing_Kind /= Val_String and Result.Kind = Val_String then
            raise SData_Core.Table.Type_Mismatch_Error with
              "Cannot assign string to numeric variable " & Var_Name;
         end if;
      end if;
      if Result.Kind = Val_Numeric and then Is_Inf (Result.Num_Val)
         and then Expected = Val_Integer
      then
         if SData_Core.Config.Ignore_Math_Errors then
            Put_Line_Error ("Warning: Cannot convert Inf to integer.");
            return (Kind => Val_Missing);
         else
            raise Script_Error with "Cannot convert Inf to integer.";
         end if;
      end if;
      if Result.Kind /= Val_Missing then
         if Expected = Val_Integer and Result.Kind /= Val_Integer then
            Result := (Kind    => Val_Integer,
                       Int_Val => Int (Real'Truncation (Convert_To_Real (Result))));
         elsif Expected = Val_Numeric and Result.Kind = Val_Integer then
            Result := (Kind => Val_Numeric, Num_Val => Real (Result.Int_Val));
         elsif Expected /= Result.Kind
            and not (Expected = Val_Numeric and Result.Kind = Val_Integer)
         then
            raise SData_Core.Table.Type_Mismatch_Error with
              "Cannot assign " & Result.Kind'Image & " to " & Expected'Image;
         end if;
      end if;
      if Result.Kind = Val_String
         and then SData_Core.Config.Max_String_Len > 0
         and then Length (Result.Str_Val) > SData_Core.Config.Max_String_Len
      then
         Put_Line_Error ("Warning: String truncated to "
                         & Integer'Image (SData_Core.Config.Max_String_Len) & " characters.");
         Result.Str_Val :=
           To_Unbounded_String (Slice (Result.Str_Val, 1, SData_Core.Config.Max_String_Len));
      end if;
      return Result;
   end Coerce_For_Scalar;

   --  LET / SET — evaluate, guard Inf for %-names, then dispatch.
   Var_Name_Str : constant String := Stmt.Var_Name (1 .. Stmt.Var_Len);
   Result       : Value;
begin
   --  Reject assignment to IN= provenance variables (read-only from user code).
   --  The base variable name is checked so that subscripted forms such as
   --  LET hasA(1) = 99 are also caught (IN= variables are scalar anyway).
   if Is_Readonly_IN_Name (Var_Name_Str) then
      raise SData_Core.Script_Error
        with "cannot assign to IN= variable """ & Var_Name_Str
             & """; IN= variables are read-only";
   end if;
   Result := Evaluate (Stmt.Expr);
   if Var_Name_Str'Length > 0
      and then Var_Name_Str (Var_Name_Str'Last) = '%'
      and then Result.Kind = Val_Numeric
      and then Is_Inf (Result.Num_Val)
   then
      if SData_Core.Config.Ignore_Math_Errors then
         Put_Line_Error ("Warning: Cannot convert Inf to integer.");
         Result := (Kind => Val_Missing);
      else
         raise Script_Error with "Cannot convert Inf to integer.";
      end if;
   end if;
   if Stmt.Is_Array then
      Execute_Array_Assignment (Stmt, Var_Name_Str, Result);
   else
      Result := Coerce_For_Scalar (Var_Name_Str, Result);
      if Stmt.Kind = Stmt_LET then
         Set_Permanent (Var_Name_Str, Result);
      else
         Set_Temporary (Var_Name_Str, Result);
      end if;
      Debug_Trace ((if Stmt.Kind = Stmt_LET then "LET " else "SET ")
                   & Var_Name_Str & " = " & Debug_Value (Result), 3);
   end if;
exception
   when E : SData_Core.Table.Type_Mismatch_Error =>
      raise Script_Error with "Type mismatch for variable " & Var_Name_Str
        & ": " & Ada.Exceptions.Exception_Message (E);
   when Script_Error => raise;
   when SData_Core.Script_Error => raise;
   when E : others =>
      raise Script_Error with "Assignment failed for variable " & Var_Name_Str
        & ": " & Ada.Exceptions.Exception_Message (E);
end Execute_Assignment;