-- F52 (2026-10-19 stress test) regression: a distribution parameter outside
-- its domain is reported at once -- the Beta, Student t and F routines used
-- to loop forever on a non-positive shape/degrees of freedom -- and a result
-- that would be NaN is an error, not a value.  Run with -k so every case runs.
REPEAT 1
LET A = TCF(1, -1)
RUN
REPEAT 1
LET B = TIF(0.5, -1)
RUN
REPEAT 1
LET C = BCF(0.5, -1, 0)
RUN
REPEAT 1
LET D = BIF(0.5, -1, -1)
RUN
REPEAT 1
LET E = FCF(0.5, -1, 0.5)
RUN
REPEAT 1
LET F = FIF(0.5, -1, -1)
RUN
REPEAT 1
LET J = BIF(-1, 2, 3)
RUN
REPEAT 1
LET K = BIF(0.5, 1e-300, 1e-300)
RUN
REPEAT 1
LET G = ROUND(1, 400)
RUN
REPEAT 1
LET H = GDF(1, 1e308, 1e308)
RUN
REPEAT 1
LET I = TCF(1, 5)
PRINT I
RUN
QUIT
