-- F22 (2026-10-19 stress test) regression: NRN(n, p) is a binomial variate
-- (integer valued, mean n*p = 6, sd sqrt(n*p*(1-p)) = 2.05), not N(n, p).
-- Prints 1 for each property that holds.
RSEED 1
REPEAT 20000
LET N = NRN(20, 0.3)
LET FR = ABS(N - INT(N))
SAVE "tests/data/binomial_nrn_gen.csv"
RUN
USE "tests/data/binomial_nrn_gen.csv"
AGGREGATE M = MEAN(N) S = STD(N) F = MAX(FR) HI = MAX(N)
LET OK_MEAN = M > 5.8 AND M < 6.2
LET OK_SD   = S > 1.9 AND S < 2.2
LET OK_INT  = F = 0
LET OK_MAX  = HI <= 20
PRINT OK_MEAN OK_SD OK_INT OK_MAX
RUN
SYSTEM "rm -f tests/data/binomial_nrn_gen.csv"
END
