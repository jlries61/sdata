REM Test Normal Distribution
PRINT NCF(0.0, 0.0, 1.0)
PRINT NDF(0.0, 0.0, 1.0)
PRINT NIF(0.5, 0.0, 1.0)

REM Test Standard Normal (Z)
PRINT ZCF(0.0)
PRINT ZDF(0.0)
PRINT ZIF(0.5)

REM Test Uniform
PRINT UCF(0.5, 0.0, 1.0)
PRINT UDF(0.5, 0.0, 1.0)
PRINT UIF(0.5, 0.0, 1.0)

REM Test Exponential
PRINT ECF(1.0, 1.0)
PRINT EDF(1.0, 1.0)
PRINT EIF(0.5, 1.0)

REM Test Beta
PRINT BCF(0.5, 2.0, 2.0)
PRINT BDF(0.5, 2.0, 2.0)
PRINT BIF(0.5, 2.0, 2.0)

REM Test Poisson
PRINT PCF(2.0, 2.0)
PRINT PDF(2.0, 2.0)

REM Test Gamma
PRINT GCF(2.0, 2.0, 1.0)
PRINT GDF(2.0, 2.0, 1.0)

REM Test Chi-square
PRINT XCF(2.0, 2.0)
PRINT XDF(2.0, 2.0)

REM Test T
PRINT TCF(0.0, 1.0)
PRINT TDF(0.0, 1.0)

REM Test F
PRINT FCF(1.0, 2.0, 2.0)
PRINT FDF(1.0, 2.0, 2.0)

REM Test Random Numbers (Verify they return numeric)
LET X = NRN(0.0, 1.0)
PRINT "NRN OK"
LET Y = ZRN()
PRINT "ZRN OK"
LET Z = URN(0.0, 1.0)
PRINT "URN OK"
END
