OPTIONS JOIN_WARN_THRESHOLD 5
USE "tests/data/merge_a_big.csv", "tests/data/merge_b_big.csv" /BY=ID /JOIN
PRINT ID, X, Y
RUN
NEW
END
