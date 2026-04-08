-- Test ARRAY command (virtual arrays over existing variables)

-- Basic virtual array: indexed write then read via underlying variables
REPEAT 1
LET A = 0
LET B = 0
LET C = 0
ARRAY V A B C
LET V{1} = 10
LET V{2} = 20
LET V{3} = 30
PRINT A B C
RUN

-- Read via array index
NEW
REPEAT 1
LET X = 100
LET Y = 200
LET Z = 300
ARRAY W X Y Z
PRINT W{1} W{2} W{3}
RUN

-- Loop over array using FOR
NEW
REPEAT 1
LET S1 = 5
LET S2 = 10
LET S3 = 15
LET S4 = 20
ARRAY SCORES S1 S2 S3 S4
SET TOTAL = 0
FOR I = 1 TO 4
  SET TOTAL = TOTAL + SCORES{I}
NEXT
PRINT TOTAL
RUN

-- Two arrays sharing no variables, used together
NEW
REPEAT 1
LET P = 1
LET Q = 2
LET R = 4
LET S = 8
ARRAY LO P Q
ARRAY HI R S
PRINT LO{1} LO{2} HI{1} HI{2}
RUN

QUIT
