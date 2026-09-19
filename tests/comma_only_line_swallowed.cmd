-- ADR-080: a line holding only a comma directly after a continuation is still
-- swallowed (ADR-072 kept this; only the first comma is a real token).
PRINT 1,
,
2
RUN
QUIT
