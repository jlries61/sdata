USE "tests/data/data.csv"
KEEP VAR1-VAR10, AGE, SEX
LET TOTAL = (BASE + BONUS) * 1.05
PRINT TOTAL
SAVE "tests/data/test1_output.csv"
RUN
END
