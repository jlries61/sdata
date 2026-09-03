-- PE-4 / ADR-061 (sdata-core ADR-0022): design.md's -q bullet claims
-- "(can be undone with ECHO ON)" -- this is the audit's own repro
-- (part-e-io-operators-implementation-notes.md), inverted into a regression
-- pin now that the claim is true: -q suppresses console output by default,
-- but ECHO ON (SData_Core.IO.Set_Local_Echo(True)) restores it, since -q and
-- ECHO now share the same Local_Echo state instead of being two independent
-- flags.
USE MOCK
ECHO ON
LET X = 1
PRINT "hello world"
RUN
