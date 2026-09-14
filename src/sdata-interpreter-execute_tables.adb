separate (SData.Interpreter)
procedure Execute_Tables (Stmt : Statement_Access) is
   package Values renames SData_Core.Values;
   package IO     renames SData_Core.IO;
   use Ada.Strings;
   use Ada.Strings.Fixed;

   --  Two-decimal float formatter (e.g. 50.00).
   function Fmt2 (X : Real) return String is
      package F_IO is new Ada.Text_IO.Float_IO (Real);
      Buf : String (1 .. 32);
   begin
      F_IO.Put (Buf, X, Aft => 2, Exp => 0);
      return Trim (Buf, Both);
   end Fmt2;

   --  Four-decimal float formatter (e.g. 0.6667) for /CHISQ statistics.
   function Fmt4 (X : Real) return String is
      package F_IO is new Ada.Text_IO.Float_IO (Real);
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

   function As_Real (V : Values.Value) return Real is
     (if V.Kind = Values.Val_Integer then Real (V.Int_Val) else V.Num_Val);

   --  Value-order comparison for two levels.
   function Level_Less (A, B : Level) return Boolean is
   begin
      if Numeric (A.Val) and then Numeric (B.Val) then
         return As_Real (A.Val) < As_Real (B.Val);
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

   --  /SAVE (ADR-071).  Save_Active implies exactly one request (parser
   --  enforces).  Chisq_Buf accumulates one row per computed chi-square
   --  statistic per BY group -- deferred (not written via the Output_*
   --  staging API until after the whole group loop) because the main
   --  crosstab table occupies that same single staging area while the
   --  group loop runs; First_Phys lets the BY-var values be re-read from
   --  the (untouched) real table afterward, the same way Put_By_Header
   --  already does.
   Save_Active : constant Boolean := Stmt.Table_Save_Len > 0;
   type Chisq_Buf_Row is record
      First_Phys : Positive;
      Statistic  : Unbounded_String;
      Has_DF     : Boolean;
      DF         : Natural;
      Stat_Value : Real;
      Has_Prob   : Boolean;
      Prob       : Real;
   end record;
   package Chisq_Buf_Vectors is new Ada.Containers.Vectors (Positive, Chisq_Buf_Row);
   Chisq_Buf : Chisq_Buf_Vectors.Vector;

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
                  Pct : constant Real :=
                    (if Grand = 0 then 0.0
                     else 100.0 * Real (F) / Real (Grand));
                  RP  : constant Real :=
                    (if L1 (I).Count = 0 then 0.0
                     else 100.0 * Real (F) / Real (L1 (I).Count));
                  CP  : constant Real :=
                    (if L2 (J).Count = 0 then 0.0
                     else 100.0 * Real (F) / Real (L2 (J).Count));
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

   -----------------------------------------------------------------
   --  /SAVE support (ADR-071) -- builds an Output_* staging table
   --  from the same counting-engine primitives the printers above use,
   --  and buffers chi-square statistic rows for a deferred second write.
   -----------------------------------------------------------------

   --  Insert "_chisq" before the last '.' extension in Full (matching the
   --  directory-boundary-aware scan Full_Path's own Has_Extension uses),
   --  or append it at the end if Full has no extension.
   function Derive_Chisq_Name (Full : String) return String is
   begin
      for I in reverse Full'Range loop
         if Full (I) = '.' then
            return Full (Full'First .. I - 1) & "_chisq" & Full (I .. Full'Last);
         elsif Full (I) = '/' or else Full (I) = '\' then
            exit;
         end if;
      end loop;
      return Full & "_chisq";
   end Derive_Chisq_Name;

   --  True if Reserved (a /SAVE-computed column name: FREQUENCY, PERCENT,
   --  CUM_FREQ, CUM_PERCENT, STATISTIC$, DF, VALUE, or PROB) matches an
   --  active BY variable's name, or (when Req /= null) one of Req's own
   --  crossing variable names -- case-insensitively, matching how
   --  SData_Core.Table.Add_Output_Column's own key canonicalization would
   --  otherwise silently treat them as the same column (see BLOCKER-1,
   --  04-code-review.md: Add_Output_Column no-ops on an existing name, so
   --  an unguarded collision here does not raise -- it silently drops the
   --  reserved column and lets the crossing/BY variable's own later write
   --  clobber the computed value, or vice versa).  Req is null for
   --  Write_Chisq_Save_File's schema, which has no crossing variables of
   --  its own to check.
   function Reserved_Name_Collision
     (Reserved : String; Req : Table_Request) return Boolean
   is
      Up : constant String := To_Upper (Reserved);
   begin
      for I in 1 .. SData_Core.Table.By_Var_Count loop
         if To_Upper (SData_Core.Table.By_Var_Name (I)) = Up then
            return True;
         end if;
      end loop;
      if Req /= null then
         declare
            C : Variable_List := Req.Vars;
         begin
            while C /= null loop
               if To_Upper (C.Var.Start_Name (1 .. C.Var.Start_Len)) = Up then
                  return True;
               end if;
               C := C.Next;
            end loop;
         end;
      end if;
      return False;
   end Reserved_Name_Collision;

   --  Raises a clear, actionable error for a reserved-name collision
   --  (BLOCKER-1's fix: loud failure instead of Add_Output_Column's own
   --  silent no-op, matching this project's established preference --
   --  e.g. the Output_Is_Spilled guard earlier in this same file, and
   --  ADR-0021's CHARSET hard-fail before it).
   procedure Check_Reserved_Name (Name : String; Req : Table_Request) is
   begin
      if Reserved_Name_Collision (Name, Req) then
         raise SData_Core.Script_Error with
           "TABLES: /SAVE column name '" & Name & "' collides with a BY "
           & "or crossing variable of the same name -- rename the "
           & "variable, or drop the option that would add this column "
           & "(e.g. /NOCUM, /NOPERCENT)";
      end if;
   end Check_Reserved_Name;

   --  Declares the Output_* staging schema for the /SAVE crosstab dataset:
   --  active BY vars, then the (single, parser-enforced) request's
   --  crossing variable(s), then Frequency/[Percent]/[Cum_Freq]/
   --  [Cum_Percent] -- the same column set /NOCUM//NOPERCENT would leave
   --  in the printed list-form report (00-brief.md decision 3, revised).
   procedure Init_Save_Schema (Req : Table_Request) is
   begin
      SData_Core.Table.Initialize_Output_Table;
      for I in 1 .. SData_Core.Table.By_Var_Count loop
         declare
            Nm : constant String := SData_Core.Table.By_Var_Name (I);
         begin
            SData_Core.Table.Add_Output_Column
              (Nm, SData_Core.Table.Get_Column_Type (Nm));
         end;
      end loop;
      declare
         C : Variable_List := Req.Vars;
      begin
         while C /= null loop
            declare
               Nm : constant String :=
                 C.Var.Start_Name (1 .. C.Var.Start_Len);
            begin
               SData_Core.Table.Add_Output_Column
                 (Nm, SData_Core.Table.Get_Column_Type (Nm));
            end;
            C := C.Next;
         end loop;
      end;
      Check_Reserved_Name ("FREQUENCY", Req);
      SData_Core.Table.Add_Output_Column
        ("FREQUENCY", SData_Core.Table.Col_Integer);
      if not Stmt.Table_NOPERCENT then
         Check_Reserved_Name ("PERCENT", Req);
         SData_Core.Table.Add_Output_Column
           ("PERCENT", SData_Core.Table.Col_Numeric);
      end if;
      if not Stmt.Table_NOCUM then
         Check_Reserved_Name ("CUM_FREQ", Req);
         SData_Core.Table.Add_Output_Column
           ("CUM_FREQ", SData_Core.Table.Col_Integer);
         if not Stmt.Table_NOPERCENT then
            Check_Reserved_Name ("CUM_PERCENT", Req);
            SData_Core.Table.Add_Output_Column
              ("CUM_PERCENT", SData_Core.Table.Col_Numeric);
         end if;
      end if;
   end Init_Save_Schema;

   --  Appends one Output_* row per observed combination for this group,
   --  to the schema Init_Save_Schema already declared.  Deliberately a
   --  near-duplicate of Render_List's tuple-enumeration (rather than a
   --  refactor of it to also return data) -- Render_List's job is
   --  formatted text, this procedure's is a dataset; keeping them
   --  separate avoids entangling two different concerns in one function.
   procedure Save_Request_Rows (Rows : Row_Index_Vectors.Vector; Req : Table_Request) is
      type Name_Arr is array (Positive range <>) of Unbounded_String;
      K          : Natural := 0;
      C          : Variable_List := Req.Vars;
      First_Phys : constant Positive := Rows.First_Element;
   begin
      while C /= null loop K := K + 1; C := C.Next; end loop;
      declare
         Names  : Name_Arr (1 .. K);
         Levels : array (1 .. K) of Level_Vectors.Vector;
         Pos    : array (1 .. K) of Count_Maps.Map;
         Seen   : Count_Maps.Map;
         Grand  : Natural := 0;

         type Idx_Array is array (1 .. K) of Positive;
         type Tuple_Rec is record
            Idx   : Idx_Array;
            Count : Natural;
         end record;
         package Tuple_Vectors is new Ada.Containers.Vectors (Positive, Tuple_Rec);
         Present : Tuple_Vectors.Vector;

         function Tuple_Less (A, B : Tuple_Rec) return Boolean is
         begin
            for I in 1 .. K loop
               if A.Idx (I) /= B.Idx (I) then
                  return A.Idx (I) < B.Idx (I);
               end if;
            end loop;
            return False;
         end Tuple_Less;
         package Tuple_Sorting is new Tuple_Vectors.Generic_Sorting ("<" => Tuple_Less);
      begin
         C := Req.Vars;
         for I in 1 .. K loop
            Names (I) := To_Unbounded_String
              (C.Var.Start_Name (1 .. C.Var.Start_Len));
            Levels (I) := Build_Levels (Rows, To_String (Names (I)));
            Pos (I)    := Index_Map (Levels (I));
            C := C.Next;
         end loop;

         for P of Rows loop
            declare
               Key : Unbounded_String;
               Tup : Idx_Array;
               OK  : Boolean := True;
            begin
               for I in 1 .. K loop
                  declare
                     V : constant Values.Value :=
                       SData_Core.Table.Get_Value (P, To_String (Names (I)));
                  begin
                     if not Is_Present (V, Include_Missing) then
                        OK := False; exit;
                     end if;
                     Tup (I) := Pos (I)(To_String (Disp_Of (V)));
                     if I > 1 then Append (Key, "|"); end if;
                     Append (Key, Trim (Tup (I)'Image, Both));
                  end;
               end loop;
               if OK then
                  declare
                     Ks : constant String := To_String (Key);
                  begin
                     if Seen.Contains (Ks) then
                        declare
                           R : Tuple_Rec := Present (Seen (Ks));
                        begin
                           R.Count := R.Count + 1;
                           Present.Replace_Element (Seen (Ks), R);
                        end;
                     else
                        Present.Append ((Idx => Tup, Count => 1));
                        Seen.Insert (Ks, Present.Last_Index);
                     end if;
                  end;
                  Grand := Grand + 1;
               end if;
            end;
         end loop;

         Tuple_Sorting.Sort (Present);
         declare
            Cum : Natural := 0;
         begin
            for R of Present loop
               declare
                  F       : constant Natural := R.Count;
                  Pct     : constant Real :=
                    (if Grand = 0 then 0.0 else 100.0 * Real (F) / Real (Grand));
                  Out_Row : Positive;
               begin
                  Cum := Cum + F;
                  SData_Core.Table.Add_Output_Row;
                  Out_Row := SData_Core.Table.Output_Row_Count;
                  for BI in 1 .. SData_Core.Table.By_Var_Count loop
                     declare
                        BNm : constant String := SData_Core.Table.By_Var_Name (BI);
                     begin
                        SData_Core.Table.Set_Output_Value
                          (Out_Row, BNm,
                           SData_Core.Table.Get_Value (First_Phys, BNm));
                     end;
                  end loop;
                  for I in 1 .. K loop
                     SData_Core.Table.Set_Output_Value
                       (Out_Row, To_String (Names (I)), Levels (I)(R.Idx (I)).Val);
                  end loop;
                  SData_Core.Table.Set_Output_Value
                    (Out_Row, "FREQUENCY",
                     (Kind => Values.Val_Integer, Int_Val => Values.Int (F)));
                  if not Stmt.Table_NOPERCENT then
                     SData_Core.Table.Set_Output_Value
                       (Out_Row, "PERCENT",
                        (Kind => Values.Val_Numeric, Num_Val => Pct));
                  end if;
                  if not Stmt.Table_NOCUM then
                     SData_Core.Table.Set_Output_Value
                       (Out_Row, "CUM_FREQ",
                        (Kind => Values.Val_Integer, Int_Val => Values.Int (Cum)));
                     if not Stmt.Table_NOPERCENT then
                        SData_Core.Table.Set_Output_Value
                          (Out_Row, "CUM_PERCENT",
                           (Kind => Values.Val_Numeric,
                            Num_Val =>
                              (if Grand = 0 then 0.0
                               else 100.0 * Real (Cum) / Real (Grand))));
                     end if;
                  end if;
               end;
            end loop;
         end;
      end;
   end Save_Request_Rows;

   --  Buffers the same one-way goodness-of-fit chi-square Put_Chisq_1Way
   --  prints, for this group -- computed a second time rather than shared
   --  with the printer, deliberately: TABLES is not a hot path, and
   --  keeping "what prints" and "what /SAVE writes" as two independent
   --  computations avoids entangling the print path with /SAVE's schema.
   procedure Save_Chisq_1Way (Rows : Row_Index_Vectors.Vector; Col : String) is
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
         if R.Valid then
            Chisq_Buf.Append
              ((First_Phys => Rows.First_Element,
                Statistic  => To_Unbounded_String ("Chi-Square"),
                Has_DF     => True, DF => R.DF,
                Stat_Value => R.Stat,
                Has_Prob   => True, Prob => R.P));
         end if;
      end;
   end Save_Chisq_1Way;

   --  Buffers the same chi-square family Put_Chisq_2Way prints, for this
   --  group.  See Save_Chisq_1Way for why this duplicates the computation
   --  rather than sharing it with the printer.
   procedure Save_Chisq_2Way (Rows : Row_Index_Vectors.Vector; V1, V2 : String) is
      JT : constant Joint_Table := Build_Joint (Rows, V1, V2);
      M  : constant SData_Core.Statistics.Count_Matrix := Build_Count_Matrix (JT);
      R  : constant SData_Core.Statistics.Chi_Square_Result :=
        SData_Core.Statistics.Chi_Square_Tests (M);
      FP : constant Positive := Rows.First_Element;

      procedure Add (Name : String; Has_DF : Boolean; DF : Natural;
                     Stat_Value : Real; Has_Prob : Boolean; Prob : Real) is
      begin
         Chisq_Buf.Append
           ((First_Phys => FP, Statistic => To_Unbounded_String (Name),
             Has_DF => Has_DF, DF => DF, Stat_Value => Stat_Value,
             Has_Prob => Has_Prob, Prob => Prob));
      end Add;
   begin
      if not R.Valid then
         return;
      end if;
      Add ("Chi-Square", True, R.DF, R.Pearson_Stat, True, R.Pearson_P);
      Add ("Likelihood-Ratio_Chi-Square", True, R.DF, R.LR_Stat, True, R.LR_P);
      if R.Has_Yates then
         Add ("Continuity-Adj._Chi-Square", True, 1, R.Yates_Stat, True, R.Yates_P);
      end if;
      Add ("Mantel-Haenszel_Chi-Square", True, 1, R.MH_Stat, True, R.MH_P);
      Add ("Phi_Coefficient", False, 0, R.Phi, False, 0.0);
      Add ("Contingency_Coefficient", False, 0, R.Contingency, False, 0.0);
      Add ("Cramers_V", False, 0, R.Cramers_V, False, 0.0);
      Add ("Sample_Size", False, 0, Real (R.N), False, 0.0);
   end Save_Chisq_2Way;

   --  Builds the second Output_* staging table from Chisq_Buf (BY vars +
   --  Statistic$ + DF + Value + Prob, one row per buffered statistic) and
   --  writes it via Open_Output.  Called once, after the main crosstab has
   --  already been fully written -- see the two-pass note at the main
   --  /SAVE dispatch below.
   procedure Write_Chisq_Save_File (File_Name : String) is
   begin
      if Chisq_Buf.Is_Empty then
         return;
      end if;
      SData_Core.Table.Initialize_Output_Table;
      for I in 1 .. SData_Core.Table.By_Var_Count loop
         declare
            Nm : constant String := SData_Core.Table.By_Var_Name (I);
         begin
            SData_Core.Table.Add_Output_Column
              (Nm, SData_Core.Table.Get_Column_Type (Nm));
         end;
      end loop;
      Check_Reserved_Name ("STATISTIC$", null);
      SData_Core.Table.Add_Output_Column ("STATISTIC$", SData_Core.Table.Col_String);
      Check_Reserved_Name ("DF", null);
      SData_Core.Table.Add_Output_Column ("DF", SData_Core.Table.Col_Integer);
      Check_Reserved_Name ("VALUE", null);
      SData_Core.Table.Add_Output_Column ("VALUE", SData_Core.Table.Col_Numeric);
      Check_Reserved_Name ("PROB", null);
      SData_Core.Table.Add_Output_Column ("PROB", SData_Core.Table.Col_Numeric);
      for Row of Chisq_Buf loop
         declare
            Out_Row : Positive;
         begin
            SData_Core.Table.Add_Output_Row;
            Out_Row := SData_Core.Table.Output_Row_Count;
            for BI in 1 .. SData_Core.Table.By_Var_Count loop
               declare
                  BNm : constant String := SData_Core.Table.By_Var_Name (BI);
               begin
                  SData_Core.Table.Set_Output_Value
                    (Out_Row, BNm,
                     SData_Core.Table.Get_Value (Row.First_Phys, BNm));
               end;
            end loop;
            SData_Core.Table.Set_Output_Value
              (Out_Row, "STATISTIC$",
               (Kind => Values.Val_String, Str_Val => Row.Statistic));
            if Row.Has_DF then
               SData_Core.Table.Set_Output_Value
                 (Out_Row, "DF",
                  (Kind => Values.Val_Integer, Int_Val => Values.Int (Row.DF)));
            else
               SData_Core.Table.Set_Output_Value
                 (Out_Row, "DF", (Kind => Values.Val_Missing));
            end if;
            SData_Core.Table.Set_Output_Value
              (Out_Row, "VALUE",
               (Kind => Values.Val_Numeric, Num_Val => Row.Stat_Value));
            if Row.Has_Prob then
               SData_Core.Table.Set_Output_Value
                 (Out_Row, "PROB",
                  (Kind => Values.Val_Numeric, Num_Val => Row.Prob));
            else
               SData_Core.Table.Set_Output_Value
                 (Out_Row, "PROB", (Kind => Values.Val_Missing));
            end if;
         end;
      end loop;
      if SData_Core.Table.Output_Is_Spilled then
         raise SData_Core.Script_Error with
           "TABLES: /SAVE not supported -- the /CHISQ statistics result is "
           & "too large (exceeds the configured spill threshold)";
      end if;
      begin
         SData_Core.File_IO.Open_Output
           (File_Name => File_Name,
            Fmt        => Stmt.Table_Save_Fmt,
            Delimiter  => (if Stmt.Table_Save_DLM_Len > 0
                           then Stmt.Table_Save_DLM (1 .. Stmt.Table_Save_DLM_Len)
                           else ","),
            Write_Header => Stmt.Table_Save_Header,
            Allow_Overwrite => SData_Core.Config.Runtime.Options_SAVEOVERWRT,
            Charset      => (if Stmt.Table_Save_Charset_Len > 0
                             then Stmt.Table_Save_Charset (1 .. Stmt.Table_Save_Charset_Len)
                             else ""),
            Decimals     => (if Stmt.Table_Save_Decimals_Specified
                             then Stmt.Table_Save_Decimals else -1),
            View         => SData_Core.Table.Output_View);
      exception
         --  Write_CSV already prints "SAVE aborted -- file already exists:
         --  ..." before raising -- swallow here rather than let it surface a
         --  second, unhandled-exception-shaped message, matching the SAVE
         --  command's own call sites (sdata-interpreter.adb, sdata_core-
         --  commands.adb).
         when SData_Core.File_IO.Save_Refused => null;
      end;
   end Write_Chisq_Save_File;

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
            Pct  : constant Real :=
              (if Total = 0 then 0.0
               else 100.0 * Real (L.Count) / Real (Total));
            CPct : constant Real :=
              (if Total = 0 then 0.0
               else 100.0 * Real (Cum) / Real (Total));
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
         Seen    : Count_Maps.Map;   --  "i1|..|iK" -> 1-based position in Present
         Grand   : Natural := 0;
         Missing : Natural := 0;

         --  One OBSERVED K-tuple of level indices with its frequency.  We
         --  enumerate only observed combinations (<= Grand of them), never the
         --  full Cartesian product of level cardinalities.
         type Idx_Array is array (1 .. K) of Positive;
         type Tuple_Rec is record
            Idx   : Idx_Array;
            Count : Natural;
         end record;
         package Tuple_Vectors is new
           Ada.Containers.Vectors (Positive, Tuple_Rec);
         Present : Tuple_Vectors.Vector;

         --  The old odometer walked tuples in lexicographic order of the
         --  level-index vector (position 1 most significant).  Sorting the
         --  observed tuples the same way reproduces that output exactly.
         function Tuple_Less (A, B : Tuple_Rec) return Boolean is
         begin
            for I in 1 .. K loop
               if A.Idx (I) /= B.Idx (I) then
                  return A.Idx (I) < B.Idx (I);
               end if;
            end loop;
            return False;
         end Tuple_Less;
         package Tuple_Sorting is new
           Tuple_Vectors.Generic_Sorting ("<" => Tuple_Less);
      begin
         C := Req.Vars;
         for I in 1 .. K loop
            Names (I) := To_Unbounded_String
              (C.Var.Start_Name (1 .. C.Var.Start_Len));
            Levels (I) := Build_Levels (Rows, To_String (Names (I)));
            Pos (I)    := Index_Map (Levels (I));
            C := C.Next;
         end loop;
         --  Accumulate one entry per DISTINCT observed tuple, keyed on the
         --  "i1|i2|..." level-index string (Seen -> position in Present).
         for P of Rows loop
            declare
               Key : Unbounded_String;
               Tup : Idx_Array;
               OK  : Boolean := True;
            begin
               for I in 1 .. K loop
                  declare
                     V : constant Values.Value :=
                       SData_Core.Table.Get_Value (P, To_String (Names (I)));
                  begin
                     if not Is_Present (V, Include_Missing) then
                        OK := False; exit;
                     end if;
                     Tup (I) := Pos (I)(To_String (Disp_Of (V)));
                     if I > 1 then Append (Key, "|"); end if;
                     Append (Key, Trim (Tup (I)'Image, Both));
                  end;
               end loop;
               if OK then
                  declare
                     Ks : constant String := To_String (Key);
                  begin
                     if Seen.Contains (Ks) then
                        declare
                           R : Tuple_Rec := Present (Seen (Ks));
                        begin
                           R.Count := R.Count + 1;
                           Present.Replace_Element (Seen (Ks), R);
                        end;
                     else
                        Present.Append ((Idx => Tup, Count => 1));
                        Seen.Insert (Ks, Present.Last_Index);
                     end if;
                  end;
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

         --  Emit observed tuples in value order (Tuple_Less == the old odometer
         --  order).  Cost is O(Present * log Present), never the Cartesian
         --  product of level cardinalities.
         Tuple_Sorting.Sort (Present);
         declare
            Cum : Natural := 0;
         begin
            for R of Present loop
               declare
                  F    : constant Natural := R.Count;
                  Line : Unbounded_String;
                  Pct  : constant Real :=
                    (if Grand = 0 then 0.0
                     else 100.0 * Real (F) / Real (Grand));
               begin
                  Cum := Cum + F;
                  for I in 1 .. K loop
                     Append (Line,
                             To_String (Levels (I)(R.Idx (I)).Disp) & " ");
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
                             else 100.0 * Real (Cum) / Real (Grand)));
                  end if;
                  IO.Put_Line (To_String (Line));
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
               if Save_Active then
                  Save_Chisq_1Way (Rows, Col);
               end if;
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
               if Save_Active then
                  Save_Chisq_2Way (Rows, V1, V2);
               end if;
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

   --  /SAVE (ADR-071): declare the Output_* staging schema once, before the
   --  group loop, so every group's rows accumulate into the same table
   --  (matching STATS/AGGREGATE's own "one combined output table" BY
   --  convention) -- Stmt.Table_Save_Len > 0 implies exactly one request
   --  (parser-enforced), so Stmt.Requests names it unambiguously.
   if Save_Active then
      Init_Save_Schema (Stmt.Requests);
   end if;

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
               if Save_Active then
                  Save_Request_Rows (G, Req);
               end if;
               IO.New_Line;
               Req := Req.Next;
            end loop;
         end;
      end loop;
   end;

   --  /SAVE (ADR-071): write the accumulated crosstab now that every group
   --  has been processed, then -- a second, independent pass, since the
   --  single Output_* staging area cannot hold both tables at once -- the
   --  /CHISQ statistics file if one was requested and any group actually
   --  produced a computed (R.Valid) statistic.  Neither write disturbs
   --  Data_Table (SData_Core.Table.Table_View, ADR-071): TABLES stays
   --  print-only.
   if Save_Active then
      if SData_Core.Table.Output_Is_Spilled then
         raise SData_Core.Script_Error with
           "TABLES: /SAVE not supported -- the crosstab result is too "
           & "large (exceeds the configured spill threshold)";
      end if;
      declare
         Full_Save  : constant String :=
           Full_Path (Stmt.Table_Save_File (1 .. Stmt.Table_Save_Len), "SAVE");
         Main_Saved : Boolean := False;
      begin
         begin
            SData_Core.File_IO.Open_Output
              (File_Name => Full_Save,
               Fmt        => Stmt.Table_Save_Fmt,
               Delimiter  => (if Stmt.Table_Save_DLM_Len > 0
                              then Stmt.Table_Save_DLM (1 .. Stmt.Table_Save_DLM_Len)
                              else ","),
               Write_Header => Stmt.Table_Save_Header,
               Allow_Overwrite => SData_Core.Config.Runtime.Options_SAVEOVERWRT,
               Charset      => (if Stmt.Table_Save_Charset_Len > 0
                                then Stmt.Table_Save_Charset
                                       (1 .. Stmt.Table_Save_Charset_Len)
                                else ""),
               Decimals     => (if Stmt.Table_Save_Decimals_Specified
                                then Stmt.Table_Save_Decimals else -1),
               View         => SData_Core.Table.Output_View);
            Main_Saved := True;
         exception
            --  Write_CSV already prints "SAVE aborted -- file already
            --  exists: ..." before raising -- swallow here rather than let
            --  it surface a second, unhandled-exception-shaped message,
            --  matching the SAVE command's own call sites.  Main_Saved
            --  stays False, so the /CHISQ file (below) is skipped too --
            --  a refused main write means /SAVE as a whole did not happen.
            when SData_Core.File_IO.Save_Refused => null;
         end;

         if Main_Saved
           and then Stmt.Table_CHISQ
           and then not Chisq_Buf.Is_Empty
         then
            declare
               Chisq_Name : constant String :=
                 (if Stmt.Table_Chisq_File_Len > 0
                  then Full_Path
                         (Stmt.Table_Chisq_File (1 .. Stmt.Table_Chisq_File_Len),
                          "SAVE")
                  else Derive_Chisq_Name (Full_Save));
            begin
               Write_Chisq_Save_File (Chisq_Name);
            end;
         end if;
      end;
   end if;

   IO.Put_Line ("TABLES complete.");
end Execute_Tables;
