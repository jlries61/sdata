USE "tests/data/data.csv"
KEEP VAR1-VAR10, AGE, SEX
-- BASE and BONUS are defined here so the LET references defined names.
-- (data.csv provides only ID and NAME; the entry-time analyzer rejects
--  references to never-defined names, so the smoke test defines them.)
SET BASE = 1000
SET BONUS = 200
LET TOTAL = (BASE + BONUS) * 1.05
PRINT TOTAL
SAVE "tests/data/test1_output.csv"
RUN
END
