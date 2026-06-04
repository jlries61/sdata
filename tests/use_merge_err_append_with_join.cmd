-- Error test: /APPEND combined with /JOIN is rejected at parse time.
USE "tests/data/merge_a.csv", "tests/data/merge_b.csv" /APPEND /JOIN
QUIT
