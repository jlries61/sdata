-- AGGREGATE on unsorted input.  BY auto-sorts the table by the BY variable,
-- so the four g=1 rows (which appear in two non-adjacent runs in the file)
-- become contiguous and collapse into a single group; g=2 is its own group.
-- (The design spec's "non-adjacent runs stay separate" note does not apply:
-- BY sorts first, so equal keys are always adjacent by AGGREGATE time.)
USE "tests/data/agg_runs.csv"
BY G
AGGREGATE TOTAL=SUM(V) NREC=N()
DISPLAY
QUIT
