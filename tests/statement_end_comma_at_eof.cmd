-- ADR-080 D5: a dangling continuation comma at the very end of the input, after a
-- complete statement, is accepted silently (nothing follows to be joined).
PRINT 1
RUN
LET Y = 2,
