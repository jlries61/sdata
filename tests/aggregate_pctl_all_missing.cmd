-- AGGREGATE: PCTL of an all-missing input returns missing, matching
-- MEDIAN's existing behavior exactly (ADR-075/sdata#93 -- Compute_Percentile
-- shares Handle_Median's missing-value handling).
NEW
REPEAT 1
LET D = .
PRINT "PCTL(D,50):" PCTL(D, 50)
PRINT "MEDIAN(D):" MEDIAN(D)
RUN
QUIT
