-- ZCF/ZDF/ZIF with optional mu/sigma: ZXF(x, mu, sigma) = ZXF((x-mu)/sigma)
-- ZCF(1.0, 1.0, 1.0) = ZCF(0.0) = 0.5
PRINT ZCF(1.0, 1.0, 1.0)
PRINT ZDF(1.0, 1.0, 1.0)
-- ZIF(0.5, mu, sigma) = mu (median of the distribution)
PRINT ZIF(0.5, 1.0, 1.0)
-- ZCF(3.0, 1.0, 2.0) = ZCF((3-1)/2) = ZCF(1.0) ~ 0.84134
PRINT ZCF(3.0, 1.0, 2.0)
PRINT ZDF(3.0, 1.0, 2.0)
PRINT ZIF(0.84134, 1.0, 2.0)
RUN

-- ZRN with 2 args (mu, sigma) and URN with 0 args: verify numeric via RSEED
RSEED 99
LET A = ZRN(5.0, 2.0)
PRINT "ZRN(5,2):" A
LET B = URN()
PRINT "URN():" B
RUN
END
