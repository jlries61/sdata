-- NEW /PROGRAM clears only the queued deferred-statement program, leaving
-- the Data Table and all variables untouched -- unlike bare NEW.
USE MOCK
SET X = 1
RUN
SET STALE = 99
NEW /PROGRAM
PRINT X
RUN
QUIT
