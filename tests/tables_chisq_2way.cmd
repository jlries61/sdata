-- TABLES two-way /CHISQ: 2x2 chi-square family.
-- Counts [[2,1],[1,2]], N=6, all expected=1.5 => low-expected warning.
-- Deterministic: Pearson=0.6667 DF=1, Continuity-Adj=0.0000, Phi=0.3333,
-- Contingency=0.3162, Cramer's V=0.3333, Sample Size=6.
USE "tests/data/freq.csv"
TABLES REGION$*PRODUCT$ /CHISQ
QUIT
