-- USE rename= converts float column X to integer Y% (truncates toward zero).
USE "tests/data/rename_retype.csv" (RENAME=(X=Y%))
NAMES
PRINT Y%
RUN
END
