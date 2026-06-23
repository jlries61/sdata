-- AGGREGATE: array input -> array output, element-wise.
USE "tests/data/subscripted.csv"
AGGREGATE MX=MEAN(X) SX=SUM(X)
DISPLAY
QUIT
