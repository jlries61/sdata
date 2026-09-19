-- ADR-080: a comma after a complete statement joins the next line; if that line is
-- blank, the statement simply ends there (D2), so nothing was joined and it is harmless.
LET X = 1,

PRINT X
RUN
QUIT
