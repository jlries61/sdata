--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

--  CSV tokenizer fuzz driver.
--
--  Reads arbitrary bytes from stdin and exercises every public function in
--  SData_Core.CSV.  Unexpected exceptions (Constraint_Error, Program_Error,
--  Storage_Error) propagate uncaught so that AFL++ or a crash-regression
--  harness can detect them.  Expected user-input errors (none defined for
--  the pure tokenizer layer) are also allowed to propagate.
--
--  AFL++ usage:
--    afl-fuzz -i tests/fuzz_corpus/csv -o fuzz_out/csv -- ./bin/csv_fuzz_driver
--
--  Corpus regression (no AFL++ required):
--    make fuzz-corpus

with Ada.Text_IO;           use Ada.Text_IO;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with SData_Core.CSV;             use SData_Core.CSV;
with SData_Core.Values;          use SData_Core.Values;

procedure CSV_Fuzz_Driver is

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

   --  Exercise every SData_Core.CSV function on a single string with a given delimiter.
   procedure Exercise (S : String; Delim : String) is
      Fields  : Field_Vectors.Vector;
      Dummy_B : Boolean;
      Dummy_F : Real;
      pragma Unreferenced (Dummy_B);
   begin
      if S'Length = 0 then return; end if;

      --  At_Delimiter and CSV_Field_End: boundary detection.
      Dummy_B := At_Delimiter (S, S'First, Delim);
      declare
         E : constant Natural := CSV_Field_End (S, S'First, Delim);
         pragma Unreferenced (E);
      begin null; end;

      --  Split_Indices: full tokenization pass.
      Split_Indices (S, Delim, Fields);

      --  Per-field exercises.
      for F of Fields loop
         declare
            Lo  : constant Natural :=
               (if F.S <= F.E then F.S else F.E);
            Hi  : constant Natural :=
               (if F.S <= F.E then F.E else F.S);
            Raw : constant String :=
               (if Lo >= S'First and then Hi <= S'Last
                then S (Lo .. Hi) else "");
         begin
            Dummy_B := Is_Numeric_Field (Raw);
            Dummy_B := Try_Fast_Float   (Raw, Dummy_F);
            declare
               Q : constant String := CSV_Unquote (Raw);
               pragma Unreferenced (Q);
            begin null; end;
         end;
      end loop;
   end Exercise;

   Input : constant String := Read_Stdin;

begin
   --  Exercise with the four delimiter styles supported by SData.
   Exercise (Input, ",");
   Exercise (Input, "|");
   Exercise (Input, "||");
   Exercise (Input, (1 => ASCII.HT));

   --  Also exercise each individual line so single-line seeds are effective.
   declare
      Start : Positive := (if Input'Length > 0 then Input'First else 1);
      NL    : Natural;
   begin
      while Start <= Input'Last loop
         NL := Start;
         while NL <= Input'Last and then Input (NL) /= ASCII.LF loop
            NL := NL + 1;
         end loop;
         if NL > Start then
            Exercise (Input (Start .. NL - 1), ",");
         end if;
         Start := NL + 1;
      end loop;
   end;
end CSV_Fuzz_Driver;