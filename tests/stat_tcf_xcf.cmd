-- T-distribution and chi-square CDF at reference quantiles.
-- Values chosen from standard statistical tables so any implementation
-- error of more than rounding tolerance is immediately recognisable.
--
-- References: Abramowitz & Stegun tables 26.7 and 26.8;
--             NIST Handbook of Mathematical Functions.
DIGITS 5

-- t(df=10): 95th and 97.5th one-tailed percentile points
-- t_(0.95, 10) = 1.81246  =>  TCF(1.81246, 10) = 0.95000
-- t_(0.975,10) = 2.22814  =>  TCF(2.22814, 10) = 0.97500
PRINT "TCF(1.812,10):"  TCF(1.812, 10)
PRINT "TCF(2.228,10):"  TCF(2.228, 10)

-- t(df=30): as df grows, t approaches z
-- t_(0.95, 30) = 1.69726  =>  TCF(1.697, 30) ~ 0.95
PRINT "TCF(1.697,30):"  TCF(1.697, 30)

-- Chi-square(df=1): XCF(3.841, 1) = 0.95003 ~ 0.95000
-- 3.841 is the classic Pearson chi-square critical value at 5% significance
PRINT "XCF(3.841,1):"   XCF(3.841, 1)

-- Chi-square(df=2): CDF(x) = 1 - e^(-x/2).  At x = ln(2) = 0.693:
-- F = 1 - e^(-0.3466) = 1 - 1/sqrt(2) ~ 0.29289
PRINT "XCF(0.693,2):"   XCF(0.693, 2)

-- Chi-square(df=10): 95th percentile = 18.307
PRINT "XCF(18.307,10):" XCF(18.307, 10)

-- Symmetry check: t CDF is symmetric around 0
-- TCF(0, df) = 0.5 for all df
PRINT "TCF(0,5):"  TCF(0, 5)
PRINT "TCF(0,30):" TCF(0, 30)

RUN
QUIT
