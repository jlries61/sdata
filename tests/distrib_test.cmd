-- Regression test for statistical distribution functions.
-- Covers PDF/CDF/IDF for the main continuous families plus Poisson.
-- Reference values are pinned against well-known mathematical identities
-- (symmetry at 0, e^-1, 5*e^-2, etc.) and standard statistical tables.
DIGITS 6

-- === Standard Normal (Z) ===
-- ZDF(0) = 1/sqrt(2*pi) = 0.398942...
PRINT "ZDF(0):"            ZDF(0)
-- ZCF(0) = 0.5 by symmetry
PRINT "ZCF(0):"            ZCF(0)
-- ZCF near the classic 1.96 boundary
PRINT "ZCF(1.96):"         ZCF(1.96)
-- ZIF(0.5) = 0 by symmetry; ZIF(0.975) is the familiar ~1.96
PRINT "ZIF(0.5):"          ZIF(0.5)
PRINT "ZIF(0.975):"        ZIF(0.975)
-- Roundtrip: CDF(IDF(p)) = p
PRINT "ZCF(ZIF(0.975)):"   ZCF(ZIF(0.975))

-- === Student's t ===
-- TDF(0, 5): t PDF at 0 with df=5
PRINT "TDF(0,5):"          TDF(0, 5)
-- TCF(0, df) = 0.5 by symmetry for any df (including Cauchy df=1)
PRINT "TCF(0,5):"          TCF(0, 5)
PRINT "TCF(0,1):"          TCF(0, 1)
-- TIF(0.975, df): classic two-tailed 5% critical values
PRINT "TIF(0.975,10):"     TIF(0.975, 10)
PRINT "TIF(0.975,30):"     TIF(0.975, 30)
-- Roundtrip: CDF(IDF(p)) = p
PRINT "TCF(TIF(0.95,10),10):"  TCF(TIF(0.95, 10), 10)

-- === Chi-square ===
-- XCF(0, df) = 0 (chi-sq support starts at 0)
PRINT "XCF(0,5):"          XCF(0, 5)
-- XIF: well-known 95th-percentile critical values
PRINT "XIF(0.95,1):"       XIF(0.95, 1)
PRINT "XIF(0.95,5):"       XIF(0.95, 5)
-- Roundtrip: CDF(IDF(p)) = p
PRINT "XCF(XIF(0.95,5),5):"   XCF(XIF(0.95, 5), 5)

-- === F distribution ===
-- FCF(1, df, df) = 0.5 by symmetry when df1 = df2
PRINT "FCF(1,1,1):"        FCF(1, 1, 1)
PRINT "FCF(1,5,5):"        FCF(1, 5, 5)
-- FIF: 95th-percentile critical values
PRINT "FIF(0.95,3,10):"    FIF(0.95, 3, 10)
PRINT "FIF(0.95,5,5):"     FIF(0.95, 5, 5)
-- Roundtrip: CDF(IDF(p)) = p
PRINT "FCF(FIF(0.95,3,10),3,10):"   FCF(FIF(0.95, 3, 10), 3, 10)

-- === Exponential ===
-- EDF(1,1) = rate*e^(-rate*x) = e^-1 = 0.367879...
-- ECF(1,1) = 1 - e^-1 = 0.632121...
PRINT "EDF(1,1):"          EDF(1, 1)
PRINT "ECF(1,1):"          ECF(1, 1)
-- Roundtrip: EIF(ECF(x, rate), rate) = x
PRINT "EIF(ECF(1,1),1):"   EIF(ECF(1, 1), 1)

-- === Poisson ===
-- PDF(0,2) = P(X=0|lambda=2) = e^-2 = 0.135335...
-- PDF(2,2) = P(X=2|lambda=2) = e^-2 * 4/2! = 2*e^-2 = 0.270671...
-- PCF(2,2) = P(X<=2|lambda=2) = e^-2*(1+2+2) = 5*e^-2 = 0.676676...
PRINT "PDF(0,2):"          PDF(0, 2)
PRINT "PDF(2,2):"          PDF(2, 2)
PRINT "PCF(2,2):"          PCF(2, 2)

RUN
QUIT
