--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

--  SData merge / RENAME execution fuzz driver.
--
--  Reads arbitrary bytes from stdin and deterministically derives a small
--  multi-dataset merge scenario: 2-4 transient tables, each with 1-4 typed
--  columns (numeric / integer / character, names shared across tables so the
--  combiners actually collide and match) and 0-4 rows of byte-derived values,
--  plus a per-table RENAME map.  It then exercises
--  Transient_Table.Apply_Rename / Sort_By and every SData.Merge combiner
--  (Positional / Match / Interleave / Join / Append) -- the ~886-line merge
--  path the standards audit (§6.2) flagged as having no fuzz coverage.
--
--  Expected domain errors (Rename_Error, Script_Error) are caught.  Unexpected
--  exceptions (Constraint_Error, Program_Error, Storage_Error) propagate
--  uncaught so that AFL++ or the corpus regression detects them as crashes.
--
--  AFL++ usage:
--    afl-fuzz -i tests/fuzz_corpus/merge -o fuzz_out/merge \
--             -- ./bin/merge_fuzz_driver
--
--  Corpus regression (no AFL++ required):
--    make fuzz-corpus

with Ada.Text_IO;            use Ada.Text_IO;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Unchecked_Deallocation;
with SData;
with SData_Core;
with SData_Core.Table;
with SData_Core.Values;
with SData.Transient_Table;
with SData.Merge;

procedure Merge_Fuzz_Driver is

   package TT renames SData.Transient_Table;
   package MG renames SData.Merge;

   function Read_Stdin return String is
      Buf  : Unbounded_String;
      Line : String (1 .. 65_536);
      Last : Natural;
   begin
      loop
         Get_Line (Line, Last);
         Append (Buf, Line (1 .. Last));
         Append (Buf, ASCII.LF);
      end loop;
   exception
      when End_Error => return To_String (Buf);
   end Read_Stdin;

   Data : constant String := Read_Stdin;
   Pos  : Natural := Data'First;
   Sink : Natural := 0;

   --  Next byte (0 .. 255) from the stream; 0 once exhausted.
   function B return Natural is
      V : Natural;
   begin
      if Pos > Data'Last then
         return 0;
      end if;
      V := Character'Pos (Data (Pos));
      Pos := Pos + 1;
      return V;
   end B;

   procedure Free is
      new Ada.Unchecked_Deallocation (TT.Table, MG.Table_Access);

   --  Column name by index.  Names are shared across tables (K0, K1, ...) so
   --  the combiners see real same-name columns to reconcile / match on.
   function Col_Name (I : Natural) return String is
      ("K" & Character'Val (Character'Pos ('0') + (I mod 10)));

   --  Build one transient table from the byte stream.
   function Build_Table return MG.Table_Access is
      T      : constant MG.Table_Access := new TT.Table;
      N_Cols : constant Natural := 1 + (B mod 4);   --  1 .. 4
      N_Rows : constant Natural := B mod 5;         --  0 .. 4
   begin
      for C in 0 .. N_Cols - 1 loop
         declare
            Kind : constant Natural := B mod 3;
            Typ  : constant SData_Core.Table.Column_Type :=
               (case Kind is
                   when 0      => SData_Core.Table.Col_Numeric,
                   when 1      => SData_Core.Table.Col_Integer,
                   when others => SData_Core.Table.Col_String);
         begin
            if not T.Has_Column (Col_Name (C)) then
               T.Add_Column (Col_Name (C), Typ);
            end if;
         end;
      end loop;

      for R in 1 .. N_Rows loop
         T.Add_Row;
         for C in 0 .. N_Cols - 1 loop
            declare
               Name : constant String := Col_Name (C);
               Typ  : constant SData_Core.Table.Column_Type :=
                        T.Get_Column_Type (Name);
               Byte : constant Natural := B;
               Val  : SData_Core.Values.Value;
            begin
               case Typ is
                  when SData_Core.Table.Col_Numeric =>
                     Val := (Kind    => SData_Core.Values.Val_Numeric,
                             Num_Val => SData_Core.Values.Real (Byte));
                  when SData_Core.Table.Col_Integer =>
                     Val := (Kind    => SData_Core.Values.Val_Integer,
                             Int_Val => SData_Core.Values.Int (Byte));
                  when SData_Core.Table.Col_String =>
                     Val := (Kind    => SData_Core.Values.Val_String,
                             Str_Val => To_Unbounded_String
                                (String'(1 => Character'Val (32 + (Byte mod 95)))));
               end case;
               T.Set_Value (R, Name, Val);
            end;
         end loop;
      end loop;
      return T;
   end Build_Table;

   --  Build a fuzzed RENAME map and apply it to T (Rename_Error swallowed).
   --  New names may carry a "$" suffix to exercise the character-suffix
   --  rename-type rule and numeric/character-boundary validation.
   procedure Maybe_Rename (T : MG.Table_Access) is
      N     : constant Natural := B mod 3;   --  0 .. 2 pairs
      Pairs : TT.Rename_Map_Vectors.Vector;
   begin
      for I in 1 .. N loop
         declare
            Old_Idx : constant Natural := B mod 5;
            New_Idx : constant Natural := B mod 6;
            Suffix  : constant String := (if (B mod 2) = 0 then "" else "$");
         begin
            Pairs.Append
              ((Old_Name => To_Unbounded_String (Col_Name (Old_Idx)),
                New_Name => To_Unbounded_String
                   ("R" & Character'Val (Character'Pos ('0') + New_Idx)
                    & Suffix)));
         end;
      end loop;
      if not Pairs.Is_Empty then
         begin
            T.Apply_Rename (Pairs);
         exception
            when TT.Rename_Error => null;
         end;
      end if;
   end Maybe_Rename;

   --  Run one combiner, discarding the result (referenced via Sink so it is
   --  not flagged unused).  By_Vars is only meaningful for Match/Interleave/
   --  Join; Positional/Append ignore it.
   procedure Run_Combine
     (Mode : Natural; Inputs : MG.Table_Vectors.Vector;
      By_Names : TT.Name_Vectors.Vector)
   is
      W : MG.Warning_Vectors.Vector;
      P : MG.Provenance_Vectors.Vector;
      R : TT.Table;
   begin
      case Mode is
         when 0      => R := MG.Combine_Positional (Inputs, W, P);
         when 1      => R := MG.Combine_Match (Inputs, By_Names, W, P);
         when 2      => R := MG.Combine_Interleave (Inputs, By_Names, W, P);
         when 3      => R := MG.Combine_Join (Inputs, By_Names, W, P);
         when others => R := MG.Combine_Append (Inputs, W, P);
      end case;
      Sink := Sink + TT.Row_Count (R);
   exception
      when SData_Core.Script_Error | SData.Script_Error => null;
   end Run_Combine;

