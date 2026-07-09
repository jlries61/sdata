separate (SData.Interpreter)
procedure Execute_Tables (Stmt : Statement_Access) is
   package Values renames SData_Core.Values;
   package IO     renames SData_Core.IO;
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

   --  Four-decimal float formatter (e.g. 0.6667) for /CHISQ statistics.
   function Fmt4 (X : Float) return String is
      package F_IO is new Ada.Text_IO.Float_IO (Float);
      Buf : String (1 .. 32);
   begin
      F_IO.Put (Buf, X, Aft => 4, Exp => 0);
      return Trim (Buf, Both);
   end Fmt4;

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

   --  Display-text -> Natural map, used both for O(1) level-membership during
   --  accumulation (Build_Levels) and O(1) value->index lookup on a sorted
   --  level vector (Index_Map), plus the two-way cell counts.
   package Count_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Natural,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   --  Build the distinct, ordered levels of Col across the given physical rows.
   --  Membership uses a Disp-text -> index map (Pos) so accumulation is
   --  O(rows), not O(rows * distinct-levels) as the old linear scan was.  Pos
   --  is discarded on return; callers needing index lookups on the SORTED
   --  result build a fresh map with Index_Map.
   function Build_Levels (Rows : Row_Index_Vectors.Vector; Col : String)
      return Level_Vectors.Vector
   is
      Levels : Level_Vectors.Vector;
      Pos    : Count_Maps.Map;   --  Disp text -> 1-based index in Levels
   begin
      for P of Rows loop
         declare
            V : constant Values.Value := SData_Core.Table.Get_Value (P, Col);
         begin
            if Is_Present (V, Include_Missing) then
               declare
                  D  : constant Unbounded_String := Disp_Of (V);
                  Ds : constant String := To_String (D);
               begin
                  if Pos.Contains (Ds) then
                     declare
                        Idx : constant Positive := Pos (Ds);
                        L   : Level := Levels (Idx);
                     begin
                        L.Count := L.Count + 1;
                        Levels.Replace_Element (Idx, L);
                     end;
                  else
                     Levels.Append ((Val => V, Disp => D, Count => 1));
                     Pos.Insert (Ds, Levels.Last_Index);
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

   --  ---- two-way helpers ----

   --  Disp-text -> 1-based index over an (already sorted) level vector, so a
   --  value's level index becomes an O(1) lookup rather than a linear scan.
   --  Keys are distinct (Build_Levels dedups by Disp).
   function Index_Map (Levels : Level_Vectors.Vector) return Count_Maps.Map is
      M : Count_Maps.Map;
   begin
      for I in Levels.First_Index .. Levels.Last_Index loop
         M.Insert (To_String (Levels (I).Disp), I);
      end loop;
      return M;
   end Index_Map;

   --  Canonical cell-map key for 1-based level indices (row I, column J).
   function Cell_Key (I, J : Positive) return String is
     (Trim (I'Image, Both) & "|" & Trim (J'Image, Both));

   --  Shared joint-derived levels/marginals/cells for a 2-way crossing.
   --  Only rows where BOTH V1 and V2 are present (per Include_Missing) are
   --  counted.  Levels, marginals, and the cell map all derive from these
   --  jointly-present rows, so orphan levels (values that only ever co-occur
   --  with a missing partner) are dropped, each row/column total equals the
   --  sum of its cells, and the grand total equals the jointly-present row
   --  count.  Both Render_Two_Way_Grid and Build_Count_Matrix consume this so
   --  they always agree (same levels, marginals, and cell counts).
   type Joint_Table is record
      L1, L2  : Level_Vectors.Vector;
      Cells   : Count_Maps.Map;    --  key "i|j" of 1-based level indices
      Grand   : Natural := 0;
      Missing : Natural := 0;
   end record;

   function Build_Joint (Rows   : Row_Index_Vectors.Vector;
                         V1, V2 : String) return Joint_Table
   is
      JT         : Joint_Table;
      Joint_Rows : Row_Index_Vectors.Vector;
   begin
      --  Partition rows into jointly-present vs. missing (any crossing var
      --  missing).  Under /MISSING, Is_Present is always True, so every row
      --  is jointly present and "." becomes a valid level in both margins.
      for P of Rows loop
         declare
            A : constant Values.Value := SData_Core.Table.Get_Value (P, V1);
            B : constant Values.Value := SData_Core.Table.Get_Value (P, V2);
         begin
            if Is_Present (A, Include_Missing)
              and then Is_Present (B, Include_Missing)
            then
               Joint_Rows.Append (P);
            else
               JT.Missing := JT.Missing + 1;
            end if;
         end;
      end loop;
      --  Marginal levels derive from jointly-present rows only (drops orphans);
      --  Build_Levels also applies the requested value/frequency ordering, so
      --  under /ORDER=FREQ the margins order by the JOINT marginal.
      JT.L1 := Build_Levels (Joint_Rows, V1);
      JT.L2 := Build_Levels (Joint_Rows, V2);
      --  Cell counts keyed on final (post-sort) level indices; index lookups
      --  go through Disp-text maps (O(1)) rather than a per-row linear scan.
      declare
         P1 : constant Count_Maps.Map := Index_Map (JT.L1);
         P2 : constant Count_Maps.Map := Index_Map (JT.L2);
      begin
         for P of Joint_Rows loop
            declare
               I   : constant Positive :=
                 P1 (To_String (Disp_Of (SData_Core.Table.Get_Value (P, V1))));
               J   : constant Positive :=
                 P2 (To_String (Disp_Of (SData_Core.Table.Get_Value (P, V2))));
               Key : constant String := Cell_Key (I, J);
            begin
               if JT.Cells.Contains (Key) then
                  JT.Cells.Replace (Key, JT.Cells (Key) + 1);
               else
                  JT.Cells.Insert (Key, 1);
               end if;
               JT.Grand := JT.Grand + 1;
            end;
         end loop;
      end;
      return JT;
   end Build_Joint;

   procedure Render_Two_Way_Grid (Rows : Row_Index_Vectors.Vector;
                                  V1, V2 : String) is
      JT      : constant Joint_Table := Build_Joint (Rows, V1, V2);
      L1      : Level_Vectors.Vector renames JT.L1;
      L2      : Level_Vectors.Vector renames JT.L2;
      Joint   : Count_Maps.Map renames JT.Cells;
      Grand   : Natural renames JT.Grand;
      Missing : Natural renames JT.Missing;
      Show_Pct : constant Boolean := not Stmt.Table_NOPERCENT;
   begin
      IO.Put_Line ("Table of " & V1 & " by " & V2);
      IO.New_Line;
      IO.Put_Line ("Cell contents: Frequency" &
                   (if Show_Pct then " Percent" else "") &
                   " Row_Percent Col_Percent");
      IO.New_Line;
      --  Column header
      declare
         H : Unbounded_String := To_Unbounded_String (V1);
      begin
         for C of L2 loop
            Append (H, " " & V2 & "=" & To_String (C.Disp));
         end loop;
         Append (H, " Total");
         IO.Put_Line (To_String (H));
      end;
      --  Data rows
      for I in L1.First_Index .. L1.Last_Index loop
         declare
            Line    : Unbounded_String := L1 (I).Disp;
            Row_Tot : constant Natural := L1 (I).Count;
         begin
            for J in L2.First_Index .. L2.Last_Index loop
               declare
                  Key : constant String := Cell_Key (I, J);
                  F   : constant Natural :=
                    (if Joint.Contains (Key) then Joint (Key) else 0);
                  Pct : constant Float :=
                    (if Grand = 0 then 0.0
                     else 100.0 * Float (F) / Float (Grand));
                  RP  : constant Float :=
                    (if L1 (I).Count = 0 then 0.0
                     else 100.0 * Float (F) / Float (L1 (I).Count));
                  CP  : constant Float :=
                    (if L2 (J).Count = 0 then 0.0
                     else 100.0 * Float (F) / Float (L2 (J).Count));
               begin
                  Append (Line, " " & Trim (F'Image, Both));
                  if Show_Pct then
                     Append (Line, " " & Fmt2 (Pct));
                  end if;
                  Append (Line, " " & Fmt2 (RP) & " " & Fmt2 (CP));
               end;
            end loop;
            Append (Line, " " & Trim (Row_Tot'Image, Both));
            IO.Put_Line (To_String (Line));
         end;
      end loop;
      --  Totals row
      declare
         T : Unbounded_String := To_Unbounded_String ("Total");
      begin
         for C of L2 loop
            Append (T, " " & Trim (C.Count'Image, Both));
         end loop;
         Append (T, " " & Trim (Grand'Image, Both));
         IO.Put_Line (To_String (T));
      end;
      if not Include_Missing and then Missing > 0 then
         IO.New_Line;
         IO.Put_Line ("Frequency Missing = " & Trim (Missing'Image, Both));
      end if;
   end Render_Two_Way_Grid;

   --  Build an R x C count matrix for /CHISQ (Task 10) directly from a
   --  Joint_Table so the matrix and the rendered grid are guaranteed to agree
   --  (same joint-derived levels, marginals, and cell counts; no spurious
   --  all-zero rows/cols from orphan levels).  Task 10 obtains L1/L2 labels
   --  from JT.L1/JT.L2 and the grand total from JT.Grand.
   function Build_Count_Matrix (JT : Joint_Table)
      return SData_Core.Statistics.Count_Matrix
   is
      M : SData_Core.Statistics.Count_Matrix
            (1 .. Natural (JT.L1.Length), 1 .. Natural (JT.L2.Length)) :=
              (others => (others => 0));
   begin
      for I in JT.L1.First_Index .. JT.L1.Last_Index loop
         for J in JT.L2.First_Index .. JT.L2.Last_Index loop
            declare
               Key : constant String := Cell_Key (I, J);
            begin
               if JT.Cells.Contains (Key) then
                  M (I, J) := JT.Cells (Key);
               end if;
            end;
         end loop;
      end loop;
      return M;
   end Build_Count_Matrix;

   --  Emit the 2-way chi-square family for V1 x V2 over Rows.  The tests are
   --  computed from the SAME joint-derived cells the grid/list renders (any
   --  partial-missing row already excluded by Build_Joint), so the statistics
   --  and the displayed table always agree on levels, marginals, and N.
   procedure Put_Chisq_2Way (Rows : Row_Index_Vectors.Vector; V1, V2 : String)
   is
      JT : constant Joint_Table := Build_Joint (Rows, V1, V2);
      M  : constant SData_Core.Statistics.Count_Matrix :=
        Build_Count_Matrix (JT);
      R  : constant SData_Core.Statistics.Chi_Square_Result :=
        SData_Core.Statistics.Chi_Square_Tests (M);
   begin
      IO.New_Line;
      IO.Put_Line ("Statistic DF Value Prob");
      if not R.Valid then
         IO.Put_Line
           ("(chi-square not computed: a row or column total is zero)");
         return;
      end if;
      IO.Put_Line ("Chi-Square " & Trim (R.DF'Image, Both) & " "
                   & Fmt4 (R.Pearson_Stat) & " " & Fmt4 (R.Pearson_P));
      IO.Put_Line ("Likelihood-Ratio_Chi-Square " & Trim (R.DF'Image, Both)
                   & " " & Fmt4 (R.LR_Stat) & " " & Fmt4 (R.LR_P));
      if R.Has_Yates then
         IO.Put_Line ("Continuity-Adj._Chi-Square 1 "
                      & Fmt4 (R.Yates_Stat) & " " & Fmt4 (R.Yates_P));
      end if;
      IO.Put_Line ("Mantel-Haenszel_Chi-Square 1 "
                   & Fmt4 (R.MH_Stat) & " " & Fmt4 (R.MH_P));
      IO.Put_Line ("Phi_Coefficient " & Fmt4 (R.Phi));
      IO.Put_Line ("Contingency_Coefficient " & Fmt4 (R.Contingency));
      IO.Put_Line ("Cramers_V " & Fmt4 (R.Cramers_V));
      IO.New_Line;
      IO.Put_Line ("Sample_Size = " & Trim (R.N'Image, Both));
      if R.Pct_Expected_Lt_5 > 20.0 then
         IO.Put_Line ("WARNING: over 20% of cells have expected count < 5; "
                      & "chi-square may be invalid.");
      end if;
   end Put_Chisq_2Way;

   --  Emit the one-way equal-proportions goodness-of-fit chi-square for Col.
   procedure Put_Chisq_1Way (Rows : Row_Index_Vectors.Vector; Col : String) is
      L   : constant Level_Vectors.Vector := Build_Levels (Rows, Col);
      V   : SData_Core.Statistics.Count_Vector (1 .. Natural (L.Length));
      Idx : Positive := 1;
   begin
      for Lv of L loop
         V (Idx) := Lv.Count;
         Idx := Idx + 1;
      end loop;
      declare
         R : constant SData_Core.Statistics.GOF_Result :=
           SData_Core.Statistics.Goodness_Of_Fit (V);
      begin
         IO.New_Line;
         IO.Put_Line ("Chi-Square Goodness-of-Fit (equal proportions)");
         if R.Valid then
            IO.Put_Line ("Chi-Square " & Trim (R.DF'Image, Both) & " "
                         & Fmt4 (R.Stat) & " " & Fmt4 (R.P));
         else
            IO.Put_Line ("(not computed: fewer than two categories)");
         end if;
      end;
   end Put_Chisq_1Way;

   --  Emit the BY-group header line, e.g. "----- BY G$=p -----", using the
   --  first physical row of the group to read each BY variable's value.
   procedure Put_By_Header (First_Phys : Positive) is
      H : Unbounded_String := To_Unbounded_String ("----- BY");
   begin
      for I in 1 .. SData_Core.Table.By_Var_Count loop
         Append (H, " " & SData_Core.Table.By_Var_Name (I) & "="
                 & Values.To_String_Formatted
                     (SData_Core.Table.Get_Value
                        (First_Phys, SData_Core.Table.By_Var_Name (I))));
      end loop;
      Append (H, " -----");
      IO.Put_Line (To_String (H));
   end Put_By_Header;

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

   --  List-form renderer: one row per observed combination of all K crossing
   --  variables.  Used for K>=3 (always) and K=2 with /LIST.
   procedure Render_List (Rows : Row_Index_Vectors.Vector;
                          Req  : Table_Request) is
      type Name_Arr is array (Positive range <>) of Unbounded_String;
      K : Natural := 0;
      C : Variable_List := Req.Vars;
      Show_Pct : constant Boolean := not Stmt.Table_NOPERCENT;
      Show_Cum : constant Boolean := not Stmt.Table_NOCUM;
   begin
      while C /= null loop K := K + 1; C := C.Next; end loop;
      declare
         Names   : Name_Arr (1 .. K);
         Levels  : array (1 .. K) of Level_Vectors.Vector;
         Pos     : array (1 .. K) of Count_Maps.Map;   --  Disp -> level index
         Joint   : Count_Maps.Map;
         Grand   : Natural := 0;
         Missing : Natural := 0;
      begin
         C := Req.Vars;
         for I in 1 .. K loop
            Names (I) := To_Unbounded_String
              (C.Var.Start_Name (1 .. C.Var.Start_Len));
            Levels (I) := Build_Levels (Rows, To_String (Names (I)));
            Pos (I)    := Index_Map (Levels (I));
            C := C.Next;
         end loop;
         --  Joint counts keyed on "i1|i2|...".
         for P of Rows loop
            declare
               Key : Unbounded_String;
               OK  : Boolean := True;
            begin
               for I in 1 .. K loop
                  declare
                     V : constant Values.Value :=
                       SData_Core.Table.Get_Value (P, To_String (Names (I)));
                     Ix : Natural;
                  begin
                     if not Is_Present (V, Include_Missing) then
                        OK := False; exit;
                     end if;
                     Ix := Pos (I)(To_String (Disp_Of (V)));
                     if I > 1 then Append (Key, "|"); end if;
                     Append (Key, Trim (Ix'Image, Both));
                  end;
               end loop;
               if OK then
                  if Joint.Contains (To_String (Key)) then
                     Joint.Replace (To_String (Key),
                                    Joint (To_String (Key)) + 1);
                  else
                     Joint.Insert (To_String (Key), 1);
                  end if;
                  Grand := Grand + 1;
               else
                  Missing := Missing + 1;
               end if;
            end;
         end loop;

         --  Title.
         declare
            T : Unbounded_String :=
              To_Unbounded_String ("Table of ") & Names (1);
         begin
            for I in 2 .. K loop
               Append (T, " by " & Names (I));
            end loop;
            IO.Put_Line (To_String (T));
         end;
         IO.New_Line;

         --  Header row.
         declare
            H : Unbounded_String;
         begin
            for I in 1 .. K loop
               Append (H, To_String (Names (I)) & " ");
            end loop;
            Append (H, "Frequency");
            if Show_Pct then Append (H, " Percent"); end if;
            if Show_Cum then Append (H, " Cum_Freq"); end if;
            if Show_Cum and then Show_Pct then Append (H, " Cum_Percent"); end if;
            IO.Put_Line (To_String (H));
         end;

         --  Enumerate tuples in value order via odometer walk over Levels.
         declare
            Cum  : Natural := 0;
            Idx  : array (1 .. K) of Positive := (others => 1);
            Done : Boolean :=
              (for some I in 1 .. K => Natural (Levels (I).Length) = 0);
         begin
            while not Done loop
               declare
                  Key : Unbounded_String;
               begin
                  for I in 1 .. K loop
                     if I > 1 then Append (Key, "|"); end if;
                     Append (Key, Trim (Idx (I)'Image, Both));
                  end loop;
                  if Joint.Contains (To_String (Key)) then
                     declare
                        F    : constant Natural := Joint (To_String (Key));
                        Line : Unbounded_String;
                        Pct  : constant Float :=
                          (if Grand = 0 then 0.0
                           else 100.0 * Float (F) / Float (Grand));
                     begin
                        Cum := Cum + F;
                        for I in 1 .. K loop
                           Append (Line,
                                   To_String (Levels (I)(Idx (I)).Disp) & " ");
                        end loop;
                        Append (Line, Trim (F'Image, Both));
                        if Show_Pct then
                           Append (Line, " " & Fmt2 (Pct));
                        end if;
                        if Show_Cum then
                           Append (Line, " " & Trim (Cum'Image, Both));
                        end if;
                        if Show_Cum and then Show_Pct then
                           Append (Line, " " &
                             Fmt2 (if Grand = 0 then 0.0
                                   else 100.0 * Float (Cum) / Float (Grand)));
                        end if;
                        IO.Put_Line (To_String (Line));
                     end;
                  end if;
                  --  Increment odometer (last index fastest) to keep value order.
                  declare
                     Carry : Integer := K;
                  begin
                     loop
                        if Idx (Carry) < Natural (Levels (Carry).Length) then
                           Idx (Carry) := Idx (Carry) + 1; exit;
                        else
                           Idx (Carry) := 1; Carry := Carry - 1;
                           if Carry = 0 then Done := True; exit; end if;
                        end if;
                     end loop;
                  end;
               end;
            end loop;
         end;

         if not Include_Missing and then Missing > 0 then
            IO.New_Line;
            IO.Put_Line ("Frequency Missing = " & Trim (Missing'Image, Both));
         end if;
      end;
   end Render_List;

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
         declare
            Col : constant String :=
              Req.Vars.Var.Start_Name (1 .. Req.Vars.Var.Start_Len);
         begin
            Render_One_Way (Rows, Col);
            if Stmt.Table_CHISQ then
               Put_Chisq_1Way (Rows, Col);
            end if;
         end;
      elsif K = 2 then
         declare
            V1 : constant String :=
              Req.Vars.Var.Start_Name (1 .. Req.Vars.Var.Start_Len);
            V2 : constant String :=
              Req.Vars.Next.Var.Start_Name (1 .. Req.Vars.Next.Var.Start_Len);
         begin
            --  Display (grid or /LIST) is independent of the statistics.
            if Stmt.Table_LIST then
               Render_List (Rows, Req);
            else
               Render_Two_Way_Grid (Rows, V1, V2);
            end if;
            if Stmt.Table_CHISQ then
               Put_Chisq_2Way (Rows, V1, V2);
            end if;
         end;
      else
         --  K >= 3: list-form rendering only.
         Render_List (Rows, Req);
         if Stmt.Table_CHISQ then
            IO.Put_Line ("TABLES: /CHISQ is not computed for tables of "
                         & "three or more variables");
         end if;
      end if;
   end Render_Request;

begin
   if Pending_Deferred > 0 then
      raise SData_Core.Script_Error with
        "TABLES: pending program statements exist; issue RUN or NEW first";
   end if;

   --  Validate every crossing variable up front -- before any output -- so a
   --  mistyped name raises a clean error instead of silently rendering an empty
   --  table (audit 2026-07-08 remediation #1). Mirrors the STATS/AGGREGATE
   --  Phase-1 unknown-variable check; the render path only ever uses Start_Name,
   --  so that is what we verify.
   declare
      Req : Table_Request := Stmt.Requests;
   begin
      while Req /= null loop
         declare
            V : Variable_List := Req.Vars;
         begin
            while V /= null loop
               declare
                  Col : constant String :=
                    V.Var.Start_Name (1 .. V.Var.Start_Len);
               begin
                  if not SData_Core.Table.Has_Column (Col) then
                     raise SData_Core.Script_Error with
                       "TABLES: unknown variable '" & Col & "'";
                  end if;
               end;
               V := V.Next;
            end loop;
         end;
         Req := Req.Next;
      end loop;
   end;

   --  Group_Boundaries rebuilds the SELECT filter map internally, so an active
   --  SELECT filter is honored with no separate Execute_Rebuild_Filter call.
   --  It is a read-only view/grouping query -- it does not mutate the table,
   --  PDV, SAVE, the SELECT expression, or BY -- so TABLES stays print-only.
   declare
      Groups      : constant SData_Core.Commands.Row_Group_Vectors.Vector :=
        SData_Core.Commands.Group_Boundaries;
      Multi_Group : constant Boolean :=
        SData_Core.Table.By_Var_Count > 0
          and then Natural (Groups.Length) > 1;
   begin
      for G of Groups loop
         if Multi_Group then
            Put_By_Header (G.First_Element);
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
