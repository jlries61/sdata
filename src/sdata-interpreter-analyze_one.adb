--  Copyright (C) 2026 John L. Ries <john@theyarnbard.com>
--  License: GNU General Public License v3 or later
--  See LICENSE or <https://www.gnu.org/licenses/gpl-3.0.html>

separate (SData.Interpreter)
procedure Analyze_One (Stmt : Statement_Access) is

   --  Entry-time fast feedback (Task C5).  Runs the subset of semantic checks
   --  that are sound at the moment a single deferred statement is entered at
   --  the REPL:
   --    • Unknown-function + arity (C2)
   --    • Type-mismatch for scalar LET/SET targets (C3)
   --
   --  The undefined-variable check (C4) is intentionally OMITTED.  At entry
   --  time a name introduced by a LATER, not-yet-entered statement would be a
   --  false positive — forward references are legal within a deferred block.
   --  Undefined-var detection is exclusively the responsibility of the whole-
   --  block pass in Analyze_Deferred (called at RUN).
   --
   --  Arrays are NOT tracked via an "Introduced" set here: DIM/ARRAY are
   --  immediate commands in the REPL, so any live array is already registered
   --  in SData_Core.Variables.Has_Array by the time a subsequent LET can
   --  reference it.  Clearing the package-level Introduced set ensures
   --  Introduced.Contains is always False on this path — identical to omitting
   --  the batch-only guard, while Has_Array still covers live arrays.
   --
   --  The shared helper (Check_Statement, declared at package-body scope in
   --  sdata-interpreter.adb) handles both behaviours via Check_Undefined.

begin
   --  Ensure the package-level Introduced set is empty for the entry path so
   --  the Expr_Function_Call guard "Introduced.Contains(FN)" is always False
   --  here — equivalent to Analyze_One's original behaviour of omitting it.
   Introduced.Clear;
   Check_Statement (Stmt, Check_Undefined => False);
end Analyze_One;
