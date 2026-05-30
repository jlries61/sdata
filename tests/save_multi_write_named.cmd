-- Follow-on C: explicit WRITE target routing.
-- p.csv receives only the record with ID=1; q.csv receives only ID=2.
USE "tests/data/merge_a.csv"
SAVE "tests/data/p.csv" AS P, "tests/data/q.csv" AS Q
IF ID = 1 THEN WRITE P
IF ID = 2 THEN WRITE Q
RUN
NEW
END
