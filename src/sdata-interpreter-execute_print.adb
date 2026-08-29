--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Execute_Print (Stmt : Statement_Access) is
begin
   if Stmt.Print_Args = null then
      --  P16 (design-vs-implementation audit): bare PRINT must show "all
      --  currently defined permanent variables ... for current record"
      --  (design.md §6.2 / Help_PRINT) -- i.e. the PDV as it stands for
      --  this record right now, not SData_Core.Table.Column_Count, which
      --  only reflects the table's already-committed schema. A LET-created
      --  permanent variable exists in the PDV from the moment it's
      --  assigned, but the table only gains that column at the end of the
      --  whole RUN (Commit_Output_Table) -- querying the table here found
      --  0 columns for a fresh, USE-less step and printed nothing at all.
      declare
         PDV_List : GNAT.Strings.String_List_Access :=
                       SData_Core.Variables.Get_PDV_Names;
         PDV_N    : constant Natural :=
                       (if PDV_List = null then 0 else PDV_List.all'Length);
      begin
         if PDV_N > 0 then
            for I in 1 .. PDV_N loop
               declare
                  Name : constant String := PDV_List.all (I).all;
                  Val  : constant Value  :=
                            SData_Core.Variables.Get_PDV_Value (I);
               begin
                  Put (Name & ": " & To_String_Formatted (Val) & "  ");
               end;
            end loop;
            New_Line;
         end if;
         GNAT.Strings.Free (PDV_List);
      end;
   else
      Print_Value_List (Stmt.Print_Args);
   end if;
end Execute_Print;
