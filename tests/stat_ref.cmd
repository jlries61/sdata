-- Statistical reference values validated against published tables.
-- Picks values at well-known quantile points that any statistician
-- would recognise as wrong if off by more than rounding error.
-- References: Abramowitz & Stegun; NIST Handbook of Mathematical Functions.
DIGITS 5

-- Standard normal: classic 97.5 / 2.5 percentage points
-- Phi(1.96) = 0.97500 to 4 d.p. by definition of the 95% CI half-width
PRINT "ZCF(1.960):"   ZCF(1.960)
PRINT "ZCF(-1.960):"  ZCF(-1.960)
PRINT "ZIF(0.975):"   ZIF(0.975)

-- N(mu=0, sigma=1) CDF must match Z at x=1
PRINT "ZCF(1.0):"          ZCF(1.0)
PRINT "NCF(1.0,0.0,1.0):"  NCF(1.0, 0.0, 1.0)

-- Beta(1,1) = Uniform(0,1): analytically exact values
PRINT "BCF(0.25,1,1):"  BCF(0.25, 1.0, 1.0)
PRINT "BCF(0.50,1,1):"  BCF(0.50, 1.0, 1.0)
PRINT "BCF(0.75,1,1):"  BCF(0.75, 1.0, 1.0)

-- Gamma(shape=1,rate=1) = Exponential(rate=1): GCF and ECF must agree at x=1
-- Exact value: 1 - 1/e = 0.63212...
PRINT "GCF(1.0,1,1):"  GCF(1.0, 1.0, 1.0)
PRINT "ECF(1.0,1):"    ECF(1.0, 1.0)

RUN
QUIT
