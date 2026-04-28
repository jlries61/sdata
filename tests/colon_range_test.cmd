-- Test colon range (numeric order, creates missing variables)

-- ARRAY with colon range: X1:X4 should create X1..X4 and define array
REPEAT 1
ARRAY SCORE X1:X4
LET SCORE{1} = 10
LET SCORE{2} = 20
LET SCORE{3} = 30
LET SCORE{4} = 40
PRINT X1 X2 X3 X4
RUN

-- ARRAY colon range reversed: X5:X3 should still produce X3 X4 X5 (numeric low-to-high)
NEW
REPEAT 1
ARRAY VALS X5:X3
LET VALS{1} = 100
LET VALS{2} = 200
LET VALS{3} = 300
PRINT X3 X4 X5
RUN

-- KEEP with colon range: keeps N1..N3, drops N4
NEW
REPEAT 3
LET N1 = 10
LET N2 = 20
LET N3 = 30
LET N4 = 40
RUN
KEEP N1:N3
PRINT N1 N2 N3
RUN

QUIT
