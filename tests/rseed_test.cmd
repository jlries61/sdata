-- Test RSEED and RAN/RANDOM for reproducibility
RSEED 42
LET R1 = RAN()
LET R2 = RAN()
LET R3 = RANDOM()
PRINT "R1:" R1
PRINT "R2:" R2
PRINT "R3:" R3
RUN

-- Re-seeding with the same value should reproduce the same sequence
RSEED 42
LET S1 = RAN()
LET S2 = RAN()
LET S3 = RANDOM()
PRINT "S1 = R1:" (S1 = R1)
PRINT "S2 = R2:" (S2 = R2)
PRINT "S3 = R3:" (S3 = R3)
RUN
QUIT
