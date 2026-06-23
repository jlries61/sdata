-- AGGREGATE: mix of whole-array, array-element, and scalar specs.
USE "tests/data/subscripted.csv"
AGGREGATE MALL=MEAN(X) MFIRST=MEAN(X(1)) TY=SUM(Y)
DISPLAY
QUIT
