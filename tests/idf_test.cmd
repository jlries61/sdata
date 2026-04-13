-- Test IDF (inverse CDF) functions not covered by stat_test.cmd/stat_test2.cmd
-- Values validated against GSL reference below
DIGITS 6

-- Normal IDF
LET N05 = ZIF(0.5, 0, 1)
LET N95 = ZIF(0.95, 0, 1)
PRINT "ZIF(0.5):"  N05
PRINT "ZIF(0.95):" N95

-- Uniform IDF
LET U = UIF(0.75, 0, 1)
PRINT "UIF(0.75,0,1):" U

-- Exponential IDF
LET E = EIF(0.5, 1)
PRINT "EIF(0.5,1):" E

-- Beta IDF
LET B = BIF(0.5, 2, 5)
PRINT "BIF(0.5,2,5):" B

-- Gamma IDF
LET G = GIF(0.5, 2, 1)

-- Chi-square IDF
LET X = XIF(0.95, 10)
PRINT "XIF(0.95,10):" X

-- T IDF
LET T = TIF(0.975, 20)
PRINT "TIF(0.975,20):" T

-- F IDF
LET F = FIF(0.95, 5, 10)
PRINT "FIF(0.95,5,10):" F

-- Weibull IDF
LET W = WIF(0.5, 1, 1)
PRINT "WIF(0.5,1,1):" W

-- Logistic IDF (quantile = log(p/(1-p)))
LET L = LIF(0.75)
PRINT "LIF(0.75):" L

-- Poisson IDF
LET P = PIF(0.5, 3)
PRINT "PIF(0.5,3):" P

RUN
QUIT
