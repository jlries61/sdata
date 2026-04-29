-- Array slice and list assignment tests
REPEAT 1
DIM A(5)
LET A(1) = 10
LET A(2) = 20
LET A(3) = 30
LET A(4) = 40
LET A(5) = 50
-- Slice assignment: set elements 2 through 4 to 99
LET A(2:4) = 99
PRINT A(1) A(2) A(3) A(4) A(5)
-- List assignment: set elements 1, 3, 5 to 77
LET A(1,3,5) = 77
PRINT A(1) A(2) A(3) A(4) A(5)
RUN
END
