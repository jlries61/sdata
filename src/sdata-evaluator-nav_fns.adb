with SData.Table;
with Ada.Characters.Handling; use Ada.Characters.Handling;
with SData.Values; use SData.Values;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

package body SData.Evaluator.Nav_Fns is

   function Handle_Recno (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind    => Val_Integer,
              Int_Val => (if SData.Table.Is_Filtered
                          then Integer (SData.Table.Get_Logical_Record_Index)
                          else Integer (SData.Table.Get_Current_Record_Index)));
   end Handle_Recno;

   function Handle_Ord (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if Has_Args (Vals, 1) then
         declare V : constant Value := Vals.Element (1);
         begin
            if V.Kind /= Val_String or else Length (V.Str_Val) = 0 then
               return (Kind => Val_Missing);
            end if;
            return (Kind    => Val_Integer,
                    Int_Val => Character'Pos (Element (V.Str_Val, 1)));
         end;
      end if;
      return (Kind    => Val_Integer,
              Int_Val => (if SData.Table.Is_Filtered
                          then Integer (SData.Table.Get_Logical_Record_Index)
                          else Integer (SData.Table.Get_Current_Record_Index)));
   end Handle_Ord;

   function Handle_BOF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind    => Val_Integer,
              Int_Val => (if SData.Table.Is_Filtered
                          then (if SData.Table.Get_Logical_Record_Index <= 1 then 1 else 0)
                          else (if SData.Table.Get_Current_Record_Index <= 1 then 1 else 0)));
   end Handle_BOF;

   function Handle_EOF (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind    => Val_Integer,
              Int_Val => (if SData.Table.Is_Filtered
                          then (if SData.Table.Get_Logical_Record_Index >= SData.Table.Logical_Row_Count then 1 else 0)
                          else (if SData.Table.Get_Current_Record_Index >= SData.Table.Row_Count then 1 else 0)));
   end Handle_EOF;

   function Handle_BOG (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind => Val_Integer, Int_Val => (if BOG_Flag then 1 else 0));
   end Handle_BOG;

   function Handle_EOG (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name, Vals);
   begin
      return (Kind => Val_Integer, Int_Val => (if EOG_Flag then 1 else 0));
   end Handle_EOG;

   function Handle_Lag (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare
         Var     : constant Value := Vals.Element (1);
         N_Val   : constant Value :=
            (if Has_Args (Vals, 2) then Vals.Element (2)
             else (Kind => Val_Integer, Int_Val => 1));
         N       : Integer;
         Log_Idx : constant Natural :=
            (if SData.Table.Is_Filtered then SData.Table.Get_Logical_Record_Index
             else SData.Table.Get_Current_Record_Index);
      begin
         if Var.Kind /= Val_String then return (Kind => Val_Missing); end if;
         N := Integer (Convert_To_Float (N_Val));
         if N <= 0 or else Log_Idx <= N then return (Kind => Val_Missing); end if;
         declare
            Phys_Curr : constant Positive := SData.Table.Logical_To_Physical (Log_Idx);
            Phys_Prev : constant Positive := SData.Table.Logical_To_Physical (Log_Idx - N);
         begin
            if not SData.Table.In_Same_Group (Phys_Curr, Phys_Prev) then
               return (Kind => Val_Missing);
            end if;
            return SData.Table.Get_Value_Upper (Phys_Prev, To_Upper (SData.Values.To_String (Var)));
         end;
      end;
   end Handle_Lag;

   function Handle_Next_Val (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 1) then return (Kind => Val_Missing); end if;
      declare
         Var       : constant Value := Vals.Element (1);
         N_Val     : constant Value :=
            (if Has_Args (Vals, 2) then Vals.Element (2)
             else (Kind => Val_Integer, Int_Val => 1));
         N         : Integer;
         Log_Idx   : constant Natural :=
            (if SData.Table.Is_Filtered then SData.Table.Get_Logical_Record_Index
             else SData.Table.Get_Current_Record_Index);
         Log_Count : constant Natural :=
            (if SData.Table.Is_Filtered then SData.Table.Logical_Row_Count
             else SData.Table.Row_Count);
      begin
         if Var.Kind /= Val_String then return (Kind => Val_Missing); end if;
         N := Integer (Convert_To_Float (N_Val));
         if N <= 0 or else (Log_Idx + N) > Log_Count then return (Kind => Val_Missing); end if;
         declare
            Phys_Curr : constant Positive := SData.Table.Logical_To_Physical (Log_Idx);
            Phys_Next : constant Positive := SData.Table.Logical_To_Physical (Log_Idx + N);
         begin
            if not SData.Table.In_Same_Group (Phys_Curr, Phys_Next) then
               return (Kind => Val_Missing);
            end if;
            return SData.Table.Get_Value_Upper (Phys_Next, To_Upper (SData.Values.To_String (Var)));
         end;
      end;
   end Handle_Next_Val;

   function Handle_Obs (Name : String; Vals : Value_Vectors.Vector) return Value is
      pragma Unreferenced (Name);
   begin
      if not Has_Args (Vals, 2) then return (Kind => Val_Missing); end if;
      declare
         Var     : constant Value := Vals.Element (1);
         Row_Val : constant Value := Vals.Element (2);
         Row     : Integer;
      begin
         if Var.Kind /= Val_String then return (Kind => Val_Missing); end if;
         Row := Integer (Convert_To_Float (Row_Val));
         if Row < 1 or else Row > SData.Table.Row_Count then
            return (Kind => Val_Missing);
         end if;
         return SData.Table.Get_Value_Upper (Row, To_Upper (SData.Values.To_String (Var)));
      end;
   end Handle_Obs;

   ---------------------------------------------------------------------------

   procedure Register is
   begin
      Dispatch_Table.Insert ("RECNO",  Handle_Recno'Access);
      Dispatch_Table.Insert ("BOF",    Handle_BOF'Access);
      Dispatch_Table.Insert ("EOF",    Handle_EOF'Access);
      Dispatch_Table.Insert ("BOG",    Handle_BOG'Access);
      Dispatch_Table.Insert ("EOG",    Handle_EOG'Access);
      Dispatch_Table.Insert ("ORD",    Handle_Ord'Access);
      Dispatch_Table.Insert ("LAG",    Handle_Lag'Access);
      Dispatch_Table.Insert ("LAGC$",  Handle_Lag'Access);
      Dispatch_Table.Insert ("NEXT",   Handle_Next_Val'Access);
      Dispatch_Table.Insert ("NEXTC$", Handle_Next_Val'Access);
      Dispatch_Table.Insert ("OBS",    Handle_Obs'Access);
      Dispatch_Table.Insert ("OBSC$",  Handle_Obs'Access);
   end Register;

begin
   Register;
end SData.Evaluator.Nav_Fns;
