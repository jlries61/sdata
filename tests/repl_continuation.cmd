-- Issue #69: comma-line-continuation buffering is REPL-only logic (batch
-- mode reads the whole file at once, so a mid-file trailing comma is never
-- distinguished from any other character). "PRINT X Y," ends with a
-- trailing comma before a newline, so the lexer swallows the comma+newline
-- and the REPL keeps buffering (prompt switches to "..>") until "Z"
-- arrives on the next line, completing "PRINT X Y Z" as a single statement.
REPEAT 1
LET X = 1
LET Y = 2
LET Z = 3
RUN
PRINT X Y,
Z
RUN
QUIT
