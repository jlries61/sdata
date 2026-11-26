REM F23: density at the support boundary, PMF at non-integer points, and
REM TDF accuracy for huge df.
DIGITS 12
REPEAT 1
LET X1 = XDF(0, 1)
LET X2 = XDF(0, 2)
LET X3 = XDF(0, 3)
LET G1 = GDF(0, 0.5, 1)
LET G2 = GDF(0, 1, 2)
LET B1 = BDF(0, 0.5, 2)
LET B2 = BDF(1, 2, 0.5)
LET B3 = BDF(0, 1, 3)
LET B4 = BDF(1, 3, 1)
LET N1 = NDF(2.5, 10, 0.5)
LET N2 = NDF(2, 10, 0.5)
LET P1 = PDF(2.5, 3)
LET T1 = TDF(0, 1e10)
LET T2 = TDF(1, 1e8)
LET T3 = TDF(1, 1e5)
PRINT X1, X2, X3, G1, G2
PRINT B1, B2, B3, B4
PRINT N1, N2, P1
PRINT T1, T2, T3
RUN
