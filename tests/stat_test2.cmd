NEW
REPEAT 1
-- Binomial(n=10, p=0.5)
-- PMF at k=5: 10C5 * 0.5^10 = 252 * 0.00097656 = 0.24609
LET B1 = MDF(5, 10, 0.5)
-- CDF at k=5: 0.6230
LET B2 = MCF(5, 10, 0.5)
-- Weibull(scale=1, shape=2)
-- PDF at x=1: (2/1)*(1/1)^(1)*e^-(1)^2 = 2*e^-1 = 0.7357
LET W1 = WDF(1, 1, 2)
-- CDF at x=1: 1 - e^-1 = 0.6321
LET W2 = WCF(1, 1, 2)
PRINT B1 B2 W1 W2
RUN
