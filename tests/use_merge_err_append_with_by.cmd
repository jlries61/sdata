-- Error test: /APPEND combined with /BY= is rejected at parse time.
USE "tests/data/merge_a.csv", "tests/data/merge_b.csv" /APPEND /BY=ID
QUIT
