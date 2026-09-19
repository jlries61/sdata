-- A comma ending a block-header line just joins the header to its first body line
-- ("WHILE X < 2 LET X = X + 1 ..." is the joined text), so it stays legal.
LET X = 0
WHILE X < 2,
  LET X = X + 1
WEND
PRINT X
RUN
QUIT
