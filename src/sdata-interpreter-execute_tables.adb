separate (SData.Interpreter)
procedure Execute_Tables (Stmt : Statement_Access) is
   package Values renames SData_Core.Values;
   package IO     renames SData_Core.IO;
   use type Values.Value_Kind;
   use Ada.Strings;
   use Ada.Strings.Fixed;

   --  Two-decimal float formatter (e.g. 50.00).
   function Fmt2 (X : Float) return String is
      package F_IO is new Ada.Text_IO.Float_IO (Float);
      Buf : String (1 .. 32);
   begin
      F_IO.Put (Buf, X, Aft => 2, Exp => 0);
      return Trim (Buf, Both);
   end Fmt2;

   --  ---- counting-engine types (reused by Tasks 6-10) ----
   type Level is record
      Val   : Values.Value;
      Disp  : Unbounded_String;
      Count : Natural := 0;
   end record;
   package Level_Vectors is new Ada.Containers.Vectors (Positive, Level);

   function Is_Present (V : Values.Value; Include_Missing : Boolean)
      return Boolean is
   begin
      if V.Kind = Values.Val_Missing then
         return Include_Missing;
      end if;
      if V.Kind = Values.Val_String
        and then Ada.Strings.Unbounded.Length (V.Str_Val) = 0
      then
         return Include_Missing;
      end if;
      return True;
   end Is_Present;

   function Disp_Of (V : Values.Value) return Unbounded_String is
   begin
      if V.Kind = Values.Val_Missing
        or else (V.Kind = Values.Val_String
                 and then Ada.Strings.Unbounded.Length (V.Str_Val) = 0)
      then
         return To_Unbounded_String (".");
      end if;
      return To_Unbounded_String (Values.To_String_Formatted (V));
   end Disp_Of;

   function Numeric (V : Values.Value) return Boolean is
     (V.Kind = Values.Val_Numeric or else V.Kind = Values.Val_Integer);

   function As_Float (V : Values.Value) return Float is
     (if V.Kind = Values.Val_Integer then Float (V.Int_Val) else V.Num_Val);

   --  Value-order comparison for two levels.
   function Level_Less (A, B : Level) return Boolean is
   begin
      if Numeric (A.Val) and then Numeric (B.Val) then
         return As_Float (A.Val) < As_Float (B.Val);
      end if;
      return A.Disp < B.Disp;
   end Level_Less;

   package Level_Sorting is new Level_Vectors.Generic_Sorting
     ("<" => Level_Less);

   function Freq_Greater (A, B : Level) return Boolean is
     (if A.Count /= B.Count then A.Count > B.Count else Level_Less (A, B));
   package Freq_Sorting is new Level_Vectors.Generic_Sorting
     ("<" => Freq_Greater);

   Order_Freq      : constant Boolean := Stmt.Table_Order_Freq;
   Include_Missing : constant Boolean := Stmt.Table_MISSING;

   --  Build the distinct, ordered levels of Col across the given physical rows.
   function Build_Levels (Rows : Row_Index_Vectors.Vector; Col : String)
      return Level_Vectors.Vector
   is
      Levels : Level_Vectors.Vector;
      function Find (D : Unbounded_String) return Natural is
      begin
         for I in Levels.First_Index .. Levels.Last_Index loop
            if Levels (I).Disp = D then
               return I;
            end if;
         end loop;
         return 0;
      end Find;
   begin
      for P of Rows loop
         declare
            V : constant Values.Value := SData_Core.Table.Get_Value (P, Col);
         begin
            if Is_Present (V, Include_Missing) then
               declare
                  D   : constant Unbounded_String := Disp_Of (V);
                  Idx : constant Natural := Find (D);
               begin
                  if Idx = 0 then
                     Levels.Append ((Val => V, Disp => D, Count => 1));
                  else
                     declare
                        L : Level := Levels (Idx);
                     begin
                        L.Count := L.Count + 1;
                        Levels.Replace_Element (Idx, L);
                     end;
                  end if;
               end;
            end if;
         end;
      end loop;
      if Order_Freq then
         Freq_Sorting.Sort (Levels);
      else
         Level_Sorting.Sort (Levels);
      end if;
      return Levels;
   end Build_Levels;

   --  ---- group splitting (replicates sdata-core Collect_Groups via public API)
   package Group_Of_Rows is new Ada.Containers.Vectors
     (Positive, Row_Index_Vectors.Vector, Row_Index_Vectors."=");

   function Group_Rows return Group_Of_Rows.Vector is
      Groups : Group_Of_Rows.Vector;
      Group  : Row_Index_Vectors.Vector;
      Prev_P : Positive := 1;
   begin
      for L in 1 .. SData_Core.Table.Logical_Row_Count loop
         declare
            P : constant Positive := SData_Core.Table.Logical_To_Physical (L);
         begin
            if L = 1 then
               Group.Append (P);
            elsif SData_Core.Table.By_Var_Count = 0
              or else SData_Core.Table.In_Same_Group (P, Prev_P)
            then
               Group.Append (P);
            else
               Groups.Append (Group);
               Group.Clear;
               Group.Append (P);
            end if;
            Prev_P := P;
         end;
      end loop;
      if not Group.Is_Empty then
         Groups.Append (Group);
      end if;
      return Groups;
   end Group_Rows;

   --  ---- one-way renderer ----
   procedure Render_One_Way (Rows : Row_Index_Vectors.Vector; Col : String) is
      Levels   : constant Level_Vectors.Vector := Build_Levels (Rows, Col);
      Total    : Natural := 0;
      Missing  : Natural := 0;
      Cum      : Natural := 0;
      Show_Pct : constant Boolean := not Stmt.Table_NOPERCENT;
      Show_Cum : constant Boolean := not Stmt.Table_NOCUM;
   begin
      for L of Levels loop
         Total := Total + L.Count;
      end loop;
      --  Missing rows for a single var = rows excluded by the present guard.
      for P of Rows loop
         if not Is_Present (SData_Core.Table.Get_Value (P, Col),
                            Include_Missing)
         then
            Missing := Missing + 1;
         end if;
      end loop;

      IO.Put_Line ("Frequency table for " & Col);
      IO.New_Line;
      --  header
      declare
         H : Unbounded_String := To_Unbounded_String (Col & " Frequency");
      begin
         if Show_Pct then
            Append (H, " Percent");
         end if;
         if Show_Cum then
            Append (H, " Cum_Freq");
         end if;
         if Show_Cum and then Show_Pct then
            Append (H, " Cum_Percent");
         end if;
         IO.Put_Line (To_String (H));
      end;
      for L of Levels loop
         Cum := Cum + L.Count;
         declare
            Line : Unbounded_String :=
              L.Disp & " " & Trim (L.Count'Image, Both);
            Pct  : constant Float :=
              (if Total = 0 then 0.0
               else 100.0 * Float (L.Count) / Float (Total));
            CPct : constant Float :=
              (if Total = 0 then 0.0
               else 100.0 * Float (Cum) / Float (Total));
         begin
            if Show_Pct then
               Append (Line, " " & Fmt2 (Pct));
            end if;
            if Show_Cum then
               Append (Line, " " & Trim (Cum'Image, Both));
            end if;
            if Show_Cum and then Show_Pct then
               Append (Line, " " & Fmt2 (CPct));
            end if;
            IO.Put_Line (To_String (Line));
         end;
      end loop;
      declare
         T : Unbounded_String :=
           To_Unbounded_String ("Total " & Trim (Total'Image, Both));
      begin
         if Show_Pct then
            Append (T, " 100.00");
         end if;
         IO.Put_Line (To_String (T));
      end;
      if not Include_Missing and then Missing > 0 then
         IO.New_Line;
         IO.Put_Line ("Frequency Missing = " & Trim (Missing'Image, Both));
      end if;
   end Render_One_Way;

   --  Dispatch one request within one group (extended in Tasks 6-10).
   procedure Render_Request (Rows : Row_Index_Vectors.Vector; Req : Table_Request)
   is
      K   : Natural := 0;
      Cur : Variable_List := Req.Vars;
   begin
      while Cur /= null loop
         K := K + 1;
         Cur := Cur.Next;
      end loop;
      if K = 1 then
         Render_One_Way
           (Rows, Req.Vars.Var.Start_Name (1 .. Req.Vars.Var.Start_Len));
      else
         --  Crossing (K >= 2) rendering added in a later task.
         IO.Put_Line ("(multiway rendering added in a later task)");
      end if;
   end Render_Request;

begin
   if Pending_Deferred > 0 then
      raise SData_Core.Script_Error with
        "TABLES: pending program statements exist; issue RUN or NEW first";
   end if;

   declare
      Groups      : constant Group_Of_Rows.Vector := Group_Rows;
      Multi_Group : constant Boolean :=
        SData_Core.Table.By_Var_Count > 0
          and then Natural (Groups.Length) > 1;
      GI          : Natural := 0;
   begin
      for G of Groups loop
         GI := GI + 1;
         if Multi_Group then
            --  BY header (extended/verified in Task 9)
            IO.Put_Line ("----- BY group" & GI'Image & " -----");
         end if;
         declare
            Req : Table_Request := Stmt.Requests;
         begin
            while Req /= null loop
               Render_Request (G, Req);
               IO.New_Line;
               Req := Req.Next;
            end loop;
         end;
      end loop;
   end;
   IO.Put_Line ("TABLES complete.");
end Execute_Tables;
