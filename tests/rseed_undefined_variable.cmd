-- ADR-062/issue #76 regression: Check_Statement is called with
-- Check_Undefined => False for RSEED, so an undefined *variable* (as
-- opposed to an undefined *function*) in the seed expression is NOT
-- newly rejected -- Evaluate's own existing undefined-name handling
-- applies unchanged, exactly as it already does for PRINT's entry-time
-- check. Mirrors note_undefined_variable.cmd's pattern for NOTE.
RSEED UNDEFINEDVAR
QUIT
