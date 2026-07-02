--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Analyze_Deferred (Start, Boundary : Statement_Access) is

   --  Set of names introduced (LET/SET/FOR/DIM/ARRAY) within the deferred block.
   --  Whole-block scope: collected in Pass 1 so forward references are legal.
   Introduced : Name_Sets.Set;

   function U (S : String) return String renames To_Upper;

   --  A name is "defined" if it is a table column, a session variable, an
   --  array, or introduced anywhere in this deferred block (forward references
   --  are legal because we collect the full environment before any check runs).
   function Is_Defined (Name : String) return Boolean is
      Up : constant String := U (Name);
   begin
      return SData_Core.Table.Has_Column (Up)
        or else SData_Core.Variables.Has_Array (Up)
        or else SData_Core.Variables.Get_Type (Up) /= Val_Missing
        or else Introduced.Contains (Up);
   end Is_Defined;

   --  Forward declaration: Note_Introduced and Walk_Body are mutually recursive.
   procedure Note_Introduced (Stmt : Statement_Access);

   --  Walk the statement chain starting at Body_Start, recording each statement's
   --  introduced names.  Used to recurse into compound-statement bodies.
   procedure Walk_Body (Body_Start : Statement_Access) is
      S : Statement_Access := Body_Start;
   begin
      while S /= null loop
         Note_Introduced (S);
         S := S.Next;
      end loop;
   end Walk_Body;

   --  Record the name(s) introduced by Stmt and recurse into any sub-bodies so
   --  that names created by nested LET/SET/DIM/ARRAY/FOR are also collected.
   --  Mirrors the case structure of Free_Program (sdata-ast.adb).
   procedure Note_Introduced (Stmt : Statement_Access) is
   begin
      case Stmt.Kind is
         when Stmt_LET | Stmt_SET =>
            Introduced.Include (U (Stmt.Var_Name (1 .. Stmt.Var_Len)));
         when Stmt_FOR =>
            Introduced.Include (U (Stmt.For_Var (1 .. Stmt.For_Var_Len)));
            Walk_Body (Stmt.For_Body);
         when Stmt_DIM | Stmt_ARRAY =>
            if Stmt.Arr_Name_Len > 0 then
               Introduced.Include (U (Stmt.Arr_Name (1 .. Stmt.Arr_Name_Len)));
            end if;
         when Stmt_IF =>
            Walk_Body (Stmt.Then_Branch);
            Walk_Body (Stmt.Else_Branch);
         when Stmt_WHILE =>
            Walk_Body (Stmt.While_Body);
         when Stmt_LOOP_REPEAT =>
            Walk_Body (Stmt.Repeat_Body);
         when Stmt_SELECT =>
            declare
               Br : Case_Branch := Stmt.Branches;
            begin
               while Br /= null loop
                  Walk_Body (Br.Branch_Body);
                  Br := Br.Next;
               end loop;
            end;
            Walk_Body (Stmt.Otherwise_Part);
         when others => null;
      end case;
   end Note_Introduced;

   pragma Unreferenced (Is_Defined);
   --  Is_Defined is used by semantic checks added in Tasks C2-C5; suppress the
   --  unreferenced warning until the first check references it.

   Cur : Statement_Access;

begin
   if Start = null or else Start = Boundary then
      return;
   end if;

   --  Pass 1: collect introduced names (whole-block scope).
   Cur := Start;
   while Cur /= null and then Cur /= Boundary loop
      Note_Introduced (Cur);
      Cur := Cur.Next;
   end loop;

   --  Pass 2: run semantic checks (added in Tasks C2-C5).
   Cur := Start;
   while Cur /= null and then Cur /= Boundary loop
      --  Check hooks inserted here by later tasks.
      Cur := Cur.Next;
   end loop;
end Analyze_Deferred;
