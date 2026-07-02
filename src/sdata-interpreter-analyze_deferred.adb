--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Analyze_Deferred (Start, Boundary : Statement_Access) is

   --  Companion: Analyze_One (sdata-interpreter-analyze_one.adb) runs the
   --  ENTRY-TIME subset of these checks (C2 + C3, no C4) on a single
   --  statement the moment it is entered at the REPL.  The two subunits share
   --  the same Check_Statement / Check_Expr helpers (declared at package-body
   --  scope in sdata-interpreter.adb); only the orchestration differs:
   --  Analyze_Deferred works over the whole deferred block (whole-block scope,
   --  forward refs collected in Pass 1), while Analyze_One operates on a
   --  single statement with an empty Introduced set (no forward-ref tracking).

   function U (S : String) return String renames To_Upper;

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
            --  ARRAY <name> v1 v2 ...  also introduces the constituent element
            --  variables (ARRAY SCORES S1 S2 S3 makes S1/S2/S3 referenceable as
            --  bare identifiers).  Record each simple (non-range) constituent so
            --  a later reference is not flagged undefined.  Range constituents
            --  (dash/colon) expand to existing columns, already covered by
            --  Has_Column, so they need no entry here.
            declare
               V : Variable_List := Stmt.Arr_Vars;
            begin
               while V /= null loop
                  if not V.Var.Is_Range
                    and then V.Var.Start_Len in 1 .. Max_Name_Len
                  then
                     Introduced.Include
                       (U (V.Var.Start_Name (1 .. V.Var.Start_Len)));
                  end if;
                  V := V.Next;
               end loop;
            end;
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

   Cur : Statement_Access;

begin
   if Start = null or else Start = Boundary then
      return;
   end if;

   --  Pass 1: collect introduced names (whole-block scope).
   --  Reset the package-level Introduced set so each call starts clean.
   Introduced.Clear;
   Cur := Start;
   while Cur /= null and then Cur /= Boundary loop
      Note_Introduced (Cur);
      Cur := Cur.Next;
   end loop;

   --  Pass 2: run semantic checks.  Task C2 adds the unknown-function and
   --  arity checks (via Check_Statement -> Check_Expr).  A violation raises
   --  SData_Core.Script_Error, which propagates out of Execute before any
   --  record is processed.
   Cur := Start;
   while Cur /= null and then Cur /= Boundary loop
      Check_Statement (Cur, Check_Undefined => True);
      Cur := Cur.Next;
   end loop;
end Analyze_Deferred;
