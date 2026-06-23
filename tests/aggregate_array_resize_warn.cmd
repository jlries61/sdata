-- AGGREGATE: outvar pre-exists as a scalar (Y) but the spec makes it an
-- array -> resize warning W1.
USE "tests/data/subscripted.csv"
AGGREGATE Y=MEAN(X)
DISPLAY
QUIT
