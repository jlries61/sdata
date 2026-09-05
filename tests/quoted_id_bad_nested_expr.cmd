-- ADR-064: a lex error nested inside an expression (not just as a
-- statement's leading token) must abort the whole script, not silently
-- drop the containing statement and let RUN proceed as if it succeeded.
USE MOCK
LET Y = `bad + 1
PRINT Y
RUN
