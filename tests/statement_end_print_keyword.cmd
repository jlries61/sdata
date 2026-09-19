-- ADR-080 terminator rule: a command keyword right after PRINT arguments is a syntax error (Parse_Primary used to eat it silently).
PRINT 1 RUN
QUIT
