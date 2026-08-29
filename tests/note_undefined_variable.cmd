-- NOTE (ADR-059): an undefined variable is not NOTE's concern -- it's
-- neither a genuine temporary nor a permanent variable, so
-- Reject_If_Permanent doesn't touch it; Evaluate's own existing
-- undefined-name handling applies unchanged, exactly as it already does
-- for PRINT (renders as the missing-value marker, no crash).
NOTE UNDEFINEDVAR
QUIT
