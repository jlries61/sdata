-- ADR-080 naive model (decided at the round-1 gate): a comma that ends a line only
-- marks that the next line is joined to this statement, even when it would make more
-- sense not to. So this is "LET X=1 PRINT X": two statements on one line with no colon,
-- a syntax error. (ADR-072 had kept the comma as a silent no-op and let PRINT X run;
-- ADR-080 first preserved that as D4 and then reversed it.)
LET X=1,
PRINT X
RUN
QUIT
