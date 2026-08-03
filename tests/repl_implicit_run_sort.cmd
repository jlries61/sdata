-- Issue #70 / ADR-055: this is the test that actually discriminates a
-- correct implementation from a naive one. A LET typed at the REPL prompt
-- is queued into Active_Program_Vec (invisible to a purely Step_Start-based
-- batch-style flush, since each REPL immediate command reaches
-- SData.Interpreter.Execute as a fresh singleton-statement call). The
-- implicit-RUN trigger for SORT must detect this via
-- Active_Program_Vec.Is_Empty and call Run_Active_Program -- not silently
-- skip the LET. If it did skip it, Z would never be created and SORT Z
-- would raise "undefined variable" instead of succeeding with 4 variables.
USE "tests/data/freq_select.csv"
LET Z = ID * -1
SORT Z
QUIT
