-- ADR-066/issue #88: an unterminated string literal nested inside an
-- expression (not just standing alone as a statement) must abort the
-- whole script, matching ADR-064's equivalent nested-expression proof
-- for backtick-quoted identifiers.
USE MOCK
LET Y$ = "bad" + "unterminated
PRINT Y$
RUN
