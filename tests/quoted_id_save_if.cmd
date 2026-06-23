-- Test: SAVE per-target IF= filter referencing a backtick-quoted reserved-name column.
-- Two targets: qid_if_big gets rows where AS > 10 (only AS=20);
--              qid_if_small gets rows where AS <= 10 (only AS=10).
-- Re-opening each file and printing values proves the filter ran and selected the right rows.
OPTIONS SAVEOVERWRT YES
USE "tests/data/reserved_cols.csv"
SAVE "tests/data/qid_if_big.csv" (IF=`AS`>10), "tests/data/qid_if_small.csv" (IF=`AS`<=10)
RUN
NEW
USE "tests/data/qid_if_big.csv"
PRINT ID, `AS`
RUN
NEW
USE "tests/data/qid_if_small.csv"
PRINT ID, `AS`
RUN
END