begin
   if Data'Length = 0 then
      return;
   end if;

   declare
      N_Tables : constant Natural := 2 + (B mod 3);   --  2 .. 4
      Inputs   : MG.Table_Vectors.Vector;
      By_Names : TT.Name_Vectors.Vector;
      BY_Ok    : Boolean := True;
   begin
      By_Names.Append (To_Unbounded_String (Col_Name (0)));  --  BY = K0

      for I in 1 .. N_Tables loop
         declare
            T : constant MG.Table_Access := Build_Table;
         begin
            Maybe_Rename (T);
            Inputs.Append (T);
         end;
      end loop;

      --  Match/Interleave/Join require the BY key present in every input and
      --  the inputs BY-sorted -- mirror the interpreter's precondition so the
      --  driver fuzzes the supported path rather than feeding the combiners an
      --  input the interpreter would have rejected up front.
      for T of Inputs loop
         if not T.Has_Column (To_String (By_Names.First_Element)) then
            BY_Ok := False;
         end if;
      end loop;
      if BY_Ok then
         for T of Inputs loop
            T.Sort_By (By_Names);
         end loop;
      end if;

      for Mode in 0 .. 4 loop
         if Mode = 0 or else Mode = 4 or else BY_Ok then
            Run_Combine (Mode, Inputs, By_Names);
         end if;
      end loop;

      for T of Inputs loop
         declare
            Tmp : MG.Table_Access := T;
         begin
            Free (Tmp);
         end;
      end loop;
   end;

   --  Reference Sink with a non-static guard so it is genuinely "used"
   --  without a constant-condition warning; the branch never fires.
   if Sink > Data'Length * 1_000_000 then
      Sink := 0;
   end if;
end Merge_Fuzz_Driver;
