-- Batch no-regression test for Task C5 (entry-time checking).
-- In BATCH mode Add_To_Active_Program is NOT on the execution path, so
-- Analyze_One is never called here; the bad LET is silently queued.
-- NAMES runs immediately after the LET (confirming the statement was queued,
-- not rejected at entry).  The error fires at RUN via the whole-block
-- Analyze_Deferred pass — exactly one error, no double-firing.
USE MOCK
LET FOO = NAME$
NAMES
RUN
