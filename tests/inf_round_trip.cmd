-- Round-trip: write Inf to CSV and read it back
DIGITS 5
USE "tests/data/inf_values.csv"
SAVE "tests/data/inf_output.csv"
RUN

USE "tests/data/inf_output.csv"
PRINT X
PRINT INF(X)
RUN
QUIT
